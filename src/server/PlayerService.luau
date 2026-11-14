-- Ciclo de vida del jugador: carga, hormiguero, personaje, morder, depositar y guardar.
-- El cliente solo pide acciones; aquí se valida todo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Data = require(script.Parent.Data)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local Monetize = require(script.Parent.Monetize)
local Profiles = require(script.Parent.Profiles)
local World = require(script.Parent.World)

local PlayerService = {}

local rng = Random.new()
local fxRemote: RemoteEvent

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Antitrampas de teletransporte. La posición la manda el cliente, así que entre un mordisco o una
-- entrega y la siguiente tiene que haber dado tiempo a recorrer la distancia con turbo (y mucho
-- margen). También lo usa la entrega del puesto avanzado (Extras), por PlayerService.canReach. Si no, la acción espera: quien se teletransporta no gana nada sobre quien camina, y
-- nadie es expulsado por un falso positivo. Las alas dan un salto libre por recarga, y el túnel
-- y el aparecer cuentan como salida desde su destino (profile.anchor).
local FLAT = Vector3.new(1, 0, 1)
-- Holgado a propósito (opción ligera): hay velocidades que solo conoce el cliente (regalo del jardín,
-- saludo, Estampida de la exploradora, Segadora, telaraña, bola de miel) y el turbo con Resuello puede
-- ir siempre puesto. Corta el teletransporte; un truco de velocidad moderado sigue pasando.
local TRAVEL_MARGIN = 1.6 -- x turbo por la senda: potenciadores del cliente que el servidor no ve
local TRAVEL_BURST = 3 -- s extra a esa velocidad: acelerones cortos (Estampida, embestidas)
local TRAVEL_SLACK = 60 -- studs extra: latencia, saltos, setas y empujones

function PlayerService.moved(profile, position: Vector3)
	profile.anchor = { position = position, at = os.clock() }
end

local function canReach(profile, position: Vector3): boolean
	local anchor = profile.anchor
	if not anchor then
		return true
	end
	local stats = profile.stats
	local now = os.clock()
	-- WalkSpeed (atributo) ya trae pociones, reglas y castas; el cliente le suma correr, turbo y senda
	local shown = profile.player:GetAttribute("WalkSpeed")
	local walk = math.max(if type(shown) == "number" then shown else 0, stats.walkSpeed, Config.Player.WalkSpeed)
	local top = walk * (stats.laneMult or 1) * Config.Sprint.Mult * TRAVEL_MARGIN
	local allowed = top * (now - anchor.at + TRAVEL_BURST) + TRAVEL_SLACK
	if ((position - anchor.position) * FLAT).Magnitude <= allowed then
		return true
	end
	if stats.hasWings and now >= (profile.wingsFreeAt or 0) then
		profile.wingsFreeAt = now + stats.wingsCooldown * 0.8 -- 0.8: la recarga se cuenta en el cliente
		return true
	end
	return false
end
PlayerService.canReach = canReach

local function assignAnthill(player: Player): Model?
	local hills = Workspace:WaitForChild("Anthills"):GetChildren()
	table.sort(hills, function(a, b)
		return a.Name < b.Name
	end)
	-- Los del centro del arco primero: quedan más cerca del camino
	local order = { 3, 4, 2, 5, 1, 6 }
	for _, index in order do
		local hill = hills[index]
		if hill and hill:IsA("Model") and hill:GetAttribute("OwnerId") == 0 then
			hill:SetAttribute("OwnerId", player.UserId)
			return hill
		end
	end
	return nil
end

local function releaseAnthill(hill: Model)
	hill:SetAttribute("OwnerId", 0)
	hill:SetAttribute("Workers", 0)
	hill:SetAttribute("Soldiers", 0)
	hill:SetAttribute("Egg", false)
	for i = 1, 3 do
		hill:SetAttribute("TrailPos" .. i, nil)
	end
	World.dressAnthill(hill, 1, 0, nil, 0)
end

local function updateCarryVisual(profile)
	local character = profile.player.Character
	local head = character and character:FindFirstChild("Head")
	if not character or not head or not head:IsA("BasePart") then
		return
	end

	local chunk = character:FindFirstChild("CarryChunk") :: Part?
	if profile.carry <= 0 then
		profile.carryGold = nil -- la carga dorada se fue con la entrega
		if chunk then
			chunk:Destroy()
		end
		return
	end

	if not chunk then
		local newChunk = Instance.new("Part")
		newChunk.Name = "CarryChunk"
		newChunk.CanCollide = false
		newChunk.CanTouch = false
		newChunk.Massless = true
		newChunk.Material = Enum.Material.SmoothPlastic
		newChunk.Parent = character
		local weld = Instance.new("Weld")
		weld.Name = "CarryWeld"
		weld.Part0 = head
		weld.Part1 = newChunk
		weld.Parent = newChunk
		chunk = newChunk
	end

	local scale = character:GetScale()
	-- Lo que no te cabe a ti lo lleva el escarabajo de carga (lo dibuja el cliente)
	local own = profile.stats.ownCapacity or profile.stats.capacity
	local side = (0.7 + 1.3 * math.clamp(profile.carry / own, 0, 1)) * scale
	local chunkPart = chunk :: Part
	-- Si llevas algo de comida dorada, el trozo es de oro y brilla
	chunkPart.Color = if profile.carryGold then Color3.fromRGB(255, 196, 40) else profile.carryColor
	chunkPart.Material = if profile.carryGold then Enum.Material.Neon else Enum.Material.SmoothPlastic
	chunkPart.Size = Vector3.new(side, side, side)
	local weld = chunkPart:FindFirstChild("CarryWeld") :: Weld
	-- Entre las mandíbulas (el frente de la hormiga es -Z)
	weld.C0 = CFrame.new(0, -0.45 * scale, -(1.15 * scale + side / 2)) * CFrame.Angles(0.3, 0.5, 0.2)
end

local function onCharacter(profile, character: Model)
	local player = profile.player
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.WalkSpeed = profile.stats.walkSpeed
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = 2.5

	Profiles.applyLook(profile, true)

	local spawn = profile.hill and profile.hill:FindFirstChild("Spawn")
	if spawn and spawn:IsA("BasePart") then
		character:PivotTo(spawn.CFrame + Vector3.new(0, 1.5 * character:GetScale(), 0))
		PlayerService.moved(profile, spawn.Position)
	end

	-- Al morir se pierde lo que llevabas encima
	profile.carry = 0
	profile.carryValue = 0
	profile.combo = 0
	Profiles.push(profile)

	humanoid.Died:Once(function()
		task.wait(2)
		if player.Parent and Profiles.get(player) then
			player:LoadCharacter()
		end
	end)
end

local function grantOffline(profile)
	local data = profile.data
	local hours = profile.stats.offlineHours
	if hours <= 0 or data.rate <= 0 then
		return
	end
	local away = math.clamp(os.time() - data.lastSeen, 0, hours * 3600)
	if away < 60 then
		return
	end
	local gain = math.floor(data.rate * away * (profile.stats.offlineEfficiency or Config.Offline.Efficiency) * profile.stats.offlineMult)
	if gain <= 0 then
		return
	end
	data.food += gain
	data.runFood += gain
	data.totalFood += gain
	task.delay(5, function()
		Profiles.say(profile, "Mientras no estabas, la colonia trajo " .. Format.short(gain) .. " de comida", 7)
	end)
end

local function onPlayerAdded(player: Player)
	local data, canSave = Data.load(player.UserId)
	if not player.Parent then
		if canSave then
			Data.release(player.UserId) -- salió mientras cargaba: que otro servidor pueda abrirla
		end
		return
	end
	if not data then
		player:Kick("No pudimos cargar tu colonia. Vuelve a entrar en un par de minutos.")
		return
	end

	local profile = Profiles.create(player, data, canSave)
	profile.hill = assignAnthill(player)
	Monetize.load(profile)
	if not player.Parent then
		return
	end
	grantOffline(profile)
	Profiles.refresh(profile)
	player:SetAttribute("Loaded", true)

	player.CharacterAdded:Connect(function(character)
		onCharacter(profile, character)
	end)
	player:LoadCharacter()
end

local function onPlayerRemoving(player: Player)
	local profile = Profiles.get(player)
	if not profile then
		return
	end
	Profiles.remove(player)
	if profile.hill then
		releaseAnthill(profile.hill)
	end
	if profile.canSave then
		Data.save(player.UserId, profile.data, true)
	end
end

local function edgeDistance(from: Vector3, food: Model): number
	local flat = (food:GetPivot().Position - from) * Vector3.new(1, 0, 1)
	return flat.Magnitude - (food:GetAttribute("Radius") :: number)
end

local function onBite(player: Player, food: any)
	local profile = Profiles.get(player)
	local root = getRoot(player)
	if not profile or not root or not FoodService.isFood(food) then
		return
	end

	local now = os.clock()
	local stats = profile.stats
	-- 10 % de margen para no castigar el retraso de red
	if now - profile.lastBite < stats.biteCooldown * 0.9 then
		return
	end
	local space = stats.capacity - profile.carry
	if space <= 0 then
		return
	end
	if edgeDistance(root.Position, food) > stats.biteRange + 2 then
		return
	end

	local def = FoodService.defOf(food)
	local gap = now - profile.lastBite
	profile.lastBite = now
	if def.zone > stats.depth then
		return -- la puerta de esa zona sigue cerrada para ti
	end
	if def.hard and not stats.canBiteHard then
		Profiles.say(profile, "¡Está durísima! Necesito la mandíbula sierra", 3)
		return
	end
	-- Después de los descartes de arriba: un mordisco que no cuenta no gasta el salto de las alas
	if not canReach(profile, root.Position) then
		return
	end
	PlayerService.moved(profile, root.Position)

	-- Racha: morder sin parar pega cada vez más
	if stats.comboCap > 0 and gap <= Config.Combo.Window then
		profile.combo = math.min(profile.combo + 1, stats.comboCap)
	else
		profile.combo = 0
	end

	local crit = rng:NextNumber() < stats.critChance
	-- Mordisco dorado (galerías): la comida que arranca este mordisco vale mucho más
	local golden = stats.goldChance > 0 and rng:NextNumber() < stats.goldChance
	local worth = if golden then Config.MiniTune.GoldMult else 1
	local damage = stats.biteDamage * (1 + profile.combo * Config.Combo.Step)
	if crit then
		damage *= stats.critMult
	end
	if def.hard then
		damage *= stats.hardMult
	end
	damage = math.ceil(damage)
	local position = food:GetPivot().Position + Vector3.new(0, 1, 0)
	local color = food:GetAttribute("Color")
	local goldFood = FoodService.isGolden(food)
	local piece = FoodService.pieceValue(food, def, stats)

	local taken, _, finished = FoodService.damage(food, math.min(damage, space))
	if taken <= 0 then
		return
	end
	profile.carry += taken
	profile.carryValue += taken * piece * worth
	profile.carryColor = color
	if goldFood then
		profile.carryGold = true
	end
	Profiles.trackFood(profile, def, taken)
	Events.fire("Ate", profile, def, taken, false)
	if finished then
		Profiles.awardTrophy(profile, def)
		Events.fire("Finished", profile, def)
	end
	if golden then
		Events.fire("Golden", profile)
	end

	-- Mordida en área: Config.Player.AreaShare del mordisco a las comidas de al lado (como mucho las
	-- tres más cercanas: en un racimo siempre hay vecinas, y Stats.harvest cuenta con tres)
	if stats.areaRadius > 0 then
		local nearby = {}
		for other in FoodService.list() do
			local gap = if other ~= food then edgeDistance(position, other) else math.huge
			if gap <= stats.areaRadius then
				table.insert(nearby, { food = other, gap = gap })
			end
		end
		table.sort(nearby, function(a, b)
			return a.gap < b.gap
		end)
		for i, item in nearby do
			if i > 3 or profile.carry >= stats.capacity then
				break
			end
			PlayerService.take(profile, item.food, math.ceil(damage * (stats.areaShare or 0.5) * (stats.neighborScale or 1)), worth)
		end
	end

	-- Para las aliadas (escolta, mega crunch) y las castas: qué mordiste, si fue seguido, dónde,
	-- con cuánto daño y si la terminaste
	Events.fire("Bite", profile, food, gap <= Config.Combo.Window, position, damage, finished)

	Profiles.push(profile)
	updateCarryVisual(profile)
	fxRemote:FireClient(player, "Bite", position, taken, finished, crit, profile.combo, golden, goldFood)

	-- Mordida en cadena (módulo Chain): después del efecto del mordisco, para que el rayo salga de ahí
	if finished then
		Events.fire("FinalBite", profile, food, position, damage)
	end
end

-- Arranca hasta `amount` de vida de una comida y lo mete en tu carga, si cabe. Comprueba la puerta
-- de su zona y la comida dura. La usan la mordida en área y las aliadas. Devuelve (trozos, si se acabó).
function PlayerService.take(profile, food: Model, amount: number, worth: number?): (number, boolean)
	local stats = profile.stats
	local space = stats.capacity - profile.carry
	if space <= 0 or amount <= 0 or not FoodService.isFood(food) then
		return 0, false
	end
	local def = FoodService.defOf(food)
	if def.zone > stats.depth or (def.hard and not stats.canBiteHard) then
		return 0, false
	end
	local color = food:GetAttribute("Color")
	local goldFood = FoodService.isGolden(food)
	local piece = FoodService.pieceValue(food, def, stats)
	local taken, _, finished = FoodService.damage(food, math.min(math.ceil(amount), space))
	if taken > 0 then
		profile.carry += taken
		profile.carryValue += taken * piece * (worth or 1)
		if typeof(color) == "Color3" then
			profile.carryColor = color
		end
		if goldFood then
			profile.carryGold = true
		end
		Profiles.trackFood(profile, def, taken)
		Events.fire("Ate", profile, def, taken, false)
	end
	if finished then
		Profiles.awardTrophy(profile, def)
		Events.fire("Finished", profile, def)
	end
	return taken, finished
end

-- Tras cambiar la carga desde fuera (abeja, tirachinas, imán): atributos y trozo entre las mandíbulas.
function PlayerService.refreshCarry(profile)
	Profiles.push(profile)
	updateCarryVisual(profile)
end

-- Lo que vale entregar una carga: la misma cuenta a pie, con la abeja o con el tirachinas.
-- Acredita la comida y avisa del suceso "Deposit". Devuelve (acreditado, carga llena, doble).
function PlayerService.credit(profile, carry: number, carryValue: number): (number, boolean, boolean)
	local stats = profile.stats
	local value = carryValue * stats.depositMult
	local full = carry >= stats.capacity
	if full then
		value *= 1 + stats.fullLoadBonus
	end
	local doubled = rng:NextNumber() < stats.doubleChance
	if doubled then
		value *= 2
	end
	local credited = Profiles.addFood(profile, value)
	Events.fire("Deposit", profile, credited, full)
	return credited, full, doubled
end

-- Entrega a distancia (Catapulta de la Porteadora): la misma cuenta y el mismo efecto que llegar a
-- pie con esa carga. Quien llama ya ha vaciado la carga. Devuelve lo acreditado.
function PlayerService.deliver(profile, carry: number, carryValue: number): number
	if not profile.hill or carry <= 0 then
		return 0
	end
	local center = profile.hill:GetPivot().Position
	local credited, _, doubled = PlayerService.credit(profile, carry, carryValue)
	Profiles.push(profile)
	fxRemote:FireClient(profile.player, "Deposit", center + Vector3.new(0, 9 * profile.stats.hillScale, 0), credited, doubled)
	return credited
end

local function depositLoop()
	while true do
		task.wait(0.1)
		for player, profile in Profiles.all() do
			if profile.carry <= 0 or not profile.hill then
				continue
			end
			local root = getRoot(player)
			if not root then
				continue
			end
			local stats = profile.stats
			local center = profile.hill:GetPivot().Position
			local flat = (center - root.Position) * Vector3.new(1, 0, 1)
			if flat.Magnitude <= Config.Anthill.DepositRadius * stats.hillScale and canReach(profile, root.Position) then
				PlayerService.moved(profile, root.Position)
				local credited, _, doubled = PlayerService.credit(profile, profile.carry, profile.carryValue)
				profile.carry = 0
				profile.carryValue = 0
				Profiles.push(profile)
				updateCarryVisual(profile)
				fxRemote:FireClient(player, "Deposit", center + Vector3.new(0, 9 * stats.hillScale, 0), credited, doubled)
			end
		end
	end
end

local function saveLoop()
	while true do
		task.wait(Config.Save.Interval)
		for player, profile in Profiles.all() do
			if profile.canSave then
				task.spawn(Data.save, player.UserId, profile.data)
			end
		end
	end
end

function PlayerService.start(remotes: Folder)
	fxRemote = remotes.Fx
	remotes.Bite.OnServerEvent:Connect(onBite)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(depositLoop)
	task.spawn(saveLoop)

	-- Espera también los guardados de salida en curso: al irse la última jugadora el servidor
	-- cierra justo mientras se guarda su colonia.
	game:BindToClose(function()
		for player, profile in Profiles.all() do
			if profile.canSave then
				task.spawn(Data.save, player.UserId, profile.data, true)
			end
		end
		Data.waitForSaves(25)
	end)
end

return PlayerService
