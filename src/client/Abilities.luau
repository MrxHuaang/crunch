-- Correr (de serie) y las habilidades activas: rastro, turbo, alas, frenesí, pisotón y tirachinas.
-- Cada una tiene tecla y botón, y el botón solo aparece cuando la tienes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)
local Fx = require(script.Parent.Fx)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Targeting = require(script.Parent.Targeting)

local Abilities = {}

-- Multiplicador de velocidad por fuera (lo sustituye el módulo Extras: senda de feromonas)
Abilities.speedBoost = function(): number
	return 1
end

local HOME_RADIUS = 45 -- desde aquí las alas ya no te llevan a casa, sino a tu zona más lejana
local FLAT = Vector3.new(1, 0, 1)
local BUTTON = 52 -- lado de los botones redondos (diseño; ~56 px a 1080 de alto)
local PAD = 8 -- entre botones (diseño)
local GAP = 10 -- en celular: aire con el botón de saltar y con el de emotes (px reales)

local player = Players.LocalPlayer
local remotes
local buttons = {}
local hud: ScreenGui
local column: Frame
local list: UIListLayout
local grid: UIGridLayout
local scale: UIScale
local home: UDim2 -- sitio de la columna fuera del celular
local homeSize: UDim2
local laidCompact: boolean? = nil
local emoteHome: UDim2? = nil
local sprintReadyAt = 0
local turboUntil = 0
local shiftHeld = false -- teclado: corres mientras mantienes Shift
local runLatched = false -- táctil o clic: el botón deja la carrera puesta
local wingsReadyAt = 0
local flying = false

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function root(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

-- Las habilidades devuelven un texto si no hicieron nada por un motivo que no se ve en el botón
-- (la recarga ya se ve: el botón muestra los segundos). Lo enseña `use` en un bocadillo.
local function doTrail(): string?
	local target = Targeting.current()
	if not target then
		return "No hay comida a tiro para el rastro"
	end
	remotes.Trail:FireServer(target)
	return nil
end

-- Correr: el botón la deja puesta o la quita. Con teclado basta mantener Shift.
local function toggleRun()
	runLatched = not runLatched
	Sfx.pop(if runLatched then 1.3 else 0.9)
end

local function isRunning(): boolean
	return shiftHeld or runLatched
end

-- Turbo: un acelerón corto con enfriamiento. La velocidad la aplica el bucle de más abajo.
local function doSprint()
	if not humanoid() or os.clock() < sprintReadyAt then
		return
	end
	local duration = State.stats().sprintDuration
	sprintReadyAt = os.clock() + Config.Sprint.Cooldown
	turboUntil = os.clock() + duration
	Fx.speed(duration)
	Sfx.pop(1.5)
end

-- Velocidad que toca ahora mismo: andar, correr o turbo.
local function wantedSpeed(): number
	local walk = State.num("WalkSpeed")
	if walk <= 0 then
		walk = Config.Player.WalkSpeed
	end
	walk *= Abilities.speedBoost() -- senda de feromonas (módulo Extras)
	if os.clock() < turboUntil then
		return walk * Config.Sprint.Mult
	elseif isRunning() then
		return walk * Config.Run.Mult
	end
	return walk
end

local function wingsCooldown(): number
	local cooldown = State.num("WingsCooldown")
	return if cooldown > 0 then cooldown else Config.Wings.Cooldown
end

-- A dónde llevan las alas: lejos de casa, a la entrada del hormiguero;
-- ya en casa, a la entrada de la zona más honda que tengas abierta. nil si no hay a dónde ir.
local function wingsTarget(from: Vector3): Vector3?
	local hill = State.hill()
	if not hill then
		return nil
	end
	if ((hill:GetPivot().Position - from) * FLAT).Magnitude <= HOME_RADIUS then
		local depth = State.depth()
		local zone = Config.Zones[depth]
		if depth <= 1 or not zone then
			return nil
		end
		return Vector3.new(0, Config.GroundY + 3, zone.z0 - 12)
	end
	local spawn = hill:FindFirstChild("Spawn")
	return if spawn and spawn:IsA("BasePart") then spawn.Position else nil
end

-- Vuelo en arco: dura más y sube más cuanto más lejos vas.
local function doWings(): string?
	local part = root()
	if flying or not part or os.clock() < wingsReadyAt then
		return nil
	end
	local from = part.Position
	local to = wingsTarget(from)
	if not to or ((to - from) * FLAT).Magnitude < 1 then
		return "Ahora no hay a dónde volar"
	end

	local distance = (to - from).Magnitude
	local duration = Config.Wings.FlightTime + distance / 350
	local height = math.min(22 + distance * 0.03, 70)
	wingsReadyAt = os.clock() + wingsCooldown()
	flying = true
	Fx.speed(duration)
	Sfx.pop(0.7)

	local facing = CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z)).Rotation
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local now = root()
		local t = math.min((os.clock() - started) / duration, 1)
		if not now then
			connection:Disconnect()
			flying = false
			return
		end
		local eased = t * t * (3 - 2 * t)
		local position = from:Lerp(to, eased) + Vector3.new(0, math.sin(eased * math.pi) * height, 0)
		now.CFrame = CFrame.new(position) * facing
		now.AssemblyLinearVelocity = Vector3.zero
		if t >= 1 then
			connection:Disconnect()
			flying = false
		end
	end)
	return nil
end

local function doFrenzy()
	if State.now() >= State.num("FrenzyReadyAt") then
		remotes.Frenzy:FireServer()
	end
end

-- Pisotón y tirachinas: los decide el servidor (módulo Allies, remoto "Allies")
local function askAllies(action: string)
	local remote = remotes:FindFirstChild("Allies")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(action)
	end
end

local function doStomp()
	if State.now() >= State.num("StompReadyAt") then
		askAllies("Stomp")
	end
end

local function doSling(): string?
	if State.num("Carry") <= 0 then
		return "Para lanzar necesitas carga: muerde algo"
	end
	if State.now() >= State.num("SlingReadyAt") then
		askAllies("Sling")
	end
	return nil
end

-- Lluvia propia: la decide el servidor (módulo Extras, remoto "Extras")
local function doRain()
	local remote = remotes:FindFirstChild("Extras")
	if remote and remote:IsA("RemoteEvent") and State.now() >= State.num("RainReadyAt") then
		remote:FireServer("Rain")
	end
end

local LIST = {
	{ id = "trail", key = Enum.KeyCode.F, keyName = "F", label = "Rastro", run = doTrail, ready = function()
		return 0
	end },
	{ id = "run", icon = "speed", key = Enum.KeyCode.LeftShift, keyName = "Shift", label = "Correr", hold = true, run = toggleRun, ready = function()
		return 0
	end },
	{ id = "sprint", key = Enum.KeyCode.Z, keyName = "Z", label = "Turbo", run = doSprint, ready = function()
		return sprintReadyAt - os.clock()
	end },
	{ id = "wings", key = Enum.KeyCode.R, keyName = "R", label = "Volar", run = doWings, ready = function()
		return wingsReadyAt - os.clock()
	end },
	{ id = "frenzy", key = Enum.KeyCode.G, keyName = "G", label = "Frenesí", run = doFrenzy, ready = function()
		return State.num("FrenzyReadyAt") - State.now()
	end },
	{ id = "stomp", icon = "area", key = Enum.KeyCode.X, keyName = "X", label = "Pisotón", run = doStomp, ready = function()
		return State.num("StompReadyAt") - State.now()
	end },
	{ id = "sling", icon = "speed", key = Enum.KeyCode.C, keyName = "C", label = "Lanzar", run = doSling, ready = function()
		return State.num("SlingReadyAt") - State.now()
	end },
	{ id = "rain", icon = "royalFood", key = Enum.KeyCode.L, keyName = "L", label = "Lluvia", run = doRain, ready = function()
		return State.num("RainReadyAt") - State.now()
	end },
}

-- ¿Puedes usar esta habilidad ahora? Las alas pueden venir del árbol o de un pase,
-- así que se leen del atributo que manda el servidor.
local function available(id: string): boolean
	if id == "run" then
		return true -- correr viene de serie
	end
	return if id == "wings" then State.flag("HasWings") else (State.nodes()[id] or 0) > 0
end

-- Sacudida de "no puedes" (la de Wardrobe/Store). Se sacude la cara y no el soporte: al soporte
-- lo coloca la lista o la rejilla. Una a la vez, para no dejarla movida.
local shaking: { [GuiObject]: boolean } = {}
local function shake(object: GuiObject)
	if shaking[object] or player:GetAttribute("ReducedMotion") == true then -- Movimiento suave: sin sacudidas
		return
	end
	shaking[object] = true
	local base = object.Position
	task.spawn(function()
		for _, dx in { 7, -7, 5, -4, 2, 0 } do
			object.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		object.Position = base
		shaking[object] = nil
	end)
end

-- Usar una habilidad (botón o tecla). En recarga o sin efecto: sacudida y "bonk", y si el motivo
-- no se ve en el botón, un bocadillo corto.
local function use(ability)
	local why = if ability.ready() > 0 then "" else ability.run()
	if type(why) ~= "string" then
		return
	end
	shake(buttons[ability.id].face)
	Sfx.error()
	if why ~= "" then
		Bubble.flash(why, 2)
	end
end

local function build(gui: ScreenGui)
	hud = gui
	column = Comic.frame(gui)
	column.Name = "Abilities"
	column.AnchorPoint = Vector2.new(1, 0.5)
	-- Pegada al borde derecho. En móvil sube un poco para no pisar el botón de saltar.
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	home = UDim2.new(1, -12, 0.5, if phone then -36 else 0)
	homeSize = column.Size
	column.Position = home
	column.AutomaticSize = Enum.AutomaticSize.XY
	scale = Hud.fitScale(column, BUTTON) -- en táctil, nunca por debajo de 44 px

	list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, PAD)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = column

	-- Celular: rejilla de 2 columnas que se llena desde abajo a la derecha (lo primero, junto al
	-- pulgar). Solo se cuelga de la columna en celular (place); en PC sigue la lista de arriba.
	grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(BUTTON, BUTTON)
	grid.CellPadding = UDim2.fromOffset(PAD, PAD)
	grid.FillDirectionMaxCells = 2
	grid.StartCorner = Enum.StartCorner.BottomRight
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
	grid.SortOrder = Enum.SortOrder.LayoutOrder

	local showKeys = UserInputService.KeyboardEnabled

	for order, ability in LIST do
		local holder = Comic.frame(column)
		holder.Size = UDim2.fromOffset(BUTTON, BUTTON)
		holder.LayoutOrder = order
		holder.Visible = false

		local shadow = Comic.frame(holder, Comic.Ink)
		shadow.Size = UDim2.fromScale(1, 1)
		shadow.Position = UDim2.fromOffset(4, 4)
		Comic.round(shadow)

		local face = Instance.new("TextButton")
		face.AutoButtonColor = false
		face.Text = ""
		face.BackgroundColor3 = Comic.Paper
		face.BorderSizePixel = 0
		face.Size = UDim2.fromScale(1, 1)
		face.Parent = holder
		Comic.round(face)
		Comic.ink(face, 3.5, true).LineJoinMode = Enum.LineJoinMode.Round

		local icon = Comic.image(face, Assets.Icons[ability.icon or ability.id] or Assets.Icons.anthill)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.62, 0.62)

		local wait = Comic.label(face, "", Comic.Display, 28, Comic.Paper)
		wait.Size = UDim2.fromScale(1, 1)
		wait.Visible = false
		wait.ZIndex = 3
		Comic.ink(wait, 2.5)

		-- En teclado, una etiqueta con la tecla; en táctil, el nombre
		local tag = Comic.label(holder, if showKeys then ability.keyName else ability.label, Comic.Display, 15, Comic.Ink)
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(0, -6, 0.5, 0)
		tag.AutomaticSize = Enum.AutomaticSize.X
		tag.Size = UDim2.fromOffset(0, 20)
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = Comic.Yellow
		tag.Rotation = -3
		Comic.ink(tag, 2.5, true)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 5)
		pad.PaddingRight = UDim.new(0, 5)
		pad.Parent = tag

		face.MouseButton1Click:Connect(function()
			if available(ability.id) then
				use(ability)
			end
		end)
		buttons[ability.id] = { holder = holder, face = face, icon = icon, wait = wait, tag = tag }
	end
end

-- Botón de saltar de Roblox (pantalla sin la barra). Si aún no existe, donde lo pone Roblox en un
-- celular: 70 px, a 95 px del borde derecho y 90 del de abajo.
local function jumpRect(): (Vector2, Vector2)
	local touch = hud.Parent and hud.Parent:FindFirstChild("TouchGui")
	local frame = touch and touch:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
		return jump.AbsolutePosition, jump.AbsoluteSize
	end
	return hud.AbsolutePosition + hud.AbsoluteSize - Vector2.new(95, 90), Vector2.new(70, 70)
end

-- Celular (Hud.compact): rejilla justo encima del botón de saltar, alineada con su borde derecho,
-- y el botón de emotes a su izquierda, a ras de la fila de abajo. Fuera del celular, todo como
-- siempre. Se llama a menudo (bucle de enfriamientos): así sigue al giro de pantalla y al botón
-- de saltar o de emotes, que Roblox y Emotes crean más tarde.
local function place()
	local compact = Hud.compact()
	if compact ~= laidCompact then
		laidCompact = compact
		list.Parent = if compact then nil else column
		grid.Parent = if compact then column else nil
		column.AnchorPoint = if compact then Vector2.new(1, 1) else Vector2.new(1, 0.5)
		-- Ancho fijo de 2 botones: con tamaño automático en X la rejilla cabría en una sola columna
		column.Size = if compact then UDim2.fromOffset(2 * BUTTON + PAD, 0) else homeSize
		column.AutomaticSize = if compact then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY
		for _, button in buttons do
			button.tag.Visible = not compact -- en el celular basta el icono
		end
	end

	local emote = hud.Parent and hud.Parent:FindFirstChild("EmoteButton")
	local emoteHolder = emote and emote:FindFirstChild("Holder")
	if not (emote and emote:IsA("ScreenGui") and emoteHolder and emoteHolder:IsA("GuiObject")) then
		emote, emoteHolder = nil, nil
	elseif not emoteHome then
		emoteHome = emoteHolder.Position -- solo lo movemos nosotros: la primera vez está en su sitio
	end

	if not compact then
		column.Position = home
		if emoteHolder and emoteHome then
			emoteHolder.Position = emoteHome
		end
		return
	end
	local at, size = jumpRect()
	local right = at.X + size.X
	local bottom = at.Y - GAP
	column.Position = UDim2.fromOffset(right - hud.AbsolutePosition.X, bottom - hud.AbsolutePosition.Y)
	if emote and emoteHolder then
		-- Su ancla es la esquina de abajo a la derecha: a la izquierda de la rejilla completa
		local left = right - (2 * BUTTON + PAD) * scale.Scale - GAP
		emoteHolder.Position = UDim2.fromOffset(left - emote.AbsolutePosition.X, bottom - emote.AbsolutePosition.Y)
	end
end

local function refreshUnlocks()
	for _, ability in LIST do
		buttons[ability.id].holder.Visible = available(ability.id)
	end
end

function Abilities.start(gui: ScreenGui, remoteFolder: Folder)
	remotes = remoteFolder
	build(gui)
	place()
	refreshUnlocks()
	State.onChange(refreshUnlocks)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = true
			return
		end
		for _, ability in LIST do
			if not ability.hold and input.KeyCode == ability.key and available(ability.id) then
				use(ability)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = false
		end
	end)

	-- La velocidad se decide aquí y solo aquí: andar, correr o turbo. Se reaplica cada fotograma
	-- porque el servidor reescribe WalkSpeed al comprar mejoras.
	RunService.Heartbeat:Connect(function()
		local hum = humanoid()
		if hum and not flying then
			local speed = wantedSpeed()
			if math.abs(hum.WalkSpeed - speed) > 0.01 then
				hum.WalkSpeed = speed
			end
		end
	end)

	-- Enfriamientos: el botón se oscurece y muestra los segundos
	task.spawn(function()
		while true do
			task.wait(0.2)
			place()
			for _, ability in LIST do
				local button = buttons[ability.id]
				local left = ability.ready()
				local cooling = left > 0
				button.wait.Visible = cooling
				button.icon.ImageTransparency = if cooling then 0.75 else 0
				local lit = (ability.id == "run" and isRunning()) or (ability.id == "sprint" and os.clock() < turboUntil)
				button.face.BackgroundColor3 = if cooling then Comic.DirtLight elseif lit then Comic.Yellow else Comic.Paper
				if cooling then
					button.wait.Text = tostring(math.ceil(left))
				end
			end
		end
	end)
end

return Abilities
