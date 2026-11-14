-- Vestidor: un panel pegado al borde derecho, para que tu propia hormiga (a la izquierda) sea
-- el probador. Cuatro baldas, cada una con su forma: botes de pintura para el color, etiquetas
-- colgadas de una barra para los sombreros, cintas pintadas para las estelas y perchas con la
-- silueta de cada traje.
-- Se compra con comida una vez y es para siempre; ponérselo luego es gratis.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Outfits = require(ReplicatedStorage.Shared.Outfits)
local Comic = require(script.Parent.Comic)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Wardrobe = {}

local W = 400 -- ancho de diseño del panel
local MARGIN = 16 -- separación con los bordes de la pantalla, en píxeles
local HEADER = 96
local PAD = 22
local INNER = W - PAD * 2 - 10 -- deja sitio a la barra de desplazamiento
local MANILA = Color3.fromRGB(240, 214, 160)
local DIM = Color3.fromRGB(226, 216, 196)
local ROD = Color3.fromRGB(176, 180, 190)

local gui: ScreenGui
local panel: Frame
local fit: UIScale
local foodLabel: TextLabel
local remotes
local isOpen = false
local views = {} -- { kind, def, base, stroke, chip, scale, holder, dimmed }

-- Qué lleva puesto, con el valor por defecto mientras los atributos aún no han llegado
local ATTRIBUTE = { skin = "Skin", hat = "Hat", trail = "Trail", outfit = "Outfit" }
local LISTS = { skin = Config.Skins, hat = Config.Hats, trail = Config.Trails, outfit = Outfits.list }
local coverNote: TextLabel? -- "El traje lo tapa", junto al rótulo de sombreros

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

local function equipped(kind: string): string
	local value = Players.LocalPlayer:GetAttribute(ATTRIBUTE[kind])
	if type(value) == "string" and value ~= "" then
		return value
	end
	return LISTS[kind][1].id
end

-- Estado de una prenda: "worn", "owned", "affordable", "expensive" o "locked"
local function stateOf(kind: string, def): string
	if def.pass and not State.flag("P_" .. def.pass) then
		return "locked"
	end
	if equipped(kind) == def.id then
		return "worn"
	end
	if def.pass or def.cost <= 0 or State.owns(def.id) then
		return "owned"
	end
	return if State.num("Food") >= def.cost then "affordable" else "expensive"
end

-- Etiqueta pequeña de estado: precio, "Puesto" o "Solo VIP"
local function chip(parent: Instance): TextLabel
	local label = Comic.label(parent, "", Comic.Display, 18, Comic.Ink)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(0, 22)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = Comic.Yellow
	label.ZIndex = 8
	Comic.ink(label, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 7)
	pad.PaddingRight = UDim.new(0, 7)
	pad.Parent = label
	return label
end

local function shake(holder: GuiObject)
	local base = holder.Position
	task.spawn(function()
		for _, dx in { 7, -7, 5, -4, 2, 0 } do
			holder.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		holder.Position = base
	end)
end

local function onClick(view)
	local state = stateOf(view.kind, view.def)
	if state == "locked" or state == "expensive" then
		shake(view.holder)
		Sfx.pop(0.7)
		return
	end
	Comic.punch(view.scale, 1.22)
	if state == "worn" then
		Sfx.pop(1.2)
		return
	end
	Sfx.pop(if state == "affordable" then 1.45 else 1.2)
	if remotes and remotes:FindFirstChild("Wear") then
		remotes.Wear:FireServer(view.kind, view.def.id)
	end
end

local function register(kind: string, def, holder: GuiObject, base: GuiButton, stroke: UIStroke, chipLabel: TextLabel)
	local scale = Instance.new("UIScale")
	scale.Parent = base
	local view = { kind = kind, def = def, holder = holder, base = base, stroke = stroke, chip = chipLabel, scale = scale }
	base.MouseButton1Click:Connect(function()
		onClick(view)
	end)
	table.insert(views, view)
	return view
end

-- Rótulo de cada balda, rotulado a mano
local function heading(parent: Instance, text: string, y: number, rotation: number)
	local label = Comic.label(parent, text, Comic.Display, 30, Comic.Red)
	at(label, PAD, y, 220, 32)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Rotation = rotation
	Comic.ink(label, 3)
end

-- Balda de colores: botes de pintura redondos, cuatro por tabla de madera
local function buildSkins(parent: Instance, y: number): number
	heading(parent, "Color", y, -3)
	y += 42
	local perRow = 4
	local slot = INNER / perRow
	local rowH = 124
	local rows = math.ceil(#Config.Skins / perRow)

	for row = 1, rows do
		local top = y + (row - 1) * rowH
		local plank = Comic.frame(parent, Comic.Crumb)
		at(plank, PAD - 6, top + 50, INNER + 12, 14)
		plank.Rotation = if row % 2 == 0 then 0.6 else -0.6
		Comic.ink(plank, 3)
	end

	for i, def in Config.Skins do
		local row = (i - 1) // perRow
		local col = (i - 1) % perRow
		local inRow = math.min(perRow, #Config.Skins - row * perRow)
		local cx = PAD + (perRow - inRow) * slot / 2 + slot * (col + 0.5)
		local top = y + row * rowH + (if col % 2 == 0 then 0 else -4)

		local holder = Comic.frame(parent)
		holder.AnchorPoint = Vector2.new(0.5, 0)
		at(holder, cx, top, slot, rowH - 6)
		holder.ZIndex = 3

		local blob = Instance.new("TextButton")
		blob.AutoButtonColor = false
		blob.Text = ""
		blob.AnchorPoint = Vector2.new(0.5, 0)
		blob.Position = UDim2.new(0.5, 0, 0, 0)
		blob.Size = UDim2.fromOffset(62, 62)
		blob.BackgroundColor3 = def.color
		blob.BorderSizePixel = 0
		blob.ZIndex = 4
		blob.Parent = holder
		Comic.round(blob)
		local stroke = Comic.ink(blob, 4, true)
		stroke.LineJoinMode = Enum.LineJoinMode.Round

		-- Brillo de pintura fresca
		local shine = Comic.frame(blob, Color3.new(1, 1, 1))
		shine.BackgroundTransparency = 0.35
		at(shine, 13, 11, 14, 10)
		shine.Rotation = -30
		shine.ZIndex = 5
		Comic.round(shine)

		local name = Comic.label(holder, def.name, Comic.Body, 16, Comic.Ink)
		at(name, 0, 70, slot, 18)
		name.ZIndex = 4

		local tag = chip(holder)
		tag.Position = UDim2.new(0.5, 0, 0, 102)
		tag.Rotation = if i % 2 == 0 then 3 else -3

		register("skin", def, holder, blob, stroke, tag)
	end
	return y + rows * rowH + 10
end

-- Balda de sombreros: etiquetas de papel colgadas de una barra; giran desde el punto de cuelgue
local function buildHats(parent: Instance, y: number): number
	heading(parent, "Sombrero", y, 2)
	-- Aviso cuando el traje puesto ocupa la cabeza (o la cara, si llevas gafas)
	local note = Comic.label(parent, "El traje lo tapa", Comic.Body, 16, Comic.Ink)
	at(note, PAD + 150, y + 6, INNER - 150, 22)
	note.TextXAlignment = Enum.TextXAlignment.Right
	note.Rotation = 2
	note.Visible = false
	coverNote = note
	y += 46
	local perRow = 4
	local slot = INNER / perRow
	local rowH = 132
	local rows = math.ceil(#Config.Hats / perRow)
	local swings = { -6, 4, -3, 7, -5, 3, -7 }

	for row = 1, rows do
		local railY = y + (row - 1) * rowH
		local rail = Comic.frame(parent, ROD)
		at(rail, PAD - 8, railY - 4, INNER + 16, 8)
		rail.ZIndex = 5
		Comic.round(rail, 4)
		Comic.ink(rail, 3)
		for _, side in { 0, 1 } do
			local knob = Comic.frame(parent, ROD)
			knob.AnchorPoint = Vector2.new(0.5, 0.5)
			at(knob, PAD - 8 + side * (INNER + 16), railY, 16, 16)
			knob.ZIndex = 6
			Comic.round(knob)
			Comic.ink(knob, 3)
		end
	end

	for i, def in Config.Hats do
		local row = (i - 1) // perRow
		local col = (i - 1) % perRow
		local inRow = math.min(perRow, #Config.Hats - row * perRow)
		local cx = PAD + (perRow - inRow) * slot / 2 + slot * (col + 0.5)
		local railY = y + row * rowH

		-- El centro del soporte cae en la barra: al girarlo, la etiqueta se balancea desde ahí
		local holder = Comic.frame(parent)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		at(holder, cx, railY, 84, 220)
		holder.Rotation = swings[(i - 1) % #swings + 1]
		holder.ZIndex = 3

		local cord = Comic.frame(holder, Comic.Ink)
		at(cord, 41, 110, 2, 16)
		cord.ZIndex = 3

		local tagButton = Instance.new("TextButton")
		tagButton.AutoButtonColor = false
		tagButton.Text = ""
		tagButton.AnchorPoint = Vector2.new(0.5, 0)
		tagButton.Position = UDim2.new(0.5, 0, 0, 124)
		tagButton.Size = UDim2.fromOffset(78, 84)
		tagButton.BackgroundColor3 = MANILA
		tagButton.BorderSizePixel = 0
		tagButton.ZIndex = 4
		tagButton.Parent = holder
		Comic.round(tagButton, 6)
		local stroke = Comic.ink(tagButton, 3, true)

		local hole = Comic.frame(tagButton, Comic.Paper)
		hole.AnchorPoint = Vector2.new(0.5, 0)
		at(hole, 39, 6, 10, 10)
		hole.ZIndex = 5
		Comic.round(hole)
		Comic.ink(hole, 2)

		local name = Comic.label(tagButton, def.name, Comic.Display, 22, Comic.Ink)
		at(name, 4, 18, 70, 38)
		name.TextWrapped = true
		name.TextScaled = true
		name.ZIndex = 5
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 22
		limit.MinTextSize = 12
		limit.Parent = name

		local tag = chip(tagButton)
		tag.Position = UDim2.new(0.5, 0, 1, -12)

		register("hat", def, holder, tagButton, stroke, tag)
	end
	return y + rows * rowH - 30
end

-- Balda de estelas: cintas pintadas con los colores del rastro, dos por fila
local function buildTrails(parent: Instance, y: number): number
	heading(parent, "Estela", y, -2)
	y += 46
	local colW = INNER / 2
	local rowH = 76

	for i, def in Config.Trails do
		local row = (i - 1) // 2
		local col = (i - 1) % 2
		local holder = Comic.frame(parent)
		at(holder, PAD + col * colW + 4, y + row * rowH, colW - 12, 64)
		holder.Rotation = if (row + col) % 2 == 0 then -2 else 1.5
		holder.ZIndex = 3

		local ribbon = Instance.new("TextButton")
		ribbon.AutoButtonColor = false
		ribbon.Text = ""
		ribbon.Size = UDim2.new(1, 0, 0, 46)
		ribbon.BackgroundColor3 = Color3.new(1, 1, 1)
		ribbon.BorderSizePixel = 0
		ribbon.ZIndex = 4
		ribbon.Parent = holder
		local stroke = Comic.ink(ribbon, 4, true)

		if def.colors and #def.colors > 0 then
			local keys = {}
			local count = #def.colors
			for k, color in def.colors do
				table.insert(keys, ColorSequenceKeypoint.new(if count == 1 then (k - 1) else (k - 1) / (count - 1), color))
			end
			if count == 1 then
				table.insert(keys, ColorSequenceKeypoint.new(1, def.colors[1]))
			end
			local paint = Instance.new("UIGradient")
			paint.Color = ColorSequence.new(keys)
			paint.Parent = ribbon
		else
			-- Sin estela: papel con trama
			ribbon.BackgroundColor3 = Comic.Paper
			local dots = Comic.halftone(ribbon, Comic.Ink, 0)
			dots.ZIndex = 4
		end

		-- Pliegue en la punta de la cinta
		local fold = Comic.frame(ribbon, Comic.Ink)
		fold.BackgroundTransparency = 0.7
		at(fold, 0, 0, 14, 46)
		fold.ZIndex = 5

		local name = Comic.label(ribbon, def.name, Comic.Display, 24, Comic.Paper)
		at(name, 20, 0, colW - 44, 46)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 6
		Comic.ink(name, 3)

		local tag = chip(holder)
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -6, 0, 50)
		tag.Rotation = if i % 2 == 0 then -4 else 3

		register("trail", def, holder, ribbon, stroke, tag)
	end
	return y + math.ceil(#Config.Trails / 2) * rowH + 10
end

-- Barra con pomos de la que cuelgan sombreros y trajes
local function rail(parent: Instance, railY: number)
	local bar = Comic.frame(parent, ROD)
	at(bar, PAD - 8, railY - 4, INNER + 16, 8)
	bar.ZIndex = 5
	Comic.round(bar, 4)
	Comic.ink(bar, 3)
	for _, side in { 0, 1 } do
		local knob = Comic.frame(parent, ROD)
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		at(knob, PAD - 8 + side * (INNER + 16), railY, 16, 16)
		knob.ZIndex = 6
		Comic.round(knob)
		Comic.ink(knob, 3)
	end
end

-- Forma suelta del dibujo de un traje: "o" óvalo, "r" rectángulo redondeado, "d" rombo
local function iconShape(parent: Instance, spec)
	local kind, x, y, w, h, color, rot = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7] or 0
	local shape = Comic.frame(parent, color)
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = UDim2.fromOffset(x, y)
	if kind == "d" then
		shape.Size = UDim2.fromOffset(w, w)
		shape.Rotation = 45 + rot
		Comic.round(shape, 2)
	else
		shape.Size = UDim2.fromOffset(w, h)
		shape.Rotation = rot
		Comic.round(shape, if kind == "o" then nil else 3)
	end
	shape.ZIndex = 5
	Comic.ink(shape, 2, true)
end

-- Balda de trajes: perchas en una barra, cada una con la silueta del traje en sus colores
local function buildOutfits(parent: Instance, y: number): number
	heading(parent, "Trajes", y, -2)
	y += 52
	local perRow = 4
	local slot = INNER / perRow
	local rowH = 158
	local half = 150 -- el soporte mide 2 × half y su centro cae en la barra (gira desde ahí)
	local list = Outfits.list
	local rows = math.ceil(#list / perRow)
	local swings = { 4, -5, 3, -6, 5, -3, 6, -4 }

	for row = 1, rows do
		rail(parent, y + (row - 1) * rowH)
	end

	for i, def in list do
		local row = (i - 1) // perRow
		local col = (i - 1) % perRow
		local inRow = math.min(perRow, #list - row * perRow)
		local cx = PAD + (perRow - inRow) * slot / 2 + slot * (col + 0.5)
		local railY = y + row * rowH

		local holder = Comic.frame(parent)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		at(holder, cx, railY, 84, half * 2)
		holder.Rotation = swings[(i - 1) % #swings + 1]
		holder.ZIndex = 3

		-- Gancho enganchado a la barra y brazos de la percha
		local hook = Comic.frame(holder)
		at(hook, 35, half - 7, 14, 14)
		hook.ZIndex = 6
		Comic.round(hook)
		Comic.ink(hook, 3, true)
		for _, s in { -1, 1 } do
			local arm = Comic.frame(holder, Comic.Ink)
			arm.AnchorPoint = Vector2.new(0.5, 0.5)
			at(arm, 42 + s * 15, half + 15, 33, 4)
			arm.Rotation = s * 25
			arm.ZIndex = 3
		end
		local bar = Comic.frame(holder, Comic.Ink)
		at(bar, 10, half + 21, 64, 4)
		bar.ZIndex = 3

		-- La prenda: torso (el botón) con mangas y detalles dentro
		local ghost = #def.slots == 0
		local torso = Instance.new("TextButton")
		torso.AutoButtonColor = false
		torso.Text = ""
		torso.Size = UDim2.fromOffset(46, 58)
		torso.Position = UDim2.fromOffset(19, half + 34)
		torso.BackgroundColor3 = def.colors[1]
		torso.BackgroundTransparency = if ghost then 1 else 0
		torso.BorderSizePixel = 0
		torso.ZIndex = 4
		torso.Parent = holder
		Comic.round(torso, 8)
		local stroke = Comic.ink(torso, 3, true)
		if not ghost then
			for _, s in { -1, 1 } do
				local sleeve = Comic.frame(torso, def.colors[1])
				sleeve.AnchorPoint = Vector2.new(0.5, 0)
				sleeve.Position = UDim2.fromOffset(if s < 0 then -2 else 48, 2)
				sleeve.Size = UDim2.fromOffset(16, 30)
				sleeve.Rotation = -s * 25
				sleeve.ZIndex = 3
				Comic.round(sleeve, 5)
				Comic.ink(sleeve, 3, true)
			end
		end
		for _, spec in def.icon do
			iconShape(torso, spec)
		end

		local name = Comic.label(holder, def.name, Comic.Display, 20, Comic.Ink)
		at(name, 0, half + 98, 84, 22)
		name.TextScaled = true
		name.ZIndex = 4
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 20
		limit.MinTextSize = 12
		limit.Parent = name

		local tag = chip(holder)
		tag.Position = UDim2.new(0.5, 0, 0, half + 134)
		tag.Rotation = if i % 2 == 0 then 3 else -3

		local view = register("outfit", def, holder, torso, stroke, tag)
		view.ghost = ghost
	end
	return y + rows * rowH - 2
end

-- Pinta cada prenda según su estado. Que no haya duda de cuál llevas.
local function paint()
	if not foodLabel then
		return
	end
	foodLabel.Text = "Comida " .. Format.short(State.num("Food"))
	if coverNote then
		coverNote.Visible = Outfits.hidesHat(equipped("outfit"), equipped("hat"))
	end
	for _, view in views do
		local state = stateOf(view.kind, view.def)
		local tag = view.chip
		view.stroke.Color = if state == "worn" then Comic.Red else Comic.Ink
		view.stroke.Thickness = if state == "worn" then 7 else (if view.kind == "hat" or view.kind == "outfit" then 3 else 4)
		view.base.BackgroundTransparency = if view.ghost then 1 elseif state == "locked" then 0.45 else 0
		tag.Visible = state ~= "owned"
		tag.TextTransparency = 0
		tag.BackgroundTransparency = 0
		if state == "worn" then
			tag.Text = "Puesto"
			tag.BackgroundColor3 = Comic.Red
			tag.TextColor3 = Comic.Paper
		elseif state == "affordable" then
			tag.Text = Format.short(view.def.cost)
			tag.BackgroundColor3 = Comic.Yellow
			tag.TextColor3 = Comic.Ink
		elseif state == "expensive" then
			tag.Text = Format.short(view.def.cost)
			tag.BackgroundColor3 = DIM
			tag.TextColor3 = Comic.Ink
			tag.TextTransparency = 0.55
		elseif state == "locked" then
			tag.Text = "Solo VIP"
			tag.BackgroundColor3 = Comic.Ink
			tag.TextColor3 = Comic.Yellow
		end
	end
end

-- Escala por altura de pantalla, sin pasar de casi media pantalla de ancho; el panel ocupa
-- toda la altura menos los márgenes y las baldas se desplazan si no caben.
local function resize()
	local camera = Workspace.CurrentCamera
	if not camera or not panel then
		return
	end
	local view = camera.ViewportSize
	local s = math.clamp(math.min(view.Y / 800, view.X * 0.45 / W), 0.5, 1.25)
	fit.Scale = s
	panel.Size = UDim2.fromOffset(W, math.max(200, (view.Y - MARGIN * 2) / s))
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Wardrobe"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local holder, face = Comic.box(gui, UDim2.fromOffset(W, 700), Comic.Paper, 10)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -MARGIN - 10, 0, MARGIN)
	face.Active = true
	face.ClipsDescendants = true
	panel = holder
	fit = Instance.new("UIScale")
	fit.Parent = holder
	local dots = Comic.halftone(face, Comic.Red, 90)
	dots.ImageTransparency = 0.6

	-- Cabecera: el nombre y tu comida, nada más
	local title = Comic.label(face, "Vestidor", Comic.Display, 54, Comic.Ink)
	at(title, PAD, 8, 260, 56)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -2
	title.ZIndex = 3

	foodLabel = Comic.label(face, "", Comic.Display, 26, Comic.Yellow)
	at(foodLabel, PAD + 4, 60, 260, 28)
	foodLabel.TextXAlignment = Enum.TextXAlignment.Left
	foodLabel.ZIndex = 3
	Comic.ink(foodLabel, 3)

	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(50, 50), Comic.Red, 4)
	closeHolder.Position = UDim2.new(1, -70, 0, 16)
	closeHolder.ZIndex = 3
	closeFace.ZIndex = 3
	local cross = Comic.label(closeFace, "X", Comic.Display, 32, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 4
	closeFace.MouseButton1Click:Connect(Wardrobe.close)

	local line = Comic.frame(face, Comic.Ink)
	at(line, 0, HEADER - 3, W, 5)
	line.ZIndex = 3

	local shelves = Instance.new("ScrollingFrame")
	shelves.BackgroundTransparency = 1
	shelves.BorderSizePixel = 0
	shelves.Position = UDim2.fromOffset(0, HEADER + 2)
	shelves.Size = UDim2.new(1, 0, 1, -HEADER - 2)
	shelves.ScrollingDirection = Enum.ScrollingDirection.Y
	shelves.ScrollBarThickness = 8
	shelves.ScrollBarImageColor3 = Comic.Ink
	shelves.ElasticBehavior = Enum.ElasticBehavior.Never
	shelves.ZIndex = 2
	shelves.Parent = face

	local y = 12
	y = buildSkins(shelves, y)
	y = buildHats(shelves, y + 8)
	y = buildTrails(shelves, y + 8)
	y = buildOutfits(shelves, y + 8)
	shelves.CanvasSize = UDim2.fromOffset(0, y + 12)

	resize()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
end

function Wardrobe.isOpen(): boolean
	return isOpen
end

function Wardrobe.open()
	if not gui then
		return
	end
	isOpen = true
	resize()
	paint()
	gui.Enabled = true
	Sfx.pop(0.9)
	-- Entra deslizándose desde el borde derecho
	local rest = UDim2.new(1, -MARGIN - 10, 0, MARGIN)
	panel.Position = rest + UDim2.fromOffset(W * fit.Scale + 40, 0)
	TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = rest }):Play()
end

function Wardrobe.close()
	isOpen = false
	if gui then
		gui.Enabled = false
	end
end

function Wardrobe.toggle()
	if isOpen then
		Wardrobe.close()
	else
		Wardrobe.open()
	end
end

function Wardrobe.start(remoteFolder: Folder)
	remotes = remoteFolder
	build()
	paint()
	State.onChange(function()
		if isOpen then
			paint()
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if isOpen and input.KeyCode == Enum.KeyCode.Escape then
			Wardrobe.close()
		end
	end)
end

return Wardrobe
