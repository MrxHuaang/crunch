-- Pases de juego (permanentes) y productos (se pueden comprar varias veces).
-- Los ids se configuran en shared/Config. Con id = 0 el artículo está apagado: el puesto del mapa
-- dice "Próximamente" y en Studio se prueba con Monetize.debugGrant (CrunchDebug "grant" o el
-- remoto "Stalls" → "Try", solo en Studio).
--
-- Nunca se pierde lo comprado: ProcessReceipt es idempotente (data.receipts) y solo confirma la compra
-- si quedó guardada. Lo que dura un rato (pociones, velocidad, imán, llave) se guarda como segundos
-- restantes en data.paid y vuelve al entrar; el reloj se para mientras no juegas.
--
-- Guardado: data.paid = { food, speed, magnet, key = segundos que quedan; keyDepth = zona que abre
-- la llave; jellyBoost, halfDig = cuántos quedan por usar; starter = ya se entregó el paquete }.
-- Atributos de la jugadora: P_<pase>, PaidFoodUntil, SpeedUntil, MagnetUntil, KeyUntil, KeyDepth
-- (horas del servidor), JellyBoost, HalfDig. Workspace: FeastUntil/FeastBy, GoldRainUntil/GoldRainBy.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Data = require(script.Parent.Data)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local Profiles = require(script.Parent.Profiles)

local Monetize = {}

-- Quien quiera enterarse de una entrega (celebración en src/server/Stalls.luau):
-- fn(compradora, definición, destinataria, "pass" | "product")
Monetize.onGrant = {} :: { (any, any, any, string) -> () }

local POTION_SMALL = 15 * 60
local POTION_BIG = 60 * 60
local BOOST_TIME = 15 * 60
local SPEED_MULT = 1.4
local MAGNET_RADIUS = 16
local KEY_TIME = 30 * 60
local CARRY_MULT = 1.5
local WIDE_TIME = 5 * 60 -- banquete y lluvia dorada
local WIDE_MAX = 30 * 60 -- por mucho que se compren seguidos, como mucho media hora por delante
local RAIN_CHANCE = 0.25
local RAIN_LIFE = 180 -- segundos que se quedan las comidas doradas de la lluvia si nadie las come
local GIFT_WINDOW = 600 -- segundos que vale la destinataria elegida antes de pagar un regalo

local passById = {}
local productById = {}
local defById: { [string]: { def: any, kind: string } } = {}
for _, pass in Config.Passes do
	defById[pass.id] = { def = pass, kind = "pass" }
	if pass.passId > 0 then
		passById[pass.passId] = pass
	end
end
for _, product in Config.Products do
	defById[product.id] = { def = product, kind = "product" }
	if product.productId > 0 then
		productById[product.productId] = product
	end
end

local feastUntil, rainUntil = 0, 0
local giftTargets: { [number]: { target: number, at: number } } = {} -- [compradora] = destinataria
local forceGold = false
local goldWrapped = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Definición y tipo ("pass" o "product") de un artículo por su id de Config
function Monetize.find(id: any): (any, string?)
	local entry = type(id) == "string" and defById[id] or nil
	if entry then
		return entry.def, entry.kind
	end
	return nil, nil
end

local function paidOf(data)
	if type(data.paid) ~= "table" then
		data.paid = {}
	end
	local paid = data.paid
	for _, key in { "food", "speed", "magnet", "key", "keyDepth", "jellyBoost", "halfDig" } do
		local value = paid[key]
		paid[key] = if type(value) == "number" and value == value and value >= 0 then value else 0
	end
	return paid
end

-- Pasa los relojes de la partida a segundos restantes en data.paid (lo que se guarda)
local function syncPaid(profile)
	local paid = paidOf(profile.data)
	local t = now()
	paid.food = math.max(0, (profile.paidFoodUntil or 0) - t)
	paid.speed = math.max(0, (profile.speedUntil or 0) - t)
	paid.magnet = math.max(0, (profile.magnetUntil or 0) - t)
	paid.key = math.max(0, (profile.keyUntil or 0) - t)
end

local function announce(buyer, def, recipient, kind: string)
	for _, fn in Monetize.onGrant do
		local ok, err = pcall(fn, buyer, def, recipient, kind)
		if not ok then
			warn("[CRUNCH!] Monetize.onGrant:", err)
		end
	end
end

local function colonyTime(profile, seconds: number, floor: number): number
	local stats = profile.stats
	-- Aunque la colonia aún sea pequeña, el saco debe valer algo a tu nivel
	local zoneFood = Config.Foods[(math.clamp(stats.depth, 1, #Config.Zones) - 1) * 3 + 1] or Config.Foods[1]
	-- data.rate ya lleva el multiplicador de comida y addFood lo vuelve a aplicar: se quita aquí
	local gain = math.max(math.floor(profile.data.rate / math.max(stats.foodMult, 1e-3) * seconds), floor * stats.biteDamage * zoneFood.value)
	return Profiles.addFood(profile, gain)
end

-- Comida x2 pagada: se suma al reloj de pago y el doble de comida dura al menos hasta ahí
local function addPaidFood(profile, seconds: number)
	local t = now()
	profile.paidFoodUntil = math.max(profile.paidFoodUntil or 0, t) + seconds
	profile.buffUntil = math.max(profile.buffUntil, profile.paidFoodUntil)
end

local function digNow(profile)
	local data = profile.data
	if data.depth < Stats.MaxDepth then
		data.depth += 1
		Profiles.say(profile, "¡Capa nueva! Se abre " .. Config.Zones[data.depth].name, 6)
		-- Las estadísticas, al día antes de avisar: los oyentes leen la capa nueva
		Profiles.refresh(profile)
		Events.fire("Dig", profile, data.depth)
	else
		-- Ya no queda nada que excavar: se devuelve en jalea
		data.jelly += 15
		Profiles.say(profile, "No queda tierra que excavar. Toma 15 de jalea", 6)
	end
end

---------------------------------------------------------------------------------------------------
-- Para todo el servidor

-- Comida x2 del banquete a todas las conectadas (y a quien entre mientras dura)
local function applyFeast(profile)
	if now() < feastUntil and profile.buffUntil < feastUntil then
		profile.buffUntil = feastUntil
		Profiles.push(profile)
	end
end

local function aliveCounts(): { [string]: number }
	local alive = {}
	for food in FoodService.list() do
		if food:GetAttribute("Event") == nil then
			local id = food:GetAttribute("FoodId")
			if id then
				alive[id] = (alive[id] or 0) + 1
			end
		end
	end
	return alive
end

local function feast(profile)
	local zone = math.clamp(profile.data.depth, 1, #Config.Zones)
	local alive = aliveCounts()
	for _, def in Config.Foods do
		if def.zone == zone and not def.boss then
			local missing = math.min(def.count - (alive[def.id] or 0) - FoodService.pending(def.id), 40)
			for _ = 1, missing do
				FoodService.spawn(def)
			end
		end
	end
	local t = now()
	feastUntil = math.min(math.max(feastUntil, t) + WIDE_TIME, t + WIDE_MAX)
	Workspace:SetAttribute("FeastUntil", feastUntil)
	Workspace:SetAttribute("FeastBy", profile.player.DisplayName)
	for _, other in Profiles.all() do
		applyFeast(other)
	end
end

-- La probabilidad de comida dorada la fija GoldFood; durante la lluvia sube a RAIN_CHANCE como poco
local function wrapGold()
	if goldWrapped then
		return
	end
	goldWrapped = true
	local base = FoodService.goldChance
	FoodService.goldChance = function(): number
		if forceGold then
			return 1
		end
		local chance = base()
		if now() < rainUntil then
			return math.max(chance, RAIN_CHANCE)
		end
		return chance
	end
end

local function goldRain(profile)
	wrapGold()
	local t = now()
	rainUntil = math.min(math.max(rainUntil, t) + WIDE_TIME, t + WIDE_MAX)
	Workspace:SetAttribute("GoldRainUntil", rainUntil)
	Workspace:SetAttribute("GoldRainBy", profile.player.DisplayName)
	-- Hasta la zona más honda de las conectadas: cada una tiene algo a su alcance
	local deepest = 1
	for _, other in Profiles.all() do
		deepest = math.max(deepest, math.clamp(other.data.depth, 1, #Config.Zones))
	end
	local spawned = {}
	forceGold = true
	local ok, err = pcall(function()
		for zone = 1, deepest do
			local def = Config.Foods[(zone - 1) * 3 + 1]
			local count = if zone == 1 then 10 else 4
			if def and not def.boss then
				for _ = 1, count do
					local model = FoodService.spawn(def, { noRespawn = true })
					if model then
						model:SetAttribute("Event", "GoldRain")
						table.insert(spawned, model)
					end
				end
			end
		end
	end)
	forceGold = false
	if not ok then
		warn("[CRUNCH!] Lluvia dorada:", err)
	end
	task.delay(RAIN_LIFE, function()
		for _, model in spawned do
			if FoodService.isFood(model) then
				FoodService.remove(model)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Entregas. GRANTS[id](destinataria, compradora): en los regalos son distintas.

local GRANTS = {
	-- Avance
	halfDig = function(profile)
		local paid = paidOf(profile.data)
		paid.halfDig += 1
		Profiles.say(profile, "¡Pala dorada! La próxima capa me cuesta la mitad", 5)
	end,
	zoneKey = function(profile)
		local data = profile.data
		if data.depth >= Stats.MaxDepth then
			data.jelly += 3
			Profiles.say(profile, "Ya tengo todas las zonas abiertas. Toma 3 de jalea", 6)
			return
		end
		local paid = paidOf(data)
		local zone = data.depth + 1
		local t = now()
		-- Si la llave ya abría esa misma zona, se suma el tiempo; si no, empieza de cero
		local from = if paid.keyDepth == zone then math.max(profile.keyUntil or 0, t) else t
		paid.keyDepth = zone
		profile.keyUntil = from + KEY_TIME
		Profiles.say(profile, "¡Llave maestra! " .. Config.Zones[zone].name .. " abierta 30 minutos para probarla", 6)
	end,
	-- Tiempo
	sack = function(profile)
		colonyTime(profile, 900, 300)
		Profiles.say(profile, "¡Un saco entero de comida!", 4)
	end,
	crate = function(profile)
		colonyTime(profile, 3600, 1200)
		Profiles.say(profile, "¡Una caja llena de comida!", 4)
	end,
	bigSack = function(profile)
		colonyTime(profile, 14400, 4800)
		Profiles.say(profile, "¡Una carretilla hasta arriba de comida!", 4)
	end,
	frenzy = function(profile)
		profile.frenzyUntil = math.max(profile.frenzyUntil, now()) + 60
		Profiles.say(profile, "¡Frenesí! La colonia se ha vuelto loca", 4)
	end,
	egg = function(profile)
		profile.eggAt = 0
		profile.eggGift = true
		Profiles.say(profile, "¡Un huevo dorado te espera junto a tu hormiguero!", 5)
	end,
	-- Potenciadores
	potion = function(profile)
		addPaidFood(profile, POTION_SMALL)
		Profiles.say(profile, "¡Poción x2! Un cuarto de hora de comida doble", 5)
	end,
	bigPotion = function(profile)
		addPaidFood(profile, POTION_BIG)
		Profiles.say(profile, "¡Poción grande! Una hora de comida doble", 5)
	end,
	speedBoost = function(profile)
		profile.speedUntil = math.max(profile.speedUntil or 0, now()) + BOOST_TIME
		Profiles.say(profile, "¡Patas de saltamontes! Corro un 40 % más", 5)
	end,
	magnet = function(profile)
		profile.magnetUntil = math.max(profile.magnetUntil or 0, now()) + BOOST_TIME
		Profiles.say(profile, "¡Imán! La comida pequeña viene sola", 5)
	end,
	jellyBoost = function(profile)
		local paid = paidOf(profile.data)
		paid.jellyBoost += 1
		Profiles.say(profile, "¡Jalea x2! Mi próximo enjambre da el doble", 5)
	end,
	-- Jalea
	jar = function(profile)
		profile.data.jelly += 5
		Profiles.say(profile, "¡Jalea real! Ábrela en la cámara real", 4)
	end,
	bigJar = function(profile)
		profile.data.jelly += 30
		Profiles.say(profile, "¡Un barril de jalea real!", 4)
	end,
	-- Para todas
	feast = function(profile)
		feast(profile)
	end,
	goldRain = function(profile)
		goldRain(profile)
	end,
	-- Regalos
	giftPotion = function(recipient, buyer)
		addPaidFood(recipient, POTION_SMALL)
		if recipient ~= buyer then
			Profiles.say(recipient, buyer.player.DisplayName .. " me ha regalado comida doble 15 minutos", 6)
		end
	end,
	giftSack = function(recipient, buyer)
		colonyTime(recipient, 900, 300)
		if recipient ~= buyer then
			Profiles.say(recipient, buyer.player.DisplayName .. " me ha regalado un saco de comida", 6)
		end
	end,
}
for _, product in Config.Products do
	if product.layers then
		GRANTS[product.id] = digNow
	end
end
for _, product in Config.Products do
	if not GRANTS[product.id] then
		warn("[CRUNCH!] Producto sin entrega:", product.id)
	end
end

-- Lo que trae el paquete de inicio, una sola vez por cuenta
local function giveStarter(profile)
	local paid = paidOf(profile.data)
	if paid.starter then
		return
	end
	paid.starter = true
	colonyTime(profile, 1800, 600)
	addPaidFood(profile, 1800)
	profile.data.jelly += 10
	profile.eggAt = 0
	profile.eggGift = true
	Profiles.say(profile, "¡Paquete de inicio! Comida, jalea, poción y un huevo dorado", 6)
end

local function grantPass(profile, pass)
	profile.passes[pass.id] = true
	profile.player:SetAttribute("P_" .. pass.id, true)
	if pass.id == "starterPack" then
		giveStarter(profile)
	end
end

---------------------------------------------------------------------------------------------------
-- Efectos que duran: se aplican encima de las estadísticas en cada Profiles.refresh

local function activeKey(profile, t: number): string
	return table.concat({
		tostring((profile.speedUntil or 0) > t),
		tostring((profile.magnetUntil or 0) > t),
		tostring((profile.keyUntil or 0) > t),
		tostring(profile.data.depth),
	}, "|")
end

local function applyBoosts(profile)
	local stats = profile.stats
	local player = profile.player
	local paid = paidOf(profile.data)
	local t = now()

	if profile.passes.bigCarry then
		-- Solo crece lo que cargas tú; el escarabajo de carga sigue igual
		local own = stats.ownCapacity or stats.capacity
		local extra = math.floor(own * (CARRY_MULT - 1))
		if stats.ownCapacity then
			stats.ownCapacity += extra
		end
		stats.capacity += extra
	end
	if (profile.speedUntil or 0) > t then
		stats.walkSpeed *= SPEED_MULT
	end
	if (profile.magnetUntil or 0) > t then
		stats.magnetRadius = math.max(stats.magnetRadius or 0, MAGNET_RADIUS)
	end
	-- Llave maestra: la zona siguiente cuenta como abierta para morder y para la puerta (KeyDepth).
	-- Solo la que va justo después de tu capa: si la excavas o enjambras, la llave deja de hacer falta.
	local keyOn = (profile.keyUntil or 0) > t and paid.keyDepth == profile.data.depth + 1 and paid.keyDepth > (stats.depth or 1)
	if keyOn then
		stats.depth = math.min(paid.keyDepth, #Config.Zones)
	end
	if paid.jellyBoost > 0 then
		stats.jellyMult *= 2
	end

	player:SetAttribute("Capacity", stats.capacity)
	player:SetAttribute("WalkSpeed", stats.walkSpeed)
	player:SetAttribute("JellyMult", stats.jellyMult)
	player:SetAttribute("PaidFoodUntil", profile.paidFoodUntil or 0)
	player:SetAttribute("SpeedUntil", profile.speedUntil or 0)
	player:SetAttribute("MagnetUntil", profile.magnetUntil or 0)
	player:SetAttribute("KeyUntil", if keyOn then profile.keyUntil else 0)
	player:SetAttribute("KeyDepth", if keyOn then paid.keyDepth else 0)
	player:SetAttribute("JellyBoost", paid.jellyBoost)
	player:SetAttribute("HalfDig", paid.halfDig)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = stats.walkSpeed
	end
	profile.boostKey = activeKey(profile, t)
end

---------------------------------------------------------------------------------------------------

-- Comprueba qué pases tiene el jugador al entrar y le devuelve lo que le quedaba de lo comprado.
function Monetize.load(profile)
	local paid = paidOf(profile.data)
	local t = now()
	profile.paidFoodUntil = if paid.food > 0 then t + paid.food else 0
	profile.speedUntil = if paid.speed > 0 then t + paid.speed else 0
	profile.magnetUntil = if paid.magnet > 0 then t + paid.magnet else 0
	profile.keyUntil = if paid.key > 0 then t + paid.key else 0
	profile.buffUntil = math.max(profile.buffUntil, profile.paidFoodUntil)
	applyFeast(profile)

	for _, pass in passById do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(profile.player.UserId, pass.passId)
		end)
		if ok and owns then
			grantPass(profile, pass)
		end
	end
end

-- Destinataria del próximo regalo que pague esta jugadora (la elige en la taquilla de regalos)
function Monetize.setGiftTarget(buyer: Player, targetUserId: number)
	giftTargets[buyer.UserId] = { target = targetUserId, at = os.clock() }
end

local function giftRecipient(buyerProfile)
	local pending = giftTargets[buyerProfile.player.UserId]
	giftTargets[buyerProfile.player.UserId] = nil
	if pending and os.clock() - pending.at <= GIFT_WINDOW then
		local target = Players:GetPlayerByUserId(pending.target)
		local targetProfile = target and Profiles.get(target)
		if targetProfile then
			return targetProfile
		end
	end
	Profiles.say(buyerProfile, "No encontré a quién regalarlo: el regalo es para mí", 6)
	return buyerProfile
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and Profiles.get(player)
	local product = productById[receipt.ProductId]
	if not profile or not product or not GRANTS[product.id] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Cada compra se entrega una sola vez aunque Roblox repita el aviso
	local data = profile.data
	if type(data.receipts) ~= "table" then
		data.receipts = {}
	end
	if table.find(data.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local recipient = if product.gift then giftRecipient(profile) else profile
	local ok, err = pcall(GRANTS[product.id], recipient, profile)
	if not ok then
		warn("[CRUNCH!] Entrega fallida", product.id, err)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.receipts, receipt.PurchaseId)
	while #data.receipts > 40 do
		table.remove(data.receipts, 1)
	end
	Profiles.refresh(profile)
	syncPaid(profile)
	if recipient ~= profile then
		Profiles.refresh(recipient)
		syncPaid(recipient)
		if recipient.canSave then
			task.spawn(Data.save, recipient.player.UserId, recipient.data)
		end
	end

	-- Solo se confirma la compra si quedó guardada
	if profile.canSave and not Data.save(player.UserId, data) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	announce(profile, product, recipient, "product")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Solo para probar en Studio: entrega un pase o producto sin pasar por Roblox.
-- target (opcional): destinataria de un regalo; sin ella, el regalo es para ti.
function Monetize.debugGrant(profile, id: string, target: any?)
	local def, kind = Monetize.find(id)
	if not def then
		warn("[CRUNCH!] debugGrant: no existe", id)
		return
	end
	local recipient = profile
	if kind == "pass" then
		grantPass(profile, def)
	else
		if def.gift and target and Profiles.get(target.player) == target then
			recipient = target
		end
		GRANTS[id](recipient, profile)
	end
	Profiles.refresh(profile)
	syncPaid(profile)
	if recipient ~= profile then
		Profiles.refresh(recipient)
		syncPaid(recipient)
	end
	announce(profile, def, recipient, kind)
end

function Monetize.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local profile = Profiles.get(player)
		local pass = passById[passId]
		if purchased and profile and pass and not profile.passes[pass.id] then
			grantPass(profile, pass)
			Profiles.refresh(profile)
			announce(profile, pass, profile, "pass")
		end
	end)

	table.insert(Profiles.onRefresh, function(profile)
		local ok, err = pcall(applyBoosts, profile)
		if not ok then
			warn("[CRUNCH!] Potenciadores:", err)
		end
	end)

	-- Enjambrar gasta la jalea x2 y pone a cero el doble de comida: lo pagado vuelve
	Events.on("Rebirth", function(profile)
		local paid = paidOf(profile.data)
		if paid.jellyBoost > 0 then
			paid.jellyBoost -= 1
		end
		profile.buffUntil = math.max(profile.buffUntil, profile.paidFoodUntil or 0)
		applyFeast(profile)
		Profiles.refresh(profile)
	end)

	Players.PlayerRemoving:Connect(function(player)
		giftTargets[player.UserId] = nil
		local profile = Profiles.get(player)
		if profile then
			syncPaid(profile) -- por si PlayerService guarda después que esto
		end
	end)

	-- Cuando algo caduca, se recalculan las estadísticas; y los relojes pasan a data.paid
	task.spawn(function()
		local beat = 0
		while true do
			task.wait(1)
			beat += 1
			local t = now()
			for _, profile in Profiles.all() do
				if profile.stats and activeKey(profile, t) ~= profile.boostKey then
					Profiles.refresh(profile)
				end
				if beat % 2 == 0 then
					syncPaid(profile)
				end
			end
		end
	end)
end

return Monetize
