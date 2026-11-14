-- Fórmulas puras: de niveles de mejoras a estadísticas y costos.
-- Las usa el servidor (para mandar) y el cliente (para mostrar), así nunca se contradicen.

local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local Stats = {}

Stats.MaxDepth = #Config.Layers

local function lvl(levels, id): number
	return levels[id] or 0
end

local PLAYER = Config.Player
local MILESTONE = Config.Milestones

-- Cuántos hitos (Config.Milestones.Levels) lleva una mejora a ese nivel. Cada hito multiplica su
-- efecto por Config.Milestones.Mult (la carga, por CarryMult). La celebración en pantalla lo lee de aquí.
function Stats.milestones(level: number): number
	return Config.milestones(level)
end

-- Siguiente nivel con hito por encima de `level` (nil si ya los tiene todos)
function Stats.nextMilestone(level: number): number?
	for _, at in MILESTONE.Levels do
		if at > level then
			return at
		end
	end
	return nil
end

-- Fuerza de mordida de Mordida fuerte (con sus hitos). Una parte (BiteSplit) es arrancar trozos y el
-- resto, que cada trozo rinda más (Stats.biteYield).
function Stats.bitePower(bite: number): number
	return PLAYER.BitePower ^ bite * MILESTONE.Mult ^ Config.milestones(bite)
end

-- Trozos por mordisco con Mordida fuerte a ese nivel (antes de galerías)
function Stats.biteDamage(bite: number): number
	return Config.levelBite(bite)
end

-- Lo que rinde cada trozo por Mordida fuerte (va al multiplicador de comida)
function Stats.biteYield(bite: number): number
	return Stats.bitePower(bite) ^ (1 - PLAYER.BiteSplit)
end

-- Carga de Lomo fuerte a ese nivel (con sus hitos), antes de multiplicarla por lo bien que muerdes
function Stats.capacity(carry: number): number
	return PLAYER.Capacity * PLAYER.CarryGrowth ^ carry * MILESTONE.CarryMult ^ Config.milestones(carry)
end

function Stats.walkSpeed(speed: number, royalSpeed: number, landing: number?): number
	return (PLAYER.WalkSpeed + PLAYER.SpeedStep * speed) * (1 + Config.Rebirth.SpeedStep * royalSpeed) * (1 + Config.Wings.LandingSpeed * (landing or 0))
end

-- Carga de una obrera con Obreras fuertes a ese nivel (con sus hitos)
function Stats.workerCarry(level: number): number
	return Config.Worker.Carry * Config.Worker.CarryGrowth ^ level * MILESTONE.Mult ^ Config.milestones(level)
end

-- Saltos de la mordida en cadena: mordiscos tuyos que arranca en total, sumando todos
function Stats.chainBites(jumps: number): number
	local total = 0
	for k = 1, jumps do
		total += Config.Chain.First * Config.Chain.Share ^ (k - 1)
	end
	return total
end

-- El montículo crece con cada capa sin pisar a sus vecinos (a unos 60 studs): x1.65 en la capa 14
function Stats.hillScale(depth: number): number
	return 1 + 0.05 * (math.clamp(depth, 1, Stats.MaxDepth) - 1)
end

-- Suma lo que dan las galerías compradas, por tipo. Las de "cheap" multiplican (cada una abarata un
-- poco lo que ya estaba abaratado) y las reglas con nombre cuentan niveles: totals.perks[id].
local function miniTotals(minis)
	local totals = { cheapMult = 1, perks = {} }
	if minis then
		for id, owned in minis do
			local def = owned == true and Config.MiniById[id]
			if def then
				if def.kind == "perk" then
					totals.perks[def.perk] = (totals.perks[def.perk] or 0) + 1
				elseif def.kind == "cheap" then
					totals.cheapMult *= 1 - def.amount
				else
					totals[def.kind] = (totals[def.kind] or 0) + def.amount
				end
			end
		end
	end
	return totals
end

-- Fuerza de una regla con nombre según las galerías compradas (0 = no la tienes)
function Stats.perk(stats, id: string): number
	return Config.perkValue(id, stats.perks and stats.perks[id] or 0)
end

-- Aliadas: cada número por nivel (0 = no la tienes). Las usan derive y las fichas del árbol.
local ALLY = Config.Allies
local EXTRA = Config.Extras -- mejoras que cambian cómo juegas (charged, doubleJaw, buche...)

-- Valor de una mejora que empieza en `base` y cambia `step` por nivel a partir del primero
local function ramp(l: number, base: number, step: number): number
	return if l > 0 then base + step * (l - 1) else 0
end

function Stats.beeInterval(l: number): number
	local bee = ALLY.Bee
	return if l > 0 then math.max(bee.MinInterval, math.floor(bee.Interval - bee.Step * (l - 1) + 0.5)) else 0
end

-- Lo que vale una comida dorada para quien tiene `l` niveles de Olfato dorado
function Stats.goldFoodMult(l: number): number
	return Config.GoldFood.Mult + Config.GoldFood.MultStep * l
end

-- Probabilidad de que una comida aparezca dorada si el mejor Olfato dorado conectado es `l`
function Stats.goldFoodChance(l: number): number
	return Config.GoldFood.Chance + Config.GoldFood.ChanceStep * l
end

-- minis: { [idGalería] = true } (opcional)
function Stats.derive(nodes, royal, depth: number?, minis: { [string]: boolean }?)
	local nursery = lvl(nodes, "nursery")
	local beetle = lvl(nodes, "beetle")
	local storage = lvl(nodes, "storage")
	local area = lvl(nodes, "area")
	local eggs = lvl(nodes, "eggs")
	local fungus = lvl(nodes, "fungus")
	local layer = depth or 1
	-- Galerías: las sencillas suman cantidades fijas (las de mordida, carga y obreras van a la base,
	-- antes de los multiplicadores) y las reglas con nombre cuentan niveles (Stats.perk)
	local mini = miniTotals(minis)
	local function m(kind: string): number
		return mini[kind] or 0
	end
	local function perk(id: string): number
		return Config.perkValue(id, mini.perks[id] or 0)
	end
	local zoneMult = {}
	for zone = 1, #Config.Zones do
		zoneMult[zone] = if zone == layer then 1 + perk("palate") / 100 else 1 -- Paladar fino
	end
	local COLONY = Config.Colony
	local bite = lvl(nodes, "bite")
	-- Mordida fuerte: arranca más (biteDamage) y cada trozo rinde más (biteYield). Mandíbula titán y
	-- Mandíbulas reales solo hacen rendir: no acortan la comida de tu zona ni los viajes.
	local levelBite = Stats.biteDamage(bite)
	local biteDamage = math.max(1, math.floor(levelBite + m("bite") + 0.5))
	-- Mordisco veloz: por debajo del enfriamiento mínimo, lo que sobra se vuelve comida
	local rawCooldown = PLAYER.BiteCooldown * PLAYER.ChewStep ^ lvl(nodes, "chew") / (1 + m("chew"))
	local biteCooldown = math.max(PLAYER.MinBiteCooldown, rawCooldown)
	local chewYield = PLAYER.MinBiteCooldown / math.min(rawCooldown, PLAYER.MinBiteCooldown)
	local biteYield = Stats.biteYield(bite) * PLAYER.TitanPower ^ lvl(nodes, "titan") * 2 ^ lvl(royal, "royalBite") * chewYield
	local foodMult = (1 + 0.5 * lvl(royal, "royalFood")) * biteYield
	local carryScale = PLAYER.GiantCarry ^ lvl(nodes, "giant")
	local workerScale = COLONY.Super ^ lvl(nodes, "super")
	local critChance = math.min(PLAYER.CritCap, PLAYER.CritStep * lvl(nodes, "crit") + m("crit"))
	local critMult = PLAYER.CritMult + PLAYER.BrutalStep * lvl(nodes, "brutal") + m("critHit")
	local jawShare = ramp(lvl(nodes, "doubleJaw"), EXTRA.DoubleJaw.Share, EXTRA.DoubleJaw.Step)
	local chainJumps = if lvl(nodes, "chain") > 0 then lvl(nodes, "chain") + m("chain") else 0
	local escorts = lvl(nodes, "escort")
	local megaEvery = ramp(lvl(nodes, "mega"), ALLY.Mega.Every, -ALLY.Mega.Step)
	local megaMult = ramp(lvl(nodes, "mega"), ALLY.Mega.Mult, ALLY.Mega.MultStep)
	-- Trozos que entran de media por cada mordisco tuyo, en mordiscos normales: mordida doble y racha
	-- (en la comida mordida), por lo que arrancan a las de al lado área, doble mandíbula, cadena, escolta
	-- y mega crunch. Eso último, como mucho NeighborCap veces: más allá, en vez de comerse el racimo de
	-- una pulsación, rinde comida. La carga crece con esto: todo lo que te hace morder mejor llena
	-- viajes más ricos, no viajes más cortos (las pulsaciones por viaje no cambian).
	local neighbors = 1 + PLAYER.AreaShare * math.min(3, area)
	neighbors *= 1 + jawShare
	neighbors *= 1 + Stats.chainBites(chainJumps) / Config.Chain.Typical
	neighbors *= 1 + ALLY.Escort.Share * escorts * PLAYER.BiteCooldown / ALLY.Escort.Tick
	if megaEvery > 0 then
		neighbors *= 1 + (megaMult - 1) / megaEvery
	end
	local neighborScale = math.min(neighbors, PLAYER.NeighborCap) / neighbors
	foodMult *= (neighbors / math.min(neighbors, PLAYER.NeighborCap)) ^ PLAYER.NeighborYield
	local harvest = (1 + critChance * (critMult - 1)) * (1 + Config.Combo.Step * math.min(10 * lvl(nodes, "combo"), Config.Combo.Typical))
		* math.min(neighbors, PLAYER.NeighborCap)
	-- Velocidad: con techo; lo que las mejoras den de más se vuelve comida
	local rawWalk = Stats.walkSpeed(lvl(nodes, "speed") + m("speed"), lvl(royal, "royalSpeed"), lvl(nodes, "landing"))
	local walkSpeed = math.min(rawWalk, PLAYER.MaxWalk)
	foodMult *= (rawWalk / walkSpeed) ^ PLAYER.SpeedYield
	-- Mejoras con yield: cada nivel, toda tu comida x(1 + yield) (Config.Tree y Config.Royal)
	for _, def in Config.Tree do
		if def.yield then
			foodMult *= (1 + def.yield) ^ lvl(nodes, def.id)
		end
	end
	for _, def in Config.Royal do
		if def.yield then
			foodMult *= (1 + def.yield) ^ lvl(royal, def.id)
		end
	end
	-- Carga: la de Lomo fuerte (y galerías de carga) por todo lo que sube la mordida aparte de Mordida
	-- fuerte. Suelo: un viaje nunca se llena con menos de MinLoadBites mordiscos normales. Con las
	-- mejoras al día la fórmula queda en 14-20 mordiscos, por encima del suelo: cada compra de carga
	-- (Lomo fuerte +8 %, galería de carga ~+8 %, gigante +15 %, escarabajo +8 %) sube el número.
	local ownCapacity = math.max(
		math.floor((Stats.capacity(lvl(nodes, "carry")) + m("carry")) * (biteDamage / levelBite) * harvest * carryScale),
		math.ceil(PLAYER.MinLoadBites * biteDamage * harvest)
	)
	return {
		depth = layer,
		hillScale = Stats.hillScale(layer),
		miniTotals = mini, -- lo que suman las galerías de cada tipo (para la ficha)
		perks = mini.perks, -- [regla] = nivel (src/server/Perks.luau)
		-- Por cuánto se multiplica lo que dan las galerías fijas, para enseñar su número real en la ficha
		miniScale = { bite = 1, carry = carryScale * harvest, workerCarry = workerScale, deposit = foodMult },
		depositFlat = m("deposit"), -- comida de más en cada entrega (la suma src/server/Perks.luau)

		biteDamage = biteDamage,
		biteYield = biteYield, -- ya va dentro de foodMult; es para enseñarlo
		harvest = harvest, -- trozos por mordisco de media, en mordiscos normales (la carga crece con esto)
		-- Por cuánto se multiplica lo que arrancan a las vecinas área, doble mandíbula, cadena, escolta y
		-- mega crunch para no pasar de Config.Player.NeighborCap (1 si no se llega)
		neighborScale = neighborScale,
		tripBites = ownCapacity / math.max(biteDamage * harvest, 1), -- mordiscos normales que caben en un viaje
		biteCooldown = biteCooldown,
		hardMult = (1 + PLAYER.VenomStep * lvl(nodes, "venom")) * math.max(1, perk("crusher")),
		biteRange = PLAYER.BiteRange + 1.5 * lvl(nodes, "reach") + m("reach"),
		critChance = critChance,
		critMult = critMult,
		comboCap = 10 * lvl(nodes, "combo"),
		canBiteHard = lvl(nodes, "saw") > 0,
		areaRadius = if area > 0 then 4 + 3 * area else 0,
		areaShare = PLAYER.AreaShare,
		goldChance = 0, -- el mordisco dorado sale de las reglas Pepita segura y Fiebre del oro (Perks.luau)
		zoneMult = zoneMult, -- [zona] = multiplicador del valor de su comida

		-- capacity cuenta también lo que lleva el escarabajo; ownCapacity es solo lo tuyo
		ownCapacity = ownCapacity,
		capacity = math.floor(ownCapacity * (1 + ALLY.Beetle.Share * beetle)),
		beetleShare = ALLY.Beetle.Share * beetle,
		walkSpeed = walkSpeed,
		rawWalkSpeed = rawWalk, -- la que darían las mejoras sin techo (lo que sobra rinde comida)
		hasSprint = lvl(nodes, "sprint") > 0,
		sprintDuration = Config.Sprint.Duration + Config.Sprint.StaminaStep * lvl(nodes, "stamina") + m("turbo"),
		hasWings = lvl(nodes, "wings") > 0,
		wingsCooldown = math.max(5, Config.Wings.Cooldown - Config.Wings.LandingStep * lvl(nodes, "landing") - m("wings")),
		fullLoadBonus = 0.1 * lvl(nodes, "fullLoad"),
		doubleChance = 0.1 * lvl(nodes, "double"),
		depositMult = 1,

		workerCap = if nursery > 0
			then math.floor(Config.NurseryCaps[nursery] * (1 + COLONY.NurseCap * lvl(nodes, "nurse"))) + 2 * m("crew")
			else 0,
		workerSpeed = (Config.Worker.Speed + m("workerSpeed")) * (1 + Config.Worker.SpeedStep * lvl(nodes, "workerSpeed")),
		workerCarry = (Stats.workerCarry(lvl(nodes, "workerCarry")) + m("workerCarry")) * workerScale,
		workerDiscount = mini.cheapMult,
		colonyMult = COLONY.Barracks ^ lvl(nodes, "barracks") * COLONY.Legion ^ lvl(nodes, "legion")
			* 1.5 ^ lvl(royal, "royalColony") * (if lvl(nodes, "queen") > 0 then COLONY.Queen else 1),
		colonySpread = COLONY.Spread, -- comidas del racimo que se reparten lo que no cabe en la marcada
		tripMult = COLONY.Express ^ lvl(nodes, "express"),
		trailBonus = (1 + COLONY.Sweet * lvl(nodes, "sweet")) * (1 + m("trail")) * (if lvl(nodes, "smart") > 0 then COLONY.Smart else 1),
		soldiers = lvl(nodes, "barracks"),
		workersBreakHard = lvl(nodes, "barracks") > 0,
		queen = lvl(nodes, "queen") > 0,
		offlineHours = (if storage > 0 then Config.StorageHours[storage] else 0) + m("offline") / 60,
		offlineMult = 1,

		eggs = eggs,
		eggInterval = math.max(
			Config.Egg.MinInterval * 0.6,
			math.max(Config.Egg.MinInterval, Config.Egg.Interval - Config.Egg.IntervalStep * eggs) - m("eggTime")
		),
		eggSeconds = Config.Egg.Seconds + Config.Egg.SecondsStep * eggs + m("eggValue"),
		eggMult = 1,
		fungus = fungus,
		buffDuration = Config.Fungus.Duration + Config.Fungus.Step * fungus + m("fungus"),

		trailSlots = lvl(nodes, "trail"),
		hasFrenzy = lvl(nodes, "frenzy") > 0,
		frenzyDuration = Config.Frenzy.Duration + Config.Frenzy.LenStep * lvl(nodes, "frenzyLen") + m("frenzyLen"),
		frenzyCooldown = math.max(30, Config.Frenzy.Cooldown - Config.Frenzy.HiveStep * lvl(nodes, "hive") - m("frenzyCd")),
		frenzyMult = Config.Frenzy.Mult + lvl(nodes, "royalPher"),
		smartTrail = lvl(nodes, "smart") > 0,

		foodMult = foodMult,
		jellyMult = (1 + 0.15 * lvl(royal, "royalJelly")) * (1 + m("jelly")),

		-- Aliadas (0 = no la tienes). Las galerías de abeja e imán solo cuentan si ya la tienes.
		beeInterval = if lvl(nodes, "bee") > 0 then math.max(6, Stats.beeInterval(lvl(nodes, "bee")) - m("bee")) else 0,
		beeOnFull = lvl(nodes, "bee") >= ALLY.Bee.FullAt,
		beeSpeed = ramp(lvl(nodes, "bee"), ALLY.Bee.Speed, ALLY.Bee.SpeedStep),
		magnetRadius = if lvl(nodes, "magnet") > 0 then ramp(lvl(nodes, "magnet"), ALLY.Magnet.Radius, ALLY.Magnet.RadiusStep) + m("magnet") else 0,
		escorts = escorts,
		stompCooldown = ramp(lvl(nodes, "stomp"), ALLY.Stomp.Cooldown, -ALLY.Stomp.Step),
		stompRadius = ramp(lvl(nodes, "stomp"), ALLY.Stomp.Radius, ALLY.Stomp.RadiusStep),
		slingCooldown = ramp(lvl(nodes, "sling"), ALLY.Sling.Cooldown, -ALLY.Sling.Step),
		slingRange = ramp(lvl(nodes, "sling"), ALLY.Sling.Range, ALLY.Sling.RangeStep),
		lensInterval = ramp(lvl(nodes, "lens"), ALLY.Lens.Interval, -ALLY.Lens.Step),
		lensMult = ramp(lvl(nodes, "lens"), ALLY.Lens.Mult, ALLY.Lens.MultStep),
		megaEvery = megaEvery,
		megaMult = megaMult,

		-- Mejoras que cambian cómo juegas (Config.Extras; 0 = no la tienes)
		chargeMax = ramp(lvl(nodes, "charged"), EXTRA.Charged.Max, EXTRA.Charged.Step),
		chargeMult = ramp(lvl(nodes, "charged"), EXTRA.Charged.Mult, EXTRA.Charged.MultStep),
		jawShare = jawShare,
		bucheShare = ramp(lvl(nodes, "buche"), EXTRA.Buche.Share, EXTRA.Buche.Step),
		hasOutpost = lvl(nodes, "outpost") > 0,
		giantInterval = ramp(lvl(nodes, "giantFood"), EXTRA.Giant.Interval, -EXTRA.Giant.Step),
		giantMult = ramp(lvl(nodes, "giantFood"), EXTRA.Giant.Mult, EXTRA.Giant.MultStep),
		rainCooldown = ramp(lvl(nodes, "rain"), EXTRA.Rain.Cooldown, -EXTRA.Rain.Step),
		rainCount = ramp(lvl(nodes, "rain"), EXTRA.Rain.Count, EXTRA.Rain.CountStep),
		laneMult = if lvl(nodes, "lane") > 0 then ramp(lvl(nodes, "lane"), EXTRA.Lane.Mult, EXTRA.Lane.MultStep) else 1,

		-- Comida dorada, túnel y mordida en cadena
		goldFood = lvl(nodes, "goldFood"), -- su nivel sube la probabilidad para todo el servidor
		goldFoodMult = Stats.goldFoodMult(lvl(nodes, "goldFood")),
		hasTunnel = lvl(nodes, "tunnel") > 0,
		chainJumps = chainJumps,
	}
end

-- Una galería se puede excavar cuando su capa está excavada y la anterior de su fila también.
function Stats.miniOpen(def, minis, depth: number): boolean
	return depth >= def.layer and (def.prev == nil or minis[def.prev] == true)
end

-- Lo que suman ya las galerías del tipo de `def` (con `plus`, contando también esa), con el número
-- real que se nota (la mordida fija ya multiplicada por Mandíbula titán, etc.). Una regla: su nivel.
function Stats.miniTotal(stats, def, plus: boolean?): number
	local kind = def.kind
	if kind == "perk" then
		return (stats.perks[def.perk] or 0) + (if plus then 1 else 0)
	elseif kind == "cheap" then
		return 1 - stats.miniTotals.cheapMult * (if plus then 1 - def.amount else 1)
	end
	local total = (stats.miniTotals[kind] or 0) + (if plus then def.amount else 0)
	return total * (stats.miniScale[kind] or 1)
end

-- Texto de lo que dan ya las galerías del tipo de `def` (con `plus`, contando también esa)
function Stats.miniLine(stats, def, plus: boolean?): string
	local total = Stats.miniTotal(stats, def, plus)
	if def.kind == "perk" then
		return if total > 0 then "Nivel " .. total .. ": " .. Config.perkText(def.perk, total) else "Aún no la tienes"
	end
	return Config.miniText(def.kind, total, def.layer, true)
end

-- Cómo se ve la hormiga según lo que ha comprado: lo usa el servidor para vestirla.
function Stats.look(nodes, royal, depth: number, rebirths: number, skin: string, hat: string)
	return {
		skin = skin,
		hat = hat,
		-- Los umbrales reparten cada rasgo a lo largo de las 14 capas (bite y carry llegan a 140)
		jaws = math.min(6, lvl(nodes, "bite") // 22 + lvl(nodes, "titan") // 3),
		saw = lvl(nodes, "saw") > 0,
		spikes = math.min(5, lvl(nodes, "crit") // 2 + lvl(nodes, "brutal") // 2 + lvl(nodes, "combo") // 3),
		belly = math.min(6, lvl(nodes, "carry") // 22),
		shoes = math.min(6, lvl(nodes, "speed") // 7),
		wings = lvl(nodes, "wings") > 0,
		armor = math.min(5, lvl(nodes, "barracks")),
		crown = rebirths,
		scale = 1 + 0.022 * (depth - 1) + 0.2 * lvl(nodes, "giant"),
	}
end

-- Hasta qué nivel puedes subir un nodo con tu profundidad actual.
function Stats.available(def, depth: number): number
	if def.per then
		return math.clamp(def.per * (depth - def.layer + 1), 0, def.max)
	end
	return def.max
end

-- Costo de subir un nodo del nivel `level` al siguiente.
function Stats.nodeCost(def, level: number): number
	if def.costs then
		return def.costs[level + 1] or math.huge
	end
	return math.floor(def.cost * def.growth ^ level)
end

function Stats.digCost(depth: number): number
	return if depth >= Stats.MaxDepth then math.huge else Config.DigBase * Config.StageGrowth ^ (depth - 1)
end

-- Un nodo se puede comprar cuando su capa está excavada y su cámara madre también.
function Stats.unlocked(def, nodes, workers: number, depth: number): boolean
	if depth < def.layer then
		return false
	end
	if def.needs == "workers" and workers <= 0 then
		return false
	end
	if not def.parent then
		return true
	end
	if Config.NodeById[def.parent].unit then
		return workers > 0
	end
	return (nodes[def.parent] or 0) > 0
end

-- Nivel de guardería necesario para que quepan `count` obreras.
function Stats.nurseryFor(count: number): number
	for level, cap in Config.NurseryCaps do
		if cap >= count then
			return level
		end
	end
	return #Config.NurseryCaps
end

function Stats.royalCost(def, level: number): number
	return def.cost + def.step * level
end

-- Costo de la siguiente obrera cuando ya tienes `count`.
function Stats.workerCost(count: number, discount: number?): number
	return math.floor(Config.Worker.BaseCost * Config.Worker.CostGrowth ^ count * (discount or 1))
end

function Stats.jellyFor(runFood: number, mult: number?): number
	local orders = math.log10(math.max(runFood / Config.Rebirth.Divisor, 1))
	return math.floor(orders ^ Config.Rebirth.Power * (mult or 1))
end

local function percent(x: number): string
	return tostring(math.floor(x * 100 + 0.5)) .. " %"
end

local function times(x: number): string
	return "x" .. (if x >= 100 then Format.short(x) else (string.format("%.1f", x):gsub("%.0$", "")))
end

local function seconds(x: number): string
	return (string.format("%.2f", x):gsub("0$", "")) .. " s"
end

-- 2,5 en vez de 2.5; sin decimales si es entero (como Config.miniText)
local function decimal(x: number): string
	if x >= 1000 then
		return Format.short(x)
	end
	if math.abs(x - math.floor(x + 0.5)) < 0.05 then
		return tostring(math.floor(x + 0.5))
	end
	return (string.format("%.1f", x):gsub("%.", ","))
end

local function has(yes: string, no: string)
	return function(l)
		return if l > 0 then yes else no
	end
end

-- Texto del efecto de un nodo a un nivel dado. Sirve para "ahora" y "luego" en la ficha.
-- "Hito en nivel 25: x2" (el siguiente hito de una mejora con hitos), o "" si ya los tiene todos
local function milestoneHint(l: number, mult: number): string
	local at = Stats.nextMilestone(l)
	return if at then "\nHito en nivel " .. at .. ": " .. times(mult) else ""
end

local EFFECT = {
	bite = function(l)
		return "Arrancas " .. decimal(Stats.biteDamage(l)) .. " por mordisco y la comida rinde " .. times(Stats.biteYield(l))
			.. milestoneHint(l, Config.Milestones.Mult)
	end,
	chew = function(l)
		local raw = Config.Player.BiteCooldown * Config.Player.ChewStep ^ l
		if raw >= Config.Player.MinBiteCooldown then
			return "Un mordisco cada " .. seconds(raw)
		end
		return "Un mordisco cada " .. seconds(Config.Player.MinBiteCooldown) .. " y la comida rinde " .. times(Config.Player.MinBiteCooldown / raw)
	end,
	crit = function(l)
		return percent(math.min(Config.Player.CritCap, Config.Player.CritStep * l)) .. " de mordida doble"
	end,
	saw = has("Muerdes comida dura", "La comida dura se te resiste"),
	combo = function(l)
		return if l > 0 then "Racha de hasta +" .. percent(10 * l * Config.Combo.Step) else "Sin racha"
	end,
	reach = function(l)
		return "Alcance de " .. (Config.Player.BiteRange + 1.5 * l) .. " pasos"
	end,
	area = function(l)
		return if l > 0 then "Radio de " .. (4 + 3 * l) .. " pasos" else "Solo muerdes una comida"
	end,
	brutal = function(l)
		return "La mordida doble pega " .. times(Config.Player.CritMult + Config.Player.BrutalStep * l)
	end,
	venom = function(l)
		return "Comida dura: mordida " .. times(1 + Config.Player.VenomStep * l)
	end,
	titan = function(l)
		return "Tu comida rinde " .. times(Config.Player.TitanPower ^ l)
	end,
	speed = function(l)
		local raw = Config.Player.WalkSpeed + Config.Player.SpeedStep * l
		if raw <= Config.Player.MaxWalk then
			return "Velocidad " .. decimal(raw)
		end
		return "Velocidad " .. Config.Player.MaxWalk .. " (el tope); lo que sobra: comida " .. times((raw / Config.Player.MaxWalk) ^ Config.Player.SpeedYield)
	end,
	carry = function(l)
		return "Carga " .. times(Stats.capacity(l) / Config.Player.Capacity) .. " (sin mejoras caben "
			.. math.floor(Config.Player.Capacity / Config.Player.BiteBase) .. " mordiscos)" .. milestoneHint(l, Config.Milestones.CarryMult)
	end,
	sprint = has("Turbo listo", "Solo corres"),
	stamina = function(l)
		return "El turbo dura " .. decimal(Config.Sprint.Duration + Config.Sprint.StaminaStep * l) .. " s"
	end,
	wings = has("Vuelas a casa y al túnel", "Vas caminando"),
	landing = function(l)
		return "Alas listas cada " .. decimal(math.max(5, Config.Wings.Cooldown - Config.Wings.LandingStep * l)) .. " s; velocidad +"
			.. percent(Config.Wings.LandingSpeed * l)
	end,
	fullLoad = function(l)
		return "Carga llena: +" .. percent(0.1 * l)
	end,
	giant = function(l)
		return "Tamaño " .. times(1 + 0.2 * l) .. ", carga " .. times(Config.Player.GiantCarry ^ l)
	end,
	double = function(l)
		return percent(0.1 * l) .. " de entrega doble"
	end,
	nursery = function(l)
		return if l > 0 then "Caben " .. Config.NurseryCaps[l] .. " obreras" else "Sin obreras"
	end,
	workerCarry = function(l)
		return "Carga " .. times(Stats.workerCarry(l) / Config.Worker.Carry) .. milestoneHint(l, Config.Milestones.Mult)
	end,
	workerSpeed = function(l)
		return "Velocidad " .. decimal(Config.Worker.Speed * (1 + Config.Worker.SpeedStep * l))
	end,
	nurse = function(l)
		return "Guardería +" .. percent(Config.Colony.NurseCap * l) .. " de cupo"
	end,
	storage = function(l)
		return if l > 0 then "Hasta " .. Config.StorageHours[l] .. " h sin ti" else "La colonia para al irte"
	end,
	barracks = function(l)
		return if l > 0 then "Colonia " .. times(Config.Colony.Barracks ^ l) .. " y rompe comida dura" else "Sin soldados"
	end,
	eggs = function(l)
		return if l > 0
			then "Un huevo cada " .. math.max(Config.Egg.MinInterval, Config.Egg.Interval - Config.Egg.IntervalStep * l) .. " s, vale "
				.. (Config.Egg.Seconds + Config.Egg.SecondsStep * l) .. " s de colonia (o " .. Config.Egg.FloorBites .. " mordiscos)"
			else "Sin huevos dorados"
	end,
	queen = function(l)
		return if l > 0 then "La reina cría sola; colonia " .. times(Config.Colony.Queen) else "Tú compras las obreras"
	end,
	fungus = function(l)
		return if l > 0 then "Comida doble durante " .. (Config.Fungus.Duration + Config.Fungus.Step * l) .. " s" else "Sin hongos"
	end,
	legion = function(l)
		return "Colonia " .. times(Config.Colony.Legion ^ l)
	end,
	super = function(l)
		return "Carga de obreras " .. times(Config.Colony.Super ^ l)
	end,
	trail = function(l)
		return if l == 0 then "Sin rastros" elseif l == 1 then "1 rastro" else l .. " rastros a la vez"
	end,
	sweet = function(l)
		return "Comida marcada: +" .. percent(Config.Colony.Sweet * l)
	end,
	frenzy = has("Frenesí listo", "Sin frenesí"),
	frenzyLen = function(l)
		return "El frenesí dura " .. (Config.Frenzy.Duration + Config.Frenzy.LenStep * l) .. " s"
	end,
	smart = function(l)
		return if l > 0 then "Eligen la mejor comida; marcada " .. times(Config.Colony.Smart) else "Van a lo que hay cerca de casa"
	end,
	express = function(l)
		return "Viajes un " .. percent(1 - Config.Colony.Express ^ l) .. " más cortos"
	end,
	hive = function(l)
		return "Frenesí cada " .. math.max(30, Config.Frenzy.Cooldown - Config.Frenzy.HiveStep * l) .. " s"
	end,
	royalPher = function(l)
		return "Frenesí " .. times(Config.Frenzy.Mult + l)
	end,
	bee = function(l)
		if l <= 0 then
			return "Sin abeja"
		end
		local speed = ramp(l, ALLY.Bee.Speed, ALLY.Bee.SpeedStep)
		return "Cada " .. Stats.beeInterval(l) .. " s" .. (if l >= ALLY.Bee.FullAt then " y al llenarte" else "") .. ", vuela a " .. speed .. " pasos/s"
	end,
	magnet = function(l)
		return if l > 0
			then "Cada " .. ALLY.Magnet.Tick .. " s, una comida pequeña a " .. ramp(l, ALLY.Magnet.Radius, ALLY.Magnet.RadiusStep) .. " pasos"
			else "Sin imán"
	end,
	beetle = function(l)
		return if l > 0 then "Carga " .. percent(ALLY.Beetle.Share * l) .. " más que tú sola" else "Sin escarabajo"
	end,
	escort = function(l)
		return if l == 0 then "Sin escolta" elseif l == 1 then "1 soldado" else l .. " soldados"
	end,
	stomp = function(l)
		return if l > 0
			then "Radio de " .. ramp(l, ALLY.Stomp.Radius, ALLY.Stomp.RadiusStep) .. " pasos, cada " .. ramp(l, ALLY.Stomp.Cooldown, -ALLY.Stomp.Step) .. " s"
			else "Sin pisotón"
	end,
	sling = function(l)
		return if l > 0
			then "Hasta " .. ramp(l, ALLY.Sling.Range, ALLY.Sling.RangeStep) .. " pasos, cada " .. ramp(l, ALLY.Sling.Cooldown, -ALLY.Sling.Step) .. " s"
			else "Sin tirachinas"
	end,
	lens = function(l)
		return if l > 0
			then "Quema " .. ramp(l, ALLY.Lens.Mult, ALLY.Lens.MultStep) .. " mordiscos cada " .. ramp(l, ALLY.Lens.Interval, -ALLY.Lens.Step) .. " s"
			else "Sin lupa"
	end,
	mega = function(l)
		return if l > 0
			then "Cada " .. ramp(l, ALLY.Mega.Every, -ALLY.Mega.Step) .. " mordiscos, uno " .. times(ramp(l, ALLY.Mega.Mult, ALLY.Mega.MultStep))
			else "Sin mega crunch"
	end,
	-- Mejoras que cambian cómo juegas (Config.Extras)
	charged = function(l)
		local c = EXTRA.Charged
		return if l > 0
			then "Carga hasta " .. ramp(l, c.Max, c.Step) .. " s; pega " .. times(ramp(l, c.Mult, c.MultStep)) .. " lo que habrías mordido"
			else "Siempre mordisquitos"
	end,
	doubleJaw = function(l)
		return if l > 0 then "La de al lado se lleva el " .. percent(ramp(l, EXTRA.DoubleJaw.Share, EXTRA.DoubleJaw.Step)) .. " del mordisco" else "Una comida por mordisco"
	end,
	buche = function(l)
		return if l > 0 then "Te guardas el " .. percent(ramp(l, EXTRA.Buche.Share, EXTRA.Buche.Step)) .. " de cada entrega" else "Un solo estómago"
	end,
	outpost = has("Puesto en tu zona más honda", "Todo va a casa"),
	giantFood = function(l)
		local g = EXTRA.Giant
		return if l > 0
			then "Cada " .. ramp(l, g.Interval, -g.Step) .. " s, una comida " .. times(ramp(l, g.Mult, g.MultStep))
			else "Sin comida gigante"
	end,
	rain = function(l)
		local r = EXTRA.Rain
		return if l > 0
			then ramp(l, r.Count, r.CountStep) .. " migas cada " .. ramp(l, r.Cooldown, -r.Step) .. " s"
			else "Sin lluvia"
	end,
	lane = function(l)
		return if l > 0 then "En tus rastros, velocidad " .. times(ramp(l, EXTRA.Lane.Mult, EXTRA.Lane.MultStep)) else "Rastros invisibles"
	end,
	goldFood = function(l)
		return percent(Stats.goldFoodChance(l)) .. " de comida dorada; la tuya vale " .. times(Stats.goldFoodMult(l))
	end,
	tunnel = has("Túnel a cada zona abierta", "Vas caminando"),
	chain = function(l)
		if l <= 0 then
			return "Sin rayo"
		end
		return (if l == 1 then "1 salto" else l .. " saltos") .. " de rayo: arrancan " .. decimal(Stats.chainBites(l)) .. " mordiscos a las vecinas"
	end,
	royalFood = function(l)
		return "Comida " .. times(1 + 0.5 * l)
	end,
	royalBite = function(l)
		return "Mordida " .. times(2 ^ l)
	end,
	royalColony = function(l)
		return "Colonia " .. times(1.5 ^ l)
	end,
	royalStart = function(l)
		return if l > 0 then "Empiezas con " .. Config.Rebirth.StartWorkers * l .. " obreras" else "Empiezas sola"
	end,
	royalSpeed = function(l)
		return "Velocidad +" .. percent(Config.Rebirth.SpeedStep * l)
	end,
	royalDepth = function(l)
		return if l > 0 then "Empiezas en la capa " .. (l + 1) else "Empiezas en la capa 1"
	end,
	royalJelly = function(l)
		return "Jalea +" .. percent(0.15 * l)
	end,
}

function Stats.effect(id: string, level: number): string
	local fn = EFFECT[id]
	local text = if fn then fn(level) else ""
	-- Las mejoras con yield dan además comida en cada nivel (Config.Tree / Config.Royal)
	local def = Config.NodeById[id] or Config.RoyalById[id]
	if def and def.yield and level > 0 then
		text ..= " · comida " .. times((1 + def.yield) ^ level)
	end
	return text
end

return Stats
