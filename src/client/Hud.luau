-- HUD: caja de narración con la Comida (arriba, al centro, lejos del chat de Roblox) y sus etiquetas,
-- la tira de narración con lo que toca hacer (abajo, sobre las casillas de migas),
-- los botones del lado izquierdo y el interruptor de la música en la esquina.
--
-- Regla de oro: el centro de la pantalla es de la hormiga. Ocupa el 56 % central de ancho y del
-- 22 % al 82 % de alto; ahí no vive nada fijo. Todo se pega a los bordes y es compacto
-- (medidas de diseño pensadas para ~1080 px de alto; Hud.fitScale las adapta a cada pantalla).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Comic = require(script.Parent.Comic)
local Sfx = require(script.Parent.Sfx)

local Hud = {}

local MAX_SLOTS = 10
local SLOT_TILTS = { -7, 4, -3, 8, -5, 3, -8, 5, -2, 6 }
local COMBO_FADE = 1.8 -- segundos sin morder hasta que se esconde la racha

-- Escala: 1 a 1000 px de alto de pantalla, entre 0.7 (letra legible en móvil) y 1.25.
-- Lo que se toca nunca baja de 44 px reales en pantallas táctiles.
local SCALE_REFERENCE = 1000
local SCALE_MIN = 0.7
local SCALE_MAX = 1.25
local MIN_TAP = 44
local TOUCH = UserInputService.TouchEnabled

-- Caja de la Comida (diseño)
local BOX_W = 184
local BOX_H = 60
local SIDE_GAP = 8 -- entre la caja y lo que va a sus lados

-- Botones de la columna izquierda (diseño)
local SIDE_W = 136
local SIDE_H = 44
local SIDE_GAP_Y = 6
local SIDE_W_COMPACT = 96 -- celular: dos columnas que no llegan a las etiquetas de poción/racha

-- Tira de narración: crece con el texto hasta HINT_MAX_WIDTH; si no cabe, dos líneas;
-- si aun así no cabe, letra más pequeña. Nunca "…".
local HINT_MAX_WIDTH = 600
local HINT_PAD_X = 14
local HINT_PAD_Y = 6
local HINT_SIZES = { 20, 18, 16 }
local HINT_SHOW = 8 -- segundos que se ve una pista que no es urgente
local HINT_REST = 30 -- una pista que ya se escondió sola no vuelve antes de esto

local gui: ScreenGui
local foodNumber: TextLabel
local foodPunch: UIScale
local jellyTag: TextLabel
local workerTag: TextLabel
local depthTag: TextLabel
local buffTag: TextLabel
local comboTag: TextLabel
local comboPunch: UIScale
local dock: Frame
local slotRow: Frame
local slots: { Frame } = {}
local slotCapacity = -1
local countLabel: TextLabel?
local lastCarry = 0
local badge: ImageLabel
local storeHolder: Frame

local hintHolder: Frame? = nil
local hintShadow: Frame
local hintLabel: TextLabel
local hintPunch: UIScale
local hintText: string? = nil
local hintFlip = false
local hintToken = 0
local hintRested: { [string]: number } = {} -- texto -> cuándo se escondió solo

local shownDepth = 0
local buffUntil = 0
local lastCombo = 0
local comboAt = 0

Hud.onAnthill = nil :: (() -> ())?
Hud.onStore = nil :: (() -> ())?
Hud.onWardrobe = nil :: (() -> ())?

-- Celular: pantalla táctil y pequeña. Decide la distribución (columnas, paneles compactos). Va por
-- tamaño y no por teclado: el simulador de Studio deja el teclado activo y así se ve como un celular
-- de verdad; una tablet grande o un PC táctil siguen con la distribución de escritorio.
function Hud.compact(): boolean
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	return UserInputService.TouchEnabled and math.min(size.X, size.Y) < 600
end

-- Escala de un widget del HUD según el alto de la pantalla. `tap` es el lado más pequeño
-- (en diseño) de lo que se pulsa dentro: en táctil la escala nunca lo deja por debajo de 44 px.
function Hud.fitScale(widget: GuiObject, tap: number?): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = widget
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local value = math.clamp(camera.ViewportSize.Y / SCALE_REFERENCE, SCALE_MIN, SCALE_MAX)
		if tap and TOUCH then
			value = math.max(value, MIN_TAP / tap)
		end
		scale.Scale = value
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

-- Tamaño de los efectos sueltos en el mundo (palabras de cómic, números, estallidos, bocadillo),
-- diseñados en píxeles fijos: 1 a 1000 px de alto. Se lee en cada efecto, así sigue a la pantalla.
function Hud.fxScale(): number
	if not Hud.compact() then
		return 1 -- en PC, como siempre
	end
	local camera = Workspace.CurrentCamera
	return if camera then math.clamp(camera.ViewportSize.Y / SCALE_REFERENCE, 0.6, 1.2) else 1
end

local function tag(parent: Instance, color: Color3, order: number): (TextLabel, UIScale)
	local label = Comic.label(parent, "", Comic.Display, 17, Comic.Ink)
	label.Size = UDim2.fromOffset(0, 24)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = color
	label.LayoutOrder = order
	label.Rotation = if order % 2 == 0 then 2 else -2
	label.Visible = false
	Comic.ink(label, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	return label, scale
end

local function stack(parent: Instance, horizontal: boolean, align: Enum.HorizontalAlignment, padding: number): Frame
	local frame = Comic.frame(parent)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	layout.HorizontalAlignment = align
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	return frame
end

-- Arriba al centro, en la franja superior (nunca baja del 22 % del alto):
--   [poción / racha]  [ COMIDA ]  [aviso de evento]
--                [capa · obreras · jalea]
-- Lo pasajero va a los lados de la caja, no debajo, así nada empuja hacia el centro.
local function buildTop()
	local top = Comic.frame(gui)
	top.Name = "Top"
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 6)
	top.Size = UDim2.fromOffset(BOX_W, BOX_H + 34)
	Hud.fitScale(top)

	local holder, face = Comic.box(top, UDim2.fromOffset(BOX_W, BOX_H), Comic.Yellow, 4)
	holder.Name = "FoodCaption"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 0)
	holder.Rotation = -2
	Comic.boil(holder, 0.45)

	-- Trama de imprenta en la mitad derecha
	local shade = Comic.frame(face)
	shade.Position = UDim2.fromScale(0.42, 0)
	shade.Size = UDim2.fromScale(0.58, 1)
	Comic.halftone(shade, Comic.Red, 0)

	local title = Comic.label(face, "Comida", Comic.Body, 15, Comic.Ink)
	title.Position = UDim2.fromOffset(12, 3)
	title.Size = UDim2.new(1, -24, 0, 16)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- Las cifras largas encogen en vez de salirse de la caja
	foodNumber = Comic.label(face, "0", Comic.Display, 40, Comic.Ink)
	foodNumber.Position = UDim2.fromOffset(12, 17)
	foodNumber.Size = UDim2.new(1, -24, 0, 40)
	foodNumber.TextXAlignment = Enum.TextXAlignment.Left
	foodNumber.TextScaled = true
	foodNumber.ZIndex = 2
	local numberLimit = Instance.new("UITextSizeConstraint")
	numberLimit.MaxTextSize = 40
	numberLimit.Parent = foodNumber
	foodPunch = Instance.new("UIScale")
	foodPunch.Parent = foodNumber

	-- Debajo, una sola fila con lo de siempre
	local steady = stack(top, true, Enum.HorizontalAlignment.Center, 8)
	steady.Name = "Tags"
	steady.AnchorPoint = Vector2.new(0.5, 0)
	steady.Position = UDim2.new(0.5, 0, 0, BOX_H + 8)
	depthTag = tag(steady, Comic.DirtLight, 1)
	workerTag = tag(steady, Comic.Paper, 2)
	jellyTag = tag(steady, Comic.Cyan, 3)

	-- A la izquierda de la caja, apiladas: poción y racha (pasajeras)
	local fleeting = stack(top, false, Enum.HorizontalAlignment.Right, 6)
	fleeting.Name = "Fleeting"
	fleeting.AnchorPoint = Vector2.new(1, 0)
	fleeting.Position = UDim2.new(0.5, -(BOX_W / 2 + SIDE_GAP), 0, 2)
	buffTag = tag(fleeting, Comic.Green, 1)
	comboTag, comboPunch = tag(fleeting, Comic.Red, 2)

	-- A la derecha de la caja: hueco para avisos compactos de otros módulos (eventos)
	dock = stack(top, false, Enum.HorizontalAlignment.Left, 6)
	dock.Name = "Dock"
	dock.AnchorPoint = Vector2.new(0, 0)
	dock.Position = UDim2.new(0.5, BOX_W / 2 + SIDE_GAP, 0, 4)
end

-- Abajo al centro: la tira de narración y, debajo, las casillas de migas. Escalan juntas.
local function buildBottom()
	local bottom = Comic.frame(gui)
	bottom.Name = "Bottom"
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -12)
	bottom.Size = UDim2.fromOffset(HINT_MAX_WIDTH, 120)
	Hud.fitScale(bottom)

	slotRow = Comic.frame(bottom)
	slotRow.Name = "CarrySlots"
	slotRow.AnchorPoint = Vector2.new(0.5, 1)
	slotRow.Position = UDim2.new(0.5, 0, 1, 0)
	slotRow.AutomaticSize = Enum.AutomaticSize.XY

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = slotRow

	-- Tira de papel con sombra dura. Su tamaño lo calcula fitHint según el texto.
	local holder = Comic.frame(bottom)
	holder.Name = "Hint"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -38)
	holder.Size = UDim2.fromOffset(200, 32)
	holder.Visible = false
	hintPunch = Instance.new("UIScale")
	hintPunch.Parent = holder

	hintShadow = Comic.frame(holder, Comic.Ink)
	hintShadow.Name = "Shadow"
	hintShadow.Size = UDim2.fromScale(1, 1)
	hintShadow.Position = UDim2.fromOffset(4, 4)
	hintShadow.ZIndex = 1

	hintLabel = Comic.label(holder, "", Comic.Body, HINT_SIZES[1], Comic.Ink)
	hintLabel.Size = UDim2.fromScale(1, 1)
	hintLabel.BackgroundTransparency = 0
	hintLabel.BackgroundColor3 = Comic.Paper
	hintLabel.ZIndex = 2
	Comic.ink(hintLabel, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, HINT_PAD_X)
	pad.PaddingRight = UDim.new(0, HINT_PAD_X)
	pad.Parent = hintLabel

	hintHolder = holder
end

local sideKeys: { [string]: boolean } = {} -- teclas de los paneles de la columna (nombre de KeyCode)
local compactSide = false -- celular: la columna es una rejilla de botones estrechos (buildSide)

local function sideButton(parent: Instance, order: number, color: Color3, text: string, icon: string?, key: string?): (Frame, TextButton, TextLabel)
	if key then
		sideKeys[key] = true
	end
	local holder, face = Comic.button(parent, UDim2.fromOffset(SIDE_W, SIDE_H), color, 4)
	holder.LayoutOrder = order
	holder.Rotation = if order % 2 == 0 then -1 else 1

	local x = 12
	if icon and not compactSide then -- en el botón estrecho del celular no cabe el dibujo con el nombre
		local image = Comic.image(face, icon)
		image.Position = UDim2.fromOffset(7, 7)
		image.Size = UDim2.fromOffset(30, 30)
		x = 40
	end
	-- Nombres largos ("Hormiguero") encogen un poco antes que salirse del botón. Alto de una sola
	-- línea: con dos, TextScaled partía la palabra y se veía "HORMIGUER".
	local label = Comic.label(face, text, Comic.Display, 22, Comic.Ink)
	label.Position = UDim2.fromOffset(x, 10)
	label.Size = UDim2.new(1, -x - 8, 0, 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.MinTextSize = 12 -- con 14, "HORMIGUERO" junto al dibujo no cabía y salía cortada
	limit.Parent = label

	if key and UserInputService.KeyboardEnabled then
		local chip = Comic.label(holder, key, Comic.Display, 15, Comic.Ink)
		chip.AnchorPoint = Vector2.new(0.5, 0.5)
		chip.Position = UDim2.new(1, -3, 0, 2)
		chip.Size = UDim2.fromOffset(22, 22)
		chip.BackgroundTransparency = 0
		chip.BackgroundColor3 = Comic.Yellow
		chip.Rotation = 8
		chip.ZIndex = 3
		Comic.ink(chip, 2.5, true)
	end
	return holder, face, label
end

-- Estallido rojo con "!" en la esquina de un botón: hay algo esperándote ahí
local function alertBadge(holder: Frame): ImageLabel
	local burst = Comic.burst(holder, 30, Comic.Red)
	burst.Position = UDim2.new(0, 3, 0, 3)
	burst.ZIndex = 4
	burst.Visible = false
	local mark = Comic.label(burst, "!", Comic.Display, 19, Comic.Paper)
	mark.Size = UDim2.fromScale(1, 1)
	mark.ZIndex = 5
	Comic.boil(burst, 9)
	return burst
end

local function call(callback: (() -> ())?)
	if callback then
		callback()
	end
end

local sideColumn: Frame
local extraButtons = 0

-- La columna lateral no puede crecer con cada sistema nuevo: los paneles se agrupan. Un grupo es un
-- botón que despliega a su derecha los suyos; las teclas de cada panel siguen funcionando igual.
local SIDE_GROUPS = {
	Colonia = { order = 3, color = Color3.fromRGB(255, 176, 64) },
	Estilo = { order = 4, color = Comic.Paper },
}
local SIDE_GROUP_OF = {
	Castas = "Colonia",
	["Órdenes"] = "Colonia",
	Mascotas = "Colonia",
	Vecinas = "Colonia",
	Vestidor = "Estilo",
	Memes = "Estilo",
}
local SIDE_ORDER = { Misiones = 2 } -- los sueltos que quieren un sitio fijo
local sideGroups = {} -- [nombre] = { holder, tray, alert, items = { {holder, alert} } }

local function closeGroups(except: any?)
	for _, group in sideGroups do
		if group ~= except then
			group.tray.Visible = false
		end
	end
end

-- Cierra las bandejas abiertas de "Colonia ›" / "Estilo ›" (p. ej. al abrir un panel por su tecla)
function Hud.closeGroups()
	closeGroups()
end

local function inside(object: GuiObject, point: Vector2): boolean
	local at, size = object.AbsolutePosition, object.AbsoluteSize
	return point.X >= at.X and point.X <= at.X + size.X and point.Y >= at.Y and point.Y <= at.Y + size.Y
end

-- Toque o clic fuera de la bandeja (y de su botón de grupo, que ya la abre y cierra): se cierra.
-- La tecla de cualquier panel de la columna (o Esc) también la cierra.
local function watchGroups()
	UserInputService.InputBegan:Connect(function(input, processed)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			for _, group in sideGroups do
				if group.tray.Visible and not inside(group.tray, point) and not inside(group.holder, point) then
					group.tray.Visible = false
				end
			end
		elseif kind == Enum.UserInputType.Keyboard then
			if input.KeyCode == Enum.KeyCode.Escape or (not processed and sideKeys[input.KeyCode.Name]) then
				closeGroups()
			end
		end
	end)
end

local function refreshGroup(group)
	local anyVisible, anyAlert = false, false
	for _, item in group.items do
		if item.holder.Visible then
			anyVisible = true
			anyAlert = anyAlert or item.alert.Visible
		end
	end
	group.holder.Visible = anyVisible
	group.alert.Visible = anyAlert
	if not anyVisible then
		group.tray.Visible = false
	end
end

local function sideGroup(name: string)
	local group = sideGroups[name]
	if group then
		return group
	end
	local info = SIDE_GROUPS[name]
	local holder, face = sideButton(sideColumn, info.order, info.color, name .. "  ›", nil, nil)
	local tray = Comic.frame(holder)
	tray.Name = "Tray"
	tray.Position = UDim2.new(1, 12, 0, 0)
	tray.AutomaticSize = Enum.AutomaticSize.XY
	tray.Visible = false
	tray.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tray
	group = { holder = holder, tray = tray, alert = alertBadge(holder), items = {} }
	sideGroups[name] = group
	face.MouseButton1Click:Connect(function()
		closeGroups(group)
		tray.Visible = not tray.Visible
	end)
	return group
end

-- Botón dentro de un grupo. Devuelve lo mismo que Hud.addSideButton.
local function groupedButton(groupName: string, text: string, key: string?, color: Color3, callback: () -> ())
	local group = sideGroup(groupName)
	local holder, face = sideButton(group.tray, #group.items + 1, color, text, nil, key)
	local alert = alertBadge(holder)
	local item = { holder = holder, alert = alert }
	table.insert(group.items, item)
	face.MouseButton1Click:Connect(function()
		closeGroups()
		callback()
	end)
	refreshGroup(group)
	return {
		holder = holder,
		setBadge = function(visible: boolean)
			alert.Visible = visible
			refreshGroup(group)
		end,
		setVisible = function(visible: boolean)
			holder.Visible = visible
			refreshGroup(group)
		end,
	}
end

local function buildSide()
	-- Pegada al borde izquierdo. En escritorio, centrada en alto (bajo el chat de Roblox);
	-- en celular, rejilla de dos columnas arriba, para dejar libre la zona del joystick (abajo a la izquierda).
	compactSide = Hud.compact()
	local column = Comic.frame(gui)
	column.Name = "Side"
	if compactSide then
		column.AnchorPoint = Vector2.new(0, 0)
		column.Position = UDim2.new(0, 10, 0, 6)
		-- Ancho fijo: la rejilla reparte las casillas según el ancho del marco; el alto crece solo
		column.Size = UDim2.fromOffset(SIDE_W_COMPACT * 2 + SIDE_GAP_Y + 2, 0)
		column.AutomaticSize = Enum.AutomaticSize.Y
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(SIDE_W_COMPACT, SIDE_H)
		grid.CellPadding = UDim2.fromOffset(SIDE_GAP_Y, SIDE_GAP_Y)
		grid.FillDirectionMaxCells = 2
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = column
	else
		column.AnchorPoint = Vector2.new(0, 0.5)
		column.Position = UDim2.new(0, 12, 0.5, 0)
		column.AutomaticSize = Enum.AutomaticSize.XY
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, SIDE_GAP_Y)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = column
	end
	Hud.fitScale(column, SIDE_H)
	sideColumn = column

	local hillHolder, hillFace = sideButton(column, 1, Comic.DirtLight, "Hormiguero", Assets.Icons.anthill, "Q")
	hillFace.MouseButton1Click:Connect(function()
		call(Hud.onAnthill)
	end)
	badge = alertBadge(hillHolder) -- hay algo que excavar

	groupedButton("Estilo", "Vestidor", "V", Comic.Paper, function()
		call(Hud.onWardrobe)
	end)

	local holder, storeFace = sideButton(column, 50, Comic.Cyan, "Tienda", nil, nil)
	storeHolder = holder
	storeHolder.Visible = false
	storeFace.MouseButton1Click:Connect(function()
		closeGroups()
		call(Hud.onStore)
	end)
	hillFace.MouseButton1Click:Connect(function()
		closeGroups()
	end)
end

-- Botón redondo del sonido, abajo a la izquierda: abre el menú de Música, Efectos y Movimiento suave.
-- No se recuerda entre partidas.
-- En celular es la última casilla de la rejilla del menú: abajo a la izquierda está el joystick.
local function buildMute()
	local corner = Comic.frame(if compactSide then sideColumn else gui)
	corner.Name = "Music"
	if compactSide then
		corner.LayoutOrder = 99 -- la rejilla ya lo escala y le da el tamaño
	else
		corner.AnchorPoint = Vector2.new(0, 1)
		corner.Position = UDim2.new(0, 14, 1, -14)
		corner.Size = UDim2.fromOffset(48, 48)
		Hud.fitScale(corner, 44)
	end

	local holder, face = Comic.button(corner, UDim2.fromOffset(44, 44), Comic.Paper, 4)
	holder.Rotation = -6
	Comic.round(face)
	Comic.round(holder:FindFirstChild("Shadow") :: Frame)

	local note = Comic.label(face, "♪", Comic.Display, 30, Comic.Ink)
	note.Size = UDim2.fromScale(1, 1)
	note.ZIndex = 2

	-- Tachón rojo cuando está en silencio
	local strike = Comic.frame(face, Comic.Red)
	strike.AnchorPoint = Vector2.new(0.5, 0.5)
	strike.Position = UDim2.fromScale(0.5, 0.5)
	strike.Size = UDim2.fromOffset(46, 6)
	strike.Rotation = -45
	strike.ZIndex = 3
	Comic.ink(strike, 2, true)

	local function paint()
		-- Tachado si la música está apagada; atenuado si además (o solo) lo están los efectos
		local muted = Sfx.isMuted()
		local quiet = muted or Sfx.isEffectsMuted()
		face.BackgroundColor3 = if quiet then Comic.DirtLight else Comic.Paper
		note.TextTransparency = if quiet then 0.5 else 0
		strike.Visible = muted
	end
	paint()

	-- Menú de sonido: el botón abre tres interruptores. Cuelga del botón, así hereda su escala
	-- (en táctil, filas de 44 px reales como mínimo). Va como una bandeja más: se cierra al tocar fuera.
	local panel = Comic.frame(corner)
	panel.Name = "SoundMenu"
	panel.AutomaticSize = Enum.AutomaticSize.XY
	panel.Visible = false
	panel.ZIndex = 6
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	local menu = { holder = corner, tray = panel, alert = nil, items = {} }
	sideGroups.Sonido = menu

	local player = Players.LocalPlayer
	if player:GetAttribute("ReducedMotion") == nil then
		-- Arranca como lo tenga en los ajustes de Roblox (si la plataforma lo expone)
		local ok, reduced = pcall(function()
			return (GuiService :: any).ReducedMotionEnabled
		end)
		player:SetAttribute("ReducedMotion", ok and reduced == true)
	end

	local function toggle(order: number, text: string, get: () -> boolean, set: (boolean) -> ())
		local row, rowFace = Comic.button(panel, UDim2.fromOffset(250, 44), Comic.Paper, 4) -- con 220 "Movimiento suave" tocaba el SÍ/NO
		row.LayoutOrder = order
		local label = Comic.label(rowFace, text, Comic.Display, 20, Comic.Ink)
		label.Position = UDim2.fromOffset(12, 0)
		label.Size = UDim2.new(1, -74, 1, 0)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 20
		limit.MinTextSize = 12
		limit.Parent = label
		-- Estado con palabra y color (no solo color)
		local chip = Comic.label(rowFace, "", Comic.Display, 17, Comic.Paper)
		chip.AnchorPoint = Vector2.new(1, 0.5)
		chip.Position = UDim2.new(1, -8, 0.5, 0)
		chip.Size = UDim2.fromOffset(50, 28)
		chip.BackgroundTransparency = 0
		Comic.round(chip, 8)
		Comic.ink(chip, 2.5, true)
		local function paintRow()
			local on = get()
			chip.Text = if on then "SÍ" else "NO"
			chip.BackgroundColor3 = if on then Comic.Green else Comic.Red
		end
		paintRow()
		rowFace.MouseButton1Click:Connect(function()
			set(not get())
			paintRow()
			paint()
		end)
	end
	toggle(1, "Música", function()
		return not Sfx.isMuted()
	end, function(on)
		Sfx.setMuted(not on)
	end)
	toggle(2, "Efectos", function()
		return not Sfx.isEffectsMuted()
	end, function(on)
		Sfx.setEffectsMuted(not on)
	end)
	toggle(3, "Movimiento suave", function()
		return player:GetAttribute("ReducedMotion") == true
	end, function(on)
		player:SetAttribute("ReducedMotion", on)
	end)

	-- PC: a la derecha del botón, creciendo hacia arriba desde la esquina. Celular: a la derecha de
	-- su casilla, hacia abajo o hacia arriba según en qué mitad de la pantalla quede (no se sale).
	local function place()
		local up = not compactSide or corner.AbsolutePosition.Y > gui.AbsoluteSize.Y / 2
		panel.AnchorPoint = Vector2.new(0, if up then 1 else 0)
		panel.Position = UDim2.new(1, 12, if up then 1 else 0, 0)
	end

	face.MouseButton1Click:Connect(function()
		closeGroups(menu)
		panel.Visible = not panel.Visible
		if panel.Visible then
			place()
		end
	end)
end

local function makeSlot(order: number): Frame
	local cell = Comic.frame(slotRow)
	cell.Size = UDim2.fromOffset(28, 28)
	cell.LayoutOrder = order

	local crumb = Comic.frame(cell, Comic.Paper)
	crumb.Name = "Crumb"
	crumb.AnchorPoint = Vector2.new(0.5, 0.5)
	crumb.Position = UDim2.fromScale(0.5, 0.5)
	crumb.Size = UDim2.fromOffset(22, 22)
	crumb.Rotation = SLOT_TILTS[(order - 1) % #SLOT_TILTS + 1]
	Comic.ink(crumb, 2.5)

	local scale = Instance.new("UIScale")
	scale.Parent = crumb
	return crumb
end

local function rebuildSlots(capacity: number)
	for _, child in slotRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(slots)
	countLabel = nil
	slotCapacity = capacity

	if capacity <= MAX_SLOTS then
		for i = 1, capacity do
			slots[i] = makeSlot(i)
		end
	else
		-- Con mucha capacidad ya no caben casillas: una miga y la cuenta
		slots[1] = makeSlot(1)
		local label = Comic.label(slotRow, "", Comic.Display, 26, Comic.Paper)
		label.LayoutOrder = 2
		label.AutomaticSize = Enum.AutomaticSize.XY
		Comic.ink(label, 2.5)
		countLabel = label
	end
end

local function paintSlot(crumb: Frame, filled: boolean, color: Color3)
	crumb.BackgroundColor3 = if filled then color else Comic.Paper
	-- La casilla vacía conserva el borde de tinta entero para leerse sobre cualquier fondo
	crumb.BackgroundTransparency = if filled then 0 else 0.45
end

-- Mide el texto con la fuente real. Devuelve nil si el motor no responde.
local function measure(text: string, size: number, width: number): Vector2?
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = Comic.Body
	params.Size = size
	params.Width = width
	local ok, bounds = pcall(function()
		return TextService:GetTextBoundsAsync(params)
	end)
	return if ok then bounds else nil
end

-- Tamaño de la tira: una línea si cabe; si no, dos líneas al ancho máximo; si tampoco,
-- letra más pequeña. Devuelve (ancho de texto, alto de texto, tamaño de letra, ¿envuelve?).
local function fitHint(text: string)
	local inner = HINT_MAX_WIDTH - HINT_PAD_X * 2
	local lastHeight, lastSize = 0, HINT_SIZES[#HINT_SIZES]
	for _, size in HINT_SIZES do
		local single = measure(text, size, 100000)
		if not single then
			return nil, 0, 0, false
		end
		if single.X <= inner then
			return single.X, single.Y, size, false
		end
		local wrapped = measure(text, size, inner)
		if not wrapped then
			return nil, 0, 0, false
		end
		lastHeight, lastSize = wrapped.Y, size
		if wrapped.Y <= single.Y * 2 + 2 then
			return inner, wrapped.Y, size, true
		end
	end
	-- Ni a la letra más pequeña cabe en dos líneas: se deja crecer en alto
	return inner, lastHeight, lastSize, true
end

local function layoutHint(width: number, height: number, size: number, wrapped: boolean)
	local holder = hintHolder :: Frame
	hintLabel.TextSize = size
	hintLabel.TextWrapped = wrapped
	hintLabel.TextScaled = false
	-- +4 de holgura: el redondeo nunca parte la última palabra en una línea
	holder.Size = UDim2.fromOffset(math.ceil(width) + HINT_PAD_X * 2 + 4, math.ceil(height) + HINT_PAD_Y * 2)
end

local function hideHint()
	hintToken += 1
	if hintHolder then
		hintHolder.Visible = false
	end
end

local function showHint(urgent: boolean)
	local holder = hintHolder
	local text = hintText
	if not holder then
		return
	end
	if not text then
		hideHint()
		return
	end
	hintToken += 1
	local token = hintToken
	task.spawn(function()
		local width, height, size, wrapped = fitHint(text)
		if hintToken ~= token then
			return
		end
		if width then
			layoutHint(width, height, size, wrapped)
		else
			-- Sin medidas: caja fija de dos líneas, el texto se ajusta dentro
			holder.Size = UDim2.fromOffset(HINT_MAX_WIDTH, HINT_SIZES[1] * 2 + HINT_PAD_Y * 2 + 6)
			hintLabel.TextWrapped = true
			hintLabel.TextScaled = true
		end
		hintLabel.Text = text
		-- Cada texto nuevo cae un poco torcido hacia el otro lado, como recortado a mano
		hintFlip = not hintFlip
		holder.Rotation = if hintFlip then -1.2 else 1
		holder.Visible = true
		Comic.punch(hintPunch, 0.55)
	end)
	-- Las pistas de tutorial se apartan solas; vuelven solo si cambia la situación
	if not urgent then
		task.delay(HINT_SHOW, function()
			if hintToken == token and hintText == text then
				hintRested[text] = os.clock()
				hideHint()
			end
		end)
	end
end

-- Bucle ligero: cuenta atrás de la poción y caducidad de la racha
local function tickTimers()
	while true do
		task.wait(0.25)
		local left = buffUntil - Workspace:GetServerTimeNow()
		if left > 0 then
			local seconds = math.ceil(left)
			buffTag.Text = string.format("Comida x2  %d:%02d", seconds // 60, seconds % 60)
			buffTag.Visible = true
		elseif buffTag.Visible then
			buffTag.Visible = false
		end
		if comboTag.Visible and os.clock() - comboAt > COMBO_FADE then
			comboTag.Visible = false
			lastCombo = 0
		end
	end
end

function Hud.start(): ScreenGui
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	buildTop()
	buildBottom()
	buildSide()
	watchGroups()
	buildMute()
	showHint(false)
	task.spawn(tickTimers)
	return gui
end

-- Hueco a la derecha de la caja de Comida, fuera del centro de la pantalla, para avisos
-- compactos de otros módulos (p. ej. el evento en curso). Escala con la cabecera.
function Hud.dock(): Frame
	return dock
end

-- Fila de etiquetas bajo la caja (capa · obreras · jalea), por si un módulo quiere poner algo junto a
-- ellas (LayoutOrder: capa 1, obreras 2, jalea 3). Escala con la cabecera.
function Hud.tagRow(): Frame?
	return if workerTag then workerTag.Parent :: Frame else nil
end

-- Contador de Comida que rueda: al subir, la cifra corre hasta el valor nuevo (~0,6 s); al gastar
-- salta de golpe. Justo después de una entrega (Hud.punchFood) cada cambio da un golpecito.
local shownFood = 0
local targetFood = 0
local rolling = false
local loudUntil = 0

function Hud.setFood(value: number)
	targetFood = value
	if value <= shownFood or shownFood <= 0 or not foodNumber then
		shownFood = value
		if foodNumber then
			foodNumber.Text = Format.short(value)
		end
		return
	end
	if rolling then
		return -- el bucle en marcha ya persigue el valor nuevo
	end
	rolling = true
	task.spawn(function()
		local RunService = game:GetService("RunService")
		local lastText = foodNumber.Text
		local lastTick = 0
		local start = shownFood
		while shownFood < targetFood do
			local dt = RunService.RenderStepped:Wait()
			local gap = targetFood - shownFood
			-- Persigue el objetivo frenando al final; nunca tarda más de ~0,7 s
			shownFood = math.min(targetFood, shownFood + math.max(gap * math.min(1, dt * 7), (targetFood - start) * dt * 1.5, 1))
			local text = Format.short(math.floor(shownFood))
			if text ~= lastText then
				lastText = text
				foodNumber.Text = text
				local now = os.clock()
				if now < loudUntil and now - lastTick > 0.05 then
					lastTick = now
					local progress = math.clamp((shownFood - start) / math.max(targetFood - start, 1), 0, 1)
					Comic.punch(foodPunch, math.max(foodPunch.Scale, 1.1))
					Sfx.tick(1.3 + 0.7 * progress)
				end
			end
		end
		foodNumber.Text = Format.short(targetFood)
		rolling = false
	end)
end

function Hud.punchFood()
	loudUntil = os.clock() + 1
	Comic.punch(foodPunch, 1.35)
end

-- Toda la fila de la carga late (al entrar un trozo, más fuerte si llena)
local function pulseRow(strength: number)
	if not slotRow then
		return
	end
	local scale = slotRow:FindFirstChild("Pulse") :: UIScale?
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "Pulse"
		created.Parent = slotRow
		scale = created
	end
	Comic.punch(scale :: UIScale, strength)
end

-- La carga se acaba de llenar: ola de rebotes por las casillas y la fila entera late.
function Hud.carryFull()
	pulseRow(1.25)
	for i, crumb in slots do
		task.delay((i - 1) * 0.03, function()
			local s = crumb.Parent and crumb:FindFirstChildOfClass("UIScale")
			if s then
				Comic.punch(s, 1.7)
			end
		end)
	end
	if countLabel then
		countLabel.TextColor3 = Comic.Yellow
		task.delay(0.6, function()
			if countLabel then
				countLabel.TextColor3 = Comic.Paper
			end
		end)
	end
end

function Hud.setTags(jelly: number, rebirths: number, workers: number, cap: number)
	jellyTag.Visible = jelly > 0 or rebirths > 0
	jellyTag.Text = "Jalea " .. Format.short(jelly)
	workerTag.Visible = cap > 0
	workerTag.Text = workers .. "/" .. cap .. " obreras"
end

-- Capa excavada y zona más honda a la que llegas.
function Hud.setDepth(depth: number)
	if depth == shownDepth then
		return
	end
	shownDepth = depth
	local zone = Config.Zones[depth]
	depthTag.Text = "Capa " .. depth .. (if zone then " · " .. zone.name else "")
	depthTag.Visible = true
end

-- Comida doble hasta este instante (hora del servidor). La cuenta atrás va sola.
function Hud.setBuff(untilTime: number)
	buffUntil = untilTime
end

-- Racha de mordiscos seguidos. 0 la esconde; cada subida rebota.
function Hud.setCombo(count: number)
	if count <= 0 then
		comboTag.Visible = false
		lastCombo = 0
		return
	end
	comboAt = os.clock()
	comboTag.Text = "Racha x" .. count
	comboTag.Visible = true
	if count > lastCombo then
		Comic.punch(comboPunch, 1.3)
	end
	lastCombo = count
end

-- Tira de narración: lo que toca hacer ahora. nil la esconde.
-- El mismo texto repetido cuenta como "ya mostrado". Salvo que sea `urgent`, la pista se
-- esconde sola a los 8 s y no vuelve hasta que la situación cambie (otro texto) y, si es la
-- misma que ya se apartó, tras un rato.
function Hud.setHint(text: string?, urgent: boolean?)
	if text == hintText then
		return
	end
	hintText = text
	if text and not urgent then
		local rested = hintRested[text]
		if rested and os.clock() - rested < HINT_REST then
			hideHint()
			return
		end
	end
	showHint(urgent == true)
end

function Hud.setCarry(carry: number, capacity: number, color: Color3?)
	if capacity ~= slotCapacity then
		rebuildSlots(capacity)
		lastCarry = 0
	end
	if carry > lastCarry and lastCarry >= 0 then
		pulseRow(1.08)
	end
	local fill = color or Comic.Crumb

	if countLabel then
		countLabel.Text = Format.short(carry) .. "/" .. Format.short(capacity)
		paintSlot(slots[1], carry > 0, fill)
		if carry > lastCarry then
			Comic.punch(slots[1]:FindFirstChildOfClass("UIScale") :: UIScale, 1.4)
		end
	else
		for i, crumb in slots do
			local filled = i <= carry
			paintSlot(crumb, filled, fill)
			if filled and i > lastCarry then
				Comic.punch(crumb:FindFirstChildOfClass("UIScale") :: UIScale, 1.6)
			end
		end
	end
	lastCarry = carry
end

-- Sacude las casillas: se usa cuando intentas morder con la carga llena.
function Hud.shakeCarry()
	for _, crumb in slots do
		Comic.punch(crumb:FindFirstChildOfClass("UIScale") :: UIScale, 0.7)
	end
end

function Hud.setBadge(visible: boolean)
	badge.Visible = visible
end

-- Añade un botón a la columna izquierda, encima de Tienda. Lo usan los módulos opcionales
-- (misiones, mascotas…). Devuelve cómo encender su aviso "!" y cómo esconderlo.
function Hud.addSideButton(text: string, key: string?, color: Color3?, callback: () -> ())
	local groupName = SIDE_GROUP_OF[text]
	if groupName then
		return groupedButton(groupName, text, key, color or Comic.Paper, callback)
	end
	extraButtons += 1
	local holder, face = sideButton(sideColumn, SIDE_ORDER[text] or (9 + extraButtons), color or Comic.Paper, text, nil, key)
	local alert = alertBadge(holder)
	face.MouseButton1Click:Connect(function()
		closeGroups()
		callback()
	end)
	return {
		holder = holder,
		setBadge = function(visible: boolean)
			alert.Visible = visible
		end,
		setVisible = function(visible: boolean)
			holder.Visible = visible
		end,
	}
end

function Hud.showStore(visible: boolean)
	storeHolder.Visible = visible
end

return Hud
