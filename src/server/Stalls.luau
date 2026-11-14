-- Puestos de compra por el mapa (servidor). Los puestos los dibuja cada cliente (src/client/Stalls.luau):
-- la mayoría son solo tuyos (la excavadora de tu próxima puerta, el buzón y el pedestal de tu
-- hormiguero, los carritos de tus zonas). Aquí va lo que tiene que ser igual para todas:
--   * el sitio del mercadillo del jardín (lejos de hormigueros, cartel, juguetes y camino), que se
--     publica en Workspace y se veta para la comida (FoodService.keepOut);
--   * la destinataria de los regalos y las pruebas de Studio (remoto "Stalls");
--   * la celebración de cada compra (a quien compra, a quien recibe y, si es para todas, a todas);
--   * los adornos de oro del pase Hormiguero dorado, que ven todas.
--
-- Atributos de Workspace: StallMarket (centro del mercadillo), StallMarketLook (hacia dónde mira).
-- Remoto "Stalls":
--   cliente -> servidor: "Gift" (UserId destinataria, id del regalo)
--                        "Try" (id, UserId destinataria?)  solo en Studio: entrega sin Robux
--   servidor -> clientes: "Bought" (UserId compradora, id, UserId destinataria, "pass" | "product")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodService = require(script.Parent.FoodService)
local Monetize = require(script.Parent.Monetize)
local Profiles = require(script.Parent.Profiles)
local World = require(script.Parent.World)

local Stalls = {}

local MAP = Config.Map
local GROUND = Config.GroundY
local FLAT = Vector3.new(1, 0, 1)
local MARKET_KEEP_OUT = 30 -- radio sin comida alrededor del mercadillo
local GOLD = Color3.fromRGB(255, 196, 40)
local GOLD_LIGHT = Color3.fromRGB(255, 232, 140)
local WOOD = Color3.fromRGB(132, 86, 52)

local remote: RemoteEvent
local lastAsk: { [Player]: number } = {}
local trims: { [Model]: { scale: number, model: Model } } = {}

---------------------------------------------------------------------------------------------------
-- Sitio del mercadillo: en la mitad del jardín que da al camino, a un lado de él, donde más hueco haya

local function marketSpot(): (Vector3, Vector3)
	local radius = MAP.LobbyRadius
	local obstacles: { { pos: Vector3, radius: number } } = {}
	for _, center in World.hillCenters do
		table.insert(obstacles, { pos = center, radius = 46 })
	end
	local board = Workspace:FindFirstChild("Board")
	if board and board:IsA("Model") then
		table.insert(obstacles, { pos = board:GetBoundingBox().Position, radius = 34 })
	end
	local toys = Workspace:FindFirstChild("GardenToys")
	if toys then
		for _, child in toys:GetChildren() do
			if child:IsA("Model") then
				table.insert(obstacles, { pos = child:GetPivot().Position, radius = 16 })
			end
		end
	end
	for _, circle in FoodService.keepOut do
		table.insert(obstacles, { pos = circle.pos, radius = circle.radius + 14 })
	end

	local best, bestRoom = nil, -math.huge
	for _, k in { 0.74, 0.68, 0.8 } do
		for degrees = -12, -168, -6 do
			local a = math.rad(degrees)
			local spot = Vector3.new(math.cos(a) * radius * k, GROUND, math.sin(a) * radius * k)
			-- Fuera del pasillo que va del centro a la boca del camino
			if math.abs(spot.X) < MAP.Half + 16 then
				continue
			end
			local room = math.huge
			for _, obstacle in obstacles do
				room = math.min(room, ((obstacle.pos - spot) * FLAT).Magnitude - obstacle.radius)
			end
			if room > bestRoom then
				best, bestRoom = spot, room
			end
		end
	end
	best = best or Vector3.new(radius * 0.55, GROUND, -radius * 0.5)
	local look = (Vector3.new(0, GROUND, 0) - best) * FLAT
	return best, if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis
end

---------------------------------------------------------------------------------------------------
-- Hormiguero dorado: anillo de pepitas de oro, dos farolillos junto a la boca y un banderín.
-- Va bajo el hormiguero (le llega su contorno de tinta) y fuera de "Mound", que se rehace a menudo.

local function piece(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, ball: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.CFrame = cframe
	p.Reflectance = if color == GOLD then 0.12 else 0
	if ball then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function buildTrim(hill: Model, s: number): Model
	local model = Instance.new("Model")
	model.Name = "GoldTrim"
	local center = hill:GetPivot().Position
	local inward = (Vector3.new(0, center.Y, 0) - center) * FLAT
	inward = if inward.Magnitude > 0.01 then inward.Unit else Vector3.zAxis
	local side = inward:Cross(Vector3.yAxis)

	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		local spot = center + Vector3.new(math.cos(a), 0, math.sin(a)) * 12 * s
		local size = 1.3 + (i % 3) * 0.3
		piece(model, Vector3.new(size * 1.2, size * 0.8, size), if i % 2 == 0 then GOLD else GOLD_LIGHT, CFrame.new(spot + Vector3.new(0, size * 0.3, 0)) * CFrame.Angles(0, a, 0.2), true)
	end
	for _, k in { -1, 1 } do
		local foot = center + (inward * 10 + side * k * 4.5) * s
		piece(model, Vector3.new(0.5, 4.2, 0.5), WOOD, CFrame.new(foot + Vector3.new(0, 2.1, 0)))
		piece(model, Vector3.new(1.6, 1.9, 1.6), GOLD, CFrame.new(foot + Vector3.new(0, 4.8, 0)), true)
		local glow = piece(model, Vector3.new(0.9, 1, 0.9), Color3.fromRGB(255, 250, 210), CFrame.new(foot + Vector3.new(0, 4.8, 0)), true)
		glow.Material = Enum.Material.Neon
		glow.Size = Vector3.new(1, 1.15, 1)
	end
	local pole = center - inward * 5 * s
	local top = 13 * s
	piece(model, Vector3.new(0.45, top, 0.45), WOOD, CFrame.new(pole + Vector3.new(0, top / 2, 0)))
	piece(model, Vector3.new(1.1, 1.1, 1.1), GOLD, CFrame.new(pole + Vector3.new(0, top + 0.4, 0)), true)
	local flag = Instance.new("WedgePart")
	flag.Anchored = true
	flag.CanCollide = false
	flag.CanQuery = false
	flag.CanTouch = false
	flag.CastShadow = false
	flag.Material = Enum.Material.SmoothPlastic
	flag.Color = GOLD
	flag.Size = Vector3.new(0.2, 2.2, 3.4)
	flag.CFrame = CFrame.lookAt(pole + Vector3.new(0, top - 1.4, 0), pole + Vector3.new(0, top - 1.4, 0) + side) * CFrame.new(0, 0, -1.7) * CFrame.Angles(math.rad(90), 0, 0)
	flag.Parent = model

	model.Parent = hill
	return model
end

local function dropTrim(hill: Model)
	local trim = trims[hill]
	if trim then
		trims[hill] = nil
		trim.model:Destroy()
	end
end

local function updateTrims()
	local wanted: { [Model]: number } = {}
	for _, profile in Profiles.all() do
		local hill = profile.hill
		if hill and hill.Parent and profile.passes.goldHill then
			wanted[hill] = hill:GetAttribute("Scale") or 1
		end
	end
	for hill, trim in trims do
		if not wanted[hill] or wanted[hill] ~= trim.scale or not trim.model.Parent then
			dropTrim(hill)
		end
	end
	for hill, scale in wanted do
		if not trims[hill] then
			trims[hill] = { scale = scale, model = buildTrim(hill, scale) }
		end
	end
end

---------------------------------------------------------------------------------------------------

local function allow(player: Player): boolean
	local t = os.clock()
	if t - (lastAsk[player] or 0) < 0.4 then
		return false
	end
	lastAsk[player] = t
	return true
end

local function profileOf(userId: any)
	if type(userId) ~= "number" then
		return nil
	end
	local player = Players:GetPlayerByUserId(userId)
	return player and Profiles.get(player)
end

local function onRequest(player: Player, action: any, a: any, b: any)
	local profile = Profiles.get(player)
	if not profile or not allow(player) then
		return
	end
	if action == "Gift" then
		local def = Monetize.find(b)
		local target = profileOf(a)
		if def and def.gift and target and target ~= profile then
			Monetize.setGiftTarget(player, target.player.UserId)
		end
	elseif action == "Try" then
		-- Solo en Studio y solo para artículos sin id: así se prueba todo antes de crearlos en Roblox
		if not RunService:IsStudio() or type(a) ~= "string" then
			return
		end
		local def, kind = Monetize.find(a)
		if not def then
			return
		end
		local id = if kind == "pass" then def.passId else def.productId
		if id > 0 then
			return
		end
		local target = profileOf(b)
		Monetize.debugGrant(profile, a, if target ~= profile then target else nil)
	end
end

local function celebrate(buyer, def, recipient, kind: string)
	local args = { buyer.player.UserId, def.id, recipient.player.UserId, kind }
	if def.wide then
		remote:FireAllClients("Bought", table.unpack(args))
		return
	end
	remote:FireClient(buyer.player, "Bought", table.unpack(args))
	if recipient ~= buyer and recipient.player.Parent then
		remote:FireClient(recipient.player, "Bought", table.unpack(args))
	end
end

function Stalls.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Stalls"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	local ok, err = pcall(function()
		local spot, look = marketSpot()
		Workspace:SetAttribute("StallMarket", spot)
		Workspace:SetAttribute("StallMarketLook", look)
		table.insert(FoodService.keepOut, { pos = spot, radius = MARKET_KEEP_OUT })
	end)
	if not ok then
		warn("[CRUNCH!] Mercadillo:", err)
	end

	table.insert(Monetize.onGrant, celebrate)

	table.insert(Profiles.onRefresh, function()
		local okTrim, errTrim = pcall(updateTrims)
		if not okTrim then
			warn("[CRUNCH!] Hormiguero dorado:", errTrim)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAsk[player] = nil
		task.defer(updateTrims)
	end)
	task.spawn(function()
		while true do
			task.wait(2)
			pcall(updateTrims)
		end
	end)
end

return Stalls
