-- Porteadora (cliente): la saca que vuela al hormiguero, la caravana de porteadoras con cesto, el
-- escarabajo-vagón del Convoy, las alforjas y el cesto del aura y el emblema.
-- Las criaturas se dibujan con piezas redondeadas en el estilo de las obreras (client/Swarm) y se
-- cuelgan del modelo "Swarm", que ya lleva el contorno de tinta (así no hace falta otro Highlight).

local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
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
local LEATHER = Color3.fromRGB(150, 96, 56)
local LEATHER_DARK = Color3.fromRGB(104, 62, 36)
local TURQ = Color3.fromRGB(48, 214, 200)
local GOLD = Color3.fromRGB(255, 200, 60)
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

-- Ejecuta fn a los `seconds` de cuando el servidor lanzó el efecto (descuenta el retraso de red)
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
		Fx.orbs(points, hill, { color = color or CRUMB })
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

-- CFrame con el eje X (el de los cilindros) apuntando en `dir`
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
		end
	end
	Debris:AddItem(model, time + 0.05)
end

---------------------------------------------------------------------------------------------------
-- Bichos: hormigas y escarabajos de piezas redondeadas que andan con patas
---------------------------------------------------------------------------------------------------

local LEG_YAW = { -38, 0, 38 }

local function newBug(k: number, body: Color3, dark: Color3, decorate: ((any, number) -> ())?)
	local model = Instance.new("Model")
	model.Name = "PorterBug"
	local bug = {
		model = model,
		parts = {} :: { BasePart },
		offsets = {} :: { CFrame },
		legs = {} :: { number },
		wheels = {} :: { number },
		spin = 0,
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
	add(V3(1, 0.9, 1.3) * k, dark, CF(0, 0.05 * k, 0.72 * k), "blob") -- abdomen
	add(V3(0.62, 0.58, 0.62) * k, body, CF(), "blob") -- tórax
	add(V3(0.95, 0.85, 0.85) * k, body, CF(0, 0.1 * k, -0.62 * k), "blob") -- cabeza
	for _, s in { -1, 1 } do
		add(V3(0.3, 0.38, 0.2) * k, WHITE, CF(s * 0.2 * k, 0.2 * k, -0.98 * k), "blob")
		add(V3(0.14, 0.2, 0.1) * k, INK, CF(s * 0.19 * k, 0.17 * k, -1.06 * k), "blob")
		local base = V3(s * 0.2 * k, 0.45 * k, -0.8 * k)
		local dir = V3(s * 0.45, 0.8, -0.5).Unit
		add(V3(0.75 * k, 0.07 * k, 0.07 * k), INK, along(base + dir * 0.37 * k, dir), "rod")
		add(V3(0.16, 0.16, 0.16) * k, INK, CF(base + dir * 0.78 * k), "blob")
	end
	for _ = 1, 3 do
		local _, index = add(V3(2 * k, 0.11 * k, 0.11 * k), INK, CF(), "rod")
		table.insert(bug.legs, index)
	end
	if decorate then
		decorate(bug, k)
	end
	model.Parent = inkParent()
	return bug
end

local function poseBug(bug, moved: number)
	if bug.dead then
		return
	end
	bug.stride += moved
	local k = bug.k
	local step = bug.stride * (1.6 / math.max(k, 0.5))
	local lift = 0.1 + 0.4 * k
	local up = bug.pos + V3(0, lift + math.abs(math.sin(step * 2)) * 0.1 * k, 0)
	local base = CFrame.lookAt(up, up + bug.heading)
	local pose = math.floor(step) % 2
	for i, offset in bug.offsets do
		bug.cframes[i] = base * offset
	end
	for j, index in bug.legs do
		local swing = if (j + pose) % 2 == 0 then 14 else -14
		bug.cframes[index] = base * CF(0, -0.2 * k, 0) * ANG(0, rad(LEG_YAW[j] + swing), 0)
	end
	if #bug.wheels > 0 then
		bug.spin += moved / math.max(0.7 * k, 0.5)
		for _, index in bug.wheels do
			bug.cframes[index] = base * bug.offsets[index] * ANG(bug.spin, 0, 0)
		end
	end
	Workspace:BulkMoveTo(bug.parts, bug.cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Avanza hacia `target` sin pasar de `speed`; gira el rumbo con suavidad. Devuelve lo andado.
local function steer(bug, target: Vector3, speed: number, dt: number): number
	local goal = V3(target.X, GROUND, target.Z)
	local gap = goal - bug.pos
	local dist = gap.Magnitude
	if dist < 1e-3 then
		return 0
	end
	local step = math.min(dist, speed * dt)
	bug.pos += gap * (step / dist)
	local flat = V3(gap.X, 0, gap.Z)
	if flat.Magnitude > 0.05 then
		local turned = bug.heading:Lerp(flat.Unit, math.min(1, dt * 9))
		bug.heading = if turned.Magnitude > 0.1 then turned.Unit else flat.Unit
	end
	return step
end

local function killBug(bug, time: number?)
	if bug.dead then
		return
	end
	bug.dead = true
	Fx.burst(bug.pos + V3(0, 1, 0), { color = Color3.fromRGB(190, 160, 120), count = 6, size = 0.6, life = 0.4 })
	fadeOut(bug.model, time or 0.35)
end

-- Porteadora con cesto a la espalda (el montoncito de dentro se ve cuando va cargada)
local function porterBug(k: number)
	return newBug(k, LEATHER, LEATHER_DARK, function(bug, s)
		bug.add(V3(0.8, 0.95, 0.95) * s, LEATHER_DARK, CF(0, 0.75 * s, 0.35 * s) * ANG(0, 0, rad(90)), "rod")
		bug.add(V3(0.14, 1.05, 1.05) * s, TURQ, CF(0, 1.02 * s, 0.35 * s) * ANG(0, 0, rad(90)), "rod")
		bug.add(V3(0.1, 1.02, 1.02) * s, TURQ, CF(0, 0.62 * s, 0.35 * s) * ANG(0, 0, rad(90)), "rod")
		local load, index = bug.add(V3(0.8, 0.55, 0.8) * s, CRUMB, CF(0, 1.15 * s, 0.35 * s), "blob")
		load.Transparency = 1
		bug.load = load
		bug.loadIndex = index
	end)
end

local function setLoad(bug, full: boolean, color: Color3?)
	if bug.load then
		bug.load.Transparency = if full then 0 else 1
		if color then
			bug.load.Color = color
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Saca que vuela en arco (Catapulta)
---------------------------------------------------------------------------------------------------

local function sack(size: number, color: Color3, golden: boolean): Model
	local model = Instance.new("Model")
	model.Name = "PorterSack"
	local bag = piece(model, V3(1.2, 1, 1.2) * size, LEATHER, "blob")
	bag.Name = "Bag"
	local strap = piece(model, V3(0.25 * size, 1.25 * size, 1.25 * size), TURQ, "rod")
	strap.Name = "Strap"
	local knot = piece(model, V3(0.45, 0.45, 0.45) * size, LEATHER_DARK, "blob")
	knot.Name = "Knot"
	local heap = piece(model, V3(0.9, 0.6, 0.9) * size, if golden then GOLD else color, "blob", if golden then Enum.Material.Neon else nil)
	heap.Name = "Heap"
	local a0 = Instance.new("Attachment")
	a0.Position = V3(0, 0.4 * size, 0)
	a0.Parent = bag
	local a1 = Instance.new("Attachment")
	a1.Position = V3(0, -0.4 * size, 0)
	a1.Parent = bag
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(TURQ, WHITE)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.35
	trail.LightEmission = 0.4
	trail.Parent = bag
	model.Parent = inkParent()
	return model
end

local function placeSack(model: Model, at: CFrame, size: number)
	local bag = model:FindFirstChild("Bag") :: BasePart
	local strap = model:FindFirstChild("Strap") :: BasePart
	local knot = model:FindFirstChild("Knot") :: BasePart
	local heap = model:FindFirstChild("Heap") :: BasePart
	Workspace:BulkMoveTo({ bag, strap, knot, heap }, {
		at,
		at * ANG(0, 0, rad(90)),
		at * CF(0, 0.55 * size, 0),
		at * CF(0, 0.35 * size, 0.2 * size),
	}, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Arco de a a b en `time` segundos; onLand al llegar
local function flySack(model: Model, size: number, a: Vector3, b: Vector3, time: number, height: number, onLand: () -> ())
	local began = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local u = math.clamp((os.clock() - began) / math.max(time, 0.05), 0, 1)
		local p = a:Lerp(b, u) + V3(0, height * 4 * u * (1 - u), 0)
		placeSack(model, CF(p) * ANG(u * 9, u * 4, 0), size)
		if u >= 1 then
			connection:Disconnect()
			onLand()
		end
	end)
end

local function impact(at: Vector3, radius: number, word: string, color: Color3, mine: boolean, shake: number)
	Fx.ring(at, radius, { color = color, life = 0.45, thickness = 0.8 })
	Fx.burst(at, { color = color, count = 14, speed = 22, size = 0.9, life = 0.6, up = 0.6 })
	Fx.word(at + V3(0, 3, 0), word, { color = color, size = 55 })
	Fx.light(at, { color = color, range = radius * 2, life = 0.4 })
	Fx.sound("thud", at, 0.9)
	if mine then
		Fx.shake(shake, 0.25)
	end
end

---------------------------------------------------------------------------------------------------
-- Caravanas vivas por jugadora
---------------------------------------------------------------------------------------------------

local caravans: { [Player]: any } = {}

local function endCaravan(caster: Player)
	local c = caravans[caster]
	if not c then
		return
	end
	caravans[caster] = nil
	c.connection:Disconnect()
	for i, bug in c.bugs do
		task.delay(i * 0.08, function()
			Fx.word(bug.pos + V3(0, 2.5, 0), "¡CHAO!", { color = TURQ, size = 28, life = 0.6 })
			killBug(bug, 0.4)
		end)
	end
end

local function startCaravan(caster: Player, payload, mine: boolean)
	endCaravan(caster)
	local root = rootOf(caster)
	if not root then
		return
	end
	local count = math.clamp(math.floor(tonumber(payload.count) or 4), 1, 10)
	local fetch = payload.fetch == true
	local c = {
		bugs = {},
		history = { root.Position },
		fetch = fetch,
	}
	caravans[caster] = c
	local start = root.Position
	for i = 1, count do
		local bug = porterBug(0.85)
		bug.mode = "line"
		bug.timer = 0
		local look = root.CFrame.LookVector * V3(1, 0, 1)
		look = if look.Magnitude > 0.05 then look.Unit else -Vector3.zAxis
		bug.pos = V3(start.X, GROUND, start.Z) - look * (2 + i * 2.5)
		bug.heading = look
		table.insert(c.bugs, bug)
		Fx.burst(bug.pos + V3(0, 0.5, 0), { color = Color3.fromRGB(190, 160, 120), count = 6, size = 0.5, life = 0.35 })
	end
	Fx.word(start + V3(0, 5, 0), "¡EN MARCHA!", { color = TURQ, size = 46 })
	Fx.ring(start, 6, { color = TURQ, life = 0.4 })
	Fx.sound("whoosh", start, 1.1)
	if mine then
		Fx.shake(0.15, 0.2)
	end

	local SPACING = 3
	local clock = 0
	c.connection = RunService.Heartbeat:Connect(function(rawDt)
		local dt = math.min(rawDt, 0.1)
		clock += dt
		local r = rootOf(caster)
		if not r then
			return
		end
		-- Rastro de la Porteadora: un punto cada medio stud para que la fila lo siga
		local here = V3(r.Position.X, GROUND, r.Position.Z)
		local last = c.history[1]
		if (here - V3(last.X, GROUND, last.Z)).Magnitude > 0.5 then
			table.insert(c.history, 1, here)
			if #c.history > 120 then
				table.remove(c.history)
			end
		end
		local hill = Fx.hillOf(caster)
		for i, bug in c.bugs do
			if bug.dead then
				continue
			end
			local moved = 0
			if bug.mode == "fetch" then
				moved = steer(bug, bug.goal, 34, dt)
				bug.timer -= dt
				if (bug.pos - V3(bug.goal.X, GROUND, bug.goal.Z)).Magnitude < 1.2 or bug.timer <= 0 then
					bug.mode = "haul"
					bug.timer = 0.9
					setLoad(bug, true, bug.loadColor)
					local away = if hill then (V3(hill.X, GROUND, hill.Z) - bug.pos) else -bug.heading
					bug.goal = bug.pos + (if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis) * 10
				end
			elseif bug.mode == "haul" then
				moved = steer(bug, bug.goal, 22, dt)
				bug.timer -= dt
				if bug.timer <= 0 then
					setLoad(bug, false)
					if hill then
						Fx.orbs({ bug.pos + V3(0, 1.2, 0) }, hill, { color = bug.loadColor or CRUMB, perPoint = 3 })
					end
					Fx.word(bug.pos + V3(0, 2, 0), "¡A CASA!", { color = TURQ, size = 23, life = 0.5 })
					bug.mode = "line"
				end
			else
				-- En fila sobre tu rastro o, con las mulas sueltas, en corro a tu alrededor
				local target: Vector3
				if c.fetch then
					local angle = clock * 0.6 + i / #c.bugs * math.pi * 2
					target = here + V3(math.cos(angle), 0, math.sin(angle)) * 6.5
				else
					local want = i * SPACING
					local walked = 0
					target = c.history[#c.history]
					for h = 1, #c.history - 1 do
						local seg = (c.history[h + 1] - c.history[h]).Magnitude
						if walked + seg >= want then
							target = c.history[h]:Lerp(c.history[h + 1], (want - walked) / math.max(seg, 1e-3))
							break
						end
						walked += seg
					end
				end
				local gap = (V3(target.X, GROUND, target.Z) - bug.pos).Magnitude
				moved = steer(bug, target, math.clamp(gap * 3, 4, 40), dt)
			end
			poseBug(bug, moved)
		end
	end)

	later(payload, tonumber(payload.duration) or 15, function()
		if caravans[caster] == c then
			endCaravan(caster)
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Escarabajo-vagón (Convoy)
---------------------------------------------------------------------------------------------------

local function wagonBug(k: number)
	return newBug(k, Color3.fromRGB(86, 58, 40), Color3.fromRGB(60, 40, 28), function(bug, s)
		-- Caparazón en cúpula con franja turquesa
		bug.add(V3(1.5, 0.95, 1.7) * s, Color3.fromRGB(70, 46, 32), CF(0, 0.38 * s, 0.25 * s), "blob")
		bug.add(V3(0.2, 0.98, 1.72) * s, TURQ, CF(0, 0.4 * s, 0.25 * s), "blob")
		bug.add(V3(0.4, 0.22, 0.6) * s, Color3.fromRGB(150, 120, 96), CF(-0.35 * s, 0.78 * s, 0.05 * s), "blob")
		-- Cuerno delante
		bug.add(V3(0.22, 0.22, 0.7) * s, INK, CF(0, 0.3 * s, -1.1 * s) * ANG(rad(-30), 0, 0), "blob")
		-- Lanza y carro detrás
		bug.add(V3(1.2 * s, 0.1 * s, 0.1 * s), INK, along(V3(0, 0.15 * s, 1.75 * s), V3(0, 0, 1)), "rod")
		bug.add(V3(1.7, 0.75, 1.5) * s, LEATHER, CF(0, 0.45 * s, 2.75 * s), "blob")
		bug.add(V3(0.12 * s, 1.75 * s, 1.55 * s), TURQ, CF(0, 0.72 * s, 2.75 * s) * ANG(0, 0, rad(90)), "rod")
		local heap = bug.add(V3(1.3, 0.8, 1.15) * s, CRUMB, CF(0, 0.95 * s, 2.75 * s), "blob")
		bug.heap = heap
		for _, x in { -1, 1 } do
			for _, z in { 2.35, 3.15 } do
				local _, index = bug.add(V3(0.18 * s, 0.7 * s, 0.7 * s), INK, CF(x * 0.85 * s, 0.05 * s, z * s), "rod")
				table.insert(bug.wheels, index)
				bug.add(V3(0.2 * s, 0.3 * s, 0.3 * s), TURQ, CF(x * 0.88 * s, 0.05 * s, z * s), "rod")
			end
		end
	end)
end

local function runConvoy(caster: Player, payload, mine: boolean)
	local from, to = payload.from, payload.to
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local travel = math.max(tonumber(payload.travel) or 2, 0.3)
	local windup = tonumber(payload.windup) or 0.45
	local wagons = math.clamp(math.floor(tonumber(payload.wagons) or 1), 1, 3)
	local gap = tonumber(payload.gap) or 0.55
	local width = tonumber(payload.width) or 16
	local dir = V3(to.X - from.X, 0, to.Z - from.Z)
	dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.xAxis
	local k = math.clamp(width / 5, 2.2, 4.4) * (if wagons > 1 then 0.8 else 1)

	-- Anticipación: humo en la salida, bocina, la franja por la que pasará
	Fx.ring(from, 8, { color = TURQ, life = 0.5 })
	Fx.burst(from + V3(0, 1, 0), { color = Color3.fromRGB(190, 160, 120), count = 16, speed = 14, size = 1, life = 0.6 })
	Fx.word(from + V3(0, 7, 0), if payload.ram then "¡ARROLLA!" else "¡VÍA LIBRE!", { color = TURQ, size = 64 })
	Fx.sound("whoosh", from, 0.6)
	Fx.wave(from, to, width, { color = TURQ, time = windup + travel, height = 0.4 })
	if mine then
		Fx.shake(0.25, 0.3)
	end

	for w = 1, wagons do
		local bug = wagonBug(k)
		bug.pos = V3(from.X, GROUND, from.Z)
		bug.heading = dir
		poseBug(bug, 0)
		local startAt = windup + (w - 1) * gap
		local began = os.clock()
		local lastPos = bug.pos
		local dust = 0
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function(dt)
			local elapsed = os.clock() - began
			local u = math.clamp((elapsed - startAt) / travel, 0, 1)
			local p = from:Lerp(to, u)
			bug.pos = V3(p.X, GROUND, p.Z)
			local moved = (bug.pos - lastPos).Magnitude
			lastPos = bug.pos
			poseBug(bug, moved)
			dust += dt
			if u > 0 and u < 1 and dust > 0.18 then
				dust = 0
				Fx.burst(bug.pos + V3(0, 0.5, 0) - dir * k * 3, { color = Color3.fromRGB(190, 160, 120), count = 3, size = 0.9, life = 0.5, speed = 6 })
			end
			if u >= 1 then
				connection:Disconnect()
				impact(bug.pos + V3(0, 2, 0), 9, if w == wagons then "¡ENTREGA!" else "¡TUTÚ!", TURQ, mine, 0.2)
				local hill = Fx.hillOf(caster)
				if hill then
					Fx.orbs({ bug.pos + V3(0, k, 0) }, hill, { color = GOLD, perPoint = 8 })
				end
				task.delay(0.35, function()
					killBug(bug, 0.5)
				end)
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Disparo automático (Gatillo fácil): la dueña pide la Catapulta al llenarse la carga
---------------------------------------------------------------------------------------------------

local Castes = nil
local function castesLib()
	if Castes == nil then
		local ok, lib = pcall(require, ReplicatedStorage.Shared:FindFirstChild("Castes"))
		Castes = if ok then lib else false
	end
	return Castes or nil
end

local function autoFireWanted(player: Player): boolean
	local lib = castesLib()
	if not lib then
		return false
	end
	local raw = player:GetAttribute("CasteData")
	if type(raw) ~= "string" then
		return false
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(data) ~= "table" then
		return false
	end
	local def = lib.get("porter")
	local xp = type(data.xp) == "table" and data.xp.porter or 0
	local muts = type(data.muts) == "table" and data.muts.porter or {}
	local resolved = lib.resolve(def, muts, lib.rankOf(xp))
	return resolved.has("catAuto")
end

---------------------------------------------------------------------------------------------------
-- Aura: alforjas a los lados y un cesto enorme a la espalda que se llena con la carga
---------------------------------------------------------------------------------------------------

local function weldTo(anchor: BasePart, part: BasePart, offset: CFrame)
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
	folder.Name = "PorterAura"
	folder.Parent = character
	local alive = true
	local load: BasePart? = nil
	local loadWeld: Weld? = nil
	local s = 1

	local function build()
		folder:ClearAllChildren()
		load, loadWeld = nil, nil
		local thorax = character:FindFirstChild("Thorax") :: BasePart?
		local abdomen = character:FindFirstChild("Abdomen") :: BasePart?
		if not thorax or not abdomen then
			return false
		end
		s = character:GetScale() * (1 + 0.035 * math.clamp(rank, 1, 10))
		local rim = if mastered then GOLD else TURQ
		local rimMat = if mastered then Enum.Material.Neon else Enum.Material.SmoothPlastic

		-- Cesto: cilindro de pie sobre la espalda, con aro y faja
		local basketAt = CF(0, 1.25 * s, 0.75 * s) * ANG(rad(-12), 0, rad(90))
		weldTo(thorax, piece(folder, V3(1.35, 1.7, 1.7) * s, LEATHER, "rod"), basketAt)
		weldTo(thorax, piece(folder, V3(1.33, 1.5, 1.5) * s, LEATHER_DARK, "rod"), basketAt * CF(0.03 * s, 0, 0))
		weldTo(thorax, piece(folder, V3(0.18, 1.82, 1.82) * s, rim, "rod", rimMat), basketAt * CF(0.66 * s, 0, 0))
		weldTo(thorax, piece(folder, V3(0.14, 1.76, 1.76) * s, TURQ, "rod"), basketAt * CF(-0.1 * s, 0, 0))
		-- Correas que bajan al pecho
		for _, x in { -0.42, 0.42 } do
			weldTo(thorax, piece(folder, V3(1.5 * s, 0.12 * s, 0.12 * s), LEATHER_DARK, "rod"), along(V3(x * s, 0.55 * s, 0.1 * s), V3(0, 0.75, 0.66)))
		end
		-- Lo que llevas, asomando por arriba del cesto
		local heap = piece(folder, V3(1.4, 0.8, 1.4) * s, CRUMB, "blob")
		heap.Transparency = 1
		loadWeld = weldTo(thorax, heap, CF(0, 1.9 * s, 0.6 * s))
		load = heap
		-- Alforjas a los lados del abdomen, con su solapa turquesa
		for _, x in { -1, 1 } do
			weldTo(abdomen, piece(folder, V3(0.55, 0.85, 1.05) * s, LEATHER, "blob"), CF(x * 0.95 * s, -0.1 * s, -0.05 * s))
			weldTo(abdomen, piece(folder, V3(0.6, 0.35, 0.9) * s, TURQ, "blob"), CF(x * 0.98 * s, 0.22 * s, -0.08 * s))
			weldTo(abdomen, piece(folder, V3(0.22, 0.22, 0.22) * s, if mastered then GOLD else LEATHER_DARK, "blob"), CF(x * 1.22 * s, 0.1 * s, -0.08 * s))
		end
		if mastered then
			local light = Instance.new("PointLight")
			light.Color = GOLD
			light.Range = 8
			light.Brightness = 0.8
			light.Shadows = false
			light.Parent = heap
		end
		return true
	end

	build()
	local player = Players:GetPlayerFromCharacter(character)
	local isMe = player == Players.LocalPlayer
	local autoAt = 0

	task.spawn(function()
		while alive and character.Parent do
			-- Si el vestidor rehizo la hormiga, el aura se vuelve a montar
			local thorax = character:FindFirstChild("Thorax")
			if not thorax or not load or not load.Parent or not (loadWeld and loadWeld.Part0 and loadWeld.Part0.Parent) then
				build()
			end
			if player and load and loadWeld then
				local carry = tonumber(player:GetAttribute("Carry")) or 0
				local capacity = math.max(tonumber(player:GetAttribute("Capacity")) or 1, 1)
				local fill = math.clamp(carry / capacity, 0, 1.5)
				load.Transparency = if fill > 0.02 then 0 else 1
				load.Size = V3(1.4, 0.35 + 0.9 * math.min(fill, 1), 1.4) * s
				loadWeld.C0 = CF(0, (1.75 + 0.35 * math.min(fill, 1)) * s, 0.6 * s)
				-- Gatillo fácil: con la carga llena, pide la Catapulta en cuanto esté lista
				if isMe and fill >= 0.999 and os.clock() > autoAt then
					local readyAt = tonumber(player:GetAttribute("CasteCd1")) or 0
					if serverNow() >= readyAt and autoFireWanted(player) then
						local remotes = ReplicatedStorage:FindFirstChild("Remotes")
						local remote = remotes and remotes:FindFirstChild("Caste")
						local root = rootOf(player)
						if remote and root then
							autoAt = os.clock() + 2
							remote:FireServer("Cast", 1, root.Position, nil)
						end
					end
				end
			end
			task.wait(0.2)
		end
	end)

	return function()
		alive = false
		folder:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- Emblema: un cesto turquesa con asa y migas
---------------------------------------------------------------------------------------------------

local function uiCircle(parent: GuiObject, size: UDim2, pos: UDim2, color: Color3, stroke: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
	if stroke then
		local st = Instance.new("UIStroke")
		st.Color = INK
		st.Thickness = stroke
		st.Parent = f
	end
	f.Parent = parent
	return f
end

local function emblem(parent: GuiObject, color: Color3)
	local holder = Instance.new("Frame")
	holder.Name = "PorterEmblem"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent

	-- Asa: un aro del que solo asoma la mitad de arriba
	local handle = uiCircle(holder, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.42), color, 3)
	handle.BackgroundTransparency = 1
	handle.ZIndex = 1
	local handleStroke = handle:FindFirstChildOfClass("UIStroke") :: UIStroke
	handleStroke.Thickness = 4
	handleStroke.Color = INK

	-- Migas que asoman
	uiCircle(holder, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.38, 0.5), CRUMB, 2).ZIndex = 2
	uiCircle(holder, UDim2.fromScale(0.24, 0.24), UDim2.fromScale(0.58, 0.47), Color3.fromRGB(240, 196, 120), 2).ZIndex = 2

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0)
	body.Position = UDim2.fromScale(0.5, 0.52)
	body.Size = UDim2.fromScale(0.66, 0.36)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.ZIndex = 3
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.35, 0)
	corner.Parent = body
	local st = Instance.new("UIStroke")
	st.Color = INK
	st.Thickness = 3
	st.Parent = body
	body.Parent = holder

	local band = Instance.new("Frame")
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.42)
	band.Size = UDim2.fromScale(1, 0.26)
	band.BackgroundColor3 = TURQ
	band.BorderSizePixel = 0
	band.ZIndex = 4
	local bst = Instance.new("UIStroke")
	bst.Color = INK
	bst.Thickness = 2
	bst.Parent = band
	band.Parent = body
end

---------------------------------------------------------------------------------------------------
-- Efectos
---------------------------------------------------------------------------------------------------

local fx = {}

-- Entrega con la carga llena: el extra de Lomo de hierro
function fx.passive(_caster: Player, payload, mine: boolean)
	local at = payload.at
	if typeof(at) ~= "Vector3" then
		return
	end
	local top = at + V3(0, 10, 0)
	Fx.ring(at, 9, { color = TURQ, life = 0.5 })
	if mine then
		Fx.word(top, "¡LOMO DE HIERRO!", { color = TURQ, size = 46 })
		local amount = tonumber(payload.amount) or 0
		if amount > 0 then
			Pop.number(top, amount, true)
		end
		Fx.sound("chime", at, 1.2)
	end
end

function fx.porter1(caster: Player, payload, mine: boolean)
	local from, to = payload.from, payload.to
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local fill = math.clamp(tonumber(payload.fill) or 0.5, 0, 1.5)
	local size = 0.9 + fill * 1.6 + (if payload.cannon then 0.6 else 0)
	local color = if typeof(payload.color) == "Color3" then payload.color else CRUMB
	local golden = payload.golden == true
	local flight = tonumber(payload.flight) or 1.3
	local total = tonumber(payload.total) or flight
	local hitTime = tonumber(payload.hitTime) or 0
	local smash = payload.smash

	-- Anticipación: la hormiga se agacha (aro y polvo) y suelta la saca
	local origin = if typeof(payload.origin) == "Vector3" then payload.origin else from
	Fx.ring(origin, 4, { color = TURQ, life = 0.3 })
	Fx.word(from + V3(0, 3, 0), if payload.cannon then "¡FUEGO!" else "¡HOP!", { color = TURQ, size = 41 })
	Fx.sound("whoosh", from, if payload.cannon then 0.7 else 1)
	if mine then
		Fx.shake(if payload.cannon then 0.35 else 0.18, 0.2)
		if payload.cannon then
			Fx.flash(TURQ, 0.25, 0.2)
		end
	end

	local model = sack(size, color, golden)
	local landWord = if payload.cannon then "¡BUM!" else "¡PLOF!"
	local function landHome(fromPoint: Vector3, time: number, height: number)
		flySack(model, size, fromPoint, to, time, height, function()
			impact(to, 10, landWord, if golden then GOLD else TURQ, mine, 0.15)
			model:Destroy()
		end)
	end
	if typeof(smash) == "Vector3" then
		flySack(model, size, from, smash, hitTime, 14, function()
			impact(smash, 8, "¡CRASH!", Color3.fromRGB(255, 120, 60), mine, 0.4)
			Fx.sound("boom", smash, 1)
			landHome(smash, math.max(total - hitTime, 0.3), 9)
		end)
	else
		local dist = (to - from).Magnitude
		landHome(from, flight, math.clamp(dist * 0.35, 10, 60))
	end

	-- Cesto plantado: queda en el suelo, recoge y luego se hunde
	if payload.basket then
		local life = tonumber(payload.basketTime) or 10
		local radius = tonumber(payload.basketRadius) or 12
		local basket = Instance.new("Model")
		basket.Name = "PorterBasket"
		local base = V3(origin.X, GROUND, origin.Z)
		local body = piece(basket, V3(2, 2.6, 2.6), LEATHER, "rod")
		body.CFrame = CF(base + V3(0, 1, 0)) * ANG(0, 0, rad(90))
		local rimPart = piece(basket, V3(0.3, 2.85, 2.85), TURQ, "rod")
		rimPart.CFrame = CF(base + V3(0, 2, 0)) * ANG(0, 0, rad(90))
		local heap = piece(basket, V3(2, 0.9, 2), CRUMB, "blob")
		heap.CFrame = CF(base + V3(0, 2.1, 0))
		basket.Parent = inkParent()
		Fx.puddle(base, radius, life, { color = TURQ })
		Fx.word(base + V3(0, 4, 0), "¡CESTO!", { color = TURQ, size = 37 })
		task.delay(life, function()
			Fx.burst(base + V3(0, 1, 0), { color = TURQ, count = 8, size = 0.6, life = 0.4 })
			fadeOut(basket, 0.4)
		end)
	end
end

function fx.porter1_smash(caster: Player, payload, mine: boolean)
	local at = payload.at
	if typeof(at) ~= "Vector3" then
		return
	end
	loot(caster, { at })
	numbers(mine, { at }, { payload.amount })
end

function fx.porter1_basket(caster: Player, payload, mine: boolean)
	local points = payload.points
	if type(points) ~= "table" then
		return
	end
	for _, p in points do
		Fx.burst(p, { color = TURQ, count = 4, size = 0.4, life = 0.3, speed = 8 })
	end
	loot(caster, points)
	numbers(mine, points, payload.amounts)
end

function fx.porter2(caster: Player, payload, mine: boolean)
	startCaravan(caster, payload, mine)
end

function fx.porter2_hit(caster: Player, payload, mine: boolean)
	local points, who = payload.points, payload.who
	if type(points) ~= "table" then
		return
	end
	local c = caravans[caster]
	for i, p in points do
		local index = type(who) == "table" and tonumber(who[i]) or i
		local bug = c and c.bugs[index]
		Fx.burst(p, { color = CRUMB, count = 4, size = 0.45, life = 0.3, speed = 9 })
		if bug and not bug.dead and bug.mode == "line" then
			-- Va a la comida, carga el cesto y sale hacia casa
			bug.mode = "fetch"
			bug.goal = p
			bug.timer = 0.7
			bug.loadColor = CRUMB
		else
			loot(caster, { p })
		end
	end
	if math.random() < 0.35 then
		Fx.word(points[1] + V3(0, 2.5, 0), "¡ÑAC!", { color = TURQ, size = 28, life = 0.45 })
	end
	numbers(mine, points, payload.amounts)
end

function fx.porter3(caster: Player, payload, mine: boolean)
	runConvoy(caster, payload, mine)
end

function fx.porter3_hit(caster: Player, payload, mine: boolean)
	local points = payload.points
	if type(points) ~= "table" then
		return
	end
	for _, p in points do
		Fx.burst(p, { color = CRUMB, count = 8, speed = 14, size = 0.7, life = 0.45, up = 0.8 })
		Fx.ring(p, 4, { color = TURQ, life = 0.3 })
	end
	Fx.word(points[1] + V3(0, 3, 0), "¡SLURP!", { color = TURQ, size = 41, life = 0.5 })
	Fx.sound("pop", points[1], 0.8)
	loot(caster, points)
	numbers(mine, points, payload.amounts)
	if mine then
		Fx.shake(0.12, 0.12)
	end
end

Players.PlayerRemoving:Connect(function(player)
	endCaravan(player)
end)

return {
	fx = fx,
	aura = aura,
	emblem = emblem,
}
