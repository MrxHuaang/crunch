-- Emotes de memes (cliente): animación procedimental de cada emote sobre la hormiga de quien lo
-- hace (AntAnim.override), accesorios de piezas redondeadas soldados al rig (van dentro del modelo,
-- así el contorno de tinta del personaje también los bordea), carteles y onomatopeyas de cómic en
-- el mundo y sonidos hechos con Sfx variando tono y ritmo.
--
-- Rueda: mantén Y (o el botón redondo en táctil) y suelta sobre un hueco. 8 huecos por página; la
-- página 1 es la tuya (se elige en el álbum) y las siguientes traen el resto de lo que tienes. Se
-- pasa de página con la rueda del ratón, pasando el puntero por la pestaña de abajo o deslizando
-- en táctil. Tocar Y sin elegir nada abre el álbum.
--
-- Álbum: cromos de cada emote; los que faltan salen en silueta con cómo conseguirlos. Tocar un
-- cromo hace que tu hormiga lo ensaye (solo en tu pantalla). Arriba, la rueda: toca un hueco y luego
-- un cromo (o arrastra el cromo al hueco).
--
-- Todas lo ven: el servidor valida y reenvía "Play"; cada cliente anima esa hormiga. Moverse corta el
-- emote (cada cliente lo ve solo), morder o pulsar otra vez lo corta para todas (servidor "Stop").
-- Si la hormiga se reconstruye a mitad (LookVersion), el emote se corta y AntAnim vuelve a la pose
-- de reposo sin soldaduras torcidas.

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AntModel = require(ReplicatedStorage.Shared.AntModel)
local Defs = require(ReplicatedStorage.Shared.Emotes)
local Format = require(ReplicatedStorage.Shared.Format)
local AntAnim = require(script.Parent.AntAnim)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Emotes = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local rng = Random.new()
local remote: RemoteEvent? = nil

local FLAT = Vector3.new(1, 0, 1)
local SEEN = 150 -- más lejos de la cámara no se anima el emote de otra
local HEAR = 70 -- más lejos no suena
local FADE_IN = 0.14
local FADE_OUT = 0.25
local GREEN = Color3.fromRGB(70, 200, 90)
local PINK = Color3.fromRGB(255, 120, 200)
local ORANGE = Color3.fromRGB(255, 140, 40)
local CONFETTI = {
	Comic.Yellow, Comic.Red, Comic.Cyan, Comic.Green, PINK, Color3.fromRGB(150, 90, 230), Color3.new(1, 1, 1),
}

------------------------------------------------------------------------------------------------
-- Curvas
------------------------------------------------------------------------------------------------

local function seg(t: number, a: number, b: number): number
	return math.clamp((t - a) / (b - a), 0, 1)
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

local function easeOut(x: number): number
	return 1 - (1 - x) * (1 - x)
end

local function easeIn(x: number): number
	return x * x
end

-- Se pasa un poco y vuelve: el remate de los gestos
local function backOut(x: number): number
	if x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end
	local c = 1.70158
	local y = x - 1
	return 1 + (c + 1) * y * y * y + c * y * y
end

-- 0 → 1 → 0 entre a y b
local function bump(t: number, a: number, b: number): number
	if t <= a or t >= b then
		return 0
	end
	return math.sin((t - a) / (b - a) * math.pi)
end

-- Valor suavizado entre claves { { tiempo, valor }, ... }
local function keyed(t: number, keys: { { number } }): number
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t < b[1] then
			return a[2] + (b[2] - a[2]) * smooth((t - a[1]) / (b[1] - a[1]))
		end
	end
	return keys[#keys][2]
end

------------------------------------------------------------------------------------------------
-- Pose (ver emotePose en AntAnim): desplazamientos sobre la pose de reposo
------------------------------------------------------------------------------------------------

-- Dirección horizontal hacia fuera de cada fila de patas (lado derecho), sacada de AntModel
local OUT = {
	Vector3.new(0.894, 0, -0.447),
	Vector3.new(0.998, 0, 0.064),
	Vector3.new(0.902, 0, 0.432),
}

local function sideOf(i: number): number
	return if i % 2 == 1 then -1 else 1
end

-- Pata i (1 delantera izq, 2 delantera der, 3/4 medias, 5/6 traseras): `swing` la lleva adelante,
-- `lift` la levanta, `knee` dobla la rodilla (negativo la estira; -1.6 ≈ recta)
local function leg(p, i: number, swing: number, lift: number, knee: number?)
	local s = sideOf(i)
	local o = OUT[(i + 1) // 2]
	local axis = Vector3.new(o.X * s, 0, o.Z).Unit:Cross(Vector3.yAxis)
	p.legs[i] = CFrame.Angles(0, s * swing, 0) * CFrame.fromAxisAngle(axis, lift)
	p.knees[i] = knee or 0
end

-- Antena i (1 izq, 2 der): `up` la levanta, `out` la abre hacia fuera, `flex` dobla el codo
-- (negativo lo estira), `sway` la gira a los lados
local function antenna(p, i: number, up: number, out: number, flex: number?, sway: number?)
	local s = if i == 1 then -1 else 1
	p.antennae[i] = CFrame.Angles(up, sway or 0, -s * out)
	p.elbows[i] = flex or 0
end

local function antennae(p, up: number, out: number, flex: number?, sway: number?)
	antenna(p, 1, up, out, flex, sway)
	antenna(p, 2, up, out, flex, sway)
end

-- Cuerpo entero (escala 1, espacio de la raíz). rx en + levanta el morro; rz en - lo tumba a la derecha.
local function body(p, x: number, y: number, z: number, rx: number?, ry: number?, rz: number?, pivot: Vector3?)
	local rot = CFrame.Angles(rx or 0, ry or 0, rz or 0)
	if pivot then
		p.body = CFrame.new(x, y, z) * CFrame.new(pivot) * rot * CFrame.new(-pivot)
	else
		p.body = CFrame.new(x, y, z) * rot
	end
end

-- Erguirse sobre las patas de atrás (k 0..1): el morro sube, el abdomen se recoge para no rozar
local REAR_PIVOT = Vector3.new(0, -1.1, 1.3)
local function rear(p, k: number, extraY: number?)
	body(p, 0, 0.25 * k + (extraY or 0), 0, 0.5 * k, 0, 0, REAR_PIVOT)
	p.abdomen = CFrame.Angles(-0.35 * k, 0, 0)
	leg(p, 5, 0, -0.25 * k, -0.25 * k)
	leg(p, 6, 0, -0.25 * k, -0.25 * k)
	leg(p, 3, 0.15 * k, -0.1 * k, 0)
	leg(p, 4, 0.15 * k, -0.1 * k, 0)
end

-- Mezcla toda la pose con el reposo (w = 1 pose entera, 0 reposo)
local function fade(p, w: number)
	if w >= 1 then
		return
	end
	w = math.max(w, 0)
	local I = CFrame.identity
	p.body = I:Lerp(p.body, w)
	p.head = I:Lerp(p.head, w)
	p.abdomen = I:Lerp(p.abdomen, w)
	for i, cf in p.legs do
		p.legs[i] = I:Lerp(cf, w)
	end
	for i, cf in p.antennae do
		p.antennae[i] = I:Lerp(cf, w)
	end
	for i, v in p.knees do
		p.knees[i] = v * w
	end
	for i, v in p.elbows do
		p.elbows[i] = v * w
	end
	p.jaw *= w
end

------------------------------------------------------------------------------------------------
-- Accesorios y carteles
------------------------------------------------------------------------------------------------

local function track(ctx, instance: Instance)
	table.insert(ctx.trash, instance)
	return instance
end

-- Pieza redondeada: "ball" (elipsoide), "rod" (cilindro a lo largo de X) o "block" (solo píxeles)
local function piece(ctx, shape: string, size: Vector3, color: Color3, glow: boolean?): BasePart
	local part = Instance.new("Part")
	part.Name = "EmoteProp"
	part.Size = size * ctx.s
	part.Color = color
	part.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif shape == "rod" then
		part.Shape = Enum.PartType.Cylinder
	end
	part.Parent = ctx.props
	return part
end

local function at(ctx, x: number, y: number, z: number): CFrame
	return CFrame.new(x * ctx.s, y * ctx.s, z * ctx.s)
end

-- Suelda `part` a `host` con C0 (posición ya escalada); se puede animar luego el C0
local function stick(part: BasePart, host: BasePart, c0: CFrame): Weld
	local weld = Instance.new("Weld")
	weld.Part0 = host
	weld.Part1 = part
	weld.C0 = c0
	weld.Parent = part
	part.CFrame = host.CFrame * c0
	return weld
end

local function fixed(part: BasePart, cf: CFrame): BasePart
	part.Anchored = true
	part.CFrame = cf
	return part
end

local function billboard(adornee: Instance, offset: Vector3, w: number, h: number): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "EmoteSign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(w, h)
	gui.StudsOffsetWorldSpace = offset
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	return gui
end

local function popIn(object: GuiObject)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = object
	TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Cartel de cómic en el mundo (papel, tinta, letras Bangers). Devuelve el gui y la etiqueta.
local function sign(ctx, host: Instance, offset: Vector3, text: string, color: Color3, px: number, life: number?): (BillboardGui, TextLabel)
	local len = utf8.len(text) or #text
	local w = math.clamp(len * px * 0.58 + 36, 64, 400)
	local gui = billboard(host, offset * ctx.s, w, px + 28)
	local box = Comic.frame(gui, Comic.Paper)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.new(1, -8, 1, -8)
	box.Rotation = rng:NextNumber(-5, 5)
	Comic.round(box, 10)
	Comic.ink(box, 3, true)
	local label = Comic.label(box, text, Comic.Display, px, color)
	label.Size = UDim2.fromScale(1, 1)
	Comic.ink(label, 2.5)
	popIn(box)
	track(ctx, gui)
	if life then
		Debris:AddItem(gui, life)
	end
	return gui, label
end

-- Bocadillo de habla (letra de texto, con cola) sobre la cabeza
local function say(ctx, text: string, life: number)
	local len = utf8.len(text) or #text
	local gui = billboard(ctx.head, Vector3.new(0, 3.4 * ctx.s, 0), math.clamp(len * 11 + 40, 70, 230), 62)
	local tail = Comic.frame(gui, Comic.Paper)
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0.5, -12, 1, -14)
	tail.Size = UDim2.fromOffset(16, 16)
	tail.Rotation = 45
	Comic.ink(tail, 3)
	local face = Comic.frame(gui, Comic.Paper)
	face.Size = UDim2.new(1, -6, 1, -20)
	face.Position = UDim2.fromOffset(3, 3)
	face.ZIndex = 2
	Comic.round(face, 18)
	Comic.ink(face, 3).LineJoinMode = Enum.LineJoinMode.Round
	local label = Comic.label(face, text, Comic.Body, 20, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 3
	popIn(face)
	track(ctx, gui)
	Debris:AddItem(gui, life)
end

-- Texto suelto que sube y se apaga (notas, "clap", "taca")
local function floater(ctx, position: Vector3, text: string, color: Color3, px: number, life: number, rise: number)
	local anchor = fixed(piece(ctx, "block", Vector3.new(0.1, 0.1, 0.1), color), CFrame.new(position))
	anchor.Transparency = 1
	local gui = billboard(anchor, Vector3.zero, px * 3 + 20, px + 16)
	local label = Comic.label(gui, text, Comic.Display, px, color)
	label.Size = UDim2.fromScale(1, 1)
	label.Rotation = rng:NextNumber(-12, 12)
	local stroke = Comic.ink(label, 2.5)
	track(ctx, gui)
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-0.6, 0.6), rise, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	Debris:AddItem(anchor, life)
	Debris:AddItem(gui, life)
end

local function once(ctx, key: string, ready: boolean): boolean
	if ready and not ctx.fired[key] then
		ctx.fired[key] = true
		return true
	end
	return false
end

-- Cuenta de pulsos: true cada vez que `t` entra en un periodo nuevo (para bucles)
local function tick(ctx, key: string, t: number, period: number): boolean
	local n = math.floor(t / period)
	if ctx.data[key] ~= n then
		ctx.data[key] = n
		return true
	end
	return false
end

local function hear(ctx, fn: (...any) -> (), ...: any)
	if ctx.hear then
		fn(...)
	end
end

local function above(ctx, up: number): Vector3
	return ctx.head.Position + Vector3.new(0, up * ctx.s, 0)
end

------------------------------------------------------------------------------------------------
-- Confeti (para el combo): piezas ancladas movidas a mano, con freno de aire
------------------------------------------------------------------------------------------------

local bits: { any } = {}
local confettiFolder: Folder? = nil

local function confetti(position: Vector3, count: number)
	if not confettiFolder then
		local folder = Instance.new("Folder")
		folder.Name = "EmoteConfetti"
		folder.Parent = Workspace
		confettiFolder = folder
	end
	for _ = 1, count do
		local part = Instance.new("Part")
		part.Name = "Confetti"
		part.Size = Vector3.new(rng:NextNumber(0.25, 0.4), 0.05, rng:NextNumber(0.18, 0.3))
		part.Color = CONFETTI[rng:NextInteger(1, #CONFETTI)]
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = CFrame.new(position)
		part.Parent = confettiFolder
		table.insert(bits, {
			part = part,
			pos = position,
			vel = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(14, 26), rng:NextNumber(-12, 12)),
			spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)),
			born = os.clock(),
		})
	end
end

local function updateConfetti(dt: number)
	local now = os.clock()
	for i = #bits, 1, -1 do
		local b = bits[i]
		local age = now - b.born
		if age > 2 or not b.part.Parent then
			b.part:Destroy()
			table.remove(bits, i)
		else
			b.vel = (b.vel + Vector3.new(0, -22 * dt, 0)) * (1 - math.min(1, 2.2 * dt))
			b.pos += b.vel * dt + Vector3.new(math.sin(age * 9 + i) * 0.03, 0, 0)
			local s = b.spin * age
			b.part.CFrame = CFrame.new(b.pos) * CFrame.Angles(s.X, s.Y, s.Z)
			b.part.Transparency = math.clamp((age - 1.4) / 0.6, 0, 1)
		end
	end
end

------------------------------------------------------------------------------------------------
-- Los emotes. start(ctx) crea los accesorios; pose(ctx, t, p) rellena la pose y mueve accesorios.
------------------------------------------------------------------------------------------------

local B: { [string]: any } = {}

-- Dab: se agacha, y de golpe una pata delantera estirada arriba, la otra doblada tapando la cara
-- y las dos antenas apuntando hacia el mismo lado
B.dab = {
	pose = function(ctx, t: number, p)
		local crouch = smooth(seg(t, 0, 0.3)) * (1 - seg(t, 0.32, 0.42))
		local k = backOut(seg(t, 0.32, 0.5)) * (1 - smooth(seg(t, 2.0, 2.3)))
		local shiver = if k > 0.9 then math.sin(t * 40) * 0.015 else 0
		rear(p, 0.55 * k, -0.15 * crouch)
		leg(p, 1, -0.3 * k, 0.9 * k - 0.2 * crouch, -1.5 * k + 0.3 * crouch)
		leg(p, 2, 1.25 * k, 0.55 * k - 0.2 * crouch, 1.4 * k + 0.3 * crouch)
		p.head = CFrame.Angles(-0.35 * k - 0.12 * crouch + shiver, 0.45 * k, 0.25 * k)
		antenna(p, 1, 0.5 * k - 0.2 * crouch, 0.6 * k, -0.3 * k)
		antenna(p, 2, 0.5 * k - 0.2 * crouch, -0.45 * k, -0.3 * k)
		if once(ctx, "dab", t >= 0.42) then
			Fx.burst(above(ctx, 1.2), "¡DAB!", Comic.Cyan, 210)
			hear(ctx, Sfx.bite, true, 1.35, 0.3)
			hear(ctx, Sfx.pop, 0.75, 0.5)
		end
		if once(ctx, "back", t >= 2.0) then
			hear(ctx, Sfx.pop, 1.25, 0.35)
		end
	end,
}

-- Pose en T: las seis patas rígidas en cruz, levita y gira despacio. Cartel "DOMINANCIA".
B.tpose = {
	pose = function(ctx, t: number, p)
		local crouch = smooth(seg(t, 0, 0.35)) * (1 - seg(t, 0.35, 0.45))
		local drop = smooth(seg(t, 3.1, 3.4))
		local k = backOut(seg(t, 0.38, 0.62)) * (1 - drop)
		local hover = (0.55 + math.sin(t * 2.2) * 0.07) * smooth(seg(t, 0.45, 1.1)) * (1 - drop)
		local land = bump(t, 3.38, 3.58) * -0.12
		body(p, 0, hover - 0.15 * crouch + land, 0, 0, math.sin(t * 0.9) * 0.3 * k, 0)
		local swings = { 0.4, 0, -0.4 }
		for i = 1, 6 do
			leg(p, i, swings[(i + 1) // 2] * k, -0.58 * k + 0.25 * crouch, -1.6 * k + 0.35 * crouch)
		end
		p.head = CFrame.Angles(0.08 * k, 0, 0)
		antennae(p, 0.7 * k, 0.25 * k, -0.45 * k)
		if once(ctx, "chord", t >= 0.45) then
			for i, pitch in { 0.5, 0.6, 0.75 } do
				task.delay((i - 1) * 0.12, hear, ctx, Sfx.pop, pitch, 0.55)
			end
		end
		if once(ctx, "sign", t >= 0.9) then
			sign(ctx, ctx.head, Vector3.new(0, 3.6, 0), "DOMINANCIA", Comic.Red, 34, 2.3)
		end
		if once(ctx, "land", t >= 3.4) then
			hear(ctx, Sfx.pop, 0.9, 0.4)
			Fx.crumbs(ctx.base.Position, Comic.Dirt, 5)
		end
	end,
}

-- Hilo dental: el abdomen a un lado y las patas delanteras al otro, en bucle, con notas
B.floss = {
	pose = function(ctx, t: number, p)
		local ph = t * math.pi * 2 / 0.6
		local s, c = math.sin(ph), math.cos(ph)
		body(p, -s * 0.12, math.abs(s) * 0.08 - 0.05, 0, 0, s * 0.12, c * 0.05)
		p.abdomen = CFrame.Angles(0.05, s * 0.36, s * 0.06)
		leg(p, 1, s * 0.75, 0.35, 0.4)
		leg(p, 2, -s * 0.75, 0.35, 0.4)
		leg(p, 3, 0, 0.1 + math.max(0, s) * 0.25, 0.2)
		leg(p, 4, 0, 0.1 + math.max(0, -s) * 0.25, 0.2)
		p.head = CFrame.Angles(math.sin(ph * 2) * 0.06, -s * 0.12, 0)
		antenna(p, 1, 0.2, 0.2 + c * 0.2, 0, s * 0.3)
		antenna(p, 2, 0.2, 0.2 - c * 0.2, 0, s * 0.3)
		if tick(ctx, "beat", t, 0.3) then
			hear(ctx, Sfx.tick, if (ctx.data.beat or 0) % 2 == 0 then 1 else 1.35)
			if (ctx.data.beat or 0) % 4 == 1 then
				floater(ctx, above(ctx, 1.4), "♪", Comic.Ink, 26, 1.2, 3 * ctx.s)
			end
		end
	end,
}

-- Bruh: se queda tiesa, bocadillo "bruh" y cae de lado como una tabla; luego se levanta de golpe
B.bruh = {
	pose = function(ctx, t: number, p)
		local stiff = smooth(seg(t, 0, 0.25)) * (1 - smooth(seg(t, 3.0, 3.3)))
		local fall = easeIn(seg(t, 0.75, 1.2))
		local up = backOut(seg(t, 3.0, 3.45))
		local a = (math.pi / 2 * fall - 0.14 * bump(t, 1.2, 1.45)) * (1 - up)
		body(p, 0, 0, 0, 0, 0, -a, Vector3.new(1.05, -1.25, 0))
		local lying = fall * (1 - up)
		for i = 1, 6 do
			local lift, knee = -0.2 * stiff, -0.6 * stiff
			if i % 2 == 0 then
				-- El lado que queda abajo recoge las patas
				lift += 0.9 * lying
				knee += 1.0 * lying
			end
			leg(p, i, 0, lift, knee)
		end
		p.knees[1] = (p.knees[1] or 0) + bump(t, 2.0, 2.35) * 0.6
		antennae(p, 0.25 * stiff, 0, -0.5 * stiff)
		p.head = CFrame.Angles(0.05 * stiff, 0, 0)
		if once(ctx, "say", t >= 0.25) then
			say(ctx, "bruh", 2.4)
			hear(ctx, Sfx.pop, 0.5, 0.4)
		end
		if once(ctx, "plof", t >= 1.2) then
			Fx.burst((ctx.base * CFrame.new(2 * ctx.s, 0.6 * ctx.s, 0)).Position, "¡PLOF!", Comic.Yellow, 170)
			hear(ctx, Sfx.bite, true, 0.6, 0.4)
			if ctx.mine then
				Fx.shake(0.12)
			end
		end
		if once(ctx, "up", t >= 3.05) then
			hear(ctx, Sfx.pop, 1.3, 0.35)
		end
	end,
}

-- Aplauso lento y sarcástico con cuatro patas, de pie, cara de nada
local function clapCurve(t: number, start: number): (number, number)
	local ph = (t - start) / 0.8
	if ph < 0 or ph >= 4 then
		return 0, -1
	end
	local frac = ph - math.floor(ph)
	local beat = math.floor(ph)
	if frac < 0.31 then
		return easeIn(frac / 0.31), beat
	elseif frac < 0.37 then
		return 1, beat
	end
	return 1 - smooth((frac - 0.37) / 0.63), beat
end

B.clap = {
	pose = function(ctx, t: number, p)
		local k = smooth(seg(t, 0, 0.45)) * (1 - smooth(seg(t, 3.8, 4.15)))
		rear(p, 0.7 * k)
		local front = clapCurve(t, 0.5)
		local mid = clapCurve(t, 0.56)
		leg(p, 1, (0.4 + 0.75 * front) * k, 0.55 * k, (0.9 - 0.3 * front) * k)
		leg(p, 2, (0.4 + 0.75 * front) * k, 0.55 * k, (0.9 - 0.3 * front) * k)
		leg(p, 3, (0.2 + 0.7 * mid) * k, 0.35 * k, 0.7 * k)
		leg(p, 4, (0.2 + 0.7 * mid) * k, 0.35 * k, 0.7 * k)
		p.head = CFrame.Angles(-0.05 * k, 0, math.sin(t * 0.7) * 0.05 * k)
		antennae(p, -0.35 * k, 0.2 * k, 0.35 * k)
		for n = 0, 3 do
			if once(ctx, "clap" .. n, t >= 0.5 + n * 0.8 + 0.25) then
				hear(ctx, Sfx.pop, 0.62, 0.55)
				task.delay(0.06, hear, ctx, Sfx.pop, 0.7, 0.35)
				floater(ctx, above(ctx, 0.6) + Vector3.new(rng:NextNumber(-1, 1), 0, 0), "clap", Comic.Ink, 20, 0.9, 2 * ctx.s)
			end
		end
	end,
}

-- NPC: saludo robótico en bucle, a tirones, con "…" y frases de relleno
local NPC_LINES = { "…", "Hola, viajera.", "…", "Bonito día.", "…", "¿Has visto mis migas?" }

B.npc = {
	start = function(ctx)
		local _, label = sign(ctx, ctx.head, Vector3.new(0, 3.2, 0), "…", Comic.Ink, 26, nil)
		ctx.data.label = label
	end,
	pose = function(ctx, t: number, p)
		local k = smooth(seg(t, 0, 0.2))
		local tq = math.floor(t * 5) / 5 -- tirones a 5 fotogramas por segundo
		local step = math.floor(t / 0.8)
		local turns = { 0, 0.35, 0, -0.35 }
		local wave = if math.floor(tq * 2.5) % 2 == 0 then 0.6 else -0.2
		leg(p, 2, 0.15 * k, 1.05 * k, (-0.3 + wave) * k)
		p.head = CFrame.Angles(0, turns[step % 4 + 1] * k, 0)
		body(p, 0, (step % 2) * 0.04 * k, 0)
		antennae(p, 0.35 * k, 0, -0.4 * k)
		if tick(ctx, "jerk", tq, 0.4) then
			hear(ctx, Sfx.tick, 0.75)
		end
		local label = ctx.data.label
		if label and tick(ctx, "line", t, 1.6) then
			label.Text = NPC_LINES[(ctx.data.line or 0) % #NPC_LINES + 1]
		end
	end,
}

-- Sigma: bandas negras de cine solo alrededor de la hormiga, mirada lenta y se acaricia la mandíbula
B.sigma = {
	start = function(ctx)
		for i = 1, 2 do
			local bar = fixed(piece(ctx, "block", Vector3.new(9, 1.5, 0.05), Color3.new(0, 0, 0)), ctx.base)
			bar.Transparency = 1
			ctx.data["bar" .. i] = bar
		end
	end,
	pose = function(ctx, t: number, p)
		local k = smooth(seg(t, 0, 0.5)) * (1 - smooth(seg(t, 4.4, 4.9)))
		local camera = Workspace.CurrentCamera
		if camera then
			local center = ctx.head.Position + Vector3.new(0, 0.2 * ctx.s, 0)
			local look = CFrame.lookAt(center, camera.CFrame.Position)
			local gap = (2.5 + (1 - k) * 3) * ctx.s
			ctx.data.bar1.CFrame = look * CFrame.new(0, gap, 0)
			ctx.data.bar2.CFrame = look * CFrame.new(0, -gap - 0.4 * ctx.s, 0)
			ctx.data.bar1.Transparency = 1 - k
			ctx.data.bar2.Transparency = 1 - k
		end
		local turn = 0.45 * smooth(seg(t, 0.3, 1.8)) * (1 - smooth(seg(t, 4.0, 4.6)))
		local rub = smooth(seg(t, 1.7, 2.1)) * (1 - smooth(seg(t, 3.7, 4.0)))
		body(p, 0, 0, 0, 0.06 * k, turn * 0.3, 0)
		p.head = CFrame.Angles(-0.08 * k, turn, 0)
		leg(p, 2, 1.15 * rub, 0.55 * rub, 1.5 * rub + math.sin(t * 6) * 0.15 * rub)
		antenna(p, 1, 0.25 * k, 0.1 * k, -0.2 * k)
		antenna(p, 2, -0.15 * k, 0, 0.35 * k)
		p.jaw = 0.08 * rub * math.max(0, math.sin(t * 6))
		if once(ctx, "boom", t >= 0.05) then
			hear(ctx, Sfx.bite, true, 0.5, 0.45)
		end
		if once(ctx, "look", t >= 1.75) then
			hear(ctx, Sfx.pop, 0.55, 0.4)
		end
	end,
}

-- GG EZ: gafas de píxeles que bajan del cielo balanceándose y se posan en los ojos
local PIXELS = { "####.####", "####.####", ".##...##." }

B.ggez = {
	start = function(ctx)
		local core = piece(ctx, "block", Vector3.new(0.1, 0.1, 0.1), Color3.new(0, 0, 0))
		core.Transparency = 1
		ctx.data.weld = stick(core, ctx.head, at(ctx, 0, 12, -0.98))
		local px = 0.17
		for row, line in PIXELS do
			for col = 1, #line do
				if line:sub(col, col) == "#" then
					local pixel = piece(ctx, "block", Vector3.new(px, px, 0.08), Color3.new(0, 0, 0))
					stick(pixel, core, at(ctx, (col - 5) * px, (2 - row) * px, 0))
				end
			end
		end
		-- Puente y brillos
		local bridge = piece(ctx, "block", Vector3.new(px * 9, px * 0.6, 0.08), Color3.new(0, 0, 0))
		stick(bridge, core, at(ctx, 0, 1.3 * px, 0))
		for _, x in { -3, 2 } do
			local shine = piece(ctx, "block", Vector3.new(px, px, 0.09), Color3.new(1, 1, 1))
			stick(shine, core, at(ctx, (x - 1) * px, px, -0.01))
		end
	end,
	pose = function(ctx, t: number, p)
		local land = 1.9
		local drop = 1 - easeOut(seg(t, 0.2, land))
		local leave = easeIn(seg(t, 3.55, 3.95))
		local sway = math.sin(t * 5) * 0.3 * drop
		local hit = bump(t, land, land + 0.2) * -0.05
		ctx.data.weld.C0 = at(ctx, 0, 0.3 + 11 * drop + hit + 7 * leave, -0.98) * CFrame.Angles(0, 0, sway)
		local cool = smooth(seg(t, land, land + 0.25)) * (1 - smooth(seg(t, 3.5, 3.9)))
		local watch = smooth(seg(t, 0.2, 0.8)) * (1 - smooth(seg(t, land - 0.2, land)))
		body(p, 0, 0, 0, 0.12 * cool, 0, 0.05 * cool)
		p.head = CFrame.Angles(0.25 * watch - 0.05 * cool, 0, 0.12 * cool)
		local fix = bump(t, 2.3, 2.8)
		leg(p, 2, 1.2 * fix, 0.65 * fix, 1.55 * fix)
		antennae(p, -0.3 * cool + 0.2 * watch, 0.3 * cool, -0.2 * cool)
		for i = 0, 4 do
			if once(ctx, "fall" .. i, t >= 0.3 + i * 0.3) then
				hear(ctx, Sfx.pop, 1.9 - i * 0.18, 0.25)
			end
		end
		if once(ctx, "land", t >= land) then
			Fx.burst(above(ctx, 1.2), "¡GG EZ!", PINK, 210)
			hear(ctx, Sfx.fanfare)
		end
	end,
}

-- Todo bien: se sienta con una tacita mientras salen llamitas alrededor
B.fine = {
	start = function(ctx)
		local thorax = ctx.thorax
		local cup = piece(ctx, "rod", Vector3.new(0.34, 0.34, 0.34), Color3.new(1, 1, 1))
		ctx.data.cup = stick(cup, thorax, at(ctx, 0.35, -0.05, -1.75) * CFrame.Angles(0, 0, math.pi / 2))
		stick(piece(ctx, "rod", Vector3.new(0.1, 0.37, 0.37), Comic.Red), cup, at(ctx, 0, 0, 0))
		stick(piece(ctx, "rod", Vector3.new(0.03, 0.28, 0.28), Color3.fromRGB(150, 90, 50)), cup, at(ctx, 0.17, 0, 0))
		stick(piece(ctx, "ball", Vector3.new(0.12, 0.2, 0.08), Color3.new(1, 1, 1)), cup, at(ctx, 0, 0, 0.2))
		local saucer = piece(ctx, "rod", Vector3.new(0.05, 0.62, 0.62), AntModel.Cream)
		ctx.data.saucer = stick(saucer, thorax, at(ctx, 0.3, -0.24, -1.72) * CFrame.Angles(0, 0, math.pi / 2))
		-- Llamitas en corro sobre el suelo: gota naranja con corazón amarillo brillante
		ctx.data.flames = {}
		for i = 1, 8 do
			local a = (i - 1) / 8 * math.pi * 2 + 0.2
			local r = 3.2 + (i % 2) * 0.5
			local cf = ctx.base * CFrame.new(math.cos(a) * r * ctx.s, 0.45 * ctx.s, math.sin(a) * r * ctx.s)
			local outer = fixed(piece(ctx, "ball", Vector3.new(0.7, 1.1, 0.7), ORANGE), cf)
			local inner = fixed(piece(ctx, "ball", Vector3.new(0.38, 0.62, 0.38), Comic.Yellow, true), cf * CFrame.new(0, -0.12 * ctx.s, 0))
			table.insert(ctx.data.flames, { outer = outer, inner = inner, seed = rng:NextNumber(0, 10) })
		end
	end,
	pose = function(ctx, t: number, p)
		local sit = smooth(seg(t, 0, 0.5)) * (1 - smooth(seg(t, 5.5, 5.9)))
		body(p, 0, -0.3 * sit, 0, 0.22 * sit, 0, 0, Vector3.new(0, -1, 1.2))
		p.abdomen = CFrame.Angles(0.18 * sit, 0, 0)
		leg(p, 5, 0.6 * sit, 0.15 * sit, 0.3 * sit)
		leg(p, 6, 0.6 * sit, 0.15 * sit, 0.3 * sit)
		leg(p, 3, 0.3 * sit, 0.1 * sit, 0.2 * sit)
		leg(p, 4, 0.3 * sit, 0.1 * sit, 0.2 * sit)
		local sip = math.max(bump(t, 2.4, 3.2), bump(t, 4.4, 5.2))
		leg(p, 2, 1.05 * sit, (0.45 + 0.25 * sip) * sit, (1.3 + 0.2 * sip) * sit)
		leg(p, 1, 1.0 * sit, 0.35 * sit, 1.2 * sit)
		p.head = CFrame.Angles((-0.05 - 0.15 * sip) * sit, 0, 0.05 * sit)
		antennae(p, -0.1 * sit, 0.15 * sit, 0.2 * sit)
		ctx.data.cup.C0 = at(ctx, 0.35 - 0.2 * sip, -0.05 + 0.3 * sip, -1.75 - 0.2 * sip) * CFrame.Angles(0, 0, math.pi / 2 + 0.5 * sip)
		local grow = smooth(seg(t, 0.6, 1.8)) * (1 - smooth(seg(t, 5.3, 5.9)))
		for _, f in ctx.data.flames do
			local flicker = 1 + 0.25 * math.sin(t * 13 + f.seed) + 0.1 * math.sin(t * 29 + f.seed)
			for _, part in { f.outer, f.inner } do
				local mesh = part:FindFirstChildOfClass("SpecialMesh")
				if mesh then
					mesh.Scale = Vector3.new(grow, grow * flicker, grow)
				end
				part.Transparency = if grow < 0.02 then 1 else 0
			end
		end
		if grow > 0.3 and tick(ctx, "crackle", t, 0.22) then
			hear(ctx, Sfx.tick, rng:NextNumber(0.55, 0.85))
		end
		if grow > 0.5 and tick(ctx, "smoke", t, 0.6) then
			local f = ctx.data.flames[rng:NextInteger(1, #ctx.data.flames)]
			local puff = fixed(piece(ctx, "ball", Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(110, 105, 110)), f.outer.CFrame)
			TweenService:Create(puff, TweenInfo.new(1.2), { CFrame = f.outer.CFrame + Vector3.new(0, 3 * ctx.s, 0), Size = puff.Size * 2.4, Transparency = 1 }):Play()
			Debris:AddItem(puff, 1.2)
		end
		if once(ctx, "say", t >= 1.4) then
			say(ctx, "Todo bien.", 3)
		end
		for i, when in { 2.8, 4.8 } do
			if once(ctx, "sip" .. i, t >= when) then
				hear(ctx, Sfx.pop, 1.7, 0.25)
				task.delay(0.12, hear, ctx, Sfx.pop, 1.85, 0.2)
			end
		end
	end,
}

-- Stonks: pose de empresaria (corbata, una pata en jarra y la otra señalando) y una flecha verde
-- que sube en zigzag detrás
local ARROW = {
	Vector3.new(-3.4, -0.6, 1.8),
	Vector3.new(-1.8, 1.0, 1.8),
	Vector3.new(-0.7, 0.2, 1.8),
	Vector3.new(1.2, 2.6, 1.8),
	Vector3.new(2.2, 2.0, 1.8),
	Vector3.new(3.8, 4.6, 1.8),
}

B.stonks = {
	start = function(ctx)
		local navy = Color3.fromRGB(40, 50, 110)
		stick(piece(ctx, "ball", Vector3.new(0.24, 0.2, 0.2), navy), ctx.thorax, at(ctx, 0, -0.12, -0.6))
		stick(piece(ctx, "ball", Vector3.new(0.22, 0.6, 0.1), navy), ctx.thorax, at(ctx, 0, -0.45, -0.56) * CFrame.Angles(-0.2, 0, 0))
		ctx.data.segments = {}
		for i = 1, #ARROW - 1 do
			local a, b = ARROW[i] * ctx.s, ARROW[i + 1] * ctx.s
			local rod = piece(ctx, "rod", Vector3.new(0.05, 0.42, 0.42), GREEN)
			rod.Transparency = 1
			local frame = CFrame.lookAt(a, b) * CFrame.Angles(0, math.pi / 2, 0)
			local joint = piece(ctx, "ball", Vector3.new(0.5, 0.5, 0.5), GREEN)
			joint.Transparency = 1
			stick(joint, ctx.root, CFrame.new(b))
			table.insert(ctx.data.segments, { rod = rod, joint = joint, weld = stick(rod, ctx.root, frame), frame = frame, len = (b - a).Magnitude })
		end
		-- Punta: dos trazos en uve
		local tip = ARROW[#ARROW] * ctx.s
		local dir = (ARROW[#ARROW] - ARROW[#ARROW - 1]).Unit
		ctx.data.heads = {}
		for _, turn in { 2.5, -2.5 } do
			local back = CFrame.fromAxisAngle(Vector3.zAxis, turn * 0.25):VectorToWorldSpace(-dir)
			local frame = CFrame.lookAt(tip, tip + back) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0.45 * ctx.s, 0, 0)
			local rod = piece(ctx, "rod", Vector3.new(0.9, 0.42, 0.42), GREEN)
			rod.Transparency = 1
			stick(rod, ctx.root, frame)
			table.insert(ctx.data.heads, rod)
		end
	end,
	pose = function(ctx, t: number, p)
		local k = smooth(seg(t, 0, 0.45)) * (1 - smooth(seg(t, 4.0, 4.4)))
		rear(p, 0.5 * k)
		leg(p, 1, -0.5 * k, 0.25 * k, 1.8 * k)
		leg(p, 2, -0.2 * k, 1.0 * k, -1.3 * k)
		p.head = CFrame.Angles(0.25 * k, -0.35 * k, 0)
		antennae(p, -0.25 * k, 0.1 * k, -0.35 * k)
		local fadeOut = smooth(seg(t, 4.0, 4.4))
		local n = #ctx.data.segments
		for i, sgm in ctx.data.segments do
			local q = seg(t, 0.45 + (i - 1) * 0.38, 0.45 + i * 0.38)
			sgm.rod.Size = Vector3.new(math.max(0.05, sgm.len * q), 0.42 * ctx.s, 0.42 * ctx.s)
			sgm.weld.C0 = sgm.frame * CFrame.new(sgm.len * q / 2, 0, 0)
			sgm.rod.Transparency = if q <= 0 then 1 else fadeOut
			sgm.joint.Transparency = if q < 1 then 1 else fadeOut
			if once(ctx, "seg" .. i, q > 0) then
				hear(ctx, Sfx.tick, 1 + 0.15 * i)
			end
		end
		local ready = t >= 0.45 + n * 0.38
		for _, rod in ctx.data.heads do
			rod.Transparency = if ready then fadeOut else 1
		end
		if once(ctx, "sign", ready) then
			local tip = ctx.root.CFrame * (ARROW[#ARROW] * ctx.s)
			Fx.burst(tip, "STONKS", GREEN, 230)
			hear(ctx, Sfx.fanfare)
		end
	end,
}

-- ¿Sus?: se agacha y mira a los lados con las antenas tiesas como un periscopio; al final te mira
B.sus = {
	pose = function(ctx, t: number, p)
		local c = smooth(seg(t, 0, 0.4)) * (1 - smooth(seg(t, 4.0, 4.4)))
		body(p, 0, -0.38 * c, 0, -0.06 * c, 0, 0)
		for i = 1, 6 do
			leg(p, i, 0, 0.32 * c, 0.55 * c)
		end
		local scan = keyed(t, { { 0.5, 0 }, { 0.8, 0.6 }, { 1.5, 0.6 }, { 1.8, -0.6 }, { 2.6, -0.6 }, { 2.85, 0 } })
		antennae(p, 0.95 * c, 0.05 * c, -0.55 * c, scan * c)
		local snap = smooth(seg(t, 3.0, 3.1)) * (1 - smooth(seg(t, 3.8, 4.1)))
		local toCamera = 0
		local camera = Workspace.CurrentCamera
		if camera then
			local rel = ctx.root.CFrame:PointToObjectSpace(camera.CFrame.Position)
			toCamera = math.clamp(math.atan2(-rel.X, -rel.Z), -0.5, 0.5)
		end
		p.head = CFrame.Angles(-0.05 * c, (scan * 0.4) * c * (1 - snap) + toCamera * snap, 0)
		for i, key in { 0.5, 1.5, 2.6 } do
			if once(ctx, "look" .. i, t >= key) then
				hear(ctx, Sfx.tick, 0.7)
			end
		end
		if once(ctx, "sign", t >= 0.9) then
			sign(ctx, ctx.head, Vector3.new(0, 3.2, 0), "¿sus?", Comic.Red, 30, 2.1)
		end
		if once(ctx, "bang", t >= 3.05) then
			Fx.burst(above(ctx, 1), "!", Comic.Yellow, 130)
			hear(ctx, Sfx.pop, 1.8, 0.45)
		end
	end,
}

-- F: saludo solemne mientras una F gigante sube despacio desde el suelo
B.f = {
	start = function(ctx)
		local core = piece(ctx, "block", Vector3.new(0.1, 0.1, 0.1), Color3.new(0, 0, 0))
		core.Transparency = 1
		ctx.data.weld = stick(core, ctx.root, at(ctx, 3.4, -3.2, -0.4))
		local gold = Color3.fromRGB(255, 214, 80)
		local parts = {}
		local function bar(x: number, y: number, len: number, vertical: boolean)
			local rod = piece(ctx, "rod", Vector3.new(len, 0.62, 0.62), gold)
			stick(rod, core, at(ctx, x, y, 0) * (if vertical then CFrame.Angles(0, 0, math.pi / 2) else CFrame.identity))
			table.insert(parts, rod)
			for _, e in { -1, 1 } do
				local cap = piece(ctx, "ball", Vector3.new(0.64, 0.64, 0.64), gold)
				local off = if vertical then Vector3.new(0, e * len / 2, 0) else Vector3.new(e * len / 2, 0, 0)
				stick(cap, core, at(ctx, x + off.X, y + off.Y, 0))
				table.insert(parts, cap)
			end
		end
		bar(0, 0, 3.2, true)
		bar(1.0, 1.6, 2.0, false)
		bar(0.75, 0.2, 1.5, false)
		ctx.data.parts = parts
	end,
	pose = function(ctx, t: number, p)
		local k = smooth(seg(t, 0, 0.4)) * (1 - smooth(seg(t, 4.0, 4.4)))
		rear(p, 0.35 * k)
		local salute = smooth(seg(t, 0.3, 0.6)) * (1 - smooth(seg(t, 3.6, 4.0)))
		leg(p, 2, 1.0 * salute, 0.8 * salute, 1.75 * salute)
		p.head = CFrame.Angles(0.05 * k, 0, 0)
		antennae(p, -0.35 * k, 0.1 * k, 0.2 * k)
		local rise = smooth(seg(t, 0.4, 3.6))
		ctx.data.weld.C0 = at(ctx, 3.4, -3.2 + 6.8 * rise, -0.4) * CFrame.Angles(0, 0, math.sin(t * 1.4) * 0.05)
		local gone = seg(t, 3.9, 4.4)
		for _, part in ctx.data.parts do
			part.Transparency = gone
		end
		for i, key in { 0.5, 1.6, 2.7 } do
			if once(ctx, "bell" .. i, t >= key) then
				hear(ctx, Sfx.pop, 0.5, 0.5)
				task.delay(0.1, hear, ctx, Sfx.pop, 0.75, 0.2)
			end
		end
	end,
}

-- Helicóptero: las antenas giran como hélices y la hormiga se eleva un poco con las patas colgando
B.heli = {
	start = function(ctx)
		local disc = piece(ctx, "ball", Vector3.new(3, 0.08, 3), Color3.new(1, 1, 1))
		disc.Transparency = 1
		stick(disc, ctx.head, at(ctx, 0, 1.15, -0.2))
		ctx.data.disc = disc
		ctx.data.angle = 0
	end,
	pose = function(ctx, t: number, p, dt: number)
		local spin = smooth(seg(t, 0, 1))
		ctx.data.angle += dt * 22 * spin
		local lift = smooth(seg(t, 0.7, 1.6))
		local hover = 0.9 * lift + math.sin(t * 3) * 0.12 * lift
		body(p, math.sin(t * 1.3) * 0.1 * lift, hover, 0, math.sin(t * 2) * 0.04 * lift, 0, math.sin(t * 1.7) * 0.05 * lift)
		for i = 1, 2 do
			local s = if i == 1 then -1 else 1
			local a = ctx.data.angle + (if i == 1 then math.pi else 0)
			p.antennae[i] = CFrame.Angles(0, a, 0) * CFrame.Angles(0.15 * spin, 0, -s * 0.95 * spin)
			p.elbows[i] = -0.5 * spin
		end
		ctx.data.disc.Transparency = 1 - 0.55 * smooth(seg(t, 0.5, 1.2))
		for i = 1, 6 do
			leg(p, i, math.sin(t * 4 + i) * 0.12 * lift, -0.35 * lift, -0.4 * lift)
		end
		p.abdomen = CFrame.Angles(0.15 * lift, math.sin(t * 2) * 0.1 * lift, 0)
		p.head = CFrame.Angles(0.1 * lift, 0, 0)
		if spin > 0.3 and tick(ctx, "chop", t, 0.11) then
			hear(ctx, Sfx.tick, 0.6 + 0.25 * spin)
		end
		if once(ctx, "burst", t >= 0.8) then
			Fx.burst(above(ctx, 1.8), "¡TACA-TACA!", Comic.Cyan, 190)
		end
		if t > 2 and tick(ctx, "taca", t, 1.4) then
			floater(ctx, above(ctx, 1.6), "taca", Comic.Ink, 18, 1, 2 * ctx.s)
		end
	end,
}

-- Breakdance: salta, se da la vuelta y gira sobre el lomo pataleando
B.breakdance = {
	start = function(ctx)
		ctx.data.angle = 0
	end,
	pose = function(ctx, t: number, p, dt: number)
		local flip = smooth(seg(t, 0.15, 0.55))
		local hop = bump(t, 0, 0.6) * 0.9
		ctx.data.angle += dt * 9 * smooth(seg(t, 0.5, 1))
		local wobble = math.sin(t * 5) * 0.08 * flip
		local pivot = Vector3.new(0, 0.1, -0.1)
		p.body = CFrame.new(0, -0.72 * flip + hop, 0)
			* CFrame.Angles(0, ctx.data.angle, 0)
			* CFrame.new(pivot)
			* CFrame.Angles(wobble, 0, math.pi * flip)
			* CFrame.new(-pivot)
		for i = 1, 6 do
			local ph = t * 9 + i * 1.1
			leg(p, i, math.sin(ph) * 0.4 * flip, (0.5 + math.sin(ph) * 0.35) * flip, (0.3 + math.cos(ph) * 0.5) * flip)
		end
		p.head = CFrame.Angles(0.15 * flip, 0, 0)
		p.abdomen = CFrame.Angles(-0.2 * flip, 0, 0)
		antenna(p, 1, math.sin(t * 11) * 0.4, 0.3, math.cos(t * 9) * 0.3)
		antenna(p, 2, math.sin(t * 11 + 1.5) * 0.4, 0.3, math.cos(t * 9 + 1) * 0.3)
		if tick(ctx, "half", ctx.data.angle, math.pi) and t > 0.5 then
			hear(ctx, Sfx.tick, 1.3)
		end
		if once(ctx, "burst", t >= 0.4) then
			Fx.burst(above(ctx, 0.5), "¡BREAK!", Comic.Yellow, 180)
			hear(ctx, Sfx.pop, 1.4, 0.4)
		end
		if t > 2 and tick(ctx, "wii", t, 3) then
			floater(ctx, above(ctx, 0.8), "¡wiii!", Comic.Red, 20, 1.1, 2.5 * ctx.s)
		end
	end,
}

-- Cabeza explotando: la cabeza se hincha temblando y revienta en una nube de galaxia
B.mind = {
	start = function(ctx)
		local head = ctx.head
		local swell = piece(ctx, "ball", Vector3.one, head.Color)
		swell.Size = head.Size
		swell.Transparency = 1
		ctx.data.swellWeld = stick(swell, head, CFrame.new(0, 0.05 * ctx.s, 0.05 * ctx.s))
		ctx.data.swell = swell
		ctx.data.eyes = {}
		for _, s in { -1, 1 } do
			local eye = piece(ctx, "ball", Vector3.new(0.7, 1, 0.45), Color3.new(1, 1, 1))
			local pupil = piece(ctx, "ball", Vector3.new(0.3, 0.5, 0.24), AntModel.Ink)
			eye.Transparency = 1
			pupil.Transparency = 1
			table.insert(ctx.data.eyes, { eye = eye, pupil = pupil, s = s, ew = stick(eye, head, CFrame.identity), pw = stick(pupil, head, CFrame.identity) })
		end
		ctx.data.stars = {}
		for i = 1, 3 do
			local star = piece(ctx, "ball", Vector3.new(0.28, 0.28, 0.28), Comic.Yellow, true)
			star.Transparency = 1
			table.insert(ctx.data.stars, { part = star, weld = stick(star, head, CFrame.identity), phase = i * math.pi * 2 / 3 })
		end
	end,
	pose = function(ctx, t: number, p)
		local POP = 1.6
		local stare = smooth(seg(t, 0, 0.4))
		local popped = t >= POP
		local g = if popped then 1 else 1 + 0.55 * easeIn(seg(t, 0.5, POP))
		local d = ctx.data
		if not popped then
			local jitter = (g - 1) * 0.05 * ctx.s
			d.swell.Size = ctx.head.Size * g
			d.swell.Transparency = if g > 1.02 then 0 else 1
			d.swellWeld.C0 = CFrame.new(rng:NextNumber(-jitter, jitter), 0.05 * ctx.s + (g - 1) * 0.4 * ctx.s, 0.05 * ctx.s)
			for _, e in d.eyes do
				local show = if g > 1.02 then 0 else 1
				e.eye.Transparency = show
				e.pupil.Transparency = show
				local base = at(ctx, e.s * 0.42 * g, 0.3 * g + (g - 1) * 0.4, -0.78 * g)
				e.ew.C0 = base
				e.pw.C0 = base * at(ctx, -e.s * 0.03, -0.12, -0.2)
			end
		elseif once(ctx, "pop", true) then
			d.swell.Transparency = 1
			for _, e in d.eyes do
				e.eye.Transparency = 1
				e.pupil.Transparency = 1
			end
			-- Nube de galaxia: bolas brillantes que crecen y suben, con estrellitas
			d.cloud = {}
			local origin = above(ctx, 1.2)
			local colors = { Color3.fromRGB(150, 90, 230), PINK, Color3.fromRGB(62, 120, 243), Color3.fromRGB(60, 30, 110) }
			for i = 1, 9 do
				local size = rng:NextNumber(0.8, 1.6)
				local ball = fixed(piece(ctx, "ball", Vector3.new(size, size * 0.8, size), colors[(i - 1) % #colors + 1], i % 3 ~= 0), CFrame.new(origin))
				table.insert(d.cloud, { part = ball, dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.2, 1), rng:NextNumber(-1, 1)).Unit, size = ball.Size })
			end
			for _ = 1, 10 do
				local star = fixed(piece(ctx, "ball", Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), true), CFrame.new(origin))
				table.insert(d.cloud, { part = star, dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.1, 1.2), rng:NextNumber(-1, 1)), size = star.Size, star = true })
			end
			d.origin = origin
			Fx.burst(origin, "¡BUM!", Color3.fromRGB(200, 150, 255), 230)
			hear(ctx, Sfx.bite, true, 0.45, 0.45)
			task.delay(0.1, hear, ctx, Sfx.fanfare)
			if ctx.mine then
				Fx.shake(0.25)
			end
		end
		if popped and d.cloud then
			local u = t - POP
			local grow = easeOut(math.min(1, u / 0.5))
			local gone = seg(t, 3.3, 3.95)
			for _, c in d.cloud do
				local reach = (if c.star then 2.6 else 1.6) * ctx.s * grow
				c.part.CFrame = CFrame.new(d.origin + c.dir * reach + Vector3.new(0, u * 0.8 * ctx.s, 0))
				c.part.Size = c.size * (0.4 + 0.8 * grow)
				c.part.Transparency = if c.star then math.max(gone, 0.5 + 0.5 * math.sin(t * 12 + c.dir.X * 9)) else math.max(gone, 0.15)
			end
			for _, s in d.stars do
				local a = t * 5 + s.phase
				s.weld.C0 = at(ctx, math.cos(a) * 0.9, 1.0, math.sin(a) * 0.9)
				s.part.Transparency = gone
			end
		end
		local after = if popped then 1 - smooth(seg(t, 3.5, 3.95)) else 0
		local before = stare * (if popped then 0 else 1)
		local tremble = math.sin(t * 50) * 0.06 * (g - 1) * 2
		body(p, 0, 0, 0, 0, 0, math.sin(t * 4) * 0.08 * after)
		p.head = CFrame.Angles(0.12 * before + tremble + (-0.1 + math.sin(t * 3) * 0.06) * after, 0, 0)
		for i = 1, 6 do
			leg(p, i, 0, -0.15 * before, -0.4 * before)
		end
		antennae(p, (0.4 + math.sin(t * 50) * 0.06) * before - 0.4 * after, 0.2 * before + 0.3 * after, -0.4 * before + 0.8 * after)
		p.jaw = 0.35 * after
	end,
}

-- No somos dignas: se vuelve hacia la jugadora más cercana y le hace reverencias; destellos encima
B.worthy = {
	start = function(ctx)
		local best, bestDist = nil, 14 * ctx.s
		for _, other in Players:GetPlayers() do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if other ~= ctx.player and root and root:IsA("BasePart") then
				local d = (root.Position - ctx.root.Position).Magnitude
				if d < bestDist then
					best, bestDist = root, d
				end
			end
		end
		ctx.data.target = best
		ctx.data.yaw = 0
		if best then
			local rel = ctx.root.CFrame:PointToObjectSpace(best.Position)
			ctx.data.yaw = math.atan2(-rel.X, -rel.Z)
		end
		ctx.data.sparks = {}
		for i = 1, 4 do
			local spark = fixed(piece(ctx, "ball", Vector3.new(0.3, 0.3, 0.3), Comic.Yellow, true), ctx.base)
			spark.Transparency = 1
			table.insert(ctx.data.sparks, { part = spark, phase = i * math.pi / 2 })
		end
	end,
	pose = function(ctx, t: number, p)
		local k = smooth(seg(t, 0, 0.4)) * (1 - smooth(seg(t, 4.0, 4.4)))
		local b = math.max(bump(t, 0.55, 1.45), bump(t, 1.75, 2.65), bump(t, 2.95, 3.85))
		local raise = (1 - b) * k * smooth(seg(t, 0.3, 0.6))
		local pivot = Vector3.new(0, -1.1, -1.4)
		p.body = CFrame.Angles(0, ctx.data.yaw * k, 0)
			* CFrame.new(pivot)
			* CFrame.Angles(-0.42 * b, 0, 0)
			* CFrame.new(-pivot)
			* CFrame.new(0, 0.15 * raise, 0)
		for i = 1, 2 do
			leg(p, i, 0.9 * b + 0.2 * raise, -0.25 * b + 0.9 * raise, -1.0 * b - 0.9 * raise)
		end
		p.head = CFrame.Angles(-0.35 * b + 0.15 * raise, 0, 0)
		p.abdomen = CFrame.Angles(-0.25 * b, 0, 0)
		antennae(p, -0.45 * b + 0.4 * raise, 0.2 * k, -0.3 * b)
		local target = ctx.data.target
		local center = if target and target.Parent
			then target.Position + Vector3.new(0, 3.2 * ctx.s, 0)
			else (ctx.base * CFrame.new(0, 3.5 * ctx.s, -5 * ctx.s)).Position
		for _, sp in ctx.data.sparks do
			local a = t * 2.5 + sp.phase
			sp.part.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 1.3, math.sin(t * 3 + sp.phase) * 0.25, math.sin(a) * 1.3) * ctx.s)
			sp.part.Transparency = 1 - k
		end
		if once(ctx, "sign", t >= 0.3) then
			sign(ctx, ctx.head, Vector3.new(0, 3.4, 0), if target then "¡NO SOMOS DIGNAS!" else "¡NO SOY DIGNA!", Comic.Red, 26, 2.6)
		end
		for i, key in { 1.0, 2.2, 3.4 } do
			if once(ctx, "bow" .. i, t >= key) then
				hear(ctx, Sfx.pop, 0.8 + 0.1 * i, 0.45)
			end
		end
		if once(ctx, "end", t >= 3.9) then
			hear(ctx, Sfx.finish, 2)
		end
	end,
}

------------------------------------------------------------------------------------------------
-- Quién está haciendo qué
------------------------------------------------------------------------------------------------

type Run = { player: Player, def: any, beh: any, ctx: any, stopAt: number?, startedAt: number, preview: boolean, conns: { RBXScriptConnection } }
local runs: { [Player]: Run } = {}

local function finish(run: Run)
	if runs[run.player] == run then
		runs[run.player] = nil
		if run.ctx.character.Parent then
			AntAnim.override(run.ctx.character, nil)
		end
	end
	for _, conn in run.conns do
		conn:Disconnect()
	end
	table.clear(run.conns)
	for _, item in run.ctx.trash do
		item:Destroy()
	end
	table.clear(run.ctx.trash)
	run.ctx.props:Destroy()
end

local function beginStop(target: Player)
	local run = runs[target]
	if run and not run.stopAt then
		run.stopAt = os.clock()
	end
end

local function step(run: Run, dt: number, t: number, p): boolean
	if runs[run.player] ~= run then
		return false
	end
	local ctx = run.ctx
	if not ctx.root.Parent or not ctx.head.Parent or not ctx.thorax.Parent then
		finish(run)
		return false
	end
	-- Moverse o saltar corta el emote (cada cliente lo ve por su cuenta)
	if not run.stopAt and t > 0.3 then
		local v = ctx.root.AssemblyLinearVelocity
		local moving = (v * FLAT).Magnitude > 4 or math.abs(v.Y) > 14
		if ctx.mine and ctx.humanoid and ctx.humanoid.MoveDirection.Magnitude > 0.3 then
			moving = true
		end
		if moving then
			run.stopAt = os.clock()
		end
	end
	local now = os.clock()
	local length = run.def.length
	if (length and t >= length) or (run.stopAt and now - run.stopAt >= FADE_OUT) then
		finish(run)
		return false
	end
	local w = smooth(seg(t, 0, FADE_IN))
	if length then
		w = math.min(w, 1 - smooth(seg(t, length - 0.3, length)))
	end
	if run.stopAt then
		w = math.min(w, 1 - seg(now - run.stopAt, 0, FADE_OUT))
	end
	run.beh.pose(ctx, t, p, dt)
	fade(p, w)
	return true
end

local function startRun(target: Player, id: string, preview: boolean): Run?
	local def = Defs.byId[id]
	local beh = B[id]
	if not def or not beh then
		return nil
	end
	local old = runs[target]
	if old then
		finish(old)
	end
	local character = target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local thorax = character and character:FindFirstChild("Thorax")
	if not character or not root or not head or not thorax or not root:IsA("BasePart") or not head:IsA("BasePart") or not thorax:IsA("BasePart") then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - root.Position).Magnitude else 0
	if target ~= player and distance > SEEN then
		return nil
	end

	local s = character:GetScale()
	local props = Instance.new("Folder")
	props.Name = "EmoteProps"
	props.Parent = character -- dentro del modelo: el contorno de tinta del personaje también los bordea
	local ctx = {
		player = target,
		character = character,
		root = root,
		head = head,
		thorax = thorax,
		humanoid = character:FindFirstChildOfClass("Humanoid"),
		s = s,
		props = props,
		trash = {},
		fired = {},
		data = {},
		mine = target == player,
		hear = distance < HEAR,
		base = root.CFrame * CFrame.new(0, -(0.5 + AntModel.HipHeight) * s, 0),
		def = def,
	}
	local run: Run = { player = target, def = def, beh = beh, ctx = ctx, stopAt = nil, startedAt = os.clock(), preview = preview, conns = {} }
	runs[target] = run
	if beh.start then
		local ok, err = pcall(beh.start, ctx)
		if not ok then
			warn("[CRUNCH!] Emote " .. id .. ":", err)
		end
	end
	-- Reconstruida (mejoras, trajes) o fuera del mundo: se corta en seco y se limpia
	table.insert(run.conns, character:GetAttributeChangedSignal("LookVersion"):Connect(function()
		finish(run)
	end))
	table.insert(run.conns, character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(Workspace) then
			finish(run)
		end
	end))
	AntAnim.override(character, function(dt: number, t: number, p): boolean
		return step(run, dt, t, p)
	end)
	return run
end

------------------------------------------------------------------------------------------------
-- Lo que tienes
------------------------------------------------------------------------------------------------

local function ownedSet(): { [string]: boolean }
	local set = {}
	local raw = player:GetAttribute("Emotes")
	if type(raw) == "string" then
		for _, id in Defs.decode(raw) do
			set[id] = true
		end
	else
		for _, def in Defs.list do
			if def.unlock.kind == "free" then
				set[def.id] = true
			end
		end
	end
	return set
end

local pendingWheel: { string }? = nil -- lo último que pediste, hasta que el servidor lo confirma

local function wheelIds(): { string }
	if pendingWheel then
		return pendingWheel
	end
	local raw = player:GetAttribute("EmoteWheel")
	if type(raw) == "string" then
		return Defs.decode(raw, Defs.WheelSize)
	end
	return table.clone(Defs.DefaultWheel)
end

-- Páginas de la rueda: la tuya y luego el resto de lo que tienes, de 8 en 8
local function wheelPages(): { { string } }
	local owned = ownedSet()
	local mine = wheelIds()
	local first = {}
	for i = 1, Defs.WheelSize do
		local id = mine[i]
		first[i] = if id and owned[id] then id else ""
	end
	local pages = { first }
	local rest = {}
	for _, def in Defs.list do
		if owned[def.id] and not table.find(first, def.id) then
			table.insert(rest, def.id)
		end
	end
	for i = 1, #rest, Defs.WheelSize do
		local page = {}
		for j = 0, Defs.WheelSize - 1 do
			page[j + 1] = rest[i + j] or ""
		end
		table.insert(pages, page)
	end
	return pages
end

local lastRequest = -math.huge

local function airborne(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return true
	end
	return humanoid.FloorMaterial == Enum.Material.Air and math.abs(root.AssemblyLinearVelocity.Y) > 8
end

-- Lanza un emote tuyo: se ve ya en tu pantalla y el servidor lo reenvía a las demás
local function request(id: string)
	local def = Defs.byId[id]
	if not def or not ownedSet()[id] or not remote then
		return
	end
	local run = runs[player]
	if run and run.def.id == id and not run.preview and not run.stopAt then
		-- Pulsar otra vez el mismo lo corta
		beginStop(player)
		remote:FireServer("Stop")
		return
	end
	if os.clock() - lastRequest < Defs.Cooldown or airborne() then
		Sfx.pop(0.6, 0.3)
		return
	end
	lastRequest = os.clock()
	startRun(player, id, false)
	remote:FireServer("Play", id)
end

------------------------------------------------------------------------------------------------
-- Pictogramas (formas de Shared/Emotes dibujadas con marcos)
------------------------------------------------------------------------------------------------

local SILHOUETTE = Color3.fromRGB(60, 50, 56)

local function drawIcon(parent: GuiObject, def, size: number, silhouette: boolean?): Frame
	local box = Comic.frame(parent)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(64, 64)
	box.Rotation = def.tilt or 0
	box.ZIndex = parent.ZIndex + 1
	local scale = Instance.new("UIScale")
	scale.Scale = size / 64
	scale.Parent = box
	local z = parent.ZIndex + 1
	for _, spec in def.icon do
		local kind, x, y, w, h, color, rot = spec[1], spec[2], spec[3], spec[4], spec[5], spec[6], spec[7] or 0
		local tint = if silhouette then SILHOUETTE else color
		if kind == "t" then
			local label = Comic.label(box, spec[8] or "", Comic.Display, h, tint)
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromOffset(x, y)
			label.Size = UDim2.fromOffset(w, h)
			label.Rotation = rot
			label.TextScaled = true
			label.ZIndex = z
			if silhouette then
				label.TextTransparency = 0.5
			end
		else
			local shape = Comic.frame(box, tint)
			shape.AnchorPoint = Vector2.new(0.5, 0.5)
			shape.Position = UDim2.fromOffset(x, y)
			shape.ZIndex = z
			if silhouette then
				shape.BackgroundTransparency = 0.5
			end
			if kind == "d" then
				shape.Size = UDim2.fromOffset(w, w)
				shape.Rotation = 45 + rot
				Comic.round(shape, 2)
			elseif kind == "l" then
				shape.Size = UDim2.fromOffset(w, h)
				shape.Rotation = rot
				Comic.round(shape, 2)
			elseif kind == "c" then
				shape.Size = UDim2.fromOffset(w, h)
				shape.BackgroundTransparency = 1
				Comic.round(shape)
				local ring = Comic.ink(shape, 2, true)
				ring.Color = tint
				ring.Transparency = if silhouette then 0.5 else 0.35
			else
				shape.Size = UDim2.fromOffset(w, h)
				shape.Rotation = rot
				Comic.round(shape, if kind == "o" then nil else 3)
			end
			if not silhouette and (kind == "o" or kind == "r" or kind == "d") then
				Comic.ink(shape, 1.5, true)
			end
		end
	end
	return box
end

local function pointerOf(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.MouseButton1 then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
end

local function inside(object: GuiObject, point: Vector2): boolean
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + s.X and point.Y <= p.Y + s.Y
end

------------------------------------------------------------------------------------------------
-- Rueda radial
------------------------------------------------------------------------------------------------

local R = 128 -- radio de diseño
local SLOT = 80
local SIZE = (R + SLOT) * 2 + 80

local wheel = {
	gui = nil :: ScreenGui?,
	root = nil :: Frame?,
	pop = nil :: UIScale?,
	slots = {} :: { any },
	name = nil :: TextLabel?,
	page = nil :: TextLabel?,
	tab = nil :: GuiObject?,
	open = false,
	mode = "hold", -- "hold" (Y o dedo pulsado) o "sticky" (se queda abierta hasta tocar)
	pageIndex = 1,
	hovered = nil :: number?,
	tabArmed = false,
	touch = nil :: InputObject?,
	touchStart = Vector2.zero,
	openedAt = 0,
	frames = 0, -- fotogramas desde que se abrió (un tirón al abrir no convierte un toque en "mantener")
	centerAt = nil :: Vector2?, -- dónde se colocó al abrir (AbsolutePosition aún no está al día)
	openPointer = Vector2.zero, -- ratón al abrir: hasta que no se mueve, no se señala nada
}
local albumToggle: () -> () = function() end

local function wheelCenter(): (Vector2, number)
	local root = wheel.root :: Frame
	local scale = root.AbsoluteSize.X / SIZE
	-- El fotograma en que se abre, AbsolutePosition aún es la de la vez anterior: con ella el ratón
	-- "señalaba" un hueco al azar y un toque rápido lanzaba un meme en vez de abrir el álbum
	local center = wheel.centerAt or (root.AbsolutePosition + root.AbsoluteSize / 2)
	return center, if scale > 0 then scale else 1
end

local function paintWheel()
	local pages = wheelPages()
	wheel.pageIndex = (wheel.pageIndex - 1) % #pages + 1
	local ids = pages[wheel.pageIndex]
	for i, slot in wheel.slots do
		local id = ids[i] or ""
		slot.id = id
		local def = Defs.byId[id]
		if slot.icon then
			slot.icon:Destroy()
			slot.icon = nil
		end
		slot.face.BackgroundColor3 = if def then def.color else Comic.Paper
		slot.face.BackgroundTransparency = if def then 0 else 0.4
		slot.plus.Visible = def == nil
		if def then
			slot.icon = drawIcon(slot.face, def, SLOT - 14)
		end
	end
	if wheel.page then
		wheel.page.Text = if #pages > 1 then "Página " .. wheel.pageIndex .. "/" .. #pages else ""
	end
	if wheel.tab then
		wheel.tab.Visible = #pages > 1
	end
end

local function setHovered(index: number?)
	if wheel.hovered == index then
		return
	end
	wheel.hovered = index
	for i, slot in wheel.slots do
		local on = i == index and Defs.byId[slot.id] ~= nil
		slot.stroke.Color = if on then Comic.Red else Comic.Ink
		slot.stroke.Thickness = if on then 6 else 4
		slot.scale.Scale = if on then 1.18 else 1
	end
	local def = index and Defs.byId[wheel.slots[index].id]
	if wheel.name then
		wheel.name.Text = if def then def.name else (if wheel.mode == "sticky" then "Toca uno" else "Suelta sobre uno")
	end
	if def then
		Sfx.tick(1.4)
	end
end

local function flipPage(delta: number)
	local count = #wheelPages()
	if count <= 1 then
		return
	end
	wheel.pageIndex = (wheel.pageIndex - 1 + delta) % count + 1
	paintWheel()
	setHovered(nil)
	Sfx.pop(1.25, 0.3)
end

local function closeWheel(commit: boolean)
	if not wheel.open then
		return
	end
	local index = wheel.hovered
	wheel.open = false
	wheel.touch = nil
	ContextActionService:UnbindAction("EmoteWheelPage")
	if wheel.gui then
		wheel.gui.Enabled = false
	end
	if commit and index then
		local id = wheel.slots[index].id
		if Defs.byId[id] then
			request(id)
		end
	end
	setHovered(nil)
end

local function openWheel(center: Vector2, mode: string)
	if not wheel.gui or not wheel.root then
		return
	end
	wheel.open = true
	wheel.mode = mode
	wheel.pageIndex = 1
	wheel.openedAt = os.clock()
	wheel.tabArmed = false
	paintWheel()
	setHovered(nil)
	if wheel.name then
		wheel.name.Text = if mode == "sticky" then "Toca uno" else "Suelta sobre uno"
	end
	wheel.gui.Enabled = true
	-- Que la rueda quepa entera aunque abras junto a un borde
	local camera = Workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local _, scale = wheelCenter()
	local half = (R + SLOT / 2 + 70) * scale
	local x = math.clamp(center.X, math.min(half, view.X / 2), math.max(view.X - half, view.X / 2))
	local y = math.clamp(center.Y, math.min(half, view.Y / 2), math.max(view.Y - half, view.Y / 2))
	wheel.root.Position = UDim2.fromOffset(x, y)
	wheel.centerAt = Vector2.new(x, y)
	wheel.frames = 0
	wheel.openPointer = UserInputService:GetMouseLocation()
	if wheel.pop then
		wheel.pop.Scale = 0.6
		TweenService:Create(wheel.pop, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	-- La rueda del ratón pasa de página en vez de acercar la cámara
	ContextActionService:BindActionAtPriority("EmoteWheelPage", function(_, state, input)
		if state == Enum.UserInputState.Change and input.UserInputType == Enum.UserInputType.MouseWheel then
			flipPage(if input.Position.Z > 0 then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, Enum.UserInputType.MouseWheel)
	Sfx.pop(1.45, 0.3)
end

-- Qué hueco señala el puntero (o el arrastre del dedo)
local function updateWheel()
	if not wheel.open or not wheel.root then
		return
	end
	wheel.frames += 1
	local center, scale = wheelCenter()
	local pointer: Vector2
	local delta: Vector2
	if wheel.touch then
		pointer = pointerOf(wheel.touch)
		-- Con el dedo cuenta la dirección del arrastre desde donde empezó (gesto de marcado)
		delta = (pointer - wheel.touchStart) / scale
		if delta.Magnitude < 30 then
			setHovered(nil)
			return
		end
	else
		pointer = UserInputService:GetMouseLocation()
		delta = (pointer - center) / scale
		-- Manteniendo Y: si el ratón no se ha movido desde que abrió, no se señala nada (junto a un
		-- borde la rueda se recoloca y el ratón quedaba ya encima de un hueco)
		if wheel.mode == "hold" and (pointer - wheel.openPointer).Magnitude < 12 then
			setHovered(nil)
			return
		end
	end
	-- Pestaña de página: pasar el puntero por encima cambia de página
	if wheel.tab and wheel.tab.Visible and inside(wheel.tab, pointer) then
		if not wheel.tabArmed then
			wheel.tabArmed = true
			flipPage(1)
		end
		return
	end
	wheel.tabArmed = false
	if wheel.mode == "sticky" and not wheel.touch then
		-- Abierta "pegada": el ratón resalta lo que tiene encima, sin zona muerta grande
		for i, slot in wheel.slots do
			if inside(slot.face, pointer) then
				setHovered(i)
				return
			end
		end
		setHovered(nil)
		return
	end
	local dist = delta.Magnitude
	if dist < 40 or (not wheel.touch and dist > R + SLOT / 2 + 60) then
		setHovered(nil)
		return
	end
	local angle = math.deg(math.atan2(delta.Y, delta.X)) + 90
	local index = math.floor(((angle + 22.5) % 360) / 45) + 1
	setHovered(if Defs.byId[wheel.slots[index].id] then index else nil)
end

local function buildWheel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EmoteWheel"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Enabled = false
	gui.Parent = playerGui
	wheel.gui = gui

	-- Suelta el ratón (primera persona, bloqueo de cámara) mientras la rueda está abierta
	local modal = Instance.new("TextButton")
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Size = UDim2.fromOffset(0, 0)
	modal.Modal = true
	modal.Parent = gui

	local root = Comic.frame(gui)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(SIZE, SIZE)
	Hud.fitScale(root, SLOT)
	wheel.root = root

	local inner = Comic.frame(root)
	inner.Size = UDim2.fromScale(1, 1)
	local pop = Instance.new("UIScale")
	pop.Parent = inner
	wheel.pop = pop

	-- Banda del anillo: solo un aro de tinta translúcida, el juego se sigue viendo por dentro y fuera
	local band = Comic.frame(inner)
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.fromOffset(R * 2, R * 2)
	Comic.round(band)
	local bandStroke = Instance.new("UIStroke")
	bandStroke.Thickness = SLOT + 14
	bandStroke.Color = Comic.Ink
	bandStroke.Transparency = 0.6
	bandStroke.Parent = band

	for i = 1, Defs.WheelSize do
		local a = math.rad(-90 + (i - 1) * 45)
		local holder = Comic.frame(inner)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.new(0.5, math.cos(a) * R, 0.5, math.sin(a) * R)
		holder.Size = UDim2.fromOffset(SLOT, SLOT)
		holder.ZIndex = 2
		local face = Instance.new("TextButton")
		face.AutoButtonColor = false
		face.Text = ""
		face.Size = UDim2.fromScale(1, 1)
		face.BackgroundColor3 = Comic.Paper
		face.BorderSizePixel = 0
		face.ZIndex = 3
		face.Parent = holder
		Comic.round(face)
		local stroke = Comic.ink(face, 4, true)
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local plus = Comic.label(face, "+", Comic.Display, 34, Comic.Ink)
		plus.Size = UDim2.fromScale(1, 1)
		plus.TextTransparency = 0.6
		plus.ZIndex = 4
		local number = Comic.label(holder, tostring(i), Comic.Display, 15, Comic.Ink)
		number.AnchorPoint = Vector2.new(0.5, 0.5)
		number.Position = UDim2.new(0.5, math.cos(a) * 46, 0.5, math.sin(a) * 46)
		number.Size = UDim2.fromOffset(20, 20)
		number.BackgroundTransparency = 0
		number.BackgroundColor3 = Comic.Yellow
		number.ZIndex = 6
		Comic.round(number)
		Comic.ink(number, 2, true)
		local slot = { face = face, stroke = stroke, scale = scale, plus = plus, id = "", icon = nil }
		face.Activated:Connect(function()
			if wheel.open and Defs.byId[slot.id] then
				wheel.hovered = i
				closeWheel(true)
			end
		end)
		table.insert(wheel.slots, slot)
	end

	-- Centro: el nombre de lo señalado y la página
	local hub = Instance.new("TextButton")
	hub.AutoButtonColor = false
	hub.Text = ""
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(112, 112)
	hub.BackgroundColor3 = Comic.Paper
	hub.BorderSizePixel = 0
	hub.ZIndex = 2
	hub.Parent = inner
	Comic.round(hub)
	Comic.ink(hub, 4, true)
	hub.Activated:Connect(function()
		if wheel.open and wheel.mode == "sticky" then
			closeWheel(false)
		end
	end)
	local name = Comic.label(hub, "", Comic.Display, 22, Comic.Ink)
	name.AnchorPoint = Vector2.new(0.5, 0.5)
	name.Position = UDim2.new(0.5, 0, 0.5, -6)
	name.Size = UDim2.fromOffset(96, 52)
	name.TextWrapped = true
	name.TextScaled = true
	name.ZIndex = 3
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 24
	limit.MinTextSize = 12
	limit.Parent = name
	wheel.name = name
	local page = Comic.label(hub, "", Comic.Body, 13, Comic.Ink)
	page.AnchorPoint = Vector2.new(0.5, 1)
	page.Position = UDim2.new(0.5, 0, 1, -12)
	page.Size = UDim2.fromOffset(90, 16)
	page.ZIndex = 3
	wheel.page = page

	-- Pestaña de página bajo el anillo (pasar por encima o tocarla)
	local tab, tabFace = Comic.button(inner, UDim2.fromOffset(120, 36), Comic.Yellow, 3)
	tab.AnchorPoint = Vector2.new(0.5, 0)
	tab.Position = UDim2.new(0.5, 0, 0.5, R + SLOT / 2 + 16)
	tabFace.ZIndex = 3
	local tabLabel = Comic.label(tabFace, "Página ›", Comic.Display, 20, Comic.Ink)
	tabLabel.Size = UDim2.fromScale(1, 1)
	tabLabel.ZIndex = 4
	tabFace.Activated:Connect(function()
		if wheel.open and wheel.mode == "sticky" then
			flipPage(1)
		end
	end)
	wheel.tab = tab
end

------------------------------------------------------------------------------------------------
-- Álbum de cromos con el editor de la rueda
------------------------------------------------------------------------------------------------

local W = 420
local MARGIN = 16
local HEADER = 100
local PAD = 20
local MINI_R = 84
local MINI_SLOT = 56
local CELL_W = 122
local CELL_H = 170
local PAGE_TINT = Color3.fromRGB(246, 232, 204)
local HOLE = Color3.fromRGB(226, 210, 180)
local DIM = Color3.fromRGB(226, 216, 196)

local album = {
	gui = nil :: ScreenGui?,
	panel = nil :: Frame?,
	fit = nil :: UIScale?,
	count = nil :: TextLabel?,
	food = nil :: TextLabel?,
	hint = nil :: TextLabel?,
	clear = nil :: GuiObject?,
	mini = {} :: { any },
	stickers = {} :: { [string]: any },
	open = false,
	selectedSlot = nil :: number?,
	selectedId = nil :: string?,
	dragGui = nil :: ScreenGui?,
}
local sideButton: any = nil
local drag: any = nil
local dragEndedAt = 0

local function sendWheel(list: { string })
	pendingWheel = list
	if remote then
		remote:FireServer("Wheel", list)
	end
end

-- Pone `id` en el hueco `index`; si ya estaba en otro, cambian de sitio
local function assign(index: number, id: string)
	local list = table.clone(wheelIds())
	for i = 1, Defs.WheelSize do
		list[i] = list[i] or ""
	end
	local from = table.find(list, id)
	if from then
		list[from] = list[index]
	end
	list[index] = id
	sendWheel(list)
	Sfx.pop(1.35, 0.4)
end

local paintAlbum: () -> ()

local function shake(object: GuiObject)
	local base = object.Position
	task.spawn(function()
		for _, dx in { 7, -7, 5, -4, 2, 0 } do
			object.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.035)
		end
		object.Position = base
	end)
end

local function onMini(index: number)
	local owned = ownedSet()
	if album.selectedId and owned[album.selectedId] then
		assign(index, album.selectedId)
		album.selectedId = nil
		album.selectedSlot = nil
	else
		album.selectedSlot = if album.selectedSlot == index then nil else index
		Sfx.pop(1.15, 0.3)
	end
	paintAlbum()
end

local function onSticker(def)
	if os.clock() - dragEndedAt < 0.15 then
		return
	end
	-- Tu hormiga lo ensaya (solo en tu pantalla), lo tengas o no
	startRun(player, def.id, true)
	local owned = ownedSet()
	if owned[def.id] and album.selectedSlot then
		assign(album.selectedSlot, def.id)
		album.selectedSlot = nil
		album.selectedId = nil
	else
		album.selectedId = if owned[def.id] then def.id else nil
		Sfx.pop(1.2, 0.3)
	end
	paintAlbum()
end

local function onBuy(def, chipHolder: GuiObject)
	local cost = Defs.price(def)
	if ownedSet()[def.id] then
		return
	end
	if State.num("Food") < cost then
		shake(chipHolder)
		Sfx.pop(0.7)
		return
	end
	if remote then
		remote:FireServer("Buy", def.id)
	end
	Sfx.pop(1.45)
end

local function startDrag(def, input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	drag = { def = def, input = input, start = pointerOf(input), active = false, ghost = nil }
end

local function moveDrag(input: InputObject)
	if not drag then
		return
	end
	local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
	if not isMouse and input ~= drag.input then
		return
	end
	local pos = pointerOf(input)
	if not drag.active and (pos - drag.start).Magnitude > 12 and ownedSet()[drag.def.id] then
		drag.active = true
		local ghost = Comic.frame(album.dragGui, drag.def.color)
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.Size = UDim2.fromOffset(64, 64)
		ghost.ZIndex = 10
		Comic.round(ghost)
		Comic.ink(ghost, 4, true)
		drawIcon(ghost, drag.def, 54)
		local fit = album.fit
		if fit then
			local scale = Instance.new("UIScale")
			scale.Scale = fit.Scale
			scale.Parent = ghost
		end
		drag.ghost = ghost
	end
	if drag.active and drag.ghost then
		drag.ghost.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
end

local function endDrag(input: InputObject)
	if not drag then
		return
	end
	if input ~= drag.input and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local current = drag
	drag = nil
	if current.ghost then
		current.ghost:Destroy()
	end
	if current.active then
		dragEndedAt = os.clock()
		local pos = pointerOf(input)
		for i, slot in album.mini do
			if inside(slot.face, pos) then
				assign(i, current.def.id)
				album.selectedId = nil
				album.selectedSlot = nil
				paintAlbum()
				return
			end
		end
	end
end

local function at2(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

-- Editor de la rueda: un aro de 8 huecos pequeños, como la rueda de verdad
local function buildMini(parent: Instance, y: number): number
	local heading = Comic.label(parent, "Tu rueda", Comic.Display, 30, Comic.Red)
	at2(heading, PAD, y, 200, 32)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Rotation = -2
	Comic.ink(heading, 3)
	local hint = Comic.label(parent, "", Comic.Body, 14, Comic.Ink)
	at2(hint, PAD, y + 34, W - PAD * 2, 18)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	album.hint = hint
	local cx, cy = W / 2, y + 60 + MINI_R + MINI_SLOT / 2
	local ring = Comic.frame(parent)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	at2(ring, cx, cy, MINI_R * 2, MINI_R * 2)
	Comic.round(ring)
	local ringStroke = Comic.ink(ring, 3)
	ringStroke.Transparency = 0.6
	for i = 1, Defs.WheelSize do
		local a = math.rad(-90 + (i - 1) * 45)
		local face = Instance.new("TextButton")
		face.AutoButtonColor = false
		face.Text = ""
		face.AnchorPoint = Vector2.new(0.5, 0.5)
		at2(face, cx + math.cos(a) * MINI_R, cy + math.sin(a) * MINI_R, MINI_SLOT, MINI_SLOT)
		face.BackgroundColor3 = Comic.Paper
		face.BorderSizePixel = 0
		face.ZIndex = 3
		face.Parent = parent
		Comic.round(face)
		local stroke = Comic.ink(face, 3, true)
		local plus = Comic.label(face, "+", Comic.Display, 26, Comic.Ink)
		plus.Size = UDim2.fromScale(1, 1)
		plus.TextTransparency = 0.6
		plus.ZIndex = 4
		local number = Comic.label(parent, tostring(i), Comic.Display, 13, Comic.Ink)
		number.AnchorPoint = Vector2.new(0.5, 0.5)
		at2(number, cx + math.cos(a) * (MINI_R + 34), cy + math.sin(a) * (MINI_R + 34), 18, 18)
		local slot = { face = face, stroke = stroke, plus = plus, icon = nil, id = nil }
		face.Activated:Connect(function()
			onMini(i)
		end)
		table.insert(album.mini, slot)
	end
	-- Centro: quitar lo del hueco elegido
	local clear, clearFace = Comic.button(parent, UDim2.fromOffset(84, 34), Comic.Paper, 3)
	clear.AnchorPoint = Vector2.new(0.5, 0.5)
	clear.Position = UDim2.fromOffset(cx, cy)
	clearFace.ZIndex = 3
	local clearLabel = Comic.label(clearFace, "Quitar", Comic.Display, 20, Comic.Ink)
	clearLabel.Size = UDim2.fromScale(1, 1)
	clearLabel.ZIndex = 4
	clearFace.Activated:Connect(function()
		local index = album.selectedSlot
		if index then
			local list = table.clone(wheelIds())
			list[index] = ""
			sendWheel(list)
			album.selectedSlot = nil
			Sfx.pop(0.9, 0.35)
			paintAlbum()
		end
	end)
	album.clear = clear
	return cy + MINI_R + MINI_SLOT / 2 + 24
end

-- Esquineros de foto en las cuatro esquinas de un hueco del álbum
local function corners(holeFrame: Frame)
	for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local corner = Comic.frame(holeFrame, Comic.Ink)
		corner.AnchorPoint = Vector2.new(0.5, 0.5)
		corner.Position = UDim2.fromScale(c[1], c[2])
		corner.Size = UDim2.fromOffset(14, 14)
		corner.Rotation = 45
		corner.ZIndex = 5
		corner.BackgroundTransparency = 0.15
	end
end

-- Un hueco del álbum con su cromo pegado (o la silueta y cómo conseguirlo)
local function buildCell(parent: Instance, def, x: number, y: number)
	local holder = Comic.frame(parent)
	at2(holder, x, y, CELL_W, CELL_H)
	holder.ZIndex = 2
	local tilt = ({ -4, 3, -2, 5, -5, 2, 4, -3 })[(def.index - 1) % 8 + 1]

	local hole = Comic.frame(holder, HOLE)
	at2(hole, 6, 4, CELL_W - 12, CELL_H - 38)
	hole.ZIndex = 2
	Comic.round(hole, 8)
	local holeStroke = Comic.ink(hole, 2, true)
	holeStroke.Transparency = 0.5
	corners(hole)
	local number = Comic.label(hole, string.format("#%02d", def.index), Comic.Body, 13, Comic.Ink)
	number.AnchorPoint = Vector2.new(0.5, 1)
	number.Position = UDim2.new(0.5, 0, 1, -4)
	number.Size = UDim2.fromOffset(60, 14)
	number.TextTransparency = 0.45
	number.ZIndex = 3
	local silhouette = Comic.frame(hole)
	silhouette.Size = UDim2.new(1, 0, 1, -18)
	silhouette.ZIndex = 3
	drawIcon(silhouette, def, 70, true)
	local how = Comic.label(hole, Defs.howTo(def), Comic.Body, 13, Comic.Ink)
	how.AnchorPoint = Vector2.new(0.5, 1)
	how.Position = UDim2.new(0.5, 0, 1, -18)
	how.Size = UDim2.new(1, -8, 0, 30)
	how.TextWrapped = true
	how.ZIndex = 4

	-- El cromo: papel blanco con el fondo de color, el pictograma y el nombre
	local sticker = Instance.new("TextButton")
	sticker.AutoButtonColor = false
	sticker.Text = ""
	sticker.AnchorPoint = Vector2.new(0.5, 0)
	sticker.Position = UDim2.new(0.5, 0, 0, 6)
	sticker.Size = UDim2.fromOffset(CELL_W - 20, CELL_H - 44)
	sticker.BackgroundColor3 = Color3.new(1, 1, 1)
	sticker.BorderSizePixel = 0
	sticker.Rotation = tilt
	sticker.ZIndex = 6
	sticker.Parent = holder
	Comic.round(sticker, 10)
	local stroke = Comic.ink(sticker, 3, true)
	local inner = Comic.frame(sticker, def.color)
	at2(inner, 6, 6, CELL_W - 32, CELL_H - 84)
	inner.ZIndex = 7
	Comic.round(inner, 8)
	local dots = Comic.halftone(inner, Comic.Ink, 135)
	dots.ImageTransparency = 0.75
	dots.ZIndex = 7
	drawIcon(inner, def, 72)
	local name = Comic.label(sticker, def.name, Comic.Display, 19, Comic.Ink)
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Position = UDim2.new(0.5, 0, 1, -4)
	name.Size = UDim2.new(1, -8, 0, 30)
	name.TextScaled = true
	name.TextWrapped = true
	name.ZIndex = 8
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 19
	limit.MinTextSize = 11
	limit.Parent = name
	-- Marca de "va en la rueda": número del hueco
	local mark = Comic.label(sticker, "", Comic.Display, 15, Comic.Paper)
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromOffset(4, 4)
	mark.Size = UDim2.fromOffset(24, 24)
	mark.BackgroundTransparency = 0
	mark.BackgroundColor3 = Comic.Red
	mark.ZIndex = 9
	Comic.round(mark)
	Comic.ink(mark, 2, true)

	-- Bajo el hueco: precio para comprar, o la frase del meme
	local caption = Comic.label(holder, def.quote, Comic.Body, 12, Comic.Ink)
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 1, -32)
	caption.Size = UDim2.new(1, -4, 0, 30)
	caption.TextWrapped = true
	caption.ZIndex = 3
	local chipHolder, chipFace = Comic.button(holder, UDim2.fromOffset(CELL_W - 22, 28), Comic.Yellow, 3)
	chipHolder.AnchorPoint = Vector2.new(0.5, 0)
	chipHolder.Position = UDim2.new(0.5, 0, 1, -32)
	chipHolder.ZIndex = 6
	chipFace.ZIndex = 6
	local chip = Comic.label(chipFace, "", Comic.Display, 17, Comic.Ink)
	chip.Size = UDim2.fromScale(1, 1)
	chip.ZIndex = 7
	chipFace.Activated:Connect(function()
		onBuy(def, chipHolder)
	end)

	-- Tocar el hueco vacío también ensaya
	local holeButton = Instance.new("TextButton")
	holeButton.BackgroundTransparency = 1
	holeButton.Text = ""
	holeButton.Size = UDim2.fromScale(1, 1)
	holeButton.ZIndex = 5
	holeButton.Parent = hole
	holeButton.Activated:Connect(function()
		onSticker(def)
	end)
	sticker.Activated:Connect(function()
		onSticker(def)
	end)
	sticker.InputBegan:Connect(function(input)
		startDrag(def, input)
	end)

	album.stickers[def.id] = {
		def = def,
		sticker = sticker,
		stroke = stroke,
		hole = hole,
		how = how,
		silhouette = silhouette,
		mark = mark,
		caption = caption,
		chipHolder = chipHolder,
		chipFace = chipFace,
		chip = chip,
	}
end

function paintAlbum()
	if not album.panel then
		return
	end
	local owned = ownedSet()
	local count = 0
	for _ in owned do
		count += 1
	end
	if album.count then
		album.count.Text = count .. "/" .. #Defs.list .. " cromos"
	end
	if album.food then
		album.food.Text = "Comida " .. Format.short(State.num("Food"))
	end
	local mine = wheelIds()
	for i, slot in album.mini do
		local id = mine[i] or ""
		local def = owned[id] and Defs.byId[id]
		if slot.id ~= id then
			slot.id = id
			if slot.icon then
				slot.icon:Destroy()
				slot.icon = nil
			end
			if def then
				slot.icon = drawIcon(slot.face, def, MINI_SLOT - 10)
			end
		end
		slot.face.BackgroundColor3 = if def then def.color else Comic.Paper
		slot.plus.Visible = not def
		local selected = album.selectedSlot == i
		slot.stroke.Color = if selected then Comic.Red else Comic.Ink
		slot.stroke.Thickness = if selected then 6 else 3
	end
	if album.clear then
		local index = album.selectedSlot
		album.clear.Visible = index ~= nil and (mine[index] or "") ~= ""
	end
	if album.hint then
		album.hint.Text = if album.selectedSlot
			then "Ahora toca un cromo para el hueco " .. album.selectedSlot
			elseif album.selectedId then "Ahora toca un hueco de la rueda"
			else "Toca un hueco y luego un cromo, o arrastra el cromo"
	end
	local food = State.num("Food")
	for id, view in album.stickers do
		local have = owned[id] == true
		local def = view.def
		view.sticker.Visible = have
		view.silhouette.Visible = not have
		view.how.Visible = not have
		local slotIndex = table.find(mine, id)
		view.mark.Visible = have and slotIndex ~= nil
		view.mark.Text = if slotIndex then tostring(slotIndex) else ""
		local selected = album.selectedId == id
		view.stroke.Color = if selected then Comic.Red else Comic.Ink
		view.stroke.Thickness = if selected then 6 else 3
		local buyable = not have and def.unlock.kind == "food"
		view.chipHolder.Visible = buyable
		view.caption.Visible = not buyable
		if buyable then
			local cost = Defs.price(def)
			view.chip.Text = "Comprar " .. Format.short(cost)
			view.chipFace.BackgroundColor3 = if food >= cost then Comic.Yellow else DIM
			view.chip.TextTransparency = if food >= cost then 0 else 0.45
		end
	end
end

local function resizeAlbum()
	local camera = Workspace.CurrentCamera
	local panel, fit = album.panel, album.fit
	if not camera or not panel or not fit then
		return
	end
	local view = camera.ViewportSize
	local s = math.clamp(math.min(view.Y / 800, view.X * 0.45 / W), 0.5, 1.25)
	fit.Scale = s
	panel.Size = UDim2.fromOffset(W, math.max(200, (view.Y - MARGIN * 2) / s))
end

local function buildAlbum()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EmoteAlbum"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 21
	gui.Enabled = false
	gui.Parent = playerGui
	album.gui = gui

	local dragGui = Instance.new("ScreenGui")
	dragGui.Name = "EmoteDrag"
	dragGui.IgnoreGuiInset = true
	dragGui.ResetOnSpawn = false
	dragGui.DisplayOrder = 40
	dragGui.Parent = playerGui
	album.dragGui = dragGui

	local holder, face = Comic.box(gui, UDim2.fromOffset(W, 700), PAGE_TINT, 10)
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -MARGIN - 10, 0, MARGIN)
	face.Active = true
	face.ClipsDescendants = true
	album.panel = holder
	local fit = Instance.new("UIScale")
	fit.Parent = holder
	album.fit = fit
	local dots = Comic.halftone(face, Comic.Red, 90)
	dots.ImageTransparency = 0.7

	local title = Comic.label(face, "Memes", Comic.Display, 54, Comic.Ink)
	at2(title, PAD, 6, 220, 56)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -2
	title.ZIndex = 3
	local count = Comic.label(face, "", Comic.Display, 24, Comic.Yellow)
	at2(count, PAD + 4, 58, 200, 26)
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.ZIndex = 3
	Comic.ink(count, 3)
	album.count = count
	local food = Comic.label(face, "", Comic.Body, 15, Comic.Ink)
	at2(food, PAD + 200, 64, 120, 18)
	food.TextXAlignment = Enum.TextXAlignment.Left
	food.ZIndex = 3
	album.food = food

	local closeHolder, closeFace = Comic.button(face, UDim2.fromOffset(50, 50), Comic.Red, 4)
	closeHolder.Position = UDim2.new(1, -70, 0, 16)
	closeHolder.ZIndex = 3
	closeFace.ZIndex = 3
	local cross = Comic.label(closeFace, "X", Comic.Display, 32, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 4
	closeFace.Activated:Connect(function()
		albumToggle()
	end)

	local line = Comic.frame(face, Comic.Ink)
	at2(line, 0, HEADER - 3, W, 5)
	line.ZIndex = 3

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(0, HEADER + 2)
	scroll.Size = UDim2.new(1, 0, 1, -HEADER - 2)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Comic.Ink
	scroll.ElasticBehavior = Enum.ElasticBehavior.Never
	scroll.ZIndex = 2
	scroll.Parent = face

	local y = buildMini(scroll, 10)
	-- Dos páginas de álbum de 8 cromos, con su doblez y su rótulo; filas al tresbolillo
	local perPage = 8
	local inner = W - PAD * 2 - 10
	for pageIndex = 1, math.ceil(#Defs.list / perPage) do
		local heading = Comic.label(scroll, "Página " .. pageIndex, Comic.Display, 28, Comic.Red)
		at2(heading, PAD, y, 200, 30)
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.Rotation = if pageIndex % 2 == 0 then 2 else -2
		Comic.ink(heading, 3)
		y += 38
		local fold = Comic.frame(scroll, Comic.Ink)
		fold.BackgroundTransparency = 0.85
		at2(fold, W / 2 - 1, y, 2, 4 * (CELL_H + 4))
		local first = (pageIndex - 1) * perPage + 1
		local last = math.min(#Defs.list, pageIndex * perPage)
		local n = 0
		for index = first, last do
			local row = n // 3
			local col = n % 3
			local inRow = math.min(3, last - first + 1 - row * 3)
			local offset = (3 - inRow) * CELL_W / 2 + (if row % 2 == 1 then 8 else -8)
			local x = PAD + offset + col * (inner / 3) + (inner / 3 - CELL_W) / 2
			buildCell(scroll, Defs.list[index], x, y + row * (CELL_H + 6))
			n += 1
		end
		y += math.ceil((last - first + 1) / 3) * (CELL_H + 6) + 14
	end
	scroll.CanvasSize = UDim2.fromOffset(0, y + 16)

	resizeAlbum()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(resizeAlbum)
	end
end

local function setAlbum(open: boolean)
	if not album.gui or not album.panel or not album.fit then
		return
	end
	album.open = open
	album.gui.Enabled = open
	if open then
		album.selectedSlot = nil
		album.selectedId = nil
		resizeAlbum()
		paintAlbum()
		Sfx.pop(0.9)
		if sideButton then
			sideButton.setBadge(false)
		end
		local rest = UDim2.new(1, -MARGIN - 10, 0, MARGIN)
		album.panel.Position = rest + UDim2.fromOffset(W * album.fit.Scale + 40, 0)
		TweenService:Create(album.panel, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = rest }):Play()
	end
end

albumToggle = function()
	setAlbum(not album.open)
end

-- Álbum abierto o rueda desplegada (para no morder mientras tanto)
function Emotes.isOpen(): boolean
	return album.open == true or wheel.open == true
end

------------------------------------------------------------------------------------------------
-- Combo y avisos
------------------------------------------------------------------------------------------------

local function headOf(target: Player): BasePart?
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	return if head and head:IsA("BasePart") then head else nil
end

local function combo(a: any, b: any)
	if typeof(a) ~= "Instance" or typeof(b) ~= "Instance" or not a:IsA("Player") or not b:IsA("Player") then
		return
	end
	local ha, hb = headOf(a), headOf(b)
	if not ha or not hb then
		return
	end
	local camera = Workspace.CurrentCamera
	local middle = (ha.Position + hb.Position) / 2
	if camera and (camera.CFrame.Position - middle).Magnitude > SEEN then
		return
	end
	for _, head in { ha, hb } do
		confetti(head.Position + Vector3.new(0, 1.5, 0), 26)
	end
	local anchor = Instance.new("Part")
	anchor.Name = "EmoteCombo"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(middle + Vector3.new(0, 4.5, 0))
	anchor.Parent = confettiFolder or Workspace
	local gui = billboard(anchor, Vector3.zero, 300, 70)
	local box = Comic.frame(gui, Comic.Yellow)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.new(1, -10, 1, -10)
	box.Rotation = -4
	Comic.round(box, 12)
	Comic.ink(box, 4, true)
	local label = Comic.label(box, "¡COMBO DE MEMES!", Comic.Display, 36, Comic.Red)
	label.Size = UDim2.fromScale(1, 1)
	Comic.ink(label, 3)
	popIn(box)
	Comic.boil(box, 3)
	Debris:AddItem(gui, 2.4)
	Debris:AddItem(anchor, 2.4)
	if camera and (camera.CFrame.Position - middle).Magnitude < HEAR then
		Sfx.fanfare()
	end
	if a == player or b == player then
		Fx.shake(0.15)
	end
end

local function onEvent(kind: any, a: any, b: any)
	if kind == "Play" then
		if typeof(a) ~= "Instance" or not a:IsA("Player") or type(b) ~= "string" then
			return
		end
		local run = runs[a]
		if a == player and run and not run.preview and run.def.id == b and os.clock() - run.startedAt < 1.5 then
			return -- ya lo estás haciendo (se lanzó al pedirlo)
		end
		startRun(a, b, false)
	elseif kind == "Stop" then
		if typeof(a) == "Instance" and a:IsA("Player") then
			beginStop(a)
		end
	elseif kind == "Combo" then
		combo(a, b)
	elseif kind == "Unlocked" or kind == "Bought" then
		local def = Defs.byId[a]
		if def then
			Sfx.fanfare()
			Bubble.flash(if kind == "Unlocked" then "¡Cromo nuevo: " .. def.name .. "! Mantén Y para la rueda" else "¡" .. def.name .. " es mío!", 5)
			if kind == "Unlocked" and sideButton and not album.open then
				sideButton.setBadge(true)
			end
		end
		pendingWheel = nil
		if album.open then
			paintAlbum()
		end
	end
end

------------------------------------------------------------------------------------------------
-- Entrada
------------------------------------------------------------------------------------------------

local function buildTouchButton()
	if not UserInputService.TouchEnabled then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "EmoteButton"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = playerGui
	local holder = Comic.frame(gui)
	holder.Name = "Holder" -- en celular lo recoloca Abilities, junto a la rejilla de habilidades
	holder.AnchorPoint = Vector2.new(1, 1)
	holder.Position = UDim2.new(1, -24, 1, -200)
	holder.Size = UDim2.fromOffset(64, 64)
	Hud.fitScale(holder, 64)
	local face = Instance.new("TextButton")
	face.AutoButtonColor = false
	face.Text = ""
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = Color3.fromRGB(255, 170, 230)
	face.BorderSizePixel = 0
	face.Parent = holder
	Comic.round(face)
	Comic.ink(face, 4, true)
	drawIcon(face, Defs.byId.dab, 52)
	face.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if wheel.open then
			closeWheel(false)
			return
		end
		local camera = Workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else Vector2.new(800, 600)
		wheel.touch = input
		wheel.touchStart = pointerOf(input)
		openWheel(view / 2, "hold")
	end)
end

function Emotes.start(remoteFolder: Folder)
	local found = remoteFolder:WaitForChild("Emote", 60)
	if not found or not found:IsA("RemoteEvent") then
		warn("[CRUNCH!] Emotes: falta el remoto Emote")
		return
	end
	remote = found

	buildWheel()
	buildAlbum()
	buildTouchButton()
	sideButton = Hud.addSideButton("Memes", "Y", Color3.fromRGB(255, 170, 230), albumToggle)

	found.OnClientEvent:Connect(onEvent)
	local fx = remoteFolder:FindFirstChild("Fx")
	if fx and fx:IsA("RemoteEvent") then
		-- Morder corta tu emote ya en tu pantalla (el servidor avisa a las demás)
		fx.OnClientEvent:Connect(function(kind)
			if kind == "Bite" then
				beginStop(player)
			end
		end)
	end

	player:GetAttributeChangedSignal("EmoteWheel"):Connect(function()
		pendingWheel = nil
		if album.open then
			paintAlbum()
		end
	end)
	State.onChange(function()
		if album.open then
			paintAlbum()
		end
	end)

	-- Y: mantener abre la rueda, soltar lanza lo señalado; tocar sin elegir abre el álbum
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape and album.open then
			setAlbum(false)
		elseif input.KeyCode == Enum.KeyCode.Y and not processed and not wheel.open then
			wheel.touch = nil
			openWheel(UserInputService:GetMouseLocation(), "hold")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Y and wheel.open and not wheel.touch then
			-- Toque = soltar sin haber elegido nada y: rápido (por tiempo o por fotogramas, que el
			-- primer abrir puede dar un tirón de más de 0,25 s) o sin haber movido el ratón
			local quick = os.clock() - wheel.openedAt < 0.4 or wheel.frames <= 3
			local still = (UserInputService:GetMouseLocation() - wheel.openPointer).Magnitude < 12
			if wheel.hovered then
				closeWheel(true)
			elseif quick or still then
				closeWheel(false)
				albumToggle()
			else
				closeWheel(false)
			end
		elseif wheel.open and wheel.touch and input == wheel.touch then
			-- Dedo: si arrastró hacia un hueco, lo lanza; un toque corto deja la rueda abierta
			local quick = os.clock() - wheel.openedAt < 0.3
			if wheel.hovered then
				closeWheel(true)
			elseif quick then
				wheel.touch = nil
				wheel.mode = "sticky"
				setHovered(nil)
			else
				closeWheel(false)
			end
		end
		endDrag(input)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if drag then
			moveDrag(input)
		end
	end)
	UserInputService.TouchSwipe:Connect(function(direction)
		if wheel.open and wheel.mode == "sticky" then
			if direction == Enum.SwipeDirection.Left then
				flipPage(1)
			elseif direction == Enum.SwipeDirection.Right then
				flipPage(-1)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		updateWheel()
		if #bits > 0 then
			updateConfetti(math.min(dt, 0.1))
		end
	end)

	Players.PlayerRemoving:Connect(function(gone)
		local run = runs[gone]
		if run then
			finish(run)
		end
	end)
end

return Emotes
