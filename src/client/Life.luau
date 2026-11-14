-- Vida: mariposas y abejas en el jardín y el huerto, luciérnagas en la jungla, banderolas de los
-- hormigueros ondeando con la brisa y nubes de cómic cruzando el cielo.
-- Todo es local (Workspace.Life) y se mueve con un solo BulkMoveTo por fotograma.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Life = {}

local INK = Color3.fromRGB(20, 16, 16)
local GROUND = Config.GroundY
local ACTIVE_IN = 160 -- se simulan los bichos a menos de esto de la cámara
local ACTIVE_OUT = 175 -- y se apagan pasado esto (margen para no parpadear)
local MAX_ACTIVE = 14
local AVOID = 9 -- si la cámara se acerca más que esto, el bicho se aparta
local FLAG_RANGE = 160
local CLOUD_WRAP = 320 -- las nubes van de -X a +X y vuelven a empezar

local rng = Random.new(7331)

local folder: Folder? = nil
local critters: Model? = nil
local cloudModel: Model? = nil
local connections: { RBXScriptConnection } = {}
local started = false

type Wing = { part: BasePart, sign: number, offset: number, z: number, y: number }
type Creature = {
	kind: string,
	body: BasePart,
	parts: { BasePart },
	wings: { Wing },
	extra: BasePart?, -- raya de la abeja o cola de la luciérnaga
	home: Vector3,
	amp: Vector3,
	freq: { number },
	phase: { number },
	speed: number,
	flapRate: number,
	seed: number,
	avoid: Vector3,
	look: Vector3,
	active: boolean,
}
type Cloud = { parts: { BasePart }, offsets: { CFrame }, x: number, y: number, z: number, speed: number }
type Flag = { rest: CFrame, hinge: Vector3, phase: number, amount: number }

local creatures: { Creature } = {}
local clouds: { Cloud } = {}
local flags: { [BasePart]: Flag } = {}

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Piezas ------------------------------------------------------------------------------------

local function blob(size: Vector3, color: Color3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = props ~= nil and props.shadow == true
	p.Material = if props and props.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.Transparency = if props and props.transparency then props.transparency else 0
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function cylinder(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Shape = Enum.PartType.Cylinder
	p.Size = size
	p.Color = color
	return p
end

local function inkOutline(model: Instance)
	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
end

-- Bichos ------------------------------------------------------------------------------------

local WING_COLORS = {
	{ Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 204, 80) },
	{ Color3.fromRGB(80, 170, 255), Color3.fromRGB(170, 224, 255) },
	{ Color3.fromRGB(255, 120, 180), Color3.fromRGB(255, 196, 224) },
	{ Color3.fromRGB(255, 220, 60), Color3.fromRGB(255, 246, 160) },
	{ Color3.fromRGB(170, 110, 240), Color3.fromRGB(214, 176, 255) },
	{ Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 226, 150) },
}

local function newCreature(kind: string, home: Vector3, amp: Vector3, speed: number): Creature
	local wings: { Wing } = {}
	local parts: { BasePart } = {}
	local body: BasePart
	local extra: BasePart? = nil
	local flapRate = 11

	if kind == "butterfly" then
		body = blob(Vector3.new(0.35, 0.35, 1.6), Color3.fromRGB(60, 44, 52))
		local colors = WING_COLORS[rng:NextInteger(1, #WING_COLORS)]
		for _, sign in { -1, 1 } do
			table.insert(wings, { part = blob(Vector3.new(1.7, 0.08, 1.3), colors[1]), sign = sign, offset = 0.95, z = -0.3, y = 0.05 })
			table.insert(wings, { part = blob(Vector3.new(1.15, 0.08, 0.95), colors[2]), sign = sign, offset = 0.7, z = 0.5, y = 0 })
		end
		flapRate = rng:NextNumber(9, 12)
	elseif kind == "bee" then
		body = blob(Vector3.new(0.9, 0.85, 1.25), Color3.fromRGB(255, 206, 40))
		extra = cylinder(Vector3.new(0.32, 0.92, 0.92), INK)
		for _, sign in { -1, 1 } do
			table.insert(wings, { part = blob(Vector3.new(0.75, 0.06, 0.45), Color3.fromRGB(240, 250, 255), { transparency = 0.3 }), sign = sign, offset = 0.38, z = 0.05, y = 0.38 })
		end
		flapRate = 44
	else -- luciérnaga
		body = blob(Vector3.new(0.35, 0.3, 0.7), Color3.fromRGB(56, 44, 40))
		extra = blob(Vector3.new(0.45, 0.4, 0.5), Color3.fromRGB(220, 255, 110), { neon = true })
		for _, sign in { -1, 1 } do
			table.insert(wings, { part = blob(Vector3.new(0.45, 0.04, 0.3), Color3.fromRGB(230, 240, 255), { transparency = 0.4 }), sign = sign, offset = 0.24, z = -0.05, y = 0.18 })
		end
		flapRate = 30
	end

	table.insert(parts, body)
	if extra then
		table.insert(parts, extra)
	end
	for _, wing in wings do
		table.insert(parts, wing.part)
	end

	return {
		kind = kind,
		body = body,
		parts = parts,
		wings = wings,
		extra = extra,
		home = home,
		amp = amp,
		freq = { rng:NextNumber(0.1, 0.16), rng:NextNumber(0.25, 0.4), rng:NextNumber(0.3, 0.55), rng:NextNumber(0.09, 0.15), rng:NextNumber(0.22, 0.36) },
		phase = { rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28) },
		speed = speed,
		flapRate = flapRate,
		seed = rng:NextNumber(0, 100),
		avoid = Vector3.zero,
		look = Vector3.new(0, 0, -1),
		active = false,
	}
end

-- Recorrido suave en bucle (Lissajous) alrededor de su casa
local function pathAt(c: Creature, t: number): Vector3
	local f, p, a = c.freq, c.phase, c.amp
	return c.home
		+ Vector3.new(
			a.X * (math.sin(t * f[1] + p[1]) * 0.75 + math.sin(t * f[2] + p[2]) * 0.25),
			a.Y * math.sin(t * f[3] + p[3]),
			a.Z * (math.cos(t * f[4] + p[4]) * 0.75 + math.sin(t * f[5] + p[5]) * 0.25)
		)
end

local function setActive(c: Creature, on: boolean)
	c.active = on
	local parent = if on then critters else nil
	for _, p in c.parts do
		p.Parent = parent
	end
end

local function zoneByTheme(theme: string)
	for _, zone in Config.Zones do
		if zone.theme == theme then
			return zone
		end
	end
	return nil
end

local function spawnCreatures()
	local radius = Config.Map.LobbyRadius
	local function inLobby(): Vector3
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * radius * 0.62
		return Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
	end
	local function inZone(zone, margin: number): Vector3
		local z0, z1 = zone.z0 - margin, zone.z1 + margin
		return Vector3.new(rng:NextNumber(-Config.Map.Half + margin, Config.Map.Half - margin), 0, rng:NextNumber(math.min(z0, z1), math.max(z0, z1)))
	end
	local function add(kind: string, spot: Vector3, baseY: number, amp: Vector3, speed: number)
		local c = newCreature(kind, spot + Vector3.new(0, GROUND + baseY, 0), amp, speed)
		table.insert(creatures, c)
	end

	-- Jardín: cinco mariposas y tres abejas
	for _ = 1, 5 do
		add("butterfly", inLobby(), rng:NextNumber(10, 15), Vector3.new(14, 3, 14), rng:NextNumber(1.4, 1.9))
	end
	for _ = 1, 3 do
		add("bee", inLobby(), rng:NextNumber(8, 12), Vector3.new(6, 1.5, 6), rng:NextNumber(2.6, 3.4))
	end

	local huerto = zoneByTheme("Huerto")
	if huerto then
		for _ = 1, 3 do
			add("butterfly", inZone(huerto, 22), rng:NextNumber(10, 15), Vector3.new(12, 3, 12), rng:NextNumber(1.4, 1.9))
		end
		for _ = 1, 3 do
			add("bee", inZone(huerto, 14), rng:NextNumber(8, 12), Vector3.new(6, 1.5, 6), rng:NextNumber(2.6, 3.4))
		end
	end

	local jungla = zoneByTheme("Jungla")
	if jungla then
		for _ = 1, 6 do
			add("firefly", inZone(jungla, 16), rng:NextNumber(9, 13), Vector3.new(9, 2.5, 9), rng:NextNumber(0.6, 0.9))
		end
	end
end

local function simulate(c: Creature, now: number, dt: number, camPos: Vector3, push: (BasePart, CFrame) -> ())
	local t = now * c.speed
	local target = pathAt(c, t)
	local ahead = pathAt(c, t + 0.2)

	-- Apartarse de la cámara cuando se acerca demasiado
	local away = target - camPos
	local distance = away.Magnitude
	local desired = Vector3.zero
	if distance < AVOID and distance > 0.01 then
		desired = away.Unit * (AVOID - distance) * 1.6
	end
	c.avoid = c.avoid:Lerp(desired, math.min(1, dt * 3))

	local pos = target + c.avoid
	if c.kind == "bee" then
		pos += Vector3.new(math.sin(now * 7.3 + c.seed) * 0.3, math.sin(now * 9.1 + c.seed) * 0.2, math.cos(now * 8.2 + c.seed) * 0.3)
	elseif c.kind == "butterfly" then
		pos += Vector3.new(0, math.sin(now * c.flapRate + c.seed + 1.6) * 0.22, 0)
	end
	pos = Vector3.new(pos.X, math.max(pos.Y, GROUND + 5.5), pos.Z)

	local dir = ahead - target
	local flat = Vector3.new(dir.X, dir.Y * 0.3, dir.Z)
	if Vector3.new(flat.X, 0, flat.Z).Magnitude > 1e-3 then
		local blended = c.look:Lerp(flat.Unit, math.min(1, dt * 5))
		if Vector3.new(blended.X, 0, blended.Z).Magnitude > 0.05 then
			c.look = blended.Unit
		end
	end
	local body = CFrame.lookAt(pos, pos + c.look)
	push(c.body, body)

	local flap
	if c.kind == "butterfly" then
		flap = 0.15 + 1.1 * (0.5 + 0.5 * math.sin(now * c.flapRate + c.seed))
	elseif c.kind == "bee" then
		flap = 0.35 + 0.45 * math.sin(now * c.flapRate + c.seed)
	else
		flap = 0.3 + 0.4 * math.sin(now * c.flapRate + c.seed)
	end
	for _, wing in c.wings do
		push(wing.part, body * CFrame.new(0, wing.y, wing.z) * CFrame.Angles(0, 0, wing.sign * flap) * CFrame.new(wing.sign * wing.offset, 0, 0))
	end

	local extra = c.extra
	if extra then
		if c.kind == "bee" then
			push(extra, body * CFrame.new(0, 0, 0.12) * CFrame.Angles(0, math.pi / 2, 0))
		else
			push(extra, body * CFrame.new(0, -0.05, 0.42))
			-- Parpadeo de luciérnaga: casi apagada y destellos cortos
			local pulse = (0.5 + 0.5 * math.sin(now * 1.7 + c.seed)) ^ 4
			extra.Transparency = 0.85 - 0.75 * pulse
		end
	end
end

-- Nubes -------------------------------------------------------------------------------------

local function spawnClouds()
	local count = 8
	local zFrom, zTo = 140, -440
	local white = Color3.fromRGB(255, 255, 255)
	local belly = Color3.fromRGB(196, 206, 226)
	for i = 1, count do
		local parts: { BasePart } = {}
		local offsets: { CFrame } = {}
		local scale = rng:NextNumber(0.8, 1.25)
		local bumps = rng:NextInteger(4, 5)
		local width = 0
		for k = 1, bumps do
			local w = rng:NextNumber(18, 28) * scale
			local h = rng:NextNumber(12, 18) * scale
			local d = rng:NextNumber(16, 22) * scale
			local x = (k - (bumps + 1) / 2) * 11 * scale + rng:NextNumber(-2, 2)
			-- Las del centro, más altas: forma de nube de dibujo
			local lift = (1 - math.abs(k - (bumps + 1) / 2) / bumps) * 6 * scale
			local p = blob(Vector3.new(w, h, d), white)
			table.insert(parts, p)
			table.insert(offsets, CFrame.new(x, lift + h * 0.2, rng:NextNumber(-3, 3)))
			width = math.max(width, math.abs(x) + w / 2)
		end
		-- Barriga plana y gris, asomando justo por debajo de los bultos blancos
		local under = blob(Vector3.new(width * 1.85, 3.2 * scale, 18 * scale), belly)
		table.insert(parts, under)
		table.insert(offsets, CFrame.new(0, -4.6 * scale, 0))
		for _, p in parts do
			p.Parent = cloudModel
		end
		local t = (i - 1) / (count - 1)
		table.insert(clouds, {
			parts = parts,
			offsets = offsets,
			x = rng:NextNumber(-CLOUD_WRAP, CLOUD_WRAP),
			y = GROUND + rng:NextNumber(110, 160),
			z = zFrom + (zTo - zFrom) * t + rng:NextNumber(-25, 25),
			speed = rng:NextNumber(1.6, 3.2),
		})
	end
end

-- Banderolas --------------------------------------------------------------------------------

local function addFlag(instance: Instance)
	if instance.Name ~= "Flag" or not instance:IsA("BasePart") or flags[instance] then
		return
	end
	local hinge = instance:GetAttribute("Hinge")
	local hasHinge = typeof(hinge) == "Vector3"
	local pivot: Vector3 = if hasHinge then hinge else instance.Position
	flags[instance] = {
		rest = instance.CFrame,
		hinge = pivot,
		phase = pivot.X * 0.37 + pivot.Z * 0.21,
		amount = if hasHinge then 1 else 0.35, -- sin mástil conocido, sólo un temblor
	}
end

local function watchAnthills()
	local hills = Workspace:WaitForChild("Anthills", 120)
	if not hills or not started then
		return
	end
	for _, d in hills:GetDescendants() do
		addFlag(d)
	end
	table.insert(connections, hills.DescendantAdded:Connect(addFlag))
	table.insert(connections, hills.DescendantRemoving:Connect(function(d)
		if flags[d :: any] then
			flags[d :: any] = nil
		end
	end))
end

-- Bucle -------------------------------------------------------------------------------------

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	dt = math.min(dt, 0.1)
	local camPos = camera.CFrame.Position
	local now = os.clock()

	table.clear(moveParts)
	table.clear(moveCFrames)
	local n = 0
	local function push(part: BasePart, cframe: CFrame)
		n += 1
		moveParts[n] = part
		moveCFrames[n] = cframe
	end

	-- Bichos: se encienden los cercanos, como mucho MAX_ACTIVE a la vez
	local activeCount = 0
	for _, c in creatures do
		if c.active then
			activeCount += 1
		end
	end
	for _, c in creatures do
		local distance = (c.home - camPos).Magnitude
		if c.active and distance > ACTIVE_OUT then
			setActive(c, false)
			activeCount -= 1
		elseif not c.active and distance < ACTIVE_IN and activeCount < MAX_ACTIVE then
			setActive(c, true)
			activeCount += 1
		end
		if c.active then
			simulate(c, now, dt, camPos, push)
		end
	end

	-- Banderolas: vaivén alrededor del mástil y un aleteo sobre su largo
	for part, flag in flags do
		if not part.Parent then
			flags[part] = nil
			continue
		end
		if (flag.hinge - camPos).Magnitude > FLAG_RANGE then
			continue
		end
		local phase = flag.phase
		local swing = (0.32 * math.sin(now * 1.9 + phase) + 0.12 * math.sin(now * 4.7 + phase * 2)) * flag.amount
		local flutter = 0.1 * math.sin(now * 6.3 + phase * 3) * flag.amount
		local h = flag.hinge
		local axis = flag.rest.LookVector
		local motion = CFrame.new(h) * CFrame.Angles(0, swing, 0) * CFrame.fromAxisAngle(axis, flutter) * CFrame.new(-h)
		push(part, motion * flag.rest)
	end

	-- Nubes: deriva lenta hacia +X y vuelta a empezar
	for _, cloud in clouds do
		cloud.x += cloud.speed * dt
		if cloud.x > CLOUD_WRAP then
			cloud.x -= CLOUD_WRAP * 2
		end
		local base = CFrame.new(cloud.x, cloud.y + math.sin(now * 0.2 + cloud.z) * 1.5, cloud.z)
		for i, p in cloud.parts do
			push(p, base * cloud.offsets[i])
		end
	end

	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Life.start()
	if started then
		return
	end
	started = true

	local existing = Workspace:FindFirstChild("Life")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Life"
		created.Parent = Workspace
		folder = created
	end

	local bugs = Instance.new("Model")
	bugs.Name = "Critters"
	inkOutline(bugs)
	bugs.Parent = folder
	critters = bugs

	local sky = Instance.new("Model")
	sky.Name = "Clouds"
	inkOutline(sky)
	sky.Parent = folder
	cloudModel = sky

	spawnCreatures()
	spawnClouds()

	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[CRUNCH!] Life:", err)
		end
	end))
	task.spawn(watchAnthills)
end

function Life.stop()
	if not started then
		return
	end
	started = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	-- Las banderolas son del servidor: vuelven a su pose original
	for part, flag in flags do
		if part.Parent then
			part.CFrame = flag.rest
		end
	end
	table.clear(flags)
	for _, c in creatures do
		for _, p in c.parts do
			p:Destroy()
		end
	end
	table.clear(creatures)
	table.clear(clouds)
	if critters then
		critters:Destroy()
		critters = nil
	end
	if cloudModel then
		cloudModel:Destroy()
		cloudModel = nil
	end
	if folder and #folder:GetChildren() == 0 then
		folder:Destroy()
	end
	folder = nil
end

return Life
