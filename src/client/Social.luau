-- Vecinas, en el cliente (ver src/server/Social.luau): aquí solo se pide y se dibuja.
--   - Despensas: un montón de comida redondeada junto a cada hormiguero ocupado, que crece al llenarse.
--     Mantener el mordisco junto a una despensa ajena la asalta; junto a la ladrona de la tuya, la pilla.
--   - Asalto: alarma, guardianas que salen en tromba y persiguen a la ladrona, saco de botín a la
--     espalda que crece, lanzamiento por los aires con onomatopeya y cartel al cobrar.
--   - Regalo: botón sobre la vecina más cercana (tecla Config.Social.Gift.Key), paquete con lazo en
--     arco, confeti y números. Hilo de corazones al cruzarte con amigas.
--   - Dúo: lazo de energía entre las que muerden juntas y "DÚO xn" / "¡BANDA!" que crece.
--   - Saludo de antenas: chispas entre las antenas y un rato andando más rápido (Abilities.speedBoost).
--   - Panel "Vecinas" (botón lateral, tecla N): mapa del lobby en arco con los seis hormigueros.
-- Los efectos del mundo cuelgan de un modelo dentro de Workspace.Anthills: heredan su contorno de
-- tinta sin crear Highlight nuevos.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AntModel = require(ReplicatedStorage.Shared.AntModel)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Abilities = require(script.Parent.Abilities)
local AntAnim = require(script.Parent.AntAnim)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Social = {}

local S = Config.Social
local player = Players.LocalPlayer
local rng = Random.new()
local FLAT = Vector3.new(1, 0, 1)
local SEEN = 170 -- más lejos de la cámara no se dibujan efectos ajenos
local KEYBOARD = UserInputService.KeyboardEnabled
local GIFT_KEY = Enum.KeyCode[S.Gift.Key] or Enum.KeyCode.H

local PINK = Color3.fromRGB(255, 120, 170)
local SACK = Color3.fromRGB(196, 150, 96)
local SACK_DARK = Color3.fromRGB(150, 108, 64)
local LEAF = Color3.fromRGB(96, 186, 80)
local GUARD_BODY = AntModel.Body:Lerp(AntModel.Ink, 0.35)
local GUARD_DARK = AntModel.BodyDark:Lerp(AntModel.Ink, 0.45)
local CONFETTI = { Comic.Yellow, Comic.Red, Comic.Cyan, Comic.Green, PINK, Color3.fromRGB(170, 120, 255) }

local remote: RemoteEvent
local fxModel: Folder -- dentro de Workspace.Anthills: contorno de tinta gratis (carpeta: nadie la toma por hormiguero)
local friends: { [string]: number } = {}
local peace = false

-- Utilidades --------------------------------------------------------------------------------------

local function rootOf(who: Player?): BasePart?
	local character = who and who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function headOf(who: Player?): BasePart?
	local character = who and who.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	return if head and head:IsA("BasePart") then head else nil
end

local function near(position: Vector3, range: number?): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= (range or SEEN)
end

local function anthills(): Instance?
	return Workspace:FindFirstChild("Anthills")
end

local function ownerOf(hill: Instance?): Player?
	if not hill then
		return nil
	end
	local id = hill:GetAttribute("OwnerId")
	return if type(id) == "number" and id ~= 0 then Players:GetPlayerByUserId(id) else nil
end

local function hillOfUser(userId: number): Model?
	local hills = anthills()
	if not hills then
		return nil
	end
	for _, hill in hills:GetChildren() do
		if hill:IsA("Model") and hill:GetAttribute("OwnerId") == userId then
			return hill
		end
	end
	return nil
end

local function hillFrame(hill: Model): (Vector3, Vector3, Vector3, number)
	local center = hill:GetPivot().Position
	local inward = Vector3.new(0, center.Y, 0) - center
	inward = if inward.Magnitude > 0.01 then inward.Unit else Vector3.zAxis
	local scale = hill:GetAttribute("Scale")
	return center, inward, inward:Cross(Vector3.yAxis), if type(scale) == "number" then scale else 1
end

local function part(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, kind: string?, neon: boolean?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.CFrame = cframe
	if kind == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif kind == "rod" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Parent = parent
	return p
end

local function tween(object: Instance, seconds: number, goal, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function attachmentOn(target: BasePart, name: string): Attachment
	local found = target:FindFirstChild(name)
	if found and found:IsA("Attachment") then
		return found
	end
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = target
	return a
end

-- Pieza invisible con un emisor que se dispara una vez y se borra sola
local function emitAt(position: Vector3, count: number, colors: { Color3 }, speed: NumberRange, life: NumberRange, size: number, gravity: number?)
	local anchor = part(fxModel, Vector3.new(0.2, 0.2, 0.2), Comic.Ink, CFrame.new(position))
	anchor.Transparency = 1
	local keys = {}
	for i, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), color))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(keys)
	emitter.Speed = speed
	emitter.Lifetime = life
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -(gravity or 30), 0)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.4) })
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-260, 260)
	emitter.LightEmission = 0.4
	emitter.Drag = 1.5
	emitter.Parent = anchor
	emitter:Emit(count)
	Debris:AddItem(anchor, life.Max + 0.2)
end

-- Onda en el suelo: un disco de neón que se abre y se apaga
local function ring(position: Vector3, color: Color3, radius: number, seconds: number?)
	local disc = part(fxModel, Vector3.new(0.15, 1, 1), color, CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), "rod", true)
	disc.Transparency = 0.2
	local time = seconds or 0.45
	tween(disc, time, { Size = Vector3.new(0.15, radius * 2, radius * 2), Transparency = 1 })
	Debris:AddItem(disc, time + 0.05)
end

-- Texto de cómic que sigue a una pieza un momento
local function floatText(adornee: BasePart, text: string, color: Color3, size: number, seconds: number, lift: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 70)
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift or 4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = adornee
	gui.Parent = player:FindFirstChildOfClass("PlayerGui")
	local label = Comic.label(gui, text, Comic.Display, size, color)
	label.Size = UDim2.fromScale(1, 1)
	label.Rotation = rng:NextNumber(-8, 8)
	local stroke = Comic.ink(label, 3)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	tween(scale, 0.18, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(gui, seconds, { StudsOffsetWorldSpace = Vector3.new(0, (lift or 4) + 2, 0) }, Enum.EasingStyle.Sine)
	task.delay(seconds * 0.7, function()
		tween(label, seconds * 0.3, { TextTransparency = 1 })
		tween(stroke, seconds * 0.3, { Transparency = 1 })
	end)
	Debris:AddItem(gui, seconds + 0.1)
	return gui, label
end

local function alarmSound()
	for i = 0, 5 do
		task.delay(i * 0.13, Sfx.pop, if i % 2 == 0 then 1.85 else 1.35)
	end
end

-- Avisos compactos junto a la caja de comida (Hud.dock) ------------------------------------------

local pills: { [string]: TextLabel } = {}

local function pill(kind: string, text: string, color: Color3, seconds: number)
	local old = pills[kind]
	if old then
		old:Destroy()
	end
	local label = Comic.label(Hud.dock(), text, Comic.Display, 17, Comic.Ink)
	label.Name = "SocialPill"
	label.Size = UDim2.fromOffset(0, 24)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = color
	label.Rotation = rng:NextNumber(-2, 2)
	label.LayoutOrder = 50
	Comic.round(label, 6)
	Comic.ink(label, 2.5, true)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	Comic.punch(scale, 1.4)
	pills[kind] = label
	task.delay(seconds, function()
		if pills[kind] == label then
			pills[kind] = nil
		end
		if label.Parent then
			tween(scale, 0.2, { Scale = 0 })
			Debris:AddItem(label, 0.25)
		end
	end)
end

-- Flecha en el mundo ("Marcar camino" y aviso de asalto) -------------------------------------------

local arrow = { target = nil :: Model?, untilTime = 0, model = nil :: Model?, label = nil :: TextLabel? }

local function clearArrow()
	if arrow.model then
		arrow.model:Destroy()
	end
	arrow.model = nil
	arrow.target = nil
end

local function pointTo(hill: Model, seconds: number)
	clearArrow()
	local model = Instance.new("Model")
	model.Name = "SocialArrow"
	local shaft = part(model, Vector3.new(2.4, 0.45, 0.45), Comic.Yellow, CFrame.new(), "rod", true)
	shaft.Name = "Shaft"
	local left = part(model, Vector3.new(1.4, 0.45, 0.45), Comic.Yellow, CFrame.new(), "rod", true)
	left.Name = "Left"
	local right = part(model, Vector3.new(1.4, 0.45, 0.45), Comic.Yellow, CFrame.new(), "rod", true)
	right.Name = "Right"
	local tip = part(model, Vector3.new(0.6, 0.6, 0.6), Comic.Paper, CFrame.new(), "ball", true)
	tip.Name = "Tip"
	model.PrimaryPart = shaft
	model.Parent = fxModel

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(110, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = shaft
	gui.Parent = model
	local label = Comic.label(gui, "", Comic.Display, 20, Comic.Paper)
	label.Size = UDim2.fromScale(1, 1)
	Comic.ink(label, 2.5)

	arrow.model = model
	arrow.label = label
	arrow.target = hill
	arrow.untilTime = os.clock() + seconds
end

local function updateArrow()
	local model = arrow.model
	local hill = arrow.target
	if not model then
		return
	end
	local root = rootOf(player)
	if not hill or not hill.Parent or not root or os.clock() > arrow.untilTime then
		clearArrow()
		return
	end
	local goal = hill:GetPivot().Position
	local delta = (goal - root.Position) * FLAT
	local distance = delta.Magnitude
	if distance < 16 then
		Sfx.pop(1.4)
		clearArrow()
		return
	end
	local dir = delta.Unit
	local bob = math.sin(os.clock() * 5) * 0.35
	local base = root.Position + Vector3.new(0, 3.2 + bob, 0) + dir * 3.2
	local frame = CFrame.lookAt(base, base + dir)
	-- Los cilindros van a lo largo de X: se giran para que miren hacia delante (-Z del marco)
	local along = CFrame.Angles(0, math.rad(90), 0)
	model.Shaft.CFrame = frame * along
	model.Left.CFrame = frame * CFrame.new(-0.45, 0, -0.75) * CFrame.Angles(0, math.rad(90 - 40), 0)
	model.Right.CFrame = frame * CFrame.new(0.45, 0, -0.75) * CFrame.Angles(0, math.rad(90 + 40), 0)
	model.Tip.CFrame = frame * CFrame.new(0, 0, -1.25)
	if arrow.label then
		arrow.label.Text = math.floor(distance) .. " m"
	end
end

-- Despensas ---------------------------------------------------------------------------------------

-- Sitios de las piezas del montón (escala 1): anillo bajo, anillo medio, corona y cima
local PILE = {}
do
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		table.insert(PILE, Vector3.new(math.cos(a) * 1.7, 0.55, math.sin(a) * 1.7))
	end
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + 0.4
		table.insert(PILE, Vector3.new(math.cos(a) * 1.05, 1.35, math.sin(a) * 1.05))
	end
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 1.1
		table.insert(PILE, Vector3.new(math.cos(a) * 0.5, 2.05, math.sin(a) * 0.5))
	end
	table.insert(PILE, Vector3.new(0, 2.65, 0))
end

local pantries: { [Model]: any } = {}

local function pantryColor(hill: Model, i: number): Color3
	local colors = {}
	for k = 1, 3 do
		local c = hill:GetAttribute("PantryColor" .. k)
		if typeof(c) == "Color3" then
			table.insert(colors, c)
		end
	end
	if #colors == 0 then
		return Comic.Crumb
	end
	return colors[(i - 1) % #colors + 1]
end

local function buildPantry(hill: Model, spot: Vector3)
	local _, _, _, scale = hillFrame(hill)
	local model = Instance.new("Model")
	model.Name = "SocialPantry"
	-- Hoja de plato debajo del montón
	local plate = part(model, Vector3.new(6.4, 0.5, 5.2) * scale, LEAF, CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), "ball")
	plate.Name = "Plate"
	local vein = part(model, Vector3.new(5.6, 0.18, 0.25) * scale, LEAF:Lerp(Comic.Ink, 0.3), plate.CFrame * CFrame.new(0, 0.18 * scale, 0), "ball")
	vein.Name = "Vein"

	local light = Instance.new("PointLight")
	light.Color = Comic.Red
	light.Range = 16
	light.Brightness = 0
	light.Parent = plate

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.5 * scale, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 45
	gui.Adornee = plate
	gui.Parent = model
	local label = Comic.label(gui, "", Comic.Display, 20, Comic.Paper)
	label.Size = UDim2.fromScale(1, 1)
	Comic.ink(label, 2.5)

	model.Parent = hill -- dentro del hormiguero: hereda su contorno de tinta
	return {
		model = model,
		plate = plate,
		light = light,
		label = label,
		pieces = {},
		spot = spot,
		scale = scale,
		flag = nil :: Model?,
		alarmUntil = 0,
	}
end

local function setFlag(pantry, on: boolean)
	if on and not pantry.flag then
		local flag = Instance.new("Model")
		flag.Name = "PeaceFlag"
		local s = pantry.scale
		local foot = pantry.spot + Vector3.new(1.9 * s, 0, -1.2 * s)
		part(flag, Vector3.new(4.2 * s, 0.22, 0.22), Color3.fromRGB(132, 86, 52), CFrame.new(foot + Vector3.new(0, 2.1 * s, 0)) * CFrame.Angles(0, 0, math.rad(90)), "rod")
		part(flag, Vector3.new(1.6 * s, 1.1 * s, 0.18), Comic.Paper, CFrame.new(foot + Vector3.new(0.8 * s, 3.6 * s, 0)), "ball")
		flag.Parent = pantry.model
		pantry.flag = flag
	elseif not on and pantry.flag then
		pantry.flag:Destroy()
		pantry.flag = nil
	end
end

local function updatePantry(hill: Model, pantry)
	local fill = hill:GetAttribute("PantryFill")
	fill = if type(fill) == "number" then fill else 0
	local value = hill:GetAttribute("PantryValue")
	value = if type(value) == "number" then value else 0
	local count = if fill > 0 then math.clamp(math.ceil(fill * #PILE), 1, #PILE) else 0
	local s = pantry.scale
	-- Piezas nuevas: aparecen con un rebote; las que sobran se encogen
	while #pantry.pieces < count do
		local i = #pantry.pieces + 1
		local offset = PILE[i]
		local size = (1.15 + rng:NextNumber(-0.15, 0.25)) * s
		local cf = CFrame.new(pantry.spot + offset * s) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
		local piece = part(pantry.model, Vector3.new(0.1, 0.1, 0.1), pantryColor(hill, i), cf, "ball")
		piece.Name = "Food"
		tween(piece, 0.3, { Size = Vector3.new(size, size * 0.85, size) }, Enum.EasingStyle.Back)
		table.insert(pantry.pieces, piece)
	end
	while #pantry.pieces > count do
		local piece = table.remove(pantry.pieces)
		tween(piece, 0.2, { Size = Vector3.new(0.05, 0.05, 0.05) })
		Debris:AddItem(piece, 0.25)
	end
	local owner = ownerOf(hill)
	local mine = owner == player
	local open = hill:GetAttribute("PantryOpen") == true
	local isPeace = hill:GetAttribute("Peace") == true
	setFlag(pantry, isPeace)
	local head = if mine then "Tu despensa" elseif isPeace then "Pacífica" elseif not open then "Protegida" else "Despensa"
	pantry.label.Text = if value > 0 then head .. " · " .. Format.short(value) else head
	pantry.label.TextColor3 = if not mine and open and not isPeace and value > 0 then Comic.Yellow else Comic.Paper
end

local function refreshPantries()
	local hills = anthills()
	if not hills then
		return
	end
	local seen = {}
	for _, hill in hills:GetChildren() do
		if not hill:IsA("Model") or hill == fxModel then
			continue
		end
		local spot = hill:GetAttribute("PantryPos")
		if typeof(spot) ~= "Vector3" or hill:GetAttribute("OwnerId") == 0 then
			continue
		end
		local _, _, _, scale = hillFrame(hill)
		local pantry = pantries[hill]
		if pantry and ((pantry.spot - spot).Magnitude > 0.5 or math.abs(pantry.scale - scale) > 0.01 or not pantry.model.Parent) then
			pantry.model:Destroy()
			pantry = nil
		end
		if not pantry then
			pantry = buildPantry(hill, spot)
			pantries[hill] = pantry
		end
		seen[hill] = true
		updatePantry(hill, pantry)
	end
	for hill, pantry in pantries do
		if not seen[hill] then
			pantry.model:Destroy()
			pantries[hill] = nil
		end
	end
end

-- Luz roja que parpadea y piezas que tiemblan mientras suena la alarma
local function animatePantries(now: number)
	for _, pantry in pantries do
		if now < pantry.alarmUntil then
			pantry.light.Brightness = if math.floor(now * 6) % 2 == 0 then 3 else 0.3
		elseif pantry.light.Brightness ~= 0 then
			pantry.light.Brightness = 0
		end
	end
end

local function wiggle(pantry)
	for _, piece in pantry.pieces do
		local base = piece.CFrame
		tween(piece, 0.06, { CFrame = base * CFrame.new(rng:NextNumber(-0.25, 0.25), 0.3, rng:NextNumber(-0.25, 0.25)) })
		task.delay(0.07, function()
			if piece.Parent then
				tween(piece, 0.12, { CFrame = base }, Enum.EasingStyle.Back)
			end
		end)
	end
end

-- Migas que vuelan en arco de un punto a otro (no son físicas: se deslizan y se encogen)
local function crumbArc(from: Vector3, to: Vector3, color: Color3, count: number, seconds: number?)
	local time = seconds or 0.45
	for i = 1, count do
		task.delay((i - 1) * 0.025, function()
			local size = rng:NextNumber(0.35, 0.6)
			local crumb = part(fxModel, Vector3.new(size, size, size), color, CFrame.new(from), "ball")
			local lift = Vector3.new(rng:NextNumber(-1.5, 1.5), 4 + (to - from).Magnitude * 0.25, rng:NextNumber(-1.5, 1.5))
			local mid = (from + to) / 2 + lift
			local start = os.clock()
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local t = math.clamp((os.clock() - start) / time, 0, 1)
				if not crumb.Parent or t >= 1 then
					connection:Disconnect()
					crumb:Destroy()
					return
				end
				local a = from:Lerp(mid, t)
				local b = mid:Lerp(to, t)
				crumb.CFrame = CFrame.new(a:Lerp(b, t))
			end)
		end)
	end
end

-- Sacos de botín a la espalda ---------------------------------------------------------------------

local sacks: { [Player]: any } = {}

local function removeSack(who: Player)
	local sack = sacks[who]
	if sack then
		sack.model:Destroy()
		sacks[who] = nil
	end
end

local function updateSacks()
	for _, who in Players:GetPlayers() do
		local loot = who:GetAttribute("Loot")
		local fill = who:GetAttribute("LootFill")
		local root = rootOf(who)
		if type(loot) ~= "number" or loot <= 0 or not root then
			removeSack(who)
			continue
		end
		fill = if type(fill) == "number" then fill else 0.3
		local character = who.Character :: Model
		local scale = character:GetScale()
		local sack = sacks[who]
		if sack and sack.model.Parent ~= character then
			removeSack(who)
			sack = nil
		end
		if not sack then
			local model = Instance.new("Model")
			model.Name = "SocialSack"
			local bag = part(model, Vector3.new(1, 1, 1), SACK, root.CFrame, "ball")
			bag.Anchored = false
			bag.Massless = true
			bag.Name = "Bag"
			local knot = part(model, Vector3.new(0.5, 0.4, 0.5), SACK_DARK, root.CFrame, "ball")
			knot.Anchored = false
			knot.Massless = true
			local shine = part(model, Vector3.new(0.45, 0.45, 0.45), Comic.Yellow, root.CFrame, "ball", true)
			shine.Anchored = false
			shine.Massless = true
			local weld = Instance.new("Weld")
			weld.Part0 = root
			weld.Part1 = bag
			weld.Parent = bag
			local knotWeld = Instance.new("Weld")
			knotWeld.Part0 = bag
			knotWeld.Part1 = knot
			knotWeld.Parent = knot
			local shineWeld = Instance.new("Weld")
			shineWeld.Part0 = bag
			shineWeld.Part1 = shine
			shineWeld.Parent = shine
			model.Parent = character -- contorno de tinta del personaje
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Rate = 4
			sparkle.Lifetime = NumberRange.new(0.5, 0.9)
			sparkle.Speed = NumberRange.new(1, 3)
			sparkle.Size = NumberSequence.new(0.25, 0)
			sparkle.Color = ColorSequence.new(Comic.Yellow)
			sparkle.LightEmission = 0.8
			sparkle.Parent = shine
			sack = { model = model, bag = bag, knot = knot, shine = shine, weld = weld, knotWeld = knotWeld, shineWeld = shineWeld, size = 0 }
			sacks[who] = sack
		end
		local size = (0.9 + 1.5 * math.clamp(fill, 0, 1)) * scale
		if math.abs(size - sack.size) > 0.02 then
			local grew = size > sack.size + 0.05 and sack.size > 0
			sack.size = size
			sack.bag.Size = Vector3.new(size, size * 0.9, size)
			sack.weld.C0 = CFrame.new(0, 0.55 * scale + size * 0.3, 0.75 * scale + size * 0.4) * CFrame.Angles(0.3, 0, 0)
			sack.knotWeld.C0 = CFrame.new(0, size * 0.48, 0)
			sack.shineWeld.C0 = CFrame.new(size * 0.18, size * 0.5, -size * 0.1)
			if grew then
				-- Rebote al crecer
				sack.bag.Size = Vector3.new(size * 1.25, size * 1.1, size * 1.25)
				tween(sack.bag, 0.25, { Size = Vector3.new(size, size * 0.9, size) }, Enum.EasingStyle.Back)
			end
		end
	end
	for who in sacks do
		if not who.Parent then
			removeSack(who)
		end
	end
end

-- Guardianas --------------------------------------------------------------------------------------

local guardGroups: { [Model]: any } = {}

local function newGuard(k: number)
	local model = Instance.new("Model")
	model.Name = "Guard"
	local parts = {
		abdomen = part(model, Vector3.new(1, 0.9, 1.3) * k, GUARD_DARK, CFrame.new(), "ball"),
		thorax = part(model, Vector3.new(0.62, 0.58, 0.62) * k, GUARD_BODY, CFrame.new(), "ball"),
		head = part(model, Vector3.new(0.95, 0.85, 0.85) * k, GUARD_BODY, CFrame.new(), "ball"),
		helmet = part(model, Vector3.new(0.9, 0.4, 0.8) * k, Comic.Red, CFrame.new(), "ball"),
		jawL = part(model, Vector3.new(0.22, 0.2, 0.7) * k, AntModel.Ink, CFrame.new(), "ball"),
		jawR = part(model, Vector3.new(0.22, 0.2, 0.7) * k, AntModel.Ink, CFrame.new(), "ball"),
		eyeL = part(model, Vector3.new(0.22, 0.26, 0.1) * k, Comic.Paper, CFrame.new(), "ball"),
		eyeR = part(model, Vector3.new(0.22, 0.26, 0.1) * k, Comic.Paper, CFrame.new(), "ball"),
		leg1 = part(model, Vector3.new(2, 0.11, 0.11) * k, AntModel.Ink, CFrame.new(), "rod"),
		leg2 = part(model, Vector3.new(2, 0.11, 0.11) * k, AntModel.Ink, CFrame.new(), "rod"),
		leg3 = part(model, Vector3.new(2, 0.11, 0.11) * k, AntModel.Ink, CFrame.new(), "rod"),
	}
	model.Parent = fxModel
	return { model = model, parts = parts, k = k }
end

local function poseGuard(guard, cf: CFrame, phase: number, angry: boolean)
	local k = guard.k
	local p = guard.parts
	local bounce = math.abs(math.sin(phase)) * 0.25 * k
	local base = cf * CFrame.new(0, bounce, 0)
	p.abdomen.CFrame = base * CFrame.new(0, 0.05 * k, 0.72 * k)
	p.thorax.CFrame = base
	p.head.CFrame = base * CFrame.new(0, 0.1 * k, -0.62 * k)
	p.helmet.CFrame = base * CFrame.new(0, 0.42 * k, -0.6 * k)
	local snap = if angry then math.abs(math.sin(phase * 2)) * 0.5 else 0.15
	p.jawL.CFrame = base * CFrame.new(-0.25 * k, 0, -1.05 * k) * CFrame.Angles(0, snap, 0)
	p.jawR.CFrame = base * CFrame.new(0.25 * k, 0, -1.05 * k) * CFrame.Angles(0, -snap, 0)
	p.eyeL.CFrame = base * CFrame.new(-0.22 * k, 0.2 * k, -1.02 * k)
	p.eyeR.CFrame = base * CFrame.new(0.22 * k, 0.2 * k, -1.02 * k)
	local swing = math.sin(phase) * 0.35
	p.leg1.CFrame = base * CFrame.new(0, -0.2 * k, -0.25 * k) * CFrame.Angles(0, math.rad(-35) + swing, 0)
	p.leg2.CFrame = base * CFrame.new(0, -0.2 * k, 0) * CFrame.Angles(0, -swing, 0)
	p.leg3.CFrame = base * CFrame.new(0, -0.2 * k, 0.25 * k) * CFrame.Angles(0, math.rad(35) + swing, 0)
end

local function endGroup(hill: Model, reason: string?)
	local group = guardGroups[hill]
	if not group then
		return
	end
	group.returning = true
	group.chasing = false
	if reason == "lost" and #group.guards > 0 then
		local g = group.guards[1]
		if near(g.pos) then
			local anchor = g.guard.parts.head
			floatText(anchor, "¡GRRR!", Comic.Red, 30, 1.2, 3)
		end
	end
end

local function startGroup(hill: Model, thief: Player, count: number, speed: number, delay: number, chase: number)
	local old = guardGroups[hill]
	if old then
		for _, g in old.guards do
			g.guard.model:Destroy()
		end
	end
	local center, inward, side, scale = hillFrame(hill)
	local door = center + inward * 8.5 * scale
	local group = {
		hill = hill,
		thief = thief,
		speed = speed,
		startAt = os.clock() + delay,
		endAt = os.clock() + delay + chase + 1,
		door = door,
		inward = inward,
		chasing = true,
		returning = false,
		emerged = false,
		guards = {},
	}
	local k = 1.7
	for i = 1, count do
		local lane = (i - (count + 1) / 2) * 1.8
		table.insert(group.guards, {
			guard = newGuard(k),
			pos = door + side * lane,
			heading = inward,
			lane = lane,
			phase = rng:NextNumber(0, 6),
			pace = rng:NextNumber(0.96, 1.06),
			alpha = 0,
		})
	end
	guardGroups[hill] = group
end

local function updateGuards(dt: number)
	local now = os.clock()
	for hill, group in guardGroups do
		local thiefRoot = rootOf(group.thief)
		if now > group.endAt then
			group.returning = true
			group.chasing = false
		end
		local ground = group.door.Y
		local allHome = true
		for _, g in group.guards do
			local k = g.guard.k
			local lift = 0.1 + 0.4 * k
			if now < group.startAt then
				-- Aún dentro: escondidas bajo la puerta
				poseGuard(g.guard, CFrame.new(g.pos - Vector3.new(0, 6, 0)), 0, false)
				allHome = false
				continue
			end
			local target: Vector3
			local angry = false
			if group.chasing and thiefRoot then
				local toThief = (thiefRoot.Position - g.pos) * FLAT
				local spread = math.clamp(toThief.Magnitude / 10, 0, 1) * g.lane
				local side = if toThief.Magnitude > 0.1 then toThief.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
				target = thiefRoot.Position + side * spread
				angry = true
			else
				target = group.door
			end
			local delta = (target - g.pos) * FLAT
			local distance = delta.Magnitude
			local step = group.speed * g.pace * dt * (if group.returning then 0.7 else 1)
			if distance > 0.05 then
				g.heading = delta.Unit
				g.pos += delta.Unit * math.min(step, distance)
			end
			g.phase += dt * (8 + group.speed * 0.6)
			local pos = Vector3.new(g.pos.X, ground + lift, g.pos.Z)
			poseGuard(g.guard, CFrame.lookAt(pos, pos + g.heading), g.phase, angry)
			if group.returning then
				if distance > 1.5 then
					allHome = false
				end
			else
				allHome = false
			end
		end
		if not group.emerged and now >= group.startAt then
			group.emerged = true
			if near(group.door) then
				ring(group.door + Vector3.new(0, 0.3, 0), Comic.Red, 7)
				emitAt(group.door + Vector3.new(0, 1, 0), 18, { Comic.DirtLight, Comic.Dirt }, NumberRange.new(10, 20), NumberRange.new(0.4, 0.8), 0.7, 40)
				Fx.burst(group.door + Vector3.new(0, 2, 0), "¡A POR ELLA!", Comic.Red, 220)
				Sfx.bite(true)
			end
		end
		if group.returning and allHome then
			for _, g in group.guards do
				local model = g.guard.model
				for _, p in model:GetChildren() do
					if p:IsA("BasePart") then
						tween(p, 0.2, { Size = p.Size * 0.05 })
					end
				end
				Debris:AddItem(model, 0.25)
			end
			guardGroups[hill] = nil
		end
	end
end

-- Mareo de cómic: estrellitas que giran sobre la cabeza
local function dizzy(who: Player, seconds: number)
	local head = headOf(who)
	if not head then
		return
	end
	local stars = {}
	for i = 1, 3 do
		stars[i] = part(fxModel, Vector3.new(0.5, 0.5, 0.5), Comic.Yellow, head.CFrame, "ball", true)
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > seconds or not head.Parent then
			connection:Disconnect()
			for _, star in stars do
				star:Destroy()
			end
			return
		end
		for i, star in stars do
			local a = t * 7 + i / 3 * math.pi * 2
			star.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(a) * 1.3, 1.6 + math.sin(t * 9 + i) * 0.15, math.sin(a) * 1.3))
		end
	end)
end

-- Lanzamiento por los aires (solo en el cliente de la ladrona, que es quien mueve su personaje)
local function launchMe(dir: Vector3)
	local root = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	local flat = if typeof(dir) == "Vector3" and (dir * FLAT).Magnitude > 0.1 then (dir * FLAT).Unit else -root.CFrame.LookVector
	local velocity = flat * S.Guard.Launch + Vector3.new(0, S.Guard.LaunchUp, 0)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local attachment = attachmentOn(root, "SocialLaunch")
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.MaxForce = math.huge
	push.VectorVelocity = velocity
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.Parent = root
	Debris:AddItem(push, 0.22)
	root.AssemblyLinearVelocity = velocity
	-- Una vuelta de campana para que se vea el golpe
	root.AssemblyAngularVelocity = flat:Cross(Vector3.yAxis) * -8
	Fx.shake(0.75)
	Fx.speed(0.8)
end

-- Regalo ------------------------------------------------------------------------------------------

local function giftPackage(from: Vector3, to: Vector3, seconds: number, onArrive: () -> ())
	local model = Instance.new("Model")
	model.Name = "SocialGift"
	local paper = CONFETTI[rng:NextInteger(1, #CONFETTI)]
	local ribbon = if paper == Comic.Yellow then Comic.Red else Comic.Yellow
	local core = part(model, Vector3.new(1.5, 1.4, 1.5), paper, CFrame.new(from), "ball")
	local bandA = part(model, Vector3.new(1.58, 1.48, 0.32), ribbon, CFrame.new(from), "ball", true)
	local bandB = part(model, Vector3.new(0.32, 1.48, 1.58), ribbon, CFrame.new(from), "ball", true)
	local bowL = part(model, Vector3.new(0.6, 0.45, 0.35), ribbon, CFrame.new(from), "ball", true)
	local bowR = part(model, Vector3.new(0.6, 0.45, 0.35), ribbon, CFrame.new(from), "ball", true)
	model.PrimaryPart = core
	model.Parent = fxModel
	local trail0 = attachmentOn(core, "A0")
	trail0.Position = Vector3.new(0, 0.3, 0)
	local trail1 = attachmentOn(core, "A1")
	trail1.Position = Vector3.new(0, -0.3, 0)
	local trail = Instance.new("Trail")
	trail.Attachment0 = trail0
	trail.Attachment1 = trail1
	trail.Lifetime = 0.35
	trail.LightEmission = 0.8
	trail.Color = ColorSequence.new(ribbon, paper)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = core

	local mid = (from + to) / 2 + Vector3.new(0, 6 + (to - from).Magnitude * 0.3, 0)
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - start) / seconds, 0, 1)
		local a = from:Lerp(mid, t)
		local b = mid:Lerp(to, t)
		local spin = CFrame.Angles(0, t * 9, math.sin(t * 12) * 0.3)
		local cf = CFrame.new(a:Lerp(b, t)) * spin
		core.CFrame = cf
		bandA.CFrame = cf
		bandB.CFrame = cf
		bowL.CFrame = cf * CFrame.new(-0.28, 0.82, 0) * CFrame.Angles(0, 0, 0.5)
		bowR.CFrame = cf * CFrame.new(0.28, 0.82, 0) * CFrame.Angles(0, 0, -0.5)
		if t >= 1 then
			connection:Disconnect()
			model:Destroy()
			onArrive()
		end
	end)
end

local giftGui: BillboardGui
local giftButton: TextButton
local giftTarget: Player? = nil
local giftCooldowns: { [number]: number } = {} -- [UserId] = os.clock() hasta (lo que sabe el cliente)

local function buildGiftGui()
	giftGui = Instance.new("BillboardGui")
	giftGui.Name = "SocialGiftButton"
	giftGui.Size = UDim2.fromOffset(150, 44)
	giftGui.StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0)
	giftGui.AlwaysOnTop = true
	giftGui.LightInfluence = 0
	giftGui.Active = true
	giftGui.Enabled = false
	giftGui.ResetOnSpawn = false
	giftGui.Parent = player:WaitForChild("PlayerGui")
	local holder, face = Comic.button(giftGui, UDim2.fromOffset(140, 36), PINK, 3)
	holder.Position = UDim2.fromOffset(4, 2)
	Comic.round(face, 10)
	local shadow = holder:FindFirstChild("Shadow")
	if shadow and shadow:IsA("GuiObject") then
		Comic.round(shadow, 10)
	end
	local label = Comic.label(face, if KEYBOARD then "Regalar  [" .. S.Gift.Key .. "]" else "Regalar", Comic.Display, 22, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	giftButton = face
	face.MouseButton1Click:Connect(function()
		if giftTarget then
			remote:FireServer("Gift", giftTarget)
		end
	end)
	Comic.boil(holder, 2)
end

local function nearestNeighbor(range: number): Player?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local best, bestDistance = nil, range
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local r = rootOf(other)
			if r then
				local d = ((r.Position - root.Position) * FLAT).Magnitude
				if d < bestDistance then
					best, bestDistance = other, d
				end
			end
		end
	end
	return best
end

local function updateGiftButton()
	local target = if State.num("Carry") > 0 then nearestNeighbor(S.Gift.Range) else nil
	if target and (giftCooldowns[target.UserId] or 0) > os.clock() then
		target = nil
	end
	giftTarget = target
	local head = headOf(target)
	if target and head then
		giftGui.Adornee = head
		giftGui.Enabled = true
	else
		giftGui.Enabled = false
	end
end

local function onGift(giver: Player, receiver: Player, received: number, back: number, welcome: boolean, level: number)
	if giver == player then
		giftCooldowns[receiver.UserId] = os.clock() + S.Gift.Cooldown
	elseif receiver == player then
		giftCooldowns[giver.UserId] = os.clock() + S.Gift.Cooldown
	end
	local a, b = rootOf(giver), rootOf(receiver)
	if not a or not b then
		return
	end
	local involved = giver == player or receiver == player
	if not involved and not near(a.Position) then
		return
	end
	local from = a.Position + Vector3.new(0, 2, 0)
	if giver == player then
		Sfx.pop(1.1)
		AntAnim.cheer()
	end
	giftPackage(from, b.Position + Vector3.new(0, 2.5, 0), 0.75, function()
		local root = rootOf(receiver)
		local at = (if root then root.Position else b.Position) + Vector3.new(0, 2.5, 0)
		emitAt(at, 45, CONFETTI, NumberRange.new(14, 26), NumberRange.new(1, 1.7), 0.45, 25)
		ring(at - Vector3.new(0, 2, 0), PINK, 6)
		Fx.burst(at, if welcome then "¡BIENVENIDA!" else "¡REGALO!", PINK, 230)
		local head = headOf(receiver)
		if head then
			floatText(head, string.rep("♥", math.clamp(level, 1, 5)), Comic.Red, 30, 1.6, 6)
		end
		if receiver == player then
			if received > 0 then
				Fx.number(at, received, true, false)
			end
			Sfx.fanfare()
			Hud.punchFood()
			Bubble.flash(if welcome then "¡Regalo de bienvenida de " .. giver.DisplayName .. "! Vale el doble" else "¡" .. giver.DisplayName .. " me ha regalado comida!", 4)
		elseif giver == player then
			if back > 0 then
				Fx.number(from, back, false, false)
			end
			Sfx.deposit()
			Hud.punchFood()
			Bubble.flash("¡Amistad nivel " .. level .. " con " .. receiver.DisplayName .. "!", 4)
		end
	end)
end

-- Hilo de corazones al cruzarte con una amiga
local threadShown: { [number]: number } = {}

local function heartThread(other: Player, level: number)
	local a, b = rootOf(player), rootOf(other)
	if not a or not b then
		return
	end
	local a0 = attachmentOn(a, "SocialHeart")
	local a1 = attachmentOn(b, "SocialHeart")
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(PINK, Comic.Red)
	beam.LightEmission = 0.8
	beam.Width0 = 0.15
	beam.Width1 = 0.15
	beam.CurveSize0 = 3
	beam.CurveSize1 = -3
	beam.FaceCamera = true
	beam.Segments = 20
	beam.Transparency = NumberSequence.new(0.3)
	beam.Parent = fxModel
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 1.8 or not beam.Parent then
			connection:Disconnect()
			beam:Destroy()
			return
		end
		local w = 0.15 + math.sin(t * 10) * 0.08
		beam.Width0 = w
		beam.Width1 = w
		beam.Transparency = NumberSequence.new(math.clamp(0.3 + (t - 1.2) * 1.2, 0.3, 1))
	end)
	local mid = (a.Position + b.Position) / 2 + Vector3.new(0, 2.5, 0)
	emitAt(mid, 8 + level * 2, { PINK, Comic.Red, Comic.Paper }, NumberRange.new(2, 6), NumberRange.new(0.6, 1.1), 0.35, -4)
	Sfx.pop(1.6 + level * 0.06)
end

local function updateThreads()
	local root = rootOf(player)
	if not root then
		return
	end
	local now = os.clock()
	for _, other in Players:GetPlayers() do
		local level = friends[tostring(other.UserId)]
		if other ~= player and level and level > 0 then
			local r = rootOf(other)
			if r and ((r.Position - root.Position) * FLAT).Magnitude < 14 and now - (threadShown[other.UserId] or -math.huge) > 25 then
				threadShown[other.UserId] = now
				heartThread(other, level)
			end
		end
	end
end

-- Dúo ---------------------------------------------------------------------------------------------

local duo = { beams = {}, gui = nil :: BillboardGui?, label = nil :: TextLabel?, scale = nil :: UIScale?, at = 0, key = "" }

local function clearDuo()
	for _, beam in duo.beams do
		beam:Destroy()
	end
	duo.beams = {}
	if duo.gui then
		duo.gui:Destroy()
	end
	duo.gui = nil
	duo.label = nil
	duo.key = ""
end

local function onDuo(biter: Player, members: { Player }, count: number)
	if type(members) ~= "table" or #members < 2 then
		return
	end
	local mine = table.find(members, player) ~= nil
	local first = rootOf(members[1])
	if not mine and (not first or not near(first.Position, 120)) then
		return
	end
	local ids = {}
	for _, m in members do
		table.insert(ids, m.UserId)
	end
	table.sort(ids)
	local key = table.concat(ids, ",")
	if key ~= duo.key then
		clearDuo()
		duo.key = key
		-- Lazo de energía entre cada pareja seguida
		for i = 1, #members do
			local a = rootOf(members[i])
			local b = rootOf(members[i % #members + 1])
			if a and b and a ~= b and not (#members == 2 and i == 2) then
				local beam = Instance.new("Beam")
				beam.Attachment0 = attachmentOn(a, "SocialTie")
				beam.Attachment1 = attachmentOn(b, "SocialTie")
				beam.Color = ColorSequence.new(Comic.Cyan, Comic.Yellow)
				beam.LightEmission = 1
				beam.Width0 = 0.5
				beam.Width1 = 0.5
				beam.CurveSize0 = 2
				beam.CurveSize1 = 2
				beam.Segments = 24
				beam.FaceCamera = true
				beam.Parent = fxModel
				table.insert(duo.beams, beam)
			end
		end
		local head = headOf(biter)
		if head then
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(220, 60)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			gui.MaxDistance = 120
			gui.Adornee = head
			gui.Parent = player:FindFirstChildOfClass("PlayerGui")
			local label = Comic.label(gui, "", Comic.Display, 26, Comic.Cyan)
			label.Size = UDim2.fromScale(1, 1)
			label.Rotation = -6
			Comic.ink(label, 3)
			local scale = Instance.new("UIScale")
			scale.Parent = label
			duo.gui, duo.label, duo.scale = gui, label, scale
		end
	end
	duo.at = os.clock()
	if duo.gui then
		local head = headOf(biter)
		if head then
			duo.gui.Adornee = head
		end
	end
	if duo.label and duo.scale then
		local band = #members >= 3
		duo.label.Text = (if band then "¡BANDA! ×" else "DÚO ×") .. count
		duo.label.TextColor3 = if band then Comic.Yellow else Comic.Cyan
		duo.label.TextSize = math.min(24 + count * 2, 46)
		Comic.punch(duo.scale, 1.35)
	end
	if mine then
		Sfx.pop(math.min(1 + count * 0.05, 1.8))
	end
end

local function updateDuo(now: number)
	if duo.key == "" then
		return
	end
	local age = now - duo.at
	if age > S.Duo.Reset then
		clearDuo()
		return
	end
	local w = 0.35 + math.abs(math.sin(now * 9)) * 0.35
	for _, beam in duo.beams do
		beam.Width0 = w
		beam.Width1 = w
		beam.Transparency = NumberSequence.new(math.clamp((age - S.Duo.Reset + 1) , 0, 1))
	end
end

local function onDuoFinish(position: Vector3, members: { Player })
	if typeof(position) ~= "Vector3" or type(members) ~= "table" then
		return
	end
	local mine = table.find(members, player) ~= nil
	if not mine and not near(position) then
		return
	end
	local band = #members >= 3
	Fx.burst(position, if band then "¡CRUNCH EN BANDA!" else "¡CRUNCH EN DÚO!", Comic.Cyan, 260)
	ring(position - Vector3.new(0, 0.6, 0), Comic.Cyan, 10, 0.55)
	ring(position - Vector3.new(0, 0.6, 0), Comic.Yellow, 6, 0.4)
	emitAt(position, 30, { Comic.Cyan, Comic.Yellow, Comic.Paper }, NumberRange.new(12, 22), NumberRange.new(0.6, 1.1), 0.5, 30)
	if mine then
		Fx.shake(0.45)
		Sfx.fanfare()
	end
end

-- Saludo de antenas -------------------------------------------------------------------------------

local function tips(who: Player): { BasePart }
	local list = {}
	local character = who.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("BasePart") and child.Name == "AntennaTip" then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function onGreet(a: Player, b: Player)
	local ha, hb = headOf(a), headOf(b)
	if not ha or not hb then
		return
	end
	local mine = a == player or b == player
	local mid = (ha.Position + hb.Position) / 2 + Vector3.new(0, 1, 0)
	if not mine and not near(mid) then
		return
	end
	-- Chispas entre las puntas de las antenas más cercanas
	local ta, tb = tips(a), tips(b)
	for i = 1, math.min(#ta, #tb, 2) do
		local beam = Instance.new("Beam")
		beam.Attachment0 = attachmentOn(ta[i], "SocialSpark")
		beam.Attachment1 = attachmentOn(tb[#tb - i + 1], "SocialSpark")
		beam.Color = ColorSequence.new(Comic.Yellow, Comic.Cyan)
		beam.LightEmission = 1
		beam.Width0 = 0.3
		beam.Width1 = 0.3
		beam.CurveSize0 = 1.5
		beam.CurveSize1 = -1.5
		beam.FaceCamera = true
		beam.Parent = fxModel
		Debris:AddItem(beam, 0.6)
	end
	emitAt(mid, 26, { Comic.Yellow, Comic.Paper, Comic.Cyan }, NumberRange.new(6, 14), NumberRange.new(0.4, 0.8), 0.4, 10)
	Fx.burst(mid, "¡CHOC!", Comic.Yellow, 180)
	Sfx.pop(1.6)
	task.delay(0.1, Sfx.pop, 1.95)
	if mine then
		local other = if a == player then b else a
		AntAnim.cheer()
		Fx.speed(0.6)
		Bubble.flash("¡Hola, " .. other.DisplayName .. "! Ando más rápido un minuto", 4)
	end
end

-- Asalto: mensajes del servidor -------------------------------------------------------------------

local function onRaid(thief: Player, hill: Model, count: number, speed: number, delay: number, chase: number)
	if typeof(hill) ~= "Instance" then
		return
	end
	startGroup(hill, thief, count, speed, delay, chase)
	local pantry = pantries[hill]
	if pantry then
		pantry.alarmUntil = os.clock() + delay + chase
	end
	local top = hill:GetPivot().Position + Vector3.new(0, 10, 0)
	if near(top) then
		alarmSound()
		Fx.burst(top, "¡ALARMA!", Comic.Red, 240)
	end
	if ownerOf(hill) == player then
		pill("raid", "¡Te asaltan la despensa! Muerde a " .. thief.DisplayName, Comic.Red, 10)
		Bubble.flash("¡" .. thief.DisplayName .. " me asalta la despensa!", 4)
		pointTo(hill, 15)
		alarmSound()
		Social.alert(true)
	elseif thief == player then
		Bubble.flash("¡Guardianas! Corre a casa (" .. (if KEYBOARD then "Shift" else "botón de correr") .. ")", 4)
	end
end

local function onRaidBite(thief: Player, hill: Model, take: number, fill: number)
	local pantry = typeof(hill) == "Instance" and pantries[hill]
	local root = rootOf(thief)
	if not pantry or not root then
		return
	end
	local mine = thief == player
	if not mine and not near(pantry.spot) then
		return
	end
	local color = if #pantry.pieces > 0 then pantry.pieces[#pantry.pieces].Color else Comic.Crumb
	crumbArc(pantry.spot + Vector3.new(0, 2, 0), root.Position + Vector3.new(0, 2, 0), color, 5, 0.35)
	wiggle(pantry)
	if mine then
		AntAnim.bite()
		Sfx.bite(fill >= 0.99)
		Fx.number(pantry.spot + Vector3.new(0, 3, 0), take, fill >= 0.99, true)
		Fx.shake(0.12)
		if fill >= 0.99 then
			Bubble.flash("¡Saco lleno! A casa antes de que me pillen", 3)
		end
	else
		Sfx.bite(false)
	end
end

local function onCaught(thief: Player, hill: Model, by: string, amount: number, dir: Vector3)
	local root = rootOf(thief)
	local group = typeof(hill) == "Instance" and guardGroups[hill]
	if group then
		group.chasing = false
		group.returning = true
	end
	local mine = thief == player
	local owner = typeof(hill) == "Instance" and ownerOf(hill) or nil
	if root and (mine or owner == player or near(root.Position)) then
		local at = root.Position + Vector3.new(0, 2, 0)
		Fx.burst(at, if by == "owner" then "¡TE PILLÉ!" else "¡PATAPLÁN!", Comic.Yellow, 260)
		task.delay(0.25, function()
			Fx.burst(at + Vector3.new(rng:NextNumber(-2, 2), 2, 0), "¡PAF!", Comic.Red, 160)
		end)
		emitAt(at, 22, { Comic.Paper, Comic.DirtLight }, NumberRange.new(10, 20), NumberRange.new(0.3, 0.6), 0.8, 20)
		ring(root.Position - Vector3.new(0, 1.5, 0), Comic.Yellow, 7)
		Sfx.bite(true)
		dizzy(thief, 1.6)
		local pantry = typeof(hill) == "Instance" and pantries[hill]
		if pantry and by ~= "owner" then
			crumbArc(at, pantry.spot + Vector3.new(0, 1.5, 0), Comic.Crumb, 7, 0.55)
		end
	end
	if mine then
		launchMe(dir)
		Bubble.flash(if by == "owner" then "¡Me pilló la dueña! Suelto el botín" else "¡Me pillaron las guardianas! Suelto el botín", 4)
	elseif owner == player then
		if by == "owner" then
			local myRoot = rootOf(player)
			if myRoot and amount > 0 then
				Fx.number(myRoot.Position + Vector3.new(0, 3, 0), amount, true, true)
			end
			Sfx.fanfare()
			Hud.punchFood()
			pill("raid", "¡Pillaste a " .. thief.DisplayName .. "! +" .. Format.short(amount), Comic.Yellow, 6)
		else
			pill("raid", "Tus guardianas echaron a " .. thief.DisplayName, Comic.Green, 6)
		end
		clearArrow()
		Social.alert(false)
	end
end

local function onStolen(thief: Player, victim: Player?, amount: number, victimName: string)
	local root = rootOf(thief)
	local name = if victim then victim.DisplayName else (victimName ~= "" and victimName or "una vecina")
	local text = thief.DisplayName .. " le robó " .. Format.short(amount) .. " a " .. name
	if thief == player then
		pill("stolen", text, Comic.Yellow, 6)
		Sfx.fanfare()
		Hud.punchFood()
		Fx.shake(0.4)
		if root then
			Fx.number(root.Position + Vector3.new(0, 3, 0), amount, true, true)
			emitAt(root.Position + Vector3.new(0, 3, 0), 30, { Comic.Yellow, Color3.fromRGB(255, 184, 28) }, NumberRange.new(10, 20), NumberRange.new(0.6, 1.2), 0.5, 25)
		end
	elseif victim == player then
		pill("stolen", text, Comic.Paper, 6)
		clearArrow()
		Social.alert(false)
	end
	if root and (thief == player or near(root.Position)) then
		Fx.burst(root.Position + Vector3.new(0, 2.5, 0), "¡BOTÍN!", Comic.Yellow, 220)
	end
end

local function onCollect(spot: Vector3, amount: number)
	local root = rootOf(player)
	if typeof(spot) ~= "Vector3" or not root then
		return
	end
	local color = Comic.Crumb
	for hill, pantry in pantries do
		if ownerOf(hill) == player and #pantry.pieces > 0 then
			color = pantry.pieces[1].Color
		end
	end
	crumbArc(spot + Vector3.new(0, 2, 0), root.Position + Vector3.new(0, 1.5, 0), color, 10, 0.4)
	Fx.number(spot + Vector3.new(0, 3, 0), amount, false, false)
	Fx.burst(spot + Vector3.new(0, 1, 0), "¡DESPENSA!\n+" .. Format.short(amount), Comic.Green, 200)
	Sfx.deposit()
	Hud.punchFood()
end

-- Morder despensas y ladronas (mismo gesto que morder comida) ------------------------------------

local holding = false
local lastTry = 0
local raidHintShown = false

local function isBiteInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.ButtonX
end

local function nearestPantry(root: BasePart): Model?
	local best, bestDistance = nil, math.huge
	for hill, pantry in pantries do
		if ownerOf(hill) ~= player then
			local d = ((pantry.spot - root.Position) * FLAT).Magnitude
			if d <= S.Raid.Reach * math.max(1, pantry.scale) and d < bestDistance then
				best, bestDistance = hill, d
			end
		end
	end
	return best
end

local function thiefNearMe(root: BasePart): Player?
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("LootFrom") == player.UserId and (tonumber(other:GetAttribute("Loot")) or 0) > 0 then
			local r = rootOf(other)
			if r and ((r.Position - root.Position) * FLAT).Magnitude <= S.Raid.CatchReach then
				return other
			end
		end
	end
	return nil
end

local function tryBite()
	local root = rootOf(player)
	if not root then
		return
	end
	local now = os.clock()
	if now - lastTry < math.max(State.stats().biteCooldown, 0.15) then
		return
	end
	local thief = thiefNearMe(root)
	if thief then
		lastTry = now
		remote:FireServer("Catch", thief)
		AntAnim.bite()
		return
	end
	local hill = nearestPantry(root)
	if hill then
		lastTry = now
		remote:FireServer("Raid", hill)
	end
end

local function raidHint()
	if raidHintShown or peace then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	local hill = nearestPantry(root)
	if hill and hill:GetAttribute("PantryOpen") == true and (tonumber(hill:GetAttribute("PantryValue")) or 0) > 0 then
		raidHintShown = true
		Bubble.flash("Una despensa ajena... Muérdela y llévate botín. ¡Ojo con las guardianas!", 4)
	end
end

-- Panel "Vecinas" ---------------------------------------------------------------------------------

local panel = { gui = nil :: ScreenGui?, holder = nil :: Frame?, open = false, nodes = {}, selected = nil :: Model?, side = nil :: any }
local MAP_W, MAP_H = 420, 250
local MAP_K = 1.45

local function mapPoint(position: Vector3): UDim2
	return UDim2.fromOffset(MAP_W / 2 + position.X * MAP_K, 34 + position.Z * MAP_K)
end

local function hearts(level: number): string
	local full = math.clamp(level, 0, S.Friend.Max)
	return string.rep("♥", full) .. string.rep("♡", S.Friend.Max - full)
end

local peaceButton: TextButton
local peaceText: TextLabel
local scoreText: TextLabel
local actionChip: Frame
local actionText: TextLabel

local function paintPeace()
	if peaceButton then
		peaceButton.BackgroundColor3 = if peace then Comic.Paper else Comic.DirtLight
		peaceText.Text = if peace then "Modo pacífico: SÍ" else "Modo pacífico: NO"
	end
end

local function buildNode(parent: Frame, hill: Model)
	local node = Instance.new("TextButton")
	node.Name = hill.Name
	node.AutoButtonColor = false
	node.Text = ""
	node.BackgroundTransparency = 1
	node.Size = UDim2.fromOffset(86, 92)
	node.AnchorPoint = Vector2.new(0.5, 0.5)
	node.Parent = parent

	local mound = Comic.frame(node, Comic.DirtLight)
	mound.Size = UDim2.fromOffset(52, 52)
	mound.AnchorPoint = Vector2.new(0.5, 0)
	mound.Position = UDim2.new(0.5, 0, 0, 14)
	Comic.round(mound)
	local ring = Comic.ink(mound, 3, true)

	local face = Instance.new("ImageLabel")
	face.BackgroundTransparency = 1
	face.Size = UDim2.fromScale(0.92, 0.92)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Parent = mound
	Comic.round(face)

	local heartsLabel = Comic.label(node, "", Comic.Body, 13, Comic.Red)
	heartsLabel.Size = UDim2.new(1, 0, 0, 14)
	heartsLabel.Position = UDim2.fromOffset(0, 0)

	local name = Comic.label(node, "", Comic.Display, 15, Comic.Ink)
	name.Size = UDim2.new(1, 8, 0, 16)
	name.Position = UDim2.new(0, -4, 0, 66)
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local layer = Comic.label(node, "", Comic.Body, 12, Comic.DirtDark)
	layer.Size = UDim2.new(1, 0, 0, 12)
	layer.Position = UDim2.fromOffset(0, 80)

	-- Montoncito de la despensa: bolitas que aparecen según lo llena que está
	local pile = Comic.frame(node)
	pile.Size = UDim2.fromOffset(24, 20)
	pile.Position = UDim2.new(0.5, 22, 0, 46)
	local dots = {}
	local places = { { 2, 12 }, { 10, 12 }, { 18, 12 }, { 6, 5 }, { 14, 5 } }
	for i, at in places do
		local dot = Comic.frame(pile, Comic.Crumb)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.Position = UDim2.fromOffset(at[1], at[2])
		Comic.round(dot)
		Comic.ink(dot, 1.5, true)
		dots[i] = dot
	end

	local flag = Comic.frame(node)
	flag.Size = UDim2.fromOffset(16, 22)
	flag.Position = UDim2.new(0.5, -36, 0, 12)
	local pole = Comic.frame(flag, Comic.DirtDark)
	pole.Size = UDim2.fromOffset(2, 22)
	local cloth = Comic.frame(flag, Comic.Paper)
	cloth.Size = UDim2.fromOffset(12, 9)
	cloth.Position = UDim2.fromOffset(2, 1)
	Comic.ink(cloth, 1.5, true)

	local scale = Instance.new("UIScale")
	scale.Parent = node
	node.MouseButton1Click:Connect(function()
		panel.selected = hill
		Comic.punch(scale, 1.2)
		Sfx.pop(1.2)
		Social.refreshPanel()
	end)

	return { node = node, mound = mound, ring = ring, face = face, hearts = heartsLabel, name = name, layer = layer, dots = dots, flag = flag, owner = 0 }
end

local function buildPanel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SocialPanel"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")

	-- A la derecha y compacto: el juego sigue a la vista
	local holder, face = Comic.box(gui, UDim2.fromOffset(MAP_W + 24, MAP_H + 128), Comic.Paper, 6)
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -16, 0.5, 0)
	holder.Rotation = 1
	-- En táctil no encoge por debajo de 44 px lo que se pulsa (X y zonas de toque de 44)
	local fit = Comic.autoScale(holder, nil, 44)
	Comic.halftone(face, Comic.DirtLight, 90)

	-- Celular: así puede no caber en alto; el mapa y lo de abajo van en una lista que se desplaza.
	-- Solo en celular: el jardín asoma por encima del mapa y en PC no debe recortarse.
	local area: GuiObject = face
	local top = 36
	if Hud.compact() then
		local list = Instance.new("ScrollingFrame")
		list.BackgroundTransparency = 1
		list.BorderSizePixel = 0
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.new(1, 0, 1, -top)
		list.CanvasSize = UDim2.fromOffset(0, MAP_H + 92)
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = Comic.Ink
		list.ElasticBehavior = Enum.ElasticBehavior.Never
		list.Parent = face
		area = list
		top = 0
		local function fitHeight()
			local camera = Workspace.CurrentCamera
			if camera then
				-- Esta pantalla ya queda bajo la barra de Roblox: el alto útil es el visor menos ella
				local room = camera.ViewportSize.Y - Comic.topInset() - 16
				holder.Size = UDim2.fromOffset(MAP_W + 24, math.min(MAP_H + 128, room / fit.Scale))
			end
		end
		fitHeight()
		fit:GetPropertyChangedSignal("Scale"):Connect(fitHeight)
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHeight)
	end

	local title = Comic.label(face, "VECINAS", Comic.Display, 30, Comic.Red)
	title.Size = UDim2.fromOffset(200, 34)
	title.Position = UDim2.fromOffset(14, 4)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -3
	Comic.ink(title, 2.5)

	local close = Comic.label(face, if KEYBOARD then "N para cerrar" else "", Comic.Body, 13, Comic.DirtDark)
	close.Size = UDim2.fromOffset(120, 20)
	close.Position = UDim2.new(1, -130, 0, 10)
	close.TextXAlignment = Enum.TextXAlignment.Right
	local closeButton = Instance.new("TextButton")
	closeButton.Text = "×"
	closeButton.FontFace = Comic.Display
	closeButton.TextSize = 28
	closeButton.TextColor3 = Comic.Ink
	closeButton.BackgroundTransparency = 1
	-- Caja de 44 con el mismo centro que la de 32: la × se ve igual y se acierta con el dedo
	closeButton.Size = UDim2.fromOffset(44, 44)
	closeButton.Position = UDim2.new(1, -40, 0, -4)
	closeButton.Parent = face
	closeButton.MouseButton1Click:Connect(function()
		Social.toggle()
	end)

	-- El mapa: el jardín redondo arriba, el camino hacia las zonas y los hormigueros en arco
	local map = Comic.frame(area)
	map.Size = UDim2.fromOffset(MAP_W, MAP_H)
	map.Position = UDim2.fromOffset(12, top)
	map.ClipsDescendants = false
	local garden = Comic.frame(map, Comic.Green)
	garden.AnchorPoint = Vector2.new(0.5, 0.5)
	garden.Size = UDim2.fromOffset(Config.Map.HillArc * MAP_K * 1.2, Config.Map.HillArc * MAP_K * 1.2)
	garden.Position = mapPoint(Vector3.zero)
	garden.BackgroundTransparency = 0.55
	Comic.round(garden)
	Comic.ink(garden, 2, true)
	local road = Comic.frame(map, Comic.DirtLight)
	road.AnchorPoint = Vector2.new(0.5, 1)
	road.Size = UDim2.fromOffset(26, 40)
	road.Position = mapPoint(Vector3.zero)
	road.BackgroundTransparency = 0.2
	local roadText = Comic.label(map, "zonas ↑", Comic.Body, 12, Comic.DirtDark)
	roadText.Size = UDim2.fromOffset(60, 14)
	roadText.AnchorPoint = Vector2.new(0.5, 1)
	roadText.Position = mapPoint(Vector3.zero) - UDim2.fromOffset(0, 40)

	-- Acción del hormiguero tocado
	actionChip = Comic.frame(area, Comic.Yellow)
	actionChip.Size = UDim2.fromOffset(MAP_W - 20, 32)
	actionChip.Position = UDim2.fromOffset(22, top + MAP_H - 6)
	actionChip.Visible = false
	Comic.round(actionChip, 8)
	Comic.ink(actionChip, 2.5, true)
	actionText = Comic.label(actionChip, "", Comic.Display, 18, Comic.Ink)
	actionText.Size = UDim2.new(1, -150, 1, 0)
	actionText.Position = UDim2.fromOffset(10, 0)
	actionText.TextXAlignment = Enum.TextXAlignment.Left
	actionText.TextTruncate = Enum.TextTruncate.AtEnd
	local markHolder, markFace = Comic.button(actionChip, UDim2.fromOffset(132, 24), Comic.Paper, 2)
	markHolder.Position = UDim2.new(1, -140, 0, 3)
	local markLabel = Comic.label(markFace, "Marcar camino", Comic.Display, 17, Comic.Ink)
	markLabel.Size = UDim2.fromScale(1, 1)
	local function mark()
		local hill = panel.selected
		if not hill then
			return
		end
		if arrow.target == hill then
			clearArrow()
			markLabel.Text = "Marcar camino"
		else
			pointTo(hill, 90)
			markLabel.Text = "Quitar flecha"
			Sfx.pop(1.3)
		end
	end
	markFace.MouseButton1Click:Connect(mark)
	Comic.touchPad(markHolder, markFace, 44, mark) -- se ve de 24: el dedo necesita 44
	panel.markLabel = markLabel

	-- Abajo: modo pacífico y marcador de la sesión
	local bottom = Comic.frame(area)
	bottom.Size = UDim2.new(1, -24, 0, 70)
	bottom.Position = UDim2.new(0, 12, 1, -78)
	local peaceHolder, peaceFace = Comic.button(bottom, UDim2.fromOffset(184, 34), Comic.DirtLight, 3)
	peaceHolder.Position = UDim2.fromOffset(0, 0)
	Comic.round(peaceFace, 17)
	local peaceShadow = peaceHolder:FindFirstChild("Shadow")
	if peaceShadow and peaceShadow:IsA("GuiObject") then
		Comic.round(peaceShadow, 17)
	end
	peaceButton = peaceFace
	peaceText = Comic.label(peaceFace, "", Comic.Display, 18, Comic.Ink)
	peaceText.Size = UDim2.fromScale(1, 1)
	local function togglePeace()
		remote:FireServer("Peace", not peace)
		Sfx.pop(1.1)
	end
	peaceFace.MouseButton1Click:Connect(togglePeace)
	Comic.touchPad(peaceHolder, peaceFace, 44, togglePeace) -- se ve de 34: el dedo necesita 44
	local peaceHelp = Comic.label(bottom, "Ni asaltas ni te asaltan; tu despensa se llena a la mitad", Comic.Body, 12, Comic.DirtDark)
	peaceHelp.Size = UDim2.new(1, -196, 0, 34)
	peaceHelp.Position = UDim2.fromOffset(196, 0)
	peaceHelp.TextWrapped = true
	peaceHelp.TextXAlignment = Enum.TextXAlignment.Left
	scoreText = Comic.label(bottom, "", Comic.Display, 17, Comic.Ink)
	scoreText.Size = UDim2.new(1, 0, 0, 26)
	scoreText.Position = UDim2.fromOffset(0, 40)
	scoreText.TextXAlignment = Enum.TextXAlignment.Left

	panel.gui = gui
	panel.holder = holder
	panel.map = map
	paintPeace()
end

function Social.refreshPanel()
	if not panel.open or not panel.map then
		return
	end
	local hills = anthills()
	if not hills then
		return
	end
	local seen = {}
	for _, hill in hills:GetChildren() do
		if not hill:IsA("Model") or not hill.Name:match("^Anthill") then
			continue
		end
		seen[hill] = true
		local node = panel.nodes[hill]
		if not node then
			node = buildNode(panel.map, hill)
			panel.nodes[hill] = node
		end
		node.node.Position = mapPoint(hill:GetPivot().Position)
		local owner = ownerOf(hill)
		if owner then
			if node.owner ~= owner.UserId then
				node.owner = owner.UserId
				node.face.Image = "rbxthumb://type=AvatarHeadShot&id=" .. owner.UserId .. "&w=48&h=48"
			end
			local me = owner == player
			node.name.Text = if me then "Tú" else owner.DisplayName
			node.layer.Text = "Capa " .. (tonumber(owner:GetAttribute("Depth")) or 1)
			node.mound.BackgroundColor3 = if me then Comic.Yellow else Comic.DirtLight
			node.ring.Color = if panel.selected == hill then Comic.Red else Comic.Ink
			node.ring.Thickness = if panel.selected == hill then 4 else 3
			node.hearts.Text = if me then "" else hearts(friends[tostring(owner.UserId)] or 0)
			local fill = tonumber(hill:GetAttribute("PantryFill")) or 0
			local shown = if fill > 0 then math.max(1, math.ceil(fill * 5)) else 0
			local tint = hill:GetAttribute("PantryColor1")
			for i, dot in node.dots do
				dot.Visible = i <= shown
				dot.BackgroundColor3 = if typeof(tint) == "Color3" then tint else Comic.Crumb
			end
			node.flag.Visible = hill:GetAttribute("Peace") == true
			node.face.Visible = true
		else
			node.owner = 0
			node.face.Image = ""
			node.face.Visible = false
			node.name.Text = "Libre"
			node.layer.Text = ""
			node.hearts.Text = ""
			node.mound.BackgroundColor3 = Comic.Paper
			node.ring.Color = Comic.Ink
			node.ring.Thickness = 2
			for _, dot in node.dots do
				dot.Visible = false
			end
			node.flag.Visible = false
		end
	end
	for hill, node in panel.nodes do
		if not seen[hill] then
			node.node:Destroy()
			panel.nodes[hill] = nil
		end
	end

	local selected = panel.selected
	local selectedOwner = ownerOf(selected)
	if selected and selected.Parent and selectedOwner then
		actionChip.Visible = true
		local value = tonumber(selected:GetAttribute("PantryValue")) or 0
		local status = if selected:GetAttribute("Peace") == true then "pacífica"
			elseif selectedOwner == player then "tu casa"
			elseif selected:GetAttribute("PantryOpen") ~= true then "protegida"
			else "despensa " .. Format.short(value)
		actionText.Text = (if selectedOwner == player then "Tu hormiguero" else selectedOwner.DisplayName) .. " · " .. status
		panel.markLabel.Text = if arrow.target == selected then "Quitar flecha" else "Marcar camino"
	else
		actionChip.Visible = false
	end

	local bonus = tonumber(player:GetAttribute("SocialBonus")) or 0
	scoreText.Text = "Robado " .. Format.short(tonumber(player:GetAttribute("SocialStolen")) or 0)
		.. "  ·  Regalado " .. Format.short(tonumber(player:GetAttribute("SocialGifted")) or 0)
		.. "  ·  Te pillaron " .. (tonumber(player:GetAttribute("SocialCaught")) or 0)
		.. (if bonus > 0 then "  ·  Amistad +" .. math.floor(bonus * 100 + 0.5) .. " %" else "")
	paintPeace()
end

function Social.isOpen(): boolean
	return panel.open == true
end

function Social.toggle()
	if not panel.gui then
		return
	end
	panel.open = not panel.open
	panel.gui.Enabled = panel.open
	if panel.open then
		Social.alert(false)
		Social.refreshPanel()
		if panel.holder then
			panel.holder.Position = UDim2.new(1, 40, 0.5, 0)
			tween(panel.holder, 0.22, { Position = UDim2.new(1, -16, 0.5, 0) }, Enum.EasingStyle.Back)
		end
	end
	Sfx.pop(if panel.open then 1.15 else 0.9)
end

function Social.alert(on: boolean)
	if panel.side then
		panel.side.setBadge(on)
	end
end

-- Arranque ----------------------------------------------------------------------------------------

local function onEvent(kind: string, a: any, b: any, c: any, d: any, e: any, f: any)
	if kind == "Raid" then
		onRaid(a, b, c, d, e, f)
	elseif kind == "RaidBite" then
		onRaidBite(a, b, c, d)
	elseif kind == "GuardsEnd" then
		if typeof(a) == "Instance" then
			endGroup(a, b)
		end
	elseif kind == "Caught" then
		onCaught(a, b, c, d, e)
	elseif kind == "Stolen" then
		onStolen(a, b, c, d)
	elseif kind == "Collect" then
		onCollect(a, b)
	elseif kind == "Gift" then
		if typeof(a) == "Instance" and typeof(b) == "Instance" then
			onGift(a, b, tonumber(c) or 0, tonumber(d) or 0, e == true, tonumber(f) or 1)
		end
	elseif kind == "Welcome" then
		if typeof(a) == "Instance" and a ~= player then
			pill("welcome", "Ha llegado " .. a.DisplayName .. " — llévale un regalo", PINK, 9)
			Bubble.flash("¡Ha llegado " .. a.DisplayName .. "! Un regalo de bienvenida vale el doble", 4)
			Sfx.pop(1.5)
			Social.alert(true)
		end
	elseif kind == "Duo" then
		onDuo(a, b, tonumber(c) or 1)
	elseif kind == "DuoFinish" then
		onDuoFinish(a, b)
	elseif kind == "Greet" then
		if typeof(a) == "Instance" and typeof(b) == "Instance" then
			onGreet(a, b)
		end
	elseif kind == "Friends" then
		friends = if type(a) == "table" then a else {}
		Social.refreshPanel()
	elseif kind == "Peace" then
		peace = a == true
		paintPeace()
	end
end

function Social.start(remotes: Folder)
	local found = remotes:WaitForChild("Social", 30)
	if not found then
		return
	end
	remote = found :: RemoteEvent
	local hills = Workspace:WaitForChild("Anthills", 60)
	if not hills then
		return
	end
	fxModel = Instance.new("Folder")
	fxModel.Name = "SocialFx"
	fxModel.Parent = hills
	peace = player:GetAttribute("Peace") == true
	player:GetAttributeChangedSignal("Peace"):Connect(function()
		peace = player:GetAttribute("Peace") == true
		paintPeace()
	end)

	buildGiftGui()
	buildPanel()
	panel.side = Hud.addSideButton("Vecinas", "N", Comic.Cyan, Social.toggle)

	remote.OnClientEvent:Connect(onEvent)
	remote:FireServer("Sync")

	-- Saludo de antenas: más velocidad al andar un rato (encima de lo que pongan otros módulos)
	task.delay(2, function()
		local base = Abilities.speedBoost
		Abilities.speedBoost = function(): number
			local boost = base()
			local untilTime = player:GetAttribute("GreetSpeedUntil")
			if type(untilTime) == "number" and State.now() < untilTime then
				boost *= S.Greet.SpeedMult
			end
			return boost
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if isBiteInput(input) and not processed then
			holding = true
		end
		if processed then
			return
		end
		if input.KeyCode == GIFT_KEY and giftTarget then
			remote:FireServer("Gift", giftTarget)
		elseif input.KeyCode == Enum.KeyCode.N then
			Social.toggle()
		elseif input.KeyCode == Enum.KeyCode.Escape and panel.open then
			Social.toggle()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if isBiteInput(input) then
			holding = false
		end
	end)

	Players.PlayerRemoving:Connect(function(who)
		removeSack(who)
		giftCooldowns[who.UserId] = nil
		threadShown[who.UserId] = nil
	end)

	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		updateGuards(dt)
		animatePantries(now)
		updateArrow()
		updateDuo(now)
		if holding then
			tryBite()
		end
	end)

	task.spawn(function()
		local ticks = 0
		while true do
			task.wait(0.15)
			ticks += 1
			updateSacks()
			updateGiftButton()
			if ticks % 2 == 0 then
				refreshPantries()
				raidHint()
			end
			if ticks % 3 == 0 then
				updateThreads()
				if panel.open then
					Social.refreshPanel()
				end
			end
		end
	end)
end

return Social
