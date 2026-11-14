-- Comandante (cliente): la bandera de asalto, la Falange de soldados con casco, la ola de la
-- Marabunta, el estandarte y el casco con cresta del aura y el emblema.
-- Las obreras que asaltan la comida marcada las dibuja client/Swarm (el servidor pone esa comida en
-- el primer rastro del hormiguero); aquí va la bandera, el hilo dorado y el botín.
-- Los bichos se cuelgan del modelo "Swarm", que ya lleva el contorno de tinta.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Fx = require(script.Parent.Parent.CasteFx)
local Pop = require(script.Parent.Parent.Fx) -- números de cómic de la dueña

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad

local INK = Color3.fromRGB(20, 16, 16)
local NAVY = Color3.fromRGB(34, 52, 112)
local NAVY_DARK = Color3.fromRGB(22, 32, 72)
local GOLD = Color3.fromRGB(255, 196, 48)
local RED = Color3.fromRGB(220, 50, 60)
local CRUMB = Color3.fromRGB(222, 166, 92)
local WHITE = Color3.new(1, 1, 1)
local GROUND = Config.GroundY

local rng = Random.new()

---------------------------------------------------------------------------------------------------
-- Ayudas
---------------------------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function later(payload, seconds: number, fn: () -> ())
	local lag = if type(payload.t) == "number" then math.max(0, serverNow() - payload.t) else 0
	local wait = seconds - lag
	if wait <= 0.01 then
		task.spawn(fn)
	else
		task.delay(wait, fn)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function numbers(mine: boolean, points: any, amounts: any)
	if not mine or type(points) ~= "table" then
		return
	end
	for i, p in points do
		local amount = type(amounts) == "table" and tonumber(amounts[i]) or 0
		if typeof(p) == "Vector3" and amount and amount > 0 then
			Pop.number(p, amount)
		end
	end
end

local function loot(caster: Player, points: any, color: Color3?)
	if type(points) ~= "table" or #points == 0 then
		return
	end
	local hill = Fx.hillOf(caster)
	if hill then
		Fx.orbs(points, hill, { color = color or GOLD })
	end
end

local function inkParent(): Instance
	return Workspace:FindFirstChild("Swarm") or Fx.folder()
end

local function piece(parent: Instance, size: Vector3, color: Color3, kind: string, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color
	if kind == "blob" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif kind == "rod" then
		p.Shape = Enum.PartType.Cylinder
	elseif kind == "ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.Parent = parent
	return p
end

local function along(pos: Vector3, dir: Vector3): CFrame
	if dir.Magnitude < 1e-4 then
		return CF(pos)
	end
	return CFrame.lookAt(pos, pos + dir) * ANG(0, rad(90), 0)
end

local function fadeOut(model: Instance, time: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(time), { Transparency = 1 }):Play()
		elseif d:IsA("Beam") then
			d.Enabled = false
		end
	end
	Debris:AddItem(model, time + 0.05)
end

---------------------------------------------------------------------------------------------------
-- Bichos (mismo dibujo que las obreras de client/Swarm, con su equipo)
---------------------------------------------------------------------------------------------------

local LEG_YAW = { -38, 0, 38 }

local function newBug(k: number, body: Color3, dark: Color3, lite: boolean, decorate: ((any, number) -> ())?)
	local model = Instance.new("Model")
	model.Name = "GeneralBug"
	local bug = {
		model = model,
		parts = {} :: { BasePart },
		offsets = {} :: { CFrame },
		legs = {} :: { number },
		cframes = {} :: { CFrame },
		k = k,
		stride = rng:NextNumber(0, 4),
		pos = Vector3.zero,
		heading = -Vector3.zAxis,
		dead = false,
	}
	local function add(size: Vector3, color: Color3, offset: CFrame, kind: string, material: Enum.Material?): (Part, number)
		local p = piece(model, size, color, kind, material)
		p.CFrame = CF(0, -200, 0)
		table.insert(bug.parts, p)
		table.insert(bug.offsets, offset)
		return p, #bug.parts
	end
	bug.add = add
	add(V3(1, 0.9, 1.3) * k, dark, CF(0, 0.05 * k, 0.72 * k), "blob")
	add(V3(0.62, 0.58, 0.62) * k, body, CF(), "blob")
	add(V3(0.95, 0.85, 0.85) * k, body, CF(0, 0.1 * k, -0.62 * k), "blob")
	for _, s in { -1, 1 } do
		add(V3(0.3, 0.38, 0.2) * k, WHITE, CF(s * 0.2 * k, 0.2 * k, -0.98 * k), "blob")
		if not lite then
			add(V3(0.14, 0.2, 0.1) * k, INK, CF(s * 0.19 * k, 0.17 * k, -1.06 * k), "blob")
			local base = V3(s * 0.2 * k, 0.45 * k, -0.8 * k)
			local dir = V3(s * 0.45, 0.8, -0.5).Unit
			add(V3(0.75 * k, 0.07 * k, 0.07 * k), INK, along(base + dir * 0.37 * k, dir), "rod")
		end
	end
	for _ = 1, (if lite then 1 else 3) do
		local _, index = add(V3(2 * k, 0.11 * k, 0.11 * k), INK, CF(), "rod")
		table.insert(bug.legs, index)
	end
	if decorate then
		decorate(bug, k)
	end
	model.Parent = inkParent()
	return bug
end

local function poseBug(bug, moved: number, extra: CFrame?)
	if bug.dead then
		return
	end
	bug.stride += moved
	local k = bug.k
	local step = bug.stride * (1.6 / math.max(k, 0.5))
	local up = bug.pos + V3(0, 0.1 + 0.4 * k + math.abs(math.sin(step * 2)) * 0.1 * k, 0)
	local base = CFrame.lookAt(up, up + bug.heading)
	if extra then
		base *= extra
	end
	local pose = math.floor(step) % 2
	for i, offset in bug.offsets do
		bug.cframes[i] = base * offset
	end
	for j, index in bug.legs do
		local swing = if (j + pose) % 2 == 0 then 14 else -14
		bug.cframes[index] = base * CF(0, -0.2 * k, 0) * ANG(0, rad((LEG_YAW[j] or 0) + swing), 0)
	end
	Workspace:BulkMoveTo(bug.parts, bug.cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function steer(bug, target: Vector3, speed: number, dt: number, face: Vector3?): number
	local goal = V3(target.X, GROUND, target.Z)
	local gap = goal - bug.pos
	local dist = gap.Magnitude
	local step = math.min(dist, speed * dt)
	if dist > 1e-3 then
		bug.pos += gap * (step / dist)
	end
	local want = if dist > 0.6 then V3(gap.X, 0, gap.Z) else (face or bug.heading)
	if want.Magnitude > 0.05 then
		local turned = bug.heading:Lerp(want.Unit, math.min(1, dt * 9))
		bug.heading = if turned.Magnitude > 0.1 then turned.Unit else want.Unit
	end
	return step
end

local function killBug(bug, time: number?)
	if bug.dead then
		return
	end
	bug.dead = true
	Fx.burst(bug.pos + V3(0, 1, 0), { color = Color3.fromRGB(190, 160, 120), count = 5, size = 0.5, life = 0.35 })
	fadeOut(bug.model, time or 0.35)
end

local function soldierBug(k: number, ring: boolean, lance: boolean)
	return newBug(k, NAVY, NAVY_DARK, false, function(bug, s)
		-- Casco de oro con cresta roja
		bug.add(V3(1, 0.62, 0.9) * s, GOLD, CF(0, 0.38 * s, -0.6 * s), "blob")
		for i = -1, 1 do
			bug.add(V3(0.2, 0.32, 0.3) * s, RED, CF(0, 0.72 * s, (-0.6 + i * 0.22) * s), "blob")
		end
		-- Mandíbulas
		for _, x in { -1, 1 } do
			bug.add(V3(0.16, 0.14, 0.5) * s, INK, CF(x * 0.2 * s, -0.05 * s, -1.15 * s) * ANG(0, -x * rad(25), 0), "blob")
		end
		if ring then
			-- Tortuga: escudo redondo con borde de oro
			bug.add(V3(0.14 * s, 1.1 * s, 1.1 * s), GOLD, CF(-0.55 * s, 0.25 * s, -0.1 * s), "rod")
			bug.add(V3(0.16 * s, 0.9 * s, 0.9 * s), NAVY, CF(-0.58 * s, 0.25 * s, -0.1 * s), "rod")
		end
		if lance then
			bug.add(V3(2.4 * s, 0.09 * s, 0.09 * s), INK, along(V3(0.45 * s, 0.35 * s, -0.5 * s), V3(0, 0.45, -1)), "rod")
			bug.add(V3(0.2, 0.2, 0.45) * s, GOLD, CF(0.45 * s, 0.85 * s, -1.6 * s) * ANG(rad(25), 0, 0), "blob")
		end
	end)
end

-- Sitio de cada soldado (la misma cuenta que el servidor)
local function slotOf(root: CFrame, i: number, count: number, ring: boolean): Vector3
	if ring then
		local angle = (i - 1) / count * math.pi * 2
		return (root * CF(math.cos(angle) * 5.5, 0, math.sin(angle) * 5.5)).Position
	end
	local row = math.ceil(i / 2)
	local side = if i % 2 == 0 then 1 else -1
	return (root * CF(side * row * 2.8, 0, 2 + row * 2.6)).Position
end

---------------------------------------------------------------------------------------------------
-- Bandera de asalto
---------------------------------------------------------------------------------------------------

local flags: { [Player]: any } = {}

local function flagModel(): (Model, { BasePart }, { CFrame })
	local model = Instance.new("Model")
	model.Name = "GeneralFlag"
	local parts, offsets = {}, {}
	local function add(size, color, offset, kind, material)
		local p = piece(model, size, color, kind, material)
		table.insert(parts, p)
		table.insert(offsets, offset)
	end
	add(V3(6, 0.25, 0.25), INK, CF(0, 3, 0) * ANG(0, 0, rad(90)), "rod")
	add(V3(0.6, 0.6, 0.6), GOLD, CF(0, 6.2, 0), "ball", Enum.Material.Neon)
	add(V3(0.25, 2, 3), NAVY, CF(0, 5, 1.55), "blob")
	add(V3(0.3, 0.9, 0.9), GOLD, CF(0, 5, 1.6), "blob", Enum.Material.Neon)
	add(V3(0.28, 0.35, 3), GOLD, CF(0, 4.05, 1.55), "blob")
	model.Parent = inkParent()
	return model, parts, offsets
end

local function placeFlag(f, at: Vector3, clock: number)
	local base = CF(at)
	local cframes = {}
	for i, offset in f.offsets do
		local wave = if i >= 3 then ANG(0, math.sin(clock * 5 + i) * 0.25, 0) else CF()
		cframes[i] = base * wave * offset
	end
	Workspace:BulkMoveTo(f.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function dropFlag(caster: Player)
	local f = flags[caster]
	if not f then
		return
	end
	flags[caster] = nil
	f.connection:Disconnect()
	if f.hillPart then
		f.hillPart:Destroy()
	end
	fadeOut(f.model, 0.35)
end

local function plantFlag(caster: Player, at: Vector3, radius: number, duration: number)
	dropFlag(caster)
	local model, parts, offsets = flagModel()
	local f = {
		model = model,
		parts = parts,
		offsets = offsets,
		at = at + V3(0, radius * 0.6, 0),
		from = at + V3(0, 40, 0),
		landAt = os.clock() + 0.25,
		untilClock = os.clock() + duration,
	}
	-- Hilo dorado del hormiguero a la bandera: por ahí van las obreras
	local hill = Fx.hillOf(caster)
	local flagAtt = Instance.new("Attachment")
	flagAtt.Position = V3(0, 0, 0)
	flagAtt.Parent = parts[2]
	if hill then
		local hillPart = Instance.new("Part")
		hillPart.Anchored = true
		hillPart.CanCollide = false
		hillPart.CanQuery = false
		hillPart.CanTouch = false
		hillPart.Transparency = 1
		hillPart.Size = V3(0.2, 0.2, 0.2)
		hillPart.CFrame = CF(hill + V3(0, 3, 0))
		hillPart.Parent = Fx.folder()
		local hillAtt = Instance.new("Attachment")
		hillAtt.Parent = hillPart
		local beam = Instance.new("Beam")
		beam.Attachment0 = hillAtt
		beam.Attachment1 = flagAtt
		beam.Color = ColorSequence.new(GOLD)
		beam.Transparency = NumberSequence.new(0.35)
		beam.Width0 = 0.6
		beam.Width1 = 0.35
		beam.LightEmission = 0.7
		beam.FaceCamera = true
		beam.Segments = 16
		beam.CurveSize0 = 8
		beam.CurveSize1 = -8
		beam.Parent = hillPart
		f.hillPart = hillPart
	end
	f.connection = RunService.Heartbeat:Connect(function()
		local clock = os.clock()
		local u = math.clamp(1 - (f.landAt - clock) / 0.25, 0, 1)
		placeFlag(f, f.from:Lerp(f.at, u * u), clock)
		if clock > f.untilClock then
			dropFlag(caster)
		end
	end)
	flags[caster] = f
	return f
end

---------------------------------------------------------------------------------------------------
-- Falange
---------------------------------------------------------------------------------------------------

local phalanxes: { [Player]: any } = {}

local function endPhalanx(caster: Player)
	local p = phalanxes[caster]
	if not p then
		return
	end
	phalanxes[caster] = nil
	p.connection:Disconnect()
	for i, bug in p.bugs do
		task.delay(i * 0.06, function()
			killBug(bug, 0.4)
		end)
	end
	local root = rootOf(caster)
	if root then
		Fx.word(root.Position + V3(0, 5, 0), "¡ROMPAN FILAS!", { color = GOLD, size = 37, life = 0.7 })
	end
end

local function startPhalanx(caster: Player, payload, mine: boolean)
	endPhalanx(caster)
	local root = rootOf(caster)
	if not root then
		return
	end
	local count = math.clamp(math.floor(tonumber(payload.count) or 6), 1, 12)
	local ring = payload.ring == true
	local lance = payload.lance == true
	local p = { bugs = {}, ring = ring }
	phalanxes[caster] = p
	for i = 1, count do
		local bug = soldierBug(1.3, ring, lance)
		local spot = slotOf(root.CFrame, i, count, ring)
		bug.pos = V3(spot.X, GROUND, spot.Z)
		local look = root.CFrame.LookVector * V3(1, 0, 1)
		bug.heading = if look.Magnitude > 0.05 then look.Unit else -Vector3.zAxis
		bug.drop = 1 -- caen del cielo al aparecer
		table.insert(p.bugs, bug)
	end
	local at = root.Position
	Fx.word(at + V3(0, 6, 0), if ring then "¡TORTUGA!" elseif lance then "¡LANCEROS!" else "¡FALANGE!", { color = GOLD, size = 60 })
	Fx.ring(at, 8, { color = GOLD, life = 0.45, thickness = 0.8 })
	Fx.sound("thud", at, 0.8)
	if mine then
		Fx.shake(0.25, 0.25)
	end

	p.connection = RunService.Heartbeat:Connect(function(rawDt)
		local dt = math.min(rawDt, 0.1)
		local r = rootOf(caster)
		if not r then
			return
		end
		local look = r.CFrame.LookVector * V3(1, 0, 1)
		look = if look.Magnitude > 0.05 then look.Unit else -Vector3.zAxis
		for i, bug in p.bugs do
			if bug.dead then
				continue
			end
			local spot = slotOf(r.CFrame, i, count, ring)
			local moved
			local extra: CFrame? = nil
			if bug.lunge then
				-- Embestida: sale hacia la comida y vuelve a su sitio
				local u = (os.clock() - bug.lunge.t0) / 0.32
				if u >= 1 then
					bug.lunge = nil
					moved = steer(bug, spot, 40, dt, look)
				else
					local reach = bug.lunge.to
					local goal = V3(spot.X, GROUND, spot.Z):Lerp(V3(reach.X, GROUND, reach.Z), math.sin(u * math.pi) * 0.85)
					local before = bug.pos
					bug.pos = goal
					local face = V3(reach.X - spot.X, 0, reach.Z - spot.Z)
					if face.Magnitude > 0.1 then
						bug.heading = face.Unit
					end
					moved = (goal - before).Magnitude
					extra = ANG(-math.sin(u * math.pi) * 0.35, 0, 0)
				end
			else
				local gap = (V3(spot.X, GROUND, spot.Z) - bug.pos).Magnitude
				moved = steer(bug, spot, math.clamp(gap * 4, 3, 50), dt, if ring then V3(spot.X - r.Position.X, 0, spot.Z - r.Position.Z) else look)
			end
			if bug.drop and bug.drop > 0 then
				bug.drop = math.max(bug.drop - dt * 4, 0)
				extra = CF(0, bug.drop * bug.drop * 18, 0) * (extra or CF())
				if bug.drop == 0 then
					Fx.burst(bug.pos + V3(0, 0.4, 0), { color = Color3.fromRGB(190, 160, 120), count = 5, size = 0.5, life = 0.3 })
				end
			end
			poseBug(bug, moved, extra)
		end
	end)

	later(payload, tonumber(payload.duration) or 12, function()
		if phalanxes[caster] == p then
			endPhalanx(caster)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Marabunta: la ola de hormigas
---------------------------------------------------------------------------------------------------

local function waveAnt(): any
	return newBug(0.95, Color3.fromRGB(232, 62, 48), Color3.fromRGB(180, 40, 40), true, nil)
end

local function runLine(origin: Vector3, dir: Vector3, length: number, width: number, travel: number, windup: number)
	local cols = math.clamp(math.floor(width / 2.6), 4, 12)
	local rows = 3
	local side = dir:Cross(Vector3.yAxis).Unit
	local ants = {}
	for r = 1, rows do
		for c = 1, cols do
			local bug = waveAnt()
			local lateral = ((c - 0.5) / cols - 0.5) * width + rng:NextNumber(-0.6, 0.6)
			bug.lateral = lateral
			bug.back = (r - 1) * 2.2 + rng:NextNumber(-0.5, 0.5)
			bug.heading = dir
			bug.pos = V3(origin.X, GROUND, origin.Z) + side * lateral * 0.15 - dir * bug.back
			table.insert(ants, bug)
		end
	end
	local began = os.clock()
	local dustAt = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - began
		local u = math.clamp((t - windup) / travel, 0, 1)
		-- Al principio salen en abanico desde ti hasta ocupar todo el ancho
		local spread = math.clamp((t - windup * 0.5) / 0.35, 0.15, 1)
		for _, bug in ants do
			local front = V3(origin.X, GROUND, origin.Z) + dir * (length * u - bug.back) + side * bug.lateral * spread
			local before = bug.pos
			bug.pos = front
			poseBug(bug, (front - before).Magnitude)
		end
		if t > dustAt and u > 0 and u < 1 then
			dustAt = t + 0.15
			local mid = V3(origin.X, GROUND, origin.Z) + dir * length * u
			Fx.burst(mid + side * rng:NextNumber(-width / 2, width / 2), { color = Color3.fromRGB(190, 160, 120), count = 4, size = 0.9, life = 0.5, speed = 6 })
		end
		if u >= 1 then
			connection:Disconnect()
			for i, bug in ants do
				task.delay(i * 0.01, function()
					killBug(bug, 0.3)
				end)
			end
		end
	end)
end

local function runVortex(origin: Vector3, startDir: Vector3, travel: number, windup: number)
	local count = 30
	local radius = 26
	local base = math.atan2(startDir.Z, startDir.X)
	local ants = {}
	for i = 1, count do
		local bug = waveAnt()
		bug.lag = (i - 1) / count * 0.9 -- vueltas de retraso (la cola del remolino)
		bug.r = radius * (0.35 + 0.65 * ((i * 7) % count) / count)
		bug.pos = V3(origin.X, GROUND, origin.Z)
		table.insert(ants, bug)
	end
	local began = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - began
		local u = math.clamp((t - windup) / travel, 0, 1.15)
		for _, bug in ants do
			local turn = math.clamp(u - bug.lag * 0.15, 0, 1.1)
			local angle = base + turn * math.pi * 2
			local out = bug.r * math.clamp(t / (windup + 0.2), 0.1, 1)
			local pos = V3(origin.X + math.cos(angle) * out, GROUND, origin.Z + math.sin(angle) * out)
			local before = bug.pos
			bug.pos = pos
			local tangent = V3(-math.sin(angle), 0, math.cos(angle))
			bug.heading = tangent
			poseBug(bug, (pos - before).Magnitude)
		end
		if u >= 1.15 then
			connection:Disconnect()
			for _, bug in ants do
				killBug(bug, 0.3)
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Aura: estandarte a la espalda y casco con cresta
---------------------------------------------------------------------------------------------------

local function weldTo(anchor: BasePart, part: BasePart, offset: CFrame): Weld
	part.Anchored = false
	part.Massless = true
	part.CFrame = anchor.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = anchor
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
	return w
end

local function aura(character: Model, rank: number, mastered: boolean): () -> ()
	local folder = Instance.new("Folder")
	folder.Name = "GeneralAura"
	folder.Parent = character
	local alive = true
	local flagWelds: { { weld: Weld, base: CFrame } } = {}
	local anchorWeld: Weld? = nil

	local function build()
		folder:ClearAllChildren()
		table.clear(flagWelds)
		anchorWeld = nil
		local thorax = character:FindFirstChild("Thorax") :: BasePart?
		local head = character:FindFirstChild("Head") :: BasePart?
		if not thorax or not head then
			return
		end
		local sc = character:GetScale()
		local s = sc * (1 + 0.04 * math.clamp(rank, 1, 10))
		local pole = (2.6 + 0.12 * math.clamp(rank, 1, 10)) * sc
		local trim = if mastered then Enum.Material.Neon else Enum.Material.SmoothPlastic

		-- Asta a la espalda, un poco inclinada hacia atrás
		local poleAt = CF(0.55 * sc, 0.4 * sc + pole / 2, 0.7 * sc) * ANG(rad(-10), 0, 0)
		anchorWeld = weldTo(thorax, piece(folder, V3(pole, 0.16 * s, 0.16 * s), INK, "rod"), poleAt * ANG(0, 0, rad(90)))
		weldTo(thorax, piece(folder, V3(0.4, 0.4, 0.4) * s, GOLD, "ball", trim), poleAt * CF(0, pole / 2 + 0.15 * s, 0))
		-- Bandera azul con estrella de oro y fleco; ondea (ver abajo)
		local flagBase = poleAt * CF(0, pole / 2 - 0.65 * s, 0.75 * s)
		local cloth = piece(folder, V3(0.14 * s, 1.15 * s, 1.5 * s), NAVY, "blob")
		table.insert(flagWelds, { weld = weldTo(thorax, cloth, flagBase), base = flagBase })
		local star = piece(folder, V3(0.18 * s, 0.5 * s, 0.5 * s), GOLD, "blob", trim)
		table.insert(flagWelds, { weld = weldTo(thorax, star, flagBase * CF(0, 0, 0.1 * s)), base = flagBase * CF(0, 0, 0.1 * s) })
		local fringe = piece(folder, V3(0.16 * s, 0.2 * s, 1.5 * s), GOLD, "blob")
		table.insert(flagWelds, { weld = weldTo(thorax, fringe, flagBase * CF(0, -0.55 * s, 0)), base = flagBase * CF(0, -0.55 * s, 0) })

		-- Casco de oro con cresta roja (cada vez más alta con el rango)
		weldTo(head, piece(folder, V3(2.2, 1.15, 1.75) * sc, GOLD, "blob", trim), CF(0, 0.45 * sc, 0.12 * sc))
		weldTo(head, piece(folder, V3(2.25, 0.25, 1.8) * sc, NAVY_DARK, "blob"), CF(0, 0.2 * sc, 0.12 * sc))
		local crest = 3 + math.floor(math.clamp(rank, 1, 10) / 4)
		for i = 1, crest do
			local z = (i - (crest + 1) / 2) * 0.32 * sc
			weldTo(head, piece(folder, V3(0.28, 0.55 + 0.04 * rank, 0.38) * sc, if i % 2 == 0 then GOLD else RED, "blob"), CF(0, 1.05 * sc, 0.12 * sc + z))
		end
	end
	build()

	local player = Players:GetPlayerFromCharacter(character)
	local isMe = player == Players.LocalPlayer
	local ringAt = 0
	local checkAt = 0
	local connection = RunService.Heartbeat:Connect(function()
		if not alive then
			return
		end
		local clock = os.clock()
		if clock > checkAt then
			checkAt = clock + 0.5
			if not anchorWeld or not anchorWeld.Parent or not anchorWeld.Part0 or not anchorWeld.Part0.Parent then
				build()
			end
		end
		for i, item in flagWelds do
			item.weld.C0 = item.base * ANG(0, math.sin(clock * 4 + i * 0.4) * 0.22, 0)
		end
		-- La dueña ve de vez en cuando hasta dónde llega su estandarte
		if isMe and player and clock > ringAt then
			ringAt = clock + 4
			local radius = tonumber(player:GetAttribute("GeneralRadius"))
			local root = rootOf(player)
			if radius and root then
				Fx.ring(root.Position, radius, { color = GOLD, life = 1.2, thickness = 0.35 })
			end
		end
	end)

	return function()
		alive = false
		connection:Disconnect()
		folder:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- Emblema: estandarte con estrella
---------------------------------------------------------------------------------------------------

local function emblem(parent: GuiObject, color: Color3)
	local holder = Instance.new("Frame")
	holder.Name = "GeneralEmblem"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent

	local pole = Instance.new("Frame")
	pole.AnchorPoint = Vector2.new(0.5, 0.5)
	pole.Position = UDim2.fromScale(0.3, 0.52)
	pole.Size = UDim2.fromScale(0.08, 0.84)
	pole.BackgroundColor3 = INK
	pole.BorderSizePixel = 0
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = pole
	pole.Parent = holder

	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.3, 0.1)
	knob.Size = UDim2.fromScale(0.16, 0.16)
	knob.BackgroundColor3 = GOLD
	knob.BorderSizePixel = 0
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob
	local ks = Instance.new("UIStroke")
	ks.Color = INK
	ks.Thickness = 2
	ks.Parent = knob
	knob.Parent = holder

	local flag = Instance.new("Frame")
	flag.Position = UDim2.fromScale(0.33, 0.16)
	flag.Size = UDim2.fromScale(0.56, 0.42)
	flag.Rotation = -4
	flag.BackgroundColor3 = color
	flag.BorderSizePixel = 0
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.25, 0)
	fc.Parent = flag
	local fs = Instance.new("UIStroke")
	fs.Color = INK
	fs.Thickness = 3
	fs.Parent = flag
	flag.Parent = holder

	local star = Instance.new("TextLabel")
	star.BackgroundTransparency = 1
	star.Size = UDim2.fromScale(1, 1)
	star.Text = "★"
	star.TextScaled = true
	star.TextColor3 = GOLD
	star.Font = Enum.Font.GothamBlack
	local ss = Instance.new("UIStroke")
	ss.Color = INK
	ss.Thickness = 2
	ss.Parent = star
	star.Parent = flag
end

---------------------------------------------------------------------------------------------------
-- Efectos
---------------------------------------------------------------------------------------------------

local fx = {}

function fx.general1(caster: Player, payload, mine: boolean)
	local at = payload.at
	if typeof(at) ~= "Vector3" then
		return
	end
	local duration = tonumber(payload.duration) or 8
	local radius = tonumber(payload.radius) or 2
	local root = rootOf(caster)
	if root then
		Fx.word(root.Position + V3(0, 5, 0), if payload.all then "¡TODAS!" else "¡A POR ESA!", { color = GOLD, size = 55 })
	end
	Fx.sound("whoosh", at, 1)
	plantFlag(caster, at, radius, duration)
	task.delay(0.25, function()
		Fx.ring(at, radius + 6, { color = GOLD, life = 0.45, thickness = 0.8 })
		Fx.burst(at + V3(0, radius * 0.5, 0), { color = GOLD, count = 12, speed = 16, size = 0.7, life = 0.5, up = 0.7 })
		Fx.word(at + V3(0, radius + 5, 0), "¡AL ASALTO!", { color = GOLD, size = 51 })
		Fx.light(at, { color = GOLD, range = 18, life = 0.4 })
		Fx.sound("thud", at, 1.1)
		if mine then
			Fx.shake(0.2, 0.2)
		end
	end)
end

function fx.general1_tick(caster: Player, payload, mine: boolean)
	local at = payload.at
	if typeof(at) ~= "Vector3" then
		return
	end
	local f = flags[caster]
	if f and ((f.at - at) * V3(1, 0, 1)).Magnitude > 2 then
		-- La comida se movió (una Tejedora la arrastró): la bandera va con ella
		f.from = f.at
		f.at = at + V3(0, 1.2, 0)
		f.landAt = os.clock() + 0.25
	end
	Fx.ring(at, 5, { color = GOLD, life = 0.35, thickness = 0.4 })
	loot(caster, { at }, GOLD)
	if mine and math.random() < 0.4 then
		Fx.word(at + V3(0, 4, 0), "x2", { color = GOLD, size = 32, life = 0.5 })
	end
end

function fx.general1_jump(caster: Player, payload, mine: boolean)
	local from, to = payload.from, payload.to
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local f = flags[caster]
	if f then
		f.from = f.at
		f.at = to + V3(0, 1.2, 0)
		f.landAt = os.clock() + 0.25
		f.untilClock = os.clock() + (tonumber(payload.duration) or 4)
	else
		plantFlag(caster, to, 2, tonumber(payload.duration) or 4)
	end
	Fx.lob(from, to, { color = GOLD, size = 0.6, time = 0.25, height = 6 })
	Fx.word(to + V3(0, 5, 0), "¡SIGUIENTE!", { color = GOLD, size = 41 })
	if mine then
		Fx.sound("chime", to, 1.2)
	end
end

function fx.general1_none(_caster: Player, payload, mine: boolean)
	if mine and typeof(payload.at) == "Vector3" then
		Fx.word(payload.at + V3(0, 4, 0), "¡SIN OBRERAS!", { color = RED, size = 41 })
	end
end

function fx.general2(caster: Player, payload, mine: boolean)
	startPhalanx(caster, payload, mine)
end

function fx.general2_hit(caster: Player, payload, mine: boolean)
	local points, who = payload.points, payload.who
	if type(points) ~= "table" then
		return
	end
	local p = phalanxes[caster]
	for i, point in points do
		local index = type(who) == "table" and tonumber(who[i]) or i
		local bug = p and p.bugs[index]
		if bug and not bug.dead then
			bug.lunge = { to = point, t0 = os.clock() }
		end
		task.delay(0.12, function()
			Fx.burst(point, { color = GOLD, count = 5, size = 0.5, life = 0.3, speed = 10 })
		end)
	end
	if math.random() < 0.35 then
		Fx.word(points[1] + V3(0, 3, 0), "¡HUA!", { color = GOLD, size = 32, life = 0.45 })
	end
	Fx.sound("slash", points[1], 1.3)
	task.delay(0.15, function()
		loot(caster, points)
	end)
	numbers(mine, points, payload.amounts)
end

function fx.general3(caster: Player, payload, mine: boolean)
	local origin = payload.origin
	if typeof(origin) ~= "Vector3" then
		return
	end
	local travel = math.max(tonumber(payload.travel) or 1.6, 0.3)
	local windup = tonumber(payload.windup) or 0.35
	local length = tonumber(payload.length) or 100
	local width = tonumber(payload.width) or 30
	local dirs = if type(payload.dirs) == "table" then payload.dirs else {}

	-- Anticipación: corneta, el suelo tiembla, aro que se cierra sobre ti
	Fx.word(origin + V3(0, 7, 0), "¡MARABUNTA!", { color = GOLD, size = 74 })
	Fx.ring(origin, 12, { color = GOLD, life = windup + 0.1, thickness = 1 })
	Fx.light(origin + V3(0, 2, 0), { color = GOLD, range = 24, life = windup + 0.2 })
	Fx.sound("boom", origin, 0.7)
	if mine then
		Fx.flash(GOLD, 0.25, 0.25)
		Fx.shake(0.45, windup + travel)
	end

	if payload.vortex then
		local first = dirs[1]
		runVortex(origin, if typeof(first) == "Vector3" then first else Vector3.xAxis, travel, windup)
		Fx.dome(origin, 26, windup + travel, { color = GOLD })
	else
		for _, dir in dirs do
			if typeof(dir) == "Vector3" then
				runLine(origin, dir, length, width, travel, windup)
				later(payload, windup, function()
					Fx.wave(origin, origin + dir * length, width, { color = GOLD, time = travel, height = 1.2 })
				end)
			end
		end
	end
end

function fx.general3_hit(caster: Player, payload, mine: boolean)
	local points = payload.points
	if type(points) ~= "table" then
		return
	end
	for _, p in points do
		Fx.burst(p, { color = CRUMB, count = 8, speed = 16, size = 0.7, life = 0.45, up = 0.8 })
		Fx.ring(p, 4, { color = GOLD, life = 0.3 })
	end
	if math.random() < 0.5 then
		Fx.word(points[1] + V3(0, 3, 0), "¡ÑAM ÑAM!", { color = GOLD, size = 41, life = 0.5 })
	end
	Fx.sound("pop", points[1], 0.9)
	loot(caster, points)
	numbers(mine, points, payload.amounts)
end

function fx.general_horn(caster: Player, payload, mine: boolean)
	local at = payload.at
	if typeof(at) ~= "Vector3" then
		return
	end
	Fx.word(at + V3(0, 6, 0), "¡TUTURUUU!", { color = GOLD, size = 46 })
	Fx.sound("chime", at, 0.8)
	if typeof(payload.hill) == "Vector3" then
		Fx.ring(payload.hill, 14, { color = GOLD, life = 0.6, thickness = 0.8 })
		Fx.pillar(payload.hill, { color = GOLD, height = 18, width = 3, life = 0.6 })
	end
	if mine then
		Fx.flash(GOLD, 0.15, 0.2)
	end
end

Players.PlayerRemoving:Connect(function(player)
	endPhalanx(player)
	dropFlag(player)
end)

return {
	fx = fx,
	aura = aura,
	emblem = emblem,
}
