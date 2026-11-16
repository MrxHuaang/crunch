-- Puestos de compra por el mapa (cliente). Las compras se encuentran caminando, hechas de bultos
-- redondos con tinta y su precio en Robux a la vista antes de pulsar nada:
--   * Excavadora: junto a la puerta de tu próxima capa. Abre esa capa ya (precio por tramos), y al lado
--     una pala dorada (la capa a mitad de comida) y una llave maestra (probar la zona 30 min). Su cartel
--     dice siempre cuánta comida te falta para abrirla gratis. Se va cuando la capa ya es tuya.
--   * Mercadillo del jardín (sitio: atributo StallMarket del servidor): frascos de potenciadores, sacos
--     de tiempo, vitrina de pases y taquilla de regalos, cada uno con su bicho tendero.
--   * En tu hormiguero: buzón con el paquete de inicio (mientras no lo tengas) y un pedestal con tus
--     potenciadores activos y su tiempo.
--   * Carritos en las zonas 3, 6, 9 y 12: imán, patas de saltamontes y banquete.
-- Casi todo es solo tuyo y lo dibuja este cliente: así cada una ve sus puertas y su hormiguero.
-- Los modelos cuelgan de modelos que ya tienen contorno de tinta (Props, Zones, el hormiguero): aquí
-- no se crea ningún Highlight.
--
-- Al acercarte sale un aviso (ProximityPrompt con estilo propio, tecla P). Abre la tienda en ese
-- artículo (Store.focus / Store.open si existen) o, si no, el aviso de compra de Roblox. Sin id en
-- Config: "Próximamente"; en Studio se entrega sin Robux para probar (remoto "Stalls" → "Try").
-- Nada se abre solo: sin ventanas emergentes ni cuentas atrás para vender.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Stalls = {}

local player = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()
local MAP = Config.Map
local GROUND = Config.GroundY
local FLAT = Vector3.new(1, 0, 1)
local KEY = Enum.KeyCode.P
local PAD_KEY = Enum.KeyCode.ButtonY
local CART_EVERY = 3 -- un carrito cada tres zonas, a partir de la 3

local INK = Comic.Ink
local PAPER = Comic.Paper
local WOOD = Color3.fromRGB(176, 120, 72)
local WOOD_DARK = Color3.fromRGB(132, 86, 52)
local GOLD = Color3.fromRGB(255, 196, 40)
local STONE = Color3.fromRGB(176, 172, 184)

local remote: RemoteEvent? = nil
local storeLib: any = nil
local storeTried = false

---------------------------------------------------------------------------------------------------
-- Catálogo

local defs: { [string]: { def: any, kind: string } } = {}
for _, pass in Config.Passes do
	defs[pass.id] = { def = pass, kind = "pass" }
end
for _, product in Config.Products do
	defs[product.id] = { def = product, kind = "product" }
end

local function find(id: string): (any, string?)
	local entry = defs[id]
	if entry then
		return entry.def, entry.kind
	end
	return nil, nil
end

local function robloxId(def, kind: string): number
	return if kind == "pass" then def.passId else def.productId
end

local function onSale(def, kind: string): boolean
	return robloxId(def, kind) > 0
end

local function owned(id: string): boolean
	local _, kind = find(id)
	return kind == "pass" and State.flag("P_" .. id)
end

-- El precio lo dice Roblox (así nunca queda desfasado); mientras tanto, el sugerido de Config
local prices: { [string]: number } = {}
local asked: { [string]: boolean } = {}
local function robux(id: string): number
	local def, kind = find(id)
	if not def then
		return 0
	end
	if not asked[id] and onSale(def, kind :: string) then
		asked[id] = true
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(robloxId(def, kind :: string), if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				prices[id] = info.PriceInRobux
			end
		end)
	end
	return prices[id] or def.robux
end

-- Lo que pone la etiqueta del artículo
local function priceText(id: string): string
	local def, kind = find(id)
	if not def then
		return ""
	end
	if owned(id) then
		return "Tuyo"
	end
	if onSale(def, kind :: string) or IS_STUDIO then
		return robux(id) .. " R$"
	end
	return "Próximamente"
end

local function getStore()
	if not storeTried then
		storeTried = true
		local module = script.Parent:FindFirstChild("Store")
		if module then
			local ok, lib = pcall(require, module)
			if ok and type(lib) == "table" then
				storeLib = lib
			end
		end
	end
	return storeLib
end

-- Comprar un artículo: tienda en ese artículo, o el aviso de Roblox, o "Próximamente".
-- target: destinataria de un regalo (ya avisada al servidor).
local function activate(id: string, target: number?)
	local def, kind = find(id)
	if not def or not kind then
		return
	end
	if owned(id) then
		Bubble.flash("¡" .. def.name .. " ya es mío!", 3)
		Sfx.pop(1.2)
		return
	end
	if not onSale(def, kind) then
		if IS_STUDIO and remote then
			remote:FireServer("Try", id, target)
			Bubble.flash("Studio: " .. def.name .. " entregado sin Robux", 3)
		else
			Bubble.flash("Próximamente: " .. def.name .. " aún no está a la venta", 4)
			Sfx.pop(0.7)
		end
		return
	end
	Sfx.pop(1.2)
	if not def.gift then
		local store = getStore()
		if store and type(store.focus) == "function" and pcall(store.focus, id) then
			return
		end
	end
	if kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, def.passId)
	else
		MarketplaceService:PromptProductPurchase(player, def.productId)
	end
end

---------------------------------------------------------------------------------------------------
-- Piezas: bultos redondos, cilindros y cuñas, sin colisión ni sombra en lo pequeño

local function piece(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, shape: string?): BasePart
	local p: BasePart = if shape == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = size.Magnitude > 4
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.CFrame = cframe
	if shape == "cyl" then
		(p :: Part).Shape = Enum.PartType.Cylinder
	elseif shape == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cilindro de pie
local FACING = CFrame.Angles(0, math.rad(90), 0) -- cilindro con la cara Right hacia delante (-Z)

-- Columna de pie entre dos alturas
local function column(parent: Instance, base: CFrame, height: number, width: number, color: Color3): BasePart
	return piece(parent, Vector3.new(height, width, width), color, base * CFrame.new(0, height / 2, 0) * UPRIGHT, "cyl")
end

-- Cilindro entre dos puntos (brazos, mangos)
local function rod(parent: Instance, a: Vector3, b: Vector3, width: number, color: Color3): BasePart
	local mid = (a + b) / 2
	local length = math.max((b - a).Magnitude, 0.05)
	-- De pie (o casi), lookAt necesita otro "arriba"
	local up = if math.abs((b - a).Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return piece(parent, Vector3.new(length, width, width), color, CFrame.lookAt(mid, b, up) * CFrame.Angles(0, math.rad(90), 0), "cyl")
end

-- Texto en una cara: líneas apiladas, con margen para que quepa en un disco
local function writeOn(target: BasePart, face: Enum.NormalId, lines: { { text: string, size: number, color: Color3?, font: Font? } }, pad: number?): { TextLabel }
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.MaxDistance = 160
	gui.Parent = target
	local margin = pad or 0.16
	local total = 0
	for _, line in lines do
		total += line.size
	end
	local labels = {}
	local y = margin
	for _, line in lines do
		local h = (1 - margin * 2) * line.size / total
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(margin * 0.75, y)
		label.Size = UDim2.fromScale(1 - margin * 1.5, h)
		label.FontFace = line.font or Comic.Display
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = line.color or INK
		label.Text = line.text
		label.Parent = gui
		table.insert(labels, label)
		y += h
	end
	return labels
end

-- Disco redondo que mira hacia delante de `cf` con texto (carteles y etiquetas de precio)
local function roundSign(parent: Instance, cf: CFrame, diameter: number, color: Color3, lines, pad: number?): (BasePart, { TextLabel })
	local disc = piece(parent, Vector3.new(0.3, diameter, diameter), color, cf * FACING, "cyl")
	disc.CastShadow = false
	-- Ribete de tinta: un disco algo mayor detrás
	piece(parent, Vector3.new(0.2, diameter + 0.35, diameter + 0.35), INK, cf * CFrame.new(0, 0, 0.12) * FACING, "cyl").CastShadow = false
	local labels = writeOn(disc, Enum.NormalId.Right, lines, pad or 0.2)
	return disc, labels
end

-- Etiqueta de precio apoyada delante de un artículo, un poco inclinada hacia arriba
local tags: { { label: TextLabel, id: string } } = {}
local function priceTag(parent: Instance, cf: CFrame, id: string, diameter: number?)
	local _, labels = roundSign(parent, cf * CFrame.Angles(math.rad(22), 0, 0), diameter or 1.6, Comic.Yellow, {
		{ text = priceText(id), size = 1 },
	}, 0.22)
	table.insert(tags, { label = labels[1], id = id })
end

---------------------------------------------------------------------------------------------------
-- Avisos con estilo propio: una tarjeta de cómic con nombre, qué hace, precio y tecla

local function addPrompt(anchorParent: Instance, at: CFrame, title: string, action: string, price: string, onTrigger: () -> ()): ProximityPrompt
	local anchor = piece(anchorParent, Vector3.new(1, 1, 1), INK, at)
	anchor.Name = "PromptAnchor"
	anchor.Transparency = 1
	anchor.CastShadow = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StallPrompt"
	prompt.ObjectText = title
	prompt.ActionText = action
	prompt.KeyboardKeyCode = KEY
	prompt.GamepadKeyCode = PAD_KEY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Stall", true)
	prompt:SetAttribute("Price", price)
	prompt.Triggered:Connect(onTrigger)
	prompt.Parent = anchor
	return prompt
end

local function promptCard(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StallPromptCard"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(250, 104)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	gui.Adornee = prompt.Parent :: any
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local holder, face = Comic.box(gui, UDim2.new(1, -8, 1, -8), PAPER, 5)
	holder.Rotation = -1.5
	local pop = Instance.new("UIScale")
	pop.Parent = holder
	Comic.punch(pop, 0.6)

	local title = Comic.label(face, prompt.ObjectText, Comic.Display, 26, INK)
	title.Position = UDim2.fromOffset(10, 4)
	title.Size = UDim2.new(1, -20, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true

	local action = Comic.label(face, prompt.ActionText, Comic.Body, 16, INK)
	action.Position = UDim2.fromOffset(10, 34)
	action.Size = UDim2.new(1, -110, 0, 40)
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextYAlignment = Enum.TextYAlignment.Top
	action.TextWrapped = true

	local price = Comic.label(face, tostring(prompt:GetAttribute("Price") or ""), Comic.Display, 22, INK)
	price.AnchorPoint = Vector2.new(1, 0)
	price.Position = UDim2.new(1, -10, 0, 38)
	price.Size = UDim2.fromOffset(92, 30)
	price.BackgroundTransparency = 0
	price.BackgroundColor3 = Comic.Yellow
	price.TextScaled = true
	price.Rotation = 3
	Comic.ink(price, 3, true)
	Comic.round(price, 8)

	local keyText = if inputType == Enum.ProximityPromptInputType.Touch
		then "Toca aquí"
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then "Botón Y"
		else "Pulsa " .. prompt.KeyboardKeyCode.Name
	local hint = Comic.label(face, keyText, Comic.Display, 18, Comic.Red)
	hint.Position = UDim2.new(0, 10, 1, -26)
	hint.Size = UDim2.new(1, -20, 0, 22)
	hint.TextXAlignment = Enum.TextXAlignment.Left

	-- En pantallas táctiles la tarjeta entera es el botón
	if inputType == Enum.ProximityPromptInputType.Touch then
		gui.Active = true
		local button = Instance.new("TextButton")
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.Parent = face
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end)
	end

	local changed = prompt:GetAttributeChangedSignal("Price"):Connect(function()
		price.Text = tostring(prompt:GetAttribute("Price") or "")
	end)
	prompt.PromptHidden:Once(function()
		changed:Disconnect()
		gui:Destroy()
	end)
end

---------------------------------------------------------------------------------------------------
-- Mostrador: lista sencilla de lo que vende un puesto (fallback de la tienda, pruebas en Studio y
-- taquilla de regalos). Solo se abre al pulsar el aviso; se cierra con la X o Esc.

local counterGui: ScreenGui? = nil

local function closeCounter()
	if counterGui then
		counterGui:Destroy()
		counterGui = nil
	end
end

-- rows: { { title, desc, button, onPick, disabled? } }
local function openCounter(heading: string, rows)
	closeCounter()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StallCounter"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 22
	gui.Parent = player:WaitForChild("PlayerGui")
	counterGui = gui

	local W = 540
	local rowH = 78
	local H = math.min(110 + #rows * rowH, 560)
	local page = Comic.frame(gui)
	page.AnchorPoint = Vector2.new(0.5, 0.5)
	page.Position = UDim2.fromScale(0.5, 0.5)
	page.Size = UDim2.fromOffset(W, H)
	Comic.autoScale(page, 820)

	local holder, face = Comic.box(page, UDim2.fromScale(1, 1), PAPER, 8)
	holder.Rotation = -0.8
	face.Active = true
	local pop = Instance.new("UIScale")
	pop.Parent = holder
	Comic.punch(pop, 0.85)

	local title = Comic.label(face, heading, Comic.Display, 38, Comic.Red)
	title.Position = UDim2.fromOffset(20, 10)
	title.Size = UDim2.new(1, -90, 0, 44)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -1.5
	Comic.ink(title, 3)

	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(16, 64)
	list.Size = UDim2.new(1, -32, 1, -80)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = INK
	list.Parent = face
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	if #rows == 0 then
		local empty = Comic.label(list, "No hay nada aquí ahora mismo", Comic.Body, 20, INK)
		empty.Size = UDim2.new(1, 0, 0, 40)
	end
	for i, row in rows do
		local line = Comic.frame(list, if i % 2 == 0 then Color3.fromRGB(255, 240, 214) else Color3.fromRGB(255, 246, 228))
		line.Size = UDim2.new(1, -10, 0, rowH - 6)
		Comic.round(line, 10)
		Comic.ink(line, 2, true)
		local name = Comic.label(line, row.title, Comic.Display, 24, INK)
		name.Position = UDim2.fromOffset(12, 4)
		name.Size = UDim2.new(1, -150, 0, 26)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextScaled = true
		local desc = Comic.label(line, row.desc or "", Comic.Body, 14, INK)
		desc.Position = UDim2.fromOffset(12, 30)
		desc.Size = UDim2.new(1, -150, 0, rowH - 38)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextWrapped = true
		local buttonHolder, buttonFace = Comic.button(line, UDim2.fromOffset(118, 44), if row.disabled then Comic.DirtLight else Comic.Yellow, 4)
		buttonHolder.AnchorPoint = Vector2.new(1, 0.5)
		buttonHolder.Position = UDim2.new(1, -12, 0.5, 0)
		local price = Comic.label(buttonFace, row.button, Comic.Display, 22, INK)
		price.Size = UDim2.fromScale(1, 1)
		price.TextScaled = true
		buttonFace.MouseButton1Click:Connect(function()
			if row.disabled then
				Sfx.pop(0.7)
				return
			end
			row.onPick()
		end)
	end

	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(50, 50), Comic.Red, 5)
	closeHolder.Position = UDim2.new(1, -34, 0, -18)
	closeHolder.Rotation = 6
	local cross = Comic.label(closeFace, "X", Comic.Display, 30, PAPER)
	cross.Size = UDim2.fromScale(1, 1)
	closeFace.MouseButton1Click:Connect(closeCounter)
	Sfx.pop(0.9)
end

local function itemRows(ids: { string }, target: number?)
	local rows = {}
	for _, id in ids do
		local def = find(id)
		if def then
			table.insert(rows, {
				title = def.name,
				desc = def.desc,
				button = priceText(id),
				disabled = owned(id),
				onPick = function()
					closeCounter()
					activate(id, target)
				end,
			})
		end
	end
	return rows
end

-- Puesto del mercadillo: la tienda en su apartado; si no está o en Studio sin ids, el mostrador
local function openStall(stall)
	local anyOnSale = false
	for _, id in stall.items do
		local def, kind = find(id)
		if def and onSale(def, kind :: string) then
			anyOnSale = true
		end
	end
	if not anyOnSale and not IS_STUDIO then
		Bubble.flash("Próximamente: este puesto aún no vende nada", 4)
		Sfx.pop(0.7)
		return
	end
	local store = getStore()
	if anyOnSale and store and type(store.open) == "function" and pcall(store.open, stall.group) then
		return
	end
	openCounter(stall.title, itemRows(stall.items))
end

-- Taquilla de regalos: primero a quién, luego qué
local function openGifts(stall)
	local rows = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(rows, {
				title = other.DisplayName,
				desc = "Elegir a " .. other.DisplayName .. " para regalarle algo",
				button = "Elegir",
				onPick = function()
					local giftRows = {}
					for _, id in stall.items do
						local def, kind = find(id)
						if def then
							table.insert(giftRows, {
								title = def.name,
								desc = def.desc,
								button = priceText(id),
								onPick = function()
									closeCounter()
									-- La destinataria se avisa antes de pagar; en Studio sin id va con la prueba
									if remote and onSale(def, kind :: string) then
										remote:FireServer("Gift", other.UserId, id)
									end
									activate(id, other.UserId)
								end,
							})
						end
					end
					openCounter("Regalo para " .. other.DisplayName, giftRows)
				end,
			})
		end
	end
	if #rows == 0 then
		Bubble.flash("No hay nadie más en el servidor a quien regalar", 4)
		return
	end
	openCounter("¿A quién le regalas?", rows)
end

---------------------------------------------------------------------------------------------------
-- Bichos tenderos (se balancean y giran un poco la cabeza)

local keepers: { { model: Model, base: CFrame, phase: number } } = {}

local function buildKeeper(parent: Instance, cf: CFrame, kind: string): Model
	local model = Instance.new("Model")
	model.Name = "Keeper"
	local white, black = Color3.fromRGB(255, 255, 255), Color3.fromRGB(26, 22, 24)
	local body, head
	if kind == "ladybug" then
		body = Color3.fromRGB(230, 52, 56)
		head = black
	elseif kind == "snail" then
		body = Color3.fromRGB(214, 150, 90)
		head = Color3.fromRGB(246, 214, 150)
	elseif kind == "bee" then
		body = Color3.fromRGB(255, 204, 50)
		head = black
	else
		body = Color3.fromRGB(70, 170, 120)
		head = Color3.fromRGB(40, 110, 80)
	end
	local root = piece(model, Vector3.new(0.4, 0.4, 0.4), INK, cf)
	root.Name = "Root"
	root.Transparency = 1
	model.PrimaryPart = root :: Part

	if kind == "snail" then
		piece(model, Vector3.new(2.6, 1.2, 1.4), head, cf * CFrame.new(0, 0.6, -0.3), "ball")
		local shell = piece(model, Vector3.new(2.4, 2.4, 1.6), body, cf * CFrame.new(0, 1.9, 0.5), "ball")
		shell.CastShadow = true
		piece(model, Vector3.new(1.2, 1.2, 1.7), Color3.fromRGB(240, 186, 120), cf * CFrame.new(0, 1.9, 0.5), "ball")
		for _, s in { -1, 1 } do
			rod(model, (cf * CFrame.new(s * 0.3, 1, -0.9)).Position, (cf * CFrame.new(s * 0.5, 2.6, -1.1)).Position, 0.18, head)
			piece(model, Vector3.new(0.5, 0.5, 0.5), white, cf * CFrame.new(s * 0.5, 2.7, -1.15), "ball")
			piece(model, Vector3.new(0.24, 0.24, 0.24), black, cf * CFrame.new(s * 0.5, 2.7, -1.38), "ball")
		end
	else
		piece(model, Vector3.new(2.4, 2.2, 2.2), body, cf * CFrame.new(0, 1.3, 0.2), "ball").CastShadow = true
		if kind == "ladybug" then
			for _, spot in { { -0.6, 1.8, -0.5 }, { 0.6, 1.6, -0.6 }, { 0, 1, -0.85 }, { -0.7, 0.9, -0.5 }, { 0.7, 0.9, -0.5 } } do
				piece(model, Vector3.new(0.45, 0.45, 0.25), black, cf * CFrame.new(spot[1], spot[2], spot[3]), "ball")
			end
		elseif kind == "bee" then
			for _, y in { 0.9, 1.6 } do
				piece(model, Vector3.new(0.35, 2.3, 2.25), black, cf * CFrame.new(0, y, 0.2) * UPRIGHT, "cyl")
			end
			for _, s in { -1, 1 } do
				local wing = piece(model, Vector3.new(1.4, 0.2, 1), white, cf * CFrame.new(s * 1, 2.4, 0.6) * CFrame.Angles(0, 0, s * 0.5), "ball")
				wing.Transparency = 0.35
			end
		end
		piece(model, Vector3.new(1.6, 1.5, 1.5), head, cf * CFrame.new(0, 2.7, -0.3), "ball")
		for _, s in { -1, 1 } do
			piece(model, Vector3.new(0.6, 0.7, 0.4), white, cf * CFrame.new(s * 0.38, 2.85, -0.98), "ball")
			piece(model, Vector3.new(0.28, 0.32, 0.2), black, cf * CFrame.new(s * 0.38, 2.82, -1.16), "ball")
			rod(model, (cf * CFrame.new(s * 0.3, 3.3, -0.4)).Position, (cf * CFrame.new(s * 0.75, 4.3, -0.7)).Position, 0.12, black)
			piece(model, Vector3.new(0.34, 0.34, 0.34), black, cf * CFrame.new(s * 0.75, 4.3, -0.7), "ball")
		end
		-- Sonrisa
		piece(model, Vector3.new(0.6, 0.14, 0.12), black, cf * CFrame.new(0, 2.35, -1.02), "ball")
	end
	model.Parent = parent
	table.insert(keepers, { model = model, base = cf, phase = math.random() * 6 })
	return model
end

---------------------------------------------------------------------------------------------------
-- Objetos del mostrador

local ITEM_COLORS = {
	potion = Color3.fromRGB(110, 200, 90), bigPotion = Color3.fromRGB(70, 170, 70), speedBoost = Color3.fromRGB(62, 193, 243),
	magnet = Color3.fromRGB(230, 57, 70), jellyBoost = Color3.fromRGB(255, 170, 196), jar = Color3.fromRGB(255, 200, 80),
	bigJar = Color3.fromRGB(255, 180, 40), feast = Color3.fromRGB(255, 150, 60), goldRain = GOLD,
}

local function itemColor(id: string, index: number): Color3
	return ITEM_COLORS[id] or ({ Comic.Cyan, Comic.Red, Comic.Green, Comic.Yellow })[(index - 1) % 4 + 1]
end

-- Un artículo sobre el mostrador: su base está en `cf` (frente = -Z)
local function buildItem(parent: Instance, cf: CFrame, look: string, id: string, index: number)
	local color = itemColor(id, index)
	if look == "jar" then
		local glass = piece(parent, Vector3.new(1.3, 1.05, 1.05), Color3.fromRGB(220, 240, 255), cf * CFrame.new(0, 0.65, 0) * UPRIGHT, "cyl")
		glass.Transparency = 0.35
		piece(parent, Vector3.new(0.8, 0.8, 0.8), color, cf * CFrame.new(0, 0.55, 0), "ball")
		piece(parent, Vector3.new(0.3, 1.12, 1.12), Comic.Red, cf * CFrame.new(0, 1.35, 0) * UPRIGHT, "cyl")
	elseif look == "sack" then
		piece(parent, Vector3.new(1.4, 1.5, 1.3), Color3.fromRGB(214, 176, 120), cf * CFrame.new(0, 0.75, 0), "ball")
		piece(parent, Vector3.new(0.6, 0.35, 0.6), WOOD_DARK, cf * CFrame.new(0, 1.45, 0), "ball")
		piece(parent, Vector3.new(0.7, 0.6, 0.7), color, cf * CFrame.new(0, 1.75, 0), "ball")
	elseif look == "gift" then
		piece(parent, Vector3.new(1.3, 1.2, 1.3), color, cf * CFrame.new(0, 0.6, 0), "ball")
		piece(parent, Vector3.new(0.25, 1.34, 1.34), PAPER, cf * CFrame.new(0, 0.6, 0), "cyl")
		for _, s in { -1, 1 } do
			piece(parent, Vector3.new(0.6, 0.4, 0.4), PAPER, cf * CFrame.new(s * 0.28, 1.3, 0) * CFrame.Angles(0, 0, s * 0.4), "ball")
		end
	else -- "ticket": entrada de feria de pie, con una estrella
		piece(parent, Vector3.new(1.5, 1, 0.22), color, cf * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(-6)), "ball")
		piece(parent, Vector3.new(0.45, 0.45, 0.3), GOLD, cf * CFrame.new(0, 0.62, -0.08), "ball")
	end
end

---------------------------------------------------------------------------------------------------
-- Mercadillo

local passIds = {}
for _, pass in Config.Passes do
	table.insert(passIds, pass.id)
end

local MARKET = {
	{ title = "Frascos", sub = "Potenciadores", group = "Potenciadores", color = Comic.Cyan, keeper = "ladybug", look = "jar", items = { "potion", "bigPotion", "speedBoost", "magnet", "jellyBoost", "jar", "bigJar" } },
	{ title = "Sacos", sub = "Tiempo y fiestas", group = "Tiempo", color = Comic.Green, keeper = "beetle", look = "sack", items = { "sack", "crate", "bigSack", "frenzy", "egg", "feast", "goldRain" } },
	{ title = "Vitrina", sub = "Para siempre", group = "Para siempre", color = Comic.Red, keeper = "snail", look = "ticket", items = passIds },
	{ title = "Regalos", sub = "Para otra jugadora", group = "Regalos", color = Color3.fromRGB(255, 150, 190), keeper = "bee", look = "gift", items = { "giftPotion", "giftSack" }, gift = true },
}

local marketSignLabel: TextLabel? = nil

local function buildStall(parent: Instance, cf: CFrame, stall)
	local model = Instance.new("Model")
	model.Name = "Stall" .. stall.title
	-- Mostrador: un bollo de madera con una franja de color y una tabla encima
	piece(model, Vector3.new(10, 3.4, 4.2), WOOD, cf * CFrame.new(0, 1.7, 0), "ball").CastShadow = true
	piece(model, Vector3.new(10.3, 1, 4.4), stall.color, cf * CFrame.new(0, 2.1, 0), "ball")
	piece(model, Vector3.new(10.6, 0.7, 4.8), WOOD_DARK, cf * CFrame.new(0, 3.4, 0), "ball")
	-- Postes y toldo a rayas con festón de bolitas
	for _, s in { -1, 1 } do
		column(model, cf * CFrame.new(s * 4.6, 0, 1.9), 8.4, 0.6, WOOD_DARK)
	end
	for i, x in { -3.6, 0, 3.6 } do
		piece(model, Vector3.new(3.9, 1.4, 6), if i % 2 == 1 then stall.color else PAPER, cf * CFrame.new(x, 8.4, -0.4) * CFrame.Angles(math.rad(-10), 0, 0), "ball").CastShadow = true
	end
	for k = 0, 6 do
		local x = -4.8 + k * 1.6
		piece(model, Vector3.new(1.3, 1.3, 1.3), if k % 2 == 0 then stall.color else PAPER, cf * CFrame.new(x, 7.6, -3.2), "ball")
	end
	-- Medallón con el nombre del puesto, sobre el toldo
	roundSign(model, cf * CFrame.new(0, 10.6, -1.6), 4.6, PAPER, {
		{ text = stall.title, size = 3, color = INK },
		{ text = stall.sub, size = 1.6, color = Comic.Red },
	})
	buildKeeper(model, cf * CFrame.new(0, 2.6, 1.6), stall.keeper)
	-- Hasta cuatro artículos a la vista, cada uno con su precio
	for i = 1, math.min(4, #stall.items) do
		local x = -3.75 + (i - 1) * 2.5
		local id = stall.items[i]
		buildItem(model, cf * CFrame.new(x, 3.75, -0.7), stall.look, id, i)
		priceTag(model, cf * CFrame.new(x, 4.05, -2.05), id, 1.5)
	end
	addPrompt(model, cf * CFrame.new(0, 3.2, -2.8), stall.title, if stall.gift then "Regalar algo a otra jugadora" else "Ver lo que vende", "Ver", function()
		if stall.gift then
			openGifts(stall)
		else
			openStall(stall)
		end
	end)
	model.Parent = parent
end

local function buildMarket(center: Vector3, look: Vector3)
	local props = Workspace:FindFirstChild("Props") or Workspace
	local old = props:FindFirstChild("Market")
	if old then
		old:Destroy()
	end
	local market = Instance.new("Model")
	market.Name = "Market"
	local plaza = center + look * 6
	for i, stall in MARKET do
		local angle = math.rad(({ -50, -17, 17, 50 })[i])
		local dir = CFrame.Angles(0, angle, 0):VectorToWorldSpace(look)
		local pos = plaza - dir * 15
		buildStall(market, CFrame.lookAt(pos, pos + dir), stall)
	end
	-- Poste del mercadillo detrás de los puestos; su cartel nombra a quien invita (banquete, lluvia)
	local post = plaza - look * 21
	local postCf = CFrame.lookAt(post, post + look)
	column(market, postCf, 12, 0.8, WOOD_DARK)
	local _, labels = roundSign(market, postCf * CFrame.new(0, 12.5, -0.6), 7, Comic.Yellow, {
		{ text = "Mercadillo", size = 3, color = INK },
		{ text = "", size = 1.6, color = Comic.Red },
	})
	marketSignLabel = labels[2]
	-- Alfombra de tierra pisada bajo la plaza
	local rug = piece(market, Vector3.new(0.12, 34, 34), Color3.fromRGB(214, 176, 124), CFrame.new(plaza.X, GROUND + 0.09, plaza.Z) * UPRIGHT, "cyl")
	rug.CastShadow = false
	market.Parent = props
end

---------------------------------------------------------------------------------------------------
-- Excavadora junto a la puerta de tu próxima capa

local digModel: Model? = nil
local digZone = 0
local digLines: { TextLabel } = {}
local digPrompts: { [string]: ProximityPrompt } = {}

local function tierFor(layer: number): string?
	for _, product in Config.Products do
		if product.layers and layer >= product.layers[1] and layer <= product.layers[2] then
			return product.id
		end
	end
	return nil
end

local function gatePivot(zone: number): Vector3?
	local gates = Workspace:FindFirstChild("Gates")
	local gate = gates and gates:FindFirstChild("Gate" .. zone)
	if gate and gate:IsA("Model") then
		return gate:GetPivot().Position
	end
	return nil
end

local function dropDig()
	if digModel then
		digModel:Destroy()
	end
	digModel = nil
	digZone = 0
	table.clear(digLines)
	table.clear(digPrompts)
end

local function buildDig(zone: number)
	dropDig()
	local gate = gatePivot(zone)
	local tier = tierFor(zone)
	if not gate or not tier then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Excavator" .. zone
	-- Del lado por donde se llega (+Z), contra la pared derecha; el frente mira a quien llega
	local base = Vector3.new(MAP.Half - 15, GROUND, gate.Z + 16)
	local cf = CFrame.lookAt(base, base + Vector3.new(0, 0, 1))
	local yellow = Color3.fromRGB(255, 196, 40)
	local dark = Color3.fromRGB(60, 56, 64)
	-- Orugas, cuerpo, cabina con ventana, chimenea
	for _, s in { -1, 1 } do
		piece(model, Vector3.new(1.9, 1.9, 7), dark, cf * CFrame.new(s * 2.6, 0.95, 0), "ball").CastShadow = true
		for k = -1, 1 do
			piece(model, Vector3.new(0.4, 1.1, 1.1), STONE, cf * CFrame.new(s * 3.5, 0.95, k * 2.2) * CFrame.Angles(0, 0, 0), "cyl")
		end
	end
	piece(model, Vector3.new(5.8, 3.4, 6.2), yellow, cf * CFrame.new(0, 3, 0), "ball").CastShadow = true
	piece(model, Vector3.new(5.9, 0.7, 6.3), INK, cf * CFrame.new(0, 2.4, 0), "ball")
	piece(model, Vector3.new(3.6, 3.2, 3.4), yellow, cf * CFrame.new(-0.9, 5.4, 1.1), "ball").CastShadow = true
	piece(model, Vector3.new(2.6, 1.8, 0.6), Color3.fromRGB(170, 220, 255), cf * CFrame.new(-0.9, 5.6, -0.55), "ball")
	column(model, cf * CFrame.new(-2.1, 5.6, 2.4), 2.2, 0.7, dark)
	for k = 0, 2 do
		piece(model, Vector3.new(1 + k * 0.4, 0.9 + k * 0.3, 1 + k * 0.4), Color3.fromRGB(235, 235, 240), cf * CFrame.new(-2.1 - k * 0.3, 8.3 + k * 0.9, 2.4 + k * 0.4), "ball")
	end
	-- Brazo y cazo hacia el lado del camino
	local shoulder = (cf * CFrame.new(1.5, 4.4, -1.8)).Position
	local elbow = (cf * CFrame.new(1.7, 7.6, -4.6)).Position
	local wrist = (cf * CFrame.new(1.7, 3.4, -7.2)).Position
	rod(model, shoulder, elbow, 0.9, yellow)
	rod(model, elbow, wrist, 0.75, yellow)
	piece(model, Vector3.new(1.2, 1.2, 1.2), dark, CFrame.new(elbow), "ball")
	piece(model, Vector3.new(2.6, 1.8, 2.2), STONE, CFrame.new(wrist) * CFrame.new(0, -0.8, 0), "ball")
	for k = -1, 1 do
		piece(model, Vector3.new(0.4, 0.7, 0.5), INK, CFrame.new(wrist) * CFrame.new(k * 0.7, -1.7, -0.6), "wedge")
	end
	-- Cartel redondo con el precio y, siempre, el camino gratis
	local signAt = cf * CFrame.new(5.2, 0, -1.6)
	column(model, signAt, 6.4, 0.5, WOOD_DARK)
	local _, lines = roundSign(model, signAt * CFrame.new(0, 8.4, -0.3), 6.4, PAPER, {
		{ text = "EXCAVADORA", size = 2.4, color = Comic.Red },
		{ text = "", size = 1.5, color = INK, font = Comic.Body },
		{ text = "", size = 2.2, color = INK },
		{ text = "", size = 1.5, color = Color3.fromRGB(40, 120, 60), font = Comic.Body },
	}, 0.17)
	digLines = lines
	digPrompts.dig = addPrompt(model, cf * CFrame.new(0, 3, -3.6), "Excavadora", "Abre la capa " .. zone .. " ya, sin pagar comida", priceText(tier), function()
		local current = tierFor(digZone)
		if current then
			activate(current)
		end
	end)
	-- Montón de tierra con la pala dorada clavada
	local pile = cf * CFrame.new(-3.4, 0, -5.6)
	piece(model, Vector3.new(3.2, 1.6, 2.8), Color3.fromRGB(170, 112, 66), pile * CFrame.new(0, 0.5, 0), "ball")
	piece(model, Vector3.new(1.8, 1.1, 1.6), Color3.fromRGB(196, 140, 86), pile * CFrame.new(0.4, 1.1, 0.2), "ball")
	rod(model, (pile * CFrame.new(0, 1.2, 0)).Position, (pile * CFrame.new(0.3, 4.4, 0.4)).Position, 0.25, WOOD_DARK)
	piece(model, Vector3.new(1.2, 1.5, 0.3), GOLD, pile * CFrame.new(-0.05, 1.3, -0.05), "ball").Reflectance = 0.15
	priceTag(model, pile * CFrame.new(0, 0.6, -1.7), "halfDig", 1.4)
	digPrompts.half = addPrompt(model, pile * CFrame.new(0, 2, -0.8), "Pala dorada", "La próxima capa te cuesta la mitad de comida", priceText("halfDig"), function()
		activate("halfDig")
	end)
	-- Poste con la llave maestra colgada
	local hook = cf * CFrame.new(7.6, 0, -4.8)
	column(model, hook, 4.6, 0.4, WOOD_DARK)
	rod(model, (hook * CFrame.new(0, 4.4, 0)).Position, (hook * CFrame.new(0, 4.4, -1)).Position, 0.2, WOOD_DARK)
	piece(model, Vector3.new(1, 1, 0.3), GOLD, hook * CFrame.new(0, 3.7, -1), "ball")
	rod(model, (hook * CFrame.new(0, 3.2, -1)).Position, (hook * CFrame.new(0, 2, -1)).Position, 0.22, GOLD)
	piece(model, Vector3.new(0.4, 0.3, 0.2), GOLD, hook * CFrame.new(0.25, 2.2, -1), "ball")
	priceTag(model, hook * CFrame.new(0, 0.7, -1.5), "zoneKey", 1.4)
	digPrompts.key = addPrompt(model, hook * CFrame.new(0, 2.4, -1.2), "Llave maestra", "Prueba la zona " .. zone .. " durante 30 minutos", priceText("zoneKey"), function()
		activate("zoneKey")
	end)

	local zones = Workspace:FindFirstChild("Zones")
	model.Parent = zones or Workspace
	digModel = model
	digZone = zone
end

local function updateDig()
	local depth = State.depth()
	local zone = depth + 1
	if zone > #Config.Zones or zone > Stats.MaxDepth then
		dropDig()
		return
	end
	if zone ~= digZone or not (digModel and digModel.Parent) then
		buildDig(zone)
	end
	if not digModel or #digLines < 4 then
		return
	end
	local tier = tierFor(zone)
	local half = State.num("HalfDig") > 0
	local cost = Stats.digCost(depth) * (if half then 0.5 else 1)
	local food = State.num("Food")
	digLines[2].Text = "Abre la capa " .. zone .. " ya"
	digLines[3].Text = if tier then priceText(tier) else ""
	digLines[4].Text = if food >= cost
		then "Gratis: ya tienes la comida. Excávala en tu hormiguero"
		else "Gratis con " .. Format.short(cost) .. " de comida: te faltan " .. Format.short(cost - food)
	if tier and digPrompts.dig then
		digPrompts.dig:SetAttribute("Price", priceText(tier))
		-- Con la comida ya en el bolsillo, excavar es gratis: no se ofrece pagar por ello
		digPrompts.dig.Enabled = food < cost
	end
	if digPrompts.half then
		digPrompts.half:SetAttribute("Price", priceText("halfDig"))
		digPrompts.half.ActionText = if half then "Ya tienes una: la próxima capa a mitad" else "La próxima capa te cuesta la mitad de comida"
	end
	if digPrompts.key then
		local keyOn = State.num("KeyDepth") == zone and State.num("KeyUntil") > State.now()
		digPrompts.key.Enabled = not keyOn
		digPrompts.key:SetAttribute("Price", priceText("zoneKey"))
	end
end

---------------------------------------------------------------------------------------------------
-- Carritos ambulantes

local carts: { [number]: Model } = {}
local CART_ITEMS = { "magnet", "speedBoost", "feast" }

local function zoneStart(zone): number
	-- Si Config trae dónde empieza de verdad cada zona, manda eso
	local fn = (Config :: any).zoneStart
	if type(fn) == "function" then
		for _, arg in { zone, zone.id } do
			local ok, value = pcall(fn, arg)
			if ok and type(value) == "number" then
				return value
			end
		end
	end
	return zone.z0
end

local function buildCart(zone): Model
	local model = Instance.new("Model")
	model.Name = "Cart" .. zone.id
	-- Pegado a la pared derecha, nada más pasar la puerta y antes de donde sale la comida
	local base = Vector3.new(MAP.Half - 7, GROUND, zoneStart(zone) - 7)
	local cf = CFrame.lookAt(base, base + Vector3.new(-1, 0, 0))
	piece(model, Vector3.new(6.4, 2.6, 3.4), WOOD, cf * CFrame.new(0, 2.3, 0), "ball").CastShadow = true
	piece(model, Vector3.new(6.7, 0.6, 3.8), WOOD_DARK, cf * CFrame.new(0, 3.5, 0), "ball")
	for _, s in { -1, 1 } do
		local wheel = cf * CFrame.new(s * 2.3, 1.3, -1.7) * FACING
		piece(model, Vector3.new(0.5, 2.6, 2.6), WOOD_DARK, wheel, "cyl")
		piece(model, Vector3.new(0.6, 0.8, 0.8), GOLD, wheel, "cyl")
	end
	rod(model, (cf * CFrame.new(3, 2.6, 0.8)).Position, (cf * CFrame.new(5.2, 2.2, 0.8)).Position, 0.3, WOOD_DARK)
	rod(model, (cf * CFrame.new(3, 2.6, -0.8)).Position, (cf * CFrame.new(5.2, 2.2, -0.8)).Position, 0.3, WOOD_DARK)
	-- Sombrilla a rayas
	column(model, cf * CFrame.new(0, 3.5, 1), 5.2, 0.35, WOOD_DARK)
	piece(model, Vector3.new(7.4, 1.6, 7.4), Comic.Red, cf * CFrame.new(0, 8.8, 1), "ball").CastShadow = true
	piece(model, Vector3.new(4.6, 1.5, 4.6), PAPER, cf * CFrame.new(0, 9.3, 1), "ball")
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		piece(model, Vector3.new(1.1, 1.1, 1.1), if k % 2 == 0 then Comic.Red else PAPER, cf * CFrame.new(math.cos(a) * 3.5, 8.3, 1 + math.sin(a) * 3.5), "ball")
	end
	roundSign(model, cf * CFrame.new(0, 6.4, 0.7), 2.8, Comic.Yellow, {
		{ text = "Carrito", size = 2, color = INK },
		{ text = "Para el camino", size = 1.2, color = Comic.Red },
	})
	buildKeeper(model, cf * CFrame.new(-0.2, 3.6, 1.3), "beetle")
	-- Imán, patas de saltamontes y bandeja del banquete, cada uno con su aviso
	for i, id in CART_ITEMS do
		local x = -2.2 + (i - 1) * 2.2
		local at = cf * CFrame.new(x, 3.8, -0.6)
		if id == "magnet" then
			for _, s in { -1, 1 } do
				rod(model, (at * CFrame.new(s * 0.35, 0.2, 0)).Position, (at * CFrame.new(s * 0.35, 1.2, 0)).Position, 0.35, Comic.Red)
				piece(model, Vector3.new(0.38, 0.3, 0.38), STONE, at * CFrame.new(s * 0.35, 1.35, 0), "ball")
			end
			piece(model, Vector3.new(1.1, 0.5, 0.45), Comic.Red, at * CFrame.new(0, 0.15, 0), "ball")
		elseif id == "speedBoost" then
			piece(model, Vector3.new(0.6, 1.3, 0.5), Comic.Green, at * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, 0.5), "ball")
			piece(model, Vector3.new(0.4, 1.1, 0.4), Comic.Green, at * CFrame.new(0.35, 0.5, 0) * CFrame.Angles(0, 0, -0.6), "ball")
		else
			piece(model, Vector3.new(0.2, 1.6, 1.6), PAPER, at * CFrame.new(0, 0.1, 0) * UPRIGHT, "cyl")
			for k, color in { Comic.Red, Comic.Yellow, Color3.fromRGB(150, 90, 50) } do
				piece(model, Vector3.new(0.55, 0.5, 0.55), color, at * CFrame.new(-0.4 + (k - 1) * 0.4, 0.45, (k % 2) * 0.2), "ball")
			end
		end
		priceTag(model, at * CFrame.new(0, 0.1, -1.1), id, 1.3)
		local def = find(id)
		addPrompt(model, at * CFrame.new(0, 0.6, -1.4), def and def.name or id, def and def.desc or "", priceText(id), function()
			activate(id)
		end)
	end
	local zones = Workspace:FindFirstChild("Zones")
	model.Parent = zones or Workspace
	return model
end

local function updateCarts()
	local depth = math.max(State.depth(), State.num("KeyDepth"))
	for id = CART_EVERY, #Config.Zones - 1, CART_EVERY do
		local zone = Config.Zones[id]
		local want = zone ~= nil and depth >= id
		local cart = carts[id]
		if want and not (cart and cart.Parent) then
			local ok, result = pcall(buildCart, zone)
			if ok then
				carts[id] = result
			else
				warn("[CRUNCH!] Carrito:", result)
			end
		elseif not want and cart then
			cart:Destroy()
			carts[id] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Tu hormiguero: buzón del paquete de inicio y pedestal de potenciadores

local homeModel: Model? = nil
local homeKey = ""
local pedestalLines: { TextLabel } = {}

local function buildHome(hill: Model, scale: number, starter: boolean)
	if homeModel then
		homeModel:Destroy()
	end
	table.clear(pedestalLines)
	local model = Instance.new("Model")
	model.Name = "StallsHome"
	local center = hill:GetPivot().Position
	local inward = (Vector3.new(0, center.Y, 0) - center) * FLAT
	inward = if inward.Magnitude > 0.01 then inward.Unit else Vector3.zAxis
	local side = inward:Cross(Vector3.yAxis)

	-- Pedestal: detrás y a un lado (lejos de la boca, la despensa, el huevo y la línea de las obreras)
	local pedestal = center + (-inward * 7 + side * 13) * scale
	local pcf = CFrame.lookAt(pedestal, pedestal + inward)
	column(model, pcf, 1, 3.2, STONE)
	column(model, pcf * CFrame.new(0, 1, 0), 3.2, 2.2, Color3.fromRGB(196, 192, 204))
	column(model, pcf * CFrame.new(0, 4.2, 0), 0.6, 3, STONE)
	piece(model, Vector3.new(2, 1.4, 2), GOLD, pcf * CFrame.new(0, 5.3, 0), "ball").Reflectance = 0.15
	local _, lines = roundSign(model, pcf * CFrame.new(0, 2.7, -1.2), 4.4, PAPER, {
		{ text = "Mis potenciadores", size = 1.5, color = Comic.Red },
		{ text = "", size = 1, color = INK, font = Comic.Body },
		{ text = "", size = 1, color = INK, font = Comic.Body },
		{ text = "", size = 1, color = INK, font = Comic.Body },
		{ text = "", size = 1, color = INK, font = Comic.Body },
	}, 0.2)
	pedestalLines = lines

	-- Buzón: al otro lado, también detrás. Solo mientras no tengas el paquete de inicio
	if not starter then
		local box = center + (-inward * 2 - side * 15) * scale
		local bcf = CFrame.lookAt(box, box + inward)
		column(model, bcf, 3.4, 0.5, WOOD_DARK)
		piece(model, Vector3.new(2, 1.8, 3), Comic.Red, bcf * CFrame.new(0, 4.1, 0), "ball").CastShadow = true
		piece(model, Vector3.new(0.2, 1.3, 1.3), INK, bcf * CFrame.new(0, 4.1, -1.4) * FACING, "cyl")
		-- Banderita levantada: hay algo dentro
		rod(model, (bcf * CFrame.new(1.05, 3.9, 0.6)).Position, (bcf * CFrame.new(1.05, 5.6, 0.6)).Position, 0.15, INK)
		piece(model, Vector3.new(0.15, 0.7, 1), Comic.Yellow, bcf * CFrame.new(1.05, 5.3, 0.15), "ball")
		-- Un paquete asomando
		piece(model, Vector3.new(1, 0.8, 0.9), Color3.fromRGB(214, 176, 120), bcf * CFrame.new(0, 4.5, -1.5), "ball")
		priceTag(model, bcf * CFrame.new(0, 2.3, -0.5), "starterPack", 1.5)
		addPrompt(model, bcf * CFrame.new(0, 3.2, -1.4), "Paquete de inicio", "Una sola vez: comida, poción, jalea y un huevo dorado", priceText("starterPack"), function()
			activate("starterPack")
		end)
	end
	model.Parent = hill
	homeModel = model
end

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function updateHome()
	local hill = State.hill()
	if not hill then
		if homeModel then
			homeModel:Destroy()
			homeModel = nil
		end
		homeKey = ""
		return
	end
	local scale = hill:GetAttribute("Scale") or 1
	local starter = State.flag("P_starterPack")
	local key = hill.Name .. "|" .. tostring(scale) .. "|" .. tostring(starter)
	if key ~= homeKey or not (homeModel and homeModel.Parent) then
		homeKey = key
		buildHome(hill, scale, starter)
	end
	if #pedestalLines < 5 then
		return
	end
	local t = State.now()
	local active = {}
	local buff = State.num("BuffUntil") - t
	if buff > 0 then
		table.insert(active, "Comida x2 · " .. clock(buff))
	end
	local speed = State.num("SpeedUntil") - t
	if speed > 0 then
		table.insert(active, "Patas +40 % · " .. clock(speed))
	end
	local magnet = State.num("MagnetUntil") - t
	if magnet > 0 then
		table.insert(active, "Imán · " .. clock(magnet))
	end
	local keyLeft = State.num("KeyUntil") - t
	local keyZone = Config.Zones[State.num("KeyDepth")]
	if keyLeft > 0 and keyZone then
		table.insert(active, "Llave " .. keyZone.name .. " · " .. clock(keyLeft))
	end
	if State.num("JellyBoost") > 0 then
		table.insert(active, "Jalea x2 al enjambrar")
	end
	if State.num("HalfDig") > 0 then
		table.insert(active, "Pala dorada: capa a mitad")
	end
	if #active == 0 then
		table.insert(active, "Ninguno ahora")
	end
	for i = 2, 5 do
		pedestalLines[i].Text = active[i - 1] or ""
	end
end

---------------------------------------------------------------------------------------------------
-- Llave maestra: aviso al quedar un minuto y, si se acaba contigo dentro, de vuelta a la puerta

local lastKeyDepth = 0
local keyWarned = false

local function watchKey()
	local keyDepth = State.num("KeyDepth")
	local left = State.num("KeyUntil") - State.now()
	if keyDepth > 0 and left > 0 and left <= 60 and not keyWarned then
		keyWarned = true
		Bubble.flash("A la llave le queda un minuto", 4)
	end
	if keyDepth ~= lastKeyDepth then
		if lastKeyDepth > 0 and keyDepth == 0 and State.depth() < lastKeyDepth then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local gate = gatePivot(lastKeyDepth)
			if root and root:IsA("BasePart") and gate and root.Position.Z < gate.Z - 1 then
				character:PivotTo(CFrame.lookAt(Vector3.new(0, GROUND + 3, gate.Z + 14), Vector3.new(0, GROUND + 3, gate.Z + 30)))
				Bubble.flash("Se acabó la llave: vuelvo a la puerta", 4)
			end
		end
		keyWarned = false
		lastKeyDepth = keyDepth
	end
end

---------------------------------------------------------------------------------------------------
-- Celebraciones

local bannerGui: ScreenGui? = nil

local function banner(text: string, color: Color3)
	if not bannerGui then
		local gui = Instance.new("ScreenGui")
		gui.Name = "StallBanner"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 18
		gui.Parent = player:WaitForChild("PlayerGui")
		bannerGui = gui
	end
	local gui = bannerGui :: ScreenGui
	local holder, face = Comic.box(gui, UDim2.fromOffset(620, 64), color, 6)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, -90)
	holder.Rotation = -1
	Comic.autoScale(holder, 900)
	local label = Comic.label(face, text, Comic.Display, 30, INK)
	label.Size = UDim2.new(1, -24, 1, -8)
	label.Position = UDim2.fromOffset(12, 4)
	label.TextScaled = true
	TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 96) }):Play()
	task.delay(6, function()
		local out = TweenService:Create(holder, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -90) })
		out:Play()
		out.Completed:Wait()
		holder:Destroy()
	end)
end

local CONFETTI = { Comic.Yellow, Comic.Red, Comic.Cyan, Comic.Green, PAPER }

local function myPosition(): Vector3?
	local character = player.Character
	return character and character:GetPivot().Position + Vector3.new(0, 3, 0) or nil
end

local function onBought(buyerId: number, id: string, recipientId: number, kind: string)
	local def = find(id)
	if not def then
		return
	end
	local buyer = Players:GetPlayerByUserId(buyerId)
	local name = if buyer then buyer.DisplayName else "Alguien"
	local mine = buyerId == player.UserId
	local forMe = recipientId == player.UserId

	if def.wide then
		if id == "feast" then
			banner("¡" .. name .. " ha invitado a un banquete! Comida x2 para todas, 5 minutos", Comic.Yellow)
		else
			banner("¡" .. name .. " ha traído una lluvia dorada! Busca la comida dorada", GOLD)
		end
		local pos = myPosition()
		if pos and not mine then
			Fx.confetti(pos + Vector3.new(0, 6, 0), CONFETTI, 24, 0.8)
			Sfx.pop(1.3)
		end
	end
	local pos = myPosition()
	if not pos then
		return
	end
	if mine then
		-- Proporcional: un pase o algo para todas, a lo grande; un frasco, una fiesta pequeña
		local big = kind == "pass" or def.wide == true or (def.robux or 0) >= 99
		Fx.confetti(pos, CONFETTI, if big then 70 else 30, if big then 1.3 else 1)
		Fx.burst(pos, "¡" .. def.name .. "!", Comic.Yellow, if big then 330 else 250)
		if big then
			Fx.ring(pos - Vector3.new(0, 2.5, 0), 9, Comic.Yellow, 0.5)
			Fx.speed(1)
		end
		Sfx.fanfare()
		if def.gift and recipientId ~= buyerId then
			local recipient = Players:GetPlayerByUserId(recipientId)
			Bubble.flash("¡Regalo enviado a " .. (if recipient then recipient.DisplayName else "ella") .. "!", 4)
		end
	elseif forMe then
		Fx.confetti(pos, CONFETTI, 40, 1.1)
		Fx.burst(pos, "¡Regalo de " .. name .. "!", Comic.Cyan, 280)
		Sfx.fanfare()
	end
end

---------------------------------------------------------------------------------------------------

local function updateTags()
	for i = #tags, 1, -1 do
		local tag = tags[i]
		if not tag.label.Parent then
			table.remove(tags, i)
		else
			tag.label.Text = priceText(tag.id)
		end
	end
end

local function updateMarketSign()
	local label = marketSignLabel
	if not label or not label.Parent then
		return
	end
	local t = State.now()
	local rain = Workspace:GetAttribute("GoldRainUntil")
	local feast = Workspace:GetAttribute("FeastUntil")
	if type(rain) == "number" and rain > t then
		label.Text = "Lluvia dorada de " .. tostring(Workspace:GetAttribute("GoldRainBy") or "")
	elseif type(feast) == "number" and feast > t then
		label.Text = "Banquete de " .. tostring(Workspace:GetAttribute("FeastBy") or "")
	else
		label.Text = "Abierto"
	end
end

local function step(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn("[CRUNCH!] Puestos (" .. name .. "):", err)
	end
end

function Stalls.start(remotes: Folder)
	remote = remotes:WaitForChild("Stalls", 30) :: RemoteEvent?
	if remote then
		remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
			if kind == "Bought" and type(a) == "number" and type(b) == "string" then
				step("celebración", function()
					onBought(a, b, tonumber(c) or a, tostring(d))
				end)
			end
		end)
	end

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom and prompt:GetAttribute("Stall") then
			step("aviso", function()
				promptCard(prompt, inputType)
			end)
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		if counterGui and input.KeyCode == Enum.KeyCode.Escape then
			closeCounter()
		end
	end)

	-- El mercadillo: donde diga el servidor
	local function market()
		local spot = Workspace:GetAttribute("StallMarket")
		local look = Workspace:GetAttribute("StallMarketLook")
		if typeof(spot) == "Vector3" and typeof(look) == "Vector3" then
			step("mercadillo", function()
				buildMarket(spot, look)
			end)
		end
	end
	Workspace:GetAttributeChangedSignal("StallMarket"):Connect(market)
	task.spawn(function()
		-- Las piezas del jardín (Props) llegan con el mundo
		Workspace:WaitForChild("Props", 60)
		market()
	end)

	-- Bichos tenderos: solo se mueven los que están cerca de la cámara
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local t = os.clock()
		local eye = camera.CFrame.Position
		for i = #keepers, 1, -1 do
			local keeper = keepers[i]
			if not keeper.model.Parent then
				table.remove(keepers, i)
			elseif (keeper.base.Position - eye).Magnitude < 140 then
				local p = keeper.phase
				keeper.model:PivotTo(keeper.base
					* CFrame.new(0, math.abs(math.sin(t * 3 + p)) * 0.25, 0)
					* CFrame.Angles(0, math.sin(t * 1.3 + p) * 0.3, math.sin(t * 2 + p) * 0.06))
			end
		end
	end)

	task.spawn(function()
		while true do
			if State.flag("Loaded") then
				step("excavadora", updateDig)
				step("carritos", updateCarts)
				step("hormiguero", updateHome)
				step("llave", watchKey)
				step("precios", updateTags)
				step("cartel", updateMarketSign)
			end
			task.wait(0.5)
		end
	end)
end

return Stalls
