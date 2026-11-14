-- Tejedora (cliente): los hilos (Beam) de la hormiga a cada comida atada, la Red que se cierra, el
-- Capullo que viaja a casa, la Telaraña del suelo, el aura de seda y el emblema.
-- Los hilos se leen del atributo "WeaverTie<UserId>" de cada comida (lo pone el servidor): así los
-- ve todo el mundo, también quien entra tarde, y siguen a la comida si se mueve.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Abilities = require(script.Parent.Parent.Abilities)
local Fx = require(script.Parent.Parent.CasteFx)
local Pop = require(script.Parent.Parent.Fx) -- números de cómic de la dueña

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad

local INK = Color3.fromRGB(20, 16, 16)
local SILK = Color3.fromRGB(250, 246, 255)
local PINK = Color3.fromRGB(255, 120, 200)
local VIOLET = Color3.fromRGB(170, 90, 230)
local GOLD = Color3.fromRGB(255, 200, 60)
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
		Fx.orbs(points, hill, { color = color or PINK })
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

-- Hilo recto de a a b que tiembla y se apaga (un tirón de seda)
local function twang(a: Vector3, b: Vector3, color: Color3, life: number, thick: number?)
	local len = (b - a).Magnitude
	if len < 0.1 then
		return
	end
	local p = piece(Fx.folder(), V3(len, thick or 0.14, thick or 0.14), color, "rod", Enum.Material.Neon)
	p.CFrame = along((a + b) / 2, b - a)
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = V3(len, 0.03, 0.03) }):Play()
	Debris:AddItem(p, life + 0.05)
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

-- Telaraña de piezas: radios y anillos de hilo sobre el suelo. Devuelve el modelo y una función para
-- desplegarla (0..1) y recolocarla.
local function webModel(radius: number, spokes: number, rings: number, color: Color3)
	local model = Instance.new("Model")
	model.Name = "WeaverWeb"
	local items = {}
	for i = 1, spokes do
		local angle = (i - 1) / spokes * math.pi * 2
		local p = piece(model, V3(radius, 0.12, 0.12), color, "rod", Enum.Material.Neon)
		table.insert(items, { part = p, kind = "spoke", angle = angle })
	end
	for r = 1, rings do
		local ringRadius = radius * r / (rings + 0.3)
		local segments = math.max(8, math.floor(ringRadius * 0.9))
		for s = 1, segments do
			local a0 = (s - 1) / segments * math.pi * 2
			local a1 = s / segments * math.pi * 2
			local p0 = V3(math.cos(a0), 0, math.sin(a0)) * ringRadius
			local p1 = V3(math.cos(a1), 0, math.sin(a1)) * ringRadius
			-- Cada tramo cuelga un poco hacia el centro, como la seda de verdad
			local mid = (p0 + p1) / 2 * 0.96
			local p = piece(model, V3((p1 - p0).Magnitude * 1.04, 0.09, 0.09), if r % 2 == 0 then PINK else color, "rod", Enum.Material.Neon)
			table.insert(items, { part = p, kind = "ring", mid = mid, dir = p1 - p0, ring = r })
		end
	end
	local function place(center: Vector3, open: number)
		local base = V3(center.X, GROUND + 0.15, center.Z)
		local parts, cframes = {}, {}
		for _, item in items do
			table.insert(parts, item.part)
			if item.kind == "spoke" then
				local dir = V3(math.cos(item.angle), 0, math.sin(item.angle))
				local len = radius * open
				table.insert(cframes, along(base + dir * len / 2, dir) * CF(0, 0, 0))
				item.part.Size = V3(math.max(len, 0.05), 0.12, 0.12)
			else
				local show = open >= item.ring / (rings + 0.5)
				item.part.Transparency = if show then 0.15 else 1
				table.insert(cframes, along(base + item.mid * math.max(open, 0.01), item.dir))
			end
		end
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	model.Parent = inkParent()
	return model, place
end

---------------------------------------------------------------------------------------------------
-- Velocidad de la dueña sobre su Telaraña (la velocidad del personaje se decide en el cliente)
---------------------------------------------------------------------------------------------------

local myWeb: any = nil -- { center, radius, untilClock, follow, speed }
local wrapped = false

local function speedNow(): number
	local web = myWeb
	if not web or os.clock() > web.untilClock then
		return 1
	end
	if web.follow then
		return web.speed
	end
	local root = rootOf(Players.LocalPlayer)
	if root and ((root.Position - web.center) * FLAT).Magnitude <= web.radius then
		return web.speed
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
-- Aura: chal de seda, hilera rosa en la punta del abdomen, halo de telaraña a la espalda y los hilos
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
	folder.Name = "WeaverAura"
	folder.Parent = character
	local alive = true
	local tip: Attachment? = nil
	local halo: BasePart? = nil
	local player = Players:GetPlayerFromCharacter(character)
	local key = if player then "WeaverTie" .. player.UserId else ""

	local function build()
		folder:ClearAllChildren()
		tip, halo = nil, nil
		local thorax = character:FindFirstChild("Thorax") :: BasePart?
		local abdomen = character:FindFirstChild("Abdomen") :: BasePart?
		if not thorax or not abdomen then
			return
		end
		local s = character:GetScale() * (1 + 0.035 * math.clamp(rank, 1, 10))

		-- Chal de seda sobre el tórax
		local shawl = piece(folder, V3(1.55, 0.7, 1.45) * s, SILK, "blob")
		shawl.Transparency = 0.25
		weldTo(thorax, shawl, CF(0, 0.42 * s, 0.05 * s))
		-- Hilera rosa en la punta del abdomen, con su luz
		local spinner = piece(folder, V3(0.5, 0.5, 0.5) * s, PINK, "blob", Enum.Material.Neon)
		weldTo(abdomen, spinner, CF(0, -0.05 * s, 1.35 * s))
		local light = Instance.new("PointLight")
		light.Color = VIOLET
		light.Range = 7
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = spinner
		local att = Instance.new("Attachment")
		att.Name = "WeaverTip"
		att.Parent = spinner
		tip = att

		-- Halo de telaraña de pie sobre la espalda: radios y cuentas rosas
		local haloRadius = (0.75 + 0.05 * math.clamp(rank, 1, 10)) * character:GetScale()
		local hub = piece(folder, V3(0.32, 0.32, 0.32) * s, if mastered then GOLD else VIOLET, "blob", Enum.Material.Neon)
		local hubAt = CF(0, 1.5 * s, 0.45 * s) * ANG(rad(-15), 0, 0)
		weldTo(thorax, hub, hubAt)
		halo = hub
		for i = 1, 6 do
			local angle = i / 6 * math.pi * 2
			local dir = V3(math.cos(angle), math.sin(angle), 0)
			local spoke = piece(folder, V3(haloRadius, 0.06, 0.06), SILK, "rod", Enum.Material.Neon)
			weldTo(thorax, spoke, hubAt * along(dir * haloRadius / 2, dir))
			local bead = piece(folder, V3(0.2, 0.2, 0.2) * s, if i % 2 == 0 then PINK else VIOLET, "blob", Enum.Material.Neon)
			weldTo(thorax, bead, hubAt * CF(dir * haloRadius))
			local following = V3(math.cos(angle + math.pi / 3), math.sin(angle + math.pi / 3), 0) * haloRadius * 0.62
			local here = dir * haloRadius * 0.62
			local link = piece(folder, V3((following - here).Magnitude, 0.05, 0.05), PINK, "rod", Enum.Material.Neon)
			weldTo(thorax, link, hubAt * along((here + following) / 2, following - here))
		end
		if mastered then
			local crown = piece(folder, V3(0.35, 0.12, 0.35) * s, GOLD, "rod", Enum.Material.Neon)
			weldTo(thorax, crown, hubAt * CF(0, haloRadius + 0.15 * s, 0) * ANG(0, 0, rad(90)))
		end
	end
	build()

	-- Hilos: un ancla por comida atada (la comida se mueve, el ancla la sigue) y un Beam desde la hilera
	local threads: { [Model]: any } = {}
	local function dropThread(food: Model)
		local t = threads[food]
		if t then
			threads[food] = nil
			t.anchor:Destroy()
		end
	end

	local scanAt = 0
	local connection = RunService.Heartbeat:Connect(function()
		if not alive then
			return
		end
		local clock = os.clock()
		if clock >= scanAt then
			scanAt = clock + 0.25
			if not tip or not tip.Parent or not halo or not halo.Parent then
				build()
			end
			local container = Workspace:FindFirstChild("Food")
			local now = serverNow()
			local seen = {}
			if container and tip then
				for _, food in container:GetChildren() do
					local untilT = food:GetAttribute(key)
					if type(untilT) == "number" and untilT > now and food:IsA("Model") then
						seen[food] = true
						if not threads[food] then
							local anchor = Instance.new("Part")
							anchor.Name = "WeaverKnot"
							anchor.Anchored = true
							anchor.CanCollide = false
							anchor.CanQuery = false
							anchor.CanTouch = false
							anchor.Transparency = 1
							anchor.Size = V3(0.2, 0.2, 0.2)
							anchor.CFrame = food:GetPivot()
							local att = Instance.new("Attachment")
							att.Parent = anchor
							local beam = Instance.new("Beam")
							beam.Attachment0 = tip
							beam.Attachment1 = att
							beam.Color = ColorSequence.new(SILK, PINK)
							beam.Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 0.05),
								NumberSequenceKeypoint.new(0.5, 0.25),
								NumberSequenceKeypoint.new(1, 0.05),
							})
							beam.Width0 = 0.16
							beam.Width1 = 0.22
							beam.LightEmission = 0.6
							beam.FaceCamera = true
							beam.Segments = 12
							beam.CurveSize0 = -1.5
							beam.CurveSize1 = 1.5
							beam.Parent = anchor
							anchor.Parent = Fx.folder()
							threads[food] = { anchor = anchor, beam = beam }
							Fx.burst(food:GetPivot().Position + V3(0, 1, 0), { color = PINK, count = 4, size = 0.35, life = 0.3, speed = 6 })
						end
					end
				end
			end
			for food in threads do
				if not seen[food] then
					dropThread(food)
				end
			end
		end
		-- Las anclas siguen a su comida (la Red y el Capullo la mueven)
		for food, t in threads do
			if food.Parent then
				local pos = food:GetPivot().Position + V3(0, 1, 0)
				t.anchor.CFrame = CF(pos)
				-- El hilo vibra un poco
				t.beam.CurveSize0 = -1.5 + math.sin(clock * 6 + pos.X) * 0.4
			else
				dropThread(food)
			end
		end
	end)

	return function()
		alive = false
		connection:Disconnect()
		for food in threads do
			dropThread(food)
		end
		folder:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- Emblema: telaraña de tres anillos con una perla
---------------------------------------------------------------------------------------------------

local function emblem(parent: GuiObject, color: Color3)
	local holder = Instance.new("Frame")
	holder.Name = "WeaverEmblem"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent

	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.Size = UDim2.fromScale(0.84, 0.84)
	back.BackgroundColor3 = color
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local st = Instance.new("UIStroke")
	st.Color = INK
	st.Thickness = 3
	st.Parent = back
	back.Parent = holder

	for i = 1, 4 do
		local spoke = Instance.new("Frame")
		spoke.AnchorPoint = Vector2.new(0.5, 0.5)
		spoke.Position = UDim2.fromScale(0.5, 0.5)
		spoke.Size = UDim2.new(0.8, 0, 0, 2)
		spoke.Rotation = (i - 1) * 45
		spoke.BackgroundColor3 = INK
		spoke.BorderSizePixel = 0
		spoke.Parent = holder
	end
	for i, scale in { 0.66, 0.44, 0.22 } do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(scale, scale)
		ring.BackgroundTransparency = 1
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(1, 0)
		rc.Parent = ring
		local rs = Instance.new("UIStroke")
		rs.Color = if i == 2 then PINK else INK
		rs.Thickness = 2
		rs.Parent = ring
		ring.Parent = holder
	end
	local pearl = Instance.new("Frame")
	pearl.AnchorPoint = Vector2.new(0.5, 0.5)
	pearl.Position = UDim2.fromScale(0.68, 0.32)
	pearl.Size = UDim2.fromScale(0.2, 0.2)
	pearl.BackgroundColor3 = PINK
	pearl.BorderSizePixel = 0
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = pearl
	local ps = Instance.new("UIStroke")
	ps.Color = INK
	ps.Thickness = 2
	ps.Parent = pearl
	pearl.Parent = holder
end

---------------------------------------------------------------------------------------------------
-- Efectos
---------------------------------------------------------------------------------------------------

local fx = {}

-- Pasiva: los hilos dan un tirón a cada atada; el Nudo final los rompe de golpe
function fx.passive(caster: Player, payload, mine: boolean)
	local from = payload.from
	if typeof(from) ~= "Vector3" then
		return
	end
	if type(payload.points) == "table" then
		for _, p in payload.points do
			twang(from, p, PINK, 0.18, 0.1)
			Fx.burst(p, { color = PINK, count = 3, size = 0.35, life = 0.25, speed = 6 })
		end
		numbers(mine, payload.points, payload.amounts)
	end
	if type(payload.snap) == "table" and #payload.snap > 0 then
		for _, p in payload.snap do
			twang(from, p, SILK, 0.3, 0.25)
			Fx.burst(p, { color = SILK, count = 10, size = 0.5, life = 0.4, speed = 14 })
			Fx.ring(p, 4, { color = PINK, life = 0.3 })
		end
		Fx.word(payload.snap[1] + V3(0, 3, 0), "¡TRAS!", { color = PINK, size = 46 })
		Fx.sound("slash", from, 1.3)
		loot(caster, payload.snap)
		numbers(mine, payload.snap, payload.snapAmounts)
		if mine then
			Fx.shake(0.2, 0.15)
		end
	end
end

-- Red: vuela, se abre sobre las comidas y se cierra arrastrándolas al montón
function fx.weaver1(caster: Player, payload, mine: boolean)
	local center, pile = payload.center, payload.pile
	if typeof(center) ~= "Vector3" or typeof(pile) ~= "Vector3" then
		return
	end
	local radius = tonumber(payload.radius) or 14
	local pull = tonumber(payload.pull) or 0.75
	local origin = if typeof(payload.origin) == "Vector3" then payload.origin else center
	Fx.sound("whoosh", origin, 1.2)
	Fx.lob(origin + V3(0, 2, 0), center + V3(0, 1, 0), { color = SILK, size = 0.8, time = 0.18, height = 5 })

	local model, place = webModel(radius, 8, 2, SILK)
	local began = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - began
		if t < 0.18 then
			place(center, t / 0.18 * 0.3)
			return
		end
		-- Se abre de golpe y luego se cierra deslizándose hasta el montón
		local open = if t < 0.3 then 0.3 + (t - 0.18) / 0.12 * 0.7 else 1
		local close = math.clamp((t - 0.3) / pull, 0, 1)
		local eased = 1 - (1 - close) ^ 3
		local c = center:Lerp(pile, eased)
		place(c, open * (1 - 0.75 * eased))
		if close >= 1 then
			connection:Disconnect()
			fadeOut(model, 0.4)
		end
	end)

	-- Un hilo de cada comida al montón mientras se arrastran
	if type(payload.from) == "table" and type(payload.to) == "table" then
		for i, p in payload.from do
			local dest = payload.to[i]
			if typeof(p) == "Vector3" and typeof(dest) == "Vector3" then
				task.delay(0.18, function()
					twang(p, dest, SILK, pull, 0.12)
				end)
			end
		end
	end
	task.delay(0.2, function()
		Fx.ring(center, radius, { color = PINK, life = 0.4, thickness = 0.6 })
		Fx.word(center + V3(0, 4, 0), if payload.haul then "¡A MIS PATAS!" else "¡ATRAPADAS!", { color = PINK, size = 51 })
		Fx.sound("pop", center, 1.4)
		if mine then
			Fx.shake(0.15, 0.2)
		end
	end)
	task.delay(0.3 + pull, function()
		Fx.burst(pile + V3(0, 1, 0), { color = SILK, count = 12, speed = 12, size = 0.6, life = 0.45, up = 0.5 })
		Fx.ring(pile, 5, { color = SILK, life = 0.35 })
		if payload.haul and typeof(origin) == "Vector3" then
			twang(origin + V3(0, 1, 0), pile + V3(0, 1, 0), PINK, 0.5, 0.2)
		end
	end)
end

function fx.weaver1_snap(caster: Player, payload, mine: boolean)
	local center = payload.center
	if typeof(center) ~= "Vector3" or type(payload.points) ~= "table" then
		return
	end
	Fx.ring(center, 8, { color = PINK, life = 0.4, thickness = 0.8 })
	Fx.word(center + V3(0, 4, 0), "¡CHAS!", { color = PINK, size = 55 })
	Fx.light(center, { color = PINK, range = 16, life = 0.3 })
	Fx.sound("slash", center, 1.1)
	for _, p in payload.points do
		Fx.burst(p, { color = PINK, count = 6, size = 0.5, life = 0.35, speed = 12 })
	end
	loot(caster, payload.points)
	numbers(mine, payload.points, payload.amounts)
	if mine then
		Fx.shake(0.25, 0.2)
	end
end

-- Capullo de seda: se teje alrededor de la comida y viaja a casa (o revienta, con el Capullo bomba)
local function cocoonModel(size: number): Model
	local model = Instance.new("Model")
	model.Name = "WeaverCocoon"
	local body = piece(model, V3(1, 1.25, 1) * size, SILK, "blob")
	body.Name = "Body"
	body.Transparency = 0.1
	for i = 1, 3 do
		local band = piece(model, V3(0.12 * size, 1.05 * size, 1.05 * size), if i == 2 then PINK else VIOLET, "rod", Enum.Material.Neon)
		band.Name = "Band" .. i
	end
	model.Parent = inkParent()
	return model
end

local function placeCocoon(model: Model, at: Vector3, size: number, spin: number, grow: number)
	local s = math.max(grow, 0.05)
	local parts, cframes = {}, {}
	local body = model:FindFirstChild("Body") :: BasePart
	body.Size = V3(1, 1.25, 1) * size * s
	table.insert(parts, body)
	table.insert(cframes, CF(at) * ANG(0, spin, 0))
	for i = 1, 3 do
		local band = model:FindFirstChild("Band" .. i) :: BasePart
		band.Size = V3(0.12, 1.05, 1.05) * size * s
		table.insert(parts, band)
		table.insert(cframes, CF(at + V3(0, (i - 2) * 0.35 * size * s, 0)) * ANG(0, spin + i, rad(90) + (i - 2) * 0.35))
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function hillAnchor(to: Vector3): Attachment
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = V3(0.2, 0.2, 0.2)
	anchor.CFrame = CF(to)
	anchor.Parent = Fx.folder()
	local att = Instance.new("Attachment")
	att.Parent = anchor
	return att
end

function fx.weaver2(caster: Player, payload, mine: boolean)
	local points, to = payload.points, payload.to
	if type(points) ~= "table" or typeof(to) ~= "Vector3" then
		return
	end
	local time = tonumber(payload.time) or 4
	local burst = payload.burst == true
	local origin = if typeof(payload.origin) == "Vector3" then payload.origin else points[1]
	Fx.sound("whoosh", origin, 1.4)

	for i, p in points do
		if typeof(p) ~= "Vector3" then
			continue
		end
		local whole = type(payload.wholes) == "table" and payload.wholes[i] == 1
		local size = if whole or burst then 3.2 else 1.7
		local model = cocoonModel(size)
		twang(origin + V3(0, 1, 0), p, SILK, 0.35, 0.1)
		Fx.word(p + V3(0, 4, 0), if burst then "¡TIC, TAC!" else "¡ENVUELTA!", { color = PINK, size = 41 })
		local began = os.clock()
		local wrapTime = 0.35
		local att: Attachment? = nil
		local cocoonAtt = Instance.new("Attachment")
		cocoonAtt.Parent = model:FindFirstChild("Body")
		if not burst then
			-- El hilo que remolca, del capullo a la boca del hormiguero
			att = hillAnchor(to)
			local beam = Instance.new("Beam")
			beam.Attachment0 = cocoonAtt
			beam.Attachment1 = att
			beam.Color = ColorSequence.new(SILK, PINK)
			beam.Width0 = 0.2
			beam.Width1 = 0.12
			beam.LightEmission = 0.6
			beam.FaceCamera = true
			beam.Segments = 10
			beam.CurveSize0 = 3
			beam.CurveSize1 = -2
			beam.Parent = att.Parent
		end
		local connection: RBXScriptConnection
		connection = RunService.Heartbeat:Connect(function()
			local t = os.clock() - began
			local grow = math.clamp(t / wrapTime, 0, 1)
			local spin = t * 7
			if burst then
				-- Se hincha y tiembla hasta reventar
				local swell = 1 + math.clamp(t / 1.1, 0, 1) * 0.35 + math.sin(t * 40) * 0.05
				placeCocoon(model, p + V3(0, 0.5, 0), size * swell, spin, grow)
				if t >= 1.15 then
					connection:Disconnect()
					model:Destroy()
				end
				return
			end
			local u = math.clamp((t - 0.05) / time, 0, 1)
			local eased = 1 - (1 - u) ^ 3 -- igual que el remolque del servidor
			local pos: Vector3
			if whole then
				pos = p:Lerp(to, eased) + V3(0, 0.5, 0)
			else
				pos = p:Lerp(to, eased) + V3(0, 6 * 4 * u * (1 - u), 0)
			end
			placeCocoon(model, pos, size, spin, grow)
			if u >= 1 then
				connection:Disconnect()
				if att then
					att.Parent:Destroy()
				end
				Fx.burst(pos, { color = SILK, count = 10, size = 0.6, life = 0.4, speed = 12 })
				model:Destroy()
			end
		end)
	end
	if mine then
		Fx.shake(0.12, 0.15)
	end
end

function fx.weaver2_land(caster: Player, payload, mine: boolean)
	local at = payload.at
	if typeof(at) ~= "Vector3" then
		return
	end
	Fx.ring(at - V3(0, 3, 0), 7, { color = PINK, life = 0.45 })
	Fx.burst(at, { color = PINK, count = 14, speed = 16, size = 0.7, life = 0.5, up = 0.7 })
	Fx.word(at + V3(0, 3, 0), "¡A LA DESPENSA!", { color = PINK, size = 46 })
	Fx.light(at, { color = VIOLET, range = 14, life = 0.4 })
	Fx.sound("chime", at, 1.1)
	numbers(mine, { at }, { payload.amount })
end

function fx.weaver2_burst(caster: Player, payload, mine: boolean)
	local centers = payload.centers
	if type(centers) ~= "table" then
		return
	end
	local radius = tonumber(payload.radius) or 10
	for _, c in centers do
		Fx.ring(c, radius, { color = PINK, life = 0.45, thickness = 0.9 })
		Fx.burst(c, { color = SILK, count = 18, speed = 22, size = 0.8, life = 0.55, up = 0.6 })
		Fx.light(c, { color = PINK, range = radius * 2, life = 0.35 })
		Fx.word(c + V3(0, 4, 0), "¡PUM!", { color = PINK, size = 60 })
		for _ = 1, 6 do
			local angle = rng:NextNumber(0, math.pi * 2)
			twang(c, c + V3(math.cos(angle), rng:NextNumber(-0.2, 0.4), math.sin(angle)) * radius, SILK, 0.3, 0.08)
		end
	end
	Fx.sound("boom", centers[1], 1.2)
	if type(payload.points) == "table" then
		loot(caster, payload.points)
		numbers(mine, payload.points, payload.amounts)
	end
	if mine then
		Fx.shake(0.35, 0.25)
		Fx.flash(PINK, 0.2, 0.15)
	end
end

-- Telaraña: se despliega en el suelo, brilla mientras dura y se deshace
function fx.weaver3(caster: Player, payload, mine: boolean)
	local center = payload.center
	if typeof(center) ~= "Vector3" then
		return
	end
	local radius = tonumber(payload.radius) or 30
	local duration = tonumber(payload.duration) or 12
	local follow = payload.follow == true
	local origin = if typeof(payload.origin) == "Vector3" then payload.origin else center

	-- Anticipación: la hilera se carga y lanza un hilo al centro
	Fx.light(origin + V3(0, 2, 0), { color = PINK, range = 10, life = 0.3 })
	if not follow then
		twang(origin + V3(0, 1, 0), center + V3(0, 0.5, 0), PINK, 0.3, 0.2)
	end
	Fx.sound("whoosh", center, 0.8)
	if mine then
		myWeb = {
			center = center,
			radius = radius,
			untilClock = os.clock() + duration,
			follow = follow,
			speed = tonumber(payload.speed) or 1.5,
		}
		wrapSpeed()
		Fx.flash(PINK, 0.18, 0.2)
		Fx.shake(0.3, 0.25)
	end

	local model, place = webModel(radius, 12, 3, SILK)
	if not follow then
		Fx.puddle(center, radius, duration, { color = Color3.fromRGB(255, 220, 245) })
	end
	task.delay(0.15, function()
		Fx.ring(center, radius, { color = PINK, life = 0.5, thickness = 1 })
		Fx.word(center + V3(0, 6, 0), "¡TELARAÑA!", { color = PINK, size = 69 })
	end)
	local began = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - began
		local open = math.clamp(t / 0.45, 0, 1)
		open = 1 - (1 - open) ^ 2
		if t > duration - 0.5 then
			open *= math.clamp((duration - t) / 0.5, 0, 1)
		end
		local c = center
		if follow then
			local r = rootOf(caster)
			if r then
				c = r.Position
			end
		end
		place(c, open)
		if t >= duration then
			connection:Disconnect()
			model:Destroy()
		end
	end)
end

function fx.weaver3_pulse(caster: Player, payload, mine: boolean)
	local from = payload.from
	if typeof(from) ~= "Vector3" or type(payload.points) ~= "table" then
		return
	end
	Fx.ring(from, 3, { color = PINK, life = 0.25 })
	for _, p in payload.points do
		twang(from, p, PINK, 0.22, 0.12)
		Fx.burst(p, { color = PINK, count = 4, size = 0.4, life = 0.3, speed = 9 })
	end
	if math.random() < 0.3 then
		Fx.word(from + V3(0, 3, 0), "¡TIIING!", { color = PINK, size = 32, life = 0.45 })
	end
	loot(caster, payload.points)
	numbers(mine, payload.points, payload.amounts)
end

return {
	fx = fx,
	aura = aura,
	emblem = emblem,
}
