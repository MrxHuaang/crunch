-- Mascotas en el servidor: huevos, tiradas, inventario, posadero (las 3 puestas), fusiones
-- y el bono que dan. Todo se valida aquí; el cliente solo pide.
--
-- data.pets = {
--   list = { { id = 7, s = "mariquita", r = 2, l = 3 }, ... }, -- hasta 30
--   equipped = { 7, 3 }, -- ids, hasta 3, en orden de hueco
--   eggs = { 4, 1, 0, ... }, -- huevos comprados en cada capa en esta partida (sube el precio)
--   next = 8, -- siguiente id
--   run = 2, -- enjambre al que pertenece `eggs`: al enjambrar se ponen a cero
-- }
-- Enjambrar no toca data.pets: los bichos se quedan.
--
-- Remoto "Pet":
--   cliente -> servidor: ("Sync") | ("Buy") | ("Best") | ("Equip", id) | ("Unequip", id) | ("Release", id) | ("Fuse", id)
--   servidor -> cliente: ("Sync", { pets, equipped, eggs }) | ("Hatch", entry) | ("Fused", entry) | ("Fail", texto)
-- Atributo del jugador PetsEquipped: "mariquita:2,abeja:1" (lo leen todos para dibujar seguidores).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Profiles = require(script.Parent.Profiles)

local PetService = {}

local ACTIONS_PER_SECOND = 12

local remote: RemoteEvent
local rng = Random.new()
local eggTimes: { [Player]: { number } } = {}
local actionTimes: { [Player]: { number } } = {}
local checked: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local syncKey: { [any]: string } = setmetatable({}, { __mode = "k" }) :: any

local function blankEggs(): { number }
	local eggs = {}
	for i = 1, PetDefs.MaxLayer do
		eggs[i] = 0
	end
	return eggs
end

-- Limpia lo guardado una vez por sesión: entradas rotas, ids repetidos, puestas que ya no existen
local function sanitize(pets)
	local list = {}
	local seen = {}
	local top = 0
	for _, entry in pets.list do
		if PetDefs.valid(entry) and type(entry.id) == "number" and not seen[entry.id] and #list < PetDefs.MaxPets then
			seen[entry.id] = true
			top = math.max(top, entry.id)
			table.insert(list, { id = entry.id, s = entry.s, r = math.floor(entry.r), l = math.floor(entry.l) })
		end
	end
	pets.list = list
	pets.next = math.max(pets.next, top + 1)

	local equipped = {}
	local used = {}
	for _, id in pets.equipped do
		if seen[id] and not used[id] and #equipped < PetDefs.MaxEquipped then
			used[id] = true
			table.insert(equipped, id)
		end
	end
	pets.equipped = equipped
end

local function petsOf(profile)
	local data = profile.data
	local pets = data.pets
	if type(pets) ~= "table" then
		pets = {}
		data.pets = pets
	end
	if type(pets.list) ~= "table" then
		pets.list = {}
	end
	if type(pets.equipped) ~= "table" then
		pets.equipped = {}
	end
	if type(pets.eggs) ~= "table" then
		pets.eggs = blankEggs()
	end
	for i = 1, PetDefs.MaxLayer do
		if type(pets.eggs[i]) ~= "number" then
			pets.eggs[i] = 0
		end
	end
	if type(pets.next) ~= "number" then
		pets.next = 1
	end
	if type(pets.run) ~= "number" then
		pets.run = data.rebirths or 0
	end
	if not checked[profile] then
		checked[profile] = true
		sanitize(pets)
	end
	return pets
end

local function find(pets, id: any): (any, number?)
	for index, entry in pets.list do
		if entry.id == id then
			return entry, index
		end
	end
	return nil, nil
end

local function isEquipped(pets, id: number): number?
	return table.find(pets.equipped, id)
end

local function equippedEntries(pets)
	local entries = {}
	for _, id in pets.equipped do
		local entry = find(pets, id)
		if entry then
			table.insert(entries, entry)
		end
	end
	return entries
end

local function sync(profile)
	local pets = petsOf(profile)
	remote:FireClient(profile.player, "Sync", {
		pets = pets.list,
		equipped = pets.equipped,
		eggs = pets.eggs,
	})
end

local function fail(profile, text: string)
	remote:FireClient(profile.player, "Fail", text)
end

-- Ventana deslizante: como mucho `limit` llamadas por segundo
local function allow(times: { [Player]: { number } }, player: Player, limit: number): boolean
	local now = os.clock()
	local list = times[player]
	if not list then
		list = {}
		times[player] = list
	end
	while list[1] and now - list[1] > 1 do
		table.remove(list, 1)
	end
	if #list >= limit then
		return false
	end
	table.insert(list, now)
	return true
end

-- Se ejecuta al final de cada Profiles.refresh, con las estadísticas recién derivadas
local function applyPets(profile)
	local data = profile.data
	local pets = petsOf(profile)

	-- Enjambraste: los precios de los huevos vuelven a empezar
	if pets.run ~= data.rebirths then
		pets.run = data.rebirths
		pets.eggs = blankEggs()
	end

	local entries = equippedEntries(pets)
	local totals = PetDefs.totals(entries)
	local stats = profile.stats
	for kind, def in PetDefs.Bonuses do
		stats[def.stat] *= totals[kind]
	end

	local player = profile.player
	-- Profiles ya publicó JellyMult antes de los ganchos: se corrige para que el cliente
	-- muestre la misma jalea que dará enjambrar
	player:SetAttribute("JellyMult", stats.jellyMult)
	player:SetAttribute("PetsEquipped", PetDefs.encode(entries))

	-- Capa nueva o enjambre: cambia el precio del huevo
	local key = data.depth .. "|" .. data.rebirths
	if syncKey[profile] ~= key then
		syncKey[profile] = key
		sync(profile)
	end
end

local function onRefresh(profile)
	local ok, err = pcall(applyPets, profile)
	if not ok then
		warn("[CRUNCH!] Mascotas:", err)
	end
end

local function buyEgg(profile)
	local player = profile.player
	if not allow(eggTimes, player, PetDefs.EggsPerSecond) then
		return
	end
	local data = profile.data
	local pets = petsOf(profile)
	if #pets.list >= PetDefs.MaxPets then
		fail(profile, "No caben más bichos. Suelta o fusiona alguno")
		return
	end
	local depth = math.clamp(data.depth, 1, PetDefs.MaxLayer)
	local price = PetDefs.eggPrice(depth, pets.eggs[depth])
	if data.food < price then
		fail(profile, "Me falta comida para ese huevo")
		return
	end
	data.food -= price
	pets.eggs[depth] += 1

	local species, rarity = PetDefs.roll(rng)
	local entry = { id = pets.next, s = species, r = rarity, l = depth }
	pets.next += 1
	table.insert(pets.list, entry)

	-- Si hay hueco en el posadero, se sube sola
	if #pets.equipped < PetDefs.MaxEquipped then
		table.insert(pets.equipped, entry.id)
		Profiles.refresh(profile)
	else
		Profiles.push(profile)
	end
	remote:FireClient(player, "Hatch", entry)
	sync(profile)
end

local function equip(profile, id: number)
	local pets = petsOf(profile)
	local entry = find(pets, id)
	if not entry or isEquipped(pets, id) then
		return
	end
	if #pets.equipped >= PetDefs.MaxEquipped then
		-- Posadero lleno: sale la más floja
		local weakest, weakestPower = 1, math.huge
		for slot, otherId in pets.equipped do
			local other = find(pets, otherId)
			local power = if other then PetDefs.power(other) else -1
			if power < weakestPower then
				weakest, weakestPower = slot, power
			end
		end
		pets.equipped[weakest] = id
	else
		table.insert(pets.equipped, id)
	end
	Profiles.refresh(profile)
	sync(profile)
end

local function unequip(profile, id: number)
	local pets = petsOf(profile)
	local slot = isEquipped(pets, id)
	if not slot then
		return
	end
	table.remove(pets.equipped, slot)
	Profiles.refresh(profile)
	sync(profile)
end

-- Las tres más fuertes al posadero
local function equipBest(profile)
	local pets = petsOf(profile)
	local sorted = table.clone(pets.list)
	table.sort(sorted, function(a, b)
		local pa, pb = PetDefs.power(a), PetDefs.power(b)
		if pa ~= pb then
			return pa > pb
		end
		return a.id < b.id
	end)
	local equipped = {}
	for i = 1, math.min(PetDefs.MaxEquipped, #sorted) do
		equipped[i] = sorted[i].id
	end
	pets.equipped = equipped
	Profiles.refresh(profile)
	sync(profile)
end

local function release(profile, id: number)
	local pets = petsOf(profile)
	local _, index = find(pets, id)
	if not index then
		return
	end
	table.remove(pets.list, index)
	local slot = isEquipped(pets, id)
	if slot then
		table.remove(pets.equipped, slot)
		Profiles.refresh(profile)
	end
	sync(profile)
end

-- Tres iguales (especie, rareza y capa) se vuelven una de la rareza siguiente
local function fuse(profile, id: number)
	local pets = petsOf(profile)
	local entry = find(pets, id)
	if not entry then
		return
	end
	if entry.r >= #PetDefs.Rarities then
		fail(profile, "No hay nada más raro que una mítica")
		return
	end
	local kind = PetDefs.kind(entry)
	local chosen = { entry }
	-- Primero las que no están en el posadero
	for pass = 1, 2 do
		for _, other in pets.list do
			if #chosen >= 3 then
				break
			end
			local equippedNow = isEquipped(pets, other.id) ~= nil
			if other ~= entry and PetDefs.kind(other) == kind and equippedNow == (pass == 2) then
				table.insert(chosen, other)
			end
		end
	end
	if #chosen < 3 then
		fail(profile, "Hacen falta tres iguales: misma especie, rareza y capa")
		return
	end

	local fused = { id = pets.next, s = entry.s, r = entry.r + 1, l = entry.l }
	pets.next += 1

	-- La nueva ocupa el primer hueco que dejan las fusionadas
	local firstSlot: number? = nil
	for _, gone in chosen do
		local slot = isEquipped(pets, gone.id)
		if slot then
			firstSlot = if firstSlot then math.min(firstSlot, slot) else slot
		end
	end
	local equipped = {}
	for slot, otherId in pets.equipped do
		if slot == firstSlot then
			table.insert(equipped, fused.id)
		else
			local removed = false
			for _, gone in chosen do
				if gone.id == otherId then
					removed = true
				end
			end
			if not removed then
				table.insert(equipped, otherId)
			end
		end
	end
	pets.equipped = equipped

	for _, gone in chosen do
		local _, index = find(pets, gone.id)
		if index then
			table.remove(pets.list, index)
		end
	end
	table.insert(pets.list, fused)

	Profiles.refresh(profile)
	remote:FireClient(profile.player, "Fused", fused)
	sync(profile)
end

local function onEvent(player: Player, action: any, id: any)
	local profile = Profiles.get(player)
	if not profile or type(action) ~= "string" then
		return
	end
	if action == "Buy" then
		buyEgg(profile)
		return
	end
	if not allow(actionTimes, player, ACTIONS_PER_SECOND) then
		return
	end
	if action == "Sync" then
		sync(profile)
		return
	elseif action == "Best" then
		equipBest(profile)
		return
	end
	if type(id) ~= "number" or id ~= id then
		return
	end
	if action == "Equip" then
		equip(profile, id)
	elseif action == "Unequip" then
		unequip(profile, id)
	elseif action == "Release" then
		release(profile, id)
	elseif action == "Fuse" then
		fuse(profile, id)
	end
end

function PetService.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Pet"
	remote.Parent = remotes

	table.insert(Profiles.onRefresh, onRefresh)
	remote.OnServerEvent:Connect(onEvent)
	Players.PlayerRemoving:Connect(function(player)
		eggTimes[player] = nil
		actionTimes[player] = nil
	end)

	-- Los que entraron antes de arrancar este módulo
	for _, profile in Profiles.all() do
		Profiles.refresh(profile)
	end

	-- Solo en Studio: regalar bichos para probar.
	-- ServerScriptService.PetDebug:Fire("give", "mariquita", 4, 3)  (especie, rareza, capa)
	if RunService:IsStudio() then
		local debug = Instance.new("BindableEvent")
		debug.Name = "PetDebug"
		debug.Event:Connect(function(command: string, species: any, rarity: any, layer: any)
			for _, profile in Profiles.all() do
				local pets = petsOf(profile)
				if command == "give" and #pets.list < PetDefs.MaxPets then
					local entry = {
						id = pets.next,
						s = if PetDefs.SpeciesById[species] then species else PetDefs.Species[rng:NextInteger(1, #PetDefs.Species)].id,
						r = math.clamp(tonumber(rarity) or 1, 1, #PetDefs.Rarities),
						l = math.clamp(tonumber(layer) or 1, 1, PetDefs.MaxLayer),
					}
					pets.next += 1
					table.insert(pets.list, entry)
				elseif command == "clear" then
					pets.list = {}
					pets.equipped = {}
				end
				Profiles.refresh(profile)
				sync(profile)
			end
		end)
		debug.Parent = game:GetService("ServerScriptService")
	end
end

return PetService
