-- Ambiente: cada sitio tiene su aire. Unas cajas invisibles siguen a la cámara y llevan
-- emisores de partículas que cambian según la zona (polen en el jardín, hojas en la jungla,
-- confeti en la feria...). Al cambiar de zona, los emisores viejos dejan de emitir (sus
-- partículas se apagan solas) y los nuevos suben poco a poco: un fundido sin cortes.
-- Pensado para móviles: como mucho 2 emisores encendidos y unas 60 partículas vivas por emisor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)

local Ambience = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local BURST = Assets.Burst

local GROUND = Config.GroundY
local TICK = 0.25
local RAMP = 2 -- segundos que tarda un emisor nuevo en llegar a su ritmo

local player = Players.LocalPlayer
local rng = Random.new()

local holder: Folder? = nil
local rigs: { [string]: BasePart } = {}
local connections: { RBXScriptConnection } = {}
local built: { [string]: { ParticleEmitter } } = {}
local tweens: { [ParticleEmitter]: Tween } = {}
local current: string? = nil
local started = false
local nextShot = 0

-- Utilidades de secuencias --------------------------------------------------------------------

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function numbers(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2], point[3] or 0))
	end
	return NumberSequence.new(keys)
end

-- Aparece, se mantiene y se desvanece
local function fade(opacity: number, fadeIn: number?, fadeOut: number?): NumberSequence
	local a = fadeIn or 0.15
	local b = 1 - (fadeOut or 0.25)
	return numbers({ { 0, 1 }, { a, opacity }, { b, opacity }, { 1, 1 } })
end

-- Bandas de color duras: como cada partícula nace en un momento distinto, a la vez se ven todas
local function bands(colors: { Color3 }): ColorSequence
	local keys = {}
	local count = #colors
	for i, color in colors do
		local from = (i - 1) / count
		local to = i / count
		table.insert(keys, ColorSequenceKeypoint.new(from, color))
		table.insert(keys, ColorSequenceKeypoint.new(if i == count then 1 else to - 0.002, color))
	end
	return ColorSequence.new(keys)
end

-- Aplastado que va y viene: el confeti y las hojas parecen girar sobre sí mismos
local function flip(amount: number, base: number?, turns: number?): NumberSequence
	local keys = {}
	local steps = math.min(18, (turns or 4) * 2)
	for i = 0, steps do
		local value = (base or 0) + (if i % 2 == 0 then amount else -amount)
		table.insert(keys, NumberSequenceKeypoint.new(i / steps, math.clamp(value, -3, 3)))
	end
	return NumberSequence.new(keys)
end

-- Recetas por tema ------------------------------------------------------------------------------
-- rig: "Air" (caja alrededor de la vista), "Floor" (a ras de suelo) o "Sky" (por encima).
-- rate * vida media se mantiene por debajo de 60 partículas.

type Recipe = { [string]: any }

local THEMES: { [string]: { Recipe } } = {
	Jardin = {
		{ -- polen
			rig = "Air", texture = SMOKE, rate = 6, life = NumberRange.new(6, 9),
			color = ColorSequence.new(rgb(255, 236, 120), rgb(255, 214, 90)),
			size = numbers({ { 0, 0.32, 0.08 }, { 1, 0.4, 0.08 } }), transparency = fade(0.15),
			speed = NumberRange.new(0.2, 0.8), spread = Vector2.new(180, 180), accel = Vector3.new(0.25, 0.08, 0),
			light = 0.6, drag = 0.4,
		},
		{ -- algún pétalo
			rig = "Air", texture = SMOKE, rate = 1, life = NumberRange.new(7, 10),
			color = ColorSequence.new(rgb(255, 176, 206), rgb(255, 236, 244)),
			size = numbers({ { 0, 0.55 }, { 1, 0.5 } }), transparency = fade(0.05),
			speed = NumberRange.new(0.3, 0.8), spread = Vector2.new(60, 60), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(0.5, -0.35, 0.2), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-80, 80),
			squash = flip(0.8, 0.4, 5), drag = 0.6, light = 0.2,
		},
	},
	Picnic = {
		{ -- migas flotando
			rig = "Air", texture = FIRE, rate = 6, life = NumberRange.new(6, 8),
			color = ColorSequence.new(rgb(222, 170, 104), rgb(196, 140, 80)),
			size = numbers({ { 0, 0.36, 0.1 }, { 1, 0.32, 0.08 } }), transparency = fade(0.05),
			speed = NumberRange.new(0.2, 0.7), spread = Vector2.new(180, 180), accel = Vector3.new(0.15, -0.12, 0),
			rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-60, 60), drag = 0.5, light = 0,
		},
		{ -- polvillo cálido
			rig = "Air", texture = SMOKE, rate = 1.4, life = NumberRange.new(6, 8),
			color = ColorSequence.new(rgb(255, 232, 196)),
			size = numbers({ { 0, 1.6, 0.4 }, { 1, 2.6, 0.4 } }), transparency = fade(0.86, 0.3, 0.4),
			speed = NumberRange.new(0.2, 0.5), spread = Vector2.new(180, 180), light = 0.5, drag = 0.3,
		},
	},
	Huerto = {
		{ -- polvo de tierra
			rig = "Air", texture = SMOKE, rate = 3, life = NumberRange.new(7, 9),
			color = ColorSequence.new(rgb(204, 160, 110), rgb(176, 130, 86)),
			size = numbers({ { 0, 1.2, 0.3 }, { 1, 2.2, 0.4 } }), transparency = fade(0.82, 0.3, 0.4),
			speed = NumberRange.new(0.3, 0.8), spread = Vector2.new(180, 30), accel = Vector3.new(0.4, 0, 0.1),
			light = 0.1, drag = 0.3,
		},
		{ -- semillitas
			rig = "Air", texture = FIRE, rate = 4, life = NumberRange.new(6, 8),
			color = ColorSequence.new(rgb(250, 232, 180), rgb(220, 196, 140)),
			size = numbers({ { 0, 0.3 }, { 1, 0.28 } }), transparency = fade(0.05),
			speed = NumberRange.new(0.3, 0.9), spread = Vector2.new(90, 90), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(0.6, -0.3, 0.2), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-120, 120),
			squash = numbers({ { 0, 1.2 }, { 1, 1.2 } }), drag = 0.5, light = 0.1,
		},
	},
	Jungla = {
		{ -- hojas cayendo y girando
			rig = "Air", texture = SMOKE, rate = 4, life = NumberRange.new(7, 9),
			color = bands({ rgb(84, 176, 72), rgb(120, 200, 84), rgb(58, 150, 74) }),
			size = numbers({ { 0, 0.9, 0.2 }, { 1, 0.9, 0.2 } }), transparency = fade(0),
			speed = NumberRange.new(0.5, 1.2), spread = Vector2.new(40, 40), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(0.4, -0.45, 0.25), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-90, 90),
			squash = flip(0.7, 1, 6), drag = 0.8, light = 0,
		},
		{ -- neblina a ras de suelo
			rig = "Floor", texture = SMOKE, rate = 1.6, life = NumberRange.new(8, 10),
			color = ColorSequence.new(rgb(220, 244, 226)),
			size = numbers({ { 0, 7, 1.5 }, { 1, 11, 2 } }), transparency = fade(0.88, 0.3, 0.4),
			speed = NumberRange.new(0.3, 0.8), spread = Vector2.new(180, 10), light = 0.3, drag = 0.2,
		},
	},
	Mar = {
		{ -- burbujas que suben
			rig = "Air", texture = SMOKE, rate = 6, life = NumberRange.new(5, 7),
			color = ColorSequence.new(rgb(220, 248, 255), rgb(170, 226, 255)),
			size = numbers({ { 0, 0.35, 0.1 }, { 1, 0.6, 0.15 } }), transparency = fade(0.35),
			speed = NumberRange.new(0.8, 1.6), spread = Vector2.new(25, 25), direction = Enum.NormalId.Top,
			accel = Vector3.new(0, 0.6, 0), drag = 0.3, light = 0.7,
		},
		{ -- destellos del sol en el agua
			rig = "Air", texture = SPARKLE, rate = 4, life = NumberRange.new(0.8, 1.4),
			color = ColorSequence.new(rgb(255, 255, 240)),
			size = numbers({ { 0, 0 }, { 0.4, 0.9, 0.2 }, { 1, 0 } }), transparency = fade(0.1, 0.2, 0.3),
			speed = NumberRange.new(0, 0.2), rotation = NumberRange.new(0, 90), light = 1,
		},
	},
	Cocina = {
		{ -- motas de harina
			rig = "Air", texture = SMOKE, rate = 7, life = NumberRange.new(6, 8),
			color = ColorSequence.new(rgb(255, 250, 238), rgb(255, 238, 214)),
			size = numbers({ { 0, 0.38, 0.1 }, { 1, 0.5, 0.1 } }), transparency = fade(0.25),
			speed = NumberRange.new(0.15, 0.5), spread = Vector2.new(180, 180), accel = Vector3.new(0.1, -0.05, 0),
			drag = 0.5, light = 0.5,
		},
		{ -- luz cálida flotando
			rig = "Air", texture = SMOKE, rate = 0.6, life = NumberRange.new(7, 9),
			color = ColorSequence.new(rgb(255, 214, 150)),
			size = numbers({ { 0, 6, 1 }, { 1, 9, 1.5 } }), transparency = fade(0.92, 0.35, 0.4),
			speed = NumberRange.new(0.1, 0.3), spread = Vector2.new(180, 180), light = 1,
		},
	},
	Barbacoa = {
		{ -- brasas que suben
			rig = "Air", texture = FIRE, rate = 5, life = NumberRange.new(4, 6),
			color = bands({ rgb(255, 200, 70), rgb(255, 130, 40), rgb(240, 80, 40) }),
			size = numbers({ { 0, 0.3, 0.1 }, { 1, 0.12 } }), transparency = fade(0.05, 0.1, 0.4),
			speed = NumberRange.new(0.8, 1.8), spread = Vector2.new(30, 30), direction = Enum.NormalId.Top,
			accel = Vector3.new(0.4, 0.5, 0.1), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-90, 90),
			drag = 0.4, light = 1,
		},
		{ -- humo de la parrilla
			rig = "Air", texture = SMOKE, rate = 1.2, life = NumberRange.new(7, 9),
			color = ColorSequence.new(rgb(236, 230, 226), rgb(200, 194, 192)),
			size = numbers({ { 0, 3, 0.8 }, { 1, 7, 1.5 } }), transparency = fade(0.88, 0.3, 0.4),
			speed = NumberRange.new(0.3, 0.8), spread = Vector2.new(40, 40), direction = Enum.NormalId.Top,
			accel = Vector3.new(0.3, 0.2, 0), light = 0.2, drag = 0.3,
		},
	},
	Despensa = {
		{ -- motas de polvo en la luz
			rig = "Air", texture = SPARKLE, rate = 4, life = NumberRange.new(6, 9),
			color = ColorSequence.new(rgb(255, 240, 200), rgb(255, 226, 170)),
			size = numbers({ { 0, 0.2, 0.06 }, { 0.5, 0.32, 0.08 }, { 1, 0.15 } }), transparency = fade(0.2),
			speed = NumberRange.new(0.1, 0.4), spread = Vector2.new(180, 180), accel = Vector3.new(0.1, -0.03, 0),
			rotation = NumberRange.new(0, 90), drag = 0.5, light = 0.8,
		},
		{ -- copos de cereal cayendo
			rig = "Air", texture = FIRE, rate = 3, life = NumberRange.new(6, 8),
			color = ColorSequence.new(rgb(236, 190, 110), rgb(214, 160, 84)),
			size = numbers({ { 0, 0.34 }, { 1, 0.3 } }), transparency = fade(0.05),
			speed = NumberRange.new(0.3, 0.8), spread = Vector2.new(60, 60), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(0.2, -0.4, 0.1), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-120, 120),
			squash = flip(0.6, 0.3, 5), drag = 0.6, light = 0.1,
		},
	},
	Juguetes = {
		{ -- chispas de colores de juguete
			rig = "Air", texture = SPARKLE, rate = 4, life = NumberRange.new(5, 7),
			color = bands({ rgb(230, 57, 70), rgb(255, 210, 63), rgb(62, 140, 243), rgb(110, 200, 90) }),
			size = numbers({ { 0, 0.25, 0.08 }, { 0.5, 0.4, 0.1 }, { 1, 0.15 } }), transparency = fade(0.1),
			speed = NumberRange.new(0.2, 0.6), spread = Vector2.new(180, 180), accel = Vector3.new(0, -0.08, 0),
			rotation = NumberRange.new(0, 90), rotSpeed = NumberRange.new(-60, 60), drag = 0.4, light = 0.8,
		},
		{ -- pelusas de la alfombra
			rig = "Floor", texture = SMOKE, rate = 2, life = NumberRange.new(6, 8),
			color = ColorSequence.new(rgb(214, 228, 255), rgb(240, 244, 255)),
			size = numbers({ { 0, 0.6, 0.2 }, { 1, 0.9, 0.2 } }), transparency = fade(0.4, 0.2, 0.4),
			speed = NumberRange.new(0.3, 0.8), spread = Vector2.new(180, 20), accel = Vector3.new(0.3, 0.05, 0.1),
			rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-40, 40), drag = 0.5, light = 0.3,
		},
	},
	Escritorio = {
		{ -- virutas de goma de borrar
			rig = "Air", texture = FIRE, rate = 3, life = NumberRange.new(6, 8),
			color = bands({ rgb(255, 150, 170), rgb(250, 244, 230) }),
			size = numbers({ { 0, 0.3 }, { 1, 0.26 } }), transparency = fade(0.05),
			speed = NumberRange.new(0.3, 0.8), spread = Vector2.new(70, 70), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(0.2, -0.5, 0), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-150, 150),
			squash = numbers({ { 0, 1.6 }, { 1, 1.6 } }), drag = 0.6, light = 0.1,
		},
		{ -- luz cálida del flexo
			rig = "Air", texture = SMOKE, rate = 0.6, life = NumberRange.new(7, 9),
			color = ColorSequence.new(rgb(255, 232, 170)),
			size = numbers({ { 0, 6, 1 }, { 1, 9, 1.5 } }), transparency = fade(0.92, 0.35, 0.4),
			speed = NumberRange.new(0.1, 0.3), spread = Vector2.new(180, 180), light = 1,
		},
	},
	Nevera = {
		{ -- escarcha cayendo
			rig = "Air", texture = SPARKLE, rate = 6, life = NumberRange.new(7, 9),
			color = ColorSequence.new(rgb(236, 248, 255), rgb(190, 228, 255)),
			size = numbers({ { 0, 0.35, 0.1 }, { 1, 0.3, 0.1 } }), transparency = fade(0.1),
			speed = NumberRange.new(0.4, 0.9), spread = Vector2.new(30, 30), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(0.1, -0.1, 0), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-40, 40),
			drag = 0.4, light = 0.8,
		},
		{ -- vaho frío a ras de suelo
			rig = "Floor", texture = SMOKE, rate = 1.5, life = NumberRange.new(7, 9),
			color = ColorSequence.new(rgb(232, 246, 255)),
			size = numbers({ { 0, 6, 1 }, { 1, 9, 1.5 } }), transparency = fade(0.85, 0.3, 0.4),
			speed = NumberRange.new(0.3, 0.7), spread = Vector2.new(180, 8), light = 0.4, drag = 0.2,
		},
	},
	Feria = {
		{ -- confeti estrellado
			rig = "Air", texture = BURST, rate = 4, life = NumberRange.new(6, 8),
			color = bands({ rgb(230, 57, 70), rgb(255, 210, 63), rgb(62, 193, 243), rgb(110, 200, 90), rgb(160, 96, 230) }),
			size = numbers({ { 0, 0.5, 0.12 }, { 1, 0.45, 0.1 } }), transparency = fade(0),
			speed = NumberRange.new(0.6, 1.6), spread = Vector2.new(45, 45), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(0.3, -1.2, 0), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-220, 220),
			squash = flip(0.9, 0, 7), drag = 1.2, light = 0,
		},
		{ -- más confeti, en otro orden de colores
			rig = "Air", texture = BURST, rate = 4, life = NumberRange.new(6, 8),
			color = bands({ rgb(255, 210, 63), rgb(255, 130, 180), rgb(230, 57, 70), rgb(62, 193, 243), rgb(255, 255, 255) }),
			size = numbers({ { 0, 0.35, 0.08 }, { 1, 0.35, 0.08 } }), transparency = fade(0),
			speed = NumberRange.new(0.6, 1.6), spread = Vector2.new(45, 45), direction = Enum.NormalId.Bottom,
			accel = Vector3.new(-0.3, -1.4, 0.2), rotation = NumberRange.new(0, 360), rotSpeed = NumberRange.new(-260, 260),
			squash = flip(1.1, 0, 8), drag = 1.2, light = 0,
		},
	},
	Dulce = {
		{ -- azúcar rosa
			rig = "Air", texture = SPARKLE, rate = 5, life = NumberRange.new(5, 7),
			color = ColorSequence.new(rgb(255, 150, 200), rgb(255, 196, 226)),
			size = numbers({ { 0, 0.3, 0.1 }, { 0.5, 0.45, 0.1 }, { 1, 0.2 } }), transparency = fade(0.1),
			speed = NumberRange.new(0.2, 0.6), spread = Vector2.new(180, 180), accel = Vector3.new(0, -0.12, 0),
			rotation = NumberRange.new(0, 90), rotSpeed = NumberRange.new(-60, 60), drag = 0.4, light = 0.8,
		},
		{ -- azúcar blanco
			rig = "Air", texture = SPARKLE, rate = 5, life = NumberRange.new(5, 7),
			color = ColorSequence.new(rgb(255, 255, 255)),
			size = numbers({ { 0, 0.25, 0.08 }, { 0.5, 0.38, 0.08 }, { 1, 0.15 } }), transparency = fade(0.1),
			speed = NumberRange.new(0.2, 0.6), spread = Vector2.new(180, 180), accel = Vector3.new(0, -0.1, 0),
			rotation = NumberRange.new(0, 90), rotSpeed = NumberRange.new(-60, 60), drag = 0.4, light = 1,
		},
	},
	Espacio = {
		{ -- polvo de estrellas
			rig = "Air", texture = SPARKLE, rate = 6, life = NumberRange.new(7, 9),
			color = bands({ rgb(255, 255, 255), rgb(214, 196, 255), rgb(190, 230, 255) }),
			size = numbers({ { 0, 0.25, 0.08 }, { 0.5, 0.4, 0.1 }, { 1, 0.2 } }), transparency = fade(0.1, 0.2, 0.3),
			speed = NumberRange.new(0.1, 0.4), spread = Vector2.new(180, 180), rotation = NumberRange.new(0, 90),
			rotSpeed = NumberRange.new(-20, 20), drag = 0.2, light = 1,
		},
		{ -- estrella fugaz de vez en cuando (no emite sola: se dispara con Emit)
			rig = "Sky", texture = SMOKE, rate = 0, life = NumberRange.new(0.9, 1.2), shooting = true,
			color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 180, 255)),
			size = numbers({ { 0, 1.4 }, { 1, 0.4 } }), transparency = numbers({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
			speed = NumberRange.new(55, 75), spread = Vector2.new(8, 8), direction = Enum.NormalId.Left,
			accel = Vector3.new(0, -8, 0), orientation = Enum.ParticleOrientation.VelocityParallel,
			squash = numbers({ { 0, 2.5 }, { 1, 2.5 } }), light = 1,
		},
	},
}

-- Construcción ----------------------------------------------------------------------------------

local function newRig(name: string, size: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = holder
	return p
end

local function makeEmitter(recipe: Recipe): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.Texture = recipe.texture
	e.Color = recipe.color
	e.Size = recipe.size
	e.Transparency = recipe.transparency
	e.Lifetime = recipe.life
	e.Speed = recipe.speed or NumberRange.new(0)
	e.SpreadAngle = recipe.spread or Vector2.zero
	e.EmissionDirection = recipe.direction or Enum.NormalId.Top
	e.Acceleration = recipe.accel or Vector3.zero
	e.Drag = recipe.drag or 0
	e.Rotation = recipe.rotation or NumberRange.new(0)
	e.RotSpeed = recipe.rotSpeed or NumberRange.new(0)
	e.LightEmission = recipe.light or 0
	e.LightInfluence = 0.3
	if recipe.squash then
		e.Squash = recipe.squash
	end
	if recipe.orientation then
		e.Orientation = recipe.orientation
	end
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LockedToPart = false
	e:SetAttribute("TargetRate", recipe.rate)
	e:SetAttribute("Shooting", recipe.shooting == true)
	e.Parent = rigs[recipe.rig]
	return e
end

local function emittersFor(theme: string): { ParticleEmitter }
	local list = built[theme]
	if list then
		return list
	end
	list = {}
	for _, recipe in THEMES[theme] or {} do
		table.insert(list, makeEmitter(recipe))
	end
	built[theme] = list
	return list
end

local function stopTween(e: ParticleEmitter)
	local tween = tweens[e]
	if tween then
		tween:Cancel()
		tweens[e] = nil
	end
end

-- Fundido: los viejos dejan de emitir (sus partículas se apagan solas), los nuevos suben poco a poco
local function switchTo(theme: string?)
	if theme == current then
		return
	end
	if current then
		for _, e in emittersFor(current) do
			stopTween(e)
			e.Enabled = false
			e.Rate = 0
		end
	end
	current = theme
	if not theme or not THEMES[theme] then
		return
	end
	for _, e in emittersFor(theme) do
		if e:GetAttribute("Shooting") then
			continue -- la estrella fugaz se dispara a mano
		end
		e.Rate = 0
		e.Enabled = true
		local tween = TweenService:Create(e, TweenInfo.new(RAMP, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Rate = e:GetAttribute("TargetRate") or 0 })
		tweens[e] = tween
		tween:Play()
	end
	nextShot = os.clock() + rng:NextNumber(2, 5)
end

-- Zona actual: igual que Places (jardín si z > -LobbyRadius; si no, la zona cuyo [z1, z0 + 20] contiene z)
local function zoneAt(z: number): number?
	if z > -Config.Map.LobbyRadius then
		return 1
	end
	for i = 2, #Config.Zones do
		local zone = Config.Zones[i]
		if z >= zone.z1 and z <= zone.z0 + 20 then
			return i
		end
	end
	return nil
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local function tick()
	local position = rootPosition()
	if not position then
		return -- sin personaje se queda el ambiente que hubiera
	end
	local index = zoneAt(position.Z)
	if not index then
		return
	end
	local zone = Config.Zones[index]
	switchTo(zone and zone.theme or nil)

	-- Estrella fugaz de vez en cuando
	if current == "Espacio" and os.clock() >= nextShot then
		nextShot = os.clock() + rng:NextNumber(3, 8)
		for _, e in emittersFor("Espacio") do
			if e:GetAttribute("Shooting") then
				e.EmissionDirection = if rng:NextNumber() < 0.5 then Enum.NormalId.Left else Enum.NormalId.Right
				e:Emit(1)
			end
		end
	end
end

-- Las cajas siguen a la vista: el aire, entre la cámara y la hormiga; la neblina, al suelo
local function follow()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local focus = rootPosition() or camera.Focus.Position
	local middle = camPos:Lerp(focus, 0.55)
	local air = rigs.Air
	local floor = rigs.Floor
	local sky = rigs.Sky
	if air then
		air.CFrame = CFrame.new(middle + Vector3.new(0, 4, 0))
	end
	if floor then
		floor.CFrame = CFrame.new(focus.X, GROUND + 1.2, focus.Z)
	end
	if sky then
		sky.CFrame = CFrame.new(focus.X, math.max(focus.Y, GROUND) + 30, focus.Z)
	end
end

function Ambience.start()
	if started then
		return
	end
	started = true

	local parent = Workspace:FindFirstChild("Life")
	if not parent then
		local created = Instance.new("Folder")
		created.Name = "Life"
		created.Parent = Workspace
		parent = created
	end
	local folder = Instance.new("Folder")
	folder.Name = "Ambience"
	folder.Parent = parent
	holder = folder

	rigs.Air = newRig("Air", Vector3.new(48, 24, 48))
	rigs.Floor = newRig("Floor", Vector3.new(60, 2, 60))
	rigs.Sky = newRig("Sky", Vector3.new(160, 4, 160))

	table.insert(connections, RunService.Heartbeat:Connect(function()
		local ok, err = pcall(follow)
		if not ok then
			warn("[CRUNCH!] Ambience:", err)
		end
	end))

	task.spawn(function()
		while started do
			local ok, err = pcall(tick)
			if not ok then
				warn("[CRUNCH!] Ambience:", err)
			end
			task.wait(TICK)
		end
	end)
end

function Ambience.stop()
	if not started then
		return
	end
	started = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for e in tweens do
		stopTween(e)
	end
	table.clear(built)
	table.clear(rigs)
	current = nil
	if holder then
		holder:Destroy()
		holder = nil
	end
end

return Ambience
