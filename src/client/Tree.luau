-- El árbol de mejoras es tu hormiguero visto en corte, como una viñeta larga que se recorre hacia
-- abajo: una galería bajo la hierba, cuatro pozos (uno por rama) que cruzan capa tras capa de
-- tierra, y la cámara real al fondo. Cada cámara es una mejora; excavarla es comprarla.
-- Las capas sin excavar están tapadas: excavar una abre sus cámaras y la zona siguiente del mapa.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Comic = require(script.Parent.Comic)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Tree = {}

local LAYOUT = Config.TreeLayout
local W, H = LAYOUT.Width, 900
local SURFACE = 139 -- y donde acaba la hierba y empieza la tierra
local GALLERY = 196
local CHAMBER = 88
local MINI = 54 -- galerías: cámaras pequeñas de un solo nivel
local FIRST_BAND = 210
local LAYERS = #Config.Layers
local ROYAL = { x = 60, y = FIRST_BAND + LAYERS * LAYOUT.LayerHeight + 36, w = 1480, h = 120 }
local CONTENT = ROYAL.y + ROYAL.h + 150 -- hueco para los botones fijos de abajo
local GOLD = Color3.fromRGB(255, 226, 150)

local gui: ScreenGui
local canvas: ScrollingFrame
local remotes
local isOpen = false

local nodeViews = {}
local royalViews = {}
local miniViews = {} -- [id] = { def, button, stroke, icon, state, sel, scale }
local rowTunnels = {} -- una galería por fila: { frame, first, state }
local covers = {}
local selected: { kind: string, id: string }? = nil

local foodLabel: TextLabel
local jellyLabel: TextLabel
local card, cardParts
local swarmFace: TextButton
local swarmSub: TextLabel

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

local function bandTop(layer: number): number
	return if layer == 1 then SURFACE else FIRST_BAND + (layer - 1) * LAYOUT.LayerHeight
end

local function iconOf(def): string
	return Assets.Icons[def.icon or def.id] or Assets.Icons.anthill
end

-- Túnel entre dos puntos: un marco girado con borde de tinta
local function tunnel(x1: number, y1: number, x2: number, y2: number): Frame
	local dx, dy = x2 - x1, y2 - y1
	local frame = Comic.frame(canvas, Comic.DirtDark)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
	frame.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + 26, 26)
	frame.Rotation = math.deg(math.atan2(dy, dx))
	frame.ZIndex = 3
	Comic.ink(frame, 4)
	return frame
end

local function pill(parent: Instance, text: string): TextLabel
	local label = Comic.label(parent, text, Comic.Display, 20, Comic.Ink)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 1, -2)
	label.Size = UDim2.fromOffset(0, 24)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = Comic.Paper
	label.ZIndex = 7
	Comic.round(label, 12)
	Comic.ink(label, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.Parent = label
	return label
end

local function chamber(x: number, y: number, size: number, icon: string)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Text = ""
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(size, size)
	button.BorderSizePixel = 0
	button.ZIndex = 5
	button.Parent = canvas
	Comic.round(button)
	local stroke = Comic.ink(button, 5, true)
	stroke.LineJoinMode = Enum.LineJoinMode.Round

	local image = Comic.image(button, icon)
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.47)
	image.Size = UDim2.fromScale(0.58, 0.58)
	image.ZIndex = 6

	-- El aviso va abajo a la izquierda para no pisar el nombre de la rama
	local badge = Comic.burst(button, 38, Comic.Red)
	badge.Position = UDim2.new(0, 6, 0, 8)
	badge.ZIndex = 8
	badge.Visible = false
	local mark = Comic.label(badge, "!", Comic.Display, 24, Comic.Paper)
	mark.Size = UDim2.fromScale(1, 1)
	mark.ZIndex = 9
	Comic.boil(badge, 8)

	local scale = Instance.new("UIScale")
	scale.Parent = button

	return { button = button, stroke = stroke, icon = image, badge = badge, level = pill(button, ""), scale = scale }
end

local function select(kind: string, id: string)
	selected = { kind = kind, id = id }
	Sfx.pop(1.3)
	Tree.refresh()
end

local function buildNode(def)
	local view = chamber(def.x, def.y, CHAMBER, iconOf(def))
	view.def = def

	-- Estrecho: a la derecha empiezan las galerías
	local name = Comic.label(canvas, def.name, Comic.Body, 17, Comic.Paper)
	name.AnchorPoint = Vector2.new(0.5, 0)
	at(name, def.x, def.y + CHAMBER / 2 + 13, 130, 20) -- las galerías empiezan 68 px a la derecha del pozo
	name.TextScaled = true
	name.ZIndex = 5
	Comic.ink(name, 3)
	local fitName = Instance.new("UITextSizeConstraint")
	fitName.MaxTextSize = 17
	fitName.MinTextSize = 11
	fitName.Parent = name
	view.name = name

	-- El túnel llega desde la cámara madre, o desde la galería si es la primera de su rama
	local parent = def.parent and Config.NodeById[def.parent]
	if parent then
		view.tunnel = tunnel(parent.x, parent.y, def.x, def.y)
		-- Cámara de paso: su túnel queda dentro del de otra cámara del mismo pozo (p. ej. la fila 2
		-- entre dos cámaras de la fila 1). Sin excavar va por debajo, para no cortar el pozo.
		for _, other in Config.Tree do
			local up = other.parent and Config.NodeById[other.parent]
			if other ~= def and up and other.x == def.x and up.x == def.x and math.min(up.y, other.y) <= math.min(parent.y, def.y) and math.max(up.y, other.y) >= math.max(parent.y, def.y) then
				view.spur = true
				break
			end
		end
	else
		view.tunnel = tunnel(def.x, GALLERY, def.x, def.y)
	end

	view.button.MouseButton1Click:Connect(function()
		select(if def.unit then "workers" else "node", def.id)
	end)
	nodeViews[def.id] = view
end

-- Galerías: 360 cámaras pequeñas, así que cada una es solo botón, borde e icono (sin chamber()).
-- Cada fila de tres sale del pozo de su rama por un túnel fino.
local function buildMinis()
	for _, def in Config.Minis do
		if def.col == 1 then
			local shaft = LAYOUT.Regions[def.key] + LAYOUT.Shaft
			local last = LAYOUT.Regions[def.key] + LAYOUT.MiniColumns[3]
			local frame = Comic.frame(canvas, Comic.DirtDark)
			at(frame, shaft, def.y - 7, last - shaft, 14)
			frame.ZIndex = 3
			Comic.ink(frame, 3)
			table.insert(rowTunnels, { frame = frame, first = def, state = "" })
		end

		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.Text = ""
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromOffset(def.x, def.y)
		-- Las reglas con nombre (tercera de cada fila) son cuadradas de esquina suave y un poco más grandes
		local isPerk = def.kind == "perk"
		local size = if isPerk then MINI + 8 else MINI
		button.Size = UDim2.fromOffset(size, size)
		button.BorderSizePixel = 0
		button.BackgroundColor3 = Comic.DirtDark
		button.ZIndex = 5
		Comic.round(button, if isPerk then 16 else nil)
		-- Con la unión en inglete el borde sale cuadrado aunque la caja sea redonda
		local stroke = Comic.ink(button, 3, true)
		stroke.LineJoinMode = Enum.LineJoinMode.Round

		local image = Comic.image(button, Assets.Icons[def.icon] or Assets.Icons.anthill)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(0.62, 0.62)
		image.ImageTransparency = 0.7
		image.ZIndex = 6

		button.Parent = canvas
		button.MouseButton1Click:Connect(function()
			select("mini", def.id)
		end)
		miniViews[def.id] = { def = def, button = button, stroke = stroke, icon = image, state = "", sel = false }
	end
end

-- Tapa de una capa sin excavar: tierra maciza con piedras y, en la siguiente, el botón de excavar.
local function buildCover(layer: number)
	local top = bandTop(layer)
	local cover = Instance.new("TextButton")
	cover.AutoButtonColor = false
	cover.Text = ""
	cover.BackgroundColor3 = Comic.DirtDark:Lerp(Comic.Ink, 0.25)
	cover.BackgroundTransparency = 0.08
	cover.BorderSizePixel = 0
	at(cover, 0, top + 3, W, LAYOUT.LayerHeight - 3)
	cover.ZIndex = 12
	cover.Parent = canvas

	local dots = Comic.image(cover, Assets.Halftone, Comic.Ink)
	dots.ScaleType = Enum.ScaleType.Tile
	dots.TileSize = UDim2.fromOffset(34, 34)
	dots.ImageTransparency = 0.75
	dots.Size = UDim2.fromScale(1, 1)
	dots.ZIndex = 12

	for i = 1, 9 do
		local rock = Comic.frame(cover, Color3.fromRGB(150, 156, 170):Lerp(Comic.DirtDark, 0.35))
		local size = 30 + (i * 37 + layer * 13) % 46
		at(rock, (i * 173 + layer * 71) % (W - 80) + 20, (i * 97 + layer * 29) % (LAYOUT.LayerHeight - 90) + 20, size, size * 0.7)
		rock.Rotation = (i * 23) % 40 - 20
		rock.ZIndex = 13
		Comic.round(rock, 14)
		Comic.ink(rock, 4, true)
	end

	local zone = Config.Zones[layer]
	local title = Comic.label(cover, "Capa " .. layer .. "  ·  " .. Config.Layers[layer], Comic.Display, 44, Comic.Paper)
	at(title, 0, 62, W, 50)
	title.ZIndex = 14
	Comic.ink(title, 4)

	local promise = Comic.label(cover, "Abre la zona " .. zone.name .. " y sube el tope de tus mejoras", Comic.Body, 22, Comic.Paper)
	at(promise, 0, 116, W, 28)
	promise.ZIndex = 14
	Comic.ink(promise, 3)

	local holder, face = Comic.button(cover, UDim2.fromOffset(380, 74), Comic.Yellow, 7)
	at(holder, W / 2 - 190, 162)
	holder.ZIndex = 14
	holder.Shadow.ZIndex = 14
	face.ZIndex = 15
	local label = Comic.label(face, "", Comic.Display, 34, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 16
	face.MouseButton1Click:Connect(function()
		remotes.Buy:FireServer("dig")
	end)

	local badge = Comic.burst(holder, 50, Comic.Red)
	badge.Position = UDim2.new(1, -4, 0, 4)
	badge.ZIndex = 17
	local mark = Comic.label(badge, "!", Comic.Display, 30, Comic.Paper)
	mark.Size = UDim2.fromScale(1, 1)
	mark.ZIndex = 18
	Comic.boil(badge, 8)

	covers[layer] = { cover = cover, holder = holder, face = face, label = label, promise = promise, badge = badge }
end

local function buildRoyal()
	local body = Comic.frame(canvas, GOLD)
	at(body, ROYAL.x, ROYAL.y, ROYAL.w, ROYAL.h)
	body.ZIndex = 4
	Comic.round(body, 56)
	Comic.ink(body, 5).LineJoinMode = Enum.LineJoinMode.Round
	local dots = Comic.halftone(body, Comic.Yellow, 0)
	dots.ZIndex = 4
	Comic.round(dots, 56)

	local title = Comic.label(canvas, "Cámara real", Comic.Display, 32, Comic.Ink)
	at(title, ROYAL.x + 34, ROYAL.y + 12, 200, 34)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 6

	jellyLabel = Comic.label(canvas, "", Comic.Display, 26, Comic.Red)
	at(jellyLabel, ROYAL.x + 34, ROYAL.y + 46, 200, 28)
	jellyLabel.TextXAlignment = Enum.TextXAlignment.Left
	jellyLabel.ZIndex = 6

	local note = Comic.label(canvas, "La jalea nunca se pierde", Comic.Body, 16, Comic.Ink)
	at(note, ROYAL.x + 34, ROYAL.y + 80, 210, 20)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.ZIndex = 6

	for i, def in Config.Royal do
		local view = chamber(ROYAL.x + 290 + (i - 1) * 98, ROYAL.y + 52, 74, iconOf(def))
		view.def = def
		view.button.ZIndex = 6
		view.icon.ZIndex = 7
		view.button.MouseButton1Click:Connect(function()
			select("royal", def.id)
		end)
		royalViews[def.id] = view
	end

	local holder, face = Comic.button(canvas, UDim2.fromOffset(190, 84), Comic.Red, 6)
	at(holder, ROYAL.x + ROYAL.w - 224, ROYAL.y + 16)
	holder.ZIndex = 6
	face.ZIndex = 6
	holder.Shadow.ZIndex = 5
	swarmFace = face
	local swarmTitle = Comic.label(face, "Enjambrar", Comic.Display, 32, Comic.Paper)
	at(swarmTitle, 0, 8, 190, 36)
	swarmTitle.ZIndex = 7
	Comic.ink(swarmTitle, 3)
	swarmSub = Comic.label(face, "", Comic.Body, 17, Comic.Paper)
	at(swarmSub, 0, 46, 190, 26)
	swarmSub.ZIndex = 7
	face.MouseButton1Click:Connect(function()
		if selected and selected.kind == "swarm" and State.jellyNow() >= 1 then
			remotes.Rebirth:FireServer()
			Tree.close()
		else
			select("swarm", "swarm")
		end
	end)

	-- Los cuatro pozos bajan hasta la cámara real: así las galerías de las capas hondas,
	-- por debajo de la última cámara grande de su rama, también salen de un pozo
	local last = {}
	for _, def in Config.Tree do
		local deepest = last[def.branch]
		if not deepest or def.y > deepest.y then
			last[def.branch] = def
		end
	end
	for _, def in last do
		tunnel(def.x, def.y, def.x, ROYAL.y + 20).BackgroundColor3 = Comic.DirtLight
	end
end

local function buildCard()
	local holder, face = Comic.box(canvas, UDim2.fromOffset(372, 232), Comic.Paper, 8)
	holder.ZIndex = 30
	holder.Visible = false
	holder.Shadow.ZIndex = 30
	face.ZIndex = 31
	face.Active = true -- los clics sobre la ficha no deben deseleccionar
	Comic.boil(holder, 0.5)

	local icon = Comic.image(face, "")
	at(icon, 16, 14, 52, 52)
	icon.ZIndex = 32

	local name = Comic.label(face, "", Comic.Display, 32, Comic.Ink)
	at(name, 80, 10, 280, 34)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 32

	local branch = Comic.label(face, "", Comic.Body, 16, Comic.Red)
	at(branch, 80, 44, 280, 20)
	branch.TextXAlignment = Enum.TextXAlignment.Left
	branch.ZIndex = 32

	local desc = Comic.label(face, "", Comic.Body, 18, Comic.Ink)
	at(desc, 16, 70, 340, 50)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.TextScaled = true
	desc.ZIndex = 32
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.MinTextSize = 12
	limit.Parent = desc

	local effect = Comic.label(face, "", Comic.Body, 17, Comic.Ink)
	at(effect, 16, 122, 340, 44)
	effect.TextXAlignment = Enum.TextXAlignment.Left
	effect.TextYAlignment = Enum.TextYAlignment.Top
	effect.TextWrapped = true
	effect.ZIndex = 32

	local function action(x: number, width: number)
		local buttonHolder, buttonFace = Comic.button(face, UDim2.fromOffset(width, 48), Comic.Yellow, 5)
		at(buttonHolder, x, 170)
		buttonHolder.ZIndex = 32
		buttonHolder.Shadow.ZIndex = 32
		buttonFace.ZIndex = 33
		local label = Comic.label(buttonFace, "", Comic.Display, 24, Comic.Ink)
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = 34
		return { holder = buttonHolder, face = buttonFace, label = label }
	end

	local buy = action(16, 216)
	local max = action(244, 112)
	max.label.Text = "Máximo"

	buy.face.MouseButton1Click:Connect(function()
		if not selected then
			return
		end
		if selected.kind == "workers" then
			remotes.Buy:FireServer("workers", nil, 1)
		elseif selected.kind == "node" or selected.kind == "royal" or selected.kind == "mini" then
			remotes.Buy:FireServer(selected.kind, selected.id)
		elseif selected.kind == "swarm" and State.jellyNow() >= 1 then
			remotes.Rebirth:FireServer()
			Tree.close()
		end
	end)
	-- Obreras: cría todas las que quepan. Cámaras con niveles: sube todos los que puedas pagar.
	max.face.MouseButton1Click:Connect(function()
		if not selected then
			return
		end
		if selected.kind == "workers" then
			remotes.Buy:FireServer("workers", nil, "max")
		elseif selected.kind == "node" then
			remotes.Buy:FireServer("node-max", selected.id)
		end
	end)

	card = holder
	cardParts = { icon = icon, name = name, branch = branch, desc = desc, effect = effect, buy = buy, max = max }
end

local function scrollTo(y: number)
	local target = math.clamp(y, 0, CONTENT - H)
	TweenService:Create(canvas, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = Vector2.new(0, target) }):Play()
end

local function build()
	local player = Players.LocalPlayer
	gui = Instance.new("ScreenGui")
	gui.Name = "Tree"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("TextButton")
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.BackgroundColor3 = Comic.Ink
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = gui
	dim.MouseButton1Click:Connect(Tree.close)

	local page = Comic.frame(gui)
	page.AnchorPoint = Vector2.new(0.5, 0.5)
	page.Position = UDim2.fromScale(0.5, 0.5)
	page.Size = UDim2.fromOffset(W, H)
	local fit = Instance.new("UIScale")
	fit.Parent = page
	local function resize()
		local camera = Workspace.CurrentCamera
		if camera then
			local view = camera.ViewportSize
			fit.Scale = math.min(view.X / W, view.Y / H) * 0.94
		end
	end
	resize()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

	local shadow = Comic.frame(page, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(14, 14)

	local face = Comic.frame(page, Comic.Dirt)
	face.Size = UDim2.fromScale(1, 1)
	face.ClipsDescendants = true
	face.Active = true
	Comic.ink(face, 6, true)

	canvas = Instance.new("ScrollingFrame")
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.CanvasSize = UDim2.fromOffset(0, CONTENT)
	canvas.ScrollingDirection = Enum.ScrollingDirection.Y
	canvas.ScrollBarThickness = 14
	canvas.ScrollBarImageColor3 = Comic.Ink
	canvas.ElasticBehavior = Enum.ElasticBehavior.Never
	canvas.Parent = face

	-- Fondo que deselecciona al tocar tierra vacía
	local ground = Instance.new("TextButton")
	ground.AutoButtonColor = false
	ground.Text = ""
	ground.BackgroundTransparency = 1
	ground.Size = UDim2.fromOffset(W, CONTENT)
	ground.Parent = canvas
	ground.MouseButton1Click:Connect(function()
		selected = nil
		Tree.refresh()
	end)

	-- Estratos: cada capa un tono más oscuro y frío
	for layer = 1, LAYERS do
		local top = bandTop(layer)
		local bottom = bandTop(layer + 1)
		local t = (layer - 1) / (LAYERS - 1)
		local band = Comic.frame(canvas, Comic.Dirt:Lerp(Color3.fromRGB(78, 62, 84), t * 0.8))
		at(band, 0, top, W, bottom - top)
		local soil = Comic.image(band, Assets.Halftone, Comic.Ink)
		soil.ScaleType = Enum.ScaleType.Tile
		soil.TileSize = UDim2.fromOffset(30, 30)
		soil.ImageTransparency = 0.82
		soil.Size = UDim2.fromScale(1, 1)
		if layer > 1 then
			local seam = Comic.frame(canvas, Comic.Ink)
			at(seam, 0, top - 3, W, 6)
			seam.ZIndex = 2
			-- Etiqueta sobre una píldora oscura, por encima del pozo de Mandíbulas (que la cruza) y
			-- encima de su primera cámara; cabe a la izquierda de sus galerías (x < 170)
			local tag = Comic.label(canvas, "Capa " .. layer .. " · " .. Config.Layers[layer], Comic.Display, 20, Comic.Paper)
			at(tag, 10, top + 6, 156, 26)
			tag.TextXAlignment = Enum.TextXAlignment.Left
			tag.TextScaled = true
			tag.BackgroundColor3 = Comic.Ink
			tag.BackgroundTransparency = 0.3
			tag.ZIndex = 7
			Comic.round(tag, 10)
			local padTag = Instance.new("UIPadding")
			padTag.PaddingLeft = UDim.new(0, 8)
			padTag.PaddingRight = UDim.new(0, 8)
			padTag.PaddingTop = UDim.new(0, 2)
			padTag.PaddingBottom = UDim.new(0, 2)
			padTag.Parent = tag
			local fitTag = Instance.new("UITextSizeConstraint")
			fitTag.MaxTextSize = 20
			fitTag.Parent = tag
		end
	end
	local floor = Comic.frame(canvas, Color3.fromRGB(60, 46, 62))
	at(floor, 0, bandTop(LAYERS + 1), W, CONTENT - bandTop(LAYERS + 1))

	-- Cielo, hierba y el montículo asomando
	local sky = Comic.frame(canvas, Comic.Cyan)
	at(sky, 0, 0, W, SURFACE - 16)
	Comic.halftone(sky, Comic.Paper, 90)
	local grass = Comic.frame(canvas, Comic.Green)
	at(grass, 0, SURFACE - 18, W, 18)
	local line = Comic.frame(canvas, Comic.Ink)
	at(line, 0, SURFACE - 3, W, 6)
	local mound = Comic.image(canvas, Assets.Icons.anthill)
	at(mound, W / 2 - 80, SURFACE - 118, 160, 130)
	mound.ZIndex = 2

	local title = Comic.label(canvas, "Tu hormiguero", Comic.Display, 60, Comic.Paper)
	at(title, 38, 26, 460, 66)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -2
	Comic.ink(title, 5)

	-- Pozo de entrada y galería de la que cuelgan las ramas
	local regions = LAYOUT.Regions
	tunnel(W / 2, SURFACE, W / 2, GALLERY).BackgroundColor3 = Comic.DirtLight
	local leftmost, rightmost = math.huge, -math.huge
	for _, x in regions do
		leftmost = math.min(leftmost, x)
		rightmost = math.max(rightmost, x)
	end
	tunnel(leftmost + LAYOUT.Shaft, GALLERY, rightmost + LAYOUT.Shaft, GALLERY).BackgroundColor3 = Comic.DirtLight

	local seen = {}
	for _, def in Config.Tree do
		buildNode(def)
		if not seen[def.branch] then
			-- El nombre de la rama, justo bajo la hierba y encima de su pozo (lejos de las galerías)
			seen[def.branch] = true
			local header = Comic.label(canvas, def.branch, Comic.Display, 30, Comic.Yellow)
			header.AnchorPoint = Vector2.new(0.5, 0)
			at(header, def.x, SURFACE + 6, 200, 32)
			header.Rotation = -2
			header.ZIndex = 6
			Comic.ink(header, 4)
		end
	end
	buildMinis()
	for layer = 2, LAYERS do
		buildCover(layer)
	end

	buildRoyal()
	buildCard()

	-- Fijo sobre el corte: la comida, el atajo a la cámara real y cerrar
	local bar = Comic.frame(face)
	bar.Size = UDim2.fromOffset(W, 110)
	bar.ZIndex = 40

	foodLabel = Comic.label(bar, "", Comic.Display, 46, Comic.Yellow)
	at(foodLabel, W - 640, 34, 500, 52)
	foodLabel.TextXAlignment = Enum.TextXAlignment.Right
	foodLabel.ZIndex = 41
	Comic.ink(foodLabel, 4)

	local closeHolder, closeFace = Comic.button(bar, UDim2.fromOffset(62, 62), Comic.Red, 5)
	at(closeHolder, W - 110, 30)
	closeHolder.ZIndex = 41
	closeHolder.Shadow.ZIndex = 41
	closeFace.ZIndex = 42
	local cross = Comic.label(closeFace, "X", Comic.Display, 38, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 43
	closeFace.MouseButton1Click:Connect(Tree.close)

	local deepHolder, deepFace = Comic.button(face, UDim2.fromOffset(210, 50), GOLD, 5)
	at(deepHolder, W - 250, H - 78)
	deepHolder.ZIndex = 41
	deepHolder.Shadow.ZIndex = 41
	deepFace.ZIndex = 42
	local deepLabel = Comic.label(deepFace, "Cámara real", Comic.Display, 26, Comic.Ink)
	deepLabel.Size = UDim2.fromScale(1, 1)
	deepLabel.ZIndex = 43
	deepFace.MouseButton1Click:Connect(function()
		-- Abajo del todo; si ya estás, vuelve a tu capa
		if canvas.CanvasPosition.Y > CONTENT - H - 40 then
			scrollTo(bandTop(State.depth()) - 120)
		else
			scrollTo(CONTENT)
		end
	end)
end

local function paintChamber(view, state: string, levelText: string, affordable: boolean)
	local fill = if state == "locked"
		then Comic.DirtDark
		elseif state == "empty" then Comic.DirtLight
		elseif state == "max" then Comic.Yellow
		elseif state == "capped" then Comic.Cyan
		else Comic.Paper
	view.button.BackgroundColor3 = fill
	view.icon.ImageTransparency = if state == "locked" then 0.7 else 0
	view.level.Text = levelText
	view.level.Visible = state ~= "locked"
	view.badge.Visible = affordable
	local isSelected = selected ~= nil and selected.id == view.def.id
	view.stroke.Color = if isSelected then Comic.Red else Comic.Ink
	view.stroke.Thickness = if isSelected then 8 else 5
	if view.tunnel then
		local dark = state == "locked" or state == "empty"
		view.tunnel.BackgroundColor3 = if dark then Comic.DirtDark else Comic.DirtLight
		if view.spur then
			view.tunnel.ZIndex = if dark then 2 else 4
		end
	end
	if view.name then
		view.name.TextTransparency = if state == "locked" then 0.45 else 0
	end
end

-- Galerías: sin excavar o cerrada (tierra oscura), a la vista pero cara (tierra clara),
-- al alcance (papel con aro rojo) y tuya (amarilla).
local MINI_FILL = { locked = Comic.DirtDark, far = Comic.DirtLight, ready = Comic.Paper, owned = Comic.Yellow }

local function paintMini(view, state: string, isSelected: boolean)
	view.state = state
	view.sel = isSelected
	view.button.BackgroundColor3 = MINI_FILL[state]
	view.icon.ImageTransparency = if state == "locked" then 0.7 elseif state == "far" then 0.3 else 0
	view.stroke.Color = if isSelected then Comic.Cyan elseif state == "ready" then Comic.Red else Comic.Ink
	view.stroke.Thickness = if isSelected or state == "ready" then 6 else 3
end

local function showCard(x: number, y: number, above: boolean, info)
	local cx = if above then x - 186 else (if x < 1000 then x + 64 else x - 64 - 372)
	local cy = if above then y - 300 else math.clamp(y - 100, SURFACE + 14, CONTENT - 250)
	card.Position = UDim2.fromOffset(math.clamp(cx, 14, W - 400), cy)
	card.Visible = true

	cardParts.icon.Image = info.icon or ""
	cardParts.name.Text = info.name
	cardParts.branch.Text = info.branch
	cardParts.desc.Text = info.desc
	cardParts.effect.Text = info.effect
	cardParts.buy.holder.Visible = info.buyText ~= nil
	cardParts.max.holder.Visible = info.showMax == true
	cardParts.max.label.Text = info.maxText or "Máximo"
	if info.buyText then
		cardParts.buy.label.Text = info.buyText
		cardParts.buy.face.BackgroundColor3 = if info.canBuy then Comic.Yellow else Comic.DirtLight
		cardParts.buy.label.TextTransparency = if info.canBuy then 0 else 0.4
		cardParts.max.face.BackgroundColor3 = if info.canBuy then Comic.Yellow else Comic.DirtLight
	end
end

local function effectLines(id: string, level: number, max: number): string
	if level >= max then
		return Stats.effect(id, level)
	end
	return "Ahora: " .. Stats.effect(id, level) .. "\nLuego: " .. Stats.effect(id, level + 1)
end

local function whyLocked(def, depth: number): string
	if depth < def.layer then
		return "Excava antes hasta la capa " .. def.layer
	end
	if def.parent then
		return "Excava antes: " .. Config.NodeById[def.parent].name
	end
	return "Primero necesitas una obrera"
end

-- Repinta todo según la partida. Devuelve true si hay algo que puedas comprar ya.
function Tree.refresh(): boolean
	local nodes = State.nodes()
	local royal = State.royal()
	local stats = State.stats()
	local depth = State.depth()
	local food = State.num("Food")
	local jelly = State.num("Jelly")
	local workers = State.num("Workers")
	local anyAffordable = false

	for _, def in Config.Tree do
		local view = nodeViews[def.id]
		local unlocked = Stats.unlocked(def, nodes, workers, depth)
		if def.unit then
			local cap = stats.workerCap
			local affordable = unlocked and workers < cap and food >= Stats.workerCost(workers, stats.workerDiscount)
			anyAffordable = anyAffordable or affordable
			local state = if not unlocked then "locked" elseif workers == 0 then "empty" elseif workers >= cap then "max" else "owned"
			paintChamber(view, state, workers .. "/" .. cap, affordable)
		else
			local level = nodes[def.id] or 0
			local available = Stats.available(def, depth)
			local maxed = level >= def.max
			local capped = not maxed and level >= available
			local affordable = unlocked and not maxed and not capped and food >= Stats.nodeCost(def, level)
			anyAffordable = anyAffordable or affordable
			local state = if not unlocked then "locked" elseif maxed then "max" elseif capped then "capped" elseif level == 0 then "empty" else "owned"
			local text = if def.max == 1 then (if maxed then "Listo" else "Nuevo") else level .. "/" .. math.max(available, 0)
			paintChamber(view, state, text, affordable)
		end
	end

	for _, def in Config.Royal do
		local level = royal[def.id] or 0
		local maxed = level >= def.max
		local affordable = not maxed and jelly >= Stats.royalCost(def, level)
		paintChamber(royalViews[def.id], if maxed then "max" elseif level == 0 then "empty" else "owned", level .. "/" .. def.max, affordable)
	end

	-- Galerías: ¿hay alguna abierta que te puedas pagar?
	local minis = State.minis()
	if not anyAffordable then
		for _, def in Config.MinisByCost do
			if def.cost > food then
				break
			end
			if not minis[def.id] and Stats.miniOpen(def, minis, depth) then
				anyAffordable = true
				break
			end
		end
	end

	local digCost = Stats.digCost(depth)
	local canDig = food >= digCost
	anyAffordable = anyAffordable or canDig
	for layer, view in covers do
		view.cover.Visible = layer > depth
		local isNext = layer == depth + 1
		view.holder.Visible = isNext
		view.promise.Visible = isNext
		view.badge.Visible = isNext and canDig
		if isNext then
			view.label.Text = if canDig then "Excavar por " .. Format.short(digCost) else "Faltan " .. Format.short(digCost - food)
			view.face.BackgroundColor3 = if canDig then Comic.Yellow else Comic.DirtLight
		end
	end

	if not isOpen then
		return anyAffordable
	end

	-- Solo se toca una galería cuando cambia su estado: esto corre cada vez que cambia la comida
	local selectedMini = if selected and selected.kind == "mini" then selected.id else nil
	for id, view in miniViews do
		local state = if minis[id] then "owned"
			elseif not Stats.miniOpen(view.def, minis, depth) then "locked"
			elseif food >= view.def.cost then "ready"
			else "far"
		local isSelected = id == selectedMini
		if state ~= view.state or isSelected ~= view.sel then
			paintMini(view, state, isSelected)
		end
	end
	for _, row in rowTunnels do
		local state = if minis[row.first.id] then "dug" else "raw"
		if state ~= row.state then
			row.state = state
			row.frame.BackgroundColor3 = if state == "dug" then Comic.DirtLight else Comic.DirtDark
		end
	end

	foodLabel.Text = "Comida " .. Format.short(food)
	jellyLabel.Text = "Jalea " .. Format.short(jelly)

	local gain = State.jellyNow()
	swarmFace.BackgroundColor3 = if gain >= 1 then Comic.Red else Comic.DirtDark
	swarmSub.Text = if gain >= 1 then "+" .. Format.short(gain) .. " de jalea" else "Aún no da jalea"

	card.Visible = false
	if selected then
		if selected.kind == "node" then
			local def = Config.NodeById[selected.id]
			local level = nodes[def.id] or 0
			local unlocked = Stats.unlocked(def, nodes, workers, depth)
			local available = Stats.available(def, depth)
			local maxed = level >= def.max
			local capped = not maxed and level >= available
			local cost = Stats.nodeCost(def, level)
			local effect = if not unlocked
				then whyLocked(def, depth)
				elseif capped then Stats.effect(def.id, level) .. "\nExcava otra capa para seguir subiéndola"
				else effectLines(def.id, level, def.max)
			local buyable = unlocked and not maxed and not capped
			showCard(def.x, def.y, false, {
				icon = iconOf(def),
				name = def.name,
				branch = def.branch,
				desc = def.desc,
				effect = effect,
				buyText = if not buyable then nil elseif food >= cost then "Excavar por " .. Format.short(cost) else "Faltan " .. Format.short(cost - food),
				canBuy = food >= cost,
				showMax = buyable and def.max > 1,
				maxText = "Máx",
			})
		elseif selected.kind == "mini" then
			local def = Config.MiniById[selected.id]
			local owned = minis[def.id] == true
			local open = Stats.miniOpen(def, minis, depth)
			local isPerk = def.kind == "perk"
			local desc, effect
			if isPerk then
				-- Regla con nombre: la regla con la fuerza que tendrá (o tiene) y su nivel
				local level = Stats.miniTotal(stats, def)
				local after = if owned then level else level + 1
				desc = Config.perkText(def.perk, after)
				effect = if owned
					then "Tuya. La regla va por el nivel " .. level .. ": cada galería suya la sube uno."
					elseif depth < def.layer then "Excava antes hasta la capa " .. def.layer
					elseif not open then "Excava antes la cámara de su izquierda"
					elseif level > 0 then "Ahora: nivel " .. level .. " (" .. Config.perkShort(def.perk, level) .. ")\nLuego: nivel " .. after .. " (" .. Config.perkShort(def.perk, after) .. ")"
					else "Regla nueva: nivel 1"
			else
				-- Galería sencilla: su número real (la mordida fija ya multiplicada por Mandíbula titán, etc.)
				desc = Config.miniText(def.kind, def.amount * (stats.miniScale[def.kind] or 1))
				effect = if owned
					then "Ya es tuya. En total: " .. Stats.miniLine(stats, def)
					elseif depth < def.layer then "Excava antes hasta la capa " .. def.layer
					elseif not open then "Excava antes la cámara de su izquierda"
					else "Ahora: " .. Stats.miniLine(stats, def) .. "\nLuego: " .. Stats.miniLine(stats, def, true)
			end
			showCard(def.x, def.y, false, {
				icon = Assets.Icons[def.icon] or Assets.Icons.anthill,
				name = def.name,
				branch = def.branch .. (if isPerk then " · regla de la capa " else " · galería de la capa ") .. def.layer,
				desc = desc,
				effect = effect,
				buyText = if owned or not open then nil elseif food >= def.cost then "Excavar por " .. Format.short(def.cost) else "Faltan " .. Format.short(def.cost - food),
				canBuy = food >= def.cost,
			})
		elseif selected.kind == "workers" then
			local def = Config.NodeById.workers
			local cap = stats.workerCap
			local cost = Stats.workerCost(workers, stats.workerDiscount)
			local full = workers >= cap
			showCard(def.x, def.y, false, {
				icon = Assets.Icons.workers,
				name = def.name,
				branch = def.branch,
				desc = def.desc,
				effect = if cap == 0 then "Excava antes: Guardería" elseif full then "Guardería llena. Súbela de nivel para criar más." else "Tienes " .. workers .. " de " .. cap,
				buyText = if cap == 0 or full then nil elseif food >= cost then "Criar por " .. Format.short(cost) else "Faltan " .. Format.short(cost - food),
				canBuy = food >= cost,
				showMax = cap > 0 and not full,
			})
		elseif selected.kind == "royal" then
			local def = Config.RoyalById[selected.id]
			local view = royalViews[def.id]
			local level = royal[def.id] or 0
			local maxed = level >= def.max
			local cost = Stats.royalCost(def, level)
			showCard(view.button.Position.X.Offset, ROYAL.y, true, {
				icon = iconOf(def),
				name = def.name,
				branch = "Cámara real",
				desc = def.desc,
				effect = effectLines(def.id, level, def.max),
				buyText = if maxed then nil elseif jelly >= cost then "Mejorar por " .. cost .. " de jalea" else "Faltan " .. (cost - jelly) .. " de jalea",
				canBuy = jelly >= cost,
			})
		elseif selected.kind == "swarm" then
			showCard(ROYAL.x + ROYAL.w - 130, ROYAL.y, true, {
				icon = Assets.Icons.queen,
				name = "Enjambrar",
				branch = "Cámara real",
				desc = "La colonia vuela a fundar un hormiguero nuevo. Pierdes comida, obreras, cámaras y capas. Te quedas la jalea, los trofeos y la ropa.",
				effect = if gain >= 1
					then "Ahora ganarías " .. Format.short(gain) .. " de jalea." .. (if State.flag("TartaDone") then "" else "\nCon la tarta comida, el doble.")
					else "Todavía no has reunido comida para una gota de jalea. Sigue hasta la zona 7.",
				buyText = if gain >= 1 then "Enjambrar ya" else nil,
				canBuy = true,
			})
		end
	end

	return anyAffordable
end

-- Historial de niveles: el nivel de antes y el de ahora de cada cámara (atributos N_ y R_), para
-- celebrar "viejo → nuevo" y detectar hitos. El atributo suele llegar justo antes del aviso
-- "Bought"; si llega después, la celebración espera un instante.
local levelBefore: { [string]: number } = {}
local levelNow: { [string]: number } = {}
local levelChangedAt: { [string]: number } = {}

local function watchLevels()
	local localPlayer = Players.LocalPlayer
	for name, value in localPlayer:GetAttributes() do
		local head = string.sub(name, 1, 2)
		if head == "N_" or head == "R_" then
			levelNow[name] = tonumber(value) or 0
		end
	end
	localPlayer.AttributeChanged:Connect(function(name: string)
		local head = string.sub(name, 1, 2)
		if head == "N_" or head == "R_" then
			levelBefore[name] = levelNow[name] or 0
			levelNow[name] = tonumber(localPlayer:GetAttribute(name)) or 0
			levelChangedAt[name] = os.clock()
		end
	end)
end

-- Nivel de antes y de ahora de una cámara si cambió hace poco (si no, antes = nil).
function Tree.levelChange(kind: string, id: string): (number?, number)
	local key = (if kind == "royal" then "R_" else "N_") .. tostring(id)
	local now = levelNow[key] or 0
	local at = levelChangedAt[key]
	if at and os.clock() - at < 2 and (levelBefore[key] or 0) < now then
		return levelBefore[key] or 0, now
	end
	return nil, now
end

-- Hitos que lleva un nivel (Stats.milestones la añade otra parte del juego: puede no existir aún)
function Tree.milestones(level: number): number
	local fn = (Stats :: any).milestones
	if type(fn) ~= "function" then
		return 0
	end
	local ok, count = pcall(fn, level)
	return if ok then tonumber(count) or 0 else 0
end

-- Texto del premio de un hito (Config.Milestones, si dice cuánto multiplica)
local function milestoneText(): string
	local m = (Config :: any).Milestones
	local mult = type(m) == "table" and tonumber(m.Mult or m.mult or m.Multiplier or m.multiplier) or nil
	return if mult then "¡HITO! ×" .. (if mult == math.floor(mult) then tostring(math.floor(mult)) else tostring(mult)) else "¡HITO!"
end

-- Anillo de tinta de color que se abre desde la cámara y un fogonazo dentro de ella
local function flashChamber(button: GuiObject, color: Color3, strength: number)
	local ring = Instance.new("Frame")
	ring.Name = "BuyRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 9
	ring.Parent = button
	Comic.round(ring)
	local stroke = Comic.ink(ring, 7, true)
	stroke.Color = color
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	local grow = TweenInfo.new(0.45 + 0.15 * strength, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(ring, grow, { Size = UDim2.fromScale(1.6 + 0.5 * strength, 1.6 + 0.5 * strength) }):Play()
	TweenService:Create(stroke, grow, { Transparency = 1, Thickness = 1 }):Play()

	local glow = Instance.new("Frame")
	glow.Name = "BuyGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundColor3 = Comic.Paper
	glow.BackgroundTransparency = 0.15
	glow.BorderSizePixel = 0
	glow.ZIndex = 8
	glow.Parent = button
	Comic.round(glow)
	TweenService:Create(glow, TweenInfo.new(0.3), { BackgroundTransparency = 1, Size = UDim2.fromScale(1.25, 1.25) }):Play()
	task.delay(0.8, function()
		ring:Destroy()
		glow:Destroy()
	end)
end

-- Cartelito que sale de la cámara y sube: "3 → 4" (o "¡HITO! ×2" en grande)
local function riseLabel(button: GuiObject, text: string, size: number, color: Color3, big: boolean)
	local label = Comic.label(canvas, text, Comic.Display, size, color)
	label.RichText = true
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = button.Position - UDim2.fromOffset(0, button.Size.Y.Offset / 2 + 6)
	label.Size = UDim2.fromOffset(0, size + 8)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.ZIndex = 12
	label.Rotation = if big then -6 else 3
	local stroke = Comic.ink(label, if big then 5 else 3)
	if big then
		-- Estallido de cómic redondo detrás del texto (no depende de ninguna imagen)
		label.BackgroundTransparency = 0
		label.BackgroundColor3 = Comic.Red
		Comic.round(label, 18)
		local border = Comic.ink(label, 5, true)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 16)
		pad.PaddingRight = UDim.new(0, 16)
		pad.Parent = label
		task.delay(1.2, function()
			TweenService:Create(label, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(border, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end)
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local hold = if big then 1.2 else 0.7
	TweenService:Create(label, TweenInfo.new(hold + 0.3, Enum.EasingStyle.Quad), { Position = label.Position - UDim2.fromOffset(0, if big then 60 else 40) }):Play()
	task.delay(hold, function()
		TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end)
	task.delay(hold + 0.35, function()
		label:Destroy()
	end)
end

-- Celebración de una compra, proporcional: destello en la ficha, nivel viejo → nuevo y, si cruza
-- un hito, un momento grande con fanfarria. Devuelve si fue hito (también lo lee Juice).
local function celebrateLevel(kind: string, id: string, view)
	local old, new = Tree.levelChange(kind, id)
	if not old then
		task.wait(0.15)
		old, new = Tree.levelChange(kind, id)
	end
	local gained = if old then new - old else 1
	local strength = math.clamp(0.3 + 0.1 * gained + new / 40, 0.3, 1)
	local milestone = kind == "node" and old ~= nil and Tree.milestones(new) > Tree.milestones(old)
	if view and view.button then
		flashChamber(view.button, if milestone then Comic.Red else Comic.Yellow, if milestone then 1.4 else strength)
		Comic.punch(view.scale, 1.3 + 0.25 * strength + (if milestone then 0.3 else 0))
		if old then
			riseLabel(view.button, old .. ' → <font color="#FFD23F">' .. new .. "</font>", 28, Comic.Paper, false)
		end
		if milestone then
			task.delay(0.12, riseLabel, view.button, milestoneText(), 46, Comic.Yellow, true)
		end
	end
	if milestone then
		Sfx.fanfare()
		task.delay(0.35, Sfx.pop, 1.9, 0.5)
	else
		-- Más agudo cuanto más alto el nivel: subir se oye
		Sfx.pop(1 + math.min(new, 30) * 0.02)
		if gained > 1 then
			for i = 1, math.min(gained - 1, 4) do
				task.delay(i * 0.05, Sfx.pop, 1.1 + i * 0.1, 0.3)
			end
		end
	end
end

-- Rebote de la cámara recién comprada
function Tree.celebrate(kind: string, id: any)
	if kind == "dig" then
		Sfx.fanfare()
		scrollTo(bandTop(State.depth()) - 120)
		return
	elseif kind == "mini" then
		local view = miniViews[id]
		if view then
			if not view.scale then
				view.scale = Instance.new("UIScale")
				view.scale.Parent = view.button
			end
			Comic.punch(view.scale, 1.5)
			flashChamber(view.button, Comic.Yellow, 0.6)
		end
		Sfx.pop(1.25)
		return
	end
	if kind == "node-max" then
		kind = "node"
	end
	local view = if kind == "royal" then royalViews[id] elseif kind == "workers" then nodeViews.workers else nodeViews[id]
	if kind == "workers" then
		if view then
			Comic.punch(view.scale, 1.35)
			flashChamber(view.button, Comic.Yellow, 0.5)
		end
		Sfx.pop(1.1)
		return
	end
	if type(id) == "string" then
		task.spawn(celebrateLevel, kind, id, view)
	end
end

function Tree.isOpen(): boolean
	return isOpen
end

function Tree.open()
	isOpen = true
	gui.Enabled = true
	Sfx.pop(0.9)
	canvas.CanvasPosition = Vector2.new(0, math.clamp(bandTop(State.depth()) - 150, 0, CONTENT - H))
	Tree.refresh()
end

function Tree.close()
	isOpen = false
	selected = nil
	gui.Enabled = false
end

function Tree.toggle()
	if isOpen then
		Tree.close()
	else
		Tree.open()
	end
end

function Tree.start(remoteFolder: Folder)
	remotes = remoteFolder
	build()
	watchLevels()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonY) then
			Tree.toggle()
		elseif isOpen and input.KeyCode == Enum.KeyCode.Escape then
			Tree.close()
		end
	end)
end

return Tree
