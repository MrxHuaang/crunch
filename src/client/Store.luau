-- Tienda de Robux. Dos cosas de naturaleza distinta, una al lado de la otra:
-- a la izquierda "Para siempre", los pases como entradas de feria apiladas (se sellan "Tuyo");
-- a la derecha "De un uso", los productos como etiquetas de precio colgando.
-- En un juego publicado solo aparece lo que tiene id en shared/Config; en Studio se ve todo
-- con el precio sugerido y una nota "sin id", para poder revisar la tienda entera.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Comic = require(script.Parent.Comic)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Store = {}

local W, H = 1000, 600
local SPLIT = 584 -- x de la línea perforada entre las dos columnas
local TICKET = Color3.fromRGB(255, 240, 204)
local TAG_COLORS = { Comic.Yellow, Comic.Cyan, Color3.fromRGB(255, 170, 196), Color3.fromRGB(170, 226, 140) }
local STUB_COLORS = { Comic.Red, Comic.Cyan, Comic.Yellow, Comic.Green }

local gui: ScreenGui
local pop: UIScale
local strips = {}

local IS_STUDIO = RunService:IsStudio()

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

local function visible(id: number): boolean
	return IS_STUDIO or id > 0
end

local function passes()
	local list = {}
	for _, pass in Config.Passes do
		if visible(pass.passId) then
			table.insert(list, pass)
		end
	end
	return list
end

local function products()
	local list = {}
	for _, product in Config.Products do
		if visible(product.productId) then
			table.insert(list, product)
		end
	end
	return list
end

function Store.enabled(): boolean
	if IS_STUDIO then
		return true
	end
	for _, pass in Config.Passes do
		if pass.passId > 0 then
			return true
		end
	end
	for _, product in Config.Products do
		if product.productId > 0 then
			return true
		end
	end
	return false
end

-- El precio lo dice Roblox, así nunca queda desfasado; si no responde, el sugerido
local function fetchPrice(label: TextLabel, id: number, infoType: Enum.InfoType, suggested: number)
	label.Text = suggested .. " R$"
	if id <= 0 then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, infoType)
		end)
		if ok and info and info.PriceInRobux then
			label.Text = info.PriceInRobux .. " R$"
		end
	end)
end

local function noId(parent: Instance): TextLabel
	local note = Comic.label(parent, "sin id", Comic.Body, 13, Comic.Red)
	note.BackgroundTransparency = 0
	note.BackgroundColor3 = Comic.Paper
	note.Size = UDim2.fromOffset(46, 16)
	note.Rotation = 4
	note.ZIndex = 9
	Comic.ink(note, 2, true)
	return note
end

local function heading(parent: Instance, text: string, x: number, rotation: number)
	local label = Comic.label(parent, text, Comic.Display, 40, Comic.Red)
	at(label, x, 14, 340, 44)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Rotation = rotation
	label.ZIndex = 3
	Comic.ink(label, 4)
end

-- Entrada de feria: talón de color con "PASE" en vertical, muescas, nombre, frase y precio
local function buildPass(parent: Instance, pass, index: number, y: number, height: number)
	local player = Players.LocalPlayer
	local holder = Comic.frame(parent)
	at(holder, 30 + (if index % 2 == 0 then 8 else 0), y, 530, height)
	holder.Rotation = if index % 2 == 0 then 0.6 else -0.5
	holder.ZIndex = 3

	local shadow = Comic.frame(holder, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(5, 5)
	shadow.ZIndex = 3

	local face = Comic.frame(holder, TICKET)
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = 4
	Comic.ink(face, 3)

	local stub = Comic.frame(face, STUB_COLORS[(index - 1) % #STUB_COLORS + 1])
	at(stub, 0, 0, 44, height)
	stub.ZIndex = 4
	local stubText = Comic.label(stub, "PASE", Comic.Display, 20, Comic.Paper)
	stubText.AnchorPoint = Vector2.new(0.5, 0.5)
	stubText.Position = UDim2.fromScale(0.5, 0.5)
	stubText.Size = UDim2.fromOffset(height, 24)
	stubText.Rotation = -90
	stubText.ZIndex = 5
	Comic.ink(stubText, 2)

	-- Muescas arriba y abajo y la línea de puntos donde se arranca el talón
	for _, edge in { 0, 1 } do
		local notch = Comic.frame(face, Comic.Paper)
		notch.AnchorPoint = Vector2.new(0.5, 0.5)
		notch.Position = UDim2.new(0, 44, edge, 0)
		notch.Size = UDim2.fromOffset(14, 14)
		notch.ZIndex = 6
		Comic.round(notch)
		Comic.ink(notch, 3)
	end
	for k = 1, math.floor((height - 16) / 9) do
		local dot = Comic.frame(face, Comic.Ink)
		at(dot, 43, 6 + k * 9, 2, 4)
		dot.ZIndex = 5
	end

	local name = Comic.label(face, pass.name, Comic.Display, 26, Comic.Ink)
	at(name, 58, 3, 320, 28)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 5

	local desc = Comic.label(face, pass.desc, Comic.Body, 15, Comic.Ink)
	at(desc, 58, 30, 330, height - 34)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.ZIndex = 5

	local buyHolder, buyFace = Comic.button(face, UDim2.fromOffset(116, 40), Comic.Yellow, 4)
	buyHolder.AnchorPoint = Vector2.new(1, 0.5)
	buyHolder.Position = UDim2.new(1, -14, 0.5, 0)
	buyHolder.ZIndex = 5
	buyHolder.Shadow.ZIndex = 5
	buyFace.ZIndex = 6
	local price = Comic.label(buyFace, "", Comic.Display, 24, Comic.Ink)
	price.Size = UDim2.fromScale(1, 1)
	price.ZIndex = 7
	fetchPrice(price, pass.passId, Enum.InfoType.GamePass, pass.robux)

	if pass.passId <= 0 then
		local note = noId(face)
		note.AnchorPoint = Vector2.new(1, 0)
		note.Position = UDim2.new(1, -8, 0, 1)
	end

	-- Sello de goma: aparece cuando el pase es tuyo
	local stamp = Comic.label(face, "Tuyo", Comic.Display, 34, Comic.Green)
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.new(1, -72, 0.5, 0)
	stamp.Size = UDim2.fromOffset(110, 44)
	stamp.Rotation = -12
	stamp.ZIndex = 8
	stamp.Visible = false
	local ring = Comic.ink(stamp, 4, true)
	ring.Color = Comic.Green
	ring.LineJoinMode = Enum.LineJoinMode.Round
	Comic.round(stamp, 8)
	local stampScale = Instance.new("UIScale")
	stampScale.Parent = stamp

	buyFace.MouseButton1Click:Connect(function()
		if pass.passId <= 0 then
			Sfx.pop(0.7)
			return
		end
		if State.flag("P_" .. pass.id) then
			Comic.punch(stampScale, 1.3)
			Sfx.pop(1.2)
			return
		end
		Sfx.pop(1.2)
		MarketplaceService:PromptGamePassPurchase(player, pass.passId)
	end)

	table.insert(strips, { pass = pass, buy = buyHolder, stamp = stamp, stampScale = stampScale, face = face })
end

-- Etiqueta de precio colgada de su cordel
local function buildProduct(parent: Instance, product, index: number, x: number, y: number)
	local player = Players.LocalPlayer
	local holder = Comic.frame(parent)
	at(holder, x, y, 172, 104)
	holder.Rotation = ({ -3, 2, 1.5, -2 })[(index - 1) % 4 + 1]
	holder.ZIndex = 3

	local shadow = Comic.frame(holder, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(5, 5)
	shadow.ZIndex = 3
	Comic.round(shadow, 16)

	local tag = Instance.new("TextButton")
	tag.AutoButtonColor = false
	tag.Text = ""
	tag.Size = UDim2.fromScale(1, 1)
	tag.BackgroundColor3 = TAG_COLORS[(index - 1) % #TAG_COLORS + 1]
	tag.BorderSizePixel = 0
	tag.ZIndex = 4
	tag.Parent = holder
	Comic.round(tag, 16)
	Comic.ink(tag, 3, true).LineJoinMode = Enum.LineJoinMode.Round
	local press = Instance.new("UIScale")
	press.Parent = tag

	-- Ojal y cordel que sale por arriba a la izquierda
	local hole = Comic.frame(tag, Comic.Paper)
	at(hole, 10, 10, 14, 14)
	hole.ZIndex = 5
	Comic.round(hole)
	Comic.ink(hole, 2)
	local cord = Comic.frame(holder, Comic.Ink)
	cord.AnchorPoint = Vector2.new(0.5, 1)
	at(cord, 12, 18, 2, 30)
	cord.Rotation = -28
	cord.ZIndex = 5

	local name = Comic.label(tag, product.name, Comic.Display, 24, Comic.Ink)
	at(name, 30, 6, 136, 26)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true
	name.ZIndex = 5
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.MinTextSize = 14
	limit.Parent = name

	local desc = Comic.label(tag, product.desc, Comic.Body, 13, Comic.Ink)
	at(desc, 10, 32, 154, 36)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.ZIndex = 5

	local price = Comic.label(tag, "", Comic.Display, 22, Comic.Ink)
	price.AnchorPoint = Vector2.new(1, 1)
	price.Position = UDim2.new(1, -8, 1, -6)
	price.Size = UDim2.fromOffset(0, 26)
	price.AutomaticSize = Enum.AutomaticSize.X
	price.BackgroundTransparency = 0
	price.BackgroundColor3 = Comic.Paper
	price.Rotation = -3
	price.ZIndex = 6
	Comic.ink(price, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = price
	fetchPrice(price, product.productId, Enum.InfoType.Product, product.robux)

	if product.productId <= 0 then
		local note = noId(tag)
		at(note, 10, 76)
	end

	tag.MouseButton1Click:Connect(function()
		if product.productId <= 0 then
			Sfx.pop(0.7)
			return
		end
		Comic.punch(press, 0.9)
		Sfx.pop(1.2)
		MarketplaceService:PromptProductPurchase(player, product.productId)
	end)
end

local function refresh()
	for _, strip in strips do
		local owned = State.flag("P_" .. strip.pass.id)
		if owned and not strip.stamp.Visible then
			Comic.punch(strip.stampScale, 1.6)
		end
		strip.stamp.Visible = owned
		strip.buy.Visible = not owned
	end
end

local function soon(parent: Instance, x: number, w: number)
	local note = Comic.label(parent, "Pronto habrá más", Comic.Body, 20, Comic.Ink)
	at(note, x, 90, w, 30)
	note.TextTransparency = 0.4
	note.ZIndex = 3
end

function Store.start()
	local player = Players.LocalPlayer

	gui = Instance.new("ScreenGui")
	gui.Name = "Store"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
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
	dim.MouseButton1Click:Connect(Store.close)

	-- Página a tamaño de diseño, encajada en la pantalla
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
			fit.Scale = math.min(view.X / (W + 40), view.Y / (H + 40), 1.4)
		end
	end
	resize()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end

	local holder, face = Comic.box(page, UDim2.fromScale(1, 1), Comic.Paper, 12)
	holder.Rotation = -0.6
	face.Active = true
	pop = Instance.new("UIScale")
	pop.Parent = holder
	local dots = Comic.halftone(face, Comic.Yellow, 45)
	dots.ZIndex = 1

	-- Columna derecha con otro tono de papel, separada por un corte perforado
	local right = Comic.frame(face, Color3.fromRGB(255, 236, 214))
	at(right, SPLIT, 0, W - SPLIT, H)
	right.ZIndex = 2
	for k = 0, math.floor(H / 18) do
		local dash = Comic.frame(face, Comic.Ink)
		at(dash, SPLIT - 2, 6 + k * 18, 4, 10)
		dash.ZIndex = 2
	end

	heading(face, "Para siempre", 30, -2)
	heading(face, "De un uso", SPLIT + 26, 2)

	-- Pases: entradas apiladas que reparten la altura disponible
	local passList = passes()
	if #passList == 0 then
		soon(face, 30, SPLIT - 60)
	else
		local top, bottom = 76, H - 20
		local stride = math.min(70, (bottom - top) / #passList)
		local height = math.min(58, stride - 6)
		for i, pass in passList do
			buildPass(face, pass, i, top + (i - 1) * stride, height)
		end
	end

	-- Productos: etiquetas en dos columnas
	local productList = products()
	if #productList == 0 then
		soon(face, SPLIT + 20, W - SPLIT - 40)
	else
		local rows = math.ceil(#productList / 2)
		local stride = math.min(124, (H - 96) / rows)
		for i, product in productList do
			local col = (i - 1) % 2
			local row = (i - 1) // 2
			buildProduct(face, product, i, SPLIT + 22 + col * 196, 80 + row * stride + col * 10)
		end
	end

	-- Cerrar: una pegatina que sobresale de la esquina
	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(56, 56), Comic.Red, 5)
	closeHolder.Position = UDim2.new(1, -36, 0, -22)
	closeHolder.Rotation = 6
	closeHolder.ZIndex = 10
	closeHolder.Shadow.ZIndex = 10
	closeFace.ZIndex = 11
	local cross = Comic.label(closeFace, "X", Comic.Display, 34, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 12
	closeFace.MouseButton1Click:Connect(Store.close)

	refresh()
	State.onChange(refresh)

	UserInputService.InputBegan:Connect(function(input)
		if Store.isOpen() and input.KeyCode == Enum.KeyCode.Escape then
			Store.close()
		end
	end)
end

function Store.open()
	if not gui then
		return
	end
	gui.Enabled = true
	Sfx.pop(0.9)
	Comic.punch(pop, 0.9)
end

function Store.close()
	if gui then
		gui.Enabled = false
	end
end

function Store.isOpen(): boolean
	return gui ~= nil and gui.Enabled
end

return Store
