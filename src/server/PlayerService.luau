-- Ciclo de vida del jugador: carga, hormiguero, personaje, morder, depositar y guardar.
-- El cliente solo pide acciones; aquí se valida todo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)
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
	local side = (0.7 + 1.3 * math.clamp(profile.carry / profile.stats.capacity, 0, 1)) * scale
	local chunkPart = chunk :: Part
	chunkPart.Color = profile.carryColor
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
		return
	end
	if not data then
		player:Kick("No pudimos cargar tu colonia. Vuelve a entrar en un momento.")
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
		Data.save(player.UserId, profile.data)
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

	local taken, _, finished = FoodService.damage(food, math.min(damage, space))
	if taken <= 0 then
		return
	end
	profile.carry += taken
	profile.carryValue += taken * def.value * stats.zoneMult[def.zone] * worth
	profile.carryColor = color
	Profiles.trackFood(profile, def, taken)
	Events.fire("Ate", profile, def, taken, false)
	if finished then
		Profiles.awardTrophy(profile, def)
		Events.fire("Finished", profile, def)
	end
	if golden then
		Events.fire("Golden", profile)
	end

	-- Mordida en área: la mitad del daño a lo que haya cerca
	if stats.areaRadius > 0 then
		local nearby = {}
		for other in FoodService.list() do
			if other ~= food and edgeDistance(position, other) <= stats.areaRadius then
				table.insert(nearby, other)
			end
		end
		for _, other in nearby do
			local left = stats.capacity - profile.carry
			if left <= 0 then
				break
			end
			local otherDef = FoodService.defOf(other)
			if otherDef.zone > stats.depth or (otherDef.hard and not stats.canBiteHard) then
				continue
			end
			local extra, _, done = FoodService.damage(other, math.min(math.ceil(damage * 0.5), left))
			profile.carry += extra
			profile.carryValue += extra * otherDef.value * stats.zoneMult[otherDef.zone] * worth
			Profiles.trackFood(profile, otherDef, extra)
			if extra > 0 then
				Events.fire("Ate", profile, otherDef, extra, false)
			end
			if done then
				Profiles.awardTrophy(profile, otherDef)
				Events.fire("Finished", profile, otherDef)
			end
		end
	end

	Profiles.push(profile)
	updateCarryVisual(profile)
	fxRemote:FireClient(player, "Bite", position, taken, finished, crit, profile.combo, golden)
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
			if flat.Magnitude <= Config.Anthill.DepositRadius * stats.hillScale then
				local value = profile.carryValue * stats.depositMult
				local full = profile.carry >= stats.capacity
				if full then
					value *= 1 + stats.fullLoadBonus
				end
				local doubled = rng:NextNumber() < stats.doubleChance
				if doubled then
					value *= 2
				end
				local credited = Profiles.addFood(profile, value)
				profile.carry = 0
				profile.carryValue = 0
				Profiles.push(profile)
				updateCarryVisual(profile)
				fxRemote:FireClient(player, "Deposit", center + Vector3.new(0, 9 * stats.hillScale, 0), credited, doubled)
				Events.fire("Deposit", profile, credited, full)
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

	game:BindToClose(function()
		local pending = 0
		for player, profile in Profiles.all() do
			if profile.canSave then
				pending += 1
				task.spawn(function()
					Data.save(player.UserId, profile.data)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	-- Herramienta de desarrollo, solo en Studio: dar comida o fijar niveles desde la barra de comandos
	if RunService:IsStudio() then
		local debug = Instance.new("BindableEvent")
		debug.Name = "CrunchDebug"
		debug.Event:Connect(function(command: string, a: any, b: any)
			for _, profile in Profiles.all() do
				local data = profile.data
				if command == "food" then
					Profiles.addFood(profile, a)
				elseif command == "node" then
					data.nodes[a] = b
				elseif command == "royal" then
					data.royal[a] = b
				elseif command == "workers" then
					data.workers = a
				elseif command == "jelly" then
					data.jelly = a
				elseif command == "depth" then
					data.depth = math.clamp(a, 1, Stats.MaxDepth)
				elseif command == "rebirths" then
					data.rebirths = a
				elseif command == "tarta" then
					data.tartaDone = true
				elseif command == "grant" then
					Monetize.debugGrant(profile, a) -- pase o producto, por su id de Config
				elseif command == "minis" then
					-- Todas las galerías de las capas ya excavadas
					for _, def in Config.Minis do
						if def.layer <= data.depth then
							data.minis[def.id] = true
						end
					end
				elseif command == "max" then
					-- Todo el árbol al tope de la capa `a`
					data.depth = math.clamp(a, 1, Stats.MaxDepth)
					for _, def in Config.Tree do
						if not def.unit then
							data.nodes[def.id] = Stats.available(def, data.depth)
							if def.layer > data.depth then
								data.nodes[def.id] = 0
							end
						end
					end
				end
				Profiles.refresh(profile)
			end
		end)
		debug.Parent = game:GetService("ServerScriptService")
	end
end

return PlayerService
