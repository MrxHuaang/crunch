-- Exploradora (servidor): el impulso del Rebufo, la Embestida, el Salto de pulga y la Estampida.
-- Los movimientos del personaje los hace el cliente; aquí solo se valida lo razonable y se aplica el daño.
-- El impulso se publica en el atributo de jugadora "ScoutCharge" (0–1) para que todos lo vean en la hormiga.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Parent.CasteKit)
local Def = require(ReplicatedStorage.Shared.Castes.scout)

local rng = Random.new()
local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.new(0, 1, 0)
local CHARGE_ATTR = "ScoutCharge"

local function base(id: string, key: string): number?
	if Def.passive.id == id then
		return Def.passive.params[key]
	end
	for _, ability in Def.abilities do
		if ability.id == id then
			return ability.params[key] or ability[key]
		end
	end
	return nil
end

local function P(ctx, id: string, key: string): number
	local ok, value = pcall(ctx.param, id, key)
	if ok and type(value) == "number" then
		return value
	end
	return base(id, key) or 0
end

local function has(ctx, flag: string): boolean
	local ok, value = pcall(ctx.has, flag)
	return ok and value == true
end

local function alive(food: Model?): boolean
	return food ~= nil and food.Parent ~= nil
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = v * FLAT
	return if f.Magnitude > 0.05 then f.Unit else fallback
end

local function turn(dir: Vector3, degrees: number): Vector3
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(dir)
end

-- Lo que dura un salto (el cliente usa la misma cuenta para moverse)
local function jumpTime(distance: number): number
	return 0.35 + distance / 140
end

-- Impulso: estado y atributo (redondeado para no inundar la red)
local function setCharge(ctx, value: number)
	value = math.clamp(value, 0, 1)
	ctx.state.charge = value
	local shown = math.floor(value * 20 + 0.5) / 20
	if ctx.player:GetAttribute(CHARGE_ATTR) ~= shown then
		ctx.player:SetAttribute(CHARGE_ATTR, shown)
	end
end

-- Adelanta el enfriamiento de una habilidad: lista en `readyIn` segundos como mucho.
-- Necesita Kit.cooldown(ctx, slot, readyIn) del núcleo (los enfriamientos viven dentro de
-- CasteService; el atributo CasteCdN solo los publica). Sin él, no hace nada: tocar el atributo
-- a mano mostraría la habilidad lista y el servidor la rechazaría.
-- Se aplica un instante después para no pisarse con el enfriamiento que pone el núcleo tras lanzar.
local function cooldownAtMost(ctx, slot: number, readyIn: number)
	Kit.after(ctx, 0.05, function()
		local kitCooldown = (Kit :: any).cooldown
		if type(kitCooldown) == "function" then
			kitCooldown(ctx, slot, math.max(readyIn, 0))
		end
	end)
end

-- Quita `seconds` al enfriamiento que le quede (lee lo publicado en CasteCdN)
local function shaveCooldown(ctx, slot: number, seconds: number)
	Kit.after(ctx, 0.06, function()
		local readyAt = ctx.player:GetAttribute("CasteCd" .. slot)
		if type(readyAt) == "number" then
			local left = readyAt - Workspace:GetServerTimeNow()
			if left > 0 then
				local kitCooldown = (Kit :: any).cooldown
				if type(kitCooldown) == "function" then
					kitCooldown(ctx, slot, math.max(left - seconds, 0))
				end
			end
		end
	end)
end

-- Ordena por distancia a `from`
local function byDistance(foods: { Model }, from: Vector3): { Model }
	local list = table.clone(foods)
	table.sort(list, function(x, y)
		return ((Kit.posOf(x) - from) * FLAT).Magnitude < ((Kit.posOf(y) - from) * FLAT).Magnitude
	end)
	return list
end

-- Punto de aterrizaje junto a una comida (no encima), a ras del suelo de `ground`
local function besideFood(food: Model, from: Vector3, groundY: number): Vector3
	local center = food:GetPivot().Position
	local radius = (food:GetAttribute("Radius") :: number?) or 2
	local back = flatUnit(from - center, Vector3.zAxis)
	local spot = center + back * (radius + 1.5)
	return Vector3.new(spot.X, groundY, spot.Z)
end

----------------------------------------------------------------------------------------------------
-- Salto de pulga

local function landWave(ctx, at: Vector3, radius: number, bites: number, small: boolean)
	local pts = {}
	for _, food in Kit.inRadius(ctx.stats, at, radius) do
		if alive(food) then
			local pos = Kit.posOf(food)
			if Kit.strike(ctx, food, bites) > 0 then
				table.insert(pts, pos)
			end
		end
	end
	ctx.fx("scout2_land", { p = at, r = radius, pts = pts, small = small, quake = has(ctx, "quake") })
end

-- Rebote: hasta `left` saltos más hacia la comida más cercana
local function bounce(ctx, from: Vector3, left: number, visited: { [Model]: boolean })
	if left <= 0 then
		return
	end
	local target = Kit.nearest(ctx.stats, from, P(ctx, "scout2", "hopRange"), visited)
	if not target then
		return
	end
	visited[target] = true
	local to = besideFood(target, from, from.Y)
	local flight = jumpTime(((to - from) * FLAT).Magnitude) * 0.8
	ctx.fx("scout2_hop", { a = from, b = to, flight = flight })
	Kit.after(ctx, flight, function()
		landWave(ctx, to, P(ctx, "scout2", "radius") * 0.8, P(ctx, "scout2", "hopBites"), true)
		bounce(ctx, to, left - 1, visited)
	end)
end

----------------------------------------------------------------------------------------------------

return {
	passive = {
		equip = function(ctx)
			setCharge(ctx, 0)
		end,

		unequip = function(ctx)
			ctx.state.charge = 0
			ctx.player:SetAttribute(CHARGE_ATTR, nil)
		end,

		-- Correr carga el impulso; quieta, se va perdiendo
		tick = function(ctx, dt: number)
			local root = ctx.root
			if not root or not root.Parent then
				return
			end
			local speed = (root.AssemblyLinearVelocity * FLAT).Magnitude
			local fast = speed >= (ctx.stats.walkSpeed or 12) * 1.2
			local charge = ctx.state.charge or 0
			local time = math.max(P(ctx, "draft", "time"), 0.5)
			if fast then
				charge += dt / time
			elseif speed < 2 then
				charge -= dt / (time * 1.5)
			end
			setCharge(ctx, charge)

			-- Chispazo: al máximo y corriendo, muerdes lo que adelantas
			if has(ctx, "sparkRun") and fast and charge >= 1 then
				ctx.state.sparkClock = (ctx.state.sparkClock or 0) + dt
				if ctx.state.sparkClock >= P(ctx, "draft", "sparkEvery") then
					ctx.state.sparkClock = 0
					local pts = {}
					local bites = P(ctx, "draft", "sparkBites")
					for _, food in Kit.inRadius(ctx.stats, root.Position, P(ctx, "draft", "sparkRadius")) do
						if alive(food) then
							local at = Kit.posOf(food)
							if Kit.nibble(ctx, food, bites) > 0 then
								table.insert(pts, at)
							end
						end
					end
					if #pts > 0 then
						Kit.flush(ctx)
						ctx.fx("passive", { spark = true, a = root.Position, pts = pts })
					end
				end
			end
		end,

		-- El mordisco gasta el impulso: multiplica y atraviesa en línea
		bite = function(ctx, food: Model?, position: Vector3, damage: number, _finished: boolean)
			local charge = ctx.state.charge or 0
			if charge < 0.1 then
				return
			end
			local spark = has(ctx, "sparkRun")
			local bite = math.max(ctx.bite, 1)
			local max = P(ctx, "draft", "max")
			-- Con Chispazo el mordisco no gasta el impulso, pero tampoco lo exprime entero
			local mult = 1 + (max - 1) * charge * (if spark then 0.5 else 1)
			local pts = {}
			if alive(food) then
				Kit.nibble(ctx, food :: Model, damage * (mult - 1) / bite)
			end
			local dir = flatUnit(position - ctx.origin, ctx.dir)
			local b = position + dir * P(ctx, "draft", "pierce")
			local share = P(ctx, "draft", "pierceShare")
			for _, other in Kit.onLine(ctx.stats, position, b, P(ctx, "draft", "pierceWidth")) do
				if other ~= food and alive(other) then
					local at = Kit.posOf(other)
					if Kit.nibble(ctx, other, damage * mult * share / bite) > 0 then
						table.insert(pts, at)
					end
				end
			end
			Kit.flush(ctx)
			ctx.fx("passive", { a = position, b = b, mult = mult, pts = pts })
			if not spark then
				setCharge(ctx, 0)
			end
		end,
	},

	abilities = {
		-- Embestida: recta, en zigzag o ariete. El acelerón lo hace el cliente.
		scout1 = function(ctx)
			local stats = ctx.stats
			local length = P(ctx, "scout1", "length")
			local width = P(ctx, "scout1", "width")
			local bites = P(ctx, "scout1", "bites")
			local a = ctx.origin
			local path = { a }
			if has(ctx, "zigzag") then
				local zig = P(ctx, "scout1", "zigAngle")
				local here = a
				for i, angle in { zig, -zig, zig } do
					here += turn(ctx.dir, angle) * length * 0.5
					path[i + 1] = here
				end
			else
				path[2] = a + ctx.dir * length
			end

			local hit: { [Model]: boolean } = {}
			local pts = {}
			local finishedCount = 0
			local ramAt = nil
			if has(ctx, "ram") then
				-- Se estrella contra la primera comida de la línea
				local first = byDistance(Kit.onLine(stats, a, path[2], width), a)[1]
				if first then
					ramAt = Kit.posOf(first)
					path[2] = besideFood(first, a, a.Y)
					local taken, finished = Kit.strike(ctx, first, bites * P(ctx, "scout1", "ramMult"))
					if taken > 0 then
						table.insert(pts, ramAt)
					end
					if finished then
						finishedCount += 1
					end
					hit[first] = true
					for _, other in Kit.inRadius(stats, ramAt, P(ctx, "scout1", "ramRadius")) do
						if not hit[other] and alive(other) then
							hit[other] = true
							local at = Kit.posOf(other)
							local got, done = Kit.strike(ctx, other, P(ctx, "scout1", "ramBites"))
							if got > 0 then
								table.insert(pts, at)
							end
							if done then
								finishedCount += 1
							end
						end
					end
				end
			end
			if not ramAt then
				for i = 1, #path - 1 do
					for _, food in byDistance(Kit.onLine(stats, path[i], path[i + 1], width), path[i]) do
						if not hit[food] and alive(food) then
							hit[food] = true
							local at = Kit.posOf(food)
							local taken, finished = Kit.strike(ctx, food, bites)
							if taken > 0 then
								table.insert(pts, at)
							end
							if finished then
								finishedCount += 1
							end
						end
					end
				end
			end

			ctx.fx("scout1", { path = path, pts = pts, ram = ramAt, time = P(ctx, "scout1", "time") })
			if has(ctx, "secondWind") and finishedCount > 0 then
				shaveCooldown(ctx, 1, finishedCount * P(ctx, "scout1", "refund"))
			end
			if has(ctx, "tailwind") then
				setCharge(ctx, 1)
			end
			return true
		end,

		-- Salto de pulga: vuelo al punto (cliente), onda al caer (aquí) y reinicio de la Embestida
		scout2 = function(ctx)
			local a = ctx.origin
			local b = Vector3.new(ctx.aim.X, a.Y, ctx.aim.Z)
			local flight = jumpTime(((b - a) * FLAT).Magnitude)
			local radius = P(ctx, "scout2", "radius")
			ctx.fx("scout2", { a = a, b = b, flight = flight, r = radius, quake = has(ctx, "quake") })
			Kit.after(ctx, flight, function()
				landWave(ctx, b, radius, P(ctx, "scout2", "bites"), false)
				cooldownAtMost(ctx, 1, 0)
				if has(ctx, "tailwind") then
					setCharge(ctx, 1)
				end
				if has(ctx, "bounce") then
					bounce(ctx, b, math.floor(P(ctx, "scout2", "hops") + 0.5), {})
				end
			end)
			return true
		end,

		-- Estampida: velocidad (cliente), manada fantasma y todo lo que tocas recibe
		scout3 = function(ctx)
			local stats = ctx.stats
			local life = P(ctx, "scout3", "life")
			local radius = P(ctx, "scout3", "radius")
			local bites = P(ctx, "scout3", "bites")
			local herd = has(ctx, "herd")
			local comet = has(ctx, "comet")
			local root = ctx.root
			ctx.fx("scout3", { life = life, speed = P(ctx, "scout3", "speed"), r = radius, herd = herd, comet = comet })

			local blasted: { [Model]: boolean } = {}
			Kit.zone(ctx, {
				center = ctx.origin,
				radius = radius,
				duration = life,
				every = P(ctx, "scout3", "every"),
				follow = root,
				tick = function(foods: { Model }, _c: Vector3, _n: number)
					local pts, blasts = {}, {}
					for _, food in foods do
						if alive(food) then
							local at = Kit.posOf(food)
							if Kit.strike(ctx, food, bites) > 0 then
								table.insert(pts, at)
							end
							-- Cometa: la primera vez que tocas una comida, estalla
							if comet and not blasted[food] then
								blasted[food] = true
								table.insert(blasts, at)
								for _, other in Kit.inRadius(stats, at, P(ctx, "scout3", "blast")) do
									if other ~= food and alive(other) then
										local there = Kit.posOf(other)
										if Kit.strike(ctx, other, P(ctx, "scout3", "blastBites")) > 0 then
											table.insert(pts, there)
										end
									end
								end
							end
						end
					end
					if #pts > 0 then
						ctx.fx("scout3_tick", { pts = pts, blasts = blasts })
					end
				end,
			})

			if herd then
				local length = P(ctx, "scout3", "herdLength")
				local herdBites = P(ctx, "scout3", "herdBites")
				Kit.every(ctx, P(ctx, "scout3", "herdEvery"), life, function(_n: number)
					if not root or not root.Parent then
						return
					end
					local from = root.Position
					local facing = flatUnit(root.CFrame.LookVector, ctx.dir)
					local as, bs, pts = {}, {}, {}
					local seen: { [Model]: boolean } = {}
					for _ = 1, 3 do
						local dir = turn(facing, rng:NextNumber(-150, 150))
						local to = from + dir * length
						table.insert(as, from)
						table.insert(bs, to)
						for _, food in Kit.onLine(stats, from, to, 5) do
							if not seen[food] and alive(food) then
								seen[food] = true
								local at = Kit.posOf(food)
								if Kit.strike(ctx, food, herdBites) > 0 then
									table.insert(pts, at)
								end
							end
						end
					end
					ctx.fx("scout3_herd", { as = as, bs = bs, pts = pts })
				end)
			end
			return true
		end,
	},
}
