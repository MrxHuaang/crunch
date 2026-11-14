-- Fórmulas puras: de niveles de mejoras a estadísticas y costos.
-- Las usa el servidor (para mandar) y el cliente (para mostrar), así nunca se contradicen.

local Config = require(script.Parent.Config)
local Format = require(script.Parent.Format)

local Stats = {}

Stats.MaxDepth = #Config.Layers

local function lvl(levels, id): number
	return levels[id] or 0
end

function Stats.biteDamage(bite: number, titan: number, royalBite: number): number
	return math.ceil(1.38 ^ bite) * 2 ^ titan * 2 ^ royalBite
end

function Stats.capacity(carry: number, giant: number): number
	return math.floor(Config.Player.Capacity * 1.38 ^ carry * 3 ^ giant)
end

function Stats.walkSpeed(speed: number, royalSpeed: number): number
	return (Config.Player.WalkSpeed + speed) * (1 + 0.08 * royalSpeed)
end

-- El montículo crece con cada capa sin pisar a sus vecinos (a unos 60 studs): x1.65 en la capa 14
function Stats.hillScale(depth: number): number
	return 1 + 0.05 * (math.clamp(depth, 1, Stats.MaxDepth) - 1)
end

-- Suma lo que dan las galerías compradas, por tipo. Paladar (zonePct) se guarda por capa y
-- cheapPct multiplica (cada una abarata un poco lo que ya estaba abaratado).
local function miniTotals(minis)
	local totals = { cheapMult = 1 }
	local zones = {}
	if minis then
		for id, owned in minis do
			local def = owned == true and Config.MiniById[id]
			if def then
				if def.kind == "zonePct" then
					zones[def.layer] = (zones[def.layer] or 0) + def.amount
				elseif def.kind == "cheapPct" then
					totals.cheapMult *= 1 - def.amount
				else
					totals[def.kind] = (totals[def.kind] or 0) + def.amount
				end
			end
		end
	end
	local zoneMult = {}
	for zone = 1, #Config.Zones do
		zoneMult[zone] = 1 + (zones[zone] or 0)
	end
	return totals, zoneMult
end

-- minis: { [idGalería] = true } (opcional)
function Stats.derive(nodes, royal, depth: number?, minis: { [string]: boolean }?)
	local nursery = lvl(nodes, "nursery")
	local storage = lvl(nodes, "storage")
	local area = lvl(nodes, "area")
	local eggs = lvl(nodes, "eggs")
	local fungus = lvl(nodes, "fungus")
	local layer = depth or 1
	local mini, zoneMult = miniTotals(minis)
	local function m(kind: string): number
		return mini[kind] or 0
	end
	return {
		depth = layer,
		hillScale = Stats.hillScale(layer),
		miniTotals = mini, -- lo que suman las galerías de cada tipo (para la ficha)

		biteDamage = math.ceil(Stats.biteDamage(lvl(nodes, "bite"), lvl(nodes, "titan"), lvl(royal, "royalBite")) * (1 + m("bitePct"))),
		biteCooldown = Config.Player.BiteCooldown * 0.95 ^ lvl(nodes, "chew") / (1 + m("chewPct")),
		hardMult = (1 + 0.5 * lvl(nodes, "venom")) * (1 + m("hardPct")),
		biteRange = Config.Player.BiteRange + 1.5 * lvl(nodes, "reach"),
		critChance = 0.08 * lvl(nodes, "crit") + m("critPct"),
		critMult = Config.Player.CritMult + lvl(nodes, "brutal"),
		comboCap = 10 * lvl(nodes, "combo"),
		canBiteHard = lvl(nodes, "saw") > 0,
		areaRadius = if area > 0 then 4 + 3 * area else 0,
		goldChance = math.min(Config.MiniTune.GoldCap, m("goldPct")),
		zoneMult = zoneMult, -- [zona] = multiplicador del valor de su comida

		capacity = math.floor(Stats.capacity(lvl(nodes, "carry"), lvl(nodes, "giant")) * (1 + m("carryPct"))),
		walkSpeed = Stats.walkSpeed(lvl(nodes, "speed"), lvl(royal, "royalSpeed")) * (1 + m("speedPct")),
		hasSprint = lvl(nodes, "sprint") > 0,
		sprintDuration = Config.Sprint.Duration + lvl(nodes, "stamina"),
		hasWings = lvl(nodes, "wings") > 0,
		wingsCooldown = math.max(5, Config.Wings.Cooldown - 3 * lvl(nodes, "landing")),
		fullLoadBonus = 0.1 * lvl(nodes, "fullLoad"),
		doubleChance = 0.1 * lvl(nodes, "double"),
		depositMult = 1 + m("depositPct"),

		workerCap = if nursery > 0 then Config.NurseryCaps[nursery] + m("capPlus") else 0,
		workerSpeed = Config.Worker.Speed * (1 + 0.2 * lvl(nodes, "workerSpeed")),
		workerCarry = Config.Worker.Carry * 1.6 ^ lvl(nodes, "workerCarry") * 2 ^ lvl(nodes, "super"),
		workerDiscount = 0.92 ^ lvl(nodes, "nurse") * mini.cheapMult,
		colonyMult = 1.5 ^ lvl(nodes, "barracks") * 1.4 ^ lvl(nodes, "legion") * 1.5 ^ lvl(royal, "royalColony") * (1 + m("workerPct")),
		tripMult = 0.88 ^ lvl(nodes, "express"),
		trailBonus = (1 + 0.2 * lvl(nodes, "sweet")) * (1 + m("trailPct")),
		soldiers = lvl(nodes, "barracks"),
		workersBreakHard = lvl(nodes, "barracks") > 0,
		queen = lvl(nodes, "queen") > 0,
		offlineHours = if storage > 0 then Config.StorageHours[storage] else 0,
		offlineMult = 1 + m("offlinePct"),

		eggs = eggs,
		eggInterval = math.max(100, Config.Egg.Interval - 40 * eggs),
		eggSeconds = Config.Egg.Seconds + 30 * eggs,
		eggMult = 1 + m("eggPct"),
		fungus = fungus,
		buffDuration = Config.Fungus.Duration + 15 * fungus,

		trailSlots = lvl(nodes, "trail"),
		hasFrenzy = lvl(nodes, "frenzy") > 0,
		frenzyDuration = Config.Frenzy.Duration + 5 * lvl(nodes, "frenzyLen"),
		frenzyCooldown = Config.Frenzy.Cooldown - 12 * lvl(nodes, "hive"),
		frenzyMult = (Config.Frenzy.Mult + lvl(nodes, "royalPher")) * (1 + m("frenzyPct")),
		smartTrail = lvl(nodes, "smart") > 0,

		foodMult = (1 + 0.5 * lvl(royal, "royalFood")) * (1 + m("foodPct")),
		jellyMult = (1 + 0.15 * lvl(royal, "royalJelly")) * (1 + m("jellyPct")),
	}
end

-- Una galería se puede excavar cuando su capa está excavada y la anterior de su fila también.
function Stats.miniOpen(def, minis, depth: number): boolean
	return depth >= def.layer and (def.prev == nil or minis[def.prev] == true)
end

-- Lo que suman ya las galerías del tipo de `def` (con `plus`, contando también esa).
function Stats.miniTotal(stats, def, plus: boolean?): number
	local kind = def.kind
	if kind == "zonePct" then
		return stats.zoneMult[def.layer] - 1 + (if plus then def.amount else 0)
	elseif kind == "cheapPct" then
		return 1 - stats.miniTotals.cheapMult * (if plus then 1 - def.amount else 1)
	end
	local total = (stats.miniTotals[kind] or 0) + (if plus then def.amount else 0)
	return if kind == "goldPct" then math.min(total, Config.MiniTune.GoldCap) else total
end

-- "Comprar lo barato": cuántas galerías se compran yendo de la más barata a la más cara sin pasar
-- de `budget`, y cuál es la más barata pendiente (o nil). Dentro de una fila cada galería cuesta más
-- que la anterior, así que la que pide siempre se compra antes: no hace falta mirar más.
function Stats.cheapMinis(minis, depth: number, budget: number): (number, any)
	local count = 0
	local cheapest = nil
	for _, def in Config.MinisByCost do
		if minis[def.id] or def.layer > depth then
			continue
		end
		cheapest = cheapest or def
		if def.cost > budget then
			break
		end
		budget -= def.cost
		count += 1
	end
	return count, cheapest
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

local function has(yes: string, no: string)
	return function(l)
		return if l > 0 then yes else no
	end
end

-- Texto del efecto de un nodo a un nivel dado. Sirve para "ahora" y "luego" en la ficha.
local EFFECT = {
	bite = function(l)
		return "Arrancas " .. Format.short(Stats.biteDamage(l, 0, 0)) .. " por mordisco"
	end,
	chew = function(l)
		return "Un mordisco cada " .. seconds(Config.Player.BiteCooldown * 0.95 ^ l)
	end,
	crit = function(l)
		return percent(0.08 * l) .. " de mordida doble"
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
		return "La mordida doble pega " .. times(Config.Player.CritMult + l)
	end,
	venom = function(l)
		return "Comida dura: mordida " .. times(1 + 0.5 * l)
	end,
	titan = function(l)
		return "Mordida " .. times(2 ^ l)
	end,
	speed = function(l)
		return "Velocidad " .. (Config.Player.WalkSpeed + l)
	end,
	carry = function(l)
		return "Cargas " .. Format.short(Stats.capacity(l, 0)) .. " trozos"
	end,
	sprint = has("Sprint listo", "Sin sprint"),
	stamina = function(l)
		return "El sprint dura " .. (Config.Sprint.Duration + l) .. " s"
	end,
	wings = has("Vuelas a casa y al túnel", "Vas caminando"),
	landing = function(l)
		return "Alas listas cada " .. math.max(5, Config.Wings.Cooldown - 3 * l) .. " s"
	end,
	fullLoad = function(l)
		return "Carga llena: +" .. percent(0.1 * l)
	end,
	giant = function(l)
		return "Tamaño " .. times(1 + 0.2 * l) .. ", carga " .. times(3 ^ l)
	end,
	double = function(l)
		return percent(0.1 * l) .. " de entrega doble"
	end,
	nursery = function(l)
		return if l > 0 then "Caben " .. Config.NurseryCaps[l] .. " obreras" else "Sin obreras"
	end,
	workerCarry = function(l)
		return "Carga " .. times(1.6 ^ l)
	end,
	workerSpeed = function(l)
		return "Velocidad " .. string.format("%.1f", Config.Worker.Speed * (1 + 0.2 * l))
	end,
	nurse = function(l)
		return "Obreras un " .. percent(1 - 0.92 ^ l) .. " más baratas"
	end,
	storage = function(l)
		return if l > 0 then "Hasta " .. Config.StorageHours[l] .. " h sin ti" else "La colonia para al irte"
	end,
	barracks = function(l)
		return if l > 0 then "Colonia " .. times(1.5 ^ l) .. " y rompe comida dura" else "Sin soldados"
	end,
	eggs = function(l)
		return if l > 0
			then "Un huevo cada " .. math.max(100, Config.Egg.Interval - 40 * l) .. " s, vale " .. (Config.Egg.Seconds + 30 * l) .. " s de colonia"
			else "Sin huevos dorados"
	end,
	queen = has("La reina cría sola", "Tú compras las obreras"),
	fungus = function(l)
		return if l > 0 then "Comida doble durante " .. (Config.Fungus.Duration + 15 * l) .. " s" else "Sin hongos"
	end,
	legion = function(l)
		return "Colonia " .. times(1.4 ^ l)
	end,
	super = function(l)
		return "Carga de obreras " .. times(2 ^ l)
	end,
	trail = function(l)
		return if l == 0 then "Sin rastros" elseif l == 1 then "1 rastro" else l .. " rastros a la vez"
	end,
	sweet = function(l)
		return "Comida marcada: +" .. percent(0.2 * l)
	end,
	frenzy = has("Frenesí listo", "Sin frenesí"),
	frenzyLen = function(l)
		return "El frenesí dura " .. (Config.Frenzy.Duration + 5 * l) .. " s"
	end,
	smart = has("Eligen la mejor comida", "Van a lo que hay cerca de casa"),
	express = function(l)
		return "Viajes un " .. percent(1 - 0.88 ^ l) .. " más cortos"
	end,
	hive = function(l)
		return "Frenesí cada " .. (Config.Frenzy.Cooldown - 12 * l) .. " s"
	end,
	royalPher = function(l)
		return "Frenesí " .. times(Config.Frenzy.Mult + l)
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
		return if l > 0 then "Empiezas con " .. 5 * l .. " obreras" else "Empiezas sola"
	end,
	royalSpeed = function(l)
		return "Velocidad +" .. percent(0.08 * l)
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
	return if fn then fn(level) else ""
end

return Stats
