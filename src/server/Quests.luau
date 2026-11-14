-- Misiones y premio diario. Todo se decide aquí: progreso, cobros, cambios de misión y fechas.
-- Siempre hay tres misiones activas, sacadas de lo que el jugador puede hacer en su capa.
-- El progreso llega por el bus de sucesos (Events) y se manda al cliente como mucho dos veces
-- por segundo; al completar una misión, al momento.
--
-- Guardado (profile.data.quests, sobrevive al enjambre):
--   version = 1
--   serial  = número que da id a cada misión nueva
--   slots   = { misión, misión, misión }   misión = { id, kind, tier, goal, have, reward, food? }
--   rerolls = { t1, t2, t3 }                os.time() desde el que cada hueco puede cambiar gratis
--   golden  = { t, ... }                    os.time() de los últimos bocados dorados (máx. 6)
--   daily   = { day, streak }               día UTC del último premio diario y su casilla (1..7)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Events = require(script.Parent.Events)
local Profiles = require(script.Parent.Profiles)

local Quests = {}

local SLOTS = 3
local REROLL_SECONDS = 600
local SEND_GAP = 0.5 -- como mucho dos avisos de progreso por segundo
local ACTION_GAP = 0.3 -- entre peticiones del cliente
local DAY = 86400
local BUFF_SECONDS = 180
local BUFF_CHANCE = 0.25
local GOLDEN_WINDOW = 1800 -- solo hay misión de bocados dorados si has cogido alguno en esta media hora

-- Por dificultad: segundos de juego que debería costar y segundos de colonia que paga
local EFFORT = { 120, 210, 300 }
local PAY = { 120, 270, 420 }

-- Premio diario: minutos de colonia, minutos de comida x2 y jalea
local DAILY = {
	{ minutes = 5 },
	{ minutes = 10 },
	{ minutes = 15, buff = 5 },
	{ minutes = 20 },
	{ minutes = 25, buff = 10 },
	{ minutes = 30 },
	{ minutes = 60, jelly = 2 },
}

local KINDS = { "eat", "finish", "loads", "buy", "golden", "workers" }
local KNOWN = {}
for _, kind in KINDS do
	KNOWN[kind] = true
end

-- Nombres en plural (y en singular cuando no basta con quitar la "s") para "Termina N ..."
local PLURAL = {
	Sandwich = "sándwiches",
	Uvas = "racimos de uvas",
	Patatas = "bolsas de patatas fritas",
	Azucar = "cubos de azúcar",
	Huevo = "huevos fritos",
	Yogur = "yogures",
	Sushi = "piezas de sushi",
	Lata = "latas de refresco",
	Palomita = "cubos de palomitas",
	HotDog = "perritos calientes",
	Donut = "donuts",
	Mazorca = "mazorcas asadas",
	Costillas = "costillares",
	Cereales = "montones de cereales",
	Pan = "panes de molde",
	Miel = "tarros de miel",
	Ganchitos = "bolsas de ganchitos",
	Zumo = "bricks de zumo",
	Sorpresa = "huevos sorpresa",
	Cruasan = "cruasanes",
	Barrita = "barritas de cereales",
	Nuez = "nueces",
}
local SINGULAR = {
	Costillas = "costillar",
	Cereales = "montón de cereales",
	Ganchitos = "bolsa de ganchitos",
	Zumo = "brick de zumo",
	Uvas = "racimo de uvas",
	Patatas = "bolsa de patatas fritas",
	Palomita = "cubo de palomitas",
	Sushi = "pieza de sushi",
}

local rng = Random.new()
local remote: RemoteEvent
local runtime = setmetatable({}, { __mode = "k" }) -- [profile] = { dirty, sent, action, sync }

local function lowerFirst(text: string): string
	return text:sub(1, 1):lower() .. text:sub(2)
end

local function singular(def): string
	return SINGULAR[def.id] or lowerFirst(def.name)
end

local function plural(def): string
	return PLURAL[def.id] or (lowerFirst(def.name) .. "s")
end

-- Redondea a dos cifras significativas para que las metas se lean bien
local function nice(n: number): number
	if n < 20 then
		return math.max(1, math.floor(n + 0.5))
	end
	local scale = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / scale + 0.5) * scale
end

local function today(): number
	return os.time() // DAY
end

-- Cálculo de rendimiento -------------------------------------------------------------

-- Comidas que este jugador puede morder ahora, de sus tres últimas zonas
local function edibleFoods(stats)
	local list = {}
	local depth = math.clamp(stats.depth, 1, #Config.Zones)
	local low = math.max(1, depth - 2)
	for i = (low - 1) * 3 + 1, math.min(depth * 3, #Config.Foods) do
		local def = Config.Foods[i]
		if not def.boss and (not def.hard or stats.canBiteHard) then
			table.insert(list, def)
		end
	end
	return list
end

-- Segundos de ida y vuelta entre el hormiguero y la zona de esa comida. En el jardín la comida
-- cercana está a unos 38 studs (la mitad sale junto a los hormigueros); al túnel se va desde el arco
-- de hormigueros hasta la mitad de la zona.
local function tripTime(stats, def): number
	local zone = Config.Zones[def.zone]
	local distance = if def.zone == 1 then 38 else Config.Map.HillArc + math.abs(zone.z0) + 75
	return math.clamp(2 * distance / math.max(stats.walkSpeed, 1), 6, 150)
end

-- Trozos por segundo que arranca el jugador de esa comida, contando los viajes a casa.
-- Se le quita un 40 %: nadie juega perfecto.
local function eatRate(stats, def): number
	local perBite = stats.biteDamage * (if def.hard then stats.hardMult else 1)
	local bites = math.ceil(stats.capacity / math.max(perBite, 1))
	local fill = bites * stats.biteCooldown
	return stats.capacity / (fill + tripTime(stats, def)) * 0.6
end

local function pickFood(stats, filter: ((any) -> boolean)?)
	local list = edibleFoods(stats)
	local total = 0
	local weights = {}
	for i, def in list do
		-- Las de la zona más honda salen más a menudo
		local w = if filter and not filter(def) then 0 else (def.zone - list[1].zone + 1) ^ 2
		weights[i] = w
		total += w
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for i, def in list do
		roll -= weights[i]
		if roll <= 0 and weights[i] > 0 then
			return def
		end
	end
	return list[#list]
end

local function recentGolden(q): number
	local count = 0
	local now = os.time()
	for _, t in q.golden do
		if now - t <= GOLDEN_WINDOW then
			count += 1
		end
	end
	return count
end

-- ¿Queda algo del árbol que se pueda subir en esta capa?
local function canBuyMore(profile): boolean
	local data = profile.data
	local open = 0
	for _, def in Config.Tree do
		if not def.unit and def.layer <= data.depth and (data.nodes[def.id] or 0) < Stats.available(def, data.depth) then
			open += 1
		end
	end
	return open >= 2
end

local function eligible(profile, kind: string): boolean
	local data = profile.data
	if kind == "golden" then
		return recentGolden(data.quests) > 0
	elseif kind == "workers" then
		return data.workers > 0 and data.rate * EFFORT[1] >= 5
	elseif kind == "buy" then
		return canBuyMore(profile)
	end
	return true
end

-- Generación -------------------------------------------------------------------------

local function rollTier(): number
	local roll = rng:NextNumber()
	return if roll < 0.4 then 1 elseif roll < 0.8 then 2 else 3
end

-- Rellena meta y comida de una misión del tipo dado. Devuelve nil si no encaja.
local function build(profile, kind: string, tier: number)
	local stats = profile.stats
	local data = profile.data
	local effort = EFFORT[tier]
	local mission = { kind = kind, tier = tier, have = 0 }

	if kind == "eat" then
		local def = pickFood(stats)
		if not def then
			return nil
		end
		mission.food = def.id
		mission.goal = nice(math.max(eatRate(stats, def) * effort, 5))
	elseif kind == "finish" then
		-- Solo comidas que se terminan en menos de una vez y media el tiempo previsto
		local def = pickFood(stats, function(candidate)
			return candidate.hp <= eatRate(stats, candidate) * effort * 1.5
		end)
		if not def then
			return nil
		end
		mission.food = def.id
		mission.goal = math.clamp(nice(eatRate(stats, def) * effort / def.hp), 1, 40)
	elseif kind == "loads" then
		local def = pickFood(stats) or Config.Foods[1]
		local perBite = stats.biteDamage * (if def.hard then stats.hardMult else 1)
		local cycle = math.ceil(stats.capacity / math.max(perBite, 1)) * stats.biteCooldown + tripTime(stats, def)
		mission.goal = math.clamp(math.floor(effort * 0.6 / cycle), 2, 15)
	elseif kind == "buy" then
		mission.goal = tier + 1
	elseif kind == "golden" then
		mission.goal = math.clamp(recentGolden(data.quests), 1, tier)
	elseif kind == "workers" then
		mission.goal = nice(data.rate * effort)
	else
		return nil
	end
	mission.reward = if rng:NextNumber() < BUFF_CHANCE then "buff" else "food"
	return mission
end

-- Misión nueva de un tipo distinto a los de `avoid`
local function generate(profile, avoid: { [string]: boolean })
	local q = profile.data.quests
	local options = {}
	for _, kind in KINDS do
		if not avoid[kind] and eligible(profile, kind) then
			table.insert(options, kind)
		end
	end
	-- Mezcla y prueba hasta que una encaje; comer siempre encaja (la miga no falla)
	for i = #options, 2, -1 do
		local j = rng:NextInteger(1, i)
		options[i], options[j] = options[j], options[i]
	end
	table.insert(options, "eat")
	for _, kind in options do
		local mission = build(profile, kind, rollTier())
		if mission then
			q.serial += 1
			mission.id = q.serial
			return mission
		end
	end
	return nil
end

local function kindsExcept(q, index: number)
	local set = {}
	for i, slot in q.slots do
		if i ~= index then
			set[slot.kind] = true
		end
	end
	return set
end

local function replace(profile, index: number, alsoAvoid: string?)
	local q = profile.data.quests
	local avoid = kindsExcept(q, index)
	if alsoAvoid then
		avoid[alsoAvoid] = true
	end
	local mission = generate(profile, avoid)
	if not mission and alsoAvoid then
		mission = generate(profile, kindsExcept(q, index))
	end
	if mission then
		q.slots[index] = mission
	end
end

-- Datos guardados ---------------------------------------------------------------------

local function validSlot(profile, slot): boolean
	if type(slot) ~= "table" or not KNOWN[slot.kind] then
		return false
	end
	if type(slot.goal) ~= "number" or slot.goal <= 0 or type(slot.have) ~= "number" or type(slot.id) ~= "number" then
		return false
	end
	if slot.tier ~= 1 and slot.tier ~= 2 and slot.tier ~= 3 then
		return false
	end
	if slot.reward ~= "food" and slot.reward ~= "buff" then
		return false
	end
	if slot.kind == "eat" or slot.kind == "finish" then
		local def = Config.FoodById[slot.food]
		if not def or def.zone > profile.stats.depth then
			return false -- p. ej. tras enjambrar la zona vuelve a estar cerrada
		end
	end
	return true
end

-- Crea o repara data.quests. Nunca falla: lo que no cuadre se rehace.
local function ensure(profile)
	local data = profile.data
	local q = data.quests
	if type(q) ~= "table" then
		q = {}
		data.quests = q
	end
	q.version = 1
	q.serial = if type(q.serial) == "number" then q.serial else 0
	if type(q.golden) ~= "table" then
		q.golden = {}
	end
	if type(q.daily) ~= "table" or type(q.daily.day) ~= "number" or type(q.daily.streak) ~= "number" then
		q.daily = { day = 0, streak = 0 }
	end
	if type(q.rerolls) ~= "table" then
		q.rerolls = {}
	end
	for i = 1, SLOTS do
		if type(q.rerolls[i]) ~= "number" then
			q.rerolls[i] = 0
		end
	end
	if type(q.slots) ~= "table" then
		q.slots = {}
	end
	for i = 1, SLOTS do
		if not validSlot(profile, q.slots[i]) then
			-- Un hueco provisional para que kindsExcept no tropiece con un nil
			q.slots[i] = { kind = "_", id = 0, tier = 1, goal = 1, have = 0, reward = "food" }
		end
	end
	for i = 1, SLOTS do
		if q.slots[i].kind == "_" then
			replace(profile, i)
		end
	end
	for i = #q.slots, SLOTS + 1, -1 do
		q.slots[i] = nil
	end
	return q
end

-- Premios -----------------------------------------------------------------------------

-- Comida "en bruto" de `seconds` de colonia, con un mínimo según tu mordida y tu zona
-- (la misma idea que el saco de la tienda). addFood le aplica luego los multiplicadores.
local function rawFood(profile, seconds: number): number
	local stats = profile.stats
	local depth = math.clamp(stats.depth, 1, #Config.Zones)
	local zoneFood = Config.Foods[(depth - 1) * 3 + 1]
	return math.max(math.floor(profile.data.rate * seconds), math.floor(seconds / 3 * stats.biteDamage * zoneFood.value))
end

-- Lo que verá el jugador (sin contar una poción o un hongo activos)
local function shownFood(profile, seconds: number): number
	return math.floor(rawFood(profile, seconds) * profile.stats.foodMult)
end

local function giveFood(profile, seconds: number): number
	return Profiles.addFood(profile, rawFood(profile, seconds))
end

local function giveBuff(profile, seconds: number)
	local now = Workspace:GetServerTimeNow()
	profile.buffUntil = math.max(profile.buffUntil, now) + seconds
end

-- Premio diario: casilla que toca, cuántas hay picadas y si se puede cobrar
local function dailyState(q)
	local d = q.daily
	local day = today()
	if d.day == day then
		return d.streak % 7 + 1, d.streak, false
	elseif d.day == day - 1 then
		return d.streak % 7 + 1, d.streak % 7, true
	end
	return 1, 0, true
end

-- Envío al cliente ----------------------------------------------------------------------

local function describe(slot): string
	local def = slot.food and Config.FoodById[slot.food]
	local goal = Format.short(slot.goal)
	if slot.kind == "eat" and def then
		return "Come " .. goal .. " trozos de " .. lowerFirst(def.name)
	elseif slot.kind == "finish" and def then
		return "Termina " .. goal .. " " .. (if slot.goal == 1 then singular(def) else plural(def))
	elseif slot.kind == "loads" then
		return "Entrega " .. goal .. " cargas llenas"
	elseif slot.kind == "buy" then
		return "Compra " .. goal .. " mejoras del árbol"
	elseif slot.kind == "golden" then
		return if slot.goal == 1 then "Consigue 1 bocado dorado" else "Consigue " .. goal .. " bocados dorados"
	elseif slot.kind == "workers" then
		return "Tus obreras traen " .. goal .. " de comida"
	end
	return "Misión"
end

local function snapshot(profile)
	local q = profile.data.quests
	local now = os.time()
	local slots = {}
	for i, slot in q.slots do
		slots[i] = {
			id = slot.id,
			kind = slot.kind,
			text = describe(slot),
			have = math.floor(slot.have),
			goal = slot.goal,
			done = slot.have >= slot.goal,
			tier = slot.tier,
			food = slot.food,
			reward = slot.reward,
			amount = if slot.reward == "buff" then BUFF_SECONDS else shownFood(profile, PAY[slot.tier]),
			reroll = math.max(0, q.rerolls[i] - now),
		}
	end
	local step, punched, ready = dailyState(q)
	local prizes = {}
	for i, prize in DAILY do
		prizes[i] = {
			food = shownFood(profile, prize.minutes * 60),
			buff = if prize.buff then prize.buff * 60 else 0,
			jelly = prize.jelly or 0,
		}
	end
	return {
		slots = slots,
		daily = {
			step = step,
			punched = punched,
			ready = ready,
			wait = (today() + 1) * DAY - now,
			prizes = prizes,
		},
	}
end

local function state(profile)
	local rt = runtime[profile]
	if not rt then
		rt = { dirty = false, sent = 0, action = 0, sync = 0 }
		runtime[profile] = rt
	end
	return rt
end

local function sendState(profile)
	local rt = state(profile)
	rt.dirty = false
	rt.sent = os.clock()
	if profile.player.Parent then
		remote:FireClient(profile.player, "State", snapshot(profile))
	end
end

local function sendProgress(profile)
	local rt = state(profile)
	rt.dirty = false
	rt.sent = os.clock()
	local have = {}
	for i, slot in profile.data.quests.slots do
		have[i] = math.floor(slot.have)
	end
	if profile.player.Parent then
		remote:FireClient(profile.player, "Progress", have)
	end
end

-- Progreso ------------------------------------------------------------------------------

local function bump(profile, test: (any) -> number?)
	local q = profile.data.quests
	if type(q) ~= "table" or type(q.slots) ~= "table" or not runtime[profile] then
		return -- aún no está listo
	end
	local finished = false
	local changed = false
	for _, slot in q.slots do
		if slot.have < slot.goal then
			local amount = test(slot)
			if amount and amount > 0 then
				slot.have = math.min(slot.goal, slot.have + amount)
				changed = true
				if slot.have >= slot.goal then
					finished = true
				end
			end
		end
	end
	if finished then
		sendState(profile)
	elseif changed then
		state(profile).dirty = true
	end
end

local function hookEvents()
	Events.on("Ate", function(profile, def, amount, byWorkers)
		if type(def) ~= "table" or type(amount) ~= "number" or amount <= 0 then
			return
		end
		bump(profile, function(slot)
			if slot.kind == "eat" and not byWorkers and slot.food == def.id then
				return amount
			elseif slot.kind == "workers" and byWorkers then
				-- Igual que data.rate: comida acreditada sin pociones (con el Paladar de su zona)
				return amount * (def.value or 0) * (profile.stats.zoneMult[def.zone] or 1) * profile.stats.foodMult
			end
			return nil
		end)
	end)

	Events.on("Finished", function(profile, def)
		if type(def) ~= "table" then
			return
		end
		bump(profile, function(slot)
			return if slot.kind == "finish" and slot.food == def.id then 1 else nil
		end)
	end)

	Events.on("Deposit", function(profile, _credited, fullLoad)
		if not fullLoad then
			return
		end
		bump(profile, function(slot)
			return if slot.kind == "loads" then 1 else nil
		end)
	end)

	Events.on("Bought", function(profile, kind)
		if kind ~= "node" and kind ~= "mini" then
			return
		end
		bump(profile, function(slot)
			return if slot.kind == "buy" then 1 else nil
		end)
	end)

	Events.on("Golden", function(profile)
		local q = profile.data.quests
		if type(q) == "table" and type(q.golden) == "table" then
			table.insert(q.golden, os.time())
			while #q.golden > 6 do
				table.remove(q.golden, 1)
			end
		end
		bump(profile, function(slot)
			return if slot.kind == "golden" then 1 else nil
		end)
	end)

	-- Capa nueva: los premios suben de tamaño
	Events.on("Dig", function(profile)
		if runtime[profile] then
			sendState(profile)
		end
	end)

	-- Enjambre: las zonas se cierran otra vez. Lo pendiente se rehace; lo cumplido se respeta.
	-- Se espera un momento: así da igual si el suceso llega antes o después de rehacer las estadísticas.
	Events.on("Rebirth", function(profile)
		task.delay(1, function()
			if not runtime[profile] or Profiles.get(profile.player) ~= profile then
				return
			end
			local q = ensure(profile)
			for _, slot in q.slots do
				if slot.have < slot.goal then
					slot.kind = "_"
				end
			end
			for i, slot in q.slots do
				if slot.kind == "_" then
					replace(profile, i)
				end
			end
			sendState(profile)
		end)
	end)
end

-- Peticiones del cliente ------------------------------------------------------------------

local function claim(profile, index: number)
	local q = profile.data.quests
	local slot = q.slots[index]
	if not slot or slot.have < slot.goal then
		return
	end
	local result = { slot = index }
	if slot.reward == "buff" then
		giveBuff(profile, BUFF_SECONDS)
		result.buff = BUFF_SECONDS
	else
		result.food = giveFood(profile, PAY[slot.tier])
	end
	replace(profile, index, slot.kind)
	Profiles.push(profile)
	remote:FireClient(profile.player, "Reward", result)
	sendState(profile)
end

local function reroll(profile, index: number)
	local q = profile.data.quests
	local slot = q.slots[index]
	if not slot or slot.have >= slot.goal or os.time() < q.rerolls[index] then
		return
	end
	q.rerolls[index] = os.time() + REROLL_SECONDS
	replace(profile, index, slot.kind)
	sendState(profile)
end

local function claimDaily(profile)
	local q = profile.data.quests
	local step, _, ready = dailyState(q)
	if not ready then
		return
	end
	local prize = DAILY[step]
	q.daily.day = today()
	q.daily.streak = step
	local result = { daily = step, food = giveFood(profile, prize.minutes * 60) }
	if prize.buff then
		giveBuff(profile, prize.buff * 60)
		result.buff = prize.buff * 60
	end
	if prize.jelly then
		profile.data.jelly += prize.jelly
		result.jelly = prize.jelly
	end
	Profiles.push(profile)
	remote:FireClient(profile.player, "Reward", result)
	sendState(profile)
end

local function onRequest(player: Player, action: any, index: any)
	local profile = Profiles.get(player)
	if not profile or not runtime[profile] or type(action) ~= "string" then
		return
	end
	local rt = state(profile)
	local now = os.clock()
	if action == "Sync" then
		if now - rt.sync >= 1 then
			rt.sync = now
			sendState(profile)
		end
		return
	end
	if now - rt.action < ACTION_GAP then
		return
	end
	rt.action = now

	if action == "Daily" then
		claimDaily(profile)
		return
	end
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > SLOTS then
		return
	end
	if action == "Claim" then
		claim(profile, index)
	elseif action == "Reroll" then
		reroll(profile, index)
	end
end

function Quests.start(remotes: Folder)
	local existing = remotes:FindFirstChild("Quest")
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		remote = Instance.new("RemoteEvent")
		remote.Name = "Quest"
		remote.Parent = remotes
	end
	remote.OnServerEvent:Connect(onRequest)
	hookEvents()

	-- Un solo bucle: prepara a quien acaba de cargar y manda el progreso acumulado
	while true do
		task.wait(SEND_GAP / 2)
		local clock = os.clock()
		for _, profile in Profiles.all() do
			if not runtime[profile] then
				if profile.stats and profile.data then
					local ok, err = pcall(ensure, profile)
					if ok then
						state(profile)
						sendState(profile)
					else
						warn("[CRUNCH!] Misiones:", err)
					end
				end
			else
				local rt = runtime[profile]
				if rt.dirty and clock - rt.sent >= SEND_GAP then
					sendProgress(profile)
				end
			end
		end
	end
end

return Quests
