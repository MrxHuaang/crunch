-- Efectos: palabritas al morder, estallidos de onomatopeya, trozos que saltan,
-- líneas de velocidad y la viñeta de pantalla completa del rebirth.
-- Impacto al morder: parada de impacto, golpe de FOV y temblor de cámara, comida que se aplasta y
-- rebota hacia el lado contrario al mordisco, marca de dientes, números que saltan y migajas que
-- vuelan en arco hasta tu boca. Rematar una comida estalla con anillo, confeti de sus colores y
-- palabra grande. Lo que golpea a varias comidas a la vez se escalona como una ráfaga.
-- Todo con presupuesto fijo: piscinas de instancias y cubos de fichas.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local AntAnim = require(script.Parent.AntAnim)
local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Fx = {}

local rng = Random.new()
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 184, 28)
local ORANGE = Color3.fromRGB(255, 140, 40)
local WHITE = Color3.new(1, 1, 1)
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds" -- textura incluida en Roblox
local lastFoodColor: Color3? = nil -- color de la última comida que mordiste (para las migajas)

-- Presupuesto: cubo de fichas que se rellena a `rate` por segundo hasta `cap`
type Bucket = { tokens: number, rate: number, cap: number, last: number }

local function bucket(rate: number, cap: number): Bucket
	return { tokens = cap, rate = rate, cap = cap, last = os.clock() }
end

local function spend(b: Bucket): boolean
	local now = os.clock()
	b.tokens = math.min(b.cap, b.tokens + (now - b.last) * b.rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local chunkBudget = bucket(30, 10) -- trozos con física (cualquier hormiga comiendo cerca)
local crumbBudget = bucket(70, 28) -- migajas de tus mordiscos
local confettiBudget = bucket(60, 36) -- confeti de los remates
local wordBudget = bucket(7, 5) -- palabras de cómic flotando
local flashBudget = bucket(10, 6) -- destellos con luz
local NIBBLES = { "ñam", "ñam", "chomp", "ñac" }
local nibbleIndex = 0

local overlay: ScreenGui
local speedLines: ImageLabel
local fxFolder: Folder

local function anchorAt(position: Vector3, life: number): Part
	local part = Instance.new("Part")
	part.Name = "FxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = position
	part.Parent = fxFolder or Workspace
	Debris:AddItem(part, life)
	return part
end

local function billboardOn(part: Part, width: number, height: number): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(width, height)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = part
	billboard.Parent = part
	return billboard
end

local function easeOut(x: number): number
	return 1 - (1 - x) * (1 - x)
end

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?, delay: number?)
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0)
	local t = TweenService:Create(object, info, goal)
	t:Play()
	return t
end

-- Punto de la boca de tu hormiga (para que números y migajas salgan de donde muerde)
local function mouth(): Vector3?
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position + head.CFrame.LookVector * (head.Size.Z * 0.6)
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Temblor de cámara por "trauma": cada golpe suma trauma (0..1), que decae solo. La sacudida es
-- trauma² con ruido suave en giro y un pelín de desplazamiento.
-- Se aplica justo DESPUÉS de que la cámara de Roblox se actualice y se deshace justo ANTES de su
-- siguiente actualización, devolviendo el CFrame exacto que ella dejó: el módulo de cámara nunca ve
-- la sacudida, así que no pelea con el ratón ni acumula deriva. Si otro script movió la cámara entre
-- medias (el CFrame ya no es el que pusimos), no se toca.
-- El golpe de FOV (un zoom muy corto hacia dentro al morder) sigue la misma regla.

local SHAKE_DECAY = 1.6 -- trauma por segundo
local SHAKE_PITCH = math.rad(1.6)
local SHAKE_YAW = math.rad(1.6)
local SHAKE_ROLL = math.rad(2.4)
local SHAKE_MOVE = 0.12
local FOV_RETURN = 16 -- lo rápido que vuelve el FOV (1/s)
local FOV_MAX = 6 -- grados

local trauma = 0
local shakeBase: CFrame? = nil
local shakeWritten: CFrame? = nil
local fovKick = 0
local fovBase: number? = nil
local fovWritten: number? = nil

-- Ajuste "Movimiento suave" (lo pone el HUD): se lee en cada efecto para que cambie al momento
local function calm(): boolean
	return player:GetAttribute("ReducedMotion") == true
end

-- Sacude la cámara. 0.2 suave, 0.45 fuerte, 0.6+ muy fuerte. Se suma y satura en 1.
-- Todo temblor del juego pasa por aquí (también CasteFx), así que basta cortarlo aquí.
function Fx.shake(amount: number)
	if calm() then
		return
	end
	trauma = math.clamp(trauma + amount, 0, 1)
end

-- Zoom muy corto hacia dentro (grados). No se suma: se queda el más fuerte.
function Fx.kick(degrees: number)
	if calm() then
		return
	end
	fovKick = math.clamp(math.max(fovKick, degrees), 0, FOV_MAX)
end

local function undoShake()
	local camera = Workspace.CurrentCamera
	local base, written = shakeBase, shakeWritten
	shakeBase, shakeWritten = nil, nil
	if base and camera and camera.CFrame == written then
		camera.CFrame = base
	end
	local fov, fovW = fovBase, fovWritten
	fovBase, fovWritten = nil, nil
	if fov and camera and camera.FieldOfView == fovW then
		camera.FieldOfView = fov
	end
end

local function applyShake(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if fovKick > 0.05 then
		fovKick *= math.exp(-FOV_RETURN * dt)
		local base = camera.FieldOfView
		camera.FieldOfView = math.clamp(base - fovKick, 20, 120)
		fovBase = base
		fovWritten = camera.FieldOfView
	else
		fovKick = 0
	end
	if trauma <= 0 then
		return
	end
	trauma = math.max(0, trauma - SHAKE_DECAY * dt)
	local power = trauma * trauma * 2 -- math.noise da más o menos -0.5..0.5
	local t = os.clock() * 24
	local offset = CFrame.new(math.noise(t, 7.31) * SHAKE_MOVE * power, math.noise(t, 13.77) * SHAKE_MOVE * power, 0)
		* CFrame.Angles(
			math.noise(t, 1.13) * SHAKE_PITCH * power,
			math.noise(t, 3.91) * SHAKE_YAW * power,
			math.noise(t, 5.27) * SHAKE_ROLL * power
		)
	local base = camera.CFrame
	camera.CFrame = base * offset
	shakeBase = base
	shakeWritten = camera.CFrame
end

---------------------------------------------------------------------------------------------------
-- Números de daño: piscina fija de carteles que se reutilizan (el más viejo cede el sitio).

type NumberPop = {
	anchor: Attachment,
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	pop: UIScale,
	born: number,
	from: Vector3,
	drift: Vector3,
	active: boolean,
}

local NUMBER_POOL = 16
local NUMBER_LIFE = 0.75
local numbers: { NumberPop } = {}
local nextNumber = 0

local function makeNumber(): NumberPop
	-- Bajo Terrain (que está en el origen) la posición local de un Attachment es la del mundo
	local anchor = Instance.new("Attachment")
	anchor.Name = "FxNumber"
	anchor.Parent = Workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 72)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = anchor

	local label = Comic.label(gui, "", Comic.Display, 30, Comic.Paper)
	label.Size = UDim2.fromScale(1, 1)
	local stroke = Comic.ink(label, 3)
	local pop = Instance.new("UIScale")
	pop.Parent = label

	return {
		anchor = anchor,
		gui = gui,
		label = label,
		stroke = stroke,
		pop = pop,
		born = 0,
		from = Vector3.zero,
		drift = Vector3.zero,
		active = false,
	}
end

-- Número de cómic que salta desde `position`: amarillo y grande en crítico, dorado en mordisco dorado.
-- `boost` (0..1, opcional) lo agranda: la racha hace que los números crezcan.
function Fx.number(position: Vector3, amount: number, crit: boolean?, golden: boolean?, boost: number?)
	if #numbers == 0 then
		return
	end
	nextNumber = nextNumber % #numbers + 1
	local n = numbers[nextNumber]
	local big = crit or golden
	local grow = math.clamp(boost or 0, 0, 1)
	local fit = Hud.fxScale() -- píxeles fijos: en celular llenaban la pantalla
	n.gui.Size = UDim2.fromOffset(170 * fit, 72 * fit)

	n.label.Text = "+" .. Format.short(amount) .. (if big then "!" else "")
	n.label.TextColor3 = if golden then GOLD elseif crit then Comic.Yellow else Comic.Paper:Lerp(Comic.Yellow, grow * 0.6)
	n.label.TextSize = math.floor(((if golden then 46 elseif crit then 44 else 30) + 10 * grow) * fit)
	n.label.Rotation = rng:NextNumber(-12, 12)
	n.label.TextTransparency = 0
	n.stroke.Thickness = if big then 4 else 3
	n.stroke.Transparency = 0
	n.pop.Scale = 0.2

	-- Un poco de dispersión para que no se apilen a 8 mordiscos por segundo
	n.from = position + Vector3.new(rng:NextNumber(-1.1, 1.1), rng:NextNumber(0.6, 1.4), rng:NextNumber(-1.1, 1.1))
	n.drift = Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(2.4, 3.2) + (if big then 1 else 0), rng:NextNumber(-0.8, 0.8))
	n.anchor.Position = n.from
	n.born = os.clock()
	n.active = true
	n.gui.Enabled = true
end

local function updateNumbers(now: number)
	for _, n in numbers do
		if not n.active then
			continue
		end
		local u = (now - n.born) / NUMBER_LIFE
		if u >= 1 then
			n.active = false
			n.gui.Enabled = false
			continue
		end
		-- Sale disparado, se pasa de tamaño y se asienta; sube frenando y se apaga al final
		if u < 0.15 then
			local k = u / 0.15
			n.pop.Scale = 0.2 + 1.1 * (1 - (1 - k) ^ 3)
		elseif u < 0.3 then
			n.pop.Scale = 1.3 - 0.3 * (u - 0.15) / 0.15
		else
			n.pop.Scale = 1
		end
		n.anchor.Position = n.from + n.drift * easeOut(u)
		local fade = if u > 0.6 then (u - 0.6) / 0.4 else 0
		n.label.TextTransparency = fade
		n.stroke.Transparency = fade
	end
end

---------------------------------------------------------------------------------------------------
-- Migajas: piscina fija de piezas ancladas que se mueven a mano (sin física) con BulkMoveTo.
-- Si se piden más de las que hay, se reutiliza la más vieja: nunca hay más de CRUMB_POOL.
-- Tres maneras de moverse: tiro parabólico (saltan y caen), curva fija (de la hormiga al
-- hormiguero) y curva que persigue tu boca (las que se "absorben" al morder).
-- Las migajas son bolitas y el confeti discos: nada cuadrado.

type Crumb = {
	part: Part,
	active: boolean,
	shown: boolean,
	born: number,
	life: number,
	p0: Vector3,
	velocity: Vector3,
	gravity: Vector3,
	ctrl: Vector3?, -- con ctrl y p1 sigue una curva
	p1: Vector3?,
	home: boolean, -- p1 es tu boca y se actualiza cada fotograma
	size: Vector3,
	spin: Vector3,
}

local CRUMB_POOL = 110
local GRAVITY = Vector3.new(0, -70, 0)
local CONFETTI_GRAVITY = Vector3.new(0, -30, 0)
local crumbs: { Crumb } = {}
local nextCrumb = 0
local crumbParts: { BasePart } = {}
local crumbFrames: { CFrame } = {}

local function makeCrumb(folder: Folder): Crumb
	local part = Instance.new("Part")
	part.Name = "Crumb"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Shape = Enum.PartType.Ball
	part.Transparency = 1
	part.Size = Vector3.new(0.3, 0.3, 0.3)
	part.CFrame = CFrame.new(0, -500, 0)
	part.Parent = folder
	return {
		part = part,
		active = false,
		shown = false,
		born = 0,
		life = 0,
		p0 = Vector3.zero,
		velocity = Vector3.zero,
		gravity = GRAVITY,
		ctrl = nil,
		p1 = nil,
		home = false,
		size = part.Size,
		spin = Vector3.zero,
	}
end

-- disc = true: confeti (disco plano que da vueltas); si no, bolita
local function launchCrumb(p0: Vector3, color: Color3, side: number, life: number, delay: number, disc: boolean?): Crumb?
	if #crumbs == 0 then
		return nil
	end
	nextCrumb = nextCrumb % #crumbs + 1
	local c = crumbs[nextCrumb]
	local part = c.part
	part.Transparency = 1
	part.Color = color
	part.Material = if color == GOLD then Enum.Material.Neon else Enum.Material.SmoothPlastic
	if disc then
		part.Shape = Enum.PartType.Cylinder
		c.size = Vector3.new(side * 0.22, side, side)
	else
		part.Shape = Enum.PartType.Ball
		c.size = Vector3.new(side, side, side)
	end
	part.Size = c.size
	c.active = true
	c.shown = false
	c.born = os.clock() + delay
	c.life = life
	c.p0 = p0
	c.velocity = Vector3.zero
	c.gravity = if disc then CONFETTI_GRAVITY else GRAVITY
	c.ctrl = nil
	c.p1 = nil
	c.home = false
	c.spin = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(-14, 14), rng:NextNumber(-14, 14))
	return c
end

-- Unas migajas pequeñas que saltan desde el punto del mordisco (con presupuesto).
function Fx.crumbs(position: Vector3, color: Color3?, count: number)
	local tint = color or lastFoodColor or Comic.Crumb
	for _ = 1, count do
		if not spend(crumbBudget) then
			return
		end
		local c = launchCrumb(position, tint, rng:NextNumber(0.22, 0.4), rng:NextNumber(0.4, 0.55), 0)
		if c then
			c.velocity = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(14, 24), rng:NextNumber(-9, 9))
		end
	end
end

-- Trozos que saltan en arco desde `from` y acaban dentro de tu boca (escalonados `stagger` s).
function Fx.absorb(from: Vector3, color: Color3?, count: number, size: number?, stagger: number?)
	local tint = color or lastFoodColor or Comic.Crumb
	local target = mouth()
	if not target or (target - from).Magnitude > 40 then
		return
	end
	local distance = (target - from).Magnitude
	for i = 1, count do
		if not spend(crumbBudget) then
			return
		end
		local side = (size or 0.4) * rng:NextNumber(0.75, 1.15)
		local start = from + Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 0.6), rng:NextNumber(-0.6, 0.6))
		local c = launchCrumb(start, tint, side, rng:NextNumber(0.32, 0.45) + distance * 0.01, (i - 1) * (stagger or 0.03))
		if c then
			c.p1 = target
			c.home = true
			c.ctrl = (start + target) / 2
				+ Vector3.new(rng:NextNumber(-2.5, 2.5), 3 + distance * 0.3 + rng:NextNumber(0, 2.5), rng:NextNumber(-2.5, 2.5))
		end
	end
end

-- Confeti de discos con los colores de la comida, que salta en corona y cae despacio.
function Fx.confetti(position: Vector3, colors: { Color3 }, count: number, power: number?)
	local strength = power or 1
	for i = 1, count do
		if not spend(confettiBudget) then
			return
		end
		local color = colors[(i - 1) % #colors + 1] or Comic.Yellow
		local c = launchCrumb(position, color, rng:NextNumber(0.35, 0.6), rng:NextNumber(0.7, 1), rng:NextNumber(0, 0.04), true)
		if c then
			local angle = rng:NextNumber(0, math.pi * 2)
			local out = rng:NextNumber(6, 13) * strength
			c.velocity = Vector3.new(math.cos(angle) * out, rng:NextNumber(14, 24) * math.sqrt(strength), math.sin(angle) * out)
		end
	end
end

local function updateCrumbs(now: number)
	table.clear(crumbParts)
	table.clear(crumbFrames)
	local target: Vector3? = nil
	local looked = false
	for _, c in crumbs do
		if not c.active then
			continue
		end
		local t = now - c.born
		if t < 0 then
			continue -- aún esperando su turno (ráfaga escalonada)
		end
		local part = c.part
		if t >= c.life then
			c.active = false
			part.Transparency = 1
			continue
		end
		if not c.shown then
			c.shown = true
			part.Transparency = 0
		end
		local u = t / c.life
		local pos: Vector3
		if c.home then
			if not looked then
				looked = true
				target = mouth()
			end
			if target then
				c.p1 = target
			end
		end
		local ctrl, p1 = c.ctrl, c.p1
		if ctrl and p1 then
			local e = u * u * (3 - 2 * u) * 0.35 + u * 0.65
			local a = 1 - e
			pos = c.p0 * (a * a) + ctrl * (2 * a * e) + p1 * (e * e)
		else
			pos = c.p0 + c.velocity * t + c.gravity * (0.5 * t * t)
		end
		if u > 0.65 then
			part.Size = c.size * (1 - (u - 0.65) / 0.35 * 0.85)
		end
		table.insert(crumbParts, part)
		table.insert(crumbFrames, CFrame.new(pos) * CFrame.Angles(c.spin.X * t, c.spin.Y * t, c.spin.Z * t))
	end
	if #crumbParts > 0 then
		Workspace:BulkMoveTo(crumbParts, crumbFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------------------------------
-- Aplastón de la comida al morderla.
-- Las comidas son modelos anclados del servidor que además pierden piezas. Técnica: al empezar se
-- guarda el CFrame y el Size ORIGINALES de cada pieza (una sola vez por aplastón; si llega otro
-- mordisco a mitad, se reutilizan esas mismas copias, nunca la pose deformada) y cada fotograma se
-- escribe la pose como función de esos originales; al acabar se escriben los originales tal cual.
-- Son escrituras solo locales: el servidor no las ve ni las devuelve. Si el servidor cambia una
-- pieza (su CFrame ya no es el último que escribimos) esa pieza se suelta y se le deja su valor
-- del servidor; si la pieza o el modelo desaparecen, simplemente se saltan.
-- Además de aplastarse, se inclina: se aparta del lado del mordisco y rebota hacia ti.

type SquashPiece = {
	part: BasePart,
	cf: CFrame,
	size: Vector3,
	weights: Vector3?, -- cuánto mira cada eje local hacia arriba (nil = no se cambia el tamaño)
	cylinder: boolean,
	wrote: CFrame?,
	lost: boolean,
}

type Squash = {
	model: Model,
	pivot: CFrame, -- en la base del modelo, sin giro
	pieces: { SquashPiece },
	born: number,
	from: number,
	amount: number,
	axis: Vector3?, -- eje de la inclinación (horizontal); nil = sin inclinación
}

local SQUASH_DOWN = 0.07
local SQUASH_BACK = 0.26
local SQUASH_AMOUNT = 0.16
local SQUASH_TILT = 0.9 -- radianes de inclinación por unidad de aplastamiento
local SQUASH_MAX_PIECES = 160
local SQUASH_MAX_ACTIVE = 8

local squashes: { [Model]: Squash } = {}
local squashCount = 0
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local movePieces: { SquashPiece } = {}

-- Aplastamiento en el instante t (positivo = aplastada, negativo = estirada). nil al acabar.
local function squashCurve(s: Squash, t: number): number?
	if t < SQUASH_DOWN then
		return s.from + (s.amount - s.from) * easeOut(t / SQUASH_DOWN)
	end
	local u = (t - SQUASH_DOWN) / SQUASH_BACK
	if u >= 1 then
		return nil
	end
	-- Muelle: vuelve, se pasa (se estira), vuelve a pasarse un poco y se asienta
	return s.amount * math.cos(u * math.pi * 2.5) * (1 - u) ^ 1.6
end

local function axisFactor(weight: number, sy: number, sh: number): number
	return math.sqrt((1 - weight) * sh * sh + weight * sy * sy)
end

-- a = nil restaura los originales exactos
local function poseSquash(s: Squash, a: number?)
	local sy, sh = 1, 1
	local tilt: CFrame? = nil
	if a then
		sy = 1 - a
		sh = 1 + a * 0.5
		if s.axis then
			local origin = s.pivot.Position
			tilt = CFrame.new(origin) * CFrame.fromAxisAngle(s.axis, a * SQUASH_TILT) * CFrame.new(-origin)
		end
	end
	table.clear(moveParts)
	table.clear(moveFrames)
	table.clear(movePieces)
	for _, p in s.pieces do
		local part = p.part
		if not part.Parent then
			continue
		end
		if not p.lost and p.wrote and part.CFrame ~= p.wrote then
			p.lost = true
		end
		local weights = p.weights
		if a == nil then
			if weights then
				part.Size = p.size
			end
			if not p.lost then
				table.insert(moveParts, part)
				table.insert(moveFrames, p.cf)
				table.insert(movePieces, p)
			end
			continue
		end
		if p.lost then
			continue
		end
		if weights then
			local fx = axisFactor(weights.X, sy, sh)
			local fy = axisFactor(weights.Y, sy, sh)
			local fz = axisFactor(weights.Z, sy, sh)
			if p.cylinder then
				local mid = (fy + fz) / 2
				fy, fz = mid, mid
			end
			part.Size = p.size * Vector3.new(fx, fy, fz)
		end
		local rel = s.pivot:PointToObjectSpace(p.cf.Position)
		local pos = s.pivot:PointToWorldSpace(Vector3.new(rel.X * sh, rel.Y * sy, rel.Z * sh))
		local cf = p.cf.Rotation + pos
		if tilt then
			cf = tilt * cf
		end
		table.insert(moveParts, part)
		table.insert(moveFrames, cf)
		table.insert(movePieces, p)
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		for i, part in moveParts do
			movePieces[i].wrote = part.CFrame
		end
	end
end

local function resizable(part: BasePart): (boolean, boolean)
	if part:IsA("Part") then
		-- Una bola se fuerza a ser redonda: cambiarle el tamaño por ejes no funcionaría
		if part.Shape == Enum.PartType.Ball then
			return false, false
		end
		return true, part.Shape == Enum.PartType.Cylinder
	end
	return part:IsA("WedgePart") or part:IsA("MeshPart"), false
end

-- Eje de inclinación para que la cima se aparte de `from` (horizontal)
local function tiltAxis(pivot: Vector3, from: Vector3?): Vector3?
	if not from then
		return nil
	end
	local away = (pivot - from) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.05 then
		return nil
	end
	return Vector3.yAxis:Cross(away.Unit)
end

-- La comida (o cualquier modelo anclado) se aplasta de golpe y rebota como gelatina.
-- amount: fuerza (0.16 normal); from: de dónde viene el golpe (se aparta de ahí);
-- maxPieces: tope de piezas (por defecto 160; el hormiguero usa más).
function Fx.squash(model: Instance?, amount: number?, from: Vector3?, maxPieces: number?)
	if not model or not model:IsA("Model") or not model.Parent then
		return
	end
	local color = model:GetAttribute("Color")
	if typeof(color) == "Color3" then
		lastFoodColor = color
	end
	local strength = amount or SQUASH_AMOUNT
	if from == nil then
		-- Mordisco de tu hormiga: el golpe viene de ella
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - model:GetPivot().Position).Magnitude < 40 then
			from = root.Position
		end
	end

	local now = os.clock()
	local existing = squashes[model]
	if existing then
		-- Ya está botando: la curva sigue desde donde va, con las mismas poses originales
		existing.from = squashCurve(existing, now - existing.born) or 0
		existing.born = now
		existing.amount = math.max(strength, existing.amount * 0.6)
		existing.axis = tiltAxis(existing.pivot.Position, from) or existing.axis
		return
	end
	if squashCount >= SQUASH_MAX_ACTIVE then
		return
	end

	local limit = maxPieces or SQUASH_MAX_PIECES
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored then
			table.insert(parts, d)
			if #parts > limit then
				return
			end
		end
	end
	if #parts == 0 then
		return
	end

	local box, extents = model:GetBoundingBox()
	local origin = model:GetPivot().Position
	local pivot = CFrame.new(origin.X, box.Position.Y - extents.Y / 2, origin.Z)
	local pieces: { SquashPiece } = {}
	for _, part in parts do
		local resize, cylinder = resizable(part)
		local weights: Vector3? = nil
		if resize then
			local rel = part.CFrame
			weights = Vector3.new(rel.RightVector.Y ^ 2, rel.UpVector.Y ^ 2, rel.LookVector.Y ^ 2)
		end
		table.insert(pieces, {
			part = part,
			cf = part.CFrame,
			size = part.Size,
			weights = weights,
			cylinder = cylinder,
			wrote = nil,
			lost = false,
		})
	end
	squashes[model] = {
		model = model,
		pivot = pivot,
		pieces = pieces,
		born = now,
		from = 0,
		amount = strength,
		axis = tiltAxis(pivot.Position, from),
	}
	squashCount += 1
end

local function updateSquashes(now: number)
	for model, s in squashes do
		if not model.Parent then
			-- Comida terminada o retirada: nada que devolver
			squashes[model] = nil
			squashCount -= 1
			continue
		end
		local a = squashCurve(s, now - s.born)
		poseSquash(s, a)
		if a == nil then
			squashes[model] = nil
			squashCount -= 1
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Registro de la comida: dónde está, su radio, sus colores y cuánta vida perdió hace poco.
-- Sirve para saber qué otras comidas recibieron daño a la vez (área) y cómo era la que acabas de
-- rematar (el servidor la destruye antes de avisar).

type FoodInfo = {
	pos: Vector3,
	radius: number,
	color: Color3,
	colors: { Color3 }?,
	hp: number,
	drop: number,
	dropAt: number,
	golden: boolean,
}

type Gone = { pos: Vector3, radius: number, color: Color3, colors: { Color3 }?, at: number, golden: boolean }

local foodInfo: { [Model]: FoodInfo } = {}
local gone: { Gone } = {}
local GONE_KEEP = 16

local function paletteOf(model: Model, info: FoodInfo): { Color3 }
	if info.colors then
		return info.colors
	end
	local list: { Color3 } = { info.color }
	local seen = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			seen += 1
			local fresh = true
			for _, c in list do
				local dr, dg, db = c.R - d.Color.R, c.G - d.Color.G, c.B - d.Color.B
				if dr * dr + dg * dg + db * db < 0.02 then
					fresh = false
					break
				end
			end
			if fresh then
				table.insert(list, d.Color)
			end
			if #list >= 4 or seen > 60 then
				break
			end
		end
	end
	info.colors = list
	return list
end

local function track(model: Instance)
	if not model:IsA("Model") or foodInfo[model] then
		return
	end
	local color = model:GetAttribute("Color")
	local info: FoodInfo = {
		pos = model:GetPivot().Position,
		radius = tonumber(model:GetAttribute("Radius")) or 2,
		color = if typeof(color) == "Color3" then color else Comic.Crumb,
		colors = nil,
		hp = tonumber(model:GetAttribute("Hp")) or 0,
		drop = 0,
		dropAt = -math.huge,
		golden = model:GetAttribute("Golden") == true,
	}
	foodInfo[model] = info
	model:GetAttributeChangedSignal("Hp"):Connect(function()
		local hp = tonumber(model:GetAttribute("Hp")) or 0
		if hp < info.hp then
			info.drop = info.hp - hp
			info.dropAt = os.clock()
		end
		info.hp = hp
	end)
	model:GetAttributeChangedSignal("Radius"):Connect(function()
		info.radius = tonumber(model:GetAttribute("Radius")) or info.radius
	end)
	model:GetAttributeChangedSignal("Color"):Connect(function()
		local c = model:GetAttribute("Color")
		if typeof(c) == "Color3" then
			info.color = c
			info.colors = nil
		end
		info.golden = model:GetAttribute("Golden") == true
	end)
	-- Los colores de las piezas se leen ahora, con todas las piezas aún puestas
	task.defer(function()
		if model.Parent then
			paletteOf(model, info)
		end
	end)
end

local function untrack(model: Instance)
	local info = foodInfo[model :: Model]
	if not info then
		return
	end
	foodInfo[model :: Model] = nil
	table.insert(gone, { pos = info.pos, radius = info.radius, color = info.color, colors = info.colors, at = os.clock(), golden = info.golden })
	if #gone > GONE_KEEP then
		table.remove(gone, 1)
	end
end

local function foodAt(position: Vector3): (Model?, FoodInfo?)
	local best, bestInfo, bestGap = nil, nil, 1.5
	for model, info in foodInfo do
		local gap = (info.pos - position).Magnitude
		if gap < bestGap then
			best, bestInfo, bestGap = model, info, gap
		end
	end
	return best, bestInfo
end

local function goneAt(position: Vector3, maxAge: number): Gone?
	local now = os.clock()
	for i = #gone, 1, -1 do
		local g = gone[i]
		if now - g.at <= maxAge and (g.pos - position).Magnitude < 1.5 then
			return g
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Marca de dientes: tres bolitas oscuras hundidas en la superficie en forma de sonrisa, donde
-- mordiste. Duran un momento y se encogen; si la pieza cae, la marca se va con ella.

type Mark = { balls: { Part }, piece: BasePart?, born: number, active: boolean, size: number }

local MARK_POOL = 6
local MARK_LIFE = 1.1
local marks: { Mark } = {}
local nextMark = 0
local markParts: { BasePart } = {}
local markFrames: { CFrame } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function makeMark(folder: Folder): Mark
	local balls = {}
	for i = 1, 3 do
		local ball = Instance.new("Part")
		ball.Name = "BiteMark" .. i
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanQuery = false
		ball.CanTouch = false
		ball.CastShadow = false
		ball.Material = Enum.Material.SmoothPlastic
		ball.Transparency = 1
		ball.Size = Vector3.new(0.4, 0.4, 0.4)
		ball.CFrame = CFrame.new(0, -500, 0)
		ball.Parent = folder
		balls[i] = ball
	end
	return { balls = balls, piece = nil, born = 0, active = false, size = 0.4 }
end

local function biteMark(model: Model, info: FoodInfo?)
	if #marks == 0 then
		return
	end
	local from = mouth()
	if not from then
		return
	end
	local center = model:GetPivot().Position + Vector3.new(0, (info and info.radius or 2) * 0.45, 0)
	local dir = center - from
	if dir.Magnitude < 0.1 or dir.Magnitude > 30 then
		return
	end
	rayParams.FilterDescendantsInstances = { model }
	local hit = Workspace:Raycast(from - dir.Unit * 1.5, dir.Unit * (dir.Magnitude + 3), rayParams)
	if not hit or not hit.Instance:IsA("BasePart") then
		return
	end
	nextMark = nextMark % #marks + 1
	local mark = marks[nextMark]
	local normal = hit.Normal
	local tangent = normal:Cross(Vector3.yAxis)
	if tangent.Magnitude < 0.1 then
		local camera = Workspace.CurrentCamera
		tangent = if camera then camera.CFrame.RightVector else Vector3.xAxis
	end
	tangent = tangent.Unit
	local down = tangent:Cross(normal).Unit
	if down.Y > 0 then
		down = -down
	end
	local size = math.clamp((info and info.radius or 2) * 0.22, 0.32, 0.8)
	local piece = hit.Instance :: BasePart
	local color = piece.Color:Lerp(Comic.Ink, 0.6)
	mark.piece = piece
	mark.born = os.clock()
	mark.active = true
	mark.size = size
	for i, ball in mark.balls do
		local k = i - 2
		local pos = hit.Position + tangent * (k * size * 1.05) + down * (math.abs(k) * -size * 0.35) - normal * size * 0.2
		ball.Color = color
		ball.Size = Vector3.new(size, size, size)
		ball.Transparency = 0
		ball.CFrame = CFrame.new(pos)
	end
end

local function updateMarks(now: number)
	for _, mark in marks do
		if not mark.active then
			continue
		end
		local u = (now - mark.born) / MARK_LIFE
		local piece = mark.piece
		if u >= 1 or not piece or not piece.Parent then
			mark.active = false
			table.clear(markParts)
			table.clear(markFrames)
			for _, ball in mark.balls do
				ball.Transparency = 1
				table.insert(markParts, ball)
				table.insert(markFrames, CFrame.new(0, -500, 0))
			end
			Workspace:BulkMoveTo(markParts, markFrames, Enum.BulkMoveMode.FireCFrameChanged)
			continue
		end
		if u > 0.55 then
			local s = mark.size * (1 - (u - 0.55) / 0.45)
			for _, ball in mark.balls do
				ball.Size = Vector3.new(s, s, s)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Destellos, chispas, anillos y tajos.

local sparkAttachment: Attachment? = nil
local sparkEmitter: ParticleEmitter? = nil

-- Chispas eléctricas en un punto (un solo emisor compartido que se mueve y dispara)
function Fx.sparks(position: Vector3, count: number, color: Color3?)
	local emitter, attachment = sparkEmitter, sparkAttachment
	if not emitter or not attachment then
		return
	end
	attachment.Position = position
	emitter.Color = ColorSequence.new(WHITE, color or Comic.Yellow)
	emitter:Emit(math.clamp(count, 1, 24))
end

-- Destello: bola de neón que se hincha y se apaga, con una luz que ilumina alrededor.
function Fx.flash(position: Vector3, color: Color3, size: number?, light: boolean?)
	if not spend(flashBudget) then
		return
	end
	local s = size or 2
	local ball = Instance.new("Part")
	ball.Name = "FxFlash"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Transparency = 0.15
	ball.Size = Vector3.new(s * 0.3, s * 0.3, s * 0.3)
	ball.CFrame = CFrame.new(position)
	ball.Parent = fxFolder
	tween(ball, 0.16, { Size = Vector3.new(s, s, s), Transparency = 1 })
	if light ~= false then
		local glow = Instance.new("PointLight")
		glow.Color = color
		glow.Range = math.clamp(s * 5, 8, 24)
		glow.Brightness = 5
		glow.Shadows = false
		glow.Parent = ball
		tween(glow, 0.22, { Brightness = 0 })
	end
	Debris:AddItem(ball, 0.3)
end

-- Anillo plano que se abre en el suelo (adorno de cilindro con hueco), con borde de tinta.
function Fx.ring(position: Vector3, radius: number, color: Color3, life: number?)
	local seconds = life or 0.35
	local part = anchorAt(position, seconds + 0.1)
	local flat = CFrame.Angles(math.rad(90), 0, 0)
	local function ringOf(c: Color3, zLift: number, width: number, transparency: number)
		local ring = Instance.new("CylinderHandleAdornment")
		ring.Adornee = part
		ring.CFrame = CFrame.new(0, zLift, 0) * flat
		ring.Height = 0.12
		ring.Radius = radius * 0.3
		ring.InnerRadius = math.max(0, radius * 0.3 - width)
		ring.Color3 = c
		ring.Transparency = transparency
		ring.ZIndex = 1
		ring.Parent = part
		tween(ring, seconds, { Radius = radius, InnerRadius = math.max(0, radius - width * 0.5), Transparency = 1 }, Enum.EasingStyle.Quart)
		return ring
	end
	local width = math.clamp(radius * 0.22, 0.35, 1.6)
	ringOf(Comic.Ink, 0, width + 0.3, 0.1)
	ringOf(color, 0.06, width, 0)
end

local beamCount = 0
local BEAM_CAP = 160

local function beam(a0: Attachment, a1: Attachment, color: Color3, w0: number, w1: number, emission: number, z: number, transparency: number): Beam?
	if beamCount >= BEAM_CAP then
		return nil
	end
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = ColorSequence.new(color)
	b.Width0 = w0
	b.Width1 = w1
	b.FaceCamera = true
	b.LightEmission = emission
	b.LightInfluence = 0
	b.Segments = 1
	b.ZOffset = z
	b.Transparency = NumberSequence.new(transparency)
	b.Parent = a0
	beamCount += 1
	b.Destroying:Once(function()
		beamCount -= 1
	end)
	return b
end

local function point(position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = "FxPoint"
	a.Position = position
	a.Parent = Workspace.Terrain
	return a
end

-- Tajo del crítico: una media luna fina (blanca con tinta) que cruza la comida en diagonal.
function Fx.slash(position: Vector3, size: number?, color: Color3?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local length = (size or 2.5) * 2
	local angle = rng:NextNumber(-0.9, -0.4) * (if rng:NextNumber() < 0.5 then 1 else -1)
	local dir = (camera.CFrame.RightVector * math.cos(angle) + camera.CFrame.UpVector * math.sin(angle)).Unit
	-- Perpendicular al tajo en el plano de la pantalla: lo curva como una media luna
	local bow = (camera.CFrame.RightVector * -math.sin(angle) + camera.CFrame.UpVector * math.cos(angle)) * length * 0.12
	local a = point(position - dir * length / 2)
	local m = point(position + bow)
	local b = point(position + dir * length / 2)
	local points = { a, m, b }
	local width = length * 0.16
	local beams = {}
	local function add(b0: Beam?)
		if b0 then
			table.insert(beams, b0)
		end
	end
	add(beam(a, m, Comic.Ink, 0, width * 1.6, 0, 0, 0))
	add(beam(m, b, Comic.Ink, width * 1.6, 0, 0, 0, 0))
	add(beam(a, m, color or WHITE, 0, width, 1, 0.05, 0))
	add(beam(m, b, color or WHITE, width, 0, 1, 0.05, 0))
	-- Entra estirándose y se adelgaza hasta desaparecer
	for _, bm in beams do
		local w0, w1 = bm.Width0, bm.Width1
		bm.Width0, bm.Width1 = w0 * 0.2, w1 * 0.2
		tween(bm, 0.05, { Width0 = w0, Width1 = w1 })
		tween(bm, 0.16, { Width0 = 0, Width1 = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.07)
	end
	task.delay(0.26, function()
		for _, p in points do
			p:Destroy()
		end
	end)
end

-- Rayo de cómic entre dos puntos: núcleo blanco con halo de color y trazo de tinta, quebrado y con
-- alguna rama. opts: width, color, life, forks (número de ramas), ink (con tinta), flicker.
type BoltOpts = { width: number?, color: Color3?, life: number?, forks: number?, ink: boolean?, flicker: boolean? }

local function zigzag(from: Vector3, to: Vector3, jag: number, segments: number): { Vector3 }
	local dir = to - from
	local side = dir:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	local up = side:Cross(dir).Unit
	local pts = { from }
	for i = 1, segments - 1 do
		local t = i / segments
		local swing = (if i % 2 == 0 then 1 else -1) * rng:NextNumber(0.5, 1) * jag
		table.insert(pts, from + dir * t + side * swing + up * rng:NextNumber(-0.6, 0.6) * jag)
	end
	table.insert(pts, to)
	return pts
end

function Fx.bolt(from: Vector3, to: Vector3, opts: BoltOpts?)
	local o: BoltOpts = opts or {}
	local length = (to - from).Magnitude
	if length < 0.2 then
		return
	end
	local width = o.width or 1
	local color = o.color or Comic.Yellow
	local life = o.life or 0.22
	local segments = math.clamp(math.floor(length / 2.2), 3, 9)
	local jag = math.min(length * 0.12, 1.5)
	local made: { Attachment } = {}
	local beams: { Beam } = {}

	local function strand(pts: { Vector3 }, w: number, withInk: boolean): { Attachment }
		local atts = {}
		for i, p in pts do
			atts[i] = point(p)
			table.insert(made, atts[i])
		end
		for i = 1, #atts - 1 do
			local a0, a1 = atts[i], atts[i + 1]
			-- El grosor se afina hacia la punta de cada rama
			local k0 = 1 - (i - 1) / #atts * 0.5
			local k1 = 1 - i / #atts * 0.5
			if withInk then
				local ink = beam(a0, a1, Comic.Ink, w * 1.25 * k0, w * 1.25 * k1, 0, 0, 0)
				if ink then
					table.insert(beams, ink)
				end
			end
			local halo = beam(a0, a1, color, w * 0.95 * k0, w * 0.95 * k1, 1, 0.03, 0.25)
			local core = beam(a0, a1, WHITE, w * 0.32 * k0, w * 0.32 * k1, 1, 0.06, 0)
			if halo then
				table.insert(beams, halo)
			end
			if core then
				table.insert(beams, core)
			end
		end
		return atts
	end

	local mainPts = zigzag(from, to, jag, segments)
	local main = strand(mainPts, width, o.ink ~= false)
	-- Ramas: salen de un quiebro y se pierden hacia un lado
	for _ = 1, o.forks or 1 do
		if beamCount > BEAM_CAP * 0.7 or #mainPts < 3 then
			break
		end
		local at = rng:NextInteger(2, #mainPts - 1)
		local start = mainPts[at]
		local ahead = (to - start)
		local sideways = ahead:Cross(Vector3.yAxis)
		sideways = if sideways.Magnitude > 0.01 then sideways.Unit else Vector3.xAxis
		local tip = start
			+ ahead * rng:NextNumber(0.25, 0.45)
			+ sideways * rng:NextNumber(-1, 1) * length * 0.25
			+ Vector3.new(0, rng:NextNumber(-0.5, 1.2), 0)
		strand(zigzag(start, tip, jag * 0.6, 3), width * 0.5, false)
	end

	-- Parpadeo: a media vida el rayo cambia de forma (como la electricidad de verdad)
	if o.flicker ~= false then
		task.delay(life * 0.4, function()
			for i = 2, #main - 1 do
				local a = main[i]
				if a.Parent then
					local p = mainPts[i]
					a.Position = p + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.6), rng:NextNumber(-1, 1)) * jag * 0.6
				end
			end
		end)
	end
	for _, bm in beams do
		tween(bm, life * 0.5, { Width0 = 0, Width1 = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, life * 0.5)
	end
	task.delay(life + 0.05, function()
		for _, a in made do
			a:Destroy()
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Palabras de cómic: texto grueso con tinta y sombra dura, que entra pasándose de tamaño, sube un
-- poco y se apaga. Duran poco y salen a un lado de la comida para no tapar el juego.

type WordOpts = { tilt: number?, rise: number?, life: number?, side: number?, ink: number?, force: boolean? }

function Fx.word(position: Vector3, text: string, color: Color3, size: number, opts: WordOpts?)
	local o: WordOpts = opts or {}
	if not o.force and not spend(wordBudget) then
		return
	end
	local life = o.life or 0.6
	-- Todo lo demás (caja, sombra, tinta) sale de px: escalarlo aquí basta para el celular
	local px = math.floor(math.clamp(size, 16, 84) * Hud.fxScale())
	local chars = utf8.len(text) or #text
	local longest = 0
	for line in string.gmatch(text, "[^\n]+") do
		longest = math.max(longest, utf8.len(line) or #line)
	end
	local lines = select(2, string.gsub(text, "\n", "")) + 1
	local width = math.floor(px * (math.max(longest, math.min(chars, 4)) * 0.6 + 1))
	local height = math.floor(px * (lines * 1.05 + 0.4))

	local part = anchorAt(position, life + 0.15)
	local billboard = billboardOn(part, width, height)
	local side = o.side or rng:NextNumber(-1.2, 1.2)
	billboard.StudsOffset = Vector3.new(side, 0.6, 0)

	local holder = Comic.frame(billboard)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.Rotation = o.tilt or rng:NextNumber(-12, 12)

	local ink = o.ink or math.max(3, px * 0.09)
	local shadow = Comic.label(holder, text, Comic.Display, px, Comic.Ink)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(math.ceil(px * 0.06), math.ceil(px * 0.08))
	local shadowStroke = Comic.ink(shadow, ink)
	local label = Comic.label(holder, text, Comic.Display, px, color)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 2
	local stroke = Comic.ink(label, ink)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.25
	scale.Parent = holder
	tween(scale, 0.12, { Scale = 1.18 }, Enum.EasingStyle.Back)
	tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.12)
	tween(billboard, life, { StudsOffset = Vector3.new(side * 1.3, 0.6 + (o.rise or 2), 0) }, Enum.EasingStyle.Quad)
	local fadeAt = life * 0.65
	local fadeTime = life - fadeAt
	for _, obj in { label, shadow } do
		tween(obj, fadeTime, { TextTransparency = 1 }, Enum.EasingStyle.Linear, Enum.EasingDirection.In, fadeAt)
	end
	for _, s in { stroke, shadowStroke } do
		tween(s, fadeTime, { Transparency = 1 }, Enum.EasingStyle.Linear, Enum.EasingDirection.In, fadeAt)
	end
end

-- Bolsa barajada: nunca la misma palabra dos veces seguidas
local function wordBag(list: { string })
	local bag: { string } = {}
	local last: string? = nil
	return function(): string
		if #bag == 0 then
			for _, w in list do
				table.insert(bag, w)
			end
			for i = #bag, 2, -1 do
				local j = rng:NextInteger(1, i)
				bag[i], bag[j] = bag[j], bag[i]
			end
			if #bag > 1 and bag[#bag] == last then
				bag[#bag], bag[1] = bag[1], bag[#bag]
			end
		end
		local w = table.remove(bag) :: string
		last = w
		return w
	end
end

local nibbleWord = wordBag({ "¡ÑAM!", "¡ÑAC!", "¡CHOMP!", "¡CRUNCH!", "¡ÑOM!", "¡CROC!", "¡MUNCH!", "¡CRIC!" })
local critWord = wordBag({ "¡CRAC!", "¡ZASCA!", "¡KRAK!", "¡PUMBA!", "¡TOMA!" })
local finishWord = wordBag({ "¡ZAMPADA!", "¡A LA PANZA!", "¡GLUP!", "¡LIMPIA!", "¡NI LAS MIGAS!", "¡FUERA!" })
local smallFinishWord = wordBag({ "¡GLUP!", "¡PAF!", "¡PLOP!", "¡ÑAM!" })

---------------------------------------------------------------------------------------------------
-- Racha: el tono sube, las letras crecen y la hormiga deja estela. Al romperse, se nota.

local COMBO_TRAIL_AT = 5
local COMBO_FULL = 25 -- con esta racha el efecto ya está al máximo
local combo = 0
local comboPeak = 0
local lastBiteAt = -math.huge
local trail: Trail? = nil
local trailOwner: Model? = nil

local function comboBoost(): number
	return math.clamp(combo / COMBO_FULL, 0, 1)
end

local function comboColor(k: number): Color3
	if k < 0.5 then
		return Comic.Yellow:Lerp(ORANGE, k * 2)
	end
	return ORANGE:Lerp(Comic.Red, (k - 0.5) * 2)
end

local function ensureTrail(): Trail?
	local character = player.Character
	if not character then
		return nil
	end
	if trail and trailOwner == character and trail.Parent then
		return trail
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local scale = character:GetScale()
	local a0 = Instance.new("Attachment")
	a0.Name = "ComboTrailTop"
	a0.Position = Vector3.new(0, 0.5 * scale, 0.9 * scale)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "ComboTrailBottom"
	a1.Position = Vector3.new(0, -0.3 * scale, 0.9 * scale)
	a1.Parent = root
	local t = Instance.new("Trail")
	t.Name = "ComboTrail"
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.FaceCamera = true
	t.Lifetime = 0.35
	t.MinLength = 0.05
	t.LightEmission = 0.7
	t.LightInfluence = 0
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	t.Enabled = false
	t.Parent = root
	trail = t
	trailOwner = character
	return t
end

local function setTrail(on: boolean)
	local t = if on then ensureTrail() else trail
	if not t then
		return
	end
	if on then
		local k = comboBoost()
		local color = comboColor(k)
		t.Color = ColorSequence.new(WHITE, color)
		t.Lifetime = 0.25 + 0.3 * k
	end
	t.Enabled = on
end

local function breakCombo()
	local peak = comboPeak
	combo = 0
	comboPeak = 0
	setTrail(false)
	if peak < COMBO_TRAIL_AT then
		return
	end
	local origin = mouth()
	if origin then
		Fx.word(origin + Vector3.new(0, 2.5, 0), "Racha x" .. peak, Comic.Paper:Lerp(Comic.Ink, 0.35), 30, {
			tilt = rng:NextNumber(-20, -10),
			rise = -1.2,
			life = 0.7,
			side = 0,
			force = true,
		})
		Fx.crumbs(origin + Vector3.new(0, 1.5, 0), Comic.DirtLight, 5)
	end
	Sfx.pop(0.55, 0.35)
	task.delay(0.08, Sfx.pop, 0.45, 0.3)
end

local function watchCombo(now: number)
	if comboPeak > 0 and now - lastBiteAt > Config.Combo.Window then
		breakCombo()
	end
	if trail and trail.Enabled and trailOwner ~= player.Character then
		trail = nil
	end
end

---------------------------------------------------------------------------------------------------
-- Ráfagas: lo que daña a varias comidas a la vez se escalona unos milisegundos.

local volleyUntil = 0

-- Programa `fn` dentro de la ráfaga en curso: cada golpe sale `gap` s después del anterior.
function Fx.stagger(fn: () -> (), gap: number?)
	local now = os.clock()
	local at = math.max(now, volleyUntil)
	volleyUntil = at + (gap or 0.045)
	if at <= now then
		task.spawn(fn)
	else
		task.delay(at - now, fn)
	end
end

-- Golpe secundario sobre una comida (área, castas, aliadas): rayito desde `from`, aplastón,
-- chispas, migajas a tu boca y su número. Va escalonado dentro de la ráfaga.
function Fx.splash(model: Model?, position: Vector3, amount: number?, from: Vector3?, color: Color3?)
	Fx.stagger(function()
		if from then
			Fx.bolt(from, position + Vector3.new(0, 0.6, 0), { width = 0.45, color = Comic.Cyan, life = 0.16, forks = 0, ink = false })
		end
		if model and model.Parent then
			Fx.squash(model, 0.12, from)
		end
		Fx.sparks(position + Vector3.new(0, 0.8, 0), 5, Comic.Cyan)
		Fx.absorb(position + Vector3.new(0, 0.8, 0), color, 2, 0.32, 0.03)
		if amount and amount > 0 then
			Fx.number(position, amount, false, false)
		end
		Sfx.pop(rng:NextNumber(1.3, 1.6), 0.25)
	end)
end

---------------------------------------------------------------------------------------------------
-- Remate: estallido con anillo, destello, confeti de sus colores, trozos que vuelan a tu boca y
-- palabra grande. Todo crece con el tamaño de la comida.

local function finishBurst(position: Vector3, radius: number, color: Color3, colors: { Color3 }?, golden: boolean?, small: boolean?)
	local size = math.clamp(radius / 3, 0.5, 3)
	local ground = position - Vector3.new(0, 1, 0)
	local palette = colors or { color }
	if golden then
		palette = { GOLD, Comic.Yellow, WHITE }
	end
	Fx.ring(ground + Vector3.new(0, 0.2, 0), radius * 1.4 + 2 * size, Comic.Yellow, 0.35 + 0.1 * size)
	if not small and size > 1.2 then
		task.delay(0.08, Fx.ring, ground + Vector3.new(0, 0.25, 0), radius * 1.1 + 1.5 * size, Comic.Paper, 0.3)
	end
	Fx.flash(position + Vector3.new(0, radius * 0.4, 0), palette[1], 2 + radius * 0.9)
	local center = position + Vector3.new(0, radius * 0.3, 0)
	Fx.confetti(center, palette, math.floor((if small then 6 else 10) + 6 * size), 0.8 + 0.3 * size)
	Fx.absorb(center, palette[1], math.floor((if small then 2 else 3) + 2 * size), 0.42 + 0.12 * size, 0.04)
	Fx.sparks(center, math.floor(6 + 4 * size), palette[1])
	if small then
		Fx.word(center + Vector3.new(0, 1.5, 0), smallFinishWord(), Comic.Paper, 30, { life = 0.5 })
		return
	end
	Fx.word(center + Vector3.new(0, 2 + radius * 0.3, 0), finishWord(), Comic.Yellow, 44 + 10 * size, {
		life = 0.75,
		rise = 2.5,
		force = true,
	})
	Fx.shake(0.18 + 0.12 * size)
	Fx.kick(2 + 1.2 * size)
	AntAnim.hitStop(0.05 + 0.02 * size, true)
	Sfx.finish(size)
end

-- Remate de cualquier comida conocida en `position` (para otros módulos: castas, aliadas…).
function Fx.finish(position: Vector3, small: boolean?)
	local g = goneAt(position, 1)
	if g then
		finishBurst(position, g.radius, g.color, g.colors, g.golden, small)
	else
		finishBurst(position, 2, lastFoodColor or Comic.Crumb, nil, false, small)
	end
end

---------------------------------------------------------------------------------------------------
-- Mordisco confirmado por el servidor (suceso "Bite").

-- Impacto de un mordisco confirmado por el servidor (evento "Bite"). goldFood: la comida era
-- dorada (número y migajas de oro, sin el temblor del mordisco dorado).
function Fx.biteImpact(position: Vector3, taken: number, finished: boolean?, crit: boolean?, golden: boolean?, goldFood: boolean?)
	if typeof(position) ~= "Vector3" then
		return
	end
	local origin = mouth()
	if not origin or (origin - position).Magnitude > 30 then
		origin = position
	end
	local gold = golden == true or goldFood == true
	local boost = comboBoost()
	Fx.number(origin, tonumber(taken) or 0, crit == true, gold, boost)
	local tint = if gold then GOLD else nil
	-- Unas saltan y caen, otras vuelan en arco a la boca
	Fx.crumbs(position + Vector3.new(0, 0.5, 0), tint, if crit or gold then 4 else 2)
	Fx.absorb(position + Vector3.new(0, 0.5, 0), tint, if crit or gold then 4 else 2, 0.34, 0.035)
	if golden == true then
		Fx.shake(0.6)
	elseif crit then
		Fx.shake(0.42)
	elseif finished then
		Fx.shake(0.22)
	else
		Fx.shake(0.1 + 0.1 * boost)
	end
end

-- Todo el mordisco: impacto, palabra, sonido, marca, racha, remate y ráfaga de área.
-- a..g como llegan del servidor: posición, trozos, ¿acabada?, ¿crítico?, racha, ¿mordisco
-- dorado?, ¿comida dorada?
function Fx.bite(position: Vector3, taken: number, finished: boolean?, crit: boolean?, streak: number?, golden: boolean?, goldFood: boolean?)
	if typeof(position) ~= "Vector3" then
		return
	end
	local now = os.clock()
	local newCombo = tonumber(streak) or 0
	if newCombo < combo and comboPeak >= COMBO_TRAIL_AT then
		breakCombo()
	end
	combo = newCombo
	comboPeak = math.max(comboPeak, combo)
	lastBiteAt = now
	local boost = comboBoost()
	setTrail(combo >= COMBO_TRAIL_AT)

	local base = position - Vector3.new(0, 1, 0)
	local model, info = foodAt(base)
	local mainGone = if finished then goneAt(base, 1) else nil

	Fx.biteImpact(position, taken, finished, crit, golden, goldFood)

	-- Parada de impacto y golpe de FOV: cortos en un mordisco normal, más largos en un crítico
	if golden then
		AntAnim.hitStop(0.09, true)
		Fx.kick(4)
	elseif crit then
		AntAnim.hitStop(0.07, true)
		Fx.kick(3)
	else
		AntAnim.hitStop(0.035)
		Fx.kick(1 + 1.2 * boost)
	end

	-- La comida reacciona (si sigue viva): se aplasta más en un crítico y le queda la marca
	if model and model.Parent then
		if crit or golden then
			Fx.squash(model, 0.26)
		end
		biteMark(model, info)
	end

	local radius = (info and info.radius) or (mainGone and mainGone.radius) or 2
	local top = position + Vector3.new(0, radius * 0.5, 0)
	local pitch = 1 + 0.014 * math.min(combo, 30)
	if golden then
		Fx.slash(top, radius + 1, GOLD)
		Fx.flash(top, GOLD, 3 + radius)
		Fx.word(top + Vector3.new(0, 2, 0), "¡DORADO!", GOLD, 58, { life = 0.75, force = true })
		Fx.sparks(top, 16, GOLD)
		Sfx.bite(true)
		Sfx.pop(1.5, 0.4)
	elseif crit then
		Fx.slash(top, radius + 1)
		Fx.flash(top, WHITE, 2.5 + radius * 0.8)
		Fx.sparks(top, 10, Comic.Yellow)
		if not finished then -- si además la remata, manda la palabra del remate
			Fx.word(top + Vector3.new(0, 1.8, 0), critWord(), Comic.Yellow, 52 + 8 * boost, { life = 0.65, force = true })
		end
		Sfx.bite(true, pitch)
		Sfx.pop(1.8, 0.3)
	elseif not finished then
		local size = 28 + 18 * boost
		local color = if combo >= COMBO_TRAIL_AT then comboColor(boost) else Comic.Paper
		Fx.word(top + Vector3.new(0, 0.8, 0), nibbleWord(), color, size, { life = 0.5, rise = 1.8 })
		Sfx.bite(false, pitch)
	end

	if finished then
		local g = mainGone
		if g then
			finishBurst(position, g.radius, g.color, g.colors, g.golden or goldFood == true, false)
		else
			finishBurst(position, radius, lastFoodColor or Comic.Crumb, nil, goldFood == true, false)
		end
		Sfx.bite(true, pitch)
	end

	-- Mordida en área: las demás comidas que perdieron vida a la vez, en ráfaga, más cercanas primero
	local area = State.stats().areaRadius or 0
	if area > 0 then
		local hits = {}
		for other, otherInfo in foodInfo do
			if other ~= model and now - otherInfo.dropAt < 0.4 then
				local gap = ((otherInfo.pos - base) * Vector3.new(1, 0, 1)).Magnitude - otherInfo.radius
				if gap <= area + 1 then
					table.insert(hits, { model = other, info = otherInfo, gap = gap })
				end
			end
		end
		table.sort(hits, function(x, y)
			return x.gap < y.gap
		end)
		for i, hit in hits do
			if i > 8 then
				break
			end
			Fx.splash(hit.model, hit.info.pos + Vector3.new(0, 0.5, 0), hit.info.drop, position, hit.info.color)
		end
		-- Las que se acabaron por el área: remate pequeño, también en la ráfaga
		local finishedNear = 0
		for i = #gone, 1, -1 do
			local g = gone[i]
			if now - g.at < 0.4 and g ~= mainGone then
				local gap = ((g.pos - base) * Vector3.new(1, 0, 1)).Magnitude - g.radius
				if gap <= area + 1 then
					finishedNear += 1
					if finishedNear > 3 then
						break
					end
					Fx.stagger(function()
						finishBurst(g.pos + Vector3.new(0, 1, 0), g.radius, g.color, g.colors, g.golden, true)
					end)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Carga llena al entregar: el servidor pone Carry a 0 justo antes de avisar del depósito, así que
-- se recuerda cómo iba la carga antes de vaciarse.

local prevCarry = 0
local dropWasFull = false
local dropFraction = 0
local dropAt = -math.huge

local function watchCarry()
	prevCarry = tonumber(player:GetAttribute("Carry")) or 0
	player:GetAttributeChangedSignal("Carry"):Connect(function()
		local carry = tonumber(player:GetAttribute("Carry")) or 0
		if carry < prevCarry then
			local capacity = tonumber(player:GetAttribute("Capacity")) or math.huge
			dropWasFull = prevCarry >= capacity
			dropFraction = math.clamp(prevCarry / math.max(capacity, 1), 0, 1)
			dropAt = os.clock()
		end
		prevCarry = carry
	end)
end

-- Entrega en el hormiguero (evento "Deposit"): chorro de migajas de la hormiga a la boca del
-- hormiguero, el hormiguero se las traga (aplastón), anillo en la boca y palabra según el tamaño
-- de la entrega. credited (opcional): lo acreditado, para la palabra.
function Fx.deposit(position: Vector3, doubled: boolean?, credited: number?)
	local recent = os.clock() - dropAt < 1.5
	local full = (recent and dropWasFull)
		or (tonumber(player:GetAttribute("Carry")) or 0) >= (tonumber(player:GetAttribute("Capacity")) or math.huge)
	local fraction = if full then 1 elseif recent then dropFraction else 0.5

	local hill = State.hill()
	local hole = if hill then hill:GetPivot().Position else (if typeof(position) == "Vector3" then position - Vector3.new(0, 9, 0) else nil)
	-- Entrega en un hormiguero de zona: el chorro va a ese montículo, no al de casa
	if hill and typeof(position) == "Vector3" and ((position - hill:GetPivot().Position) * Vector3.new(1, 0, 1)).Magnitude > 30 then
		hole = position - Vector3.new(0, 9 * Config.Depot.Scale, 0)
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not hole or not root or not root:IsA("BasePart") then
		Fx.shake(if full then 0.55 elseif doubled then 0.35 else 0.15)
		return
	end
	local start = root.Position + Vector3.new(0, 1.5, 0)
	local distance = (hole - start).Magnitude
	local tint = lastFoodColor or Comic.Crumb
	local count = math.floor(8 + 16 * fraction)
	local spread = 0.3 + 0.15 * fraction
	for i = 1, count do
		local from = start + Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(0, 0.8), rng:NextNumber(-0.8, 0.8))
		local to = hole + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		local c = launchCrumb(from, if i % 4 == 0 then Comic.Crumb else tint, rng:NextNumber(0.3, 0.55), rng:NextNumber(0.38, 0.5), (i - 1) / count * spread)
		if c then
			c.p1 = to
			c.ctrl = (from + to) / 2
				+ Vector3.new(rng:NextNumber(-2, 2), 5 + distance * 0.35 + rng:NextNumber(0, 2), rng:NextNumber(-2, 2))
		end
	end

	-- Cuando llegan las migajas: el hormiguero traga, anillo en la boca, palabra y golpe
	local arrive = 0.42 + spread * 0.5
	task.delay(arrive, function()
		local mouthOfHill = hole + Vector3.new(0, 1, 0)
		if hill and hill.Parent then
			-- Poca fuerza: puede que estés de pie encima del montículo
			-- (golpe "desde" su propio centro: se aplasta recto, sin inclinarse)
			Fx.squash(hill, 0.05 + 0.04 * fraction, hill:GetPivot().Position, 400)
		end
		Fx.ring(hole + Vector3.new(0, 0.6, 0), 5 + 5 * fraction, if doubled then Comic.Yellow else Comic.Cyan, 0.4)
		Fx.sparks(mouthOfHill + Vector3.new(0, 2, 0), math.floor(4 + 8 * fraction), if doubled then Comic.Yellow else Comic.Cyan)
		Fx.shake(if full then 0.5 elseif doubled then 0.35 else 0.15)
		local text
		if doubled then
			text = "¡DOBLE!"
		elseif full then
			text = "¡CARGAZO!"
		elseif fraction >= 0.5 then
			text = "¡BUENA CARGA!"
		else
			text = "¡BIEN!"
		end
		if credited then
			text ..= "\n+" .. Format.short(credited)
		end
		Fx.word(
			(if typeof(position) == "Vector3" then position else hole + Vector3.new(0, 9, 0)),
			text,
			if doubled then Comic.Yellow elseif full then ORANGE else Comic.Cyan,
			38 + 18 * fraction + (if doubled then 8 else 0),
			{ life = 0.9, rise = 2.5, side = 0, force = true }
		)
		if full or doubled then
			Fx.flash(mouthOfHill + Vector3.new(0, 2, 0), if doubled then Comic.Yellow else Comic.Cyan, 6)
		end
	end)
end

local function startImpact()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "FxWorld"
	fxFolder.Parent = Workspace

	for _ = 1, NUMBER_POOL do
		table.insert(numbers, makeNumber())
	end
	local folder = Instance.new("Folder")
	folder.Name = "FxCrumbs"
	folder.Parent = Workspace
	for _ = 1, CRUMB_POOL do
		table.insert(crumbs, makeCrumb(folder))
	end
	for _ = 1, MARK_POOL do
		table.insert(marks, makeMark(folder))
	end

	-- Emisor de chispas compartido (se mueve a cada punto y dispara)
	local attachment = Instance.new("Attachment")
	attachment.Name = "FxSparks"
	attachment.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.18, 0.32)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 6
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) })
	emitter.Parent = attachment
	sparkAttachment = attachment
	sparkEmitter = emitter

	watchCarry()

	-- Registro de la comida
	task.spawn(function()
		local foods = Workspace:WaitForChild("Food", 180)
		if not foods then
			return
		end
		for _, child in foods:GetChildren() do
			track(child)
		end
		foods.ChildAdded:Connect(track)
		foods.ChildRemoved:Connect(untrack)
	end)

	local cameraPriority = Enum.RenderPriority.Camera.Value
	RunService:BindToRenderStep("CrunchShakeUndo", cameraPriority - 1, undoShake)
	RunService:BindToRenderStep("CrunchShake", cameraPriority + 1, applyShake)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		updateSquashes(now)
		updateNumbers(now)
		updateCrumbs(now)
		updateMarks(now)
		watchCombo(now)
	end)
end

function Fx.start()
	overlay = Instance.new("ScreenGui")
	overlay.Name = "FxOverlay"
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = -5
	overlay.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	if Hud.compact() then
		-- Celular: menos palabras sueltas; la pequeña del mordisco ya no sale en cada uno
		wordBudget = bucket(1.5, 2)
	end

	-- Viñeta de trama en los bordes: da el aire de dibujo animado antiguo
	local vignette = Comic.image(overlay, Assets.Vignette)
	vignette.ScaleType = Enum.ScaleType.Stretch
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.ImageTransparency = 0.62

	speedLines = Comic.image(overlay, Assets.SpeedLines)
	speedLines.ScaleType = Enum.ScaleType.Stretch
	speedLines.AnchorPoint = Vector2.new(0.5, 0.5)
	speedLines.Position = UDim2.fromScale(0.5, 0.5)
	speedLines.Size = UDim2.fromScale(1.25, 1.25)
	speedLines.ImageTransparency = 1

	startImpact()
end

-- Líneas de velocidad de manga durante `seconds`. Giran a saltos 3 veces por segundo (antes 14:
-- parpadeaba); con Movimiento suave no giran y entran y salen con un fundido.
-- Si ya hay unas puestas, solo se alarga su final: un solo bucle, y no se apagan antes de tiempo.
local speedUntil = 0
local speedFade: Tween? = nil

function Fx.speed(seconds: number)
	local finish = os.clock() + seconds
	local running = speedUntil > os.clock()
	speedUntil = math.max(speedUntil, finish)
	if speedFade then
		speedFade:Cancel() -- un fundido de salida a medias no debe apagar las nuevas
		speedFade = nil
	end
	if calm() then
		TweenService:Create(speedLines, TweenInfo.new(0.25), { ImageTransparency = 0.5 }):Play()
	else
		speedLines.ImageTransparency = 0.25
	end
	if running then
		return
	end
	task.spawn(function()
		while os.clock() < speedUntil do
			if not calm() then
				speedLines.Rotation = rng:NextInteger(0, 11) * 30
			end
			task.wait(math.min(0.33, math.max(speedUntil - os.clock(), 0.03)))
		end
		speedFade = TweenService:Create(speedLines, TweenInfo.new(if calm() then 0.35 else 0.2), { ImageTransparency = 1 })
		speedFade:Play()
	end)
end

-- Palabra pequeña que sube y se desvanece. Una por mordisco.
function Fx.nibble(position: Vector3)
	nibbleIndex = nibbleIndex % #NIBBLES + 1
	local fit = Hud.fxScale()
	local part = anchorAt(position + Vector3.new(0, 1.2, 0), 0.6)
	local billboard = billboardOn(part, 120 * fit, 48 * fit)

	local label = Comic.label(billboard, NIBBLES[nibbleIndex], Comic.Display, math.floor(30 * fit), Comic.Paper)
	label.Size = UDim2.fromScale(1, 1)
	label.Rotation = rng:NextNumber(-16, 16)
	local stroke = Comic.ink(label, 3)

	local rise = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, rise, { StudsOffset = Vector3.new(rng:NextNumber(-1, 1), 2.6, 0) }):Play()
	local fade = TweenInfo.new(0.2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.3)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
end

-- Estallido con texto grande. Para momentos que importan, pero como floritura: el diámetro
-- pedido se reduce a ~62 % y nunca pasa de BURST_MAX px (a 1000 px de alto de pantalla; escala con
-- ella), y todo dura menos de 0.9 s.
-- El texto lleva su propia tinta: se lee aunque la imagen del estallido no llegue a cargar.
local BURST_MAX = 170
local BURST_MIN = 96

function Fx.burst(position: Vector3, text: string, color: Color3, diameter: number?)
	local size = math.floor(math.clamp((diameter or 220) * 0.62, BURST_MIN, BURST_MAX) * Hud.fxScale())
	local part = anchorAt(position + Vector3.new(0, 2.5, 0), 0.8)
	local billboard = billboardOn(part, size + 16, size + 16)

	local burst = Comic.burst(billboard, size, color)
	burst.Rotation = rng:NextNumber(-14, 14)

	-- Textos largos ("¡HUEVO DORADO!") encogen para caber dentro del estallido
	local label = Comic.label(burst, text, Comic.Display, size * 0.22, Comic.Ink)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.78, 0.6)
	label.TextScaled = true
	label.Rotation = -burst.Rotation - 6
	local outline = Comic.ink(label, 2)
	outline.Color = Comic.Paper
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = math.floor(size * 0.22)
	limit.Parent = label

	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = burst

	TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(0.55, function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
	end)
end

-- Trozo que sale volando cuando la comida pierde una pieza. Con una colonia grande comiendo
-- cerca puede haber cientos de piezas por segundo: el cubo de fichas lo deja en ~30 por segundo.
function Fx.chunk(piece: BasePart)
	if not spend(chunkBudget) then
		return
	end

	local side = math.clamp(math.min(piece.Size.X, piece.Size.Y, piece.Size.Z) * 0.6, 0.35, 1.6)
	local bit = Instance.new("Part")
	bit.Shape = Enum.PartType.Ball
	bit.Size = Vector3.new(side, side, side)
	bit.Color = piece.Color
	bit.Material = Enum.Material.SmoothPlastic
	bit.CanCollide = false
	bit.CanQuery = false
	bit.CanTouch = false
	bit.CastShadow = false
	bit.CFrame = piece.CFrame
	bit.Parent = Workspace
	bit.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(22, 36), rng:NextNumber(-14, 14))
	bit.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
	TweenService:Create(bit, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.zero }):Play()
	Debris:AddItem(bit, 0.6)
end

-- Viñeta a pantalla completa: líneas de velocidad, estallido y la Jalea ganada.
-- Con Movimiento suave: la misma viñeta quieta (sin líneas ni golpe) que entra y sale con un fundido.
function Fx.rebirth(gain: number)
	local still = calm()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RebirthSplash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer.PlayerGui

	local back: GuiObject
	if still then
		-- Un CanvasGroup funde la viñeta entera (fondo, estallido y textos) de una vez
		local group = Instance.new("CanvasGroup")
		group.BackgroundColor3 = Comic.Yellow
		group.BorderSizePixel = 0
		group.GroupTransparency = 1
		group.Parent = gui
		back = group
	else
		back = Comic.frame(gui, Comic.Yellow)
	end
	back.Size = UDim2.fromScale(1, 1)

	local lines = Comic.image(back, Assets.SpeedLines)
	lines.ScaleType = Enum.ScaleType.Stretch
	lines.AnchorPoint = Vector2.new(0.5, 0.5)
	lines.Position = UDim2.fromScale(0.5, 0.5)
	lines.Size = UDim2.fromScale(1.3, 1.3)

	local holder = Comic.frame(back)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(620, 620)
	Comic.autoScale(holder)

	local burst = Comic.burst(holder, 620, Comic.Paper)
	local pop = Instance.new("UIScale")
	pop.Parent = burst

	local title = Comic.label(burst, "¡ENJAMBRE!", Comic.Display, 110, Comic.Red)
	title.Size = UDim2.new(1, 0, 0, 120)
	title.Position = UDim2.new(0, 0, 0.5, -110)
	title.Rotation = -5
	Comic.ink(title, 6)

	local sub = Comic.label(burst, "+" .. gain .. " de jalea real", Comic.Display, 56, Comic.Ink)
	sub.Size = UDim2.new(1, 0, 0, 60)
	sub.Position = UDim2.new(0, 0, 0.5, 20)
	sub.Rotation = -5

	if still then
		lines.Visible = false
		local fade = TweenInfo.new(0.4, Enum.EasingStyle.Sine)
		TweenService:Create(back, fade, { GroupTransparency = 0 }):Play()
		task.delay(1.6, function()
			TweenService:Create(back, fade, { GroupTransparency = 1 }):Play()
			task.wait(0.45)
			gui:Destroy()
		end)
		return
	end
	Comic.punch(pop, 0.2)
	task.spawn(function()
		for _ = 1, 16 do -- ~1.4 s de viñeta: celebra sin tapar el juego mucho rato
			lines.Rotation = rng:NextInteger(0, 11) * 30
			task.wait(0.09)
		end
		local out = TweenInfo.new(0.3)
		TweenService:Create(back, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(lines, out, { ImageTransparency = 1 }):Play()
		TweenService:Create(pop, out, { Scale = 0 }):Play()
		task.wait(0.35)
		gui:Destroy()
	end)
end

return Fx
