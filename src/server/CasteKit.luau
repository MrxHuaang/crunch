-- Primitivas de servidor para las castas (src/server/Castes/<id>.luau). Buscar comida a tiro, golpear
-- con una habilidad (el botín va directo al hormiguero), mordisquear con la pasiva (a la carga),
-- zonas y temporizadores que se cancelan solos al salir o cambiar de casta, marcas en la comida.
-- Todo lo que llama a código de una casta va envuelto en pcall: un fallo avisa y no rompe nada.
--
-- Firmas (contrato de las castas):
--   Kit.edible(stats, food): boolean
--   Kit.inRadius(stats, center, radius): {Model}            comibles, la más cercana primero
--   Kit.inCone(stats, origin, dir, range, halfAngleDeg): {Model}
--   Kit.onLine(stats, a, b, width): {Model}                 en orden de a hacia b
--   Kit.nearest(stats, from, range, skip?): Model?
--   Kit.posOf(food): Vector3                                centro + 1 de alto
--   Kit.strike(ctx, food, bites, worth?): (trozos, terminada)    golpe de HABILIDAD
--   Kit.strikeMany(ctx, foods, bites, worth?): ({Vector3}, {number})
--   Kit.nibble(ctx, food, bites, worth?): (trozos, terminada)    golpe de PASIVA (a la carga)
--   Kit.flush(ctx)                                          tras una tanda de nibble
--   Kit.credit(ctx, food)                                   comida ya con multiplicadores
--   Kit.zone(ctx, { center, radius, duration, every, follow?, tick }): { stop }
--   Kit.after(ctx, seconds, fn)
--   Kit.every(ctx, interval, duration, fn(n)): { stop }
--   Kit.mark(food, key, seconds, value?) / Kit.marked(food, key)
--   Kit.xp(ctx, bitesWorth)
-- Zonas y `every`: el primer pulso llega a los `every` / `interval` segundos (no al instante) y hay
-- floor(duration / every) pulsos. Sin duration (o 0), siguen hasta stop() o hasta cambiar de casta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local PlayerService = require(script.Parent.PlayerService)
local Profiles = require(script.Parent.Profiles)

local Kit = {}

local C = Config.Castes
local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.new(0, 1, 0)

-- Lo engancha CasteService al arrancar: experiencia de la casta de esa sesión
Kit._xp = nil :: ((ctx: any, amount: number) -> ())?

---------------------------------------------------------------------------------------------------
-- Ayudas

local function warnCaste(ctx: any, where: string, err: any)
	local id = if type(ctx) == "table" and ctx.casteId then ctx.casteId else "?"
	warn("[CRUNCH!] Casta " .. tostring(id) .. " (" .. where .. "):", err)
end

-- Llama a código de una casta sin que un fallo rompa nada
local function safe(ctx: any, where: string, fn: any, ...: any)
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warnCaste(ctx, where, err)
	end
end
Kit._safe = safe

-- La sesión de la casta sigue viva (no cambió de casta ni se fue)
local function live(ctx: any): boolean
	if type(ctx) ~= "table" or not ctx.profile then
		return false
	end
	if Profiles.get(ctx.profile.player) ~= ctx.profile then
		return false
	end
	local session = ctx._s
	return session == nil or session.alive == true
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function radiusOf(food: Model): number
	local r = food:GetAttribute("Radius")
	return if type(r) == "number" then r else 1
end

local function edgeGap(from: Vector3, food: Model): number
	return ((food:GetPivot().Position - from) * FLAT).Magnitude - radiusOf(food)
end

-- Un Profiles.push y una carga refrescada por fotograma, aunque haya cien golpes
local pushPending: { [any]: boolean } = {}
local carryPending: { [any]: boolean } = {}

local function schedulePush(profile)
	if pushPending[profile] then
		return
	end
	pushPending[profile] = true
	task.defer(function()
		pushPending[profile] = nil
		if Profiles.get(profile.player) == profile then
			Profiles.push(profile)
		end
	end)
end

local function scheduleCarry(profile)
	if carryPending[profile] then
		return
	end
	carryPending[profile] = true
	task.defer(function()
		if not carryPending[profile] then
			return -- ya lo hizo Kit.flush
		end
		carryPending[profile] = nil
		if Profiles.get(profile.player) == profile then
			PlayerService.refreshCarry(profile)
		end
	end)
end

local function giveXp(ctx: any, amount: number)
	if Kit._xp and finite(amount) and amount > 0 then
		Kit._xp(ctx, amount)
	end
end

---------------------------------------------------------------------------------------------------
-- Buscar comida

function Kit.edible(stats: any, food: any): boolean
	if not stats or not FoodService.isFood(food) then
		return false
	end
	local def = FoodService.defOf(food)
	return def ~= nil and def.zone <= (stats.depth or 1) and (not def.hard or stats.canBiteHard == true)
end

function Kit.posOf(food: Model): Vector3
	return food:GetPivot().Position + UP
end

-- Comibles a menos de `radius` (de borde) de `center`, la más cercana primero
function Kit.inRadius(stats: any, center: Vector3, radius: number): { Model }
	local found = {}
	if typeof(center) ~= "Vector3" or not finite(radius) then
		return {}
	end
	for food in FoodService.list() do
		if Kit.edible(stats, food) then
			local gap = edgeGap(center, food)
			if gap <= radius then
				table.insert(found, { food = food, gap = gap })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.gap < b.gap
	end)
	local out = table.create(#found)
	for i, item in found do
		out[i] = item.food
	end
	return out
end

function Kit.inCone(stats: any, origin: Vector3, dir: Vector3, range: number, halfAngleDeg: number): { Model }
	local found = {}
	local flatDir = if typeof(dir) == "Vector3" then dir * FLAT else Vector3.zero
	if flatDir.Magnitude < 1e-3 or typeof(origin) ~= "Vector3" or not finite(range) then
		return {}
	end
	flatDir = flatDir.Unit
	local half = math.rad(math.clamp(tonumber(halfAngleDeg) or 30, 0, 180))
	for food in FoodService.list() do
		if Kit.edible(stats, food) then
			local v = (food:GetPivot().Position - origin) * FLAT
			local distance = v.Magnitude
			local r = radiusOf(food)
			if distance - r <= range then
				local inside = distance <= r
				local angle = if inside then 0 else math.acos(math.clamp(v.Unit:Dot(flatDir), -1, 1))
				local slack = if inside then math.pi else math.atan(r / math.max(distance, 0.1))
				if angle <= half + slack then
					table.insert(found, { food = food, gap = distance - r })
				end
			end
		end
	end
	table.sort(found, function(a, b)
		return a.gap < b.gap
	end)
	local out = table.create(#found)
	for i, item in found do
		out[i] = item.food
	end
	return out
end

-- Comibles que toca una franja de `width` de ancho entre a y b, en orden de a hacia b
function Kit.onLine(stats: any, a: Vector3, b: Vector3, width: number): { Model }
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return {}
	end
	local fa, fb = a * FLAT, b * FLAT
	local seg = fb - fa
	local lengthSq = seg:Dot(seg)
	local half = math.max(tonumber(width) or 4, 0) / 2
	local found = {}
	for food in FoodService.list() do
		if Kit.edible(stats, food) then
			local p = food:GetPivot().Position * FLAT
			local t = if lengthSq > 1e-6 then math.clamp((p - fa):Dot(seg) / lengthSq, 0, 1) else 0
			local closest = fa + seg * t
			if (p - closest).Magnitude - radiusOf(food) <= half then
				table.insert(found, { food = food, t = t })
			end
		end
	end
	table.sort(found, function(x, y)
		return x.t < y.t
	end)
	local out = table.create(#found)
	for i, item in found do
		out[i] = item.food
	end
	return out
end

function Kit.nearest(stats: any, from: Vector3, range: number, skip: { [Model]: boolean }?): Model?
	if typeof(from) ~= "Vector3" then
		return nil
	end
	local best, bestGap = nil, tonumber(range) or 0
	for food in FoodService.list() do
		if not (skip and skip[food]) and Kit.edible(stats, food) then
			local gap = edgeGap(from, food)
			if gap <= bestGap then
				best, bestGap = food, gap
			end
		end
	end
	return best
end

---------------------------------------------------------------------------------------------------
-- Golpes

-- Golpe de HABILIDAD: arranca bites mordiscos (con la comida dura y su valor por zona) y acredita
-- directo PowerShare de lo que vale, sin pasar por la carga. Sucesos y trofeos como un mordisco.
function Kit.strike(ctx: any, food: any, bites: number, worth: number?): (number, boolean)
	if not live(ctx) or not finite(bites) or bites <= 0 then
		return 0, false
	end
	local profile = ctx.profile
	local stats = profile.stats
	if not Kit.edible(stats, food) then
		return 0, false
	end
	local def = FoodService.defOf(food)
	local hard = if def.hard then (stats.hardMult or 1) else 1
	local bite = math.max(stats.biteDamage or 1, 1)
	local amount = math.ceil(bites * bite * hard)
	local piece = FoodService.pieceValue(food, def, stats) -- antes de dañarla: puede desaparecer
	local taken, _, finished = FoodService.damage(food, amount)
	if taken <= 0 then
		return 0, false
	end
	local mult = if finite(worth) then worth :: number else 1
	Profiles.addFood(profile, taken * piece * mult * C.PowerShare)
	Profiles.trackFood(profile, def, taken)
	Events.fire("Ate", profile, def, taken, false)
	if finished then
		Profiles.awardTrophy(profile, def)
		Events.fire("Finished", profile, def)
	end
	giveXp(ctx, taken / (bite * hard) * C.XpPower)
	schedulePush(profile)
	return taken, finished == true
end

function Kit.strikeMany(ctx: any, foods: { Model }, bites: number, worth: number?): ({ Vector3 }, { number })
	local points, amounts = {}, {}
	if type(foods) ~= "table" then
		return points, amounts
	end
	for _, food in foods do
		if FoodService.isFood(food) then
			local at = Kit.posOf(food)
			local taken = Kit.strike(ctx, food, bites, worth)
			if taken > 0 then
				table.insert(points, at)
				table.insert(amounts, taken)
			end
		end
	end
	return points, amounts
end

-- Golpe de PASIVA: como un mordisco normal, a la carga (PlayerService.take). 0 si no cabe.
function Kit.nibble(ctx: any, food: any, bites: number, worth: number?): (number, boolean)
	if not live(ctx) or not finite(bites) or bites <= 0 then
		return 0, false
	end
	local profile = ctx.profile
	local stats = profile.stats
	if not Kit.edible(stats, food) or profile.carry >= stats.capacity then
		return 0, false
	end
	local def = FoodService.defOf(food)
	local hard = if def.hard then (stats.hardMult or 1) else 1
	local bite = math.max(stats.biteDamage or 1, 1)
	local taken, finished = PlayerService.take(profile, food, math.ceil(bites * bite * hard), if finite(worth) then worth else nil)
	if taken > 0 then
		giveXp(ctx, taken / (bite * hard) * C.XpPassive)
		scheduleCarry(profile)
	end
	return taken, finished == true
end

function Kit.flush(ctx: any)
	if type(ctx) ~= "table" or not ctx.profile then
		return
	end
	local profile = ctx.profile
	carryPending[profile] = nil
	if Profiles.get(profile.player) == profile then
		PlayerService.refreshCarry(profile)
	end
end

-- Comida directa, ya con multiplicadores aplicados por quien llama
function Kit.credit(ctx: any, food: number)
	if not live(ctx) or not finite(food) or food <= 0 then
		return
	end
	local data = ctx.profile.data
	data.food += food
	data.runFood += food
	data.totalFood += food
	schedulePush(ctx.profile)
end

-- Deja el enfriamiento de la habilidad `slot` en como mucho ahora + readyIn s (nunca lo alarga) y
-- publica CasteCd<slot>. Vale también dentro de la propia habilidad: se aplica tras fijar el suyo.
Kit._cooldown = nil :: ((ctx: any, slot: number, readyIn: number) -> ())?

function Kit.cooldown(ctx: any, slot: number, readyIn: number)
	if Kit._cooldown and live(ctx) and finite(slot) and finite(readyIn) then
		Kit._cooldown(ctx, math.floor(slot), math.max(readyIn, 0))
	end
end

function Kit.xp(ctx: any, bitesWorth: number)
	if live(ctx) then
		giveXp(ctx, tonumber(bitesWorth) or 0)
	end
end

---------------------------------------------------------------------------------------------------
-- Tiempo: zonas, retardos y pulsos. Se apuntan en la sesión para cancelarse al cambiar de casta.

local function newHandle(ctx: any)
	local session = if type(ctx) == "table" then ctx._s else nil
	local handle = { stopped = false }
	function handle.stop()
		handle.stopped = true
		if session and session.tasks then
			session.tasks[handle] = nil
		end
	end
	if session and session.tasks then
		session.tasks[handle] = true
	end
	return handle
end

local function running(ctx: any, handle): boolean
	return not handle.stopped and live(ctx)
end

-- Pulsos cada `interval` s durante `duration` s (sin duration: hasta stop o cambio de casta)
local function pulse(ctx: any, interval: number, duration: number?, where: string, step: (n: number) -> ())
	local handle = newHandle(ctx)
	local every = math.max(if finite(interval) then interval else 0.5, 0.05)
	local count = if finite(duration) and (duration :: number) > 0 then math.max(1, math.floor((duration :: number) / every + 1e-6)) else math.huge
	task.spawn(function()
		local n = 0
		while n < count do
			task.wait(every)
			if not running(ctx, handle) then
				break
			end
			n += 1
			local ok, err = pcall(step, n)
			if not ok then
				warnCaste(ctx, where, err)
			end
		end
		handle.stop()
	end)
	return { stop = handle.stop }
end

function Kit.zone(ctx: any, opts: any): { stop: () -> () }
	opts = if type(opts) == "table" then opts else {}
	local center: Vector3 = if typeof(opts.center) == "Vector3" then opts.center else (ctx and ctx.origin) or Vector3.zero
	local radius = if finite(opts.radius) then opts.radius else 8
	local follow = opts.follow
	local tick = opts.tick
	return pulse(ctx, opts.every, opts.duration, "zona", function(n: number)
		if typeof(follow) == "Instance" and follow:IsA("BasePart") then
			if follow.Parent then
				center = follow.Position
			end
		end
		local foods = Kit.inRadius(ctx.profile.stats, center, radius)
		if type(tick) == "function" then
			tick(foods, center, n)
		end
	end)
end

function Kit.every(ctx: any, interval: number, duration: number?, fn: (n: number) -> ()): { stop: () -> () }
	return pulse(ctx, interval, duration, "every", function(n: number)
		if type(fn) == "function" then
			fn(n)
		end
	end)
end

function Kit.after(ctx: any, seconds: number, fn: () -> ())
	local handle = newHandle(ctx)
	task.delay(math.max(if finite(seconds) then seconds else 0, 0), function()
		if running(ctx, handle) then
			safe(ctx, "after", fn)
		end
		handle.stop()
	end)
	return { stop = handle.stop }
end

---------------------------------------------------------------------------------------------------
-- Marcas temporales en la comida (también como atributo "Caste_<key>" para que la vean los clientes)

local marks: { [Model]: { [string]: { value: any, untilAt: number, token: number } } } = setmetatable({}, { __mode = "k" }) :: any
local markToken = 0

local function attributeValue(value: any): any
	local kind = typeof(value)
	if kind == "number" or kind == "string" or kind == "boolean" or kind == "Vector3" or kind == "Color3" then
		return value
	end
	return true
end

function Kit.mark(food: any, key: string, seconds: number, value: any?)
	if typeof(food) ~= "Instance" or not food.Parent or type(key) ~= "string" then
		return
	end
	local stored = if value == nil then true else value
	local life = math.max(if finite(seconds) then seconds else 1, 0)
	markToken += 1
	local token = markToken
	local list = marks[food]
	if not list then
		list = {}
		marks[food] = list
	end
	list[key] = { value = stored, untilAt = os.clock() + life, token = token }
	local name = "Caste_" .. key
	pcall(food.SetAttribute, food, name, attributeValue(stored))
	task.delay(life, function()
		local now = marks[food]
		local entry = now and now[key]
		if entry and entry.token == token then
			now[key] = nil
			if food.Parent then
				pcall(food.SetAttribute, food, name, nil)
			end
		end
	end)
end

function Kit.marked(food: any, key: string): any?
	local list = if typeof(food) == "Instance" then marks[food] else nil
	local entry = list and list[key]
	if entry and os.clock() < entry.untilAt then
		return entry.value
	end
	return nil
end

return Kit
