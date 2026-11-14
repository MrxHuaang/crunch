-- Eventos para todo el servidor cada 8-12 minutos: lluvia de migas doradas y banquete gigante
-- (con minijuego de puntería al lado de la comida).
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

-- Banquete: minijuego de puntería. El cliente informa de cada golpe (0, 1, 3 o 4 bocados)
-- y el servidor lo acota: un golpe cada 0,3 s de media, solo al alcance y con el evento vivo.
local FEAST_TIME = 90
local FEAST_LAND = 1 -- segundos que tarda en caer del cielo
local FEAST_RADIUS = 20
local FEAST_REACH = 8
local FEAST_SLACK = 4 -- margen extra al validar golpes (el lag mueve un poco a la hormiga)
local FEAST_TICK = 0.1
local FEAST_BASE = 130 -- bocados con un jugador; × conectados^0,85 (≈ 50-65 s jugando bien)
local FEAST_GROWTH = 0.85
local HIT_GAP = 0.3 -- ritmo máximo de golpes por jugador...
local HIT_BURST = 2 -- ...con un colchón de 2 para que el lag no se coma golpes buenos
local HIT_VALID = { [0] = true, [1] = true, [3] = true, [4] = true } -- fallo, bien, perfecto, perfecto con racha
local PASSIVE_EVERY = 2 -- quien está al lado sin jugar se lleva un bocado cada 2 s
local PASSIVE_IDLE = 3 -- "sin jugar": 3 s sin golpes
local FEAST_SECONDS = 240 -- bote de cada jugador: unos 4 minutos de su colonia
local FEAST_FLOOR = 80
local FEAST_PRIZE = 0.4 -- parte fija del bote por participar; el resto, según lo que comas
local FEAST_PAR = 0.75 -- referencia mínima: 3/4 de lo que tocaría a cada uno con un banquete a su medida
local RATIO_MAX = 1.6
local TOP_BONUS = 0.25 -- solo si hay más de un participante
local SMALL_PIECE = 0.2 -- pieza decorativa: menos de 1/5 del volumen medio
local FINAL = 0.999
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
local feast = nil -- banquete en marcha (solo mientras se puede comer)

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
	-- data.rate ya lleva el multiplicador de comida y addFood lo vuelve a aplicar: se quita aquí
	return math.max(profile.data.rate / math.max(stats.foodMult, 1e-3) * seconds, floorBites * stats.biteDamage * zoneFood.value)
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

local function poolFor(players: number): number
	return math.floor(FEAST_BASE * math.max(1, players) ^ FEAST_GROWTH + 0.5)
end

-- Volumen aproximado de una pieza según su forma
local function volume(part: BasePart): number
	local size = part.Size
	local v = size.X * size.Y * size.Z
	if part:IsA("WedgePart") then
		return v * 0.5
	end
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Sphere then
		return v * math.pi / 6
	end
	if part:IsA("Part") then
		if part.Shape == Enum.PartType.Ball then
			return v * math.pi / 6
		elseif part.Shape == Enum.PartType.Cylinder then
			return v * math.pi / 4
		end
	end
	return v
end

-- Distancia de un punto a la caja de una pieza (0 si está dentro)
local function boxDistance(part: BasePart, position: Vector3): number
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return Vector3.new(
		math.max(math.abs(p.X) - half.X, 0),
		math.max(math.abs(p.Y) - half.Y, 0),
		math.max(math.abs(p.Z) - half.Z, 0)
	).Magnitude
end

-- Plan de desmontaje: cada pieza cae cuando se ha comido la fracción `at` del bote.
-- Las piezas grandes, de la última a la primera (como la comida normal) y según su volumen:
-- con medio bote comido se ha ido media masa. Las decorativas se reparten por todo el banquete,
-- pero nunca sobreviven a la pieza grande en la que se apoyan. La última grande (at = 1) solo
-- cae con el último bocado.
local function bitePlan(pieces: { BasePart })
	local weights, sum = {}, 0
	for i, piece in pieces do
		weights[i] = volume(piece)
		sum += weights[i]
	end
	local average = sum / math.max(#pieces, 1)
	local big, small = {}, {}
	for i in pieces do
		table.insert(if weights[i] < average * SMALL_PIECE then small else big, i)
	end
	if #big == 0 then
		big, small = small, {}
	end

	local at = {}
	local bigSum = 0
	for _, i in big do
		bigSum += weights[i]
	end
	local cumulative = 0
	for k = #big, 1, -1 do
		cumulative += weights[big[k]]
		at[big[k]] = if bigSum > 0 then cumulative / bigSum else 1 - (k - 1) / #big
	end
	if big[1] then
		at[big[1]] = 1
	end

	for k = #small, 1, -1 do
		local i = small[k]
		local rank = #small - k + 1
		local spread = 0.04 + 0.86 * (rank - 0.5) / #small
		local host, best = nil, math.huge
		for _, j in big do
			local d = boxDistance(pieces[j], pieces[i].Position)
			if d < best then
				host, best = j, d
			end
		end
		at[i] = if host then math.min(spread, at[host]) else spread
	end

	local plan = {}
	for i, piece in pieces do
		table.insert(plan, { part = piece, at = at[i], order = i })
	end
	table.sort(plan, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.order > b.order
	end)
	return plan
end

-- Quita las piezas que ya tocan según lo comido (las finales las quita el remate)
local function trim(state)
	local eaten = 1 - state.left / state.total
	local plan = state.plan
	while state.cut < #plan do
		local step = plan[state.cut + 1]
		if step.at >= FINAL or step.at > eaten + 1e-6 then
			break
		end
		state.cut += 1
		step.part:Destroy()
	end
end

local function inReach(state, player: Player, slack: number): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local offset = root.Position - state.center
	return (offset * FLAT).Magnitude <= state.reach + slack and math.abs(offset.Y) < 40
end

local function take(state, player: Player, amount: number)
	amount = math.min(amount, state.left)
	if amount <= 0 then
		return
	end
	state.left -= amount
	local count = (state.bites[player] or 0) + amount
	state.bites[player] = count
	state.model:SetAttribute("B_" .. player.UserId, count)
	state.model:SetAttribute("Left", state.left)
	trim(state)
end

-- Golpe del minijuego. El servidor no ve la marca: se fía del resultado, pero lo acota.
local function onFeastHit(player: Player, amount: any)
	local state = feast
	if not state or state.left <= 0 or typeof(amount) ~= "number" or not HIT_VALID[amount] then
		return
	end
	if not Profiles.get(player) then
		return
	end
	local clock = os.clock()
	local tokens = math.min(HIT_BURST, (state.tokens[player] or HIT_BURST) + (clock - (state.tokenAt[player] or clock)) / HIT_GAP)
	state.tokenAt[player] = clock
	if tokens < 1 then
		state.tokens[player] = tokens
		return
	end
	state.tokens[player] = tokens - 1
	if not inReach(state, player, FEAST_SLACK) then
		return
	end
	state.lastHit[player] = clock
	state.idle[player] = 0
	if amount > 0 then
		take(state, player, amount)
	end
end

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
	local plan = bitePlan(pieces)

	local total = poolFor(onlineCount())
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

	local state = {
		model = model,
		plan = plan,
		cut = 0,
		total = total,
		left = left,
		center = home.Position,
		reach = FEAST_RADIUS + FEAST_REACH,
		bites = {} :: { [Player]: number },
		lastHit = {} :: { [Player]: number },
		idle = {} :: { [Player]: number },
		tokens = {} :: { [Player]: number },
		tokenAt = {} :: { [Player]: number },
	}
	feast = state

	-- Los golpes llegan por el remoto; aquí solo el bocado lento de quien está al lado sin jugar
	local finish = os.clock() + FEAST_TIME
	local last = os.clock()
	while state.left > 0 and os.clock() < finish do
		task.wait(FEAST_TICK)
		local clock = os.clock()
		local dt = clock - last
		last = clock
		for player in Profiles.all() do
			if state.left <= 0 then
				break
			end
			if inReach(state, player, 0) and clock - (state.lastHit[player] or -math.huge) >= PASSIVE_IDLE then
				local idle = (state.idle[player] or 0) + dt
				if idle >= PASSIVE_EVERY then
					idle -= PASSIVE_EVERY
					take(state, player, 1)
				end
				state.idle[player] = idle
			else
				state.idle[player] = 0
			end
		end
	end
	feast = nil
	left = state.left
	local bites = state.bites

	-- Remate: las últimas piezas caen seguidas, solo con el último bocado
	if left <= 0 then
		local remaining = #plan - state.cut
		local gap = if remaining > 0 then math.min(0.08, 0.6 / remaining) else 0
		for i = state.cut + 1, #plan do
			plan[i].part:Destroy()
			task.wait(gap)
		end
		state.cut = #plan
	end

	-- Reparto: premio fijo + parte según lo comido respecto a la media (o a una referencia mínima,
	-- para que comer de verdad cuente aunque estés solo). Con rivales, quien más come +25 %.
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
		local reference = math.max(sum / people, FEAST_PAR * poolFor(people) / people)
		for player, count in bites do
			local profile = Profiles.get(player)
			if not player.Parent or not profile then
				continue
			end
			local ratio = math.clamp(count / reference, 0, RATIO_MAX)
			local gain = income(profile, FEAST_SECONDS, FEAST_FLOOR) * (FEAST_PRIZE + (1 - FEAST_PRIZE) * ratio)
			if people > 1 and count == top then
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
			mine = if gains[player]
				then { count = bites[player], gain = gains[player], top = people > 1 and bites[player] == top }
				else nil,
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
		feast = nil
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
local function onHello(player: Player)
	if greeted[player] then
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

-- Mensajes del cliente: "Hello" al entrar; "FeastHit", n en cada golpe del minijuego.
local function onMessage(player: Player, kind: any, amount: any)
	if kind == "Hello" then
		onHello(player)
	elseif kind == "FeastHit" then
		onFeastHit(player, amount)
	end
end

function WorldEvents.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "WorldEvent"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onMessage)

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
