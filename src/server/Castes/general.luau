-- Comandante (servidor): el estandarte que hace trabajar más a las obreras cercanas, la orden de
-- asalto, la Falange de soldados y la Marabunta. Definición en shared/Castes/general; efectos en
-- client/Castes/general.
--
-- Las obreras son un número que simula Colony; esta casta les habla con dos ganchos de Colony:
--   Colony.forced(profile) -> (comida, obreras): la comida asaltada ocupa el primer rastro un rato.
--   Colony.boost(profile, comida) -> (trabajo, valor): estandarte, corneta y botín x2.
-- Sin ninguna Comandante conectada los ganchos devuelven lo neutro (nil / 1, 1).

local Players = game:GetService("Players")

local Kit = require(script.Parent.Parent.CasteKit)
local Colony = require(script.Parent.Parent.Colony)
local FoodService = require(script.Parent.Parent.FoodService)

local FLAT = Vector3.new(1, 0, 1)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- [jugadora] = { radius, mult, hornUntil } mientras lleva la casta
local banners: { [Player]: any } = {}
-- [jugadora] = { food, untilT, crew, worth, chain, jumps, ctx }
local orders: { [Player]: any } = {}

---------------------------------------------------------------------------------------------------
-- Ganchos de Colony (encadenan a quien los hubiera puesto antes)
---------------------------------------------------------------------------------------------------

local prevForced = Colony.forced
local prevBoost = Colony.boost

local function orderFood(profile): (Model?, number?)
	local order = orders[profile.player]
	if not order then
		return nil, nil
	end
	local t = now()
	if t > order.untilT then
		orders[profile.player] = nil
		return nil, nil
	end
	if not FoodService.isFood(order.food) then
		-- Botín de guerra: la orden salta a la comida más cercana y dura un poco más
		if order.chain and order.jumps < 3 then
			local last = order.lastPos
			local nextFood = Kit.nearest(profile.stats, last, 40)
			if nextFood then
				order.jumps += 1
				order.food = nextFood
				order.lastPos = Kit.posOf(nextFood)
				order.untilT = math.max(order.untilT, t) + order.chainTime
				order.ctx.fx("general1_jump", { from = last, to = order.lastPos, duration = order.untilT - t })
				return nextFood, order.crew
			end
		end
		orders[profile.player] = nil
		return nil, nil
	end
	order.lastPos = Kit.posOf(order.food)
	return order.food, order.crew
end

Colony.forced = function(profile): (Model?, number?)
	local food, crew = orderFood(profile)
	if food then
		return food, crew
	end
	if prevForced then
		return prevForced(profile)
	end
	return nil, nil
end

Colony.boost = function(profile, food: Model): (number, number)
	local work, worth = 1, 1
	if prevBoost then
		work, worth = prevBoost(profile, food)
	end
	local player = profile.player
	local banner = banners[player]
	if banner then
		local root = rootOf(player)
		if root then
			local gap = ((food:GetPivot().Position - root.Position) * FLAT).Magnitude
			if gap <= banner.radius then
				work *= banner.mult
			end
		end
		if now() < banner.hornUntil then
			work *= 2
		end
	end
	local order = orders[player]
	if order and order.food == food and now() <= order.untilT then
		worth *= order.worth
	end
	return work, worth
end

Players.PlayerRemoving:Connect(function(player)
	banners[player] = nil
	orders[player] = nil
end)

---------------------------------------------------------------------------------------------------

local function syncBanner(ctx)
	local banner = banners[ctx.player]
	if not banner then
		banner = { hornUntil = 0 }
		banners[ctx.player] = banner
	end
	banner.radius = ctx.param("estandarte", "radius")
	banner.mult = ctx.param("estandarte", "mult")
	if ctx.player:GetAttribute("GeneralRadius") ~= banner.radius then
		ctx.player:SetAttribute("GeneralRadius", banner.radius)
	end
end

-- Corneta (mutación): cada habilidad hace que toda la colonia trabaje x2 un rato
local function horn(ctx)
	if not ctx.has("hornRally") then
		return
	end
	syncBanner(ctx)
	banners[ctx.player].hornUntil = now() + 4
	ctx.fx("general_horn", { at = ctx.origin, hill = ctx.hill, duration = 4 })
end

---------------------------------------------------------------------------------------------------
-- ¡A por esa!
---------------------------------------------------------------------------------------------------

local function charge(ctx): boolean
	local food = ctx.aimFood or Kit.nearest(ctx.stats, ctx.aim, 10)
	if not food then
		return false
	end
	local def = FoodService.defOf(food)
	local workers = ctx.profile.data.workers or 0
	if workers <= 0 then
		ctx.fx("general1_none", { at = Kit.posOf(food) })
		return false
	end
	if def and def.boss then
		return false -- la tarta no se asalta (Colony tampoco deja marcarla)
	end
	local duration = ctx.param("general1", "duration")
	local crew = if ctx.has("rushAll") then workers else math.min(workers, ctx.param("general1", "crew"))
	local at = Kit.posOf(food)
	orders[ctx.player] = {
		food = food,
		untilT = now() + duration,
		crew = crew,
		worth = ctx.param("general1", "worth"),
		chain = ctx.has("rushChain"),
		chainTime = ctx.param("general1", "chain"),
		jumps = 0,
		lastPos = at,
		ctx = ctx,
	}
	ctx.fx("general1", {
		at = at,
		radius = (food:GetAttribute("Radius") :: number?) or 2,
		hill = ctx.hill,
		duration = duration,
		crew = math.min(crew, 40),
		all = ctx.has("rushAll"),
	})
	-- Pulso cada segundo: el botín que sale de la asaltada vuela a casa
	local order = orders[ctx.player]
	Kit.every(ctx, 1, duration + 3 * ctx.param("general1", "chain"), function(_n: number)
		if orders[ctx.player] ~= order or now() > order.untilT then
			return
		end
		if FoodService.isFood(order.food) then
			ctx.fx("general1_tick", { at = Kit.posOf(order.food) })
		end
	end)
	horn(ctx)
	return true
end

---------------------------------------------------------------------------------------------------
-- Falange
---------------------------------------------------------------------------------------------------

-- Sitio de cada soldado respecto a la Comandante (la misma cuenta que el cliente): V detrás de ti,
-- o un anillo a tu alrededor con la Tortuga.
local function slotOf(root: CFrame, i: number, count: number, ring: boolean): Vector3
	if ring then
		local angle = (i - 1) / count * math.pi * 2
		return (root * CFrame.new(math.cos(angle) * 5.5, 0, math.sin(angle) * 5.5)).Position
	end
	local row = math.ceil(i / 2)
	local side = if i % 2 == 0 then 1 else -1
	return (root * CFrame.new(side * row * 2.8, 0, 2 + row * 2.6)).Position
end

local function phalanx(ctx): boolean
	local count = math.floor(ctx.param("general2", "soldiers"))
	local duration = ctx.param("general2", "duration")
	local ring = ctx.has("phalanxRing")
	local lance = ctx.has("phalanxLance")
	local token = {}
	ctx.state.phalanx = {
		token = token,
		untilT = now() + duration,
		count = count,
		share = ctx.param("general2", "sharePct") / 100,
		reach = ctx.param("general2", "reach"),
		ring = ring,
		lance = lance,
	}
	ctx.fx("general2", { count = count, duration = duration, ring = ring, lance = lance })
	if lance then
		-- Lanceros: atacan solos a su ritmo, cada uno a la comida más cercana a su sitio
		local share = ctx.param("general2", "sharePct") / 100
		local reach = ctx.param("general2", "reach")
		Kit.every(ctx, ctx.param("general2", "every"), duration, function(_n: number)
			local root = rootOf(ctx.player)
			if not root then
				return
			end
			local skip = {}
			local points, amounts, who = {}, {}, {}
			for i = 1, count do
				local spot = slotOf(root.CFrame, i, count, false)
				local food = Kit.nearest(ctx.stats, spot, reach, skip) or Kit.nearest(ctx.stats, spot, reach)
				if food then
					skip[food] = true
					local at = Kit.posOf(food)
					local taken = Kit.strike(ctx, food, share)
					if taken > 0 then
						table.insert(points, at)
						table.insert(amounts, taken)
						table.insert(who, i)
					end
				end
			end
			if #points > 0 then
				ctx.fx("general2_hit", { points = points, amounts = amounts, who = who })
			end
		end)
	end
	Kit.after(ctx, duration, function()
		if ctx.state.phalanx and ctx.state.phalanx.token == token then
			ctx.state.phalanx = nil
		end
	end)
	horn(ctx)
	return true
end

local function phalanxBite(ctx, food: Model, position: Vector3, damage: number, finished: boolean)
	local p = ctx.state.phalanx
	if not p or p.lance or now() > p.untilT then
		return
	end
	local root = rootOf(ctx.player)
	if not root then
		return
	end
	local bites = damage * p.share / math.max(ctx.bite, 1)
	local skip = {}
	local points, amounts, who = {}, {}, {}
	for i = 1, p.count do
		local target: Model?
		if p.ring then
			-- Tortuga: todas a la misma que tú
			target = if not finished and FoodService.isFood(food) then food else Kit.nearest(ctx.stats, position, p.reach)
		else
			local spot = slotOf(root.CFrame, i, p.count, false)
			target = Kit.nearest(ctx.stats, spot, p.reach, skip) or Kit.nearest(ctx.stats, spot, p.reach)
		end
		if target then
			skip[target] = true
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
	end
	if #points > 0 then
		ctx.fx("general2_hit", { points = points, amounts = amounts, who = who })
	end
end

---------------------------------------------------------------------------------------------------
-- Marabunta
---------------------------------------------------------------------------------------------------

local function rotate(dir: Vector3, degrees: number): Vector3
	return (CFrame.Angles(0, math.rad(degrees), 0) * dir).Unit
end

local function marabunta(ctx): boolean
	local bites = ctx.param("general3", "bites")
	local speed = ctx.param("general3", "speed")
	local length = ctx.param("general3", "length")
	local width = ctx.param("general3", "width")
	local origin = ctx.origin
	local vortex = ctx.has("swarmVortex")
	local twin = ctx.has("swarmTwin")
	local windup = 0.35

	local plan = {}
	local seen = {}
	local function add(food: Model, at: number)
		if not seen[food] then
			seen[food] = true
			table.insert(plan, { food = food, at = windup + at })
		end
	end

	local dirs = { ctx.dir }
	local travel: number
	if vortex then
		-- Remolino: el frente gira una vuelta entera alrededor de ti en ~1.4 s
		local radius = 26
		travel = 1.4
		local base = math.atan2(ctx.dir.Z, ctx.dir.X)
		for _, food in Kit.inRadius(ctx.stats, origin, radius) do
			local gap = (food:GetPivot().Position - origin) * FLAT
			local angle = (math.atan2(gap.Z, gap.X) - base) % (math.pi * 2)
			add(food, angle / (math.pi * 2) * travel)
		end
	else
		if twin then
			dirs = { rotate(ctx.dir, 25), rotate(ctx.dir, -25) }
		end
		travel = length / speed
		for _, dir in dirs do
			for _, food in Kit.onLine(ctx.stats, origin, origin + dir * length, width) do
				local along = math.clamp(((food:GetPivot().Position - origin) * FLAT):Dot(dir), 0, length)
				add(food, along / speed)
			end
		end
	end
	table.sort(plan, function(a, b)
		return a.at < b.at
	end)

	ctx.fx("general3", {
		origin = origin,
		dirs = dirs,
		length = length,
		width = width,
		travel = travel,
		windup = windup,
		vortex = vortex,
		hill = ctx.hill,
	})

	local began = os.clock()
	local index = 1
	Kit.every(ctx, 0.1, windup + travel + 0.4, function(_n: number)
		local elapsed = os.clock() - began
		local due = {}
		while plan[index] and plan[index].at <= elapsed do
			if FoodService.isFood(plan[index].food) then
				table.insert(due, plan[index].food)
			end
			index += 1
		end
		if #due > 0 then
			local points, amounts = Kit.strikeMany(ctx, due, bites)
			if #points > 0 then
				ctx.fx("general3_hit", { points = points, amounts = amounts })
			end
		end
	end)
	horn(ctx)
	return true
end

---------------------------------------------------------------------------------------------------

return {
	passive = {
		equip = function(ctx)
			syncBanner(ctx)
		end,
		unequip = function(ctx)
			banners[ctx.player] = nil
			orders[ctx.player] = nil
			ctx.player:SetAttribute("GeneralRadius", nil)
		end,
		tick = function(ctx, _dt: number)
			syncBanner(ctx) -- por si cambió una mutación
		end,
		bite = function(ctx, food: Model, position: Vector3, damage: number, finished: boolean)
			phalanxBite(ctx, food, position, damage, finished)
		end,
	},
	abilities = {
		general1 = charge,
		general2 = phalanx,
		general3 = marabunta,
	},
}
