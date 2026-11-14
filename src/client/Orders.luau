-- Órdenes y escuadrones (cliente). La lógica vive en src/server/Orders.luau; aquí:
--   · Panel "Órdenes" (botón lateral, tecla O): una mesa de mando. Arriba, la colonia como una fila de
--     hormiguitas partida en escuadrones (se arrastran los separadores, pasos de 10 %). Debajo, cada
--     escuadrón con su banderín y un abanico de órdenes dibujadas con piezas (sin imágenes); la elegida
--     se enciende en el centro y explica en una línea qué hace y cuánta comida por segundo traería.
--     Las bloqueadas salen en silueta con su requisito. Un escuadrón por formar es una tarjeta fantasma.
--   · Fuera del panel: un chip por escuadrón junto a la etiqueta de obreras; tocarlo (o Mayús+O) pasa
--     a la siguiente orden desbloqueada.
--   · En el mundo: banderín de color a la cabeza de cada fila (con dos o más escuadrones) y, al cambiar
--     de orden, "¡A LA ORDEN!" sobre el hormiguero y un aviso donde van ahora.
-- Remoto "Orders" (ver el servidor). Atributos del hormiguero que se leen: TrailPos1..3, TrailSquad1..3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Swarm = require(script.Parent.Swarm)

local Orders = {}

local O = Config.Orders
local player = Players.LocalPlayer
local keyboard = UserInputService.KeyboardEnabled

local ORDER_BY_ID = {}
for _, def in O.List do
	ORDER_BY_ID[def.id] = def
end

-- Medidas del panel (diseño a ~1000 px de alto; Hud.fitScale lo adapta)
local W, H = 520, 392
local ANTS = 20 -- hormiguitas de la fila de arriba: cada una, un 5 %
local ANT_W = 22
local STRIP_X = (W - ANTS * ANT_W) / 2
local STRIP_Y = 78
local COL_W, COL_GAP, COL_Y = 160, 10, 124
local FAN_R = 58
local TOKEN = 30

local TABLE_WOOD = Color3.fromRGB(122, 84, 56)
local MAP = Color3.fromRGB(246, 236, 210)
local CAKE = Color3.fromRGB(255, 170, 196)

local remote: RemoteEvent
local snap: any = nil -- última instantánea del servidor
local gui: ScreenGui
local panel: Frame
local isOpen = false
local side: any = nil
local selected = 1 -- escuadrón al que va Mayús+O
local hovered: { [number]: string? } = {}

local stripAnts: { { Frame } } = {}
local handles: { Frame } = {}
local shareLabels: { TextLabel } = {}
local dragShares: { number }? = nil -- reparto mientras se arrastra (aún no enviado)
local columns: { any } = {}
local footer: TextLabel
local chipRow: Frame? = nil
local chips: { any } = {}

---------------------------------------------------------------------------------------------------
-- Pictogramas hechos con piezas: lienzo de 30 x 30 que se escala

local function bit(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, radius: number?, stroke: number?): Frame
	local f = Comic.frame(parent, color)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	if radius then
		Comic.round(f, if radius >= 99 then nil else radius)
	end
	if stroke and stroke > 0 then
		local s = Comic.ink(f, stroke, true)
		s.LineJoinMode = Enum.LineJoinMode.Round
	end
	return f
end

-- opts: silhouette (bloqueada: todo en tinta apagada), bg (color del fondo, para los mordiscos)
local function picto(parent: Instance, id: string, size: number, opts: any?): Frame
	local silhouette = opts and opts.silhouette
	local bg = (opts and opts.bg) or Comic.Paper
	local canvas = Comic.frame(parent)
	canvas.Size = UDim2.fromOffset(30, 30)
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	local scale = Instance.new("UIScale")
	scale.Scale = size / 30
	scale.Parent = canvas
	local function c(color: Color3): Color3
		return if silhouette then Comic.Ink else color
	end
	local ink = Comic.Ink
	if id == "near" then
		-- Hormiguero con una flecha corta
		bit(canvas, 2, 11, 17, 15, c(Comic.Dirt), 8, 1.5)
		bit(canvas, 8, 18, 5, 8, ink, 2)
		bit(canvas, 19, 16, 7, 3, ink, 1)
		local head = bit(canvas, 22, 13.5, 6, 6, ink, 1)
		head.Rotation = 45
	elseif id == "rich" then
		-- Pastel con estrella
		bit(canvas, 5, 15, 20, 11, c(CAKE), 3, 1.5)
		bit(canvas, 5, 13, 20, 5, c(Comic.Paper), 2, 1.5)
		bit(canvas, 9, 21, 4, 3, c(Comic.Red), 99)
		bit(canvas, 17, 21, 4, 3, c(Comic.Red), 99)
		local a = bit(canvas, 11, 2, 8, 8, c(Comic.Yellow), 1, 1.2)
		local b = bit(canvas, 11, 2, 8, 8, c(Comic.Yellow), 1, 1.2)
		a.Rotation = 0
		b.Rotation = 45
	elseif id == "yield" then
		-- Cronómetro
		bit(canvas, 13, 2, 4, 4, ink, 1)
		bit(canvas, 6, 6, 18, 18, c(Comic.Paper), 99, 2)
		local hand = bit(canvas, 14.25, 8, 1.6, 14, c(Comic.Red), 1)
		hand.Rotation = 40
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.51, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = hand
		bit(canvas, 13.5, 13.5, 3, 3, ink, 99)
	elseif id == "side" then
		-- Tu silueta con obreras alrededor
		bit(canvas, 10, 12, 10, 13, c(Comic.Red), 99, 1.5)
		bit(canvas, 11, 4, 8, 8, c(Comic.Red), 99, 1.5)
		bit(canvas, 2, 16, 4, 4, ink, 99)
		bit(canvas, 24, 16, 4, 4, ink, 99)
		bit(canvas, 13, 26, 4, 3.5, ink, 99)
		bit(canvas, 4, 6, 3, 3, ink, 99)
	elseif id == "finish" then
		-- Comida mordida
		bit(canvas, 4, 6, 20, 20, c(Comic.Crumb), 99, 1.5)
		bit(canvas, 18, 3, 10, 10, bg, 99)
		bit(canvas, 21, 11, 8, 8, bg, 99)
		bit(canvas, 8, 14, 3, 3, c(Comic.DirtDark), 99)
		bit(canvas, 13, 19, 3, 3, c(Comic.DirtDark), 99)
	elseif id == "big" then
		-- Comida gigante y una hormiguita a su lado
		bit(canvas, 1, 2, 23, 23, c(Comic.Crumb), 99, 1.5)
		bit(canvas, 6, 8, 5, 5, c(Comic.DirtDark), 99)
		bit(canvas, 13, 14, 6, 6, c(Comic.DirtDark), 99)
		bit(canvas, 22, 22, 4, 4, ink, 99)
		bit(canvas, 25.5, 23, 3.5, 3.5, ink, 99)
	elseif id == "zone" then
		-- Mapa con chincheta
		local map = bit(canvas, 3, 7, 23, 18, c(MAP), 2, 1.5)
		map.Rotation = -6
		local f1 = bit(map, 7, 0, 1.2, 18, c(Comic.DirtLight))
		f1.ZIndex = map.ZIndex
		local f2 = bit(map, 15, 0, 1.2, 18, c(Comic.DirtLight))
		f2.ZIndex = map.ZIndex
		bit(canvas, 17.4, 11, 1.4, 7, ink, 1)
		bit(canvas, 14, 4, 8, 8, c(Comic.Red), 99, 1.5)
	end
	if silhouette then
		for _, child in canvas:GetDescendants() do
			if child:IsA("Frame") then
				child.BackgroundTransparency = 0.55
			end
		end
	end
	return canvas
end

---------------------------------------------------------------------------------------------------
-- Ayudas

local function send(...)
	if remote then
		remote:FireServer(...)
	end
end

local function at(object: GuiObject, x: number, y: number, w: number, h: number)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(w, h)
end

local function squadColor(k: number): Color3
	local def = O.Squads[k]
	return if def then def.color else Comic.Paper
end

local function requirement(def): string
	if def.depth and def.depth > 1 then
		return "Capa " .. def.depth
	end
	return (def.workers or 0) .. (if (def.workers or 0) == 1 then " obrera" else " obreras")
end

local function shortReq(def): string
	if def.depth and def.depth > 1 then
		return "C" .. def.depth
	end
	return tostring(def.workers or 0)
end

local function unlocked(id: string): boolean
	return snap ~= nil and snap.unlocked ~= nil and snap.unlocked[id] == true
end

local function squads(): { any }
	return (snap and snap.squads) or { { order = "near", share = 100, zone = 1 } }
end

local function shares(): { number }
	if dragShares then
		return dragShares
	end
	local list = {}
	for k, squad in squads() do
		list[k] = squad.share or 0
	end
	return list
end

local function hasNew(): boolean
	if not snap or not snap.unlocked then
		return false
	end
	local viewed = snap.viewed or {}
	for id in snap.unlocked do
		if not viewed[id] then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- Fila de la colonia: 20 hormiguitas partidas por escuadrones

local function antGlyph(parent: Instance, x: number): { Frame }
	local holder = Comic.frame(parent)
	at(holder, x, 0, ANT_W, 20)
	-- Patitas primero, para que queden debajo del cuerpo
	for i = 0, 2 do
		local leg = bit(holder, 8 + i * 2.4, 4, 1, 12, Comic.Ink)
		leg.Rotation = -20 + i * 20
	end
	return {
		bit(holder, 1, 6, 9, 8, Comic.Ink, 99, 1.2), -- abdomen
		bit(holder, 9, 7.5, 5, 5, Comic.Ink, 99, 1.2), -- tórax
		bit(holder, 13, 6, 7, 7, Comic.Ink, 99, 1.2), -- cabeza
	}
end

local function paintStrip()
	local list = shares()
	local count = #list
	local cum, k = 0, 1
	local bounds = {}
	for i = 1, count do
		cum += list[i]
		bounds[i] = cum
	end
	for i = 1, ANTS do
		local mid = (i - 0.5) * 100 / ANTS
		k = 1
		while k < count and mid > bounds[k] do
			k += 1
		end
		local color = squadColor(k)
		for _, part in stripAnts[i] do
			part.BackgroundColor3 = color
		end
	end
	-- Separadores y porcentajes
	local startCum = 0
	for i = 1, 3 do
		local handle = handles[i]
		if handle then
			handle.Visible = i < count
			if i < count then
				handle.Position = UDim2.fromOffset(STRIP_X + bounds[i] / 100 * ANTS * ANT_W, STRIP_Y - 6)
			end
		end
		local label = shareLabels[i]
		if i <= count then
			label.Visible = true
			local center = (startCum + list[i] / 2) / 100 * ANTS * ANT_W
			label.Position = UDim2.fromOffset(STRIP_X + center - 30, STRIP_Y - 26)
			label.Text = list[i] .. " %"
			label.TextColor3 = squadColor(i)
			startCum += list[i]
		else
			label.Visible = false
		end
	end
end

local dragging: number? = nil
local stripRow: Frame -- la fila de hormiguitas: de su borde izquierdo (0 %) al derecho (100 %)

local function dragTo(screenX: number)
	local index = dragging
	if not index or not dragShares then
		return
	end
	local list = dragShares
	local left = stripRow.AbsolutePosition.X
	local width = math.max(stripRow.AbsoluteSize.X, 1)
	local pct = math.floor(((screenX - left) / width * 100) / O.Step + 0.5) * O.Step
	local before = 0
	for i = 1, index - 1 do
		before += list[i]
	end
	local after = before + list[index] + list[index + 1]
	pct = math.clamp(pct, before + O.MinShare, after - O.MinShare)
	local newLeft = pct - before
	local newRight = after - pct
	if newLeft ~= list[index] then
		list[index] = newLeft
		list[index + 1] = newRight
		Sfx.tick(0.9 + index * 0.15)
		paintStrip()
	end
end

local function buildStrip(face: Frame)
	local back = Comic.frame(face, Comic.Paper)
	at(back, STRIP_X - 8, STRIP_Y - 4, ANTS * ANT_W + 16, 28)
	Comic.round(back, 14)
	Comic.ink(back, 3, true)
	back.ZIndex = 2
	local row = Comic.frame(face)
	at(row, STRIP_X, STRIP_Y, ANTS * ANT_W, 20)
	row.ZIndex = 3
	stripRow = row
	for i = 1, ANTS do
		stripAnts[i] = antGlyph(row, (i - 1) * ANT_W)
	end
	for i = 1, 3 do
		local label = Comic.label(face, "", Comic.Display, 18, Comic.Paper)
		label.Size = UDim2.fromOffset(60, 20)
		label.ZIndex = 4
		Comic.ink(label, 2)
		shareLabels[i] = label
	end
	-- Separadores: palitos con una bola que se arrastran
	for i = 1, 2 do
		local handle = Comic.frame(face)
		handle.Size = UDim2.fromOffset(24, 40)
		handle.AnchorPoint = Vector2.new(0.5, 0)
		handle.ZIndex = 6
		handle.Active = true
		local stick = bit(handle, 10.5, 2, 3, 34, Comic.Ink, 1)
		stick.ZIndex = 6
		local knob = bit(handle, 4, 26, 16, 16, Comic.Yellow, 99, 2.5)
		knob.Name = "Knob"
		knob.ZIndex = 7
		local grip = Comic.label(knob, "↔", Comic.Display, 14, Comic.Ink)
		grip.Size = UDim2.fromScale(1, 1)
		grip.ZIndex = 8
		local button = Instance.new("TextButton")
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.new(1, 12, 1, 8)
		button.Position = UDim2.fromOffset(-6, -2)
		button.ZIndex = 9
		button.Parent = handle
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = i
				dragShares = table.clone(shares())
				knob.BackgroundColor3 = Comic.Paper
			end
		end)
		handles[i] = handle
	end
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			dragTo(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			local index = dragging
			dragging = nil
			local knob = handles[index] and handles[index]:FindFirstChild("Knob", true)
			if knob and knob:IsA("Frame") then
				knob.BackgroundColor3 = Comic.Yellow
			end
			if dragShares then
				send("Shares", dragShares)
				-- Se queda así hasta que llegue la respuesta
				local sent = dragShares
				task.delay(1.5, function()
					if dragShares == sent then
						dragShares = nil
						paintStrip()
					end
				end)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Columnas de escuadrón: banderín, abanico de órdenes y línea de explicación

-- Banderín de un escuadrón: mástil, bola y tela de su color con su número. Devuelve (mástil, tela).
local function flagGui(parent: Instance, k: number): (Frame, Frame)
	local holder = Comic.frame(parent)
	at(holder, 6, 2, 46, 34)
	bit(holder, 2, 0, 3, 34, Comic.Ink, 1)
	bit(holder, 1, -2, 5, 5, Comic.Yellow, 99, 1.5)
	local cloth = bit(holder, 5, 3, 30, 18, squadColor(k), 4, 2.5)
	cloth.Rotation = -4
	local number = Comic.label(cloth, tostring(k), Comic.Display, 18, Comic.Paper)
	number.Size = UDim2.fromScale(1, 1)
	Comic.ink(number, 2)
	Comic.boil(cloth, 1.5)
	return holder, cloth
end

local function estimateText(k: number, id: string): string
	local est = snap and snap.est and snap.est[k]
	local value = est and est[id]
	if type(value) ~= "number" then
		return ""
	end
	return "≈ " .. Format.short(math.floor(value + 0.5)) .. "/s"
end

local function paintInfo(col)
	local k = col.index
	local list = squads()
	local squad = list[k]
	if not squad then
		return
	end
	local id = hovered[k] or squad.order
	local def = ORDER_BY_ID[id] or O.List[1]
	local locked = not unlocked(def.id)
	col.name.Text = def.name
	col.name.TextColor3 = if locked then Comic.DirtDark else Comic.Ink
	col.zoneRow.Visible = false
	if locked then
		col.desc.Text = "Se abre con " .. requirement(def) .. "."
		col.estimate.Text = ""
	else
		local text = def.desc
		if k == 1 and snap and snap.marked then
			text = "Ahora siguen tus rastros (F). " .. def.desc
		elseif not (snap and snap.deep) and def.id ~= "near" and def.id ~= "side" then
			text = def.desc .. " Sin Rastro, solo en el jardín."
		end
		col.desc.Text = text
		col.estimate.Text = estimateText(k, def.id)
		if def.id == "zone" and squad.order == "zone" and not hovered[k] then
			col.desc.Text = ""
			col.zoneRow.Visible = true
			local zone = Config.Zones[squad.zone or 1]
			col.zoneLabel.Text = (squad.zone or 1) .. " · " .. (if zone then zone.name else "")
		end
	end
end

local function paintColumn(col)
	local k = col.index
	local list = squads()
	local count = #list
	local max = (snap and snap.max) or 1
	local squad = list[k]
	col.live.Visible = squad ~= nil
	col.ghost.Visible = squad == nil and k == count + 1
	if not squad then
		if col.ghost.Visible then
			local open = k <= max
			col.ghostTitle.Text = if open then "+ Escuadrón " .. k else "Escuadrón " .. k
			col.ghostNote.Text = if open
				then "Parte la colonia: toca para formarlo"
				else "Con " .. (O.Squads[k].workers or 0) .. " obreras"
			col.ghostFace.BackgroundTransparency = if open then 0.35 else 0.7
			col.ghostTitle.TextTransparency = if open then 0 else 0.4
		end
		return
	end
	col.title.Text = O.Squads[k].name
	col.remove.Visible = k > 1 and k == count
	for id, token in col.tokens do
		local def = ORDER_BY_ID[id]
		local open = unlocked(id)
		local chosen = squad.order == id
		token.face.BackgroundColor3 = if chosen then Comic.Yellow elseif open then Comic.Paper else Comic.DirtLight
		token.scale.Scale = if chosen then 1.18 else 1
		token.lockTag.Visible = not open
		token.lockTag.Text = shortReq(def)
		token.newDot.Visible = open and snap ~= nil and not (snap.viewed or {})[id]
		if token.open ~= open then
			token.open = open
			if token.art then
				token.art:Destroy()
			end
			token.art = picto(token.face, id, 24, { silhouette = not open, bg = Comic.Paper })
		end
	end
	if col.centerId ~= squad.order then
		col.centerId = squad.order
		if col.centerArt then
			col.centerArt:Destroy()
		end
		col.centerArt = picto(col.center, squad.order, 40, { bg = Comic.Yellow })
		Comic.punch(col.centerPunch, 1.3)
	end
	col.cloth.BackgroundColor3 = squadColor(k)
	paintInfo(col)
end

local function buildColumn(face: Frame, k: number)
	local x = 10 + (k - 1) * (COL_W + COL_GAP)
	local col = { index = k, tokens = {} }

	-- Escuadrón formado
	local live = Comic.frame(face)
	at(live, x, COL_Y, COL_W, 236)
	live.ZIndex = 2
	col.live = live
	local backing = bit(live, 0, 0, COL_W, 236, MAP, 12, 3)
	backing.BackgroundTransparency = 0.08
	local _, cloth = flagGui(live, k)
	col.cloth = cloth
	col.title = Comic.label(live, "", Comic.Display, 20, Comic.Ink)
	at(col.title, 48, 6, COL_W - 80, 22)
	col.title.TextXAlignment = Enum.TextXAlignment.Left

	-- Quitar el último escuadrón: sus obreras vuelven al primero
	local removeHolder, removeFace = Comic.button(live, UDim2.fromOffset(24, 24), Comic.Red, 3)
	removeHolder.Position = UDim2.fromOffset(COL_W - 30, 6)
	Comic.round(removeFace)
	Comic.round(removeHolder:FindFirstChild("Shadow") :: Frame)
	local cross = Comic.label(removeFace, "×", Comic.Display, 20, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	removeFace.MouseButton1Click:Connect(function()
		send("Squads", k - 1)
		Sfx.pop(0.8)
	end)
	col.remove = removeHolder

	-- Centro del abanico: la orden elegida, grande y encendida
	local cx, cy = COL_W / 2, 122
	local center = bit(live, cx - 27, cy - 27, 54, 54, Comic.Yellow, 99, 3)
	center.ZIndex = 3
	col.center = center
	col.centerPunch = Instance.new("UIScale")
	col.centerPunch.Parent = center
	Comic.boil(center, 2)

	-- Abanico: las siete órdenes en arco por encima
	local count = #O.List
	for i, def in O.List do
		local angle = math.rad(200 - (i - 1) * 220 / (count - 1))
		local tx = cx + FAN_R * math.cos(angle)
		local ty = cy - FAN_R * math.sin(angle)
		local holder, tokenFace = Comic.button(live, UDim2.fromOffset(TOKEN, TOKEN), Comic.Paper, 3)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromOffset(tx, ty)
		holder.ZIndex = 4
		tokenFace.ZIndex = 4
		Comic.round(tokenFace)
		Comic.round(holder:FindFirstChild("Shadow") :: Frame)
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local lockTag = Comic.label(holder, "", Comic.Display, 12, Comic.Paper)
		lockTag.AnchorPoint = Vector2.new(0.5, 0)
		lockTag.Position = UDim2.new(0.5, 0, 1, -2)
		lockTag.Size = UDim2.fromOffset(30, 12)
		lockTag.ZIndex = 6
		Comic.ink(lockTag, 1.5)
		local newDot = bit(holder, TOKEN - 8, -3, 10, 10, Comic.Red, 99, 1.5)
		newDot.ZIndex = 7
		newDot.Visible = false
		local token = { face = tokenFace, scale = scale, lockTag = lockTag, newDot = newDot, open = nil, art = nil }
		col.tokens[def.id] = token
		tokenFace.MouseEnter:Connect(function()
			hovered[k] = def.id
			paintInfo(col)
		end)
		tokenFace.MouseLeave:Connect(function()
			if hovered[k] == def.id then
				hovered[k] = nil
				paintInfo(col)
			end
		end)
		tokenFace.MouseButton1Click:Connect(function()
			selected = k
			if unlocked(def.id) then
				hovered[k] = nil
				send("Set", k, def.id)
				Sfx.pop(1.1)
			else
				-- Bloqueada: se queda a la vista con su requisito
				hovered[k] = def.id
				paintInfo(col)
				Comic.punch(scale, 0.8)
				Sfx.pop(0.6)
			end
		end)
	end

	-- Línea de explicación
	col.name = Comic.label(live, "", Comic.Display, 19, Comic.Ink)
	at(col.name, 8, 170, COL_W - 16, 20)
	col.desc = Comic.label(live, "", Comic.Body, 12, Comic.Ink)
	at(col.desc, 8, 190, COL_W - 16, 30)
	col.desc.TextWrapped = true
	col.desc.TextYAlignment = Enum.TextYAlignment.Top
	col.desc.TextScaled = true -- los textos largos encogen antes que salirse
	local descLimit = Instance.new("UITextSizeConstraint")
	descLimit.MaxTextSize = 12
	descLimit.MinTextSize = 8
	descLimit.Parent = col.desc
	col.estimate = Comic.label(live, "", Comic.Display, 17, Comic.Red)
	at(col.estimate, 8, 216, COL_W - 16, 18)
	col.estimate.TextXAlignment = Enum.TextXAlignment.Right

	-- Zona elegida: ◀ zona ▶
	local zoneRow = Comic.frame(live)
	at(zoneRow, 8, 190, COL_W - 16, 26)
	zoneRow.Visible = false
	col.zoneRow = zoneRow
	col.zoneLabel = Comic.label(zoneRow, "", Comic.Body, 13, Comic.Ink)
	at(col.zoneLabel, 26, 0, COL_W - 68, 26)
	for side, dir in { [-1] = "◀", [1] = "▶" } do
		local holder, arrow = Comic.button(zoneRow, UDim2.fromOffset(22, 22), Comic.Paper, 2)
		holder.Position = UDim2.fromOffset(if side < 0 then 0 else COL_W - 40, 1)
		Comic.round(arrow, 6)
		local glyph = Comic.label(arrow, dir, Comic.Body, 13, Comic.Ink)
		glyph.Size = UDim2.fromScale(1, 1)
		arrow.MouseButton1Click:Connect(function()
			local squad = squads()[k]
			if not squad then
				return
			end
			local depth = math.max((snap and snap.depth) or 1, 1)
			local zone = ((squad.zone or 1) - 1 + side) % depth + 1
			send("Zone", k, zone)
			Sfx.tick(1 + side * 0.1)
		end)
	end

	-- Tarjeta fantasma: escuadrón por formar
	local ghost = Comic.frame(face)
	at(ghost, x, COL_Y, COL_W, 236)
	ghost.ZIndex = 2
	col.ghost = ghost
	local ghostFace = Instance.new("TextButton")
	ghostFace.AutoButtonColor = false
	ghostFace.Text = ""
	ghostFace.BackgroundColor3 = MAP
	ghostFace.BackgroundTransparency = 0.35
	ghostFace.Size = UDim2.fromScale(1, 1)
	ghostFace.Parent = ghost
	Comic.round(ghostFace, 12)
	local dashed = Comic.ink(ghostFace, 2.5, true)
	dashed.Transparency = 0.35
	col.ghostFace = ghostFace
	col.ghostTitle = Comic.label(ghostFace, "", Comic.Display, 22, Comic.Ink)
	at(col.ghostTitle, 8, 88, COL_W - 16, 26)
	col.ghostNote = Comic.label(ghostFace, "", Comic.Body, 13, Comic.Ink)
	at(col.ghostNote, 12, 116, COL_W - 24, 36)
	col.ghostNote.TextWrapped = true
	local ghostFlag = flagGui(ghostFace, k)
	ghostFlag.Position = UDim2.fromOffset(COL_W / 2 - 20, 40)
	for _, child in ghostFlag:GetDescendants() do
		if child:IsA("Frame") then
			child.BackgroundTransparency = 0.5
		end
	end
	ghostFace.MouseButton1Click:Connect(function()
		local max = (snap and snap.max) or 1
		if k <= max then
			send("Squads", k)
			Sfx.pop(1.2)
		else
			Sfx.pop(0.6)
		end
	end)

	columns[k] = col
	return col
end

local function paintFooter()
	if not footer then
		return
	end
	if not snap then
		footer.Text = ""
		return
	end
	local parts = { "Ahora la colonia trae " .. Format.short(math.floor((snap.rate or 0) + 0.5)) .. "/s" }
	if not snap.deep then
		table.insert(parts, "Con Rastro saldrán del jardín")
	end
	if keyboard then
		table.insert(parts, "Mayús+O: siguiente orden")
	end
	footer.Text = table.concat(parts, "  ·  ")
end

local function paintAll()
	if not gui then
		return
	end
	paintStrip()
	for _, col in columns do
		paintColumn(col)
	end
	paintFooter()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Orders"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 22
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Al borde derecho, a media altura: el centro de la pantalla es de la hormiga
	local holder, face = Comic.box(gui, UDim2.fromOffset(W, H), TABLE_WOOD, 8)
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -18, 0.52, 0)
	face.Active = true
	face.ClipsDescendants = true
	Comic.round(face, 18)
	Comic.round(holder:FindFirstChild("Shadow") :: Frame, 18)
	Hud.fitScale(holder) -- sin mínimo táctil: en móvil el panel entero no cabría
	panel = holder

	-- Vetas de la mesa
	local grain = Comic.halftone(face, Comic.DirtDark, 90)
	grain.ImageTransparency = 0.5

	-- Rótulo de papel con chincheta
	local strip = Comic.frame(face, Comic.Paper)
	at(strip, 16, 10, 160, 40)
	strip.Rotation = -2
	strip.ZIndex = 3
	Comic.round(strip, 8)
	Comic.ink(strip, 3, true)
	local title = Comic.label(strip, "Órdenes", Comic.Display, 34, Comic.Ink)
	title.Size = UDim2.fromScale(1, 1)
	title.ZIndex = 4
	local pin = bit(face, 22, 8, 12, 12, Comic.Red, 99, 2)
	pin.ZIndex = 5

	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(40, 40), Comic.Red, 4)
	closeHolder.Position = UDim2.new(1, -54, 0, 10)
	closeHolder.ZIndex = 5
	closeFace.ZIndex = 5
	Comic.round(closeFace)
	Comic.round(closeHolder:FindFirstChild("Shadow") :: Frame)
	local cross = Comic.label(closeFace, "X", Comic.Display, 26, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 6
	closeFace.MouseButton1Click:Connect(function()
		Orders.close()
	end)

	buildStrip(face)
	for k = 1, 3 do
		buildColumn(face, k)
	end

	footer = Comic.label(face, "", Comic.Body, 13, Comic.Paper)
	at(footer, 14, H - 30, W - 28, 22)
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 14
	limit.Parent = footer
	Comic.ink(footer, 1.5)
end

---------------------------------------------------------------------------------------------------
-- Chips junto a la etiqueta de obreras

local function buildChips()
	local row = Hud.tagRow()
	if not row then
		return
	end
	local holder = Comic.frame(row)
	holder.Name = "OrderChips"
	holder.AutomaticSize = Enum.AutomaticSize.XY
	holder.LayoutOrder = 2 -- justo detrás de las obreras
	holder.Visible = false
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	chipRow = holder
	for k = 1, 3 do
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.Text = ""
		button.Size = UDim2.fromOffset(26, 26)
		button.BackgroundColor3 = Comic.Paper
		button.LayoutOrder = k
		button.Visible = false
		button.Parent = holder
		Comic.round(button)
		local ring = Instance.new("UIStroke")
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Thickness = 3
		ring.Color = squadColor(k)
		ring.Parent = button
		local scale = Instance.new("UIScale")
		scale.Parent = button
		chips[k] = { button = button, scale = scale, id = nil, art = nil }
		button.MouseButton1Click:Connect(function()
			selected = k
			send("Cycle", k)
			Comic.punch(scale, 1.3)
		end)
	end
end

local function paintChips()
	if not chipRow then
		return
	end
	local list = squads()
	chipRow.Visible = unlocked("near")
	for k, chip in chips do
		local squad = list[k]
		chip.button.Visible = squad ~= nil
		if squad and chip.id ~= squad.order then
			chip.id = squad.order
			if chip.art then
				chip.art:Destroy()
			end
			chip.art = picto(chip.button, squad.order, 20, { bg = Comic.Paper })
			Comic.punch(chip.scale, 1.35)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- En el mundo: banderines y "¡A LA ORDEN!"

local flags: { any } = {} -- [hueco] = { model, pole, cloth, knob, hop }

local function flagPart(size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.Color = color
	if shape then
		part.Shape = shape
	end
	return part
end

local function makeFlag(slot: number)
	-- Dentro del modelo de las hormigas: hereda su contorno de tinta (no hace falta otro Highlight)
	local container = Workspace:FindFirstChild("Swarm")
	if not container then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "OrderFlag" .. slot
	local pole = flagPart(Vector3.new(3.6, 0.22, 0.22), Comic.Ink, Enum.PartType.Cylinder)
	pole.Parent = model
	local knob = flagPart(Vector3.new(0.6, 0.6, 0.6), Comic.Yellow, Enum.PartType.Ball)
	knob.Parent = model
	local cloth = flagPart(Vector3.new(0.14, 1.1, 1.7), Comic.Paper)
	cloth.Parent = model
	local tip = flagPart(Vector3.new(0.14, 1.1, 1.1), Comic.Paper, Enum.PartType.Cylinder) -- punta redonda
	tip.Parent = model
	model.Parent = container
	return { model = model, pole = pole, knob = knob, cloth = cloth, tip = tip, hop = 0, squad = 0 }
end

local function updateFlags(dt: number)
	local hill = State.hill()
	local show = hill ~= nil and #squads() >= 2
	for slot = 1, 3 do
		local flag = flags[slot]
		local route = if show then Swarm.route(hill :: Model, slot) else nil
		local squad = if show then (hill :: Model):GetAttribute("TrailSquad" .. slot) else nil
		if route and type(squad) == "number" then
			if not flag or not flag.model.Parent then
				flag = makeFlag(slot)
				flags[slot] = flag
			end
			if flag then
				if flag.squad ~= squad then
					flag.squad = squad
					flag.cloth.Color = squadColor(squad)
					flag.tip.Color = squadColor(squad)
					flag.hop = 1
				end
				flag.hop = math.max(flag.hop - dt * 2.2, 0)
				-- A la cabeza de la fila, junto a la comida, un poco a un lado del carril
				local base = route.to - route.dir * 1.2 + route.side * 2.4
				local lift = math.sin(flag.hop * math.pi) * 2.5
				local foot = Vector3.new(base.X, Config.GroundY + 1.8 + lift, base.Z)
				flag.pole.CFrame = CFrame.new(foot) * CFrame.Angles(0, 0, math.rad(90))
				flag.knob.CFrame = CFrame.new(foot + Vector3.new(0, 1.9, 0))
				local wave = math.sin(os.clock() * 4 + slot) * 0.25
				local facing = CFrame.lookAt(foot, foot + route.side) * CFrame.Angles(0, wave, 0)
				-- La tela se abre hacia un lado del carril; su punta es un disco (forma redondeada)
				flag.cloth.CFrame = facing * CFrame.new(0, 1.15, -0.9)
				flag.tip.CFrame = facing * CFrame.new(0, 1.15, -1.75)
			end
		elseif flag then
			flag.model:Destroy()
			flags[slot] = nil
		end
	end
end

local function onAck(k: number, id: string)
	local def = ORDER_BY_ID[id]
	local hill = State.hill()
	local color = squadColor(k)
	Sfx.pop(1.15)
	if hill then
		local top = hill:GetPivot().Position + Vector3.new(0, 9 + 3 * ((hill:GetAttribute("Scale") or 1) - 1), 0)
		Fx.word(top, "¡A LA ORDEN!", color, 44, { life = 0.9, force = true, side = 0 })
		-- Al rato, donde van ahora
		task.delay(0.9, function()
			local first = true
			for slot = 1, 3 do
				local squad = hill:GetAttribute("TrailSquad" .. slot)
				local pos = hill:GetAttribute("TrailPos" .. slot)
				local mine = squad == k or (squad == nil and k == 1)
				if mine and typeof(pos) == "Vector3" then
					if first then
						first = false
						Fx.word(pos + Vector3.new(0, 5, 0), "¡VAMOS!", color, 34, { life = 0.8, force = true, side = 0 })
					end
					Fx.sparks(pos + Vector3.new(0, 1.5, 0), 8, color)
				end
			end
		end)
	end
	if def and not isOpen then
		Bubble.flash(O.Squads[k].name .. ": " .. def.name, 2.5)
	end
end

local function onUnlocked(id: string)
	local how = if keyboard then "Pulsa O" else "Toca Órdenes"
	local def = ORDER_BY_ID[id]
	if def then
		if id == "near" then
			Bubble.flash("¡Ya puedo dar órdenes a mis obreras! " .. how, 6)
		else
			Bubble.flash("¡Orden nueva: " .. def.name .. "! " .. how, 6)
		end
	else
		local k = tonumber(string.match(id, "%d+"))
		if k then
			Bubble.flash("¡Puedo partir la colonia en " .. k .. " escuadrones! " .. how, 6)
		end
	end
	Sfx.fanfare()
	if side then
		side.setBadge(true) -- marca en el botón hasta que se abra el panel
	end
end

---------------------------------------------------------------------------------------------------
-- Abrir y cerrar

local function refreshSide()
	if not side then
		return
	end
	side.setVisible(unlocked("near"))
	side.setBadge(hasNew() and not isOpen)
end

function Orders.isOpen(): boolean
	return isOpen
end

function Orders.open()
	if not gui or not unlocked("near") then
		return
	end
	isOpen = true
	gui.Enabled = true
	send("Watch", true)
	send("Viewed")
	Sfx.pop(0.95)
	paintAll()
	refreshSide()
	local rest = UDim2.new(1, -18, 0.52, 0)
	panel.Position = rest + UDim2.fromOffset(W + 60, 0)
	TweenService:Create(panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = rest }):Play()
end

function Orders.close()
	if not isOpen then
		return
	end
	isOpen = false
	dragging = nil
	table.clear(hovered)
	if gui then
		gui.Enabled = false
	end
	send("Watch", false)
	refreshSide()
end

function Orders.toggle()
	if isOpen then
		Orders.close()
	else
		Orders.open()
	end
end

local function onState(data: any)
	if type(data) ~= "table" then
		return
	end
	snap = data
	if not dragging then
		dragShares = nil
	end
	local count = #squads()
	if selected > count then
		selected = 1
	end
	paintChips()
	refreshSide()
	if isOpen then
		paintAll()
	end
end

function Orders.start(remotes: Folder)
	remote = remotes:WaitForChild("Orders", 30) :: RemoteEvent
	if not remote then
		return
	end
	build()
	buildChips()
	side = Hud.addSideButton("Órdenes", "O", Comic.Red, Orders.toggle)
	side.setVisible(false)

	remote.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "State" then
			onState(a)
		elseif kind == "Ack" then
			if type(a) == "number" and type(b) == "string" then
				onAck(a, b)
			end
		elseif kind == "Unlocked" then
			if type(a) == "string" then
				onUnlocked(a)
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape then
			if isOpen then
				Orders.close()
			end
		elseif input.KeyCode == Enum.KeyCode.O and not processed then
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shift then
				if unlocked("near") then
					send("Cycle", selected)
				end
			else
				Orders.toggle()
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		updateFlags(math.min(dt, 0.1))
	end)

	-- Pide su estado hasta que llegue (el perfil puede tardar en existir al entrar)
	task.spawn(function()
		for _ = 1, 20 do
			if snap then
				break
			end
			send("Sync")
			task.wait(3)
		end
	end)
end

return Orders
