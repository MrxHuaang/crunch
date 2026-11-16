-- Todos los números de balance y textos del juego viven aquí. Cambia valores sin tocar lógica.

local Config = {}

-- Antes de tocar estos números, mira tools/sim.py (simula el bucle de ir, morder, llenarse y volver).
Config.Player = {
	WalkSpeed = 16, -- subió de 12: las zonas son más grandes. Paso rápido suma SpeedStep por nivel
	SpeedStep = 1.2,
	-- Techo de la velocidad al andar (sin correr): las zonas miden 230. Lo que las mejoras den de más
	-- se vuelve comida: x(velocidad de las mejoras / MaxWalk) ^ SpeedYield (Stats.derive)
	MaxWalk = 45,
	SpeedYield = 0.5,
	BiteCooldown = 0.3,
	-- Mordisco veloz multiplica el enfriamiento por ChewStep por nivel; por debajo de MinBiteCooldown ya no
	-- muerdes más rápido: lo que sobra se vuelve comida (Stats.derive, chewYield)
	MinBiteCooldown = 0.18,
	ChewStep = 0.88,
	BiteRange = 6, -- distancia máxima al borde de la comida
	-- Mordida: cada nivel de Mordida fuerte multiplica tu fuerza de mordida por BitePower. Una parte
	-- (BiteSplit) es arrancar más trozos por mordisco; el resto es que cada trozo rinda más (va al
	-- multiplicador de comida). Así subir la mordida se nota siempre en el ingreso, pero la comida de tu
	-- zona sigue pidiendo varios mordiscos. BiteBase: trozos del primer mordisco.
	BiteBase = 3,
	BitePower = 1.2,
	BiteSplit = 0.42,
	-- Carga (en trozos): Capacity * CarryGrowth^nivel de Lomo fuerte, multiplicada por todo lo que hace
	-- morder mejor (Stats.harvest). Nunca baja de MinLoadBites mordiscos normales.
	Capacity = 42, -- 14 mordiscos de 3 trozos
	CarryGrowth = 1.08, -- cada nivel de Lomo fuerte, +8 % de carga
	MinLoadBites = 12,
	CritMult = 3,
	CritStep = 0.05, -- Mordida doble: probabilidad por nivel
	CritCap = 0.35,
	BrutalStep = 0.5, -- Mordisco brutal: lo que pega de más la mordida doble por nivel
	VenomStep = 0.25, -- Saliva ácida: mordida contra comida dura por nivel
	AreaShare = 0.5, -- Mordida en área: parte del mordisco que se lleva cada comida vecina
	TitanPower = 1.3, -- Mandíbula titán: tu comida rinde x esto por nivel (antes x2 de mordida)
	GiantCarry = 1.15, -- Hormiga gigante: carga x esto por nivel (antes x3: los viajes no acababan nunca)
	-- Lo que arrancan a las comidas de al lado área, doble mandíbula, cadena, escolta y mega crunch, todo
	-- junto, como mucho NeighborCap veces lo de tu mordisco (si no, una pulsación se comía el racimo
	-- entero). Lo que pase del tope se vuelve comida: x(lo que darían / NeighborCap) ^ NeighborYield.
	NeighborCap = 2.5,
	NeighborYield = 0.5,
}

-- Hitos: al llegar a estos niveles, Mordida fuerte, Lomo fuerte y Obreras fuertes dan un salto. La
-- mordida y las obreras se multiplican por Mult; la carga por CarryMult (si saltara x2, los viajes se
-- alargarían sin fin). Stats.milestones(nivel) dice cuántos hitos lleva un nivel.
Config.Milestones = { Levels = { 10, 25, 50, 75, 100, 125 }, Mult = 2, CarryMult = 1.15 }

Config.Anthill = {
	DepositRadius = 11, -- se multiplica por la escala del hormiguero
}

Config.Worker = {
	Speed = 16, -- subió de 8: las zonas son más largas
	SpeedStep = 0.1, -- Obreras rápidas: velocidad por nivel (antes 0.3; con hormigueros de zona el viaje es corto)
	Carry = 1,
	CarryGrowth = 1.18, -- Obreras fuertes: carga por nivel (más los hitos)
	TurnTime = 1.5, -- segundos que pierde cada obrera por viaje entre morder y soltar
	BaseCost = 200, -- la primera obrera llega hacia los tres minutos
	CostGrowth = 1.03,
}

-- Multiplicadores de la colonia por nivel (Stats.derive). Spread: lo que no cabe en la comida marcada
-- (tope de su vida cada 3 s) pasa a tantas comidas de su racimo (src/server/Colony.luau).
Config.Colony = {
	Barracks = 1.15,
	Legion = 1.05, -- (y +3 % de comida por nivel: Config.Tree yield)
	Super = 1.35, -- Supercolonia: carga de cada obrera
	Express = 0.92, -- Autopista: lo que dura cada viaje (antes 0.85)
	Sweet = 0.1, -- Feromona dulce: la comida marcada rinde esto más (antes 0.4)
	Queen = 1.15, -- con la reina, la colonia rinde esto más
	Smart = 1.25, -- con el rastro listo, la comida marcada rinde esto más
	NurseCap = 0.15, -- Nodrizas: cupo de guardería por nivel
	Spread = 4,
}

Config.Swarm = {
	MaxLocal = 160, -- hormigas dibujadas de tu colonia; si hay más, cada una representa a varias
	MaxOther = 24, -- hormigas dibujadas de cada colonia ajena
}

Config.Run = { Mult = 1.35 } -- correr: de serie, mientras mantienes Shift (o el botón, en táctil)
Config.Sprint = { Mult = 2.3, Duration = 3, Cooldown = 12, StaminaStep = 4 } -- turbo: la mejora del árbol
-- Vuelo corto, por nivel: LandingStep s menos de espera y LandingSpeed más de velocidad al andar
Config.Wings = { FlightTime = 1.4, Cooldown = 12, LandingStep = 1.5, LandingSpeed = 0.08 }
Config.Frenzy = { Mult = 3, Duration = 20, Cooldown = 90, LenStep = 8, HiveStep = 15 } -- LenStep: Frenesí largo; HiveStep: Mente colmena
-- Cada mordisco seguido suma un 3 %. Typical: racha media que cuenta para la carga (se pierde al caminar)
Config.Combo = { Step = 0.03, Window = 1.6, Typical = 8 }
-- Huevo dorado: cada Interval s (IntervalStep menos por nivel, nunca menos de MinInterval) vale Seconds
-- s de colonia (SecondsStep más por nivel) o, como poco, FloorBites mordiscos a la comida pequeña de tu zona
-- PaidSeconds y PaidFloor: el huevo comprado (producto "egg"), como un saco pequeño: 10 min de colonia
-- (el saco, 15 por 29 R$) y como poco PaidFloor mordiscos. El del árbol usa Seconds y FloorBites.
Config.Egg = { Interval = 300, IntervalStep = 15, MinInterval = 210, Seconds = 15, SecondsStep = 4, FloorBites = 300, PaidSeconds = 600, PaidFloor = 200 }
Config.Fungus = { Regrow = 300, Duration = 15, Step = 3, Mult = 2 }
Config.Trophy = { Bonus = 0.03 } -- por cada tipo de comida terminado alguna vez

-- Comida dorada: al aparecer, cada comida (nunca la tarta) sale dorada con Chance, más ChanceStep por
-- nivel de "Olfato dorado" (el más alto entre las jugadoras conectadas). Vale Mult veces; a quien
-- tiene la mejora, MultStep más por cada nivel suyo.
Config.GoldFood = { Chance = 0.02, ChanceStep = 0.004, Mult = 5, MultStep = 1.5 }
-- Mordida en cadena: al terminar una comida, un rayo salta a la más cercana a Range studs (de borde a
-- borde: los racimos la dejan siempre a tiro) y le arranca First mordiscos tuyos; cada salto siguiente,
-- Share del anterior, tantas veces como niveles. Typical: mordiscos de una comida típica (para contar
-- la cadena en la carga, Stats.harvest).
Config.Chain = { Range = 14, Share = 0.7, First = 3, Typical = 8 }
-- Túnel exprés: el viaje dura Travel s (lo que tardas en asomar por el otro lado) y luego hay que
-- esperar Cooldown s. Reach: a cuántos studs del agujero tienes que estar.
Config.Tunnel = { Travel = 0.4, Cooldown = 3, Reach = 12 }

Config.Rebirth = {
	-- Jalea = floor(log10(comida de la partida / Divisor) ^ Power). Se puede enjambrar en cuanto da 1
	-- (diez veces el Divisor). Crece despacio a propósito: con 14 capas una potencia de la comida
	-- daba miles de jalea en una sola partida y llenaba el árbol real de golpe.
	Divisor = 3e12, -- subió de 1e12 con los costos nuevos (CostScale x15): el primer enjambre llega hacia la capa 7
	Power = 2,
	TartaMult = 2, -- comerse la tarta entera duplica la jalea de esa partida
	StartWorkers = 15, -- Nido heredado: obreras por nivel (antes 5; casi no se notaba)
	SpeedStep = 0.15, -- Patas reales: velocidad por nivel (antes 0.08)
}

Config.Offline = {
	Efficiency = 0.5, -- la colonia rinde la mitad mientras no estás
}

Config.Save = {
	Store = "CrunchSave_v3",
	TopStore = "CrunchTop_v3",
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
	-- Única fuente de verdad de la geometría del camino: World, FoodService, Hazards, Tunnel, Extras,
	-- Life, Places, Ambience y Quests leen de aquí (y de Config.zoneStart).
	Half = 95, -- media anchura del camino (antes 60)
	ZoneLength = 230, -- largo del suelo de cada zona (antes 150)
	LastZoneLength = 320, -- la última (Espacio) es más larga: allí espera la tarta
	ZoneGap = 250, -- de la puerta de una zona a la de la siguiente (antes 170)
	DepthIn = 60, -- cuánto se mete una hormiga de media hasta el racimo que se come (Quests, tools/sim.py)
	GardenTrip = 34, -- hormiguero -> racimos del jardín de media
}

-- Dónde empieza (z0, la puerta) cada zona del camino. La zona 2 empieza justo después del borde del jardín.
function Config.zoneStart(id: number): number
	if id <= 1 then
		return 0
	end
	return -(Config.Map.LobbyRadius + 10 + (id - 2) * Config.Map.ZoneGap)
end

local function zone(id, name, theme, floor)
	local z0 = Config.zoneStart(id)
	local length = if id == 1 then 0 elseif id == 14 then Config.Map.LastZoneLength else Config.Map.ZoneLength
	return { id = id, name = name, theme = theme, z0 = z0, z1 = z0 - length, floor = floor }
end

-- Hormigueros de zona: uno compartido a la entrada de cada zona 2..14, a la derecha del camino (la salida
-- del túnel está a la izquierda). Entregar ahí es como en casa; tus obreras de esa zona también entregan ahí.
-- Radius: radio de entrega (plano); Scale: tamaño respecto al hormiguero de casa; X: lado; ZIn: fondo desde z0
Config.Depot = { Radius = 12, Scale = 0.75, X = Config.Map.Half - 20, ZIn = 12 }

-- Dónde está el hormiguero de una zona (nil en el jardín). Servidor, cliente y tools/sim.py usan esta fórmula.
function Config.depotPos(id: number): Vector3?
	if id < 2 or id > 14 then
		return nil
	end
	return Vector3.new(Config.Depot.X, Config.GroundY, Config.zoneStart(id) - Config.Depot.ZIn)
end

-- Distancia media del hormiguero de una zona a los centros de su rejilla 3x3 de racimos (la misma geometría
-- que FoodService). La usan Quests para estimar viajes y tools/sim.py (depot_trip), que la copia.
function Config.depotTrip(id: number): number
	local at = Config.depotPos(id)
	if not at then
		return Config.Map.GardenTrip
	end
	local zone = Config.Zones[id]
	local x0, x1 = -Config.Map.Half + 14, Config.Map.Half - 14
	local zNear = zone.z0 - Config.FoodLayout.Margin
	local zFar = zone.z1 + (if id == #Config.Zones then 95 else 16)
	local cellW, cellL = (x1 - x0) / 3, (zNear - zFar) / 3
	local total = 0
	for row = 1, 3 do
		for col = 1, 3 do
			local c = Vector3.new(x0 + (col - 0.5) * cellW, at.Y, zNear - (row - 0.5) * cellL)
			total += (c - at).Magnitude
		end
	end
	return total / 9
end

-- La zona en la que cae una Z del camino (1 = jardín). Cada zona va de 10 studs antes de su puerta a 10
-- después de su fondo; más allá de la última, la última.
function Config.zoneAt(z: number): number
	local map = Config.Map
	if z > Config.zoneStart(2) + 10 then
		return 1
	end
	for id = 2, 13 do
		if z >= Config.zoneStart(id) - map.ZoneLength - 10 then
			return id
		end
	end
	return 14
end

-- Studs de media del hormiguero a los racimos de una zona: hasta la boca del jardín, por el camino y un
-- poco dentro (lo usan Quests y tools/sim.py para estimar viajes)
function Config.zoneDistance(id: number): number
	local map = Config.Map
	if id <= 1 then
		return map.GardenTrip
	end
	local mouth = math.sqrt(map.LobbyRadius ^ 2 - map.Half ^ 2)
	local toMouth = 0
	for k = 0, map.HillCount - 1 do
		local angle = math.rad(map.HillFrom + (map.HillTo - map.HillFrom) * k / (map.HillCount - 1))
		toMouth += Vector2.new(math.cos(angle) * map.HillArc, math.sin(angle) * map.HillArc + mouth).Magnitude
	end
	return toMouth / map.HillCount + (-Config.zoneStart(id) - mouth) + map.DepthIn
end

-- Sitios por donde andaría una hormiga, cada vez más lejos de casa.
Config.Zones = {
	zone(1, "Jardín", "Jardin", Color3.fromRGB(124, 200, 84)),
	zone(2, "Picnic", "Picnic", Color3.fromRGB(255, 244, 222)),
	zone(3, "Huerto", "Huerto", Color3.fromRGB(150, 104, 66)),
	zone(4, "Jungla", "Jungla", Color3.fromRGB(58, 150, 74)),
	zone(5, "Playa", "Mar", Color3.fromRGB(250, 224, 160)),
	zone(6, "Barbacoa", "Barbacoa", Color3.fromRGB(214, 132, 92)),
	zone(7, "Cocina", "Cocina", Color3.fromRGB(246, 236, 214)),
	zone(8, "Despensa", "Despensa", Color3.fromRGB(236, 210, 160)),
	zone(9, "Nevera", "Nevera", Color3.fromRGB(206, 232, 246)),
	zone(10, "Cuarto de juguetes", "Juguetes", Color3.fromRGB(104, 150, 220)),
	zone(11, "Escritorio", "Escritorio", Color3.fromRGB(70, 84, 104)),
	zone(12, "Feria", "Feria", Color3.fromRGB(150, 146, 160)),
	zone(13, "Dulcelandia", "Dulce", Color3.fromRGB(255, 190, 214)),
	zone(14, "Espacio", "Espacio", Color3.fromRGB(34, 30, 66)),
}

-- Tres comidas por zona (pequeña, mediana, grande). La vida se fija para quien EMPIEZA la capa con lo de
-- la anterior comprado: Bites pulsaciones con Mordida fuerte a nivel 10 * (zona - 1), por Press (lo
-- que pega de más una pulsación entonces: galerías, mordida doble y racha de media) y HardPress contra
-- la comida dura (Saliva ácida, Quebrantahuesos). A media capa cuestan más o menos 3-5 / 8-14 / 25-40.
-- Press y HardPress salen de python tools/sim.py --calibrar. El valor de un trozo: ZoneValues de su zona por
-- SlotValue. Todo medido con tools/sim.py para que cada capa dure unos 30 min jugando activo; las capas
-- 7 y 12 abren pocas mejoras nuevas y su comida vale bastante más que la de la zona anterior.
-- Lo que vale una comida entera es hp * value. hard: hace falta la mandíbula sierra (tú) o el cuartel.
Config.FoodCurve = {
	Bites = { 6, 18, 55 },
	SlotValue = { 1, 1.3, 1.7 },
	-- Rebajado desde la zona 3 con los hormigueros de zona (viajes cortos): antes 4.4, 15.5, 36, 61, 670, 1300, 2100, 3600, 11000, 1.2e5, 5.2e5, 8e5
	ZoneValues = { 1, 2.4, 3.6, 11.6, 26, 45, 560, 1010, 1520, 2640, 7380, 1.01e5, 3.44e5, 5.29e5 },
	Press = { 1, 1.3, 2.1, 2.5, 2.5, 2.4, 3.2, 3.6, 3.8, 3.9, 3.7, 4, 4.2, 4.2 },
	HardPress = { 1, 1, 1.4, 1.5, 1.5, 1.8, 1.8, 2.8, 3.5, 4.5, 5.1, 5.1, 7, 5.6 },
	BossHp = 20,
}

-- Racimos de comida de cada zona del camino (src/server/FoodService.luau). Cada receta: { veces,
-- pequeñas, medianas, grandes, jefa }. La jefa es una grande del banquete con JefaHp veces su vida y
-- JefaScale de tamaño. Los racimos van casi tocándose (Gap studs de borde a borde, dentro de la mordida
-- en cadena y del área) con pasillos de al menos Corridor studs entre racimos; empiezan a Margin studs
-- de la puerta. Respawn: segundos hasta que vuelve cada comida, en su sitio del racimo.
-- 52 comidas por zona: 13 zonas = 677 modelos, más el jardín (172, hasta 413 con mucha gente). Tope
-- duro de modelos de comida: MaxModels (lo que pase de ahí, como los rellenos del jardín, no sale).
Config.FoodLayout = {
	Clusters = {
		{ 2, 7, 0, 0, 0 }, -- migas
		{ 3, 4, 0, 1, 0 }, -- mixto: una grande rodeada de pequeñas
		{ 2, 2, 3, 0, 0 }, -- medianas
		{ 1, 6, 4, 2, 1 }, -- banquete
	},
	Respawn = { 2, 4, 7 },
	JefaHp = 4,
	JefaScale = 1.5,
	JefaRespawn = 30,
	Gap = 2.5,
	Corridor = 16,
	Margin = 25,
	GardenClusters = 34, -- centros de racimo del jardín (la mitad junto a los hormigueros)
	GardenSpread = 9, -- radio de un racimo del jardín
	MaxModels = 1200,
}

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

-- Cuántos hitos (Config.Milestones) lleva un nivel. Stats.milestones es la misma cuenta.
function Config.milestones(level: number): number
	local count = 0
	for _, at in Config.Milestones.Levels do
		if level >= at then
			count += 1
		end
	end
	return count
end

-- Trozos por mordisco con Mordida fuerte a nivel `level` (sin galerías ni nada más)
function Config.levelBite(level: number): number
	local p = Config.Player
	return p.BiteBase * (p.BitePower ^ level * Config.Milestones.Mult ^ Config.milestones(level)) ^ p.BiteSplit
end

-- Cuántas comidas de cada puesto (pequeña, mediana, grande) salen en una zona del camino
local COUNTS = { 0, 0, 0 }
for _, recipe in Config.FoodLayout.Clusters do
	for slot = 1, 3 do
		COUNTS[slot] += recipe[1] * recipe[slot + 1]
	end
end

Config.Foods = {}
for i, entry in FOOD_LIST do
	local curve = Config.FoodCurve
	local slot = (i - 1) % 3 + 1
	local zoneId = (i - 1) // 3 + 1
	local hard = entry[3] == true
	-- Lo que arranca una pulsación de quien empieza la capa de esta zona (ver Config.FoodCurve)
	local ref = Config.levelBite(10 * (zoneId - 1)) * curve.Press[zoneId]
	local def = {
		id = entry[1],
		name = entry[2],
		hard = hard,
		zone = zoneId,
		hp = round2(curve.Bites[slot] * ref * (if hard then curve.HardPress[zoneId] else 1)),
		value = round2(curve.ZoneValues[zoneId] * curve.SlotValue[slot]),
		count = COUNTS[slot],
		respawn = Config.FoodLayout.Respawn[slot],
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
Config.DigBase = 12000 -- excavar la capa 2; cada capa siguiente, StageGrowth veces más (tools/sim.py)
Config.CostScale = 7.5 -- abarata o encarece todo el árbol de golpe (ver tools/sim.py); subió de 0.5 con la carga nueva

local BRANCH = { M = "Mandíbulas", P = "Patas", C = "Colonia", F = "Feromonas", A = "Aliadas" }

-- `cost` se escribe a escala de la capa 1 y se multiplica por StageGrowth^(capa - 1).
-- yield: cada nivel multiplica además toda tu comida por (1 + yield). Lo llevan las mejoras que solas
-- apenas movían el ingreso (tools/sim.py --audit), para que ninguna compra sea inútil.
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
	node("bite", "M", 1, 1, { name = "Mordida fuerte", desc = "Cada mordisco arranca más.", max = 140, per = 10, cost = 6, growth = 1.6 }),
	node("chew", "M", 1, 2, { name = "Mordisco veloz", desc = "Muerdes más seguido.", max = 28, per = 2, cost = 60, growth = 10.5, parent = "bite", icon = "bite" }),
	node("crit", "M", 2, 1, { name = "Mordida doble", desc = "A veces muerdes mucho más fuerte.", max = 5, cost = 30, growth = 3.5, parent = "chew", yield = 0.02 }),
	node("saw", "M", 2, 2, { name = "Mandíbula sierra", desc = "Puedes morder comida dura: manzanas, cocos, latas.", max = 1, cost = 300, growth = 1, parent = "crit" }),
	node("combo", "M", 3, 1, { name = "Racha", desc = "Cada mordisco seguido pega un poco más. Si paras, se pierde.", max = 5, cost = 40, growth = 5, parent = "saw", icon = "crit" }),
	node("reach", "M", 4, 1, { name = "Cuello largo", desc = "Alcanzas la comida desde más lejos.", max = 4, cost = 40, growth = 6, parent = "combo", icon = "area" }),
	node("area", "M", 5, 1, { name = "Mordida en área", desc = "Tu mordisco alcanza también la comida cercana.", max = 3, cost = 40, growth = 8, parent = "reach" }),
	node("brutal", "M", 6, 1, { name = "Mordisco brutal", desc = "La mordida doble pega todavía más.", max = 5, cost = 40, growth = 5, parent = "area", icon = "crit" }),
	node("venom", "M", 8, 1, { name = "Saliva ácida", desc = "La comida dura se deshace: la muerdes mucho más rápido.", max = 5, cost = 40, growth = 5, parent = "brutal", icon = "saw", yield = 0.06 }),
	node("titan", "M", 8, 2, { name = "Mandíbula titán", desc = "Tu mordida pega y rinde bastante más.", max = 5, cost = 50, growth = 8, parent = "venom", icon = "saw" }),
	node("chain", "M", 3, 2, { name = "Mordida en cadena", desc = "Al terminar una comida, un rayo salta a la de al lado y le arranca un trozo. Y otra vez.", max = 5, cost = 50, growth = 5, parent = "combo", icon = "crit" }),
	-- Mejoras que cambian cómo juegas (Config.Extras, módulos Extras del servidor y del cliente)
	node("charged", "M", 4, 2, { name = "Mordisco cargado", desc = "Quédate quieta junto a la comida sin morder: tus mandíbulas se cargan y el siguiente mordisco arranca un pedazo enorme.", max = 3, cost = 45, growth = 6, parent = "reach", icon = "royalBite" }),
	node("doubleJaw", "M", 9, 1, { name = "Doble mandíbula", desc = "Cada mordisco muerde también la comida de al lado.", max = 3, cost = 50, growth = 8, parent = "titan", icon = "bite" }),

	-- Patas
	node("speed", "P", 1, 1, { name = "Paso rápido", desc = "Caminas más rápido.", max = 42, per = 3, cost = 15, growth = 4.8, yield = 0.01 }),
	node("carry", "P", 1, 2, { name = "Lomo fuerte", desc = "Cargas más trozos por viaje.", max = 140, per = 10, cost = 6, growth = 1.6, parent = "speed", yield = 0.01 }),
	node("sprint", "P", 2, 1, { name = "Turbo", desc = "Un acelerón corto a más del doble de velocidad. Correr normal ya lo tienes.", max = 1, cost = 25, growth = 1, parent = "carry", hint = "{tecla} para meter el turbo", key = "Z", button = "Turbo" }),
	node("stamina", "P", 2, 2, { name = "Resuello", desc = "El turbo dura más.", max = 5, cost = 20, growth = 4, parent = "sprint", icon = "sprint", yield = 0.05 }),
	node("wings", "P", 3, 1, { name = "Alas", desc = "Vuelas a tu hormiguero. Y desde casa, a tu zona más lejana.", max = 1, cost = 170, growth = 1, parent = "stamina", hint = "{tecla} y vuelvo volando a casa. Desde casa, vuelo a mi zona más lejana", key = "R", button = "Volar" }),
	node("landing", "P", 4, 1, { name = "Vuelo corto", desc = "Las alas se recuperan antes y caminas más rápido.", max = 5, cost = 45, growth = 4, parent = "wings", icon = "wings", yield = 0.05 }),
	node("fullLoad", "P", 5, 1, { name = "Entrega llena", desc = "Si entregas con la carga llena, la entrega vale más. No da más carga.", max = 5, cost = 40, growth = 5, parent = "landing", icon = "anthill" }),
	node("giant", "P", 7, 1, { name = "Hormiga gigante", desc = "Creces. Y cargas más.", max = 3, cost = 60, growth = 15, parent = "fullLoad", icon = "carry", yield = 0.06 }),
	node("tunnel", "P", 2, 3, { name = "Túnel exprés", desc = "Un agujero junto a tu hormiguero que sale a la entrada de cada zona abierta. Y vuelta.", max = 1, cost = 40, growth = 1, parent = "stamina", icon = "anthill", hint = "Mi túnel está delante del hormiguero, junto al cartel", key = "B", button = "Túnel" }),
	node("buche", "P", 6, 1, { name = "Buche", desc = "Un segundo estómago: al entregar te guardas parte de la carga y sales con ella para el siguiente viaje.", max = 5, cost = 45, growth = 5, parent = "fullLoad", icon = "royalFood" }),
	node("double", "P", 9, 1, { name = "Reparto doble", desc = "A veces una entrega vale el doble.", max = 5, cost = 40, growth = 5, parent = "giant", icon = "anthill" }),

	-- Colonia
	node("nursery", "C", 1, 1, { name = "Guardería", desc = "Espacio para criar obreras. Cada nivel caben más.", max = 28, per = 2, cost = 50, growth = 10.5 }),
	node("workers", "C", 1, 2, { name = "Obreras", desc = "Traen comida solas, sin que hagas nada.", unit = true, parent = "nursery" }),
	node("workerSpeed", "C", 2, 1, { name = "Obreras rápidas", desc = "Tus obreras caminan más rápido.", max = 12, per = 2, cost = 35, growth = 10.5, parent = "workers" }),
	node("workerCarry", "C", 2, 2, { name = "Obreras fuertes", desc = "Cada obrera carga más por viaje.", max = 26, per = 2, cost = 100, growth = 10.5, parent = "workerSpeed", yield = 0.02 }),
	node("storage", "C", 3, 1, { name = "Almacén", desc = "La colonia sigue trabajando mientras no estás.", max = 5, cost = 50, growth = 9, parent = "workerCarry" }),
	node("nurse", "C", 3, 2, { name = "Nodrizas", desc = "Caben más obreras en la guardería.", max = 5, cost = 55, growth = 4, parent = "storage", icon = "nursery" }),
	node("barracks", "C", 4, 1, { name = "Cuartel", desc = "Soldados que rompen comida dura y aceleran a toda la colonia.", max = 5, cost = 60, growth = 12, parent = "nurse" }),
	node("eggs", "C", 4, 2, { name = "Huevos dorados", desc = "Cada cierto tiempo aparece un huevo dorado junto a tu hormiguero. Písalo.", max = 5, cost = 25, growth = 6, parent = "barracks", icon = "nursery", yield = 0.05 }),
	node("queen", "C", 5, 1, { name = "Reina ponedora", desc = "La reina cría obreras sola cuando hay comida de sobra, y la colonia rinde más.", max = 1, cost = 70, growth = 1, parent = "eggs" }),
	-- (Puesto avanzado retirado hasta el rediseño de movilidad: lo sustituyen los hormigueros de zona, Config.Depot)
	node("fungus", "C", 6, 1, { name = "Jardín de hongos", desc = "Crecen hongos junto a tu hormiguero. Cómete uno y toda la comida vale el doble un rato.", max = 5, cost = 50, growth = 6, parent = "queen", icon = "storage" }),
	node("legion", "C", 7, 1, { name = "Legión", desc = "La colonia entera trabaja más.", max = 10, cost = 45, growth = 4, parent = "fungus", icon = "barracks", yield = 0.03 }),
	node("super", "C", 9, 1, { name = "Supercolonia", desc = "Cada obrera carga más.", max = 5, cost = 50, growth = 6, parent = "legion", icon = "workerCarry", yield = 0.05 }),

	-- Feromonas
	node("trail", "F", 1, 1, { name = "Rastro", desc = "Marcas una comida y las obreras van por ella. Cada nivel, un rastro más.", max = 3, costs = { 1200, 4.5e7, 6e13 }, needs = "workers", hint = "{tecla} junto a una comida y mis obreras irán por ella", key = "F", button = "Rastro" }),
	node("sweet", "F", 2, 1, { name = "Feromona dulce", desc = "Las obreras rinden más en la comida que marcas tú.", max = 5, cost = 70, growth = 5, parent = "trail", icon = "trail" }),
	node("frenzy", "F", 3, 1, { name = "Frenesí", desc = "Toda la colonia trabaja al triple durante unos segundos.", max = 1, cost = 120, growth = 1, parent = "sweet", hint = "{tecla} y la colonia se vuelve loca", key = "G", button = "Frenesí" }),
	node("frenzyLen", "F", 4, 1, { name = "Frenesí largo", desc = "El frenesí dura más.", max = 5, cost = 40, growth = 5, parent = "frenzy", icon = "frenzy", yield = 0.03 }),
	node("smart", "F", 5, 1, { name = "Rastro listo", desc = "Las obreras sin rastro eligen solas la mejor comida, y la comida marcada rinde más.", max = 1, cost = 100, growth = 1, parent = "frenzyLen" }),
	node("express", "F", 6, 1, { name = "Autopista", desc = "Las obreras tardan menos en cada viaje.", max = 5, cost = 40, growth = 5, parent = "smart", icon = "workerSpeed" }),
	node("goldFood", "F", 2, 2, { name = "Olfato dorado", desc = "Aparece más comida dorada por el mapa, y la tuya vale todavía más. No es el mordisco dorado: es comida entera de oro.", max = 5, cost = 60, growth = 4, parent = "sweet", icon = "royalFood" }),
	node("lane", "F", 3, 2, { name = "Senda de feromonas", desc = "Tus rastros brillan en el suelo, de tu hormiguero a la comida. Si caminas por ellos, vas mucho más rápido.", max = 3, cost = 60, growth = 6, parent = "frenzy", icon = "trail", yield = 0.06 }),
	node("giantFood", "F", 7, 1, { name = "Comida gigante", desc = "De vez en cuando una comida de la zona donde estás crece enorme: muchas veces más comida, para quien llegue.", max = 3, cost = 50, growth = 8, parent = "express", icon = "royalFood", yield = 0.06 }),
	node("hive", "F", 8, 1, { name = "Mente colmena", desc = "El frenesí se recupera antes.", max = 5, cost = 40, growth = 5, parent = "express", icon = "smart" }),
	node("royalPher", "F", 10, 1, { name = "Feromona real", desc = "El frenesí es todavía más fuerte.", max = 3, cost = 40, growth = 10, parent = "hive", icon = "frenzy", yield = 0.08 }),

	-- Aliadas: bichos y cachivaches que trabajan contigo y se ven en el mundo (ver Config.Allies).
	-- Un juguete nuevo casi en cada capa; cada nivel se abre con la capa siguiente (per = 1).
	node("bee", "A", 2, 1, { name = "Abeja mensajera", desc = "Una abeja viene a por tu carga y la lleva volando a tu hormiguero.", max = 6, per = 1, cost = 60, growth = 100, icon = "wings" }),
	node("magnet", "A", 3, 1, { name = "Imán de migas", desc = "De vez en cuando una comida pequeña de cerca salta entera a tus mandíbulas.", max = 5, per = 1, cost = 50, growth = 100, parent = "bee", icon = "royalFood", yield = 0.03 }),
	node("beetle", "A", 4, 1, { name = "Escarabajo de carga", desc = "Un escarabajo te sigue y carga lo que ya no te cabe.", max = 5, per = 1, cost = 50, growth = 100, parent = "magnet", icon = "carry" }),
	node("escort", "A", 5, 1, { name = "Escolta", desc = "Soldados pequeños que van contigo y muerden lo que muerdes tú.", max = 5, per = 1, cost = 50, growth = 100, parent = "beetle", icon = "barracks" }),
	node("stomp", "A", 6, 1, { name = "Pisotón", desc = "Un pisotón que muerde toda la comida de alrededor a la vez.", max = 5, per = 1, cost = 60, growth = 100, parent = "escort", icon = "area", hint = "{tecla} y doy un pisotón que muerde todo alrededor", key = "X", button = "Pisotón" }),
	node("sling", "A", 7, 1, { name = "Tirachinas", desc = "Lanzas toda tu carga de un tirón hasta tu hormiguero.", max = 5, per = 1, cost = 60, growth = 100, parent = "stomp", icon = "speed", hint = "{tecla} y lanzo la carga a mi hormiguero", key = "C", button = "Lanzar", yield = 0.05 }),
	node("rain", "A", 8, 1, { name = "Lluvia propia", desc = "Unos segundos de lluvia de migas de tu zona a tu alrededor. Pásales por encima y van a tu carga.", max = 5, per = 1, cost = 60, growth = 100, parent = "sling", icon = "royalFood", hint = "{tecla} y llueven migas a mi alrededor", key = "L", button = "Lluvia", yield = 0.05 }),
	node("lens", "A", 9, 1, { name = "Lupa solar", desc = "Una lupa quema de vez en cuando un buen trozo de la comida más grande que tengas cerca.", max = 5, per = 1, cost = 50, growth = 100, parent = "sling", icon = "smart", yield = 0.05 }),
	node("mega", "A", 11, 1, { name = "Mega crunch", desc = "Si muerdes sin parar, cada cierto número de mordiscos llega uno gigante.", max = 4, per = 1, cost = 60, growth = 100, parent = "lens", icon = "royalBite" }),
}

-- Números de las Aliadas. Los niveles se traducen a estadísticas en Stats.derive.
Config.Allies = {
	-- Viene cada Interval s (Step menos por nivel, nunca menos de MinInterval) si llevas al menos
	-- MinLoad de tu carga; desde el nivel FullAt también en cuanto te llenas. Vuela de verdad, a
	-- Speed studs/s (SpeedStep más por nivel; cada tramo dura al menos MinFly s), y no vuelve a por
	-- otra carga hasta regresar: lejos de casa ayuda menos. Es la mejora que más mueve el ritmo
	-- (es un segundo porteador): antes de tocar Speed, mira tools/sim.py.
	Bee = { Interval = 30, Step = 4, MinInterval = 10, MinLoad = 0.5, FullAt = 4, Speed = 30, SpeedStep = 5, MinFly = 1.6, Approach = 0.45 },
	-- Cada Tick s se traga hasta Count comidas a Radius studs que caerían en Bites mordiscos tuyos (con
	-- Bites = 10, las pequeñas de tu zona: en los racimos siempre hay alguna a tiro)
	Magnet = { Tick = 2, Radius = 9, RadiusStep = 3, Bites = 10, Count = 1 },
	Beetle = { Share = 0.08 }, -- carga extra por nivel, sobre la tuya (antes 0.4: alargaba los viajes sin fin)
	-- Mientras muerdes (y Linger s después), cada Tick s cada soldado arranca Share de tu mordida
	Escort = { Tick = 0.5, Share = 0.6, Linger = 1.5 },
	Stomp = { Cooldown = 20, Step = 2, Radius = 12, RadiusStep = 2, Mult = 8 },
	Sling = { Cooldown = 40, Step = 5, Range = 4000, RangeStep = 0, FlyTime = 2 }, -- llega desde cualquier zona
	-- Cada Interval s quema Mult mordiscos de la comida más grande a Radius studs. La comida va directa a casa.
	Lens = { Interval = 20, Step = 2, Radius = 40, Mult = 20, MultStep = 8, Delay = 0.9 },
	-- Cada Every mordiscos seguidos, uno que pega Mult veces y salpica a Radius studs
	Mega = { Every = 15, Step = 2, Mult = 15, MultStep = 5, Radius = 10 },
}

-- Mejoras que cambian cómo juegas (src/server/Extras.luau). Los niveles se traducen en Stats.derive.
Config.Extras = {
	-- Quieta junto a comida, sin morder durante Pause s, empiezas a cargar; hasta Max s (Step más por
	-- nivel). El siguiente mordisco (o la carga llena, sola) arranca Mult (MultStep más por nivel) veces
	-- los mordiscos que cabían en ese tiempo. Por debajo de MinCharge s no cuenta.
	Charged = { Pause = 0.5, MinCharge = 0.4, Max = 1.5, Step = 1, Mult = 2.2, MultStep = 0.6 },
	-- Cada mordisco arranca Share (Step más por nivel) de tu mordida a la comida más cercana a Reach studs
	DoubleJaw = { Share = 0.6, Step = 0.2, Reach = 5 },
	-- Al entregar te quedas Share (Step más por nivel) de la carga; vuelve a tus mandíbulas al salir
	Buche = { Share = 0.1, Step = 0.05 },
	-- Radius: radio de entrega. Relay: parte del camino puesto-hormiguero que las obreras aún pagan
	-- (lo demás lo pasa el puesto en cadena). Mueve mucho el ritmo de la colonia: mira tools/sim.py.
	Outpost = { Radius = 9, Relay = 0.85 },
	-- Cada Interval s (Step menos por nivel) una comida de tu zona crece: Mult veces su vida (MultStep más por nivel)
	Giant = { Interval = 60, Step = 10, Mult = 8, MultStep = 2 },
	-- Durante Duration s caen Count migas (CountStep más por nivel) a Radius studs de ti. Cada una vale
	-- Bites mordiscos tuyos a la mejor comida de tu zona (como mucho esa comida entera); duran Life s en
	-- el suelo y se cogen a Reach studs.
	Rain = { Cooldown = 45, Step = 3, Duration = 5, Count = 16, CountStep = 6, Radius = 16, Bites = 6, Life = 12, Reach = 4.5, Fall = 1.1 },
	-- Velocidad xMult (MultStep más por nivel) mientras pisas uno de tus rastros (a Width studs de su línea)
	Lane = { Mult = 1.3, MultStep = 0.2, Width = 3.5 },
}

-- Dos niveles de guardería por capa
Config.NurseryCaps = {
	5, 10, 20, 35, 55, 80, 110, 150, 200, 260, 330, 410, 500, 600,
	700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000,
}
Config.StorageHours = { 1, 2, 4, 8, 12 }

-- Galerías: cámaras pequeñas de un solo nivel, 9 por rama en cada capa (504 en total). Se generan solas
-- a partir de esta tabla. Cada fila de tres se excava desde el pozo hacia fuera: cada cámara pide la
-- anterior de su fila, y la primera solo pide la capa excavada.
-- Las dos primeras de cada fila dan algo que se nota con su número: cantidades fijas calculadas con lo
-- que se tiene a media capa (una galería de la capa 9 da muchísima más carga que una de la 1), obreras,
-- segundos o pasos. La tercera de cada fila es una regla con nombre (Perks) que vuelve en capas más
-- hondas con un número más (I, II, III...): cada galería de una regla le sube un nivel.
-- Se aplican en Stats.derive y en src/server/Perks.luau. Antes de tocar números, mira tools/sim.py.
local Format = require(script.Parent.Format)

Config.MiniTune = {
	Span = { 10, 250 }, -- costo de la galería más barata y de la más cara de una capa, a escala de capa 1
	BranchCost = { M = 1, P = 1.1, C = 1.2, F = 0.9 },
	Rotate = 4, -- en cada capa los tipos de las galerías sencillas se corren estos huecos
	GoldCap = 0.2, -- probabilidad máxima de mordisco dorado
	GoldMult = 10, -- lo que vale la comida de un mordisco dorado
	-- Referencia de las cantidades fijas: Mordida fuerte y Lomo fuerte suben 10 niveles por capa y
	-- Obreras fuertes 2; se toma su nivel a media capa (MidLevel menos que el tope, y 1 menos las obreras).
	MidLevel = 5,
	-- Las cantidades fijas de las primeras capas valen más (antes las subía el Paladar de su zona)
	Early = { 1.5, 1.5, 1.2 },
	-- Galerías sencillas. text: {n} número, {d} número con decimales, {p} porcentaje, {c} el doble de {n}.
	-- many: texto si la cantidad no es 1. total: texto para lo que suman todas (si es distinto).
	-- ref + share: parte de la referencia de su capa. amount (+ step por capa): cantidad fija.
	-- from: primera capa en la que sale; antes, su hueco pasa al tipo siguiente del montón.
	Kinds = {
		bite = { ref = "bite", share = 0.08, icon = "bite", text = "+{n} de mordida", names = { "Colmillo afilado", "Mandíbula prieta", "Diente de sierra" } },
		chew = { amount = 0.03, icon = "royalBite", text = "Ritmo de mordisco +{p}", names = { "Masticar rápido", "Ñam ñam", "Mandíbula suelta" } },
		crit = { amount = 0.01, icon = "crit", text = "+{p} de mordida doble", names = { "Ojo certero", "Punto débil", "Golpe de suerte" } },
		critHit = { amount = 0.08, icon = "crit", text = "La mordida doble pega +{d} veces más", names = { "Golpe seco", "Mandíbula de hierro", "Crac" } },
		reach = { amount = 0.5, icon = "area", text = "+{d} pasos de alcance", names = { "Cuello estirado", "Brazo largo", "Antenas finas" } },
		chain = { amount = 1, from = 4, icon = "crit", text = "+{d} salto de la mordida en cadena", many = "+{d} saltos de la mordida en cadena", names = { "Chispa", "Relámpago", "Rayo doble" } },
		carry = { ref = "carry", share = 0.08, icon = "carry", text = "+{n} de carga", names = { "Lomo ancho", "Mochila", "Carga extra" } },
		speed = { amount = 1, step = 0.1, round = 0.5, icon = "speed", text = "+{d} de velocidad", names = { "Zancada", "Pasito rápido", "Patas finas" } },
		turbo = { amount = 0.5, from = 2, icon = "sprint", text = "El turbo dura {d} s más", names = { "Pulmón grande", "Aguante", "Segundo aire" } },
		deposit = { ref = "deposit", share = 0.25, icon = "anthill", text = "+{n} de comida en cada entrega", names = { "Buena entrega", "Despensa ordenada", "Reparto fino" } },
		bee = { amount = 1, from = 2, icon = "wings", text = "La abeja vuelve {d} s antes", names = { "Néctar", "Atajo de abeja", "Flor amiga" } },
		magnet = { amount = 1, from = 3, icon = "royalFood", text = "El imán atrae migas {d} pasos más lejos", names = { "Imán fuerte", "Polo norte", "Tirón" } },
		wings = { amount = 1, from = 3, icon = "wings", text = "Las alas vuelven {d} s antes", names = { "Plumón", "Ala ligera", "Viento a favor" } },
		crew = { amount = 1, step = 1, icon = "workers", text = "+{n} obrera gratis ahora y +{c} de cupo", many = "+{n} obreras gratis ahora y +{c} de cupo", total = "Guardería +{c} plazas", names = { "Cuna nueva", "Literas", "Ala de cría" } },
		workerCarry = { ref = "worker", share = 0.15, icon = "workerCarry", text = "Cada obrera carga +{n}", names = { "Obrera forzuda", "Cesta", "Espalda fuerte" } },
		cheap = { amount = 0.04, icon = "royalStart", text = "Obreras un {p} más baratas", names = { "Cría barata", "Papilla", "Nodriza novata" } },
		eggTime = { amount = 10, from = 4, icon = "nursery", text = "El huevo dorado sale {d} s antes", names = { "Nido caliente", "Gallina lista", "Cáscara fina" } },
		eggValue = { amount = 4, from = 4, icon = "queen", text = "El huevo dorado vale {d} s más de colonia", names = { "Yema rica", "Huevo gordo", "Nido dorado" } },
		offline = { amount = 15, from = 3, icon = "storage", text = "La colonia trabaja {d} min más sin ti", names = { "Turno de noche", "Vigilantes", "Despensa llena" } },
		workerSpeed = { amount = 0.4, icon = "workerSpeed", text = "+{d} de velocidad para tus obreras", names = { "Sendero liso", "Paso de hormiga", "Prisa" } },
		jelly = { amount = 0.02, icon = "royalFood", text = "+{p} de jalea al enjambrar", names = { "Gota real", "Jalea pura", "Panal" } },
		trail = { amount = 0.03, icon = "trail", text = "La comida que marcas rinde +{p}", names = { "Rastro fresco", "Olor dulce", "Marca clara" } },
		frenzyLen = { amount = 1, from = 3, icon = "frenzy", text = "El frenesí dura {d} s más", names = { "Tambores", "Euforia", "Grito largo" } },
		frenzyCd = { amount = 2, from = 3, icon = "frenzy", text = "El frenesí vuelve {d} s antes", names = { "Ganas", "Pila cargada", "Mecha corta" } },
		fungus = { amount = 2, from = 6, icon = "storage", text = "La comida doble del hongo dura {d} s más", names = { "Hongo jugoso", "Esporas", "Sombrero grande" } },
	},
	-- Tipos de las 6 galerías sencillas de cada rama, de la más barata a la más cara (antes de correrlos)
	Pools = {
		M = { "bite", "chew", "bite", "crit", "reach", "critHit", "chain" },
		P = { "carry", "speed", "deposit", "carry", "turbo", "bee", "magnet", "wings" },
		C = { "crew", "workerCarry", "cheap", "workerCarry", "eggTime", "offline", "eggValue" },
		F = { "workerSpeed", "jelly", "frenzyLen", "trail", "frenzyCd", "workerSpeed", "fungus" },
	},
	-- Reglas con nombre: la tercera galería de cada fila. Fila a fila y capa a capa salen en este orden
	-- (las tres de la capa 1, las tres siguientes en la 2...) y al acabar la lista vuelven con un nivel más.
	PerkOrder = {
		M = { "first", "lastBite", "streak", "hungry", "sweep", "palate", "crusher" },
		P = { "fullSpeed", "lightSpeed", "depStreak", "starDep", "filler", "pedometer", "loot" },
		C = { "star", "pantry", "cradle", "shift", "rush", "fullNest", "wake" },
		F = { "early", "nugget", "clover", "pureGold", "party", "fever", "frenzyBite" },
	},
	-- {v} = base + step * (nivel - 1); int: hacia abajo. one: texto si {v} es 1. Los números fijos de
	-- cada regla (radios, ventanas, topes) van en PerkRules. Flojas a propósito: hay 168 y se suman.
	Perks = {
		-- Mandíbulas
		first = { name = "Primer mordisco", icon = "bite", base = 1.5, step = 0.25, text = "Tu primer mordisco a cada comida pega x{v}" },
		lastBite = { name = "Última miga", icon = "royalFood", base = 2, step = 0.25, text = "El último bocado de cada comida vale x{v}" },
		streak = { name = "Buena racha", icon = "crit", base = 20, step = -2, text = "Cada {v} mordiscos seguidos, uno gratis con mordida doble" },
		hungry = { name = "Hambre voraz", icon = "royalBite", base = 2, step = 0.5, text = "Al salir de casa vacía, tus {v} primeros mordiscos pegan doble" },
		sweep = { name = "Barrido", icon = "area", base = 10, step = -1, text = "Cada {v} mordiscos, muerdes también toda la comida a 8 pasos" },
		palate = { name = "Paladar fino", icon = "smart", base = 3, step = 1, text = "La comida de tu zona más honda vale un {v} % más" },
		crusher = { name = "Quebrantahuesos", icon = "saw", base = 1.5, step = 0.25, text = "Contra la comida dura muerdes x{v}" },
		-- Patas
		fullSpeed = { name = "Carga viva", icon = "speed", base = 4, step = 1.5, text = "Con la carga llena caminas un {v} % más rápido" },
		lightSpeed = { name = "Patas ligeras", icon = "speed", base = 4, step = 1.5, text = "Con la carga vacía caminas un {v} % más rápido" },
		depStreak = { name = "Entrega en racha", icon = "anthill", base = 2, step = 1, text = "Entregar antes de 20 s desde la anterior suma un {v} %, hasta 3 veces" },
		starDep = { name = "Entrega estrella", icon = "queen", base = 1.5, step = 0.1, text = "Cada 5 min, tu siguiente entrega vale x{v}" },
		filler = { name = "Recolectora", icon = "royalFood", base = 2, step = 1, text = "Al llenar la carga del todo, ganas ya un {v} % de lo que llevas" },
		pedometer = { name = "Cuentapasos", icon = "sprint", base = 1, step = 0.5, text = "Cada 1000 pasos, ganas un {v} % de lo que vale una carga llena" },
		loot = { name = "Botín", icon = "royalFood", base = 2, step = 1, text = "Terminar una comida grande te da un {v} % de lo que valía entera" },
		-- Colonia
		star = { name = "Obrera estrella", icon = "workers", base = 5, step = 5, text = "Una de tus obreras vale por {v}" },
		pantry = { name = "Despensa viva", icon = "storage", base = 0.5, step = 0.1, text = "Cada minuto tu comida guardada crece un {v} %, hasta 30 s de colonia" },
		cradle = { name = "Cuna rápida", icon = "nursery", base = 1, step = 0.2, int = true, text = "Cada 5 min nacen {v} obreras gratis, si caben", one = "Cada 5 min nace una obrera gratis, si cabe" },
		shift = { name = "Turno doble", icon = "royalColony", base = 1, step = 0.5, text = "Cada entrega tuya trae además {v} s de trabajo de la colonia" },
		rush = { name = "Hora punta", icon = "barracks", base = 10, step = 2, text = "Cada 4 min, la colonia trabaja el doble durante {v} s" },
		fullNest = { name = "Hormiguero lleno", icon = "anthill", base = 10, step = 5, text = "Con la guardería llena, la colonia trabaja un {v} % más" },
		wake = { name = "Despertador", icon = "queen", base = 2, step = 1, text = "Si vuelves tras 10 min fuera, la colonia te regala {v} min de trabajo" },
		-- Feromonas
		early = { name = "Madrugadora", icon = "frenzy", base = 1, step = 0.5, text = "Al entrar al juego y al excavar una capa, {v} min de comida doble" },
		nugget = { name = "Pepita segura", icon = "queen", base = 250, step = -25, text = "Cada {v} mordiscos, uno vale como dorado" },
		clover = { name = "Trébol", icon = "smart", base = 1, step = 0.3, text = "Un {v} % de tus mordiscos deja un regalo de 2 mordiscos más" },
		pureGold = { name = "Oro puro", icon = "royalFood", base = 12, step = 1, text = "Tus mordiscos dorados valen x{v} en vez de x10" },
		party = { name = "Olor a fiesta", icon = "trail", base = 2, step = 0.5, text = "Cada entrega tuya hace trabajar a la colonia el doble {v} s" },
		fever = { name = "Fiebre del oro", icon = "queen", base = 1, step = 0.2, int = true, text = "Tras un mordisco dorado, los {v} siguientes también valen como dorados", one = "Tras un mordisco dorado, el siguiente también vale como dorado" },
		frenzyBite = { name = "Frenesí contagioso", icon = "frenzy", base = 1.5, step = 0.25, text = "Durante el frenesí tú también muerdes x{v}" },
	},
	-- Números fijos de las reglas (src/server/Perks.luau)
	PerkRules = {
		LastShare = 0.025, -- "el último bocado": como mucho esta parte de la vida de la comida
		Gap = 1.6, -- segundos entre mordiscos para que cuenten como seguidos (como Config.Combo.Window)
		SweepRadius = 8,
		DepositWindow = 20, -- Entrega en racha
		DepositStacks = 3,
		StarEvery = 300, -- Entrega estrella
		Steps = 1000, -- Cuentapasos
		PantryEvery = 60,
		PantryCap = 30, -- segundos de colonia
		CradleEvery = 300,
		RushEvery = 240,
		WakeAway = 600, -- segundos fuera para Despertador y la comida doble de Madrugadora al entrar
		CloverBites = 2,
		CueGap = 2.5, -- segundos mínimos entre dos avisos de la misma regla
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

-- 2,5 en vez de 2.5; sin decimales si es entero
local function decimalText(x: number): string
	if math.abs(x - math.floor(x + 0.5)) < 1e-6 then
		return tostring(math.floor(x + 0.5))
	end
	return (string.format("%.2f", x):gsub("0$", ""):gsub("%.", ","))
end

local function fill(template: string, values): string
	return (template:gsub("{(%a)}", function(key)
		return values[key] or ""
	end))
end

-- Texto de una galería sencilla con una cantidad dada (la de una cámara o, con total, la de todas las de su tipo).
function Config.miniText(kind: string, amount: number, _layer: number?, total: boolean?): string
	local info = Config.MiniTune.Kinds[kind]
	if not info then
		return ""
	end
	local template = if total and info.total then info.total elseif amount ~= 1 and info.many then info.many else info.text
	return fill(template, {
		n = Format.short(math.floor(amount + 0.5)),
		d = decimalText(amount),
		p = percentText(amount),
		c = Format.short(math.floor(2 * amount + 0.5)),
	})
end

-- Fuerza de una regla con nombre a un nivel (0 = no la tienes)
function Config.perkValue(id: string, level: number): number
	local perk = Config.MiniTune.Perks[id]
	if not perk or level <= 0 then
		return 0
	end
	local value = perk.base + perk.step * (level - 1)
	return if perk.int then math.floor(value + 1e-9) else value
end

function Config.perkText(id: string, level: number): string
	local perk = Config.MiniTune.Perks[id]
	local value = Config.perkValue(id, math.max(level, 1))
	local template = if value == 1 and perk.one then perk.one else perk.text
	return fill(template, { v = decimalText(value) })
end

-- Solo el número de una regla con su unidad ("x2,5", "4 %", "6 s", "250 mordiscos"), para la ficha
function Config.perkShort(id: string, level: number): string
	local perk = Config.MiniTune.Perks[id]
	local value = decimalText(Config.perkValue(id, math.max(level, 1)))
	if perk.text:find("x{v}", 1, true) then
		return "x" .. value
	end
	return value .. (perk.text:match("{v}( %%)") or perk.text:match("{v}( %a+)") or "")
end

-- Referencia de las cantidades fijas de una capa: lo que da Mordida fuerte, Lomo fuerte u Obreras
-- fuertes a media capa, y media carga de su comida mediana para las entregas
local function miniRef(ref: string, layer: number): number
	local level = 10 * layer - Config.MiniTune.MidLevel
	local carry = Config.Player.Capacity * Config.Player.CarryGrowth ^ level * Config.Milestones.CarryMult ^ Config.milestones(level)
	if ref == "bite" then
		return Config.levelBite(level)
	elseif ref == "carry" then
		return carry
	elseif ref == "worker" then
		local workerLevel = 2 * layer - 1
		return Config.Worker.Carry * Config.Worker.CarryGrowth ^ workerLevel * Config.Milestones.Mult ^ Config.milestones(workerLevel)
	end
	local food = Config.Foods[(layer - 1) * 3 + 2]
	return carry * (if food then food.value else 1)
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

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
			local order = tune.PerkOrder[key]
			local seen = {} -- cuántas de cada tipo van en esta capa, para no repetir nombre
			for slot = 1, 9 do
				local row = (slot - 1) // 3 + 1
				local col = (slot - 1) % 3 + 1
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
					-- De 15 a 600 a lo largo de los 9 huecos: siempre queda alguna barata
					cost = round2(tune.Span[1] * ratio ^ ((slot - 1) / 8) * tune.BranchCost[key] * stage),
					prev = if col > 1 then "m" .. key .. layer .. "_" .. (slot - 1) else nil,
				}
				if col == 3 then
					-- Regla con nombre: sube un nivel la regla que toque
					local i = (layer - 1) * 3 + (row - 1)
					local id = order[i % #order + 1]
					local perk = tune.Perks[id]
					local level = i // #order + 1
					def.kind = "perk"
					def.perk = id
					def.amount = 1
					def.level = level
					def.icon = perk.icon
					def.name = perk.name .. " " .. ROMAN[level]
					def.desc = Config.perkText(id, level)
				else
					local start = ((row - 1) * 2 + col - 1 + (layer - 1) * tune.Rotate) % #pool
					local kind = pool[start + 1]
					for k = 0, #pool - 1 do
						local candidate = pool[(start + k) % #pool + 1]
						if (tune.Kinds[candidate].from or 1) <= layer then
							kind = candidate
							break
						end
					end
					local info = tune.Kinds[kind]
					local amount = if info.ref
						then round2(info.share * miniRef(info.ref, layer) * (tune.Early[layer] or 1))
						else info.amount + (info.step or 0) * (layer - 1)
					if info.round then
						amount = math.max(info.round, math.floor(amount / info.round + 0.5) * info.round)
					end
					seen[kind] = (seen[kind] or 0) + 1
					def.kind = kind
					def.amount = amount
					def.icon = info.icon
					def.name = info.names[(layer + seen[kind]) % #info.names + 1]
					def.desc = Config.miniText(kind, amount)
				end
				def.index = #Config.Minis + 1
				table.insert(Config.Minis, def)
				Config.MiniById[def.id] = def
			end
		end
	end
end

-- Las mismas galerías de la más barata a la más cara (el árbol mira si hay alguna al alcance).
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
	{ id = "royalStart", name = "Nido heredado", desc = "Empiezas cada partida con obreras.", max = 10, cost = 2, step = 2, yield = 0.05 },
	{ id = "royalSpeed", name = "Patas reales", desc = "Caminas más rápido para siempre.", max = 5, cost = 2, step = 1, yield = 0.05 },
	{ id = "royalDepth", name = "Planos del nido", desc = "Empiezas cada partida con capas ya excavadas.", max = 7, cost = 4, step = 4, icon = "anthill", yield = 0.06 },
	{ id = "royalJelly", name = "Jalea espesa", desc = "Ganas más jalea al enjambrar.", max = 10, cost = 2, step = 2, icon = "royalFood", yield = 0.05 },
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
-- group: apartado de la tienda (src/client/Store.luau agrupa por él) y del puesto que lo vende
-- (src/client/Stalls.luau). Efectos: src/server/Profiles.luau (los ocho primeros) y
-- src/server/Monetize.luau (el resto). Nada de pago es obligatorio: todo se consigue jugando.
Config.Passes = {
	{ id = "x2Food", passId = 2088369535, robux = 199, group = "Para siempre", name = "Comida doble", desc = "Toda la comida vale el doble, para siempre." },
	{ id = "autoBite", passId = 2089911561, robux = 149, group = "Para siempre", name = "Mordida automática", desc = "Tu hormiga muerde sola en cuanto tiene comida a tiro." },
	{ id = "fastColony", passId = 2088333604, robux = 149, group = "Para siempre", name = "Colonia veloz", desc = "Tus obreras trabajan al doble, para siempre." },
	{ id = "goldWings", passId = 2089929537, robux = 129, group = "Para siempre", name = "Alas doradas", desc = "Alas desde el primer minuto y casi sin espera entre vuelos." },
	{ id = "vip", passId = 2089629650, robux = 299, group = "Para siempre", name = "VIP", desc = "Un 25 % más de comida, estela de oro y tu cartel con estrella." },
	{ id = "x2Jelly", passId = 2088297560, robux = 249, group = "Para siempre", name = "Jalea doble", desc = "Cada enjambre te da el doble de jalea." },
	{ id = "turbo", passId = 2089557565, robux = 99, group = "Para siempre", name = "Patas turbo", desc = "Caminas un 30 % más rápido, para siempre." },
	{ id = "bigStore", passId = 2089803567, robux = 99, group = "Para siempre", name = "Despensa sin fondo", desc = "La colonia trabaja 24 horas sin ti, y al 100 %." },
	{ id = "bigCarry", passId = 2088795574, robux = 129, group = "Para siempre", name = "Mochila grande", desc = "Cargas un 50 % más de trozos en cada viaje, para siempre." },
	-- Una vez por cuenta: el contenido se entrega la primera vez que se tiene el pase (data.paid.starter)
	{ id = "starterPack", passId = 2089275586, robux = 99, group = "Para siempre", name = "Paquete de inicio", desc = "Una sola vez: 30 minutos de trabajo de tu colonia, 30 minutos de comida x2, 10 de jalea real y un huevo dorado." },
	{ id = "goldHill", passId = 2089629651, robux = 79, group = "Aspecto", name = "Hormiguero dorado", desc = "Adornos de oro en tu hormiguero, que ven todas, y la estela Cometa. Solo aspecto: no da comida." },
}

-- Productos: se pueden comprar las veces que quieras.
-- Cada uno lleva su equivalente en minutos de juego (para la revisión de balance): nada de pago da
-- algo que no se pueda conseguir jugando; solo adelanta tiempo. Minutos de capa: tools/sim.py.
-- layers: tramo de capas que abre esa excavadora. gift: se le regala a otra jugadora del servidor.
-- wide: beneficia a todo el servidor y se anuncia con el nombre de quien lo compró.
Config.Products = {
	-- Avance. Excavadora ≈ la comida de excavar esa capa (activo hoy en el simulador: capas 2-4
	-- unos 18, 8 y 4 min; de la 5 en adelante, de 2 min a segundos: por eso cuesta menos por capa)
	{ id = "dig1", productId = 3731485910, robux = 49, group = "Avance", layers = { 2, 4 }, name = "Excavadora", desc = "Excava ya la siguiente capa sin pagar comida. Para abrir las capas 2, 3 o 4." },
	{ id = "dig2", productId = 3731486042, robux = 79, group = "Avance", layers = { 5, 8 }, name = "Excavadora grande", desc = "Excava ya la siguiente capa sin pagar comida. Para abrir las capas 5 a 8." },
	{ id = "dig3", productId = 3731486058, robux = 99, group = "Avance", layers = { 9, 12 }, name = "Excavadora pesada", desc = "Excava ya la siguiente capa sin pagar comida. Para abrir las capas 9 a 12." },
	{ id = "dig4", productId = 3731486072, robux = 129, group = "Avance", layers = { 13, 14 }, name = "Excavadora gigante", desc = "Excava ya la siguiente capa sin pagar comida. Para abrir las capas 13 y 14." },
	-- ≈ la mitad de la comida de excavar la capa siguiente
	{ id = "halfDig", productId = 3731486092, robux = 39, group = "Avance", name = "Pala dorada", desc = "La próxima capa que excaves cuesta la mitad de comida. Se guarda hasta que la uses." },
	-- ≈ 30 min con la comida de la zona siguiente (cada trozo vale unas 4 veces más); la capa no cambia
	{ id = "zoneKey", productId = 3731486122, robux = 29, group = "Avance", name = "Llave maestra", desc = "Abre la puerta de la zona siguiente durante 30 minutos para que la pruebes. Tu capa no cambia." },
	-- Tiempo. Saco = 15 min de colonia; caja = 60; carretilla = 240. Frenesí ≈ 2 min de comida
	-- (x3 durante 60 s). Huevo = 10 min de colonia (Config.Egg.PaidSeconds).
	{ id = "sack", productId = 3731486161, robux = 29, group = "Tiempo", name = "Saco de comida", desc = "15 minutos de trabajo de tu colonia, de golpe." },
	{ id = "crate", productId = 3731486197, robux = 69, group = "Tiempo", name = "Caja de comida", desc = "1 hora de trabajo de tu colonia, de golpe." },
	{ id = "bigSack", productId = 3731486225, robux = 179, group = "Tiempo", name = "Carretilla", desc = "4 horas de trabajo de tu colonia, de golpe." },
	{ id = "frenzy", productId = 3731486252, robux = 19, group = "Tiempo", name = "Frenesí ya", desc = "Un minuto de frenesí al instante." },
	{ id = "egg", productId = 3731486283, robux = 25, group = "Tiempo", name = "Huevo dorado", desc = "Un huevo dorado junto a tu hormiguero con 10 minutos de trabajo de tu colonia." },
	-- Potenciadores. Poción: +15 / +60 min de comida (dobla lo que ganas ese rato). Velocidad +40 %
	-- 15 min ≈ +3-4 min de comida a mano. Imán 15 min ≈ +1-2 min. Jalea x2 ≈ un enjambre más.
	{ id = "potion", productId = 3731486315, robux = 25, group = "Potenciadores", name = "Poción x2", desc = "Toda la comida vale el doble durante 15 minutos. Se acumula." },
	{ id = "bigPotion", productId = 3731486351, robux = 79, group = "Potenciadores", name = "Poción x2 grande", desc = "Toda la comida vale el doble durante 60 minutos. Se acumula." },
	{ id = "speedBoost", productId = 3731486393, robux = 25, group = "Potenciadores", name = "Patas de saltamontes", desc = "Caminas un 40 % más rápido durante 15 minutos. Se acumula." },
	{ id = "magnet", productId = 3731486425, robux = 29, group = "Potenciadores", name = "Imán de comida", desc = "Durante 15 minutos, la comida pequeña (la que acabas en 2 mordiscos) salta sola a ti desde 16 pasos." },
	{ id = "jellyBoost", productId = 3731486463, robux = 99, group = "Potenciadores", name = "Jalea x2", desc = "Tu próximo enjambre da el doble de jalea real. Se guarda hasta que enjambres." },
	-- Jalea: 5 y 30 de jalea real
	{ id = "jar", productId = 3731486501, robux = 49, group = "Jalea", name = "Tarro de jalea", desc = "5 de jalea real." },
	{ id = "bigJar", productId = 3731486538, robux = 199, group = "Jalea", name = "Barril de jalea", desc = "30 de jalea real." },
	-- Para todas: +5 min de comida a cada jugadora conectada (y relleno de la zona); la lluvia, ~25
	-- comidas doradas (x10) repartidas por las zonas abiertas y 5 min con más comida dorada
	{ id = "feast", productId = 3731486571, robux = 99, group = "Para todas", wide = true, name = "Banquete instantáneo", desc = "Rellena ya la comida de tu zona más honda y toda la comida vale el doble durante 5 minutos para todas las del servidor." },
	{ id = "goldRain", productId = 3731486615, robux = 149, group = "Para todas", wide = true, name = "Lluvia dorada", desc = "Caen comidas doradas en todas las zonas abiertas y, durante 5 minutos, 1 de cada 4 comidas nuevas sale dorada. Tu nombre sale en el mercadillo." },
	-- Regalos: lo mismo que la poción pequeña y el saco, para otra jugadora del servidor
	{ id = "giftPotion", productId = 3731486674, robux = 25, group = "Regalos", gift = true, name = "Regalo: poción x2", desc = "Regalas a otra jugadora del servidor 15 minutos de comida doble." },
	{ id = "giftSack", productId = 3731486712, robux = 29, group = "Regalos", gift = true, name = "Regalo: saco de comida", desc = "Regalas a otra jugadora del servidor 15 minutos de trabajo de su colonia." },
}

-- Jardín con mucha gente (src/server/Garden.luau, tools/sim.py).
-- Escala = 1 + PlayerStep por jugadora de más + WorkerStep * log10(1 + obreras sin rastro / WorkerRef),
-- como mucho MaxScale. Cada comida del jardín busca count * escala ejemplares y vuelve
-- min(escala, RespawnMax) veces antes. Todas las colonias juntas se llevan como mucho DrainShare de
-- lo que rebrota el jardín, a partes iguales. Las obreras sin rastro no comen a menos de Near studs
-- de un hormiguero ajeno ni lo que alguien mordió hace menos de BittenGrace s. Junto al hormiguero
-- de quien va por la capa NewcomerDepth o menos, si a Near studs quedan menos de NearMin comidas,
-- sale comida hasta NearFill.
Config.Garden = {
	PlayerStep = 0.2,
	WorkerStep = 0.3,
	WorkerRef = 25,
	MaxScale = 2.4,
	RespawnMax = 2,
	DrainShare = 0.18, -- antes 0.5: con racimos y obreras más rápidas el jardín sostenía demasiada colonia
	Near = 62,
	BittenGrace = 3,
	NearMin = 6,
	NearFill = 8,
	NewcomerDepth = 2,
	-- Sucesos pequeños: el primero a los First s de abrir el servidor, luego uno cada GapMin-GapMax s.
	-- A quien entra por primera vez le llega una mariposa a los Welcome s si no vio ninguno antes.
	Happen = { First = 50, GapMin = 120, GapMax = 180, Welcome = 45 },
	-- Regalo: Seconds s de tu colonia o FloorBites mordiscos a la primera comida de tu zona (lo que
	-- sea más). Sorpresa: jalea (solo si ya enjambraste) o SpeedTime s andando SpeedMult veces más rápido.
	Gift = { Seconds = 30, FloorBites = 20, Life = 40, Reach = 5, JellyChance = 0.25, SpeedChance = 0.4, SpeedMult = 1.4, SpeedTime = 30 },
	Happy = { Duration = 30, Mult = 2 }, -- hora feliz: la comida del jardín vale Mult
	-- Pan gigante: Scale veces una miga, con BaseHp + LoadsPerPlayer cargas de cada conectada de vida.
	-- Cada trozo vale como la primera comida de tu capa más honda, por ValueMult. Se va a los Life s.
	Loaf = { Scale = 4.5, BaseHp = 150, LoadsPerPlayer = 4, ValueMult = 1.5, Life = 75 },
	Mushroom = { Launch = 80 }, -- velocidad hacia arriba de la seta saltarina
}

-- Primeros pasos (src/server/Opening.luau): Bites trozos mordidos, primera entrega, primera mejora,
-- correr, primera obrera y capa 2. Prizes: comida al completar cada paso. Los Juicy primeros trozos
-- del jardín que muerde quien empieza valen JuicyMult veces.
Config.Opening = { Bites = 3, Prizes = { 15, 50, 20, 50, 125, 7500 }, Juicy = 30, JuicyMult = 2 }

-- Vecinas (src/server/Social.luau y src/client/Social.luau): despensa y asalto, regalos, amistad,
-- morder en dúo y saludo de antenas. Nadie pierde progreso: lo que se roba sale de un extra creado.
-- "Ingreso" de una jugadora = lo mayor entre data.rate (colonia) y lo que entregó en los últimos
-- PantryCapSeconds s por segundo, con un suelo de medio mordisco por segundo a la comida de su zona.
-- Presupuesto: todo lo social junto debería quedarse en ~10 % del ingreso de una jugadora activa
-- (despensa 8 % de las entregas, amistad como mucho 5 %, regalos limitados por la hucha al 4 %,
-- dúo solo mientras se muerde a la vez la misma comida).
Config.Social = {
	-- Despensa: cada entrega propia mete PantryShare de lo acreditado como comida EXTRA (no se quita a
	-- nadie), con modo pacífico la mitad (PeaceShare). Tope: PantryShare de lo entregado en los últimos
	-- PantryCapSeconds s. La dueña la cobra entera al pisarla (a PantryReach studs, por la escala).
	-- Sitio: centro + (inward * Spot[1] + side * Spot[2]) * escala (lejos del cartel, huevo y túnel).
	PantryShare = 0.08,
	PeaceShare = 0.5,
	PantryCapSeconds = 180,
	PantryReach = 6,
	PantrySpot = { 2, 12.5 },
	-- Asalto: cada mordisco a una despensa ajena (a Reach studs) arranca BiteShare del tope del
	-- asalto, que es lo menor entre CapSeconds s del ingreso de la LADRONA y lo que haya en la
	-- despensa. Protegidas: quien lleva menos de MinTenure s en el servidor o va por una capa menor
	-- que MinDepth. Tras un asalto (cobrado o escapado) esa despensa queda Protect s cerrada para esa
	-- ladrona; si la pillan, CaughtBlock s. Gap: segundos entre dos asaltos de la misma ladrona.
	-- Si la dueña muerde a la ladrona (a CatchReach studs), cobra el botín por OwnerMult.
	-- Más lejos que Leave studs del hormiguero asaltado, la ladrona ya ha huido.
	Raid = {
		Reach = 7,
		BiteShare = 0.2,
		CapSeconds = 40,
		MinTenure = 300,
		MinDepth = 2,
		Protect = 60,
		CaughtBlock = 20,
		Gap = 20,
		OwnerMult = 1.5,
		CatchReach = 7,
		Leave = 75,
	},
	-- Guardianas: salen Delay s después del primer mordisco, Min + 1 por cada PerSoldiers soldados de
	-- la dueña (hasta Max). Corren a la velocidad al andar de la ladrona por SpeedBase + SpeedPerSoldier
	-- por soldado (como mucho SpeedMax): andando te pillan, corriendo (x1.35) o con turbo te escapas.
	-- Persiguen hasta Leash studs del hormiguero o ChaseTime s. Alcanzar = a CatchRange studs.
	-- Launch/LaunchUp: impulso del lanzamiento por los aires (en el cliente de la ladrona, sin daño).
	Guard = {
		Min = 2,
		Max = 6,
		PerSoldiers = 3,
		Delay = 1.1,
		SpeedBase = 1.08,
		SpeedPerSoldier = 0.015,
		SpeedMax = 1.3,
		Leash = 60,
		ChaseTime = 14,
		CatchRange = 3.5,
		Launch = 70,
		LaunchUp = 60,
	},
	-- Regalo: con carga, a Range studs de otra jugadora. Ella cobra (carga/capacidad) * CapSeconds s de
	-- SU ingreso, entre FloorSeconds y CapSeconds; tú recuperas Refund de lo que llevabas más Gratitude.
	-- Cooldown s por pareja. Hucha de la que recibe (en segundos de su ingreso): empieza en
	-- BudgetStart, se llena BudgetRate s por segundo hasta BudgetMax; un regalo nunca paga más de lo que
	-- hay en la hucha (así los regalos no pasan de ~4 % del ingreso). El primer regalo a una recién
	-- llegada (menos de WelcomeWindow s en el servidor) vale WelcomeMult a las dos y no gasta hucha.
	Gift = {
		Key = "H",
		Range = 12,
		Cooldown = 180,
		FloorSeconds = 30,
		CapSeconds = 120,
		Refund = 0.6,
		Gratitude = 0.1,
		BudgetStart = 60,
		BudgetRate = 0.04,
		BudgetMax = 120,
		WelcomeMult = 2,
		WelcomeWindow = 300,
	},
	-- Amistad: cada regalo entre dos sube su vínculo un nivel (hasta Max); el mejor nivel con cada
	-- UserId se guarda (como mucho Keep amigas). Mientras las dos estén en el servidor, cada una gana
	-- PerLevel de comida por nivel, sumando todas sus amigas presentes hasta MaxBonus.
	Friend = { Max = 5, PerLevel = 0.02, MaxBonus = 0.05, Keep = 60 },
	-- Dúo: dos que muerden la misma comida con menos de Window s de diferencia ganan Bonus del valor
	-- de esos mordiscos. La cuenta "DÚO xn" se reinicia tras Reset s sin mordisco en dúo.
	Duo = { Window = 2, Bonus = 0.25, Reset = 3 },
	-- Saludo de antenas: dos quietas (menos de Still studs/s) cara a cara (Facing) a menos de Range
	-- studs durante Hold s. Ambas andan SpeedMult más rápido Duration s. Cooldown s por pareja.
	Greet = { Range = 5, Hold = 0.8, Still = 2, Facing = 0.4, SpeedMult = 1.1, Duration = 60, Cooldown = 120 },
	-- Interruptor de modo pacífico: no se puede cambiar más de una vez cada PeaceCooldown s.
	PeaceCooldown = 30,
}

-- Castas (src/server/CasteService.luau, Shared/Castes): desde la capa UnlockDepth eliges una.
-- Lo que arrancan las habilidades vuela solo al hormiguero y se acredita al PowerShare de su valor.
-- Cambiar de casta deja las habilidades en enfriamiento y bloquea el cambio SwitchLock s. Cada casta
-- dominada (rango MaxRank) da MasteryFood más de comida para siempre.
-- Experiencia, en "mordiscos equivalentes" (trozos / mordida): el rango r pide XpBase * (r - 1) ^ XpPow
-- acumulada (rango 2 en un par de minutos, rango 10 en torno a una hora). Cada mordisco equivalente
-- da XpHand a mano (como mucho XpBiteMax por mordisco), XpPower de habilidad y XpPassive de pasiva.
-- Tope: se gana como mucho XpRate por segundo, con una reserva de XpBurst para las ráfagas.
Config.Castes = {
	PowerShare = 0.6,
	SwitchLock = 30,
	UnlockDepth = 2,
	MasteryFood = 0.03,
	MaxRank = 10,
	XpBase = 40,
	XpPow = 2.2,
	XpHand = 1,
	XpBiteMax = 3,
	XpPower = 0.5,
	XpPassive = 0.5,
	XpRate = 2.5,
	XpBurst = 45,
	MutationRanks = { 2, 4, 5, 7, 9 },
	AbilityRanks = { 1, 3, 6 },
}

-- Órdenes y escuadrones (src/server/Orders.luau, src/client/Orders.luau): adónde van las obreras que
-- no siguen un rastro marcado a mano. Una orden solo cambia el reparto entre distancia y valor: lo que
-- traen sale de la misma cuenta de Colony (carga / viaje de ida y vuelta, tope de una comida en 3 s,
-- parte del jardín de cada colonia), sin multiplicadores propios. Sin orden elegida nunca, Colony
-- elige como siempre (el jardín, lo más grande primero).
-- Referencia (capa 4, 150 obreras a ~17,6 studs/s, carga ~280): en el jardín manda el tope por
-- comida (una miga da 1 trozo/s por hueco): "lo más cercano" ~3 de valor/s, lo de siempre ~80/s;
-- "lo más rico" / "lo que más rinde" en la zona 4 ~75 000/s, lo mismo que un rastro marcado al
-- plátano (sin la feromona dulce). Entre las órdenes del túnel (rico, rinde, zona, la grande) hay
-- de 1x a 2x. La distancia grande (jardín contra túnel) ya existía: es la de no marcar rastros.
Config.Orders = {
	-- Sin Rastro (Feromonas) ninguna orden sale del jardín: lo hondo sigue pidiendo esa mejora, como
	-- supone tools/sim.py. DeepWorth: valor de lo que traen las órdenes fuera del jardín (1 = igual que
	-- con rastro; bájalo, p. ej. a 0.7, si marcar a mano debe rendir claramente más que una orden).
	DeepNeedsTrail = true,
	DeepWorth = 1,
	Recalc = 2, -- s entre repasos de la lista de comida de cada colonia (no cada tick)
	EstimateEvery = 2, -- s entre estimaciones de comida/s mientras el panel está abierto
	SideRadius = 40, -- "A mi lado": comida a menos de esto de ti (studs)
	SideKeep = 60, -- y la sueltan cuando te alejas más que esto
	Step = 10, -- el reparto entre escuadrones va en pasos de 10 %
	MinShare = 10, -- ningún escuadrón con menos
	-- Escuadrones: obreras (o capa) que hacen falta para el segundo y el tercero, y su color
	Squads = {
		{ name = "Rojo", color = Color3.fromRGB(230, 57, 70) },
		{ name = "Azul", color = Color3.fromRGB(62, 193, 243), workers = 40 },
		{ name = "Verde", color = Color3.fromRGB(110, 200, 90), workers = 150 },
	},
	-- En orden de aparición. workers / depth: obreras y capa que hacen falta.
	List = {
		{ id = "near", name = "Lo más cercano", workers = 1, desc = "La comida más cerca de casa. Viajes cortos, poco valor." },
		{ id = "rich", name = "Lo más rico", workers = 5, desc = "Lo que más vale por trozo, en lo más hondo que alcancen. Viajes largos." },
		{ id = "side", name = "A mi lado", depth = 2, desc = "Trabajan a tu alrededor y se mueven contigo." },
		{ id = "yield", name = "Lo que más rinde", workers = 25, desc = "Lo que más comida trae por segundo, contando ida y vuelta." },
		{ id = "finish", name = "Rematar", workers = 50, desc = "Primero lo ya empezado: terminan comidas y limpian la zona." },
		{ id = "zone", name = "Zona elegida", depth = 3, desc = "Solo la zona que tú elijas." },
		{ id = "big", name = "A por la grande", depth = 4, desc = "Todas contra la comida más grande que puedan." },
	},
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
