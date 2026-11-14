-- Aliadas en el cliente: dibuja para todas las jugadoras la abeja mensajera, el escarabajo de carga,
-- la escolta y la lupa solar, y los efectos del imán, el pisotón, el tirachinas y el mega crunch.
-- Quién tiene qué sale de los atributos N_<mejora> de cada jugadora; los momentos (la abeja se lleva
-- la carga, la lupa quema, el pisotón...) llegan por el remoto "Allies" (ver src/server/Allies.luau).
-- Todo son piezas ancladas que se mueven de una vez con BulkMoveTo. Un solo Highlight de tinta.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

-- Los modelos de la abeja y el escarabajo son los de las mascotas; si faltan, unos sencillos
local PetModels = nil
do
	local module = ReplicatedStorage.Shared:FindFirstChild("PetModels")
	if module then
		local ok, lib = pcall(require, module)
		if ok then
			PetModels = lib
		end
	end
end

local Allies = {}

local player = Players.LocalPlayer
local rng = Random.new()
local A = Config.Allies

local PARK = CFrame.new(0, -500, 0)
local VIEW = 320 -- más lejos de la cámara no se dibujan
local NEAR = 220 -- efectos que solo se ven si pasan cerca
local SNAP = 60 -- más lejos que esto de su sitio, aparecen directamente allí
local BEE_SCALE = 1.5
local BEETLE_SCALE = 2
-- El escarabajo iba justo detrás (0, 0, 7,2): en la línea de la cámara, que lo tenía encima y tapaba
-- media pantalla. Ahora va a la derecha y algo detrás, con hueco según su tamaño y el de la hormiga.
local BEETLE_GAP = Vector3.new(1.6, 0, 1.2) -- aire entre la hormiga y el escarabajo (lado, detrás)
local BEETLE_MAX = 1.3 -- nunca más largo que 1,3 veces la hormiga
local BEETLE_FADE = 0.65 -- transparencia si aun así se mete entre la cámara y tu hormiga
local ESCORT_SLOTS = {
	Vector3.new(-3.4, 0, -0.6),
	Vector3.new(3.4, 0, -0.6),
	Vector3.new(-4.6, 0, 2.4),
	Vector3.new(4.6, 0, 2.4),
	Vector3.new(-1.8, 0, 9),
}
local ESCORT_FAN = { -0.55, 0.55, -1.1, 1.1, 0 } -- alrededor de la comida, en radianes desde tu lado
local MAX_ESCORTS = #ESCORT_SLOTS

local INK = Comic.Ink
local BEE_YELLOW = Color3.fromRGB(255, 205, 50)
local SOLDIER = Color3.fromRGB(150, 44, 46)
local SOLDIER_DARK = Color3.fromRGB(104, 30, 34)
local HELMET = Color3.fromRGB(176, 184, 200)
local BRASS = Color3.fromRGB(226, 168, 58)
local GLASS = Color3.fromRGB(176, 232, 255)
local WOOD = Color3.fromRGB(150, 96, 54)
local SATCHEL = Color3.fromRGB(196, 120, 62)
local SMOKE = Color3.fromRGB(122, 118, 128)

-- Lo que dice tu hormiga al estrenar cada aliada (pisotón y tirachinas los explica el árbol)
local INTRO = {
	bee = "¡Tengo abeja mensajera! Vendrá a por mi carga",
	magnet = "Las migas pequeñas ya vienen solas a mí",
	beetle = "Mi escarabajo carga lo que no me cabe",
	escort = "¡Mi escolta muerde conmigo!",
	lens = "La lupa quemará comida para mí",
	mega = "Si muerdo sin parar, llega el MEGA CRUNCH",
}

local container: Model
local fxFolder: Folder
local focus: Vector3? = nil -- tu hormiga, para ver si un escarabajo se pone entre ella y la cámara
local camNow = Vector3.zero
local remote: RemoteEvent? = nil
local rigs: { [Player]: any } = {}
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local n = 0

---------------------------------------------------------------------------------------------------
-- Piezas y modelos

local function newPart(parent: Instance?, size: Vector3, color: Color3, kind: string?): Part
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
	p.CFrame = PARK
	if kind == "rod" then
		p.Shape = Enum.PartType.Cylinder
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function blob(model: Model, size: Vector3, color: Color3, at: Vector3, rotation: CFrame?): Part
	local p = newPart(model, size, color)
	p.CFrame = CFrame.new(at) * (rotation or CFrame.identity)
	return p
end

-- Ala o mandíbula que gira sobre una bisagra: Flap gira en Z (aleteo), Jaw en Y (mordisco)
local function hinged(p: Part, hinge: CFrame, side: number, attribute: string)
	p:SetAttribute("Hinge", hinge)
	p:SetAttribute(attribute, side)
end

local function fallbackBee(): Model
	local m = Instance.new("Model")
	m.Name = "Abeja"
	blob(m, Vector3.new(1.25, 1.15, 1.7), BEE_YELLOW, Vector3.new(0, 0, 0.25))
	blob(m, Vector3.new(1.29, 1.19, 0.26), INK, Vector3.new(0, 0, 0.25))
	blob(m, Vector3.new(0.9, 0.85, 0.8), INK, Vector3.new(0, 0.12, -0.75))
	for _, s in { -1, 1 } do
		local hinge = CFrame.new(s * 0.3, 0.55, 0.05)
		local wing = blob(m, Vector3.new(0.95, 0.06, 0.55), Color3.fromRGB(222, 244, 255), (hinge * CFrame.new(s * 0.45, 0.1, 0)).Position)
		wing.Transparency = 0.3
		hinged(wing, hinge, s, "Flap")
	end
	m:SetAttribute("Height", 0.6)
	return m
end

local function fallbackBeetle(): Model
	local m = Instance.new("Model")
	m.Name = "Escarabajo"
	blob(m, Vector3.new(1.45, 0.95, 1.8), Color3.fromRGB(92, 72, 176), Vector3.new(0, 0.05, 0.25))
	blob(m, Vector3.new(1.1, 0.8, 0.8), Color3.fromRGB(72, 56, 140), Vector3.new(0, 0.1, -0.7))
	blob(m, Vector3.new(0.75, 0.6, 0.55), Color3.fromRGB(44, 32, 66), Vector3.new(0, 0, -1.1))
	m:SetAttribute("Height", 0.65)
	return m
end

local function petModel(species: string, fallback: () -> Model): Model
	if PetModels then
		local ok, model = pcall(PetModels.build, species, 1, true)
		if ok and typeof(model) == "Instance" then
			return model
		end
	end
	return fallback()
end

-- Soldado de la escolta: cabeza con casco, mandíbulas que muerden, tres pares de patas
local function buildEscort(): Model
	local m = Instance.new("Model")
	m.Name = "Escolta"
	blob(m, Vector3.new(1.1, 0.95, 1.35), SOLDIER_DARK, Vector3.new(0, 0.1, 0.85))
	blob(m, Vector3.new(0.7, 0.62, 0.75), SOLDIER, Vector3.new(0, 0, 0))
	blob(m, Vector3.new(1.05, 0.9, 0.95), SOLDIER, Vector3.new(0, 0.12, -0.72))
	blob(m, Vector3.new(1.14, 0.5, 0.92), HELMET, Vector3.new(0, 0.48, -0.74))
	for _, s in { -1, 1 } do
		blob(m, Vector3.new(0.26, 0.3, 0.2), Color3.new(1, 1, 1), Vector3.new(s * 0.3, 0.18, -1.15))
		local hinge = CFrame.new(s * 0.3, -0.05, -1.1)
		local jaw = blob(m, Vector3.new(0.24, 0.2, 0.8), INK, (hinge * CFrame.new(s * 0.05, 0, -0.35)).Position)
		hinged(jaw, hinge, s, "Jaw")
	end
	for _, z in { -0.3, 0.05, 0.4 } do
		local leg = newPart(m, Vector3.new(2, 0.11, 0.11), INK, "rod")
		leg.CFrame = CFrame.new(0, -0.3, z)
	end
	m:SetAttribute("Height", 0.55)
	return m
end

-- Lupa: aro de latón, cristal y mango. El cristal mira hacia abajo.
local function buildLens(): Model
	local m = Instance.new("Model")
	m.Name = "Lupa"
	local face = CFrame.Angles(0, 0, math.pi / 2) -- el eje del cilindro, vertical
	newPart(m, Vector3.new(0.3, 4.2, 4.2), BRASS, "rod").CFrame = face
	local glass = newPart(m, Vector3.new(0.38, 3.4, 3.4), GLASS, "rod")
	glass.CFrame = face
	glass.Transparency = 0.45
	newPart(m, Vector3.new(2.6, 0.6, 0.6), WOOD, "rod").CFrame = CFrame.new(3.2, 0, 0)
	blob(m, Vector3.new(0.8, 0.12, 0.5), Color3.new(1, 1, 1), Vector3.new(-0.7, 0.25, -0.8)).Transparency = 0.2
	return m
end

-- Kit: las piezas de un modelo con su sitio relativo al origen, ya escaladas
local function kit(model: Model, scale: number)
	local origin = if model.PrimaryPart then model.PrimaryPart.CFrame else CFrame.identity
	local k = {
		model = model,
		parts = {},
		offsets = {},
		hinges = {},
		height = ((model:GetAttribute("Height") :: number?) or 0.6) * scale,
		shown = false,
		-- Medidas a la escala de partida, para poder encogerlo luego (resize)
		baseSizes = {},
		baseOffsets = {},
		baseHinges = {},
		factor = 1,
		length = 0,
		width = 0,
	}
	k.baseHeight = k.height
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		if d.Transparency >= 1 then
			d:Destroy() -- la raíz invisible de las mascotas
			continue
		end
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		local offset = origin:ToObjectSpace(d.CFrame)
		offset = offset.Rotation + offset.Position * scale
		d.Size *= scale
		d.CFrame = PARK
		table.insert(k.parts, d)
		local i = #k.parts
		k.offsets[i] = offset
		k.baseSizes[i] = d.Size
		k.baseOffsets[i] = offset
		-- Planta del modelo (mira hacia -Z): largo en Z, ancho en X
		local half = d.Size / 2
		local r, u, b = offset.RightVector * half.X, offset.UpVector * half.Y, offset.LookVector * half.Z
		local ex = math.abs(r.X) + math.abs(u.X) + math.abs(b.X)
		local ez = math.abs(r.Z) + math.abs(u.Z) + math.abs(b.Z)
		minX, maxX = math.min(minX, offset.X - ex), math.max(maxX, offset.X + ex)
		minZ, maxZ = math.min(minZ, offset.Z - ez), math.max(maxZ, offset.Z + ez)
		local hinge = d:GetAttribute("Hinge")
		local flap = d:GetAttribute("Flap")
		local jaw = d:GetAttribute("Jaw")
		if typeof(hinge) == "CFrame" and (type(flap) == "number" or type(jaw) == "number") then
			local h = hinge.Rotation + hinge.Position * scale
			k.hinges[i] = { hinge = h, rel = h:ToObjectSpace(offset), side = flap or jaw, yaw = type(jaw) == "number" }
			k.baseHinges[i] = h
		end
	end
	if #k.parts > 0 then
		k.length, k.width = maxZ - minZ, maxX - minX
	end
	return k
end

-- Encoge (o devuelve) un kit a `factor` de su escala de partida. Solo toca las piezas si cambia.
local function resize(k, factor: number)
	if math.abs(factor - k.factor) < 0.04 then
		return
	end
	k.factor = factor
	for i, part in k.parts do
		part.Size = k.baseSizes[i] * factor
		local o = k.baseOffsets[i]
		k.offsets[i] = o.Rotation + o.Position * factor
		local hb = k.baseHinges[i]
		if hb and k.hinges[i] then
			local h = hb.Rotation + hb.Position * factor
			k.hinges[i].hinge = h
			k.hinges[i].rel = h:ToObjectSpace(k.offsets[i])
		end
	end
	k.height = k.baseHeight * factor
end

local function push(part: BasePart, cframe: CFrame)
	n += 1
	moveParts[n] = part
	moveFrames[n] = cframe
end

local function place(k, base: CFrame, flap: number, jaw: number)
	if not k.shown then
		k.model.Parent = container
		k.shown = true
	end
	for i, part in k.parts do
		local h = k.hinges[i]
		if h then
			local turn = if h.yaw then CFrame.Angles(0, h.side * jaw, 0) else CFrame.Angles(0, 0, h.side * flap)
			push(part, base * h.hinge * turn * h.rel)
		else
			push(part, base * k.offsets[i])
		end
	end
end

local function hide(k)
	if k and k.shown then
		k.model.Parent = nil
		k.shown = false
	end
end

local function drop(k)
	if k then
		k.model:Destroy()
	end
end

---------------------------------------------------------------------------------------------------
-- Efectos sueltos

local function arc(a: Vector3, b: Vector3, u: number, height: number): Vector3
	local e = u * u * (3 - 2 * u)
	return a:Lerp(b, e) + Vector3.new(0, math.sin(e * math.pi) * height, 0)
end

local function near(position: Vector3): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < NEAR
end

-- Onda en el suelo que se abre y se apaga
local function ring(position: Vector3, radius: number, color: Color3, life: number)
	local p = newPart(fxFolder, Vector3.new(0.3, 1.5, 1.5), color, "rod")
	p.Transparency = 0.1
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, life + 0.1)
end

local function puff(position: Vector3)
	for _ = 1, 4 do
		local s = rng:NextNumber(0.8, 1.4)
		local p = newPart(fxFolder, Vector3.new(s, s, s), SMOKE)
		p.Transparency = 0.25
		p.CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1), 0.5, rng:NextNumber(-1, 1)))
		TweenService:Create(p, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = p.CFrame + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(3, 5), rng:NextNumber(-1, 1)),
			Size = Vector3.new(s, s, s) * 2.2,
			Transparency = 1,
		}):Play()
		Debris:AddItem(p, 1.2)
	end
end

-- Trozos que vuelan en arco: piscina fija, el más viejo cede el sitio
local BIT_POOL = 32
local bits = {}
local nextBit = 0

local function launch(from: Vector3, to: Vector3 | BasePart, color: Color3, size: number, duration: number, height: number, delay: number?, onLand: (() -> ())?)
	if #bits == 0 then
		return
	end
	nextBit = nextBit % #bits + 1
	local b = bits[nextBit]
	b.part.Color = color
	b.part.Size = Vector3.new(size, size * 0.85, size)
	b.from = from
	b.to = to
	b.t0 = os.clock() + (delay or 0)
	b.duration = duration
	b.height = height
	b.onLand = onLand
	b.spin = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10))
	b.active = true
end

local function updateBits(now: number)
	for _, b in bits do
		if not b.active then
			continue
		end
		local t = now - b.t0
		if t < 0 then
			push(b.part, PARK)
			continue
		end
		local to = b.to
		local goal = if typeof(to) == "Vector3" then to else (if to.Parent then to.Position + Vector3.new(0, 1, 0) else b.from)
		local u = math.min(t / b.duration, 1)
		if u >= 1 then
			b.active = false
			push(b.part, PARK)
			if b.onLand then
				task.spawn(b.onLand)
			end
			continue
		end
		push(b.part, CFrame.new(arc(b.from, goal, u, b.height)) * CFrame.Angles(b.spin.X * t, b.spin.Y * t, b.spin.Z * t))
	end
end

---------------------------------------------------------------------------------------------------
-- Aliadas de cada jugadora

local function rigOf(target: Player)
	local rig = rigs[target]
	if not rig then
		rig = { escorts = {}, levels = {} }
		rigs[target] = rig
	end
	return rig
end

local function dropRig(target: Player)
	local rig = rigs[target]
	if not rig then
		return
	end
	if rig.bee then
		drop(rig.bee.kit)
	end
	if rig.beetle then
		drop(rig.beetle.kit)
	end
	if rig.lens then
		drop(rig.lens.kit)
	end
	for _, escort in rig.escorts do
		drop(escort.kit)
	end
	rigs[target] = nil
end

local function level(target: Player, id: string): number
	local value = target:GetAttribute("N_" .. id)
	return if type(value) == "number" then value else 0
end

local function newBee()
	local model = petModel("abeja", fallbackBee)
	local k = kit(model, BEE_SCALE)
	-- Cartera de cartera: la abeja es mensajera
	local satchel = newPart(model, Vector3.new(0.75, 0.65, 0.55) * BEE_SCALE, SATCHEL)
	local chunk = newPart(model, Vector3.new(1, 1, 1), Comic.Crumb)
	return { kit = k, satchel = satchel, chunk = chunk, pos = nil :: Vector3?, heading = -Vector3.zAxis, trip = nil }
end

local function newBeetle()
	local model = petModel("escarabajo", fallbackBeetle)
	local k = kit(model, BEETLE_SCALE)
	local pile = newPart(model, Vector3.new(1, 1, 1), Comic.Crumb)
	return { kit = k, pile = pile, pos = nil :: Vector3?, yaw = 0, step = 0, fade = 0 }
end

local function newEscort(index: number)
	return { kit = kit(buildEscort(), 1), index = index, pos = nil :: Vector3?, heading = -Vector3.zAxis, stride = rng:NextNumber(0, 4), seed = rng:NextNumber() }
end

local function headingCFrame(position: Vector3, heading: Vector3): CFrame
	local flat = Vector3.new(heading.X, 0, heading.Z)
	if flat.Magnitude < 1e-3 then
		flat = -Vector3.zAxis
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

-- Punto de la boca de la hormiga (o del trozo que lleva)
local function mouthOf(character: Model, root: BasePart, scale: number): Vector3
	local chunk = character:FindFirstChild("CarryChunk")
	if chunk and chunk:IsA("BasePart") then
		return chunk.Position
	end
	return root.Position + root.CFrame.LookVector * (1.6 * scale) + Vector3.new(0, 0.3 * scale, 0)
end

local function updateBee(rig, owner, now: number, dt: number)
	local bee = rig.bee
	local scale = owner.scale
	local idle = owner.root.Position + owner.turn:VectorToWorldSpace(Vector3.new(2.6, 3.4, 1.2) * scale)
		+ Vector3.new(0, math.sin(now * 2.6 + owner.phase) * 0.35, 0)
	local pos = bee.pos or idle
	if (pos - idle).Magnitude > SNAP and not bee.trip then
		pos = idle
	end
	local carrying = false
	local trip = bee.trip
	if trip then
		local t = now - trip.t0
		local back = trip.approach + trip.fly
		if t < trip.approach then
			local mouth = mouthOf(owner.character, owner.root, scale) + Vector3.new(0, 1.2 * scale, 0)
			pos = trip.start:Lerp(mouth, math.min(t / trip.approach, 1))
		elseif t < back then
			if not trip.grab then
				trip.grab = pos
				Sfx.pop(1.4)
			end
			local distance = (trip.target - trip.grab).Magnitude
			pos = arc(trip.grab, trip.target + Vector3.new(0, 2, 0), (t - trip.approach) / trip.fly, math.min(8 + distance * 0.08, 60))
			carrying = true
		elseif t < back + trip.fly then
			if not trip.dropped then
				trip.dropped = true
				if near(trip.target) then
					Fx.crumbs(trip.target, trip.color, 6)
				end
			end
			local from = trip.target + Vector3.new(0, 2, 0)
			pos = arc(from, idle, (t - back) / trip.fly, math.min(8 + (idle - from).Magnitude * 0.06, 40))
		else
			bee.trip = nil
		end
	end
	if not bee.trip then
		pos = pos:Lerp(idle, 1 - math.exp(-dt * 6))
	end
	local moved = pos - (bee.pos or pos)
	bee.pos = pos
	if Vector3.new(moved.X, 0, moved.Z).Magnitude > 0.02 then
		bee.heading = bee.heading:Lerp(moved.Unit, math.min(1, dt * 10))
	elseif not bee.trip then
		bee.heading = bee.heading:Lerp(owner.look, math.min(1, dt * 4))
	end
	local base = headingCFrame(pos, bee.heading)
	place(bee.kit, base, math.sin(now * 32 + owner.phase) * 0.6, 0)
	push(bee.satchel, base * CFrame.new(0.72 * BEE_SCALE, -0.3 * BEE_SCALE, 0.25 * BEE_SCALE))
	if carrying then
		local side = 0.9 * scale + 0.4
		bee.chunk.Size = Vector3.new(side, side, side)
		if bee.chunk.Color ~= trip.color then
			bee.chunk.Color = trip.color
		end
		push(bee.chunk, base * CFrame.new(0, -0.9 * BEE_SCALE - side * 0.4, 0) * CFrame.Angles(0.3, now * 3, 0.2))
	else
		push(bee.chunk, PARK)
	end
end

-- ¿Está `point` (con radio `radius`) entre la cámara y tu hormiga? Devuelve el punto más cercano
-- de esa línea si lo está.
local function blocking(point: Vector3, radius: number): Vector3?
	local target = focus
	if not target then
		return nil
	end
	local line = target - camNow
	local len2 = line:Dot(line)
	if len2 < 1 then
		return nil
	end
	local t = (point - camNow):Dot(line) / len2
	if t <= 0 or t >= 1 then
		return nil
	end
	local closest = camNow + line * t
	return if (point - closest).Magnitude < radius then closest else nil
end

local function updateBeetle(rig, owner, target: Player, now: number, dt: number)
	local beetle = rig.beetle
	local k = beetle.kit
	-- Tamaño: como mucho BEETLE_MAX veces lo que mide la hormiga (caja alineada con su raíz)
	if not rig.antAt or now - rig.antAt > 1 then
		rig.antAt = now
		local ok, ext = pcall(function()
			return owner.character:GetExtentsSize()
		end)
		if ok and typeof(ext) == "Vector3" then
			rig.antLen = math.max(ext.Z, ext.X, 0.5)
			rig.antWidth = math.max(ext.X, 0.5)
		end
	end
	local antLen = rig.antLen or 3 * owner.scale
	local antWidth = rig.antWidth or 2 * owner.scale
	if k.length > 0 then
		resize(k, math.clamp(BEETLE_MAX * antLen / k.length, 0.25, 1))
	end
	local length, width = k.length * k.factor, k.width * k.factor
	-- Sitio: a la derecha de la hormiga y algo detrás (no en la línea de la cámara)
	local slot = Vector3.new(antWidth / 2 + width / 2 + BEETLE_GAP.X, 0, antLen / 2 + length / 2 + BEETLE_GAP.Z)
	local goal = owner.ground + owner.turn:VectorToWorldSpace(slot)
	-- Si aun así su sitio queda entre la cámara y tu hormiga, se aparta hacia un lado
	local radius = math.max(length, width) * 0.5
	if target == player then
		local closest = blocking(goal + Vector3.new(0, k.height, 0), radius + 1.5)
		if closest then
			local away = goal - closest
			away = Vector3.new(away.X, 0, away.Z)
			if away.Magnitude < 0.05 then
				away = owner.turn:VectorToWorldSpace(Vector3.xAxis)
			end
			local push = closest + away.Unit * (radius + 1.5)
			goal = Vector3.new(push.X, owner.ground.Y, push.Z)
		end
	end
	local pos = beetle.pos
	if not pos or (pos - goal).Magnitude > SNAP then
		pos = goal
	end
	local nextPos = pos:Lerp(goal, 1 - math.exp(-dt * 4))
	local moved = nextPos - pos
	local speed = Vector3.new(moved.X, 0, moved.Z).Magnitude / math.max(dt, 1e-3)
	beetle.pos = nextPos
	local wantYaw = if speed > 1 then math.atan2(-moved.X, -moved.Z) else owner.yaw
	local diff = (wantYaw - beetle.yaw + math.pi) % (2 * math.pi) - math.pi
	beetle.yaw += diff * math.min(1, dt * 6)
	if speed > 0.8 then
		beetle.step += dt * (5 + speed * 0.6)
	end
	local lift = beetle.kit.height + math.abs(math.sin(beetle.step)) * 0.12 * math.clamp(speed / 4, 0, 1)
	local base = CFrame.new(nextPos + Vector3.new(0, lift, 0)) * CFrame.Angles(0, beetle.yaw, 0)
	place(beetle.kit, base, 0, 0)
	-- Mientras pasa por delante de la cámara (al girarla, por ejemplo), se vuelve semitransparente
	local want = if blocking(nextPos + Vector3.new(0, lift, 0), radius + 0.5) then BEETLE_FADE else 0
	if beetle.fade ~= want then
		local fade = beetle.fade + (want - beetle.fade) * math.min(1, dt * 8)
		if math.abs(want - fade) < 0.02 then
			fade = want
		end
		beetle.fade = fade
		for _, part in k.parts do
			part.LocalTransparencyModifier = fade
		end
		beetle.pile.LocalTransparencyModifier = fade
	end
	local s = BEETLE_SCALE * k.factor

	-- Lo que no te cabe a ti va en su lomo
	local carry = tonumber(target:GetAttribute("Carry")) or 0
	local capacity = tonumber(target:GetAttribute("Capacity")) or 0
	local share = A.Beetle.Share * level(target, "beetle")
	local own = capacity / (1 + share)
	local fill = if capacity > own then math.clamp((carry - own) / (capacity - own), 0, 1) else 0
	if fill > 0 then
		local chunk = owner.character:FindFirstChild("CarryChunk")
		local color = if chunk and chunk:IsA("BasePart") then chunk.Color else Comic.Crumb
		if beetle.pile.Color ~= color then
			beetle.pile.Color = color
		end
		local side = (0.7 + 1.5 * fill) * s * 0.5
		beetle.pile.Size = Vector3.new(side * 1.2, side, side * 1.1)
		push(beetle.pile, base * CFrame.new(0, 0.45 * s + side * 0.35, 0.25 * s) * CFrame.Angles(0.15, 0.4, 0))
	else
		push(beetle.pile, PARK)
	end
end

local function updateEscorts(rig, owner, count: number, now: number, dt: number)
	local escorts = rig.escorts
	while #escorts < count do
		table.insert(escorts, newEscort(#escorts + 1))
	end
	while #escorts > count do
		drop(table.remove(escorts).kit)
	end
	local focus = rig.focus
	local busy = focus ~= nil and now < focus.untilT
	for i, escort in escorts do
		local goal: Vector3
		local face: Vector3? = nil
		local lunge = 0
		if busy then
			-- En corro alrededor de la comida, por tu lado
			local away = (owner.root.Position - focus.pos) * Vector3.new(1, 0, 1)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.zAxis
			local dir = CFrame.Angles(0, ESCORT_FAN[i] or 0, 0):VectorToWorldSpace(away)
			goal = Vector3.new(focus.pos.X, owner.ground.Y, focus.pos.Z) + dir * (focus.radius + 1.1)
			face = -dir
			local k = (now - focus.biteAt - (i - 1) * 0.06) / 0.25
			if k > 0 and k < 1 then
				lunge = math.sin(k * math.pi)
			end
		else
			goal = owner.ground + owner.turn:VectorToWorldSpace(ESCORT_SLOTS[i] * owner.scale)
		end
		local pos = escort.pos
		if not pos or (pos - goal).Magnitude > SNAP then
			pos = goal
		end
		local nextPos = pos:Lerp(goal, 1 - math.exp(-dt * 7))
		local moved = nextPos - pos
		escort.pos = nextPos
		local flat = Vector3.new(moved.X, 0, moved.Z)
		escort.stride += flat.Magnitude
		local desired = if flat.Magnitude > 0.03 then flat.Unit else (face or owner.look)
		escort.heading = escort.heading:Lerp(desired, math.min(1, dt * 10))
		local bob = math.abs(math.sin(escort.stride * 2.2)) * 0.15
		local forward = Vector3.new(escort.heading.X, 0, escort.heading.Z)
		forward = if forward.Magnitude > 1e-3 then forward.Unit else -Vector3.zAxis
		local at = nextPos + forward * (lunge * 0.7) + Vector3.new(0, escort.kit.height + bob, 0)
		local jaw = 0.25 + 0.15 * math.sin(now * 5 + escort.seed * 20) - lunge * 0.4
		place(escort.kit, headingCFrame(at, forward) * CFrame.Angles(-lunge * 0.25, 0, 0), 0, jaw)
	end
end

local function updateLens(rig, owner, now: number)
	local lens = rig.lens
	local job = lens.job
	if not job then
		hide(lens.kit)
		return
	end
	local t = now - job.t0
	local over = job.target + Vector3.new(0, 9 + job.radius * 0.3, 0)
	local start = owner.root.Position + owner.turn:VectorToWorldSpace(Vector3.new(-2.5, 4, 0.5) * owner.scale)
	local pos: Vector3
	if t < 0.35 then
		pos = arc(start, over, t / 0.35, 2)
	elseif t < job.delay then
		pos = over
		if not job.beam then
			-- Rayo de sol del cristal a la comida, y un punto ardiendo
			local length = (over - job.target).Magnitude
			local beam = newPart(fxFolder, Vector3.new(length, 0.55, 0.55), Color3.fromRGB(255, 236, 120), "rod")
			beam.Material = Enum.Material.Neon
			beam.Transparency = 0.25
			beam.CFrame = CFrame.lookAt((over + job.target) / 2, job.target) * CFrame.Angles(0, math.pi / 2, 0)
			local spot = newPart(fxFolder, Vector3.new(1.4, 0.4, 1.4), Color3.fromRGB(255, 150, 40))
			spot.Material = Enum.Material.Neon
			spot.CFrame = CFrame.new(job.target + Vector3.new(0, 0.6, 0))
			Debris:AddItem(beam, job.delay - t + 0.1)
			Debris:AddItem(spot, job.delay - t + 0.1)
			job.beam = beam
		end
	elseif t < job.delay + 0.5 then
		if not job.burnt then
			job.burnt = true
			if near(job.target) then
				puff(job.target + Vector3.new(0, 1, 0))
				Fx.crumbs(job.target + Vector3.new(0, 1, 0), Color3.fromRGB(90, 56, 40), 5)
			end
		end
		pos = arc(over, start, (t - job.delay) / 0.5, 2)
	else
		lens.job = nil
		hide(lens.kit)
		return
	end
	place(lens.kit, CFrame.new(pos) * CFrame.Angles(0, owner.yaw, 0) * CFrame.Angles(0, 0, 0.15), 0, 0)
end

local function hideRig(rig, forget: boolean)
	for _, key in { "bee", "beetle", "lens" } do
		local item = rig[key]
		if item then
			hide(item.kit)
			if forget then
				item.pos = nil
			end
		end
	end
	for _, escort in rig.escorts do
		hide(escort.kit)
		if forget then
			escort.pos = nil
		end
	end
end

-- Crea o quita cada aliada según su nivel
local function syncRig(target: Player, rig)
	local function want(key: string, id: string, make: () -> any)
		local has = level(target, id) > 0
		if has and not rig[key] then
			rig[key] = make()
		elseif not has and rig[key] then
			drop(rig[key].kit)
			rig[key] = nil
		end
	end
	want("bee", "bee", newBee)
	want("beetle", "beetle", newBeetle)
	want("lens", "lens", function()
		return { kit = kit(buildLens(), 1), job = nil }
	end)
end

local function step(rawDt: number)
	local dt = math.min(rawDt, 0.1)
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	n = 0
	camNow = camPos
	local myCharacter = player.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	focus = if myRoot and myRoot:IsA("BasePart") then myRoot.Position else nil

	for _, target in Players:GetPlayers() do
		local escortCount = math.min(level(target, "escort"), MAX_ESCORTS)
		local rig = rigs[target]
		if not rig then
			if level(target, "bee") + level(target, "beetle") + level(target, "lens") + escortCount <= 0 then
				continue
			end
			rig = rigOf(target)
		end
		syncRig(target, rig)

		local character = target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
			hideRig(rig, true)
			continue
		end
		if (root.Position - camPos).Magnitude > VIEW then
			hideRig(rig, true)
			continue
		end

		local scale = character:GetScale()
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else -Vector3.zAxis
		local yaw = math.atan2(-flatLook.X, -flatLook.Z)
		local groundY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
		rig.phase = rig.phase or rng:NextNumber(0, 6)
		local owner = {
			character = character,
			root = root,
			scale = scale,
			look = flatLook,
			yaw = yaw,
			turn = CFrame.Angles(0, yaw, 0),
			ground = Vector3.new(root.Position.X, groundY, root.Position.Z),
			phase = rig.phase,
		}

		if rig.bee then
			updateBee(rig, owner, now, dt)
		end
		if rig.beetle then
			updateBeetle(rig, owner, target, now, dt)
		end
		updateEscorts(rig, owner, escortCount, now, dt)
		if rig.lens then
			updateLens(rig, owner, now)
		end
	end

	updateBits(now)

	for i = #moveParts, n + 1, -1 do
		moveParts[i] = nil
		moveFrames[i] = nil
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------------------------------
-- Sucesos del servidor

local function isPlayer(value: any): boolean
	return typeof(value) == "Instance" and value:IsA("Player") and value.Parent ~= nil
end

local function color3(value: any): Color3
	return if typeof(value) == "Color3" then value else Comic.Crumb
end

local function groundUnder(owner: Player, fallback: Vector3): Vector3
	local character = owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid then
		return Vector3.new(fallback.X, root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight + 0.2, fallback.Z)
	end
	return fallback
end

local function onEvent(kind: string, a: any, b: any, c: any, d: any, e: any, f: any)
	local mine = a == player
	if kind == "Bee" and isPlayer(a) and typeof(b) == "Vector3" then
		local rig = rigOf(a)
		syncRig(a, rig)
		local bee = rig.bee
		if bee then
			bee.trip = {
				t0 = os.clock(),
				approach = tonumber(c) or A.Bee.Approach,
				fly = math.max(tonumber(d) or 2, 0.5),
				target = b,
				color = color3(e),
				start = bee.pos or b,
				grab = nil,
				dropped = false,
			}
		end
	elseif kind == "Magnet" and isPlayer(a) and typeof(b) == "Vector3" then
		local character = a.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and near(b) then
			for i = 1, 3 do
				launch(b + Vector3.new(0, 1, 0), root, color3(c), rng:NextNumber(0.35, 0.6), rng:NextNumber(0.35, 0.5), rng:NextNumber(2, 4), (i - 1) * 0.06, if mine and i == 3 then function()
					Sfx.pop(1.7)
				end else nil)
			end
		end
	elseif kind == "Escort" and isPlayer(a) and typeof(b) == "Vector3" then
		local rig = rigOf(a)
		local now = os.clock()
		rig.focus = { pos = b, radius = tonumber(c) or 2, untilT = now + A.Escort.Linger, biteAt = now }
		if near(b) then
			Fx.crumbs(b + Vector3.new(0, 1, 0), color3(d), 2)
		end
	elseif kind == "Lens" and isPlayer(a) and typeof(b) == "Vector3" then
		local rig = rigOf(a)
		syncRig(a, rig)
		if rig.lens then
			rig.lens.job = { t0 = os.clock(), target = b, radius = tonumber(c) or 2, delay = tonumber(d) or A.Lens.Delay }
		end
	elseif kind == "Mega" and isPlayer(a) and typeof(b) == "Vector3" then
		if near(b) then
			Fx.burst(b, "¡MEGA\nCRUNCH!", Comic.Red, 230)
			ring(groundUnder(a, b), A.Mega.Radius, Color3.fromRGB(255, 140, 40), 0.45)
			Fx.crumbs(b, nil, 8)
			Sfx.bite(true)
		end
		if mine then
			Fx.shake(0.8)
			Sfx.fanfare()
		end
	elseif kind == "Stomp" and isPlayer(a) and typeof(b) == "Vector3" then
		local radius = tonumber(c) or 10
		if near(b) then
			local ground = groundUnder(a, b)
			ring(ground, radius, Comic.Yellow, 0.45)
			task.delay(0.08, ring, ground, radius * 0.7, Comic.Paper, 0.4)
			Fx.burst(b + Vector3.new(0, 1, 0), "¡BOOM!", Comic.Yellow, 180)
			Fx.crumbs(ground + Vector3.new(0, 0.5, 0), Comic.DirtLight, 10)
			Sfx.bite(true)
			Sfx.pop(0.55)
			if not mine then
				Fx.shake(0.15)
			end
		end
		if mine then
			Fx.shake(0.65)
		end
	elseif kind == "Sling" and isPlayer(a) and typeof(b) == "Vector3" and typeof(c) == "Vector3" then
		local fly = math.max(tonumber(d) or 2, 0.5)
		local tint = color3(e)
		local size = 1.2 + 1.4 * math.clamp(tonumber(f) or 0.5, 0, 1)
		local height = math.min(20 + (c - b).Magnitude * 0.12, 120)
		launch(b, c, tint, size, fly, height, 0, function()
			if near(c) then
				Fx.crumbs(c, tint, 10)
				ring(c - Vector3.new(0, 1, 0), 6, Comic.Paper, 0.35)
			end
		end)
		if mine then
			Sfx.pop(0.6)
			Fx.shake(0.25)
		end
	elseif kind == "Delivered" and typeof(a) == "Vector3" then
		-- Entrega a distancia (abeja o tirachinas): como la de a pie
		local credited = tonumber(b) or 0
		if c == true then
			Fx.burst(a, "¡DOBLE!\n+" .. Format.short(credited), Comic.Yellow, 240)
		else
			Fx.burst(a, "+" .. Format.short(credited), Comic.Cyan, 200)
		end
		Fx.crumbs(a, nil, 6)
		Fx.shake(if d == true then 0.35 else 0.12)
		Sfx.deposit()
		Hud.punchFood()
	elseif kind == "LensBurn" and typeof(a) == "Vector3" then
		Fx.number(a + Vector3.new(0, 2, 0), tonumber(b) or 0, true)
		Sfx.pop(0.8)
		Hud.punchFood()
	elseif kind == "Full" then
		Hud.shakeCarry()
	end
end

-- Al estrenar una aliada, tu hormiga cuenta qué hace (una vez por mejora y sesión, no al entrar)
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

function Allies.start(remotes: Folder)
	container = Instance.new("Model")
	container.Name = "Allies"
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Comic.Ink
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = container
	container.Parent = Workspace

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "AlliesFx"
	fxFolder.Parent = Workspace

	for _ = 1, BIT_POOL do
		local part = newPart(container, Vector3.new(0.5, 0.5, 0.5), Comic.Crumb)
		table.insert(bits, { part = part, active = false, t0 = 0, duration = 1, height = 0, from = Vector3.zero, to = Vector3.zero, spin = Vector3.zero })
	end

	Players.PlayerRemoving:Connect(dropRig)
	State.onChange(announce)
	RunService.Heartbeat:Connect(step)

	local found = remotes:WaitForChild("Allies", 30)
	if found and found:IsA("RemoteEvent") then
		remote = found
		found.OnClientEvent:Connect(onEvent)
	else
		warn("[CRUNCH!] Falta el remoto Allies")
	end
end

return Allies
