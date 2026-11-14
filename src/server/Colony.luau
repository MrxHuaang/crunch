-- Simulación de las obreras. En el servidor son solo un número: cada medio segundo se calcula
-- cuánta comida arrancan de cada rastro. Las hormigas que se ven las dibuja cada cliente,
-- a partir de la posición de cada destino que se publica en el hormiguero.
-- Por muchas obreras que haya, una colonia no puede con una comida en menos de BITE_TIME
-- segundos: las que no caben alrededor esperan sin hacer nada.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local Profiles = require(script.Parent.Profiles)

local Colony = {}

local TICK = 0.5
local BITE_TIME = 3 -- segundos que, como poco, tarda una colonia en terminar una comida
local AUTO_TARGETS = 3 -- comidas del jardín a la vez cuando no hay rastros
local fxRemote: RemoteEvent

local function canEat(profile, def): boolean
	local stats = profile.stats
	return def.zone <= stats.depth and (not def.hard or stats.workersBreakHard)
end

local function makeTrail(profile, food: Model)
	profile.trailOrder += 1
	return {
		food = food,
		id = food:GetAttribute("FoodId"),
		pos = food:GetPivot().Position,
		order = profile.trailOrder,
	}
end

local function isTargeted(profile, food: Model): boolean
	for _, trail in profile.trails do
		if trail.food == food then
			return true
		end
	end
	return false
end

-- Quita rastros de comida ya comida. Si queda otra igual cerca, las obreras pasan a ella.
local function cleanTrails(profile, slots: number)
	for slot = 1, 3 do
		local trail = profile.trails[slot]
		if not trail then
			continue
		end
		if slot > slots then
			profile.trails[slot] = nil
		elseif not FoodService.isFood(trail.food) then
			local nextFood = FoodService.nearest(trail.pos, 90, function(food, def)
				return def.id == trail.id and not isTargeted(profile, food)
			end)
			profile.trails[slot] = if nextFood then makeTrail(profile, nextFood) else nil
		end
	end
end

-- Rastro listo: los huecos libres van a la comida más valiosa que la colonia pueda comer.
local function fillSmart(profile, slots: number, hillPos: Vector3)
	for slot = 1, slots do
		if profile.trails[slot] then
			continue
		end
		for i = #Config.Foods, 1, -1 do
			local wanted = Config.Foods[i]
			if wanted.boss or not canEat(profile, wanted) then
				continue
			end
			local food = FoodService.nearest(hillPos, math.huge, function(candidate, def)
				return def.id == wanted.id and not isTargeted(profile, candidate)
			end)
			if food then
				profile.trails[slot] = makeTrail(profile, food)
				break
			end
		end
	end
end

-- Sin rastro, las obreras van a lo que hay en el jardín: hasta tres comidas a la vez, las de más
-- vida que queden (y entre iguales, las más cercanas). Cada hueco solo cambia de comida cuando
-- la suya se acaba, así las filas no saltan de una a otra.
-- Devuelve los huecos 1..3 (puede haber huecos vacíos si en el jardín no queda nada).
local function autoFoods(profile, hillPos: Vector3): { [number]: Model }
	local chosen = profile.autoFoods
	local function taken(food: Model): boolean
		for slot = 1, AUTO_TARGETS do
			if chosen[slot] == food then
				return true
			end
		end
		return false
	end
	for slot = 1, AUTO_TARGETS do
		local current = chosen[slot]
		if current and FoodService.isFood(current) then
			continue
		end
		local best: Model? = nil
		local bestScore = -math.huge
		for food in FoodService.list() do
			local def = FoodService.defOf(food)
			if def.zone == 1 and not def.hard and not taken(food) then
				local distance = (food:GetPivot().Position - hillPos).Magnitude
				local score = (food:GetAttribute("Hp") :: number) * 1000 - distance
				if score > bestScore then
					best = food
					bestScore = score
				end
			end
		end
		chosen[slot] = best
	end
	return chosen
end

-- targets: [hueco 1..3] = comida; un hueco vacío borra su destino
local function publish(hill: Model, targets: { [number]: Model })
	for i = 1, 3 do
		local food = targets[i]
		if food then
			hill:SetAttribute("TrailPos" .. i, food:GetPivot().Position)
			hill:SetAttribute("TrailRadius" .. i, food:GetAttribute("Radius"))
			hill:SetAttribute("TrailColor" .. i, food:GetAttribute("Color"))
		else
			hill:SetAttribute("TrailPos" .. i, nil)
		end
	end
end

local function tick(profile, dt: number)
	local hill = profile.hill
	if not hill then
		return
	end
	local data = profile.data
	local stats = profile.stats
	local hillPos = hill:GetPivot().Position
	local slots = stats.trailSlots

	cleanTrails(profile, slots)
	if stats.smartTrail and data.workers > 0 then
		fillSmart(profile, slots, hillPos)
	end

	-- [hueco] = comida. Los rastros marcados se publican seguidos, como siempre;
	-- los automáticos conservan su hueco para que su fila no salte a otra.
	local targets: { [number]: Model } = {}
	local count = 0
	for slot = 1, slots do
		local trail = profile.trails[slot]
		if trail then
			count += 1
			targets[count] = trail.food
		end
	end

	local marked = count > 0
	hill:SetAttribute("Auto", not marked)
	if not marked and data.workers > 0 then
		for slot, food in autoFoods(profile, hillPos) do
			targets[slot] = food
			count += 1
		end
	end
	publish(hill, targets)

	local credited = 0
	local remainders = {} -- solo se guardan las de los destinos de ahora
	if data.workers > 0 and count > 0 then
		local now = Workspace:GetServerTimeNow()
		local mult = stats.colonyMult * (if now < profile.frenzyUntil then stats.frenzyMult else 1)
		if marked then
			mult *= stats.trailBonus
		end
		local share = data.workers / count

		for _, food in targets do
			local def = FoodService.defOf(food)
			if not canEat(profile, def) then
				continue
			end
			local flat = (food:GetPivot().Position - hillPos) * Vector3.new(1, 0, 1)
			local trip = (2 * flat.Magnitude / stats.workerSpeed + Config.Worker.TurnTime) * stats.tripMult
			-- Tope por comida: lo que no cabe se pierde (esas obreras esperan), no se guarda para luego
			local cap = (food:GetAttribute("MaxHp") or def.hp) * dt / BITE_TIME
			local gain = math.min(share * stats.workerCarry / trip * mult * dt, cap)
			local hp = gain + (profile.remainders[food] or 0)
			local whole = math.floor(hp)
			remainders[food] = hp - whole
			if whole > 0 then
				local taken, _, finished = FoodService.damage(food, whole)
				if taken > 0 then
					credited += Profiles.addFood(profile, taken * def.value * stats.zoneMult[def.zone])
					Profiles.trackFood(profile, def, taken)
					Events.fire("Ate", profile, def, taken, true)
				end
				if finished then
					Profiles.awardTrophy(profile, def)
					Events.fire("Finished", profile, def)
				end
			end
		end
	end
	profile.remainders = remainders

	-- Media móvil del ingreso: es lo que rinde la colonia cuando no estás
	data.rate = data.rate * 0.95 + (credited / dt) * 0.05

	-- La reina cría sola, gastando como mucho una décima de lo que tienes por obrera
	if stats.queen then
		for _ = 1, 5 do
			local cost = Stats.workerCost(data.workers, stats.workerDiscount)
			if data.workers >= stats.workerCap or cost > data.food * 0.1 then
				break
			end
			data.food -= cost
			data.workers += 1
		end
	end

	Profiles.push(profile)
end

local function onTrail(player: Player, food: any)
	local profile = Profiles.get(player)
	if not profile or not FoodService.isFood(food) then
		return
	end
	local slots = profile.stats.trailSlots
	if slots <= 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local flat = (food:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude - (food:GetAttribute("Radius") :: number) > profile.stats.biteRange + 8 then
		return
	end

	-- Marcar otra vez la misma comida quita el rastro
	for slot = 1, slots do
		local trail = profile.trails[slot]
		if trail and trail.food == food then
			profile.trails[slot] = nil
			fxRemote:FireClient(player, "Trail", food:GetPivot().Position, false)
			return
		end
	end

	local def = FoodService.defOf(food)
	if def.zone > profile.stats.depth then
		return
	end
	if def.boss then
		Profiles.say(profile, "La tarta es cosa mía. Las obreras no se atreven", 4)
		return
	end
	if def.hard and not profile.stats.workersBreakHard then
		Profiles.say(profile, "Mis obreras no pueden con eso. Hace falta el cuartel", 4)
		return
	end

	-- Usa un hueco libre; si no hay, reemplaza el rastro más viejo
	local chosen = 1
	local oldest = math.huge
	for slot = 1, slots do
		local trail = profile.trails[slot]
		if not trail then
			chosen = slot
			break
		elseif trail.order < oldest then
			oldest = trail.order
			chosen = slot
		end
	end
	profile.trails[chosen] = makeTrail(profile, food)
	fxRemote:FireClient(player, "Trail", food:GetPivot().Position, true)
end

local function onFrenzy(player: Player)
	local profile = Profiles.get(player)
	if not profile or not profile.stats.hasFrenzy then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now < profile.frenzyReadyAt then
		return
	end
	profile.frenzyUntil = now + profile.stats.frenzyDuration
	profile.frenzyReadyAt = now + profile.stats.frenzyCooldown
	Profiles.push(profile)
	fxRemote:FireClient(player, "Frenzy")
end

function Colony.clearTrails(profile)
	table.clear(profile.trails)
	table.clear(profile.remainders)
	table.clear(profile.autoFoods)
end

function Colony.start(remotes: Folder)
	fxRemote = remotes.Fx
	remotes.Trail.OnServerEvent:Connect(onTrail)
	remotes.Frenzy.OnServerEvent:Connect(onFrenzy)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, profile in Profiles.all() do
				tick(profile, dt)
			end
		end
	end)
end

return Colony
