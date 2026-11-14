-- Mascotas en el cliente: el panel (puesto de huevos, posadero y tablero de bichos), la
-- eclosión y los seguidores que acompañan a cada hormiga en el mundo.
--
-- El panel va pegado al borde derecho, como el vestidor, para que veas a tu hormiga y a sus
-- bichos mientras eliges. Arriba el huevo en su nido; en medio una rama con tres huecos
-- (el posadero: lo que llevas puesto); abajo un tablero de corcho con tus bichos clavados.
-- Al tocar uno sube su ficha por abajo con lo que se puede hacer con él.
--
-- Seguidores: el servidor publica en cada jugador el atributo PetsEquipped
-- ("mariquita:2,abeja:1"); aquí cada cliente dibuja los de todos con piezas ancladas
-- que se mueven de una vez con BulkMoveTo, siguiendo a su dueña con un muelle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Format = require(ReplicatedStorage.Shared.Format)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local PetModels = require(ReplicatedStorage.Shared.PetModels)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Pets = {}

local player = Players.LocalPlayer

-- Panel
local W = 420
local MARGIN = 16
local HEADER = 92
local PAD = 20
local INNER = W - PAD * 2 - 10
local SHEET = 132
local EGG_Y = 10
local PERCH_Y = 232
local BOARD_Y = 470
local ROW = 120
local PER_ROW = 4

local EGG = Color3.fromRGB(255, 244, 222)
local CORK = Color3.fromRGB(206, 160, 108)
local DIM = Color3.fromRGB(226, 216, 196)
local BUY_COOLDOWN = 0.2

-- Seguidores
local SLOTS = { Vector3.new(-2.8, 0, 2.2), Vector3.new(2.8, 0, 2.2), Vector3.new(0, 0, 4.3) }
local STIFF = { 55, 45, 36 } -- cada hueco sigue con un muelle algo distinto: no van en bloque
local SNAP = 45 -- más lejos que esto de su sitio, aparece directamente allí
local VIEW = 320 -- más lejos de la cámara no se dibujan
local HOP = { rana = 0.95, grillo = 0.8, escarabajo = 0.35, escarabajoOro = 0.35 }
local FLAP = { mariposa = { 9, 0.85 } } -- frecuencia y amplitud; el resto aletea rápido

local remote: RemoteEvent? = nil
local inv = { pets = {}, equipped = {}, eggs = {} }
local sideButton = nil

local gui: ScreenGui
local panel: Frame
local face: Frame
local fit: UIScale
local body: ScrollingFrame
local foodLabel: TextLabel
local isOpen = false

local eggHolder: Frame
local eggScale: UIScale
local eggCaption: TextLabel
local buyFace: TextButton
local buyLabel: TextLabel
local buyHolder: Frame
local lastBuy = 0

local perch = {} -- [hueco] = { holder, button, stroke, scale, plus, chip, view, key }
local perchTotals: TextLabel

local boardTitle: TextLabel
local cork: Frame
local emptyNote: TextLabel
local cards = {} -- [id] = { holder, button, stroke, scale, tag, worn, fuse }
local fresh = {} -- [id] = true: recién llegados, rebotan al aparecer

local sheet: Frame
local sheetPortrait: Frame
local sheetView: ViewportFrame? = nil
local sheetId: number? = nil
local sheetShown = false
local sheetName: TextLabel
local sheetRarity: TextLabel
local sheetBonus: TextLabel
local equipFace: TextButton
local equipLabel: TextLabel
local fuseFace: TextButton
local fuseLabel: TextLabel
local releaseFace: TextButton
local releaseLabel: TextLabel
local selected: number? = nil
local armedId: number? = nil
local armedUntil = 0

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

local function send(action: string, id: number?)
	if remote then
		remote:FireServer(action, id)
	end
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

-- Etiqueta pequeña de tinta, crece con el texto
local function chip(parent: Instance, size: number): TextLabel
	local label = Comic.label(parent, "", Comic.Display, size, Comic.Ink)
	label.Size = UDim2.fromOffset(0, size + 6)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = Comic.Yellow
	Comic.ink(label, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 7)
	pad.PaddingRight = UDim.new(0, 7)
	pad.Parent = label
	return label
end

---------------------------------------------------------------------------------------------
-- Inventario

local function find(id: number?)
	if not id then
		return nil
	end
	for _, entry in inv.pets do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function isEquipped(id: number): boolean
	return table.find(inv.equipped, id) ~= nil
end

local function kindCounts(): { [string]: number }
	local counts = {}
	for _, entry in inv.pets do
		local kind = PetDefs.kind(entry)
		counts[kind] = (counts[kind] or 0) + 1
	end
	return counts
end

local function sorted()
	local list = table.clone(inv.pets)
	table.sort(list, function(a, b)
		local pa, pb = PetDefs.power(a), PetDefs.power(b)
		if pa ~= pb then
			return pa > pb
		end
		return a.id > b.id
	end)
	return list
end

local function eggState(): (number, number, boolean)
	local depth = State.depth()
	local bought = inv.eggs[depth] or 0
	return depth, PetDefs.eggPrice(depth, bought), #inv.pets >= PetDefs.MaxPets
end

local function bonusText(entry): string
	local bonus = PetDefs.bonusOf(entry)
	return PetDefs.percent(PetDefs.power(entry)) .. " " .. (if bonus then bonus.name else "")
end

local function tint(rarity: number): Color3
	local def = PetDefs.Rarities[rarity] or PetDefs.Rarities[1]
	return def.color:Lerp(Comic.Paper, 0.45)
end

---------------------------------------------------------------------------------------------
-- Dibujos

-- El bicho dentro de un círculo de la interfaz, en tres cuartos
local function petView(parent: GuiObject, entry, size: number): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency = 1
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Size = UDim2.fromOffset(size, size)
	view.Ambient = Color3.fromRGB(176, 176, 176)
	view.LightColor = Color3.new(1, 1, 1)
	view.LightDirection = Vector3.new(-0.6, -1, -0.8)
	view.ZIndex = 5
	view.Parent = parent

	local model = PetModels.build(entry.s, entry.r, true)
	model:PivotTo(CFrame.Angles(0, math.rad(-30), 0))
	model.Parent = view
	local box, extents = model:GetBoundingBox()
	local radius = extents.Magnitude / 2
	local distance = radius / math.tan(math.rad(15)) * 0.92
	local center = box.Position
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, distance * 0.38, -distance), center)
	camera.Parent = view
	view.CurrentCamera = camera
	return view
end

-- Huevo moteado. Llena a su padre.
local SPOTS = {
	{ 0.3, 0.3, 0.2, Comic.Cyan },
	{ 0.68, 0.45, 0.24, Comic.Green },
	{ 0.36, 0.66, 0.18, Comic.Red },
	{ 0.7, 0.74, 0.14, Comic.Yellow },
}

local function drawEgg(parent: GuiObject): Frame
	local shell = Comic.frame(parent, EGG)
	shell.Size = UDim2.fromScale(1, 1)
	Comic.round(shell)
	Comic.ink(shell, 4).LineJoinMode = Enum.LineJoinMode.Round
	for _, spot in SPOTS do
		local dot = Comic.frame(shell, spot[4])
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(spot[1], spot[2])
		dot.Size = UDim2.fromScale(spot[3], spot[3] * 0.72)
		Comic.round(dot)
		Comic.ink(dot, 2)
	end
	local shine = Comic.frame(shell, Color3.new(1, 1, 1))
	shine.BackgroundTransparency = 0.25
	shine.Position = UDim2.fromScale(0.2, 0.12)
	shine.Size = UDim2.fromScale(0.14, 0.18)
	shine.Rotation = -25
	Comic.round(shine)
	return shell
end

---------------------------------------------------------------------------------------------
-- Pintar

local function paintHeader()
	if foodLabel then
		foodLabel.Text = "Comida " .. Format.short(State.num("Food"))
	end
end

local function paintEgg()
	if not buyLabel then
		return
	end
	local depth, price, full = eggState()
	eggCaption.Text = "Huevo de capa " .. depth
	buyLabel.TextTransparency = 0
	if full then
		buyFace.BackgroundColor3 = DIM
		buyLabel.Text = "Sin sitio"
	else
		buyLabel.Text = "Incubar · " .. Format.short(price)
		if State.num("Food") >= price then
			buyFace.BackgroundColor3 = Comic.Yellow
		else
			buyFace.BackgroundColor3 = DIM
			buyLabel.TextTransparency = 0.45
		end
	end
end

local function paintBadge()
	if not sideButton then
		return
	end
	local _, price, full = eggState()
	local alert = #inv.pets == 0 and not full and State.num("Food") >= price
	for kind, count in kindCounts() do
		if count >= 3 and not kind:match("|5|") then
			alert = true
		end
	end
	sideButton.setBadge(alert)
end

local function paintPerch()
	local entries = {}
	for slot, view in perch do
		local entry = find(inv.equipped[slot])
		local key = if entry then entry.id .. ":" .. entry.s .. ":" .. entry.r else ""
		if key ~= view.key then
			view.key = key
			if view.view then
				view.view:Destroy()
				view.view = nil
			end
			if entry then
				view.view = petView(view.button, entry, 96)
				Comic.punch(view.scale, 1.25)
			end
		end
		if entry then
			table.insert(entries, entry)
			view.button.BackgroundColor3 = tint(entry.r)
			view.button.BackgroundTransparency = 0
			view.plus.Visible = false
			view.chip.Text = bonusText(entry)
			view.chip.BackgroundColor3 = PetDefs.bonusOf(entry).color
		else
			view.button.BackgroundColor3 = Comic.Paper
			view.button.BackgroundTransparency = 0.35
			view.plus.Visible = true
			view.chip.Text = "Libre"
			view.chip.BackgroundColor3 = Comic.Paper
		end
		view.stroke.Color = if entry and entry.id == selected then Comic.Red else Comic.Ink
		view.stroke.Thickness = if entry and entry.id == selected then 6 else 4
	end

	local totals = PetDefs.totals(entries)
	local parts = {}
	for _, kind in PetDefs.BonusOrder do
		local mult = totals[kind]
		if mult > 1 then
			local text = PetDefs.Bonuses[kind].name .. " " .. PetDefs.times(mult)
			if mult >= PetDefs.MaxMult then
				text ..= " (tope)"
			end
			table.insert(parts, text)
		end
	end
	perchTotals.Text = if #parts > 0 then "En total: " .. table.concat(parts, " · ") else "Pon hasta tres bichos en la rama"
end

local function paintSheet()
	local entry = find(selected)
	if not entry then
		selected = nil
	end
	local shown = entry ~= nil
	if shown ~= sheetShown then
		sheetShown = shown
		local goal = if shown then UDim2.new(0, 0, 1, 0) else UDim2.new(0, 0, 1, SHEET + 14)
		TweenService:Create(sheet, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goal }):Play()
	end
	if not entry then
		return
	end

	if sheetId ~= entry.id then
		sheetId = entry.id
		if sheetView then
			sheetView:Destroy()
		end
		sheetView = petView(sheetPortrait, entry, 104)
	end
	local rarity = PetDefs.Rarities[entry.r]
	local bonus = PetDefs.bonusOf(entry)
	sheetPortrait.BackgroundColor3 = tint(entry.r)
	sheetName.Text = PetDefs.SpeciesById[entry.s].name
	sheetRarity.Text = rarity.name .. " · capa " .. entry.l
	sheetRarity.BackgroundColor3 = rarity.color
	sheetBonus.Text = bonusText(entry)
	sheetBonus.BackgroundColor3 = bonus.color

	local worn = isEquipped(entry.id)
	if worn then
		equipLabel.Text = "Quitar"
		equipFace.BackgroundColor3 = Comic.DirtLight
	else
		equipLabel.Text = if #inv.equipped >= PetDefs.MaxEquipped then "Cambiar" else "Poner"
		equipFace.BackgroundColor3 = Comic.Green
	end

	local count = kindCounts()[PetDefs.kind(entry)] or 0
	fuseLabel.TextTransparency = 0
	if entry.r >= #PetDefs.Rarities then
		fuseLabel.Text = "Ya es mítica"
		fuseFace.BackgroundColor3 = DIM
		fuseLabel.TextTransparency = 0.45
	else
		-- Apagado dice qué falta: tres de la misma especie y rareza (la capa no importa)
		fuseLabel.Text = if count >= 3 then "Fusionar 3" elseif count == 2 then "Falta 1 igual" else "Faltan 2 iguales"
		fuseFace.BackgroundColor3 = if count >= 3 then Comic.Yellow else DIM
		if count < 3 then
			fuseLabel.TextTransparency = 0.45
		end
	end

	local armed = armedId == entry.id and os.clock() < armedUntil
	releaseLabel.Text = if armed then "¿Seguro?" else "Soltar"
	releaseFace.BackgroundColor3 = if armed then Comic.Red else Comic.Paper
	releaseLabel.TextColor3 = if armed then Comic.Paper else Comic.Ink
end

local selectPet: (id: number?) -> ()

local function makeCard(entry)
	local holder = Comic.frame(cork)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Size = UDim2.fromOffset(86, 112)
	holder.ZIndex = 3

	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Text = ""
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = UDim2.new(0.5, 0, 0, 4)
	button.Size = UDim2.fromOffset(78, 78)
	button.BackgroundColor3 = tint(entry.r)
	button.BorderSizePixel = 0
	button.ZIndex = 4
	button.Parent = holder
	Comic.round(button)
	local stroke = Comic.ink(button, 3, true)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	local scale = Instance.new("UIScale")
	scale.Parent = button
	petView(button, entry, 74)

	-- Chincheta que lo clava al corcho
	local pin = Comic.frame(holder, Comic.Red)
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	pin.Position = UDim2.new(0.5, 0, 0, 5)
	pin.Size = UDim2.fromOffset(14, 14)
	pin.ZIndex = 7
	Comic.round(pin)
	Comic.ink(pin, 2)

	local tag = chip(holder, 17)
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, 84)
	tag.Text = PetDefs.percent(PetDefs.power(entry))
	tag.BackgroundColor3 = PetDefs.bonusOf(entry).color
	tag.ZIndex = 6

	local worn = chip(holder, 13)
	worn.AnchorPoint = Vector2.new(1, 0)
	worn.Position = UDim2.new(1, 4, 0, 0)
	worn.Text = "Puesto"
	worn.BackgroundColor3 = Comic.Red
	worn.TextColor3 = Comic.Paper
	worn.Rotation = 10
	worn.ZIndex = 8

	local fuse = Comic.burst(holder, 38, Comic.Yellow)
	fuse.Position = UDim2.fromOffset(12, 14)
	fuse.ZIndex = 8
	local three = Comic.label(fuse, "x3", Comic.Display, 16, Comic.Ink)
	three.Size = UDim2.fromScale(1, 1)
	three.ZIndex = 9

	local card = { holder = holder, button = button, stroke = stroke, scale = scale, worn = worn, fuse = fuse }
	button.MouseButton1Click:Connect(function()
		Comic.punch(scale, 1.18)
		Sfx.pop(1.15)
		selectPet(if selected == entry.id then nil else entry.id)
	end)
	return card
end

local function paintBoard()
	local list = sorted()
	local alive = {}
	for _, entry in list do
		alive[entry.id] = true
	end
	for id, card in cards do
		if not alive[id] then
			card.holder:Destroy()
			cards[id] = nil
		end
	end

	local counts = kindCounts()
	local cell = (INNER + 12 - 16) / PER_ROW
	for index, entry in list do
		local card = cards[entry.id]
		if not card then
			card = makeCard(entry)
			cards[entry.id] = card
		end
		local row = (index - 1) // PER_ROW
		local col = (index - 1) % PER_ROW
		card.holder.Position = UDim2.fromOffset(8 + cell * (col + 0.5), 10 + row * ROW)
		card.holder.Rotation = ({ -3, 2, -1.5, 3, 1, -2.5 })[index % 6 + 1]
		local chosen = entry.id == selected
		card.stroke.Color = if chosen then Comic.Red else Comic.Ink
		card.stroke.Thickness = if chosen then 6 else (if entry.r >= 4 then 5 else 3)
		card.worn.Visible = isEquipped(entry.id)
		card.fuse.Visible = entry.r < #PetDefs.Rarities and (counts[PetDefs.kind(entry)] or 0) >= 3
		if fresh[entry.id] then
			fresh[entry.id] = nil
			Comic.punch(card.scale, 1.45)
		end
	end

	local rows = math.max(1, math.ceil(#list / PER_ROW))
	local boardH = if #list == 0 then 120 else rows * ROW + 14
	cork.Size = UDim2.fromOffset(INNER + 12, boardH)
	emptyNote.Visible = #list == 0
	boardTitle.Text = "Bichos " .. #list .. "/" .. PetDefs.MaxPets
	body.CanvasSize = UDim2.fromOffset(0, BOARD_Y + 44 + boardH + 18 + (if selected then SHEET else 0))
end

local function paintLive()
	paintBadge()
	if isOpen then
		paintHeader()
		paintEgg()
		paintSheet()
	end
end

local function paintAll()
	paintBadge()
	if not gui then
		return
	end
	paintHeader()
	paintEgg()
	paintPerch()
	paintSheet()
	paintBoard()
end

selectPet = function(id: number?)
	selected = id
	armedId = nil
	paintPerch()
	paintSheet()
	paintBoard()
end

---------------------------------------------------------------------------------------------
-- Acciones

local function buy()
	local now = os.clock()
	if now - lastBuy < BUY_COOLDOWN then
		return
	end
	local _, price, full = eggState()
	if full then
		shake(buyHolder)
		Sfx.pop(0.7)
		Bubble.flash("No caben más bichos. Suelta o fusiona alguno", 3)
		return
	end
	if State.num("Food") < price then
		shake(buyHolder)
		Sfx.pop(0.7)
		return
	end
	lastBuy = now
	Comic.punch(eggScale, 1.2)
	send("Buy")
end

local function onEquip()
	local entry = find(selected)
	if not entry then
		return
	end
	Sfx.pop(1.25)
	send(if isEquipped(entry.id) then "Unequip" else "Equip", entry.id)
end

local function onFuse()
	local entry = find(selected)
	if not entry then
		return
	end
	local count = kindCounts()[PetDefs.kind(entry)] or 0
	if entry.r >= #PetDefs.Rarities or count < 3 then
		shake(fuseFace.Parent :: GuiObject)
		Sfx.pop(0.7)
		if entry.r < #PetDefs.Rarities then
			Bubble.flash("Hacen falta tres iguales: misma especie, rareza y capa", 4)
		end
		return
	end
	send("Fuse", entry.id)
end

local function onRelease()
	local entry = find(selected)
	if not entry then
		return
	end
	if armedId == entry.id and os.clock() < armedUntil then
		armedId = nil
		Sfx.pop(0.8)
		send("Release", entry.id)
		selectPet(nil)
		return
	end
	armedId = entry.id
	armedUntil = os.clock() + 3
	Sfx.pop(0.9)
	paintSheet()
	task.delay(3.05, function()
		if armedId == entry.id and os.clock() >= armedUntil then
			armedId = nil
			paintSheet()
		end
	end)
end

local function onSlot(slot: number)
	local entry = find(inv.equipped[slot])
	if entry then
		Sfx.pop(1.15)
		selectPet(if selected == entry.id then nil else entry.id)
		return
	end
	local chosen = find(selected)
	if chosen and not isEquipped(chosen.id) then
		Sfx.pop(1.25)
		send("Equip", chosen.id)
	else
		Comic.punch(perch[slot].scale, 0.85)
		Bubble.flash("Toca un bicho del tablero y luego Poner", 3)
	end
end

---------------------------------------------------------------------------------------------
-- Construcción del panel

local function sheetButton(parent: Instance, x: number, w: number, color: Color3, callback: () -> ()): (TextButton, TextLabel)
	local holder, buttonFace = Comic.button(parent, UDim2.fromOffset(w, 40), color, 4)
	holder.Position = UDim2.fromOffset(x, 80)
	holder.ZIndex = 12
	buttonFace.ZIndex = 12
	local label = Comic.label(buttonFace, "", Comic.Display, 20, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 13
	buttonFace.MouseButton1Click:Connect(callback)
	return buttonFace, label
end

local function buildEggStand()
	-- Nido de ramitas con el huevo dentro
	eggHolder = Comic.frame(body)
	eggHolder.AnchorPoint = Vector2.new(0.5, 1)
	at(eggHolder, PAD + 76, EGG_Y + 178, 110, 140)
	eggHolder.ZIndex = 3
	drawEgg(eggHolder)
	eggScale = Instance.new("UIScale")
	eggScale.Parent = eggHolder
	Comic.boil(eggHolder, 1.5)
	local eggButton = Instance.new("TextButton")
	eggButton.BackgroundTransparency = 1
	eggButton.Text = ""
	eggButton.Size = UDim2.fromScale(1, 1)
	eggButton.ZIndex = 6
	eggButton.Parent = eggHolder
	eggButton.MouseButton1Click:Connect(buy)

	local nest = Comic.frame(body, Comic.DirtLight)
	nest.AnchorPoint = Vector2.new(0.5, 0)
	at(nest, PAD + 76, EGG_Y + 160, 164, 46)
	nest.ZIndex = 7
	Comic.round(nest, 22)
	Comic.ink(nest, 3)
	for i, rotation in { -18, 12, -6 } do
		local twig = Comic.frame(nest, Comic.Dirt)
		twig.AnchorPoint = Vector2.new(0.5, 0.5)
		twig.Position = UDim2.new(0.5, (i - 2) * 34, 0.5, (i % 2) * 6 - 3)
		twig.Size = UDim2.fromOffset(64, 6)
		twig.Rotation = rotation
		twig.ZIndex = 8
		Comic.round(twig, 3)
	end

	eggCaption = Comic.label(body, "", Comic.Display, 30, Comic.Ink)
	at(eggCaption, PAD + 170, EGG_Y + 4, 210, 34)
	eggCaption.TextXAlignment = Enum.TextXAlignment.Left
	eggCaption.Rotation = -1.5
	eggCaption.ZIndex = 3

	local sub = Comic.label(body, "Más capa, bichos más fuertes", Comic.Body, 15, Comic.DirtDark)
	at(sub, PAD + 170, EGG_Y + 36, 210, 18)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 3

	-- Probabilidades, una línea por rareza con su color
	for i, rarity in PetDefs.Rarities do
		local y = EGG_Y + 60 + (i - 1) * 19
		local dot = Comic.frame(body, rarity.color)
		at(dot, PAD + 172, y + 3, 12, 12)
		dot.ZIndex = 3
		Comic.round(dot)
		Comic.ink(dot, 2)
		local line = Comic.label(body, rarity.name .. "  " .. PetDefs.chance(rarity.chance), Comic.Body, 16, Comic.Ink)
		at(line, PAD + 190, y, 190, 18)
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.ZIndex = 3
	end

	local holder, buttonFace = Comic.button(body, UDim2.fromOffset(212, 52), Comic.Yellow, 5)
	at(holder, PAD + 166, EGG_Y + 160)
	holder.ZIndex = 3
	buttonFace.ZIndex = 3
	buyHolder = holder
	buyFace = buttonFace
	buyLabel = Comic.label(buttonFace, "", Comic.Display, 26, Comic.Ink)
	buyLabel.Size = UDim2.fromScale(1, 1)
	buyLabel.ZIndex = 4
	buttonFace.MouseButton1Click:Connect(buy)
end

local function buildPerch()
	local heading = Comic.label(body, "Posadero", Comic.Display, 30, Comic.Red)
	at(heading, PAD, PERCH_Y, 200, 34)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Rotation = -2
	heading.ZIndex = 3
	Comic.ink(heading, 3)

	local bestHolder, bestFace = Comic.button(body, UDim2.fromOffset(112, 38), Comic.Cyan, 4)
	at(bestHolder, PAD + INNER - 116, PERCH_Y + 2)
	bestHolder.Rotation = 1.5
	bestHolder.ZIndex = 3
	bestFace.ZIndex = 3
	local bestLabel = Comic.label(bestFace, "Los mejores", Comic.Display, 20, Comic.Ink)
	bestLabel.Size = UDim2.fromScale(1, 1)
	bestLabel.ZIndex = 4
	bestFace.MouseButton1Click:Connect(function()
		if #inv.pets == 0 then
			shake(bestHolder)
			return
		end
		Sfx.pop(1.3)
		send("Best")
	end)

	-- La rama donde se posan
	local twig = Comic.frame(body, Comic.Dirt)
	at(twig, PAD - 6, PERCH_Y + 146, INNER + 12, 14)
	twig.Rotation = -1.2
	twig.ZIndex = 2
	Comic.round(twig, 7)
	Comic.ink(twig, 3)
	local leaf = Comic.frame(body, Comic.Green)
	at(leaf, PAD + INNER - 24, PERCH_Y + 134, 30, 16)
	leaf.Rotation = 28
	leaf.ZIndex = 2
	Comic.round(leaf)
	Comic.ink(leaf, 2)

	for slot = 1, PetDefs.MaxEquipped do
		local cx = PAD + INNER * (slot - 0.5) / PetDefs.MaxEquipped
		local holder = Comic.frame(body)
		holder.AnchorPoint = Vector2.new(0.5, 0)
		at(holder, cx, PERCH_Y + 46, 100, 100)
		holder.ZIndex = 3

		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundColor3 = Comic.Paper
		button.BorderSizePixel = 0
		button.ZIndex = 4
		button.Parent = holder
		Comic.round(button)
		local stroke = Comic.ink(button, 4, true)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		local scale = Instance.new("UIScale")
		scale.Parent = holder

		local plus = Comic.label(button, "+", Comic.Display, 46, Comic.Ink)
		plus.Size = UDim2.fromScale(1, 1)
		plus.TextTransparency = 0.7
		plus.ZIndex = 5

		local label = chip(body, 17)
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromOffset(cx, PERCH_Y + 166)
		label.Rotation = if slot % 2 == 0 then 2 else -2
		label.ZIndex = 4

		perch[slot] = { holder = holder, button = button, stroke = stroke, scale = scale, plus = plus, chip = label, key = nil, view = nil }
		button.MouseButton1Click:Connect(function()
			onSlot(slot)
		end)
	end

	perchTotals = Comic.label(body, "", Comic.Body, 16, Comic.Ink)
	at(perchTotals, PAD, PERCH_Y + 200, INNER, 20)
	perchTotals.TextXAlignment = Enum.TextXAlignment.Left
	perchTotals.TextTruncate = Enum.TextTruncate.AtEnd
	perchTotals.ZIndex = 3
end

local function buildBoard()
	boardTitle = Comic.label(body, "", Comic.Display, 30, Comic.Red)
	at(boardTitle, PAD, BOARD_Y, 200, 34)
	boardTitle.TextXAlignment = Enum.TextXAlignment.Left
	boardTitle.Rotation = 1.5
	boardTitle.ZIndex = 3
	Comic.ink(boardTitle, 3)

	local hint = Comic.label(body, "Tres iguales se fusionan", Comic.Body, 14, Comic.DirtDark)
	at(hint, PAD + 150, BOARD_Y + 10, INNER - 150, 18)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.ZIndex = 3

	cork = Comic.frame(body, CORK)
	at(cork, PAD - 6, BOARD_Y + 44, INNER + 12, 120)
	cork.ZIndex = 2
	Comic.round(cork, 6)
	Comic.ink(cork, 4)
	local dots = Comic.halftone(cork, Comic.Dirt, 120)
	dots.ImageTransparency = 0.5
	dots.ZIndex = 2

	emptyNote = Comic.label(cork, "Incuba un huevo y tu primer bicho aparecerá aquí", Comic.Body, 17, Comic.Ink)
	emptyNote.Size = UDim2.new(1, -40, 1, 0)
	emptyNote.Position = UDim2.fromOffset(20, 0)
	emptyNote.TextWrapped = true
	emptyNote.ZIndex = 3
end

local function buildSheet()
	sheet = Comic.frame(face, Comic.Paper)
	sheet.Name = "Ficha"
	sheet.AnchorPoint = Vector2.new(0, 1)
	sheet.Size = UDim2.new(1, 0, 0, SHEET)
	sheet.Position = UDim2.new(0, 0, 1, SHEET + 14)
	sheet.ZIndex = 10
	sheet.Active = true
	local line = Comic.frame(sheet, Comic.Ink)
	line.Size = UDim2.new(1, 0, 0, 5)
	line.ZIndex = 11
	local dots = Comic.halftone(sheet, Comic.Yellow, 0)
	dots.ImageTransparency = 0.35
	dots.ZIndex = 10

	sheetPortrait = Comic.frame(sheet, Comic.Paper)
	at(sheetPortrait, PAD, 18, 100, 100)
	sheetPortrait.ZIndex = 11
	Comic.round(sheetPortrait)
	Comic.ink(sheetPortrait, 4)

	sheetName = Comic.label(sheet, "", Comic.Display, 30, Comic.Ink)
	at(sheetName, PAD + 116, 10, 260, 32)
	sheetName.TextXAlignment = Enum.TextXAlignment.Left
	sheetName.TextTruncate = Enum.TextTruncate.AtEnd
	sheetName.ZIndex = 12

	local row = Comic.frame(sheet)
	at(row, PAD + 116, 44, 270, 26)
	row.ZIndex = 12
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	sheetRarity = chip(row, 17)
	sheetRarity.LayoutOrder = 1
	sheetRarity.ZIndex = 12
	sheetBonus = chip(row, 17)
	sheetBonus.LayoutOrder = 2
	sheetBonus.ZIndex = 12

	local x = PAD + 116
	equipFace, equipLabel = sheetButton(sheet, x, 74, Comic.Green, onEquip)
	fuseFace, fuseLabel = sheetButton(sheet, x + 80, 100, Comic.Yellow, onFuse)
	releaseFace, releaseLabel = sheetButton(sheet, x + 186, 76, Comic.Paper, onRelease)
end

-- Escala por altura de pantalla sin pasar de casi media pantalla de ancho (como el vestidor)
local function resize()
	local camera = Workspace.CurrentCamera
	if not camera or not panel then
		return
	end
	local view = camera.ViewportSize
	local s = math.clamp(math.min(view.Y / 800, view.X * 0.45 / W), 0.5, 1.25)
	fit.Scale = s
	panel.Size = UDim2.fromOffset(W, math.max(240, (view.Y - MARGIN * 2) / s))
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Pets"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder, panelFace = Comic.box(gui, UDim2.fromOffset(W, 700), Comic.Paper, 10)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -MARGIN - 10, 0, MARGIN)
	panelFace.Active = true
	panelFace.ClipsDescendants = true
	panel = holder
	face = panelFace
	fit = Instance.new("UIScale")
	fit.Parent = holder
	local dots = Comic.halftone(face, Comic.Green, 90)
	dots.ImageTransparency = 0.6

	local title = Comic.label(face, "Mascotas", Comic.Display, 54, Comic.Ink)
	at(title, PAD, 8, 260, 56)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -2
	title.ZIndex = 3

	foodLabel = Comic.label(face, "", Comic.Display, 26, Comic.Yellow)
	at(foodLabel, PAD + 4, 58, 260, 28)
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
	closeFace.MouseButton1Click:Connect(function()
		Pets.close()
	end)

	local line = Comic.frame(face, Comic.Ink)
	at(line, 0, HEADER - 3, W, 5)
	line.ZIndex = 3

	body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(0, HEADER + 2)
	body.Size = UDim2.new(1, 0, 1, -HEADER - 2)
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ScrollBarThickness = 8
	body.ScrollBarImageColor3 = Comic.Ink
	body.ElasticBehavior = Enum.ElasticBehavior.Never
	body.ZIndex = 2
	body.Parent = face

	buildEggStand()
	buildPerch()
	buildBoard()
	buildSheet()

	resize()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
end

function Pets.isOpen(): boolean
	return isOpen
end

-- Cierra los otros paneles anclados para no pisarse
local function closeOthers()
	for _, name in { "Wardrobe", "Tree", "Store" } do
		local module = script.Parent:FindFirstChild(name)
		if module then
			pcall(function()
				local lib = require(module) :: any
				if lib.isOpen() then
					lib.close()
				end
			end)
		end
	end
end

function Pets.open()
	if not gui then
		return
	end
	closeOthers()
	isOpen = true
	resize()
	paintAll()
	gui.Enabled = true
	Sfx.pop(0.9)
	local rest = UDim2.new(1, -MARGIN - 10, 0, MARGIN)
	panel.Position = rest + UDim2.fromOffset(W * fit.Scale + 40, 0)
	TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = rest }):Play()
end

function Pets.close()
	isOpen = false
	if gui then
		gui.Enabled = false
	end
	if selected then
		selected = nil
		armedId = nil
		paintAll()
	end
end

function Pets.toggle()
	if isOpen then
		Pets.close()
	else
		Pets.open()
	end
end

---------------------------------------------------------------------------------------------
-- Eclosión: el huevo tiembla, se agrieta y sale el bicho. Menos de 2.5 s; tocar la acelera.

local SHAKE_TIME = 0.85
local CRACK_TIME = 0.3
local HOLD_TIME = 1.1
local FADE_TIME = 0.2

local hatchGui: ScreenGui? = nil
local hatchToken = 0

local function closeHatch()
	hatchToken += 1
	if hatchGui then
		hatchGui:Destroy()
		hatchGui = nil
	end
end

local function waitFor(seconds: number, token: number, stop: (() -> boolean)?): boolean
	local start = os.clock()
	while os.clock() - start < seconds do
		if token ~= hatchToken or (stop and stop()) then
			break
		end
		RunService.RenderStepped:Wait()
	end
	return token == hatchToken
end

local function playHatch(entry)
	closeHatch()
	local token = hatchToken
	local rarity = PetDefs.Rarities[entry.r] or PetDefs.Rarities[1]
	local species = PetDefs.SpeciesById[entry.s]
	if not species then
		return
	end

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "PetHatch"
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = 40
	overlay.Parent = player:WaitForChild("PlayerGui")
	hatchGui = overlay

	local dim = Comic.frame(overlay, Comic.Ink)
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	local stage = Comic.frame(overlay)
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(560, 560)
	stage.ZIndex = 2
	Comic.autoScale(stage, 800)
	local inner = Comic.frame(stage)
	inner.Size = UDim2.fromScale(1, 1)
	local pop = Instance.new("UIScale")
	pop.Parent = inner

	local glow = Comic.burst(inner, 120, rarity.color)
	glow.Position = UDim2.new(0.5, 0, 0.5, 10)
	glow.Visible = false

	local egg = Comic.frame(inner)
	egg.AnchorPoint = Vector2.new(0.5, 0.5)
	egg.Position = UDim2.new(0.5, 0, 0.5, 10)
	egg.Size = UDim2.fromOffset(170, 214)
	drawEgg(egg)

	-- Grieta en zigzag
	local cracks = {}
	for i = 1, 5 do
		local piece = Comic.frame(egg, Comic.Ink)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.new(0, 14 + (i - 0.5) * 28.4, 0.47, 0)
		piece.Size = UDim2.fromOffset(34, 6)
		piece.Rotation = if i % 2 == 0 then -38 else 38
		piece.ZIndex = 4
		piece.Visible = false
		table.insert(cracks, piece)
	end

	local catcher = Instance.new("TextButton")
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = 50
	catcher.Parent = overlay

	local skip = false
	local revealed = false
	catcher.MouseButton1Click:Connect(function()
		if revealed then
			if token == hatchToken then
				closeHatch()
			end
		else
			skip = true
		end
	end)

	local function reveal()
		egg.Visible = false
		glow.Visible = false

		-- Las dos mitades de la cáscara salen despedidas
		for half = 1, 2 do
			local clip = Comic.frame(inner)
			clip.AnchorPoint = Vector2.new(0.5, 0)
			clip.Position = UDim2.new(0.5, 0, 0.5, 10 - 107 + (half - 1) * 107)
			clip.Size = UDim2.fromOffset(170, 107)
			clip.ClipsDescendants = true
			clip.ZIndex = 3
			local shell = Comic.frame(clip)
			shell.Position = UDim2.fromOffset(0, if half == 1 then 0 else -107)
			shell.Size = UDim2.fromOffset(170, 214)
			drawEgg(shell)
			local goal = if half == 1 then UDim2.new(0.5, -150, 0.5, -260) else UDim2.new(0.5, 140, 0.5, 220)
			TweenService:Create(clip, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goal }):Play()
			task.delay(0.36, function()
				clip:Destroy()
			end)
		end

		local burst = Comic.burst(inner, 300 + 45 * entry.r, rarity.color)
		burst.Position = UDim2.new(0.5, 0, 0.5, -10)
		burst.ZIndex = 1
		local burstPop = Instance.new("UIScale")
		burstPop.Parent = burst
		Comic.punch(burstPop, 0.2)
		Comic.boil(burst, 3 + entry.r)

		local view = petView(inner, entry, 250)
		view.Position = UDim2.new(0.5, 0, 0.5, -20)
		view.ZIndex = 4
		local viewPop = Instance.new("UIScale")
		viewPop.Parent = view
		Comic.punch(viewPop, 0.3)

		local name = Comic.label(inner, "¡" .. species.name .. "!", Comic.Display, 58, Comic.Paper)
		name.AnchorPoint = Vector2.new(0.5, 0)
		name.Position = UDim2.new(0.5, 0, 0, 398)
		name.Size = UDim2.fromOffset(560, 62)
		name.Rotation = -4
		name.ZIndex = 6
		Comic.ink(name, 4)

		local tag = chip(inner, 26)
		tag.AnchorPoint = Vector2.new(0.5, 0)
		tag.Position = UDim2.new(0.5, 0, 0, 464)
		tag.Text = rarity.name .. " · capa " .. entry.l
		tag.BackgroundColor3 = rarity.color
		tag.Rotation = 2
		tag.ZIndex = 6

		local bonus = Comic.label(inner, bonusText(entry), Comic.Display, 28, Comic.Yellow)
		bonus.AnchorPoint = Vector2.new(0.5, 0)
		bonus.Position = UDim2.new(0.5, 0, 0, 508)
		bonus.Size = UDim2.fromOffset(400, 32)
		bonus.ZIndex = 6
		Comic.ink(bonus, 3)

		-- Cuanto más rara, más ruido
		if entry.r >= 3 then
			Sfx.fanfare()
		else
			Sfx.pop(1.35)
		end
		if entry.r >= 4 then
			Fx.speed(0.9)
		end
		if entry.r >= 5 then
			local flash = Comic.frame(overlay, Color3.new(1, 1, 1))
			flash.Size = UDim2.fromScale(1, 1)
			flash.ZIndex = 40
			TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		end
	end

	task.spawn(function()
		-- Tiembla, cada vez más
		local start = os.clock()
		local ticks = 0
		while not skip and token == hatchToken do
			local t = os.clock() - start
			if t >= SHAKE_TIME then
				break
			end
			local k = t / SHAKE_TIME
			egg.Rotation = math.sin(t * 38) * (4 + 14 * k)
			egg.Position = UDim2.new(0.5, 0, 0.5, 10 - math.abs(math.sin(t * 19)) * 8 * k)
			if t > ticks * 0.28 then
				ticks += 1
				Sfx.pop(0.55 + ticks * 0.1)
			end
			RunService.RenderStepped:Wait()
		end
		if token ~= hatchToken then
			return
		end
		egg.Rotation = 0
		egg.Position = UDim2.new(0.5, 0, 0.5, 10)

		-- Se agrieta y asoma el color de la rareza
		if not skip then
			for _, piece in cracks do
				piece.Visible = true
			end
			glow.Visible = true
			TweenService:Create(glow, TweenInfo.new(CRACK_TIME), { Size = UDim2.fromOffset(300, 300) }):Play()
			Sfx.pop(0.5)
			if not waitFor(CRACK_TIME, token, function()
				return skip
			end) then
				return
			end
		end

		reveal()
		revealed = true
		if not waitFor(HOLD_TIME, token) then
			return
		end
		TweenService:Create(pop, TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		TweenService:Create(dim, TweenInfo.new(FADE_TIME), { BackgroundTransparency = 1 }):Play()
		if waitFor(FADE_TIME, token) then
			closeHatch()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Seguidores en el mundo

local container: Model
local owners: { [Player]: { list: { any } } } = {}

local function scaled(cf: CFrame, s: number): CFrame
	return cf.Rotation + cf.Position * s
end

local function setScale(pet, s: number)
	if pet.scale ~= s then
		pcall(function()
			pet.model:ScaleTo(s)
		end)
	end
	pet.scale = s
	for i, offset in pet.offsets do
		local flap = pet.flaps[i]
		if flap then
			pet.scaledHinge[i] = scaled(flap.hinge, s)
			pet.scaledRel[i] = scaled(flap.rel, s)
		else
			pet.scaledOffsets[i] = scaled(offset, s)
		end
	end
end

local function newFollower(speciesId: string, rarity: number, slot: number)
	local model = PetModels.build(speciesId, rarity)
	local root = model.PrimaryPart :: BasePart
	local pet = {
		model = model,
		key = speciesId .. ":" .. rarity,
		slot = slot,
		parts = {},
		offsets = {},
		flaps = {},
		scaledOffsets = {},
		scaledHinge = {},
		scaledRel = {},
		height = model:GetAttribute("Height") or 0.5,
		gait = model:GetAttribute("Gait") or "hop",
		hopAmp = HOP[speciesId] or 0.5,
		flap = FLAP[speciesId] or { 30, 0.55 },
		pos = nil :: Vector3?,
		vel = Vector3.zero,
		yaw = 0,
		hop = 0,
		phase = math.random() * 6,
		scale = 1,
		shown = false,
	}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(pet.parts, part)
			local index = #pet.parts
			local offset = root.CFrame:ToObjectSpace(part.CFrame)
			pet.offsets[index] = offset
			local hinge = part:GetAttribute("Hinge")
			local side = part:GetAttribute("Flap")
			if typeof(hinge) == "CFrame" and type(side) == "number" then
				pet.flaps[index] = { hinge = hinge, rel = hinge:ToObjectSpace(offset), side = side }
			end
		end
	end
	setScale(pet, 1)
	return pet
end

local function dropOwner(target: Player)
	local owner = owners[target]
	if owner then
		for _, pet in owner.list do
			pet.model:Destroy()
		end
		owners[target] = nil
	end
end

-- Rehace los seguidores de un jugador; reutiliza los que no cambian
local function refreshOwner(target: Player)
	local owner = owners[target]
	if not owner then
		owner = { list = {} }
		owners[target] = owner
	end
	local old = owner.list
	local list = {}
	for slot, want in PetDefs.decode(target:GetAttribute("PetsEquipped")) do
		local key = want.s .. ":" .. want.r
		local reuse = nil
		for i, pet in old do
			if pet.key == key then
				reuse = table.remove(old, i)
				break
			end
		end
		if reuse then
			reuse.slot = slot
			list[slot] = reuse
		else
			list[slot] = newFollower(want.s, want.r, slot)
		end
	end
	for _, pet in old do
		pet.model:Destroy()
	end
	owner.list = list
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function hide(pet, forget: boolean)
	if pet.shown then
		pet.model.Parent = nil
		pet.shown = false
	end
	if forget then
		pet.pos = nil
	end
end

local function step(rawDt: number)
	local dt = math.min(rawDt, 0.1)
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local cameraPos = if camera then camera.CFrame.Position else nil
	local n = 0

	for target, owner in owners do
		local character = target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			for _, pet in owner.list do
				hide(pet, true)
			end
			continue
		end
		if cameraPos and (root.Position - cameraPos).Magnitude > VIEW then
			for _, pet in owner.list do
				hide(pet, false)
			end
			continue
		end

		local ownerScale = character:GetScale()
		local petScale = 1 + 0.45 * (ownerScale - 1)
		local look = root.CFrame.LookVector
		local ownerYaw = if math.abs(look.X) + math.abs(look.Z) > 0.01 then math.atan2(-look.X, -look.Z) else 0
		local turn = CFrame.Angles(0, ownerYaw, 0)
		local ground = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight

		for _, pet in owner.list do
			if math.abs(pet.scale - petScale) > 0.03 then
				setScale(pet, petScale)
			end
			local offset = turn:VectorToWorldSpace(SLOTS[pet.slot] * ownerScale)
			local goal = Vector3.new(root.Position.X + offset.X, ground, root.Position.Z + offset.Z)

			-- Muelle: persigue su sitio y frena al llegar
			if not pet.pos or (pet.pos - goal).Magnitude > SNAP then
				pet.pos = goal
				pet.vel = Vector3.zero
			end
			local k = STIFF[pet.slot] or 40
			local damping = 2 * math.sqrt(k) * 0.85
			pet.vel += ((goal - pet.pos) * k - pet.vel * damping) * dt
			pet.pos += pet.vel * dt

			local flat = Vector3.new(pet.vel.X, 0, pet.vel.Z)
			local speed = flat.Magnitude
			local wantYaw = if speed > 1.2 then math.atan2(-flat.X, -flat.Z) else ownerYaw
			local diff = (wantYaw - pet.yaw + math.pi) % (2 * math.pi) - math.pi
			pet.yaw += diff * math.min(1, dt * 8)

			local s = pet.scale
			local lift = pet.height * s
			local pitch = 0
			local flapAngle = 0
			if pet.gait == "fly" then
				lift += (1.5 + math.sin(now * 2.4 + pet.phase) * 0.3) * s
				pitch = -math.clamp(speed * 0.03, 0, 0.35)
				flapAngle = math.sin(now * pet.flap[1] + pet.phase) * pet.flap[2]
			elseif pet.gait == "crawl" then
				if speed > 0.8 then
					pet.hop += dt * (5 + speed * 0.8)
				end
				lift += math.abs(math.sin(pet.hop)) * 0.12 * s * math.clamp(speed / 4, 0, 1)
			else
				if speed > 0.8 then
					pet.hop += dt * (6 + speed * 0.6)
				end
				lift += math.abs(math.sin(pet.hop)) * pet.hopAmp * s * math.clamp(speed / 5, 0, 1)
				pitch = -math.clamp(speed * 0.012, 0, 0.12)
			end

			local base = CFrame.new(pet.pos.X, pet.pos.Y + lift, pet.pos.Z) * CFrame.Angles(0, pet.yaw, 0) * CFrame.Angles(pitch, 0, 0)
			if not pet.shown then
				pet.model.Parent = container
				pet.shown = true
			end
			for i, part in pet.parts do
				local flap = pet.flaps[i]
				n += 1
				moveParts[n] = part
				if flap then
					moveFrames[n] = base * pet.scaledHinge[i] * CFrame.Angles(0, 0, flap.side * flapAngle) * pet.scaledRel[i]
				else
					moveFrames[n] = base * pet.scaledOffsets[i]
				end
			end
		end
	end

	for i = #moveParts, n + 1, -1 do
		moveParts[i] = nil
		moveFrames[i] = nil
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function startFollowers()
	container = Instance.new("Model")
	container.Name = "PetFollowers"
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Comic.Ink
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = container
	container.Parent = Workspace

	local function track(target: Player)
		refreshOwner(target)
		target:GetAttributeChangedSignal("PetsEquipped"):Connect(function()
			if target.Parent then
				refreshOwner(target)
			end
		end)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(dropOwner)
	for _, target in Players:GetPlayers() do
		track(target)
	end
	RunService.Heartbeat:Connect(step)
end

---------------------------------------------------------------------------------------------
-- Arranque

local function onEvent(kind: string, payload: any)
	if kind == "Sync" and type(payload) == "table" then
		inv.pets = if type(payload.pets) == "table" then payload.pets else {}
		inv.equipped = if type(payload.equipped) == "table" then payload.equipped else {}
		inv.eggs = if type(payload.eggs) == "table" then payload.eggs else {}
		if selected and not find(selected) then
			selected = nil
		end
		paintAll()
	elseif kind == "Hatch" and type(payload) == "table" then
		fresh[payload.id] = true
		playHatch(payload)
	elseif kind == "Fused" and type(payload) == "table" then
		fresh[payload.id] = true
		selected = payload.id
		Sfx.fanfare()
		local species = PetDefs.SpeciesById[payload.s]
		local rarity = PetDefs.Rarities[payload.r]
		if species and rarity then
			Bubble.flash("¡Fusión! " .. species.name .. " · " .. rarity.name, 3)
		end
	elseif kind == "Fail" and type(payload) == "string" then
		Sfx.pop(0.7)
		Bubble.flash(payload, 3)
	end
end

function Pets.start(remoteFolder: Folder)
	startFollowers()

	local found = remoteFolder:WaitForChild("Pet", 30)
	if not found or not found:IsA("RemoteEvent") then
		warn("[CRUNCH!] No llegó el remoto de mascotas")
		return
	end
	remote = found

	build()
	sideButton = Hud.addSideButton("Mascotas", "M", Comic.Green, Pets.toggle)
	found.OnClientEvent:Connect(onEvent)
	found:FireServer("Sync")

	State.onChange(paintLive)
	paintAll()

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape then
			if isOpen then
				Pets.close()
			end
		elseif input.KeyCode == Enum.KeyCode.M and not processed then
			Pets.toggle()
		end
	end)

	-- Solo en Studio: abrir el panel desde la barra de comandos
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("DevPets"):Connect(Pets.toggle)
	end
end

return Pets
