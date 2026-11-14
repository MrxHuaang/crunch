-- Túnel exprés (cliente): enciende solo tus avisos de túnel, abre el mapa de salidas junto a tu
-- agujero y dibuja el viaje (caes por el agujero, un momento de oscuridad con líneas de velocidad y
-- asomas por el otro con un estallido de tierra). Los avisos son ProximityPrompt: tecla B, mando o toque.
-- El servidor (src/server/Tunnel.luau) valida y mueve a la hormiga.
--
-- El mapa es un corte de tierra visto de lado: el hormiguero arriba y un túnel que baja serpenteando
-- por las zonas como una línea de metro. Cada estación lleva el color y un dibujo de su zona; las
-- que aún no has excavado siguen tapadas de tierra y el tramo que lleva a ellas es solo un punteado.
-- Tu hormiga sale del hormiguero: al elegir estación corre por la línea hasta ella y entonces viaja.
-- Si el túnel aún se está asentando tras el último viaje, unas piedras taponan la línea con los
-- segundos que faltan; la hormiga espera ahí y sigue sola en cuanto se despeja.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Tunnel = {}

local player = Players.LocalPlayer
local FLAT = Vector3.new(1, 0, 1)

-- Medidas de diseño del mapa (Hud.fitScale las adapta a la pantalla)
local W = 400
local MARGIN = 16
local SURFACE = 104 -- donde acaba la hierba
local HOME = Vector2.new(200, 90) -- boca del hormiguero: la estación de casa
local FIRST = 196 -- y de la primera estación bajo tierra
local STEP = 64 -- separación vertical entre estaciones
local SWING = 96 -- cuánto serpentea la línea a cada lado
local STATION = 46
local ROW = 60 -- alto de la zona que se toca de cada estación
local TUBE = 20
local TUBE_INK = 30
local SAMPLES = 8 -- trozos rectos por tramo de curva
local ZONES = #Config.Zones
local CONTENT = FIRST + (ZONES - 2) * STEP + 74

local SKY = Color3.fromRGB(150, 214, 240)
local DEEP = Color3.fromRGB(78, 62, 84)
local PEBBLE = Color3.fromRGB(170, 166, 160)
local CLOD = Color3.fromRGB(92, 60, 40)

local remote: RemoteEvent? = nil
local gui: ScreenGui
local panel: Frame
local fit: UIScale
local canvas: ScrollingFrame
local dark: Frame -- la oscuridad del viaje
local openAt: Vector3? = nil -- agujero junto al que se abrió el mapa
local isOpen = false
local closedAt = 0
local readyAt = 0 -- cuándo se puede volver a viajar (aproximado: lo decide el servidor)
local lastZone: number? = nil -- última estación a la que viajaste

-- Geometría de la línea, calculada una vez
local points: { Vector2 } = {}
local gaps: { { Vector2 } } = {} -- gaps[i]: puntos de la curva de la estación i a la i + 1

-- Lo que se rehace al cambiar de capa
local builtDepth = -1
local stations = {} -- [zona] = { holder, name, open }
local digOrder: { GuiObject } = {} -- trozos del túnel excavado, de arriba abajo
local layers: { [string]: Frame } = {}
local ant: Frame
local antBody: { Frame } = {}
local focusRing: Frame
local plug: Frame
local plugLabel: TextLabel
local focused: number? = nil
local running = false -- la hormiga va de camino
local runToken = 0

local function rootPart(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function hasTunnel(): boolean
	return (State.nodes().tunnel or 0) > 0
end

local function openDepth(): number
	return math.clamp(State.depth(), 1, ZONES)
end

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

-- Forma centrada en (x, y). radius: nil = esquinas rectas, -1 = redonda del todo
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

-- Trozo recto de a a b, de grosor w
local function segment(parent: Instance, a: Vector2, b: Vector2, w: number, color: Color3): Frame
	local d = b - a
	local f = Comic.frame(parent, color)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude + 1, w)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	return f
end

local function catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: number): Vector2
	local t2, t3 = t * t, t * t * t
	return (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
end

local function buildGeometry()
	points[1] = HOME
	for zone = 2, ZONES do
		local k = zone - 2
		points[zone] = Vector2.new(W / 2 + SWING * math.sin(k * 1.95 + 0.6), FIRST + k * STEP)
	end
	for i = 1, ZONES - 1 do
		local p0 = points[math.max(1, i - 1)]
		local p1, p2 = points[i], points[i + 1]
		local p3 = points[math.min(ZONES, i + 2)]
		if i == 1 then
			-- Sale de la boca hacia abajo, recto
			p0 = p1 - Vector2.new(0, 60)
		end
		local list = {}
		for s = 0, SAMPLES do
			table.insert(list, catmull(p0, p1, p2, p3, s / SAMPLES))
		end
		gaps[i] = list
	end
end

-- Dibujos de cada zona, hechos con formas en un cuadro de 40 x 40
local PICTOS = {
	Jardin = function(p)
		blob(p, Comic.Dirt, 20, 26, 32, 22, 0, -1, 2)
		blob(p, Comic.Ink, 20, 24, 9, 7, 0, -1)
		blob(p, Comic.Green, 9, 34, 8, 4, -20, -1)
	end,
	Picnic = function(p)
		local cloth = blob(p, nil, 20, 20, 26, 26, -12)
		for i, spot in { { 7, 7 }, { 19, 7 }, { 7, 19 }, { 19, 19 } } do
			blob(cloth, if i == 1 or i == 4 then Comic.Red else Comic.Paper, spot[1], spot[2], 12, 12, 0, nil, 2)
		end
	end,
	Huerto = function(p)
		blob(p, Comic.Green, 16, 9, 6, 12, -25, -1, 2)
		blob(p, Comic.Green, 24, 9, 6, 12, 25, -1, 2)
		blob(p, Color3.fromRGB(250, 140, 50), 20, 25, 12, 24, 0, 6, 2)
	end,
	Jungla = function(p)
		blob(p, Color3.fromRGB(90, 190, 90), 20, 20, 16, 32, 35, -1, 2)
		blob(p, Comic.Ink, 20, 20, 2, 26, 35)
	end,
	Mar = function(p)
		blob(p, Comic.Yellow, 27, 13, 14, 14, 0, -1, 2)
		blob(p, Comic.Cyan, 20, 29, 34, 11, 0, 5, 2)
	end,
	Barbacoa = function(p)
		blob(p, Color3.fromRGB(250, 120, 50), 20, 19, 18, 26, 0, -1, 2)
		blob(p, Comic.Yellow, 20, 23, 8, 12, 0, -1)
		blob(p, Comic.Ink, 20, 34, 30, 3)
	end,
	Cocina = function(p)
		blob(p, Color3.fromRGB(120, 120, 130), 31, 13, 15, 5, -35, 2, 2)
		blob(p, Color3.fromRGB(90, 90, 100), 17, 22, 24, 24, 0, -1, 2)
		blob(p, Comic.Paper, 17, 22, 14, 12, 0, -1)
		blob(p, Comic.Yellow, 17, 22, 7, 7, 0, -1)
	end,
	Despensa = function(p)
		blob(p, Color3.fromRGB(240, 170, 60), 20, 25, 20, 22, 0, 5, 2)
		blob(p, Comic.Red, 20, 12, 22, 6, 0, 2, 2)
	end,
	Nevera = function(p)
		blob(p, Color3.fromRGB(200, 240, 255), 20, 21, 22, 22, 12, 4, 2)
		blob(p, Color3.new(1, 1, 1), 15, 16, 5, 8, 12, -1)
	end,
	Juguetes = function(p)
		blob(p, Comic.Yellow, 20, 20, 24, 24, -8, 3, 2)
		blob(p, Comic.Red, 20, 20, 10, 10, 37, 0)
	end,
	Escritorio = function(p)
		local pencil = blob(p, nil, 20, 20, 34, 9, -40)
		blob(pencil, Comic.Yellow, 13, 4.5, 26, 9, 0, nil, 2)
		blob(pencil, Comic.DirtLight, 29, 4.5, 7, 7, 45, nil, 2)
		blob(pencil, Comic.Red, 1, 4.5, 4, 9, 0, nil, 2)
	end,
	Feria = function(p)
		local ring = blob(p, nil, 20, 19, 28, 28, 0, -1, 3)
		ring.BackgroundTransparency = 1
		for _, r in { 0, 60, 120 } do
			blob(p, Comic.Ink, 20, 19, 26, 2, r)
		end
		blob(p, Comic.Red, 20, 19, 7, 7, 0, -1)
		blob(p, Comic.Ink, 20, 36, 18, 3)
	end,
	Dulce = function(p)
		local pink = Color3.fromRGB(255, 120, 180)
		blob(p, pink, 8, 20, 10, 10, 45, nil, 2)
		blob(p, pink, 32, 20, 10, 10, 45, nil, 2)
		blob(p, Color3.fromRGB(255, 200, 230), 20, 20, 18, 18, 0, -1, 2)
	end,
	Espacio = function(p)
		blob(p, Color3.fromRGB(250, 160, 80), 20, 21, 18, 18, 0, -1, 2)
		local ring = blob(p, nil, 20, 21, 34, 9, -20, -1, 2)
		ring.BackgroundTransparency = 1
		blob(p, Comic.Yellow, 7, 7, 5, 5, 45)
	end,
}

local function pictogram(parent: Instance, zone)
	local box = Comic.frame(parent)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(40, 40)
	local draw = PICTOS[zone.theme]
	if draw then
		draw(box)
	else
		local number = Comic.label(box, tostring(zone.id), Comic.Display, 26, Comic.Ink)
		number.Size = UDim2.fromScale(1, 1)
	end
	return box
end

-- Hormiga de perfil mirando a la derecha, del color de tu piel. Cada pieza recuerda dónde va para
-- poder darle la vuelta (espejo) cuando corre hacia la izquierda.
local ANT_W = 44
local antParts: { { frame: Frame, x: number, y: number, rot: number } } = {}
local antFlipped = false

local function antPart(holder: Instance, color: Color3, x: number, y: number, w: number, h: number, rot: number, radius: number?, inkWidth: number?): Frame
	local f = blob(holder, color, x, y, w, h, rot, radius, inkWidth)
	table.insert(antParts, { frame = f, x = x, y = y, rot = rot })
	return f
end

local function drawAnt(parent: Instance): Frame
	local holder = Comic.frame(parent)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(ANT_W, 30)
	for _, x in { 16, 22, 28 } do
		for _, s in { -1, 1 } do
			antPart(holder, Comic.Ink, x + s * 2, 15 + s * 8, 3, 12, s * 25)
		end
	end
	local abdomen = antPart(holder, Comic.Red, 11, 15, 20, 15, 0, -1, 2)
	local thorax = antPart(holder, Comic.Red, 23, 15, 10, 9, 0, -1, 2)
	local head = antPart(holder, Comic.Red, 33, 13, 13, 12, 0, -1, 2)
	antPart(holder, Comic.Paper, 35, 11, 4, 4, 0, -1)
	for _, s in { -1, 1 } do
		antPart(holder, Comic.Ink, 41, 6 + s * 2, 2, 10, 30 + s * 12)
	end
	antBody = { abdomen, thorax, head }
	return holder
end

local function flipAnt(flip: boolean)
	if flip == antFlipped then
		return
	end
	antFlipped = flip
	for _, e in antParts do
		e.frame.Position = UDim2.fromOffset(if flip then ANT_W - e.x else e.x, e.y)
		e.frame.Rotation = if flip then -e.rot else e.rot
	end
end

local function paintAnt()
	local def = Config.SkinById[player:GetAttribute("Skin") or ""]
	local color = if def then def.color else Comic.Red
	for _, part in antBody do
		part.BackgroundColor3 = color
	end
end

local function placeAnt(pos: Vector2, dir: Vector2?)
	ant.Position = UDim2.fromOffset(pos.X, pos.Y - 4)
	if dir and dir.Magnitude > 0.01 then
		local angle = math.deg(math.atan2(dir.Y, dir.X))
		-- Nunca cabeza abajo: si va hacia la izquierda, se mira en el espejo
		local flip = math.abs(angle) > 90
		flipAnt(flip)
		ant.Rotation = if flip then angle - 180 else angle
	end
end

local function viewHeight(): number
	return canvas.AbsoluteWindowSize.Y / math.max(fit.Scale, 0.01)
end

local function scrollTo(y: number, instant: boolean?)
	local target = math.clamp(y - viewHeight() / 2, 0, math.max(0, CONTENT - viewHeight()))
	if instant then
		canvas.CanvasPosition = Vector2.new(0, target)
	else
		TweenService:Create(canvas, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = Vector2.new(0, target) }):Play()
	end
end

local function setFocus(zone: number?, scroll: boolean?)
	focused = zone
	for id, view in stations do
		local on = id == zone
		view.name.TextColor3 = if on then Comic.Yellow elseif view.open then Comic.Paper else Comic.DirtLight
	end
	focusRing.Visible = zone ~= nil
	if zone then
		local p = points[zone]
		focusRing.Position = UDim2.fromOffset(p.X, p.Y)
		if scroll then
			scrollTo(p.Y)
		end
	end
end

local function moveFocus(step: number)
	if running then
		return
	end
	local depth = openDepth()
	if depth < 2 then
		return
	end
	local zone = math.clamp((focused or 1) + step, 2, depth)
	if zone ~= focused then
		Sfx.tick(1 + zone * 0.03)
	end
	setFocus(zone, true)
end

-- Rehace estaciones, túnel y tapas (solo si cambió la capa)
local function rebuild()
	local depth = openDepth()
	if depth == builtDepth then
		return
	end
	builtDepth = depth
	for _, name in { "ink", "fill", "dashes", "stations" } do
		layers[name]:ClearAllChildren()
	end
	stations = {}
	digOrder = {}

	for i = 1, ZONES - 1 do
		local list = gaps[i]
		local dug = i + 1 <= depth
		for k = 1, #list - 1 do
			local a, b = list[k], list[k + 1]
			if dug then
				segment(layers.ink, a, b, TUBE_INK, Comic.Ink)
				blob(layers.ink, Comic.Ink, b.X, b.Y, TUBE_INK, TUBE_INK, 0, -1)
				local fill = segment(layers.fill, a, b, TUBE, Comic.DirtLight)
				local joint = blob(layers.fill, Comic.DirtLight, b.X, b.Y, TUBE, TUBE, 0, -1)
				table.insert(digOrder, fill)
				table.insert(digOrder, joint)
			elseif k % 2 == 1 then
				-- Lo que falta por excavar: un punteado
				local dash = segment(layers.dashes, a, b, 5, Comic.DirtLight)
				dash.BackgroundTransparency = 0.55
			end
		end
	end

	for zone = 2, ZONES do
		local def = Config.Zones[zone]
		local p = points[zone]
		local open = zone <= depth

		-- Fila que se toca: todo el ancho, para dedos y ratón
		local row = Instance.new("TextButton")
		row.AutoButtonColor = false
		row.Text = ""
		row.BackgroundTransparency = 1
		row.AnchorPoint = Vector2.new(0, 0.5)
		at(row, 0, p.Y, W, ROW)
		row.Selectable = false
		row.Parent = layers.stations

		local holder = blob(layers.stations, nil, p.X, p.Y, STATION, STATION)
		holder.ZIndex = 2
		local disc = blob(holder, if open then def.floor else Comic.DirtDark, STATION / 2, STATION / 2, STATION, STATION, 0, -1, 4)
		if open then
			pictogram(disc, def)
		else
			-- Tapada de tierra: terrones encima
			for i, spot in { { 14, 16, 16 }, { 30, 14, 13 }, { 22, 30, 18 }, { 34, 30, 9 } } do
				blob(disc, if i % 2 == 0 then CLOD else Comic.Dirt, spot[1], spot[2], spot[3], spot[3] * 0.8, i * 20, -1, 2)
			end
		end

		-- Nombre al lado con más sitio
		local right = p.X < W / 2
		local name = Comic.label(layers.stations, if open then def.name else "Capa " .. zone, Comic.Display, 22, if open then Comic.Paper else Comic.DirtLight)
		name.AnchorPoint = Vector2.new(if right then 0 else 1, 0.5)
		if right then
			at(name, p.X + STATION / 2 + 10, p.Y, W - p.X - STATION / 2 - 22, 30)
		else
			at(name, p.X - STATION / 2 - 10, p.Y, p.X - STATION / 2 - 22, 30)
		end
		name.TextXAlignment = if right then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		name.TextScaled = true
		name.ZIndex = 3
		Comic.ink(name, 3)
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 26
		limit.MinTextSize = 13
		limit.Parent = name

		stations[zone] = { holder = holder, name = name, open = open }

		row.MouseEnter:Connect(function()
			if open and not running then
				setFocus(zone)
			end
		end)
		row.MouseButton1Click:Connect(function()
			if open then
				Tunnel.go(zone)
			else
				Sfx.pop(0.7)
				local base = holder.Position
				task.spawn(function()
					for _, dx in { 5, -5, 3, 0 } do
						holder.Position = base + UDim2.fromOffset(dx, 0)
						task.wait(0.03)
					end
				end)
			end
		end)
	end
end

-- Destapa el túnel de arriba abajo al abrir: se excava delante de ti
local function digIn()
	local list = digOrder
	for _, piece in list do
		piece.Visible = false
	end
	local token = runToken
	task.spawn(function()
		local total = #list
		local per = math.max(1, math.ceil(total / 14))
		for i = 1, total, per do
			if token ~= runToken or not isOpen then
				break
			end
			for j = i, math.min(total, i + per - 1) do
				list[j].Visible = true
			end
			task.wait(0.02)
		end
		for _, piece in list do
			piece.Visible = true
		end
	end)
end

local function resize()
	local camera = Workspace.CurrentCamera
	if not camera or not panel then
		return
	end
	local s = math.max(fit.Scale, 0.01)
	local view = camera.ViewportSize
	panel.Size = UDim2.fromOffset(W, math.min(CONTENT, (view.Y - MARGIN * 2) / s))
end

function Tunnel.isOpen(): boolean
	return isOpen
end

function Tunnel.close()
	if not isOpen then
		return
	end
	isOpen = false
	running = false
	runToken += 1
	openAt = nil
	closedAt = os.clock()
	-- El mapa se recoge hacia el borde
	local tween = TweenService:Create(panel, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0, -W * fit.Scale - 30, 0.5, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not isOpen then
			gui.Enabled = false
		end
	end)
end

-- Tramo de la línea de casa a la estación `zone`, con su largo acumulado
local function pathTo(zone: number): ({ Vector2 }, { number })
	local path = { points[1] }
	for i = 1, zone - 1 do
		local list = gaps[i]
		for k = 2, #list do
			table.insert(path, list[k])
		end
	end
	local lengths = { 0 }
	for k = 2, #path do
		lengths[k] = lengths[k - 1] + (path[k] - path[k - 1]).Magnitude
	end
	return path, lengths
end

local function plugDistance(): number
	-- El tapón está a media bajada del primer tramo
	local list = gaps[1]
	local d = 0
	for k = 2, SAMPLES // 2 + 1 do
		d += (list[k] - list[k - 1]).Magnitude
	end
	return d
end

local function send(zone: number)
	lastZone = zone
	Tunnel.close()
	if remote then
		Sfx.pop(0.8)
		remote:FireServer("Go", zone)
	end
end

-- Elige estación: la hormiga corre por la línea hasta ella y entonces viaja
function Tunnel.go(zone: number)
	if not isOpen or running or zone < 2 or zone > openDepth() then
		return
	end
	running = true
	runToken += 1
	local token = runToken
	setFocus(zone)
	Sfx.pop(1.1)
	local path, lengths = pathTo(zone)
	local total = lengths[#lengths]
	local speed = math.max(total / 0.75, 700) -- nunca más de ~0,75 s de carrera
	local plugAt = plugDistance()
	task.spawn(function()
		local d, k = 0, 2
		while d < total do
			local dt = RunService.Heartbeat:Wait()
			if token ~= runToken or not isOpen then
				return
			end
			local blocked = os.clock() < readyAt and d >= plugAt - 1
			if not blocked then
				d = math.min(total, d + speed * dt)
			end
			while k < #path and lengths[k] < d do
				k += 1
			end
			local a, b = path[k - 1], path[k]
			local span = lengths[k] - lengths[k - 1]
			local t = if span > 0 then math.clamp((d - lengths[k - 1]) / span, 0, 1) else 1
			local pos = a:Lerp(b, t)
			placeAnt(pos, b - a)
			canvas.CanvasPosition = Vector2.new(0, math.clamp(pos.Y - viewHeight() / 2, 0, math.max(0, CONTENT - viewHeight())))
		end
		if token == runToken and isOpen then
			Fx.shake(0.1)
			task.wait(0.06)
			if token == runToken and isOpen then
				send(zone)
			end
		end
	end)
end

function Tunnel.open(at: Vector3)
	if not gui or not hasTunnel() then
		return
	end
	if State.depth() < 2 then
		Fx.burst(at, "¡Aún no hay zonas!", Comic.Paper, 180)
		return
	end
	rebuild()
	paintAnt()
	openAt = at
	isOpen = true
	running = false
	runToken += 1
	gui.Enabled = true
	resize()
	placeAnt(points[1], Vector2.new(1, 0))
	local depth = openDepth()
	local start = if lastZone and lastZone <= depth then lastZone else depth
	setFocus(start)
	canvas.CanvasPosition = Vector2.zero
	-- Al fotograma siguiente ya se conoce el alto visible: se baja hasta la estación elegida
	task.defer(function()
		if isOpen and not running then
			scrollTo(points[start].Y)
		end
	end)
	-- Entra desde el borde izquierdo y el túnel se excava solo
	panel.Position = UDim2.new(0, -W * fit.Scale - 30, 0.5, 0)
	TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, MARGIN, 0.5, 0),
	}):Play()
	digIn()
	Sfx.pop(1.1)
end

local function build()
	buildGeometry()

	gui = Instance.new("ScreenGui")
	gui.Name = "TunnelMap"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Tocar fuera del mapa lo cierra (sin oscurecer el juego)
	local outside = Instance.new("TextButton")
	outside.AutoButtonColor = false
	outside.Text = ""
	outside.BackgroundTransparency = 1
	outside.Size = UDim2.fromScale(1, 1)
	outside.Selectable = false
	outside.Parent = gui
	outside.MouseButton1Click:Connect(Tunnel.close)

	panel = Comic.frame(gui)
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Position = UDim2.new(0, MARGIN, 0.5, 0)
	panel.Size = UDim2.fromOffset(W, 600)
	fit = Hud.fitScale(panel, ROW)

	local shadow = Comic.frame(panel, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(8, 8)

	local face = Comic.frame(panel, Comic.Dirt)
	face.Size = UDim2.fromScale(1, 1)
	face.ClipsDescendants = true
	face.Active = true
	Comic.ink(face, 5, true)

	canvas = Instance.new("ScrollingFrame")
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.CanvasSize = UDim2.fromOffset(0, CONTENT)
	canvas.ScrollingDirection = Enum.ScrollingDirection.Y
	canvas.ScrollBarThickness = 0 -- la rueda cambia de estación; se arrastra con el dedo
	canvas.ElasticBehavior = Enum.ElasticBehavior.Never
	canvas.ScrollingEnabled = UserInputService.TouchEnabled
	canvas.Parent = face

	-- Estratos: cada zona un tono más hondo, con trama de imprenta y piedrecitas
	local soil = Comic.frame(canvas)
	soil.Size = UDim2.fromOffset(W, CONTENT)
	for zone = 2, ZONES do
		local y = points[zone].Y
		local band = Comic.frame(soil, Comic.Dirt:Lerp(DEEP, (zone - 2) / (ZONES - 2) * 0.85))
		local top = if zone == 2 then SURFACE else y - STEP / 2
		at(band, 0, top, W, (if zone == ZONES then CONTENT else y + STEP / 2) - top)
	end
	local grain = Comic.image(soil, Assets.Halftone, Comic.Ink)
	grain.ScaleType = Enum.ScaleType.Tile
	grain.TileSize = UDim2.fromOffset(28, 28)
	grain.ImageTransparency = 0.84
	at(grain, 0, SURFACE, W, CONTENT - SURFACE)
	local rng = Random.new(14)
	for _ = 1, 26 do
		local y = rng:NextNumber(SURFACE + 20, CONTENT - 10)
		local stone = blob(soil, PEBBLE:Lerp(DEEP, y / CONTENT * 0.6), rng:NextNumber(10, W - 10), y, rng:NextNumber(6, 13), rng:NextNumber(4, 8), rng:NextNumber(-30, 30), -1, 2)
		stone.BackgroundTransparency = 0.25
	end

	-- Cielo, hierba y el hormiguero con su boca
	local sky = Comic.frame(soil, SKY)
	at(sky, 0, 0, W, SURFACE - 12)
	Comic.halftone(sky, Comic.Paper, 90)
	local grass = Comic.frame(soil, Comic.Green)
	at(grass, 0, SURFACE - 14, W, 14)
	local line = Comic.frame(soil, Comic.Ink)
	at(line, 0, SURFACE - 3, W, 5)
	-- El montículo: media cúpula que acaba justo en la hierba
	local hill = Comic.frame(soil)
	at(hill, 0, 0, W, SURFACE - 2)
	hill.ClipsDescendants = true
	blob(hill, Comic.Ink, HOME.X, SURFACE, 140, 96, 0, -1)
	blob(hill, Comic.DirtLight, HOME.X, SURFACE + 2, 130, 88, 0, -1)
	blob(hill, Comic.Dirt, HOME.X - 30, SURFACE - 30, 18, 10, -20, -1).BackgroundTransparency = 0.4
	blob(hill, Comic.Dirt, HOME.X + 32, SURFACE - 22, 14, 8, 15, -1).BackgroundTransparency = 0.4

	-- Letrero clavado en la hierba
	local post = Comic.frame(soil, Color3.fromRGB(150, 100, 58))
	at(post, 64, 36, 8, SURFACE - 40)
	Comic.ink(post, 3, true)
	local signHolder, signFace = Comic.box(soil, UDim2.fromOffset(150, 40), Comic.Yellow, 4)
	at(signHolder, 14, 16)
	signHolder.Rotation = -4
	local signText = Comic.label(signFace, "Túnel exprés", Comic.Display, 26, Comic.Ink)
	signText.Size = UDim2.fromScale(1, 1)

	for _, name in { "ink", "fill", "dashes", "plug", "focus", "stations", "ant" } do
		local layer = Comic.frame(canvas)
		layer.Name = name
		layer.Size = UDim2.fromOffset(W, CONTENT)
		layers[name] = layer
	end

	-- Boca del hormiguero, encima del túnel (la hormiga sale de aquí)
	blob(layers.plug, Comic.Ink, HOME.X, HOME.Y - 4, 34, 22, 0, -1)

	-- Tapón de piedras con los segundos que faltan
	local plugPoint = gaps[1][SAMPLES // 2 + 1]
	plug = Comic.frame(layers.plug)
	plug.AnchorPoint = Vector2.new(0.5, 0.5)
	at(plug, plugPoint.X, plugPoint.Y, 56, 40)
	plug.Visible = false
	blob(plug, PEBBLE, 16, 22, 22, 18, -10, -1, 3)
	blob(plug, PEBBLE:Lerp(Comic.Ink, 0.15), 36, 24, 20, 16, 12, -1, 3)
	blob(plug, PEBBLE, 27, 12, 18, 14, 0, -1, 3)
	plugLabel = Comic.label(plug, "", Comic.Display, 26, Comic.Paper)
	plugLabel.AnchorPoint = Vector2.new(0, 0.5)
	at(plugLabel, 60, 20, 40, 30)
	plugLabel.TextXAlignment = Enum.TextXAlignment.Left
	Comic.ink(plugLabel, 3)

	focusRing = blob(layers.focus, Comic.Yellow, 0, 0, STATION + 16, STATION + 16, 0, -1, 3)

	ant = drawAnt(layers.ant)
	placeAnt(points[1], Vector2.new(1, 0))

	-- Cerrar: una chapa roja en el cielo
	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(44, 44), Comic.Red, 4)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -14, 0, 12)
	closeHolder.ZIndex = 5
	closeFace.ZIndex = 5
	Comic.round(closeFace)
	Comic.round((closeHolder :: any).Shadow)
	local cross = Comic.label(closeFace, "X", Comic.Display, 28, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 6
	closeFace.MouseButton1Click:Connect(Tunnel.close)

	-- Atajos, solo con teclado y abajo del todo
	if UserInputService.KeyboardEnabled then
		local keys = Comic.label(face, "Flechas: elegir · Enter: viajar · B: cerrar", Comic.Body, 15, Comic.Paper)
		keys.AnchorPoint = Vector2.new(0.5, 1)
		keys.Position = UDim2.new(0.5, 0, 1, -6)
		keys.Size = UDim2.new(1, -20, 0, 22)
		keys.BackgroundTransparency = 0.25
		keys.BackgroundColor3 = Comic.Ink
		keys.ZIndex = 5
		Comic.round(keys, 6)
	end

	fit:GetPropertyChangedSignal("Scale"):Connect(resize)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	resize()

	-- Oscuridad del viaje, en su propia capa por encima del resto
	local travelGui = Instance.new("ScreenGui")
	travelGui.Name = "TunnelTravel"
	travelGui.IgnoreGuiInset = true
	travelGui.ResetOnSpawn = false
	travelGui.DisplayOrder = 30
	travelGui.Parent = player:WaitForChild("PlayerGui")
	dark = Comic.frame(travelGui, Color3.fromRGB(14, 9, 6))
	dark.Size = UDim2.fromScale(1, 1)
	dark.BackgroundTransparency = 1
	dark.Active = false
end

-- Cada fotograma con el mapa abierto: el aro de la estación elegida late y el tapón (visible
-- mientras el túnel se asienta tras un viaje) cuenta los segundos
local function updateMap()
	if not isOpen then
		return
	end
	local size = STATION + 14 + math.sin(os.clock() * 7) * 3
	focusRing.Size = UDim2.fromOffset(size, size)
	local left = readyAt - os.clock()
	plug.Visible = left > 0
	if left > 0 then
		plugLabel.Text = tostring(math.ceil(left))
	end
end

-- Viaje (suceso Fx "Tunnel"): caída, oscuridad breve con líneas de velocidad y salida con tierra
function Tunnel.travel(from: any, to: any)
	Tunnel.close()
	local travel = Config.Tunnel.Travel
	-- Margen pequeño: el reloj del servidor manda
	readyAt = os.clock() + travel + Config.Tunnel.Cooldown + 0.2
	if typeof(from) == "Vector3" then
		Fx.crumbs(from + Vector3.new(0, 1, 0), Comic.Dirt, 8)
	end
	Sfx.pop(0.6)
	Fx.speed(travel + 0.25)
	TweenService:Create(dark, TweenInfo.new(travel * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0.08 }):Play()
	task.delay(travel + 0.05, function()
		TweenService:Create(dark, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		if typeof(to) == "Vector3" then
			Fx.crumbs(to + Vector3.new(0, 1, 0), Comic.Dirt, 10)
			Fx.burst(to, "¡PLOP!", Comic.DirtLight, 170)
		end
		Fx.shake(0.3)
		Sfx.pop(1.25)
	end)
end

-- Cada cliente enciende solo los avisos que puede usar: el de su agujero de casa y las salidas de
-- las zonas que tiene abiertas. Sin la mejora (p. ej. tras enjambrar), ninguno. Con el mapa abierto
-- el de casa se apaga: así la B cierra el mapa sin volver a abrirlo.
local function refreshPrompts()
	local mine = hasTunnel()
	local depth = State.depth()
	local hill = State.hill()
	local homeHole = hill and hill:FindFirstChild("Tunnel")
	if homeHole then
		local prompt = homeHole:FindFirstChild("TunnelPrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = mine and not isOpen
		end
	end
	local zones = Workspace:FindFirstChild("Zones")
	local exits = zones and zones:FindFirstChild("TunnelExits")
	if exits then
		for _, hole in exits:GetChildren() do
			local prompt = hole:FindFirstChild("TunnelPrompt", true)
			local zone = hole:GetAttribute("Zone")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = mine and type(zone) == "number" and depth >= zone
			end
		end
	end
end

-- Marcador para la dueña: un estallido amarillo con la tecla que bota encima de su agujero. Sale
-- los primeros minutos tras comprar el túnel y siempre que estés a menos de MARK_NEAR studs.
local MARK_NEAR = 40
local MARK_AFTER_BUY = 180
local marker: BillboardGui
local boughtAt = -math.huge
local hadTunnel: boolean? = nil -- nil hasta la primera lectura (al entrar no cuenta como compra)

local function buildMarker()
	marker = Instance.new("BillboardGui")
	marker.Name = "TunnelMarker"
	marker.Size = UDim2.fromOffset(84, 104)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.MaxDistance = 400
	marker.ResetOnSpawn = false
	marker.Enabled = false
	marker.Parent = player:WaitForChild("PlayerGui")
	local burst = Comic.burst(marker, 76, Comic.Yellow)
	burst.Position = UDim2.new(0.5, 0, 0, 40)
	Comic.boil(burst, 6)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local key = Comic.label(burst, if touch then "Túnel" else "B", Comic.Display, if touch then 20 else 36, Comic.Ink)
	key.Size = UDim2.fromScale(1, 1)
	-- Punta hacia abajo, señalando la boca
	local tip = Comic.frame(marker, Comic.Yellow)
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.new(0.5, 0, 0, 86)
	tip.Size = UDim2.fromOffset(18, 18)
	tip.Rotation = 45
	tip.ZIndex = 0
	Comic.ink(tip, 3)
end

local function homeAnchor(): BasePart?
	local hill = State.hill()
	local hole = hill and hill:FindFirstChild("Tunnel")
	local anchor = hole and hole:FindFirstChild("PromptAnchor")
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

local function updateMarker()
	local anchor = homeAnchor()
	local root = rootPart()
	local show = anchor ~= nil
		and hasTunnel()
		and not isOpen
		and (os.clock() - boughtAt < MARK_AFTER_BUY or (root ~= nil and ((root.Position - anchor.Position) * FLAT).Magnitude < MARK_NEAR))
	marker.Enabled = show
	if show then
		marker.Adornee = anchor
		marker.StudsOffsetWorldSpace = Vector3.new(0, 5 + math.sin(os.clock() * 4) * 0.6, 0)
	end
end

-- Compra detectada en el cliente: empieza la ventana del marcador
local function watchPurchase()
	local now = hasTunnel()
	if hadTunnel == false and now then
		boughtAt = os.clock()
	end
	if State.flag("Loaded") then
		hadTunnel = now
	end
end

function Tunnel.start(remotes: Folder)
	build()
	buildMarker()
	task.spawn(function()
		local found = remotes:WaitForChild("Tunnel", 60)
		if found and found:IsA("RemoteEvent") then
			remote = found
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local kind = prompt:GetAttribute("Tunnel")
		if kind == "Home" then
			local anchor = prompt.Parent
			if isOpen then
				Tunnel.close()
			elseif os.clock() - closedAt > 0.4 and anchor and anchor:IsA("BasePart") then
				Tunnel.open(anchor.Position)
			end
		elseif kind == "Exit" and remote then
			remote:FireServer("Home")
		end
	end)

	-- Teclado y mando: flechas o cruceta para moverse, Enter o A para viajar, B o Esc para cerrar
	UserInputService.InputBegan:Connect(function(input, processed)
		if not isOpen then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
			Tunnel.close()
		elseif processed then
			return
		elseif key == Enum.KeyCode.B then
			Tunnel.close()
		elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.DPadLeft then
			moveFocus(-1)
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadDown or key == Enum.KeyCode.DPadRight then
			moveFocus(1)
		elseif (key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA) and focused then
			Tunnel.go(focused)
		end
	end)
	-- La rueda pasa de estación en estación
	UserInputService.InputChanged:Connect(function(input)
		if isOpen and input.UserInputType == Enum.UserInputType.MouseWheel then
			moveFocus(if input.Position.Z > 0 then -1 else 1)
		end
	end)

	State.onChange(function()
		watchPurchase()
		refreshPrompts()
		-- Solo se rehace si cambió la capa (rebuild lo mira): esto salta con cada bocado
		if isOpen and not running then
			local before = builtDepth
			rebuild()
			if builtDepth ~= before then
				setFocus(math.min(focused or 2, openDepth()))
			end
			paintAnt()
		end
	end)

	-- Un agujero nuevo (comprado ahora, montículo que creció, salida de una zona recién abierta):
	-- su aviso se enciende en el siguiente fotograma, sin esperar a la pasada lenta
	Workspace.DescendantAdded:Connect(function(instance)
		if instance:IsA("ProximityPrompt") and instance:GetAttribute("Tunnel") ~= nil then
			task.defer(refreshPrompts)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.3)
			refreshPrompts()
			-- Si te alejas del agujero, el mapa se cierra solo
			if openAt then
				local root = rootPart()
				if not root or not hasTunnel() or ((root.Position - openAt) * FLAT).Magnitude > Config.Tunnel.Reach + 2 then
					Tunnel.close()
				end
			end
		end
	end)

	-- El marcador bota y el tapón cuenta cada fotograma mientras se ven
	RunService.RenderStepped:Connect(function()
		updateMarker()
		updateMap()
	end)
end

return Tunnel
