-- Compras del árbol, excavar capas, obreras, Árbol Real, vestidor y el rebirth (Enjambrar).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Outfits = require(ReplicatedStorage.Shared.Outfits)
local Trails = require(ReplicatedStorage.Shared.Trails)
local Colony = require(script.Parent.Colony)
local Events = require(script.Parent.Events)
local Profiles = require(script.Parent.Profiles)

local Shop = {}

local fxRemote: RemoteEvent

-- Como mucho 8 peticiones por segundo entre Buy, Wear y Rebirth (cubo de fichas, como Orders).
-- Vive en el perfil (no se guarda) para no tener que limpiarlo al salir.
local function allow(profile): boolean
	local clock = os.clock()
	profile.shopTokens = math.min(8, (profile.shopTokens or 8) + (clock - (profile.shopTokenAt or clock)) * 8)
	profile.shopTokenAt = clock
	if profile.shopTokens < 1 then
		return false
	end
	profile.shopTokens -= 1
	return true
end

local function buyNode(profile, id: string): boolean
	local def = Config.NodeById[id]
	if not def or def.unit then
		return false
	end
	local data = profile.data
	local level = data.nodes[id] or 0
	if level >= Stats.available(def, data.depth) or not Stats.unlocked(def, data.nodes, data.workers, data.depth) then
		return false
	end
	local cost = Stats.nodeCost(def, level)
	if data.food < cost then
		return false
	end
	data.food -= cost
	data.nodes[id] = level + 1
	return true
end

-- Todos los niveles de un nodo que te puedas pagar ahora, hasta su tope. Devuelve cuántos compró.
local function buyNodeMax(profile, id: string): number
	local bought = 0
	while bought < 200 and buyNode(profile, id) do
		bought += 1
	end
	return bought
end

local function buyMini(profile, id: string): boolean
	local def = Config.MiniById[id]
	if not def then
		return false
	end
	local data = profile.data
	if data.minis[id] or not Stats.miniOpen(def, data.minis, data.depth) or data.food < def.cost then
		return false
	end
	data.food -= def.cost
	data.minis[id] = true
	-- "Cuna nueva": obreras gratis al momento. Caben siempre: la misma galería sube el cupo el doble
	-- (Profiles.refresh recorta a la guardería, así que sin guardería no llegan)
	if def.kind == "crew" then
		data.workers += def.amount
	end
	return true
end

-- Excavar una capa más: abre la zona siguiente y sube el tope de las mejoras.
local function dig(profile): boolean
	local data = profile.data
	local cost = Stats.digCost(data.depth)
	-- Pala dorada (Monetize, data.paid.halfDig): esta capa cuesta la mitad
	local paid = data.paid
	local half = type(paid) == "table" and type(paid.halfDig) == "number" and paid.halfDig > 0
	if half then
		cost *= 0.5
	end
	if data.depth >= Stats.MaxDepth or data.food < cost then
		return false
	end
	data.food -= cost
	data.depth += 1
	if half then
		paid.halfDig -= 1
	end
	return true
end

-- Devuelve cuántas obreras compró.
local function buyWorkers(profile, wanted: number): number
	local data = profile.data
	local cap = profile.stats.workerCap
	local bought = 0
	while bought < wanted and data.workers < cap do
		local cost = Stats.workerCost(data.workers, profile.stats.workerDiscount)
		if data.food < cost then
			break
		end
		data.food -= cost
		data.workers += 1
		bought += 1
	end
	return bought
end

local function buyRoyal(profile, id: string): boolean
	local def = Config.RoyalById[id]
	if not def then
		return false
	end
	local data = profile.data
	local level = data.royal[id] or 0
	local cost = Stats.royalCost(def, level)
	if level >= def.max or data.jelly < cost then
		return false
	end
	data.jelly -= cost
	data.royal[id] = level + 1
	return true
end

local function onBuy(player: Player, kind: any, id: any, amount: any)
	local profile = Profiles.get(player)
	if not profile or type(kind) ~= "string" or not allow(profile) then
		return
	end

	-- Sucesos "Bought" que toca avisar: uno por cosa comprada, también en las compras de golpe
	local bought: { { any } } = {}
	local ok = false
	if kind == "node" and type(id) == "string" then
		ok = buyNode(profile, id)
		if ok then
			table.insert(bought, { "node", id })
		end
	elseif kind == "node-max" and type(id) == "string" then
		for _ = 1, buyNodeMax(profile, id) do
			table.insert(bought, { "node", id })
		end
		ok = #bought > 0
	elseif kind == "mini" and type(id) == "string" then
		ok = buyMini(profile, id)
		if ok then
			table.insert(bought, { "mini", id })
		end
	elseif kind == "dig" then
		ok = dig(profile)
		id = profile.data.depth
	elseif kind == "workers" then
		local count = buyWorkers(profile, if amount == "max" then 10000 else 1)
		ok = count > 0
		if ok then
			table.insert(bought, { "workers", count })
		end
	elseif kind == "royal" and type(id) == "string" then
		ok = buyRoyal(profile, id)
		if ok then
			table.insert(bought, { "royal", id })
		end
	end

	if ok then
		Profiles.refresh(profile)
		fxRemote:FireClient(player, "Bought", kind, id)
		if kind == "dig" then
			Events.fire("Dig", profile, profile.data.depth)
		end
		for _, item in bought do
			Events.fire("Bought", profile, item[1], item[2])
		end
	end
end

-- Vestidor: la primera vez se compra con comida; luego ponérselo es gratis.
local function onWear(player: Player, kind: any, id: any)
	local profile = Profiles.get(player)
	if not profile or type(id) ~= "string" or not allow(profile) then
		return
	end
	local def = if kind == "skin" then Config.SkinById[id] elseif kind == "hat" then Config.HatById[id] elseif kind == "trail" then Trails.byId[id] elseif kind == "outfit" then Outfits.byId[id] else nil
	-- kind es skin, hat, trail u outfit: el mismo nombre que su campo en data.
	-- Si ya lo llevas no se hace nada (refresh rehace el modelo de la hormiga).
	local data = profile.data
	if not def or data[kind] == id then
		return
	end
	if def.pass then
		if not profile.passes[def.pass] then
			return
		end
	elseif not data.owned[id] then
		if data.food < def.cost then
			return
		end
		data.food -= def.cost
		data.owned[id] = true
	end
	data[kind] = id
	Profiles.refresh(profile)
	fxRemote:FireClient(player, "Worn", kind, id)
end

-- Jalea que daría enjambrar ahora mismo.
function Shop.jellyNow(profile): number
	local data = profile.data
	local gain = Stats.jellyFor(data.runFood, profile.stats.jellyMult)
	if data.tartaDone then
		gain *= Config.Rebirth.TartaMult
	end
	return gain
end

local function onRebirth(player: Player)
	local profile = Profiles.get(player)
	if not profile or not allow(profile) then
		return
	end
	local gain = Shop.jellyNow(profile)
	if gain < 1 then
		return
	end
	local data = profile.data
	data.jelly += gain
	data.rebirths += 1
	Shop.resetRun(profile)
	fxRemote:FireClient(player, "Rebirth", gain)
	Events.fire("Rebirth", profile, gain)

	-- Reaparece en casa, sin carga
	player:LoadCharacter()
end

-- Vuelve la partida al principio: lo que se pierde al enjambrar. También lo usa el panel DEV.
function Shop.resetRun(profile)
	local data = profile.data
	data.food = 0
	data.runFood = 0
	data.nodes = {}
	data.minis = {}
	data.workers = 0
	data.tartaDamage = 0
	data.tartaDone = false
	data.rate = 0
	data.baseRate = 0
	data.depth = 1 + math.min(data.royal.royalDepth or 0, Stats.MaxDepth - 1)

	-- Nido heredado: empiezas con obreras y con la guardería justa para que quepan
	local inherited = Config.Rebirth.StartWorkers * (data.royal.royalStart or 0)
	if inherited > 0 then
		data.nodes.nursery = Stats.nurseryFor(inherited)
		data.workers = inherited
	end

	profile.frenzyUntil = 0
	profile.frenzyReadyAt = 0
	profile.buffUntil = 0
	profile.eggAt = nil
	Colony.clearTrails(profile)
	Profiles.refresh(profile)
	Events.fire("RunReset", profile)
end

function Shop.start(remotes: Folder)
	fxRemote = remotes.Fx
	remotes.Buy.OnServerEvent:Connect(onBuy)
	remotes.Wear.OnServerEvent:Connect(onWear)
	remotes.Rebirth.OnServerEvent:Connect(onRebirth)
end

return Shop
