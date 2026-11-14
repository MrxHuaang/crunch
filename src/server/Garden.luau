-- El jardín (zona 1) cuando hay mucha gente:
--   * más comida cuanta más gente y más obreras sin rastro haya (Config.Garden: escala acotada);
--   * las obreras sin rastro no van a la comida de al lado de los hormigueros ajenos ni a la que
--     alguien está mordiendo, y todas las colonias juntas se llevan como mucho una parte de lo que
--     rebrota el jardín, repartida a partes iguales (la que no cabe espera: es la señal de marcar
--     rastros a comida más grande, y la hormiga lo dice);
--   * junto al hormiguero de quien va por la capa 1-2 nunca falta comida.
-- Además, sucesos pequeños cada 2-3 minutos (mariposa con regalo, hora feliz, pan gigante) y los
-- juguetes del jardín (setas saltarinas y dientes de león; los anima src/client/Garden.luau).
--
-- Remoto "Garden" (servidor -> todos): "Butterfly" (id, desde, hasta, segundos de vuelo, aterriza a
-- la hora del servidor), "GiftTaken" (id, UserId, comida, sorpresa "speed"/"jelly"/nil), "GiftGone" (id),
-- "Happy" (hasta), "Loaf" (comida, posición), "LoafGone" (posición, comido).
-- Atributos: Workspace "HappyUntil"; jugadora "GiftSpeedUntil" (hora del servidor); comida "Event".
-- Modelo Workspace.GardenToys: "Mushroom" (atributos Radius, Top) y "Dandelion" (Top).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Colony = require(script.Parent.Colony)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local Profiles = require(script.Parent.Profiles)

local Garden = {}

local G = Config.Garden
local FLAT = Vector3.new(1, 0, 1)
local GROUND = Config.GroundY
local RADIUS = Config.Map.LobbyRadius
local BITE_TIME = 3 -- el mismo de Colony: una colonia tarda como poco esto en acabar una comida
local GIFT_DROP = 1 -- segundos que tarda el regalo en caer de la mariposa al suelo

local rng = Random.new()
local remote: RemoteEvent

local scale, speed = 1, 1 -- escala del jardín y de lo rápido que rebrota
local alive: { [string]: number } = {} -- [idComida] = ejemplares del jardín (sin los de eventos)
local hillPos: { [any]: Vector3 } = {} -- [profile] = centro de su hormiguero
local lastBitten: { [Model]: number } = {} -- [comida] = os.clock del último mordisco a mano

-- Reparto entre colonias
local demand: { [any]: { rate: number, at: number } } = {}
local alloc: { [any]: number } = {}
local allocAt = 0
local capHungry: { [any]: number } = {} -- [profile] = desde cuándo le toca menos de la mitad
local emptySince: { [any]: number } = {} -- [profile] = desde cuándo sus obreras no tienen adónde ir
local nudgedAt: { [any]: number } = {}

-- Sucesos
local happyUntil = 0
local loaf: Model? = nil
local loafPos = Vector3.zero
local loafEnd = 0
local gifts: { [number]: { from: Vector3, pos: Vector3, fly: number, landAt: number, dieAt: number } } = {}
local giftId = 0
local lastHappening = -math.huge
local nextAt = 0
local order = { "gift", "happy", "loaf" }
local orderIndex = 0
local seen: { [any]: boolean } = {}
local welcome: { [any]: { at: number, joined: number } } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function gardenDefs()
	local list = {}
	for _, def in Config.Foods do
		if def.zone == 1 and not def.boss then
			table.insert(list, def)
		end
	end
	return list
end
local GARDEN = gardenDefs()

local function target(def): number
	return math.floor(def.count * scale + 0.5)
end

---------------------------------------------------------------------------------------------------
-- Cuánta comida: escala según la gente y las obreras que comen en el jardín

local function updateScale()
	local players, workers = 0, 0
	for _, profile in Profiles.all() do
		players += 1
		local hill = profile.hill
		if hill then
			hillPos[profile] = hill:GetPivot().Position
			if hill:GetAttribute("Auto") ~= false then
				workers += profile.data.workers
			end
		end
	end
	for profile in hillPos do
		if Profiles.get(profile.player) ~= profile or not profile.hill then
			hillPos[profile] = nil
		end
	end
	local s = 1 + G.PlayerStep * math.max(players - 1, 0) + G.WorkerStep * math.log10(1 + workers / G.WorkerRef)
	scale = math.clamp(s, 1, G.MaxScale)
	speed = math.min(scale, G.RespawnMax)
end

local function countAlive()
	table.clear(alive)
	for food in FoodService.list() do
		if food:GetAttribute("Event") == nil then
			local id = food:GetAttribute("FoodId")
			if id then
				alive[id] = (alive[id] or 0) + 1
			end
		end
	end
end

-- Lo que vuelve: si el jardín ya tiene su objetivo de esa comida, no vuelve (así baja solo al irse gente)
local function respawnDelay(def): number?
	if def.zone ~= 1 or def.boss then
		return def.respawn
	end
	alive[def.id] = math.max((alive[def.id] or 1) - 1, 0) -- la que se acaba de terminar
	if alive[def.id] + FoodService.pending(def.id) >= target(def) then
		return nil
	end
	return def.respawn / speed
end

-- Sube hasta el objetivo poco a poco (unas pocas por tick para no dar tirones)
local function topUpGarden()
	local budget = 4
	for _, def in GARDEN do
		local missing = target(def) - (alive[def.id] or 0) - FoodService.pending(def.id)
		while missing > 0 and budget > 0 do
			if FoodService.spawn(def) then
				alive[def.id] = (alive[def.id] or 0) + 1
			end
			missing -= 1
			budget -= 1
		end
	end
end

-- Un sitio libre a 36..Near studs de un hormiguero, dentro del jardín
local function nearSpot(center: Vector3, taken: { Vector3 }): Vector3?
	for _ = 1, 24 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(36, G.Near - 4)
		local spot = Vector3.new(center.X + math.cos(angle) * r, GROUND, center.Z + math.sin(angle) * r)
		if (spot * FLAT).Magnitude < RADIUS - 12 and FoodService.spotOk(spot) then
			local clear = true
			for _, other in taken do
				if ((other - spot) * FLAT).Magnitude < 3.5 then
					clear = false
					break
				end
			end
			if clear then
				return spot
			end
		end
	end
	return nil
end

-- Quien empieza siempre tiene comida a mano: si alrededor de su hormiguero queda poca, sale más
local function topUpNewcomers()
	local crumb, seed = GARDEN[1], GARDEN[2]
	for profile, center in hillPos do
		if profile.data.depth > G.NewcomerDepth then
			continue
		end
		local near = 0
		local taken = {}
		for food in FoodService.list() do
			if food:GetAttribute("Event") ~= nil then
				continue
			end
			local def = FoodService.defOf(food)
			if def and def.zone == 1 then
				local position = food:GetPivot().Position
				local distance = ((position - center) * FLAT).Magnitude
				if distance <= G.Near + 4 then
					table.insert(taken, position)
					if distance <= G.Near then
						near += 1
					end
				end
			end
		end
		if near < G.NearMin then
			for i = 1, G.NearFill - near do
				local spot = nearSpot(center, taken)
				if not spot then
					break
				end
				local def = if i % 3 == 0 and seed then seed else crumb
				if FoodService.spawn(def, { spot = spot }) then
					alive[def.id] = (alive[def.id] or 0) + 1
				end
				table.insert(taken, spot)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Obreras: adónde pueden ir solas y cuánto se llevan

local function autoAllowed(profile, food: Model): boolean
	if food:GetAttribute("Event") ~= nil then
		return false
	end
	local bitten = lastBitten[food]
	if bitten and os.clock() - bitten < G.BittenGrace then
		return false
	end
	local position = food:GetPivot().Position
	for other, center in hillPos do
		if other ~= profile and ((center - position) * FLAT).Magnitude < G.Near then
			return false
		end
	end
	return true
end

-- Vida por segundo que rebrota el jardín con su objetivo de ahora
local function supply(): number
	local total = 0
	for _, def in GARDEN do
		total += target(def) * def.hp / (def.respawn / speed + BITE_TIME)
	end
	return total
end

-- Reparto justo: de menor a mayor demanda, cada colonia se lleva lo que pide o su parte igual de lo
-- que queda (lo que una no usa pasa a las demás)
local function reallocate(now: number)
	allocAt = now
	table.clear(alloc)
	local list = {}
	for profile, entry in demand do
		if now - entry.at > 2 or Profiles.get(profile.player) ~= profile then
			demand[profile] = nil
		else
			table.insert(list, { profile = profile, rate = entry.rate })
		end
	end
	table.sort(list, function(a, b)
		return a.rate < b.rate
	end)
	local left = G.DrainShare * supply()
	for i, item in list do
		local give = math.min(item.rate, left / (#list - i + 1))
		alloc[item.profile] = give
		left -= give
	end
end

local function gardenLimit(profile, wanted: number, dt: number): number
	local now = os.clock()
	demand[profile] = { rate = wanted / math.max(dt, 1e-3), at = now }
	if alloc[profile] == nil or now - allocAt > 0.25 then
		reallocate(now)
	end
	local allowed = math.min(wanted, (alloc[profile] or 0) * dt)
	if allowed < wanted * 0.5 then
		capHungry[profile] = capHungry[profile] or now
	else
		capHungry[profile] = nil
	end
	return allowed
end

local function nudgeText(profile): string
	local data = profile.data
	if data.depth <= 1 then
		return "Mis obreras no caben en el jardín. Excava la capa 2 y llévalas más lejos con un rastro"
	elseif (data.nodes.trail or 0) <= 0 then
		return "Mis obreras no caben en el jardín. Compra Rastro en el hormiguero y llévalas a comida más grande"
	end
	return "Mis obreras no caben en el jardín. Márcales un rastro a comida más grande"
end

-- Colonias paradas en el jardín: la hormiga avisa (como mucho cada 3 minutos)
local function checkHungry(now: number)
	for profile in pairs(capHungry) do
		if Profiles.get(profile.player) ~= profile then
			capHungry[profile] = nil
		end
	end
	for profile in pairs(emptySince) do
		if Profiles.get(profile.player) ~= profile then
			emptySince[profile] = nil
			nudgedAt[profile] = nil
		end
	end
	for _, profile in Profiles.all() do
		local hill = profile.hill
		local idle = hill ~= nil
			and profile.data.workers > 0
			and hill:GetAttribute("Auto") ~= false
			and hill:GetAttribute("TrailPos1") == nil
			and hill:GetAttribute("TrailPos2") == nil
			and hill:GetAttribute("TrailPos3") == nil
		if idle then
			emptySince[profile] = emptySince[profile] or now
		else
			emptySince[profile] = nil
		end
		local since = math.min(capHungry[profile] or math.huge, emptySince[profile] or math.huge)
		if now - since > 15 and now - (nudgedAt[profile] or -math.huge) > 180 then
			nudgedAt[profile] = now
			Profiles.say(profile, nudgeText(profile), 6)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Valor: hora feliz y pan gigante

local function valueHook(food: Model, def, stats, value: number): number
	if food:GetAttribute("Event") == "Loaf" then
		-- El pan vale como la primera comida de tu capa más honda: igual de rico para todas
		local zone = math.clamp(stats.depth or 1, 1, #Config.Zones)
		local first = Config.Foods[(zone - 1) * 3 + 1] or def
		return first.value * (stats.zoneMult[zone] or 1) * G.Loaf.ValueMult
	end
	if def.zone == 1 and serverNow() < happyUntil then
		return value * G.Happy.Mult
	end
	return value
end

---------------------------------------------------------------------------------------------------
-- Sucesos pequeños

-- Un punto libre del jardín: cerca de un hormiguero (center) o en cualquier sitio
local function gardenSpot(center: Vector3?, maxRadius: number?, margin: number?): Vector3
	for _ = 1, 40 do
		local spot
		if center then
			local angle, r = rng:NextNumber(0, math.pi * 2), rng:NextNumber(38, 56)
			spot = Vector3.new(center.X + math.cos(angle) * r, GROUND, center.Z + math.sin(angle) * r)
		else
			local angle = rng:NextNumber(0, math.pi * 2)
			local r = math.sqrt(rng:NextNumber()) * (maxRadius or (RADIUS - 25))
			spot = Vector3.new(math.cos(angle) * r, GROUND, math.sin(angle) * r)
		end
		local ok = (spot * FLAT).Magnitude < RADIUS - 15 and FoodService.spotOk(spot)
		if ok and margin then
			for _, circle in FoodService.keepOut do
				if ((circle.pos - spot) * FLAT).Magnitude < circle.radius + margin then
					ok = false
					break
				end
			end
		end
		if ok then
			return spot
		end
	end
	return Vector3.new(0, GROUND, 0)
end

local function startGift(center: Vector3?)
	giftId += 1
	local to = gardenSpot(center)
	local angle = rng:NextNumber(0, math.pi * 2)
	local from = Vector3.new(math.cos(angle) * (RADIUS + 25), GROUND + 34, math.sin(angle) * (RADIUS + 25))
	local fly = math.clamp(((to - from) * FLAT).Magnitude / 26, 4, 9)
	local landAt = serverNow() + fly + GIFT_DROP
	gifts[giftId] = { from = from, pos = to, fly = fly, landAt = landAt, dieAt = landAt + G.Gift.Life }
	remote:FireAllClients("Butterfly", giftId, from, to, fly, landAt)
end

local function awardGift(profile, id: number)
	gifts[id] = nil
	local stats, data = profile.stats, profile.data
	local zoneFood = Config.Foods[(stats.depth - 1) * 3 + 1] or Config.Foods[1]
	-- A tu nivel: lo que trae tu colonia en Seconds s o FloorBites mordiscos tuyos (lo que sea más)
	local raw = math.max(
		data.rate * G.Gift.Seconds / math.max(stats.foodMult, 1e-3),
		G.Gift.FloorBites * stats.biteDamage * zoneFood.value
	)
	local credited = Profiles.addFood(profile, raw)
	local surprise = nil
	if data.rebirths > 0 and rng:NextNumber() < G.Gift.JellyChance then
		data.jelly += 1
		surprise = "jelly"
	elseif rng:NextNumber() < G.Gift.SpeedChance then
		profile.player:SetAttribute("GiftSpeedUntil", serverNow() + G.Gift.SpeedTime)
		surprise = "speed"
	end
	Profiles.push(profile)
	remote:FireAllClients("GiftTaken", id, profile.player.UserId, credited, surprise)
end

local function updateGifts()
	local now = serverNow()
	for id, gift in gifts do
		if now >= gift.dieAt then
			gifts[id] = nil
			remote:FireAllClients("GiftGone", id)
		elseif now >= gift.landAt then
			-- La primera que llega: la más cercana de las que están encima
			local best, bestDistance = nil, G.Gift.Reach
			for player, profile in Profiles.all() do
				local root = rootOf(player)
				if root and profile.stats and math.abs(root.Position.Y - gift.pos.Y) < 10 then
					local distance = ((root.Position - gift.pos) * FLAT).Magnitude
					if distance <= bestDistance then
						best = profile
						bestDistance = distance
					end
				end
			end
			if best then
				awardGift(best, id)
			end
		end
	end
end

local function startHappy()
	happyUntil = serverNow() + G.Happy.Duration
	Workspace:SetAttribute("HappyUntil", happyUntil)
	remote:FireAllClients("Happy", happyUntil)
end

local function startLoaf(): boolean
	if loaf and FoodService.isFood(loaf) then
		return false
	end
	local def = Config.FoodById.Miga
	if not def then
		return false
	end
	local spot = gardenSpot(nil, 80, 10)
	local model = FoodService.spawn(def, { spot = spot, plain = true, noRespawn = true })
	if not model then
		return false
	end
	model:SetAttribute("Event", "Loaf")
	model:SetAttribute("Giant", 0) -- la comida gigante (Extras) no lo hace crecer más
	local k = G.Loaf.Scale
	pcall(function()
		model:ScaleTo(model:GetScale() * k)
	end)
	model:SetAttribute("Radius", ((model:GetAttribute("Radius") :: number?) or 1) * k)
	local hp = G.Loaf.BaseHp
	for _, profile in Profiles.all() do
		if profile.stats then
			hp += profile.stats.capacity * G.Loaf.LoadsPerPlayer
		end
	end
	hp = math.floor(hp)
	model:SetAttribute("MaxHp", hp)
	model:SetAttribute("Hp", hp)
	loaf = model
	loafPos = spot
	loafEnd = os.clock() + G.Loaf.Life
	remote:FireAllClients("Loaf", model, spot)

	-- Cae del cielo en menos de un segundo
	local resting = model:GetPivot()
	task.spawn(function()
		for i = 8, 1, -1 do
			if not model.Parent then
				return
			end
			model:PivotTo(resting + Vector3.new(0, (i / 8) ^ 2 * 40, 0))
			task.wait(0.08)
		end
		if model.Parent then
			model:PivotTo(resting)
		end
	end)
	return true
end

local function updateLoaf()
	if not loaf then
		return
	end
	if not FoodService.isFood(loaf) then
		loaf = nil
		remote:FireAllClients("LoafGone", loafPos, true)
	elseif os.clock() > loafEnd then
		FoodService.remove(loaf)
		loaf = nil
		remote:FireAllClients("LoafGone", loafPos, false)
	end
end

local function runHappening(kind: string, center: Vector3?)
	lastHappening = os.clock()
	if kind == "gift" then
		startGift(center)
	elseif kind == "happy" then
		startHappy()
	elseif not startLoaf() then
		startGift(center)
	end
end

local function shuffle()
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
end

-- Quien entra por primera vez: si a los Welcome s no vio ningún suceso, le llega una mariposa cerca
local function checkWelcome(now: number)
	for _, profile in Profiles.all() do
		if seen[profile] then
			continue
		end
		seen[profile] = true
		local data = profile.data
		if data.rebirths == 0 and data.depth <= 1 and data.totalFood < 1000 then
			welcome[profile] = { at = now + G.Happen.Welcome, joined = now }
		end
	end
	for profile in pairs(seen) do
		if Profiles.get(profile.player) ~= profile then
			seen[profile] = nil
			welcome[profile] = nil
		end
	end
	for profile, entry in pairs(welcome) do
		if now >= entry.at then
			welcome[profile] = nil
			if lastHappening < entry.joined then
				runHappening("gift", hillPos[profile])
				nextAt = math.max(nextAt, now + 45)
			end
		end
	end
end

local function updateHappenings(now: number)
	checkWelcome(now)
	if now < nextAt then
		return
	end
	nextAt = now + rng:NextNumber(G.Happen.GapMin, G.Happen.GapMax)
	if next(Profiles.all()) == nil then
		return
	end
	orderIndex += 1
	if orderIndex > #order then
		orderIndex = 1
		shuffle()
	end
	runHappening(order[orderIndex])
end

---------------------------------------------------------------------------------------------------
-- Juguetes: setas saltarinas y dientes de león. El servidor solo los pone; los anima el cliente.

local MUSHROOMS = { -- radio, grados, tamaño, color del sombrero
	{ 40, 200, 1.1, Color3.fromRGB(230, 52, 56) },
	{ 45, 330, 1, Color3.fromRGB(160, 96, 230) },
	{ 70, 90, 1.15, Color3.fromRGB(230, 52, 56) },
	{ 90, 350, 1, Color3.fromRGB(62, 140, 243) },
	{ 90, 190, 1, Color3.fromRGB(255, 150, 40) },
}
local DANDELION_PATCHES = { Vector3.new(-55, 0, 40), Vector3.new(55, 0, 40) }

local function piece(parent: Instance, name: string, size: Vector3, color: Color3, cframe: CFrame, sphere: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.CFrame = cframe
	if sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function buildMushroom(parent: Instance, base: Vector3, s: number, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Mushroom"
	local stalkH = 1.2 * s
	local stalk = piece(model, "Stalk", Vector3.new(stalkH, 2.2 * s, 2.2 * s), Color3.fromRGB(255, 240, 214), CFrame.new(base + Vector3.new(0, stalkH / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2))
	stalk.Shape = Enum.PartType.Cylinder
	local capR, capH = 3.5 * s, 1.3 * s
	local capCenter = base + Vector3.new(0, stalkH + capH * 0.6, 0)
	piece(model, "Cap", Vector3.new(capR * 2, capH * 2, capR * 2), color, CFrame.new(capCenter), true)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + 0.3
		local along = 0.55
		local y = capH * math.sqrt(1 - along * along)
		piece(model, "Spot", Vector3.new(1.3 * s, 0.5 * s, 1.3 * s), Color3.fromRGB(255, 255, 255), CFrame.new(capCenter + Vector3.new(math.cos(a) * capR * along, y - 0.1 * s, math.sin(a) * capR * along)), true)
	end
	piece(model, "Spot", Vector3.new(1.5 * s, 0.5 * s, 1.5 * s), Color3.fromRGB(255, 255, 255), CFrame.new(capCenter + Vector3.new(0, capH - 0.15 * s, 0)), true)
	model:SetAttribute("Radius", capR)
	model:SetAttribute("Top", stalkH + capH * 1.6)
	model.WorldPivot = CFrame.new(base)
	model.Parent = parent
	table.insert(FoodService.keepOut, { pos = base, radius = capR + 2.5 })
end

local function buildDandelion(parent: Instance, base: Vector3, height: number)
	local model = Instance.new("Model")
	model.Name = "Dandelion"
	local stem = piece(model, "Stem", Vector3.new(height, 0.3, 0.3), Color3.fromRGB(86, 170, 70), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2))
	stem.Shape = Enum.PartType.Cylinder
	local head = piece(model, "Head", Vector3.new(2.6, 2.6, 2.6), Color3.fromRGB(255, 255, 250), CFrame.new(base + Vector3.new(0, height + 0.9, 0)), true)
	head.Transparency = 0.12
	piece(model, "Heart", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(196, 214, 120), CFrame.new(base + Vector3.new(0, height + 0.9, 0)), true)
	local leaf = piece(model, "Leaf", Vector3.new(0.2, 0.6, 2.4), Color3.fromRGB(70, 160, 66), CFrame.new(base + Vector3.new(0.6, 0.3, 0)) * CFrame.Angles(0, 0.6, 0.5))
	leaf.CastShadow = false
	model:SetAttribute("Top", height + 0.9)
	model.WorldPivot = CFrame.new(base)
	model.Parent = parent
end

local function buildToys()
	local toys = Instance.new("Model")
	toys.Name = "GardenToys"
	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(20, 16, 16)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = toys
	for _, spec in MUSHROOMS do
		local a = math.rad(spec[2])
		buildMushroom(toys, Vector3.new(math.cos(a) * spec[1], GROUND, math.sin(a) * spec[1]), spec[3], spec[4])
	end
	for _, center in DANDELION_PATCHES do
		local c = Vector3.new(center.X, GROUND, center.Z)
		buildDandelion(toys, c, 6)
		buildDandelion(toys, c + Vector3.new(2.8, 0, 1.4), 7.5)
		buildDandelion(toys, c + Vector3.new(-2.2, 0, 2.4), 5)
		table.insert(FoodService.keepOut, { pos = c, radius = 7 })
	end
	toys.Parent = Workspace
end

---------------------------------------------------------------------------------------------------

function Garden.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Garden"
	remote.Parent = remotes

	local ok, err = pcall(buildToys)
	if not ok then
		warn("[CRUNCH!] Garden: juguetes", err)
	end

	FoodService.respawnDelay = respawnDelay
	FoodService.valueHook = valueHook
	Colony.autoAllowed = autoAllowed
	Colony.gardenLimit = gardenLimit
	Events.on("Bite", function(_profile, food)
		lastBitten[food] = os.clock()
	end)

	-- Quien entra a mitad de un regalo también lo ve
	Players.PlayerAdded:Connect(function(player)
		task.delay(3, function()
			for id, gift in gifts do
				if player.Parent then
					remote:FireClient(player, "Butterfly", id, gift.from, gift.pos, gift.fly, gift.landAt)
				end
			end
		end)
	end)

	shuffle()
	nextAt = os.clock() + G.Happen.First

	-- Comida y reparto (cada medio segundo; arranca cuando FoodService ya sembró el jardín)
	task.spawn(function()
		task.wait(3)
		local beat = 0
		while true do
			local okTick, errTick = pcall(function()
				local now = os.clock()
				updateScale()
				countAlive()
				topUpGarden()
				topUpNewcomers()
				updateLoaf()
				updateHappenings(now)
				beat += 1
				if beat % 2 == 0 then
					checkHungry(now)
				end
				if beat % 10 == 0 then
					for food, at in lastBitten do
						if now - at > G.BittenGrace or not FoodService.isFood(food) then
							lastBitten[food] = nil
						end
					end
				end
			end)
			if not okTick then
				warn("[CRUNCH!] Garden:", errTick)
			end
			task.wait(0.5)
		end
	end)

	-- Regalos: quién llega primero
	task.spawn(function()
		while true do
			task.wait(0.2)
			local okTick, errTick = pcall(updateGifts)
			if not okTick then
				warn("[CRUNCH!] Garden regalos:", errTick)
			end
		end
	end)
end

return Garden
