-- Habilidades activas: rastro, sprint, alas, frenesí, pisotón y tirachinas. Cada una tiene tecla y botón,
-- y el botón solo aparece cuando la tienes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)
local Fx = require(script.Parent.Fx)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Targeting = require(script.Parent.Targeting)

local Abilities = {}

local HOME_RADIUS = 45 -- desde aquí las alas ya no te llevan a casa, sino a tu zona más lejana
local FLAT = Vector3.new(1, 0, 1)
local BUTTON = 52 -- lado de los botones redondos (diseño; ~56 px a 1080 de alto)

local player = Players.LocalPlayer
local remotes
local buttons = {}
local sprintReadyAt = 0
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

local function doTrail()
	local target = Targeting.current()
	if target then
		remotes.Trail:FireServer(target)
	end
end

local function doSprint()
	local hum = humanoid()
	if not hum or os.clock() < sprintReadyAt then
		return
	end
	local duration = State.stats().sprintDuration
	sprintReadyAt = os.clock() + Config.Sprint.Cooldown
	hum.WalkSpeed = State.num("WalkSpeed") * Config.Sprint.Mult
	Fx.speed(duration)
	Sfx.pop(1.5)
	task.delay(duration, function()
		local later = humanoid()
		if later then
			later.WalkSpeed = State.num("WalkSpeed")
		end
	end)
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
local function doWings()
	local part = root()
	if flying or not part or os.clock() < wingsReadyAt then
		return
	end
	local from = part.Position
	local to = wingsTarget(from)
	if not to or ((to - from) * FLAT).Magnitude < 1 then
		return
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

local function doSling()
	if State.now() >= State.num("SlingReadyAt") and State.num("Carry") > 0 then
		askAllies("Sling")
	end
end

local LIST = {
	{ id = "trail", key = Enum.KeyCode.F, keyName = "F", label = "Rastro", run = doTrail, ready = function()
		return 0
	end },
	{ id = "sprint", key = Enum.KeyCode.LeftShift, keyName = "Shift", label = "Sprint", run = doSprint, ready = function()
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
}

-- ¿Puedes usar esta habilidad ahora? Las alas pueden venir del árbol o de un pase,
-- así que se leen del atributo que manda el servidor.
local function available(id: string): boolean
	return if id == "wings" then State.flag("HasWings") else (State.nodes()[id] or 0) > 0
end

local function build(gui: ScreenGui)
	local column = Comic.frame(gui)
	column.Name = "Abilities"
	column.AnchorPoint = Vector2.new(1, 0.5)
	-- Pegada al borde derecho. En móvil sube un poco para no pisar el botón de saltar.
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	column.Position = UDim2.new(1, -12, 0.5, if phone then -36 else 0)
	column.AutomaticSize = Enum.AutomaticSize.XY
	Hud.fitScale(column, BUTTON) -- en táctil, nunca por debajo de 44 px

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = column

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
				ability.run()
			end
		end)
		buttons[ability.id] = { holder = holder, face = face, icon = icon, wait = wait }
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
	refreshUnlocks()
	State.onChange(refreshUnlocks)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		for _, ability in LIST do
			if input.KeyCode == ability.key and available(ability.id) then
				ability.run()
			end
		end
	end)

	-- Enfriamientos: el botón se oscurece y muestra los segundos
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, ability in LIST do
				local button = buttons[ability.id]
				local left = ability.ready()
				local cooling = left > 0
				button.wait.Visible = cooling
				button.icon.ImageTransparency = if cooling then 0.75 else 0
				button.face.BackgroundColor3 = if cooling then Comic.DirtLight else Comic.Paper
				if cooling then
					button.wait.Text = tostring(math.ceil(left))
				end
			end
		end
	end)
end

return Abilities
