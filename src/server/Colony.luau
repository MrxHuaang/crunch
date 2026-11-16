-- Simulación de las obreras. En el servidor son solo un número: cada medio segundo se calcula
-- cuánta comida arrancan de cada rastro. Las hormigas que se ven las dibuja cada cliente,
-- a partir de la posición de cada destino que se publica en el hormiguero.
-- Por muchas obreras que haya, una colonia no puede con una comida en menos de BITE_TIME
-- segundos: las que no caben alrededor esperan sin hacer nada.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Depots = require(script.Parent.Depots)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local Profiles = require(script.Parent.Profiles)

local Colony = {}

-- (profile, def, posición de la comida, distancia desde casa) -> distancia que pagan las obreras.
-- Lo pone el módulo Extras (puesto avanzado); sin él, la distancia es la de siempre.
Colony.shortcut = nil :: ((any, any, Vector3, number) -> number)?
-- Ganchos del módulo Garden: (profile, comida) -> si las obreras sin rastro pueden ir a esa comida
-- del jardín; (profile, vida que querrían arrancar al jardín en este tick, dt) -> la que les toca.
Colony.autoAllowed = nil :: ((any, Model) -> boolean)?
Colony.gardenLimit = nil :: ((any, number, number) -> number)?
-- Ganchos de las castas (Comandante). forced: (profile) -> comida a la que van a la fuerza ahora y
-- cuántas obreras como mucho (nil: ninguna). boost: (profile, comida) -> (multiplicador de trabajo,
-- multiplicador de valor). Sin ellos, todo es como siempre.
Colony.forced = nil :: ((any) -> (Model?, number?))?
Colony.boost = nil :: ((any, Model) -> (number, number))?
-- Gancho del módulo Orders (órdenes y escuadrones): (profile, centro del hormiguero, rastros marcados
-- [1..n]) -> (destinos [hueco 1..3], obreras [hueco], cuántos de los primeros huecos son rastros
-- marcados) o nil para el reparto de siempre (sin orden elegida devuelve nil).
Colony.orders = nil :: ((any, Vector3, { Model }) -> ({ [number]: Model }?, { [number]: number }?, number?))?

local TICK = 0.5
local BITE_TIME = 3 -- segundos que, como poco, tarda una colonia en terminar una comida
local AUTO_TARGETS = 3 -- comidas del jardín a la vez cuando no hay rastros
local fxRemote: RemoteEvent

-- Distancia de un viaje de obrera (ida): fuera del jardín, hasta el hormiguero de esa zona (Depots); en el
-- jardín, hasta casa. La usan Colony y Orders, para que las estimaciones coincidan con lo que pasa.
function Colony.reach(profile, def, foodPos: Vector3, hillPos: Vector3): number
	if def.zone >= 2 then
		return Depots.distance(def.zone, foodPos)
	end
	local reach = ((foodPos - hillPos) * Vector3.new(1, 0, 1)).Magnitude
	if Colony.shortcut then
		reach = Colony.shortcut(profile, def, foodPos, reach) -- puesto avanzado (Extras)
	end
	return reach
end

local function canEat(profile, def): boolean
	local stats = profile.stats
	return def.zone <= stats.depth and (not def.hard or stats.workersBreakHard)
end

-- Hasta `count` comidas del mismo racimo que `food` (a Config.Chain.Range studs de borde a borde), de
-- la más cercana a la más lejana, que esta colonia pueda comer
function Colony.clusterMates(profile, food: Model, count: number): { Model }
	if count <= 0 then
		return {}
	end
	local center = food:GetPivot().Position
	local near = {}
	for other in FoodService.list() do
		if other ~= food then
			local def = FoodService.defOf(other)
			if def and canEat(profile, def) then
				local gap = ((other:GetPivot().Position - center) * Vector3.new(1, 0, 1)).Magnitude - ((other:GetAttribute("Radius") :: number?) or 0)
				if gap <= Config.Chain.Range then
					table.insert(near, { food = other, gap = gap })
				end
			end
		end
	end
	table.sort(near, function(a, b)
		return a.gap < b.gap
	end)
	local out = {}
	for i = 1, math.min(count, #near) do
		out[i] = near[i].food
	end
	return out
end

local function makeTrail(profile, food: Model)
	profile.trailOrder += 1
	return {
		food = food,
		id = food:GetAttribute("FoodId"),
		pos = food:GetPivot().Position,
		order = profile.trailOrder,
	}
end

local function isTargeted(profile, food: Model): boolean
	for _, trail in profile.trails do
		if trail.food == food then
			return true
		end
	end
	return false
end

-- Quita rastros de comida ya comida. Si queda otra igual cerca, las obreras pasan a ella.
local function cleanTrails(profile, slots: number)
	for slot = 1, 3 do
		local trail = profile.trails[slot]
		if not trail then
			continue
		end
		if slot > slots then
			profile.trails[slot] = nil
		elseif not FoodService.isFood(trail.food) then
			local nextFood = FoodService.nearest(trail.pos, 90, function(food, def)
				return def.id == trail.id and not isTargeted(profile, food)
			end)
			profile.trails[slot] = if nextFood then makeTrail(profile, nextFood) else nil
		end
	end
end

-- Rastro listo: los huecos libres van a la comida más valiosa que la colonia pueda comer.
local function fillSmart(profile, slots: number, hillPos: Vector3)
	for slot = 1, slots do
		if profile.trails[slot] then
			continue
		end
		for i = #Config.Foods, 1, -1 do
			local wanted = Config.Foods[i]
			if wanted.boss or not canEat(profile, wanted) then
				continue
			end
			local food = FoodService.nearest(hillPos, math.huge, function(candidate, def)
				return def.id == wanted.id and not isTargeted(profile, candidate) and candidate:GetAttribute("Event") == nil
			end)
			if food then
				profile.trails[slot] = makeTrail(profile, food)
				break
			end
		end
	end
end

-- Sin rastro, las obreras van a lo que hay en el jardín: hasta tres comidas a la vez, las de más
-- vida que queden (y entre iguales, las más cercanas). Cada hueco solo cambia de comida cuando
-- la suya se acaba, así las filas no saltan de una a otra.
-- Devuelve los huecos 1..3 (puede haber huecos vacíos si en el jardín no queda nada).
local function autoFoods(profile, hillPos: Vector3): { [number]: Model }
	local chosen = profile.autoFoods
	local allowed = Colony.autoAllowed -- Garden: lejos de hormigueros ajenos y de lo que alguien muerde
	local function taken(food: Model): boolean
		for slot = 1, AUTO_TARGETS do
			if chosen[slot] == food then
				return true
			end
		end
		return false
	end
	for slot = 1, AUTO_TARGETS do
		local current = chosen[slot]
		if current and FoodService.isFood(current) and (not allowed or allowed(profile, current)) then
			continue
		end
		chosen[slot] = nil -- deja de contar como cogida mientras se busca otra
		local best: Model? = nil
		local bestScore = -math.huge
		for food in FoodService.list() do
			local def = FoodService.defOf(food)
			if def.zone == 1 and not def.hard and not taken(food) and (not allowed or allowed(profile, food)) then
				local distance = (food:GetPivot().Position - hillPos).Magnitude
				local score = (food:GetAttribute("Hp") :: number) * 1000 - distance
				if score > bestScore then
					best = food
					bestScore = score
				end
			end
		end
		chosen[slot] = best
	end
	return chosen
end

-- targets: [hueco 1..3] = comida; un hueco vacío borra su destino.
-- crews (escuadrones, módulo Orders): [hueco] = obreras; se publica la parte de cada hueco en
-- TrailShare1..3 para que el cliente reparta las filas igual. Sin crews, filas iguales (TrailShare nil).
local function publish(hill: Model, targets: { [number]: Model }, crews: { [number]: number }?, workers: number)
	for i = 1, 3 do
		local food = targets[i]
		if food then
			hill:SetAttribute("TrailPos" .. i, food:GetPivot().Position)
			hill:SetAttribute("TrailRadius" .. i, food:GetAttribute("Radius"))
			hill:SetAttribute("TrailColor" .. i, food:GetAttribute("Color"))
		else
			hill:SetAttribute("TrailPos" .. i, nil)
		end
		local share = if crews and food and workers > 0 then math.floor((crews[i] or 0) / workers * 100 + 0.5) / 100 else nil
		hill:SetAttribute("TrailShare" .. i, share)
	end
end

local function tick(profile, dt: number)
	local hill = profile.hill
	if not hill then
		return
	end
	local data = profile.data
	local stats = profile.stats
	local hillPos = hill:GetPivot().Position
	local slots = stats.trailSlots

	cleanTrails(profile, slots)
	if stats.smartTrail and data.workers > 0 then
		fillSmart(profile, slots, hillPos)
	end

	-- [hueco] = comida. Los rastros marcados se publican seguidos, como siempre;
	-- los automáticos conservan su hueco para que su fila no salte a otra.
	local targets: { [number]: Model } = {}
	local count = 0
	for slot = 1, slots do
		local trail = profile.trails[slot]
		if trail then
			count += 1
			targets[count] = trail.food
		end
	end

	local marked = count > 0
	hill:SetAttribute("Auto", not marked)
	-- Órdenes y escuadrones (módulo Orders): si hay orden elegida, destinos y obreras de cada hueco
	-- salen de ahí; los rastros marcados son del primer escuadrón (markedSlots: los primeros huecos)
	local crews: { [number]: number }? = nil
	local markedSlots = count
	if Colony.orders and data.workers > 0 then
		local planned, plannedCrews, plannedMarked = Colony.orders(profile, hillPos, table.clone(targets))
		if planned and plannedCrews then
			targets, crews, markedSlots = planned, plannedCrews, plannedMarked or 0
			count = 0
			for _ in targets do
				count += 1
			end
		end
	end
	hill:SetAttribute("Marked", markedSlots) -- las banderas de rastro solo van en estos huecos
	if not marked and not crews and data.workers > 0 then
		for slot, food in autoFoods(profile, hillPos) do
			targets[slot] = food
			count += 1
		end
	end
	-- Castas (Comandante): la comida asaltada a la fuerza ocupa el primer hueco si no estaba ya
	local forced, crew = nil, 0
	if Colony.forced and data.workers > 0 then
		local food, most = Colony.forced(profile)
		if food and FoodService.isFood(food) and canEat(profile, FoodService.defOf(food)) then
			forced, crew = food, most or data.workers
			local present = false
			for _, other in targets do
				present = present or other == food
			end
			if not present then
				if targets[1] == nil then
					count += 1
				end
				targets[1] = food
			end
		end
	end
	-- Con escuadrones, la asaltada se lleva su cuadrilla (o la de su hueco, si es mayor) y los demás
	-- huecos se quedan con lo que sobra, en la misma proporción
	if crews and forced then
		local forcedSlot = nil
		for slot, food in targets do
			if food == forced then
				forcedSlot = slot
			end
		end
		if forcedSlot then
			local own = crews[forcedSlot] or 0
			local want = math.max(own, math.min(crew, data.workers))
			local rest = data.workers - own
			local scale = if rest > 0 then math.max(data.workers - want, 0) / rest else 0
			for slot in targets do
				crews[slot] = if slot == forcedSlot then want else (crews[slot] or 0) * scale
			end
		end
	end
	publish(hill, targets, crews, data.workers)

	local credited = 0
	local remainders = {} -- solo se guardan las de los destinos de ahora
	if data.workers > 0 and count > 0 then
		local now = Workspace:GetServerTimeNow()
		local mult = stats.colonyMult * (if now < profile.frenzyUntil then stats.frenzyMult else 1)
		if marked and not crews then
			mult *= stats.trailBonus
		end
		local share = data.workers / count
		local forcedShare = 0
		if forced then
			-- La asaltada se lleva su cuadrilla (o su parte normal, si es mayor); el resto se reparte
			forcedShare = math.max(share, math.min(crew, data.workers))
			share = if count > 1 then math.max(data.workers - forcedShare, 0) / (count - 1) else 0
		end

		-- Primero lo que arrancaría cada destino; la parte del jardín se recorta luego a lo que
		-- le toca a esta colonia (Colony.gardenLimit, módulo Garden)
		local plan = {}
		local garden = 0
		for slot, food in targets do
			local def = FoodService.defOf(food)
			if not canEat(profile, def) then
				continue
			end
			local reach = Colony.reach(profile, def, food:GetPivot().Position, hillPos)
			local trip = (2 * reach / stats.workerSpeed + Config.Worker.TurnTime) * stats.tripMult
			-- Tope por comida: lo que no cabe se pierde (esas obreras esperan), no se guarda para luego
			local cap = (food:GetAttribute("MaxHp") or def.hp) * dt / BITE_TIME
			local work, worth = 1, 1
			if Colony.boost then
				work, worth = Colony.boost(profile, food) -- castas (Comandante)
			end
			local crewHere = if crews then (crews[slot] or 0) elseif food == forced then forcedShare else share
			-- Con escuadrones, la feromona dulce solo cuenta en los huecos de rastros marcados
			local scent = if crews and slot <= markedSlots then stats.trailBonus else 1
			local raw = crewHere * stats.workerCarry / trip * mult * scent * work * dt
			local gain = math.min(raw, cap * work)
			table.insert(plan, { food = food, def = def, gain = gain, worth = worth })
			if def.zone == 1 then
				garden += gain
			elseif raw > gain then
				-- Racimos: lo que no cabe en la comida marcada pasa a las de su racimo (las más cercanas,
				-- cada una con su propio tope), hasta stats.colonySpread comidas en total
				for _, other in Colony.clusterMates(profile, food, (stats.colonySpread or 1) - 1) do
					local otherDef = FoodService.defOf(other)
					local otherCap = (other:GetAttribute("MaxHp") or otherDef.hp) * dt / BITE_TIME * work
					local extra = math.min(raw - gain, otherCap)
					if extra <= 0 then
						break
					end
					gain += extra
					table.insert(plan, { food = other, def = otherDef, gain = extra, worth = worth })
				end
			end
		end
		local gardenScale = 1
		if garden > 0 and Colony.gardenLimit then
			gardenScale = math.clamp(Colony.gardenLimit(profile, garden, dt) / garden, 0, 1)
			profile.gardenScale = gardenScale -- lo lee Orders para estimar lo que rinde el jardín
		end

		for _, item in plan do
			local food, def = item.food, item.def
			local gain = if def.zone == 1 then item.gain * gardenScale else item.gain
			local hp = gain + (profile.remainders[food] or 0)
			local whole = math.floor(hp)
			remainders[food] = hp - whole
			if whole > 0 then
				local piece = FoodService.pieceValue(food, def, stats) -- antes de dañarla: puede desaparecer
				local taken, _, finished = FoodService.damage(food, whole)
				if taken > 0 then
					credited += Profiles.addFood(profile, taken * piece * (item.worth or 1))
					Profiles.trackFood(profile, def, taken)
					Events.fire("Ate", profile, def, taken, true)
				end
				if finished then
					Profiles.awardTrophy(profile, def)
					Events.fire("Finished", profile, def)
				end
			end
		end
	end
	profile.remainders = remainders

	-- Media móvil del ingreso: es lo que rinde la colonia cuando no estás
	data.rate = data.rate * 0.95 + (credited / dt) * 0.05

	-- La reina cría sola, gastando como mucho una décima de lo que tienes por obrera
	if stats.queen then
		for _ = 1, 5 do
			local cost = Stats.workerCost(data.workers, stats.workerDiscount)
			if data.workers >= stats.workerCap or cost > data.food * 0.1 then
				break
			end
			data.food -= cost
			data.workers += 1
		end
	end

	Profiles.push(profile)
end

local function onTrail(player: Player, food: any)
	local profile = Profiles.get(player)
	if not profile or not FoodService.isFood(food) then
		return
	end
	local slots = profile.stats.trailSlots
	if slots <= 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local flat = (food:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude - (food:GetAttribute("Radius") :: number) > profile.stats.biteRange + 8 then
		return
	end

	-- Marcar otra vez la misma comida quita el rastro
	for slot = 1, slots do
		local trail = profile.trails[slot]
		if trail and trail.food == food then
			profile.trails[slot] = nil
			fxRemote:FireClient(player, "Trail", food:GetPivot().Position, false)
			return
		end
	end

	local def = FoodService.defOf(food)
	if def.zone > profile.stats.depth then
		return
	end
	if def.boss then
		Profiles.say(profile, "La tarta es cosa mía. Las obreras no se atreven", 4)
		return
	end
	if def.hard and not profile.stats.workersBreakHard then
		Profiles.say(profile, "Mis obreras no pueden con eso. Hace falta el cuartel", 4)
		return
	end
	if food:GetAttribute("Event") ~= nil then
		Profiles.say(profile, "Esto se come a mordiscos, no con rastro", 3) -- pan gigante (Garden)
		return
	end

	-- Usa un hueco libre; si no hay, reemplaza el rastro más viejo
	local chosen = 1
	local oldest = math.huge
	for slot = 1, slots do
		local trail = profile.trails[slot]
		if not trail then
			chosen = slot
			break
		elseif trail.order < oldest then
			oldest = trail.order
			chosen = slot
		end
	end
	profile.trails[chosen] = makeTrail(profile, food)
	fxRemote:FireClient(player, "Trail", food:GetPivot().Position, true)
end

local function onFrenzy(player: Player)
	local profile = Profiles.get(player)
	if not profile or not profile.stats.hasFrenzy then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now < profile.frenzyReadyAt then
		return
	end
	-- Si hay un frenesí pagado en marcha, el gratis va detrás y no lo corta. Sobre otro gratis no se
	-- apila: con la duración por encima de la recarga se acumularían minutos
	local base = math.max(profile.paidFrenzyUntil or 0, now)
	profile.frenzyUntil = math.max(profile.frenzyUntil, base + profile.stats.frenzyDuration)
	profile.frenzyReadyAt = now + profile.stats.frenzyCooldown
	Profiles.push(profile)
	fxRemote:FireClient(player, "Frenzy")
end

function Colony.clearTrails(profile)
	table.clear(profile.trails)
	table.clear(profile.remainders)
	table.clear(profile.autoFoods)
end

function Colony.start(remotes: Folder)
	fxRemote = remotes.Fx
	remotes.Trail.OnServerEvent:Connect(onTrail)
	remotes.Frenzy.OnServerEvent:Connect(onFrenzy)

	task.spawn(function()
		local last = os.clock()
		local lastErr, lastAt = nil, 0
		while true do
			task.wait(TICK)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, profile in Profiles.all() do
				-- Un fallo con una jugadora no para la colonia de las demás ni apaga el bucle
				local ok, err = pcall(tick, profile, dt)
				if not ok and (err ~= lastErr or now - lastAt > 10) then
					lastErr, lastAt = err, now
					warn("[CRUNCH!] Colonia:", err)
				end
			end
		end
	end)
end

return Colony
