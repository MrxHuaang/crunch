-- Mordida en cadena: cuando tu mordisco termina una comida, un rayo salta a la comida más cercana
-- (a Config.Chain.Range studs) y le arranca First mordiscos tuyos; luego salta otra vez desde allí con
-- Share del anterior,
-- tantas veces como niveles. Lo arrancado entra en tu carga por PlayerService.take (carga, puertas,
-- comida dura y sucesos). Los clientes dibujan el rayo con el suceso Fx "Chain".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local PlayerService = require(script.Parent.PlayerService)

local Chain = {}

local FLAT = Vector3.new(1, 0, 1)
local fxRemote: RemoteEvent

local function edible(stats, def): boolean
	return def ~= nil and def.zone <= stats.depth and (not def.hard or stats.canBiteHard)
end

-- La comida más cercana a `from` (borde a borde) que puedas morder y no haya recibido ya el rayo
local function nextTarget(stats, from: Vector3, visited): Model?
	local best, bestGap = nil, Config.Chain.Range
	for food in FoodService.list() do
		if not visited[food] then
			local def = FoodService.defOf(food)
			if edible(stats, def) then
				local gap = ((food:GetPivot().Position - from) * FLAT).Magnitude - ((food:GetAttribute("Radius") :: number?) or 0)
				if gap < bestGap then
					best, bestGap = food, gap
				end
			end
		end
	end
	return best
end

local function onFinalBite(profile, _food: Model, position: Vector3, damage: number)
	local stats = profile.stats
	local jumps = stats and stats.chainJumps or 0
	if jumps <= 0 or profile.carry >= stats.capacity then
		return
	end
	local points = { position } -- de dónde sale cada tramo del rayo
	local amounts = {}
	local visited = {}
	local from = position
	-- El primer salto arranca Config.Chain.First mordiscos tuyos (no un pedazo del último, que solía
	-- ser una miga); cada salto siguiente, Share del anterior. Stats.chainBites cuenta lo mismo.
	local _ = damage
	local hit = stats.biteDamage * Config.Chain.First / Config.Chain.Share
	for _ = 1, jumps do
		hit *= Config.Chain.Share
		if hit < 1 or profile.carry >= stats.capacity then
			break
		end
		local target = nextTarget(stats, from, visited)
		if not target then
			break
		end
		visited[target] = true
		local def = FoodService.defOf(target)
		local spot = target:GetPivot().Position + Vector3.new(0, 1, 0)
		local taken = PlayerService.take(profile, target, math.ceil(hit * (if def.hard then stats.hardMult else 1)))
		if taken <= 0 then
			break
		end
		table.insert(points, spot)
		table.insert(amounts, taken)
		from = spot
	end
	if #amounts == 0 then
		return
	end
	PlayerService.refreshCarry(profile)
	-- A todos: el rayo se ve en el mundo; los números y el temblor solo los pinta la dueña
	fxRemote:FireAllClients("Chain", profile.player, points, amounts)
end

function Chain.start(remotes: Folder)
	fxRemote = remotes.Fx
	Events.on("FinalBite", onFinalBite)
end

return Chain
