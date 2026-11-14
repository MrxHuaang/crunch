-- Eventos para todo el servidor cada 8-12 minutos: lluvia de migas doradas y banquete gigante.
-- El servidor decide dónde y cuándo; los clientes animan caídas, rebotes y trozos a partir de eso.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local Profiles = require(script.Parent.Profiles)

local WorldEvents = {}

local FIRST = 180 -- el primero, a los 3 minutos de abrir el servidor
local WARN = 15 -- aviso previo
local GAP_MIN, GAP_MAX = 480, 720 -- entre un evento y el siguiente (de inicio a inicio)

-- Lluvia de migas doradas
local RAIN_TIME = 45
local RAIN_COUNT = 50
local RAIN_SPAWN_TIME = 40 -- caen durante los primeros 40 s; al final no queda ninguna a medio coger
local CRUMB_FALL = 1.4 -- segundos de caída desde el cielo
local CRUMB_LIFE = 20 -- segundos en el suelo antes de desaparecer
local CRUMB_REACH = 4
local CRUMB_SECONDS = 25 -- cada miga vale unos 25 s de tu colonia
local CRUMB_FLOOR = 10 -- ...o 10 mordiscos a la primera comida de tu zona, lo que sea más

-- Banquete
local FEAST_TIME = 90
local FEAST_LAND = 1 -- segundos que tarda en caer del cielo
local FEAST_RADIUS = 20
local FEAST_REACH = 8
local FEAST_BITE = 0.4
local FEAST_BASE = 220 -- bocados con un jugador; se multiplica por la raíz de los conectados
local FEAST_SECONDS = 240 -- bote de cada jugador: unos 4 minutos de su colonia
local FEAST_FLOOR = 80
local FEAST_PRIZE = 0.4 -- parte fija del bote por participar; el resto, según lo que comas
local TOP_BONUS = 0.5
local FEAST_FOODS = { "Tarta", "Sandia", "Donut", "Hamburguesa" }

local FLAT = Vector3.new(1, 0, 1)
local GROUND = Config.GroundY
local MAP = Config.Map
local BOARD = Vector3.new(-0.46 * MAP.LobbyRadius, GROUND, -0.66 * MAP.LobbyRadius)

local rng = Random.new()
local remote: RemoteEvent
local container: Model

local phase = "idle" -- "idle" | "announce" | "live"
local current = nil -- lo que se anunció o está en marcha
local crumbs: { [number]: { pos: Vector3, landAt: number } } = {}
local greeted: { [Player]: boolean } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Comida "a tu nivel": lo que gana tu colonia en `seconds`, con un suelo de mordiscos
-- a la primera comida de tu zona para quien aún no tiene obreras (misma idea que Monetize).
local function income(profile, seconds: number, floorBites: number): number
	local stats = profile.stats
	local zoneFood = Config.Foods[(stats.depth - 1) * 3 + 1] or Config.Foods[1]
	return math.max(profile.data.rate * seconds, floorBites * stats.biteDamage * zoneFood.value)
end

local function onlineCount(): number
	local count = 0
	for _ in Profiles.all() do
		count += 1
	end
	return count
end

-- Ranking corto para la línea de resultados.
local function ranking(counts: { [Player]: number }, limit: number)
	local list = {}
	for player, count in counts do
		if player.Parent then
			table.insert(list, { name = player.DisplayName, count = count })
		end
	end
	table.sort(list, function(a, b)
		return a.count > b.count
	end)
	while #list > limit do
		table.remove(list)
	end
	return list
end

------------------------------------------------------------------------------------------
-- Lluvia de migas doradas
------------------------------------------------------------------------------------------

local function rainSpot(hills: { Vector3 }): Vector3
	local radius = MAP.LobbyRadius - 14
	for _ = 1, 30 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * radius
		local spot = Vector3.new(math.cos(angle) * r, GROUND, math.sin(angle) * r)
		local clear = ((spot - BOARD) * FLAT).Magnitude > 20
		if clear then
			for _, center in hills do
				if ((center - spot) * FLAT).Magnitude < 30 then
					clear = false
					break
				end
			end
		end
		if clear then
			return spot
		end
	end
	return Vector3.new(0, GROUND, -20)
end

local function runRain(info)
	local hills = {}
	local anthills = Workspace:FindFirstChild("Anthills")
	if anthills then
		for _, hill in anthills:GetChildren() do
			if hill:IsA("Model") then
				table.insert(hills, hill:GetPivot().Position)
			end
		end
	end

	local counts: { [Player]: number } = {}
	local gains: { [Player]: number } = {}
	local every = RAIN_SPAWN_TIME / RAIN_COUNT
	local spawned = 0
	local nextSpawn = info.startAt
	local finish = info.startAt + RAIN_TIME

	while serverNow() < finish do
		local now = serverNow()

		while spawned < RAIN_COUNT and now >= nextSpawn do
			spawned += 1
			nextSpawn += every
			local pos = rainSpot(hills)
			local landAt = now + CRUMB_FALL
			crumbs[spawned] = { pos = pos, landAt = landAt }
			remote:FireAllClients("Crumb", spawned, pos, landAt)
		end

		-- Unas pocas distancias, cinco veces por segundo
		local walkers = {}
		for player, profile in Profiles.all() do
			local root = rootOf(player)
			if root then
				table.insert(walkers, { player = player, profile = profile, pos = root.Position })
			end
		end
		for id, crumb in crumbs do
			if now >= crumb.landAt + CRUMB_LIFE then
				crumbs[id] = nil
				continue
			end
			if now < crumb.landAt then
				continue
			end
			for _, walker in walkers do
				local offset = walker.pos - crumb.pos
				if (offset * FLAT).Magnitude <= CRUMB_REACH and math.abs(offset.Y) < 10 then
					crumbs[id] = nil
					local profile = walker.profile
					local credited = Profiles.addFood(profile, income(profile, CRUMB_SECONDS, CRUMB_FLOOR))
					Profiles.push(profile)
					counts[walker.player] = (counts[walker.player] or 0) + 1
					gains[walker.player] = (gains[walker.player] or 0) + credited
					remote:FireAllClients("CrumbTaken", id, walker.player.UserId, credited)
					break
				end
			end
		end
		task.wait(0.2)
	end
	table.clear(crumbs)

	local top = ranking(counts, 3)
	for _, player in Players:GetPlayers() do
		remote:FireClient(player, "End", {
			kind = "rain",
			ranking = top,
			mine = if counts[player] then { count = counts[player], gain = gains[player] } else nil,
		})
	end
end

------------------------------------------------------------------------------------------
-- Banquete
------------------------------------------------------------------------------------------

local function runFeast(info)
	local def = Config.FoodById[info.food]
	local model = FoodModels.build(def)
	model:ScaleTo(FEAST_RADIUS / (model:GetAttribute("Radius") :: number))
	model.Name = "Banquete"

	local pieces = {}
	for _, child in model:GetChildren() do
		if child:GetAttribute("Order") then
			table.insert(pieces, child)
		end
	end
	table.sort(pieces, function(a, b)
		return (a:GetAttribute("Order") :: number) < (b:GetAttribute("Order") :: number)
	end)

	local total = math.max(FEAST_BASE, math.floor(FEAST_BASE * math.sqrt(onlineCount())))
	local left = total
	local home = CFrame.new(0, GROUND, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	model:SetAttribute("Radius", FEAST_RADIUS)
	model:SetAttribute("Total", total)
	model:SetAttribute("Left", left)
	model:SetAttribute("Home", home.Position)
	-- Aparece en lo alto; los clientes lo dejan caer y aquí se coloca en su sitio al aterrizar
	model:PivotTo(home + Vector3.new(0, 90, 0))
	model.Parent = container

	task.wait(FEAST_LAND)
	model:PivotTo(home)

	local center = home.Position
	local reach = FEAST_RADIUS + FEAST_REACH
	local bites: { [Player]: number } = {}
	local finish = os.clock() + FEAST_TIME
	while left > 0 and os.clock() < finish do
		task.wait(FEAST_BITE)
		for player in Profiles.all() do
			if left <= 0 then
				break
			end
			local root = rootOf(player)
			if not root then
				continue
			end
			local offset = root.Position - center
			if (offset * FLAT).Magnitude <= reach and math.abs(offset.Y) < 40 then
				left -= 1
				bites[player] = (bites[player] or 0) + 1
				model:SetAttribute("B_" .. player.UserId, bites[player])
			end
		end
		model:SetAttribute("Left", left)
		-- Se desmonta de la última pieza a la primera, como la comida normal
		local keep = math.ceil(#pieces * left / total)
		for i = #pieces, keep + 1, -1 do
			pieces[i]:Destroy()
			pieces[i] = nil
		end
	end

	-- Reparto: premio fijo + parte según lo comido (respecto a la media). Quien más come, +50 %.
	local sum, top, people = 0, 0, 0
	for player, count in bites do
		if player.Parent and Profiles.get(player) then
			sum += count
			top = math.max(top, count)
			people += 1
		end
	end
	local gains: { [Player]: number } = {}
	if people > 0 then
		local average = sum / people
		for player, count in bites do
			local profile = Profiles.get(player)
			if not player.Parent or not profile then
				continue
			end
			local ratio = math.clamp(count / average, 0, 2)
			local gain = income(profile, FEAST_SECONDS, FEAST_FLOOR) * (FEAST_PRIZE + (1 - FEAST_PRIZE) * ratio)
			if count == top then
				gain *= 1 + TOP_BONUS
			end
			gains[player] = Profiles.addFood(profile, gain)
			Profiles.push(profile)
		end
	end

	local podium = ranking(bites, 3)
	for _, player in Players:GetPlayers() do
		remote:FireClient(player, "End", {
			kind = "feast",
			finished = left <= 0,
			ranking = podium,
			mine = if gains[player] then { count = bites[player], gain = gains[player], top = bites[player] == top } else nil,
		})
	end

	task.wait(0.4)
	model:Destroy()
end

------------------------------------------------------------------------------------------
-- Calendario
------------------------------------------------------------------------------------------

local function describe(kind: string, startAt: number)
	if kind == "rain" then
		return {
			kind = "rain",
			name = "Lluvia de migas doradas",
			startAt = startAt,
			endAt = startAt + RAIN_TIME,
			fall = CRUMB_FALL,
			life = CRUMB_LIFE,
		}
	end
	local food = FEAST_FOODS[rng:NextInteger(1, #FEAST_FOODS)]
	return {
		kind = "feast",
		name = "Banquete: " .. string.lower(Config.FoodById[food].name) .. " gigante",
		food = food,
		startAt = startAt,
		endAt = startAt + FEAST_LAND + FEAST_TIME,
		land = FEAST_LAND,
		radius = FEAST_RADIUS,
		reach = FEAST_REACH,
	}
end

local function scheduler()
	local order = { "rain", "feast" }
	local index = rng:NextInteger(1, 2)
	local nextStart = serverNow() + FIRST
	while true do
		local pause = nextStart - WARN - serverNow()
		if pause > 0 then
			task.wait(pause)
		end
		if onlineCount() == 0 then
			nextStart = serverNow() + 60 + WARN
			continue
		end

		local info = describe(order[index], serverNow() + WARN)
		index = index % #order + 1
		current = info
		phase = "announce"
		remote:FireAllClients("Announce", info)
		task.wait(math.max(0, info.startAt - serverNow()))

		phase = "live"
		remote:FireAllClients("Start", info)
		local ok, err = pcall(if info.kind == "rain" then runRain else runFeast, info)
		if not ok then
			warn("[CRUNCH!] El evento falló:", err)
			table.clear(crumbs)
			local stray = container:FindFirstChild("Banquete")
			if stray then
				stray:Destroy()
			end
			remote:FireAllClients("End", { kind = info.kind, failed = true, ranking = {} })
		end
		phase = "idle"
		current = nil
		nextStart = info.startAt + rng:NextNumber(GAP_MIN, GAP_MAX)
	end
end

-- Quien entra a mitad de un evento pide el estado una vez.
local function onHello(player: Player, kind: any)
	if kind ~= "Hello" or greeted[player] then
		return
	end
	greeted[player] = true
	if not current then
		return
	end
	if phase == "announce" then
		remote:FireClient(player, "Announce", current)
	elseif phase == "live" then
		remote:FireClient(player, "Start", current)
		for id, crumb in crumbs do
			remote:FireClient(player, "Crumb", id, crumb.pos, crumb.landAt)
		end
	end
end

function WorldEvents.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "WorldEvent"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onHello)

	container = Instance.new("Model")
	container.Name = "WorldEvents"
	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(20, 16, 16)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = container
	container.Parent = Workspace

	Players.PlayerRemoving:Connect(function(player)
		greeted[player] = nil
	end)

	task.spawn(scheduler)
end

return WorldEvents
