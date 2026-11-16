-- Túnel exprés: un agujero bien visible delante del montículo de cada dueña de la mejora y un agujero
-- de salida justo dentro de cada zona que alguna dueña conectada tenga abierta (geometría compartida).
-- Cada agujero lleva un ProximityPrompt que el servidor deja apagado: cada cliente enciende solo los
-- suyos (ver src/client/Tunnel.luau). El viaje lo pide el cliente por el remoto "Tunnel" y aquí se
-- valida todo: la mejora, la zona abierta, que estés junto al agujero y la espera.
--
-- Los agujeros se rehacen en el acto con cada Profiles.refresh (compra, entrada, enjambre, capa
-- nueva) y, por si acaso, en una pasada lenta.
--
-- Remoto "Tunnel" (cliente -> servidor): ("Go", zona) desde casa, ("Home") desde una salida.
-- Suceso Fx "Tunnel" (servidor -> viajera): (agujero de salida, agujero de llegada).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Profiles = require(script.Parent.Profiles)

local Tunnel = {}

local TICK = 1
local FLAT = Vector3.new(1, 0, 1)
local MOUTH = 6.6 -- diámetro de la boca negra
-- Las salidas quedan a un lado del camino, entre la puerta y los racimos (que empiezan a
-- Config.FoodLayout.Margin studs de la puerta y a 14 del muro)
local EXIT_X = -(Config.Map.Half - 30) -- lejos de los puestos avanzados, que van pegados a los muros
local EXIT_IN = 8
local HOLE = Color3.fromRGB(16, 10, 8)
local THROAT = Color3.fromRGB(40, 26, 18)
-- Tierra recién removida: más clara y cálida que la del montículo, para que se vea de lejos
local FRESH = { Color3.fromRGB(240, 172, 98), Color3.fromRGB(250, 196, 124), Color3.fromRGB(226, 150, 84) }
local WOOD = Color3.fromRGB(150, 100, 58)
local WOOD_DARK = Color3.fromRGB(118, 76, 44)
local BOARD = Color3.fromRGB(255, 210, 63)
local PEBBLE = { Color3.fromRGB(170, 174, 186), Color3.fromRGB(190, 188, 194) }
local INK = Color3.fromRGB(20, 16, 16)
local DISPLAY = Font.new("rbxasset://fonts/families/Bangers.json")

local fxRemote: RemoteEvent
local homes: { [Model]: any } = {} -- hormiguero -> { profile, model, spot, inward, scale }
local exits: { [number]: Model } = {} -- zona -> agujero de salida
local exitFolder: Model? = nil
local busy: { [Player]: number } = {} -- hasta cuándo (os.clock) no puede volver a viajar

local function part(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, kind: string?): BasePart
	local p: BasePart = if kind == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "cylinder" then
		(p :: Part).Shape = Enum.PartType.Cylinder
	end
	p.Size = size
	p.Color = color
	p.CFrame = cframe
	if kind == "blob" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local function exitSpot(zone): Vector3
	return Vector3.new(EXIT_X, Config.GroundY, zone.z0 - EXIT_IN)
end

local function boardText(board: BasePart, text: string)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.2
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.05, 0.08)
		label.Size = UDim2.fromScale(0.9, 0.84)
		label.FontFace = DISPLAY
		label.TextScaled = true
		label.TextColor3 = INK
		label.Text = text
		label.Parent = gui
	end
end

-- Boca de túnel de cómic: boca negra ancha con garganta, anillo de terrones de tierra fresca, dos
-- tablones y unas piedras enmarcándola, y un poste alto con una flecha amarilla.
-- `facing`: hacia dónde mira la flecha (hacia quien llega). `outward`: lado donde va el poste.
local function buildHole(parent: Instance, name: string, spot: Vector3, facing: Vector3, outward: Vector3, title: string, kind: string, zoneId: number?): Model
	local model = Instance.new("Model")
	model.Name = name
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local look = Vector3.new(facing.X, 0, facing.Z)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
	local out = Vector3.new(outward.X, 0, outward.Z)
	out = if out.Magnitude > 0.01 then out.Unit else look:Cross(Vector3.yAxis)

	-- Boca: un disco negro ancho y, dentro, una garganta algo más clara hundida, para que parezca hondo
	part(model, Vector3.new(0.3, MOUTH, MOUTH), HOLE, CFrame.new(spot + Vector3.new(0, 0.14, 0)) * flat, "cylinder")
	part(model, Vector3.new(0.3, MOUTH * 0.55, MOUTH * 0.55), THROAT, CFrame.new(spot + Vector3.new(0, 0.18, 0)) * flat, "cylinder")
	part(model, Vector3.new(0.32, MOUTH * 0.3, MOUTH * 0.3), HOLE, CFrame.new(spot + Vector3.new(0, 0.2, 0)) * flat, "cylinder")
	-- Anillo de terrones gordos de tierra fresca, más altos que el suelo
	local ring = MOUTH / 2 + 0.9
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local w = 2.4 + (i % 3) * 0.35
		local h = 1.3 + ((i * 7) % 3) * 0.3
		part(model, Vector3.new(w, h, 1.9), FRESH[i % 3 + 1], CFrame.new(spot + Vector3.new(math.cos(a) * ring, h * 0.32, math.sin(a) * ring)) * CFrame.Angles(0, -a, 0.12), "blob")
	end
	-- Dos tablones cruzando el borde y tres piedras redondas
	local across = look:Cross(Vector3.yAxis)
	for _, k in { -1, 1 } do
		local at = spot + across * k * (MOUTH / 2 + 0.2) + look * 0.6
		part(model, Vector3.new(0.9, 0.35, 4.2), if k < 0 then WOOD else WOOD_DARK, CFrame.lookAt(at + Vector3.new(0, 0.9, 0), at + Vector3.new(0, 0.9, 0) + look) * CFrame.Angles(0.18, k * 0.35, k * 0.2))
	end
	for i = 0, 2 do
		local a = math.atan2(look.Z, look.X) + (i - 1) * 0.55
		local r = ring + 1.6
		part(model, Vector3.new(1.4, 1, 1.2), PEBBLE[i % 2 + 1], CFrame.new(spot + Vector3.new(math.cos(a) * r, 0.35, math.sin(a) * r)), "blob")
	end

	-- Poste alto (unos 8 studs) a un lado, con una flecha amarilla que mira a quien llega
	local base = spot + out * (ring + 2.2)
	part(model, Vector3.new(0.7, 8.2, 0.7), WOOD, CFrame.new(base + Vector3.new(0, 4.1, 0)))
	part(model, Vector3.new(1.4, 0.6, 1.4), WOOD_DARK, CFrame.new(base + Vector3.new(0, 0.25, 0)), "blob")
	local boardAt = base + Vector3.new(0, 6.6, 0) + look * 0.45
	-- La flecha apunta hacia la boca: su punta va hacia -out
	-- Eje X de la tablilla hacia fuera (out): así su cara Front mira a `look` (out x arriba = -look)
	local board = part(model, Vector3.new(4.6, 1.8, 0.35), BOARD, CFrame.fromMatrix(boardAt - out * 0.6, out, Vector3.yAxis) * CFrame.Angles(0, 0, math.rad(-3)))
	board.Name = "Board"
	boardText(board, title)
	-- Punta de flecha: un rombo en el extremo que da a la boca (-X de la tablilla)
	part(model, Vector3.new(1.3, 1.3, 0.35), BOARD, board.CFrame * CFrame.new(-2.3, 0, 0) * CFrame.Angles(0, 0, math.rad(45)))

	-- El aviso de la tecla, apagado: cada cliente enciende el suyo
	local anchor = part(model, Vector3.new(1, 1, 1), HOLE, CFrame.new(spot + Vector3.new(0, 2, 0)))
	anchor.Name = "PromptAnchor"
	anchor.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TunnelPrompt"
	prompt.ObjectText = "Túnel exprés"
	prompt.ActionText = if kind == "Home" then "Viajar" else "Volver a casa"
	prompt.KeyboardKeyCode = Enum.KeyCode.B
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt:SetAttribute("Tunnel", kind)
	if zoneId then
		prompt:SetAttribute("Zone", zoneId)
	end
	prompt.Parent = anchor

	model:SetAttribute("Tunnel", kind)
	if zoneId then
		model:SetAttribute("Zone", zoneId)
	end
	model.Parent = parent
	return model
end

-- Sitio del agujero de casa, en unidades de la escala del montículo: DELANTE, del lado del jardín
-- (inward), por fuera del cartel del nombre (inward*8 + side*8) y de todo HillModel (que llega a ~11),
-- a un lado de la línea de las obreras (a lo largo de inward) y lejos del huevo (inward*6 - side*9.5)
-- y del punto de aparición (inward*(18 + 14*escala), en la línea central).
local function homePlace(hill: Model)
	local center = hill:GetPivot().Position
	local inward = (Vector3.new(0, center.Y, 0) - center).Unit
	local side = inward:Cross(Vector3.yAxis)
	local scale = hill:GetAttribute("Scale") or 1
	return center + (inward * 14 + side * 8) * scale, inward, side, scale
end

local function dropHome(hill: Model)
	local home = homes[hill]
	if home then
		homes[hill] = nil
		home.model:Destroy()
	end
end

local function wantsHome(profile): boolean
	return Profiles.get(profile.player) == profile and profile.hill ~= nil and profile.stats ~= nil and profile.stats.hasTunnel == true
end

-- Pone, quita o recoloca el agujero de casa de una jugadora
local function syncHome(profile)
	local hill = profile.hill
	-- Agujeros que ya no son de nadie (se fue, enjambró o cambió de hormiguero)
	for other, home in homes do
		if home.profile == profile and other ~= hill then
			dropHome(other)
		end
	end
	if not hill then
		return
	end
	local home = homes[hill]
	if home and (home.profile ~= profile or not wantsHome(profile) or (hill:GetAttribute("Scale") or 1) ~= home.scale or not home.model.Parent) then
		dropHome(hill) -- también si el montículo creció: se rehace en su sitio nuevo
		home = nil
	end
	if not home and wantsHome(profile) and hill.Parent then
		local spot, inward, side, scale = homePlace(hill)
		-- Bajo el modelo del hormiguero: le llega su contorno de tinta. La flecha mira al jardín
		-- y el poste queda por fuera, lejos de la línea de las obreras.
		local model = buildHole(hill, "Tunnel", spot, inward, side, "Túnel", "Home", nil)
		homes[hill] = { profile = profile, model = model, spot = spot, inward = inward, scale = scale }
	end
end

local function updateExits()
	-- Zonas que alguna dueña conectada tiene abiertas
	local wanted = {}
	for _, profile in Profiles.all() do
		local stats = profile.stats
		if stats and stats.hasTunnel then
			for zone = 2, math.min(stats.depth, #Config.Zones) do
				wanted[zone] = true
			end
		end
	end
	for zone, model in exits do
		if not wanted[zone] or not model.Parent then
			exits[zone] = nil
			model:Destroy()
		end
	end
	if next(wanted) == nil then
		return
	end
	if not exitFolder or not exitFolder.Parent then
		-- Bajo "Zones", que ya tiene su contorno de tinta: no hace falta otro Highlight
		local zones = Workspace:FindFirstChild("Zones")
		local folder = Instance.new("Model")
		folder.Name = "TunnelExits"
		folder.Parent = zones or Workspace
		exitFolder = folder
	end
	for zone in wanted do
		if not exits[zone] then
			local def = Config.Zones[zone]
			-- La flecha mira a la puerta (+Z), hacia quien entra; el poste, hacia la pared
			exits[zone] = buildHole(exitFolder :: Model, "Exit" .. zone, exitSpot(def), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), "Túnel a casa", "Exit", zone)
		end
	end
end

local function sync(profile)
	syncHome(profile)
	updateExits()
end

-- Pasada lenta por si algo se escapó (p. ej. un hormiguero liberado sin refresh)
local function tick()
	for hill, home in homes do
		if not wantsHome(home.profile) or home.profile.hill ~= hill then
			dropHome(hill)
		end
	end
	for _, profile in Profiles.all() do
		syncHome(profile)
	end
	updateExits()
end

local function near(root: BasePart, spot: Vector3): boolean
	return ((root.Position - spot) * FLAT).Magnitude <= Config.Tunnel.Reach
end

local function travel(player: Player, from: Vector3, to: Vector3, facing: Vector3)
	busy[player] = os.clock() + Config.Tunnel.Travel + Config.Tunnel.Cooldown
	fxRemote:FireClient(player, "Tunnel", from, to)
	local character = player.Character
	task.delay(Config.Tunnel.Travel, function()
		if player.Character ~= character or not getRoot(player) or not character then
			return
		end
		local up = Vector3.new(0, 1.5 * character:GetScale() + 1, 0)
		character:PivotTo(CFrame.lookAt(to + up, to + up + facing))
		-- El antitrampas de PlayerService mide el siguiente viaje desde la salida del túnel
		local profile = Profiles.get(player)
		if profile then
			profile.anchor = { position = to, at = os.clock() }
		end
	end)
end

local function onRequest(player: Player, action: any, zoneId: any)
	local profile = Profiles.get(player)
	local root = getRoot(player)
	if not profile or not root or not profile.stats or not profile.stats.hasTunnel or not profile.hill then
		return
	end
	if os.clock() < (busy[player] or 0) then
		return
	end
	local depth = profile.stats.depth
	local home = homes[profile.hill]
	if not home then
		return
	end

	if action == "Go" then
		-- zoneId == zoneId descarta NaN, que pasaría todas las comparaciones de abajo
		local zone = if type(zoneId) == "number" and zoneId == zoneId then math.floor(zoneId) else 0
		if zone < 2 or zone > depth or zone > #Config.Zones or not near(root, home.spot) then
			return
		end
		local exit = exitSpot(Config.Zones[zone])
		-- Asomas junto a la boca, hacia el centro del camino, mirando hacia el fondo de la zona
		travel(player, home.spot, exit + Vector3.new(MOUTH / 2 + 4, 0, 0), Vector3.new(0, 0, -1))
	elseif action == "Home" then
		for zone = 2, math.min(depth, #Config.Zones) do
			local exit = exitSpot(Config.Zones[zone])
			if near(root, exit) then
				-- Asomas junto a la boca, por el lado del jardín, mirando a tu hormiguero
				local center = profile.hill:GetPivot().Position
				local arrive = home.spot + home.inward * (MOUTH / 2 + 4)
				local look = (center - arrive) * FLAT
				travel(player, exit, arrive, if look.Magnitude > 0.01 then look.Unit else -home.inward)
				return
			end
		end
	end
end

function Tunnel.start(remotes: Folder)
	fxRemote = remotes.Fx
	local remote = Instance.new("RemoteEvent")
	remote.Name = "Tunnel"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	-- En el acto con cada refresh: comprar, entrar, enjambrar o excavar
	table.insert(Profiles.onRefresh, function(profile)
		local ok, err = pcall(sync, profile)
		if not ok then
			warn("[CRUNCH!] Túnel:", err)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		task.defer(tick) -- su agujero y las salidas que solo eran suyas se van ya
	end)
	-- Quien ya estaba conectada antes de arrancar este módulo
	task.defer(tick)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[CRUNCH!] Túnel:", err)
			end
		end
	end)
end

return Tunnel
