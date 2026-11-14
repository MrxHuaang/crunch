-- Peligros en el cliente: dibuja la araña y el cangrejo (suavizando las posiciones que manda
-- el servidor 10 veces por segundo), y el zapato o rodillo del pisotón con su sombra de aviso.
-- También el aplastado (solo visual) y el temblor de cámara.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Hazards = {}

local player = Players.LocalPlayer
local rng = Random.new()

local FLAT = Vector3.new(1, 0, 1)
local GROUND = Config.GroundY
local SQUASH_TIME = 1.5
local DRAW_DISTANCE = 380

local INK = Color3.fromRGB(20, 16, 16)
local WHITE = Color3.new(1, 1, 1)
local CREAM = Color3.fromRGB(255, 244, 222)
local RED = Color3.fromRGB(230, 57, 70)
local YELLOW = Color3.fromRGB(255, 210, 63)

local folder: Model
local creatures: { [number]: any } = {}
local squashing: { [Model]: boolean } = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function nearCamera(position: Vector3, distance: number): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < distance
end

------------------------------------------------------------------------------------------
-- Piezas redondas
------------------------------------------------------------------------------------------

local function newPart(parent: Instance, size: Vector3, color: Color3, cframe: CFrame?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	if cframe then
		part.CFrame = cframe
	end
	part.Parent = parent
	return part
end

-- Elipsoide: bloque con malla de esfera
local function blob(parent: Instance, size: Vector3, color: Color3, cframe: CFrame?): Part
	local part = newPart(parent, size, color, cframe)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Cilindro: el eje sigue el eje X del CFrame
local function rod(parent: Instance, length: number, thickness: number, color: Color3, cframe: CFrame?): Part
	local part = newPart(parent, Vector3.new(length, thickness, thickness), color, cframe)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function ball(parent: Instance, diameter: number, color: Color3, cframe: CFrame?): Part
	local part = newPart(parent, Vector3.new(diameter, diameter, diameter), color, cframe)
	part.Shape = Enum.PartType.Ball
	return part
end

------------------------------------------------------------------------------------------
-- Araña y cangrejo. Cada pieza guarda su sitio respecto a la raíz; las patas se balancean.
-- El frente es -Z.
------------------------------------------------------------------------------------------

local function buildSpider()
	local model = Instance.new("Model")
	model.Name = "Arana"
	local rig = {}
	local function fixed(part: Part, cf: CFrame)
		table.insert(rig, { part = part, base = cf })
	end
	local purple = rgb(126, 74, 196)
	local lilac = rgb(162, 112, 232)
	local dark = rgb(70, 42, 110)

	local abdomen = blob(model, Vector3.new(7, 6, 8), purple)
	fixed(abdomen, CFrame.new(0, 4.4, 3))
	fixed(blob(model, Vector3.new(3.2, 0.9, 3.2), YELLOW), CFrame.new(0, 7.2, 3.3) * CFrame.Angles(math.rad(-10), 0, 0))
	fixed(blob(model, Vector3.new(5, 4.4, 4.6), lilac), CFrame.new(0, 3.8, -1.5))
	for _, s in { -1, 1 } do
		fixed(blob(model, Vector3.new(2, 2.4, 1.1), WHITE), CFrame.new(s * 1.05, 4.7, -3.6))
		fixed(blob(model, Vector3.new(0.9, 1.2, 0.5), INK), CFrame.new(s * 0.95, 4.5, -4.1))
		fixed(blob(model, Vector3.new(0.35, 0.4, 0.2), WHITE), CFrame.new(s * 0.8, 4.85, -4.35))
		fixed(blob(model, Vector3.new(0.5, 0.9, 0.5), CREAM), CFrame.new(s * 0.45, 2.1, -3.4))
	end
	fixed(blob(model, Vector3.new(1.6, 0.45, 0.4), INK), CFrame.new(0, 2.9, -3.75))

	local spread = { 0.55, 0.18, -0.18, -0.55 }
	local zs = { -2.6, -1.6, -0.4, 0.8 }
	for i = 1, 4 do
		for _, s in { -1, 1 } do
			table.insert(rig, {
				part = rod(model, 7, 0.7, dark),
				base = CFrame.new(s * 2, 3.6, zs[i]) * CFrame.Angles(0, s * spread[i], 0),
				side = s,
				half = 3.5,
				droop = 0.55,
				phase = i * math.pi / 2 + (if s > 0 then math.pi else 0),
			})
		end
	end
	return model, rig, abdomen, 0
end

local function buildCrab()
	local model = Instance.new("Model")
	model.Name = "Cangrejo"
	local rig = {}
	local function fixed(part: Part, cf: CFrame)
		table.insert(rig, { part = part, base = cf })
	end
	local red = rgb(240, 92, 58)
	local shine = rgb(255, 164, 128)
	local dark = rgb(196, 62, 40)

	local body = blob(model, Vector3.new(8.4, 4.4, 5.8), red)
	fixed(body, CFrame.new(0, 3.3, 0))
	fixed(blob(model, Vector3.new(4, 1, 2.6), shine), CFrame.new(-1.3, 5.2, 0.3) * CFrame.Angles(0, 0, math.rad(10)))
	fixed(blob(model, Vector3.new(2, 0.45, 0.4), INK), CFrame.new(0, 2.7, -2.85))
	for _, s in { -1, 1 } do
		fixed(rod(model, 2.6, 0.55, dark), CFrame.new(s * 1.3, 6.2, -1.5) * CFrame.Angles(0, 0, math.pi / 2))
		fixed(blob(model, Vector3.new(1.8, 2.1, 1.8), WHITE), CFrame.new(s * 1.3, 7.9, -1.6))
		fixed(blob(model, Vector3.new(0.8, 1, 0.4), INK), CFrame.new(s * 1.2, 7.8, -2.45))
		fixed(blob(model, Vector3.new(0.32, 0.36, 0.2), WHITE), CFrame.new(s * 1.0, 8.1, -2.6))
		fixed(rod(model, 3.4, 1, dark), CFrame.new(s * 4.3, 3.4, -2.3) * CFrame.Angles(0, s * math.rad(50), 0))
		fixed(blob(model, Vector3.new(2.8, 2.4, 3.2), red), CFrame.new(s * 5.4, 3.8, -4.6))
		-- Mitad de arriba de la pinza: se abre y se cierra
		table.insert(rig, { part = blob(model, Vector3.new(1.5, 1.1, 2.2), shine), base = CFrame.new(s * 5.6, 5, -3.6), jaw = true, reach = CFrame.new(0, 0, -1) })
	end

	local spread = { 0.35, 0, -0.35 }
	local zs = { -0.9, 0.5, 1.9 }
	for i = 1, 3 do
		for _, s in { -1, 1 } do
			table.insert(rig, {
				part = rod(model, 4.8, 0.6, dark),
				base = CFrame.new(s * 3.4, 2.8, zs[i]) * CFrame.Angles(0, s * spread[i], 0),
				side = s,
				half = 2.4,
				droop = 0.62,
				phase = i * 2.1 + (if s > 0 then math.pi else 0),
			})
		end
	end
	-- Camina de lado: el modelo gira un cuarto de vuelta respecto a la marcha
	return model, rig, body, math.pi / 2
end

local function createCreature(id: number, kind: string)
	local model, rig, body, turn
	if kind == "cangrejo" then
		model, rig, body, turn = buildCrab()
	else
		model, rig, body, turn = buildSpider()
	end

	-- Signo de exclamación mientras persigue
	local alert = Instance.new("BillboardGui")
	alert.Size = UDim2.fromOffset(70, 70)
	alert.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	alert.AlwaysOnTop = true
	alert.LightInfluence = 0
	alert.MaxDistance = 160
	alert.Enabled = false
	alert.Adornee = body
	alert.Parent = body
	local mark = Comic.label(alert, "!", Comic.Display, 64, Comic.Red)
	mark.Size = UDim2.fromScale(1, 1)
	Comic.ink(mark, 4)
	Comic.boil(mark, 8)

	model.Parent = folder
	local creature = {
		model = model,
		rig = rig,
		parts = {},
		alert = alert,
		turn = turn,
		lastPos = nil :: Vector3?,
		lastTime = 0,
		vel = Vector3.zero,
		shown = nil :: Vector3?,
		yaw = 0,
		shownYaw = 0,
		walk = 0,
		chase = false,
		happy = false,
	}
	for i, entry in rig do
		creature.parts[i] = entry.part
	end
	creatures[id] = creature
	return creature
end

local function onPositions(list)
	if type(list) ~= "table" then
		return
	end
	local clock = os.clock()
	for _, item in list do
		local id, kind, x, z, yaw, chase, happy = item[1], item[2], item[3], item[4], item[5], item[6], item[7]
		if type(id) ~= "number" or type(x) ~= "number" or type(z) ~= "number" then
			continue
		end
		local creature = creatures[id] or createCreature(id, kind)
		local p = Vector3.new(x, GROUND, z)
		local last = creature.lastPos
		if last then
			local dt = clock - creature.lastTime
			if (p - last).Magnitude > 30 then
				creature.shown = p -- salto grande: sin suavizar
				creature.vel = Vector3.zero
			elseif dt > 0.02 then
				local vel = (p - last) / dt
				creature.vel = if vel.Magnitude > 25 then vel.Unit * 25 else vel
			end
		else
			creature.shown = p
			creature.shownYaw = yaw
		end
		creature.lastPos = p
		creature.lastTime = clock
		creature.yaw = yaw
		creature.chase = chase == true
		creature.happy = happy == true
	end
end

local function drawCreature(creature, dt: number, clock: number)
	local last = creature.lastPos
	if not last then
		return
	end
	-- Un pelín por delante del último dato y suavizado hacia ahí
	local predicted = last + creature.vel * math.min(clock - creature.lastTime, 0.2)
	local before = creature.shown or predicted
	local shown = before:Lerp(predicted, 1 - math.exp(-14 * dt))
	creature.shown = shown

	local diff = (creature.yaw - creature.shownYaw + math.pi) % (math.pi * 2) - math.pi
	creature.shownYaw += diff * (1 - math.exp(-10 * dt))

	creature.alert.Enabled = creature.chase
	if not nearCamera(shown, DRAW_DISTANCE) then
		return
	end

	local speed = ((shown - before) * FLAT).Magnitude / math.max(dt, 1 / 240)
	creature.walk += dt * math.min(speed, 20) * 0.9
	local walk = creature.walk
	local hop = if creature.happy then math.abs(math.sin(clock * 12)) * 2 else 0
	local bob = 0.22 * math.abs(math.sin(walk)) + hop
	local root = CFrame.new(shown + Vector3.new(0, bob, 0)) * CFrame.Angles(0, creature.shownYaw + creature.turn, 0)

	local cframes = table.create(#creature.rig)
	for i, entry in creature.rig do
		if entry.side then
			local swing = math.sin(walk + entry.phase)
			local lift = math.max(swing, 0) * 0.2
			cframes[i] = root
				* entry.base
				* CFrame.Angles(0, swing * 0.22, 0)
				* CFrame.Angles(0, 0, -entry.side * (entry.droop - lift))
				* CFrame.new(entry.side * entry.half, 0, 0)
		elseif entry.jaw then
			local snap = if creature.chase then math.abs(math.sin(clock * 10)) * 0.5 else math.abs(math.sin(clock * 2)) * 0.15
			cframes[i] = root * entry.base * entry.reach:Inverse() * CFrame.Angles(snap, 0, 0) * entry.reach
		else
			cframes[i] = root * entry.base
		end
	end
	Workspace:BulkMoveTo(creature.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

------------------------------------------------------------------------------------------
-- Zapato y rodillo gigantes. Se construyen con la suela en y = 0 y el centro en el origen.
------------------------------------------------------------------------------------------

local function buildShoe(): Model
	local model = Instance.new("Model")
	model.Name = "Zapato"
	blob(model, Vector3.new(13, 2.6, 25), CREAM, CFrame.new(0, 1.3, 0))
	blob(model, Vector3.new(12, 9, 21), RED, CFrame.new(0, 5.2, 1.2))
	blob(model, Vector3.new(11, 6.5, 9.5), CREAM, CFrame.new(0, 3.8, -7.4))
	blob(model, Vector3.new(10, 8, 9), RED, CFrame.new(0, 10, 5.6))
	blob(model, Vector3.new(7, 1.2, 6), INK, CFrame.new(0, 13.9, 5.8))
	blob(model, Vector3.new(3.4, 5, 2.4), YELLOW, CFrame.new(0, 11, 10.2))
	for i, spot in { { -3.6, 9.3 }, { -1.2, 9.8 }, { 1.2, 10.3 } } do
		rod(model, 8, 0.9, WHITE, CFrame.new(0, spot[2], spot[1]) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 6 else -6)))
	end
	for _, s in { -1, 1 } do
		blob(model, Vector3.new(1.2, 4.6, 9), YELLOW, CFrame.new(s * 5.7, 5.4, 0.6))
	end
	model.WorldPivot = CFrame.new()
	return model
end

local function buildPin(): Model
	local model = Instance.new("Model")
	model.Name = "Rodillo"
	local wood = rgb(222, 168, 104)
	local dark = rgb(170, 112, 64)
	rod(model, 24, 8, wood, CFrame.new(0, 4, 0))
	blob(model, Vector3.new(18, 0.8, 1.6), rgb(245, 214, 170), CFrame.new(0, 7.75, -1.4))
	for _, s in { -1, 1 } do
		rod(model, 0.9, 8.3, RED, CFrame.new(s * 7, 4, 0))
		rod(model, 6, 2.6, dark, CFrame.new(s * 15, 4, 0))
		ball(model, 3.6, dark, CFrame.new(s * 19, 4, 0))
	end
	model.WorldPivot = CFrame.new()
	return model
end

local function shake(seconds: number, power: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local finish = os.clock() + seconds
		while os.clock() < finish and humanoid.Parent do
			local k = (finish - os.clock()) / seconds
			humanoid.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * power * k
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

local function impact(pos: Vector3, radius: number)
	local root = rootPart()
	local distance = if root then ((root.Position - pos) * FLAT).Magnitude else math.huge
	if distance < 60 then
		shake(0.45, 1.6 * (1 - distance / 80))
	end
	if distance < 140 then
		Sfx.pop(0.45)
	end
	-- Anillo de polvo que se abre
	local ring = newPart(Workspace, Vector3.new(0.3, radius * 2, radius * 2), CREAM, CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2))
	ring.Shape = Enum.PartType.Cylinder
	ring.CastShadow = false
	ring.Transparency = 0.3
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 3.4, radius * 3.4),
		Transparency = 1,
	}):Play()
	task.delay(0.5, function()
		ring:Destroy()
	end)
end

local function onStomp(info)
	if type(info) ~= "table" or typeof(info.pos) ~= "Vector3" then
		return
	end
	if not nearCamera(info.pos, DRAW_DISTANCE) then
		return
	end
	local pos = info.pos
	local warn = info.warn or 2.2
	local radius = info.radius or 10
	local isPin = info.kind == "rodillo"
	local model = if isPin then buildPin() else buildShoe()
	local yaw = rng:NextNumber(0, math.pi * 2)
	model:PivotTo(CFrame.new(pos + Vector3.new(0, 200, 0)))
	model.Parent = folder

	-- Sombra redonda que crece en el suelo
	local shadow = newPart(Workspace, Vector3.new(0.2, 4, 4), rgb(34, 24, 38), CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2))
	shadow.Name = "SombraPisoton"
	shadow.Shape = Enum.PartType.Cylinder
	shadow.CastShadow = false
	shadow.Transparency = 0.55

	local landed = false
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = Workspace:GetServerTimeNow() - info.hitAt -- negativo antes del golpe
		local clock = os.clock()
		if t > 1.4 then
			connection:Disconnect()
			model:Destroy()
			shadow:Destroy()
			return
		end
		local k = math.clamp(1 + t / warn, 0, 1)
		local r = 2 + (radius - 2) * k
		shadow.Size = Vector3.new(0.2, r * 2, r * 2)
		shadow.Transparency = if t < 0 then 0.55 - 0.25 * k else 0.3 + math.clamp(t / 1.2, 0, 1) * 0.7

		local y
		local wobble = 0
		if t < -0.16 then
			-- Baja despacio y se balancea, amenazando
			y = 22 + 40 * (1 - k) ^ 2 + math.sin(clock * 7) * 0.8
			wobble = math.sin(clock * 5) * 0.08
		elseif t < 0 then
			local q = (t + 0.16) / 0.16
			y = 22 * (1 - q * q)
		elseif t < 0.5 then
			y = 0
			if not landed then
				landed = true
				impact(pos, radius)
			end
		else
			local q = (t - 0.5) / 0.9
			y = 90 * q * q
		end

		local cf = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, yaw, 0)
		if isPin then
			-- El rodillo gira sobre su eje
			local roll = clock * 2.5
			cf *= CFrame.new(0, 4, 0) * CFrame.Angles(roll, 0, 0) * CFrame.new(0, -4, 0)
		else
			cf *= CFrame.Angles(wobble, 0, wobble * 0.5)
		end
		model:PivotTo(cf)
	end)
end

-- Aplastado: las piezas redondas de la hormiga se aplanan un momento. Solo visual.
local function squash(character: Model, mine: boolean)
	if squashing[character] then
		return
	end
	squashing[character] = true
	local meshes = {}
	for _, item in character:GetDescendants() do
		if item:IsA("SpecialMesh") then
			table.insert(meshes, { mesh = item, scale = item.Scale })
		end
	end
	local flat = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, entry in meshes do
		TweenService:Create(entry.mesh, flat, { Scale = entry.scale * Vector3.new(1.45, 0.3, 1.45) }):Play()
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = humanoid and humanoid.HipHeight
	if mine and humanoid then
		humanoid.HipHeight = hip * 0.35
		humanoid.WalkSpeed = 0
	end
	task.delay(SQUASH_TIME, function()
		local back = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		for _, entry in meshes do
			if entry.mesh.Parent then
				TweenService:Create(entry.mesh, back, { Scale = entry.scale }):Play()
			end
		end
		if mine and humanoid and humanoid.Parent then
			humanoid.HipHeight = hip
			humanoid.WalkSpeed = State.num("WalkSpeed")
		end
		task.delay(0.35, function()
			squashing[character] = nil
		end)
	end)
end

local function onPlaf(info)
	if type(info) ~= "table" or typeof(info.pos) ~= "Vector3" then
		return
	end
	local hit = info.hit or {}
	if #hit > 0 and nearCamera(info.pos, 160) then
		Fx.burst(info.pos + Vector3.new(0, 2, 0), "¡PLAF!", Comic.Red, 280)
	end
	for _, userId in hit do
		local victim = Players:GetPlayerByUserId(userId)
		local character = victim and victim.Character
		if character then
			squash(character, victim == player)
		end
	end
	if table.find(info.lost or {}, player.UserId) then
		Bubble.flash("¡Plaf! Se me cayó la carga", 3)
	end
end

local function onStolen(userId: number, id: number, at: Vector3, knock: Vector3)
	if typeof(at) == "Vector3" and nearCamera(at, 160) then
		Fx.burst(at, "¡Me robó\nla carga!", Comic.Red, 260)
	end
	local creature = creatures[id]
	if creature then
		creature.happy = true
	end
	if userId == player.UserId then
		local root = rootPart()
		if root and typeof(knock) == "Vector3" then
			root.AssemblyLinearVelocity = knock
		end
		Sfx.pop(0.6)
	end
end

function Hazards.start(remotes: Folder)
	local remote = remotes:WaitForChild("Hazard") :: RemoteEvent
	local posRemote = remotes:WaitForChild("HazardPos") :: UnreliableRemoteEvent

	folder = Instance.new("Model")
	folder.Name = "Peligros"
	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = folder
	folder.Parent = Workspace

	posRemote.OnClientEvent:Connect(onPositions)
	remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
		if kind == "Stomp" then
			onStomp(a)
		elseif kind == "Plaf" then
			onPlaf(a)
		elseif kind == "Stolen" then
			onStolen(a, b, c, d)
		end
	end)

	local last = os.clock()
	RunService.RenderStepped:Connect(function()
		local clock = os.clock()
		local dt = math.min(clock - last, 0.1)
		last = clock
		for _, creature in creatures do
			drawCreature(creature, dt, clock)
		end
	end)
end

return Hazards
