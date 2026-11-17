-- Estelas del vestidor: lo que deja tu hormiga al andar. Única fuente de las estelas: la lista, sus precios, la regla VIP y cómo se montan.
--
-- Cada estela se compone de capas que salen del abdomen:
--   ribbons:   cintas (Trail) de distinto ancho y color; `half` es medio ancho en alturas de abdomen
--   particles: hasta 3 emisores (chispas, estrellas, burbujas, llamas, humo), ≤ 40 partículas vivas
--              cada uno (Rate × vida máxima). Solo emiten mientras la hormiga anda (Trails.startClient)
--   light:     una PointLight pequeña, opcionalmente con parpadeo
-- Las cintas se desvanecen rápido cerca de la hormiga para no tapar la vista de la cámara.
--
-- Campos para el vestidor: `colors` (muestra de la cinta), `dots` y `mark` (pista de sus partículas:
-- "star", "dot", "spark", "flame") y `pairs` (trajes de Shared/Outfits con los que forma conjunto).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Assets = require(script.Parent.Assets)

local Trails = {}

local V3, rgb = Vector3.new, Color3.fromRGB

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	burst = Assets.Burst,
	dots = Assets.Halftone,
	lines = Assets.SpeedLines,
}

-- Etiquetas que lee el cliente: emisores que solo van al andar, luces que parpadean, cintas que cambian de tono
local TAG_MOVING = "EstelaMov"
local TAG_FLICKER = "EstelaChispa"
local TAG_DRIFT = "EstelaTono"

local WHITE = rgb(255, 255, 255)

local LIST = {
	{ id = "sin", name = "Ninguna", cost = 0 },
	{
		id = "polvo",
		name = "Polvo",
		cost = 1e4,
		colors = { rgb(214, 168, 116), rgb(150, 98, 60) },
		dots = { rgb(214, 168, 116), rgb(150, 98, 60) },
		mark = "dot",
		ribbons = { { colors = { rgb(214, 168, 116), rgb(150, 98, 60) }, half = 0.5, life = 0.5, alpha = { 0.3, 1 }, glow = 0 } },
		particles = {
			{ tex = "smoke", colors = { rgb(214, 168, 116), rgb(150, 98, 60) }, size = { 0.5, 1.3 }, alpha = { 0.45, 1 }, life = { 0.5, 0.8 }, rate = 30, speed = { 1, 2 }, spread = { 25, 25 }, drag = 2 },
		},
	},
	{
		-- Eléctrica: línea blanca muy fina, aura amarilla con rayas, chispas que saltan a los lados
		id = "electrica",
		name = "Eléctrica",
		cost = 2e5,
		pairs = { "rayo" },
		colors = { rgb(255, 236, 60), rgb(80, 220, 255) },
		dots = { rgb(255, 236, 60), rgb(80, 220, 255), WHITE },
		mark = "spark",
		ribbons = {
			{ colors = { WHITE, rgb(80, 220, 255) }, half = 0.14, life = 0.35, alpha = { 0, 1 }, glow = 1, bright = 2.5 },
			{ colors = { rgb(255, 236, 60), rgb(80, 220, 255) }, half = 0.6, life = 0.45, alpha = { 0.5, 1 }, glow = 0.9, bright = 1.5, texture = "lines", texLength = 1.5 },
		},
		particles = {
			{ tex = "spark", colors = { rgb(255, 250, 160), rgb(80, 220, 255) }, size = { 0.45, 0 }, life = { 0.15, 0.3 }, rate = 110, speed = { 9, 15 }, spread = { 90, 30 }, drag = 7, glow = 1 },
			{ tex = "burst", colors = { WHITE, rgb(255, 236, 60) }, size = { 0.7, 0.1 }, life = { 0.12, 0.22 }, rate = 14, speed = { 0, 1 }, spread = { 180, 180 }, spin = { -400, 400 }, glow = 1 },
		},
		light = { color = rgb(120, 230, 255), range = 8, bright = 1.6, flicker = true },
	},
	{
		id = "azucar",
		name = "Azúcar",
		cost = 1e6,
		colors = { WHITE, rgb(190, 230, 255) },
		dots = { WHITE, rgb(190, 230, 255) },
		mark = "dot",
		ribbons = { { colors = { WHITE, rgb(190, 230, 255) }, half = 0.5, life = 0.6, alpha = { 0.25, 1 }, glow = 0.4 } },
		particles = {
			{ tex = "spark", colors = { WHITE, rgb(200, 236, 255) }, size = { 0.3, 0 }, life = { 0.4, 0.7 }, rate = 40, speed = { 0.5, 1.5 }, spread = { 40, 40 }, accel = V3(0, -2, 0), glow = 0.6 },
		},
	},
	{
		-- Mágica: cinta violeta-rosa que cambia de tono despacio y estrellas que suben
		id = "magica",
		name = "Mágica",
		cost = 3e7,
		pairs = { "hada", "mago" },
		colors = { rgb(170, 90, 255), rgb(255, 110, 200) },
		dots = { rgb(255, 210, 250), rgb(255, 110, 200), rgb(255, 230, 120) },
		mark = "star",
		ribbons = {
			{ colors = { rgb(170, 90, 255), rgb(255, 110, 200) }, half = 0.6, life = 0.7, alpha = { 0.35, 1 }, glow = 0.7, bright = 1.4, drift = true },
			{ colors = { WHITE, rgb(255, 200, 240) }, half = 0.14, life = 0.5, alpha = { 0.1, 1 }, glow = 1, bright = 2 },
		},
		particles = {
			{ tex = "burst", colors = { WHITE, rgb(255, 150, 230), rgb(180, 120, 255) }, size = { 0.2, 0.55, 0 }, life = { 0.8, 1.2 }, rate = 30, speed = { 0.4, 1 }, spread = { 50, 50 }, accel = V3(0, 3, 0), spin = { -120, 120 }, glow = 1 },
			{ tex = "spark", colors = { rgb(255, 240, 160), WHITE }, size = { 0.25, 0 }, life = { 0.5, 0.8 }, rate = 30, speed = { 0.5, 1.5 }, spread = { 70, 70 }, accel = V3(0, 1.5, 0), glow = 1 },
		},
		light = { color = rgb(230, 130, 255), range = 6, bright = 1 },
	},
	{
		-- Fuego: llamas de verdad con brasas que suben
		id = "fuego",
		name = "Fuego",
		cost = 1e9,
		pairs = { "llamas" },
		colors = { rgb(255, 220, 80), rgb(230, 57, 70) },
		dots = { rgb(255, 220, 80), rgb(255, 130, 40), rgb(230, 57, 70) },
		mark = "flame",
		ribbons = { { colors = { rgb(255, 230, 110), rgb(255, 120, 40), rgb(200, 30, 40) }, half = 0.55, life = 0.45, alpha = { 0.3, 1 }, glow = 0.9, bright = 1.5 } },
		particles = {
			{ tex = "fire", colors = { rgb(255, 240, 150), rgb(255, 140, 40), rgb(200, 40, 30) }, size = { 1, 0.25 }, alpha = { 0.15, 1 }, life = { 0.3, 0.5 }, rate = 70, speed = { 1, 3 }, spread = { 20, 20 }, accel = V3(0, 5, 0), glow = 1 },
			{ tex = "spark", colors = { rgb(255, 200, 80), rgb(255, 90, 30) }, size = { 0.18, 0 }, life = { 0.5, 0.9 }, rate = 40, speed = { 2, 4 }, spread = { 50, 50 }, accel = V3(0, 4, 0), glow = 1 },
		},
		light = { color = rgb(255, 150, 60), range = 7, bright = 1.3, flicker = true },
	},
	{
		-- Galaxia: cinta ancha azul-violeta con trama de estrellas, estrellas que titilan y neblina
		id = "galaxia",
		name = "Galaxia",
		cost = 5e9,
		pairs = { "galactica", "astronauta" },
		colors = { rgb(30, 40, 140), rgb(120, 60, 200), rgb(40, 20, 80) },
		dots = { WHITE, rgb(190, 210, 255), rgb(200, 150, 255) },
		mark = "star",
		ribbons = {
			{ colors = { rgb(40, 60, 180), rgb(120, 60, 200), rgb(30, 20, 70) }, half = 0.95, life = 0.9, alpha = { 0.35, 1 }, glow = 0.5, texture = "dots", texLength = 2.5 },
		},
		particles = {
			{ tex = "spark", colors = { WHITE, rgb(190, 210, 255) }, size = { 0, 0.4, 0.06, 0.35, 0 }, life = { 1, 1.4 }, rate = 25, speed = { 0.2, 0.6 }, spread = { 180, 180 }, drag = 1, glow = 1 },
			{ tex = "smoke", colors = { rgb(120, 70, 220), rgb(40, 60, 180) }, size = { 1.4, 3 }, alpha = { 0.82, 1 }, life = { 1.2, 1.6 }, rate = 12, speed = { 0.2, 0.5 }, spread = { 60, 60 }, glow = 0.5 },
		},
	},
	{
		id = "corazones",
		name = "Corazones",
		cost = 3e11,
		pairs = { "kawaii" },
		colors = { rgb(255, 150, 200), rgb(255, 80, 140) },
		dots = { rgb(255, 80, 140), rgb(255, 180, 215) },
		mark = "dot",
		ribbons = { { colors = { rgb(255, 170, 210), rgb(255, 80, 140) }, half = 0.5, life = 0.6, alpha = { 0.3, 1 }, glow = 0.6 } },
		particles = {
			{ tex = "smoke", colors = { rgb(255, 120, 180), rgb(255, 60, 120) }, size = { 0.5, 1 }, alpha = { 0.35, 1 }, life = { 0.6, 0.9 }, rate = 25, speed = { 0.5, 1.5 }, spread = { 45, 45 }, accel = V3(0, 2, 0), glow = 0.7 },
			{ tex = "burst", colors = { WHITE, rgb(255, 170, 210) }, size = { 0.35, 0 }, life = { 0.6, 0.9 }, rate = 15, speed = { 0.5, 1 }, spread = { 60, 60 }, accel = V3(0, 2.5, 0), spin = { -90, 90 }, glow = 1 },
		},
		light = { color = rgb(255, 120, 180), range = 5, bright = 0.8 },
	},
	{
		-- Arcoíris: cinco bandas apiladas a lo ancho
		id = "arcoiris",
		name = "Arcoíris",
		cost = 1e13,
		colors = { rgb(230, 57, 70), rgb(255, 210, 63), rgb(110, 200, 90), rgb(62, 193, 243), rgb(160, 96, 230) },
		dots = { WHITE, rgb(255, 210, 63) },
		mark = "star",
		ribbons = {
			{ colors = { rgb(230, 57, 70) }, half = 0.17, y = 0.64, life = 0.65, alpha = { 0.2, 1 }, glow = 0.6 },
			{ colors = { rgb(255, 210, 63) }, half = 0.17, y = 0.32, life = 0.65, alpha = { 0.2, 1 }, glow = 0.6 },
			{ colors = { rgb(110, 200, 90) }, half = 0.17, y = 0, life = 0.65, alpha = { 0.2, 1 }, glow = 0.6 },
			{ colors = { rgb(62, 193, 243) }, half = 0.17, y = -0.32, life = 0.65, alpha = { 0.2, 1 }, glow = 0.6 },
			{ colors = { rgb(160, 96, 230) }, half = 0.17, y = -0.64, life = 0.65, alpha = { 0.2, 1 }, glow = 0.6 },
		},
		particles = {
			{ tex = "spark", colors = { WHITE, rgb(255, 240, 180) }, size = { 0.35, 0 }, life = { 0.4, 0.7 }, rate = 30, speed = { 1, 2 }, spread = { 70, 70 }, glow = 1 },
		},
	},
	{
		id = "toxica",
		name = "Tóxica",
		cost = 2e15,
		colors = { rgb(150, 255, 60), rgb(40, 160, 40) },
		dots = { rgb(150, 255, 60), rgb(210, 255, 120) },
		mark = "dot",
		ribbons = { { colors = { rgb(170, 255, 80), rgb(40, 160, 40) }, half = 0.55, life = 0.6, alpha = { 0.3, 1 }, glow = 0.7, bright = 1.3 } },
		particles = {
			{ tex = "dots", colors = { rgb(170, 255, 80), rgb(60, 200, 60) }, size = { 0.4, 0.75 }, alpha = { 0.2, 1 }, life = { 0.7, 1.1 }, rate = 30, speed = { 1, 2 }, spread = { 50, 50 }, accel = V3(0, 2, 0), spin = { -60, 60 }, glow = 0.6 },
			{ tex = "spark", colors = { rgb(210, 255, 120), rgb(90, 220, 60) }, size = { 0.25, 0.05 }, life = { 0.4, 0.6 }, rate = 25, speed = { 0.5, 1.5 }, spread = { 30, 30 }, accel = V3(0, -6, 0), glow = 0.8 },
		},
		light = { color = rgb(140, 255, 80), range = 6, bright = 0.9 },
	},
	{
		id = "escarcha",
		name = "Escarcha",
		cost = 5e17,
		pairs = { "hielo" },
		colors = { WHITE, rgb(120, 220, 255) },
		dots = { WHITE, rgb(170, 235, 255) },
		mark = "star",
		ribbons = {
			{ colors = { WHITE, rgb(120, 220, 255), rgb(60, 140, 230) }, half = 0.6, life = 0.7, alpha = { 0.3, 1 }, glow = 0.6, bright = 1.3 },
			{ colors = { WHITE }, half = 0.12, life = 0.4, alpha = { 0.1, 1 }, glow = 1, bright = 2 },
		},
		particles = {
			{ tex = "burst", colors = { WHITE, rgb(190, 240, 255) }, size = { 0.38, 0.1 }, life = { 0.9, 1.3 }, rate = 25, speed = { 0.5, 1.5 }, spread = { 60, 60 }, accel = V3(0, -1.5, 0), spin = { -80, 80 }, glow = 0.8 },
			{ tex = "smoke", colors = { rgb(210, 240, 255), rgb(150, 210, 255) }, size = { 0.8, 1.8 }, alpha = { 0.75, 1 }, life = { 0.8, 1.1 }, rate = 12, speed = { 0.3, 0.8 }, spread = { 40, 40 }, glow = 0.3 },
		},
		light = { color = rgb(160, 225, 255), range = 6, bright = 0.9 },
	},
	{
		-- Sombra: humo oscuro con brasas rojas
		id = "sombra",
		name = "Sombra",
		cost = 1e20,
		pairs = { "ninja" },
		colors = { rgb(30, 24, 36), rgb(90, 30, 90) },
		dots = { rgb(255, 60, 40), rgb(255, 150, 60) },
		mark = "dot",
		ribbons = { { colors = { rgb(26, 20, 30), rgb(80, 26, 80) }, half = 0.65, life = 0.7, alpha = { 0.25, 1 }, glow = 0 } },
		particles = {
			{ tex = "smoke", colors = { rgb(40, 30, 50), rgb(15, 10, 20) }, size = { 1, 2.4 }, alpha = { 0.4, 1 }, life = { 0.8, 1.2 }, rate = 25, speed = { 0.5, 1.5 }, spread = { 40, 40 }, accel = V3(0, 1, 0), glow = 0 },
			{ tex = "spark", colors = { rgb(255, 80, 40), rgb(200, 20, 30) }, size = { 0.2, 0 }, life = { 0.6, 0.9 }, rate = 30, speed = { 1.5, 3 }, spread = { 60, 60 }, accel = V3(0, 3, 0), glow = 1 },
		},
		light = { color = rgb(255, 60, 40), range = 5, bright = 0.7, flicker = true },
	},
	{
		-- Neón: doble línea dura cian y magenta
		id = "neon",
		name = "Neón",
		cost = 1e25,
		pairs = { "neonpunk" },
		colors = { rgb(0, 240, 255), rgb(255, 40, 220) },
		dots = { rgb(0, 240, 255), rgb(255, 40, 220) },
		mark = "spark",
		ribbons = {
			{ colors = { rgb(0, 240, 255) }, half = 0.12, y = 0.38, life = 0.6, alpha = { 0, 0.2, 1 }, glow = 1, bright = 3 },
			{ colors = { rgb(255, 40, 220) }, half = 0.12, y = -0.38, life = 0.6, alpha = { 0, 0.2, 1 }, glow = 1, bright = 3 },
		},
		particles = {
			{ tex = "spark", colors = { rgb(0, 240, 255), rgb(255, 40, 220) }, size = { 0.3, 0 }, life = { 0.3, 0.45 }, rate = 30, speed = { 2, 4 }, spread = { 80, 20 }, drag = 4, glow = 1 },
		},
		light = { color = rgb(255, 60, 230), range = 6, bright = 1.2 },
	},
	{
		-- Solo VIP
		id = "oro",
		name = "Oro VIP",
		cost = 0,
		pass = "vip",
		pairs = { "faraon" },
		colors = { rgb(255, 240, 160), rgb(255, 190, 40) },
		dots = { rgb(255, 240, 160), rgb(255, 190, 40) },
		mark = "star",
		ribbons = {
			{ colors = { rgb(255, 240, 160), rgb(255, 190, 40) }, half = 0.6, life = 0.7, alpha = { 0.3, 1 }, glow = 0.6, bright = 1.4 },
			{ colors = { WHITE }, half = 0.12, life = 0.45, alpha = { 0.1, 1 }, glow = 1, bright = 2 },
		},
		particles = {
			{ tex = "spark", colors = { rgb(255, 245, 180), rgb(255, 190, 40) }, size = { 0.3, 0 }, life = { 0.5, 0.7 }, rate = 30, speed = { 0.5, 1.5 }, spread = { 50, 50 }, glow = 1 },
			{ tex = "burst", colors = { WHITE, rgb(255, 200, 60) }, size = { 0.5, 0 }, life = { 0.6, 0.8 }, rate = 8, speed = { 0.3, 0.8 }, spread = { 60, 60 }, spin = { -90, 90 }, glow = 1 },
		},
		light = { color = rgb(255, 210, 90), range = 6, bright = 1 },
	},
	{
		-- Solo con el pase Hormiguero dorado (Monetize): cola de cometa blanca y azul con estrellas
		id = "cometa",
		name = "Cometa",
		cost = 0,
		pass = "goldHill",
		colors = { WHITE, rgb(120, 200, 255) },
		dots = { WHITE, rgb(255, 230, 120) },
		mark = "star",
		ribbons = {
			{ colors = { WHITE, rgb(120, 200, 255) }, half = 0.55, life = 0.8, alpha = { 0.2, 1 }, glow = 0.8, bright = 1.6 },
		},
		particles = {
			{ tex = "burst", colors = { WHITE, rgb(255, 230, 120) }, size = { 0.45, 0 }, life = { 0.5, 0.8 }, rate = 12, speed = { 0.3, 1 }, spread = { 50, 50 }, spin = { -120, 120 }, glow = 1 },
		},
		light = { color = rgb(170, 220, 255), range = 5, bright = 0.9 },
	},
}

Trails.list = LIST
Trails.byId = {}
for _, def in LIST do
	Trails.byId[def.id] = def
end

-- ¿La estela forma conjunto con ese traje?
function Trails.pairsWith(trailId: any, outfitId: any): boolean
	local def = Trails.byId[trailId]
	return def ~= nil and def.pairs ~= nil and table.find(def.pairs, outfitId) ~= nil
end

-- Estela con la que forma conjunto un traje (la primera que lo nombre), o nil
function Trails.forOutfit(outfitId: any)
	for _, def in LIST do
		if def.pairs and table.find(def.pairs, outfitId) then
			return def
		end
	end
	return nil
end

-- Secuencias repartidas por igual de 0 a 1
local function numbers(values: { number }, k: number): NumberSequence
	if #values == 1 then
		return NumberSequence.new(values[1] * k)
	end
	local keys = {}
	for i, v in values do
		table.insert(keys, NumberSequenceKeypoint.new((i - 1) / (#values - 1), v * k))
	end
	return NumberSequence.new(keys)
end

local function colorsOf(list: { Color3 }): ColorSequence
	if #list == 1 then
		return ColorSequence.new(list[1])
	end
	local keys = {}
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), c))
	end
	return ColorSequence.new(keys)
end

local function point(abdomen: BasePart, position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = "EstelaPunto"
	a.Position = position
	a.Parent = abdomen
	return a
end

-- Quita lo que hubiera de la estela anterior
local function clear(character: Model)
	local old = character:FindFirstChild("Estela")
	if old then
		old:Destroy()
	end
	local abdomen = character:FindFirstChild("Abdomen")
	if abdomen then
		for _, child in abdomen:GetChildren() do
			if child.Name == "EstelaPunto" then
				child:Destroy()
			end
		end
	end
end

-- Monta la estela `id` en el personaje (servidor). `scale` es la escala del modelo; el ancho de
-- las cintas sigue además al abdomen, que crece con la mejora de carga.
function Trails.apply(character: Model, id: any, scale: number)
	clear(character)
	local def = Trails.byId[id]
	local abdomen = character:FindFirstChild("Abdomen")
	if not def or not def.ribbons or not abdomen or not abdomen:IsA("BasePart") then
		return
	end
	local s = math.max(tonumber(scale) or 1, 0.1)
	local size = abdomen.Size
	local tall = size.Y / 1.7 -- 1 con el abdomen de serie a escala 1
	local back = size.Z * 0.33 -- donde nacen las cintas (como la estela antigua: 0,6 a escala 1)

	local folder = Instance.new("Folder")
	folder.Name = "Estela"

	for i, r in def.ribbons do
		local y = (r.y or 0) * tall
		local half = r.half * tall
		local trail = Instance.new("Trail")
		trail.Name = "Cinta" .. i
		trail.Attachment0 = point(abdomen, V3(0, y + half, back))
		trail.Attachment1 = point(abdomen, V3(0, y - half, back))
		trail.Color = colorsOf(r.colors)
		trail.Transparency = numbers(r.alpha or { 0.2, 1 }, 1)
		trail.WidthScale = NumberSequence.new(1, 0.3)
		trail.Lifetime = r.life or 0.6
		trail.MinLength = 0.05
		trail.LightEmission = r.glow or 0.3
		trail.Brightness = r.bright or 1
		trail.LightInfluence = if (r.glow or 0) > 0.5 then 0 else 1
		trail.FaceCamera = true
		if r.texture then
			trail.Texture = TEX[r.texture]
			trail.TextureMode = Enum.TextureMode.Wrap
			trail.TextureLength = (r.texLength or 2) * s
		end
		if r.drift and #r.colors >= 2 then
			trail:SetAttribute("ColorA", r.colors[1])
			trail:SetAttribute("ColorB", r.colors[#r.colors])
			CollectionService:AddTag(trail, TAG_DRIFT)
		end
		trail.Parent = folder
	end

	if def.particles or def.light then
		local emitPoint = point(abdomen, V3(0, 0, size.Z * 0.55))
		for i, p in def.particles or {} do
			if i > 3 then
				break
			end
			local e = Instance.new("ParticleEmitter")
			e.Name = "Particulas" .. i
			e.Texture = TEX[p.tex] or TEX.spark
			e.Color = colorsOf(p.colors)
			e.Size = numbers(p.size, s)
			e.Transparency = numbers(p.alpha or { 0, 1 }, 1)
			e.Lifetime = NumberRange.new(p.life[1], p.life[2])
			e.Rate = p.rate
			e.Speed = NumberRange.new(p.speed[1] * s, p.speed[2] * s)
			e.SpreadAngle = Vector2.new(p.spread and p.spread[1] or 30, p.spread and p.spread[2] or 30)
			e.EmissionDirection = Enum.NormalId.Back -- +Z del abdomen: hacia atrás
			e.Acceleration = (p.accel or Vector3.zero) * s
			e.Drag = p.drag or 0
			e.LightEmission = p.glow or 0.5
			e.LightInfluence = if (p.glow or 0.5) > 0.5 then 0 else 1
			if p.spin then
				e.Rotation = NumberRange.new(0, 360)
				e.RotSpeed = NumberRange.new(p.spin[1], p.spin[2])
			end
			e.Parent = emitPoint
			CollectionService:AddTag(e, TAG_MOVING)
		end
		if def.light then
			local l = Instance.new("PointLight")
			l.Name = "Luz"
			l.Color = def.light.color
			l.Range = def.light.range * math.min(s, 1.6)
			l.Brightness = def.light.bright
			l.Shadows = false
			l:SetAttribute("Base", def.light.bright)
			l.Parent = emitPoint
			if def.light.flicker then
				CollectionService:AddTag(l, TAG_FLICKER)
			end
		end
	end

	folder.Parent = character
end

-- Cliente: los emisores solo emiten mientras su hormiga anda (así una hormiga quieta no se queda en
-- una nube), las luces eléctricas parpadean y las cintas mágicas cambian de tono despacio.
-- Los cambios son locales y visuales; el servidor no vuelve a tocar estas propiedades.
local started = false
function Trails.startClient()
	if started or not RunService:IsClient() then
		return
	end
	started = true
	local moveClock, flickerClock = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		moveClock += dt
		flickerClock += dt
		if flickerClock >= 0.07 then
			flickerClock = 0
			for _, light in CollectionService:GetTagged(TAG_FLICKER) do
				if light:IsA("PointLight") then
					local base = tonumber(light:GetAttribute("Base")) or 1
					light.Brightness = base * (if math.random() < 0.2 then 0.15 else 0.6 + math.random() * 0.7)
				end
			end
		end
		if moveClock < 0.1 then
			return
		end
		moveClock = 0
		for _, emitter in CollectionService:GetTagged(TAG_MOVING) do
			if emitter:IsA("ParticleEmitter") then
				local model = emitter:FindFirstAncestorOfClass("Model")
				local root = model and model:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local v = root.AssemblyLinearVelocity
					local moving = v.X * v.X + v.Z * v.Z > 4
					if emitter.Enabled ~= moving then
						emitter.Enabled = moving
					end
				end
			end
		end
		local t = (math.sin(os.clock() * 0.7) + 1) / 2
		for _, trail in CollectionService:GetTagged(TAG_DRIFT) do
			local a, b = trail:GetAttribute("ColorA"), trail:GetAttribute("ColorB")
			if trail:IsA("Trail") and typeof(a) == "Color3" and typeof(b) == "Color3" then
				trail.Color = ColorSequence.new(a:Lerp(b, t), b:Lerp(a, t))
			end
		end
	end)
end

return Trails
