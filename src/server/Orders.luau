-- Órdenes y escuadrones: cómo eligen comida las obreras que no siguen un rastro marcado a mano.
--
-- Órdenes (Config.Orders.List): lo más cercano, lo más rico, a mi lado, lo que más rinde, rematar,
-- zona elegida y a por la grande. La colonia se puede partir en hasta tres escuadrones, cada uno con
-- su orden y su parte de las obreras (pasos de Config.Orders.Step %). Los rastros marcados a mano (F)
-- siguen mandando: son del escuadrón 1, y con un solo escuadrón todo es como siempre.
--
-- Cómo habla con Colony (src/server/Colony.luau):
--   Colony.orders(profile, hillPos, marcadas) -> (destinos, obreras, huecos marcados) | nil
--     destinos: [hueco 1..3] = comida; obreras: [hueco] = cuántas van; huecos marcados: los primeros
--     huecos que son rastros a mano (cobran la feromona dulce). nil: Colony elige como siempre.
--   La Comandante (Colony.forced) gana a la orden mientras dura su asalto, y Colony.autoAllowed (el
--   jardín) filtra siempre lo que pueden coger.
-- Coste: la lista de comida de cada colonia se repasa cada Config.Orders.Recalc s (no cada tick); en
-- cada tick solo se comprueba si los destinos siguen vivos y se rellenan los huecos que se vaciaron.
--
-- Guardado (perezoso): data.orders = { squads = { { order, share, zone? }, ... } } solo cuando la
-- jugadora elige algo (sin él, Colony sigue igual que siempre); data.ordersTold = { [id] = true } avisos
-- ya dados; data.ordersViewed = { [id] = true } órdenes ya vistas en el panel (marca del botón).
-- Atributos del hormiguero: TrailSquad1..3 (escuadrón de cada hueco, solo con órdenes).
-- Remoto "Orders":
--   cliente -> servidor: "Sync" | "Watch" (bool) | "Set" (escuadrón, orden, zona?) | "Cycle" (escuadrón)
--                        | "Shares" ({ % }) | "Squads" (cuántos) | "Zone" (escuadrón, zona) | "Viewed"
--   servidor -> dueña:   "State" (instantánea) | "Ack" (escuadrón, orden) | "Unlocked" (id)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Colony = require(script.Parent.Colony)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local Profiles = require(script.Parent.Profiles)

local Orders = {}

local O = Config.Orders
local FLAT = Vector3.new(1, 0, 1)
local BITE_TIME = 3 -- como en Colony: una colonia no termina una comida en menos de esto
local SLOTS = 3 -- huecos publicados en el hormiguero (TrailPos1..3)
local LOOP = 0.5

local ORDER_BY_ID = {}
for index, def in O.List do
	ORDER_BY_ID[def.id] = def
	def.index = index
end

local remote: RemoteEvent
local states: { [any]: any } = {} -- [profile] = estado en memoria (no se guarda)

---------------------------------------------------------------------------------------------------
-- Desbloqueos

local function reached(def, data): boolean
	return (data.workers or 0) >= (def.workers or 0) and (data.depth or 1) >= (def.depth or 1)
end

-- Escuadrones que puede tener ahora (1..3)
local function squadMax(data): number
	local count = 1
	for k = 2, #O.Squads do
		if reached(O.Squads[k], data) then
			count = k
		else
			break
		end
	end
	return count
end

-- [id] = true de lo desbloqueado ahora; los escuadrones van como "squad2", "squad3"
local function unlockedSet(data): { [string]: boolean }
	local set = {}
	for _, def in O.List do
		if reached(def, data) then
			set[def.id] = true
		end
	end
	for k = 2, #O.Squads do
		if reached(O.Squads[k], data) then
			set["squad" .. k] = true
		end
	end
	return set
end

-- Zona que se usa de verdad: la elegida si sigue abierta; si no, la más honda abierta
local function zoneOf(squad, data): number
	local depth = math.clamp(data.depth or 1, 1, #Config.Zones)
	local zone = tonumber(squad.zone)
	if zone and zone >= 1 and zone <= depth then
		return math.floor(zone)
	end
	return depth
end

-- Reparto que de verdad se aplica: órdenes bloqueadas pasan a "near" y los escuadrones que ya no se
-- tienen (tras enjambrar) devuelven su parte al primero. nil si nunca eligió nada.
local function effective(profile)
	local data = profile.data
	local saved = data.orders
	if type(saved) ~= "table" or type(saved.squads) ~= "table" or #saved.squads == 0 then
		return nil
	end
	local max = squadMax(data)
	local list = {}
	local spare = 0
	for k, squad in saved.squads do
		if k > max then
			spare += squad.share or 0
			continue
		end
		local def = ORDER_BY_ID[squad.order]
		local id = if def and reached(def, data) then def.id else "near"
		table.insert(list, { order = id, share = squad.share or 0, zone = zoneOf(squad, data) })
	end
	list[1].share += spare
	return list
end

---------------------------------------------------------------------------------------------------
-- Estado en memoria y lista de candidatas

local function stateOf(profile)
	local st = states[profile]
	if not st then
		st = {
			entries = {}, -- candidatas reutilizables (ver rebuild)
			count = 0,
			byFood = {}, -- [comida] = su entrada
			builtAt = -math.huge,
			slots = { {}, {}, {} }, -- [escuadrón][j] = comida a la que van (se mantiene mientras viva)
			keys = { "", "", "" }, -- orden de cada escuadrón la última vez (si cambia, se suelta todo)
			auto = {}, -- [comida] = true: destinos de orden (no rastros) en el último tick
			loose = {}, -- [comida] = true: de recambio (su orden no encontró nada); se revisan al repasar
			squadOf = {}, -- [hueco] = escuadrón, publicado como TrailSquad
			published = false,
			lastTargets = {}, -- [hueco] = comida, para la estimación de "ahora"
			lastCrews = {},
			watching = false,
			estimateAt = -math.huge,
			sentKey = "",
			tokens = 8, -- mensajes que puede mandar (se rellena 8 por segundo)
			tokenAt = os.clock(),
		}
		states[profile] = st
	end
	return st
end

local function rootOf(profile): BasePart?
	local character = profile.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Repasa la comida del mapa: lo que esta colonia puede comer, con su viaje y su valor ya calculados.
-- Las tablas de las entradas se reutilizan entre repasos.
local function rebuild(profile, st, hillPos: Vector3)
	local stats = profile.stats
	local deep = stats.trailSlots > 0 or not O.DeepNeedsTrail
	local entries = st.entries
	local byFood = st.byFood
	table.clear(byFood)
	table.clear(st.loose) -- las de recambio vuelven a medirse con su orden
	local n = 0
	for food in FoodService.list() do
		local def = FoodService.defOf(food)
		if
			def
			and not def.boss -- la tarta: las obreras no se atreven (como en Colony)
			and def.zone <= stats.depth
			and (deep or def.zone == 1)
			and (not def.hard or stats.workersBreakHard)
			and food:GetAttribute("Event") == nil -- el pan gigante se come a mordiscos
		then
			local pos = food:GetPivot().Position
			local reach = Colony.reach(profile, def, pos, hillPos) -- la misma cuenta que hace Colony
			local maxHp = (food:GetAttribute("MaxHp") :: number?) or def.hp
			n += 1
			local entry = entries[n]
			if not entry then
				entry = {}
				entries[n] = entry
			end
			entry.food = food
			entry.def = def
			entry.pos = pos
			entry.reach = reach
			entry.trip = (2 * reach / stats.workerSpeed + Config.Worker.TurnTime) * stats.tripMult
			entry.piece = FoodService.pieceValue(food, def, stats)
			entry.maxHp = maxHp
			entry.cap = maxHp / BITE_TIME
			byFood[food] = entry
		end
	end
	for i = n + 1, st.count do
		entries[i] = nil
	end
	st.count = n
	st.builtAt = os.clock()
end

---------------------------------------------------------------------------------------------------
-- Puntuación de cada orden (más alto = mejor; nil = no vale para esta orden)

-- Comida (sin multiplicador de comida) que traen por segundo `crew` obreras a esta entrada: carga por
-- viaje de ida y vuelta, tope de la comida en BITE_TIME s y, en el jardín, la parte que le toca a la
-- colonia (la última que vio Colony). Es la misma cuenta que hace Colony en cada tick.
local function rateOf(e, crew: number, ctx): number
	local pieces = math.min(crew * ctx.carry / e.trip * ctx.mult, e.cap)
	if e.def.zone == 1 then
		pieces *= ctx.garden
	end
	return pieces * e.piece
end

local function flatGap(a: Vector3, b: Vector3): number
	return ((a - b) * FLAT).Magnitude
end

local function score(e, ctx): number?
	local id = ctx.order
	if id == "near" then
		return -e.reach
	elseif id == "rich" then
		-- Lo que más vale por trozo; entre iguales, lo más cerca
		return e.piece * (1 - math.min(e.reach, 5000) * 1e-5)
	elseif id == "yield" then
		return rateOf(e, ctx.crew, ctx) - e.reach * 1e-9
	elseif id == "side" then
		if not ctx.root then
			return nil
		end
		local gap = flatGap(e.pos, ctx.root)
		return if gap <= O.SideRadius then -gap else nil
	elseif id == "finish" then
		-- Lo empezado primero, lo que menos vida le queda (en proporción); si no hay, lo más cerca
		local hp = (e.food:GetAttribute("Hp") :: number?) or e.maxHp
		local left = hp / math.max(e.maxHp, 1)
		local started = if hp < e.maxHp then 1e9 else 0
		return started + (1 - left) * 1e6 - e.reach
	elseif id == "big" then
		local hp = (e.food:GetAttribute("Hp") :: number?) or e.maxHp
		return hp - e.reach * 1e-3
	elseif id == "zone" then
		if e.def.zone ~= ctx.zone then
			return nil
		end
		return rateOf(e, ctx.crew, ctx) - e.reach * 1e-9
	end
	return nil
end

-- ¿Sigue valiendo este destino para su orden? (además de estar viva y permitida)
local function stillFits(e, ctx): boolean
	if ctx.order == "side" then
		return ctx.root ~= nil and flatGap(e.pos, ctx.root) <= O.SideKeep
	elseif ctx.order == "zone" then
		return e.def.zone == ctx.zone
	end
	return true
end

local function usable(profile, e, taken): boolean
	if taken[e.food] or not FoodService.isFood(e.food) then
		return false
	end
	local allowed = Colony.autoAllowed -- Garden: lejos de hormigueros ajenos y de lo que alguien muerde
	return not allowed or allowed(profile, e.food)
end

-- La mejor candidata libre para esta orden
local function pick(profile, st, ctx, taken)
	local best, bestScore = nil, -math.huge
	local entries = st.entries
	for i = 1, st.count do
		local e = entries[i]
		local s = score(e, ctx)
		if s and s > bestScore and usable(profile, e, taken) then
			best, bestScore = e, s
		end
	end
	return best
end

-- Las `n` mejores (para la estimación del panel; no mira lo que cogen otros escuadrones)
local function topN(profile, st, ctx, n: number)
	local top, scores = {}, {}
	local entries = st.entries
	local none = {}
	for i = 1, st.count do
		local e = entries[i]
		local s = score(e, ctx)
		if s and (#top < n or s > scores[#top]) and usable(profile, e, none) then
			local at = #top + 1
			for j = 1, #top do
				if s > scores[j] then
					at = j
					break
				end
			end
			table.insert(top, at, e)
			table.insert(scores, at, s)
			if #top > n then
				table.remove(top)
				table.remove(scores)
			end
		end
	end
	return top
end

local function context(profile, squad, crewPerSlot: number, root: Vector3?)
	local stats = profile.stats
	return {
		order = squad.order,
		zone = squad.zone,
		crew = crewPerSlot,
		root = root,
		carry = stats.workerCarry,
		mult = stats.colonyMult,
		garden = profile.gardenScale or 1, -- lo pone Colony: parte del jardín que se llevó en el último tick
	}
end

---------------------------------------------------------------------------------------------------
-- Huecos de cada escuadrón

-- Cada escuadrón tiene al menos un hueco; los que sobran van primero a los rastros del escuadrón 1
-- y luego a quien tenga más obreras por hueco ("A por la grande" va siempre a una sola comida).
local function slotsFor(squads, marked: number): { number }
	local count = #squads
	local slots = {}
	for k = 1, count do
		slots[k] = 1
	end
	local extra = SLOTS - count
	if marked > 0 then
		local add = math.min(marked - 1, extra)
		slots[1] += add
		extra -= add
	end
	while extra > 0 do
		local best, bestRatio = nil, -1
		for k, squad in squads do
			local wants = squad.order ~= "big" and not (k == 1 and marked > 0)
			if wants and squad.share / slots[k] > bestRatio then
				best, bestRatio = k, squad.share / slots[k]
			end
		end
		if not best then
			break
		end
		slots[best] += 1
		extra -= 1
	end
	return slots
end

local function setSquadAttributes(profile, st, squadOf: { [number]: number }?)
	local hill = profile.hill
	if not hill then
		return
	end
	if not squadOf then
		if st.published then
			st.published = false
			for i = 1, SLOTS do
				hill:SetAttribute("TrailSquad" .. i, nil)
			end
		end
		return
	end
	st.published = true
	for i = 1, SLOTS do
		hill:SetAttribute("TrailSquad" .. i, squadOf[i])
	end
end

-- Gancho de Colony: destinos y obreras de cada hueco, o nil para el reparto de siempre
local function plan(profile, hillPos: Vector3, marked: { [number]: Model })
	local st = stateOf(profile)
	local squads = effective(profile)
	local markedCount = #marked
	table.clear(st.auto)
	if not squads or (#squads == 1 and markedCount > 0) then
		setSquadAttributes(profile, st, nil)
		table.clear(st.lastTargets)
		return nil
	end
	if os.clock() - st.builtAt > O.Recalc then
		rebuild(profile, st, hillPos)
	end

	local data = profile.data
	local root = rootOf(profile)
	local rootPos = root and root.Position
	local slots = slotsFor(squads, markedCount)
	local targets: { [number]: Model } = {}
	local crews: { [number]: number } = {}
	local squadOf: { [number]: number } = {}
	local taken = {}
	for _, food in marked do
		taken[food] = true
	end

	local markedSlots = 0
	local p = 0
	for k, squad in squads do
		local n = slots[k]
		local crew = data.workers * squad.share / 100
		local chosen = {}
		local found = 0
		if k == 1 and markedCount > 0 then
			-- El escuadrón 1 sigue los rastros marcados a mano
			for j = 1, math.min(n, markedCount) do
				chosen[j] = marked[j]
				found += 1
			end
			markedSlots = found
		else
			local mine = st.slots[k]
			local key = squad.order .. ":" .. squad.zone .. ":" .. n
			if st.keys[k] ~= key then
				st.keys[k] = key
				table.clear(mine)
			end
			local ctx = context(profile, squad, crew / n, rootPos)
			local fallback: any = nil
			for j = 1, n do
				local food = mine[j]
				local entry = food and st.byFood[food]
				-- Las de recambio (st.loose) no se miden con su orden hasta el próximo repaso
				if not entry or not usable(profile, entry, taken) or (not st.loose[food] and not stillFits(entry, ctx)) then
					local e = pick(profile, st, ctx, taken)
					if not e and squad.order ~= "near" then
						-- Nada que cumpla la orden (lejos de comida, zona vacía): a lo más cercano
						fallback = fallback or context(profile, { order = "near", zone = squad.zone }, crew / n, rootPos)
						e = pick(profile, st, fallback, taken)
						if e then
							st.loose[e.food] = true
						end
					end
					food = e and e.food
				end
				mine[j] = food
				if food then
					taken[food] = true
					chosen[j] = food
					found += 1
					st.auto[food] = true
				end
			end
			for j = n + 1, SLOTS do
				mine[j] = nil
			end
		end
		local each = if found > 0 then crew / found else 0
		for j = 1, n do
			local slot = p + j
			squadOf[slot] = k
			local food = chosen[j]
			if food then
				targets[slot] = food
				crews[slot] = each
			end
		end
		p += n
	end
	-- Escuadrones de más (no debería pasar: como mucho tres huecos)
	for k = #squads + 1, SLOTS do
		table.clear(st.slots[k])
		st.keys[k] = ""
	end

	setSquadAttributes(profile, st, squadOf)
	st.squadOf = squadOf
	st.lastTargets = targets
	st.lastCrews = crews
	return targets, crews, markedSlots
end

---------------------------------------------------------------------------------------------------
-- Estimaciones para el panel

-- [escuadrón] = { [orden] = comida/s } y [escuadrón] = comida/s de lo que hacen ahora
local function estimates(profile)
	local st = stateOf(profile)
	local hill = profile.hill
	local squads = effective(profile) or { { order = "near", share = 100, zone = 1 } }
	if not hill then
		return nil, nil
	end
	if os.clock() - st.builtAt > O.Recalc then
		rebuild(profile, st, hill:GetPivot().Position)
	end
	local data = profile.data
	local stats = profile.stats
	local root = rootOf(profile)
	local rootPos = root and root.Position
	local markedCount = 0
	for _, trail in profile.trails do
		if trail then
			markedCount += 1
		end
	end
	local unlocked = unlockedSet(data)
	local slots = slotsFor(squads, markedCount)
	local foodMult = stats.foodMult
	local per, now = {}, {}
	for k, squad in squads do
		local crew = data.workers * squad.share / 100
		local row = {}
		for _, def in O.List do
			if unlocked[def.id] then
				local n = if def.id == "big" then 1 else slots[k]
				local trial = { order = def.id, zone = squad.zone, share = squad.share }
				local ctx = context(profile, trial, crew / n, rootPos)
				local picks = topN(profile, st, ctx, n)
				local total = 0
				local each = if #picks > 0 then crew / #picks else 0
				for _, e in picks do
					total += rateOf(e, each, ctx)
				end
				row[def.id] = total * foodMult
			end
		end
		per[k] = row
		-- Lo de ahora: sus huecos de verdad
		local ctx = context(profile, squad, 0, rootPos)
		local total = 0
		for slot, food in st.lastTargets do
			local e = st.byFood[food]
			if e and st.squadOf[slot] == k then
				total += rateOf(e, st.lastCrews[slot] or 0, ctx)
			end
		end
		now[k] = total * foodMult
	end
	return per, now
end

---------------------------------------------------------------------------------------------------
-- Instantánea para el cliente

local function savedSquads(data)
	local saved = data.orders
	if type(saved) == "table" and type(saved.squads) == "table" and #saved.squads > 0 then
		return saved.squads, false
	end
	return { { order = "near", share = 100 } }, true
end

local function snapshot(profile, withEstimates: boolean)
	local data = profile.data
	local squads, isDefault = savedSquads(data)
	local list = {}
	for k, squad in squads do
		list[k] = { order = squad.order, share = squad.share, zone = zoneOf(squad, data) }
	end
	local marked = false
	for _, trail in profile.trails do
		marked = marked or trail ~= nil
	end
	local snap = {
		squads = list,
		default = isDefault,
		max = squadMax(data),
		unlocked = unlockedSet(data),
		viewed = data.ordersViewed or {},
		depth = data.depth,
		deep = profile.stats.trailSlots > 0 or not O.DeepNeedsTrail,
		marked = marked,
		rate = data.rate,
	}
	if withEstimates then
		local per, now = estimates(profile)
		snap.est = per
		snap.now = now
	end
	return snap
end

-- Clave de lo que ve el cliente fuera del panel (chips y botón): si cambia, se manda
local function stateKey(profile): string
	local data = profile.data
	local squads = savedSquads(data)
	local parts = {}
	for _, squad in squads do
		table.insert(parts, tostring(squad.order) .. tostring(squad.share) .. tostring(squad.zone))
	end
	local unlocked = unlockedSet(data)
	for _, def in O.List do
		table.insert(parts, if unlocked[def.id] then "1" else "0")
	end
	table.insert(parts, tostring(squadMax(data)))
	table.insert(parts, tostring(data.depth))
	table.insert(parts, tostring(profile.stats.trailSlots > 0))
	return table.concat(parts, "|")
end

local function send(profile, withEstimates: boolean?)
	local st = stateOf(profile)
	st.sentKey = stateKey(profile)
	remote:FireClient(profile.player, "State", snapshot(profile, withEstimates == true))
end

---------------------------------------------------------------------------------------------------
-- Cambios pedidos por la jugadora (todo validado)

local function ensureOrders(data)
	if type(data.orders) ~= "table" or type(data.orders.squads) ~= "table" or #data.orders.squads == 0 then
		data.orders = { squads = { { order = "near", share = 100 } } }
	end
	return data.orders
end

-- Deja el reparto bien: tantos escuadrones como se tienen, cada uno con al menos MinShare en pasos de
-- Step, y que sume 100 (lo que falte o sobre, al primero)
local function normalize(orders, max: number)
	local squads = orders.squads
	while #squads > max do
		local extra = table.remove(squads)
		squads[1].share += extra.share or 0
	end
	local total = 0
	for _, squad in squads do
		local share = math.floor((tonumber(squad.share) or 0) / O.Step + 0.5) * O.Step
		squad.share = math.max(share, O.MinShare)
		total += squad.share
	end
	squads[1].share += 100 - total
	if squads[1].share < O.MinShare then
		-- Demasiado para los demás: todo vuelve a partes iguales
		local each = math.floor(100 / #squads / O.Step) * O.Step
		for _, squad in squads do
			squad.share = each
		end
		squads[1].share += 100 - each * #squads
	end
end

local function nextUnlocked(data, current: string?): string
	local start = (current and ORDER_BY_ID[current] and ORDER_BY_ID[current].index) or 0
	for step = 1, #O.List do
		local def = O.List[(start + step - 1) % #O.List + 1]
		if reached(def, data) then
			return def.id
		end
	end
	return "near"
end

local function ack(profile, squad: number, order: string)
	local st = stateOf(profile)
	st.builtAt = -math.huge -- que la próxima vuelta elija con la lista al día
	remote:FireClient(profile.player, "Ack", squad, order)
	send(profile, st.watching)
end

local function setOrder(profile, squad: number, order: string, zone: any): boolean
	local data = profile.data
	local def = ORDER_BY_ID[order]
	if not def or not reached(def, data) then
		return false
	end
	local orders = ensureOrders(data)
	normalize(orders, squadMax(data))
	local entry = orders.squads[squad]
	if not entry then
		return false
	end
	entry.order = order
	local wanted = tonumber(zone)
	if order == "zone" then
		if wanted and wanted >= 1 and wanted <= math.min(data.depth or 1, #Config.Zones) then
			entry.zone = math.floor(wanted)
		elseif not entry.zone then
			entry.zone = math.clamp(data.depth or 1, 1, #Config.Zones)
		end
	end
	ack(profile, squad, order)
	return true
end

local function setShares(profile, shares: any)
	local data = profile.data
	if type(shares) ~= "table" then
		return
	end
	local orders = ensureOrders(data)
	local max = squadMax(data)
	normalize(orders, max)
	local squads = orders.squads
	if #shares ~= #squads then
		return
	end
	local total = 0
	for k = 1, #squads do
		local share = shares[k]
		if type(share) ~= "number" or share ~= share or share % O.Step ~= 0 or share < O.MinShare then
			return
		end
		total += share
	end
	if total ~= 100 then
		return
	end
	for k, squad in squads do
		squad.share = shares[k]
	end
	send(profile, stateOf(profile).watching)
end

local function setSquadCount(profile, count: any)
	local data = profile.data
	if type(count) ~= "number" or count ~= count then
		return
	end
	count = math.floor(count)
	local max = squadMax(data)
	if count < 1 or count > max then
		return
	end
	local orders = ensureOrders(data)
	normalize(orders, max)
	local squads = orders.squads
	local added = false
	while #squads < count do
		-- El nuevo escuadrón sale del más grande, con una orden que no lleve nadie
		local largest = squads[1]
		for _, squad in squads do
			if squad.share > largest.share then
				largest = squad
			end
		end
		local give = math.min(if #squads == 1 then 30 else 20, largest.share - O.MinShare)
		if give < O.MinShare then
			break
		end
		largest.share -= give
		local used = {}
		for _, squad in squads do
			used[squad.order] = true
		end
		local order = "near"
		for _, def in O.List do
			if reached(def, data) and not used[def.id] then
				order = def.id
				break
			end
		end
		table.insert(squads, { order = order, share = give })
		added = true
	end
	while #squads > count do
		local gone = table.remove(squads)
		squads[1].share += gone.share
	end
	normalize(orders, max)
	if added then
		ack(profile, #squads, squads[#squads].order)
	else
		send(profile, stateOf(profile).watching)
	end
end

local function onRequest(player: Player, action: any, a: any, b: any, c: any)
	local profile = Profiles.get(player)
	if not profile or type(action) ~= "string" then
		return
	end
	local st = stateOf(profile)
	-- Como mucho 8 mensajes por segundo
	local clock = os.clock()
	st.tokens = math.min(8, st.tokens + (clock - st.tokenAt) * 8)
	st.tokenAt = clock
	if st.tokens < 1 then
		return
	end
	st.tokens -= 1

	local data = profile.data
	local squad = if type(a) == "number" and a == a then math.floor(a) else nil
	if action == "Sync" then
		send(profile, st.watching)
	elseif action == "Watch" then
		st.watching = a == true
		if st.watching then
			st.estimateAt = clock
			send(profile, true)
		end
	elseif action == "Set" then
		if squad and type(b) == "string" then
			setOrder(profile, squad, b, c)
		end
	elseif action == "Cycle" then
		local squads = effective(profile)
		local index = squad or 1
		local current = if squads and squads[index] then squads[index].order else (if index == 1 then "near" else nil)
		if current then
			setOrder(profile, index, nextUnlocked(data, current))
		end
	elseif action == "Zone" then
		local squads = effective(profile)
		if squad and squads and squads[squad] and squads[squad].order == "zone" then
			setOrder(profile, squad, "zone", b)
		end
	elseif action == "Shares" then
		setShares(profile, a)
	elseif action == "Squads" then
		setSquadCount(profile, a)
	elseif action == "Viewed" then
		local viewed = data.ordersViewed
		if type(viewed) ~= "table" then
			viewed = {}
			data.ordersViewed = viewed
		end
		for id in unlockedSet(data) do
			viewed[id] = true
		end
		send(profile, st.watching)
	end
end

---------------------------------------------------------------------------------------------------
-- Avisos de desbloqueo y bucle

local function checkUnlocks(profile)
	local data = profile.data
	local unlocked = unlockedSet(data)
	local told = data.ordersTold
	if type(told) ~= "table" then
		-- Primera vez: lo que ya tenía se da por avisado (sin lluvia de avisos al entrar); el botón
		-- lleva la marca hasta que lo vea en el panel
		told = {}
		for id in unlocked do
			told[id] = true
		end
		data.ordersTold = told
		return
	end
	for _, def in O.List do
		if unlocked[def.id] and not told[def.id] then
			told[def.id] = true
			remote:FireClient(profile.player, "Unlocked", def.id)
		end
	end
	for k = 2, #O.Squads do
		local id = "squad" .. k
		if unlocked[id] and not told[id] then
			told[id] = true
			remote:FireClient(profile.player, "Unlocked", id)
		end
	end
end

function Orders.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Orders"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	Colony.orders = plan

	-- Valor de lo que traen las órdenes fuera del jardín (Config.Orders.DeepWorth). Con 1 no se engancha.
	if O.DeepWorth ~= 1 then
		local prevBoost = Colony.boost
		Colony.boost = function(profile, food: Model): (number, number)
			local work, worth = 1, 1
			if prevBoost then
				work, worth = prevBoost(profile, food)
			end
			local st = states[profile]
			if st and st.auto[food] then
				local def = FoodService.defOf(food)
				if def and def.zone > 1 then
					worth *= O.DeepWorth
				end
			end
			return work, worth
		end
	end

	-- Partida nueva (enjambre o panel DEV): los escuadrones sueltan sus destinos
	Events.on("RunReset", function(profile)
		local st = states[profile]
		if st then
			for k = 1, SLOTS do
				table.clear(st.slots[k])
				st.keys[k] = ""
			end
			st.builtAt = -math.huge
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for profile in pairs(states) do
			if profile.player == player then
				states[profile] = nil
			end
		end
	end)

	task.spawn(function()
		local beat = 0
		while true do
			task.wait(LOOP)
			beat += 1
			local clock = os.clock()
			for profile in pairs(states) do
				if Profiles.get(profile.player) ~= profile then
					states[profile] = nil
				end
			end
			for _, profile in Profiles.all() do
				local st = stateOf(profile)
				if beat % 4 == 0 then
					checkUnlocks(profile)
				end
				if st.watching and clock - st.estimateAt >= O.EstimateEvery then
					st.estimateAt = clock
					send(profile, true)
				elseif beat % 4 == 0 and stateKey(profile) ~= st.sentKey then
					send(profile, false)
				end
			end
		end
	end)
end

return Orders
