-- Melera (cliente): el abdomen de miel que se hincha y brilla con la carga y el fermento, la bola de
-- néctar, la comida bañada (gotea y brilla mientras vale más), la bola de miel que rueda o bota,
-- el Reventón dorado con su lluvia de gotas y el emblema.
-- Atributos que lee: jugadora "Carry", "Capacity", "HoneyFerment" (en %), "HoneyFermentMax";
-- comida "HoneyGlaze" / "HoneyGold" (hora de servidor en que se acaba el baño).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Abilities = require(script.Parent.Parent.Abilities)
local Comic = require(script.Parent.Parent.Comic)
local Fx = require(script.Parent.Parent.CasteFx)
local Pop = require(script.Parent.Parent.Fx) -- números de cómic de la dueña

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad

local INK = Color3.fromRGB(20, 16, 16)
local AMBER = Color3.fromRGB(255, 170, 30)
local HONEY = Color3.fromRGB(255, 226, 92)
local DEEP = Color3.fromRGB(240, 120, 10)
local PALE = Color3.fromRGB(255, 240, 170)
local GOLD = Color3.fromRGB(255, 200, 40)
local GROUND = Config.GroundY
local FLAT = V3(1, 0, 1)

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
		Fx.orbs(points, hill, { color = color or AMBER })
	end
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

-- Gota de miel que cae de a a b y salpica
local function drip(a: Vector3, b: Vector3, time: number, color: Color3, onLand: (() -> ())?)
	local drop = piece(Fx.folder(), V3(0.6, 0.9, 0.6), color, "blob", Enum.Material.Neon)
	drop.CFrame = CF(a)
	local tween = TweenService:Create(drop, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CF(b) })
	tween:Play()
	tween.Completed:Once(function()
		drop:Destroy()
		Fx.burst(b, { color = color, count = 5, size = 0.4, life = 0.3, speed = 8, up = 0.6 })
		if onLand then
			onLand()
		end
	end)
end

local function dripEmitter(parent: Instance, color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.35
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.15) })
	e.Transparency = NumberSequence.new(0.1, 0.6)
	e.Lifetime = NumberRange.new(0.5, 0.8)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.Acceleration = V3(0, -28, 0)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Rate = rate
	e.Parent = parent
	return e
end

---------------------------------------------------------------------------------------------------
-- Comida bañada: gotea y brilla mientras dura el baño
---------------------------------------------------------------------------------------------------

local coats: { [Model]: { [string]: any } } = {}
local coatLoop: RBXScriptConnection? = nil

local function foodNear(point: Vector3): Model?
	local container = Workspace:FindFirstChild("Food")
	if not container then
		return nil
	end
	local best, bestGap = nil, 3.5
	for _, food in container:GetChildren() do
		if food:IsA("Model") then
			local gap = (food:GetPivot().Position + V3(0, 1, 0) - point).Magnitude
			if gap < bestGap then
				best, bestGap = food, gap
			end
		end
	end
	return best
end

local function dropCoat(food: Model, kind: string)
	local list = coats[food]
	local c = list and list[kind]
	if c then
		list[kind] = nil
		c.anchor:Destroy()
		if next(list) == nil then
			coats[food] = nil
		end
	end
end

local function ensureCoatLoop()
	if coatLoop then
		return
	end
	coatLoop = RunService.Heartbeat:Connect(function()
		local now = serverNow()
		local any = false
		for food, list in coats do
			for kind, c in list do
				any = true
				if not food.Parent or now > c.untilT then
					dropCoat(food, kind)
				else
					c.anchor.CFrame = CF(food:GetPivot().Position + V3(0, c.lift, 0))
				end
			end
		end
		if not any and coatLoop then
			coatLoop:Disconnect()
			coatLoop = nil
		end
	end)
end

-- kind: "nectar" o "gold". El fin del baño sale del atributo de la comida si ya llegó.
local function coat(point: Vector3, kind: string, seconds: number, mult: number?, mine: boolean)
	local food = foodNear(point)
	if not food then
		return
	end
	local attr = if kind == "gold" then "HoneyGold" else "HoneyGlaze"
	local untilT = food:GetAttribute(attr)
	if type(untilT) ~= "number" then
		untilT = serverNow() + seconds
	end
	dropCoat(food, kind)
	local radius = (food:GetAttribute("Radius") :: number?) or 2
	local anchor = Instance.new("Part")
	anchor.Name = "HoneyCoat"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = V3(radius * 1.6, 0.3, radius * 1.6)
	local color = if kind == "gold" then GOLD else AMBER
	dripEmitter(anchor, color, if kind == "gold" then 5 else 8)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = radius * 3 + 4
	light.Brightness = if kind == "gold" then 1.6 else 0.9
	light.Shadows = false
	light.Parent = anchor
	if kind == "gold" then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 245, 180))
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.4), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Lifetime = NumberRange.new(0.4, 0.7)
		sparkle.Speed = NumberRange.new(1, 3)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Rate = 10
		sparkle.Parent = anchor
	end
	if mine and mult then
		-- Solo la dueña ve cuánto vale ahora
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(70, 34)
		gui.StudsOffset = V3(0, radius + 1.5, 0)
		gui.LightInfluence = 0
		gui.MaxDistance = 90
		gui.Adornee = anchor
		local text = string.format("x%.1f", mult):gsub("%.0$", ""):gsub("%.", ",")
		local label = Comic.label(gui, text, Comic.Display, 26, color)
		label.Size = UDim2.fromScale(1, 1)
		label.Rotation = rng:NextNumber(-10, 10)
		Comic.ink(label, 3)
		gui.Parent = anchor
	end
	anchor.CFrame = CF(food:GetPivot().Position + V3(0, radius * 0.6, 0))
	anchor.Parent = Fx.folder()
	coats[food] = coats[food] or {}
	coats[food][kind] = { anchor = anchor, untilT = untilT, lift = radius * 0.6 }
	ensureCoatLoop()
end

---------------------------------------------------------------------------------------------------
-- Velocidad de la dueña dentro de la Bola de miel
---------------------------------------------------------------------------------------------------

local myBall: any = nil -- { untilClock, speed }
local wrapped = false

local function speedNow(): number
	if myBall and os.clock() < myBall.untilClock then
		return myBall.speed
	end
	return 1
end

local function wrapSpeed()
	if wrapped then
		return
	end
	wrapped = true
	local base = Abilities.speedBoost
	Abilities.speedBoost = function(): number
		return base() * speedNow()
	end
end

---------------------------------------------------------------------------------------------------
-- Bola de miel alrededor de la hormiga
---------------------------------------------------------------------------------------------------

local balls: { [Player]: any } = {}

local function popBall(caster: Player)
	local b = balls[caster]
	if not b then
		return
	end
	balls[caster] = nil
	b.connection:Disconnect()
	local at = b.shell.Position
	Fx.burst(at, { color = AMBER, count = 16, speed = 18, size = 0.7, life = 0.5, up = 0.6 })
	Fx.word(at + V3(0, 3, 0), "¡PLOP!", { color = AMBER, size = 46 })
	Fx.sound("splash", at, 1.2)
	b.model:Destroy()
end

local function startBall(caster: Player, payload, mine: boolean)
	popBall(caster)
	local root = rootOf(caster)
	if not root then
		return
	end
	local character = caster.Character :: Model
	local scale = character:GetScale()
	local radius = 3.2 * scale
	local bounce = payload.bounce == true
	local duration = tonumber(payload.duration) or 4
	local model = Instance.new("Model")
	model.Name = "HoneyBall"
	local shell = piece(model, V3(2, 2, 2) * radius, AMBER, "ball", Enum.Material.Glass)
	shell.Transparency = 0.55
	local inner = piece(model, V3(1.6, 1.6, 1.6) * radius, HONEY, "ball", Enum.Material.Neon)
	inner.Transparency = 0.82
	local light = Instance.new("PointLight")
	light.Color = AMBER
	light.Range = radius * 4
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = inner
	dripEmitter(shell, AMBER, 10)
	model.Parent = Fx.folder()

	local b = {
		model = model,
		shell = shell,
		inner = inner,
		stuck = {} :: { { part: BasePart, offset: CFrame } },
		spin = CF(),
		radius = radius,
		lastPos = root.Position,
		hopT = 0,
	}
	balls[caster] = b

	-- Anticipación: la hormiga se encoge en un estallido de miel
	Fx.burst(root.Position, { color = HONEY, count = 12, speed = 12, size = 0.6, life = 0.4 })
	Fx.word(root.Position + V3(0, 4, 0), if bounce then "¡BOING!" else "¡ROLL!", { color = AMBER, size = 51 })
	Fx.sound("splash", root.Position, 0.9)
	if mine then
		myBall = { untilClock = os.clock() + duration, speed = if bounce then 1.25 else (tonumber(payload.speed) or 1.8) }
		wrapSpeed()
		Fx.shake(0.15, 0.2)
	end

	local began = os.clock()
	local nextHop = 0.8 - 0.3
	b.connection = RunService.Heartbeat:Connect(function(dt)
		local r = rootOf(caster)
		if not r then
			return
		end
		local t = os.clock() - began
		local pos = r.Position
		local moved = (pos - b.lastPos) * FLAT
		b.lastPos = pos
		if moved.Magnitude > 1e-3 then
			local axis = Vector3.yAxis:Cross(moved.Unit)
			b.spin = CFrame.fromAxisAngle(axis, moved.Magnitude / b.radius) * b.spin
		end
		local squash = 1
		if bounce then
			squash = 1 + math.max(0, 1 - (t % 0.8) / 0.12) * 0.25 -- se aplasta un instante al caer
		end
		local center = CF(pos + V3(0, 0.2, 0)) * b.spin
		shell.Size = V3(2 * squash, 2 / squash, 2 * squash) * b.radius
		local parts, cframes = { shell, inner }, { CF(pos + V3(0, 0.2, 0)), CF(pos + V3(0, 0.2, 0)) }
		for _, s in b.stuck do
			table.insert(parts, s.part)
			table.insert(cframes, center * s.offset)
		end
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

		-- Bola rebotona: la dueña bota a ritmo, justo antes de cada aplastamiento del servidor
		if mine and bounce and t >= nextHop and t < duration then
			nextHop += 0.8
			local v = r.AssemblyLinearVelocity
			r.AssemblyLinearVelocity = V3(v.X, 30, v.Z)
		end
		if t >= duration then
			popBall(caster)
		end
	end)

	later(payload, duration + 0.1, function()
		if balls[caster] == b then
			popBall(caster)
		end
	end)
end

-- Lo aplastado se pega a la bola
local function stickTo(caster: Player, points: { Vector3 })
	local b = balls[caster]
	if not b then
		return
	end
	for _ = 1, math.min(#points, 3) do
		if #b.stuck >= 14 then
			break
		end
		local dir = V3(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
		if dir.Magnitude < 0.1 then
			dir = Vector3.yAxis
		end
		local crumb = piece(b.model, V3(0.7, 0.55, 0.7) * rng:NextNumber(0.8, 1.3), Color3.fromRGB(222, 166, 92), "blob")
		table.insert(b.stuck, { part = crumb, offset = CF(dir.Unit * b.radius * 0.95) })
	end
end

---------------------------------------------------------------------------------------------------
-- Aura: abdomen de miel translúcido que se llena y brilla con el fermento
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
	folder.Name = "HoneyAura"
	folder.Parent = character
	local alive = true
	local parts: any = {}
	local player = Players:GetPlayerFromCharacter(character)
	local isMe = player == Players.LocalPlayer

	local function build()
		folder:ClearAllChildren()
		parts = {}
		local abdomen = character:FindFirstChild("Abdomen") :: BasePart?
		local head = character:FindFirstChild("Head") :: BasePart?
		if not abdomen then
			return
		end
		local sc = character:GetScale()
		local grow = 1.08 + 0.012 * math.clamp(rank, 1, 10)
		parts.base = abdomen.Size
		-- Cáscara de ámbar sobre el abdomen
		local shell = piece(folder, abdomen.Size * grow, AMBER, "blob", Enum.Material.Glass)
		shell.Transparency = 0.45
		weldTo(abdomen, shell, CF(0, 0.02 * sc, 0.05 * sc))
		parts.shell = shell
		-- Miel de dentro: crece con la carga, se oscurece y brilla con el fermento
		local core = piece(folder, abdomen.Size * 0.4, PALE, "blob", Enum.Material.Neon)
		core.Transparency = 0.2
		parts.coreWeld = weldTo(abdomen, core, CF(0, -0.1 * sc, 0.05 * sc))
		parts.core = core
		local light = Instance.new("PointLight")
		light.Color = AMBER
		light.Range = 8 * sc
		light.Brightness = 0.3
		light.Shadows = false
		light.Parent = core
		parts.light = light
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220))
		bubbles.LightEmission = 0.6
		bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0.22) })
		bubbles.Transparency = NumberSequence.new(0.2, 0.9)
		bubbles.Lifetime = NumberRange.new(0.5, 0.9)
		bubbles.Speed = NumberRange.new(0.6, 1.4)
		bubbles.EmissionDirection = Enum.NormalId.Top
		bubbles.SpreadAngle = Vector2.new(30, 30)
		bubbles.Rate = 0
		bubbles.Parent = core
		parts.bubbles = bubbles
		local tip = character:FindFirstChild("AbdomenTip") :: BasePart?
		local drips = dripEmitter(tip or abdomen, AMBER, 0)
		parts.drips = drips
		-- Gotitas de miel en las antenas
		if head then
			for _, x in { -1, 1 } do
				weldTo(head, piece(folder, V3(0.32, 0.4, 0.32) * sc, HONEY, "blob", Enum.Material.Neon), CF(x * 0.7 * sc, 1.45 * sc, -0.95 * sc))
			end
		end
		if mastered then
			local band = piece(folder, V3(0.25 * sc, abdomen.Size.Y * 1.18, abdomen.Size.Y * 1.18), GOLD, "rod", Enum.Material.Neon)
			weldTo(abdomen, band, CF(0, 0, 0.1 * sc) * ANG(0, rad(90), 0))
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 245, 180))
			sparkle.LightEmission = 1
			sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) })
			sparkle.Lifetime = NumberRange.new(0.4, 0.7)
			sparkle.Rate = 4
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Speed = NumberRange.new(0.5, 1.5)
			sparkle.Parent = band
		end
		-- La dueña ve el fermento en número, pequeño, sobre el abdomen
		if isMe then
			local gui = Instance.new("BillboardGui")
			gui.Size = UDim2.fromOffset(80, 30)
			gui.StudsOffset = V3(0, 2.2 * sc, 0)
			gui.LightInfluence = 0
			gui.Adornee = shell
			gui.Enabled = false
			local label = Comic.label(gui, "", Comic.Display, 22, HONEY)
			label.Size = UDim2.fromScale(1, 1)
			Comic.ink(label, 3)
			gui.Parent = folder
			parts.gui = gui
			parts.label = label
		end
	end
	build()

	local shown = -1
	task.spawn(function()
		while alive and character.Parent do
			if not parts.shell or not parts.shell.Parent or not parts.coreWeld or not parts.coreWeld.Part0 or not parts.coreWeld.Part0.Parent then
				build()
			end
			if player and parts.core then
				local carry = tonumber(player:GetAttribute("Carry")) or 0
				local capacity = math.max(tonumber(player:GetAttribute("Capacity")) or 1, 1)
				local fill = math.clamp(carry / capacity, 0, 1.5)
				local pct = tonumber(player:GetAttribute("HoneyFerment")) or 0
				local max = math.max(tonumber(player:GetAttribute("HoneyFermentMax")) or 100, 1)
				local ferment = math.clamp(pct / max, 0, 1)
				local size = parts.base * (0.25 + 0.75 * math.min(fill, 1.2))
				TweenService:Create(parts.core, TweenInfo.new(0.25), {
					Size = size,
					Color = PALE:Lerp(HONEY, math.min(ferment * 2, 1)):Lerp(DEEP, math.max(ferment * 2 - 1, 0)),
					Transparency = if fill > 0.01 then 0.15 else 0.85,
				}):Play()
				-- El abdomen se hincha un pelín cuando va lleno
				if parts.shell then
					local swell = 1.08 + 0.012 * math.clamp(rank, 1, 10) + 0.12 * math.min(fill, 1.5)
					parts.shell.Size = parts.base * swell
				end
				parts.light.Brightness = 0.2 + 2.2 * ferment * math.min(fill * 2, 1)
				parts.bubbles.Rate = if fill > 0.01 then 2 + 16 * ferment else 0
				parts.drips.Rate = if ferment > 0.6 and fill > 0.01 then 3 + 6 * ferment else 0
				if parts.gui then
					local on = pct > 0 and fill > 0.01
					parts.gui.Enabled = on
					if on and pct ~= shown then
						shown = pct
						parts.label.Text = "+" .. pct .. " %"
						parts.label.TextColor3 = if ferment >= 1 then GOLD else HONEY
					end
				end
			end
			task.wait(0.25)
		end
	end)

	return function()
		alive = false
		folder:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- Emblema: gota de miel con brillo
---------------------------------------------------------------------------------------------------

local function emblem(parent: GuiObject, color: Color3)
	local holder = Instance.new("Frame")
	holder.Name = "HoneyEmblem"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent

	-- Punta: un cuadrado redondeado girado; cuerpo: un círculo. Juntos, una gota.
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(0.5, 0.44)
	tip.Size = UDim2.fromScale(0.44, 0.44)
	tip.Rotation = 45
	tip.BackgroundColor3 = color
	tip.BorderSizePixel = 0
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0.18, 0)
	tc.Parent = tip
	local ts = Instance.new("UIStroke")
	ts.Color = INK
	ts.Thickness = 3
	ts.Parent = tip
	tip.Parent = holder

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.6)
	body.Size = UDim2.fromScale(0.62, 0.62)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = body
	local bs = Instance.new("UIStroke")
	bs.Color = INK
	bs.Thickness = 3
	bs.Parent = body
	body.Parent = holder

	-- Tapa la línea de la punta dentro del cuerpo
	local patch = Instance.new("Frame")
	patch.AnchorPoint = Vector2.new(0.5, 0.5)
	patch.Position = UDim2.fromScale(0.5, 0.5)
	patch.Size = UDim2.fromScale(0.34, 0.2)
	patch.BackgroundColor3 = color
	patch.BorderSizePixel = 0
	patch.ZIndex = 2
	patch.Parent = holder

	local shine = Instance.new("Frame")
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.38, 0.58)
	shine.Size = UDim2.fromScale(0.13, 0.2)
	shine.Rotation = 20
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BorderSizePixel = 0
	shine.ZIndex = 3
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(1, 0)
	sc.Parent = shine
	shine.Parent = holder
end

---------------------------------------------------------------------------------------------------
-- Efectos
---------------------------------------------------------------------------------------------------

local fx = {}

-- Entrega fermentada: burbujas en el hormiguero
function fx.passive(_caster: Player, payload, mine: boolean)
	local at = payload.at
	if typeof(at) ~= "Vector3" then
		return
	end
	local top = at + V3(0, 10, 0)
	Fx.burst(top, { color = HONEY, count = 10, speed = 10, size = 0.5, life = 0.5, up = 1 })
	if mine then
		Fx.word(top + V3(0, 2, 0), "¡FERMENTO +" .. tostring(payload.pct or 0) .. " %!", { color = HONEY, size = 46 })
		Fx.sound("chime", at, 0.9)
	end
end

function fx.honey1(caster: Player, payload, mine: boolean)
	local from, center = payload.from, payload.center
	if typeof(from) ~= "Vector3" or typeof(center) ~= "Vector3" then
		return
	end
	local flight = tonumber(payload.flight) or 0.45
	Fx.sound("whoosh", from, 1.1)
	Fx.lob(from, center + V3(0, 1, 0), { color = AMBER, size = if payload.drop then 1 else 1.8, time = flight, height = 9 })
end

function fx.honey1_land(caster: Player, payload, mine: boolean)
	local center = payload.center
	if typeof(center) ~= "Vector3" then
		return
	end
	local radius = tonumber(payload.radius) or 12
	local duration = tonumber(payload.duration) or 8
	-- El charco dura lo que el baño; si no, solo una salpicadura breve
	local pool = payload.pool == true
	Fx.puddle(center, radius, if pool then duration else 1.2, { color = AMBER })
	Fx.ring(center, radius, { color = HONEY, life = 0.45, thickness = 0.9 })
	Fx.burst(center + V3(0, 1, 0), { color = AMBER, count = 18, speed = 16, size = 0.8, life = 0.55, up = 0.8 })
	Fx.word(center + V3(0, 4, 0), if radius <= 6 then "¡GLUP!" else "¡SPLASH!", { color = AMBER, size = 55 })
	Fx.light(center, { color = AMBER, range = radius * 2, life = 0.4 })
	Fx.sound("splash", center, 1)
	if mine then
		Fx.shake(0.15, 0.2)
	end
	if type(payload.points) == "table" then
		local mult = tonumber(payload.mult)
		for _, p in payload.points do
			coat(p, "nectar", duration, mult, mine)
			Fx.burst(p, { color = HONEY, count = 4, size = 0.4, life = 0.3, speed = 6 })
		end
	end
end

function fx.honey1_pool(caster: Player, payload, mine: boolean)
	if type(payload.points) ~= "table" then
		return
	end
	for _, p in payload.points do
		Fx.burst(p, { color = AMBER, count = 4, size = 0.4, life = 0.35, speed = 5, up = 1 })
	end
	loot(caster, payload.points)
	numbers(mine, payload.points, payload.amounts)
end

function fx.honey2(caster: Player, payload, mine: boolean)
	startBall(caster, payload, mine)
end

function fx.honey2_hit(caster: Player, payload, mine: boolean)
	local points = payload.points
	if type(points) ~= "table" then
		return
	end
	local root = rootOf(caster)
	for _, p in points do
		Fx.burst(p, { color = AMBER, count = 5, size = 0.45, life = 0.3, speed = 9 })
	end
	if root then
		-- Lo aplastado vuela a la bola, no a casa: se te pega a la carga
		Fx.orbs(points, root.Position, { color = Color3.fromRGB(222, 166, 92), time = 0.25, perPoint = 1 })
	end
	stickTo(caster, points)
	if math.random() < 0.3 then
		Fx.word(points[1] + V3(0, 2.5, 0), "¡CHOF!", { color = AMBER, size = 32, life = 0.45 })
	end
	Fx.sound("pop", points[1], 1.1)
	numbers(mine, points, payload.amounts)
end

function fx.honey2_hop(caster: Player, payload, mine: boolean)
	local center = payload.center
	if typeof(center) ~= "Vector3" then
		return
	end
	local radius = tonumber(payload.radius) or 10
	local ground = V3(center.X, GROUND, center.Z)
	Fx.ring(ground, radius, { color = AMBER, life = 0.35, thickness = 0.8 })
	Fx.burst(ground + V3(0, 0.5, 0), { color = HONEY, count = 10, speed = 14, size = 0.6, life = 0.4, up = 0.5 })
	Fx.sound("thud", ground, 1.2)
	if mine then
		Fx.shake(0.2, 0.15)
	end
	local points = payload.points
	if type(points) == "table" and #points > 0 then
		Fx.word(ground + V3(0, 3, 0), "¡BOING!", { color = AMBER, size = 41, life = 0.5 })
		local root = rootOf(caster)
		if root then
			Fx.orbs(points, root.Position, { color = Color3.fromRGB(222, 166, 92), time = 0.25, perPoint = 1 })
		end
		stickTo(caster, points)
		numbers(mine, points, payload.amounts)
	end
end

function fx.honey3(caster: Player, payload, mine: boolean)
	local center = payload.center
	if typeof(center) ~= "Vector3" then
		return
	end
	local radius = tonumber(payload.radius) or 28
	local windup = tonumber(payload.windup) or 0.4
	local duration = tonumber(payload.duration) or 10

	if payload.rain then
		-- Nube de miel dorada que llueve el rato que dure
		local cloud = Instance.new("Model")
		cloud.Name = "HoneyCloud"
		local sky = center + V3(0, 22, 0)
		for i = 1, 7 do
			local angle = i / 7 * math.pi * 2
			local r = if i == 7 then 0 else radius * 0.35
			local puff = piece(cloud, V3(9, 4.5, 8) * rng:NextNumber(0.8, 1.2), if i % 2 == 0 then HONEY else Color3.fromRGB(255, 250, 225), "blob")
			puff.CFrame = CF(sky + V3(math.cos(angle) * r, rng:NextNumber(-1, 1), math.sin(angle) * r))
			puff.Transparency = 0.15
		end
		cloud.Parent = Workspace:FindFirstChild("Swarm") or Fx.folder()
		Fx.word(sky + V3(0, 5, 0), "¡LLUEVE MIEL!", { color = GOLD, size = 64 })
		Fx.sound("chime", center, 0.7)
		task.delay(duration, function()
			for _, d in cloud:GetChildren() do
				if d:IsA("BasePart") then
					TweenService:Create(d, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				end
			end
			Debris:AddItem(cloud, 0.7)
		end)
		if mine then
			Fx.flash(GOLD, 0.15, 0.25)
		end
		return
	end

	-- Anticipación: la Melera brilla, el aire se encoge hacia ella
	Fx.pillar(center, { color = GOLD, height = 14, width = 4, life = windup + 0.1 })
	Fx.light(center + V3(0, 2, 0), { color = GOLD, range = 30, life = windup + 0.3 })
	Fx.ring(center, 10, { color = HONEY, life = windup, thickness = 0.6 })
	Fx.burst(center + V3(0, 2, 0), { color = HONEY, count = 10, speed = 4, size = 0.5, life = windup })
	Fx.sound("whoosh", center, 0.6)
	if mine then
		Fx.shake(0.2, windup)
	end
end

function fx.honey3_boom(caster: Player, payload, mine: boolean)
	local center = payload.center
	if typeof(center) ~= "Vector3" then
		return
	end
	local radius = tonumber(payload.radius) or 28
	local duration = tonumber(payload.duration) or 10
	Fx.dome(center, radius, 0.6, { color = GOLD })
	Fx.ring(center, radius, { color = GOLD, life = 0.5, thickness = 1.4 })
	task.delay(0.12, function()
		Fx.ring(center, radius * 0.7, { color = AMBER, life = 0.45, thickness = 1 })
	end)
	Fx.burst(center + V3(0, 2, 0), { color = GOLD, count = 30, speed = 30, size = 1.1, life = 0.8, up = 0.7 })
	Fx.word(center + V3(0, 7, 0), "¡REVENTÓN!", { color = GOLD, size = 83 })
	Fx.light(center, { color = GOLD, range = radius * 2.2, life = 0.6 })
	Fx.sound("boom", center, 0.8)
	if mine then
		Fx.flash(GOLD, 0.35, 0.3)
		Fx.shake(0.6, 0.45)
	end
	-- Lluvia de gotas que caen por toda la zona
	for i = 1, 22 do
		task.delay(0.1 + i * 0.06, function()
			local angle = rng:NextNumber(0, math.pi * 2)
			local r = math.sqrt(rng:NextNumber()) * radius
			local spot = V3(center.X + math.cos(angle) * r, GROUND + 0.3, center.Z + math.sin(angle) * r)
			drip(spot + V3(0, 16, 0), spot, 0.45, if i % 3 == 0 then GOLD else AMBER)
		end)
	end
	if type(payload.points) == "table" then
		for _, p in payload.points do
			Fx.burst(p, { color = AMBER, count = 6, size = 0.5, life = 0.35, speed = 12 })
		end
		loot(caster, payload.points, GOLD)
		numbers(mine, payload.points, payload.amounts)
	end
	if type(payload.golden) == "table" then
		for _, p in payload.golden do
			coat(p, "gold", duration, tonumber(payload.gold), mine)
		end
	end
end

function fx.honey3_drop(caster: Player, payload, mine: boolean)
	local points = payload.points
	if type(points) ~= "table" then
		return
	end
	for _, p in points do
		drip(p + V3(rng:NextNumber(-1, 1), 20, rng:NextNumber(-1, 1)), p, 0.35, GOLD, function()
			Fx.ring(p, 3, { color = GOLD, life = 0.25 })
			coat(p, "gold", tonumber(payload.duration) or 10, tonumber(payload.gold), mine)
		end)
	end
	task.delay(0.35, function()
		if type(payload.hit) == "table" then
			loot(caster, payload.hit, GOLD)
			numbers(mine, payload.hit, payload.amounts)
		end
	end)
	if math.random() < 0.3 then
		Fx.word(points[1] + V3(0, 3, 0), "¡PLIC!", { color = GOLD, size = 32, life = 0.45 })
	end
end

Players.PlayerRemoving:Connect(function(player)
	popBall(player)
end)

return {
	fx = fx,
	aura = aura,
	emblem = emblem,
}
