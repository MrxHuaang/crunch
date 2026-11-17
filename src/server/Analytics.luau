-- Medición (AnalyticsService) e insignias (BadgeService). Solo escucha: no cambia la partida ni
-- guarda nada en el perfil. Si Roblox falla, se avisa en la consola y el juego sigue.
--   Embudo de primeros pasos: suceso "Opening" (0 = empieza la cadena, 1..6 = pasos de Opening.luau).
--   Progresión: "Capas" (suceso "Dig") y "Enjambres" (suceso "Rebirth").
--   Economía, sin acercarse al límite de Roblox (120 + 20 por jugadora llamadas al minuto):
--     Jalea: fuente al enjambrar; gasto en la cámara real (suceso "Bought" "royal"). Pocas al día.
--     Comida: lo ganado y lo gastado se suman por jugadora y salen cada FLUSH s y al salir (2 llamadas).
--   Compras con Robux: evento personalizado "CompraRobux" (valor = robux; campos: id y tipo).
-- Insignias: Config.Badges (badgeId = 0, apagada). Se piden en segundo plano y una vez por sesión.

local AnalyticsService = game:GetService("AnalyticsService")
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Events = require(script.Parent.Events)
local Monetize = require(script.Parent.Monetize)
local Profiles = require(script.Parent.Profiles)

local Analytics = {}

local FLUSH = 300
-- Nombres del embudo: el paso n del suceso "Opening" es el escalón n + 1
local STEPS = { "Entra", "Muerde migas", "Primera entrega", "Primera mejora", "Corre", "Primera obrera", "Capa 2" }
local FIELD1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local FIELD2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name
local SOURCE = Enum.AnalyticsEconomyFlowType.Source
local SINK = Enum.AnalyticsEconomyFlowType.Sink
local GAMEPLAY = Enum.AnalyticsEconomyTransactionType.Gameplay.Name
local SHOP = Enum.AnalyticsEconomyTransactionType.Shop.Name

-- Comida de cada perfil desde el último envío: saldo y total visto, y lo ganado y gastado pendiente
type Ledger = { food: number, total: number, earned: number, spent: number }
local ledgers: { [any]: Ledger } = {}
local given: { [Player]: { [number]: boolean } } = {} -- [jugadora][badgeId] = dada o pidiéndose

-- Una llamada que falle no debe tocar la partida
local function log(method: string, ...: any)
	local ok, err = pcall(function(...)
		(AnalyticsService :: any)[method](AnalyticsService, ...)
	end, ...)
	if not ok then
		warn("[CRUNCH!] Analytics", method, err)
	end
end

-- totalFood solo sube, así que lo ganado es su diferencia; lo gastado, lo que falta para cuadrar el saldo
local function track(profile)
	local data = profile.data
	local ledger = ledgers[profile]
	if not ledger then
		ledgers[profile] = { food = data.food, total = data.totalFood, earned = 0, spent = 0 }
		return
	end
	local income = data.totalFood - ledger.total
	ledger.earned += income
	ledger.spent += math.max(0, ledger.food + income - data.food)
	ledger.food, ledger.total = data.food, data.totalFood
end

local function flush(profile)
	local ledger = ledgers[profile]
	if not ledger then
		return
	end
	track(profile)
	local player, food = profile.player, profile.data.food
	if ledger.earned > 0 then
		log("LogEconomyEvent", player, SOURCE, "Comida", ledger.earned, food, GAMEPLAY, "Ingreso")
	end
	if ledger.spent > 0 then
		log("LogEconomyEvent", player, SINK, "Comida", ledger.spent, food, SHOP, "Compras")
	end
	ledger.earned, ledger.spent = 0, 0
end

local function reached(def, data): boolean
	if def.depth then
		return data.depth >= def.depth
	elseif def.rebirths then
		return data.rebirths >= def.rebirths
	end
	return def.tarta == true and data.tartaDone == true
end

local function checkBadges(profile)
	local player = profile.player
	local mine = given[player]
	if not mine then
		mine = {}
		given[player] = mine
	end
	for _, def in Config.Badges do
		local id = def.badgeId
		if id > 0 and not mine[id] and reached(def, profile.data) then
			mine[id] = true -- ya en camino: no se pide dos veces
			-- En segundo plano: las llamadas esperan a Roblox y no deben frenar el suceso
			task.spawn(function()
				local ok, err = pcall(function()
					if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
						BadgeService:AwardBadgeAsync(player.UserId, id)
					end
				end)
				if not ok then
					mine[id] = nil -- se reintenta en el siguiente suceso
					warn("[CRUNCH!] Insignia", def.id, err)
				end
			end)
		end
	end
end

-- Primera vez que se ve el perfil (al entrar): saldo de partida y las insignias que ya se merece
local function onRefresh(profile)
	if not ledgers[profile] then
		track(profile)
		checkBadges(profile)
	end
end

function Analytics.start(_remotes: Folder)
	table.insert(Profiles.onRefresh, onRefresh)
	for _, profile in Profiles.all() do
		onRefresh(profile)
	end

	Events.on("Opening", function(profile, step: number)
		local name = STEPS[step + 1]
		if name then
			log("LogOnboardingFunnelStepEvent", profile.player, step + 1, name)
		end
	end)

	Events.on("Dig", function(profile, depth: number)
		track(profile) -- la comida de la capa se cuenta como gasto antes de un posible enjambre
		local zone = Config.Zones[depth]
		log("LogProgressionCompleteEvent", profile.player, "Capas", depth, if zone then zone.name else tostring(depth))
		checkBadges(profile)
	end)

	Events.on("Bought", function(profile, kind: string, id: any)
		track(profile)
		local def = kind == "royal" and Config.RoyalById[id]
		if def then
			local data = profile.data
			-- El nivel ya subió: lo pagado es el precio del nivel anterior
			local cost = Stats.royalCost(def, (data.royal[id] or 1) - 1)
			log("LogEconomyEvent", profile.player, SINK, "Jalea", cost, data.jelly, SHOP, id)
		end
	end)

	Events.on("Rebirth", function(profile, jelly: number)
		local data = profile.data
		log("LogEconomyEvent", profile.player, SOURCE, "Jalea", jelly, data.jelly, GAMEPLAY, "Enjambre")
		log("LogProgressionCompleteEvent", profile.player, "Enjambres", data.rebirths, "Enjambre " .. data.rebirths)
		checkBadges(profile)
	end)

	-- Enjambrar deja la comida a cero: eso no es un gasto, solo se recoge lo ganado y se empieza de nuevo
	Events.on("RunReset", function(profile)
		local ledger = ledgers[profile]
		if ledger then
			ledger.earned += profile.data.totalFood - ledger.total
			ledger.food, ledger.total = profile.data.food, profile.data.totalFood
		end
	end)

	-- La tarta no tiene suceso propio: Profiles.trackFood la marca justo antes de "Ate". Se revisa una
	-- sola vez por partida (si no, cada mordisco a la tarta, también de las obreras, volvía a pedirlo)
	local tartaChecked: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	Events.on("Ate", function(profile, def)
		if def.id == "Tarta" and profile.data.tartaDone and not tartaChecked[profile] then
			tartaChecked[profile] = true
			checkBadges(profile)
		end
	end)

	table.insert(Monetize.onGrant, function(buyer, def, _recipient, kind: string)
		log("LogCustomEvent", buyer.player, "CompraRobux", def.robux or 1, { [FIELD1] = def.id, [FIELD2] = kind })
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH)
			for profile in pairs(ledgers) do
				flush(profile)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		given[player] = nil
		for profile in pairs(ledgers) do
			if profile.player == player then
				flush(profile)
				ledgers[profile] = nil
			end
		end
	end)
end

return Analytics
