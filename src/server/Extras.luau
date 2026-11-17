-- Mejoras que cambian cómo juegas (no son porcentajes):
--   mordisco cargado (quieta junto a la comida, el siguiente mordisco arranca un pedazo enorme),
--   doble mandíbula (cada mordisco muerde también la comida de al lado), buche (te guardas parte de
--   cada entrega para el siguiente viaje), comida gigante (una comida de tu zona crece) y lluvia
--   propia (habilidad activa).
--   La senda de feromonas es solo del cliente (dibujo y velocidad, como correr): ver src/client/Extras.luau.
-- Aquí se decide todo; los clientes dibujan lo que se les cuenta por el remoto "Extras".
--
-- Remoto "Extras" (servidor -> todos): "Charged", "Jaw", "Giant",
-- "RainCrumb", "RainTaken", "RainGone". (Servidor -> dueña): "Buche". (Cliente -> servidor): "Rain".
-- Atributos: jugadora "RainReadyAt"; comida "Giant" (UserId de quien la hizo crecer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Depots = require(script.Parent.Depots)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local PlayerService = require(script.Parent.PlayerService)
local Profiles = require(script.Parent.Profiles)

local Extras = {}

local X = Config.Extras
local TICK = 0.2
local FLAT = Vector3.new(1, 0, 1)
local JAW_FX_GAP = 0.12 -- como mucho un aviso de doble mandíbula cada tanto (se muerde a 10 por segundo)
local GIANT_STALE = 2 -- una gigante que nadie come deja de bloquear la siguiente tras este número de intervalos

local rng = Random.new()
local remote: RemoteEvent
local states: { [Player]: any } = {}
local colorCache: { [string]: Color3 } = {}

local function getRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return root, humanoid
end

local function edgeDistance(from: Vector3, food: Model): number
	return ((food:GetPivot().Position - from) * FLAT).Magnitude - ((food:GetAttribute("Radius") :: number?) or 0)
end

local function edible(stats, def): boolean
	return def ~= nil and def.zone <= stats.depth and (not def.hard or stats.canBiteHard)
end

-- Zona del túnel en la que está una posición (la puerta cuenta como su zona; el jardín es la 1)
local function zoneAt(position: Vector3): number
	for i = #Config.Zones, 2, -1 do
		if position.Z <= Config.Zones[i].z0 + 12 then
			return i
		end
	end
	return 1
end

-- La comida que te dejan morder más cercana a `position` (borde a menos de `range`), sin `except`
local function nearestEdible(stats, position: Vector3, range: number, except: Model?): Model?
	local best: Model? = nil
	local bestDistance = range
	-- Solo tu zona y las de al lado: las demás quedan a cientos de studs (se descartan sin medir)
	local here = zoneAt(position)
	for food in FoodService.list() do
		if food ~= except then
			local def = FoodService.defOf(food)
			if def and math.abs(def.zone - here) <= 1 and edible(stats, def) then
				local distance = edgeDistance(position, food)
				if distance <= bestDistance then
					best = food
					bestDistance = distance
				end
			end
		end
	end
	return best
end


local function hardMult(stats, def): number
	return if def and def.hard then stats.hardMult else 1
end

local function stateOf(profile)
	local s = states[profile.player]
	if not s or s.profile ~= profile then
		s = {
			profile = profile,
			runId = profile.data.rebirths,
			chargeFrom = nil :: number?,
			lastBite = -math.huge,
			jawFxAt = 0,
			buche = nil,
			giant = nil :: Model?,
			giantBorn = 0,
			giantAt = 0,
			rainReadyAt = 0,
			rainId = 0,
			crumbs = {},
		}
		states[profile.player] = s
	end
	return s
end

-- Sigue siendo la misma partida de la misma jugadora (no se fue ni enjambró)
local function current(profile, runId: number): boolean
	return Profiles.get(profile.player) == profile and profile.data.rebirths == runId
end

---------------------------------------------------------------------------------------------------
-- Dónde se entrega a pie: el hormiguero de casa o el de zona (Depots)
local function atDepot(profile, position: Vector3, margin: number): boolean
	local hill = profile.hill
	if hill then
		local flat = ((hill:GetPivot().Position - position) * FLAT).Magnitude
		if flat <= Config.Anthill.DepositRadius * profile.stats.hillScale + margin then
			return true
		end
	end
	return Depots.near(profile, position, margin) ~= nil
end

---------------------------------------------------------------------------------------------------
-- Buche: lo que te guardas al entregar vuelve a tus mandíbulas al salir

local function onDeposit(profile)
	local stats = profile.stats
	if not stats or stats.bucheShare <= 0 or profile.carry <= 0 then
		return
	end
	local root = getRoot(profile.player)
	local s = stateOf(profile)
	-- Solo en las entregas a pie: la abeja y el tirachinas no cuentan
	if not root or not atDepot(profile, root.Position, 2) then
		return
	end
	local n = math.floor(profile.carry * stats.bucheShare)
	if n < 1 then
		return
	end
	s.buche = {
		n = n,
		value = profile.carryValue / profile.carry * n,
		color = profile.carryColor,
		runId = profile.data.rebirths,
	}
end

local function updateBuche(profile, s, root: BasePart)
	local b = s.buche
	if not b then
		return
	end
	if b.runId ~= profile.data.rebirths then
		s.buche = nil
		return
	end
	local stats = profile.stats
	if profile.carry >= stats.capacity or atDepot(profile, root.Position, 4) then
		return
	end
	s.buche = nil
	local n = math.min(b.n, stats.capacity - profile.carry)
	if profile.carry <= 0 then
		profile.carryColor = b.color
	end
	profile.carry += n
	profile.carryValue += b.value * n / b.n
	PlayerService.refreshCarry(profile)
	remote:FireClient(profile.player, "Buche", n)
end

---------------------------------------------------------------------------------------------------
-- Mordisco cargado y doble mandíbula

-- Suelta la carga sobre `food`: Mult veces los mordiscos que cabían en el tiempo cargado
local function release(profile, s, food: Model?, now: number)
	local stats = profile.stats
	local from = s.chargeFrom
	s.chargeFrom = nil
	if not from or stats.chargeMax <= 0 then
		return
	end
	local charge = math.min(now - from, stats.chargeMax)
	if charge < X.Charged.MinCharge then
		return
	end
	local root = getRoot(profile.player)
	if not food or not FoodService.isFood(food) then
		food = if root then nearestEdible(stats, root.Position, stats.biteRange + 2) else nil
	end
	if not food then
		return
	end
	local def = FoodService.defOf(food)
	local taps = charge / math.max(stats.biteCooldown, 0.05)
	local damage = stats.biteDamage * stats.chargeMult * taps * hardMult(stats, def)
	local position = food:GetPivot().Position
	local taken = PlayerService.take(profile, food, damage)
	if taken > 0 then
		PlayerService.refreshCarry(profile)
		remote:FireAllClients("Charged", profile.player, position + Vector3.new(0, 1, 0), taken, charge / stats.chargeMax)
	end
end

local function updateCharge(profile, s, now: number, root: BasePart)
	local stats = profile.stats
	if stats.chargeMax <= 0 or profile.carry >= stats.capacity then
		s.chargeFrom = nil
		return
	end
	local bitAt = math.max(s.lastBite, profile.lastBite or 0)
	local near = nearestEdible(stats, root.Position, stats.biteRange + 2)
	if not near or now - bitAt < X.Charged.Pause then
		s.chargeFrom = nil
		return
	end
	-- La carga cuenta desde que paraste (más la pausa), como la dibuja el cliente; si llegaste
	-- andando, desde que tienes comida a tiro
	s.chargeFrom = s.chargeFrom or math.max(bitAt + X.Charged.Pause, now - TICK)
	-- Carga llena: el mordisco sale solo
	if now - s.chargeFrom >= stats.chargeMax then
		release(profile, s, near, now)
		s.lastBite = now
	end
end

local function onBite(profile, food: Model)
	local stats = profile.stats
	if not stats then
		return
	end
	local s = stateOf(profile)
	local now = os.clock()
	if s.chargeFrom then
		release(profile, s, food, now)
	end
	s.lastBite = now

	if stats.jawShare <= 0 then
		return
	end
	local root = getRoot(profile.player)
	if not root or profile.carry >= stats.capacity then
		return
	end
	local other = nearestEdible(stats, root.Position, stats.biteRange + X.DoubleJaw.Reach, food)
	if not other then
		return
	end
	local def = FoodService.defOf(other)
	local damage = stats.biteDamage * (1 + (profile.combo or 0) * Config.Combo.Step) * stats.jawShare * (stats.neighborScale or 1) * hardMult(stats, def)
	local position = other:GetPivot().Position
	local radius = other:GetAttribute("Radius")
	local color = other:GetAttribute("Color")
	local taken = PlayerService.take(profile, other, damage)
	if taken > 0 and now >= s.jawFxAt then
		s.jawFxAt = now + JAW_FX_GAP
		remote:FireAllClients("Jaw", profile.player, other, position, radius, color)
	end
end

---------------------------------------------------------------------------------------------------
-- Comida gigante

local function grow(profile, food: Model): boolean
	local def = FoodService.defOf(food)
	local mult = profile.stats.giantMult
	local radius = (food:GetAttribute("Radius") :: number?) or 2
	-- El volumen crece como la comida: la raíz cúbica de Mult, con un empujón para que se note
	local k = math.clamp(mult ^ (1 / 3) * 1.15, 1.5, 2.6)
	local ok = pcall(function()
		food:ScaleTo(food:GetScale() * k)
	end)
	if not ok then
		return false
	end
	food:SetAttribute("Radius", radius * k)
	food:SetAttribute("MaxHp", ((food:GetAttribute("MaxHp") :: number?) or def.hp) * mult)
	food:SetAttribute("Hp", ((food:GetAttribute("Hp") :: number?) or def.hp) * mult)
	food:SetAttribute("Giant", profile.player.UserId)
	remote:FireAllClients("Giant", profile.player, food, food:GetPivot().Position, radius * k)
	return true
end

local function updateGiant(profile, s, now: number, root: BasePart)
	local stats = profile.stats
	if stats.giantInterval <= 0 then
		s.giantAt = 0
		return
	end
	if s.giantAt == 0 then
		s.giantAt = now + stats.giantInterval * 0.5 -- la primera llega antes
	end
	if now < s.giantAt then
		return
	end
	if s.giant and FoodService.isFood(s.giant) and now - s.giantBorn < stats.giantInterval * GIANT_STALE then
		s.giantAt = now + 5
		return
	end
	local zone = zoneAt(root.Position)
	if zone > stats.depth then
		s.giantAt = now + 5
		return
	end
	-- La más jugosa de las que tienes cerca (entera y sin crecer), o cualquiera de la zona
	-- Orden: que la puedas morder, que esté cerca, la que más vale y, entre iguales, la más cercana
	local best: Model? = nil
	local bestTier, bestWorth = -1, -math.huge
	for food in FoodService.list() do
		local def = FoodService.defOf(food)
		if def and def.zone == zone and not def.boss and food:GetAttribute("Giant") == nil and food:GetAttribute("Hp") == food:GetAttribute("MaxHp") then
			local distance = ((food:GetPivot().Position - root.Position) * FLAT).Magnitude
			local tier = (if edible(stats, def) then 2 else 0) + (if distance <= 90 then 1 else 0)
			local worth = def.hp * def.value - distance
			if tier > bestTier or (tier == bestTier and worth > bestWorth) then
				best = food
				bestTier = tier
				bestWorth = worth
			end
		end
	end
	if not best or not grow(profile, best) then
		s.giantAt = now + 5
		return
	end
	s.giant = best
	s.giantBorn = now
	s.giantAt = now + stats.giantInterval
end

---------------------------------------------------------------------------------------------------
-- Lluvia propia

-- La mejor comida de esa zona que te dejan morder (o la de más atrás si ninguna)
local function rainFood(stats, zone: number)
	local pick = nil
	for i = (zone - 1) * 3 + 1, zone * 3 do
		local def = Config.Foods[i]
		if def and not def.boss and edible(stats, def) then
			pick = def
		end
	end
	return pick or Config.Foods[(zone - 1) * 3 + 1] or Config.Foods[1]
end

local function foodColor(def): Color3
	local cached = colorCache[def.id]
	if cached then
		return cached
	end
	for food in FoodService.list() do
		if food:GetAttribute("FoodId") == def.id and food:GetAttribute("Golden") ~= true then
			local color = food:GetAttribute("Color")
			if typeof(color) == "Color3" then
				colorCache[def.id] = color
				return color
			end
		end
	end
	return Color3.fromRGB(222, 166, 92)
end

local function clearCrumbs(profile, s)
	for id in s.crumbs do
		remote:FireAllClients("RainGone", profile.player.UserId, id)
	end
	table.clear(s.crumbs)
end

local function onRain(profile, s)
	local stats = profile.stats
	local now = Workspace:GetServerTimeNow()
	if stats.rainCooldown <= 0 or now < s.rainReadyAt then
		return
	end
	s.rainReadyAt = now + stats.rainCooldown
	profile.player:SetAttribute("RainReadyAt", s.rainReadyAt)
	local runId = profile.data.rebirths
	local count = stats.rainCount
	local every = X.Rain.Duration / math.max(count, 1)
	task.spawn(function()
		for _ = 1, count do
			if not current(profile, runId) then
				return
			end
			local root, humanoid = getRoot(profile.player)
			if root and humanoid then
				local zone = math.min(zoneAt(root.Position), profile.stats.depth)
				local def = rainFood(profile.stats, zone)
				local angle = rng:NextNumber(0, math.pi * 2)
				local r = 3 + math.sqrt(rng:NextNumber()) * (X.Rain.Radius - 3)
				local x = root.Position.X + math.cos(angle) * r
				local z = root.Position.Z + math.sin(angle) * r
				if zone > 1 then
					x = math.clamp(x, -Config.Map.Half + 4, Config.Map.Half - 4)
				end
				local ground = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
				local position = Vector3.new(x, ground, z)
				s.rainId += 1
				local landAt = os.clock() + X.Rain.Fall
				local color = foodColor(def)
				s.crumbs[s.rainId] = {
					pos = position,
					landAt = landAt,
					dieAt = landAt + X.Rain.Life,
					-- Bites mordiscos tuyos, como mucho una comida entera (al final del árbol un mordisco ya se la come)
					n = math.max(1, math.floor(math.min(profile.stats.biteDamage * (profile.stats.harvest or 1) * X.Rain.Bites, def.hp))),
					value = def.value * (profile.stats.zoneMult[def.zone] or 1),
					color = color,
				}
				remote:FireAllClients("RainCrumb", profile.player.UserId, s.rainId, position, X.Rain.Fall, color)
			end
			task.wait(every)
		end
	end)
end

local function updateCrumbs(profile, s, now: number, root: BasePart?)
	if next(s.crumbs) == nil then
		return
	end
	local stats = profile.stats
	local changed = false
	for id, crumb in s.crumbs do
		if now >= crumb.dieAt then
			s.crumbs[id] = nil
			remote:FireAllClients("RainGone", profile.player.UserId, id)
		elseif root and now >= crumb.landAt and profile.carry < stats.capacity then
			local offset = root.Position - crumb.pos
			if (offset * FLAT).Magnitude <= X.Rain.Reach and math.abs(offset.Y) < 10 then
				local n = math.min(crumb.n, stats.capacity - profile.carry)
				profile.carry += n
				profile.carryValue += n * crumb.value
				profile.carryColor = crumb.color
				changed = true
				s.crumbs[id] = nil
				remote:FireAllClients("RainTaken", profile.player.UserId, id)
			end
		end
	end
	if changed then
		PlayerService.refreshCarry(profile)
	end
end

---------------------------------------------------------------------------------------------------

local function onRequest(player: Player, action: any)
	local profile = Profiles.get(player)
	if not profile or not profile.stats or not getRoot(player) then
		return
	end
	if action == "Rain" then
		onRain(profile, stateOf(profile))
	end
end

local function forget(player: Player)
	local s = states[player]
	if not s then
		return
	end
	clearCrumbs(s.profile, s)
	states[player] = nil
end

local function tick()
	for player, s in states do
		if Profiles.get(player) ~= s.profile then
			forget(player)
		end
	end
	local now = os.clock()
	for player, profile in Profiles.all() do
		if not profile.stats then
			continue
		end
		local s = stateOf(profile)
		-- Enjambre: lo de la partida anterior se va
		if s.runId ~= profile.data.rebirths then
			s.runId = profile.data.rebirths
			s.buche = nil
			s.chargeFrom = nil
			s.giant = nil
			s.giantAt = 0
			clearCrumbs(profile, s)
		end
		local root = getRoot(player)
		updateCrumbs(profile, s, now, root)
		if not root then
			s.chargeFrom = nil
			continue
		end
		updateBuche(profile, s, root)
		updateCharge(profile, s, now, root)
		updateGiant(profile, s, now, root)
	end
end

function Extras.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Extras"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	Events.on("Bite", onBite)
	Events.on("Deposit", onDeposit)
	-- Partida nueva sin enjambrar (panel DEV): data.rebirths no cambia, así que se fuerza la limpieza
	-- del siguiente tick (buche, mordisco cargado, comida gigante, migas)
	Events.on("RunReset", function(profile)
		local s = stateOf(profile)
		s.runId = nil
		s.buche = nil
	end)
	Players.PlayerRemoving:Connect(forget)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[CRUNCH!] Extras:", err)
			end
		end
	end)
end

return Extras
