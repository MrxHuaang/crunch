-- Mejoras que cambian cómo juegas, en el cliente (ver src/server/Extras.luau):
--   mordisco cargado (un brillo que crece en tus mandíbulas y un pitido que sube), doble mandíbula,
--   buche, puesto avanzado (entrega y relevo de hormiguitas hacia casa), comida gigante, lluvia propia
--   (migas que caen y se recogen) y la senda de feromonas: tus rastros marcados brillan en el suelo y,
--   mientras pisas uno, vas más rápido (como correr, la velocidad la decide el cliente: Abilities.speedBoost).
-- Los momentos llegan por el remoto "Extras". Nada de texto fijo en pantalla: todo pasa en el mundo.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Abilities = require(script.Parent.Abilities)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Targeting = require(script.Parent.Targeting)

local Extras = {}

local player = Players.LocalPlayer
local rng = Random.new()
local X = Config.Extras

local NEAR = 220 -- efectos que solo se ven si pasan cerca de la cámara
local LANE_COLOR = Color3.fromRGB(120, 255, 200)
local LANE_PIECE = 1500 -- una pieza no puede medir más de 2048 studs: las sendas largas van en trozos
local LANE_Y = Config.GroundY + 0.15
local CHARGE_COLOR = Color3.fromRGB(255, 220, 80)
local CHARGE_FULL = Color3.fromRGB(255, 90, 60)
local ANT = Color3.fromRGB(40, 28, 26)

-- Lo que dice tu hormiga al estrenar cada mejora (la lluvia la explica el árbol con su tecla)
local INTRO = {
	charged = "Si me quedo quieta junto a la comida, cargo un mordisco enorme",
	doubleJaw = "¡Ahora muerdo dos comidas a la vez!",
	buche = "Con el buche, parte de cada entrega se viene conmigo",
	outpost = "Tengo puesto avanzado en mi zona más honda: puedo entregar allí",
	giantFood = "De vez en cuando, una comida a mi alrededor crecerá enorme",
	lane = "Mis rastros brillan: si camino por ellos, voy volando",
}

local fxFolder: Folder
local chargeFrom: number? = nil
local lastBite = -math.huge
local chargeStep = 0
local chargeOrb: Part? = nil
local boost = 1
local onLane = false
local ownSegments: { { a: Vector3, b: Vector3 } } = {}
local lanes: { [Player]: { Part } } = {}
local crumbs: { [number]: { [number]: any } } = {} -- [UserId][id] = { part, mark }

---------------------------------------------------------------------------------------------------
-- Piezas

local function newPart(size: Vector3, color: Color3, kind: string?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	if kind == "rod" then
		p.Shape = Enum.PartType.Cylinder
	elseif kind == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = fxFolder
	return p
end

local function near(position: Vector3): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < NEAR
end

-- Onda en el suelo que se abre y se apaga
local function ring(position: Vector3, radius: number, color: Color3, life: number)
	local p = newPart(Vector3.new(0.3, 1.5, 1.5), color, "rod")
	p.Transparency = 0.1
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, life + 0.1)
end

local function rootOf(target: Player?): (BasePart?, Humanoid?)
	local character = target and target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function mouthOf(target: Player): Vector3?
	local root = rootOf(target)
	if not root then
		return nil
	end
	local scale = (target.Character :: Model):GetScale()
	return root.Position + root.CFrame.LookVector * (1.6 * scale) + Vector3.new(0, 0.3 * scale, 0)
end

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player") and value.Parent ~= nil
end

local function color3(value: any): Color3
	return if typeof(value) == "Color3" then value else Comic.Crumb
end

---------------------------------------------------------------------------------------------------
-- Mordisco cargado: brillo en tus mandíbulas mientras cargas

local function hideOrb()
	if chargeOrb then
		chargeOrb.Parent = nil
	end
	chargeStep = 0
end

local function updateCharge(now: number)
	local stats = State.stats()
	local root = rootOf(player)
	local charging = (stats.chargeMax or 0) > 0
		and root ~= nil
		and State.num("Carry") < stats.capacity
		and Targeting.current() ~= nil
		and now - lastBite >= X.Charged.Pause
	if not charging then
		chargeFrom = nil
		hideOrb()
		return
	end
	chargeFrom = chargeFrom or now
	local u = math.clamp((now - (chargeFrom :: number)) / stats.chargeMax, 0, 1)
	local mouth = mouthOf(player)
	if not mouth then
		hideOrb()
		return
	end
	local orb = chargeOrb
	if not orb then
		orb = newPart(Vector3.one, CHARGE_COLOR, "ball")
		orb.Material = Enum.Material.Neon
		chargeOrb = orb
	end
	local scale = (player.Character :: Model):GetScale()
	local pulse = 1 + 0.12 * math.sin(now * (10 + 16 * u))
	local side = (0.5 + 2.1 * u) * scale * pulse
	orb.Size = Vector3.new(side, side, side)
	orb.Color = CHARGE_COLOR:Lerp(CHARGE_FULL, u)
	orb.Transparency = 0.6 - 0.35 * u
	orb.CFrame = CFrame.new(mouth)
	orb.Parent = fxFolder
	-- Un pitido que sube por cada cuarto de carga
	local step = math.floor(u * 4 + 1e-6)
	if step > chargeStep then
		chargeStep = step
		Sfx.pop(0.8 + 0.28 * step)
	end
end

---------------------------------------------------------------------------------------------------
-- Senda de feromonas

local function hillOf(target: Player): Model?
	if target == player then
		return State.hill()
	end
	local hills = Workspace:FindFirstChild("Anthills")
	if not hills then
		return nil
	end
	for _, hill in hills:GetChildren() do
		if hill:IsA("Model") and hill:GetAttribute("OwnerId") == target.UserId then
			return hill
		end
	end
	return nil
end

-- Tramos de senda de una jugadora: de casa (o de su puesto, si la comida está más allá) a cada rastro marcado
local function segmentsOf(target: Player): { { a: Vector3, b: Vector3 } }
	local list = {}
	local level = target:GetAttribute("N_lane")
	local hill = hillOf(target)
	if type(level) ~= "number" or level <= 0 or not hill or hill:GetAttribute("Auto") ~= false then
		return list
	end
	local home = hill:GetPivot().Position
	local scale = hill:GetAttribute("Scale")
	local outpost, edge = hill:GetAttribute("OutpostPos"), hill:GetAttribute("OutpostZ")
	local marked = hill:GetAttribute("Marked") -- con escuadrones, solo los primeros huecos son rastros
	for i = 1, if type(marked) == "number" then math.min(marked, 3) else 3 do
		local food = hill:GetAttribute("TrailPos" .. i)
		if typeof(food) == "Vector3" then
			local base, gap = home, 9 * (if type(scale) == "number" then scale else 1)
			if typeof(outpost) == "Vector3" and type(edge) == "number" and food.Z <= edge then
				base, gap = outpost, 4
			end
			local flat = (food - base) * Vector3.new(1, 0, 1)
			local length = flat.Magnitude
			local radius = hill:GetAttribute("TrailRadius" .. i)
			local stop = length - (if type(radius) == "number" then radius else 1)
			if stop > gap + 1 then
				local dir = flat / length
				local a = Vector3.new(base.X, LANE_Y, base.Z) + dir * gap
				local b = Vector3.new(base.X, LANE_Y, base.Z) + dir * stop
				table.insert(list, { a = a, b = b })
			end
		end
	end
	return list
end

local function drawLanes(target: Player, segments, now: number)
	local parts = lanes[target]
	if not parts then
		parts = {}
		lanes[target] = parts
	end
	local used = 0
	local glow = 0.5 + 0.12 * math.sin(now * 3)
	for _, seg in segments do
		local total = (seg.b - seg.a).Magnitude
		local pieces = math.max(1, math.ceil(total / LANE_PIECE))
		for k = 1, pieces do
			local a = seg.a:Lerp(seg.b, (k - 1) / pieces)
			local b = seg.a:Lerp(seg.b, k / pieces)
			used += 1
			local p = parts[used]
			if not p then
				p = newPart(Vector3.one, LANE_COLOR)
				p.Material = Enum.Material.Neon
				parts[used] = p
			end
			p.Size = Vector3.new(X.Lane.Width * 0.8, 0.12, (b - a).Magnitude)
			p.CFrame = CFrame.lookAt((a + b) / 2, b)
			p.Transparency = glow
			p.Parent = fxFolder
		end
	end
	for i = #parts, used + 1, -1 do
		parts[i]:Destroy()
		parts[i] = nil
	end
end

local function dropLanes(target: Player)
	local parts = lanes[target]
	if parts then
		for _, p in parts do
			p:Destroy()
		end
		lanes[target] = nil
	end
end

local function updateLanes(now: number)
	for _, target in Players:GetPlayers() do
		local segments = segmentsOf(target)
		if #segments == 0 and not lanes[target] then
			continue
		end
		drawLanes(target, segments, now)
		if target == player then
			ownSegments = segments
		end
	end
end

-- Distancia en planta de un punto a un tramo
local function toSegment(point: Vector3, a: Vector3, b: Vector3): number
	local ab = (b - a) * Vector3.new(1, 0, 1)
	local ap = (point - a) * Vector3.new(1, 0, 1)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

local function updateBoost()
	local stats = State.stats()
	local root = rootOf(player)
	local inside = false
	if root and (stats.laneMult or 1) > 1 then
		for _, seg in ownSegments do
			if toSegment(root.Position, seg.a, seg.b) <= X.Lane.Width then
				inside = true
				break
			end
		end
	end
	if inside and not onLane then
		Sfx.pop(1.45)
	end
	onLane = inside
	boost = if inside then stats.laneMult else 1
end

---------------------------------------------------------------------------------------------------
-- Lluvia propia

local function dropCrumb(userId: number, id: number, taken: boolean)
	local list = crumbs[userId]
	local c = list and list[id]
	if not c then
		return
	end
	list[id] = nil
	if c.mark then
		c.mark:Destroy()
	end
	local part = c.part
	if taken then
		local owner = Players:GetPlayerByUserId(userId)
		local mouth = owner and mouthOf(owner)
		if mouth then
			TweenService:Create(part, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(mouth),
				Size = part.Size * 0.4,
			}):Play()
			Debris:AddItem(part, 0.25)
			if owner == player then
				Sfx.pop(1.6 + rng:NextNumber(0, 0.3))
			end
			return
		end
	end
	TweenService:Create(part, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	Debris:AddItem(part, 0.45)
end

local function addCrumb(userId: number, id: number, position: Vector3, fall: number, color: Color3)
	local list = crumbs[userId]
	if not list then
		list = {}
		crumbs[userId] = list
	end
	-- Una sombra clara en el suelo dice dónde va a caer
	local mark = newPart(Vector3.new(0.1, 2.6, 2.6), Comic.Paper, "rod")
	mark.Transparency = 0.55
	mark.CFrame = CFrame.new(position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local part = newPart(Vector3.new(1.5, 1.1, 1.4), color, "ball")
	local rest = CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	part.CFrame = rest + Vector3.new(0, 45, 0)
	TweenService:Create(part, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = rest }):Play()
	list[id] = { part = part, mark = mark }
	task.delay(fall, function()
		if list[id] and list[id].part == part then
			if near(position) then
				Fx.crumbs(position + Vector3.new(0, 0.5, 0), color, 3)
			end
			-- Se queda botando un poco para que se vea
			TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				CFrame = rest + Vector3.new(0, 0.5, 0),
			}):Play()
		end
	end)
end

local function dropAllCrumbs(userId: number)
	local list = crumbs[userId]
	if not list then
		return
	end
	for id in list do
		dropCrumb(userId, id, false)
	end
	crumbs[userId] = nil
end

---------------------------------------------------------------------------------------------------
-- Sucesos del servidor

-- Relevo del puesto: una fila de hormiguitas corre del puesto hacia casa
local function relay(from: Vector3, home: Vector3)
	local flat = (home - from) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 1 then
		return
	end
	local dir = flat.Unit
	local ground = Vector3.new(from.X, Config.GroundY + 0.35, from.Z)
	for i = 1, 7 do
		local ant = newPart(Vector3.new(0.5, 0.35, 0.8), ANT, "ball")
		local side = dir:Cross(Vector3.yAxis) * rng:NextNumber(-0.6, 0.6)
		local a = ground + dir * 3 + side
		ant.CFrame = CFrame.lookAt(a, a + dir) + Vector3.new(0, -50, 0)
		task.delay((i - 1) * 0.1, function()
			ant.CFrame = CFrame.lookAt(a, a + dir)
			TweenService:Create(ant, TweenInfo.new(1.6, Enum.EasingStyle.Linear), {
				CFrame = CFrame.lookAt(a + dir * 38, a + dir * 39),
				Transparency = 1,
			}):Play()
		end)
		Debris:AddItem(ant, (i - 1) * 0.1 + 1.7)
	end
end

local function onEvent(kind: string, a: any, b: any, c: any, d: any, e: any, f: any)
	local mine = a == player
	if kind == "Charged" and isPlayer(a) and typeof(b) == "Vector3" then
		local ratio = math.clamp(tonumber(d) or 0.5, 0, 1)
		if mine then
			lastBite = os.clock()
			chargeFrom = nil
			hideOrb()
			Fx.shake(0.3 + 0.5 * ratio)
			Fx.number(b + Vector3.new(0, 2, 0), tonumber(c) or 0, true)
			Sfx.bite(true)
			Sfx.pop(0.55)
		end
		if near(b) then
			Fx.burst(b, "¡ÑAAAM!", Comic.Red, 170 + 90 * ratio)
			Fx.crumbs(b, nil, 6 + math.floor(8 * ratio))
			ring(b - Vector3.new(0, 0.6, 0), 3 + 5 * ratio, CHARGE_COLOR, 0.35)
		end
	elseif kind == "Jaw" and isPlayer(a) and typeof(c) == "Vector3" then
		if near(c) then
			if typeof(b) == "Instance" and b:IsA("Model") and b.Parent then
				Fx.squash(b)
			end
			Fx.crumbs(c + Vector3.new(0, 1, 0), color3(e), 3)
			ring(c + Vector3.new(0, 0.2, 0), (tonumber(d) or 2) + 0.8, Comic.Paper, 0.25)
		end
	elseif kind == "Buche" then
		local mouth = mouthOf(player)
		if mouth then
			Fx.crumbs(mouth, nil, 4)
			Fx.burst(mouth + Vector3.new(0, 2, 0), "¡Buche!", Comic.Green, 120)
		end
		Sfx.pop(0.75)
	elseif kind == "OutpostUp" and isPlayer(a) and typeof(b) == "Vector3" then
		if near(b) then
			ring(b + Vector3.new(0, 0.2, 0), 10, Comic.DirtLight, 0.6)
			Fx.crumbs(b + Vector3.new(0, 3, 0), Comic.DirtLight, 10)
		end
		if mine then
			local zone = Config.Zones[State.depth()]
			Bubble.flash("Mi puesto avanzado ya está en " .. (if zone then zone.name else "mi zona más honda"), 5)
		end
	elseif kind == "Outpost" and isPlayer(a) and typeof(b) == "Vector3" then
		if mine then
			local credited = tonumber(c) or 0
			if d == true then
				Fx.burst(b, "¡DOBLE!\n+" .. Format.short(credited), Comic.Yellow, 240)
			else
				Fx.burst(b, "+" .. Format.short(credited), Comic.Cyan, 200)
			end
			-- (Fx.deposit tira las migajas hacia el hormiguero de casa: aquí caen en el puesto)
			Fx.crumbs(b, nil, 8)
			Fx.shake(if d == true then 0.35 else 0.15)
			Sfx.deposit()
			Hud.punchFood()
		end
		if near(b) and typeof(e) == "Vector3" then
			relay(b, e)
		end
	elseif kind == "Giant" and isPlayer(a) and typeof(c) == "Vector3" then
		local radius = tonumber(d) or 4
		if near(c) then
			Fx.burst(c + Vector3.new(0, radius + 4, 0), "¡GIGANTE!", Comic.Yellow, 260)
			ring(c + Vector3.new(0, 0.3, 0), radius * 1.8, Comic.Yellow, 0.6)
			task.delay(0.1, ring, c + Vector3.new(0, 0.3, 0), radius * 1.3, Comic.Paper, 0.5)
			Fx.crumbs(c + Vector3.new(0, radius, 0), nil, 12)
			Sfx.pop(0.5)
		end
		if mine then
			Sfx.fanfare()
			Fx.shake(0.3)
		end
	elseif kind == "RainCrumb" and type(a) == "number" and type(b) == "number" and typeof(c) == "Vector3" then
		addCrumb(a, b, c, math.max(tonumber(d) or 1, 0.2), color3(e))
	elseif kind == "RainTaken" and type(a) == "number" and type(b) == "number" then
		dropCrumb(a, b, true)
	elseif kind == "RainGone" and type(a) == "number" and type(b) == "number" then
		dropCrumb(a, b, false)
	end
end

-- Al estrenar una mejora, tu hormiga cuenta qué hace (una vez por mejora y sesión, no al entrar)
local known: { [string]: boolean } = {}
local primed = false
local function announce()
	if not State.flag("Loaded") then
		return
	end
	local nodes = State.nodes()
	for id, text in INTRO do
		local has = (nodes[id] or 0) > 0
		if primed and has and not known[id] then
			Bubble.flash(text, 6)
		end
		known[id] = has
	end
	primed = true
end

function Extras.start(remotes: Folder)
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ExtrasFx"
	fxFolder.Parent = Workspace

	Abilities.speedBoost = function(): number
		return boost
	end

	-- Tus mordiscos aceptados (para saber cuándo paras de morder)
	remotes.Fx.OnClientEvent:Connect(function(kind: string)
		if kind == "Bite" then
			lastBite = os.clock()
		end
	end)

	Players.PlayerRemoving:Connect(function(target)
		dropLanes(target)
		dropAllCrumbs(target.UserId)
	end)
	State.onChange(announce)

	local laneAt = 0
	local pausedUntil = 0 -- tras un fallo, descansa unos segundos en vez de avisar cada fotograma
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < pausedUntil then
			return
		end
		local ok, err = pcall(function()
			updateCharge(now)
			if now >= laneAt then
				laneAt = now + 0.25
				updateLanes(now)
			end
			updateBoost()
		end)
		if not ok then
			warn("[CRUNCH!] Extras:", err)
			pausedUntil = now + 5
			boost = 1
		end
	end)

	local found = remotes:WaitForChild("Extras", 30)
	if found and found:IsA("RemoteEvent") then
		found.OnClientEvent:Connect(onEvent)
	else
		warn("[CRUNCH!] Falta el remoto Extras")
	end
end

return Extras
