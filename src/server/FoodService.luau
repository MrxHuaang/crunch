-- Crea la comida del jardín, lleva su vida, le quita piezas al comerla y la hace reaparecer.
-- La comida sale en RACIMOS (Config.FoodLayout): grupos de comidas casi tocándose, al alcance de la
-- mordida en cadena y del área, con pasillos libres entre racimos. En el camino cada comida tiene su
-- sitio fijo en un racimo y reaparece en él; en el jardín los racimos son centros alrededor de los
-- que sale la comida (también la que añade el módulo Garden).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)

local FoodService = {}

local container: Model
local rng = Random.new()
local foods: { [Model]: { BasePart } } = {} -- comida viva -> sus piezas en orden

local MAP = Config.Map
local LAYOUT = Config.FoodLayout
local hillCenters: { Vector3 } = {}
local pending: { [string]: number } = {} -- [idComida] = reapariciones en camino
local alive = 0 -- modelos de comida vivos (tope: Config.FoodLayout.MaxModels)

-- Sitio de una comida en un racimo del camino. slotOf: comida viva -> su sitio (reaparece en él)
type Slot = { def: any, pos: Vector3, jefa: boolean }
local slotsByZone: { [number]: { Slot } } = {}
local slotOf: { [Model]: Slot } = {}
local gardenCenters: { Vector3 } = {}
local radiusOf: { [string]: number } = {} -- radio de cada comida (lo mide FoodModels al construirla)

-- Ganchos del módulo Garden (comida según la gente que haya, sitios vetados, valor por jugadora)
-- Segundos hasta que vuelve una comida acabada; nil: no vuelve
FoodService.respawnDelay = function(def): number?
	return def.respawn
end
-- (comida, definición, estadísticas, valor) -> valor final de cada trozo
FoodService.valueHook = nil :: ((Model, any, any, number) -> number)?
-- Círculos del jardín donde no sale comida (juguetes)
FoodService.keepOut = {} :: { { pos: Vector3, radius: number } }

local function inLobby(spot: Vector3): boolean
	for _, center in hillCenters do
		if (center - spot).Magnitude < 34 then
			return false
		end
	end
	for _, circle in FoodService.keepOut do
		if ((circle.pos - spot) * Vector3.new(1, 0, 1)).Magnitude < circle.radius then
			return false
		end
	end
	-- Ni encima de la tabla de puntuaciones ni en la boca del camino
	return (spot - Vector3.new(-0.46 * MAP.LobbyRadius, 0, -0.66 * MAP.LobbyRadius)).Magnitude > 34
end

-- Un punto al azar dentro de la zona de la comida.
local function zoneSpot(def): Vector3
	local zone = Config.Zones[def.zone]
	if def.boss then
		return Vector3.new(0, Config.GroundY, zone.z1 + 42)
	end
	if def.zone == 1 then
		-- Alrededor de un centro de racimo del jardín (la mitad, en la media luna de los hormigueros:
		-- así los primeros viajes son cortos). Nunca dentro de un montículo (lo vigila inLobby).
		for _ = 1, 30 do
			local center = gardenCenters[rng:NextInteger(1, math.max(1, #gardenCenters))] or Vector3.zero
			local angle = rng:NextNumber(0, math.pi * 2)
			local r = math.sqrt(rng:NextNumber()) * LAYOUT.GardenSpread
			local spot = Vector3.new(center.X + math.cos(angle) * r, Config.GroundY, center.Z + math.sin(angle) * r)
			if inLobby(spot) and Vector3.new(spot.X, 0, spot.Z).Magnitude < MAP.LobbyRadius - 10 then
				return spot
			end
		end
		return Vector3.new(0, Config.GroundY, 0)
	end
	-- En el camino: junto a un sitio de racimo de esa comida (comida extra de sucesos y de la tienda)
	local slots = slotsByZone[def.zone]
	if slots and #slots > 0 then
		local slot = slots[rng:NextInteger(1, #slots)]
		for _ = 1, 8 do
			local candidate = slots[rng:NextInteger(1, #slots)]
			if candidate.def == def then
				slot = candidate
				break
			end
		end
		local angle = rng:NextNumber(0, math.pi * 2)
		return slot.pos + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(3, 7)
	end
	return Vector3.new(0, Config.GroundY, zone.z0 - (zone.z0 - zone.z1) / 2)
end

local function freeSpot(def, radius: number): Vector3
	local spot = Vector3.zero
	for _ = 1, 14 do
		spot = zoneSpot(def)
		local clear = true
		for other in foods do
			local gap = (other:GetPivot().Position - spot).Magnitude
			if gap < radius + (other:GetAttribute("Radius") :: number) + 1.5 then
				clear = false
				break
			end
		end
		if clear then
			break
		end
	end
	return spot
end

---------------------------------------------------------------------------------------------------
-- Racimos

-- Coloca las comidas de un racimo alrededor de (0, 0): la más grande en el centro y las demás en
-- anillos, casi tocándose (Config.FoodLayout.Gap de borde a borde). Devuelve { { item, offset } }.
local function packCluster(items, crng: Random)
	table.sort(items, function(a, b)
		return a.radius > b.radius
	end)
	local placed = {}
	for i, item in items do
		if i == 1 then
			table.insert(placed, { item = item, offset = Vector2.zero })
			continue
		end
		local distance = placed[1].item.radius + item.radius + LAYOUT.Gap
		local done = false
		for _ = 1, 6 do
			local start = crng:NextNumber(0, math.pi * 2)
			for k = 0, 23 do
				local angle = start + k / 24 * math.pi * 2
				local offset = Vector2.new(math.cos(angle), math.sin(angle)) * distance
				local clear = true
				for _, other in placed do
					if (other.offset - offset).Magnitude < other.item.radius + item.radius + LAYOUT.Gap * 0.6 then
						clear = false
						break
					end
				end
				if clear then
					table.insert(placed, { item = item, offset = offset })
					done = true
					break
				end
			end
			if done then
				break
			end
			distance += item.radius + LAYOUT.Gap
		end
		if not done then
			table.insert(placed, { item = item, offset = Vector2.new(distance, 0) })
		end
	end
	return placed
end

-- Sitios de los racimos de una zona del camino, en una rejilla de 3 x 3 (el banquete en la fila del
-- fondo; sobra una celda). Determinista: la misma zona siempre tiene los mismos racimos.
local function layoutZone(zone): { Slot }
	local zrng = Random.new(zone.id * 7919)
	local first = (zone.id - 1) * 3
	local defs = { Config.Foods[first + 1], Config.Foods[first + 2], Config.Foods[first + 3] }
	local recipes = {}
	local feast = nil
	for _, recipe in LAYOUT.Clusters do
		for _ = 1, recipe[1] do
			if recipe[5] > 0 then
				feast = recipe
			else
				table.insert(recipes, recipe)
			end
		end
	end
	for i = #recipes, 2, -1 do
		local j = zrng:NextInteger(1, i)
		recipes[i], recipes[j] = recipes[j], recipes[i]
	end
	local feastCol = zrng:NextInteger(1, 3)
	local cells = {}
	for row = 1, 3 do
		for col = 1, 3 do
			if not (feast and row == 3 and col == feastCol) then
				table.insert(cells, { row = row, col = col })
			end
		end
	end
	for i = #cells, 2, -1 do
		local j = zrng:NextInteger(1, i)
		cells[i], cells[j] = cells[j], cells[i]
	end
	local order = {}
	if feast then
		table.insert(order, { recipe = feast, row = 3, col = feastCol })
	end
	for i, recipe in recipes do
		if cells[i] then
			table.insert(order, { recipe = recipe, row = cells[i].row, col = cells[i].col })
		end
	end

	local x0, x1 = -MAP.Half + 14, MAP.Half - 14
	local zNear = zone.z0 - LAYOUT.Margin
	-- En la última zona queda sitio al fondo para la tarta
	local zFar = zone.z1 + (if zone.id == #Config.Zones then 95 else 16)
	local cellW, cellL = (x1 - x0) / 3, (zNear - zFar) / 3
	local slots = {}
	for _, entry in order do
		local recipe = entry.recipe
		local items = {}
		for slot = 1, 3 do
			for _ = 1, recipe[slot + 1] do
				table.insert(items, { def = defs[slot], radius = radiusOf[defs[slot].id] or 3, jefa = false })
			end
		end
		for _ = 1, recipe[5] do
			table.insert(items, { def = defs[3], radius = (radiusOf[defs[3].id] or 3) * LAYOUT.JefaScale, jefa = true })
		end
		local cx = x0 + (entry.col - 0.5) * cellW + zrng:NextNumber(-6, 6)
		local cz = zNear - (entry.row - 0.5) * cellL + zrng:NextNumber(-6, 6)
		for _, placed in packCluster(items, zrng) do
			local x = math.clamp(cx + placed.offset.X, x0, x1)
			local z = math.clamp(cz + placed.offset.Y, zFar, zNear)
			table.insert(slots, { def = placed.item.def, pos = Vector3.new(x, Config.GroundY, z), jefa = placed.item.jefa })
		end
	end
	return slots
end

-- Centros de racimo del jardín: la mitad en la media luna de los hormigueros
local function layoutGarden()
	local grng = Random.new(4242)
	gardenCenters = {}
	for i = 1, LAYOUT.GardenClusters do
		local nearHills = i % 2 == 0
		for _ = 1, 40 do
			local angle, r
			if nearHills then
				angle = math.rad(grng:NextNumber(MAP.HillFrom - 12, MAP.HillTo + 12))
				r = grng:NextNumber(MAP.HillArc - 50, MAP.LobbyRadius - 16)
			else
				angle = grng:NextNumber(0, math.pi * 2)
				-- sqrt reparte uniforme en el disco en vez de amontonar hacia el centro
				r = math.sqrt(grng:NextNumber()) * (MAP.LobbyRadius - 16)
			end
			local spot = Vector3.new(math.cos(angle) * r, Config.GroundY, math.sin(angle) * r)
			local clear = inLobby(spot)
			for _, other in gardenCenters do
				if (other - spot).Magnitude < LAYOUT.GardenSpread * 2 + 6 then
					clear = false
					break
				end
			end
			if clear then
				table.insert(gardenCenters, spot)
				break
			end
		end
	end
end

-- Comida dorada: piezas teñidas de oro, una luz suave y unas chispas, para verla de lejos.
-- La luz y las chispas van en la primera pieza, que es la última en caer.
local GOLD = Color3.fromRGB(255, 196, 40)

local function gild(model: Model, pieces: { BasePart })
	model:SetAttribute("Golden", true)
	model:SetAttribute("Color", GOLD)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Color = child.Color:Lerp(GOLD, 0.8)
			child.Material = Enum.Material.SmoothPlastic
			child.Reflectance = 0.15
		end
	end
	local core = pieces[1] or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if core then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 214, 110)
		light.Range = 14
		light.Brightness = 1.6
		light.Shadows = false
		light.Parent = core
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 236, 140)
		sparkles.Parent = core
	end
end

-- Probabilidad de que una comida salga dorada (la fija PlayerService según quién esté conectado)
FoodService.goldChance = function(): number
	return Config.GoldFood.Chance
end

-- opts (opcional): spot (sitio fijo), plain (nunca dorada), noRespawn (al acabarse no vuelve),
-- slot (su sitio en un racimo del camino: sale ahí y, si es la jefa del banquete, más grande y con más vida)
local function spawnFood(def, opts: any?): Model
	local model = FoodModels.build(def)
	local slot: Slot? = opts and opts.slot
	local spot = (opts and opts.spot) or (slot and slot.pos) or freeSpot(def, model:GetAttribute("Radius") :: number)
	model:PivotTo(CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	if slot and slot.jefa then
		-- La jefa del banquete: la grande de la zona, más grande y con JefaHp veces su vida
		local radius = (model:GetAttribute("Radius") :: number?) or 3
		local ok = pcall(function()
			model:ScaleTo(model:GetScale() * LAYOUT.JefaScale)
		end)
		if ok then
			model:SetAttribute("Radius", radius * LAYOUT.JefaScale)
		end
		model:SetAttribute("MaxHp", def.hp * LAYOUT.JefaHp)
		model:SetAttribute("Hp", def.hp * LAYOUT.JefaHp)
		model:SetAttribute("Jefa", true)
	end
	if slot then
		slotOf[model] = slot
	end
	local golden = not def.boss and not (opts and opts.plain) and rng:NextNumber() < FoodService.goldChance()
	if opts and opts.noRespawn then
		model:SetAttribute("NoRespawn", true)
	end

	local pieces = {}
	for _, child in model:GetChildren() do
		if child:GetAttribute("Order") then
			table.insert(pieces, child)
		end
	end
	table.sort(pieces, function(a, b)
		return (a:GetAttribute("Order") :: number) < (b:GetAttribute("Order") :: number)
	end)

	if golden then
		gild(model, pieces)
	end

	foods[model] = pieces
	alive += 1
	model.Parent = container
	return model
end

-- Una comida deja de estar viva (comida, quitada o destruida)
local function forget(food: Model)
	if foods[food] then
		foods[food] = nil
		alive -= 1
	end
	slotOf[food] = nil
end

-- Vuelve a salir pasado `delay`; si tenía sitio en un racimo, en ese mismo sitio (un pelo movida)
local function respawnLater(def, delay: number, slot: Slot?)
	pending[def.id] = (pending[def.id] or 0) + 1
	task.delay(delay, function()
		pending[def.id] -= 1
		if slot then
			local nudge = Vector3.new(rng:NextNumber(-0.8, 0.8), 0, rng:NextNumber(-0.8, 0.8))
			local ok, err = pcall(spawnFood, def, { slot = slot, spot = slot.pos + nudge })
			if not ok then
				warn("[CRUNCH!] No se pudo crear", def.id, err)
			end
		else
			local ok, err = pcall(spawnFood, def)
			if not ok then
				warn("[CRUNCH!] No se pudo crear", def.id, err)
			end
		end
	end)
end

function FoodService.start(centers: { Vector3 })
	hillCenters = centers
	container = Instance.new("Model")
	container.Name = "Food"

	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(20, 16, 16)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = container

	container.Parent = Workspace

	-- Radio de cada comida, para colocar los racimos antes de construirlos
	for _, def in Config.Foods do
		local ok, probe = pcall(FoodModels.build, def)
		if ok and probe then
			radiusOf[def.id] = (probe:GetAttribute("Radius") :: number?) or 3
			probe:Destroy()
		end
	end
	layoutGarden()
	for _, zone in Config.Zones do
		if zone.id > 1 then
			slotsByZone[zone.id] = layoutZone(zone)
		end
	end

	for _, def in Config.Foods do
		if def.zone == 1 or def.boss then
			for _ = 1, def.count do
				local ok, err = pcall(spawnFood, def)
				if not ok then
					warn("[CRUNCH!] No se pudo crear", def.id, err)
					break
				end
			end
			task.wait()
		end
	end
	for zoneId = 2, #Config.Zones do
		for _, slot in slotsByZone[zoneId] or {} do
			local ok, err = pcall(spawnFood, slot.def, { slot = slot })
			if not ok then
				warn("[CRUNCH!] No se pudo crear", slot.def.id, err)
			end
		end
		task.wait()
	end
end

-- Modelos de comida vivos ahora mismo (tope: Config.FoodLayout.MaxModels)
function FoodService.count(): number
	return alive
end

FoodService.onFinished = function(_def, _food) end -- lo sustituye quien quiera enterarse

function FoodService.isFood(instance: any): boolean
	return typeof(instance) == "Instance" and foods[instance] ~= nil
end

-- FoodId se pone una sola vez al construir la comida (FoodModels): se recuerda por modelo, porque
-- la colonia y las aliadas lo preguntan para cada comida del mapa varias veces por segundo
local defCache: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any
function FoodService.defOf(food: Model)
	local def = defCache[food]
	if def == nil then
		def = Config.FoodById[food:GetAttribute("FoodId") :: string] or false
		defCache[food] = def
	end
	return def or nil
end

function FoodService.list()
	return foods
end

function FoodService.isGolden(food: Model): boolean
	return food:GetAttribute("Golden") == true
end

-- Crea una comida ahora (el módulo Garden: más comida con más gente, rellenos y eventos).
-- opts como en spawnFood. Devuelve el modelo o nil si falló o si ya hay Config.FoodLayout.MaxModels.
function FoodService.spawn(def, opts: any?): Model?
	if alive >= LAYOUT.MaxModels then
		-- Recuento de verdad por si algún módulo destruyó comida sin pasar por FoodService.remove
		alive = 0
		for food in foods do
			if food.Parent then
				alive += 1
			else
				foods[food] = nil
				slotOf[food] = nil
			end
		end
		if alive >= LAYOUT.MaxModels then
			return nil
		end
	end
	local ok, result = pcall(spawnFood, def, opts)
	if not ok then
		warn("[CRUNCH!] No se pudo crear", def.id, result)
		return nil
	end
	return result
end

-- Reapariciones de esa comida que aún no han llegado
function FoodService.pending(id: string): number
	return pending[id] or 0
end

-- Quita una comida sin que vuelva (comida de un evento que se acabó el tiempo)
function FoodService.remove(food: Model)
	if foods[food] then
		forget(food)
		food:Destroy()
	end
end

-- Si en ese punto del jardín puede salir comida (lejos de hormigueros, cartel y juguetes)
function FoodService.spotOk(spot: Vector3): boolean
	return inLobby(spot)
end

-- Lo que vale cada trozo de esta comida para una jugadora con estas estadísticas: su valor, el
-- paladar de su zona y, si es dorada, el multiplicador dorado de esa jugadora. Toda la comida que
-- se acredita (mordiscos, aliadas, obreras) pasa por aquí. Llámalo antes de dañarla.
function FoodService.pieceValue(food: Model, def, stats): number
	local value = def.value * (stats.zoneMult[def.zone] or 1)
	if food:GetAttribute("Golden") == true then
		value *= stats.goldFoodMult or Config.GoldFood.Mult
	end
	if FoodService.valueHook then
		value = FoodService.valueHook(food, def, stats, value) -- hora feliz y pan gigante (Garden)
	end
	return value
end

-- Quita hasta `amount` de vida. Devuelve (trozos arrancados, definición, si se acabó).
function FoodService.damage(food: Model, amount: number)
	local pieces = foods[food]
	local def = FoodService.defOf(food)
	if not pieces or not def or amount <= 0 then
		return 0, def, false
	end

	local hp = food:GetAttribute("Hp") :: number
	local taken = math.min(amount, hp)
	hp -= taken
	food:SetAttribute("Hp", hp)

	if hp <= 0 then
		local again = food:GetAttribute("NoRespawn") ~= true
		local slot = slotOf[food]
		forget(food)
		food:Destroy()
		if again then
			local delay = if slot and slot.jefa then LAYOUT.JefaRespawn else FoodService.respawnDelay(def)
			if delay then
				respawnLater(def, delay, slot)
			end
		end
		FoodService.onFinished(def, food)
		return taken, def, true
	end

	-- MaxHp: la comida gigante (módulo Extras) tiene más vida que su definición
	local keep = math.ceil(#pieces * hp / ((food:GetAttribute("MaxHp") :: number?) or def.hp))
	for i = #pieces, keep + 1, -1 do
		pieces[i]:Destroy()
		pieces[i] = nil
	end
	return taken, def, false
end

-- La comida viva más cercana a `position` que cumpla `accept`.
function FoodService.nearest(position: Vector3, maxDistance: number, accept: (Model, any) -> boolean): Model?
	local best: Model? = nil
	local bestDistance = maxDistance
	for food in foods do
		local def = FoodService.defOf(food)
		if accept(food, def) then
			local distance = (food:GetPivot().Position - position).Magnitude
			if distance < bestDistance then
				best = food
				bestDistance = distance
			end
		end
	end
	return best
end

return FoodService
