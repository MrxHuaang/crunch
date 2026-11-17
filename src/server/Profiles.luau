-- Estado en memoria de cada jugador y su reflejo en atributos, que es lo que lee el cliente.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AntLook = require(ReplicatedStorage.Shared.AntLook)
local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Trails = require(ReplicatedStorage.Shared.Trails)
local World = require(script.Parent.World)

local Profiles = {}

local byPlayer = {}

Profiles.fx = nil :: RemoteEvent? -- lo asigna init
Profiles.onRefresh = {} :: { (any) -> () } -- otros módulos se apuntan aquí para reaccionar a compras

function Profiles.get(player: Player)
	return byPlayer[player]
end

function Profiles.all()
	return byPlayer
end

function Profiles.create(player: Player, data, canSave: boolean)
	local profile = {
		player = player,
		data = data,
		canSave = canSave,
		passes = {},
		stats = nil,
		hill = nil,
		carry = 0,
		carryValue = 0,
		carryColor = Color3.fromRGB(222, 166, 92),
		lastBite = 0,
		combo = 0,
		buffUntil = 0,
		trails = {}, -- [hueco] = { food, id, pos, order }
		trailOrder = 0,
		autoFoods = {}, -- [hueco] = comida del jardín a la que van las obreras sin rastro
		remainders = {}, -- [comida] = fracción de trozo que las obreras llevan arrancada
		frenzyUntil = 0,
		frenzyReadyAt = 0,
		lookKey = "",
		hillKey = "",
		minisKey = "",
	}
	byPlayer[player] = profile
	Profiles.refresh(profile)
	return profile
end

function Profiles.remove(player: Player)
	byPlayer[player] = nil
end

-- Sincroniza los números que cambian a menudo.
function Profiles.push(profile)
	local player = profile.player
	local data = profile.data
	player:SetAttribute("Food", data.food)
	player:SetAttribute("RunFood", data.runFood)
	player:SetAttribute("TotalFood", data.totalFood)
	player:SetAttribute("Jelly", data.jelly)
	player:SetAttribute("Rebirths", data.rebirths)
	player:SetAttribute("Workers", data.workers)
	player:SetAttribute("Carry", profile.carry)
	player:SetAttribute("TartaDamage", data.tartaDamage)
	player:SetAttribute("TartaDone", data.tartaDone)
	player:SetAttribute("FrenzyUntil", profile.frenzyUntil)
	player:SetAttribute("FrenzyReadyAt", profile.frenzyReadyAt)
	player:SetAttribute("BuffUntil", profile.buffUntil)
	-- Comida por segundo de la colonia (la ficha de la tienda la usa para hablar con tus números)
	player:SetAttribute("Rate", math.floor(Profiles.baseRate(profile) * 10) / 10)

	local hill = profile.hill
	if hill then
		hill:SetAttribute("Workers", data.workers)
		hill:SetAttribute("Soldiers", profile.stats.soldiers)
		hill:SetAttribute("WorkerSpeed", profile.stats.workerSpeed)
		hill:SetAttribute("FrenzyUntil", profile.frenzyUntil)
	end
end

local function trophyCount(data): number
	local count = 0
	for _ in data.trophies do
		count += 1
	end
	return count
end

-- Viste a la hormiga según sus mejoras. Solo rehace el modelo si algo visible cambió.
function Profiles.applyLook(profile, force: boolean?)
	local character = profile.player.Character
	if not character then
		return
	end
	local data = profile.data
	local look = Stats.look(data.nodes, data.royal, data.depth, data.rebirths, data.skin, data.hat)
	look.wings = look.wings or profile.passes.goldWings == true
	look.outfit = data.outfit
	local key = table.concat({ data.trail, look.skin, look.hat, look.jaws, tostring(look.saw), look.spikes, look.belly, look.shoes, tostring(look.wings), look.armor, math.min(look.crown, 5), look.scale }, "|")
	key ..= "|" .. tostring(look.outfit)
	if not force and key == profile.lookKey then
		return
	end
	profile.lookKey = key
	local ok, err = pcall(AntLook.apply, character, look)
	if not ok then
		warn("[CRUNCH!] No se pudo vestir a la hormiga:", err)
	end

	-- Estela: cintas, partículas y luz que salen del abdomen (Shared/Trails)
	local trailOk, trailErr = pcall(Trails.apply, character, data.trail, character:GetScale())
	if not trailOk then
		warn("[CRUNCH!] No se pudo poner la estela:", trailErr)
	end
end

-- Recalcula estadísticas tras comprar algo y sincroniza todo.
function Profiles.refresh(profile)
	local player = profile.player
	local data = profile.data
	if type(data.minis) ~= "table" then
		data.minis = {}
	end
	profile.stats = Stats.derive(data.nodes, data.royal, data.depth, data.minis)
	data.workers = math.min(data.workers, profile.stats.workerCap)

	-- Pases de juego: multiplican por encima de todo lo demás
	local passes = profile.passes
	if passes.x2Food then
		profile.stats.foodMult *= 2
	end
	if passes.fastColony then
		profile.stats.colonyMult *= 2
	end
	if passes.turbo then
		profile.stats.walkSpeed *= 1.3
	end
	if passes.vip then
		profile.stats.foodMult *= 1.25
	end
	if passes.x2Jelly then
		profile.stats.jellyMult *= 2
	end
	if passes.goldWings then
		profile.stats.hasWings = true
		profile.stats.wingsCooldown = 4
	end
	if passes.bigStore then
		profile.stats.offlineHours = 24
		profile.stats.offlineEfficiency = 1
	end
	local trophies = trophyCount(data)
	profile.stats.foodMult *= 1 + Config.Trophy.Bonus * trophies

	for _, def in Config.Tree do
		if not def.unit then
			player:SetAttribute("N_" .. def.id, data.nodes[def.id] or 0)
		end
	end
	for _, def in Config.Royal do
		player:SetAttribute("R_" .. def.id, data.royal[def.id] or 0)
	end
	-- Galerías: un solo atributo, un carácter por galería en el orden de Config.Minis ("1" = tuya)
	local bits = table.create(#Config.Minis)
	for i, def in Config.Minis do
		bits[i] = if data.minis[def.id] then "1" else "0"
	end
	local code = table.concat(bits)
	if code ~= profile.minisKey then
		profile.minisKey = code
		player:SetAttribute("Minis", code)
	end
	local owned = {}
	for id in data.owned do
		table.insert(owned, id)
	end
	player:SetAttribute("Owned", table.concat(owned, ","))
	player:SetAttribute("Skin", data.skin)
	player:SetAttribute("Hat", data.hat)
	player:SetAttribute("Trail", data.trail)
	player:SetAttribute("Outfit", data.outfit)
	player:SetAttribute("JellyMult", profile.stats.jellyMult)
	player:SetAttribute("HasWings", profile.stats.hasWings)
	player:SetAttribute("WingsCooldown", profile.stats.wingsCooldown)
	player:SetAttribute("Depth", data.depth)
	player:SetAttribute("Trophies", trophies)
	player:SetAttribute("Capacity", profile.stats.capacity)
	player:SetAttribute("WalkSpeed", profile.stats.walkSpeed)
	Profiles.push(profile)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = profile.stats.walkSpeed
	end
	Profiles.applyLook(profile)

	-- El hormiguero crece con la profundidad, se llena de banderas con cada enjambre
	-- y su cartel cuenta los trofeos
	local hill = profile.hill
	if hill then
		local key = data.depth .. "|" .. data.rebirths .. "|" .. trophies .. "|" .. tostring(passes.vip)
		if key ~= profile.hillKey then
			profile.hillKey = key
			World.dressAnthill(hill, data.depth, data.rebirths, (if passes.vip then "★ " else "") .. player.DisplayName, trophies)
		end
	end

	for _, hook in Profiles.onRefresh do
		-- Un módulo que falla no corta la compra ni la entrada que pidieron este refresh
		local ok, err = pcall(hook, profile)
		if not ok then
			warn("[CRUNCH!] Profiles.onRefresh:", err)
		end
	end
end

-- Lo que rinde la colonia de normal (comida por segundo, con el multiplicador de comida pero sin
-- frenesí ni potenciadores temporales). Las partidas de antes no tienen baseRate: vale su rate.
function Profiles.baseRate(profile): number
	local data = profile.data
	local base = data.baseRate
	return if type(base) == "number" and base == base and base >= 0 then base else math.max(data.rate or 0, 0)
end

-- Suma comida aplicando los multiplicadores. Devuelve lo acreditado.
function Profiles.addFood(profile, raw: number): number
	local credited = raw * profile.stats.foodMult
	if Workspace:GetServerTimeNow() < profile.buffUntil then
		credited *= Config.Fungus.Mult
	end
	local data = profile.data
	data.food += credited
	data.runFood += credited
	data.totalFood += credited
	return credited
end

-- Cada mordisco a la Tarta cuenta: terminarla duplica la jalea del enjambre.
function Profiles.trackFood(profile, def, taken: number)
	if def.id ~= "Tarta" or taken <= 0 then
		return
	end
	local data = profile.data
	data.tartaDamage += taken
	if not data.tartaDone and data.tartaDamage >= def.hp then
		data.tartaDone = true
		Profiles.say(profile, "¡Me comí la tarta entera! Si enjambro ahora, la jalea vale el doble", 8)
	end
end

-- Terminar por primera vez un tipo de comida da un trofeo: se cuenta en el cartel del hormiguero y sube todo lo que ganas.
function Profiles.awardTrophy(profile, def)
	local data = profile.data
	if data.trophies[def.id] then
		return
	end
	data.trophies[def.id] = true
	Profiles.refresh(profile)
	Profiles.say(profile, "¡Trofeo nuevo: " .. def.name .. "! Toda la comida vale un 3 % más", 6)
end

-- Hace hablar a la hormiga del jugador con un bocadillo temporal.
function Profiles.say(profile, text: string, seconds: number?)
	if Profiles.fx then
		Profiles.fx:FireClient(profile.player, "Say", text, seconds or 4)
	end
end

return Profiles
