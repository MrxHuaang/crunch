-- Tienda de Robux: el puesto de mercado del hormiguero. Bajo un toldo de rayas, estantes por tipo:
-- arriba lo que es para siempre (los pases, cosas grandes con su cartel), debajo lo que se gasta
-- (frascos, tarros, sacos y herramientas) y cualquier grupo nuevo que aparezca en shared/Config.
-- Cada artículo es un objeto dibujado con formas, con el precio en una etiqueta de cartón colgando.
-- Al tocarlo, a su lado se clava una ficha con lo que hace en TUS números ("tu colonia: 1.2K/s →
-- 2.4K/s") y el botón de compra. Lo que ya es tuyo lleva el sello "Tuyo" y su efecto a la vista.
-- Sin relojes ni ofertas que metan prisa: precios claros y frases honestas (juegan menores).
--
-- Los artículos salen de Config.Passes y Config.Products tal cual: se agrupan por su campo `group`
-- si lo tienen (y Config.StoreGroups, si existe, les pone nombre y orden); si no, se deduce. En un
-- juego publicado solo aparece lo que tiene id; en Studio se ve todo con una nota "sin id".
--
-- Store.open(section?) abre el puesto (en un estante concreto si se pide) y Store.focus(id) abre
-- la ficha de un artículo y lo señala.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Outfits = require(ReplicatedStorage.Shared.Outfits)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Trails = require(ReplicatedStorage.Shared.Trails)
local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Store = {}

local player = Players.LocalPlayer
local IS_STUDIO = RunService:IsStudio()

-- Medidas de diseño (Hud.fitScale las adapta; el alto se ajusta a la pantalla)
local STALL_W = 640
local SHEET_W = 320
local GAP = 18
local TOTAL_W = STALL_W + GAP + SHEET_W
local H = 660
local MARGIN = 16
local AWNING = 92
local COUNTER = 58
local POST = 18
local INNER_W = STALL_W - POST * 2 - 16
local TAP = 48

local STRIPE = Color3.fromRGB(214, 56, 66)
local WALL = Color3.fromRGB(222, 182, 132)
local WALL_LINE = Color3.fromRGB(200, 158, 108)
local WOOD = Color3.fromRGB(150, 100, 58)
local WOOD_DARK = Color3.fromRGB(112, 72, 46)
local CARD = Color3.fromRGB(226, 196, 150)
local SHUTTER = Color3.fromRGB(176, 180, 190)
local SHUTTER_RIB = Color3.fromRGB(146, 150, 162)
local GOLD = Color3.fromRGB(255, 200, 60)
local DIM = Color3.fromRGB(214, 206, 190)
local OWNED = Color3.fromRGB(70, 160, 80)

-- Estantes que no dicen su nombre en Config: nombre y orden por defecto
local GROUP_NAMES = { siempre = "Para siempre", frascos = "Frascos y tarros", sacos = "De un uso" }

local gui: ScreenGui
local panel: Frame
local fit: UIScale
local stall: Frame
local shelves: ScrollingFrame
local shutter: Frame
local sheet: Frame
local compact = false
local isOpen = false
local closing = 0

local items = {} -- artículos dibujados: { def, kind, group, holder, base, tag, stamp, label, scale, halo }
local groupTops: { [string]: number } = {}
local groupOrder: { string } = {}
local selected: any = nil
local prices: { [number]: number } = {}

local sheetParts = {} :: any

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

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

local function visible(id: number?): boolean
	return IS_STUDIO or (id or 0) > 0
end

local function idOf(entry): number
	return if entry.kind == "pass" then (entry.def.passId or 0) else (entry.def.productId or 0)
end

function Store.enabled(): boolean
	if IS_STUDIO then
		return true
	end
	for _, pass in Config.Passes do
		if (pass.passId or 0) > 0 then
			return true
		end
	end
	for _, product in Config.Products do
		if (product.productId or 0) > 0 then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Catálogo: lo que hay en Config, agrupado
-------------------------------------------------------------------------------

local function groupName(key: string): string
	local custom = (Config :: any).StoreGroups
	if type(custom) == "table" then
		local entry = custom[key]
		if type(entry) == "string" then
			return entry
		elseif type(entry) == "table" and type(entry.name) == "string" then
			return entry.name
		end
		for _, item in custom do
			if type(item) == "table" and item.id == key and type(item.name) == "string" then
				return item.name
			end
		end
	end
	if GROUP_NAMES[key] then
		return GROUP_NAMES[key]
	end
	return (key:sub(1, 1):upper() .. key:sub(2))
end

local function textOf(def): string
	return (tostring(def.id) .. " " .. tostring(def.name)):lower()
end

local function has(text: string, words: { string }): boolean
	for _, word in words do
		if text:find(word, 1, true) then
			return true
		end
	end
	return false
end

local function groupOf(def, kind: string): string
	if type(def.group) == "string" and def.group ~= "" then
		return def.group
	end
	if kind == "pass" then
		return "siempre"
	end
	if has(textOf(def), { "jar", "tarro", "barril", "barrel", "poci", "potion", "frasco" }) then
		return "frascos"
	end
	return "sacos"
end

-- Lista ordenada: pases primero, luego productos; los grupos salen en el orden en que aparecen
-- (o en el de Config.StoreGroups si es una lista)
local function catalog()
	local byGroup: { [string]: { any } } = {}
	local order: { string } = {}
	local function add(def, kind: string)
		local id = if kind == "pass" then def.passId else def.productId
		if not visible(id) then
			return
		end
		local group = groupOf(def, kind)
		if not byGroup[group] then
			byGroup[group] = {}
			table.insert(order, group)
		end
		table.insert(byGroup[group], { def = def, kind = kind, group = group })
	end
	for _, def in Config.Passes do
		add(def, "pass")
	end
	for _, def in Config.Products do
		add(def, "product")
	end
	local custom = (Config :: any).StoreGroups
	if type(custom) == "table" and #custom > 0 then
		local rank = {}
		for i, key in order do
			rank[key] = 1000 + i -- los que no estén en la lista, detrás y en su orden
		end
		for i, item in custom do
			local key = if type(item) == "table" then item.id else item
			if type(key) == "string" and rank[key] then
				rank[key] = i
			end
		end
		table.sort(order, function(a, b)
			return rank[a] < rank[b]
		end)
	end
	return byGroup, order
end

local function owned(entry): boolean
	return entry.kind == "pass" and State.flag("P_" .. entry.def.id)
end

-------------------------------------------------------------------------------
-- Objetos dibujados: cada artículo se reconoce por su forma
-------------------------------------------------------------------------------

-- Dibuja en un cuadro de 100 x 90 unidades escalado a `scale`
local function painter(parent: Instance, scale: number)
	return function(color: Color3?, x: number, y: number, w: number, h: number, rot: number?, radius: number?, inkWidth: number?): Frame
		local r = if radius and radius >= 0 then radius * scale else radius
		local ink = if inkWidth then math.max(1.5, inkWidth * math.min(scale, 1.2)) else nil
		return blob(parent, color, x * scale, y * scale, w * scale, h * scale, rot, r, ink)
	end
end

local function sticker(parent: Instance, text: string, x: number, y: number, size: number, scale: number, color: Color3)
	local label = Comic.label(parent, text, Comic.Display, size * scale, color)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(x * scale, y * scale)
	label.Size = UDim2.fromOffset(60 * scale, size * scale * 1.1)
	label.Rotation = -8
	Comic.ink(label, math.max(2, 3 * scale))
	return label
end

local SHAPES = {}

SHAPES.plate2 = function(p, s, parent)
	p(Comic.Paper, 50, 76, 90, 20, 0, -1, 3)
	p(Comic.Crumb, 40, 52, 50, 46, 0, -1, 3)
	p(Comic.Crumb, 60, 40, 48, 44, 0, -1, 3)
	for _, spot in { { 32, 50 }, { 46, 60 }, { 56, 34 }, { 68, 44 }, { 60, 50 } } do
		p(Comic.DirtDark, spot[1], spot[2], 7, 7, 0, -1)
	end
	sticker(parent, "x2", 82, 24, 26, s, Comic.Yellow)
end

SHAPES.jaw = function(p, s)
	p(GOLD, 86, 44, 8, 26, 0, 3, 2)
	p(GOLD, 92, 44, 16, 8, 0, 3, 2)
	p(Comic.Red, 46, 30, 70, 26, -8, 12, 3)
	p(Comic.Red, 46, 62, 70, 26, 8, 12, 3)
	for k = 0, 3 do
		p(Comic.Paper, 22 + k * 14, 44, 9, 9, 45, nil, 2)
	end
end

SHAPES.colony = function(p, s)
	for k = 0, 2 do
		p(Comic.Ink, 12, 40 + k * 12, 18 - k * 3, 4)
	end
	p(Comic.Dirt, 58, 70, 78, 60, 0, -1, 3)
	p(Comic.Ink, 58, 56, 14, 10, 0, -1)
	p(Comic.Green, 58, 84, 96, 10, 0, 3, 2)
end

SHAPES.wings = function(p, s)
	p(GOLD, 30, 40, 38, 62, -28, -1, 3)
	p(GOLD, 70, 40, 38, 62, 28, -1, 3)
	p(Color3.fromRGB(255, 240, 170), 30, 36, 14, 30, -28, -1)
	p(Color3.fromRGB(255, 240, 170), 70, 36, 14, 30, 28, -1)
	p(Comic.Red, 50, 54, 14, 30, 0, -1, 3)
end

SHAPES.star = function(p, s, parent)
	p(Comic.Red, 38, 76, 14, 34, 20, nil, 2)
	p(Comic.Red, 62, 76, 14, 34, -20, nil, 2)
	p(GOLD, 50, 40, 60, 60, 0, 6, 3)
	p(GOLD, 50, 40, 60, 60, 45, 6, 3)
	local label = sticker(parent, "VIP", 50, 40, 24, s, Comic.Paper)
	label.Rotation = 0
end

SHAPES.jelly2 = function(p, s, parent)
	p(Color3.fromRGB(255, 190, 60), 46, 56, 56, 58, 0, 12, 3)
	p(Color3.fromRGB(255, 230, 150), 36, 50, 10, 24, 0, -1)
	p(Comic.Red, 46, 24, 62, 14, 0, 4, 3)
	sticker(parent, "x2", 82, 30, 26, s, Comic.Yellow)
end

SHAPES.shoe = function(p, s)
	for k = 0, 2 do
		p(Comic.Ink, 10, 40 + k * 10, 14, 4)
	end
	p(Comic.Red, 50, 52, 64, 32, 0, 14, 3)
	p(Comic.Red, 72, 60, 34, 22, 0, -1, 3)
	p(Comic.Paper, 54, 74, 84, 12, 0, 5, 3)
	for k = 0, 2 do
		p(Comic.Paper, 42 + k * 9, 44, 4, 14, 30)
	end
end

SHAPES.pantry = function(p, s)
	p(WOOD, 50, 58, 80, 56, 0, 4, 3)
	p(WOOD_DARK, 50, 50, 80, 4)
	p(WOOD_DARK, 50, 66, 80, 4)
	for k = 0, 4 do
		p(Comic.Crumb, 22 + k * 14, 30 - (k % 2) * 6, 18, 16, k * 30, -1, 2)
	end
end

SHAPES.potion = function(p, s, parent)
	p(Color3.fromRGB(200, 120, 230), 50, 58, 56, 56, 0, -1, 3)
	p(Color3.fromRGB(230, 200, 255), 50, 26, 18, 24, 0, 3, 3)
	p(Comic.Crumb, 50, 12, 22, 10, 0, 3, 2)
	p(Color3.new(1, 1, 1), 38, 50, 10, 10, 0, -1)
	p(Color3.new(1, 1, 1), 58, 66, 6, 6, 0, -1)
	sticker(parent, "x2", 84, 34, 24, s, Comic.Yellow)
end

SHAPES.sack = function(p, s)
	p(Comic.DirtLight, 50, 58, 66, 60, 0, 26, 3)
	p(Comic.DirtLight, 50, 18, 36, 16, 0, 6, 3)
	p(Comic.Crumb, 50, 28, 32, 8, 0, 3, 2)
	p(Comic.Crumb, 86, 80, 12, 10, 20, -1, 2)
	p(Comic.Crumb, 74, 84, 9, 8, 0, -1, 2)
end

SHAPES.cart = function(p, s)
	p(Comic.Ink, 18, 62, 34, 5, 25)
	p(Comic.Crumb, 46, 30, 60, 24, 0, -1, 2)
	p(Comic.Red, 48, 48, 74, 30, -6, 6, 3)
	p(Comic.Ink, 72, 72, 26, 26, 0, -1)
	p(Color3.fromRGB(170, 170, 180), 72, 72, 10, 10, 0, -1)
end

SHAPES.shovel = function(p, s)
	p(WOOD, 60, 34, 9, 64, 35, 3, 2)
	p(WOOD_DARK, 80, 8, 20, 9, 35, 3, 2)
	p(GOLD, 36, 68, 32, 36, 35, 10, 3)
end

SHAPES.bolt = function(p, s)
	p(Comic.Yellow, 58, 22, 18, 40, 25, nil, 3)
	p(Comic.Yellow, 46, 46, 38, 14, -10, nil, 3)
	p(Comic.Yellow, 40, 68, 18, 40, 25, nil, 3)
end

SHAPES.egg = function(p, s)
	p(GOLD, 50, 48, 56, 70, 0, -1, 3)
	p(Color3.fromRGB(255, 240, 170), 40, 36, 12, 18, -20, -1)
	p(Comic.Paper, 82, 20, 10, 10, 45)
	p(Comic.Paper, 18, 70, 7, 7, 45)
end

SHAPES.jar = function(p, s)
	p(Color3.fromRGB(255, 170, 40), 50, 58, 48, 50, 0, 10, 3)
	p(Comic.Paper, 50, 60, 48, 14, 0, nil, 0)
	p(Comic.Red, 50, 28, 54, 12, 0, 4, 3)
end

SHAPES.barrel = function(p, s)
	p(WOOD, 50, 50, 64, 74, 0, 18, 3)
	p(WOOD_DARK, 50, 26, 66, 6)
	p(WOOD_DARK, 50, 74, 66, 6)
	p(Color3.fromRGB(255, 180, 50), 50, 14, 44, 12, 0, -1, 2)
	p(Color3.fromRGB(255, 180, 50), 62, 30, 8, 18, 0, 4)
end

SHAPES.parcel = function(p, s)
	p(Comic.Crumb, 50, 54, 72, 58, 0, 4, 3)
	p(Comic.Red, 50, 54, 8, 58)
	p(Comic.Red, 50, 54, 72, 8)
	p(Comic.Red, 42, 22, 18, 12, 20, -1, 2)
	p(Comic.Red, 58, 22, 18, 12, -20, -1, 2)
end

SHAPES.backpack = function(p, s)
	p(Comic.Crumb, 42, 20, 16, 14, 0, -1, 2)
	p(Comic.Crumb, 58, 18, 14, 12, 20, -1, 2)
	p(Color3.fromRGB(96, 170, 90), 50, 54, 58, 64, 0, 14, 3)
	p(Color3.fromRGB(70, 136, 70), 50, 68, 36, 24, 0, 6, 2)
	p(WOOD_DARK, 36, 30, 8, 18, 0, 3, 2)
	p(WOOD_DARK, 64, 30, 8, 18, 0, 3, 2)
end

SHAPES.digger = function(p, s)
	p(Color3.fromRGB(150, 150, 160), 84, 64, 20, 18, 20, 3, 3)
	p(Comic.Yellow, 70, 42, 9, 44, 40, 3, 3)
	p(Comic.Ink, 44, 78, 72, 16, 0, -1)
	p(Comic.Yellow, 40, 54, 42, 30, 0, 4, 3)
	p(Comic.Cyan, 46, 48, 16, 12, 0, 2, 2)
end

SHAPES.key = function(p, s)
	p(GOLD, 62, 40, 52, 10, 0, 3, 3)
	p(GOLD, 76, 52, 8, 16, 0, nil, 2)
	p(GOLD, 88, 52, 8, 12, 0, nil, 2)
	p(GOLD, 28, 40, 36, 36, 0, -1, 3)
	p(Comic.Ink, 28, 40, 12, 12, 0, -1)
end

SHAPES.magnet = function(p, s)
	p(Comic.Red, 50, 70, 50, 28, 0, 14, 3)
	p(Comic.Red, 32, 46, 14, 40, 0, nil, 3)
	p(Comic.Red, 68, 46, 14, 40, 0, nil, 3)
	p(Color3.fromRGB(210, 214, 222), 32, 22, 14, 12, 0, nil, 3)
	p(Color3.fromRGB(210, 214, 222), 68, 22, 14, 12, 0, nil, 3)
	p(Comic.Crumb, 50, 16, 10, 10, 0, -1, 2)
end

SHAPES.feast = function(p, s)
	p(Comic.Paper, 50, 76, 92, 20, 0, -1, 3)
	p(Comic.Crumb, 32, 58, 30, 26, 0, -1, 3)
	p(Comic.Red, 62, 56, 30, 28, 0, -1, 3)
	p(Comic.Green, 66, 40, 10, 6, -30, -1, 2)
	p(Comic.Yellow, 48, 42, 22, 22, 45, nil, 3)
end

SHAPES.rain = function(p, s)
	for _, drop in { { 34, 62 }, { 54, 72 }, { 72, 58 }, { 44, 84 } } do
		p(GOLD, drop[1], drop[2], 10, 14, 0, -1, 2)
	end
	p(Comic.Paper, 36, 30, 30, 28, 0, -1, 3)
	p(Comic.Paper, 72, 32, 26, 24, 0, -1, 3)
	p(Comic.Paper, 56, 24, 36, 34, 0, -1, 3)
	p(Comic.Paper, 54, 38, 60, 16, 0, 8)
end

SHAPES.goldhill = function(p, s)
	p(Comic.Ink, 50, 34, 3, 26)
	p(Comic.Red, 58, 26, 16, 10, 0, nil, 2)
	p(GOLD, 50, 72, 80, 50, 0, -1, 3)
	p(Comic.Ink, 50, 62, 14, 10, 0, -1)
	p(Color3.fromRGB(255, 240, 170), 34, 64, 10, 6, -20, -1)
end

-- Lazo de regalo encima de lo que sea
local function giftBow(p)
	p(Comic.Red, 80, 12, 16, 11, 25, -1, 2)
	p(Comic.Red, 94, 12, 16, 11, -25, -1, 2)
	p(Comic.Red, 87, 13, 8, 8, 0, -1, 2)
end

local SHAPE_BY_ID = {
	x2Food = "plate2", autoBite = "jaw", fastColony = "colony", goldWings = "wings", vip = "star",
	x2Jelly = "jelly2", turbo = "shoe", bigStore = "pantry", bigCarry = "backpack", starterPack = "parcel",
	goldHill = "goldhill", halfDig = "shovel", zoneKey = "key", sack = "sack", crate = "pantry",
	bigSack = "cart", frenzy = "bolt", egg = "egg", potion = "potion", bigPotion = "potion",
	speedBoost = "shoe", magnet = "magnet", jellyBoost = "jelly2", jar = "jar", bigJar = "barrel",
	feast = "feast", goldRain = "rain", giftPotion = "potion", giftSack = "sack", shovel = "shovel",
}
-- Para lo que añadan después: se deduce por palabras de su id o su nombre
local SHAPE_WORDS = {
	{ "digger", { "excav", "digger" } },
	{ "key", { "llave", "key" } },
	{ "magnet", { "imán", "iman", "magnet" } },
	{ "backpack", { "mochila", "carry" } },
	{ "rain", { "lluvia", "rain" } },
	{ "feast", { "banquete", "feast" } },
	{ "pantry", { "caja", "crate", "despensa" } },
	{ "potion", { "poci", "potion", "frasco" } },
	{ "barrel", { "barril", "barrel" } },
	{ "jar", { "tarro", "jar", "miel" } },
	{ "cart", { "carretilla", "cart" } },
	{ "sack", { "saco", "sack", "bolsa" } },
	{ "egg", { "huevo", "egg" } },
	{ "shovel", { "pala", "shovel" } },
	{ "bolt", { "frenes", "frenzy", "rayo" } },
	{ "wings", { "ala", "wing" } },
	{ "shoe", { "pata", "turbo", "veloc" } },
	{ "star", { "vip", "estrella", "star" } },
	{ "jelly2", { "jalea", "jelly" } },
	{ "plate2", { "comida", "food" } },
	{ "colony", { "colonia", "obrera", "colony" } },
}

local function shapeOf(def): string
	if type(def.shape) == "string" and SHAPES[def.shape] then
		return def.shape
	end
	local known = SHAPE_BY_ID[def.id]
	if known then
		return known
	end
	if type(def.layers) == "table" then
		return "digger"
	end
	local text = textOf(def)
	for _, entry in SHAPE_WORDS do
		if has(text, entry[2]) then
			return entry[1]
		end
	end
	return "parcel"
end

-- El objeto de un artículo en un cuadro de size x size*0.9
local function drawObject(parent: Instance, def, size: number): Frame
	local box = Comic.frame(parent)
	box.Size = UDim2.fromOffset(size, size * 0.9)
	local s = size / 100
	local p = painter(box, s)
	SHAPES[shapeOf(def)](p, s, box)
	if def.gift then
		giftBow(p)
	end
	return box
end

-- Las piezas del dibujo nacen con ZIndex 1: se igualan al del cuadro para que nunca queden
-- debajo del fondo del puesto o del papel de la ficha (pase lo que pase con ZIndexBehavior).
local function lift(box: GuiObject, z: number)
	box.ZIndex = z
	for _, piece in box:GetDescendants() do
		if piece:IsA("GuiObject") then
			piece.ZIndex = z
		end
	end
end

-------------------------------------------------------------------------------
-- Tus números: qué hace cada cosa en tu partida
-------------------------------------------------------------------------------

local function perSec(n: number): string
	if n < 10 then
		local text = string.format("%.1f", n):gsub("%.0$", "")
		return text .. "/s"
	end
	return Format.short(n) .. "/s"
end

local function minutes(seconds: number): string
	return math.max(1, math.floor(seconds / 60 + 0.5)) .. " min"
end

local function rate(): number
	return math.max(0, State.num("Rate"))
end

-- Multiplicador de comida como lo calcula el servidor (sin castas)
local function foodMult(): number
	local m = State.stats().foodMult or 1
	if State.flag("P_x2Food") then
		m *= 2
	end
	if State.flag("P_vip") then
		m *= 1.25
	end
	return m * (1 + Config.Trophy.Bonus * State.num("Trophies"))
end

-- Lo que da un saco: lo mismo que cuenta el servidor (Monetize), redondeado
local function sackGain(seconds: number, floor: number): number
	local depth = math.clamp(State.depth(), 1, #Config.Zones)
	local zoneFood = Config.Foods[(depth - 1) * 3 + 1]
	local bite = State.stats().biteDamage or 1
	-- Rate ya trae el multiplicador de comida (es lo acreditado); el mínimo no, como en el servidor
	return math.max(rate() * seconds, floor * bite * (zoneFood and zoneFood.value or 1) * foodMult())
end

local function colonyRow(mult: number)
	local r = rate()
	if r <= 0 then
		return { "Tu colonia", "aún no trae comida" }
	end
	return { "Tu colonia gana", perSec(r) .. " → " .. perSec(r * mult) }
end

-- Prendas del vestidor que vienen con un pase (sus nombres, tal cual están en Shared)
local function passItems(pass: string): string
	local names = {}
	for _, def in Trails.list do
		if def.pass == pass then
			table.insert(names, def.name)
		end
	end
	for _, def in Outfits.list do
		if def.pass == pass then
			table.insert(names, def.name)
		end
	end
	return if #names > 0 then table.concat(names, " y ") else "nada"
end

-- Las cantidades son las mismas que entrega src/server/Monetize.luau (si cambian allí, cambian aquí).
-- Cada efecto devuelve filas { etiqueta, valor }, la frase corta de "activo" para el estante y, si
-- ahora mismo no te sirve, por qué (entonces no se ofrece comprarlo).
local function remaining(attribute: string): number
	local untilTime = player:GetAttribute(attribute)
	return if type(untilTime) == "number" then math.max(0, untilTime - State.now()) else 0
end

local function walkSpeed(): number
	return player:GetAttribute("WalkSpeed") or State.stats().walkSpeed or 16
end

local function tenth(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

local function doubleFood(seconds: number)
	local left = remaining("PaidFoodUntil")
	if left > 0 then
		return { { "Comida x2", "te quedan " .. minutes(left) .. " → " .. minutes(left + seconds) } }
	end
	return { { "Comida x2", "durante " .. minutes(seconds) }, { "Si ya tienes una", "se suma el tiempo" } }
end

local function colonyTime(seconds: number, floor: number, label: string)
	return { { "Te da", "≈ " .. Format.short(sackGain(seconds, floor)) .. " de comida" }, { "Es lo que trae tu colonia en", label } }
end

local function jellyRows(amount: number)
	local jelly = State.num("Jelly")
	return { { "Tu jalea real", Format.short(jelly) .. " → " .. Format.short(jelly + amount) } }
end

local EFFECTS = {
	x2Food = function(mine)
		if mine then
			return { { "Activo", "toda tu comida vale el doble" }, { "Tu colonia gana", perSec(rate()) } }, "x2 comida"
		end
		return { colonyRow(2), { "Cada mordisco y entrega", "vale el doble" } }, "x2 comida"
	end,
	fastColony = function(mine)
		if mine then
			return { { "Activo", "obreras al doble" }, { "Tu colonia gana", perSec(rate()) } }, "colonia x2"
		end
		return { colonyRow(2), { "Tus obreras", "trabajan al doble" } }, "colonia x2"
	end,
	vip = function(mine)
		local rows = { if mine then { "Tu colonia gana", perSec(rate()) .. " (con +25 %)" } else colonyRow(1.25) }
		table.insert(rows, { "En el vestidor", passItems("vip") })
		table.insert(rows, { "Tu cartel", "con estrella" })
		return rows, "+25 % comida"
	end,
	autoBite = function(mine)
		return { { if mine then "Activo" else "Con el pase", "muerdes sola con comida a tiro" } }, "muerde sola"
	end,
	goldWings = function(mine)
		local cooldown = player:GetAttribute("WingsCooldown") or Config.Wings.Cooldown
		if mine then
			return { { "Activo", "alas siempre" }, { "Espera entre vuelos", cooldown .. " s" } }, "alas doradas"
		end
		return {
			{ "Alas", if State.flag("HasWings") then "ya las tienes" else "desde ahora" },
			{ "Espera entre vuelos", cooldown .. " s → 4 s" },
		}, "alas doradas"
	end,
	x2Jelly = function(mine)
		local jelly = math.floor(State.jellyNow())
		if mine then
			return { { "Si enjambras ahora", jelly .. " de jalea (ya doble)" } }, "x2 jalea"
		end
		if jelly >= 1 then
			return { { "Si enjambras ahora", jelly .. " → " .. jelly * 2 .. " de jalea" } }, "x2 jalea"
		end
		return { { "Cada enjambre", "el doble de jalea" } }, "x2 jalea"
	end,
	turbo = function(mine)
		local walk = walkSpeed()
		if mine then
			return { { "Tu velocidad", tenth(walk) .. " (con +30 %)" } }, "+30 % velocidad"
		end
		return { { "Tu velocidad", tenth(walk) .. " → " .. tenth(walk * 1.3) } }, "+30 % velocidad"
	end,
	bigStore = function(mine)
		if mine then
			return { { "Sin ti, tu colonia", "trabaja 24 h al 100 %" } }, "24 h al 100 %"
		end
		local hours = State.stats().offlineHours or 0
		local before = if hours > 0 then tenth(hours) .. " h al " .. math.floor(Config.Offline.Efficiency * 100) .. " %" else "nada"
		return { { "Sin ti, tu colonia trabaja", before .. " → 24 h al 100 %" } }, "24 h al 100 %"
	end,
	bigCarry = function(mine)
		local capacity = State.stats().capacity or 0
		if mine then
			return { { "Cargas por viaje", Format.short(capacity) .. " (con +50 %)" } }, "+50 % carga"
		end
		return { { "Cargas por viaje", Format.short(capacity) .. " → " .. Format.short(math.floor(capacity * 1.5)) } }, "+50 % carga"
	end,
	starterPack = function(mine)
		if mine then
			return { { "Ya entregado", "es una sola vez por cuenta" } }, "entregado"
		end
		return {
			{ "Comida de golpe", "≈ " .. Format.short(sackGain(1800, 600)) .. " (30 min de colonia)" },
			{ "Comida x2", "30 min" },
			{ "Jalea real", "+10, y un huevo dorado" },
		}, "entregado"
	end,
	goldHill = function(mine)
		return { { "Tu hormiguero", "con adornos de oro" }, { "En el vestidor", passItems("goldHill") }, { "Comida", "no da: es solo aspecto" } }, "oro en tu hormiguero"
	end,
	halfDig = function()
		local depth = State.depth()
		if depth >= Stats.MaxDepth then
			return { { "Ya no quedan capas", "no te sirve" } }, nil, "Ya tienes todas las capas"
		end
		local cost = Stats.digCost(depth)
		local rows = { { "Tu próxima capa cuesta", Format.short(cost) .. " → " .. Format.short(cost / 2) .. " de comida" } }
		local saved = State.num("HalfDig")
		if saved > 0 then
			table.insert(rows, { "Ya tienes guardadas", tostring(saved) })
		end
		return rows
	end,
	zoneKey = function()
		local depth = State.depth()
		local zone = Config.Zones[depth + 1]
		if not zone then
			return { { "Ya tienes todas las zonas", "te da 3 de jalea" } }
		end
		local rows = { { "Abre durante 30 min", zone.name }, { "Tu capa", "no cambia" } }
		local left = remaining("KeyUntil")
		if left > 0 then
			table.insert(rows, { "Tu llave abierta", "te quedan " .. minutes(left) })
		end
		return rows
	end,
	sack = function()
		return colonyTime(900, 300, "15 min")
	end,
	crate = function()
		return colonyTime(3600, 1200, "1 h")
	end,
	bigSack = function()
		return colonyTime(14400, 4800, "4 h")
	end,
	frenzy = function()
		return { { "Frenesí", "x" .. Config.Frenzy.Mult .. " durante 1 min" } }
	end,
	egg = function()
		local rows = colonyTime(Config.Egg.PaidSeconds, Config.Egg.PaidFloor, "10 min")
		table.insert(rows, { "Aparece", "junto a tu hormiguero" })
		return rows
	end,
	potion = function()
		return doubleFood(15 * 60)
	end,
	bigPotion = function()
		return doubleFood(60 * 60)
	end,
	speedBoost = function()
		local walk = walkSpeed()
		local rows = { { "Tu velocidad, 15 min", tenth(walk) .. " → " .. tenth(walk * 1.4) } }
		local left = remaining("SpeedUntil")
		if left > 0 then
			table.insert(rows, { "Ya corres más", "te quedan " .. minutes(left) .. " → " .. minutes(left + 900) })
		end
		return rows
	end,
	magnet = function()
		local rows = { { "Durante", "15 min" }, { "Atrae desde", "16 pasos" } }
		local left = remaining("MagnetUntil")
		if left > 0 then
			table.insert(rows, { "Ya tienes imán", "te quedan " .. minutes(left) .. " → " .. minutes(left + 900) })
		end
		return rows
	end,
	jellyBoost = function()
		local jelly = math.floor(State.jellyNow())
		local rows = if jelly >= 1 then { { "Tu próximo enjambre", jelly .. " → " .. jelly * 2 .. " de jalea" } } else { { "Tu próximo enjambre", "el doble de jalea" } }
		local saved = State.num("JellyBoost")
		if saved > 0 then
			table.insert(rows, { "Ya tienes guardados", tostring(saved) })
		end
		-- Antes del primer enjambre no sirve en horas: no se vende hasta que ya puedas enjambrar
		if jelly < 1 and State.num("Rebirths") == 0 then
			return rows, nil, "Aún no puedes enjambrar: sirve cuando tu partida ya dé jalea"
		end
		return rows
	end,
	jar = function()
		return jellyRows(5)
	end,
	bigJar = function()
		return jellyRows(30)
	end,
	feast = function()
		return { { "Para", "todas las del servidor" }, { "Comida x2", "5 min" } }
	end,
	goldRain = function()
		return { { "Para", "todas las del servidor" }, { "Comida dorada", "1 de cada 4 durante 5 min" } }
	end,
}

-- Excavadoras (las que tienen `layers`): solo sirven para la capa siguiente si cae en su tramo
local function digEffect(def)
	local depth = State.depth()
	local from, to = def.layers[1], def.layers[2] or def.layers[1]
	local nextLayer = depth + 1
	if depth >= Stats.MaxDepth then
		return { { "Ya tienes todas las capas", "no te sirve" } }, nil, "Ya tienes todas las capas"
	end
	local zone = Config.Zones[nextLayer]
	local rows = { { "Capa", depth .. " → " .. nextLayer }, { "Se abre", if zone then zone.name else "una zona nueva" } }
	if nextLayer < from or nextLayer > to then
		local span = if from == to then "la capa " .. from else "las capas " .. from .. " a " .. to
		return { { "Sirve para", span }, { "Tu próxima capa", "es la " .. nextLayer } }, nil, "No es para tu próxima capa"
	end
	-- Lo que de verdad ahorra: la comida de excavar y, a tu ritmo de colonia, cuánto tardarías
	local cost = Stats.digCost(depth) * (if State.num("HalfDig") > 0 then 0.5 else 1)
	local food = State.num("Food")
	if food >= cost then
		table.insert(rows, { "Ya tienes", Format.short(cost) .. " de comida" })
		return rows, nil, "Ya tienes la comida: excávala gratis en tu hormiguero"
	end
	local missing = cost - food
	local r = rate()
	table.insert(rows, { "Te ahorras", Format.short(missing) .. " de comida" .. (if r > 0 then " (≈ " .. minutes(missing / r) .. " de tu colonia)" else "") })
	return rows
end

local function effectOf(entry): ({ { string } }, string?, string?)
	local def = entry.def
	if def.gift then
		return { { "Para", "otra jugadora del servidor" } }, nil, "Se regala en la taquilla del mercadillo"
	end
	local fn = EFFECTS[def.id]
	if not fn and type(def.layers) == "table" then
		fn = digEffect
	end
	if not fn then
		return {}, nil, nil
	end
	local ok, rows, active, blocked
	if fn == digEffect then
		ok, rows, active, blocked = pcall(digEffect, def)
	else
		ok, rows, active, blocked = pcall(fn, owned(entry), def)
	end
	if not ok or type(rows) ~= "table" then
		return {}, nil, nil
	end
	return rows, active, blocked
end

-------------------------------------------------------------------------------
-- Precios: los dice Roblox; si no responde, el sugerido
-------------------------------------------------------------------------------

local function priceText(entry): string
	local id = idOf(entry)
	local robux = prices[id] or entry.def.robux or 0
	return robux .. " R$"
end

local function fetchPrice(entry, onDone: () -> ())
	local id = idOf(entry)
	if id <= 0 or prices[id] then
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(id, if entry.kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		end)
		if ok and info and info.PriceInRobux then
			prices[id] = info.PriceInRobux
			onDone()
		end
	end)
end

-------------------------------------------------------------------------------
-- El puesto
-------------------------------------------------------------------------------

local selectItem: (item: any, scroll: boolean?) -> ()

-- Cartel de cada estante
local function shelfSign(parent: Instance, text: string, y: number, big: boolean)
	local label = Comic.label(parent, text, Comic.Display, if big then 30 else 24, Comic.Ink)
	label.Position = UDim2.fromOffset(8, y)
	label.Size = UDim2.fromOffset(0, if big then 38 else 30)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = if big then Comic.Yellow else CARD
	label.Rotation = if big then -2 else 1.5
	label.ZIndex = 4
	Comic.ink(label, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = label
	-- Cuelga de dos cordeles
	for _, side in { 0, 1 } do
		local cord = Comic.frame(label, Comic.Ink)
		cord.AnchorPoint = Vector2.new(0.5, 1)
		cord.Position = UDim2.new(side, if side == 0 then 14 else -14, 0, 0)
		cord.Size = UDim2.fromOffset(2, 12)
		cord.ZIndex = 3
	end
end

local function buildItem(entry, x: number, y: number, slot: number, rowH: number, objSize: number, index: number)
	local holder = Comic.frame(shelves)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	at(holder, x, y, slot, rowH)
	holder.ZIndex = 3
	local cx = slot / 2

	local halo = blob(holder, Comic.Yellow, cx, objSize * 0.45 + 8, objSize + 18, objSize * 0.9 + 18, 0, 14, 3)
	halo.ZIndex = 2
	halo.Visible = false

	local object = drawObject(holder, entry.def, objSize)
	object.AnchorPoint = Vector2.new(0.5, 0)
	object.Position = UDim2.fromOffset(cx, 8)
	lift(object, 3)
	object.Rotation = ({ -3, 2, -1, 3 })[(index - 1) % 4 + 1]

	-- Rótulo en el canto del estante
	local label = Comic.label(holder, entry.def.name, Comic.Body, 15, Comic.Ink)
	label.AnchorPoint = Vector2.new(0.5, 0)
	at(label, cx, objSize * 0.9 + 22, slot - 12, 20)
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = Comic.Paper
	label.ZIndex = 5
	fitText(label, 15, 10)
	Comic.ink(label, 2, true)

	-- Etiqueta de cartón con el precio, colgando de un hilo
	local thread = blob(holder, Comic.Ink, cx + objSize * 0.42, 20, 2, 18, -20)
	thread.ZIndex = 4
	local tag = Comic.label(holder, "", Comic.Display, 18, Comic.Ink)
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.fromOffset(cx + objSize * 0.46, 26)
	tag.Size = UDim2.fromOffset(0, 24)
	tag.AutomaticSize = Enum.AutomaticSize.X
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = CARD
	tag.Rotation = if index % 2 == 0 then 8 else -6
	tag.ZIndex = 6
	Comic.ink(tag, 2, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 7)
	pad.PaddingRight = UDim.new(0, 7)
	pad.Parent = tag

	-- Sello de goma "Tuyo" sobre lo que ya tienes
	local stamp = Comic.label(holder, "Tuyo", Comic.Display, 26, OWNED)
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.fromOffset(cx + objSize * 0.3, 26)
	stamp.Size = UDim2.fromOffset(78, 32)
	stamp.Rotation = -12
	stamp.BackgroundTransparency = 0.15
	stamp.BackgroundColor3 = Comic.Paper
	stamp.ZIndex = 7
	stamp.Visible = false
	Comic.round(stamp, 6)
	local ring = Comic.ink(stamp, 3, true)
	ring.Color = OWNED
	ring.LineJoinMode = Enum.LineJoinMode.Round

	-- Lo que aún no tiene id de Roblox (solo se ve en Studio) lleva un cartelito claro
	if idOf(entry) <= 0 then
		local note = Comic.label(holder, "Próximamente", Comic.Body, 13, Comic.Red)
		note.AnchorPoint = Vector2.new(0, 0)
		at(note, 4, 4, 0, 18)
		note.AutomaticSize = Enum.AutomaticSize.X
		note.BackgroundTransparency = 0
		note.BackgroundColor3 = Comic.Paper
		note.Rotation = -4
		note.ZIndex = 8
		Comic.ink(note, 2, true)
		local notePad = Instance.new("UIPadding")
		notePad.PaddingLeft = UDim.new(0, 5)
		notePad.PaddingRight = UDim.new(0, 5)
		notePad.Parent = note
	end

	local base = button(holder)
	base.Size = UDim2.fromScale(1, 1)
	base.ZIndex = 9
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local item = { def = entry.def, kind = entry.kind, group = entry.group, holder = holder, base = base, tag = tag, stamp = stamp, label = label, scale = scale, halo = halo }
	base.MouseButton1Click:Connect(function()
		selectItem(item)
	end)
	base.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1.05 }):Play()
	end)
	base.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1 }):Play()
	end)
	table.insert(items, item)
	fetchPrice(item, function()
		tag.Text = priceText(item)
		if selected == item then
			Store.refresh()
		end
	end)
	tag.Text = priceText(item)
	return item
end

local function buildShelves()
	shelves:ClearAllChildren()
	items = {}
	groupTops = {}
	local byGroup, order = catalog()
	groupOrder = order
	local y = 10
	if #order == 0 then
		local note = Comic.label(shelves, "Hoy el puesto está vacío", Comic.Display, 28, Comic.Ink)
		at(note, 0, 60, INNER_W, 40)
		note.ZIndex = 3
		shelves.CanvasSize = UDim2.fromOffset(0, 200)
		return
	end
	for _, group in order do
		local list = byGroup[group]
		-- Lo que es para siempre (pases) va en grande, con su cartel amarillo
		local big = list[1].kind == "pass"
		groupTops[group] = y
		shelfSign(shelves, groupName(group), y + 10, big)
		y += if big then 58 else 50
		local objSize = if big then 96 else 72
		local slot = if big then 146 else 112
		local rowH = math.floor(objSize * 0.9) + 50
		local perRow = math.max(1, math.floor(INNER_W / slot))
		slot = INNER_W / perRow
		local rows = math.ceil(#list / perRow)
		for row = 1, rows do
			-- Balda de madera bajo cada fila
			local plankY = y + (row - 1) * rowH + math.floor(objSize * 0.9) + 10
			local plank = Comic.frame(shelves, WOOD)
			at(plank, 0, plankY, INNER_W, 12)
			plank.ZIndex = 2
			Comic.ink(plank, 3, true)
			local edge = Comic.frame(shelves, WOOD_DARK)
			at(edge, 0, plankY + 12, INNER_W, 8)
			edge.ZIndex = 2
		end
		for i, entry in list do
			local row = (i - 1) // perRow
			local col = (i - 1) % perRow
			buildItem(entry, slot * (col + 0.5), y + row * rowH, slot, rowH, objSize, i)
		end
		y += rows * rowH + 18
	end
	shelves.CanvasSize = UDim2.fromOffset(0, y + 10)
end

-------------------------------------------------------------------------------
-- La ficha
-------------------------------------------------------------------------------

local function paintSheet()
	local p = sheetParts
	local item = selected
	sheet.Visible = item ~= nil or not compact
	p.empty.Visible = item == nil
	p.content.Visible = item ~= nil
	if not item then
		return
	end
	local mine = owned(item)
	-- Esto se llama con cada bocado: solo se redibuja lo que cambió
	if p.drawnFor ~= item then
		p.drawnFor = item
		p.drawing:ClearAllChildren()
		local object = drawObject(p.drawing, item.def, 132)
		object.AnchorPoint = Vector2.new(0.5, 0.5)
		object.Position = UDim2.fromScale(0.5, 0.5)
		lift(object, 24)
		p.body.CanvasPosition = Vector2.zero
	end
	p.name.Text = item.def.name
	p.kind.Text = if item.kind == "pass" then "Pase: es para siempre" else "Se usa al comprarlo. Puedes comprarlo otra vez."
	p.desc.Text = item.def.desc or ""

	local rows, _, blocked = effectOf(item)
	local signature = {}
	for _, row in rows do
		table.insert(signature, tostring(row[1]) .. "=" .. tostring(row[2]))
	end
	local key = table.concat(signature, "|")
	if p.rowsKey == key and p.rowsFor == item then
		rows = nil :: any
	else
		p.rowsKey = key
		p.rowsFor = item
		for _, child in p.rows:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	local y = 0
	for _, row in rows or {} do
		local label = Comic.label(p.rows, tostring(row[1]), Comic.Body, 15, Comic.Ink)
		at(label, 0, y, SHEET_W - 40, 18)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTransparency = 0.3
		label.ZIndex = 4
		local value = Comic.label(p.rows, tostring(row[2] or ""), Comic.Display, 22, Comic.Ink)
		at(value, 0, y + 17, SHEET_W - 40, 26)
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.ZIndex = 4
		fitText(value, 22, 12)
		y += 48
	end
	if rows then
		p.rowsTitle.Visible = #rows > 0
		p.rows.Size = UDim2.fromOffset(SHEET_W - 40, y)
		p.body.CanvasSize = UDim2.fromOffset(0, p.rows.Position.Y.Offset + y + 16)
	end

	local id = idOf(item)
	local face, label = p.buyFace, p.buyLabel
	label.TextColor3 = Comic.Ink
	label.TextTransparency = 0
	if mine then
		face.BackgroundColor3 = DIM
		label.Text = "Es tuyo"
		label.TextTransparency = 0.3
	elseif blocked then
		-- Ahora no te sirve: se dice por qué y no se ofrece comprarlo
		face.BackgroundColor3 = DIM
		label.Text = blocked
		label.TextTransparency = 0.25
	elseif id <= 0 then
		face.BackgroundColor3 = DIM
		label.Text = "Próximamente"
		label.TextTransparency = 0.3
	else
		face.BackgroundColor3 = Comic.Yellow
		label.Text = "Comprar por " .. priceText(item)
	end
end

local function paintShelves()
	for _, item in items do
		local mine = owned(item)
		item.stamp.Visible = mine
		item.tag.Visible = not mine
		item.halo.Visible = item == selected
		if mine then
			local _, active = effectOf(item)
			item.label.Text = if active then "Tuyo · " .. active else item.def.name
			item.label.BackgroundColor3 = Color3.fromRGB(214, 240, 200)
		else
			item.label.Text = item.def.name
			item.label.BackgroundColor3 = Comic.Paper
		end
	end
end

function Store.refresh()
	if not gui then
		return
	end
	paintShelves()
	paintSheet()
end

local function scrollToItem(item)
	local s = math.max(fit.Scale, 0.01)
	local top = (item.holder.AbsolutePosition.Y - shelves.AbsolutePosition.Y) / s + shelves.CanvasPosition.Y
	local view = shelves.AbsoluteWindowSize.Y / s
	local maxY = math.max(0, shelves.CanvasSize.Y.Offset - view)
	TweenService:Create(shelves, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CanvasPosition = Vector2.new(0, math.clamp(top - view / 3, 0, maxY)),
	}):Play()
end

selectItem = function(item, scroll)
	local was = selected
	selected = item
	Comic.punch(item.scale, 1.12)
	Sfx.pop(1.15)
	if scroll then
		scrollToItem(item)
	end
	Store.refresh()
	-- La ficha se clava: un golpecito al cambiar de artículo
	if was ~= item then
		Comic.punch(sheetParts.pop, 0.94)
	end
end

local function buy()
	local item = selected
	if not item then
		return
	end
	local id = idOf(item)
	local _, _, blocked = effectOf(item)
	if owned(item) or id <= 0 or blocked then
		Sfx.pop(0.7)
		Comic.punch(item.scale, 1.2)
		return
	end
	Sfx.pop(1.2)
	if item.kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, id)
	else
		MarketplaceService:PromptProductPurchase(player, id)
	end
end

-------------------------------------------------------------------------------
-- Montaje
-------------------------------------------------------------------------------

local function layout()
	if not sheet then
		return
	end
	if compact then
		-- La ficha va encima del puesto, a la derecha, y se quita con "Volver"
		panel.Size = UDim2.fromOffset(STALL_W, panel.Size.Y.Offset)
		sheet.Position = UDim2.new(0, STALL_W - SHEET_W - 6, 0, 8)
		sheet.Size = UDim2.new(0, SHEET_W, 1, -16)
	else
		panel.Size = UDim2.fromOffset(TOTAL_W, panel.Size.Y.Offset)
		sheet.Position = UDim2.fromOffset(STALL_W + GAP, 24)
		sheet.Size = UDim2.new(0, SHEET_W, 1, -40)
	end
	sheetParts.back.Visible = compact
	paintSheet()
end

local function resize()
	local cam = Workspace.CurrentCamera
	if not cam or not panel then
		return
	end
	local view = cam.ViewportSize
	local s = math.max(fit.Scale, 0.01)
	local room = view.X - MARGIN * 2
	local wantCompact = TOTAL_W * s > room
	local widest = room / (if wantCompact then STALL_W else TOTAL_W)
	if s > widest then
		s = math.max(widest, 0.01)
		fit.Scale = s
	end
	panel.Size = UDim2.fromOffset(if wantCompact then STALL_W else TOTAL_W, math.min(H, (view.Y - MARGIN * 2) / s))
	if wantCompact ~= compact then
		compact = wantCompact
	end
	layout()
end

local function buildSheet()
	sheet = Comic.frame(panel)
	sheet.ZIndex = 20
	local pop = Instance.new("UIScale")
	pop.Parent = sheet

	local shadow = Comic.frame(sheet, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(7, 7)
	shadow.ZIndex = 20
	local paper = Comic.frame(sheet, Comic.Paper)
	paper.Size = UDim2.fromScale(1, 1)
	paper.Rotation = 1
	paper.Active = true
	paper.ZIndex = 21
	Comic.ink(paper, 4, true)
	-- Chincheta roja arriba
	local pin = blob(paper, Comic.Red, SHEET_W / 2, 6, 20, 20, 0, -1, 3)
	pin.ZIndex = 25

	local empty = Comic.label(paper, "Toca algo del mostrador para verlo de cerca", Comic.Display, 26, Comic.Ink)
	at(empty, 24, 120, SHEET_W - 48, 120)
	empty.TextWrapped = true
	empty.TextTransparency = 0.35
	empty.ZIndex = 22

	local content = Comic.frame(paper)
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 22

	local body = Instance.new("ScrollingFrame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 1, -84)
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ScrollBarThickness = 5
	body.ScrollBarImageColor3 = Comic.Ink
	body.ElasticBehavior = Enum.ElasticBehavior.Never
	body.ZIndex = 22
	body.Parent = content

	local drawing = Comic.frame(body)
	at(drawing, 20, 18, SHEET_W - 40, 130)
	drawing.ZIndex = 23

	local name = Comic.label(body, "", Comic.Display, 34, Comic.Ink)
	at(name, 20, 150, SHEET_W - 40, 38)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 23
	fitText(name, 34, 18)
	local kind = Comic.label(body, "", Comic.Body, 15, Comic.Red)
	at(kind, 20, 188, SHEET_W - 40, 20)
	kind.TextXAlignment = Enum.TextXAlignment.Left
	kind.ZIndex = 23
	fitText(kind, 15, 10)
	local desc = Comic.label(body, "", Comic.Body, 17, Comic.Ink)
	at(desc, 20, 212, SHEET_W - 40, 46)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.ZIndex = 23
	fitText(desc, 17, 11)

	local rowsTitle = Comic.label(body, "En tu partida", Comic.Display, 22, Comic.Red)
	at(rowsTitle, 20, 266, SHEET_W - 40, 26)
	rowsTitle.TextXAlignment = Enum.TextXAlignment.Left
	rowsTitle.ZIndex = 23
	local underline = Comic.frame(rowsTitle, Comic.Red)
	underline.Position = UDim2.new(0, 0, 1, -2)
	underline.Size = UDim2.fromOffset(120, 3)
	underline.ZIndex = 23
	local rows = Comic.frame(body)
	at(rows, 20, 298, SHEET_W - 40, 10)
	rows.ZIndex = 23

	local buyHolder, buyFace = Comic.button(content, UDim2.new(1, -40, 0, 56), Comic.Yellow, 5)
	buyHolder.AnchorPoint = Vector2.new(0, 1)
	buyHolder.Position = UDim2.new(0, 18, 1, -18)
	buyHolder.ZIndex = 24
	buyFace.ZIndex = 25
	local buyLabel = Comic.label(buyFace, "", Comic.Display, 28, Comic.Ink)
	buyLabel.Size = UDim2.fromScale(1, 1)
	buyLabel.ZIndex = 26
	fitText(buyLabel, 28, 14)
	buyFace.MouseButton1Click:Connect(buy)

	-- En pantallas estrechas la ficha tapa el puesto: "Volver" la quita
	local back = button(paper)
	at(back, 12, 12, 96, 34)
	back.BackgroundTransparency = 0
	back.BackgroundColor3 = CARD
	back.Rotation = -3
	back.ZIndex = 27
	back.Visible = false
	Comic.ink(back, 2, true)
	local backText = Comic.label(back, "Volver", Comic.Display, 22, Comic.Ink)
	backText.Size = UDim2.fromScale(1, 1)
	backText.ZIndex = 28
	back.MouseButton1Click:Connect(function()
		selected = nil
		Sfx.pop(0.9)
		Store.refresh()
	end)

	sheetParts = {
		pop = pop,
		empty = empty,
		content = content,
		body = body,
		drawing = drawing,
		name = name,
		kind = kind,
		desc = desc,
		rowsTitle = rowsTitle,
		rows = rows,
		buyFace = buyFace,
		buyLabel = buyLabel,
		back = back,
	}
end

local function buildStall()
	stall = Comic.frame(panel)
	stall.Size = UDim2.new(0, STALL_W, 1, 0)
	stall.ZIndex = 2

	local shadow = Comic.frame(stall, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(10, 10)
	shadow.ZIndex = 2

	local face = Comic.frame(stall, WALL)
	face.Size = UDim2.fromScale(1, 1)
	face.ClipsDescendants = true
	face.Active = true
	face.ZIndex = 3
	Comic.ink(face, 5, true)
	-- Tablones de la pared del puesto
	for k = 1, math.floor(STALL_W / 46) do
		local line = Comic.frame(face, WALL_LINE)
		line.Position = UDim2.fromOffset(k * 46, 0)
		line.Size = UDim2.new(0, 3, 1, 0)
		line.ZIndex = 3
	end

	shelves = Instance.new("ScrollingFrame")
	shelves.BackgroundTransparency = 1
	shelves.BorderSizePixel = 0
	shelves.Position = UDim2.fromOffset(POST + 8, AWNING + 4)
	shelves.Size = UDim2.new(0, INNER_W, 1, -AWNING - COUNTER - 8)
	shelves.ScrollingDirection = Enum.ScrollingDirection.Y
	shelves.ScrollBarThickness = 6
	shelves.ScrollBarImageColor3 = Comic.Ink
	shelves.ElasticBehavior = Enum.ElasticBehavior.Never
	shelves.ZIndex = 4
	shelves.Parent = face

	-- Postes del puesto
	for _, side in { 0, 1 } do
		local post = Comic.frame(face, WOOD)
		post.AnchorPoint = Vector2.new(side, 0)
		post.Position = UDim2.fromScale(side, 0)
		post.Size = UDim2.new(0, POST, 1, 0)
		post.ZIndex = 6
		Comic.ink(post, 3, true)
	end

	-- Mostrador: una tabla delante con una frase clara
	local counter = Comic.frame(face, WOOD)
	counter.AnchorPoint = Vector2.new(0, 1)
	counter.Position = UDim2.fromScale(0, 1)
	counter.Size = UDim2.new(1, 0, 0, COUNTER)
	counter.ZIndex = 7
	Comic.ink(counter, 4, true)
	local lip = Comic.frame(counter, WOOD_DARK)
	lip.Size = UDim2.new(1, 0, 0, 10)
	lip.ZIndex = 7
	local chalk = Comic.label(counter, "Todo se paga con Robux", Comic.Body, 18, Comic.Paper)
	chalk.Position = UDim2.fromOffset(0, 12)
	chalk.Size = UDim2.new(1, 0, 1, -14)
	chalk.ZIndex = 8

	-- Persiana metálica: sube al abrir, baja al cerrar
	shutter = Comic.frame(face, SHUTTER)
	shutter.Position = UDim2.fromOffset(0, AWNING - 6)
	shutter.Size = UDim2.new(1, 0, 1, -AWNING - COUNTER + 6)
	shutter.ClipsDescendants = true
	shutter.ZIndex = 9
	Comic.ink(shutter, 3, true)
	for k = 0, 30 do
		local rib = Comic.frame(shutter, SHUTTER_RIB)
		rib.Position = UDim2.fromOffset(0, k * 22 + 16)
		rib.Size = UDim2.new(1, 0, 0, 4)
		rib.ZIndex = 9
	end

	-- Toldo de rayas con el borde festoneado y el letrero colgado
	local awning = Comic.frame(face, Comic.Paper)
	awning.Size = UDim2.new(1, 0, 0, AWNING - 18)
	awning.ZIndex = 11
	Comic.ink(awning, 4, true)
	local stripeW = 40
	for k = 0, math.ceil(STALL_W / stripeW) do
		if k % 2 == 0 then
			local stripe = Comic.frame(awning, STRIPE)
			stripe.Position = UDim2.fromOffset(k * stripeW, 0)
			stripe.Size = UDim2.new(0, stripeW, 1, 0)
			stripe.ZIndex = 11
		end
		local scallop = blob(face, if k % 2 == 0 then STRIPE else Comic.Paper, k * stripeW + stripeW / 2, AWNING - 18, stripeW, 26, 0, -1, 3)
		scallop.ZIndex = 10
	end
	local signHolder, signFace = Comic.box(face, UDim2.fromOffset(170, 46), Comic.Yellow, 4)
	signHolder.AnchorPoint = Vector2.new(0.5, 0)
	signHolder.Position = UDim2.new(0.5, 0, 0, 14)
	signHolder.Rotation = -2
	signHolder.ZIndex = 12
	local signShadow: any = signHolder:FindFirstChild("Shadow")
	signShadow.ZIndex = 12
	signFace.ZIndex = 13
	local signText = Comic.label(signFace, "Tienda", Comic.Display, 34, Comic.Ink)
	signText.Size = UDim2.fromScale(1, 1)
	signText.ZIndex = 14

	-- Cerrar: chapa redonda sobre el toldo
	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(46, 46), Comic.Paper, 4)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -POST - 8, 0, 14)
	closeHolder.ZIndex = 12
	local closeShadow: any = closeHolder:FindFirstChild("Shadow")
	closeShadow.ZIndex = 12
	closeFace.ZIndex = 13
	Comic.round(closeFace)
	Comic.round(closeShadow)
	local cross = Comic.label(closeFace, "X", Comic.Display, 30, Comic.Red)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 14
	closeFace.MouseButton1Click:Connect(function()
		Store.close()
	end)
end

-------------------------------------------------------------------------------
-- Abrir, cerrar, enfocar
-------------------------------------------------------------------------------

local function findGroup(section: string): string?
	local wanted = section:lower()
	for _, key in groupOrder do
		if key:lower() == wanted or groupName(key):lower() == wanted then
			return key
		end
	end
	if wanted == "passes" or wanted == "pases" or wanted == "pass" then
		return if groupTops.siempre then "siempre" else groupOrder[1]
	end
	if wanted == "products" or wanted == "productos" or wanted == "product" then
		for _, key in groupOrder do
			if key ~= "siempre" then
				return key
			end
		end
	end
	return nil
end

function Store.isOpen(): boolean
	return isOpen
end

function Store.open(section: string?)
	if not gui then
		return
	end
	local wasOpen = isOpen
	isOpen = true
	closing += 1
	gui.Enabled = true
	resize()
	Store.refresh()
	if not wasOpen then
		Sfx.pop(0.9)
		shelves.CanvasPosition = Vector2.zero
		-- La persiana sube
		shutter.Visible = true
		shutter.Size = UDim2.new(1, 0, 1, -AWNING - COUNTER + 6)
		TweenService:Create(shutter, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 0, 0),
		}):Play()
		if not compact then
			sheet.Position = UDim2.fromOffset(STALL_W - SHEET_W, 24)
			TweenService:Create(sheet, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(STALL_W + GAP, 24),
			}):Play()
		end
	end
	if section then
		local key = findGroup(section)
		local top = key and groupTops[key]
		if top then
			task.defer(function()
				local s = math.max(fit.Scale, 0.01)
				local view = shelves.AbsoluteWindowSize.Y / s
				local maxY = math.max(0, shelves.CanvasSize.Y.Offset - view)
				TweenService:Create(shelves, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CanvasPosition = Vector2.new(0, math.clamp(top, 0, maxY)),
				}):Play()
			end)
		end
	end
end

-- Abre la ficha de un artículo y lo señala en su estante
function Store.focus(id: string)
	if not gui then
		return
	end
	if not isOpen then
		Store.open()
	end
	for _, item in items do
		if item.def.id == id then
			task.defer(function()
				selectItem(item, true)
			end)
			return
		end
	end
end

function Store.close()
	if not isOpen then
		return
	end
	isOpen = false
	closing += 1
	local token = closing
	-- La persiana baja y el puesto se va
	TweenService:Create(shutter, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(1, 0, 1, -AWNING - COUNTER + 6),
	}):Play()
	task.delay(0.16, function()
		if token == closing and not isOpen and gui then
			gui.Enabled = false
		end
	end)
end

-- Teclado y mando: flechas para moverse por el puesto, Enter para comprar lo elegido
local function step(dx: number, dy: number)
	if #items == 0 then
		return
	end
	local index = selected and table.find(items, selected) or 0
	local target
	if dy ~= 0 and index > 0 then
		local g = table.find(groupOrder, items[index].group) or 1
		local nextGroup = groupOrder[math.clamp(g + dy, 1, #groupOrder)]
		for _, item in items do
			if item.group == nextGroup then
				target = item
				break
			end
		end
	else
		target = items[if index == 0 then 1 else math.clamp(index + (if dx ~= 0 then dx else dy), 1, #items)]
	end
	if target and target ~= selected then
		selectItem(target, true)
	end
end

function Store.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Store"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
	gui.Enabled = false
	-- Instance.new deja ZIndexBehavior en Global: los dibujos (ZIndex 1) quedaban debajo de la
	-- pared del puesto (ZIndex 3). Todo el puesto está pensado por capas de padre a hijo.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = button(gui)
	dim.BackgroundColor3 = Comic.Ink
	dim.BackgroundTransparency = 0.55
	dim.Size = UDim2.fromScale(1, 1)
	dim.Selectable = false
	dim.MouseButton1Click:Connect(function()
		Store.close()
	end)

	panel = Comic.frame(gui)
	panel.ZIndex = 2 -- siempre sobre el velo oscuro
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(TOTAL_W, H)
	fit = Hud.fitScale(panel, TAP)

	buildStall()
	buildSheet()
	buildShelves()

	fit:GetPropertyChangedSignal("Scale"):Connect(resize)
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(resize)
	end
	resize()
	Store.refresh()

	State.onChange(function()
		if isOpen then
			Store.refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not isOpen then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB then
			Store.close()
		elseif processed then
			return
		elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft then
			step(-1, 0)
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadRight then
			step(1, 0)
		elseif key == Enum.KeyCode.Up or key == Enum.KeyCode.DPadUp then
			step(0, -1)
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.DPadDown then
			step(0, 1)
		elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA then
			if selected then
				buy()
			else
				step(1, 0)
			end
		end
	end)
end

return Store
