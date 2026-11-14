-- Construye el mundo entero por código: luz, cielo, el jardín redondo con los hormigueros en arco,
-- y el camino largo hacia delante (-Z) partido en zonas con puertas.
-- Así el mapa vive en git y no depende de lo que haya guardado en el lugar de Studio.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local AntModel = require(ReplicatedStorage.Shared.AntModel)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)

local World = {}

-- El modelo del hormiguero vive en su propio módulo; si falta, se usa uno sencillo de reserva
local HillModel = nil
do
	local module = script.Parent:FindFirstChild("HillModel")
	if module then
		local ok, lib = pcall(require, module)
		if ok then
			HillModel = lib
		else
			warn("[CRUNCH!] No se pudo cargar HillModel:", lib)
		end
	end
end

local MAP = Config.Map
local GROUND = Config.GroundY
local INK = Color3.fromRGB(20, 16, 16)
local BANGERS = Font.new("rbxasset://fonts/families/Bangers.json")
local rng = Random.new(2026)

World.hillCenters = {} :: { Vector3 }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function part(parent: Instance, props): Part
	local p = if props.wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide == true
	p.CanTouch = false
	p.CanQuery = props.collide == true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = props.shadow ~= false
	p.Size = props.size
	p.Color = props.color or INK
	p.CFrame = props.cframe
	p.Transparency = props.transparency or 0
	if props.shape then
		(p :: Part).Shape = props.shape
	end
	if props.blob then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Name = props.name or "Part"
	p.Parent = parent
	return p :: Part
end

-- Cilindro de pie
local function disc(parent, diameter, height, color, position, extra)
	local props = extra or {}
	props.size = Vector3.new(height, diameter, diameter)
	props.color = color
	props.cframe = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	props.shape = Enum.PartType.Cylinder
	return part(parent, props)
end

local function wall(parent, size: Vector3, cframe: CFrame, name: string?)
	return part(parent, { name = name or "Wall", size = size, cframe = cframe, collide = true, transparency = 1, shadow = false })
end

local function inkOutline(model: Instance)
	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
end

local function surfaceText(target: BasePart, face: Enum.NormalId, lines: { { text: string, size: number, color: Color3, name: string? } })
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = target
	local total = 0
	for _, line in lines do
		total += line.size
	end
	local y = 0
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = line.name or "Label"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0.04, y / total)
		label.Size = UDim2.fromScale(0.92, line.size / total)
		label.FontFace = BANGERS
		label.TextScaled = true
		label.TextColor3 = line.color
		label.Text = line.text
		label.Parent = gui
		y += line.size
	end
	return gui
end

local deflicker: (Instance) -> () -- se define más abajo

local function buildLighting()
	Lighting:ClearAllChildren()
	-- La sombra es bastante más oscura que la luz: así las formas redondas se leen redondas
	Lighting.Ambient = rgb(112, 108, 126)
	Lighting.OutdoorAmbient = rgb(142, 144, 160)
	Lighting.Brightness = 3.1
	Lighting.ColorShift_Top = rgb(255, 238, 206)
	Lighting.ClockTime = 15.2
	Lighting.GeographicLatitude = 34
	Lighting.ShadowSoftness = 0.06 -- sombras de borde duro, como tinta
	Lighting.EnvironmentDiffuseScale = 0.3
	Lighting.EnvironmentSpecularScale = 0.55 -- un brillo de plástico pulido, como juguete
	Lighting.ExposureCompensation = 0.12
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000

	local sky = Instance.new("Sky")
	sky.SkyboxBk = Assets.SkySide
	sky.SkyboxFt = Assets.SkySide
	sky.SkyboxLf = Assets.SkySide
	sky.SkyboxRt = Assets.SkySide
	sky.SkyboxUp = Assets.SkyTop
	sky.SkyboxDn = Assets.SkyBottom
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	sky.Parent = Lighting

	-- Aire: lo lejano se aclara un poco, y el camino largo gana profundidad
	local air = Instance.new("Atmosphere")
	air.Density = 0.22
	air.Offset = 0.35
	air.Color = rgb(214, 234, 255)
	air.Decay = rgb(255, 236, 204)
	air.Glare = 0
	air.Haze = 0
	air.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.28
	bloom.Size = 22
	bloom.Threshold = 1.5
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "Grade"
	color.Saturation = 0.2
	color.Contrast = 0.14
	color.Parent = Lighting
end

local function halftone(target: BasePart, color: Color3, transparency: number)
	local dots = Instance.new("Texture")
	dots.Texture = Assets.Halftone
	dots.Face = Enum.NormalId.Top
	dots.StudsPerTileU = 3.5
	dots.StudsPerTileV = 3.5
	dots.Color3 = color
	dots.Transparency = transparency
	dots.Parent = target
end

local function lastZone()
	return Config.Zones[#Config.Zones]
end

local function buildGround()
	local ground = Instance.new("Model")
	ground.Name = "Ground"

	local lawnHalf = 350
	local lawn = part(ground, {
		name = "Lawn",
		size = Vector3.new(lawnHalf * 2, 8, lawnHalf * 2),
		color = rgb(124, 200, 84),
		cframe = CFrame.new(0, GROUND - 4, 0),
		collide = true,
	})
	halftone(lawn, rgb(60, 150, 60), 0.86)

	-- Base oscura bajo el resto del camino, desde donde acaba el césped: sin solaparse con él,
	-- así dos superficies casi a la misma altura no parpadean de lejos
	local far = lastZone().z1 - 60
	local length = -far - lawnHalf
	part(ground, {
		name = "Under",
		size = Vector3.new(420, 8, length),
		color = rgb(70, 120, 66),
		cframe = CFrame.new(0, GROUND - 4.05, -lawnHalf - length / 2),
		collide = true,
	})

	-- Manchas de césped más claro, tantas como quepan a la misma densidad. No llegan a la boca del
	-- camino: allí empiezan la tierra y el suelo de la primera zona, casi a su misma altura
	local edge = math.sqrt(MAP.LobbyRadius ^ 2 - MAP.Half ^ 2) - 6
	for _ = 1, math.floor(16 * (MAP.LobbyRadius / 100) ^ 2) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local size = rng:NextNumber(14, 30)
		local radius = rng:NextNumber(10, edge - size / 2)
		disc(ground, size, 0.06, rgb(104, 184, 76), Vector3.new(math.cos(angle) * radius, GROUND + 0.03, math.sin(angle) * radius), { shadow = false })
	end
	deflicker(ground)
	ground.Parent = Workspace
end

-- Borde del jardín: hierba gigante y un muro invisible, con hueco hacia el camino
local function buildLobbyEdge(props: Model, walls: Model)
	local radius = MAP.LobbyRadius
	local opening = math.asin(MAP.Half / radius)
	-- Las cantidades se pensaron para un jardín de radio 100: el borde crece con el radio y el
	-- suelo con su cuadrado, para que la densidad no cambie
	local around = radius / 100
	local area = around * around
	local segments = 40
	for i = 0, segments - 1 do
		local angle = (i + 0.5) / segments * math.pi * 2
		-- El camino sale hacia -Z: ángulo -90°
		local fromFront = math.abs(((angle + math.pi / 2 + math.pi) % (math.pi * 2)) - math.pi)
		if fromFront > opening then
			local position = Vector3.new(math.cos(angle) * (radius + 2), GROUND + 30, math.sin(angle) * (radius + 2))
			wall(walls, Vector3.new(2 * math.pi * radius / segments + 3, 60, 3), CFrame.lookAt(position, Vector3.new(0, GROUND + 30, 0)))
		end
	end

	local greens = { rgb(62, 166, 70), rgb(86, 190, 78), rgb(46, 146, 66) }
	local clumps = math.floor(150 * around)
	for i = 1, clumps do
		local angle = i / clumps * math.pi * 2 + rng:NextNumber(-0.02, 0.02)
		local fromFront = math.abs(((angle + math.pi / 2 + math.pi) % (math.pi * 2)) - math.pi)
		if fromFront < opening + 0.03 then
			continue
		end
		local r = radius + rng:NextNumber(3, 16)
		local spot = Vector3.new(math.cos(angle) * r, GROUND, math.sin(angle) * r)
		for _ = 1, 3 do
			local height = rng:NextNumber(14, 30)
			part(props, {
				wedge = true,
				size = Vector3.new(0.8, height, rng:NextNumber(3, 5)),
				color = greens[rng:NextInteger(1, 3)],
				cframe = CFrame.new(spot + Vector3.new(rng:NextNumber(-2, 2), height / 2 - 0.2, rng:NextNumber(-2, 2)))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
					* CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, 0),
			})
		end
	end

	-- Flores y setas asomando entre la hierba
	local petals = { rgb(255, 255, 255), rgb(255, 170, 200), rgb(255, 214, 80), rgb(190, 150, 255) }
	local flowers = math.floor(16 * around)
	for i = 1, flowers do
		local angle = (i + rng:NextNumber(-0.3, 0.3)) / flowers * math.pi * 2
		local fromFront = math.abs(((angle + math.pi / 2 + math.pi) % (math.pi * 2)) - math.pi)
		if fromFront < opening + 0.1 then
			continue
		end
		local spot = Vector3.new(math.cos(angle) * (radius + 6), GROUND, math.sin(angle) * (radius + 6))
		if i % 4 == 0 then
			local height = rng:NextNumber(8, 12)
			disc(props, 3.4, height, rgb(255, 240, 214), spot + Vector3.new(0, height / 2, 0))
			local cap = spot + Vector3.new(0, height + 1.4, 0)
			part(props, { size = Vector3.new(14, 8, 14), color = rgb(230, 52, 56), cframe = CFrame.new(cap), blob = true })
			for k = 0, 4 do
				local a = k / 5 * math.pi * 2
				part(props, { size = Vector3.new(2.4, 1.2, 2.4), color = rgb(255, 255, 255), cframe = CFrame.new(cap + Vector3.new(math.cos(a) * 4, 2.9, math.sin(a) * 4)), blob = true, shadow = false })
			end
		else
			local height = rng:NextNumber(20, 30)
			local top = spot + Vector3.new(0, height, 0)
			disc(props, 1, height, rgb(70, 170, 74), spot + Vector3.new(0, height / 2, 0))
			local color = petals[rng:NextInteger(1, #petals)]
			local face = CFrame.lookAt(top, Vector3.new(0, top.Y - 12, 0))
			for k = 0, 5 do
				local a = k / 6 * math.pi * 2
				part(props, { size = Vector3.new(4.4, 4.4, 1.6), color = color, cframe = face * CFrame.new(math.cos(a) * 3.6, math.sin(a) * 3.6, 0), blob = true })
			end
			part(props, { size = Vector3.new(4.4, 4.4, 2.4), color = rgb(255, 196, 40), cframe = face, blob = true })
		end
	end

	-- Lomas bajas pegadas al borde: rompen la línea recta del horizonte
	local hills = math.floor(18 * around)
	for i = 1, hills do
		local angle = i / hills * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local fromFront = math.abs(((angle + math.pi / 2 + math.pi) % (math.pi * 2)) - math.pi)
		if fromFront < opening + 0.15 then
			continue
		end
		local r = radius + rng:NextNumber(18, 34)
		local w = rng:NextNumber(40, 70)
		part(props, { size = Vector3.new(w, rng:NextNumber(14, 26), w * 0.8), color = if i % 2 == 0 then rgb(104, 184, 76) else rgb(88, 170, 70), cframe = CFrame.new(math.cos(angle) * r, GROUND + 1, math.sin(angle) * r), blob = true })
	end

	-- Matas sueltas y tréboles por dentro, para que el suelo no sea una mesa lisa
	for _ = 1, math.floor(46 * area) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber()) * (radius - 6)
		local spot = Vector3.new(math.cos(angle) * r, GROUND, math.sin(angle) * r)
		if rng:NextNumber() < 0.6 then
			for _ = 1, 3 do
				local height = rng:NextNumber(1.6, 3.4)
				part(props, {
					wedge = true,
					size = Vector3.new(0.25, height, rng:NextNumber(0.8, 1.3)),
					color = greens[rng:NextInteger(1, 3)],
					cframe = CFrame.new(spot + Vector3.new(rng:NextNumber(-0.6, 0.6), height / 2 - 0.1, rng:NextNumber(-0.6, 0.6)))
						* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
						* CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, 0),
					shadow = false,
				})
			end
		else
			for k = 0, 2 do
				local a = k / 3 * math.pi * 2
				part(props, { size = Vector3.new(1.5, 0.3, 1.5), color = rgb(70, 170, 74), cframe = CFrame.new(spot + Vector3.new(math.cos(a) * 0.8, 0.5, math.sin(a) * 0.8)), blob = true, shadow = false })
			end
			disc(props, 0.2, 0.5, rgb(70, 170, 74), spot + Vector3.new(0, 0.25, 0), { shadow = false })
		end
	end

	for _ = 1, math.floor(14 * area) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(20, radius - 8)
		local s = rng:NextNumber(1.5, 3.5)
		part(props, { size = Vector3.new(s, s * 0.5, s * rng:NextNumber(0.7, 1.2)), color = if rng:NextNumber() < 0.5 then rgb(176, 180, 190) else rgb(150, 156, 170), cframe = CFrame.new(math.cos(angle) * r, GROUND + s * 0.15, math.sin(angle) * r) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), blob = true })
	end
end

-- Dos caras planas a la misma altura parpadean. Esto repasa las piezas planas pegadas al suelo
-- de un modelo y, donde dos se pisan a la misma altura, sube un pelo la más pequeña.
deflicker = function(model: Instance)
	local flats = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and item.Transparency < 1 then
			local cf, size = item.CFrame, item.Size
			local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
			-- Media caja alineada con el mundo
			local hx = (math.abs(rx.X) * size.X + math.abs(ry.X) * size.Y + math.abs(rz.X) * size.Z) / 2
			local hy = (math.abs(rx.Y) * size.X + math.abs(ry.Y) * size.Y + math.abs(rz.Y) * size.Z) / 2
			local hz = (math.abs(rx.Z) * size.X + math.abs(ry.Z) * size.Y + math.abs(rz.Z) * size.Z) / 2
			local top = cf.Position.Y + hy
			if hy <= 0.3 and top < GROUND + 0.9 and top > GROUND - 0.2 and hx * hz > 0.5 then
				table.insert(flats, { part = item, x = cf.Position.X, z = cf.Position.Z, hx = hx, hz = hz, top = top, area = hx * hz })
			end
		end
	end
	-- De mayor a menor: las grandes se quedan abajo, las pequeñas suben
	table.sort(flats, function(a, b)
		return a.area > b.area
	end)
	for i = 2, #flats do
		local flat = flats[i]
		local lift = 0
		for j = 1, i - 1 do
			local other = flats[j]
			if math.abs(flat.x - other.x) < flat.hx + other.hx and math.abs(flat.z - other.z) < flat.hz + other.hz then
				local gap = flat.top + lift - other.top
				if gap < 0.012 and gap > -0.05 then
					lift = other.top + 0.012 - flat.top
				end
			end
		end
		if lift > 0 then
			flat.part.CFrame += Vector3.new(0, lift, 0)
			flat.top += lift
		end
	end
end

local function decorate(theme: string, parent: Instance, area)
	for _, name in { "Decor3", "Decor2", "Decor" } do
		local module = script.Parent:FindFirstChild(name)
		if module then
			local ok, lib = pcall(require, module)
			if ok and type(lib) == "table" and (lib.Themes == nil or lib.Themes[theme]) then
				-- El suelo de la zona queda 0.08 por encima de GROUND; el decorado plano (manteles,
				-- surcos, baldosas) se apoya un pelo más arriba para no parpadear contra él
				local built, err = pcall(lib.build, theme, parent, area, GROUND + 0.1)
				if built then
					return
				end
				warn(`[CRUNCH!] Decorado de {theme} falló:`, err)
			end
		end
	end
end

-- Puerta de una zona: un muro de rocas apiladas con un arco, cartel y una barrera que cada
-- cliente quita si ya puede pasar. Nada de cajas: todo son bultos redondos.
local function buildGate(gates: Model, zones: Model, zone)
	local z = zone.z0 + 10
	local door = 22 -- media anchura del arco
	local height = 30
	local gateRng = Random.new(zone.id * 97)
	local accent = zone.floor:Lerp(rgb(255, 170, 60), 0.25)
	local stone = { rgb(150, 142, 150), rgb(128, 120, 132), rgb(172, 164, 168) }
	local tint = zone.floor:Lerp(INK, 0.2)

	for _, s in { -1, 1 } do
		local width = MAP.Half - door + 14
		-- Colisión simple detrás de las rocas
		wall(zones, Vector3.new(width, 60, 5), CFrame.new(s * (door + width / 2), GROUND + 30, z))
		-- Dos hiladas de rocas grandes, más pequeñas arriba
		local x = door + 5
		local row = 0
		while x < MAP.Half + 16 do
			local size = gateRng:NextNumber(13, 19)
			for layer = 0, 1 do
				local k = if layer == 0 then 1 else 0.72
				local color = stone[gateRng:NextInteger(1, 3)]:Lerp(tint, 0.25)
				part(zones, {
					size = Vector3.new(size * k * 1.15, size * k * gateRng:NextNumber(0.85, 1.05), size * k * 0.9),
					color = color,
					cframe = CFrame.new(s * (x + size * 0.4 + layer * gateRng:NextNumber(-2, 4)), GROUND + size * 0.38 + layer * size * 0.62, z + gateRng:NextNumber(-1.2, 1.2))
						* CFrame.Angles(gateRng:NextNumber(-0.15, 0.15), gateRng:NextNumber(0, 3), gateRng:NextNumber(-0.15, 0.15)),
					blob = true,
				})
			end
			-- Mata de hierba o musgo coronando algunas rocas
			if row % 2 == 0 then
				part(zones, { size = Vector3.new(7, 4, 6), color = rgb(96, 190, 84), cframe = CFrame.new(s * (x + size * 0.4), GROUND + size * 1.45, z), blob = true })
			end
			x += size * 0.82
			row += 1
		end
		-- Pilar del arco: tambores redondeados apilados
		for i = 0, 4 do
			local d = 9.5 - i * 0.5
			part(zones, { size = Vector3.new(d, 7.4, d), color = if i % 2 == 0 then accent else accent:Lerp(Color3.new(1, 1, 1), 0.3), cframe = CFrame.new(s * (door + 3), GROUND + 3.4 + i * 6.2, z), blob = true, collide = true })
		end
	end

	-- Arco: una fila de dovelas redondas de pilar a pilar
	for i = 0, 8 do
		local t = i / 8
		local a = math.pi * t
		local x = -math.cos(a) * (door + 3)
		local y = height + math.sin(a) * 9
		part(zones, { size = Vector3.new(8.5, 7, 7.5), color = if i % 2 == 0 then accent:Lerp(Color3.new(1, 1, 1), 0.3) else accent, cframe = CFrame.new(x, GROUND + y, z) * CFrame.Angles(0, 0, a - math.pi / 2), blob = true })
	end

	local sign = part(zones, { name = "GateSign", size = Vector3.new(30, 10, 1.2), color = rgb(255, 244, 222), cframe = CFrame.new(0, GROUND + height - 6, z + 4.6) * CFrame.Angles(math.rad(-6), 0, math.rad(-2)) })
	surfaceText(sign, Enum.NormalId.Back, {
		{ text = zone.name, size = 7, color = INK },
		{ text = "Capa " .. zone.id .. " del hormiguero", size = 3, color = rgb(200, 50, 60) },
	})
	for _, s in { -1, 1 } do
		disc(zones, 0.5, 9, rgb(132, 86, 52), Vector3.new(s * 11, GROUND + height + 2.5, z + 4.4))
	end

	local gate = Instance.new("Model")
	gate.Name = "Gate" .. zone.id
	gate:SetAttribute("Zone", zone.id)
	wall(gate, Vector3.new(door * 2, 60, 3), CFrame.new(0, GROUND + 30, z), "Block")
	for i = 0, 3 do
		local bar = part(gate, {
			name = "Bar",
			size = Vector3.new(2.4, door * 2, 2.4),
			color = if i % 2 == 0 then rgb(230, 57, 70) else rgb(255, 250, 235),
			cframe = CFrame.new(0, GROUND + 3.5 + i * 5, z) * CFrame.Angles(0, 0, math.rad(90 + (if i % 2 == 0 then 4 else -4))),
			shape = Enum.PartType.Cylinder,
		})
		bar.Size = Vector3.new(door * 2, 2.4, 2.4)
		bar.CFrame = CFrame.new(0, GROUND + 3.5 + i * 5, z) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 4 else -4))
	end
	gate.WorldPivot = CFrame.new(0, GROUND, z)
	gate.Parent = gates
end

local function buildZones()
	local zones = Instance.new("Model")
	zones.Name = "Zones"
	local walls = Instance.new("Model")
	walls.Name = "Walls"
	-- Un solo contorno para todas las puertas: Roblox dibuja como mucho unos 31 Highlight a la vez.
	-- Las barras abiertas quedan del todo transparentes y así no dejan contorno fantasma.
	local gates = Instance.new("Model")
	gates.Name = "Gates"
	inkOutline(gates)

	local props = Instance.new("Model")
	props.Name = "Props"
	buildLobbyEdge(props, walls)
	inkOutline(props)
	props.Parent = Workspace

	-- Embudo del jardín al camino
	local mouth = -math.sqrt(MAP.LobbyRadius ^ 2 - MAP.Half ^ 2)
	local first = Config.Zones[2]
	local far = lastZone().z1
	for _, s in { -1, 1 } do
		wall(walls, Vector3.new(3, 60, mouth - far + 20), CFrame.new(s * (MAP.Half + 1.5), GROUND + 30, (mouth + far) / 2 - 10))
	end
	wall(walls, Vector3.new(MAP.Half * 2 + 6, 60, 3), CFrame.new(0, GROUND + 30, far - 1.5))
	-- Tierra entre la boca del jardín y el suelo de la primera zona (que empieza en z0 + 20):
	-- a la misma altura que ese suelo y pegada a él, sin solaparse, para que no parpadee
	local pathFrom = first.z0 + 20
	local pathTo = mouth + 4
	if pathTo > pathFrom then
		part(zones, { name = "Path", size = Vector3.new(MAP.Half * 2, 1, pathTo - pathFrom), color = rgb(214, 176, 124), cframe = CFrame.new(0, GROUND - 0.42, (pathTo + pathFrom) / 2), collide = true, shadow = false })
	end

	for index, zone in Config.Zones do
		if index == 1 then
			continue
		end
		local model = Instance.new("Model")
		model.Name = zone.theme
		local length = zone.z0 - zone.z1
		local floor = part(model, {
			name = "Floor",
			size = Vector3.new(MAP.Half * 2 + 30, 1, length + 20),
			color = zone.floor,
			cframe = CFrame.new(0, GROUND - 0.42, zone.z0 - length / 2 + 10),
			collide = true,
			shadow = false,
		})
		halftone(floor, zone.floor:Lerp(INK, 0.3), 0.9)
		decorate(zone.theme, model, { x0 = -MAP.Half, x1 = MAP.Half, z0 = zone.z0, z1 = zone.z1 })
		deflicker(model)
		model.Parent = zones
		buildGate(gates, zones, zone)
		task.wait()
	end

	inkOutline(zones)
	zones.Parent = Workspace
	walls.Parent = Workspace
	gates.Parent = Workspace
end

-- Dos carteles de las más glotonas, junto a la salida del jardín: las de este servidor y las del
-- mundo entero. Los rellena el módulo Leaderboard.
local function buildBoard()
	local board = Instance.new("Model")
	board.Name = "Board"
	local spot = Vector3.new(-0.46 * MAP.LobbyRadius, GROUND, -0.66 * MAP.LobbyRadius)
	local facing = CFrame.lookAt(spot + Vector3.new(0, 13, 0), Vector3.new(0, 13, 0))

	local function panel(name: string, side: number, subtitle: string, ribbon: Color3)
		-- Cada cartel se abre un poco hacia fuera, como las hojas de un biombo
		local frame = facing * CFrame.new(side * 13.6, 0, 0) * CFrame.Angles(0, math.rad(side * 10), 0)
		for _, s in { -1, 1 } do
			part(board, { size = Vector3.new(1.4, 14, 1.4), color = rgb(132, 86, 52), cframe = frame * CFrame.new(s * 9, -6.5, 0.4), collide = true })
		end
		local face = part(board, { name = name, size = Vector3.new(24, 22, 1), color = rgb(255, 244, 222), cframe = frame * CFrame.Angles(0, 0, math.rad(side * 1.5)), collide = true })
		part(board, { size = Vector3.new(27, 2.4, 1.8), color = ribbon, cframe = frame * CFrame.new(0, 12, 0) * CFrame.Angles(0, 0, math.rad(side * -2)), blob = true })
		for _, s in { -1, 1 } do
			part(board, { size = Vector3.new(4, 4, 2.2), color = rgb(255, 210, 63), cframe = frame * CFrame.new(s * 12.6, 11.4, 0), blob = true })
		end

		local gui = Instance.new("SurfaceGui")
		gui.Name = "BoardGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = face

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 0, 0, 6)
		title.Size = UDim2.new(1, 0, 0, 62)
		title.FontFace = BANGERS
		title.TextSize = 60
		title.TextColor3 = INK
		title.Text = "Las más glotonas"
		title.Parent = gui

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.new(0, 0, 0, 62)
		sub.Size = UDim2.new(1, 0, 0, 36)
		sub.FontFace = BANGERS
		sub.TextSize = 34
		sub.TextColor3 = ribbon
		sub.Text = subtitle
		sub.Parent = gui

		for i = 1, 10 do
			local row = Instance.new("TextLabel")
			row.Name = "Row" .. i
			row.BackgroundTransparency = if i % 2 == 0 then 1 else 0.85
			row.BackgroundColor3 = INK
			row.BorderSizePixel = 0
			row.Position = UDim2.new(0.04, 0, 0, 104 + (i - 1) * 54)
			row.Size = UDim2.new(0.92, 0, 0, 50)
			row.FontFace = BANGERS
			row.TextSize = 40
			row.TextColor3 = INK
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.Text = ""
			row.Parent = gui
		end
	end

	panel("ServerPanel", -1, "En este servidor", rgb(230, 57, 70))
	panel("WorldPanel", 1, "En el mundo entero", rgb(40, 150, 230))

	inkOutline(board)
	board.Parent = Workspace
end

-- Viste un hormiguero según lo hondo que ha excavado su dueña, las veces que ha enjambrado y los
-- trofeos que lleva. Los demás jugadores ven cuánto llevas: el montículo crece y se llena de banderas.
function World.dressAnthill(hill: Model, depth: number, rebirths: number, title: string?, trophies: number?)
	local old = hill:FindFirstChild("Mound")
	if old then
		old:Destroy()
	end
	local center = hill:GetPivot().Position
	local inward = (Vector3.new(0, center.Y, 0) - center).Unit
	local side = inward:Cross(Vector3.yAxis)
	local s = Stats.hillScale(depth)

	local mound = Instance.new("Model")
	mound.Name = "Mound"

	-- La tierra se vuelve más rica y rojiza cuanto más honda es la colonia
	local warm = math.clamp((depth - 1) / (Stats.MaxDepth - 1), 0, 1)
	local dirt = {
		rgb(170, 112, 66):Lerp(rgb(150, 70, 52), warm),
		rgb(188, 128, 78):Lerp(rgb(176, 88, 60), warm),
		rgb(204, 144, 90):Lerp(rgb(206, 112, 70), warm),
	}
	local function at(x: number, y: number, z: number): Vector3
		return center + Vector3.new(x, y, z) * s
	end

	-- La colisión es siempre un cilindro simple; el montículo visible lo hace HillModel
	disc(mound, 13 * s, 6 * s, dirt[1], center + Vector3.new(0, 3 * s, 0), { name = "Collider", collide = true, transparency = 1 })

	local built = false
	if HillModel then
		local ok, err = pcall(HillModel.build, mound, { center = center, inward = inward, side = side, scale = s, depth = depth, rebirths = rebirths })
		built = ok
		if not ok then
			warn("[CRUNCH!] Modelo de hormiguero falló:", err)
			for _, child in mound:GetChildren() do
				if child.Name ~= "Collider" then
					child:Destroy()
				end
			end
		end
	end

	-- Los cuerpos grandes del montículo son sólidos: no se atraviesan y, sobre todo, la cámara
	-- no puede quedarse dentro (desde dentro, el contorno de tinta deja la pantalla en negro)
	if built then
		for _, child in mound:GetChildren() do
			if child:IsA("BasePart") and child.Name ~= "Collider" and child.Transparency < 0.25 then
				local size = child.Size
				if math.min(size.X, size.Z) >= 5 * s and size.Y >= 2 * s then
					child.CanCollide = true
					child.CanQuery = true
				end
			end
		end
	end

	-- Montículo de reserva, por si el modelo nuevo no está o falla
	if not built then
		part(mound, { name = "Base", size = Vector3.new(17, 7, 17) * s, color = dirt[1], cframe = CFrame.new(at(0, 1.2, 0)), blob = true })
		part(mound, { size = Vector3.new(12, 7, 12) * s, color = dirt[2], cframe = CFrame.new(at(0.4, 4, -0.3)), blob = true })
		part(mound, { size = Vector3.new(7.5, 5.5, 7.5) * s, color = dirt[3], cframe = CFrame.new(at(-0.2, 6.6, 0.2)), blob = true })
		part(mound, { name = "Hole", size = Vector3.new(3.6, 1.2, 3.6) * s, cframe = CFrame.new(at(-0.2, 9, 0.2)), blob = true, shadow = false })
		disc(mound, 27 * s, 0.08, rgb(196, 150, 100), center + Vector3.new(0, 0.05, 0), { shadow = false })

		-- Boca del montículo, mirando al jardín
		local doorAt = center + inward * 7.6 * s
		part(mound, { name = "Door", size = Vector3.new(5 * s, 6.4 * s, 1.6), cframe = CFrame.lookAt(doorAt + Vector3.new(0, 1.2 * s, 0), doorAt + inward * 5 + Vector3.new(0, 4 * s, 0)), blob = true, shadow = false })

		-- Un montículo satélite por cada dos capas
		local local_rng = Random.new(hill.Name:len() * 7 + depth)
		for i = 1, depth // 2 do
			local a = (i * 1.9) + 2.4
			local away = -inward * math.cos(a) + side * math.sin(a)
			local base = center + away * (10.5 + i * 0.5) * s
			local size = (4 + local_rng:NextNumber(0, 3)) * s
			part(mound, { size = Vector3.new(size, size * 0.8, size), color = dirt[i % 3 + 1], cframe = CFrame.new(base + Vector3.new(0, size * 0.2, 0)), blob = true })
			part(mound, { size = Vector3.new(size * 0.3, size * 0.12, size * 0.3), cframe = CFrame.new(base + Vector3.new(0, size * 0.6, 0)), blob = true, shadow = false })
		end
		for _ = 1, 7 do
			local a = local_rng:NextNumber(0, math.pi * 2)
			local r = local_rng:NextNumber(9, 13) * s
			local size = local_rng:NextNumber(0.8, 1.8)
			part(mound, { size = Vector3.new(size, size * 0.7, size), color = dirt[local_rng:NextInteger(1, 3)], cframe = CFrame.new(center + Vector3.new(math.cos(a) * r, size * 0.25, math.sin(a) * r)), blob = true })
		end

		-- Banderas doradas: una por enjambre, hasta ocho. Con diez, corona.
		local flags = math.min(rebirths, 8)
		for i = 1, flags do
			local a = i / flags * math.pi * 2
			local foot = at(math.cos(a) * 4.6, 5.6, math.sin(a) * 4.6)
			disc(mound, 0.3, 5, rgb(132, 86, 52), foot + Vector3.new(0, 2.5, 0))
			part(mound, { name = "Flag", wedge = true, size = Vector3.new(0.2, 1.6, 2.6), color = if i % 2 == 0 then rgb(255, 200, 60) else rgb(230, 57, 70), cframe = CFrame.new(foot + Vector3.new(0, 4.2, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 1.3) * CFrame.Angles(math.rad(90), 0, 0) })
		end
		if rebirths >= 10 then
			local top = at(-0.2, 10.4, 0.2)
			disc(mound, 5 * s, 1.2, rgb(255, 200, 60), top)
			for i = 0, 5 do
				local a = i / 6 * math.pi * 2
				part(mound, { size = Vector3.new(1.3, 2.2, 1.3), color = rgb(255, 200, 60), cframe = CFrame.new(top + Vector3.new(math.cos(a) * 2.3 * s, 1.5, math.sin(a) * 2.3 * s)) * CFrame.Angles(0, -a, 0), wedge = true })
			end
		end
	end

	-- Cartel de madera con el nombre de la dueña, mirando al jardín
	local signPos = center + (inward * 8 + side * 8) * s
	part(mound, { size = Vector3.new(0.6, 7, 0.6), color = rgb(132, 86, 52), cframe = CFrame.new(signPos + Vector3.new(0, 3.5, 0)) })
	local plank = part(mound, {
		name = "Plank",
		size = Vector3.new(9, 3.6, 0.5),
		color = rgb(255, 236, 204),
		cframe = CFrame.lookAt(signPos + Vector3.new(0, 6.8, 0), signPos + Vector3.new(0, 6.8, 0) + inward) * CFrame.Angles(0, 0, math.rad(-4)),
	})
	-- Segunda línea: "Capa 3 · 5 trofeos · Enjambre 2", sin lo que esté a cero
	local detail = ""
	if title ~= nil then
		local bits = { "Capa " .. depth }
		local count = trophies or 0
		if count > 0 then
			table.insert(bits, count .. (if count == 1 then " trofeo" else " trofeos"))
		end
		if rebirths > 0 then
			table.insert(bits, "Enjambre " .. rebirths)
		end
		detail = table.concat(bits, " · ")
	end
	surfaceText(plank, Enum.NormalId.Front, {
		{ text = title or "Libre", size = 6, color = INK },
		{ text = detail, size = 3, color = rgb(200, 50, 60) },
	})

	mound.Parent = hill

	hill:SetAttribute("Scale", s)
	local spawn = hill:FindFirstChild("Spawn") :: BasePart
	spawn.CFrame = CFrame.lookAt(center + inward * (18 + 14 * s) + Vector3.new(0, 2.5, 0), Vector3.new(0, GROUND + 2.5, 0))
end

local function buildAnthill(parent: Instance, index: number)
	local t = (index - 1) / (MAP.HillCount - 1)
	local angle = math.rad(MAP.HillFrom + (MAP.HillTo - MAP.HillFrom) * t)
	local center = Vector3.new(math.cos(angle) * MAP.HillArc, GROUND, math.sin(angle) * MAP.HillArc)
	World.hillCenters[index] = center

	local hill = Instance.new("Model")
	hill.Name = "Anthill" .. index
	hill.WorldPivot = CFrame.new(center)

	local spawn = part(hill, { name = "Spawn", size = Vector3.new(2, 1, 2), transparency = 1, cframe = CFrame.new(center), shadow = false })
	spawn.CanQuery = false

	hill:SetAttribute("OwnerId", 0)
	hill:SetAttribute("Workers", 0)
	hill:SetAttribute("Soldiers", 0)
	hill:SetAttribute("WorkerSpeed", Config.Worker.Speed)
	hill:SetAttribute("FrenzyUntil", 0)
	hill:SetAttribute("Auto", true)
	hill.Parent = parent
	World.dressAnthill(hill, 1, 0, nil, 0)
end

function World.build()
	Players.CharacterAutoLoads = false

	for _, name in { "Ground", "Baseplate", "Anthills", "Props", "Blanket", "Patches", "SpawnLocation", "LookDev", "Zones", "Walls", "Gates", "Board" } do
		local old = Workspace:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local oldCharacter = StarterPlayer:FindFirstChild("StarterCharacter")
	if oldCharacter then
		oldCharacter:Destroy()
	end
	AntModel.build().Parent = StarterPlayer

	buildLighting()
	buildGround()

	local hills = Instance.new("Model")
	hills.Name = "Anthills"
	for i = 1, MAP.HillCount do
		buildAnthill(hills, i)
	end
	inkOutline(hills)
	hills.Parent = Workspace

	buildZones()
	buildBoard()
end

return World
