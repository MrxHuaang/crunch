-- Crea la comida del jardín, lleva su vida, le quita piezas al comerla y la hace reaparecer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)

local FoodService = {}

local container: Model
local rng = Random.new()
local foods: { [Model]: { BasePart } } = {} -- comida viva -> sus piezas en orden

local MAP = Config.Map
local NEAR_HILLS = 0.5 -- parte de la comida del jardín que sale cerca de los hormigueros (tools/sim.py)
local hillCenters: { Vector3 } = {}

local function inLobby(spot: Vector3): boolean
	for _, center in hillCenters do
		if (center - spot).Magnitude < 34 then
			return false
		end
	end
	-- Ni encima de la tabla de puntuaciones ni en la boca del camino
	return (spot - Vector3.new(-0.46 * MAP.LobbyRadius, 0, -0.66 * MAP.LobbyRadius)).Magnitude > 18
end

-- Un punto al azar dentro de la zona de la comida.
local function zoneSpot(def): Vector3
	local zone = Config.Zones[def.zone]
	if def.boss then
		return Vector3.new(0, Config.GroundY, zone.z1 + 42)
	end
	if def.zone == 1 then
		-- La mitad de la comida del jardín sale en la media luna de los hormigueros: así los
		-- primeros viajes son cortos. Nunca dentro de un montículo (lo vigila inLobby).
		local nearHills = rng:NextNumber() < NEAR_HILLS
		for _ = 1, 30 do
			local angle, r
			if nearHills then
				angle = math.rad(rng:NextNumber(MAP.HillFrom - 12, MAP.HillTo + 12))
				r = rng:NextNumber(MAP.HillArc - 50, MAP.LobbyRadius - 12)
			else
				angle = rng:NextNumber(0, math.pi * 2)
				-- sqrt reparte uniforme en el disco en vez de amontonar hacia el centro
				r = math.sqrt(rng:NextNumber()) * (MAP.LobbyRadius - 12)
			end
			local spot = Vector3.new(math.cos(angle) * r, Config.GroundY, math.sin(angle) * r)
			if inLobby(spot) then
				return spot
			end
		end
		return Vector3.new(0, Config.GroundY, 0)
	end
	local last = def.zone == #Config.Zones
	local near = zone.z0 - 14
	local far = zone.z1 + (if last then 84 else 14)
	return Vector3.new(rng:NextNumber(-48, 48), Config.GroundY, rng:NextNumber(far, near))
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

local function spawnFood(def)
	local model = FoodModels.build(def)
	local spot = freeSpot(def, model:GetAttribute("Radius") :: number)
	model:PivotTo(CFrame.new(spot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))

	local pieces = {}
	for _, child in model:GetChildren() do
		if child:GetAttribute("Order") then
			table.insert(pieces, child)
		end
	end
	table.sort(pieces, function(a, b)
		return (a:GetAttribute("Order") :: number) < (b:GetAttribute("Order") :: number)
	end)

	foods[model] = pieces
	model.Parent = container
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

	for _, def in Config.Foods do
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

FoodService.onFinished = function(_def, _food) end -- lo sustituye quien quiera enterarse

function FoodService.isFood(instance: any): boolean
	return typeof(instance) == "Instance" and foods[instance] ~= nil
end

function FoodService.defOf(food: Model)
	return Config.FoodById[food:GetAttribute("FoodId") :: string]
end

function FoodService.list()
	return foods
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
		foods[food] = nil
		food:Destroy()
		task.delay(def.respawn, spawnFood, def)
		FoodService.onFinished(def, food)
		return taken, def, true
	end

	local keep = math.ceil(#pieces * hp / def.hp)
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
