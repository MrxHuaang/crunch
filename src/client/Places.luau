-- Lugares: abre en local las puertas de las zonas a las que ya llegas, avisa al chocar con una
-- cerrada, tiñe la luz según la zona en la que estás y saluda con el nombre de cada zona nueva.
-- Nada de esto toca el servidor: la barrera sigue sólida para los demás.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Places = {}

local TICK = 0.2 -- cinco veces por segundo basta
local GATE_REACH = 9 -- distancia al plano de la puerta para dar el aviso
local DOOR = 24 -- media anchura del arco
local WARN_EVERY = 6
-- Título de zona (diseño, misma escala que el HUD): bajo la caja de Comida, 2 s en total
local TITLE_Y = 100
local TITLE_W = 520
local TITLE_H = 60
local TITLE_HOLD = 1.7 -- entra en 0.3 s, se queda y sale en 0.3 s: 2 s desde que aparece

local player = Players.LocalPlayer

-- Tinte y luz ambiente por tema. Sutil: la paleta del cómic manda.
local BASE_AMBIENT = Color3.fromRGB(150, 150, 150)
local BASE_OUTDOOR = Color3.fromRGB(165, 165, 165)
local WHITE = Color3.new(1, 1, 1)

local function look(tint: Color3, ambient: Color3?, outdoor: Color3?)
	return { tint = tint, ambient = ambient or BASE_AMBIENT, outdoor = outdoor or BASE_OUTDOOR }
end

local MOODS = {
	Jardin = look(WHITE),
	Picnic = look(WHITE),
	Huerto = look(WHITE),
	Feria = look(WHITE),
	Jungla = look(Color3.fromRGB(236, 255, 236), Color3.fromRGB(144, 158, 144), Color3.fromRGB(158, 174, 158)),
	Mar = look(Color3.fromRGB(255, 250, 236), Color3.fromRGB(162, 158, 150), Color3.fromRGB(180, 174, 162)),
	Cocina = look(Color3.fromRGB(255, 246, 232), Color3.fromRGB(156, 150, 144), Color3.fromRGB(170, 164, 156)),
	Barbacoa = look(Color3.fromRGB(255, 238, 220), Color3.fromRGB(162, 146, 136), Color3.fromRGB(178, 160, 146)),
	Despensa = look(Color3.fromRGB(255, 244, 226), Color3.fromRGB(150, 142, 134), Color3.fromRGB(164, 156, 146)),
	Juguetes = look(Color3.fromRGB(244, 246, 255)),
	Escritorio = look(Color3.fromRGB(248, 244, 236), Color3.fromRGB(146, 146, 154), Color3.fromRGB(160, 160, 170)),
	Nevera = look(Color3.fromRGB(232, 244, 255), Color3.fromRGB(144, 152, 164), Color3.fromRGB(156, 166, 180)),
	Dulce = look(Color3.fromRGB(255, 238, 246), Color3.fromRGB(158, 148, 154), Color3.fromRGB(174, 162, 170)),
	Espacio = look(Color3.fromRGB(236, 228, 255), Color3.fromRGB(110, 104, 128), Color3.fromRGB(122, 114, 142)),
}

-- Puertas -----------------------------------------------------------------------------------

local gatesFolder: Instance? = nil
local gateOpen: { [number]: boolean } = {} -- último estado conocido por zona (nil: aún no se sabe)
local animating: { [Model]: boolean } = {}
local barOrigin: { [BasePart]: { cframe: CFrame, transparency: number } } = {}

local function depthKnown(): boolean
	return player:GetAttribute("Depth") ~= nil
end

-- Hasta qué zona se abren las puertas: tu capa o la de la llave maestra (Monetize, atributo KeyDepth)
local function gateDepth(): number
	local key = player:GetAttribute("KeyDepth")
	return math.max(State.depth(), if type(key) == "number" then key else 0)
end

local function zoneOf(gate: Instance): number?
	local zone = gate:GetAttribute("Zone")
	if type(zone) == "number" then
		return zone
	end
	local fromName = tonumber(string.match(gate.Name, "^Gate(%d+)$"))
	return fromName
end

local function bars(gate: Model): { BasePart }
	local list = {}
	for _, child in gate:GetChildren() do
		if child.Name == "Bar" and child:IsA("BasePart") then
			if not barOrigin[child] then
				barOrigin[child] = { cframe = child.CFrame, transparency = child.Transparency }
			end
			table.insert(list, child)
		end
	end
	return list
end

local function setHighlights(gate: Model, enabled: boolean)
	for _, child in gate:GetChildren() do
		if child:IsA("Highlight") then
			child.Enabled = enabled
		end
	end
end

local function setBlock(gate: Model, solid: boolean)
	local block = gate:FindFirstChild("Block")
	if block and block:IsA("BasePart") then
		block.CanCollide = solid
	end
end

local function closeGate(gate: Model)
	setBlock(gate, true)
	setHighlights(gate, true)
	for _, bar in bars(gate) do
		local origin = barOrigin[bar]
		bar.CFrame = origin.cframe
		bar.Transparency = origin.transparency
	end
end

local function openGate(gate: Model)
	setBlock(gate, false)
	setHighlights(gate, false)
	for _, bar in bars(gate) do
		bar.Transparency = 1
	end
end

-- La barrera se levanta como un paso a nivel y se desvanece
local function swingOpen(gate: Model)
	if animating[gate] then
		return
	end
	animating[gate] = true
	setBlock(gate, false)
	local list = bars(gate)
	task.spawn(function()
		local duration = 0.9
		local start = os.clock()
		while true do
			local t = math.clamp((os.clock() - start) / duration, 0, 1)
			local eased = 1 - (1 - t) ^ 3
			for i, bar in list do
				if bar.Parent then
					local origin = barOrigin[bar]
					local half = bar.Size.X / 2
					local hinge = origin.cframe * CFrame.new(-half, 0, 0)
					local lift = math.rad(78 + i * 3) * eased
					bar.CFrame = hinge * CFrame.Angles(0, 0, lift) * CFrame.new(half, 0, 0)
					bar.Transparency = origin.transparency + (1 - origin.transparency) * t ^ 2
				end
			end
			if t >= 1 then
				break
			end
			task.wait()
		end
		animating[gate] = nil
		if gate.Parent then
			if gateDepth() >= (zoneOf(gate) or math.huge) then
				openGate(gate)
			else
				closeGate(gate)
			end
		end
	end)
	task.delay(0.6, function()
		if gate.Parent and animating[gate] then
			setHighlights(gate, false)
		end
	end)
end

local function applyGate(gate: Instance, animate: boolean)
	if not gate:IsA("Model") then
		return
	end
	local zone = zoneOf(gate)
	if not zone or animating[gate] then
		return
	end
	if gateDepth() >= zone then
		if animate then
			swingOpen(gate)
		else
			openGate(gate)
		end
	else
		closeGate(gate)
	end
end

local function applyAll()
	local depth = gateDepth()
	local known = depthKnown()
	-- Qué zonas acaban de abrirse ahora mismo, durante la partida
	local justOpened = {}
	for _, zone in Config.Zones do
		local open = depth >= zone.id
		if known then
			if gateOpen[zone.id] == false and open then
				justOpened[zone.id] = true
			end
			gateOpen[zone.id] = open
		end
	end
	if not gatesFolder then
		return
	end
	for _, gate in gatesFolder:GetChildren() do
		local zone = zoneOf(gate)
		applyGate(gate, zone ~= nil and justOpened[zone] == true)
	end
end

-- Las piezas de una puerta pueden llegar sueltas con el streaming: se reaplica a su modelo
local pending: { [Instance]: boolean } = {}
local function schedule(gate: Instance)
	if pending[gate] then
		return
	end
	pending[gate] = true
	task.defer(function()
		pending[gate] = nil
		if gate.Parent then
			applyGate(gate, false)
		end
	end)
end

local function watchGates(folder: Instance)
	gatesFolder = folder
	folder.DescendantAdded:Connect(function(descendant)
		local gate = if descendant.Parent == folder then descendant else descendant:FindFirstAncestorWhichIsA("Model")
		if gate and gate:IsDescendantOf(folder) then
			schedule(gate)
		end
	end)
	folder.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			barOrigin[descendant] = nil
		end
	end)
	applyAll()
end

local function findGates()
	local folder = Workspace:FindFirstChild("Gates")
	if folder then
		watchGates(folder)
		return
	end
	local connection
	connection = Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Gates" and not gatesFolder then
			connection:Disconnect()
			watchGates(child)
		end
	end)
	task.spawn(function()
		local found = Workspace:WaitForChild("Gates", 30)
		if found and not gatesFolder then
			connection:Disconnect()
			watchGates(found)
		end
	end)
end

-- Aviso al chocar con una puerta cerrada ----------------------------------------------------

local lastWarn = -math.huge

local function checkClosedGate(position: Vector3)
	if os.clock() - lastWarn < WARN_EVERY or math.abs(position.X) > DOOR then
		return
	end
	local depth = gateDepth()
	for i = 2, #Config.Zones do
		local zone = Config.Zones[i]
		if depth < zone.id and math.abs(position.Z - (zone.z0 + 10)) <= GATE_REACH then
			lastWarn = os.clock()
			Bubble.flash("Cerrado. Necesito excavar hasta la capa " .. zone.id .. " para entrar en " .. zone.name, 4)
			return
		end
	end
end

-- Ambiente y nombre de la zona -------------------------------------------------------------

local gui: ScreenGui
local titleHolder: Frame
local titleLabel: TextLabel
local titleBurst: ImageLabel
local titleToken = 0
local seen: { [number]: boolean } = { [1] = true } -- el jardín no se anuncia al aparecer
local currentMood = nil

local function zoneAt(z: number): number?
	if z > -Config.Map.LobbyRadius then
		return 1
	end
	for i = 2, #Config.Zones do
		local zone = Config.Zones[i]
		if z >= zone.z1 and z <= zone.z0 + 20 then
			return i
		end
	end
	return nil
end

local function setMood(mood)
	if mood == currentMood then
		return
	end
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local grade = Lighting:FindFirstChild("Grade")
	if grade and grade:IsA("ColorCorrectionEffect") then
		TweenService:Create(grade, info, { TintColor = mood.tint }):Play()
		currentMood = mood -- sin el filtro aún replicado, se reintenta en la siguiente vuelta
	end
	TweenService:Create(Lighting, info, { Ambient = mood.ambient, OutdoorAmbient = mood.outdoor }):Play()
end

local function buildTitle()
	gui = Instance.new("ScreenGui")
	gui.Name = "Places"
	gui.IgnoreGuiInset = false -- mismo sistema que el HUD: bajo la barra de Roblox
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Misma posición y escala que la cabecera del HUD: el título cae justo bajo la comida,
	-- en la franja de arriba (sin bajar al centro de la pantalla) y se va en 2 s
	local top = Comic.frame(gui)
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 6)
	top.Size = UDim2.fromOffset(TITLE_W, TITLE_Y + TITLE_H)
	Hud.fitScale(top)

	titleHolder = Comic.frame(top)
	titleHolder.AnchorPoint = Vector2.new(0.5, 0)
	titleHolder.Position = UDim2.new(0.5, 0, 0, TITLE_Y)
	titleHolder.Size = UDim2.fromOffset(TITLE_W, TITLE_H)
	titleHolder.Visible = false

	titleBurst = Comic.burst(titleHolder, 70, Comic.Red)
	titleBurst.Position = UDim2.new(0.5, -150, 0.5, 0)
	Comic.boil(titleBurst, 6)

	titleLabel = Comic.label(titleHolder, "", Comic.Display, 52, Comic.Yellow)
	titleLabel.Size = UDim2.fromScale(1, 1)
	titleLabel.TextScaled = true
	titleLabel.ZIndex = 2
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 52
	limit.Parent = titleLabel
	local stroke = Comic.ink(titleLabel, 4.5)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
end

local function showTitle(name: string)
	titleToken += 1
	local token = titleToken
	titleLabel.Text = name
	titleHolder.Visible = true
	titleHolder.Rotation = -4
	titleHolder.Position = UDim2.new(0.5, 0, 0, TITLE_Y - 24)
	titleLabel.TextTransparency = 0
	titleBurst.ImageTransparency = 0.1
	local inInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(titleHolder, inInfo, { Position = UDim2.new(0.5, 0, 0, TITLE_Y) }):Play()
	Sfx.pop(0.8)
	task.delay(TITLE_HOLD, function()
		if titleToken ~= token then
			return
		end
		local out = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(titleHolder, out, { Position = UDim2.new(0.5, 0, 0, TITLE_Y - 24) }):Play()
		TweenService:Create(titleLabel, out, { TextTransparency = 1 }):Play()
		TweenService:Create(titleBurst, out, { ImageTransparency = 1 }):Play()
		task.delay(0.3, function()
			if titleToken == token then
				titleHolder.Visible = false
			end
		end)
	end)
end

local function tick()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local position = root.Position

	checkClosedGate(position)

	local index = zoneAt(position.Z)
	if not index then
		return
	end
	local zone = Config.Zones[index]
	setMood(MOODS[zone.theme] or MOODS.Jardin)
	if not seen[index] then
		seen[index] = true
		showTitle(zone.name)
	end
end

function Places.start()
	buildTitle()
	findGates()
	-- Solo cuando cambia lo que abre las puertas: con cada cambio del perfil (la comida, varias veces
	-- por segundo) se volvían a colocar las barras de todas las puertas cerradas
	local applied = ""
	State.onChange(function()
		local key = tostring(gateDepth()) .. "|" .. tostring(depthKnown())
		if key ~= applied then
			applied = key
			applyAll()
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("[CRUNCH!] Places:", err)
			end
			task.wait(TICK)
		end
	end)
end

return Places
