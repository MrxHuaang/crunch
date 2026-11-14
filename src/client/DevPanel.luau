-- Panel DEV, solo en Studio (arranca solo si el servidor creó Remotes.Dev, cosa que solo pasa en Studio).
-- Botón "DEV" a la izquierda o tecla F2. Las capas, zonas, pases y productos salen de Config y los eventos
-- los pide al servidor (DevTools.register): un evento o una zona nueva aparecen solos, sin tocar este archivo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Comic = require(script.Parent.Comic)

local DevPanel = {}

local W, H = 440, 480 -- diseño en píxeles; Comic.autoScale lo ajusta a la pantalla
local ROW_H = 40
local GAP = 6

local player = Players.LocalPlayer
local remote: RemoteEvent
local panel: Frame? = nil
local status: TextLabel
local statusToken = 0

local function say(text: string)
	statusToken += 1
	local token = statusToken
	status.Text = text
	task.delay(3, function()
		if token == statusToken then
			status.Text = ""
		end
	end)
end

local function send(action: string, a: any?)
	remote:FireServer("Do", action, a)
end

-- Botón de texto con el estilo del juego
local function button(parent: Instance, text: string, width: number, color: Color3, onClick: () -> ()): TextButton
	local holder, face = Comic.button(parent, UDim2.fromOffset(width, ROW_H - 8), color, 3)
	holder.Name = text
	local label = Comic.label(face, text, Comic.Body, 17, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	face.Activated:Connect(onClick)
	return face
end

local function row(parent: Instance, title: string?): Frame
	local frame = Comic.frame(parent)
	frame.Size = UDim2.new(1, 0, 0, ROW_H)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	if title then
		local label = Comic.label(frame, title, Comic.Body, 17, Comic.Ink)
		label.Size = UDim2.fromOffset(92, ROW_H)
		label.TextXAlignment = Enum.TextXAlignment.Left
	end
	return frame
end

local function heading(parent: Instance, text: string)
	local label = Comic.label(parent, text, Comic.Display, 22, Comic.Ink)
	label.Size = UDim2.new(1, 0, 0, 28)
	label.TextXAlignment = Enum.TextXAlignment.Left
end

-- Página desplazable con sus filas apiladas
local function page(parent: Instance): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = Comic.Ink
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Visible = false
	scroll.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	return scroll
end

-- Un número con − y + (capa, enjambres)
local function stepper(parent: Instance, min: number, max: number, start: number): () -> number
	local value = start
	local label: TextLabel
	button(parent, "−", 36, Comic.Paper, function()
		value = math.max(min, value - 1)
		label.Text = tostring(value)
	end)
	label = Comic.label(parent, tostring(value), Comic.Display, 22, Comic.Ink)
	label.Size = UDim2.fromOffset(40, ROW_H)
	button(parent, "+", 36, Comic.Paper, function()
		value = math.min(max, value + 1)
		label.Text = tostring(value)
	end)
	return function()
		return value
	end
end

local function buildGame(scroll: ScrollingFrame)
	heading(scroll, "Partida")
	local layer = row(scroll, "Capa")
	local getLayer = stepper(layer, 1, Stats.MaxDepth, math.min(8, Stats.MaxDepth))
	button(layer, "Preparar", 110, Comic.Yellow, function()
		send("prepare", getLayer())
	end)

	local food = row(scroll, "Comida")
	for _, entry in { { "+1K", 1e3 }, { "+1M", 1e6 }, { "+1B", 1e9 }, { "+1T", 1e12 } } do
		button(food, entry[1], 64, Comic.Green, function()
			send("food", entry[2])
		end)
	end

	local jelly = row(scroll, "Jalea")
	for _, entry in { { "+10", 10 }, { "+100", 100 } } do
		button(jelly, entry[1], 64, Comic.Cyan, function()
			send("jelly", entry[2])
		end)
	end

	local swarms = row(scroll, "Enjambres")
	local getSwarms = stepper(swarms, 0, 100, 0)
	button(swarms, "Fijar", 110, Comic.Yellow, function()
		send("rebirths", getSwarms())
	end)

	local reset = row(scroll)
	button(reset, "Reiniciar partida", 200, Comic.Red, function()
		send("reset")
	end)

	heading(scroll, "Pases y productos")
	for _, list in { Config.Passes, Config.Products } do
		for _, def in list do
			local item = row(scroll)
			local name = Comic.label(item, def.name, Comic.Body, 16, Comic.Ink)
			name.Size = UDim2.fromOffset(W - 140, ROW_H)
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextTruncate = Enum.TextTruncate.AtEnd
			button(item, "Dar", 70, Comic.Green, function()
				send("grant", def.id)
			end)
		end
	end
end

local function buildTravel(scroll: ScrollingFrame)
	heading(scroll, "Viaje")
	button(row(scroll), "A casa", 200, Comic.Yellow, function()
		send("home")
	end)
	for index, zone in Config.Zones do
		button(row(scroll), `{index}. {zone.name}`, W - 60, Comic.Paper, function()
			send("zone", index)
		end)
	end
end

-- Los eventos los dice el servidor: se piden al abrir la pestaña
local function fillEvents(scroll: ScrollingFrame, list: { { id: string, label: string } })
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	heading(scroll, "Eventos")
	if #list == 0 then
		heading(scroll, "(ninguno registrado)")
	end
	for _, entry in list do
		button(row(scroll), entry.label, W - 60, Comic.Paper, function()
			send("event", entry.id)
		end)
	end
end

-- Para init.client: con un panel abierto no se muerde
function DevPanel.isOpen(): boolean
	return panel ~= nil and panel.Visible
end

function DevPanel.start(remotes: Folder)
	remote = remotes:WaitForChild("Dev") :: RemoteEvent

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Botón para abrir, abajo a la izquierda encima del de música (a media altura está el menú del HUD)
	local toggleHolder, toggle = Comic.button(gui, UDim2.fromOffset(64, 40), Comic.Red, 3)
	toggleHolder.AnchorPoint = Vector2.new(0, 1)
	toggleHolder.Position = UDim2.new(0, 14, 1, -84)
	local toggleLabel = Comic.label(toggle, "DEV", Comic.Display, 22, Comic.Paper)
	toggleLabel.Size = UDim2.fromScale(1, 1)
	Comic.autoScale(toggleHolder)

	local holder, face = Comic.box(gui, UDim2.fromOffset(W, H), Comic.Paper, 5)
	holder.Name = "Panel"
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0.1, 0, 0.5, 0) -- a la derecha del menú del HUD
	holder.Visible = false
	Comic.autoScale(holder)
	face.Active = true -- los clics en el panel no llegan al juego (no muerden)
	panel = holder
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = face

	local title = Comic.label(face, "DEV · datos de prueba", Comic.Display, 26, Comic.Ink)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local tabs = row(face)
	tabs.Position = UDim2.fromOffset(0, 34)

	local body = Comic.frame(face)
	body.Position = UDim2.fromOffset(0, 34 + ROW_H + GAP)
	body.Size = UDim2.new(1, 0, 1, -(34 + ROW_H + GAP + 28))

	status = Comic.label(face, "", Comic.Body, 16, Comic.Ink)
	status.Size = UDim2.new(1, 0, 0, 24)
	status.Position = UDim2.new(0, 0, 1, -24)
	status.TextXAlignment = Enum.TextXAlignment.Left

	local pages = { Partida = page(body), Eventos = page(body), Viaje = page(body) }
	buildGame(pages.Partida)
	buildTravel(pages.Viaje)
	fillEvents(pages.Eventos, {})

	local function show(name: string)
		for key, scroll in pages do
			scroll.Visible = key == name
		end
		if name == "Eventos" then
			remote:FireServer("List")
		end
	end
	for _, name in { "Partida", "Eventos", "Viaje" } do
		button(tabs, name, 124, Comic.Yellow, function()
			show(name)
		end)
	end
	show("Partida")

	remote.OnClientEvent:Connect(function(kind: string, value: any)
		if kind == "Done" and type(value) == "string" then
			say(value)
		elseif kind == "List" and type(value) == "table" then
			fillEvents(pages.Eventos, value)
		end
	end)

	local function flip()
		holder.Visible = not holder.Visible
	end
	toggle.Activated:Connect(flip)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 then
			flip()
		end
	end)
end

return DevPanel
