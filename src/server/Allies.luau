-- Aliadas: la quinta rama del árbol. Bichos y cachivaches que trabajan contigo:
--   abeja mensajera (se lleva tu carga a casa), imán de migas, escarabajo de carga (solo estadística),
--   escolta (muerde lo que muerdes), pisotón y tirachinas (habilidades activas), lupa solar y mega crunch.
-- Aquí se decide todo (daño, comida, enfriamientos); los clientes solo dibujan lo que se les cuenta
-- por el remoto "Allies". Nada corre cada fotograma: un bucle de TICK segundos y algún task.delay.
--
-- Remoto "Allies" (servidor -> todos): "Bee", "Magnet", "Escort", "Stomp", "Sling", "Lens", "Mega"
-- (servidor -> dueña): "Delivered", "LensBurn", "Full". (Cliente -> servidor): "Stomp", "Sling".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local PlayerService = require(script.Parent.PlayerService)
local Profiles = require(script.Parent.Profiles)

local Allies = {}

local A = Config.Allies
local TICK = 0.2
local FLAT = Vector3.new(1, 0, 1)

local remote: RemoteEvent
local states: { [Player]: any } = {}

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local function edgeDistance(from: Vector3, food: Model): number
	return ((food:GetPivot().Position - from) * FLAT).Magnitude - ((food:GetAttribute("Radius") :: number?) or 0)
end

-- Estado de cada jugadora. Si el perfil cambió (volvió a entrar), se empieza de cero.
local function stateOf(profile)
	local s = states[profile.player]
	if not s or s.profile ~= profile then
		s = {
			profile = profile,
			beeReadyAt = 0,
			beeBusy = false,
			magnetAt = 0,
			escortAt = 0,
			lensAt = 0,
			lastFood = nil :: Model?,
			lastBiteAt = -math.huge,
			chain = 0,
			stompReadyAt = 0,
			slingReadyAt = 0,
		}
		states[profile.player] = s
	end
	return s
end

-- Sigue siendo la misma partida de la misma jugadora (no se fue ni enjambró)
local function current(profile, runId: number): boolean
	return Profiles.get(profile.player) == profile and profile.data.rebirths == runId
end

local function hillTop(profile): Vector3
	return profile.hill:GetPivot().Position + Vector3.new(0, 9 * profile.stats.hillScale, 0)
end

local function nearHome(profile, position: Vector3, margin: number): boolean
	local center = profile.hill:GetPivot().Position
	return ((center - position) * FLAT).Magnitude <= Config.Anthill.DepositRadius * profile.stats.hillScale + margin
end

-- Entrega a distancia (abeja o tirachinas): la misma cuenta que a pie, con sus sucesos.
local function deliver(profile, carry: number, carryValue: number, runId: number)
	if carry <= 0 or not current(profile, runId) or not profile.hill then
		return
	end
	local credited, full, doubled = PlayerService.credit(profile, carry, carryValue)
	Profiles.push(profile)
	remote:FireClient(profile.player, "Delivered", hillTop(profile), credited, doubled, full)
end

-- Quita la carga entera a la jugadora. Devuelve (trozos, valor).
local function grabLoad(profile): (number, number)
	local carry, value = profile.carry, profile.carryValue
	profile.carry = 0
	profile.carryValue = 0
	PlayerService.refreshCarry(profile)
	return carry, value
end

-- Comida que te dejan morder (puerta abierta y, si es dura, con sierra)
local function edible(stats, def): boolean
	return def.zone <= stats.depth and (not def.hard or stats.canBiteHard)
end

---------------------------------------------------------------------------------------------------
-- Abeja mensajera

local function updateBee(profile, s, now: number, root: BasePart)
	local stats = profile.stats
	if stats.beeInterval <= 0 or s.beeBusy or not profile.hill or profile.carry <= 0 then
		return
	end
	local full = profile.carry >= stats.capacity
	local ready = (now >= s.beeReadyAt and profile.carry >= stats.capacity * A.Bee.MinLoad) or (stats.beeOnFull and full)
	if not ready or nearHome(profile, root.Position, 6) then
		return
	end

	local player = profile.player
	local runId = profile.data.rebirths
	local target = hillTop(profile)
	local distance = ((target - root.Position) * FLAT).Magnitude
	local fly = math.max(distance / math.max(stats.beeSpeed, 1), A.Bee.MinFly)
	local approach = A.Bee.Approach
	s.beeBusy = true
	s.beeReadyAt = now + stats.beeInterval
	remote:FireAllClients("Bee", player, target, approach, fly, profile.carryColor)

	-- La abeja llega, coge lo que lleves en ese momento y se va
	task.delay(approach, function()
		if not current(profile, runId) then
			return
		end
		local carry, value = grabLoad(profile)
		task.delay(fly, deliver, profile, carry, value, runId)
	end)
	task.delay(approach + fly * 2 + 0.3, function()
		s.beeBusy = false
	end)
end

---------------------------------------------------------------------------------------------------
-- Imán de migas

local function updateMagnet(profile, s, now: number, root: BasePart)
	local stats = profile.stats
	if stats.magnetRadius <= 0 or now < s.magnetAt or profile.carry >= stats.capacity then
		return
	end
	s.magnetAt = now + A.Magnet.Tick
	local limit = stats.biteDamage * A.Magnet.Bites
	local found = {}
	for food in FoodService.list() do
		local def = FoodService.defOf(food)
		local hp = food:GetAttribute("Hp")
		if def and not def.boss and type(hp) == "number" and hp <= limit and edible(stats, def) then
			local distance = edgeDistance(root.Position, food)
			if distance <= stats.magnetRadius then
				table.insert(found, { food = food, distance = distance, hp = hp })
			end
		end
	end
	if #found == 0 then
		return
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	local changed = false
	for i = 1, math.min(#found, A.Magnet.Count) do
		local item = found[i]
		local position = item.food:GetPivot().Position
		local color = item.food:GetAttribute("Color")
		local taken = PlayerService.take(profile, item.food, item.hp)
		if taken > 0 then
			changed = true
			remote:FireAllClients("Magnet", profile.player, position, color)
		end
		if profile.carry >= stats.capacity then
			break
		end
	end
	if changed then
		PlayerService.refreshCarry(profile)
	end
end

---------------------------------------------------------------------------------------------------
-- Escolta: mientras muerdes, tus soldados muerden lo mismo

local function updateEscort(profile, s, now: number, root: BasePart)
	local stats = profile.stats
	local food = s.lastFood
	if stats.escorts <= 0 or now < s.escortAt or now - s.lastBiteAt > A.Escort.Linger then
		return
	end
	if not food or not FoodService.isFood(food) or profile.carry >= stats.capacity then
		return
	end
	if edgeDistance(root.Position, food) > stats.biteRange + 6 then
		return
	end
	s.escortAt = now + A.Escort.Tick
	local def = FoodService.defOf(food)
	-- (neighborScale: lo que muerde por ti a las vecinas no pasa de Config.Player.NeighborCap)
	local damage = stats.biteDamage * A.Escort.Share * stats.escorts * (stats.neighborScale or 1) * (if def.hard then stats.hardMult else 1)
	local position = food:GetPivot().Position
	local radius = food:GetAttribute("Radius")
	local color = food:GetAttribute("Color")
	local taken = PlayerService.take(profile, food, damage)
	if taken > 0 then
		PlayerService.refreshCarry(profile)
		remote:FireAllClients("Escort", profile.player, position, radius, color)
	end
end

---------------------------------------------------------------------------------------------------
-- Lupa solar: quema un trozo de la comida más grande que tengas cerca; ese trozo va directo a casa

local function burn(profile, food: Model, runId: number)
	if not current(profile, runId) or not FoodService.isFood(food) then
		return
	end
	local stats = profile.stats
	local def = FoodService.defOf(food)
	if not edible(stats, def) or stats.lensMult <= 0 then
		return
	end
	local position = food:GetPivot().Position
	local piece = FoodService.pieceValue(food, def, stats) -- antes de dañarla: puede desaparecer
	-- Como todo lo que muerde por ti, pega con tu mordida media (Stats.harvest)
	local taken, _, finished = FoodService.damage(food, math.ceil(stats.biteDamage * (stats.harvest or 1) * stats.lensMult))
	if taken <= 0 then
		return
	end
	local credited = Profiles.addFood(profile, taken * piece)
	Profiles.trackFood(profile, def, taken)
	Events.fire("Ate", profile, def, taken, false)
	if finished then
		Profiles.awardTrophy(profile, def)
		Events.fire("Finished", profile, def)
	end
	Profiles.push(profile)
	remote:FireClient(profile.player, "LensBurn", position, credited)
end

local function updateLens(profile, s, now: number, root: BasePart)
	local stats = profile.stats
	if stats.lensInterval <= 0 or now < s.lensAt then
		return
	end
	local best: Model? = nil
	local bestHp = 0
	for food in FoodService.list() do
		local def = FoodService.defOf(food)
		local hp = food:GetAttribute("Hp")
		if def and type(hp) == "number" and hp > bestHp and edible(stats, def) and edgeDistance(root.Position, food) <= A.Lens.Radius then
			best = food
			bestHp = hp
		end
	end
	if not best then
		s.lensAt = now + 1.5 -- nada a tiro: vuelve a mirar en un momento
		return
	end
	s.lensAt = now + stats.lensInterval
	remote:FireAllClients("Lens", profile.player, best:GetPivot().Position, best:GetAttribute("Radius"), A.Lens.Delay)
	task.delay(A.Lens.Delay, burn, profile, best, profile.data.rebirths)
end

---------------------------------------------------------------------------------------------------
-- Mega crunch: cada megaEvery mordiscos seguidos, uno gigante que salpica alrededor

local function onBite(profile, food: Model, chained: boolean)
	local s = stateOf(profile)
	s.lastFood = food
	s.lastBiteAt = os.clock()
	local stats = profile.stats
	if stats.megaEvery <= 0 then
		s.chain = 0
		return
	end
	s.chain = if chained then s.chain + 1 else 1
	if s.chain < stats.megaEvery or not FoodService.isFood(food) then
		return
	end
	s.chain = 0
	local center = food:GetPivot().Position
	local damage = stats.biteDamage * stats.megaMult * (stats.neighborScale or 1)
	local def = FoodService.defOf(food)
	local total = PlayerService.take(profile, food, damage * (if def.hard then stats.hardMult else 1))
	local nearby = {}
	for other in FoodService.list() do
		if other ~= food and edgeDistance(center, other) <= A.Mega.Radius then
			table.insert(nearby, other)
		end
	end
	for _, other in nearby do
		if profile.carry >= stats.capacity then
			break
		end
		total += PlayerService.take(profile, other, damage * 0.5)
	end
	PlayerService.refreshCarry(profile)
	remote:FireAllClients("Mega", profile.player, center + Vector3.new(0, 1, 0), total)
end

---------------------------------------------------------------------------------------------------
-- Habilidades activas

local function onStomp(profile, s, root: BasePart)
	local stats = profile.stats
	local now = Workspace:GetServerTimeNow()
	if stats.stompCooldown <= 0 or now < s.stompReadyAt then
		return
	end
	if profile.carry >= stats.capacity then
		remote:FireClient(profile.player, "Full")
		return
	end
	s.stompReadyAt = now + stats.stompCooldown
	profile.player:SetAttribute("StompReadyAt", s.stompReadyAt)

	local center = root.Position
	local hit = {}
	for food in FoodService.list() do
		local distance = edgeDistance(center, food)
		if distance <= stats.stompRadius then
			table.insert(hit, { food = food, distance = distance })
		end
	end
	table.sort(hit, function(a, b)
		return a.distance < b.distance
	end)
	local damage = stats.biteDamage * (stats.harvest or 1) * A.Stomp.Mult -- con tu mordida media (Stats.harvest)
	local total = 0
	for _, item in hit do
		if profile.carry >= stats.capacity then
			break
		end
		local def = FoodService.defOf(item.food)
		total += PlayerService.take(profile, item.food, damage * (if def and def.hard then stats.hardMult else 1))
	end
	PlayerService.refreshCarry(profile)
	remote:FireAllClients("Stomp", profile.player, center, stats.stompRadius, total)
end

local function onSling(profile, s, root: BasePart)
	local stats = profile.stats
	local now = Workspace:GetServerTimeNow()
	if stats.slingCooldown <= 0 or now < s.slingReadyAt or profile.carry <= 0 or not profile.hill then
		return
	end
	if nearHome(profile, root.Position, 0) then
		return -- ya estás en casa: se entrega sola
	end
	local target = hillTop(profile)
	local distance = ((target - root.Position) * FLAT).Magnitude
	if distance > stats.slingRange then
		Profiles.say(profile, "Mi hormiguero está demasiado lejos para lanzar", 2.5)
		return
	end
	s.slingReadyAt = now + stats.slingCooldown
	profile.player:SetAttribute("SlingReadyAt", s.slingReadyAt)
	local share = math.clamp(profile.carry / math.max(stats.capacity, 1), 0, 1)
	local color = profile.carryColor
	local runId = profile.data.rebirths
	local carry, value = grabLoad(profile)
	local fly = math.min(A.Sling.FlyTime + distance / 800, 3.5)
	remote:FireAllClients("Sling", profile.player, root.Position + Vector3.new(0, 2, 0), target, fly, color, share)
	task.delay(fly, deliver, profile, carry, value, runId)
end

local function onRequest(player: Player, action: any)
	local profile = Profiles.get(player)
	local root = getRoot(player)
	if not profile or not root or not profile.stats then
		return
	end
	local s = stateOf(profile)
	if action == "Stomp" then
		onStomp(profile, s, root)
	elseif action == "Sling" then
		onSling(profile, s, root)
	end
end

---------------------------------------------------------------------------------------------------

local function tick()
	for player, s in states do
		if Profiles.get(player) ~= s.profile then
			states[player] = nil
		end
	end
	local now = os.clock()
	for player, profile in Profiles.all() do
		local stats = profile.stats
		if not stats then
			continue
		end
		local root = getRoot(player)
		if not root then
			continue
		end
		local s = stateOf(profile)
		updateBee(profile, s, now, root)
		updateMagnet(profile, s, now, root)
		updateEscort(profile, s, now, root)
		updateLens(profile, s, now, root)
	end
end

function Allies.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Allies"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	Events.on("Bite", onBite)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[CRUNCH!] Aliadas:", err)
			end
		end
	end)
end

return Allies
