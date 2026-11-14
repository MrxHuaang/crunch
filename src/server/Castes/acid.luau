-- Ácida (servidor): la corrosión de la pasiva, el Escupitajo, la Estela cáustica y el Diluvio fórmico.
-- Todo el daño pasa por CasteKit; los clientes pintan con los puntos que mandamos en cada efecto.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Parent.CasteKit)
local Def = require(ReplicatedStorage.Shared.Castes.acid)

local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.new(0, 1, 0)
local DOT_STEP = 0.5 -- la corrosión muerde cada medio segundo

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

-- Golpe de habilidad ácida. Con "Empapada", lo que pisa tus charcos queda marcado y recibe +50 %.
local function melt(ctx, food: Model, bites: number, pts: { Vector3 }): (number, boolean)
	local pos = Kit.posOf(food)
	local soak = has(ctx, "soak")
	if soak then
		if Kit.marked(food, "soak") == true then
			bites *= 1.5
		end
		Kit.mark(food, "soak", 3, true)
	end
	local taken, finished = Kit.strike(ctx, food, bites)
	if taken > 0 then
		table.insert(pts, pos)
	end
	return taken, finished
end

-- Charco volátil: al secarse revienta
local function popPuddle(ctx, center: Vector3, radius: number)
	local pts = {}
	for _, food in Kit.inRadius(ctx.stats, center, radius) do
		if alive(food) then
			melt(ctx, food, 3, pts)
		end
	end
	ctx.fx("acid_pop", { p = center, r = radius, pts = pts })
end

-- Un charco fijo (o que sigue a algo) que muerde cada `every` s lo que tenga encima
local function puddle(ctx, center: Vector3, radius: number, life: number, every: number, bites: number, onEnd: ((Vector3) -> ())?)
	Kit.zone(ctx, {
		center = center,
		radius = radius,
		duration = life,
		every = every,
		tick = function(foods: { Model }, c: Vector3, _n: number)
			local pts = {}
			for _, food in foods do
				if alive(food) then
					melt(ctx, food, bites, pts)
				end
			end
			if #pts > 0 then
				ctx.fx("acid_tick", { c = c, pts = pts })
			end
		end,
	})
	Kit.after(ctx, life, function()
		if onEnd then
			onEnd(center)
		end
		if has(ctx, "volatile") then
			popPuddle(ctx, center, radius)
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Corrosión

local function dropDot(state, dot)
	local i = table.find(state.dots, dot)
	if i then
		table.remove(state.dots, i)
	end
end

local function corrode(ctx, food: Model, position: Vector3, damage: number)
	local bite = math.max(ctx.bite, 1)
	local share = P(ctx, "corrode", "share")
	local state = ctx.state

	if has(ctx, "burst") then
		-- Quemadura: aguanta un momento y revienta de golpe
		state.pops = state.pops or 0
		if state.pops >= math.max(1, math.floor(P(ctx, "corrode", "max") + 0.5)) then
			return
		end
		state.pops += 1
		local delay = P(ctx, "corrode", "popDelay")
		ctx.fx("passive", { p = position, life = delay, burst = true })
		Kit.after(ctx, delay, function()
			state.pops = math.max(0, (state.pops or 1) - 1)
			local pts = {}
			if alive(food) then
				if Kit.nibble(ctx, food, damage * share / bite) > 0 then
					table.insert(pts, position)
				end
			end
			local splash = damage * share * P(ctx, "corrode", "popSplash") / bite
			for _, other in Kit.inRadius(ctx.stats, position, P(ctx, "corrode", "popRadius")) do
				if other ~= food and alive(other) then
					local at = Kit.posOf(other)
					if Kit.nibble(ctx, other, splash) > 0 then
						table.insert(pts, at)
					end
				end
			end
			Kit.flush(ctx)
			ctx.fx("acid_pop", { p = position, r = P(ctx, "corrode", "popRadius"), pts = pts, small = true })
		end)
		return
	end

	-- Goteo: el daño repartido en tics; si ya estaba corroída se suma lo que quedaba
	state.dots = state.dots or {}
	local ticks = math.max(1, math.floor(P(ctx, "corrode", "time") / DOT_STEP + 0.5))
	local total = damage * share / bite
	for _, dot in state.dots do
		if dot.food == food then
			local rest = dot.per * dot.left
			dot.left = ticks
			dot.per = (rest + total) / ticks
			return
		end
	end
	local max = math.max(1, math.floor(P(ctx, "corrode", "max") + 0.5))
	while #state.dots >= max do
		table.remove(state.dots, 1) -- la más antigua deja de corroerse
	end
	table.insert(state.dots, { food = food, pos = position, per = total / ticks, left = ticks })
	ctx.fx("passive", { p = position, life = ticks * DOT_STEP })
end

local function dotTick(ctx)
	local state = ctx.state
	local dots = state.dots
	if not dots or #dots == 0 then
		return
	end
	local any = false
	for _, dot in table.clone(dots) do
		if not alive(dot.food) then
			-- Ácido contagioso: lo que quedaba salta a la comida más cercana
			if has(ctx, "spread") and dot.left > 0 then
				local nextFood = Kit.nearest(ctx.stats, dot.pos, P(ctx, "corrode", "spread"), { [dot.food] = true })
				local taken = false
				for _, other in dots do
					if other.food == nextFood then
						taken = true
					end
				end
				if nextFood and not taken then
					local at = Kit.posOf(nextFood)
					ctx.fx("acid_spread", { a = dot.pos, b = at, life = dot.left * DOT_STEP })
					dot.food = nextFood
					dot.pos = at
					continue
				end
			end
			dropDot(state, dot)
			continue
		end
		if Kit.nibble(ctx, dot.food, dot.per) > 0 then
			any = true
		end
		dot.left -= 1
		if dot.left <= 0 then
			dropDot(state, dot)
		end
	end
	if any then
		Kit.flush(ctx)
	end
end

----------------------------------------------------------------------------------------------------

return {
	passive = {
		unequip = function(ctx)
			ctx.state.dots = {}
			ctx.state.pops = 0
		end,

		bite = function(ctx, food: Model?, position: Vector3, damage: number, finished: boolean)
			if alive(food) and not finished then
				corrode(ctx, food :: Model, position, damage)
			elseif has(ctx, "spread") and finished then
				-- Si el mordisco la terminó, el ácido busca otra al momento
				local nextFood = Kit.nearest(ctx.stats, position, P(ctx, "corrode", "spread"))
				if nextFood then
					ctx.fx("acid_spread", { a = position, b = Kit.posOf(nextFood), life = P(ctx, "corrode", "time") })
					corrode(ctx, nextFood, Kit.posOf(nextFood), damage * 0.5)
				end
			end
		end,

		tick = function(ctx, dt: number)
			local state = ctx.state
			state.dotClock = (state.dotClock or 0) + dt
			if state.dotClock >= DOT_STEP - 0.01 then
				state.dotClock = 0
				dotTick(ctx)
			end
		end,
	},

	abilities = {
		-- Escupitajo: una bola (o tres en abanico) que deja charco; con Géiser estalla al secarse
		acid1 = function(ctx)
			local radius = P(ctx, "acid1", "radius")
			local life = P(ctx, "acid1", "life")
			local every = P(ctx, "acid1", "every")
			local bites = P(ctx, "acid1", "bites")
			local flight = P(ctx, "acid1", "flight")
			local mouth = ctx.origin + UP
			local targets = { ctx.aim }
			if has(ctx, "spitFan") then
				local fan = math.rad(P(ctx, "acid1", "fan"))
				local offset = ctx.aim - ctx.origin
				for _, angle in { fan, -fan } do
					table.insert(targets, ctx.origin + CFrame.Angles(0, angle, 0):VectorToWorldSpace(offset))
				end
			end
			local geyser = has(ctx, "geyser")
			ctx.fx("acid1", { a = mouth, bs = targets, r = radius, life = life, flight = flight, geyser = geyser })
			Kit.after(ctx, flight, function()
				for _, spot in targets do
					puddle(ctx, spot, radius, life, every, bites, if geyser
						then function(center: Vector3)
							local pts = {}
							for _, food in Kit.inRadius(ctx.stats, center, radius) do
								if alive(food) then
									melt(ctx, food, P(ctx, "acid1", "geyserBites"), pts)
								end
							end
							ctx.fx("acid1_geyser", { p = center, r = radius, pts = pts })
						end
						else nil)
				end
			end)
			return true
		end,

		-- Estela cáustica: charcos por donde pasas, o una nube que te envuelve
		acid2 = function(ctx)
			local life = P(ctx, "acid2", "life")
			local every = P(ctx, "acid2", "every")
			local bites = P(ctx, "acid2", "bites")
			local root = ctx.root

			if has(ctx, "cloud") then
				local radius = P(ctx, "acid2", "cloudRadius")
				ctx.fx("acid2", { cloud = true, life = life, r = radius })
				Kit.zone(ctx, {
					center = ctx.origin,
					radius = radius,
					duration = life,
					every = every,
					follow = root,
					tick = function(foods: { Model }, c: Vector3, _n: number)
						local pts = {}
						for _, food in foods do
							if alive(food) then
								melt(ctx, food, bites * 1.25, pts)
							end
						end
						if #pts > 0 then
							ctx.fx("acid_tick", { c = c, pts = pts })
						end
					end,
				})
				return true
			end

			local spacing = math.max(P(ctx, "acid2", "spacing"), 1)
			local radius = P(ctx, "acid2", "radius")
			local puddleLife = P(ctx, "acid2", "puddleLife")
			local volatile = has(ctx, "volatile")
			local spots: { { pos: Vector3, untilAt: number } } = {}
			local last: Vector3? = nil
			ctx.fx("acid2", { cloud = false, life = life, r = radius })

			local function drop(at: Vector3)
				last = at
				local spot = Vector3.new(at.X, ctx.aim.Y, at.Z)
				table.insert(spots, { pos = spot, untilAt = os.clock() + puddleLife })
				ctx.fx("acid2_drop", { p = spot, r = radius, life = puddleLife })
			end

			drop(ctx.origin)
			-- Mira cada poco cuánto has andado y suelta charco cada `spacing` studs
			Kit.every(ctx, 0.1, life, function(_n: number)
				if root and root.Parent then
					local here = root.Position
					if not last or flatDist(here, last) >= spacing then
						drop(here)
					end
				end
			end)
			-- Un solo reloj muerde por todos los charcos (lo que pisa dos, recibe una vez)
			Kit.every(ctx, every, life + puddleLife + 0.1, function(_n: number)
				local now = os.clock()
				local seen: { [Model]: boolean } = {}
				local pts = {}
				for i = #spots, 1, -1 do
					local spot = spots[i]
					if now >= spot.untilAt then
						table.remove(spots, i)
						if volatile then
							popPuddle(ctx, spot.pos, radius)
						end
						continue
					end
					for _, food in Kit.inRadius(ctx.stats, spot.pos, radius) do
						if not seen[food] and alive(food) then
							seen[food] = true
							melt(ctx, food, bites, pts)
						end
					end
				end
				if #pts > 0 then
					ctx.fx("acid_tick", { pts = pts })
				end
			end)
			return true
		end,

		-- Diluvio fórmico: lluvia en un sitio, que te sigue (Tifón) o que se cierra (Monzón)
		acid3 = function(ctx)
			local stats = ctx.stats
			local life = P(ctx, "acid3", "life")
			local radius = P(ctx, "acid3", "radius")
			local every = P(ctx, "acid3", "every")
			local bites = P(ctx, "acid3", "bites")
			local bubbleRadius = P(ctx, "acid3", "bubbleRadius")
			local bubbleBites = P(ctx, "acid3", "bubbleBites")
			local follow = has(ctx, "rainFollow")
			local monsoon = has(ctx, "monsoon")
			local shrinkTo = P(ctx, "acid3", "shrinkTo")
			local growTo = P(ctx, "acid3", "growTo")
			if follow then
				radius = P(ctx, "acid3", "followRadius")
			end
			local root = ctx.root
			local home = ctx.aim
			local started = os.clock()
			ctx.fx("acid3", { c = home, r = radius, life = life, follow = follow, monsoon = monsoon, r2 = shrinkTo })

			Kit.every(ctx, every, life, function(_n: number)
				local t = math.clamp((os.clock() - started) / life, 0, 1)
				local center = if follow and root and root.Parent then root.Position else home
				local r = radius
				local hit = bites
				if monsoon then
					r = radius + (shrinkTo - radius) * t
					hit = bites * (1 + (growTo - 1) * t)
				end
				local pts, pops = {}, {}
				for _, food in Kit.inRadius(stats, center, r) do
					if alive(food) then
						local at = Kit.posOf(food)
						local _, finished = melt(ctx, food, hit, pts)
						if finished then
							-- Burbuja: revienta y salpica a las vecinas
							table.insert(pops, at)
							for _, other in Kit.inRadius(stats, at, bubbleRadius) do
								if alive(other) then
									melt(ctx, other, bubbleBites, pts)
								end
							end
						end
					end
				end
				if #pts > 0 or #pops > 0 then
					ctx.fx("acid3_tick", { c = center, r = r, pts = pts, pops = pops })
				end
			end)
			return true
		end,
	},
}
