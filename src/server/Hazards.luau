-- Peligros ligeros: nunca matan, solo te quitan la carga.
-- Araña (Jungla) y cangrejo (Playa) patrullan su zona y persiguen a quien lleva comida.
-- Pisotón (Picnic y Cocina): un zapato o un rodillo gigante cae donde sale la comida.
-- El servidor solo lleva la posición lógica (10 veces por segundo) y la publica; los clientes
-- dibujan y suavizan los modelos.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Profiles = require(script.Parent.Profiles)

local Hazards = {}

local TICK = 0.1
local PATROL_SPEED = 12
local CHASE_SPEED = 17
local SEE = 26
local CHASE_TIME = 5
local REST = 2.5 -- tras perseguir o robar, un respiro antes de volver a fijarse en nadie
local CONTACT = 4.5
local IMMUNE = 6
local GATE_GAP = 30
local KNOCK = 55
local KNOCK_UP = 32

local STOMP_MIN, STOMP_MAX = 20, 35
local STOMP_WARN = 2.2
local STOMP_RADIUS = 10
local STOMP_AIM = 0.6 -- probabilidad de apuntar cerca de un jugador

local FLAT = Vector3.new(1, 0, 1)
local GROUND = Config.GroundY
local HALF = Config.Map.Half
local FOOD_HALF = HALF - 14 -- donde salen los racimos (FoodService)

local rng = Random.new()
local remote: RemoteEvent
local posRemote: UnreliableRemoteEvent
local listening = {} :: { [Player]: true } -- clientes que ya conectaron HazardPos (avisan con "Ready")
local immuneUntil: { [Player]: number } = {}
local creatures = {}

local function zoneByTheme(theme: string)
	for _, zone in Config.Zones do
		if zone.theme == theme then
			return zone
		end
	end
	return nil
end

-- Límites de una zona: de su puerta a la de la siguiente.
local function areaOf(zone)
	local nextZone = Config.Zones[zone.id + 1]
	local near = zone.z0 + 10
	local far = if nextZone then nextZone.z0 + 10 else zone.z1
	return {
		zone = zone,
		inNear = near,
		inFar = far,
		walkNear = near - GATE_GAP,
		walkFar = far + GATE_GAP,
		foodNear = zone.z0 - Config.FoodLayout.Margin,
		foodFar = zone.z1 + 14,
	}
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Jugadores que ya pueden entrar en la zona y están dentro ahora mismo.
local function playersIn(area)
	local list = {}
	for player, profile in Profiles.all() do
		if profile.data.depth < area.zone.id then
			continue
		end
		local root = rootOf(player)
		if not root then
			continue
		end
		local p = root.Position
		if p.Y > GROUND - 20 and p.Y < GROUND + 40 and math.abs(p.X) <= HALF + 2 and p.Z <= area.inNear and p.Z >= area.inFar then
			table.insert(list, { player = player, profile = profile, root = root })
		end
	end
	return list
end

local function dropLoad(profile)
	profile.carry = 0
	profile.carryValue = 0
	Profiles.push(profile)
	local character = profile.player.Character
	local chunk = character and character:FindFirstChild("CarryChunk")
	if chunk then
		chunk:Destroy()
	end
end

local function flatDistance(a: Vector3, b: Vector3): number
	return ((a - b) * FLAT).Magnitude
end

------------------------------------------------------------------------------------------
-- Bichos que patrullan
------------------------------------------------------------------------------------------

local function newCreature(kind: string, zone)
	local area = areaOf(zone)
	local mid = (area.walkNear + area.walkFar) / 2
	local rz = (area.walkNear - area.walkFar) / 2 - 6
	local rx = HALF - 26
	-- Un óvalo algo torcido por el centro de la zona
	local points = {}
	local count = 10
	for i = 1, count do
		local angle = (i - 1) / count * math.pi * 2
		local wobble = 1 + rng:NextNumber(-0.18, 0.05)
		table.insert(points, Vector3.new(math.cos(angle) * rx * wobble, GROUND, mid + math.sin(angle) * rz * wobble))
	end
	return {
		id = zone.id,
		kind = kind,
		area = area,
		points = points,
		next = 2,
		pos = points[1],
		yaw = 0,
		mode = "patrol",
		target = nil :: Player?,
		chaseUntil = 0,
		restUntil = 0,
	}
end

local function clampWalk(creature, p: Vector3): Vector3
	local area = creature.area
	local half = HALF - 4
	return Vector3.new(math.clamp(p.X, -half, half), GROUND, math.clamp(p.Z, area.walkFar, area.walkNear))
end

-- Avanza hacia `goal`. Devuelve la distancia que falta.
local function stepToward(creature, goal: Vector3, speed: number, dt: number): number
	local delta = (goal - creature.pos) * FLAT
	local distance = delta.Magnitude
	if distance < 0.05 then
		return 0
	end
	local direction = delta / distance
	local move = math.min(distance, speed * dt)
	creature.pos += direction * move
	creature.yaw = math.atan2(-direction.X, -direction.Z) -- el frente del modelo es -Z
	return distance - move
end

local function nearestPoint(creature): number
	local best, bestDistance = 1, math.huge
	for i, point in creature.points do
		local distance = flatDistance(point, creature.pos)
		if distance < bestDistance then
			best, bestDistance = i, distance
		end
	end
	return best
end

local function calmDown(creature, now: number)
	creature.mode = "patrol"
	creature.target = nil
	creature.restUntil = now + REST
	creature.next = nearestPoint(creature)
end

local function steal(creature, entry)
	dropLoad(entry.profile)
	immuneUntil[entry.player] = os.clock() + IMMUNE
	local away = (entry.root.Position - creature.pos) * FLAT
	away = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	local knock = away * KNOCK + Vector3.new(0, KNOCK_UP, 0)
	-- La raíz es del cliente: él también aplica el empujón al recibir el aviso
	entry.root.AssemblyLinearVelocity = knock
	remote:FireAllClients("Stolen", entry.player.UserId, creature.id, entry.root.Position, knock)
end

local function canBeRobbed(entry, now: number): boolean
	return entry.profile.carry > 0 and (immuneUntil[entry.player] or 0) <= now
end

local function updateCreature(creature, dt: number, now: number)
	local nearby = playersIn(creature.area)

	-- Contacto: le roba a cualquiera con carga que se deje tocar
	for _, entry in nearby do
		if canBeRobbed(entry, now) and flatDistance(entry.root.Position, creature.pos) <= CONTACT then
			steal(creature, entry)
			calmDown(creature, now)
			creature.happyUntil = now + 1
			return
		end
	end

	if creature.mode == "chase" then
		local chased = nil
		for _, entry in nearby do
			if entry.player == creature.target then
				chased = entry
				break
			end
		end
		if not chased or not canBeRobbed(chased, now) or now > creature.chaseUntil then
			calmDown(creature, now)
		else
			stepToward(creature, clampWalk(creature, chased.root.Position), CHASE_SPEED, dt)
			return
		end
	elseif now >= creature.restUntil then
		local best, bestDistance = nil, SEE
		for _, entry in nearby do
			local distance = flatDistance(entry.root.Position, creature.pos)
			if canBeRobbed(entry, now) and distance <= bestDistance then
				best, bestDistance = entry, distance
			end
		end
		if best then
			creature.mode = "chase"
			creature.target = best.player
			creature.chaseUntil = now + CHASE_TIME
			stepToward(creature, clampWalk(creature, best.root.Position), CHASE_SPEED, dt)
			return
		end
	end

	local left = stepToward(creature, creature.points[creature.next], PATROL_SPEED, dt)
	if left < 1 then
		creature.next = creature.next % #creature.points + 1
	end
end

local function creatureLoop()
	local last = os.clock()
	local lastErr, lastAt = nil, 0
	while true do
		task.wait(TICK)
		local now = os.clock()
		local dt = math.min(now - last, 0.3)
		last = now
		local packet = {}
		for _, creature in creatures do
			local ok, err = pcall(updateCreature, creature, dt, now)
			if not ok and (err ~= lastErr or now - lastAt > 10) then
				lastErr, lastAt = err, now
				warn("[CRUNCH!] Peligros:", err)
			end
			table.insert(packet, {
				creature.id,
				creature.kind,
				math.floor(creature.pos.X * 10 + 0.5) / 10,
				math.floor(creature.pos.Z * 10 + 0.5) / 10,
				math.floor(creature.yaw * 100 + 0.5) / 100,
				creature.mode == "chase",
				(creature.happyUntil or 0) > now,
			})
		end
		-- Solo a quien ya escucha: a un cliente que aún carga, Roblox le tira el paquete con un aviso
		for player in listening do
			posRemote:FireClient(player, packet)
		end
	end
end

------------------------------------------------------------------------------------------
-- Pisotones
------------------------------------------------------------------------------------------

local function stompLoop(kind: string, zone)
	local area = areaOf(zone)
	local lastTarget: Player? = nil
	while true do
		task.wait(rng:NextNumber(STOMP_MIN, STOMP_MAX))
		local inside = playersIn(area)
		if #inside == 0 then
			continue -- nadie lo vería: se ahorra
		end

		local candidates = {}
		for _, entry in inside do
			if entry.player ~= lastTarget then
				table.insert(candidates, entry)
			end
		end
		local spot
		if #candidates > 0 and rng:NextNumber() < STOMP_AIM then
			local pick = candidates[rng:NextInteger(1, #candidates)]
			lastTarget = pick.player
			local angle = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(0, 5)
			spot = pick.root.Position + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		else
			lastTarget = nil
			spot = Vector3.new(rng:NextNumber(-FOOD_HALF, FOOD_HALF), GROUND, rng:NextNumber(area.foodFar, area.foodNear))
		end
		spot = Vector3.new(math.clamp(spot.X, -FOOD_HALF, FOOD_HALF), GROUND, math.clamp(spot.Z, area.foodFar, area.foodNear))

		remote:FireAllClients("Stomp", {
			zone = zone.id,
			kind = kind,
			pos = spot,
			hitAt = Workspace:GetServerTimeNow() + STOMP_WARN,
			warn = STOMP_WARN,
			radius = STOMP_RADIUS,
		})
		task.wait(STOMP_WARN)

		local hit, lost = {}, {}
		for _, entry in playersIn(area) do
			local p = entry.root.Position
			if flatDistance(p, spot) <= STOMP_RADIUS + 1 and p.Y < GROUND + 14 then
				table.insert(hit, entry.player.UserId)
				if entry.profile.carry > 0 then
					dropLoad(entry.profile)
					table.insert(lost, entry.player.UserId)
				end
			end
		end
		remote:FireAllClients("Plaf", { zone = zone.id, pos = spot, hit = hit, lost = lost })
	end
end

function Hazards.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Hazard"
	remote.Parent = remotes
	posRemote = Instance.new("UnreliableRemoteEvent")
	posRemote.Name = "HazardPos"
	posRemote.Parent = remotes
	remote.OnServerEvent:Connect(function(player, kind)
		if kind == "Ready" and player.Parent then
			listening[player] = true
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		listening[player] = nil
		immuneUntil[player] = nil
	end)

	for _, entry in { { "arana", "Jungla" }, { "cangrejo", "Mar" } } do
		local zone = zoneByTheme(entry[2])
		if zone then
			table.insert(creatures, newCreature(entry[1], zone))
		end
	end
	task.spawn(creatureLoop)

	for _, entry in { { "zapato", "Picnic" }, { "rodillo", "Cocina" } } do
		local zone = zoneByTheme(entry[2])
		if zone then
			task.spawn(stompLoop, entry[1], zone)
		end
	end
end

return Hazards
