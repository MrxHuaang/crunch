-- Misiones y premio diario: un tablero de corcho pegado al borde derecho. Arriba, tres notas
-- clavadas con chincheta (cada una es una misión; el progreso es una galleta a la que se le van
-- dando mordiscos y, al cumplirla, aparece el sello "¡Cobrar!"). Abajo, la tarjeta de siete
-- casillas del premio diario, que se pica una vez al día.
-- El cliente solo pinta y pide; el servidor decide todo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Format = require(ReplicatedStorage.Shared.Format)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local Wardrobe = require(script.Parent.Wardrobe)

local Quests = {}

local W = 420 -- tamaño de diseño del panel
local H = 700
local MARGIN = 16
local NOTE_W = 360
local NOTE_H = 128
local COOKIE_W = 250
local COOKIE_H = 26
local BITES = 10
local HOLE = 40
local TAP = HOLE -- lo más pequeño que se pulsa (el botón de cambiar misión lleva zona de toque)
local TOP = 72 -- alto de la cabecera fija (rótulo y X); debajo, notas y tarjeta se desplazan

local CORK = Color3.fromRGB(196, 146, 92)
local MANILA = Color3.fromRGB(240, 214, 160)
local CHIP = Color3.fromRGB(92, 56, 34)
local NOTE_COLORS = { Color3.fromRGB(255, 236, 150), Color3.fromRGB(196, 234, 250), Color3.fromRGB(255, 204, 216) }
local NOTE_TILTS = { -2.5, 1.8, -1.2 }
local NOTE_X = { 24, 40, 28 }

local player = Players.LocalPlayer
local keyboard = UserInputService.KeyboardEnabled
local remote: RemoteEvent
local gui: ScreenGui
local panel: Frame
local fit: UIScale
local list: ScrollingFrame
local side -- botón lateral del HUD
local isOpen = false

local notes = {} -- [hueco] = vista de la nota
local holes = {} -- [día] = vista de la casilla
local dailyStatus: TextLabel

local snap = nil -- último estado completo del servidor
local rerollAt = { 0, 0, 0 } -- os.clock() local en que cada hueco puede cambiar
local dailyAt = 0 -- os.clock() local del siguiente día
local daySync = 0
local nudged = false

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%d h %d min", seconds // 3600, (seconds % 3600) // 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function send(action: string, index: number?)
	if remote then
		remote:FireServer(action, index)
	end
end

local function shake(object: GuiObject)
	local base = object.Position
	task.spawn(function()
		for _, dx in { 6, -6, 4, -3, 1, 0 } do
			object.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		object.Position = base
	end)
end

-- Estallido de cómic dentro del panel, encima de lo que acabas de cobrar
local function pop(anchor: GuiObject, text: string, color: Color3)
	-- Va colgado del panel (no de la nota) para que ninguna otra nota lo tape
	local s = math.max(fit.Scale, 0.01)
	local center = anchor.AbsolutePosition + anchor.AbsoluteSize / 2 - panel.AbsolutePosition
	local burst = Comic.burst(panel, 150, color)
	burst.Position = UDim2.fromOffset(center.X / s, center.Y / s)
	burst.ZIndex = 20
	burst.Rotation = math.random(-12, 12)
	local label = Comic.label(burst, text, Comic.Display, 30, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.TextWrapped = true
	label.ZIndex = 21
	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = burst
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.9, function()
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.wait(0.16)
		burst:Destroy()
	end)
end

-- Notas -----------------------------------------------------------------------------------

-- Galleta con chispas. Cada mordisco es un círculo del color de la nota que se come un trozo
-- desde la izquierda. No depende del recorte (en una nota girada Roblox no recorta): lo que
-- sobresale cae sobre papel del mismo color y no se ve.
local function buildCookie(parent: Instance, noteColor: Color3)
	local cookie = Comic.frame(parent, Comic.Crumb)
	at(cookie, 16, 80, COOKIE_W, COOKIE_H)
	cookie.ClipsDescendants = true
	cookie.ZIndex = 4
	Comic.round(cookie, 8)
	Comic.ink(cookie, 3)

	for i, spot in { { 18, 6 }, { 52, 14 }, { 88, 5 }, { 120, 15 }, { 158, 7 }, { 192, 13 }, { 226, 6 } } do
		local chip = Comic.frame(cookie, CHIP)
		at(chip, spot[1], spot[2], if i % 2 == 0 then 7 else 6, 6)
		chip.ZIndex = 5
		Comic.round(chip, 3)
	end

	local bites = {}
	local step = COOKIE_W / BITES
	for i = 1, BITES do
		local bite = Comic.frame(cookie, noteColor)
		bite.AnchorPoint = Vector2.new(0.5, 0.5)
		at(bite, (i - 0.5) * step, COOKIE_H / 2, 40, 40)
		bite.ZIndex = 6
		bite.Visible = false
		Comic.round(bite)
		bites[i] = bite
	end
	return cookie, bites
end

local function buildNote(parent: Instance, index: number, y: number)
	local color = NOTE_COLORS[index]
	local holder = Comic.frame(parent)
	at(holder, NOTE_X[index], y, NOTE_W, NOTE_H)
	holder.Rotation = NOTE_TILTS[index]
	holder.ZIndex = 3
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	-- Sombra corta: el papel apenas se separa del corcho
	local shadow = Comic.frame(holder, Comic.Ink)
	shadow.BackgroundTransparency = 0.55
	at(shadow, 5, 6, NOTE_W, NOTE_H)
	shadow.ZIndex = 2

	local paper = Comic.frame(holder, color)
	at(paper, 0, 0, NOTE_W, NOTE_H)
	paper.ZIndex = 3
	Comic.ink(paper, 3)

	local pin = Comic.frame(holder, Comic.Red)
	pin.AnchorPoint = Vector2.new(0.5, 0.5)
	at(pin, NOTE_W / 2, 4, 20, 20)
	pin.ZIndex = 9
	Comic.round(pin)
	Comic.ink(pin, 3)
	local shine = Comic.frame(pin, Color3.new(1, 1, 1))
	at(shine, 4, 4, 6, 5)
	shine.ZIndex = 10
	Comic.round(shine)

	local text = Comic.label(paper, "", Comic.Body, 22, Comic.Ink)
	at(text, 16, 16, 236, 54)
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.ZIndex = 5
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 22
	limit.MinTextSize = 14
	limit.Parent = text
	text.TextScaled = true

	-- Premio: una etiqueta pegada en la esquina
	local prize = Comic.label(paper, "", Comic.Display, 22, Comic.Ink)
	prize.AnchorPoint = Vector2.new(0.5, 0.5)
	at(prize, NOTE_W - 50, 30, 92, 44)
	prize.BackgroundTransparency = 0
	prize.BackgroundColor3 = Comic.Yellow
	prize.TextWrapped = true
	prize.Rotation = if index % 2 == 0 then -6 else 5
	prize.ZIndex = 6
	Comic.ink(prize, 3, true)

	local cookie, bites = buildCookie(paper, color)

	local count = Comic.label(paper, "", Comic.Display, 22, Comic.Ink)
	at(count, 16 + COOKIE_W + 10, 78, NOTE_W - COOKIE_W - 32, 30)
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.ZIndex = 5

	-- Cambiar la misión gratis, cada diez minutos
	local rerollHolder, rerollFace = Comic.button(paper, UDim2.fromOffset(112, 26), Comic.Paper, 3)
	at(rerollHolder, 16, NOTE_H - 22)
	rerollHolder.ZIndex = 6
	rerollFace.ZIndex = 6
	local rerollLabel = Comic.label(rerollFace, "Otra misión", Comic.Display, 18, Comic.Ink)
	rerollLabel.Size = UDim2.fromScale(1, 1)
	rerollLabel.ZIndex = 7

	-- Sello rojo de "¡Cobrar!": ocupa la derecha de la nota cuando está cumplida
	local stamp = Instance.new("TextButton")
	stamp.AutoButtonColor = false
	stamp.Text = ""
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.fromOffset(NOTE_W - 92, 84)
	stamp.Size = UDim2.fromOffset(150, 58)
	stamp.BackgroundColor3 = Comic.Red
	stamp.BorderSizePixel = 0
	stamp.Rotation = -10
	stamp.ZIndex = 12
	stamp.Visible = false
	stamp.Parent = paper
	Comic.round(stamp, 10)
	Comic.ink(stamp, 4, true)
	local stampLabel = Comic.label(stamp, "¡Cobrar!", Comic.Display, 36, Comic.Paper)
	stampLabel.Size = UDim2.fromScale(1, 1)
	stampLabel.ZIndex = 13
	Comic.ink(stampLabel, 3)
	local stampScale = Instance.new("UIScale")
	stampScale.Parent = stamp
	Comic.boil(stamp, 2)

	local view = {
		holder = holder,
		scale = scale,
		paper = paper,
		text = text,
		prize = prize,
		cookie = cookie,
		bites = bites,
		count = count,
		reroll = rerollHolder,
		rerollFace = rerollFace,
		rerollLabel = rerollLabel,
		stamp = stamp,
		stampScale = stampScale,
		id = nil,
		done = false,
	}

	stamp.MouseButton1Click:Connect(function()
		Comic.punch(stampScale, 0.8)
		send("Claim", index)
	end)
	local function reroll()
		if os.clock() < rerollAt[index] then
			shake(rerollHolder)
			Sfx.pop(0.7)
			return
		end
		Sfx.pop(1.1)
		send("Reroll", index)
	end
	rerollFace.MouseButton1Click:Connect(reroll)
	-- Se ve bajito (26): en táctil su zona de toque llega a 44 de diseño (≥ 44 px con la escala)
	Comic.touchPad(rerollHolder, rerollFace, 44, reroll)
	return view
end

-- Mordiscos de la galleta y número de progreso
local function paintProgress(view, have: number, goal: number)
	local ratio = math.clamp(have / math.max(goal, 1), 0, 1)
	local eaten = math.floor(ratio * BITES + 1e-6)
	for i, bite in view.bites do
		bite.Visible = i <= eaten
	end
	view.count.Text = Format.short(have) .. "/" .. Format.short(goal)
end

local function paintRerolls()
	local now = os.clock()
	for index, view in notes do
		local wait = rerollAt[index] - now
		if wait > 0 then
			view.rerollLabel.Text = "Otra en " .. clock(wait)
			view.rerollLabel.TextTransparency = 0.45
		else
			view.rerollLabel.Text = "Otra misión"
			view.rerollLabel.TextTransparency = 0
		end
	end
end

local function paintNote(index: number, slot)
	local view = notes[index]
	if not view then
		return
	end
	local fresh = view.id ~= nil and view.id ~= slot.id
	local justDone = view.id == slot.id and slot.done and not view.done
	view.id = slot.id
	view.done = slot.done

	view.text.Text = slot.text
	if slot.reward == "buff" then
		view.prize.Text = "Comida x2\n" .. math.floor(slot.amount / 60) .. " min"
		view.prize.BackgroundColor3 = Comic.Green
		view.prize.TextSize = 18
	else
		view.prize.Text = "+" .. Format.short(slot.amount)
		view.prize.BackgroundColor3 = Comic.Yellow
		view.prize.TextSize = 24
	end
	paintProgress(view, slot.have, slot.goal)
	view.stamp.Visible = slot.done
	view.reroll.Visible = not slot.done
	view.count.Visible = not slot.done

	if fresh then
		-- Nota nueva: se clava otra vez
		Comic.punch(view.scale, 0.55)
	elseif justDone then
		Comic.punch(view.stampScale, 1.6)
		Sfx.pop(1.45)
	end
end

-- Tarjeta del premio diario -----------------------------------------------------------------

local function buildCard(parent: Instance, y: number)
	local holder, face = Comic.box(parent, UDim2.fromOffset(380, 166), MANILA, 6)
	at(holder, 20, y)
	holder.Rotation = 1
	holder.ZIndex = 3
	face.ZIndex = 3
	holder:FindFirstChild("Shadow").ZIndex = 2

	local title = Comic.label(face, "Premio diario", Comic.Display, 30, Comic.Red)
	at(title, 14, 6, 200, 34)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -2
	title.ZIndex = 5
	Comic.ink(title, 2)

	dailyStatus = Comic.label(face, "", Comic.Body, 18, Comic.Ink)
	at(dailyStatus, 184, 10, 182, 28)
	dailyStatus.TextXAlignment = Enum.TextXAlignment.Right
	dailyStatus.TextScaled = true
	dailyStatus.ZIndex = 5
	local statusLimit = Instance.new("UITextSizeConstraint")
	statusLimit.MaxTextSize = 18
	statusLimit.MinTextSize = 11
	statusLimit.Parent = dailyStatus

	-- Línea de troquel bajo el título
	for i = 0, 17 do
		local dash = Comic.frame(face, Comic.Ink)
		at(dash, 14 + i * 20, 44, 10, 2)
		dash.ZIndex = 4
	end

	local step = 50
	local left = (380 - step * 7) / 2
	for day = 1, 7 do
		local cx = left + step * (day - 0.5)
		local hole = Instance.new("TextButton")
		hole.AutoButtonColor = false
		hole.Text = ""
		hole.AnchorPoint = Vector2.new(0.5, 0.5)
		hole.Position = UDim2.fromOffset(cx, 78)
		hole.Size = UDim2.fromOffset(HOLE, HOLE)
		hole.BackgroundColor3 = Comic.Paper
		hole.BorderSizePixel = 0
		hole.ZIndex = 5
		hole.Parent = face
		Comic.round(hole)
		local stroke = Comic.ink(hole, 3, true)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		local scale = Instance.new("UIScale")
		scale.Parent = hole

		local number = Comic.label(hole, tostring(day), Comic.Display, 24, Comic.Ink)
		number.Size = UDim2.fromScale(1, 1)
		number.ZIndex = 6

		local prize = Comic.label(face, "", Comic.Body, 13, Comic.Ink)
		prize.AnchorPoint = Vector2.new(0.5, 0)
		at(prize, cx, 104, step, 52)
		prize.TextWrapped = true
		prize.TextYAlignment = Enum.TextYAlignment.Top
		prize.ZIndex = 5

		hole.MouseButton1Click:Connect(function()
			local daily = snap and snap.daily
			if daily and daily.ready and daily.step == day then
				Comic.punch(scale, 0.6)
				send("Daily")
			else
				shake(hole)
				Sfx.pop(0.7)
			end
		end)
		holes[day] = { hole = hole, stroke = stroke, number = number, prize = prize, scale = scale }
	end
end

local function paintDaily(daily)
	for day, view in holes do
		local prize = daily.prizes[day]
		if prize then
			local text = "+" .. Format.short(prize.food)
			if prize.jelly > 0 then
				text = prize.jelly .. " jalea\n" .. text
			elseif prize.buff > 0 then
				text ..= "\nx2 " .. math.floor(prize.buff / 60) .. " min"
			end
			view.prize.Text = text
		end
		local punched = day <= daily.punched
		local today = daily.ready and day == daily.step
		-- Picada: un agujero por el que se ve el corcho
		view.hole.BackgroundColor3 = if punched then CORK elseif today then Comic.Yellow else Comic.Paper
		view.number.Visible = not punched
		view.number.TextColor3 = Comic.Ink
		view.stroke.Thickness = if today then 5 else 3
		view.stroke.Color = if today then Comic.Red else Comic.Ink
		view.prize.TextTransparency = if punched then 0.5 else 0
	end
	if daily.ready then
		dailyStatus.Text = "¡Pica la casilla " .. daily.step .. "!"
		dailyStatus.TextColor3 = Comic.Red
	else
		dailyStatus.Text = "Vuelve en " .. clock(dailyAt - os.clock())
		dailyStatus.TextColor3 = Comic.Ink
	end
end

-- Estado ------------------------------------------------------------------------------------

local function claimable(): boolean
	if not snap then
		return false
	end
	if snap.daily.ready then
		return true
	end
	for _, slot in snap.slots do
		if slot.done then
			return true
		end
	end
	return false
end

local function refreshBadge()
	if side then
		side.setBadge(claimable() and not isOpen)
	end
end

local function applyState(data)
	if type(data) ~= "table" or type(data.slots) ~= "table" or type(data.daily) ~= "table" then
		return
	end
	local before = snap
	snap = data
	local now = os.clock()
	for index, slot in data.slots do
		rerollAt[index] = now + (slot.reroll or 0)
		local old = before and before.slots[index]
		-- Misión cumplida con el panel cerrado: la hormiga lo dice
		if not isOpen and slot.done and old and old.id == slot.id and not old.done then
			Bubble.flash("¡Misión cumplida! " .. (if keyboard then "Pulsa T para cobrar" else "Cóbrala en Misiones"), 4)
			Sfx.pop(1.4)
		end
		paintNote(index, slot)
	end
	dailyAt = now + (data.daily.wait or 0)
	paintDaily(data.daily)
	paintRerolls()
	refreshBadge()

	-- Al entrar: si el premio diario espera, un aviso corto (sin bloquear nada)
	if not nudged then
		nudged = true
		if data.daily.ready then
			task.delay(4, function()
				Bubble.flash("¡Premio diario listo! " .. (if keyboard then "Pulsa T" else "Toca Misiones"), 6)
			end)
		end
	end
end

local function applyProgress(have)
	if not snap or type(have) ~= "table" then
		return
	end
	for index, value in have do
		local slot = snap.slots[index]
		local view = notes[index]
		if slot and view and type(value) == "number" and not slot.done then
			slot.have = value
			paintProgress(view, value, slot.goal)
		end
	end
end

local function onReward(result)
	if type(result) ~= "table" then
		return
	end
	local parts = {}
	if type(result.jelly) == "number" and result.jelly > 0 then
		table.insert(parts, "+" .. result.jelly .. " jalea")
	end
	if type(result.food) == "number" and result.food > 0 then
		table.insert(parts, "+" .. Format.short(result.food))
	end
	if type(result.buff) == "number" and result.buff > 0 then
		table.insert(parts, "x2 " .. math.floor(result.buff / 60) .. " min")
	end
	local text = table.concat(parts, "\n")
	Sfx.fanfare()
	Hud.punchFood()

	local anchor: GuiObject? = nil
	if type(result.slot) == "number" and notes[result.slot] then
		anchor = notes[result.slot].holder
	elseif type(result.daily) == "number" and holes[result.daily] then
		anchor = holes[result.daily].hole
	end
	if isOpen and anchor then
		pop(anchor, text, if result.buff and not result.food then Comic.Green else Comic.Yellow)
	end
	local character = player.Character
	if character then
		Fx.burst(character:GetPivot().Position + Vector3.new(0, 3, 0), text, Comic.Yellow, 220)
	end
end

-- Panel -------------------------------------------------------------------------------------

-- Sitio del panel: en táctil, bajo la barra de Roblox para que la X no quede bajo sus botones
local function rest(): UDim2
	return UDim2.new(1, -MARGIN - 10, 0, MARGIN + Comic.topInset())
end

local function resize()
	local camera = Workspace.CurrentCamera
	if not camera or not panel then
		return
	end
	local view = camera.ViewportSize
	local room = view.Y - MARGIN * 2 - Comic.topInset()
	local s = math.clamp(math.min(room / H, view.X * 0.45 / W), 0.4, 1.2)
	-- En táctil no se encoge por debajo del toque mínimo: si no cabe, se recorta y se desplaza
	s = math.max(s, Comic.tapScale(TAP))
	fit.Scale = s
	local height = math.min(H, room / s)
	panel.Size = UDim2.fromOffset(W, height)
	panel.Position = rest()
	list.ScrollingEnabled = height < H
	list.ScrollBarThickness = if height < H then 8 else 0
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Quests"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 22
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder, face = Comic.box(gui, UDim2.fromOffset(W, H), CORK, 10)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = rest()
	face.Active = true
	face.ClipsDescendants = true
	panel = holder
	fit = Instance.new("UIScale")
	fit.Parent = holder

	-- Textura del corcho: trama oscura en toda la tabla
	local grain = Comic.image(face, Assets.Halftone, Comic.DirtDark)
	grain.ScaleType = Enum.ScaleType.Tile
	grain.TileSize = UDim2.fromOffset(18, 18)
	grain.Size = UDim2.fromScale(1, 1)
	grain.ImageTransparency = 0.72
	grain.ZIndex = 1

	-- Rótulo: una tira de papel sujeta con cinta
	local strip = Comic.frame(face, Comic.Paper)
	at(strip, 18, 14, 210, 52)
	strip.Rotation = -2.5
	strip.ZIndex = 3
	Comic.ink(strip, 3)
	local tape = Comic.frame(face, Comic.Yellow)
	tape.BackgroundTransparency = 0.25
	tape.AnchorPoint = Vector2.new(0.5, 0.5)
	at(tape, 30, 18, 48, 16)
	tape.Rotation = -32
	tape.ZIndex = 4
	local title = Comic.label(strip, "Misiones", Comic.Display, 44, Comic.Ink)
	title.Size = UDim2.fromScale(1, 1)
	title.ZIndex = 4

	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(50, 50), Comic.Red, 4)
	closeHolder.Position = UDim2.new(1, -70, 0, 14)
	closeHolder.ZIndex = 5
	closeFace.ZIndex = 5
	local cross = Comic.label(closeFace, "X", Comic.Display, 32, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 6
	closeFace.MouseButton1Click:Connect(Quests.close)

	-- Notas y tarjeta en una lista: en PC cabe entera y no se mueve; en celular se desplaza
	list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, TOP)
	list.Size = UDim2.new(1, 0, 1, -TOP)
	list.CanvasSize = UDim2.fromOffset(0, H - TOP)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarImageColor3 = Comic.Ink
	list.ElasticBehavior = Enum.ElasticBehavior.Never
	list.ZIndex = 3
	list.Parent = face

	local y = 84 - TOP
	for index = 1, 3 do
		notes[index] = buildNote(list, index, y)
		y += NOTE_H + 14
	end
	buildCard(list, y + 6)

	resize()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
end

function Quests.isOpen(): boolean
	return isOpen
end

function Quests.open()
	if not gui then
		return
	end
	-- Comparte el borde derecho con el vestidor: solo uno a la vez
	if Wardrobe.isOpen() then
		Wardrobe.close()
	end
	isOpen = true
	resize()
	gui.Enabled = true
	send("Sync") -- los premios crecen con tu colonia: que lleguen al día
	refreshBadge()
	Sfx.pop(0.9)
	panel.Position = rest() + UDim2.fromOffset(W * fit.Scale + 40, 0)
	TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = rest() }):Play()
end

function Quests.close()
	isOpen = false
	if gui then
		gui.Enabled = false
	end
	refreshBadge()
end

function Quests.toggle()
	if isOpen then
		Quests.close()
	else
		Quests.open()
	end
end

function Quests.start(remotes: Folder)
	build()
	side = Hud.addSideButton("Misiones", "T", Comic.Yellow, Quests.toggle)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape then
			if isOpen then
				Quests.close()
			end
		elseif input.KeyCode == Enum.KeyCode.T and not processed then
			Quests.toggle()
		end
	end)

	-- Cuentas atrás (cambiar misión, día siguiente) y convivencia con el vestidor
	task.spawn(function()
		local wardrobeWas = Wardrobe.isOpen()
		while true do
			task.wait(1)
			local wardrobeNow = Wardrobe.isOpen()
			if isOpen and wardrobeNow and not wardrobeWas then
				Quests.close()
			end
			wardrobeWas = wardrobeNow
			-- Ya es otro día: se pide el estado aunque el panel esté cerrado, para el aviso del botón
			if snap and not snap.daily.ready and dailyAt - os.clock() <= 0 and os.clock() - daySync > 5 then
				daySync = os.clock()
				send("Sync")
			end
			if isOpen and snap then
				paintRerolls()
				paintDaily(snap.daily)
			end
		end
	end)

	remote = remotes:WaitForChild("Quest") :: RemoteEvent
	remote.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "State" then
			applyState(payload)
		elseif kind == "Progress" then
			applyProgress(payload)
		elseif kind == "Reward" then
			onReward(payload)
		end
	end)
	send("Sync")
end

return Quests
