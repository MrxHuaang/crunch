-- Voltaica (servidor): el arco de la pasiva, la Descarga, la Bobina y la Tormenta, con sus mutaciones.
-- Todo el daño pasa por CasteKit; los clientes pintan con los puntos que mandamos en cada efecto.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.CasteKit)
local Def = require(ReplicatedStorage.Shared.Castes.volt)

local rng = Random.new()
local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.new(0, 1, 0)
local RESONANCE_GAP = 0.35 -- una bobina no resuena más de una vez cada tanto

-- Valor base de un parámetro (por si el núcleo no lo diera)
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

local function flat(a: Vector3, b: Vector3): number
	return ((a - b) * FLAT).Magnitude
end

local function alive(food: Model?): boolean
	return food ~= nil and food.Parent ~= nil
end

-- Acumulador de lo que pasó en una tanda: puntos golpeados (botín) y chispas extra (a→b)
local function newOut()
	return { pts = {}, xa = {}, xb = {} }
end

-- Golpe de habilidad a una comida. Con "Electricidad estática", lo cargado pega el doble y estalla.
local function zap(ctx, food: Model, bites: number, out): (Vector3, number, boolean)
	local pos = Kit.posOf(food)
	local charged = has(ctx, "staticMark") and Kit.marked(food, "static") == true
	if charged then
		bites *= 2
		Kit.mark(food, "static", 0.05, false)
	end
	local taken, finished = Kit.strike(ctx, food, bites)
	if taken > 0 then
		table.insert(out.pts, pos)
	end
	if charged then
		-- La carga estática salta a lo que haya alrededor
		for _, other in Kit.inRadius(ctx.stats, pos, 8) do
			if other ~= food and alive(other) then
				local at = Kit.posOf(other)
				local got = Kit.strike(ctx, other, 1.5)
				if got > 0 then
					table.insert(out.pts, at)
					table.insert(out.xa, pos)
					table.insert(out.xb, at)
				end
			end
		end
	end
	return pos, taken, finished
end

-- Chispas de una comida que estalla: daño a las vecinas
local function sparks(ctx, from: Vector3, radius: number, bites: number, out)
	for _, other in Kit.inRadius(ctx.stats, from, radius) do
		if alive(other) then
			local at = Kit.posOf(other)
			local got = Kit.strike(ctx, other, bites)
			if got > 0 then
				table.insert(out.pts, at)
				table.insert(out.xa, from)
				table.insert(out.xb, at)
			end
		end
	end
end

local function pickRandom(list: { Model }, n: number): { Model }
	local pool = table.clone(list)
	local picked = {}
	for _ = 1, math.min(n, #pool) do
		local i = rng:NextInteger(1, #pool)
		table.insert(picked, pool[i])
		table.remove(pool, i)
	end
	return picked
end

----------------------------------------------------------------------------------------------------
-- Bobina

local coilSerial = 0

-- Una tanda de rayos desde una bobina a `n` comidas de su radio
local function volley(ctx, coil, foods: { Model }?, resonance: boolean)
	if coil.dead then
		return
	end
	local center = coil.at()
	local list = foods or Kit.inRadius(ctx.stats, center, coil.radius)
	local picks = pickRandom(list, coil.targets)
	local out = newOut()
	for _, food in picks do
		if alive(food) then
			zap(ctx, food, coil.bites, out)
		end
	end
	if #out.pts > 0 or resonance then
		ctx.fx("volt2_zap", {
			id = coil.id,
			from = center + UP * 5,
			pts = out.pts,
			xa = out.xa,
			xb = out.xb,
			res = resonance,
		})
	end
end

local function plantCoil(ctx, at: () -> Vector3, radius: number, follow: BasePart?)
	coilSerial += 1
	local life = P(ctx, "volt2", "life")
	local coil = {
		id = tostring(ctx.player.UserId) .. "_" .. coilSerial,
		at = at,
		radius = radius,
		targets = math.max(1, math.floor(P(ctx, "volt2", "targets") + 0.5)),
		bites = P(ctx, "volt2", "bites"),
		lastRes = 0,
		dead = false,
	}
	ctx.state.coils = ctx.state.coils or {}
	table.insert(ctx.state.coils, coil)
	local zone = Kit.zone(ctx, {
		center = at(),
		radius = radius,
		duration = life,
		every = P(ctx, "volt2", "every"),
		follow = follow,
		tick = function(foods: { Model }, _center: Vector3, _n: number)
			volley(ctx, coil, foods, false)
		end,
	})
	Kit.after(ctx, life, function()
		coil.dead = true
		local list = ctx.state.coils
		if list then
			local i = table.find(list, coil)
			if i then
				table.remove(list, i)
			end
		end
	end)
	return coil, zone
end

----------------------------------------------------------------------------------------------------

return {
	passive = {
		unequip = function(ctx)
			for _, coil in ctx.state.coils or {} do
				coil.dead = true
			end
		end,

		-- Arco: el mordisco salta a las comidas de al lado, a la carga
		bite = function(ctx, food: Model?, position: Vector3, damage: number, _finished: boolean)
			local stats = ctx.stats
			local bite = math.max(ctx.bite, 1)
			local targets = math.max(1, math.floor(P(ctx, "arc", "targets") + 0.5))
			local share = P(ctx, "arc", "share")
			local static = has(ctx, "staticMark")
			local staticTime = P(ctx, "arc", "staticTime")
			local pts = {}
			local hit = 0
			if static and alive(food) then
				Kit.mark(food :: Model, "static", staticTime, true)
			end
			for _, other in Kit.inRadius(stats, position, P(ctx, "arc", "range")) do
				if hit >= targets then
					break
				end
				if other ~= food and alive(other) then
					hit += 1
					local at = Kit.posOf(other)
					local taken = Kit.nibble(ctx, other, damage * share / bite)
					if taken > 0 then
						table.insert(pts, at)
					end
					if static and alive(other) then
						Kit.mark(other, "static", staticTime, true)
					end
				end
			end

			-- Sobrecarga: cada N mordiscos, una nova alrededor
			local nova = nil
			if has(ctx, "overload") then
				ctx.state.arcCount = (ctx.state.arcCount or 0) + 1
				if ctx.state.arcCount >= P(ctx, "arc", "novaEvery") then
					ctx.state.arcCount = 0
					nova = {}
					local novaBites = P(ctx, "arc", "novaBites")
					for _, other in Kit.inRadius(stats, position, P(ctx, "arc", "novaRadius")) do
						if alive(other) then
							local at = Kit.posOf(other)
							if Kit.nibble(ctx, other, novaBites) > 0 then
								table.insert(nova, at)
							end
						end
					end
				end
			end

			if #pts > 0 or nova then
				Kit.flush(ctx)
			end
			if #pts > 0 then
				ctx.fx("passive", { o = position, pts = pts, heavy = has(ctx, "arcHeavy"), static = static })
			end
			if nova then
				ctx.fx("volt_nova", { o = position, r = P(ctx, "arc", "novaRadius"), pts = nova })
			end

			-- Resonancia: morder dentro del radio de una bobina la hace disparar otra tanda
			local now = os.clock()
			for _, coil in ctx.state.coils or {} do
				if not coil.dead and now - coil.lastRes >= RESONANCE_GAP and flat(coil.at(), position) <= coil.radius then
					coil.lastRes = now
					volley(ctx, coil, nil, true)
				end
			end
		end,
	},

	abilities = {
		-- Descarga: cadena, árbol (bifurcado) o lanza recta
		volt1 = function(ctx)
			local stats = ctx.stats
			local bites = P(ctx, "volt1", "bites")
			local out = newOut()
			local mouth = ctx.origin + UP

			if has(ctx, "lanceBolt") then
				local reach = P(ctx, "volt1", "range") + P(ctx, "volt1", "lance")
				local b = mouth + ctx.dir * reach
				for _, food in Kit.onLine(stats, mouth, b, P(ctx, "volt1", "width")) do
					if alive(food) then
						zap(ctx, food, bites, out)
					end
				end
				ctx.fx("volt1", { mode = "lance", o = mouth, b = b, pts = out.pts, xa = out.xa, xb = out.xb })
				return true
			end

			local hop = P(ctx, "volt1", "hop")
			local start = ctx.aimFood or Kit.nearest(stats, ctx.aim, hop)
			if not alive(start) then
				return false
			end
			local first = start :: Model
			local jumps = math.max(1, math.floor(P(ctx, "volt1", "jumps") + 0.5))
			local visited = { [first] = true }
			local where = { [first] = Kit.posOf(first) }
			local nodes = { first }
			local sa, sb, lv = { mouth }, { where[first] }, { 0 }

			local function link(from: Model, to: Model, level: number)
				visited[to] = true
				where[to] = Kit.posOf(to)
				table.insert(nodes, to)
				table.insert(sa, where[from])
				table.insert(sb, where[to])
				table.insert(lv, level)
			end

			local fork = has(ctx, "forkBolt")
			if fork then
				-- Cada nodo se parte en dos; la profundidad es la mitad de los saltos
				local frontier = { first }
				for level = 1, math.ceil(jumps / 2) do
					local nextFrontier = {}
					for _, node in frontier do
						for _ = 1, 2 do
							local nextFood = Kit.nearest(stats, where[node], hop, visited)
							if not nextFood then
								break
							end
							link(node, nextFood, level)
							table.insert(nextFrontier, nextFood)
						end
					end
					frontier = nextFrontier
					if #frontier == 0 then
						break
					end
				end
			else
				local current = first
				for level = 1, jumps - 1 do
					local nextFood = Kit.nearest(stats, where[current], hop, visited)
					if not nextFood then
						break
					end
					link(current, nextFood, level)
					current = nextFood
				end
			end

			for _, node in nodes do
				if alive(node) then
					zap(ctx, node, bites, out)
				end
			end
			ctx.fx("volt1", {
				mode = if fork then "fork" else "chain",
				sa = sa,
				sb = sb,
				lv = lv,
				pts = out.pts,
				xa = out.xa,
				xb = out.xb,
			})
			return true
		end,

		-- Bobina: fija, orbital o en pareja
		volt2 = function(ctx)
			local radius = P(ctx, "volt2", "radius")
			local life = P(ctx, "volt2", "life")
			local root = ctx.root

			if has(ctx, "coilOrbit") then
				local fallback = ctx.origin
				local coil = plantCoil(ctx, function()
					if root and root.Parent then
						fallback = root.Position
					end
					return fallback
				end, radius, root)
				ctx.fx("volt2", { mode = "orbit", id = coil.id, pos = ctx.origin, life = life, r = radius })
				return true
			end

			local a = ctx.aim
			if has(ctx, "coilPair") then
				local side = ctx.dir:Cross(UP)
				side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
				local spread = math.min(radius * 0.8, 18)
				local p1, p2 = a + side * spread * 0.5, a - side * spread * 0.5
				local c1 = plantCoil(ctx, function()
					return p1
				end, radius * 0.6)
				local c2 = plantCoil(ctx, function()
					return p2
				end, radius * 0.6)
				ctx.fx("volt2", { mode = "pair", id = c1.id, id2 = c2.id, pos = p1, pos2 = p2, life = life, r = radius * 0.6 })
				-- El rayo que se pasan entre ellas fríe lo que cruce
				local pairBites = P(ctx, "volt2", "pairBites")
				Kit.every(ctx, P(ctx, "volt2", "every"), life, function(_n: number)
					local out = newOut()
					for _, food in Kit.onLine(ctx.stats, p1, p2, 4) do
						if alive(food) then
							zap(ctx, food, pairBites, out)
						end
					end
					ctx.fx("volt2_link", { a = p1 + UP * 5, b = p2 + UP * 5, pts = out.pts })
				end)
				return true
			end

			local coil = plantCoil(ctx, function()
				return a
			end, radius)
			ctx.fx("volt2", { mode = "fixed", id = coil.id, pos = a, life = life, r = radius })
			return true
		end,

		-- Tormenta: nube que te sigue (o fija) y suelta rayos al azar
		volt3 = function(ctx)
			local stats = ctx.stats
			local life = P(ctx, "volt3", "life")
			local radius = P(ctx, "volt3", "radius")
			local rate = math.max(P(ctx, "volt3", "rate"), 0.5)
			local bites = P(ctx, "volt3", "bites")
			local sparkRadius = P(ctx, "volt3", "sparkRadius")
			local sparkBites = P(ctx, "volt3", "sparkBites")
			local fixed = has(ctx, "stormFixed")
			local chain = has(ctx, "stormChain")
			local forks = math.floor(P(ctx, "volt3", "forks") + 0.5)
			local root = ctx.root
			local home = ctx.origin
			ctx.fx("volt3", { life = life, r = radius, fixed = fixed, c = home })

			Kit.every(ctx, 1 / rate, life, function(_n: number)
				local center = if not fixed and root and root.Parent then root.Position else home
				local foods = Kit.inRadius(stats, center, radius)
				if #foods == 0 then
					return
				end
				local target = foods[rng:NextInteger(1, #foods)]
				local out = newOut()
				local pos, _, finished = zap(ctx, target, bites, out)
				local big = finished
				if finished then
					sparks(ctx, pos, sparkRadius, sparkBites, out)
				end
				if chain then
					-- Supercélula: el rayo sigue saltando
					local visited = { [target] = true }
					local from = pos
					for _ = 1, forks do
						local nextFood = Kit.nearest(stats, from, 16, visited)
						if not nextFood then
							break
						end
						visited[nextFood] = true
						local at, _, done = zap(ctx, nextFood, bites * 0.75, out)
						table.insert(out.xa, from)
						table.insert(out.xb, at)
						if done then
							big = true
							sparks(ctx, at, sparkRadius, sparkBites, out)
						end
						from = at
					end
				end
				ctx.fx("volt3_hit", { p = pos, pts = out.pts, xa = out.xa, xb = out.xb, big = big })
			end)
			return true
		end,
	},
}
