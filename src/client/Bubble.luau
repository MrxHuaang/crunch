-- Bocadillo de cómic sobre la cabeza de tu hormiga, solo para frases cortas que duran unos segundos.
-- Lo que toca hacer (el texto "de estado") ya no va aquí: va a la tira de narración del HUD,
-- para no tapar el centro de la pantalla.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)

local Bubble = {}

local WIDTH = 220 -- nunca más de 230 px de ancho
local HEIGHT = 70
local TALL = 94 -- para frases largas
local MAX_TIME = 4 -- segundos como mucho sobre la cabeza, aunque pidan más
local LIFT = 4.2 -- studs sobre la cabeza con la hormiga a tamaño normal

local player = Players.LocalPlayer
local billboard: BillboardGui
local textLabel: TextLabel
local pop: UIScale
local shown: string? = nil
local flashToken = 0

local function attach(character: Model)
	local head = character:WaitForChild("Head", 10)
	if head and head:IsA("BasePart") then
		billboard.Adornee = head
	end
end

-- La hormiga puede crecer hasta el doble: el globo sube con ella para no taparla
local function place(text: string)
	local character = player.Character
	local scale = if character then character:GetScale() else 1
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LIFT * scale, 0)
	local long = (utf8.len(text) or #text) > 44
	billboard.Size = UDim2.fromOffset(WIDTH, if long then TALL else HEIGHT)
end

function Bubble.start()
	billboard = Instance.new("BillboardGui")
	billboard.Name = "Bubble"
	billboard.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LIFT, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Enabled = false
	billboard.Parent = player:WaitForChild("PlayerGui")

	local root = Comic.frame(billboard)
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, 1)
	root.Size = UDim2.fromScale(1, 1)

	pop = Instance.new("UIScale")
	pop.Parent = root

	-- Cola: un cuadrado girado que asoma por debajo del globo
	local tail = Comic.frame(root, Comic.Paper)
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, -14, 1, -17)
	tail.Size = UDim2.fromOffset(18, 18)
	tail.Rotation = 45
	Comic.ink(tail, 3)

	local face = Comic.frame(root, Comic.Paper)
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.new(0.5, 0, 0, 3)
	face.Size = UDim2.new(1, -6, 1, -22)
	face.ZIndex = 2
	Comic.round(face, 20)
	Comic.ink(face, 3).LineJoinMode = Enum.LineJoinMode.Round

	-- Tapa la línea de tinta donde la cola se une al globo
	local patch = Comic.frame(root, Comic.Paper)
	patch.AnchorPoint = Vector2.new(0.5, 1)
	patch.Position = UDim2.new(0.5, -14, 1, -18)
	patch.Size = UDim2.fromOffset(22, 9)
	patch.ZIndex = 3

	-- 17 px; las frases largas encogen un poco en vez de salirse del globo
	textLabel = Comic.label(root, "", Comic.Body, 17, Comic.Ink)
	textLabel.AnchorPoint = Vector2.new(0.5, 0)
	textLabel.Position = UDim2.new(0.5, 0, 0, 7)
	textLabel.Size = UDim2.new(1, -28, 1, -30)
	textLabel.TextWrapped = true
	textLabel.TextScaled = true
	textLabel.ZIndex = 4
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 17
	limit.MinTextSize = 11
	limit.Parent = textLabel

	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end
end

-- Texto de estado: ahora vive en la tira de narración del HUD. nil la esconde.
-- `urgent` (opcional) la mantiene visible; si no, se aparta sola a los 8 s.
function Bubble.say(text: string?, urgent: boolean?)
	Hud.setHint(text, urgent)
end

-- Frase corta sobre la cabeza durante `seconds` (como mucho MAX_TIME).
function Bubble.flash(text: string, seconds: number)
	seconds = math.min(tonumber(seconds) or MAX_TIME, MAX_TIME)
	flashToken += 1
	local token = flashToken
	if text ~= shown then
		-- Un mensaje nuevo rebota; el mismo repetido solo alarga su tiempo
		shown = text
		place(text)
		textLabel.Text = text
		billboard.Enabled = true
		pop.Scale = 0.4
		TweenService:Create(pop, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(seconds, function()
		if flashToken == token then
			shown = nil
			billboard.Enabled = false
		end
	end)
end

return Bubble
