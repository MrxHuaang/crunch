-- Efectos: palabritas al morder, estallidos de onomatopeya, trozos que saltan,
-- líneas de velocidad y la viñeta de pantalla completa del rebirth.
-- Impacto al morder: temblor de cámara, comida que se aplasta y rebota, números que saltan
-- y migajas. Todo con presupuesto fijo: piscinas de instancias y cubos de fichas.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Format = require(ReplicatedStorage.Shared.Format)
local Comic = require(script.Parent.Comic)
local State = require(script.Parent.State)

local Fx = {}

local rng = Random.new()
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 184, 28)
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
local crumbBudget = bucket(40, 16) -- migajas de tus mordiscos
local NIBBLES = { "ñam", "ñam", "chomp", "ñac" }
local nibbleIndex = 0

local overlay: ScreenGui
local speedLines: ImageLabel

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
	part.Parent = Workspace
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

---------------------------------------------------------------------------------------------------
-- Temblor de cámara por "trauma": cada golpe suma trauma (0..1), que decae solo. La sacudida es
-- trauma² con ruido suave en giro y un pelín de desplazamiento.
-- Se aplica justo DESPUÉS de que la cámara de Roblox se actualice y se deshace justo ANTES de su
-- siguiente actualización, devolviendo el CFrame exacto que ella dejó: el módulo de cámara nunca ve
-- la sacudida, así que no pelea con el ratón ni acumula deriva. Si otro script movió la cámara entre
-- medias (el CFrame ya no es el que pusimos), no se toca.

local SHAKE_DECAY = 1.6 -- trauma por segundo
local SHAKE_PITCH = math.rad(1.6)
local SHAKE_YAW = math.rad(1.6)
local SHAKE_ROLL = math.rad(2.4)
local SHAKE_MOVE = 0.12

local trauma = 0
local shakeBase: CFrame? = nil
local shakeWritten: CFrame? = nil

-- Sacude la cámara. 0.2 suave, 0.45 fuerte, 0.6+ muy fuerte. Se suma y satura en 1.
function Fx.shake(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

local function undoShake()
	local base, written = shakeBase, shakeWritten
	shakeBase, shakeWritten = nil, nil
	local camera = Workspace.CurrentCamera
	if base and camera and camera.CFrame == written then
		camera.CFrame = base
	end
end

local function applyShake(dt: number)
	if trauma <= 0 then
		return
	end
	trauma = math.max(0, trauma - SHAKE_DECAY * dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
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

local NUMBER_POOL = 12
local NUMBER_LIFE = 0.75
local numbers: { NumberPop } = {}
local nextNumber = 0

local function makeNumber(): NumberPop
	-- Bajo Terrain (que está en el origen) la posición local de un Attachment es la del mundo
	local anchor = Instance.new("Attachment")
	anchor.Name = "FxNumber"
	anchor.Parent = Workspace.Terrain

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 64)
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
function Fx.number(position: Vector3, amount: number, crit: boolean?, golden: boolean?)
	if #numbers == 0 then
		return
	end
	nextNumber = nextNumber % #numbers + 1
	local n = numbers[nextNumber]
	local big = crit or golden

	n.label.Text = Format.short(amount) .. (if big then "!" else "")
	n.label.TextColor3 = if golden then GOLD elseif crit then Comic.Yellow else Comic.Paper
	n.label.TextSize = if golden then 44 elseif crit then 40 else 30
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

type Crumb = {
	part: Part,
	active: boolean,
	shown: boolean,
	born: number,
	life: number,
	p0: Vector3,
	velocity: Vector3,
	ctrl: Vector3?, -- con ctrl y p1 sigue una curva (de la hormiga al hormiguero)
	p1: Vector3?,
	size: Vector3,
	spin: Vector3,
}

local CRUMB_POOL = 48
local GRAVITY = Vector3.new(0, -70, 0)
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
		ctrl = nil,
		p1 = nil,
		size = part.Size,
		spin = Vector3.zero,
	}
end

local function launchCrumb(p0: Vector3, color: Color3, side: number, life: number, delay: number): Crumb?
	if #crumbs == 0 then
		return nil
	end
	nextCrumb = nextCrumb % #crumbs + 1
	local c = crumbs[nextCrumb]
	c.part.Transparency = 1
	c.part.Color = color
	c.size = Vector3.new(side, side * rng:NextNumber(0.7, 1), side * rng:NextNumber(0.8, 1.2))
	c.part.Size = c.size
	c.active = true
	c.shown = false
	c.born = os.clock() + delay
	c.life = life
	c.p0 = p0
	c.velocity = Vector3.zero
	c.ctrl = nil
	c.p1 = nil
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
		local c = launchCrumb(position, tint, rng:NextNumber(0.2, 0.38), rng:NextNumber(0.4, 0.55), 0)
		if c then
			c.velocity = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(14, 24), rng:NextNumber(-9, 9))
		end
	end
end

local function updateCrumbs(now: number)
	table.clear(crumbParts)
	table.clear(crumbFrames)
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
		local ctrl, p1 = c.ctrl, c.p1
		if ctrl and p1 then
			local e = u * u * (3 - 2 * u) * 0.35 + u * 0.65
			local a = 1 - e
			pos = c.p0 * (a * a) + ctrl * (2 * a * e) + p1 * (e * e)
		else
			pos = c.p0 + c.velocity * t + GRAVITY * (0.5 * t * t)
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
	pivot: CFrame,
	pieces: { SquashPiece },
	born: number,
	from: number,
	amount: number,
}

local SQUASH_DOWN = 0.12
local SQUASH_BACK = 0.18
local SQUASH_AMOUNT = 0.16
local SQUASH_MAX_PIECES = 160
local SQUASH_MAX_ACTIVE = 4

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
	-- Muelle: vuelve, se pasa (se estira) y se asienta
	return s.amount * math.cos(u * math.pi * 1.5) * (1 - u)
end

local function axisFactor(weight: number, sy: number, sh: number): number
	return math.sqrt((1 - weight) * sh * sh + weight * sy * sy)
end

-- a = nil restaura los originales exactos
local function poseSquash(s: Squash, a: number?)
	local sy, sh = 1, 1
	if a then
		sy = 1 - a
		sh = 1 + a * 0.5
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
		table.insert(moveParts, part)
		table.insert(moveFrames, p.cf.Rotation + pos)
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

-- La comida que acabas de morder se aplasta (~0,12 s) y rebota (~0,18 s).
function Fx.squash(model: Instance?)
	if not model or not model:IsA("Model") or not model.Parent then
		return
	end
	local color = model:GetAttribute("Color")
	if typeof(color) == "Color3" then
		lastFoodColor = color
	end

	local now = os.clock()
	local existing = squashes[model]
	if existing then
		-- Ya está botando: la curva sigue desde donde va, con las mismas poses originales
		existing.from = squashCurve(existing, now - existing.born) or 0
		existing.born = now
		return
	end
	if squashCount >= SQUASH_MAX_ACTIVE then
		return
	end

	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 or #parts > SQUASH_MAX_PIECES then
		return
	end

	local pivot = model:GetPivot()
	local pieces: { SquashPiece } = {}
	for _, part in parts do
		local resize, cylinder = resizable(part)
		local weights: Vector3? = nil
		if resize then
			local rel = pivot:ToObjectSpace(part.CFrame)
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
	squashes[model] = { model = model, pivot = pivot, pieces = pieces, born = now, from = 0, amount = SQUASH_AMOUNT }
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
-- Carga llena al entregar: el servidor pone Carry a 0 justo antes de avisar del depósito, así que
-- se recuerda cómo iba la carga antes de vaciarse.

local prevCarry = 0
local dropWasFull = false
local dropAt = -math.huge

local function watchCarry()
	prevCarry = tonumber(player:GetAttribute("Carry")) or 0
	player:GetAttributeChangedSignal("Carry"):Connect(function()
		local carry = tonumber(player:GetAttribute("Carry")) or 0
		if carry < prevCarry then
			local capacity = tonumber(player:GetAttribute("Capacity")) or math.huge
			dropWasFull = prevCarry >= capacity
			dropAt = os.clock()
		end
		prevCarry = carry
	end)
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

-- Impacto de un mordisco confirmado por el servidor (evento "Bite").
function Fx.biteImpact(position: Vector3, taken: number, finished: boolean?, crit: boolean?, golden: boolean?)
	if typeof(position) ~= "Vector3" then
		return
	end
	local origin = mouth()
	if not origin or (origin - position).Magnitude > 30 then
		origin = position
	end
	Fx.number(origin, tonumber(taken) or 0, crit == true, golden == true)
	Fx.crumbs(origin, if golden == true then GOLD else nil, if crit or golden then 4 else 2)
	if golden == true then
		Fx.shake(0.6)
	elseif crit then
		Fx.shake(0.42)
	elseif finished then
		Fx.shake(0.22)
	end
end

-- Entrega en el hormiguero (evento "Deposit"): ráfaga de migajas que caen en el agujero.
function Fx.deposit(position: Vector3, doubled: boolean?)
	local full = (os.clock() - dropAt < 1.5 and dropWasFull)
		or (tonumber(player:GetAttribute("Carry")) or 0) >= (tonumber(player:GetAttribute("Capacity")) or math.huge)
	Fx.shake(if full then 0.55 elseif doubled then 0.35 else 0.15)

	local hill = State.hill()
	local hole = if hill then hill:GetPivot().Position else (if typeof(position) == "Vector3" then position - Vector3.new(0, 9, 0) else nil)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not hole or not root or not root:IsA("BasePart") then
		return
	end
	local start = root.Position + Vector3.new(0, 1.5, 0)
	local distance = (hole - start).Magnitude
	local tint = lastFoodColor or Comic.Crumb
	local count = if full then 14 else 8
	for i = 1, count do
		local from = start + Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(0, 0.8), rng:NextNumber(-0.8, 0.8))
		local to = hole + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		local c = launchCrumb(from, tint, rng:NextNumber(0.28, 0.5), rng:NextNumber(0.4, 0.55), (i - 1) / count * 0.25)
		if c then
			c.p1 = to
			c.ctrl = (from + to) / 2
				+ Vector3.new(rng:NextNumber(-2, 2), 5 + distance * 0.35 + rng:NextNumber(0, 2), rng:NextNumber(-2, 2))
		end
	end
end

local function startImpact()
	for _ = 1, NUMBER_POOL do
		table.insert(numbers, makeNumber())
	end
	local folder = Instance.new("Folder")
	folder.Name = "FxCrumbs"
	folder.Parent = Workspace
	for _ = 1, CRUMB_POOL do
		table.insert(crumbs, makeCrumb(folder))
	end
	watchCarry()

	local cameraPriority = Enum.RenderPriority.Camera.Value
	RunService:BindToRenderStep("CrunchShakeUndo", cameraPriority - 1, undoShake)
	RunService:BindToRenderStep("CrunchShake", cameraPriority + 1, applyShake)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		updateSquashes(now)
		updateNumbers(now)
		updateCrumbs(now)
	end)
end

function Fx.start()
	overlay = Instance.new("ScreenGui")
	overlay.Name = "FxOverlay"
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = -5
	overlay.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

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

-- Líneas de velocidad de manga durante `seconds`.
function Fx.speed(seconds: number)
	speedLines.ImageTransparency = 0.25
	task.spawn(function()
		local finish = os.clock() + seconds
		while os.clock() < finish do
			speedLines.Rotation = rng:NextInteger(0, 11) * 30
			task.wait(0.07)
		end
		TweenService:Create(speedLines, TweenInfo.new(0.2), { ImageTransparency = 1 }):Play()
	end)
end

-- Palabra pequeña que sube y se desvanece. Una por mordisco.
function Fx.nibble(position: Vector3)
	nibbleIndex = nibbleIndex % #NIBBLES + 1
	local part = anchorAt(position + Vector3.new(0, 1.2, 0), 0.6)
	local billboard = billboardOn(part, 120, 48)

	local label = Comic.label(billboard, NIBBLES[nibbleIndex], Comic.Display, 30, Comic.Paper)
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
-- pedido se reduce a ~62 % y nunca pasa de BURST_MAX px, y todo dura menos de 0.9 s.
local BURST_MAX = 170
local BURST_MIN = 96

function Fx.burst(position: Vector3, text: string, color: Color3, diameter: number?)
	local size = math.clamp(math.floor((diameter or 220) * 0.62), BURST_MIN, BURST_MAX)
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
function Fx.rebirth(gain: number)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RebirthSplash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.Parent = Players.LocalPlayer.PlayerGui

	local back = Comic.frame(gui, Comic.Yellow)
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
