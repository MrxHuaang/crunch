-- Guardado en DataStore. Carga con reintentos, guarda al salir, cada minuto y al cerrar el servidor.
-- En Studio sin acceso a la API se juega sin guardar en vez de fallar.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Data = {}

local store = nil
local storeFailed = false

local function getStore()
	if store or storeFailed then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Save.Store)
	end)
	if ok then
		store = result
	else
		storeFailed = true
		warn("[CRUNCH!] DataStore no disponible:", result)
	end
	return store
end

function Data.default()
	return {
		version = 2,
		food = 0,
		depth = 1, -- capas excavadas: abre zonas y sube el tope de las mejoras
		trophies = {}, -- [idComida] = true: tipos de comida terminados alguna vez
		owned = { rojo = true, ninguno = true, sin = true }, -- vestidor
		skin = "rojo",
		hat = "ninguno",
		trail = "sin",
		runFood = 0, -- comida ganada en esta partida (decide la Jalea)
		totalFood = 0,
		jelly = 0,
		rebirths = 0,
		nodes = {},
		minis = {}, -- [idGalería] = true: galerías excavadas en esta partida
		royal = {},
		workers = 0,
		tartaDamage = 0,
		tartaDone = false,
		rate = 0, -- comida por segundo de la colonia, para el progreso sin conexión
		lastSeen = os.time(),
	}
end

local function key(userId: number): string
	return "u_" .. userId
end

-- Devuelve (datos, puedeGuardar). Si falla la carga en un servidor real devuelve nil:
-- es mejor expulsar que jugar con datos vacíos y pisar los buenos al guardar.
function Data.load(userId: number)
	local ds = getStore()
	if not ds then
		return Data.default(), false
	end

	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return ds:GetAsync(key(userId))
		end)
		if ok then
			local data = Data.default()
			if type(result) == "table" then
				for k, v in result do
					data[k] = v
				end
			end
			return data, true
		end
		-- En Studio sin acceso a la API no tiene sentido reintentar
		if RunService:IsStudio() and tostring(result):find("Studio access") then
			break
		end
		warn(`[CRUNCH!] Carga fallida (intento {attempt}):`, result)
		task.wait(1.5 * attempt)
	end

	if RunService:IsStudio() then
		warn("[CRUNCH!] Sin guardado en esta sesión. Activa 'Enable Studio Access to API Services' en la configuración del juego.")
		return Data.default(), false
	end
	return nil, false
end

function Data.save(userId: number, data): boolean
	local ds = getStore()
	if not ds then
		return false
	end
	data.lastSeen = os.time()
	local ok, err = pcall(function()
		ds:SetAsync(key(userId), data)
	end)
	if not ok then
		warn("[CRUNCH!] Guardado fallido:", err)
	end
	return ok
end

return Data
