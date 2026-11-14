-- Tejedora (servidor): hilos que atan comida, Red que la amontona, Capullo que la remolca y Telaraña
-- que reparte el daño. Definición en shared/Castes/weaver; efectos en client/Castes/weaver.
--
-- Las comidas se mueven de verdad (PivotTo, suave, en Heartbeat). Nadie guarda la posición de una
-- comida aparte salvo el rastro de Colony (solo para buscar otra igual si se acaba) y los
-- clientes, que la leen del modelo: moverla no rompe obreras ni reapariciones (la reaparición
-- busca sitio nuevo con FoodService.freeSpot).
-- Cada hilo se publica como atributo de la comida "WeaverTie<UserId>" = hora de servidor en que se
-- suelta; el cliente dibuja los Beam leyendo ese atributo (así también los ve quien entra tarde).

local RunService = game:GetService("RunService")

local Kit = require(script.Parent.Parent.CasteKit)
local FoodService = require(script.Parent.Parent.FoodService)

local FLAT = Vector3.new(1, 0, 1)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(ctx): BasePart?
	local character = ctx.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function movable(food: Model): boolean
	local def = FoodService.defOf(food)
	return def ~= nil and not def.boss
end

---------------------------------------------------------------------------------------------------
-- Mover comida con suavidad (la última orden manda)
---------------------------------------------------------------------------------------------------

local gliding: { [Model]: any } = {}

local function glide(food: Model, to: Vector3, time: number, onDone: (() -> ())?)
	if not FoodService.isFood(food) then
		return
	end
	local token = {}
	gliding[food] = token
	local start = food:GetPivot()
	local from = start.Position
	local target = Vector3.new(to.X, from.Y, to.Z)
	local began = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if gliding[food] ~= token or not FoodService.isFood(food) then
			connection:Disconnect()
			if gliding[food] == token then
				gliding[food] = nil
			end
			return
		end
		local a = math.clamp((os.clock() - began) / math.max(time, 0.05), 0, 1)
		local eased = 1 - (1 - a) ^ 3
		food:PivotTo(start.Rotation + from:Lerp(target, eased))
		if a >= 1 then
			connection:Disconnect()
			gliding[food] = nil
			if onDone then
				onDone()
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Hilos
---------------------------------------------------------------------------------------------------

local function tieKey(ctx): string
	return "WeaverTie" .. ctx.player.UserId
end

local function untie(ctx, food: Model)
	local ties = ctx.state.ties
	if ties then
		ties[food] = nil
	end
	if food.Parent then
		food:SetAttribute(tieKey(ctx), nil)
	end
end

-- passive: cuenta para el tope de hilos de la pasiva (las de la Red y la Telaraña no)
local function tie(ctx, food: Model, seconds: number, passive: boolean)
	if not FoodService.isFood(food) then
		return
	end
	ctx.state.ties = ctx.state.ties or {}
	local ties = ctx.state.ties
	local untilT = now() + seconds
	local old = ties[food]
	if old and old.untilT > untilT then
		untilT = old.untilT
	end
	ties[food] = { untilT = untilT, passive = passive or (old ~= nil and old.passive) }
	food:SetAttribute(tieKey(ctx), untilT)

	if passive then
		local max = math.max(1, math.floor(ctx.param("hilo", "max")))
		local list = {}
		for other, entry in ties do
			if entry.passive then
				table.insert(list, { food = other, untilT = entry.untilT })
			end
		end
		table.sort(list, function(a, b)
			return a.untilT < b.untilT
		end)
		for i = 1, #list - max do
			if list[i].food ~= food then
				untie(ctx, list[i].food)
			end
		end
	end
end

local function tiedFoods(ctx, except: Model?): { Model }
	local list = {}
	local t = now()
	for food, entry in ctx.state.ties or {} do
		if food ~= except and entry.untilT > t and FoodService.isFood(food) then
			table.insert(list, food)
		end
	end
	return list
end

local function untieAll(ctx)
	for food in ctx.state.ties or {} do
		untie(ctx, food)
	end
end

---------------------------------------------------------------------------------------------------
-- Telaraña: reparte el daño entre las comidas que estén sobre ella
---------------------------------------------------------------------------------------------------

local function webCenter(ctx): Vector3?
	local web = ctx.state.web
	if not web or now() > web.untilT then
		return nil
	end
	if web.follow then
		local root = rootOf(ctx)
		return if root then root.Position else nil
	end
	return web.center
end

local function webSpread(ctx, food: Model?, position: Vector3, damage: number)
	local web = ctx.state.web
	local center = webCenter(ctx)
	if not web or not center then
		return
	end
	if ((position - center) * FLAT).Magnitude > web.radius + 1 then
		return
	end
	local others = {}
	for _, other in Kit.inRadius(ctx.stats, center, web.radius) do
		if other ~= food then
			table.insert(others, other)
			if #others >= web.max then
				break
			end
		end
	end
	if #others == 0 then
		return
	end
	local points, amounts = Kit.strikeMany(ctx, others, damage * web.share / math.max(ctx.bite, 1))
	if #points > 0 then
		ctx.fx("weaver3_pulse", { from = position, points = points, amounts = amounts })
	end
end

---------------------------------------------------------------------------------------------------
-- Habilidades
---------------------------------------------------------------------------------------------------

-- Sitios del montón: espiral apretada alrededor del centro, las grandes primero
local function pileSpots(center: Vector3, foods: { Model }): { Vector3 }
	local spots = {}
	local size = 0
	for _, food in foods do
		size += (food:GetAttribute("Radius") :: number?) or 1
	end
	size /= math.max(#foods, 1)
	for i = 1, #foods do
		if i == 1 then
			spots[i] = center
		else
			local angle = i * 2.39996
			local dist = math.sqrt(i - 1) * size * 1.55
			spots[i] = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		end
	end
	return spots
end

local function net(ctx): boolean
	local radius = ctx.param("weaver1", "radius")
	local tieTime = ctx.param("weaver1", "tie")
	local haul = ctx.has("netHaul")
	local snap = ctx.has("netSnap")
	local foods = {}
	for _, food in Kit.inRadius(ctx.stats, ctx.aim, radius) do
		if movable(food) then
			table.insert(foods, food)
		end
	end
	table.sort(foods, function(a, b)
		return ((a:GetAttribute("Radius") :: number?) or 1) > ((b:GetAttribute("Radius") :: number?) or 1)
	end)

	-- Red de pesca: el montón se hace a tus patas, un poco por delante
	local center = ctx.aim
	if haul then
		local toward = (ctx.aim - ctx.origin) * FLAT
		local step = if toward.Magnitude > 0.1 then toward.Unit else ctx.dir
		local lead = 3 + (if foods[1] then ((foods[1]:GetAttribute("Radius") :: number?) or 1) else 0)
		center = Vector3.new(ctx.origin.X, ctx.aim.Y, ctx.origin.Z) + step * lead
	end

	local spots = pileSpots(center, foods)
	local from = {}
	local pull = 0.75 -- segundos que tarda en cerrarse
	for i, food in foods do
		from[i] = Kit.posOf(food)
		glide(food, spots[i], pull + (i - 1) * 0.03)
		tie(ctx, food, tieTime, false)
	end
	local to = {}
	for i, spot in spots do
		to[i] = spot + Vector3.new(0, 1, 0)
	end
	Kit.xp(ctx, #foods)

	ctx.fx("weaver1", {
		center = ctx.aim,
		pile = center,
		radius = radius,
		from = from,
		to = to,
		pull = pull,
		haul = haul,
		snap = snap,
		origin = ctx.origin,
	})

	if snap and #foods > 0 then
		Kit.after(ctx, pull + 0.05, function()
			local alive = {}
			for _, food in foods do
				if FoodService.isFood(food) then
					table.insert(alive, food)
				end
			end
			local points, amounts = Kit.strikeMany(ctx, alive, ctx.param("weaver1", "snapBites"))
			if #points > 0 then
				ctx.fx("weaver1_snap", { center = center, points = points, amounts = amounts })
			end
		end)
	end
	return true
end

local function cocoon(ctx): boolean
	local cap = ctx.param("weaver2", "cap")
	local time = ctx.param("weaver2", "time")
	local burst = ctx.has("cocoonBurst")
	local targets = {}
	if ctx.has("cocoonTriple") then
		for _, food in Kit.inRadius(ctx.stats, ctx.aim, 16) do
			if movable(food) then
				table.insert(targets, food)
				if #targets >= math.floor(ctx.param("weaver2", "count")) then
					break
				end
			end
		end
	else
		local food = ctx.aimFood or Kit.nearest(ctx.stats, ctx.aim, 8)
		if food then
			targets[1] = food
		end
	end
	if #targets == 0 then
		return false
	end

	local hill = ctx.hill or ctx.origin
	local points, wholes = {}, {}
	for i, food in targets do
		points[i] = Kit.posOf(food)
		local hp = (food:GetAttribute("Hp") :: number?) or 0
		local whole = not burst and movable(food) and hp <= cap * ctx.bite
		wholes[i] = if whole then 1 else 0
	end

	ctx.fx("weaver2", {
		points = points,
		wholes = wholes,
		to = hill + Vector3.new(0, 4, 0),
		time = time,
		burst = burst,
		origin = ctx.origin,
	})

	if burst then
		-- Capullo bomba: revienta donde está y salpica alrededor
		local burstRadius = ctx.param("weaver2", "burstRadius")
		local burstBites = ctx.param("weaver2", "burstBites")
		Kit.after(ctx, 1.1, function()
			local hitPoints, hitAmounts = {}, {}
			for i, food in targets do
				if FoodService.isFood(food) then
					local taken = Kit.strike(ctx, food, cap)
					if taken > 0 then
						table.insert(hitPoints, points[i])
						table.insert(hitAmounts, taken)
					end
				end
				local splash = {}
				for _, other in Kit.inRadius(ctx.stats, points[i], burstRadius) do
					if not table.find(targets, other) then
						table.insert(splash, other)
					end
				end
				local sp, sa = Kit.strikeMany(ctx, splash, burstBites)
				for j, p in sp do
					table.insert(hitPoints, p)
					table.insert(hitAmounts, sa[j])
				end
			end
			ctx.fx("weaver2_burst", { centers = points, points = hitPoints, amounts = hitAmounts, radius = burstRadius })
		end)
		return true
	end

	for i, food in targets do
		if wholes[i] == 1 then
			-- Entera: el hilo remolca la comida de verdad hasta el hormiguero y allí se entrega
			local home = food:GetPivot()
			local flatGap = (points[i] - hill) * FLAT
			local dest = hill + (if flatGap.Magnitude > 0.1 then flatGap.Unit else Vector3.xAxis) * 5
			tie(ctx, food, time + 0.5, false)
			glide(food, dest, time, function()
				if not FoodService.isFood(food) then
					return
				end
				local hp = (food:GetAttribute("Hp") :: number?) or 0
				local taken = Kit.strike(ctx, food, hp / math.max(ctx.bite, 1) + 1)
				ctx.fx("weaver2_land", { at = dest + Vector3.new(0, 2, 0), amount = taken })
				if FoodService.isFood(food) then
					glide(food, home.Position, 1.2) -- no se pudo comer: vuelve a su sitio
				end
			end)
		else
			-- Demasiado grande: se arranca un trozo envuelto (lo demás se queda donde estaba)
			local taken = Kit.strike(ctx, food, cap)
			task.delay(time, function()
				if ctx.player.Parent then
					ctx.fx("weaver2_land", { at = hill + Vector3.new(0, 4, 0), amount = taken })
				end
			end)
		end
	end
	return true
end

local function web(ctx): boolean
	local follow = ctx.has("webFollow")
	local duration = ctx.param("weaver3", "duration")
	local radius = ctx.param("weaver3", "radius")
	local token = {}
	ctx.state.web = {
		token = token,
		center = if follow then ctx.origin else ctx.aim,
		radius = radius,
		untilT = now() + duration,
		follow = follow,
		share = ctx.param("weaver3", "sharePct") / 100,
		max = math.floor(ctx.param("weaver3", "maxSpread")),
	}
	ctx.fx("weaver3", {
		center = if follow then ctx.origin else ctx.aim,
		radius = radius,
		duration = duration,
		follow = follow,
		speed = ctx.param("weaver3", "speed"),
		origin = ctx.origin,
	})
	Kit.after(ctx, duration, function()
		if ctx.state.web and ctx.state.web.token == token then
			ctx.state.web = nil
		end
	end)
	return true
end

---------------------------------------------------------------------------------------------------

return {
	passive = {
		equip = function(ctx)
			ctx.state.ties = {}
		end,
		unequip = function(ctx)
			untieAll(ctx)
		end,
		bite = function(ctx, food: Model, position: Vector3, damage: number, finished: boolean)
			local share = ctx.param("hilo", "sharePct") / 100
			local others = tiedFoods(ctx, food)

			-- Las atadas pierden su parte del mordisco (a la carga)
			local points, amounts = {}, {}
			local bites = damage * share / math.max(ctx.bite, 1)
			for _, other in others do
				local at = Kit.posOf(other)
				local taken = Kit.nibble(ctx, other, bites)
				if taken > 0 then
					table.insert(points, at)
					table.insert(amounts, taken)
				end
			end
			if #points > 0 then
				Kit.flush(ctx)
			end

			-- Nudo final: al acabar una comida, los hilos de las demás se rompen de golpe
			local snapPoints, snapAmounts = {}, {}
			if finished and ctx.has("threadSnap") then
				for _, other in tiedFoods(ctx, food) do
					local at = Kit.posOf(other)
					local taken = Kit.strike(ctx, other, 3)
					if taken > 0 then
						table.insert(snapPoints, at)
						table.insert(snapAmounts, taken)
					end
					untie(ctx, other)
				end
			end

			if finished then
				untie(ctx, food)
			else
				tie(ctx, food, ctx.param("hilo", "life"), true)
			end

			if #points > 0 or #snapPoints > 0 then
				ctx.fx("passive", {
					from = position,
					points = points,
					amounts = amounts,
					snap = snapPoints,
					snapAmounts = snapAmounts,
				})
			end

			webSpread(ctx, if finished then nil else food, position, damage)
		end,
		tick = function(ctx, dt: number)
			local ties = ctx.state.ties
			if not ties then
				return
			end
			local t = now()
			for food, entry in ties do
				if entry.untilT <= t or not FoodService.isFood(food) then
					untie(ctx, food)
				end
			end
			-- Hilos que tiran: las atadas se arrastran despacio hacia ti
			if ctx.has("threadPull") then
				local root = rootOf(ctx)
				if not root then
					return
				end
				local step = ctx.param("hilo", "pull") * math.max(dt, 0.25)
				for food in ties do
					if gliding[food] or not movable(food) then
						continue
					end
					local pos = food:GetPivot().Position
					local gap = (root.Position - pos) * FLAT
					local room = gap.Magnitude - ((food:GetAttribute("Radius") :: number?) or 1) - 4
					if room > 0.2 then
						glide(food, pos + gap.Unit * math.min(step, room), 0.22)
					end
				end
			end
		end,
	},
	abilities = {
		weaver1 = net,
		weaver2 = cocoon,
		weaver3 = web,
	},
}
