-- Voltaica (cliente): rayos de cómic, bobinas, la nube de tormenta, el aura de chispas y el emblema.
-- El servidor manda en cada efecto los puntos exactos que golpeó; aquí solo se pinta.
-- La sacudida, el destello y los sonidos fuertes solo para la dueña (`mine`).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Fx = require(script.Parent.Parent.CasteFx)
local OldFx = require(script.Parent.Parent.Fx)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local rng = Random.new()
local UP = Vector3.new(0, 1, 0)
local INK = Color3.fromRGB(20, 16, 16)
local YELLOW = Color3.fromRGB(255, 221, 51)
local CYAN = Color3.fromRGB(64, 196, 255)
local WHITE = Color3.fromRGB(255, 255, 240)
local GOLD = Color3.fromRGB(255, 196, 40)
local STORM = Color3.fromRGB(58, 58, 78)
local SEEN = 260 -- más lejos de la cámara, los efectos de otras no se pintan

----------------------------------------------------------------------------------------------------
-- Ayudas

-- Onomatopeya: los tamaños de este archivo van en "veces lo normal" (CasteFx.word mide en píxeles);
-- las grandes llevan estallido de cómic detrás
local function word(pos: Vector3, text: string, opts: any?)
	local o = table.clone(opts or {})
	local k = tonumber(o.size) or 1
	o.size = 46 * k
	if o.burst == nil then
		o.burst = k >= 1.2
	end
	Fx.word(pos, text, o)
end

-- Onda pegada al suelo (los puntos del servidor van a media altura) y con grosor razonable
local function ring(pos: Vector3, radius: number, opts: any?)
	local o = table.clone(opts or {})
	if o.thickness then
		o.thickness = math.min(o.thickness, 1.4)
	end
	Fx.ring(Vector3.new(pos.X, Config.GroundY + 0.06, pos.Z), radius, o)
end

local function seen(pos: Vector3?): boolean
	local camera = Workspace.CurrentCamera
	return pos == nil or camera == nil or (camera.CFrame.Position - pos).Magnitude < SEEN
end

local function vec(v: any, fallback: Vector3?): Vector3?
	return if typeof(v) == "Vector3" then v else fallback
end

local function list(v: any): { Vector3 }
	local out = {}
	if type(v) == "table" then
		for _, p in v do
			if typeof(p) == "Vector3" then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function tween(obj: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape -- antes que Size: una bola fuerza tamaño uniforme
	end
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent or Fx.folder()
	return p
end

-- La comida que hay en un punto golpeado (el servidor manda centro + 1 de alto)
local function foodAt(pt: Vector3): Model?
	local folder = Workspace:FindFirstChild("Food")
	if not folder then
		return nil
	end
	local best, bestGap = nil, 2.5
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			local gap = (model:GetPivot().Position + UP - pt).Magnitude
			if gap < bestGap then
				best, bestGap = model, gap
			end
		end
	end
	return best
end

-- Las comidas golpeadas se aplastan a la vez, apartándose del golpe
local function react(pts: { Vector3 }, from: Vector3?, amount: number?)
	for i, pt in pts do
		if i > 14 then
			break
		end
		local food = foodAt(pt)
		if food then
			pcall(OldFx.squash, food, amount or 0.22, from)
		end
	end
end

-- El botín vuela al hormiguero de quien lanzó
local function loot(caster: Player, pts: { Vector3 }, color: Color3?)
	if #pts == 0 then
		return
	end
	local hill = Fx.hillOf(caster)
	if hill then
		Fx.orbs(pts, hill, { color = color or YELLOW })
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

----------------------------------------------------------------------------------------------------
-- Bobinas (las guarda el cliente por id para tirar los rayos desde su punta)

type Coil = { model: Model, top: BasePart, rings: { BasePart }, life: number, dead: boolean }
local coils: { [string]: Coil } = {}

local function buildCoil(at: Vector3, scale: number): Coil
	local model = Instance.new("Model")
	model.Name = "VoltCoil"
	local function add(props): Part
		return part(props, model)
	end
	add({
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = INK,
		Size = Vector3.new(0.7, 3.4, 3.4) * scale,
		CFrame = CFrame.new(at + UP * 0.35 * scale) * CFrame.Angles(0, 0, math.pi / 2),
	})
	add({
		Name = "Shaft",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 70, 86),
		Size = Vector3.new(4.6, 0.9, 0.9) * scale,
		CFrame = CFrame.new(at + UP * 2.6 * scale) * CFrame.Angles(0, 0, math.pi / 2),
	})
	local rings = {}
	for i, d in { 2.5, 2.0, 1.5 } do
		table.insert(
			rings,
			add({
				Name = "Ring",
				Shape = Enum.PartType.Cylinder,
				Color = YELLOW,
				Size = Vector3.new(0.32, d, d) * scale,
				CFrame = CFrame.new(at + UP * (1.3 + i * 1.05) * scale) * CFrame.Angles(0, 0, math.pi / 2),
			})
		)
	end
	local top = add({
		Name = "Top",
		Shape = Enum.PartType.Ball,
		Color = CYAN,
		Size = Vector3.one * 1.6 * scale,
		CFrame = CFrame.new(at + UP * 5.4 * scale),
	})
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = 14 * scale
	light.Brightness = 2.2
	light.Shadows = false
	light.Parent = top
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(WHITE, CYAN)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.35 * scale, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 14
	sparks.Parent = top
	model.PrimaryPart = top
	model.Parent = Fx.folder()
	return { model = model, top = top, rings = rings, life = 0, dead = false }
end

-- La bobina cae del cielo, se clava y se queda zumbando; al final se apaga y se hunde
local function plant(id: string, at: Vector3, life: number, radius: number, follow: Player?, mine: boolean)
	local scale = if follow then 0.6 else 1
	local coil = buildCoil(at, scale)
	coils[id] = coil
	local model = coil.model
	local landed = model:GetPivot()
	model:PivotTo(landed + UP * 14)

	-- Zona de alcance: un disco tenue en el suelo
	local disc = part({
		Name = "Reach",
		Shape = Enum.PartType.Cylinder,
		Color = CYAN,
		Transparency = 0.88,
		Size = Vector3.new(0.12, radius * 2, radius * 2),
		CFrame = CFrame.new(at + UP * 0.08) * CFrame.Angles(0, 0, math.pi / 2),
	}, model)

	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if coil.dead or not model.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - started
		local base: CFrame
		if follow then
			-- Bobina orbital: da vueltas alrededor de la dueña a media altura
			local root = rootOf(follow)
			local center = if root then root.Position else at
			local angle = t * 3.2
			base = CFrame.new(center + Vector3.new(math.cos(angle) * 4, 1.5 + math.sin(t * 6) * 0.3, math.sin(angle) * 4))
			model:PivotTo(base)
			disc.CFrame = CFrame.new(Vector3.new(center.X, at.Y + 0.08, center.Z)) * CFrame.Angles(0, 0, math.pi / 2)
		elseif t < 0.18 then
			local k = t / 0.18
			model:PivotTo(landed + UP * 14 * (1 - k * k))
		else
			model:PivotTo(landed)
		end
		-- Los anillos laten uno detrás de otro
		for i, ring in coil.rings do
			local pulse = 0.5 + 0.5 * math.sin(t * 10 - i * 1.3)
			ring.Color = YELLOW:Lerp(WHITE, pulse * 0.6)
		end
	end)

	if not follow then
		task.delay(0.18, function()
			if coil.dead then
				return
			end
			ring(at, radius, { color = CYAN, life = 0.45, thickness = 1.2 })
			Fx.burst(at + UP, { color = YELLOW, count = 16, speed = 18, size = 0.6, life = 0.4, up = 6 })
			word(at + UP * 7, "¡CLANK!", { color = YELLOW, size = 1 })
			Fx.light(at + UP * 4, { color = CYAN, range = 18, life = 0.3 })
			Fx.sound("thud", at, 1.1)
			if mine then
				Fx.shake(0.22, 0.2)
			end
		end)
	else
		Fx.burst(at + UP * 2, { color = CYAN, count = 12, speed = 12, size = 0.5, life = 0.35 })
		Fx.sound("chime", at, 1.4)
	end

	task.delay(life, function()
		coil.dead = true
		if coils[id] == coil then
			coils[id] = nil
		end
		if model.Parent then
			Fx.burst(coil.top.Position, { color = CYAN, count = 10, speed = 8, size = 0.4, life = 0.3 })
			for _, child in model:GetDescendants() do
				if child:IsA("BasePart") then
					tween(child, 0.35, { Transparency = 1 })
				elseif child:IsA("ParticleEmitter") then
					child.Enabled = false
				end
			end
			Debris:AddItem(model, 0.4)
		end
	end)
end

local function coilTop(id: any, fallback: Vector3): Vector3
	local coil = if type(id) == "string" then coils[id] else nil
	if coil and not coil.dead and coil.top.Parent then
		return coil.top.Position
	end
	return fallback
end

----------------------------------------------------------------------------------------------------
-- Nubes de tormenta (por jugadora)

local storms: { [Player]: { model: Model, core: BasePart, center: () -> Vector3 } } = {}

local function buildCloud(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "VoltStorm"
	for i = 1, 9 do
		local angle = i / 9 * math.pi * 2
		local r = if i % 3 == 0 then 2 else 5.5
		local size = rng:NextNumber(6, 10)
		part({
			Name = "Puff",
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.SmoothPlastic,
			Color = STORM:Lerp(Color3.fromRGB(110, 110, 135), rng:NextNumber(0, 0.4)),
			Size = Vector3.one * size,
			CFrame = CFrame.new(math.cos(angle) * r, rng:NextNumber(-1, 1.5), math.sin(angle) * r),
		}, model)
	end
	local core = part({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Color = YELLOW,
		Transparency = 0.35,
		Size = Vector3.one * 5,
		CFrame = CFrame.new(0, -1.5, 0),
	}, model)
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Range = 40
	light.Brightness = 2
	light.Shadows = false
	light.Parent = core
	model.PrimaryPart = core
	return model, core
end

----------------------------------------------------------------------------------------------------
-- Efectos

local fx = {}

-- Arco de la pasiva: rayos finos a las comidas de al lado (o uno gordo con Alto voltaje)
function fx.passive(caster: Player, p: any, mine: boolean)
	local o = vec(p.o)
	if not o or (not mine and not seen(o)) then
		return
	end
	local pts = list(p.pts)
	local heavy = p.heavy == true
	for _, pt in pts do
		Fx.bolt(o, pt, { color = if heavy then YELLOW else CYAN, width = if heavy then 0.55 else 0.25, life = 0.14, jitter = 0.9, forks = if heavy then 2 else 0 })
		Fx.burst(pt, { color = if p.static then CYAN else YELLOW, count = if heavy then 10 else 5, speed = 10, size = 0.4, life = 0.3 })
		if p.static then
			ring(pt, 2.5, { color = CYAN, life = 0.3, thickness = 0.4 })
		end
	end
	react(pts, o, if heavy then 0.25 else 0.14)
	if heavy and #pts > 0 then
		word(pts[1] + UP * 2, "¡BZZT!", { color = YELLOW, size = 0.7, life = 0.5 })
	end
	if mine then
		Fx.sound("zap", o, rng:NextNumber(1.5, 1.9))
	end
end

-- Sobrecarga: nova alrededor
function fx.volt_nova(caster: Player, p: any, mine: boolean)
	local o = vec(p.o)
	if not o or (not mine and not seen(o)) then
		return
	end
	local r = tonumber(p.r) or 16
	local pts = list(p.pts)
	ring(o, r, { color = YELLOW, life = 0.4, thickness = 1.4 })
	ring(o, r * 0.6, { color = CYAN, life = 0.3, thickness = 0.8 })
	Fx.light(o, { color = YELLOW, range = r * 1.5, life = 0.3 })
	word(o + UP * 5, "¡BZZZT!", { color = YELLOW, size = 1.1 })
	for _, pt in pts do
		Fx.bolt(o, pt, { color = YELLOW, width = 0.35, life = 0.18, forks = 1 })
	end
	react(pts, o, 0.3)
	Fx.sound("zap", o, 0.8)
	if mine then
		Fx.shake(0.25, 0.25)
		Fx.flash(YELLOW, 0.2, 0.12)
	end
end

-- Descarga: carga en las mandíbulas, rayo de tramo en tramo y estallido al final
function fx.volt1(caster: Player, p: any, mine: boolean)
	local mode = p.mode
	local pts = list(p.pts)
	local xa, xb = list(p.xa), list(p.xb)

	if mode == "lance" then
		local o, b = vec(p.o), vec(p.b)
		if not o or not b or (not mine and not seen(o)) then
			return
		end
		-- Anticipación: chispas que se juntan en la boca
		Fx.light(o, { color = CYAN, range = 10, life = 0.15 })
		Fx.burst(o, { color = WHITE, count = 8, speed = 3, size = 0.4, life = 0.15 })
		task.delay(0.1, function()
			local beam = part({
				Name = "Lance",
				Shape = Enum.PartType.Cylinder,
				Color = WHITE,
				Size = Vector3.new((b - o).Magnitude, 1.6, 1.6),
				CFrame = CFrame.lookAt((o + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
			})
			local glow = part({
				Name = "LanceGlow",
				Shape = Enum.PartType.Cylinder,
				Color = CYAN,
				Transparency = 0.5,
				Size = Vector3.new((b - o).Magnitude, 3.2, 3.2),
				CFrame = beam.CFrame,
			})
			tween(beam, 0.3, { Size = Vector3.new(beam.Size.X, 0.05, 0.05) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(glow, 0.3, { Size = Vector3.new(glow.Size.X, 0.1, 0.1), Transparency = 1 })
			Debris:AddItem(beam, 0.32)
			Debris:AddItem(glow, 0.32)
			Fx.bolt(o, b, { color = YELLOW, width = 0.6, life = 0.3, forks = 5, jitter = 1.6 })
			word((o + b) / 2 + UP * 4, "¡KZZAK!", { color = YELLOW, size = 1.4 })
			for _, pt in pts do
				Fx.burst(pt, { color = YELLOW, count = 12, speed = 16, size = 0.5, life = 0.35, up = 4 })
				Fx.light(pt, { color = CYAN, range = 10, life = 0.2 })
			end
			for i = 1, #xa do
				if xb[i] then
					Fx.bolt(xa[i], xb[i], { color = CYAN, width = 0.25, life = 0.18 })
				end
			end
			react(pts, o, 0.3)
			loot(caster, pts, YELLOW)
			Fx.sound("zap", o, 0.7)
			if mine then
				Fx.shake(0.35 + 0.02 * #pts, 0.3)
				Fx.flash(WHITE, 0.25, 0.12)
			end
		end)
		return
	end

	local sa, sb, lv = list(p.sa), list(p.sb), (if type(p.lv) == "table" then p.lv else {})
	if #sa == 0 or (not mine and not seen(sa[1])) then
		return
	end
	local step = if mode == "fork" then 0.09 else 0.065
	-- Anticipación: un chispazo blanco en la boca antes del primer tramo
	Fx.light(sa[1], { color = CYAN, range = 9, life = 0.15 })
	Fx.burst(sa[1], { color = WHITE, count = 6, speed = 6, size = 0.35, life = 0.15 })
	if mine then
		Fx.sound("zap", sa[1], 1.3)
	end
	local lastLevel = 0
	for i = 1, #sa do
		local a, b = sa[i], sb[i]
		if not b then
			continue
		end
		local level = tonumber(lv[i]) or (i - 1)
		lastLevel = math.max(lastLevel, level)
		task.delay(0.06 + level * step, function()
			Fx.bolt(a, b, { color = YELLOW, width = 0.45, life = 0.22, forks = 2, jitter = 1.2 })
			Fx.burst(b, { color = CYAN, count = 10, speed = 14, size = 0.45, life = 0.3, up = 3 })
			Fx.light(b, { color = YELLOW, range = 9, life = 0.15 })
			react({ b }, a, 0.26)
			if mine then
				Fx.sound("zap", b, 1.1 + 0.08 * level)
			end
		end)
	end
	local finale = 0.06 + lastLevel * step + 0.05
	task.delay(finale, function()
		local last = sb[#sb] or sa[1]
		word(last + UP * 3, "¡ZAP!", { color = YELLOW, size = 1.3 })
		ring(last, 6, { color = CYAN, life = 0.35, thickness = 0.8 })
		for i = 1, #xa do
			if xb[i] then
				Fx.bolt(xa[i], xb[i], { color = CYAN, width = 0.25, life = 0.18 })
				Fx.burst(xb[i], { color = CYAN, count = 5, speed = 8, size = 0.35, life = 0.25 })
			end
		end
		loot(caster, pts, YELLOW)
		if mine then
			Fx.shake(math.min(0.2 + 0.03 * #pts, 0.55), 0.3)
			Fx.flash(YELLOW, 0.18, 0.1)
		end
	end)
end

-- Bobina: fija, orbital o pareja
function fx.volt2(caster: Player, p: any, mine: boolean)
	local pos = vec(p.pos)
	local life = tonumber(p.life) or 8
	local r = tonumber(p.r) or 22
	if not pos or type(p.id) ~= "string" then
		return
	end
	if not mine and not seen(pos) then
		return
	end
	if p.mode == "orbit" then
		plant(p.id, pos, life, r, caster, mine)
	elseif p.mode == "pair" then
		local pos2 = vec(p.pos2, pos) :: Vector3
		plant(p.id, pos, life, r, nil, mine)
		if type(p.id2) == "string" then
			task.delay(0.1, function()
				plant(p.id2, pos2, life, r, nil, false)
			end)
		end
	else
		plant(p.id, pos, life, r, nil, mine)
	end
end

-- Tanda de rayos de una bobina (res = resonancia por morder dentro)
function fx.volt2_zap(caster: Player, p: any, mine: boolean)
	local from = coilTop(p.id, vec(p.from, Vector3.zero) :: Vector3)
	if not mine and not seen(from) then
		return
	end
	local pts = list(p.pts)
	local res = p.res == true
	for _, pt in pts do
		Fx.bolt(from, pt, { color = if res then WHITE else YELLOW, width = if res then 0.45 else 0.32, life = 0.16, forks = if res then 2 else 1 })
		Fx.burst(pt, { color = CYAN, count = 7, speed = 10, size = 0.4, life = 0.28 })
	end
	local xa, xb = list(p.xa), list(p.xb)
	for i = 1, #xa do
		if xb[i] then
			Fx.bolt(xa[i], xb[i], { color = CYAN, width = 0.22, life = 0.15 })
		end
	end
	Fx.light(from, { color = CYAN, range = if res then 20 else 12, life = 0.15 })
	react(pts, from, 0.2)
	loot(caster, pts, YELLOW)
	if res then
		ring(from - UP * 5, 5, { color = WHITE, life = 0.3, thickness = 0.6 })
		word(from + UP * 2, "¡BZZT!", { color = CYAN, size = 0.9, life = 0.5 })
	end
	if mine then
		Fx.sound("zap", from, if res then 0.9 else rng:NextNumber(1.2, 1.5))
		if res then
			Fx.shake(0.15, 0.15)
		end
	end
end

-- El rayo que se pasan dos bobinas
function fx.volt2_link(caster: Player, p: any, mine: boolean)
	local a, b = vec(p.a), vec(p.b)
	if not a or not b or (not mine and not seen(a)) then
		return
	end
	Fx.bolt(a, b, { color = WHITE, width = 0.5, life = 0.2, forks = 2, jitter = 1.4 })
	Fx.bolt(a, b, { color = CYAN, width = 0.3, life = 0.25, jitter = 2 })
	local pts = list(p.pts)
	for _, pt in pts do
		Fx.burst(pt, { color = YELLOW, count = 8, speed = 12, size = 0.45, life = 0.3 })
	end
	react(pts, a, 0.2)
	loot(caster, pts, YELLOW)
end

-- Tormenta: nube oscura que sigue a la dueña (o se queda quieta) con el disco de alcance debajo
function fx.volt3(caster: Player, p: any, mine: boolean)
	local life = tonumber(p.life) or 8
	local r = tonumber(p.r) or 35
	local home = vec(p.c, Vector3.zero) :: Vector3
	if not mine and not seen(home) then
		return
	end
	local old = storms[caster]
	if old then
		old.model:Destroy()
	end
	local model, core = buildCloud()
	local disc = part({
		Name = "StormReach",
		Shape = Enum.PartType.Cylinder,
		Color = CYAN,
		Transparency = 0.9,
		Size = Vector3.new(0.12, r * 2, r * 2),
	})
	local fixed = p.fixed == true
	local function center(): Vector3
		if not fixed then
			local root = rootOf(caster)
			if root then
				return root.Position
			end
		end
		return home
	end
	local entry = { model = model, core = core, center = center }
	storms[caster] = entry
	model.Parent = Fx.folder()

	local started = os.clock()
	local height = 26
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			connection:Disconnect()
			disc:Destroy()
			return
		end
		local t = os.clock() - started
		local c = center()
		-- Aparece desde arriba y se queda flotando con un leve vaivén
		local rise = math.min(t / 0.35, 1)
		model:PivotTo(CFrame.new(c + UP * (height + (1 - rise) * 20 + math.sin(t * 2) * 0.6)) * CFrame.Angles(0, t * 0.4, 0))
		disc.CFrame = CFrame.new(Vector3.new(c.X, Config.GroundY + 0.06, c.Z)) * CFrame.Angles(0, 0, math.pi / 2)
		-- El corazón de la nube parpadea como relámpagos dentro
		core.Transparency = if rng:NextNumber() < 0.12 then 0.05 else 0.55
	end)

	word(home + UP * 8, "¡BRRROOM!", { color = YELLOW, size = 1.5 })
	Fx.sound("boom", home, 0.6)
	if mine then
		Fx.shake(0.35, 0.4)
		Fx.flash(STORM, 0.3, 0.25)
	end

	task.delay(life, function()
		if storms[caster] == entry then
			storms[caster] = nil
		end
		if not model.Parent then
			return
		end
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") then
				tween(child, 0.6, { Transparency = 1, Size = child.Size * 1.4 })
			end
		end
		tween(disc, 0.6, { Transparency = 1 })
		Debris:AddItem(model, 0.65)
	end)
end

-- Un rayo de la tormenta
function fx.volt3_hit(caster: Player, p: any, mine: boolean)
	local pos = vec(p.p)
	if not pos or (not mine and not seen(pos)) then
		return
	end
	local storm = storms[caster]
	local sky = if storm and storm.core.Parent then storm.core.Position else pos + UP * 26
	local big = p.big == true
	local pts = list(p.pts)
	Fx.bolt(sky, pos, { color = WHITE, width = if big then 0.9 else 0.65, life = 0.2, forks = 3, jitter = 2.2 })
	Fx.bolt(sky, pos, { color = YELLOW, width = 0.35, life = 0.25, forks = 1, jitter = 3 })
	ring(pos, if big then 9 else 4.5, { color = CYAN, life = 0.35, thickness = 0.8 })
	Fx.burst(pos, { color = YELLOW, count = if big then 22 else 10, speed = if big then 22 else 14, size = 0.55, life = 0.4, up = 8 })
	Fx.light(pos, { color = WHITE, range = if big then 22 else 14, life = 0.18 })
	if big then
		Fx.pillar(pos, { color = YELLOW, height = 10, width = 3, life = 0.25 })
		word(pos + UP * 4, "¡KRAK!", { color = YELLOW, size = 1.2 })
	elseif rng:NextNumber() < 0.25 then
		word(pos + UP * 3, "¡ZAP!", { color = YELLOW, size = 0.8, life = 0.5 })
	end
	local xa, xb = list(p.xa), list(p.xb)
	for i = 1, #xa do
		if xb[i] then
			task.delay(0.05 + i * 0.03, function()
				Fx.bolt(xa[i], xb[i], { color = CYAN, width = 0.3, life = 0.18, forks = 1 })
				Fx.burst(xb[i], { color = YELLOW, count = 6, speed = 10, size = 0.4, life = 0.25 })
			end)
		end
	end
	react(pts, sky, if big then 0.32 else 0.22)
	loot(caster, pts, YELLOW)
	Fx.sound("zap", pos, rng:NextNumber(0.7, 1))
	if mine then
		Fx.shake(if big then 0.28 else 0.12, 0.18)
	end
end

----------------------------------------------------------------------------------------------------
-- Aura: bolas de energía en las antenas que se pasan chispas, y chispas en el abdomen

local function weld(host: BasePart, folder: Instance, props: { [string]: any }, offset: CFrame): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	if props.Shape then
		p.Shape = props.Shape -- antes que Size: una bola fuerza tamaño uniforme
	end
	for key, value in props do
		(p :: any)[key] = value
	end
	p.CFrame = host.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = host
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = folder
	return p
end

local function aura(character: Model, rank: number, mastered: boolean): () -> ()
	local folder = Instance.new("Folder")
	folder.Name = "VoltAura"
	folder.Parent = Fx.folder()
	local scale = character:GetScale()
	local grow = 1 + (math.clamp(rank, 1, 10) - 1) * 0.05
	local main = if mastered then GOLD else YELLOW
	local alive = true

	local tips = {}
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name == "AntennaTip" then
			local orb = weld(child, folder, {
				Name = "VoltOrb",
				Shape = Enum.PartType.Ball,
				Color = main,
				Size = Vector3.one * 0.55 * scale * grow,
			}, CFrame.new())
			local light = Instance.new("PointLight")
			light.Color = CYAN
			light.Range = 5 * grow
			light.Brightness = 1.4
			light.Shadows = false
			light.Parent = orb
			table.insert(tips, orb)
		end
	end

	local abdomen = character:FindFirstChild("Abdomen")
	if abdomen and abdomen:IsA("BasePart") then
		local anchor = weld(abdomen, folder, {
			Name = "VoltSparks",
			Transparency = 1,
			Size = Vector3.one * 0.2,
		}, CFrame.new(0, 0.5 * scale, 0))
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(if mastered then GOLD else WHITE, CYAN)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.3 * scale, 0)
		sparks.Lifetime = NumberRange.new(0.15, 0.35)
		sparks.Speed = NumberRange.new(3, 7)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Rate = 4 + rank * 1.5
		sparks.Parent = anchor
		-- Una franja en zigzag en el lomo: el rayo de la casta
		for i, x in { -0.35, 0, 0.35 } do
			weld(abdomen, folder, {
				Name = "VoltStripe",
				Color = if i == 2 then CYAN else main,
				Size = Vector3.new(0.18, 0.12, 0.62) * scale,
			}, CFrame.new(x * scale, 0.86 * scale, (i - 2) * 0.32 * scale) * CFrame.Angles(0, math.rad(if i == 2 then -40 else 40), 0))
		end
	end

	-- Chispas sueltas entre las antenas, más a menudo cuanto más rango
	task.spawn(function()
		while alive do
			task.wait(rng:NextNumber(0.5, 1.6) / grow)
			if not alive or not folder.Parent then
				break
			end
			if #tips >= 2 and tips[1].Parent and seen(tips[1].Position) then
				Fx.bolt(tips[1].Position, tips[2].Position, { color = CYAN, width = 0.08, life = 0.08, jitter = 0.3 })
			end
		end
	end)

	local gone = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			alive = false
			folder:Destroy()
		end
	end)
	return function()
		alive = false
		gone:Disconnect()
		folder:Destroy()
	end
end

----------------------------------------------------------------------------------------------------
-- Emblema: un rayo en zigzag sobre un disco cian

local function emblem(parent: GuiObject, color: Color3)
	local disc = Instance.new("Frame")
	disc.Name = "VoltEmblem"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.86, 0.86)
	disc.BackgroundColor3 = CYAN
	disc.BorderSizePixel = 0
	disc.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Parent = disc

	local function bar(size: UDim2, pos: UDim2, rotation: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = size
		f.Position = pos
		f.Rotation = rotation
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Parent = disc
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.25, 0)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Color = INK
		s.Thickness = 2.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
		return f
	end
	bar(UDim2.fromScale(0.17, 0.42), UDim2.fromScale(0.56, 0.3), 28)
	bar(UDim2.fromScale(0.42, 0.14), UDim2.fromScale(0.5, 0.5), -12)
	bar(UDim2.fromScale(0.17, 0.42), UDim2.fromScale(0.44, 0.7), 28)
end

return {
	fx = fx,
	aura = aura,
	emblem = emblem,
}
