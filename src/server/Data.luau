-- Guardado en DataStore. Carga con reintentos, guarda al salir, cada minuto y al cerrar el servidor.
-- En Studio sin acceso a la API se juega sin guardar en vez de fallar.
-- Bloqueo de sesión: cada guardado lleva { job, at } del servidor dueño. Otro servidor no carga
-- hasta que el dueño lo suelta al salir o el bloqueo caduca (servidor caído), y un servidor que
-- perdió el bloqueo ya no escribe: así un guardado viejo nunca pisa uno nuevo.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local Data = {}

local store = nil
local storeFailed = false
local pending = 0 -- guardados en curso; BindToClose espera a que lleguen a cero
local saving = {} -- [userId] = true: los guardados de una jugadora van de uno en uno, en orden
local released = {} -- [userId] = true: ya se soltó la colonia; ningún guardado tardío la vuelve a coger

-- El autoguardado renueva el bloqueo cada Interval: si lleva 3 sin renovarse, su servidor cayó
local LOCK_STALE = Config.Save.Interval * 3
local LOCK_WAIT = 30 -- segundos que espera la carga a que otro servidor suelte el bloqueo

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
		outfit = "ninguno", -- traje del vestidor (ver Shared/Outfits)
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

local function ownLock()
	return { job = game.JobId, at = os.time() }
end

-- ¿Otro servidor vivo tiene esta colonia?
local function heldByOther(old): boolean
	local lock = type(old) == "table" and old.lock
	return type(lock) == "table" and lock.job ~= game.JobId and os.time() - (tonumber(lock.at) or 0) < LOCK_STALE
end

-- Devuelve (datos, puedeGuardar). Si falla la carga en un servidor real devuelve nil:
-- es mejor expulsar que jugar con datos vacíos y pisar los buenos al guardar.
-- Si otro servidor aún tiene la colonia (la jugadora acaba de saltar de servidor), espera a que la suelte.
function Data.load(userId: number)
	local ds = getStore()
	if not ds then
		if RunService:IsStudio() then
			return Data.default(), false
		end
		return nil, false
	end

	local deadline = os.clock() + LOCK_WAIT
	local failures = 0
	while true do
		local busy = false
		local ok, result = pcall(function()
			return ds:UpdateAsync(key(userId), function(old)
				busy = heldByOther(old)
				if busy then
					return nil -- no escribe nada: el otro servidor sigue siendo el dueño
				end
				local new = if type(old) == "table" then old else {}
				new.lock = ownLock()
				return new
			end)
		end)
		if ok and not busy then
			local data = Data.default()
			if type(result) == "table" then
				for k, v in result do
					data[k] = v
				end
			end
			data.lock = nil -- el bloqueo vive solo en el DataStore
			released[userId] = nil
			return data, true
		end
		if not ok then
			-- En Studio sin acceso a la API no tiene sentido reintentar
			local msg = tostring(result):lower()
			if RunService:IsStudio() and (msg:find("studio access") or msg:find("api access")) then
				break
			end
			failures += 1
			warn(`[CRUNCH!] Carga fallida (intento {failures}):`, result)
			if failures >= 3 then
				break
			end
		end
		if os.clock() >= deadline then
			warn("[CRUNCH!] La colonia sigue abierta en otro servidor:", userId)
			break
		end
		task.wait(if busy then 3 else 1.5 * failures)
	end

	if RunService:IsStudio() then
		warn("[CRUNCH!] Sin guardado en esta sesión. Activa 'Enable Studio Access to API Services' en la configuración del juego.")
		return Data.default(), false
	end
	return nil, false
end

-- Guarda con 3 intentos. release = true al salir: suelta el bloqueo para que otro servidor cargue ya.
-- Devuelve false si no quedó guardado, también si otro servidor se quedó con la colonia.
function Data.save(userId: number, data, release: boolean?): boolean
	local ds = getStore()
	if not ds then
		return false
	end
	pending += 1
	while saving[userId] do
		task.wait()
	end
	if released[userId] then
		-- La colonia ya se guardó y se soltó al salir: escribir ahora pisaría eso y la volvería a bloquear
		pending -= 1
		return true
	end
	saving[userId] = true

	local saved, lost = false, false
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			ds:UpdateAsync(key(userId), function(old)
				local lock = type(old) == "table" and old.lock
				lost = type(lock) == "table" and lock.job ~= game.JobId
				if lost then
					return nil -- otro servidor la cargó después: su copia es la buena
				end
				-- La foto se toma aquí, al escribir, y no al llamar: cada intento lleva lo último
				data.lastSeen = os.time()
				local out = table.clone(data)
				out.lock = if release then nil else ownLock()
				return out
			end)
		end)
		if ok then
			saved = not lost
			break
		end
		warn(`[CRUNCH!] Guardado fallido (intento {attempt}):`, err)
		if attempt < 3 then
			task.wait(attempt)
		end
	end
	if release and saved then
		released[userId] = true
	end
	saving[userId] = nil
	pending -= 1

	if lost then
		warn("[CRUNCH!] Otro servidor tiene esta colonia; este ya no la guarda:", userId)
	end
	return saved
end

-- Suelta el bloqueo sin guardar (la jugadora salió antes de terminar de cargar).
function Data.release(userId: number)
	local ds = getStore()
	if not ds then
		return
	end
	pending += 1
	pcall(function()
		ds:UpdateAsync(key(userId), function(old)
			local lock = type(old) == "table" and old.lock
			if type(lock) ~= "table" or lock.job ~= game.JobId then
				return nil
			end
			old.lock = nil
			return old
		end)
	end)
	pending -= 1
end

-- Espera a que terminen los guardados en curso (los de salida incluidos) o a que pase timeout.
function Data.waitForSaves(timeout: number)
	local deadline = os.clock() + timeout
	while pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

return Data
