-- Vestidor: un probador de verdad, pegado al borde derecho. A la izquierda del probador, tu hormiga
-- en grande sobre una peana que gira (arrástrala para darle la vuelta) con los botes de pintura a sus
-- pies; a la derecha, las prendas expuestas cada una a su manera: trajes en perchas, sombreros en su
-- sombrerera y estelas como cintas colgadas.
--
-- Tocar una prenda te la prueba al momento en la peana, aunque no sea tuya. Debajo, un único botón
-- dice qué pasa si lo pulsas: "Ponérmelo", "Comprar por N", "Te falta N" o "Solo VIP". Los trajes y
-- estelas que hacen conjunto llevan el mismo sello de lacre y se pueden poner de una vez.
-- La cortina de arriba enseña todo o solo lo tuyo. Se compra con comida una vez y es para siempre;
-- ponérselo luego es gratis.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AntLook = require(ReplicatedStorage.Shared.AntLook)
local AntModel = require(ReplicatedStorage.Shared.AntModel)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Outfits = require(ReplicatedStorage.Shared.Outfits)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Trails = require(ReplicatedStorage.Shared.Trails)
local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Store = require(script.Parent.Store)
local ViewFit = require(script.Parent.ViewFit)

local Wardrobe = {}

local player = Players.LocalPlayer

-- Medidas de diseño (Hud.fitScale las adapta; el alto se ajusta a la pantalla)
local W = 790
local H = 760
local MARGIN = 16
local PAD = 16
local ROD = 46 -- barra de la cortina
local STAGE_W = 290
local GAP = 14
local RACK_X = PAD + STAGE_W + GAP
local RACK_W = W - RACK_X - PAD
local FILTER_H = 46
local POTS_H = 78
local ACTION_H = 176
local TAP = 48

local WALL = Color3.fromRGB(248, 236, 214)
local WALL_LINE = Color3.fromRGB(236, 218, 190)
local CURTAIN = Color3.fromRGB(200, 52, 64)
local CURTAIN_FOLD = Color3.fromRGB(160, 34, 48)
local ROD_COLOR = Color3.fromRGB(196, 150, 70)
local CARD = Color3.fromRGB(226, 196, 150) -- cartón de las etiquetas
local DIM = Color3.fromRGB(214, 206, 190)
local WOOD = Color3.fromRGB(176, 120, 72)
local TIN = Color3.fromRGB(196, 198, 208)
local BOXES = { Color3.fromRGB(255, 196, 214), Color3.fromRGB(186, 232, 206), Color3.fromRGB(210, 196, 255), Color3.fromRGB(255, 228, 150) }
local SEAL = Color3.fromRGB(190, 30, 44)

local ATTRIBUTE = { skin = "Skin", hat = "Hat", trail = "Trail", outfit = "Outfit" }
local LISTS = { skin = Config.Skins, hat = Config.Hats, trail = Trails.list, outfit = Outfits.list }
local KIND_NAME = { skin = "Color", hat = "Sombrero", trail = "Estela", outfit = "Traje" }
local ORDER = { "outfit", "hat", "trail", "skin" } -- orden del teclado

local gui: ScreenGui
local panel: Frame
local fit: UIScale
local face: Frame
local remotes
local isOpen = false
local closing = 0

local rack: ScrollingFrame
local stageCol: Frame
local potsRow: Frame
local mineOnly = false

local views = {} -- prendas dibujadas: { kind, def, holder, base, tag, pin, halo, seal, scale }
local sections = {} -- [kind] = { top = y en el estante } (para desplazar hasta ella)

-- Probador
local trial: { [string]: string } = {} -- lo que te estás probando, por tipo
local selection: any = nil -- { kind, id } o { set = { outfit, trail } }
local preview: Model? = nil
local world: WorldModel
local camera: Camera
local viewport: ViewportFrame
local stand: { BasePart } = {}
local center = Vector3.zero
local fitState = {} -- encuadre de la cámara (ViewFit): se mide la caja real de la hormiga vestida
local angle = 0.6
local dragging: InputObject? = nil
local dragX = 0
local lastDrag = -10
local swoosh: Frame
local swooshPaint: UIGradient

-- Mostrador de abajo
local action = {} :: any
local foodTag: TextLabel
local revert: TextButton
local filterTab: Frame
local filterWords = {} :: { [string]: TextLabel }
local filterCurtain: Frame
local curtains: { Frame } = {}

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

-- Forma centrada en (x, y). radius: nil = recta, -1 = redonda del todo
local function blob(parent: Instance, color: Color3?, x: number, y: number, w: number, h: number, rot: number?, radius: number?, inkWidth: number?): Frame
	local f = Comic.frame(parent, color)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	if radius then
		Comic.round(f, if radius < 0 then nil else radius)
	end
	if inkWidth and inkWidth > 0 then
		Comic.ink(f, inkWidth, true)
	end
	return f
end

local function fitText(label: TextLabel, max: number, min: number)
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = min
	limit.Parent = label
end

local function button(parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Parent = parent
	return b
end

local function equipped(kind: string): string
	local value = player:GetAttribute(ATTRIBUTE[kind])
	if type(value) == "string" and value ~= "" then
		return value
	end
	return LISTS[kind][1].id
end

local function defOf(kind: string, id: string)
	for _, def in LISTS[kind] do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function owns(def): boolean
	if def.pass then
		return State.flag("P_" .. def.pass)
	end
	return def.cost <= 0 or State.owns(def.id)
end

-- Estado de una prenda: "worn", "owned", "affordable", "expensive" o "locked"
local function stateOf(kind: string, def): string
	if def.pass and not State.flag("P_" .. def.pass) then
		return "locked"
	end
	if equipped(kind) == def.id then
		return "worn"
	end
	if owns(def) then
		return "owned"
	end
	return if State.num("Food") >= def.cost then "affordable" else "expensive"
end

local function wearing(kind: string): string
	return trial[kind] or equipped(kind)
end

-------------------------------------------------------------------------------
-- Peana: tu hormiga en 3D con lo que llevas y lo que te pruebas
-------------------------------------------------------------------------------

local function framePreview()
	local model = preview
	if not model then
		return
	end
	local cf, size = model:GetBoundingBox()
	center = cf.Position
	ViewFit.reset(fitState) -- ropa nueva: se vuelve a medir y la cámara se coloca de golpe
	local width = math.max(size.X, size.Z) * 0.95 + 0.6
	local floor = cf.Position.Y - size.Y / 2
	local up = CFrame.Angles(0, 0, math.rad(90))
	stand[1].Size = Vector3.new(0.5, width, width)
	stand[1].CFrame = CFrame.new(center.X, floor - 0.25, center.Z) * up
	stand[2].Size = Vector3.new(0.3, width + 0.5, width + 0.5)
	stand[2].CFrame = CFrame.new(center.X, floor - 0.6, center.Z) * up
	-- Tachuelas en el borde: así se ve que la peana gira
	for i = 3, #stand do
		local a = (i - 3) / (#stand - 2) * math.pi * 2
		stand[i].CFrame = CFrame.new(center.X + math.cos(a) * width * 0.42, floor, center.Z + math.sin(a) * width * 0.42)
	end
end

local function lookNow()
	local look = Stats.look(State.nodes(), State.royal(), State.depth(), State.num("Rebirths"), wearing("skin"), wearing("hat")) :: any
	look.wings = look.wings or State.flag("P_goldWings")
	look.outfit = wearing("outfit")
	look.scale = 1
	return look
end

local function paintSwoosh()
	local def = Trails.byId[wearing("trail")]
	local colors = def and def.colors
	swoosh.Visible = colors ~= nil and #colors > 0
	if swoosh.Visible then
		local keys = {}
		local count = #colors
		for k, color in colors do
			table.insert(keys, ColorSequenceKeypoint.new(if count == 1 then 0 else (k - 1) / (count - 1), color))
		end
		if count == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
		end
		swooshPaint.Color = ColorSequence.new(keys)
	end
end

local function dressPreview()
	if not preview then
		local ok, model = pcall(AntModel.build)
		if not ok or not model then
			return
		end
		for _, d in model:GetDescendants() do
			if d:IsA("Highlight") or d:IsA("LocalScript") or d:IsA("Script") then
				d:Destroy()
			end
		end
		model.Name = "Probador"
		local root = model.PrimaryPart
		if root then
			root.Anchored = true
		end
		model.Parent = world
		preview = model
	end
	local model = preview :: Model
	local ok, err = pcall(AntLook.apply, model, lookNow())
	if not ok then
		warn("[CRUNCH!] Vestidor (probador):", err)
	end
	model:PivotTo(CFrame.new(0, 0, 0))
	framePreview()
	paintSwoosh()
end

local function spin(dt: number)
	if not isOpen then
		return
	end
	if not dragging and os.clock() - lastDrag > 2.5 then
		angle += dt * 0.35
	end
	-- Antes: distancia fija según el lado mayor (tope 15) y sin contar la proporción del marco, así
	-- que la hormiga se salía por los lados. Ahora cabe entera, peana incluida (0,9 por debajo).
	if preview then
		ViewFit.orbit(camera, viewport, preview, angle, fitState, 0.9)
	end
end

-------------------------------------------------------------------------------
-- Dibujos de las prendas
-------------------------------------------------------------------------------

-- Sombreros, en un cuadro de 44 x 34
local HATS = {
	hoja = function(p)
		blob(p, Color3.fromRGB(110, 200, 90), 22, 17, 18, 30, 50, -1, 2)
		blob(p, Comic.Ink, 22, 17, 2, 24, 50)
	end,
	lazo = function(p)
		local pink = Color3.fromRGB(255, 120, 170)
		blob(p, pink, 12, 17, 16, 16, 45, 3, 2)
		blob(p, pink, 32, 17, 16, 16, 45, 3, 2)
		blob(p, Color3.fromRGB(230, 80, 140), 22, 17, 9, 11, 0, 3, 2)
	end,
	chistera = function(p)
		blob(p, Comic.Ink, 22, 14, 22, 22, 0, 2)
		blob(p, Comic.Red, 22, 20, 22, 4)
		blob(p, Comic.Ink, 22, 27, 36, 5, 0, 2)
	end,
	gafas = function(p)
		blob(p, Comic.Ink, 13, 17, 15, 13, 0, -1)
		blob(p, Comic.Ink, 31, 17, 15, 13, 0, -1)
		blob(p, Comic.Ink, 22, 15, 8, 3)
		blob(p, Comic.Cyan, 11, 15, 4, 3, -20, -1)
		blob(p, Comic.Cyan, 29, 15, 4, 3, -20, -1)
	end,
	casco = function(p)
		blob(p, Comic.Yellow, 22, 18, 30, 22, 0, 11, 2)
		blob(p, Comic.Yellow, 22, 27, 38, 5, 0, 2, 2)
		blob(p, Comic.Ink, 22, 14, 3, 14)
	end,
	corona = function(p)
		local gold = Color3.fromRGB(255, 200, 60)
		for _, x in { 12, 22, 32 } do
			blob(p, gold, x, 12, 10, 10, 45, nil, 2)
		end
		blob(p, gold, 22, 22, 32, 12, 0, 2, 2)
		blob(p, Comic.Red, 22, 22, 6, 6, 0, -1)
	end,
}

-- Pista de las partículas de una estela sobre su cinta: estrellas, puntos, chispas o llamas
local function particleMarks(ribbon: GuiObject, def, height: number)
	if not def.dots then
		return
	end
	for i = 1, 4 do
		local color = def.dots[(i - 1) % #def.dots + 1]
		local x = if i % 2 == 0 then 28 else 12
		local y = height * (0.2 + 0.17 * i)
		if def.mark == "star" then
			blob(ribbon, color, x, y, 9, 9, 45, nil, 2)
			blob(ribbon, color, x, y, 9, 9, 0)
		elseif def.mark == "spark" then
			blob(ribbon, color, x, y, 3, 12, if i % 2 == 0 then 35 else -30, nil, 2)
		elseif def.mark == "flame" then
			blob(ribbon, color, x, y, 8, 12, 0, -1, 2)
		else
			blob(ribbon, color, x, y, 8, 8, 0, -1, 2)
		end
	end
end

local function paintRibbon(frame: GuiObject, colors: { Color3 }?)
	if colors and #colors > 0 then
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		local keys = {}
		local count = #colors
		for k, color in colors do
			table.insert(keys, ColorSequenceKeypoint.new(if count == 1 then 0 else (k - 1) / (count - 1), color))
		end
		if count == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
		end
		local paint = Instance.new("UIGradient")
		paint.Rotation = 90
		paint.Color = ColorSequence.new(keys)
		paint.Parent = frame
	else
		frame.BackgroundColor3 = Comic.Paper
	end
end

-- Forma suelta del dibujo de un traje: "o" óvalo, "r" rectángulo redondeado, "d" rombo
local function iconShape(parent: Instance, spec)
	local kind, x, y, w, h, color, rot = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7] or 0
	if kind == "d" then
		blob(parent, color, x, y, w, w, 45 + rot, 2, 2)
	else
		blob(parent, color, x, y, w, h, rot, if kind == "o" then -1 else 3, 2)
	end
end

-- Sello de lacre: lo llevan los trajes y estelas que hacen conjunto
local function seal(parent: Instance, x: number, y: number): Frame
	local s = blob(parent, SEAL, x, y, 20, 20, 0, -1, 2)
	s.ZIndex = 6
	local inner = blob(s, Color3.fromRGB(230, 70, 80), 10, 10, 10, 10, 0, -1)
	inner.ZIndex = 6
	return s
end

-- Etiqueta de cartón colgada de un hilo: precio, "Puesto" o "VIP"
local function hangTag(parent: Instance, x: number, y: number, rot: number): TextLabel
	local thread = blob(parent, Comic.Ink, x, y - 7, 2, 12, 0)
	thread.ZIndex = 5
	local tag = Comic.label(parent, "", Comic.Display, 16, Comic.Ink)
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.fromOffset(x, y)
	tag.Size = UDim2.fromOffset(0, 20)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = CARD
	tag.Rotation = rot
	tag.ZIndex = 6
	Comic.ink(tag, 2, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = tag
	return tag
end

-- Pinza roja de "Puesto"
local function clothespin(parent: Instance, x: number, y: number): Frame
	local pin = blob(parent, Comic.Red, x, y, 12, 26, 12, 3, 2)
	pin.ZIndex = 7
	pin.Visible = false
	return pin
end

-- Aro amarillo detrás de la prenda elegida
local function halo(parent: Instance, w: number, h: number, radius: number?): Frame
	local f = Comic.frame(parent, Comic.Yellow)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.ZIndex = 0
	f.Visible = false
	Comic.round(f, radius)
	local stroke = Comic.ink(f, 3, true)
	stroke.Color = Comic.Ink
	return f
end

local onPick: (view: any) -> ()

local function register(kind: string, def, holder: GuiObject, base: GuiButton, tag: TextLabel, pin: Frame, glow: Frame)
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	local view = { kind = kind, def = def, holder = holder, base = base, tag = tag, pin = pin, halo = glow, scale = scale }
	base.MouseButton1Click:Connect(function()
		onPick(view)
	end)
	base.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1.06 }):Play()
	end)
	base.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1 }):Play()
	end)
	table.insert(views, view)
	return view
end

local function shown(kind: string): { any }
	local list = {}
	for _, def in LISTS[kind] do
		if not mineOnly or owns(def) then
			table.insert(list, def)
		end
	end
	return list
end

-- Letrero de cartón clavado sobre cada expositor
local function sign(parent: Instance, text: string, x: number, y: number, rot: number)
	local label = Comic.label(parent, text, Comic.Display, 24, Comic.Ink)
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(0, 30)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = CARD
	label.Rotation = rot
	label.ZIndex = 3
	Comic.ink(label, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = label
	for _, side in { 0, 1 } do
		local nail = Comic.frame(label, Comic.Ink)
		nail.AnchorPoint = Vector2.new(0.5, 0.5)
		nail.Position = UDim2.new(side, if side == 0 then 5 else -5, 0.5, 0)
		nail.Size = UDim2.fromOffset(4, 4)
		nail.ZIndex = 4
		Comic.round(nail)
	end
end

local function emptyNote(parent: Instance, text: string, y: number)
	local note = Comic.label(parent, text, Comic.Body, 17, Comic.Ink)
	at(note, 12, y, RACK_W - 24, 40)
	note.TextTransparency = 0.35
	note.TextWrapped = true
	note.ZIndex = 3
end

-- Perchas en barras, cuatro por barra
local function buildOutfits(y: number): number
	sign(rack, "Trajes", 6, y, -3)
	sections.outfit = { top = y }
	y += 50
	local list = shown("outfit")
	local perRow = 4
	local slot = RACK_W / perRow
	local rowH = 172
	local rows = math.ceil(#list / perRow)
	local swings = { 3, -4, 2, -5, 4, -2, 5, -3 }
	for row = 1, rows do
		local railY = y + (row - 1) * rowH
		local bar = Comic.frame(rack, TIN)
		at(bar, 0, railY - 4, RACK_W, 8)
		bar.ZIndex = 2
		Comic.round(bar, 4)
		Comic.ink(bar, 3, true)
	end
	for i, def in list do
		local row = (i - 1) // perRow
		local col = (i - 1) % perRow
		local railY = y + row * rowH
		local holder = Comic.frame(rack)
		holder.AnchorPoint = Vector2.new(0.5, 0)
		at(holder, slot * (col + 0.5), railY - 8, slot - 6, rowH - 10)
		holder.Rotation = swings[(i - 1) % #swings + 1]
		holder.ZIndex = 3
		local cx = (slot - 6) / 2

		local glow = halo(holder, slot - 10, rowH - 18, 10)
		-- Gancho y percha
		local hook = blob(holder, nil, cx, 10, 14, 14, 0, -1, 3)
		hook.ZIndex = 5
		for _, s in { -1, 1 } do
			blob(holder, Comic.Ink, cx + s * 15, 26, 33, 4, s * 25).ZIndex = 4
		end
		blob(holder, Comic.Ink, cx, 32, 64, 4).ZIndex = 4

		-- La prenda: torso con mangas y su dibujo
		local base = button(holder)
		base.AnchorPoint = Vector2.new(0.5, 0)
		at(base, cx, 0, slot - 6, rowH - 34)
		base.ZIndex = 8
		local ghost = #def.slots == 0
		if not ghost then
			-- Mangas por detrás del torso
			for _, s in { -1, 1 } do
				local sleeve = blob(holder, def.colors[1], cx + s * 21, 56, 16, 30, -s * 25, 5, 3)
				sleeve.ZIndex = 3
			end
		end
		local torso = Comic.frame(holder, def.colors[1])
		torso.AnchorPoint = Vector2.new(0.5, 0)
		at(torso, cx, 40, 46, 58)
		torso.BackgroundTransparency = if ghost then 1 else 0
		torso.ZIndex = 4
		Comic.round(torso, 8)
		Comic.ink(torso, 3, true)
		for _, spec in def.icon do
			iconShape(torso, spec)
		end

		local name = Comic.label(holder, def.name, Comic.Display, 20, Comic.Ink)
		name.AnchorPoint = Vector2.new(0.5, 0)
		at(name, cx, 104, slot - 10, 22)
		name.ZIndex = 4
		fitText(name, 20, 12)

		local tag = hangTag(holder, cx, 134, if i % 2 == 0 then 4 else -4)
		local pin = clothespin(holder, cx + 26, 40)
		local view = register("outfit", def, holder, base, tag, pin, glow)
		if Trails.forOutfit(def.id) then
			view.seal = seal(holder, cx - 22, 48)
		end
	end
	if mineOnly and #list <= 1 then
		emptyNote(rack, "Aún no tienes trajes. Quita la cortina para verlos todos.", y + 8)
		return y + 60
	end
	return y + rows * rowH - 6
end

-- Sombrerera: cajas redondas con su sombrero pintado delante, cuatro por balda
local function buildHats(y: number): number
	sign(rack, "Sombreros", 6, y, 2)
	sections.hat = { top = y }
	y += 48
	local list = shown("hat")
	local perRow = 4
	local slot = RACK_W / perRow
	local rowH = 132
	local rows = math.ceil(#list / perRow)
	for row = 1, rows do
		local plank = Comic.frame(rack, WOOD)
		at(plank, 0, y + (row - 1) * rowH + 86, RACK_W, 12)
		plank.Rotation = if row % 2 == 0 then 0.5 else -0.5
		plank.ZIndex = 3
		Comic.ink(plank, 3, true)
	end
	for i, def in list do
		local row = (i - 1) // perRow
		local col = (i - 1) % perRow
		local holder = Comic.frame(rack)
		holder.AnchorPoint = Vector2.new(0.5, 0)
		at(holder, slot * (col + 0.5), y + row * rowH, slot - 8, rowH - 6)
		holder.ZIndex = 4
		local cx = (slot - 8) / 2

		local glow = halo(holder, slot - 6, 92, 12)
		local color = BOXES[(i - 1) % #BOXES + 1]
		local box = blob(holder, color, cx, 56, 86, 58, 0, 14, 3)
		box.ZIndex = 4
		local lid = blob(holder, color:Lerp(Comic.Ink, 0.15), cx, 26, 94, 16, 0, 6, 3)
		lid.ZIndex = 5
		local drawing = Comic.frame(box)
		drawing.AnchorPoint = Vector2.new(0.5, 0.5)
		drawing.Position = UDim2.fromScale(0.5, 0.55)
		drawing.Size = UDim2.fromOffset(44, 34)
		drawing.ZIndex = 5
		local draw = HATS[def.id]
		if draw then
			draw(drawing)
		end

		local base = button(holder)
		base.AnchorPoint = Vector2.new(0.5, 0)
		at(base, cx, 10, slot - 8, 84)
		base.ZIndex = 8

		local name = Comic.label(holder, def.name, Comic.Body, 16, Comic.Ink)
		name.AnchorPoint = Vector2.new(0.5, 0)
		at(name, cx, 98, slot - 12, 18)
		name.ZIndex = 4
		fitText(name, 16, 11)

		local tag = hangTag(holder, cx + 34, 30, 6)
		local pin = clothespin(holder, cx - 40, 26)
		register("hat", def, holder, base, tag, pin, glow)
	end
	if mineOnly and #list <= 1 then
		emptyNote(rack, "Aún no tienes sombreros.", y + 96)
		return y + rowH + 40
	end
	return y + rows * rowH
end

-- Cintas colgadas de una barra: se ven sus colores y la pista de sus chispas
local function buildTrails(y: number): number
	sign(rack, "Estelas", 6, y, -2)
	sections.trail = { top = y }
	y += 50
	local list = shown("trail")
	local perRow = math.max(1, math.floor(RACK_W / 64))
	local slot = RACK_W / perRow
	local rowH = 158
	local rows = math.ceil(#list / perRow)
	for row = 1, rows do
		local bar = Comic.frame(rack, ROD_COLOR)
		at(bar, 0, y + (row - 1) * rowH - 4, RACK_W, 8)
		bar.ZIndex = 2
		Comic.round(bar, 4)
		Comic.ink(bar, 3, true)
	end
	for i, def in list do
		local row = (i - 1) // perRow
		local col = (i - 1) % perRow
		local holder = Comic.frame(rack)
		holder.AnchorPoint = Vector2.new(0.5, 0)
		at(holder, slot * (col + 0.5), y + row * rowH, slot - 4, rowH - 8)
		holder.Rotation = if i % 2 == 0 then 2 else -2
		holder.ZIndex = 3
		local cx = (slot - 4) / 2

		local glow = halo(holder, slot - 6, 120, 8)
		local ribbonH = 92
		local ribbon = Comic.frame(holder, Comic.Paper)
		ribbon.AnchorPoint = Vector2.new(0.5, 0)
		at(ribbon, cx, 2, 40, ribbonH)
		ribbon.ZIndex = 4
		ribbon.ClipsDescendants = true
		Comic.ink(ribbon, 3, true)
		paintRibbon(ribbon, def.colors)
		if not def.colors then
			-- "Ninguna": papel con una raya de lápiz
			blob(ribbon, Comic.Ink, 20, ribbonH / 2, 2, ribbonH * 0.7, 20).ZIndex = 5
		end
		particleMarks(ribbon, def, ribbonH)
		-- Corte en uve al final de la cinta
		blob(holder, WALL, cx, 2 + ribbonH, 22, 22, 45).ZIndex = 5

		local base = button(holder)
		base.AnchorPoint = Vector2.new(0.5, 0)
		at(base, cx, 0, slot - 4, ribbonH + 8)
		base.ZIndex = 8

		local name = Comic.label(holder, def.name, Comic.Body, 14, Comic.Ink)
		name.AnchorPoint = Vector2.new(0.5, 0)
		at(name, cx, ribbonH + 10, slot - 4, 16)
		name.ZIndex = 4
		fitText(name, 14, 9)

		local tag = hangTag(holder, cx, ribbonH + 36, if i % 2 == 0 then -5 else 5)
		local pin = clothespin(holder, cx + 16, 4)
		local view = register("trail", def, holder, base, tag, pin, glow)
		if def.pairs then
			view.seal = seal(holder, cx, 26)
		end
	end
	if mineOnly and #list <= 1 then
		emptyNote(rack, "Aún no tienes estelas.", y + 24)
		return y + 80
	end
	return y + rows * rowH
end

-- Botes de pintura a los pies de la peana
local function buildPots()
	potsRow:ClearAllChildren()
	local list = shown("skin")
	local slot = STAGE_W / math.max(#list, 1)
	for i, def in list do
		local holder = Comic.frame(potsRow)
		holder.AnchorPoint = Vector2.new(0.5, 0)
		at(holder, slot * (i - 0.5), 0, slot, POTS_H)
		holder.ZIndex = 3
		local cx = slot / 2
		local glow = halo(holder, slot - 2, 56, 8)
		local can = blob(holder, TIN, cx, 30, 32, 30, 0, 4, 2)
		can.ZIndex = 4
		blob(can, def.color, 16, 17, 32, 10, 0, nil, 0).ZIndex = 4
		local top = blob(holder, def.color, cx, 15, 36, 10, 0, -1, 2)
		top.ZIndex = 5
		local drip = blob(holder, def.color, cx + 9, 22, 6, 12, 0, 3, 2)
		drip.ZIndex = 5

		local base = button(holder)
		base.AnchorPoint = Vector2.new(0.5, 0)
		at(base, cx, 0, slot, 50)
		base.ZIndex = 8

		local tag = hangTag(holder, cx, 52, if i % 2 == 0 then 4 else -4)
		tag.TextSize = 14
		local pin = clothespin(holder, cx - 14, 14)
		register("skin", def, holder, base, tag, pin, glow)
	end
end

-- Rehace los expositores (al abrir la cortina del filtro)
local function buildDisplays()
	views = {}
	rack:ClearAllChildren()
	local y = 10
	y = buildOutfits(y)
	y = buildHats(y + 14)
	y = buildTrails(y + 14)
	rack.CanvasSize = UDim2.fromOffset(0, y + 20)
	buildPots()
end

-------------------------------------------------------------------------------
-- Estado y mostrador
-------------------------------------------------------------------------------

-- Piezas de la selección: una prenda o el conjunto traje + estela
local function pieces(): { { kind: string, def: any } }
	if not selection then
		return {}
	end
	if selection.set then
		local list = {}
		local outfit = Outfits.byId[selection.set.outfit]
		local trail = Trails.byId[selection.set.trail]
		if outfit then
			table.insert(list, { kind = "outfit", def = outfit })
		end
		if trail then
			table.insert(list, { kind = "trail", def = trail })
		end
		return list
	end
	local def = defOf(selection.kind, selection.id)
	return if def then { { kind = selection.kind, def = def } } else {}
end

-- Qué hace el botón ahora: estado, coste por pagar
local function verdict(): (string, number)
	local list = pieces()
	if #list == 0 then
		return "none", 0
	end
	local cost, allWorn = 0, true
	for _, piece in list do
		local state = stateOf(piece.kind, piece.def)
		if state == "locked" then
			return "locked", 0
		end
		if state ~= "worn" then
			allWorn = false
		end
		if state == "affordable" or state == "expensive" then
			cost += piece.def.cost
		end
	end
	if allWorn then
		return "worn", 0
	end
	if cost <= 0 then
		return "owned", 0
	end
	return if State.num("Food") >= cost then "affordable" else "expensive", cost
end

-- Pase que hace falta para lo elegido, si alguna pieza viene con uno
local function neededPass(): string?
	for _, piece in pieces() do
		if stateOf(piece.kind, piece.def) == "locked" then
			return piece.def.pass
		end
	end
	return nil
end

local function passName(id: string?): string
	for _, pass in Config.Passes do
		if pass.id == id then
			return pass.name
		end
	end
	return tostring(id)
end

local function lockedText(pass: string?): string
	return if pass == "vip" then "Solo VIP" else "Con el pase " .. passName(pass)
end

local function partnerOf(kind: string, id: string): (string?, string?)
	if kind == "outfit" then
		local trail = Trails.forOutfit(id)
		return if trail then "trail" else nil, if trail then trail.id else nil
	elseif kind == "trail" then
		local def = Trails.byId[id]
		local outfit = def and def.pairs and def.pairs[1]
		return if outfit then "outfit" else nil, outfit
	end
	return nil, nil
end

local function paintAction()
	local list = pieces()
	local state, cost = verdict()
	local food = State.num("Food")
	local b = action
	b.holder.Visible = state ~= "none"
	if state == "none" then
		b.name.Text = "Tu hormiga"
		b.status.Text = "Toca una prenda para probártela"
	elseif selection.set then
		b.name.Text = list[1].def.name .. " + " .. (if list[2] then list[2].def.name else "")
		b.status.Text = "Conjunto completo"
	else
		local def = list[1].def
		b.name.Text = def.name
		local kind = KIND_NAME[selection.kind] or ""
		b.status.Text = if state == "worn" then kind .. " · lo llevas puesto"
			elseif state == "owned" then kind .. " · es tuyo"
			elseif state == "locked" then kind .. " · viene con el pase " .. passName(def.pass)
			else kind .. " · cuesta " .. Format.short(def.cost) .. " de comida"
	end

	local face, label = b.face, b.label
	label.TextColor3 = Comic.Ink
	label.TextTransparency = 0
	if state == "worn" then
		face.BackgroundColor3 = DIM
		label.Text = "Lo llevas puesto"
		label.TextTransparency = 0.35
	elseif state == "owned" then
		face.BackgroundColor3 = Comic.Yellow
		label.Text = if selection.set then "Ponérmelo todo" else "Ponérmelo"
	elseif state == "affordable" then
		face.BackgroundColor3 = Comic.Green
		label.Text = "Comprar por " .. Format.short(cost)
	elseif state == "expensive" then
		face.BackgroundColor3 = DIM
		label.Text = "Te falta " .. Format.short(cost - food)
		label.TextTransparency = 0.2
	elseif state == "locked" then
		face.BackgroundColor3 = Comic.Ink
		label.Text = lockedText(neededPass())
		label.TextColor3 = Comic.Yellow
	end

	-- Sello del conjunto: si lo elegido tiene pareja, se ofrece ponerse los dos
	local setLine = b.set
	setLine.holder.Visible = false
	if selection and not selection.set and state ~= "none" then
		local otherKind, otherId = partnerOf(selection.kind, selection.id)
		local other = otherKind and otherId and defOf(otherKind, otherId)
		if other then
			setLine.holder.Visible = true
			setLine.label.Text = "Hace conjunto con " .. other.name .. ". Probar los dos"
		end
	elseif selection and selection.set then
		setLine.holder.Visible = true
		setLine.label.Text = "Llevas a prueba el conjunto entero"
	end

	foodTag.Text = "Comida " .. Format.short(food)
	local changed = false
	for kind, id in trial do
		if id ~= equipped(kind) then
			changed = true
		end
	end
	revert.Visible = changed
end

-- Pinta cada prenda según su estado. Que no haya duda de cuál llevas ni de cuál miras.
local function paint()
	if not gui then
		return
	end
	local list = pieces()
	local chosen = {}
	for _, piece in list do
		chosen[piece.kind .. ":" .. piece.def.id] = true
	end
	-- La pareja de lo elegido se marca con su sello latiendo
	local partnerKey = nil
	if selection and not selection.set then
		local otherKind, otherId = partnerOf(selection.kind, selection.id)
		if otherKind and otherId then
			partnerKey = otherKind .. ":" .. otherId
		end
	end
	for _, view in views do
		local state = stateOf(view.kind, view.def)
		local key = view.kind .. ":" .. view.def.id
		view.halo.Visible = chosen[key] == true
		view.pin.Visible = state == "worn"
		if view.seal then
			view.seal.Size = if key == partnerKey or (chosen[key] and selection and selection.set) then UDim2.fromOffset(28, 28) else UDim2.fromOffset(20, 20)
		end
		local tag = view.tag
		tag.Visible = state ~= "owned" and state ~= "worn"
		tag.TextTransparency = 0
		tag.BackgroundColor3 = CARD
		tag.TextColor3 = Comic.Ink
		if state == "affordable" then
			tag.Text = Format.short(view.def.cost)
		elseif state == "expensive" then
			tag.Text = Format.short(view.def.cost)
			tag.BackgroundColor3 = DIM
			tag.TextTransparency = 0.5
		elseif state == "locked" then
			tag.Text = if view.def.pass == "vip" then "VIP" else "Pase"
			tag.BackgroundColor3 = Comic.Ink
			tag.TextColor3 = Comic.Yellow
		end
	end
	paintAction()
end

local function scrollToView(view)
	if view.kind == "skin" then
		return
	end
	local y = view.holder.AbsolutePosition.Y - rack.AbsolutePosition.Y
	local h = rack.AbsoluteWindowSize.Y
	local s = math.max(fit.Scale, 0.01)
	if y < 0 or y + view.holder.AbsoluteSize.Y > h then
		local target = rack.CanvasPosition.Y + (y - h / 3) / s
		local maxY = math.max(0, rack.AbsoluteCanvasSize.Y / s - h / s)
		TweenService:Create(rack, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CanvasPosition = Vector2.new(0, math.clamp(target, 0, maxY)),
		}):Play()
	end
end

-- Tocar una prenda: te la pruebas en la peana
onPick = function(view)
	trial[view.kind] = view.def.id
	selection = { kind = view.kind, id = view.def.id }
	Comic.punch(view.scale, 1.15)
	Sfx.pop(1.15)
	dressPreview()
	paint()
	scrollToView(view)
end

local function shake(object: GuiObject)
	local base = object.Position
	task.spawn(function()
		for _, dx in { 7, -7, 5, -4, 2, 0 } do
			object.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		object.Position = base
	end)
end

-- El botón del mostrador
local function act()
	local state = verdict()
	if state == "none" then
		return
	end
	if state == "locked" then
		-- El pase está en la tienda: se abre justo en él
		local pass = neededPass() or "vip"
		Sfx.pop(1)
		Wardrobe.close()
		Store.open()
		Store.focus(pass)
		return
	end
	if state == "worn" or state == "expensive" then
		shake(action.holder)
		Sfx.pop(0.7)
		return
	end
	Sfx.pop(if state == "affordable" then 1.45 else 1.2)
	Comic.punch(action.scale, 1.1)
	local wear = remotes and remotes:FindFirstChild("Wear")
	if not wear then
		return
	end
	for _, piece in pieces() do
		if stateOf(piece.kind, piece.def) ~= "worn" then
			wear:FireServer(piece.kind, piece.def.id)
		end
	end
end

local function trySet()
	if not selection then
		return
	end
	if selection.set then
		return
	end
	local otherKind, otherId = partnerOf(selection.kind, selection.id)
	if not otherKind or not otherId then
		return
	end
	local outfit = if selection.kind == "outfit" then selection.id else otherId
	local trailId = if selection.kind == "trail" then selection.id else otherId
	trial.outfit = outfit
	trial.trail = trailId
	selection = { set = { outfit = outfit, trail = trailId } }
	Sfx.pop(1.3)
	dressPreview()
	paint()
end

local function revertTrial()
	trial = {}
	selection = nil
	Sfx.pop(0.9)
	dressPreview()
	paint()
end

-------------------------------------------------------------------------------
-- Cortina del filtro: "Todo" o "Lo mío"
-------------------------------------------------------------------------------

local function paintFilter()
	filterTab.Position = UDim2.fromOffset(if mineOnly then RACK_W / 2 else 0, 0)
	for key, label in filterWords do
		label.TextColor3 = if (key == "mine") == mineOnly then Comic.Paper else Comic.Ink
	end
end

local function setFilter(mine: boolean)
	if mine == mineOnly then
		return
	end
	mineOnly = mine
	Sfx.pop(0.95)
	TweenService:Create(filterTab, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(if mineOnly then RACK_W / 2 else 0, 0),
	}):Play()
	for key, label in filterWords do
		label.TextColor3 = if (key == "mine") == mineOnly then Comic.Paper else Comic.Ink
	end
	-- La cortina tapa el expositor, se cambia detrás y se vuelve a abrir
	filterCurtain.Visible = true
	filterCurtain.Size = UDim2.new(0, 0, 1, 0)
	local cover = TweenService:Create(filterCurtain, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(1, 0, 1, 0) })
	cover:Play()
	cover.Completed:Connect(function()
		buildDisplays()
		rack.CanvasPosition = Vector2.zero
		paint()
		local uncover = TweenService:Create(filterCurtain, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 0, 1, 0) })
		uncover:Play()
		uncover.Completed:Connect(function()
			filterCurtain.Visible = false
		end)
	end)
end

-------------------------------------------------------------------------------
-- Montaje
-------------------------------------------------------------------------------

local stageParts = {} :: any

-- En pantallas bajas (móvil apaisado) el mostrador se aprieta para que la peana siga viéndose
local function layoutStage(compact: boolean)
	local p = stageParts
	if not p.back then
		return
	end
	local actionH = if compact then 126 else ACTION_H
	p.back.Size = UDim2.new(1, 0, 1, -actionH - 6)
	p.counter.Size = UDim2.new(1, 0, 0, actionH)
	p.status.Visible = not compact
	p.holder.Position = UDim2.fromOffset(0, if compact then 34 else 62)
	p.set.Position = UDim2.fromOffset(0, if compact then 94 else 128)
end

local function resize()
	local cam = Workspace.CurrentCamera
	if not cam or not panel then
		return
	end
	local view = cam.ViewportSize
	-- Nunca más ancho que la pantalla
	local s = math.max(fit.Scale, 0.01)
	local widest = (view.X - MARGIN * 2 - 8) / W
	if s > widest then
		s = math.max(widest, 0.01)
		fit.Scale = s
	end
	local height = math.min(H, (view.Y - MARGIN * 2) / s)
	panel.Size = UDim2.fromOffset(W, height)
	layoutStage(height < 600)
end

-- Una cortina con sus pliegues: tapa media cara del probador
local function curtain(side: number): Frame
	local c = Comic.frame(face, CURTAIN)
	c.Size = UDim2.new(0.5, 0, 1, 0)
	c.ZIndex = 50
	c.ClipsDescendants = true
	c.AnchorPoint = Vector2.new(side, 0)
	c.Position = UDim2.fromScale(side, 0)
	Comic.ink(c, 3, true)
	for k = 1, 7 do
		local fold = Comic.frame(c, CURTAIN_FOLD)
		fold.Position = UDim2.new(k / 8, -4, 0, 0)
		fold.Size = UDim2.new(0, 8, 1, 0)
		fold.ZIndex = 50
	end
	return c
end

local function buildStage()
	stageCol = Comic.frame(face)
	stageCol.Position = UDim2.fromOffset(PAD, ROD + 8)
	stageCol.Size = UDim2.new(0, STAGE_W, 1, -ROD - 16)
	stageCol.ZIndex = 2

	-- El fondo del probador: un papel algo más claro con un marco de espejo
	local back = Comic.frame(stageCol, Comic.Paper)
	back.Size = UDim2.new(1, 0, 1, -ACTION_H - 6)
	back.ZIndex = 2
	Comic.ink(back, 4, true)
	Comic.round(back, 10)
	local dots = Comic.halftone(back, Comic.Yellow, 90)
	dots.ZIndex = 2
	dots.ImageTransparency = 0.4

	-- La estela que llevas a prueba, pintada detrás de la peana
	swoosh = Comic.frame(back, Color3.new(1, 1, 1))
	swoosh.AnchorPoint = Vector2.new(0.5, 0.5)
	swoosh.Position = UDim2.new(0.5, 0, 1, -POTS_H - 50)
	swoosh.Size = UDim2.new(1.2, 0, 0, 30)
	swoosh.Rotation = -12
	swoosh.ZIndex = 3
	swoosh.Visible = false
	Comic.round(swoosh)
	Comic.ink(swoosh, 3, true)
	-- Sus colores y, en el mismo gradiente, que se desvanezca hacia la cola
	swooshPaint = Instance.new("UIGradient")
	swooshPaint.Parent = swoosh
	swooshPaint.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.6, 0.1),
		NumberSequenceKeypoint.new(1, 0),
	})

	viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(1, 0, 1, -POTS_H)
	viewport.Ambient = Color3.fromRGB(190, 186, 200)
	viewport.LightColor = Color3.fromRGB(255, 248, 236)
	viewport.LightDirection = Vector3.new(-0.6, -1, -0.4)
	viewport.ZIndex = 4
	viewport.Active = true
	viewport.Parent = back
	world = Instance.new("WorldModel")
	world.Parent = viewport
	camera = Instance.new("Camera")
	camera.FieldOfView = 38
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- La peana: madera con un canto oscuro y tachuelas doradas
	local function standPart(size: Vector3, color: Color3, cylinder: boolean): BasePart
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = size
		p.Color = color
		if cylinder then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Parent = world
		return p
	end
	stand = {
		standPart(Vector3.new(0.5, 4, 4), WOOD, true),
		standPart(Vector3.new(0.3, 4.5, 4.5), WOOD:Lerp(Comic.Ink, 0.4), true),
	}
	for _ = 1, 6 do
		table.insert(stand, standPart(Vector3.new(0.22, 0.12, 0.22), Color3.fromRGB(255, 200, 60), false))
	end

	-- Arrastrar sobre la peana la gira
	viewport.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = input
			dragX = input.Position.X
			lastDrag = os.clock()
		end
	end)

	-- "Volver a lo mío": quita lo que te estás probando
	revert = button(back)
	revert.AnchorPoint = Vector2.new(0, 0)
	revert.Position = UDim2.fromOffset(10, 10)
	revert.Size = UDim2.fromOffset(150, 30)
	revert.BackgroundTransparency = 0
	revert.BackgroundColor3 = CARD
	revert.Rotation = -3
	revert.ZIndex = 6
	revert.Visible = false
	Comic.ink(revert, 2, true)
	local revertText = Comic.label(revert, "Volver a lo mío", Comic.Display, 18, Comic.Ink)
	revertText.Size = UDim2.fromScale(1, 1)
	revertText.ZIndex = 7
	revert.MouseButton1Click:Connect(revertTrial)

	-- Botes de pintura en el suelo, a los pies de la peana
	potsRow = Comic.frame(back)
	potsRow.AnchorPoint = Vector2.new(0, 1)
	potsRow.Position = UDim2.new(0, 0, 1, -4)
	potsRow.Size = UDim2.new(1, 0, 0, POTS_H)
	potsRow.ZIndex = 5

	-- Mostrador: qué miras, qué cuesta y el botón
	local counter = Comic.frame(stageCol)
	counter.AnchorPoint = Vector2.new(0, 1)
	counter.Position = UDim2.fromScale(0, 1)
	counter.Size = UDim2.new(1, 0, 0, ACTION_H)
	counter.ZIndex = 3

	local name = Comic.label(counter, "", Comic.Display, 30, Comic.Ink)
	at(name, 2, 2, STAGE_W - 4, 32)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 4
	fitText(name, 30, 16)
	local status = Comic.label(counter, "", Comic.Body, 17, Comic.Ink)
	at(status, 2, 34, STAGE_W - 4, 22)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = 4
	fitText(status, 17, 11)

	local holder, buttonFace = Comic.button(counter, UDim2.fromOffset(STAGE_W - 6, 56), Comic.Yellow, 5)
	at(holder, 0, 62)
	holder.ZIndex = 4
	buttonFace.ZIndex = 5
	local label = Comic.label(buttonFace, "", Comic.Display, 28, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 6
	fitText(label, 28, 16)
	local pressScale = Instance.new("UIScale")
	pressScale.Parent = holder
	buttonFace.MouseButton1Click:Connect(act)

	-- Sello del conjunto: un lacre y una línea que se toca
	local setHolder = button(counter)
	at(setHolder, 0, 128, STAGE_W - 6, 40)
	setHolder.ZIndex = 4
	setHolder.Visible = false
	local wax = blob(setHolder, SEAL, 18, 20, 30, 30, 0, -1, 3)
	wax.ZIndex = 5
	blob(wax, Color3.fromRGB(230, 70, 80), 15, 15, 14, 14, 0, -1).ZIndex = 5
	local setLabel = Comic.label(setHolder, "", Comic.Body, 16, SEAL)
	at(setLabel, 40, 0, STAGE_W - 50, 40)
	setLabel.TextXAlignment = Enum.TextXAlignment.Left
	setLabel.TextWrapped = true
	setLabel.ZIndex = 5
	fitText(setLabel, 16, 11)
	setHolder.MouseButton1Click:Connect(trySet)

	action = {
		holder = holder,
		face = buttonFace,
		label = label,
		name = name,
		status = status,
		scale = pressScale,
		set = { holder = setHolder, label = setLabel },
	}
	stageParts = { back = back, counter = counter, status = status, holder = holder, set = setHolder }
end

local function buildRack()
	local col = Comic.frame(face)
	col.Position = UDim2.fromOffset(RACK_X, ROD + 8)
	col.Size = UDim2.new(0, RACK_W, 1, -ROD - 16)
	col.ZIndex = 2

	-- Cortina del filtro: una tela que se corre entre "Todo" y "Lo mío"
	local filter = Comic.frame(col, CARD)
	at(filter, 0, 0, RACK_W, FILTER_H - 8)
	filter.ZIndex = 3
	filter.ClipsDescendants = true
	Comic.ink(filter, 3, true)
	filterTab = Comic.frame(filter, CURTAIN)
	at(filterTab, 0, 0, RACK_W / 2, FILTER_H - 8)
	filterTab.ZIndex = 3
	for k = 1, 4 do
		local fold = Comic.frame(filterTab, CURTAIN_FOLD)
		fold.Position = UDim2.new(k / 5, -3, 0, 0)
		fold.Size = UDim2.new(0, 6, 1, 0)
		fold.ZIndex = 3
	end
	for i, entry in { { "all", "Todo" }, { "mine", "Lo mío" } } do
		local hit = button(filter)
		at(hit, (i - 1) * RACK_W / 2, 0, RACK_W / 2, FILTER_H - 8)
		hit.ZIndex = 5
		local word = Comic.label(hit, entry[2], Comic.Display, 24, Comic.Ink)
		word.Size = UDim2.fromScale(1, 1)
		word.ZIndex = 5
		filterWords[entry[1]] = word
		hit.MouseButton1Click:Connect(function()
			setFilter(entry[1] == "mine")
		end)
	end

	rack = Instance.new("ScrollingFrame")
	rack.BackgroundTransparency = 1
	rack.BorderSizePixel = 0
	rack.Position = UDim2.fromOffset(0, FILTER_H)
	rack.Size = UDim2.new(1, 0, 1, -FILTER_H)
	rack.ScrollingDirection = Enum.ScrollingDirection.Y
	rack.ScrollBarThickness = 6
	rack.ScrollBarImageColor3 = Comic.Ink
	rack.ElasticBehavior = Enum.ElasticBehavior.Never
	rack.ZIndex = 2
	rack.Parent = col

	filterCurtain = Comic.frame(col, CURTAIN)
	filterCurtain.Position = UDim2.fromOffset(0, FILTER_H)
	filterCurtain.Size = UDim2.new(0, 0, 1, -FILTER_H)
	filterCurtain.ZIndex = 20
	filterCurtain.ClipsDescendants = true
	filterCurtain.Visible = false
	for k = 1, 9 do
		local fold = Comic.frame(filterCurtain, CURTAIN_FOLD)
		fold.Position = UDim2.fromOffset(k * 48, 0)
		fold.Size = UDim2.new(0, 8, 1, 0)
		fold.ZIndex = 20
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Wardrobe"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Tocar fuera cierra (el juego se sigue viendo)
	local outside = button(gui)
	outside.Size = UDim2.fromScale(1, 1)
	outside.Selectable = false
	outside.MouseButton1Click:Connect(function()
		Wardrobe.close()
	end)

	panel = Comic.frame(gui)
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -MARGIN - 8, 0.5, 0)
	panel.Size = UDim2.fromOffset(W, H)
	fit = Hud.fitScale(panel, TAP)

	local shadow = Comic.frame(panel, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(8, 8)

	face = Comic.frame(panel, WALL)
	face.Size = UDim2.fromScale(1, 1)
	face.ClipsDescendants = true
	face.Active = true
	Comic.ink(face, 5, true)
	-- Papel pintado de rayas
	for k = 0, math.floor(W / 40) do
		local stripe = Comic.frame(face, WALL_LINE)
		stripe.Position = UDim2.fromOffset(k * 40 + 14, 0)
		stripe.Size = UDim2.new(0, 12, 1, 0)
	end

	buildStage()
	buildRack()

	-- Barra de la cortina con su cenefa; de ella cuelgan la comida y el cierre
	local valance = Comic.frame(face, CURTAIN)
	at(valance, 0, 0, W, ROD - 8)
	valance.ZIndex = 55
	Comic.ink(valance, 3, true)
	for k = 0, math.floor(W / 36) do
		local scallop = blob(face, CURTAIN, k * 36 + 18, ROD - 8, 36, 18, 0, -1, 3)
		scallop.ZIndex = 54
	end
	local rodBar = Comic.frame(face, ROD_COLOR)
	at(rodBar, 0, 6, W, 10)
	rodBar.ZIndex = 56
	Comic.ink(rodBar, 3, true)

	foodTag = Comic.label(face, "", Comic.Display, 22, Comic.Ink)
	foodTag.AnchorPoint = Vector2.new(0.5, 0)
	foodTag.Position = UDim2.fromOffset(PAD + STAGE_W / 2, 14)
	foodTag.Size = UDim2.fromOffset(0, 26)
	foodTag.AutomaticSize = Enum.AutomaticSize.X
	foodTag.BackgroundTransparency = 0
	foodTag.BackgroundColor3 = Comic.Yellow
	foodTag.Rotation = -2
	foodTag.ZIndex = 57
	Comic.ink(foodTag, 3, true)
	local foodPad = Instance.new("UIPadding")
	foodPad.PaddingLeft = UDim.new(0, 10)
	foodPad.PaddingRight = UDim.new(0, 10)
	foodPad.Parent = foodTag

	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(42, 42), Comic.Paper, 4)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -10, 0, 2)
	closeHolder.ZIndex = 57
	closeFace.ZIndex = 58
	Comic.round(closeFace)
	Comic.round((closeHolder :: any).Shadow)
	local cross = Comic.label(closeFace, "X", Comic.Display, 28, Comic.Red)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 59
	closeFace.MouseButton1Click:Connect(function()
		Wardrobe.close()
	end)

	curtains = { curtain(0), curtain(1) }

	fit:GetPropertyChangedSignal("Scale"):Connect(resize)
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	resize()

	buildDisplays()
	paintFilter()
end

-------------------------------------------------------------------------------
-- Abrir, cerrar y teclado
-------------------------------------------------------------------------------

function Wardrobe.isOpen(): boolean
	return isOpen
end

function Wardrobe.open()
	if not gui then
		return
	end
	isOpen = true
	closing += 1
	trial = {}
	selection = nil
	gui.Enabled = true
	resize()
	dressPreview()
	paint()
	Sfx.pop(0.9)
	-- La cortina del probador se descorre hacia los lados
	for i, c in curtains do
		c.Visible = true
		c.Size = UDim2.new(0.5, 0, 1, 0)
		TweenService:Create(c, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 12, 1, 0),
		}):Play()
		c.Position = UDim2.fromScale(i - 1, 0)
	end
end

function Wardrobe.close()
	if not isOpen then
		return
	end
	isOpen = false
	dragging = nil
	closing += 1
	local token = closing
	-- Se corre la cortina y luego se va
	for _, c in curtains do
		TweenService:Create(c, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0.5, 0, 1, 0),
		}):Play()
	end
	task.delay(0.18, function()
		if token == closing and not isOpen and gui then
			gui.Enabled = false
		end
	end)
end

function Wardrobe.toggle()
	if isOpen then
		Wardrobe.close()
	else
		Wardrobe.open()
	end
end

-- Flechas izquierda/derecha: prenda anterior o siguiente; arriba/abajo: otro expositor
local function stepPick(dx: number, dy: number)
	if #views == 0 then
		return
	end
	local index = 0
	if selection and not selection.set then
		for i, view in views do
			if view.kind == selection.kind and view.def.id == selection.id then
				index = i
			end
		end
	end
	local target
	if dy ~= 0 then
		local kindNow = if index > 0 then views[index].kind else ORDER[1]
		local k = table.find(ORDER, kindNow) or 1
		local nextKind = ORDER[(k - 1 + dy) % #ORDER + 1]
		for _, view in views do
			if view.kind == nextKind then
				target = view
				break
			end
		end
	else
		local i = if index == 0 then 1 else (index - 1 + dx) % #views + 1
		target = views[i]
	end
	if target then
		onPick(target)
	end
end

function Wardrobe.start(remoteFolder: Folder)
	remotes = remoteFolder
	-- Las estelas de todos solo echan partículas mientras su hormiga anda (ver Shared/Trails)
	Trails.startClient()
	build()
	State.onChange(function()
		if isOpen then
			paint()
		end
	end)
	-- Lo que llevas puesto cambió (compra, otra prenda): la peana se viste de nuevo
	for _, attribute in ATTRIBUTE do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if isOpen then
				dressPreview()
				paint()
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if not isOpen then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
			Wardrobe.close()
		elseif processed then
			return
		elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft then
			stepPick(-1, 0)
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadRight then
			stepPick(1, 0)
		elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.DPadUp then
			stepPick(0, -1)
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.DPadDown then
			stepPick(0, 1)
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA then
			act()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local drag = dragging
		if not drag then
			return
		end
		local moved = (drag.UserInputType == Enum.UserInputType.Touch and input == drag)
			or (drag.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
		if moved then
			angle -= (input.Position.X - dragX) * 0.012
			dragX = input.Position.X
			lastDrag = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local drag = dragging
		if drag and (input == drag or input.UserInputType == drag.UserInputType) then
			dragging = nil
			lastDrag = os.clock()
		end
	end)
	RunService.RenderStepped:Connect(spin)
end

return Wardrobe
