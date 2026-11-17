-- Primeros pasos: una cadena corta de metas, una cada vez, en la tira de narración del cliente.
--   1 morder Config.Opening.Bites trozos  2 primera entrega  3 primera mejora  4 correr
--   5 primera obrera  6 excavar la capa 2
-- Cada meta cumplida se celebra y da un premio pequeño (Config.Opening.Prizes) que deja pagar la
-- siguiente. Los Juicy primeros trozos del jardín que muerde quien empieza valen JuicyMult veces.
-- Solo para quien empieza de cero; quien ya tenía progreso se la salta entera.
--
-- Guardado (perezoso): data.opening = paso actual (1..6) o 7 si ya terminó; data.openingBites =
-- trozos jugosos ya mordidos.
-- Atributos de la jugadora: "Opening" (paso actual, nil si terminó), "OpeningCount" (progreso del paso 1).
-- Remoto "Opening": servidor -> dueña "Step" (paso hecho, premio, paso siguiente);
-- cliente -> servidor "Ran" (corrió con Shift o el botón, paso 4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(script.Parent.Events)
local Profiles = require(script.Parent.Profiles)

local Opening = {}

local O = Config.Opening
local STEPS = 6
local DONE = STEPS + 1

local remote: RemoteEvent
local counts: { [any]: number } = {} -- [profile] = trozos mordidos en el paso 1 (no se guarda)

local function anyUpgrade(data): boolean
	for _, level in data.nodes do
		if level > 0 then
			return true
		end
	end
	return type(data.minis) == "table" and next(data.minis) ~= nil
end

-- Pasos que ya se cumplen solos (comprar obreras antes de tiempo, por ejemplo)
local function satisfied(profile, step: number): boolean
	local data = profile.data
	if step == 3 then
		return anyUpgrade(data)
	elseif step == 5 then
		return data.workers > 0
	elseif step == 6 then
		return data.depth >= 2
	end
	return false
end

local function sync(profile)
	local player = profile.player
	local step = profile.data.opening
	if type(step) == "number" and step >= 1 and step <= STEPS then
		player:SetAttribute("Opening", step)
		player:SetAttribute("OpeningCount", counts[profile] or 0)
	else
		player:SetAttribute("Opening", nil)
		player:SetAttribute("OpeningCount", nil)
	end
end

-- Campo perezoso: la primera vez se decide si esta jugadora empieza de cero
local function ensure(profile): boolean
	local data = profile.data
	if data.opening == nil then
		local fresh = data.totalFood <= 0 and data.rebirths == 0 and data.workers == 0 and data.depth <= 1 and not anyUpgrade(data)
		data.opening = if fresh then 1 else DONE
		if fresh then
			data.openingBites = 0
			Events.fire("Opening", profile, 0) -- primer escalón del embudo: quien empieza la cadena
		end
	end
	return type(data.opening) == "number" and data.opening < DONE
end

local function complete(profile, step: number)
	local data = profile.data
	if data.opening ~= step then
		return
	end
	data.opening = step + 1
	Events.fire("Opening", profile, step)
	while data.opening <= STEPS and satisfied(profile, data.opening) do
		Events.fire("Opening", profile, data.opening) -- cuenta para el embudo aunque no tenga fiesta
		data.opening += 1 -- ya hecho por su cuenta: sin premio ni fiesta
	end
	counts[profile] = 0
	local prize = O.Prizes[step] or 0
	if prize > 0 then
		data.food += prize
		data.runFood += prize
		data.totalFood += prize
	end
	sync(profile)
	Profiles.push(profile)
	remote:FireClient(profile.player, "Step", step, prize, data.opening)
end

-- Tras cada compra o cambio (Profiles.refresh): mejoras, obreras y capas
local function onRefresh(profile)
	if not remote or not ensure(profile) then
		if remote then
			sync(profile)
		end
		return
	end
	local step = profile.data.opening
	if satisfied(profile, step) then
		complete(profile, step)
	else
		sync(profile)
	end
end

local function onAte(profile, def, taken: number, byWorkers: boolean)
	if byWorkers or taken <= 0 or not ensure(profile) then
		return
	end
	local data = profile.data
	-- Los primeros trozos del jardín valen más (se suma a la carga que acaba de entrar)
	local juicy = data.openingBites
	if type(juicy) == "number" and juicy < O.Juicy and def.zone == 1 then
		local n = math.min(taken, O.Juicy - juicy)
		data.openingBites = juicy + n
		profile.carryValue += n * def.value * (profile.stats.zoneMult[1] or 1) * (O.JuicyMult - 1)
	end
	if data.opening == 1 then
		counts[profile] = (counts[profile] or 0) + taken
		if counts[profile] >= O.Bites then
			complete(profile, 1)
		else
			sync(profile)
		end
	end
end

local function onDeposit(profile)
	if not ensure(profile) then
		return
	end
	complete(profile, 1)
	complete(profile, 2)
end

local function onRequest(player: Player, action: any)
	local profile = Profiles.get(player)
	if not profile or action ~= "Ran" or not ensure(profile) then
		return
	end
	complete(profile, 4)
end

function Opening.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Opening"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	table.insert(Profiles.onRefresh, onRefresh)
	Events.on("Ate", onAte)
	Events.on("Deposit", onDeposit)

	-- Las que entraron antes de arrancar este módulo
	for _, profile in Profiles.all() do
		onRefresh(profile)
	end

	-- Las que se van: fuera de la tabla de progreso
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		for profile in pairs(counts) do
			if profile.player == player then
				counts[profile] = nil
			end
		end
	end)
end

return Opening
