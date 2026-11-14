-- Porteadora (servidor): carga enorme, Catapulta, Caravana y Convoy.
-- Definición y números en shared/Castes/porter; efectos en client/Castes/porter.

local Kit = require(script.Parent.Parent.CasteKit)
local FoodService = require(script.Parent.Parent.FoodService)
local PlayerService = require(script.Parent.Parent.PlayerService)
local Profiles = require(script.Parent.Parent.Profiles)

local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.new(0, 1, 0)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return v * FLAT
end

-- Golpea varias comidas y devuelve las posiciones y trozos de las que dieron algo
local function strikeList(ctx, foods: { Model }, bites: number, worth: number?): ({ Vector3 }, { number })
	if #foods == 0 then
		return {}, {}
	end
	return Kit.strikeMany(ctx, foods, bites, worth)
end

---------------------------------------------------------------------------------------------------
-- Catapulta
---------------------------------------------------------------------------------------------------

-- Cesto plantado (mutación): recoge solo a su alrededor un rato, botín directo a casa
local function plantBasket(ctx, at: Vector3)
	local radius = ctx.param("porter1", "basketRadius")
	Kit.zone(ctx, {
		center = at,
		radius = radius,
		duration = ctx.param("porter1", "basketTime"),
		every = 0.5,
		tick = function(foods: { Model }, center: Vector3, _n: number)
			local picked = {}
			for i = 1, math.min(2, #foods) do
				picked[i] = foods[i]
			end
			local points, amounts = strikeList(ctx, picked, 1)
			if #points > 0 then
				ctx.fx("porter1_basket", { at = center, points = points, amounts = amounts })
			end
		end,
	})
end

local function catapult(ctx): boolean
	local profile = ctx.profile
	local stats = ctx.stats
	local carry, value = profile.carry, profile.carryValue
	if carry <= 0 or not ctx.hill then
		Profiles.say(profile, "¡El cesto está vacío! Primero hay que llenarlo", 3)
		return false
	end
	local cannon = ctx.has("catCannon")
	if cannon and carry < stats.capacity then
		Profiles.say(profile, "La bala de cañón solo sale con el cesto lleno", 3)
		return false
	end

	local fill = math.clamp(carry / math.max(stats.capacity, 1), 0, 1.5)
	local color = profile.carryColor
	local golden = profile.carryGold == true
	profile.carry = 0
	profile.carryValue = 0
	PlayerService.refreshCarry(profile)

	local worth = if cannon then 1 + ctx.param("porter1", "cannonPct") / 100 else 1
	local flight = ctx.param("porter1", "flight")
	local from = ctx.origin + UP * 2.5
	local hillTop = ctx.hill + UP * 8

	-- Asedio: primero cae sobre la comida más cercana y la revienta; luego rebota a casa
	local smashAt: Vector3? = nil
	local target = if ctx.has("catSiege") then Kit.nearest(stats, ctx.origin, 45) else nil
	if target then
		smashAt = Kit.posOf(target)
	end

	local hitTime = if smashAt then flight * 0.6 else 0
	local total = if smashAt then flight * 1.5 else flight

	ctx.fx("porter1", {
		from = from,
		to = hillTop,
		smash = smashAt,
		flight = flight,
		hitTime = hitTime,
		total = total,
		fill = fill,
		color = color,
		golden = golden,
		cannon = cannon,
		basket = ctx.has("catBasket"),
		basketTime = ctx.param("porter1", "basketTime"),
		basketRadius = ctx.param("porter1", "basketRadius"),
		origin = ctx.origin,
	})

	if target and smashAt then
		local bites = ctx.param("porter1", "smashBites") * (0.5 + fill)
		Kit.after(ctx, hitTime, function()
			if FoodService.isFood(target) then
				local taken = Kit.strike(ctx, target, bites)
				ctx.fx("porter1_smash", { at = smashAt, amount = taken })
			end
		end)
	end
	if ctx.has("catBasket") then
		plantBasket(ctx, ctx.origin)
	end

	-- La entrega no se cancela aunque cambies de casta: la comida ya va por el aire
	task.delay(total, function()
		if profile.player.Parent then
			PlayerService.deliver(profile, carry, value * worth)
		end
	end)
	return true
end

---------------------------------------------------------------------------------------------------
-- Caravana
---------------------------------------------------------------------------------------------------

local function caravan(ctx): boolean
	local duration = ctx.param("porter2", "duration")
	local count = math.floor(ctx.param("porter2", "porters"))
	local fetch = ctx.has("caravanFetch")
	local token = {}
	ctx.state.caravan = {
		token = token,
		untilT = now() + duration,
		count = count,
		share = ctx.param("porter2", "sharePct") / 100,
		reach = ctx.param("porter2", "reach"),
	}
	ctx.fx("porter2", { duration = duration, count = count, fetch = fetch })

	if fetch then
		-- Mulas sueltas: forrajean solas cerca de ti, cada una a su comida
		local bites = ctx.param("porter2", "fetchBites")
		local reach = ctx.param("porter2", "reach") + 10
		Kit.every(ctx, ctx.param("porter2", "fetchEvery"), duration, function(_n: number)
			local root = ctx.player.Character and ctx.player.Character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				return
			end
			local skip = {}
			local points, amounts, who = {}, {}, {}
			for i = 1, count do
				local food = Kit.nearest(ctx.stats, root.Position, reach, skip)
				if not food then
					break
				end
				skip[food] = true
				local at = Kit.posOf(food)
				local taken = Kit.strike(ctx, food, bites)
				if taken > 0 then
					table.insert(points, at)
					table.insert(amounts, taken)
					table.insert(who, i)
				end
			end
			if #points > 0 then
				ctx.fx("porter2_hit", { points = points, amounts = amounts, who = who })
			end
		end)
	end
	Kit.after(ctx, duration, function()
		if ctx.state.caravan and ctx.state.caravan.token == token then
			ctx.state.caravan = nil
		end
	end)
	return true
end

-- Cada porteadora repite tu mordisco sobre la misma comida (o la más cercana si se acabó)
local function caravanBite(ctx, food: Model, position: Vector3, damage: number, finished: boolean)
	local c = ctx.state.caravan
	if not c or now() > c.untilT or ctx.has("caravanFetch") then
		return
	end
	local bites = damage * c.share / math.max(ctx.bite, 1)
	local points, amounts, who = {}, {}, {}
	for i = 1, c.count do
		local target: Model? = nil
		if not finished and FoodService.isFood(food) then
			target = food
		else
			target = Kit.nearest(ctx.stats, position, c.reach)
		end
		if not target then
			break
		end
		local at = Kit.posOf(target)
		local taken, done = Kit.strike(ctx, target, bites)
		if taken > 0 then
			table.insert(points, at)
			table.insert(amounts, taken)
			table.insert(who, i)
		end
		if done and target == food then
			finished = true
		end
	end
	if #points > 0 then
		ctx.fx("porter2_hit", { points = points, amounts = amounts, who = who })
	end
end

---------------------------------------------------------------------------------------------------
-- Convoy
---------------------------------------------------------------------------------------------------

local function convoy(ctx): boolean
	local ram = ctx.has("convoyRam")
	local start = if ram or not ctx.hill then ctx.origin else ctx.hill
	local finish = ctx.aim
	if ram then
		finish = ctx.origin + ctx.dir * 80 -- arrasa hasta el alcance entero de la habilidad
	end
	start = Vector3.new(start.X, ctx.aim.Y, start.Z)
	finish = Vector3.new(finish.X, ctx.aim.Y, finish.Z)
	local path = flat(finish - start)
	local length = path.Magnitude
	if length < 4 then
		return false
	end
	local dir = path / length
	-- Nunca tarda más de ~4 s en llegar, por lejos que quede el hormiguero
	local speed = math.max(ctx.param("porter3", "speed"), length / 4)
	local width = ctx.param("porter3", "width")
	local bites = ctx.param("porter3", "bites")
	local worth = ctx.param("porter3", "worth")
	local wagons = if ctx.has("convoyTrain") then 3 else 1
	local gap = 0.55 -- segundos entre vagones del tren
	local windup = 0.45 -- el escarabajo sale del hormiguero

	-- Cuándo pasa cada vagón por cada comida
	local plan = {}
	for _, food in Kit.onLine(ctx.stats, start, finish, width) do
		local along = math.clamp(flat(food:GetPivot().Position - start):Dot(dir), 0, length)
		for w = 1, wagons do
			table.insert(plan, { food = food, at = windup + along / speed + (w - 1) * gap })
		end
	end
	table.sort(plan, function(a, b)
		return a.at < b.at
	end)

	local travel = length / speed
	ctx.fx("porter3", {
		from = start,
		to = finish,
		travel = travel,
		windup = windup,
		width = width,
		wagons = wagons,
		gap = gap,
		ram = ram,
	})

	local began = os.clock()
	local index = 1
	Kit.every(ctx, 0.1, windup + travel + gap * wagons + 0.3, function(_n: number)
		local elapsed = os.clock() - began
		local due = {}
		while plan[index] and plan[index].at <= elapsed do
			local food = plan[index].food
			if FoodService.isFood(food) and not table.find(due, food) then
				table.insert(due, food)
			end
			index += 1
		end
		local points, amounts = strikeList(ctx, due, bites, worth)
		if #points > 0 then
			ctx.fx("porter3_hit", { points = points, amounts = amounts })
		end
	end)
	return true
end

---------------------------------------------------------------------------------------------------

return {
	passive = {
		stats = function(stats, ctx)
			local mult = ctx.param("lomo", "carry")
			stats.capacity = math.floor(stats.capacity * mult)
			if stats.ownCapacity then
				stats.ownCapacity = math.floor(stats.ownCapacity * mult)
			end
		end,
		deposit = function(ctx, credited: number, fullLoad: boolean)
			local pct = ctx.param("lomo", "fullPct")
			if fullLoad and pct > 0 and credited > 0 then
				local bonus = credited * pct / 100
				Kit.credit(ctx, bonus)
				ctx.fx("passive", { at = ctx.hill or ctx.origin, amount = bonus })
			end
		end,
		bite = function(ctx, food: Model, position: Vector3, damage: number, finished: boolean)
			caravanBite(ctx, food, position, damage, finished)
		end,
	},
	abilities = {
		porter1 = catapult,
		porter2 = caravan,
		porter3 = convoy,
	},
}
