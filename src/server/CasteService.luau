-- Castas (roles): la casta activa de cada jugadora, su experiencia y mutaciones por casta, los
-- enfriamientos de las tres habilidades y el despacho a la lógica de cada casta
-- (src/server/Castes/<id>.luau). Módulo opcional: si falta, el juego sigue igual.
--
-- Remoto "Caste" (cliente -> servidor):
--   ("Pick", id)                          hacerse de esa casta ("" para dejarla)
--   ("Cast", slot, aim: Vector3, aimFood: Model?)
--   ("Mutate", rank, option, casteId?)    elegir A (1) o B (2) en ese rango; sin casteId, la activa
-- Atributos de la jugadora: Caste (id o ""), CasteData (JSON { xp = {}, muts = {}, best = capa más
-- honda alcanzada }), CasteRank (rango de la casta activa), CasteCd1..3 (hora de servidor en que cada
-- habilidad vuelve a estar lista), CasteSwitchAt (hora de servidor desde la que se puede cambiar).
-- Efectos: Fx:FireAllClients("Caste", player, casteId, event, payload) con payload.t = hora de servidor.
-- El núcleo manda además "pick" (al hacerse de una casta) y "rankup" ({ rank, mastered }).
--
-- Guardado perezoso en el perfil: data.caste (id o ""), data.casteXp ([id] = experiencia),
-- data.casteMuts ([id] = { ["2"] = 1, ... }) y data.casteBest (capa más honda alcanzada: una casta
-- abierta sigue abierta después de enjambrar).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Castes = require(ReplicatedStorage.Shared.Castes)
local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local Kit = require(script.Parent.CasteKit)
local Profiles = require(script.Parent.Profiles)

local CasteService = {}

local C = Config.Castes
local TICK = 0.25
local FLAT = Vector3.new(1, 0, 1)
local SAME_BITE = 0.05 -- los trozos de un mismo mordisco llegan juntos (como en Perks)
local CD_MARGIN = 0.2 -- margen de red al comprobar enfriamientos
local MAX_RANK = Castes.MaxRank

local fxRemote: RemoteEvent
local remote: RemoteEvent
local modules: { [string]: any } = {}
local states: { [Player]: any } = {}

---------------------------------------------------------------------------------------------------
-- Ayudas

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function finiteVector(v: any): boolean
	return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function stateOf(profile)
	local player = profile.player
	local st = states[player]
	if not st or st.profile ~= profile then
		st = {
			profile = profile,
			session = nil,
			cd = { 0, 0, 0 },
			switchAt = 0,
			tokens = C.XpBurst,
			tokensAt = os.clock(),
			dirty = false,
			publishedAt = 0,
			lastCast = 0,
			lastAsk = 0,
			ate = nil, -- { amount, t }: primer trozo del mordisco en curso
			resolved = {}, -- [id] = Castes.resolve(...)
		}
		states[player] = st
	end
	return st
end

-- Campos perezosos del guardado
local function ensure(profile)
	local data = profile.data
	if type(data.casteXp) ~= "table" then
		data.casteXp = {}
	end
	if type(data.casteMuts) ~= "table" then
		data.casteMuts = {}
	end
	if type(data.caste) ~= "string" then
		data.caste = ""
	end
	local best = tonumber(data.casteBest) or 0
	if (data.depth or 1) > best then
		data.casteBest = data.depth or 1
	elseif data.casteBest ~= best then
		data.casteBest = best
	end
end

local function activeId(profile): string?
	local id = profile.data.caste
	return if type(id) == "string" and Castes.get(id) then id else nil
end

local function xpOf(profile, id: string): number
	return tonumber(profile.data.casteXp[id]) or 0
end

local function rankOf(profile, id: string): number
	return Castes.rankOf(xpOf(profile, id))
end

local function mutsOf(profile, id: string)
	local muts = profile.data.casteMuts[id]
	return if type(muts) == "table" then muts else {}
end

local function resolvedFor(profile, st, id: string)
	local hit = st.resolved[id]
	if not hit then
		hit = Castes.resolve(Castes.get(id), mutsOf(profile, id), rankOf(profile, id))
		st.resolved[id] = hit
	end
	return hit
end

local function masteredCount(profile): number
	local count = 0
	local top = Castes.xpFor(MAX_RANK)
	for _, xp in profile.data.casteXp do
		if (tonumber(xp) or 0) >= top then
			count += 1
		end
	end
	return count
end

local function unlocked(profile, def): boolean
	local best = math.max(tonumber(profile.data.casteBest) or 0, profile.data.depth or 1)
	return best >= math.max(C.UnlockDepth, def.depth or 1)
end

local function hillCenter(profile): Vector3?
	local hill = profile.hill
	return if hill then hill:GetPivot().Position else nil
end

-- Punto del suelo bajo `pos` (ignora personajes, comida y lo que no choca)
local function groundAt(pos: Vector3): Vector3
	local ignore = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local foods = Workspace:FindFirstChild("Food")
	if foods then
		table.insert(ignore, foods)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else Vector3.new(pos.X, Config.GroundY or pos.Y, pos.Z)
end

local function fire(player: Player, id: string, event: string, payload: any)
	if not fxRemote then
		return
	end
	local p = if type(payload) == "table" then payload else {}
	p.t = now()
	fxRemote:FireAllClients("Caste", player, id, event, p)
end

---------------------------------------------------------------------------------------------------
-- Atributos

local function publishData(profile, st)
	local player = profile.player
	local data = profile.data
	local xp = {}
	for id, value in data.casteXp do
		xp[id] = math.floor((tonumber(value) or 0) * 10 + 0.5) / 10
	end
	local ok, json = pcall(HttpService.JSONEncode, HttpService, { xp = xp, muts = data.casteMuts, best = data.casteBest })
	if ok then
		player:SetAttribute("CasteData", json)
	end
	local id = activeId(profile)
	player:SetAttribute("Caste", id or "")
	player:SetAttribute("CasteRank", if id then rankOf(profile, id) else 0)
	st.dirty = false
	st.publishedAt = os.clock()
end

local function publishCds(profile, st)
	local player = profile.player
	for slot = 1, 3 do
		player:SetAttribute("CasteCd" .. slot, st.cd[slot])
	end
	player:SetAttribute("CasteSwitchAt", st.switchAt)
end

---------------------------------------------------------------------------------------------------
-- ctx y sesiones

local function makeCtx(profile, st, id: string)
	local player = profile.player
	local stats = profile.stats
	local root = getRoot(player)
	local hill = hillCenter(profile)
	local origin = if root then root.Position else (hill or Vector3.zero)
	local look = if root then root.CFrame.LookVector * FLAT else Vector3.new(0, 0, -1)
	local dir = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local resolved = resolvedFor(profile, st, id)
	local session = st.session
	return {
		profile = profile,
		player = player,
		stats = stats,
		root = root,
		origin = origin,
		aim = origin,
		aimFood = nil,
		dir = dir,
		hill = hill,
		rank = rankOf(profile, id),
		bite = stats.biteDamage,
		param = resolved.param,
		has = resolved.has,
		fx = function(event: string, payload: any)
			if type(event) == "string" then
				fire(player, id, event, payload)
			end
		end,
		state = if session and session.casteId == id then session.state else {},
		casteId = id,
		def = Castes.get(id),
		_s = if session and session.casteId == id then session else nil,
	}
end

local function passiveOf(id: string?)
	local module = id and modules[id]
	local passive = module and module.passive
	return if type(passive) == "table" then passive else nil
end

local function startSession(profile, st)
	local id = activeId(profile)
	if not id or (st.session and st.session.casteId == id) then
		return
	end
	st.session = { alive = true, casteId = id, tasks = {}, state = {} }
	local passive = passiveOf(id)
	if passive and passive.equip then
		local ctx = makeCtx(profile, st, id)
		Kit._safe(ctx, "equip", passive.equip, ctx)
	end
end

local function endSession(profile, st)
	local session = st.session
	if not session then
		return
	end
	local passive = passiveOf(session.casteId)
	if passive and passive.unequip and Castes.get(session.casteId) then
		local ctx = makeCtx(profile, st, session.casteId)
		Kit._safe(ctx, "unequip", passive.unequip, ctx)
	end
	session.alive = false
	for handle in session.tasks do
		handle.stopped = true
	end
	table.clear(session.tasks)
	table.clear(session.state)
	st.session = nil
end

-- Pasiva de la casta activa: crea la sesión si hace falta y llama al gancho con pcall
local function dispatch(profile, hook: string, ...: any)
	local st = stateOf(profile)
	local id = activeId(profile)
	local passive = passiveOf(id)
	local fn = passive and passive[hook]
	if not id or type(fn) ~= "function" then
		return
	end
	if not st.session then
		startSession(profile, st)
	end
	local ctx = makeCtx(profile, st, id)
	Kit._safe(ctx, hook, fn, ctx, ...)
end

---------------------------------------------------------------------------------------------------
-- Experiencia y rangos

-- En los rangos de mutación, la opción A queda puesta hasta que elijas otra
local function fillDefaults(profile, id: string)
	local def = Castes.get(id)
	if not def then
		return
	end
	local rank = rankOf(profile, id)
	local muts = profile.data.casteMuts[id]
	for _, level in def.mutations do
		if (level.rank or 99) <= rank then
			if type(muts) ~= "table" then
				muts = {}
				profile.data.casteMuts[id] = muts
			end
			if muts[tostring(level.rank)] == nil then
				muts[tostring(level.rank)] = 1
			end
		end
	end
end

local function onRankUp(profile, st, id: string, rank: number)
	local def = Castes.get(id)
	fillDefaults(profile, id)
	st.resolved = {}
	publishData(profile, st)
	fire(profile.player, id, "rankup", { rank = rank, mastered = rank >= MAX_RANK })
	if not def then
		return
	end
	if rank >= MAX_RANK then
		Profiles.say(profile, "¡Maestría de " .. def.name .. "! Toda la comida vale un " .. math.floor(C.MasteryFood * 100 + 0.5) .. " % más para siempre", 8)
		Profiles.refresh(profile)
		return
	end
	for _, ability in def.abilities do
		if (ability.rank or 1) == rank then
			Profiles.say(profile, "¡Rango " .. rank .. "! Nueva habilidad: " .. tostring(ability.name) .. " (" .. tostring(ability.slot) .. ")", 6)
			return
		end
	end
	for _, level in def.mutations do
		if level.rank == rank then
			Profiles.say(profile, "¡Rango " .. rank .. "! Tienes una mutación nueva: cámbiala en Castas", 6)
			return
		end
	end
	Profiles.say(profile, "¡Rango " .. rank .. " de " .. def.name .. "!", 4)
end

local function addXp(profile, id: string, amount: number)
	if not finite(amount) or amount <= 0 or activeId(profile) ~= id then
		return
	end
	local st = stateOf(profile)
	local clock = os.clock()
	st.tokens = math.min(C.XpBurst, st.tokens + (clock - st.tokensAt) * C.XpRate)
	st.tokensAt = clock
	local gain = math.min(amount, st.tokens)
	if gain <= 0 then
		return
	end
	st.tokens -= gain
	local before = xpOf(profile, id)
	local after = before + gain
	profile.data.casteXp[id] = after
	st.dirty = true
	local r0, r1 = Castes.rankOf(before), Castes.rankOf(after)
	if r1 > r0 then
		onRankUp(profile, st, id, r1)
	end
end

Kit._xp = function(ctx, amount: number)
	if ctx and ctx.profile and ctx.casteId then
		addXp(ctx.profile, ctx.casteId, amount)
	end
end

Kit._cooldown = function(ctx, slot: number, readyIn: number)
	local profile = ctx and ctx.profile
	if not profile or slot < 1 or slot > 3 or activeId(profile) ~= ctx.casteId then
		return
	end
	local st = stateOf(profile)
	local readyAt = now() + readyIn
	if st.pendingCaps then
		st.pendingCaps[slot] = math.min(st.pendingCaps[slot] or math.huge, readyAt)
		return
	end
	if readyAt < st.cd[slot] then
		st.cd[slot] = readyAt
		publishCds(profile, st)
	end
end

---------------------------------------------------------------------------------------------------
-- Estadísticas: Maestría y passive.stats de la casta activa (tras Stats.derive, en cada refresh)

local function applyStats(profile)
	ensure(profile)
	local stats = profile.stats
	if not stats then
		return
	end
	local mastered = masteredCount(profile)
	if mastered > 0 then
		stats.foodMult *= 1 + C.MasteryFood * mastered
	end
	local id = activeId(profile)
	local passive = passiveOf(id)
	if id and passive and type(passive.stats) == "function" then
		local capacity, speed = stats.capacity, stats.walkSpeed
		local ctx = makeCtx(profile, stateOf(profile), id)
		Kit._safe(ctx, "stats", passive.stats, stats, ctx)
		local player = profile.player
		if stats.capacity ~= capacity and finite(stats.capacity) then
			player:SetAttribute("Capacity", stats.capacity)
		end
		if stats.walkSpeed ~= speed and finite(stats.walkSpeed) then
			player:SetAttribute("WalkSpeed", stats.walkSpeed)
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = stats.walkSpeed
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Peticiones

local function abilityCooldown(profile, st, id: string, ability): number
	local value = resolvedFor(profile, st, id).param(ability.id, "cooldown")
	return math.max(if finite(value) then value else (tonumber(ability.cooldown) or 5), 0.5)
end

local function pick(profile, id: string?, force: boolean?)
	local st = stateOf(profile)
	ensure(profile)
	local current = activeId(profile)
	local wanted = if type(id) == "string" and id ~= "" then id else nil
	if wanted == current then
		return
	end
	local t = now()
	local def = if wanted then Castes.get(wanted) else nil
	if wanted and not def then
		return
	end
	if def and not force and not unlocked(profile, def) then
		Profiles.say(profile, def.name .. " se abre en la capa " .. math.max(C.UnlockDepth, def.depth), 3)
		return
	end
	if current and not force and t < st.switchAt then
		Profiles.say(profile, "Aún no puedo cambiar de casta: " .. math.ceil(st.switchAt - t) .. " s", 3)
		return
	end

	endSession(profile, st)
	profile.data.caste = wanted or ""
	st.switchAt = t + C.SwitchLock
	st.resolved = {}
	-- Cambiar deja las tres habilidades en enfriamiento (hacerse de la primera casta, no)
	for slot = 1, 3 do
		local ability = def and Castes.ability(def, slot)
		st.cd[slot] = if current and ability and wanted then t + abilityCooldown(profile, st, wanted :: string, ability) else 0
	end
	if wanted then
		fillDefaults(profile, wanted)
	end
	publishData(profile, st)
	publishCds(profile, st)
	Profiles.refresh(profile)
	if wanted then
		startSession(profile, st)
		fire(profile.player, wanted, "pick", { first = current == nil })
	end
end

local function cast(profile, slotAny: any, aimAny: any, foodAny: any)
	local player = profile.player
	local st = stateOf(profile)
	local id = activeId(profile)
	local slot = tonumber(slotAny)
	if not id or not slot or slot ~= math.floor(slot) or slot < 1 or slot > 3 or not finiteVector(aimAny) then
		return
	end
	local def = Castes.get(id)
	local ability = Castes.ability(def, slot)
	if not ability then
		return
	end
	if rankOf(profile, id) < (ability.rank or 1) then
		return
	end
	local t = now()
	if t < st.cd[slot] - CD_MARGIN or os.clock() - st.lastCast < 0.12 then
		return
	end
	local root = getRoot(player)
	local module = modules[id]
	local fn = module and type(module.abilities) == "table" and module.abilities[ability.id]
	if not root or type(fn) ~= "function" then
		return
	end
	st.lastCast = os.clock()
	if not st.session then
		startSession(profile, st)
	end

	local stats = profile.stats
	local resolved = resolvedFor(profile, st, id)
	local rangeValue = resolved.param(ability.id, "range")
	local range = if finite(rangeValue) then math.max(rangeValue, 0) else (tonumber(ability.range) or 0)
	local origin = root.Position
	local kind = ability.aim or "ground"

	-- Punto apuntado: recortado al alcance y a ras de suelo
	local aim: Vector3 = aimAny
	local offset = (aim - origin) * FLAT
	if kind == "self" then
		offset = Vector3.zero
	elseif range > 0 and offset.Magnitude > range then
		offset = offset.Unit * range
	end
	aim = groundAt(Vector3.new(origin.X + offset.X, origin.Y, origin.Z + offset.Z))

	-- Comida apuntada: existe, su zona está abierta, se puede morder y está a tiro
	local reach = math.max(range, stats.biteRange or 6) + 8
	local food: Model? = nil
	if FoodService.isFood(foodAny) and Kit.edible(stats, foodAny) then
		local gap = ((foodAny:GetPivot().Position - origin) * FLAT).Magnitude - ((foodAny:GetAttribute("Radius") :: number?) or 1)
		if gap <= reach then
			food = foodAny
		end
	end
	if kind == "food" and not food then
		local near = Kit.nearest(stats, aim, 8)
		if near and ((near:GetPivot().Position - origin) * FLAT).Magnitude - ((near:GetAttribute("Radius") :: number?) or 1) <= reach then
			food = near
		end
	end
	if kind == "food" and food then
		local p = food:GetPivot().Position
		aim = groundAt(Vector3.new(p.X, origin.Y, p.Z))
	end
	local flatDir = (aim - origin) * FLAT
	if flatDir.Magnitude < 0.5 then
		flatDir = root.CFrame.LookVector * FLAT
	end
	local dir = if flatDir.Magnitude > 1e-3 then flatDir.Unit else Vector3.new(0, 0, -1)

	local ctx = makeCtx(profile, st, id)
	ctx.aim = aim
	ctx.aimFood = food
	ctx.dir = dir

	-- Kit.cooldown llamado dentro de la habilidad se guarda y se aplica tras fijar su enfriamiento
	st.pendingCaps = {}
	local ok, result = pcall(fn, ctx)
	local caps = st.pendingCaps
	st.pendingCaps = nil
	if not ok then
		warn("[CRUNCH!] Casta " .. id .. " (" .. tostring(ability.id) .. "):", result)
		st.cd[slot] = t + 1
		publishCds(profile, st)
		return
	end
	if result ~= false then
		st.cd[slot] = t + abilityCooldown(profile, st, id, ability)
	end
	for capSlot, readyAt in caps do
		st.cd[capSlot] = math.min(st.cd[capSlot], readyAt)
	end
	if result ~= false or next(caps) ~= nil then
		publishCds(profile, st)
	end
end

local function mutate(profile, rankAny: any, optionAny: any, casteAny: any)
	local st = stateOf(profile)
	local id = if type(casteAny) == "string" and Castes.get(casteAny) then casteAny else activeId(profile)
	local rank, option = tonumber(rankAny), tonumber(optionAny)
	if not id or not rank or not option then
		return
	end
	local def = Castes.get(id)
	local level = nil
	for _, candidate in def.mutations do
		if candidate.rank == rank then
			level = candidate
			break
		end
	end
	if not level or type(level.options) ~= "table" or not level.options[option] then
		return
	end
	if rankOf(profile, id) < rank then
		Profiles.say(profile, "Esa mutación pide rango " .. rank, 3)
		return
	end
	local muts = profile.data.casteMuts[id]
	if type(muts) ~= "table" then
		muts = {}
		profile.data.casteMuts[id] = muts
	end
	if muts[tostring(rank)] == option then
		return
	end
	muts[tostring(rank)] = option
	st.resolved = {}
	publishData(profile, st)
	if id == activeId(profile) then
		Profiles.refresh(profile) -- la pasiva puede tocar estadísticas según sus parámetros
	end
end

local function onRequest(player: Player, action: any, a: any, b: any, c: any)
	local profile = Profiles.get(player)
	if not profile or not profile.stats then
		return
	end
	local st = stateOf(profile)
	ensure(profile)
	if action == "Cast" then
		cast(profile, a, b, c)
		return
	end
	-- Elegir y mutar: como mucho unas pocas por segundo
	if os.clock() - st.lastAsk < 0.15 then
		return
	end
	st.lastAsk = os.clock()
	if action == "Pick" then
		pick(profile, if type(a) == "string" then a else nil, false)
	elseif action == "Mutate" then
		mutate(profile, a, b, c)
	end
end

---------------------------------------------------------------------------------------------------
-- Sucesos

local function onAte(profile, _def, amount: number, byWorkers: boolean?)
	if byWorkers or type(amount) ~= "number" or amount <= 0 then
		return
	end
	local st = stateOf(profile)
	local clock = os.clock()
	if not st.ate or clock - st.ate.t > SAME_BITE then
		st.ate = { amount = amount, t = clock }
	end
end

local function onBite(profile, food: any, _chained: any, position: any, damage: any, finished: any)
	local id = activeId(profile)
	if not id then
		return
	end
	local st = stateOf(profile)
	local stats = profile.stats
	local bite = math.max(stats.biteDamage or 1, 1)
	-- Experiencia: trozos de este mordisco en mordiscos equivalentes
	local taken = if st.ate and os.clock() - st.ate.t <= SAME_BITE then st.ate.amount else (tonumber(damage) or bite)
	st.ate = nil
	addXp(profile, id, math.min(taken / bite, C.XpBiteMax) * C.XpHand)

	if typeof(position) ~= "Vector3" then
		local ok, pivot = pcall(function()
			return food:GetPivot().Position
		end)
		position = if ok then pivot + Vector3.new(0, 1, 0) else Vector3.zero
	end
	dispatch(profile, "bite", food, position, tonumber(damage) or bite, finished == true)
end

---------------------------------------------------------------------------------------------------

local function loadModules()
	local folder = script.Parent:FindFirstChild("Castes")
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, lib = pcall(require, child)
			if ok and type(lib) == "table" then
				modules[child.Name] = lib
			else
				warn("[CRUNCH!] Lógica de la casta", child.Name, "no se pudo cargar:", lib)
			end
		end
	end
end

local function tickProfile(player: Player, profile)
	local st = stateOf(profile)
	ensure(profile)
	if (profile.data.depth or 1) > (tonumber(profile.data.casteBest) or 0) then
		profile.data.casteBest = profile.data.depth
		st.dirty = true
	end
	local id = activeId(profile)
	if id then
		if not st.session then
			startSession(profile, st)
		end
		local passive = passiveOf(id)
		if passive and type(passive.tick) == "function" and getRoot(player) then
			local ctx = makeCtx(profile, st, id)
			Kit._safe(ctx, "tick", passive.tick, ctx, TICK)
		end
	elseif st.session then
		endSession(profile, st)
	end
	if st.dirty and os.clock() - st.publishedAt >= 1 then
		publishData(profile, st)
	end
end

local function debugCommands()
	local debug = ServerScriptService:WaitForChild("CrunchDebug", 15)
	if not debug or not debug:IsA("BindableEvent") then
		return
	end
	debug.Event:Connect(function(command: any, a: any)
		if command ~= "caste" and command ~= "casterank" and command ~= "castecd" then
			return
		end
		for _, profile in Profiles.all() do
			local st = stateOf(profile)
			ensure(profile)
			if command == "caste" then
				pick(profile, tostring(a or ""), true)
			elseif command == "casterank" then
				local id = activeId(profile)
				if id then
					profile.data.casteXp[id] = Castes.xpFor(tonumber(a) or 1)
					fillDefaults(profile, id)
					st.resolved = {}
					publishData(profile, st)
					Profiles.refresh(profile)
				end
			elseif command == "castecd" then
				st.cd = { 0, 0, 0 }
				st.switchAt = 0
				publishCds(profile, st)
			end
		end
	end)
end

-- Por si otro módulo quiere saberlo
function CasteService.active(player: Player): string?
	local profile = Profiles.get(player)
	return if profile then activeId(profile) else nil
end

function CasteService.rank(player: Player, id: string): number
	local profile = Profiles.get(player)
	return if profile and type(profile.data.casteXp) == "table" then rankOf(profile, id) else 1
end

function CasteService.start(remotes: Folder)
	fxRemote = remotes:WaitForChild("Fx") :: RemoteEvent
	remote = Instance.new("RemoteEvent")
	remote.Name = "Caste"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(function(player, action, a, b, c)
		local ok, err = pcall(onRequest, player, action, a, b, c)
		if not ok then
			warn("[CRUNCH!] Castas:", err)
		end
	end)

	loadModules()

	table.insert(Profiles.onRefresh, function(profile)
		local ok, err = pcall(applyStats, profile)
		if not ok then
			warn("[CRUNCH!] Castas (estadísticas):", err)
		end
	end)

	Events.on("Ate", onAte)
	Events.on("Bite", onBite)
	Events.on("FinalBite", function(profile, _food, position: any, damage: any)
		dispatch(profile, "finalBite", position, damage)
	end)
	Events.on("Deposit", function(profile, credited: any, fullLoad: any)
		dispatch(profile, "deposit", credited, fullLoad)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local st = states[player]
		if st then
			pcall(endSession, st.profile, st)
			states[player] = nil
		end
	end)

	-- Las que entraron antes de arrancar este módulo
	for _, profile in Profiles.all() do
		local st = stateOf(profile)
		ensure(profile)
		publishData(profile, st)
		publishCds(profile, st)
		Profiles.refresh(profile)
	end
	Players.PlayerAdded:Connect(function(player)
		-- Atributos de partida en cuanto exista su perfil
		task.spawn(function()
			for _ = 1, 120 do
				local profile = Profiles.get(player)
				if profile then
					local st = stateOf(profile)
					ensure(profile)
					publishData(profile, st)
					publishCds(profile, st)
					return
				end
				if not player.Parent then
					return
				end
				task.wait(0.5)
			end
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for player, profile in Profiles.all() do
				if profile.stats and player.Parent then
					local ok, err = pcall(tickProfile, player, profile)
					if not ok then
						warn("[CRUNCH!] Castas:", err)
					end
				end
			end
		end
	end)

	if RunService:IsStudio() then
		task.spawn(debugCommands)
	end
end

return CasteService
