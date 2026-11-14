-- Melera (servidor): la carga que fermenta, el Néctar que hace valer más la comida, la Bola de miel
-- que se lo pega todo y el Reventón dorado. Definición en shared/Castes/honey; efectos en
-- client/Castes/honey.
--
-- El valor extra de la comida bañada pasa por FoodService.valueHook (el gancho de Garden): se
-- encadena al que ya hubiera, no lo sustituye. Así vale más para la Melera y para su colonia, y
-- para nadie más. Se instala la primera vez que hace falta (después de que Garden ponga el suyo).
-- Atributos que lee el cliente: en la comida "HoneyGlaze" / "HoneyGold" (hora de servidor en que se
-- acaba), en la jugadora "HoneyFerment" (fermento en %, entero) y "HoneyFermentMax".

local Players = game:GetService("Players")

local Kit = require(script.Parent.Parent.CasteKit)
local Events = require(script.Parent.Parent.Events)
local FoodService = require(script.Parent.Parent.FoodService)
local PlayerService = require(script.Parent.Parent.PlayerService)
local Profiles = require(script.Parent.Parent.Profiles)

local function now(): number
	return workspace:GetServerTimeNow()
end

---------------------------------------------------------------------------------------------------
-- Comida bañada: [comida] = { [clave] = { player, mult, untilT } }
---------------------------------------------------------------------------------------------------

local glazed: { [Model]: { [string]: any } } = {}
local hooked = false

local function installHook()
	if hooked then
		return
	end
	hooked = true
	local previous = FoodService.valueHook
	FoodService.valueHook = function(food: Model, def, stats, value: number): number
		if previous then
			value = previous(food, def, stats, value)
		end
		local coats = glazed[food]
		if not coats then
			return value
		end
		local t = now()
		for key, coat in coats do
			if t > coat.untilT then
				coats[key] = nil
			else
				local profile = Profiles.get(coat.player)
				if profile and profile.stats == stats then
					value *= coat.mult
				end
			end
		end
		if next(coats) == nil then
			glazed[food] = nil
		end
		return value
	end
end

local ATTR = { nectar = "HoneyGlaze", gold = "HoneyGold" }

local function glaze(ctx, food: Model, key: string, mult: number, seconds: number)
	if not FoodService.isFood(food) then
		return
	end
	installHook()
	local coats = glazed[food]
	if not coats then
		coats = {}
		glazed[food] = coats
	end
	local untilT = now() + seconds
	local old = coats[key]
	if old and old.player == ctx.player and old.untilT > untilT and old.mult >= mult then
		return
	end
	coats[key] = { player = ctx.player, mult = mult, untilT = untilT }
	food:SetAttribute(ATTR[key], untilT)
	Kit.mark(food, "honey_" .. key, seconds, ctx.player.UserId)
end

-- Limpieza de lo caducado (comidas que nadie volvió a valorar)
task.spawn(function()
	while true do
		task.wait(5)
		local t = now()
		for food, coats in glazed do
			if not FoodService.isFood(food) then
				glazed[food] = nil
				continue
			end
			for key, coat in coats do
				if t > coat.untilT then
					coats[key] = nil
				end
			end
			if next(coats) == nil then
				glazed[food] = nil
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for _, coats in glazed do
		for key, coat in coats do
			if coat.player == player then
				coats[key] = nil
			end
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Fermento
---------------------------------------------------------------------------------------------------

local function fermentOf(ctx): number
	local s = ctx.state.ferment
	return if s then s.applied else 0
end

local function publish(ctx, applied: number)
	local pct = math.floor(applied * 100 + 0.5)
	local player = ctx.player
	if player:GetAttribute("HoneyFerment") ~= pct then
		player:SetAttribute("HoneyFerment", pct)
	end
	local max = ctx.param("fermento", "maxPct")
	if player:GetAttribute("HoneyFermentMax") ~= max then
		player:SetAttribute("HoneyFermentMax", max)
	end
end

local function resetFerment(ctx, keep: boolean)
	local s = ctx.state.ferment
	local carried = if s then s.applied else 0
	ctx.state.ferment = {
		since = nil, -- hora en que empezó la carga
		base = 0, -- valor de la carga sin fermentar
		lastSet = 0, -- valor que pusimos en la carga la última vez
		applied = 0,
		head = if keep then carried * ctx.param("fermento", "keepPct") / 100 else 0,
	}
	publish(ctx, 0)
end

-- La carga gana valor con el tiempo. Lo que entra nuevo se suma a la base sin fermentar y fermenta
-- igual que lo demás (el fermento es de la carga entera, no trozo a trozo).
local function fermentTick(ctx)
	local profile = ctx.profile
	if not ctx.state.ferment then
		resetFerment(ctx, false)
	end
	local s = ctx.state.ferment
	if profile.carry <= 0 then
		if s.since then
			resetFerment(ctx, false)
		end
		return
	end
	local rate = ctx.param("fermento", "ratePct") / 100
	local max = ctx.param("fermento", "maxPct") / 100
	local t = now()
	if not s.since then
		-- Madre de la miel: la carga nueva empieza con parte del fermento anterior
		s.since = t - (if rate > 0 then s.head / rate else 0)
	end
	local applied = math.clamp(rate * (t - s.since), 0, max)
	local delta = profile.carryValue - s.lastSet
	if delta < -1e-6 then
		-- Alguien vació o recortó la carga por fuera: recalculamos la base desde lo que hay
		s.base = profile.carryValue / (1 + s.applied)
	else
		s.base += delta
	end
	profile.carryValue = s.base * (1 + applied)
	s.lastSet = profile.carryValue
	s.applied = applied
	publish(ctx, applied)
end

---------------------------------------------------------------------------------------------------
-- Pegar comida a la carga pudiendo pasarse del tope (Bola de miel)
---------------------------------------------------------------------------------------------------

local function stick(ctx, food: Model, bites: number, cap: number): number
	local profile = ctx.profile
	local stats = ctx.stats
	local space = cap - profile.carry
	if space <= 0 or not FoodService.isFood(food) or not Kit.edible(stats, food) then
		return 0
	end
	local def = FoodService.defOf(food)
	local amount = bites * ctx.bite * (if def.hard then stats.hardMult else 1)
	local color = food:GetAttribute("Color")
	local goldFood = FoodService.isGolden(food)
	local piece = FoodService.pieceValue(food, def, stats)
	local taken, _, finished = FoodService.damage(food, math.min(math.ceil(amount), math.floor(space)))
	if taken > 0 then
		profile.carry += taken
		profile.carryValue += taken * piece
		if typeof(color) == "Color3" then
			profile.carryColor = color
		end
		if goldFood then
			profile.carryGold = true
		end
		Profiles.trackFood(profile, def, taken)
		Events.fire("Ate", profile, def, taken, false)
		Kit.xp(ctx, taken / math.max(ctx.bite, 1))
	end
	if finished then
		Profiles.awardTrophy(profile, def)
		Events.fire("Finished", profile, def)
	end
	return taken
end

---------------------------------------------------------------------------------------------------
-- Habilidades
---------------------------------------------------------------------------------------------------

local function nectar(ctx): boolean
	local radius = ctx.param("honey1", "radius")
	local mult = ctx.param("honey1", "mult")
	local duration = ctx.param("honey1", "duration")
	local drop = ctx.has("nectarDrop")
	local pool = ctx.has("nectarPool")
	local center = ctx.aim
	local flight = 0.45

	if drop then
		-- Gota concentrada: solo la comida más cercana al punto, aunque esté algo más lejos
		local food = ctx.aimFood or Kit.nearest(ctx.stats, center, radius + 8)
		if not food then
			return false
		end
		center = Kit.posOf(food) - Vector3.new(0, 1, 0)
	end

	ctx.fx("honey1", {
		from = ctx.origin + Vector3.new(0, 2, 0),
		center = center,
		radius = radius,
		duration = duration,
		flight = flight,
		pool = pool,
		drop = drop,
	})

	Kit.after(ctx, flight, function()
		local foods = Kit.inRadius(ctx.stats, center, radius)
		if drop then
			foods = { foods[1] }
		end
		local points = {}
		for _, food in foods do
			glaze(ctx, food, "nectar", mult, duration)
			table.insert(points, Kit.posOf(food))
		end
		Kit.xp(ctx, #points)
		ctx.fx("honey1_land", { center = center, radius = radius, points = points, duration = duration, mult = mult, pool = pool })

		if pool then
			-- Charco de miel: muerde cada segundo a lo que hay dentro y baña a lo que llegue
			local bites = ctx.param("honey1", "poolBites")
			Kit.zone(ctx, {
				center = center,
				radius = radius,
				duration = duration,
				every = 1,
				tick = function(inside: { Model }, at: Vector3, _n: number)
					for _, food in inside do
						glaze(ctx, food, "nectar", mult, 2)
					end
					local hit, amounts = Kit.strikeMany(ctx, inside, bites)
					if #hit > 0 then
						ctx.fx("honey1_pool", { center = at, points = hit, amounts = amounts })
					end
				end,
			})
		end
	end)
	return true
end

local function honeyBall(ctx): boolean
	local bounce = ctx.has("ballBounce")
	local duration = ctx.param("honey2", "duration")
	local cap = ctx.stats.capacity * ctx.param("honey2", "over")
	local root = ctx.root
	local radius = if bounce then ctx.param("honey2", "hopRadius") else ctx.param("honey2", "radius")
	local bites = if bounce then ctx.param("honey2", "hopBites") else ctx.param("honey2", "bites")
	ctx.fx("honey2", {
		duration = duration,
		speed = ctx.param("honey2", "speed"),
		radius = radius,
		bounce = bounce,
		every = if bounce then 0.8 else 0.2,
	})
	Kit.zone(ctx, {
		center = ctx.origin,
		radius = radius,
		duration = duration,
		every = if bounce then 0.8 else 0.2,
		follow = root,
		tick = function(foods: { Model }, center: Vector3, _n: number)
			local points, amounts = {}, {}
			for i = 1, math.min(#foods, 6) do
				local food = foods[i]
				local at = Kit.posOf(food)
				local taken = stick(ctx, food, bites, cap)
				if taken > 0 then
					table.insert(points, at)
					table.insert(amounts, taken)
				end
			end
			if #points > 0 then
				PlayerService.refreshCarry(ctx.profile)
			end
			if bounce then
				ctx.fx("honey2_hop", { center = center, radius = radius, points = points, amounts = amounts })
			elseif #points > 0 then
				ctx.fx("honey2_hit", { center = center, points = points, amounts = amounts })
			end
		end,
	})
	return true
end

local function goldenBurst(ctx): boolean
	local radius = ctx.param("honey3", "radius")
	local gold = ctx.param("honey3", "gold")
	local duration = ctx.param("honey3", "duration")
	local center = ctx.origin
	local windup = 0.4

	if ctx.has("burstRain") then
		-- Lluvia de miel: sin explosión, gotas de oro que caen una a una sobre la comida cercana
		ctx.fx("honey3", { center = center, radius = radius, windup = windup, rain = true, duration = duration })
		local rng = Random.new()
		Kit.every(ctx, 0.5, duration, function(_n: number)
			local foods = Kit.inRadius(ctx.stats, center, radius)
			if #foods == 0 then
				return
			end
			local picked, points = {}, {}
			for _ = 1, math.min(3, #foods) do
				local food = foods[rng:NextInteger(1, #foods)]
				if not table.find(picked, food) then
					table.insert(picked, food)
				end
			end
			for _, food in picked do
				table.insert(points, Kit.posOf(food))
			end
			local hit, amounts = Kit.strikeMany(ctx, picked, 2)
			for _, food in picked do
				glaze(ctx, food, "gold", gold, duration)
			end
			ctx.fx("honey3_drop", { points = points, hit = hit, amounts = amounts, gold = gold, duration = duration })
		end)
		return true
	end

	ctx.fx("honey3", { center = center, radius = radius, windup = windup, rain = false, duration = duration })
	Kit.after(ctx, windup, function()
		local foods = Kit.inRadius(ctx.stats, center, radius)
		local points, amounts = Kit.strikeMany(ctx, foods, ctx.param("honey3", "bites"))
		local golden = {}
		for _, food in foods do
			if FoodService.isFood(food) then
				glaze(ctx, food, "gold", gold, duration)
				table.insert(golden, Kit.posOf(food))
			end
		end
		ctx.fx("honey3_boom", {
			center = center,
			radius = radius,
			points = points,
			amounts = amounts,
			golden = golden,
			duration = duration,
			gold = gold,
		})
	end)
	return true
end

---------------------------------------------------------------------------------------------------

return {
	passive = {
		equip = function(ctx)
			resetFerment(ctx, false)
		end,
		unequip = function(ctx)
			ctx.player:SetAttribute("HoneyFerment", nil)
			ctx.player:SetAttribute("HoneyFermentMax", nil)
		end,
		tick = function(ctx, _dt: number)
			fermentTick(ctx)
		end,
		deposit = function(ctx, _credited: number, _fullLoad: boolean)
			local applied = fermentOf(ctx)
			if applied > 0.05 then
				ctx.fx("passive", { at = ctx.hill or ctx.origin, pct = math.floor(applied * 100 + 0.5) })
			end
			resetFerment(ctx, true)
		end,
		bite = function(ctx, food: Model, _position: Vector3, damage: number, finished: boolean)
			-- Miel ácida: más fermento, más mordisco (va a la carga, como el mordisco)
			local pct = ctx.param("fermento", "bitePct")
			if pct <= 0 or finished or not FoodService.isFood(food) then
				return
			end
			local max = math.max(ctx.param("fermento", "maxPct") / 100, 0.01)
			local strength = math.clamp(fermentOf(ctx) / max, 0, 1)
			local extra = damage * pct / 100 * strength
			if extra >= 1 then
				Kit.nibble(ctx, food, extra / math.max(ctx.bite, 1))
				Kit.flush(ctx)
			end
		end,
	},
	abilities = {
		honey1 = nectar,
		honey2 = honeyBall,
		honey3 = goldenBurst,
	},
}
