-- Primitivas de efectos para las castas (src/client/Castes/<id>.luau): rayos quebrados con núcleo
-- blanco y halo de color, ondas en el suelo con borde de tinta, estallidos, columnas, charcos que
-- burbujean, cúpulas, proyectiles en arco, frentes que avanzan, botín que vuela al hormiguero,
-- estelas de siluetas, onomatopeyas de cómic, destellos y sonidos sintetizados con los que ya hay.
-- Todo vive en la carpeta Workspace.CasteFx (local) y se limpia solo. Topes globales de piezas, luces
-- y sonidos: con seis jugadoras lanzando a la vez, lo que sobra se simplifica o se salta.
--
-- Firmas (contrato de las castas):
--   bolt(a, b, opts?)  opts: color, width, life, forks, jitter
--   chain(points, opts?)  (además: step = segundos entre tramos)
--   ring(pos, radius, opts?)  opts: color, life, thickness
--   burst(pos, opts?)  opts: color, count, speed, size, life, up
--   pillar(pos, opts?)  opts: color, height, width, life
--   puddle(pos, radius, life, opts?): Model   opts: color
--   dome(pos, radius, life, opts?): Model     opts: color
--   lob(a, b, opts?)  opts: color, size, time, height, land
--   wave(a, b, width, opts?)  opts: color, time, height
--   orbs(from, to, opts?)  opts: color, time, perPoint
--   ghosts(character, life, opts?)  opts: color
--   word(pos, text, opts?)  opts: color, size, life
--   light(pos, opts?)  opts: color, range, life
--   shake(amount, time) / flash(color, alpha, time)   solo para la dueña
--   sound(kind, pos?, pitch?)  "zap","boom","whoosh","splash","slash","thud","chime","pop"
--   part(props): Part / folder(): Folder / hillOf(player): Vector3?

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Comic = require(script.Parent.Comic)
local GameFx = require(script.Parent.Fx)
local Sfx = require(script.Parent.Sfx)

local CasteFx = {}

local rng = Random.new()
local WHITE = Color3.new(1, 1, 1)
local INK = Comic.Ink
local UP = Vector3.new(0, 1, 0)
local FLAT = Vector3.new(1, 0, 1)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local MAX_PARTS = 700 -- piezas de efecto vivas a la vez; por encima, lo accesorio se salta
local MAX_LIGHTS = 10
local SEEN = 320 -- más lejos de la cámara no se dibuja nada
local RING_PPS = 24 -- píxeles por stud de los aros del suelo

local folder: Folder? = nil
local liveParts = 0
local liveLights = 0

-- Lo pone CasteClient mientras despacha un efecto ajeno: ni sacudidas ni destellos de pantalla
CasteFx._quiet = false

---------------------------------------------------------------------------------------------------
-- Ayudas

local function num(value: any, default: number): number
	return if type(value) == "number" and value == value then value else default
end

local function color(value: any, default: Color3): Color3
	return if typeof(value) == "Color3" then value else default
end

local function tween(object: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?)
	local info = TweenInfo.new(math.max(time, 0.01), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0)
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end

local function cameraPos(): Vector3?
	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.Position
end

local function near(pos: Vector3, limit: number?): boolean
	local cam = cameraPos()
	return cam == nil or (cam - pos).Magnitude <= (limit or SEEN)
end

local function busy(): boolean
	return liveParts > MAX_PARTS
end

function CasteFx.folder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = "CasteFx"
	-- Cuenta de piezas vivas (también las de modelos que cuelgan de aquí)
	liveParts = 0
	created.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			liveParts += 1
		end
	end)
	created.DescendantRemoving:Connect(function(d)
		if d:IsA("BasePart") then
			liveParts = math.max(0, liveParts - 1)
		end
	end)
	created.Parent = Workspace
	folder = created
	return created
end

-- Pieza suelta sin colisión, anclada, en la carpeta de efectos. Shape y Size se aplican antes que
-- el resto y CFrame / Position al final.
function CasteFx.part(props: any): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(1, 1, 1)
	local parent: Instance? = nil
	if type(props) == "table" then
		if props.Shape ~= nil then
			pcall(function()
				p.Shape = props.Shape
			end)
		end
		if props.Size ~= nil then
			pcall(function()
				p.Size = props.Size
			end)
		end
		for key, value in props do
			if key == "Parent" then
				parent = value
			elseif key ~= "Shape" and key ~= "Size" and key ~= "CFrame" and key ~= "Position" then
				local ok, err = pcall(function()
					(p :: any)[key] = value
				end)
				if not ok then
					warn("[CRUNCH!] CasteFx.part:", key, err)
				end
			end
		end
		if props.CFrame ~= nil then
			p.CFrame = props.CFrame
		elseif props.Position ~= nil then
			p.Position = props.Position
		end
	end
	p.Parent = parent or CasteFx.folder()
	return p
end

local function life(instance: Instance, seconds: number)
	Debris:AddItem(instance, seconds)
end

-- Cilindro de a a b (el eje del cilindro es X)
local function rod(a: Vector3, b: Vector3, width: number, tint: Color3, neon: boolean, alpha: number, parent: Instance?): Part?
	local length = (b - a).Magnitude
	if length < 0.05 then
		return nil
	end
	return CasteFx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length + width * 0.4, width, width),
		CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0),
		Color = tint,
		Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		Transparency = alpha,
		Parent = parent,
	})
end

-- Disco plano (cilindro tumbado) centrado en pos
local function disc(pos: Vector3, diameter: number, thick: number, tint: Color3, props: any?): Part
	local base = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thick, diameter, diameter),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		Color = tint,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return CasteFx.part(base)
end

local function anchorPart(pos: Vector3, seconds: number): Part
	local p = CasteFx.part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, Position = pos })
	life(p, seconds)
	return p
end

---------------------------------------------------------------------------------------------------
-- Aro en el suelo con borde de tinta (SurfaceGui sobre una pieza plana e invisible). Lo usan ring,
-- dome y los indicadores de apuntado de CasteClient. `fill` es la transparencia del relleno (1 = hueco).

export type GroundRing = {
	part: Part,
	ink: UIStroke,
	stroke: UIStroke,
	face: Frame,
	setRadius: (radius: number) -> (),
	setColor: (tint: Color3) -> (),
	destroy: () -> (),
}

function CasteFx.groundRing(pos: Vector3, radius: number, tint: Color3, thickness: number?, fill: number?): GroundRing
	local thick = math.max(num(thickness, 0.5), 0.08)
	local d = math.max(radius * 2, 0.2)
	local part = CasteFx.part({
		Size = Vector3.new(d, 0.05, d),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.14, 0)),
		Transparency = 1,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = RING_PPS
	gui.LightInfluence = 0
	gui.MaxDistance = SEEN
	gui.ZOffset = 1
	gui.Parent = part

	local back = Instance.new("Frame")
	back.BackgroundTransparency = 1
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui
	Comic.round(back)
	local ink = Instance.new("UIStroke")
	ink.Color = INK
	ink.Thickness = thick * RING_PPS * 1.7
	ink.Parent = back

	local face = Instance.new("Frame")
	face.BackgroundColor3 = tint
	face.BackgroundTransparency = num(fill, 1)
	face.Size = UDim2.fromScale(1, 1)
	face.Parent = gui
	Comic.round(face)
	local stroke = Instance.new("UIStroke")
	stroke.Color = tint
	stroke.Thickness = thick * RING_PPS
	stroke.Parent = face

	local ring = {
		part = part,
		ink = ink,
		stroke = stroke,
		face = face,
	} :: any
	function ring.setRadius(r: number)
		local size = math.max(r * 2, 0.2)
		part.Size = Vector3.new(size, 0.05, size)
	end
	function ring.setColor(c: Color3)
		stroke.Color = c
		face.BackgroundColor3 = c
	end
	function ring.destroy()
		part:Destroy()
	end
	return ring
end

---------------------------------------------------------------------------------------------------
-- Luces y sonidos

function CasteFx.light(pos: Vector3, opts: any?)
	opts = opts or {}
	if typeof(pos) ~= "Vector3" or liveLights >= MAX_LIGHTS or not near(pos, 200) then
		return
	end
	local seconds = num(opts.life, 0.25)
	local anchor = anchorPart(pos, seconds + 0.1)
	local light = Instance.new("PointLight")
	light.Color = color(opts.color, Comic.Yellow)
	light.Range = math.clamp(num(opts.range, 14), 2, 60)
	light.Brightness = num(opts.brightness, 3)
	light.Shadows = false
	light.Parent = anchor
	liveLights += 1
	anchor.Destroying:Once(function()
		liveLights -= 1
	end)
	tween(light, seconds, { Brightness = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
end

local templates: { [string]: Sound } = {}
local soundTimes: { number } = {}

local function template(kind: string): Sound
	local hit = templates[kind]
	if hit then
		return hit
	end
	local sound = Instance.new("Sound")
	if kind == "pop" then
		sound.SoundId = Assets.Sounds.Pop
	else
		local list = Assets.Sounds.Bite
		sound.SoundId = list[if kind == "bite2" then math.min(2, #list) else 1]
	end
	sound.Volume = 0.5
	templates[kind] = sound
	return sound
end

local function effect(sound: Sound, name: string)
	if name == "distort" then
		local d = Instance.new("DistortionSoundEffect")
		d.Level = 0.65
		d.Parent = sound
	elseif name == "boom" then
		local d = Instance.new("DistortionSoundEffect")
		d.Level = 0.45
		d.Parent = sound
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 8
		eq.MidGain = 0
		eq.HighGain = -12
		eq.Parent = sound
	elseif name == "dull" then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 6
		eq.MidGain = -2
		eq.HighGain = -24
		eq.Parent = sound
	elseif name == "bright" then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = -18
		eq.MidGain = 0
		eq.HighGain = 6
		eq.Parent = sound
	elseif name == "flange" then
		local f = Instance.new("FlangeSoundEffect")
		f.Depth = 0.7
		f.Rate = 3
		f.Mix = 0.8
		f.Parent = sound
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = -6
		eq.MidGain = -4
		eq.HighGain = 2
		eq.Parent = sound
	elseif name == "echo" then
		local e = Instance.new("EchoSoundEffect")
		e.Delay = 0.11
		e.Feedback = 0.35
		e.WetLevel = -4
		e.Parent = sound
	end
end

-- Cada tipo de sonido se sintetiza con los dos mordiscos y el pop del juego, variando tono y efecto
local RECIPES = {
	zap = { { "pop", 2.5, 0.45, 0, "distort" }, { "pop", 3.2, 0.35, 0.045, "distort" }, { "pop", 2.8, 0.25, 0.09, "distort" } },
	boom = { { "bite", 0.4, 0.9, 0, "boom" }, { "bite2", 0.5, 0.6, 0.03, "dull" }, { "pop", 0.45, 0.5, 0.01, "boom" } },
	whoosh = { { "pop", 0.5, 0.5, 0, "flange" }, { "pop", 0.62, 0.3, 0.06, "flange" } },
	splash = { { "bite", 1.7, 0.45, 0 }, { "bite2", 2.15, 0.35, 0.05 }, { "pop", 1.35, 0.35, 0.1 } },
	slash = { { "bite", 1.95, 0.55, 0, "bright" }, { "pop", 2.7, 0.25, 0.025, "bright" } },
	thud = { { "bite", 0.55, 0.8, 0, "dull" }, { "bite2", 0.48, 0.5, 0.02, "dull" } },
	chime = { { "pop", 1.8, 0.4, 0 }, { "pop", 2.4, 0.35, 0.08 }, { "pop", 3.0, 0.3, 0.16, "echo" } },
	pop = { { "pop", 1, 0.5, 0 } },
}

function CasteFx.sound(kind: string, pos: Vector3?, pitch: number?)
	local recipe = RECIPES[kind] or RECIPES.pop
	local clock = os.clock()
	for i = #soundTimes, 1, -1 do
		if clock - soundTimes[i] > 0.3 then
			table.remove(soundTimes, i)
		end
	end
	if #soundTimes >= 14 then
		return
	end
	table.insert(soundTimes, clock)
	if typeof(pos) == "Vector3" and not near(pos, 160) then
		return
	end
	local scale = num(pitch, 1) * rng:NextNumber(0.95, 1.05)
	for _, layer in recipe do
		task.delay(layer[4], function()
			local sound = template(layer[1]):Clone()
			sound.PlaybackSpeed = layer[2] * scale
			sound.Volume = layer[3]
			if layer[5] then
				effect(sound, layer[5])
			end
			-- Sale por Sfx: mismo límite de voces, grupo "Efectos" y 3D con la misma atenuación
			Sfx.emit(sound, if typeof(pos) == "Vector3" then pos else nil)
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Rayos

-- Rayo quebrado: tinta detrás (algo desplazada, como tinta mal registrada), halo de color y núcleo
-- blanco; ramas finas que salen de los quiebros.
function CasteFx.bolt(a: Vector3, b: Vector3, opts: any?)
	opts = opts or {}
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return
	end
	if not near(a) and not near(b) then
		return
	end
	local dir = b - a
	local length = dir.Magnitude
	if length < 0.1 then
		return
	end
	local tint = color(opts.color, Comic.Yellow)
	local width = math.clamp(num(opts.width, 0.32), 0.05, 3)
	local seconds = num(opts.life, 0.22)
	local forks = math.clamp(math.floor(num(opts.forks, 2)), 0, 6)
	local jitter = num(opts.jitter, math.clamp(length * 0.09, 0.4, 2.4))
	local lite = busy()
	local side = dir:Cross(UP)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	local lift = side:Cross(dir.Unit)

	local count = math.clamp(math.floor(length / 3.2), 3, 10)
	local points = { a }
	for i = 1, count - 1 do
		local t = i / count
		local envelope = math.sin(math.pi * t) * 0.65 + 0.35
		table.insert(points, a + dir * t + side * rng:NextNumber(-1, 1) * jitter * envelope + lift * rng:NextNumber(-0.6, 0.6) * jitter * envelope)
	end
	table.insert(points, b)

	local cam = cameraPos() or (a - dir)
	local parts = {}
	local function segment(p: Vector3, q: Vector3, w: number, ink: boolean)
		if ink and not lite then
			local away = ((p + q) / 2 - cam)
			away = if away.Magnitude > 0.01 then away.Unit * w * 1.1 else Vector3.zero
			local back = rod(p + away, q + away, w * 3, INK, false, 0.05)
			if back then
				table.insert(parts, back)
			end
		end
		local halo = rod(p, q, w * 2.3, tint, true, 0.3)
		local core = rod(p, q, w, WHITE, true, 0)
		if halo then
			table.insert(parts, halo)
		end
		if core then
			table.insert(parts, core)
		end
	end

	for i = 1, #points - 1 do
		segment(points[i], points[i + 1], width, true)
	end
	-- Ramas: salen de un quiebro, se abren hacia un lado y se apagan antes
	if not lite then
		for _ = 1, forks do
			local k = rng:NextInteger(2, math.max(2, #points - 1))
			local from = points[k]
			local angle = math.rad(rng:NextNumber(25, 60)) * (if rng:NextNumber() < 0.5 then -1 else 1)
			local branchDir = CFrame.fromAxisAngle(UP, angle):VectorToWorldSpace(dir.Unit) + UP * rng:NextNumber(-0.3, 0.35)
			local branchLen = length * rng:NextNumber(0.16, 0.3)
			local prev = from
			for j = 1, 3 do
				local nextPoint = from + branchDir.Unit * branchLen * (j / 3) + side * rng:NextNumber(-0.5, 0.5) * jitter * 0.5
				segment(prev, nextPoint, width * 0.55, false)
				prev = nextPoint
			end
		end
	end

	for _, p in parts do
		tween(p, seconds * 0.55, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, seconds * 0.45)
		life(p, seconds + 0.05)
	end
	if opts.light ~= false then
		CasteFx.light((a + b) / 2, { color = tint, range = math.clamp(length * 0.7, 8, 26), life = seconds })
	end
end

function CasteFx.chain(points: { Vector3 }, opts: any?)
	opts = opts or {}
	if type(points) ~= "table" or #points < 2 then
		return
	end
	local step = num(opts.step, 0.06)
	local tint = color(opts.color, Comic.Yellow)
	for i = 1, #points - 1 do
		task.delay((i - 1) * step, function()
			local from, to = points[i], points[i + 1]
			if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
				return
			end
			CasteFx.bolt(from, to, opts)
			if opts.sparks ~= false and not busy() then
				CasteFx.burst(to, { color = tint, count = 6, speed = 12, size = 0.4, life = 0.35 })
			end
		end)
	end
end

---------------------------------------------------------------------------------------------------
-- Suelo: ondas, charcos, cúpulas

function CasteFx.ring(pos: Vector3, radius: number, opts: any?)
	opts = opts or {}
	if typeof(pos) ~= "Vector3" or not near(pos) then
		return
	end
	local tint = color(opts.color, Comic.Yellow)
	local seconds = num(opts.life, 0.45)
	local r = math.max(num(radius, 6), 0.5)
	local ring = CasteFx.groundRing(pos, 0.3, tint, num(opts.thickness, math.clamp(r * 0.06, 0.25, 1.2)), 0.82)
	life(ring.part, seconds + 0.1)
	tween(ring.part, seconds, { Size = Vector3.new(r * 2, 0.05, r * 2) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local fadeTime = seconds * 0.45
	tween(ring.stroke, fadeTime, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, seconds - fadeTime)
	tween(ring.ink, fadeTime, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, seconds - fadeTime)
	tween(ring.face, seconds * 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	return ring.part
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(WHITE, k)
end

function CasteFx.puddle(pos: Vector3, radius: number, seconds: number, opts: any?): Model
	opts = opts or {}
	local tint = color(opts.color, Comic.Green)
	local r = math.max(num(radius, 4), 0.5)
	local lifeTime = math.max(num(seconds, 3), 0.2)
	local model = Instance.new("Model")
	model.Name = "CastePuddle"
	local base = if typeof(pos) == "Vector3" then pos else Vector3.zero

	local rim = disc(base + Vector3.new(0, 0.05, 0), 0.2, 0.08, INK, { Parent = model })
	local liquid = disc(base + Vector3.new(0, 0.09, 0), 0.2, 0.1, tint, { Parent = model, Reflectance = 0.15 })
	local shine = disc(base + Vector3.new(r * 0.18, 0.12, -r * 0.18), 0.2, 0.06, lighter(tint, 0.35), {
		Parent = model,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	})
	model.PrimaryPart = liquid
	model.Parent = CasteFx.folder()
	life(model, lifeTime + 1)

	local grow = 0.28
	tween(rim, grow, { Size = Vector3.new(0.08, r * 2 + 0.7, r * 2 + 0.7) }, Enum.EasingStyle.Back)
	tween(liquid, grow, { Size = Vector3.new(0.1, r * 2, r * 2) }, Enum.EasingStyle.Back)
	tween(shine, grow, { Size = Vector3.new(0.06, r * 0.9, r * 0.9) }, Enum.EasingStyle.Back)

	-- Burbujas: crecen y revientan (como mucho unas pocas vivas por charco)
	local alive = 0
	local maxBubbles = math.clamp(math.floor(r * 1.5), 3, 9)
	task.spawn(function()
		local started = os.clock()
		while model.Parent and os.clock() - started < lifeTime - 0.2 do
			task.wait(rng:NextNumber(0.1, 0.25) * math.clamp(5 / r, 0.4, 1.4))
			if not model.Parent or alive >= maxBubbles or busy() then
				continue
			end
			local center = model:GetPivot().Position
			if not near(center, 180) then
				continue
			end
			local angle = rng:NextNumber(0, math.pi * 2)
			local dist = math.sqrt(rng:NextNumber()) * r * 0.82
			local at = center + Vector3.new(math.cos(angle) * dist, 0.15, math.sin(angle) * dist)
			local size = rng:NextNumber(0.35, 0.9) * math.clamp(r / 4, 0.6, 1.6)
			local bubble = CasteFx.part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.1, 0.1, 0.1),
				Position = at,
				Color = lighter(tint, 0.3),
				Transparency = 0.15,
				Reflectance = 0.2,
				Parent = model,
			})
			alive += 1
			local riseTime = rng:NextNumber(0.3, 0.6)
			tween(bubble, riseTime, { Size = Vector3.new(size, size, size), Position = at + Vector3.new(0, size * 0.35, 0) }, Enum.EasingStyle.Sine)
			task.delay(riseTime, function()
				if bubble.Parent then
					tween(bubble, 0.08, { Size = Vector3.new(size * 1.4, size * 1.4, size * 1.4), Transparency = 1 })
					if rng:NextNumber() < 0.35 then
						CasteFx.burst(bubble.Position, { color = lighter(tint, 0.4), count = 3, speed = 6, size = 0.25, life = 0.3, up = true })
					end
				end
				task.delay(0.1, function()
					alive -= 1
					bubble:Destroy()
				end)
			end)
		end
	end)

	task.delay(lifeTime, function()
		if not model.Parent then
			return
		end
		for _, p in { rim, liquid, shine } do
			if p.Parent then
				tween(p, 0.3, { Size = Vector3.new(p.Size.X, 0.1, 0.1), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
		task.delay(0.32, function()
			model:Destroy()
		end)
	end)
	return model
end

function CasteFx.dome(pos: Vector3, radius: number, seconds: number, opts: any?): Model
	opts = opts or {}
	local tint = color(opts.color, Comic.Cyan)
	local r = math.max(num(radius, 6), 0.5)
	local lifeTime = math.max(num(seconds, 3), 0.2)
	local base = if typeof(pos) == "Vector3" then pos else Vector3.zero
	local model = Instance.new("Model")
	model.Name = "CasteDome"

	local shell = CasteFx.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = base,
		Color = tint,
		Material = Enum.Material.ForceField,
		Transparency = 0,
		Parent = model,
	})
	local body = CasteFx.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = base,
		Color = lighter(tint, 0.2),
		Material = Enum.Material.Glass,
		Transparency = 0.86,
		Parent = model,
	})
	model.PrimaryPart = shell
	local ring = CasteFx.groundRing(base, r, tint, math.clamp(r * 0.05, 0.25, 0.9), 0.9)
	ring.part.Parent = model
	model.Parent = CasteFx.folder()
	life(model, lifeTime + 1)

	local full = Vector3.new(r * 2, r * 2, r * 2)
	tween(shell, 0.3, { Size = full }, Enum.EasingStyle.Back)
	tween(body, 0.3, { Size = full * 0.98 }, Enum.EasingStyle.Back)
	CasteFx.ring(base, r * 1.15, { color = tint, life = 0.4 })

	task.delay(lifeTime, function()
		if not model.Parent then
			return
		end
		tween(shell, 0.25, { Size = full * 1.08, Transparency = 1 })
		tween(body, 0.25, { Size = full * 1.08, Transparency = 1 })
		tween(ring.stroke, 0.25, { Transparency = 1 })
		tween(ring.ink, 0.25, { Transparency = 1 })
		task.delay(0.27, function()
			model:Destroy()
		end)
	end)
	return model
end

---------------------------------------------------------------------------------------------------
-- Estallidos y columnas

function CasteFx.burst(pos: Vector3, opts: any?)
	opts = opts or {}
	if typeof(pos) ~= "Vector3" or not near(pos, 240) then
		return
	end
	local tint = color(opts.color, Comic.Yellow)
	local count = math.clamp(math.floor(num(opts.count, 14)), 1, 40)
	if busy() then
		count = math.max(1, count // 3)
	end
	local speed = num(opts.speed, 18)
	local size = num(opts.size, 0.55)
	local seconds = num(opts.life, 0.55)
	local anchor = anchorPart(pos, seconds + 0.3)
	local point = Instance.new("Attachment")
	point.Parent = anchor

	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(lighter(tint, 0.25), tint)
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(0.6, size * 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(seconds * 0.6, seconds)
	e.Speed = NumberRange.new(speed * 0.55, speed)
	e.SpreadAngle = if opts.up then Vector2.new(35, 35) else Vector2.new(180, 180)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, if opts.up then -25 else -40, 0)
	e.Drag = 3
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Rate = 0
	e.Parent = point
	e:Emit(count)

	-- Destello blanco en el centro
	local flash = Instance.new("ParticleEmitter")
	flash.Texture = SPARK
	flash.Color = ColorSequence.new(WHITE)
	flash.LightEmission = 1
	flash.LightInfluence = 0
	flash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 3.5), NumberSequenceKeypoint.new(1, 0) })
	flash.Transparency = NumberSequence.new(0.1, 1)
	flash.Lifetime = NumberRange.new(0.16)
	flash.Speed = NumberRange.new(0)
	flash.Rate = 0
	flash.Parent = point
	flash:Emit(1)
end

function CasteFx.pillar(pos: Vector3, opts: any?)
	opts = opts or {}
	if typeof(pos) ~= "Vector3" or not near(pos) then
		return
	end
	local tint = color(opts.color, Comic.Yellow)
	local height = math.max(num(opts.height, 14), 0.5)
	local width = math.max(num(opts.width, 3), 0.2)
	local seconds = num(opts.life, 0.6)
	local center = CFrame.new(pos + UP * (height / 2)) * CFrame.Angles(0, 0, math.pi / 2)
	local outer = CasteFx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width * 0.2, width * 0.2),
		CFrame = center,
		Color = tint,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	local core = CasteFx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, width * 0.1, width * 0.1),
		CFrame = center,
		Color = WHITE,
		Material = Enum.Material.Neon,
		Transparency = 0,
	})
	life(outer, seconds + 0.1)
	life(core, seconds + 0.1)
	local pop = math.min(0.09, seconds * 0.25)
	tween(outer, pop, { Size = Vector3.new(height, width, width) }, Enum.EasingStyle.Back)
	tween(core, pop, { Size = Vector3.new(height, width * 0.4, width * 0.4) }, Enum.EasingStyle.Back)
	tween(outer, seconds - pop, { Size = Vector3.new(height * 1.05, 0.05, 0.05), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, pop)
	tween(core, seconds - pop, { Size = Vector3.new(height * 1.05, 0.03, 0.03), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, pop)
	CasteFx.ring(pos, width * 1.7, { color = tint, life = seconds * 0.8 })
	CasteFx.light(pos + UP * (height * 0.4), { color = tint, range = math.clamp(height, 10, 30), life = seconds })
end

---------------------------------------------------------------------------------------------------
-- Cosas que se mueven: proyectil en arco, frente que avanza, botín al hormiguero

local function bezier(a: Vector3, c: Vector3, b: Vector3, t: number): Vector3
	local u = 1 - t
	return a * (u * u) + c * (2 * u * t) + b * (t * t)
end

local function addTrail(part: BasePart, tint: Color3, half: number, seconds: number, width: number?)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, half, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -half, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(lighter(tint, 0.3), tint)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.WidthScale = NumberSequence.new(1, width or 0.2)
	trail.Lifetime = seconds
	trail.LightEmission = 0.6
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.MinLength = 0.05
	trail.Parent = part
	return trail
end

function CasteFx.lob(a: Vector3, b: Vector3, opts: any?)
	opts = opts or {}
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return
	end
	local land = opts.land
	if not near(a) and not near(b) then
		-- Lejos no se dibuja, pero quien lo pidió puede contar con su aterrizaje
		if type(land) == "function" then
			task.delay(num(opts.time, 0.6), function()
				pcall(land)
			end)
		end
		return
	end
	local tint = color(opts.color, Comic.Green)
	local size = math.max(num(opts.size, 1.1), 0.1)
	local seconds = math.max(num(opts.time, 0.6), 0.05)
	local distance = ((b - a) * FLAT).Magnitude
	local height = num(opts.height, math.max(4, distance * 0.35))
	local control = (a + b) / 2 + UP * (height * 2)

	local ball = CasteFx.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Position = a,
		Color = tint,
		Material = Enum.Material.Neon,
	})
	local ink = CasteFx.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size * 1.3, size * 1.3, size * 1.3),
		Position = a,
		Color = INK,
	})
	addTrail(ball, tint, size * 0.4, 0.25)
	life(ball, seconds + 1)
	life(ink, seconds + 1)

	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - started) / seconds, 1)
		local pos = bezier(a, control, b, t)
		local cam = cameraPos()
		local away = if cam and (pos - cam).Magnitude > 0.1 then (pos - cam).Unit * size * 0.25 else Vector3.zero
		ball.CFrame = CFrame.new(pos) * CFrame.Angles(t * 9, t * 5, 0)
		ink.CFrame = CFrame.new(pos + away)
		if t >= 1 then
			connection:Disconnect()
			ball:Destroy()
			ink:Destroy()
			CasteFx.burst(b, { color = tint, count = 8, speed = 14, size = 0.45, life = 0.4, up = true })
			if type(land) == "function" then
				task.spawn(function()
					local ok, err = pcall(land)
					if not ok then
						warn("[CRUNCH!] CasteFx.lob land:", err)
					end
				end)
			end
		end
	end)
end

function CasteFx.wave(a: Vector3, b: Vector3, width: number, opts: any?)
	opts = opts or {}
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" or (not near(a) and not near(b)) then
		return
	end
	local tint = color(opts.color, Comic.Cyan)
	local seconds = math.max(num(opts.time, 0.5), 0.05)
	local height = math.max(num(opts.height, 2.5), 0.3)
	local w = math.max(num(width, 6), 0.5)
	local travel = (b - a) * FLAT
	local dir = if travel.Magnitude > 0.01 then travel.Unit else Vector3.new(0, 0, -1)
	local side = dir:Cross(UP).Unit

	-- Tubo que rueda: el eje del cilindro (X) va de lado a lado del frente
	local function frameAt(pos: Vector3, spin: number): CFrame
		return CFrame.fromMatrix(pos, side, UP) * CFrame.Angles(spin, 0, 0)
	end
	local tube = CasteFx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(w, height, height),
		CFrame = frameAt(a + UP * height / 2, 0),
		Color = tint,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	local lip = CasteFx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(w * 0.96, height * 0.45, height * 0.45),
		CFrame = frameAt(a + UP * height / 2, 0),
		Color = WHITE,
		Material = Enum.Material.Neon,
	})
	local ink = CasteFx.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(w * 1.02, height * 1.15, height * 1.15),
		CFrame = frameAt(a + UP * height / 2, 0),
		Color = INK,
	})
	for _, x in { -w / 2, w / 2 } do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(x, -height * 0.45, 0)
		a0.Parent = tube
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(x, height * 0.2, 0)
		a1.Parent = tube
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(tint)
		trail.Transparency = NumberSequence.new(0.3, 1)
		trail.Lifetime = 0.35
		trail.LightEmission = 0.5
		trail.Parent = tube
	end
	for _, p in { tube, lip, ink } do
		life(p, seconds + 0.5)
	end

	local started = os.clock()
	local lastDust = 0
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.min((os.clock() - started) / seconds, 1)
		local eased = 1 - (1 - t) * (1 - t)
		local pos = a:Lerp(b, eased) + UP * height / 2
		local spin = -t * 14
		tube.CFrame = frameAt(pos, spin)
		lip.CFrame = frameAt(pos + dir * height * 0.22, spin)
		ink.CFrame = frameAt(pos - dir * height * 0.18, 0)
		if t - lastDust > 0.18 then
			lastDust = t
			CasteFx.burst(pos - UP * height * 0.4, { color = Comic.DirtLight, count = 4, speed = 8, size = 0.5, life = 0.35, up = true })
		end
		if t >= 1 then
			connection:Disconnect()
			for _, p in { tube, lip, ink } do
				tween(p, 0.15, { Transparency = 1 })
			end
		end
	end)
end

-- Botín que vuela al hormiguero: bolitas con estela, cada una en su arco; al llegar, un tintineo
local orbList: { any } = {}
local orbConnection: RBXScriptConnection? = nil

local function stepOrbs()
	local clock = os.clock()
	for i = #orbList, 1, -1 do
		local o = orbList[i]
		local t = (clock - o.start) / o.time
		if t < 0 then
			continue
		end
		if not o.shown then
			o.shown = true
			o.part.Transparency = 0
		end
		if t >= 1 or not o.part.Parent then
			table.remove(orbList, i)
			o.part:Destroy()
			if o.onArrive then
				o.onArrive()
			end
		else
			local e = t * t * (3 - 2 * t) * 0.4 + t * 0.6
			o.part.CFrame = CFrame.new(bezier(o.a, o.c, o.b, e))
		end
	end
	if #orbList == 0 and orbConnection then
		orbConnection:Disconnect()
		orbConnection = nil
	end
end

function CasteFx.orbs(from: { Vector3 }, to: Vector3, opts: any?)
	opts = opts or {}
	if type(from) ~= "table" or typeof(to) ~= "Vector3" then
		return
	end
	local tint = color(opts.color, Comic.Yellow)
	local perPoint = math.clamp(math.floor(num(opts.perPoint, 1)), 1, 6)
	local total = 0
	local arrived = false
	local clock = os.clock()
	for index, point in from do
		if typeof(point) ~= "Vector3" or not near(point, 260) then
			continue
		end
		for _ = 1, perPoint do
			if total >= 28 or busy() then
				break
			end
			total += 1
			local distance = (to - point).Magnitude
			local flight = num(opts.time, math.clamp(0.55 + distance / 120, 0.6, 1.6))
			local size = rng:NextNumber(0.45, 0.7)
			local orb = CasteFx.part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				Position = point,
				Color = tint,
				Material = Enum.Material.Neon,
				Transparency = 1,
			})
			addTrail(orb, tint, size * 0.45, 0.3, 0)
			life(orb, flight + 2)
			local sideways = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * (2 + distance * 0.08)
			table.insert(orbList, {
				part = orb,
				a = point,
				b = to + Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6)),
				c = (point + to) / 2 + UP * (6 + distance * 0.3) + sideways,
				start = clock + (index - 1) * 0.03 + rng:NextNumber(0, 0.08),
				time = flight,
				shown = false,
				onArrive = function()
					if arrived then
						return
					end
					arrived = true
					CasteFx.burst(to, { color = tint, count = 10, speed = 12, size = 0.5, life = 0.4, up = true })
					CasteFx.ring(to - UP * 2, 3.5, { color = tint, life = 0.35 })
					CasteFx.sound("chime", to, 1.1)
				end,
			})
		end
	end
	if #orbList > 0 and not orbConnection then
		orbConnection = RunService.RenderStepped:Connect(stepOrbs)
	end
end

---------------------------------------------------------------------------------------------------
-- Siluetas, palabras, pantalla

function CasteFx.ghosts(character: Model, seconds: number, opts: any?)
	opts = opts or {}
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return
	end
	local tint = color(opts.color, WHITE)
	local lifeTime = math.max(num(seconds, 0.5), 0.05)
	local interval = math.max(num(opts.interval, 0.07), 0.03)
	-- Las piezas grandes del cuerpo, sin la raíz invisible
	local body = {}
	for _, d in character:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 then
			table.insert(body, d)
		end
	end
	table.sort(body, function(x, y)
		return x.Size.Magnitude > y.Size.Magnitude
	end)
	local pieces = {}
	for i = 1, math.min(#body, 8) do
		pieces[i] = body[i]
	end
	task.spawn(function()
		local started = os.clock()
		while os.clock() - started < lifeTime and character.Parent do
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and near(root.Position, 200) and not busy() then
				for _, source in pieces do
					if source.Parent then
						local ghost = CasteFx.part({
							Shape = if source:IsA("Part") then source.Shape else Enum.PartType.Block,
							Size = source.Size,
							CFrame = source.CFrame,
							Color = tint,
							Material = Enum.Material.Neon,
							Transparency = 0.45,
						})
						local mesh = source:FindFirstChildOfClass("SpecialMesh")
						if mesh then
							local copy = Instance.new("SpecialMesh")
							copy.MeshType = mesh.MeshType
							copy.Scale = mesh.Scale
							copy.Parent = ghost
						end
						tween(ghost, 0.3, { Transparency = 1, Size = source.Size * 0.85 })
						life(ghost, 0.32)
					end
				end
			end
			task.wait(interval)
		end
	end)
end

function CasteFx.word(pos: Vector3, text: string, opts: any?)
	opts = opts or {}
	if typeof(pos) ~= "Vector3" or type(text) ~= "string" or not near(pos, 220) then
		return
	end
	local tint = color(opts.color, Comic.Yellow)
	local px = math.clamp(num(opts.size, 46), 14, 140)
	local seconds = math.max(num(opts.life, 0.75), 0.2)
	local anchor = anchorPart(pos, seconds + 0.1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(math.floor(px * (#text * 0.62 + 1.4)), math.floor(px * 1.7))
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Adornee = anchor
	gui.Parent = anchor

	local holder = Comic.frame(gui)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.Rotation = rng:NextNumber(-12, 12)
	local pop = Instance.new("UIScale")
	pop.Scale = 0.2
	pop.Parent = holder

	if opts.burst then
		local burst = Comic.burst(holder, px * 2.4, lighter(tint, 0.55))
		burst.Rotation = rng:NextNumber(-20, 20)
	end
	-- Sombra de tinta desplazada y, encima, la palabra con su trazo
	local shadow = Comic.label(holder, text, Comic.Display, px, INK)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, math.floor(px * 0.08), 0.5, math.floor(px * 0.1))
	shadow.Size = UDim2.fromScale(1, 1)
	local label = Comic.label(holder, text, Comic.Display, px, tint)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	local stroke = Comic.ink(label, math.max(2, px * 0.08))

	tween(pop, 0.14, { Scale = 1.25 }, Enum.EasingStyle.Back)
	task.delay(0.14, function()
		tween(pop, 0.12, { Scale = 1 }, Enum.EasingStyle.Quad)
	end)
	tween(gui, seconds, { StudsOffset = Vector3.new(0, 2.6, 0) }, Enum.EasingStyle.Quad)
	local fade = math.min(0.22, seconds * 0.35)
	tween(label, fade, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, seconds - fade)
	tween(shadow, fade, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, seconds - fade)
	tween(stroke, fade, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, seconds - fade)
	tween(pop, fade, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, seconds - fade)
end

function CasteFx.shake(amount: number, time: number?)
	if CasteFx._quiet then
		return
	end
	local power = math.clamp(num(amount, 0.3), 0, 1)
	GameFx.shake(power)
	local duration = num(time, 0)
	if duration > 0.25 then
		task.spawn(function()
			local started = os.clock()
			while os.clock() - started < duration do
				task.wait(0.12)
				GameFx.shake(power * 0.3)
			end
		end)
	end
end

local flashGui: ScreenGui? = nil

function CasteFx.flash(tint: Color3, alpha: number, time: number?)
	if CasteFx._quiet then
		return
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui = flashGui
	if not gui or not gui.Parent then
		gui = Instance.new("ScreenGui")
		gui.Name = "CasteFlash"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 4
		gui.Parent = playerGui
		flashGui = gui
	end
	local frame = Comic.frame(gui :: ScreenGui, color(tint, WHITE))
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1 - math.clamp(num(alpha, 0.3), 0, 0.85)
	local seconds = math.max(num(time, 0.25), 0.05)
	tween(frame, seconds, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	life(frame, seconds + 0.05)
end

-- Boca del hormiguero de esa jugadora
function CasteFx.hillOf(player: Player): Vector3?
	local hills = Workspace:FindFirstChild("Anthills")
	if not hills or typeof(player) ~= "Instance" then
		return nil
	end
	for _, hill in hills:GetChildren() do
		if hill:IsA("Model") and hill:GetAttribute("OwnerId") == player.UserId then
			return hill:GetPivot().Position + UP * 3
		end
	end
	return nil
end

return CasteFx
