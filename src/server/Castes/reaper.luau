-- Segadora (servidor): el tajo en cono de la pasiva, la Guillotina, el Torbellino y la Gran Siega.
-- Todo el daño pasa por CasteKit; los clientes pintan con los puntos que mandamos en cada efecto.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.CasteKit)
local FoodService = require(script.Parent.Parent.FoodService)
local Def = require(ReplicatedStorage.Shared.Castes.reaper)

local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.new(0, 1, 0)
local SIEGE_STEPS = 8 -- tramos en que avanza la Gran Siega

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

local function flatDist(a: Vector3, b: Vector3): number
	return ((a - b) * FLAT).Magnitude
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = v * FLAT
	return if f.Magnitude > 0.05 then f.Unit else fallback
end

-- Le queda poca vida (Ejecución)
local function low(ctx, food: Model): boolean
	local hp = food:GetAttribute("Hp")
	if type(hp) ~= "number" then
		return false
	end
	local max = food:GetAttribute("MaxHp")
	if type(max) ~= "number" then
		local def = FoodService.defOf(food)
		max = def and def.hp or hp
	end
	return max > 0 and hp / max <= P(ctx, "slash", "executeAt")
end

local function execMult(ctx, food: Model): number
	if has(ctx, "execute") and low(ctx, food) then
		return P(ctx, "slash", "executeMult")
	end
	return 1
end

-- Golpe de habilidad (con Ejecución). Apunta el punto si dio algo.
local function cut(ctx, food: Model, bites: number, pts: { Vector3 }): (number, boolean)
	local pos = Kit.posOf(food)
	local taken, finished = Kit.strike(ctx, food, bites * execMult(ctx, food))
	if taken > 0 then
		table.insert(pts, pos)
	end
	return taken, finished
end

----------------------------------------------------------------------------------------------------
-- Guillotina

local function slam(ctx, center: Vector3, radius: number, bites: number, core: number, coreMult: number, event: string)
	local pts, hard = {}, {}
	for _, food in Kit.inRadius(ctx.stats, center, radius) do
		if alive(food) then
			local inCore = core > 0 and flatDist(Kit.posOf(food), center) <= core
			local before = #pts
			cut(ctx, food, if inCore then bites * coreMult else bites, pts)
			if inCore and #pts > before then
				table.insert(hard, pts[#pts])
			end
		end
	end
	ctx.fx(event, { p = center, r = radius, pts = pts, core = hard })
end

local function boomerang(ctx)
	local width = P(ctx, "reaper1", "boomWidth")
	local bites = P(ctx, "reaper1", "boomBites")
	local travel = P(ctx, "reaper1", "boomTime")
	local a = ctx.origin + UP
	local b = ctx.aim + UP
	local root = ctx.root
	ctx.fx("reaper1", { boom = true, a = a, b = b, time = travel })
	local hitOut = {}
	Kit.after(ctx, travel, function()
		local pts = {}
		for _, food in Kit.onLine(ctx.stats, a, b, width) do
			if alive(food) then
				hitOut[food] = true
				cut(ctx, food, bites, pts)
			end
		end
		ctx.fx("reaper1_boom", { pts = pts, p = b })
	end)
	Kit.after(ctx, travel * 2, function()
		local back = if root and root.Parent then root.Position else a
		local pts = {}
		for _, food in Kit.onLine(ctx.stats, b, back, width) do
			if alive(food) then
				-- A la vuelta pega más a lo que ya cortó a la ida
				cut(ctx, food, if hitOut[food] then bites * 1.5 else bites, pts)
			end
		end
		ctx.fx("reaper1_boom", { pts = pts, p = back, back = true })
	end)
	return true
end

----------------------------------------------------------------------------------------------------

return {
	passive = {
		unequip = function(ctx)
			ctx.state.count = 0
		end,

		-- Tajo: todo lo que está en el cono delante de ti recibe parte del mordisco, a la carga
		bite = function(ctx, food: Model?, position: Vector3, damage: number, _finished: boolean)
			local stats = ctx.stats
			local bite = math.max(ctx.bite, 1)
			ctx.state.count = (ctx.state.count or 0) + 1
			local every = math.max(2, math.floor(P(ctx, "slash", "heavyEvery") + 0.5))
			local heavy = ctx.state.count % every == 0
			local thrust = has(ctx, "thrust")

			local angle = P(ctx, "slash", "angle")
			local extra = P(ctx, "slash", "extra")
			local share = P(ctx, "slash", "share")
			local heavyMult = P(ctx, "slash", "heavyMult")
			if heavy then
				if thrust then
					extra += P(ctx, "slash", "heavyExtra") * 2 -- la estocada pesada llega más lejos
				else
					angle = math.max(angle, P(ctx, "slash", "heavyAngle"))
					extra += P(ctx, "slash", "heavyExtra")
				end
				share *= heavyMult
			end

			local dir = flatUnit(position - ctx.origin, ctx.dir)
			local range = (stats.biteRange or 6) + extra
			local pts = {}
			for _, other in Kit.inCone(stats, ctx.origin, dir, range, angle / 2) do
				if other ~= food and alive(other) then
					local at = Kit.posOf(other)
					if Kit.nibble(ctx, other, damage * share * execMult(ctx, other) / bite) > 0 then
						table.insert(pts, at)
					end
				end
			end
			-- El tajo pesado también se ensaña con la comida que mordiste
			if heavy and alive(food) then
				Kit.nibble(ctx, food :: Model, damage * (heavyMult - 1) * 0.5 / bite)
			end
			if #pts > 0 or heavy then
				Kit.flush(ctx)
				ctx.fx("passive", {
					o = ctx.origin,
					dir = dir,
					ang = angle,
					r = range,
					pts = pts,
					heavy = heavy,
					thrust = thrust,
				})
			end
		end,
	},

	abilities = {
		-- Guillotina: salto y caída (el salto lo hace el cliente), bumerán o con réplicas
		reaper1 = function(ctx)
			if has(ctx, "boomerang") then
				return boomerang(ctx)
			end
			local radius = P(ctx, "reaper1", "radius")
			local bites = P(ctx, "reaper1", "bites")
			local land = P(ctx, "reaper1", "land")
			local center = ctx.aim
			ctx.fx("reaper1", { a = ctx.origin, b = center, land = land, r = radius })
			Kit.after(ctx, land, function()
				slam(ctx, center, radius, bites, P(ctx, "reaper1", "core"), P(ctx, "reaper1", "coreMult"), "reaper1_hit")
				if has(ctx, "aftershock") then
					local shockBites = P(ctx, "reaper1", "shockBites")
					for i = 1, math.floor(P(ctx, "reaper1", "shocks") + 0.5) do
						Kit.after(ctx, 0.5 * i, function()
							slam(ctx, center, radius * (1 + 0.35 * i), shockBites, 0, 1, "reaper1_shock")
						end)
					end
				end
			end)
			return true
		end,

		-- Torbellino: giras tú (con o sin danza) o sueltas un tornado que avanza
		reaper2 = function(ctx)
			local life = P(ctx, "reaper2", "life")
			local radius = P(ctx, "reaper2", "radius")
			local bites = P(ctx, "reaper2", "bites")
			local root = ctx.root
			local tornado = has(ctx, "tornado")
			local dance = has(ctx, "bladeDance")
			local a = ctx.origin
			local b = a + ctx.dir * P(ctx, "reaper2", "travel")
			local started = os.clock()
			local endAt = started + life
			local extendMax = P(ctx, "reaper2", "extendMax")
			local extend = P(ctx, "reaper2", "extend")
			local extended = 0

			ctx.fx("reaper2", {
				mode = if tornado then "tornado" else "spin",
				a = a,
				b = b,
				life = life,
				r = radius,
				speed = if tornado then 1 else P(ctx, "reaper2", "speed"),
				dance = dance,
			})

			local ended = false
			local function finish()
				if not ended then
					ended = true
					ctx.fx("reaper2_end", {})
				end
			end

			local ticker
			ticker = Kit.every(ctx, P(ctx, "reaper2", "every"), life + extendMax + 0.1, function(_n: number)
				local now = os.clock()
				if now > endAt then
					finish()
					if ticker then
						ticker.stop()
					end
					return
				end
				local center
				if tornado then
					center = a:Lerp(b, math.clamp((now - started) / life, 0, 1))
				else
					center = if root and root.Parent then root.Position else a
				end
				local pts = {}
				local finishedAny = 0
				for _, food in Kit.inRadius(ctx.stats, center, radius) do
					if alive(food) then
						local _, finished = cut(ctx, food, bites, pts)
						if finished then
							finishedAny += 1
						end
					end
				end
				if dance and finishedAny > 0 and extended < extendMax then
					local add = math.min(extend * finishedAny, extendMax - extended)
					extended += add
					endAt += add
					ctx.fx("reaper2_ext", { add = add })
				end
				if #pts > 0 then
					ctx.fx("reaper2_tick", { c = center, pts = pts })
				end
			end)
			-- Por si el último tic no llega a pasar del final (o el Kit corta antes)
			Kit.after(ctx, life + extendMax + 0.2, finish)
			return true
		end,

		-- Gran Siega: media luna que avanza, dos en aspa o un anillo que crece
		reaper3 = function(ctx)
			local stats = ctx.stats
			local length = P(ctx, "reaper3", "length")
			local width = P(ctx, "reaper3", "width")
			local bites = P(ctx, "reaper3", "bites")
			local travel = P(ctx, "reaper3", "time")
			local origin = ctx.origin + UP
			local ring = has(ctx, "ringReap")
			local dirs = { ctx.dir }
			if has(ctx, "crossReap") then
				local spread = math.rad(P(ctx, "reaper3", "spread"))
				dirs = {
					CFrame.Angles(0, spread, 0):VectorToWorldSpace(ctx.dir),
					CFrame.Angles(0, -spread, 0):VectorToWorldSpace(ctx.dir),
				}
			end
			local ringRadius = P(ctx, "reaper3", "ringRadius")

			ctx.fx("reaper3", {
				mode = if ring then "ring" elseif #dirs > 1 then "cross" else "line",
				a = origin,
				d1 = dirs[1],
				d2 = dirs[2] or dirs[1],
				len = length,
				w = width,
				time = travel,
				r = ringRadius,
				scar = P(ctx, "reaper3", "scar"),
			})

			local hit: { [Model]: boolean } = {}
			local step = 0
			Kit.every(ctx, travel / SIEGE_STEPS, travel, function(_n: number)
				step += 1
				if step > SIEGE_STEPS then
					return
				end
				local pts = {}
				if ring then
					local r1 = ringRadius * step / SIEGE_STEPS
					for _, food in Kit.inRadius(stats, origin, r1) do
						if not hit[food] and alive(food) then
							hit[food] = true
							cut(ctx, food, bites, pts)
						end
					end
				else
					for _, dir in dirs do
						local s0 = origin + dir * length * (step - 1) / SIEGE_STEPS
						local s1 = origin + dir * length * step / SIEGE_STEPS
						for _, food in Kit.onLine(stats, s0, s1, width) do
							if not hit[food] and alive(food) then
								hit[food] = true
								cut(ctx, food, bites, pts)
							end
						end
					end
				end
				if #pts > 0 then
					ctx.fx("reaper3_hit", { pts = pts })
				end
			end)
			return true
		end,
	},
}
