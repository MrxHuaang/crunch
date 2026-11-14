-- Todos los números de balance y textos del juego viven aquí. Cambia valores sin tocar lógica.

local Config = {}

Config.Player = {
	WalkSpeed = 12, -- lento a propósito: la velocidad se compra
	BiteCooldown = 0.3,
	BiteRange = 6, -- distancia máxima al borde de la comida
	Capacity = 3,
	CritMult = 3,
}

Config.Anthill = {
	DepositRadius = 11, -- se multiplica por la escala del hormiguero
}

Config.Worker = {
	Speed = 8,
	Carry = 1,
	TurnTime = 1.5, -- segundos que pierde cada obrera por viaje entre morder y soltar
	BaseCost = 8, -- la primera obrera llega a los dos o tres minutos
	CostGrowth = 1.03,
}

Config.Swarm = {
	MaxLocal = 160, -- hormigas dibujadas de tu colonia; si hay más, cada una representa a varias
	MaxOther = 24, -- hormigas dibujadas de cada colonia ajena
}

Config.Run = { Mult = 1.35 } -- correr: de serie, mientras mantienes Shift (o el botón, en táctil)
Config.Sprint = { Mult = 2.3, Duration = 3, Cooldown = 12 } -- turbo: la mejora del árbol
Config.Wings = { FlightTime = 1.4, Cooldown = 20 }
Config.Frenzy = { Mult = 3, Duration = 15, Cooldown = 90 }
Config.Combo = { Step = 0.03, Window = 1.6 } -- cada mordisco seguido suma un 3 %
Config.Egg = { Interval = 300, Seconds = 90 } -- huevo dorado: cada cuánto sale y cuántos segundos de colonia vale
Config.Fungus = { Regrow = 240, Duration = 45, Mult = 2 }
Config.Trophy = { Bonus = 0.03 } -- por cada tipo de comida terminado alguna vez

Config.Rebirth = {
	-- Jalea = floor(log10(comida de la partida / Divisor) ^ Power). Se puede enjambrar en cuanto da 1
	-- (diez veces el Divisor). Crece despacio a propósito: con 14 capas una potencia de la comida
	-- daba miles de jalea en una sola partida y llenaba el árbol real de golpe.
	Divisor = 1e12,
	Power = 2,
	TartaMult = 2, -- comerse la tarta entera duplica la jalea de esa partida
}

Config.Offline = {
	Efficiency = 0.5, -- la colonia rinde la mitad mientras no estás
}

Config.Save = {
	Store = "CrunchSave_v2",
	TopStore = "CrunchTop_v2",
	Interval = 60,
}

Config.GroundY = 0

-- Mapa: un jardín redondo con los hormigueros en arco al fondo y, hacia delante (-Z),
-- un túnel largo partido en zonas. Cada zona pide una capa más de profundidad en tu hormiguero.
Config.Map = {
	LobbyRadius = 150,
	HillArc = 122, -- radio del arco de hormigueros (unos 66 studs entre vecinos)
	HillFrom = 12, -- grados
	HillTo = 168,
	HillCount = 6,
	Half = 60, -- media anchura del túnel
}

-- La zona 2 empieza justo después del borde del jardín; cada una ocupa 170 studs del túnel
local function zone(id, name, theme, length, floor)
	local z0 = if id == 1 then 0 else -(Config.Map.LobbyRadius + 10 + (id - 2) * 170)
	return { id = id, name = name, theme = theme, z0 = z0, z1 = z0 - length, floor = floor }
end

-- Sitios por donde andaría una hormiga, cada vez más lejos de casa.
Config.Zones = {
	zone(1, "Jardín", "Jardin", 0, Color3.fromRGB(124, 200, 84)),
	zone(2, "Picnic", "Picnic", 150, Color3.fromRGB(255, 244, 222)),
	zone(3, "Huerto", "Huerto", 150, Color3.fromRGB(150, 104, 66)),
	zone(4, "Jungla", "Jungla", 150, Color3.fromRGB(58, 150, 74)),
	zone(5, "Playa", "Mar", 150, Color3.fromRGB(250, 224, 160)),
	zone(6, "Barbacoa", "Barbacoa", 150, Color3.fromRGB(214, 132, 92)),
	zone(7, "Cocina", "Cocina", 150, Color3.fromRGB(246, 236, 214)),
	zone(8, "Despensa", "Despensa", 150, Color3.fromRGB(236, 210, 160)),
	zone(9, "Nevera", "Nevera", 150, Color3.fromRGB(206, 232, 246)),
	zone(10, "Cuarto de juguetes", "Juguetes", 150, Color3.fromRGB(104, 150, 220)),
	zone(11, "Escritorio", "Escritorio", 150, Color3.fromRGB(70, 84, 104)),
	zone(12, "Feria", "Feria", 150, Color3.fromRGB(150, 146, 160)),
	zone(13, "Dulcelandia", "Dulce", 150, Color3.fromRGB(255, 190, 214)),
	zone(14, "Espacio", "Espacio", 240, Color3.fromRGB(34, 30, 66)),
}

-- Tres comidas por zona, en orden. La vida y el valor salen del puesto en la lista, así
-- toda la curva se ajusta con cuatro números. Lo que vale una comida entera es hp * value.
-- hard: hace falta la mandíbula sierra (tú) o el cuartel (obreras).
Config.FoodCurve = { Hp = 3, HpGrowth = 2.92, ValueGrowth = 1.64, BossHp = 20 }

local FOOD_LIST = {
	{ "Miga", "Miga" }, { "Semilla", "Pipa" }, { "Arandano", "Arándano" },
	{ "Galleta", "Galleta" }, { "Sandwich", "Sándwich" }, { "Manzana", "Manzana", true },
	{ "Fresa", "Fresa" }, { "Tomate", "Tomate" }, { "Zanahoria", "Zanahoria", true },
	{ "Uvas", "Uvas" }, { "Platano", "Plátano" }, { "Coco", "Coco", true },
	{ "Patatas", "Patatas fritas" }, { "Helado", "Helado" }, { "Sandia", "Sandía", true },
	{ "Mazorca", "Mazorca asada" }, { "Brocheta", "Brocheta" }, { "Costillas", "Costillas", true },
	{ "Azucar", "Cubo de azúcar" }, { "Huevo", "Huevo frito" }, { "Queso", "Queso" },
	{ "Cereales", "Cereales" }, { "Pan", "Pan de molde" }, { "Miel", "Tarro de miel", true },
	{ "Yogur", "Yogur" }, { "Sushi", "Sushi" }, { "Lata", "Lata de refresco", true },
	{ "Ganchitos", "Ganchitos" }, { "Zumo", "Zumo" }, { "Sorpresa", "Huevo sorpresa", true },
	{ "Cruasan", "Cruasán" }, { "Barrita", "Barrita de cereales" }, { "Nuez", "Nuez", true },
	{ "Palomita", "Palomitas" }, { "HotDog", "Perrito caliente" }, { "Hamburguesa", "Hamburguesa" },
	{ "Donut", "Donut" }, { "Cupcake", "Magdalena" }, { "Chocolate", "Chocolate", true },
	{ "Gominola", "Gominola" }, { "Pizza", "Pizza" }, { "Tarta", "Tarta" },
}

local function round2(n: number): number
	if n < 10 then
		return math.max(1, math.floor(n + 0.5))
	end
	local scale = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / scale + 0.5) * scale
end

local COUNTS = { 12, 7, 5 }
local RESPAWNS = { 5, 9, 14 } -- segundos hasta que reaparece cada comida de una zona

Config.Foods = {}
for i, entry in FOOD_LIST do
	local curve = Config.FoodCurve
	local slot = (i - 1) % 3 + 1
	local def = {
		id = entry[1],
		name = entry[2],
		hard = entry[3] == true,
		zone = (i - 1) // 3 + 1,
		hp = round2(curve.Hp * curve.HpGrowth ^ (i - 1)),
		value = round2(curve.ValueGrowth ^ (i - 1)),
		count = COUNTS[slot],
		respawn = RESPAWNS[slot],
	}
	if def.zone == 1 then
		-- El jardín es grande y es donde se empieza: más comida que en el túnel (la mitad, junto a
		-- los hormigueros; ver FoodService) y vuelve enseguida
		def.count = ({ 110, 40, 22 })[slot]
		def.respawn = ({ 1.5, 3, 5 })[slot]
	end
	if def.id == "Tarta" then
		def.boss = true
		def.hp *= curve.BossHp
		def.count = 1
		def.respawn = 45
	end
	table.insert(Config.Foods, def)
end

Config.FoodById = {}
for _, def in Config.Foods do
	Config.FoodById[def.id] = def
end

-- Árbol de mejoras: tu hormiguero en corte, por capas. Cada capa excavada abre una fila de cámaras,
-- sube el tope de las mejoras con `per` y abre la zona siguiente del túnel.
-- costo = cost * growth^nivel (o la lista `costs`). per: niveles disponibles por capa desde la suya.
-- needs = "workers": hace falta tener al menos una obrera.
-- Cada rama tiene una franja de 345 px: su pozo (cámaras grandes) y, a la derecha, las galerías
-- (cámaras pequeñas) en una rejilla de 3 x 3 por capa. La quinta rama (Aliadas) no tiene galerías:
-- solo su pozo, pegado al borde derecho.
Config.TreeLayout = {
	Width = 1600,
	Top = 290, -- y de la primera fila
	LayerHeight = 300,
	RowGap = 132,
	Regions = { M = 30, P = 375, C = 720, F = 1065, A = 1420 }, -- x donde empieza la franja de cada rama
	Shaft = 75, -- x del pozo dentro de su franja
	MiniColumns = { 170, 240, 310 }, -- x de las galerías dentro de su franja
	MiniRows = { -30, 50, 130 }, -- y de las galerías respecto a la primera fila de su capa
}

-- Una capa por zona: excavar la capa N abre la zona N.
Config.Layers = {
	"Mantillo", "Tierra húmeda", "Raíces", "Arcilla", "Arena", "Ceniza", "Grava",
	"Caliza", "Roca fría", "Pizarra", "Granito", "Roca viva", "Cristal", "El fondo",
}
Config.StageGrowth = 110 -- cada capa todo cuesta (y rinde) unas 110 veces más
Config.DigBase = 5000 -- excavar la capa 2; cada capa siguiente, StageGrowth veces más (subió de 3000 al llegar la abeja mensajera)
Config.CostScale = 0.5 -- abarata o encarece todo el árbol de golpe (ver tools/sim.py)

local BRANCH = { M = "Mandíbulas", P = "Patas", C = "Colonia", F = "Feromonas", A = "Aliadas" }

-- `cost` se escribe a escala de la capa 1 y se multiplica por StageGrowth^(capa - 1).
local function node(id, col, layer, row, def)
	local layout = Config.TreeLayout
	local stage = Config.StageGrowth ^ (layer - 1)
	def.id = id
	def.branch = BRANCH[col]
	def.layer = layer
	def.x = layout.Regions[col] + layout.Shaft
	def.y = layout.Top + (layer - 1) * layout.LayerHeight + (row - 1) * layout.RowGap
	if def.cost then
		def.cost *= stage * Config.CostScale
	end
	return def
end

Config.Tree = {
	-- Mandíbulas
	node("bite", "M", 1, 1, { name = "Mordida fuerte", desc = "Cada mordisco arranca más.", max = 140, per = 10, cost = 10, growth = 1.6 }),
	node("chew", "M", 1, 2, { name = "Mordisco veloz", desc = "Muerdes más seguido.", max = 28, per = 2, cost = 80, growth = 10.5, parent = "bite", icon = "bite" }),
	node("crit", "M", 2, 1, { name = "Mordida doble", desc = "A veces muerdes mucho más fuerte.", max = 5, cost = 30, growth = 3.5, parent = "chew" }),
	node("saw", "M", 2, 2, { name = "Mandíbula sierra", desc = "Puedes morder comida dura: manzanas, cocos, latas.", max = 1, cost = 300, growth = 1, parent = "crit" }),
	node("combo", "M", 3, 1, { name = "Racha", desc = "Cada mordisco seguido pega un poco más. Si paras, se pierde.", max = 5, cost = 40, growth = 5, parent = "saw", icon = "crit" }),
	node("reach", "M", 4, 1, { name = "Cuello largo", desc = "Alcanzas la comida desde más lejos.", max = 4, cost = 40, growth = 6, parent = "combo", icon = "area" }),
	node("area", "M", 5, 1, { name = "Mordida en área", desc = "Tu mordisco alcanza también la comida cercana.", max = 3, cost = 40, growth = 8, parent = "reach" }),
	node("brutal", "M", 6, 1, { name = "Mordisco brutal", desc = "La mordida doble pega todavía más.", max = 5, cost = 40, growth = 5, parent = "area", icon = "crit" }),
	node("venom", "M", 7, 1, { name = "Saliva ácida", desc = "La comida dura se deshace: la muerdes mucho más rápido.", max = 5, cost = 40, growth = 5, parent = "brutal", icon = "saw" }),
	node("titan", "M", 8, 1, { name = "Mandíbula titán", desc = "Tu mordida se duplica.", max = 5, cost = 50, growth = 8, parent = "venom", icon = "saw" }),

	-- Patas
	node("speed", "P", 1, 1, { name = "Paso rápido", desc = "Caminas más rápido.", max = 42, per = 3, cost = 24, growth = 4.8 }),
	node("carry", "P", 1, 2, { name = "Lomo fuerte", desc = "Cargas más trozos por viaje.", max = 140, per = 10, cost = 10, growth = 1.6, parent = "speed" }),
	node("sprint", "P", 2, 1, { name = "Turbo", desc = "Un acelerón corto a más del doble de velocidad. Correr normal ya lo tienes.", max = 1, cost = 45, growth = 1, parent = "carry", hint = "{tecla} para meter el turbo", key = "Z", button = "Turbo" }),
	node("stamina", "P", 2, 2, { name = "Resuello", desc = "El turbo dura más.", max = 5, cost = 70, growth = 4, parent = "sprint", icon = "sprint" }),
	node("wings", "P", 3, 1, { name = "Alas", desc = "Vuelas a tu hormiguero. Y desde casa, a tu zona más lejana.", max = 1, cost = 170, growth = 1, parent = "stamina", hint = "{tecla} y vuelvo volando a casa. Desde casa, vuelo a mi zona más lejana", key = "R", button = "Volar" }),
	node("landing", "P", 4, 1, { name = "Vuelo corto", desc = "Las alas se recuperan antes.", max = 5, cost = 45, growth = 4, parent = "wings", icon = "wings" }),
	node("fullLoad", "P", 5, 1, { name = "Carga completa", desc = "Si entregas con la carga llena, vale más.", max = 5, cost = 40, growth = 5, parent = "landing", icon = "carry" }),
	node("giant", "P", 7, 1, { name = "Hormiga gigante", desc = "Creces. Y cargas el triple.", max = 3, cost = 60, growth = 30, parent = "fullLoad", icon = "carry" }),
	node("double", "P", 9, 1, { name = "Reparto doble", desc = "A veces una entrega vale el doble.", max = 5, cost = 40, growth = 5, parent = "giant", icon = "carry" }),

	-- Colonia
	node("nursery", "C", 1, 1, { name = "Guardería", desc = "Espacio para criar obreras. Cada nivel caben más.", max = 28, per = 2, cost = 36, growth = 10.5 }),
	node("workers", "C", 1, 2, { name = "Obreras", desc = "Traen comida solas, sin que hagas nada.", unit = true, parent = "nursery" }),
	node("workerSpeed", "C", 2, 1, { name = "Obreras rápidas", desc = "Tus obreras caminan más rápido.", max = 12, per = 2, cost = 35, growth = 10.5, parent = "workers" }),
	node("workerCarry", "C", 2, 2, { name = "Obreras fuertes", desc = "Cada obrera carga más por viaje.", max = 52, per = 4, cost = 200, growth = 3.24, parent = "workerSpeed" }),
	node("storage", "C", 3, 1, { name = "Almacén", desc = "La colonia sigue trabajando mientras no estás.", max = 5, cost = 50, growth = 9, parent = "workerCarry" }),
	node("nurse", "C", 3, 2, { name = "Nodrizas", desc = "Criar obreras cuesta menos.", max = 5, cost = 55, growth = 4, parent = "storage", icon = "nursery" }),
	node("barracks", "C", 4, 1, { name = "Cuartel", desc = "Soldados que rompen comida dura y aceleran a toda la colonia.", max = 5, cost = 60, growth = 12, parent = "nurse" }),
	node("eggs", "C", 4, 2, { name = "Huevos dorados", desc = "Cada cierto tiempo aparece un huevo dorado junto a tu hormiguero. Písalo.", max = 5, cost = 40, growth = 6, parent = "barracks", icon = "nursery" }),
	node("queen", "C", 5, 1, { name = "Reina ponedora", desc = "La reina cría obreras sola cuando hay comida de sobra.", max = 1, cost = 70, growth = 1, parent = "eggs" }),
	node("fungus", "C", 6, 1, { name = "Jardín de hongos", desc = "Crecen hongos junto a tu hormiguero. Cómete uno y toda la comida vale el doble un rato.", max = 5, cost = 50, growth = 6, parent = "queen", icon = "storage" }),
	node("legion", "C", 7, 1, { name = "Legión", desc = "La colonia entera trabaja más.", max = 10, cost = 45, growth = 4, parent = "fungus", icon = "barracks" }),
	node("super", "C", 9, 1, { name = "Supercolonia", desc = "Cada obrera carga el doble.", max = 5, cost = 50, growth = 6, parent = "legion", icon = "workerCarry" }),

	-- Feromonas
	node("trail", "F", 1, 1, { name = "Rastro", desc = "Marcas una comida y las obreras van por ella. Cada nivel, un rastro más.", max = 3, costs = { 250, 3e6, 4e12 }, needs = "workers", hint = "{tecla} junto a una comida y mis obreras irán por ella", key = "F", button = "Rastro" }),
	node("sweet", "F", 2, 1, { name = "Feromona dulce", desc = "Las obreras rinden más en la comida que marcas tú.", max = 5, cost = 70, growth = 5, parent = "trail", icon = "trail" }),
	node("frenzy", "F", 3, 1, { name = "Frenesí", desc = "Toda la colonia trabaja al triple durante unos segundos.", max = 1, cost = 120, growth = 1, parent = "sweet", hint = "{tecla} y la colonia se vuelve loca", key = "G", button = "Frenesí" }),
	node("frenzyLen", "F", 4, 1, { name = "Frenesí largo", desc = "El frenesí dura más.", max = 5, cost = 60, growth = 5, parent = "frenzy", icon = "frenzy" }),
	node("smart", "F", 5, 1, { name = "Rastro listo", desc = "Las obreras sin rastro eligen solas la mejor comida.", max = 1, cost = 100, growth = 1, parent = "frenzyLen" }),
	node("express", "F", 6, 1, { name = "Autopista", desc = "Las obreras tardan menos en cada viaje.", max = 5, cost = 40, growth = 5, parent = "smart", icon = "workerSpeed" }),
	node("hive", "F", 8, 1, { name = "Mente colmena", desc = "El frenesí se recupera antes.", max = 5, cost = 40, growth = 5, parent = "express", icon = "smart" }),
	node("royalPher", "F", 10, 1, { name = "Feromona real", desc = "El frenesí es todavía más fuerte.", max = 3, cost = 40, growth = 10, parent = "hive", icon = "frenzy" }),

	-- Aliadas: bichos y cachivaches que trabajan contigo y se ven en el mundo (ver Config.Allies).
	-- Un juguete nuevo casi en cada capa; cada nivel se abre con la capa siguiente (per = 1).
	node("bee", "A", 2, 1, { name = "Abeja mensajera", desc = "Una abeja viene a por tu carga y la lleva volando a tu hormiguero.", max = 6, per = 1, cost = 60, growth = 100, icon = "wings" }),
	node("magnet", "A", 3, 1, { name = "Imán de migas", desc = "Las migas pequeñas que pasan cerca saltan solas a tus mandíbulas.", max = 5, per = 1, cost = 50, growth = 100, parent = "bee", icon = "royalFood" }),
	node("beetle", "A", 4, 1, { name = "Escarabajo de carga", desc = "Un escarabajo te sigue y carga lo que ya no te cabe.", max = 5, per = 1, cost = 50, growth = 100, parent = "magnet", icon = "carry" }),
	node("escort", "A", 5, 1, { name = "Escolta", desc = "Soldados pequeños que van contigo y muerden lo que muerdes tú.", max = 5, per = 1, cost = 50, growth = 100, parent = "beetle", icon = "barracks" }),
	node("stomp", "A", 6, 1, { name = "Pisotón", desc = "Un pisotón que muerde toda la comida de alrededor a la vez.", max = 5, per = 1, cost = 60, growth = 100, parent = "escort", icon = "area", hint = "{tecla} y doy un pisotón que muerde todo alrededor", key = "X", button = "Pisotón" }),
	node("sling", "A", 7, 1, { name = "Tirachinas", desc = "Lanzas toda tu carga de un tirón hasta tu hormiguero.", max = 5, per = 1, cost = 60, growth = 100, parent = "stomp", icon = "speed", hint = "{tecla} y lanzo la carga a mi hormiguero", key = "C", button = "Lanzar" }),
	node("lens", "A", 9, 1, { name = "Lupa solar", desc = "Una lupa quema de vez en cuando un buen trozo de la comida más grande que tengas cerca.", max = 5, per = 1, cost = 50, growth = 100, parent = "sling", icon = "smart" }),
	node("mega", "A", 11, 1, { name = "Mega crunch", desc = "Si muerdes sin parar, cada cierto número de mordiscos llega uno gigante.", max = 4, per = 1, cost = 60, growth = 100, parent = "lens", icon = "royalBite" }),
}

-- Números de las Aliadas. Los niveles se traducen a estadísticas en Stats.derive.
Config.Allies = {
	-- Viene cada Interval s (Step menos por nivel, nunca menos de MinInterval) si llevas al menos
	-- MinLoad de tu carga; desde el nivel FullAt también en cuanto te llenas. Vuela de verdad, a
	-- Speed studs/s (SpeedStep más por nivel; cada tramo dura al menos MinFly s), y no vuelve a por
	-- otra carga hasta regresar: lejos de casa ayuda menos. Es la mejora que más mueve el ritmo
	-- (es un segundo porteador): antes de tocar Speed, mira tools/sim.py.
	Bee = { Interval = 45, Step = 6.6, MinInterval = 12, MinLoad = 0.5, FullAt = 4, Speed = 14, SpeedStep = 3, MinFly = 1.6, Approach = 0.45 },
	-- Cada Tick s se traga hasta Count comidas a Radius studs que caerían en Bites mordiscos tuyos
	Magnet = { Tick = 0.6, Radius = 9, RadiusStep = 3, Bites = 2, Count = 2 },
	Beetle = { Share = 0.4 }, -- carga extra por nivel, sobre la tuya
	-- Mientras muerdes (y Linger s después), cada Tick s cada soldado arranca Share de tu mordida
	Escort = { Tick = 0.7, Share = 0.3, Linger = 1.5 },
	Stomp = { Cooldown = 30, Step = 4, Radius = 12, RadiusStep = 2, Mult = 3 },
	Sling = { Cooldown = 40, Step = 5, Range = 400, RangeStep = 200, FlyTime = 2 },
	-- Cada Interval s quema Mult mordiscos de la comida más grande a Radius studs. La comida va directa a casa.
	Lens = { Interval = 20, Step = 2, Radius = 40, Mult = 4, MultStep = 2, Delay = 0.9 },
	-- Cada Every mordiscos seguidos, uno que pega Mult veces y salpica a Radius studs
	Mega = { Every = 25, Step = 3, Mult = 10, MultStep = 5, Radius = 10 },
}

-- Dos niveles de guardería por capa
Config.NurseryCaps = {
	5, 10, 20, 35, 60, 100, 150, 220, 300, 400, 500, 620, 750, 900,
	1050, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600, 2800, 3000, 3200, 3400, 3600,
}
Config.StorageHours = { 1, 2, 4, 8, 12 }

-- Galerías: cámaras pequeñas de un solo nivel, 9 por rama en cada capa (504 en total). Se generan solas
-- a partir de esta tabla. Cada fila de tres se excava desde el pozo hacia fuera: cada cámara pide la
-- anterior de su fila, y la primera solo pide la capa excavada. Dentro de un tipo las cantidades se
-- suman y luego multiplican (ver Stats.derive). Antes de tocar números, mira tools/sim.py.
Config.MiniTune = {
	Span = { 15, 600 }, -- costo de la galería más barata y de la más cara de una capa, a escala de capa 1
	BranchCost = { M = 1, P = 1.1, C = 1.2, F = 0.9 },
	Rotate = 4, -- en cada capa los tipos se corren estos huecos, para que no caigan siempre en el mismo sitio
	GoldCap = 0.2, -- probabilidad máxima de mordisco dorado
	GoldMult = 10, -- lo que vale la comida de un mordisco dorado
	BuyAllShare = 0.5, -- "Comprar lo barato" gasta como mucho esta parte de la comida que tenías
	-- Paladar (zonePct): lo que sube la comida de la zona de esa capa. Va por capa porque solo
	-- sirve mientras comes allí; es lo que más mueve el ritmo de cada capa.
	Zone = { 0.15, 0.3, 0.1, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05 },
	-- text: {p} porcentaje, {n} número, {z} zona. names: se alternan; %s es la zona.
	Kinds = {
		bitePct = { amount = 0.08, icon = "bite", text = "Mordida +{p}", names = { "Colmillo afilado", "Mandíbula prieta", "Diente de sierra" } },
		chewPct = { amount = 0.03, icon = "royalBite", text = "Ritmo de mordisco +{p}", names = { "Masticar rápido", "Ñam ñam", "Mandíbula suelta" } },
		critPct = { amount = 0.01, icon = "crit", text = "+{p} de mordida doble", names = { "Ojo certero", "Punto débil", "Golpe de suerte" } },
		hardPct = { amount = 0.15, icon = "saw", text = "Comida dura +{p}", names = { "Rompecáscaras", "Diente de piedra", "Pico duro" } },
		zonePct = { icon = "royalFood", text = "Comida de {z} +{p}", names = { "Paladar: %s", "Antojo de %s", "Receta de %s" } },
		goldPct = { amount = 0.002, icon = "queen", text = "+{p} de mordisco dorado", names = { "Brillo dorado", "Pepita", "Toque de oro" } },
		speedPct = { amount = 0.03, icon = "speed", text = "Velocidad +{p}", names = { "Patas ligeras", "Zancada", "Pasito rápido" } },
		carryPct = { amount = 0.02, icon = "carry", text = "Carga +{p}", names = { "Lomo ancho", "Mochila", "Carga extra" } },
		depositPct = { amount = 0.02, icon = "anthill", text = "Cada entrega +{p}", names = { "Buena entrega", "Despensa ordenada", "Reparto fino" } },
		workerPct = { amount = 0.03, icon = "royalColony", text = "Colonia +{p}", names = { "Obreras motivadas", "Turno extra", "Buen equipo" } },
		capPlus = { amount = 2, perLayer = true, icon = "workers", text = "Guardería +{n} plazas", names = { "Cuna nueva", "Literas", "Ala de cría" } },
		cheapPct = { amount = 0.04, icon = "royalStart", text = "Obreras un {p} más baratas", names = { "Cría barata", "Papilla", "Nodriza novata" } },
		eggPct = { amount = 0.1, icon = "nursery", text = "Huevo dorado +{p}", names = { "Nido dorado", "Cáscara gruesa", "Yema rica" } },
		offlinePct = { amount = 0.1, icon = "storage", text = "Colonia sin ti +{p}", names = { "Turno de noche", "Despensa llena", "Vigilantes" } },
		trailPct = { amount = 0.03, icon = "trail", text = "Comida marcada +{p}", names = { "Rastro fresco", "Olor dulce", "Marca clara" } },
		frenzyPct = { amount = 0.03, icon = "frenzy", text = "Frenesí +{p}", names = { "Euforia", "Tambores", "Grito de guerra" } },
		jellyPct = { amount = 0.02, icon = "royalFood", text = "Jalea +{p}", names = { "Gota real", "Jalea pura", "Panal" } },
		foodPct = { amount = 0.01, icon = "smart", text = "Toda la comida +{p}", names = { "Buen olfato", "Sabor intenso", "Banquete" } },
	},
	-- Los 9 huecos de cada rama, del más barato al más caro (antes de correrlos con Rotate).
	Pools = {
		M = { "bitePct", "chewPct", "zonePct", "critPct", "bitePct", "hardPct", "goldPct", "bitePct", "zonePct" },
		P = { "carryPct", "zonePct", "speedPct", "zonePct", "carryPct", "zonePct", "depositPct", "zonePct", "zonePct" },
		C = { "workerPct", "capPlus", "cheapPct", "eggPct", "workerPct", "offlinePct", "capPlus", "eggPct", "cheapPct" },
		F = { "foodPct", "trailPct", "jellyPct", "frenzyPct", "goldPct", "trailPct", "jellyPct", "frenzyPct", "jellyPct" },
	},
}

local function percentText(x: number): string
	local p = x * 100
	local whole = math.floor(p + 0.5)
	if math.abs(p - whole) < 1e-6 then
		return whole .. " %"
	end
	return (string.format("%.1f", p):gsub("%.", ",")) .. " %"
end

-- Texto de un efecto de galería con una cantidad dada (la de una cámara o el total de su tipo).
function Config.miniText(kind: string, amount: number, layer: number): string
	local zone = Config.Zones[layer]
	local values = {
		p = percentText(amount),
		n = tostring(math.floor(amount + 0.5)),
		z = if zone then zone.name else "",
	}
	return (Config.MiniTune.Kinds[kind].text:gsub("{(%a)}", function(key)
		return values[key]
	end))
end

Config.Minis = {}
Config.MiniById = {}
do
	local tune = Config.MiniTune
	local layout = Config.TreeLayout
	local ratio = tune.Span[2] / tune.Span[1]
	for layer = 1, #Config.Layers do
		local stage = Config.StageGrowth ^ (layer - 1) * Config.CostScale
		local y0 = layout.Top + (layer - 1) * layout.LayerHeight
		for _, key in { "M", "P", "C", "F" } do
			local pool = tune.Pools[key]
			local seen = {} -- cuántas de cada tipo van en esta capa, para no repetir nombre
			for slot = 1, 9 do
				local row = (slot - 1) // 3 + 1
				local col = (slot - 1) % 3 + 1
				local kind = pool[(slot - 1 + (layer - 1) * tune.Rotate) % #pool + 1]
				local info = tune.Kinds[kind]
				local amount = if kind == "zonePct" then tune.Zone[layer] elseif info.perLayer then info.amount * layer else info.amount
				seen[kind] = (seen[kind] or 0) + 1
				local name = info.names[(layer + seen[kind]) % #info.names + 1]
				local def = {
					id = "m" .. key .. layer .. "_" .. slot,
					key = key,
					branch = BRANCH[key],
					layer = layer,
					row = row,
					col = col,
					slot = slot,
					x = layout.Regions[key] + layout.MiniColumns[col],
					y = y0 + layout.MiniRows[row],
					kind = kind,
					amount = amount,
					-- De 15 a 600 a lo largo de los 9 huecos: siempre queda alguna barata
					cost = round2(tune.Span[1] * ratio ^ ((slot - 1) / 8) * tune.BranchCost[key] * stage),
					icon = info.icon,
					name = if kind == "zonePct" then string.format(name, Config.Zones[layer].name) else name,
					desc = Config.miniText(kind, amount, layer),
					prev = if col > 1 then "m" .. key .. layer .. "_" .. (slot - 1) else nil,
				}
				def.index = #Config.Minis + 1
				table.insert(Config.Minis, def)
				Config.MiniById[def.id] = def
			end
		end
	end
end

-- Las mismas galerías de la más barata a la más cara: así compra "Comprar lo barato".
-- Dentro de una fila cada una cuesta más que la anterior, así que nunca sale antes que la que pide.
Config.MinisByCost = table.clone(Config.Minis)
table.sort(Config.MinisByCost, function(a, b)
	if a.cost ~= b.cost then
		return a.cost < b.cost
	end
	return a.index < b.index
end)

-- Árbol Real: se paga con Jalea y nunca se pierde. costo = cost + step * nivel.
Config.Royal = {
	{ id = "royalFood", name = "Jalea nutritiva", desc = "Toda la comida vale más.", max = 20, cost = 1, step = 1 },
	{ id = "royalBite", name = "Mandíbulas reales", desc = "Tu mordida se duplica.", max = 10, cost = 3, step = 3 },
	{ id = "royalColony", name = "Linaje fuerte", desc = "La colonia entera trabaja más rápido.", max = 10, cost = 3, step = 3 },
	{ id = "royalStart", name = "Nido heredado", desc = "Empiezas cada partida con obreras.", max = 10, cost = 2, step = 2 },
	{ id = "royalSpeed", name = "Patas reales", desc = "Caminas más rápido para siempre.", max = 5, cost = 2, step = 1 },
	{ id = "royalDepth", name = "Planos del nido", desc = "Empiezas cada partida con capas ya excavadas.", max = 7, cost = 4, step = 4, icon = "anthill" },
	{ id = "royalJelly", name = "Jalea espesa", desc = "Ganas más jalea al enjambrar.", max = 10, cost = 2, step = 2, icon = "royalFood" },
}

-- Vestidor: se paga con comida y es para siempre, también tras enjambrar.
Config.Skins = {
	{ id = "rojo", name = "Roja", cost = 0, color = Color3.fromRGB(232, 62, 48) },
	{ id = "negra", name = "Negra", cost = 2e4, color = Color3.fromRGB(58, 52, 60) },
	{ id = "azul", name = "Azul", cost = 5e5, color = Color3.fromRGB(62, 140, 243) },
	{ id = "verde", name = "Verde", cost = 2e7, color = Color3.fromRGB(96, 196, 84) },
	{ id = "morada", name = "Morada", cost = 1e9, color = Color3.fromRGB(160, 96, 230) },
	{ id = "rosa", name = "Rosa", cost = 5e10, color = Color3.fromRGB(255, 130, 180) },
	{ id = "dorada", name = "Dorada", cost = 5e12, color = Color3.fromRGB(255, 200, 60) },
}

Config.Hats = {
	{ id = "ninguno", name = "Nada", cost = 0 },
	{ id = "hoja", name = "Hoja", cost = 5e3 },
	{ id = "lazo", name = "Lazo", cost = 2e5 },
	{ id = "chistera", name = "Chistera", cost = 1e7 },
	{ id = "gafas", name = "Gafas de sol", cost = 5e8 },
	{ id = "casco", name = "Casco", cost = 2e10 },
	{ id = "corona", name = "Corona", cost = 1e12 },
}

-- Estelas: el rastro que deja tu hormiga al andar. pass: solo con ese pase de juego.
Config.Trails = {
	{ id = "sin", name = "Ninguna", cost = 0 },
	{ id = "polvo", name = "Polvo", cost = 1e4, colors = { Color3.fromRGB(214, 168, 116), Color3.fromRGB(150, 98, 60) } },
	{ id = "azucar", name = "Azúcar", cost = 1e6, colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 230, 255) } },
	{ id = "fuego", name = "Fuego", cost = 1e9, colors = { Color3.fromRGB(255, 220, 80), Color3.fromRGB(230, 57, 70) } },
	{ id = "arcoiris", name = "Arcoíris", cost = 1e13, colors = { Color3.fromRGB(230, 57, 70), Color3.fromRGB(255, 210, 63), Color3.fromRGB(110, 200, 90), Color3.fromRGB(62, 193, 243), Color3.fromRGB(160, 96, 230) } },
	{ id = "oro", name = "Oro VIP", cost = 0, pass = "vip", colors = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 190, 40) } },
}

-- Microtransacciones. Crea cada pase y producto en el panel de creador de Roblox
-- (Monetización) y pega aquí su id. Con id = 0 el artículo no aparece en la tienda
-- (en Studio se listan todos para poder revisarla).
-- Pases: se compran una vez y son para siempre. robux es solo el precio sugerido al crearlos.
Config.Passes = {
	{ id = "x2Food", passId = 0, robux = 199, name = "Comida doble", desc = "Toda la comida vale el doble, para siempre." },
	{ id = "autoBite", passId = 0, robux = 149, name = "Mordida automática", desc = "Tu hormiga muerde sola en cuanto tiene comida a tiro." },
	{ id = "fastColony", passId = 0, robux = 149, name = "Colonia veloz", desc = "Tus obreras trabajan al doble, para siempre." },
	{ id = "goldWings", passId = 0, robux = 129, name = "Alas doradas", desc = "Alas desde el primer minuto y casi sin espera entre vuelos." },
	{ id = "vip", passId = 0, robux = 299, name = "VIP", desc = "Un 25 % más de comida, estela de oro y tu cartel con estrella." },
	{ id = "x2Jelly", passId = 0, robux = 249, name = "Jalea doble", desc = "Cada enjambre te da el doble de jalea." },
	{ id = "turbo", passId = 0, robux = 99, name = "Patas turbo", desc = "Caminas un 30 % más rápido, para siempre." },
	{ id = "bigStore", passId = 0, robux = 99, name = "Despensa sin fondo", desc = "La colonia trabaja 24 horas sin ti, y al 100 %." },
}

-- Productos: se pueden comprar las veces que quieras.
Config.Products = {
	{ id = "potion", productId = 0, robux = 39, name = "Poción x2", desc = "Toda la comida vale el doble durante 30 minutos. Se acumula." },
	{ id = "sack", productId = 0, robux = 29, name = "Saco de comida", desc = "15 minutos de trabajo de tu colonia, de golpe." },
	{ id = "bigSack", productId = 0, robux = 99, name = "Carretilla", desc = "2 horas de trabajo de tu colonia, de golpe." },
	{ id = "shovel", productId = 0, robux = 149, name = "Pala dorada", desc = "Excava la capa siguiente ahora mismo, sin pagar comida." },
	{ id = "frenzy", productId = 0, robux = 19, name = "Frenesí ya", desc = "Un minuto de frenesí al instante." },
	{ id = "egg", productId = 0, robux = 25, name = "Huevo dorado", desc = "Un huevo dorado junto a tu hormiguero, ya." },
	{ id = "jar", productId = 0, robux = 49, name = "Tarro de jalea", desc = "5 de jalea real." },
	{ id = "bigJar", productId = 0, robux = 199, name = "Barril de jalea", desc = "30 de jalea real." },
}

local function index(list)
	local map = {}
	for _, def in list do
		map[def.id] = def
	end
	return map
end

Config.NodeById = index(Config.Tree)
Config.RoyalById = index(Config.Royal)
Config.SkinById = index(Config.Skins)
Config.HatById = index(Config.Hats)
Config.TrailById = index(Config.Trails)

return Config
