-- Modelos de las mascotas, hechos con piezas: elipsoides (bloque con malla de esfera) y
-- cilindros, colores planos y ojos grandes. Miden 1.5-2.5 studs. El frente es -Z.
-- Todas las piezas van ancladas y sin colisión: quien las usa las mueve en bloque.
-- El contorno de tinta lo pone quien llama (un Highlight en el contenedor).
--
-- Atributos que deja en el modelo y sus piezas:
--   Model.Height: distancia del suelo al centro de la pieza Root
--   Model.Gait: "hop", "crawl" o "fly"
--   Pieza.Hinge (CFrame relativo a Root) y Pieza.Flap (-1 o 1): alas que aletean sobre su eje Z

local PetDefs = require(script.Parent.PetDefs)

local PetModels = {}

local INK = Color3.fromRGB(26, 20, 22)
local WHITE = Color3.new(1, 1, 1)
local WING = Color3.fromRGB(222, 244, 255)

local function make(model: Model, name: string, size: Vector3, color: Color3, cf: CFrame, kind: string?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if kind == "rod" then
		part.Shape = Enum.PartType.Cylinder
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.CFrame = cf
	part.Parent = model
	return part
end

local function blob(model, name, size: Vector3, color: Color3, at: Vector3, rotation: CFrame?): Part
	return make(model, name, size, color, CFrame.new(at) * (rotation or CFrame.identity))
end

-- Cilindro de a hasta b
local function segment(model, name, a: Vector3, b: Vector3, thickness: number, color: Color3): Part
	local length = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
	return make(model, name, Vector3.new(length, thickness, thickness), color, cf, "rod")
end

-- Par de ojos de dibujo animado: blanco, pupila y brillo
local function eyes(model, center: Vector3, spread: number, size: number, glint: boolean?)
	for _, s in { -1, 1 } do
		local at = center + Vector3.new(s * spread, 0, 0)
		blob(model, "Eye", Vector3.new(size, size * 1.15, size * 0.6), WHITE, at)
		blob(model, "Pupil", Vector3.new(size * 0.5, size * 0.64, size * 0.3), INK, at + Vector3.new(s * size * 0.05, -size * 0.08, -size * 0.2))
		if glint ~= false then
			blob(model, "Glint", Vector3.new(size * 0.18, size * 0.2, size * 0.1), WHITE, at + Vector3.new(-s * size * 0.06, size * 0.12, -size * 0.34))
		end
	end
end

-- Antena con bolita en la punta
local function antennae(model, base: Vector3, tip: Vector3, thickness: number, color: Color3, ball: number?)
	for _, s in { -1, 1 } do
		local a = Vector3.new(s * base.X, base.Y, base.Z)
		local b = Vector3.new(s * tip.X, tip.Y, tip.Z)
		segment(model, "Antenna", a, b, thickness, color)
		if ball then
			blob(model, "AntennaTip", Vector3.new(ball, ball, ball), color, b)
		end
	end
end

-- Ala: elipsoide plano que gira alrededor de su bisagra
local function wing(model, s: number, hinge: Vector3, size: Vector3, offset: Vector3, color: Color3, transparency: number, yaw: number?): Part
	local hingeCF = CFrame.new(s * hinge.X, hinge.Y, hinge.Z)
	local cf = hingeCF * CFrame.new(s * offset.X, offset.Y, offset.Z) * CFrame.Angles(0, s * (yaw or 0), s * 0.22)
	local part = make(model, "Wing", size, color, cf)
	part.Transparency = transparency
	part:SetAttribute("Hinge", hingeCF)
	part:SetAttribute("Flap", s)
	return part
end

local function legs(model, list, thickness: number, color: Color3)
	for _, leg in list do
		for _, s in { -1, 1 } do
			segment(model, "Leg", Vector3.new(s * leg[1].X, leg[1].Y, leg[1].Z), Vector3.new(s * leg[2].X, leg[2].Y, leg[2].Z), thickness, color)
		end
	end
end

local BUILD = {}

BUILD.mariquita = function(m)
	local red = Color3.fromRGB(232, 44, 44)
	blob(m, "Body", Vector3.new(1.7, 1.1, 1.9), red, Vector3.new(0, 0, 0.15))
	blob(m, "Line", Vector3.new(0.1, 1.14, 1.94), INK, Vector3.new(0, 0, 0.15))
	for _, spot in { Vector3.new(0.45, 0.43, -0.15), Vector3.new(0.38, 0.42, 0.6) } do
		for _, s in { -1, 1 } do
			blob(m, "Spot", Vector3.new(0.42, 0.36, 0.42), INK, Vector3.new(s * spot.X, spot.Y, spot.Z))
		end
	end
	blob(m, "Head", Vector3.new(1, 0.75, 0.75), INK, Vector3.new(0, -0.1, -0.85))
	eyes(m, Vector3.new(0, 0, -1.12), 0.22, 0.34)
	antennae(m, Vector3.new(0.2, 0.2, -1), Vector3.new(0.4, 0.6, -1.3), 0.07, INK, 0.18)
	return 0.62
end

BUILD.pulgon = function(m)
	local green = Color3.fromRGB(156, 218, 84)
	local dark = Color3.fromRGB(88, 158, 52)
	blob(m, "Body", Vector3.new(1.15, 1, 1.5), green, Vector3.new(0, 0.05, 0.2))
	blob(m, "Head", Vector3.new(0.8, 0.72, 0.7), green, Vector3.new(0, 0.1, -0.65))
	blob(m, "Shine", Vector3.new(0.35, 0.18, 0.5), Color3.fromRGB(214, 246, 170), Vector3.new(-0.25, 0.5, 0.1))
	for _, s in { -1, 1 } do
		segment(m, "Cornicle", Vector3.new(s * 0.25, 0.35, 0.6), Vector3.new(s * 0.35, 0.68, 0.95), 0.12, dark)
		segment(m, "Antenna", Vector3.new(s * 0.45, 0.95, -0.55), Vector3.new(s * 0.6, 1, 0.1), 0.06, dark)
	end
	eyes(m, Vector3.new(0, 0.18, -0.95), 0.2, 0.3)
	antennae(m, Vector3.new(0.15, 0.4, -0.8), Vector3.new(0.45, 0.95, -0.55), 0.06, dark)
	legs(m, {
		{ Vector3.new(0.4, -0.2, -0.2), Vector3.new(0.7, -0.62, -0.35) },
		{ Vector3.new(0.4, -0.2, 0.45), Vector3.new(0.7, -0.62, 0.6) },
	}, 0.08, dark)
	return 0.62
end

BUILD.abeja = function(m)
	local yellow = Color3.fromRGB(255, 205, 50)
	local black = Color3.fromRGB(38, 30, 32)
	blob(m, "Body", Vector3.new(1.25, 1.15, 1.7), yellow, Vector3.new(0, 0, 0.25))
	blob(m, "Stripe", Vector3.new(1.29, 1.19, 0.26), black, Vector3.new(0, 0, 0.25))
	blob(m, "Stripe", Vector3.new(1.12, 1.03, 0.24), black, Vector3.new(0, 0, 0.68))
	blob(m, "Stinger", Vector3.new(0.16, 0.16, 0.42), black, Vector3.new(0, -0.05, 1.15))
	blob(m, "Head", Vector3.new(0.9, 0.85, 0.8), black, Vector3.new(0, 0.12, -0.75))
	eyes(m, Vector3.new(0, 0.2, -1.05), 0.22, 0.34)
	antennae(m, Vector3.new(0.18, 0.45, -0.9), Vector3.new(0.35, 0.85, -1.15), 0.06, black, 0.16)
	for _, s in { -1, 1 } do
		wing(m, s, Vector3.new(0.3, 0.55, 0.05), Vector3.new(0.95, 0.06, 0.55), Vector3.new(0.45, 0.1, 0.05), WING, 0.3)
	end
	return 0.6
end

BUILD.caracol = function(m)
	local skin = Color3.fromRGB(196, 206, 150)
	local shell = Color3.fromRGB(238, 142, 60)
	blob(m, "Foot", Vector3.new(0.8, 0.5, 2.3), skin, Vector3.new(0, -0.3, 0.05))
	blob(m, "Head", Vector3.new(0.65, 1, 0.65), skin, Vector3.new(0, 0.05, -0.85))
	for _, s in { -1, 1 } do
		segment(m, "Stalk", Vector3.new(s * 0.14, 0.45, -0.9), Vector3.new(s * 0.28, 1.05, -1), 0.1, skin)
		blob(m, "Eye", Vector3.new(0.32, 0.36, 0.3), WHITE, Vector3.new(s * 0.28, 1.08, -1.02))
		blob(m, "Pupil", Vector3.new(0.16, 0.2, 0.1), INK, Vector3.new(s * 0.28, 1.06, -1.17))
	end
	blob(m, "Shell", Vector3.new(1.25, 1.45, 1.45), shell, Vector3.new(0, 0.45, 0.4))
	for _, s in { -1, 1 } do
		blob(m, "Swirl", Vector3.new(0.3, 0.95, 0.95), Color3.fromRGB(192, 96, 40), Vector3.new(s * 0.5, 0.48, 0.42))
		blob(m, "Swirl", Vector3.new(0.3, 0.5, 0.5), Color3.fromRGB(255, 192, 112), Vector3.new(s * 0.56, 0.5, 0.42))
	end
	return 0.55
end

BUILD.oruga = function(m)
	local light = Color3.fromRGB(128, 206, 74)
	local dark = Color3.fromRGB(92, 172, 60)
	local yellow = Color3.fromRGB(255, 210, 63)
	local sizes = { 0.75, 0.72, 0.7, 0.66, 0.58 }
	local z = -0.45
	for i, size in sizes do
		local y = -0.38 + size / 2 + (if i % 2 == 0 then 0.06 else 0)
		blob(m, "Segment", Vector3.new(size * 1.05, size, size), if i % 2 == 0 then dark else light, Vector3.new(0, y, z))
		if i == 2 or i == 4 then
			blob(m, "Dot", Vector3.new(0.22, 0.14, 0.22), yellow, Vector3.new(0, y + size / 2 - 0.03, z))
		end
		z += 0.42 - (0.75 - size) * 0.3
	end
	blob(m, "Head", Vector3.new(0.9, 0.85, 0.8), Color3.fromRGB(150, 214, 86), Vector3.new(0, 0.12, -0.95))
	eyes(m, Vector3.new(0, 0.24, -1.28), 0.18, 0.3)
	antennae(m, Vector3.new(0.15, 0.5, -1), Vector3.new(0.3, 0.85, -0.95), 0.06, dark, 0.15)
	return 0.38
end

BUILD.luciernaga = function(m)
	local body = Color3.fromRGB(64, 52, 74)
	local glowColor = Color3.fromRGB(255, 240, 120)
	blob(m, "Body", Vector3.new(0.85, 0.75, 1.2), body, Vector3.new(0, 0.05, -0.05))
	local glow = blob(m, "Glow", Vector3.new(0.8, 0.75, 0.85), glowColor, Vector3.new(0, -0.05, 0.75))
	glow.Material = Enum.Material.Neon
	glow:SetAttribute("Light", glowColor)
	blob(m, "Head", Vector3.new(0.7, 0.62, 0.6), Color3.fromRGB(232, 96, 60), Vector3.new(0, 0.05, -0.75))
	eyes(m, Vector3.new(0, 0.12, -0.98), 0.17, 0.27)
	antennae(m, Vector3.new(0.12, 0.3, -0.9), Vector3.new(0.3, 0.75, -1.2), 0.05, body, 0.12)
	for _, s in { -1, 1 } do
		wing(m, s, Vector3.new(0.25, 0.4, -0.1), Vector3.new(0.85, 0.05, 0.45), Vector3.new(0.4, 0.1, 0.1), WING, 0.35)
	end
	return 0.5
end

BUILD.mariposa = function(m)
	local body = Color3.fromRGB(64, 42, 64)
	local upper = Color3.fromRGB(62, 193, 243)
	local lower = Color3.fromRGB(255, 124, 182)
	blob(m, "Body", Vector3.new(0.3, 0.3, 1.3), body, Vector3.new(0, 0, 0.1))
	blob(m, "Head", Vector3.new(0.55, 0.52, 0.5), body, Vector3.new(0, 0.05, -0.65))
	eyes(m, Vector3.new(0, 0.1, -0.84), 0.13, 0.24)
	antennae(m, Vector3.new(0.08, 0.25, -0.75), Vector3.new(0.3, 0.8, -1.05), 0.04, body, 0.15)
	for _, s in { -1, 1 } do
		local hinge = Vector3.new(0.12, 0.08, 0.1)
		wing(m, s, hinge, Vector3.new(1.15, 0.05, 0.9), Vector3.new(0.6, 0, -0.3), upper, 0, 0.25)
		wing(m, s, hinge, Vector3.new(0.8, 0.05, 0.65), Vector3.new(0.42, -0.02, 0.4), lower, 0, -0.3)
		wing(m, s, hinge, Vector3.new(0.38, 0.07, 0.32), Vector3.new(0.68, 0.03, -0.32), Color3.fromRGB(255, 226, 90), 0, 0.25)
	end
	return 0.5
end

BUILD.escarabajo = function(m)
	local shell = Color3.fromRGB(92, 72, 176)
	local dark = Color3.fromRGB(44, 32, 66)
	blob(m, "Body", Vector3.new(1.45, 0.95, 1.8), shell, Vector3.new(0, 0.05, 0.25))
	blob(m, "Line", Vector3.new(0.08, 0.99, 1.84), dark, Vector3.new(0, 0.05, 0.25))
	blob(m, "Shine", Vector3.new(0.35, 0.15, 0.6), Color3.fromRGB(184, 172, 255), Vector3.new(-0.35, 0.48, 0.1))
	blob(m, "Thorax", Vector3.new(1.1, 0.8, 0.8), Color3.fromRGB(72, 56, 140), Vector3.new(0, 0.1, -0.7))
	blob(m, "Head", Vector3.new(0.75, 0.6, 0.55), dark, Vector3.new(0, 0, -1.1))
	segment(m, "Horn", Vector3.new(0, 0.15, -1.25), Vector3.new(0, 0.75, -1.65), 0.2, dark)
	segment(m, "Horn", Vector3.new(0, 0.73, -1.64), Vector3.new(0, 1.05, -1.5), 0.14, dark)
	eyes(m, Vector3.new(0, 0.1, -1.3), 0.25, 0.28)
	legs(m, {
		{ Vector3.new(0.5, -0.2, -0.6), Vector3.new(0.95, -0.65, -0.8) },
		{ Vector3.new(0.5, -0.2, 0), Vector3.new(0.98, -0.65, 0) },
		{ Vector3.new(0.5, -0.2, 0.6), Vector3.new(0.95, -0.65, 0.85) },
	}, 0.1, INK)
	return 0.65
end

BUILD.bichoBola = function(m)
	local grey = Color3.fromRGB(132, 137, 152)
	local greyDark = Color3.fromRGB(106, 111, 128)
	local plates = { -0.6, -0.25, 0.1, 0.45, 0.78 }
	for i, z in plates do
		local last = i == #plates
		local size = if last then Vector3.new(1.1, 0.8, 0.5) else Vector3.new(1.3, 0.95, 0.55)
		blob(m, "Plate", size, if i % 2 == 0 then greyDark else grey, Vector3.new(0, if last then -0.06 else 0, z))
	end
	blob(m, "Head", Vector3.new(0.75, 0.55, 0.5), Color3.fromRGB(86, 90, 106), Vector3.new(0, -0.1, -0.95))
	eyes(m, Vector3.new(0, 0, -1.12), 0.18, 0.26)
	antennae(m, Vector3.new(0.2, 0, -1.1), Vector3.new(0.55, 0.35, -1.45), 0.06, greyDark, 0.13)
	for _, s in { -1, 1 } do
		blob(m, "Tail", Vector3.new(0.15, 0.15, 0.3), greyDark, Vector3.new(s * 0.3, -0.25, 1.05))
	end
	return 0.48
end

BUILD.libelula = function(m)
	local teal = Color3.fromRGB(40, 190, 180)
	local dark = Color3.fromRGB(26, 112, 120)
	blob(m, "Thorax", Vector3.new(0.55, 0.55, 0.75), teal, Vector3.new(0, 0, -0.2))
	blob(m, "Tail", Vector3.new(0.26, 0.26, 1.9), teal, Vector3.new(0, 0, 1))
	blob(m, "TailTip", Vector3.new(0.3, 0.3, 0.3), dark, Vector3.new(0, 0, 1.9))
	blob(m, "Head", Vector3.new(0.55, 0.5, 0.45), dark, Vector3.new(0, 0.05, -0.72))
	for _, s in { -1, 1 } do
		blob(m, "Eye", Vector3.new(0.42, 0.5, 0.4), Color3.fromRGB(150, 236, 120), Vector3.new(s * 0.2, 0.18, -0.85))
		blob(m, "Pupil", Vector3.new(0.2, 0.26, 0.15), INK, Vector3.new(s * 0.21, 0.15, -1.03))
		blob(m, "Glint", Vector3.new(0.08, 0.1, 0.06), WHITE, Vector3.new(s * 0.17, 0.24, -1.1))
		wing(m, s, Vector3.new(0.15, 0.22, -0.35), Vector3.new(1.35, 0.04, 0.32), Vector3.new(0.7, 0, -0.05), WING, 0.35, 0.1)
		wing(m, s, Vector3.new(0.15, 0.22, -0.05), Vector3.new(1.3, 0.04, 0.32), Vector3.new(0.68, 0, 0.12), WING, 0.35, -0.12)
	end
	return 0.55
end

BUILD.rana = function(m)
	local green = Color3.fromRGB(112, 202, 90)
	local dark = Color3.fromRGB(70, 150, 66)
	blob(m, "Body", Vector3.new(1.35, 1, 1.35), green, Vector3.new(0, 0, 0.05))
	blob(m, "Belly", Vector3.new(1, 0.7, 0.6), Color3.fromRGB(232, 246, 182), Vector3.new(0, -0.15, -0.42))
	for _, s in { -1, 1 } do
		blob(m, "Bump", Vector3.new(0.55, 0.55, 0.55), green, Vector3.new(s * 0.33, 0.48, -0.3))
		blob(m, "Eye", Vector3.new(0.42, 0.46, 0.3), WHITE, Vector3.new(s * 0.33, 0.52, -0.5))
		blob(m, "Pupil", Vector3.new(0.2, 0.26, 0.14), INK, Vector3.new(s * 0.33, 0.5, -0.64))
		blob(m, "Glint", Vector3.new(0.08, 0.1, 0.06), WHITE, Vector3.new(s * 0.29, 0.58, -0.7))
		blob(m, "Thigh", Vector3.new(0.45, 0.4, 0.85), dark, Vector3.new(s * 0.62, -0.3, 0.25))
		blob(m, "Hand", Vector3.new(0.3, 0.12, 0.35), dark, Vector3.new(s * 0.38, -0.48, -0.55))
	end
	blob(m, "Mouth", Vector3.new(0.7, 0.07, 0.12), Color3.fromRGB(44, 30, 32), Vector3.new(0, 0.12, -0.64))
	return 0.5
end

BUILD.escarabajoOro = function(m)
	local gold = Color3.fromRGB(255, 196, 52)
	local deep = Color3.fromRGB(204, 138, 30)
	local body = blob(m, "Body", Vector3.new(1.4, 0.9, 1.6), gold, Vector3.new(0, 0.05, 0.3))
	body.Reflectance = 0.15
	blob(m, "Line", Vector3.new(0.08, 0.94, 1.64), deep, Vector3.new(0, 0.05, 0.3))
	blob(m, "Shine", Vector3.new(0.35, 0.15, 0.55), Color3.fromRGB(255, 244, 170), Vector3.new(-0.35, 0.46, 0.15))
	blob(m, "Gem", Vector3.new(0.3, 0.14, 0.3), Color3.fromRGB(62, 193, 243), Vector3.new(0, 0.48, 0.3))
	local thorax = blob(m, "Thorax", Vector3.new(1.15, 0.75, 0.75), gold, Vector3.new(0, 0.05, -0.55))
	thorax.Reflectance = 0.15
	blob(m, "Head", Vector3.new(0.95, 0.4, 0.5), deep, Vector3.new(0, -0.05, -0.95))
	for _, x in { -0.3, 0, 0.3 } do
		blob(m, "Tooth", Vector3.new(0.18, 0.14, 0.22), deep, Vector3.new(x, -0.05, if x == 0 then -1.23 else -1.2))
	end
	eyes(m, Vector3.new(0, 0.2, -0.95), 0.22, 0.28)
	legs(m, {
		{ Vector3.new(0.55, -0.2, -0.4), Vector3.new(0.95, -0.62, -0.6) },
		{ Vector3.new(0.55, -0.2, 0.5), Vector3.new(0.95, -0.62, 0.75) },
	}, 0.1, INK)
	return 0.62
end

BUILD.arana = function(m)
	local purple = Color3.fromRGB(124, 82, 176)
	blob(m, "Abdomen", Vector3.new(1.2, 1.1, 1.25), purple, Vector3.new(0, 0.25, 0.4))
	blob(m, "Mark", Vector3.new(0.45, 0.2, 0.5), Color3.fromRGB(206, 176, 244), Vector3.new(0, 0.77, 0.4))
	blob(m, "Head", Vector3.new(0.85, 0.7, 0.8), Color3.fromRGB(96, 62, 140), Vector3.new(0, 0.05, -0.45))
	eyes(m, Vector3.new(0, 0.15, -0.8), 0.18, 0.3)
	for _, s in { -1, 1 } do
		blob(m, "Eye", Vector3.new(0.14, 0.14, 0.1), WHITE, Vector3.new(s * 0.32, 0.34, -0.7))
	end
	legs(m, {
		{ Vector3.new(0.35, 0.1, -0.6), Vector3.new(1.05, -0.5, -1) },
		{ Vector3.new(0.38, 0.1, -0.35), Vector3.new(1.15, -0.5, -0.45) },
		{ Vector3.new(0.38, 0.1, -0.1), Vector3.new(1.15, -0.5, 0.1) },
		{ Vector3.new(0.35, 0.1, 0.15), Vector3.new(1.05, -0.5, 0.6) },
	}, 0.09, INK)
	return 0.5
end

BUILD.grillo = function(m)
	local brown = Color3.fromRGB(128, 86, 52)
	local light = Color3.fromRGB(176, 124, 72)
	blob(m, "Body", Vector3.new(0.85, 0.75, 1.6), light, Vector3.new(0, 0.05, 0.25))
	blob(m, "Wings", Vector3.new(0.9, 0.3, 1.3), brown, Vector3.new(0, 0.36, 0.45))
	blob(m, "Head", Vector3.new(0.75, 0.75, 0.65), light, Vector3.new(0, 0.15, -0.65))
	eyes(m, Vector3.new(0, 0.25, -0.92), 0.2, 0.3)
	antennae(m, Vector3.new(0.12, 0.45, -0.85), Vector3.new(0.6, 1.05, 0.4), 0.05, brown)
	legs(m, {
		{ Vector3.new(0.42, 0.1, 0.45), Vector3.new(0.6, 0.75, 0.95) },
		{ Vector3.new(0.6, 0.73, 0.95), Vector3.new(0.62, -0.45, 1.25) },
		{ Vector3.new(0.35, -0.1, -0.35), Vector3.new(0.6, -0.45, -0.55) },
	}, 0.12, brown)
	return 0.45
end

-- Brillos según la rareza: las épicas y mejores sueltan chispas (y la mítica, luz).
local SPARKLE_RATE = { 0, 0, 3, 7, 14 }

local function addRarity(root: BasePart, rarity: number)
	local def = PetDefs.Rarities[rarity]
	if not def or SPARKLE_RATE[rarity] <= 0 then
		return
	end
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(def.color)
	sparkles.LightEmission = 1
	sparkles.Rate = SPARKLE_RATE[rarity]
	sparkles.Lifetime = NumberRange.new(0.7, 1.3)
	sparkles.Speed = NumberRange.new(0.6, 1.6)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Parent = root
	if rarity >= 5 then
		local light = Instance.new("PointLight")
		light.Color = def.color
		light.Brightness = 1.2
		light.Range = 7
		light.Parent = root
	end
end

-- Construye la mascota. preview = true: sin chispas ni luces (para las ViewportFrame).
function PetModels.build(speciesId: string, rarity: number?, preview: boolean?): Model
	local def = PetDefs.SpeciesById[speciesId] or PetDefs.Species[1]
	local model = Instance.new("Model")
	model.Name = def.id

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root

	local height = BUILD[def.id](model)
	model:SetAttribute("Height", height)
	model:SetAttribute("Gait", def.gait)

	if not preview then
		addRarity(root, rarity or 1)
		for _, part in model:GetChildren() do
			local color = part:GetAttribute("Light")
			if typeof(color) == "Color3" then
				local light = Instance.new("PointLight")
				light.Color = color
				light.Brightness = 1
				light.Range = 6
				light.Parent = part
			end
		end
	end
	return model
end

return PetModels
