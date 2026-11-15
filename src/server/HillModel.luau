-- El montículo visible de un hormiguero: un volcán bajo y ancho de tierra suelta, con un cráter
-- coronado de bolitas, una puerta en arco al pie y detalles que rompen la silueta.
-- Crece en categoría con la capa excavada, para que los demás lean de un vistazo cuánto llevas:
--   capa 1: montículo humilde (cono de terrones, cráter, puerta, matas, guijarros, hoja, ramita)
--   capa 2: un montón de tierra recién sacada detrás
--   capa 3: dos chimeneas de ventilación y una segunda entrada
--   capa 5: ventanitas redondas con luz cálida, balcón de ramitas y escalera
--   capa 6: tercera chimenea
--   capa 7: terraza de piedras alrededor y dos torrecillas
--   capa 9: borde del cráter con oro y farolillos a la entrada
--   capa 10: las torrecillas con punta de oro
--   capa 11: dos tinajas de reserva junto a la puerta, con miel asomando
--   capa 12: arco de piedras sobre la puerta con clave de oro
--   capa 13: cristales que brotan de la ladera
--   capa 14: un faro de luz en la punta de una torrecilla
-- Enjambres: una banderola por enjambre (hasta 8) y, con 10 o más, una corona de oro en el cráter.
-- Las banderolas se llaman "Flag" y guardan el atributo "Hinge" (punto del mástil) para que el
-- cliente las ondee alrededor de él.
--
-- Coordenadas locales: ángulo `theta` alrededor del centro (0 = `side`, pi/2 = `inward`, hacia el
-- jardín), radio y altura en studs a escala 1; todo se multiplica por `scale`.

local HillModel = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Tierra arenosa: ocres y tostados, nada de chocolate uniforme
local SAND = rgb(236, 196, 128)
local OCHRE = rgb(214, 156, 80)
local TAN = rgb(194, 140, 88)
local CLAY = rgb(176, 120, 74)
local SPILL = rgb(226, 190, 132)
local WARM = rgb(214, 124, 70) -- hacia donde se templa la tierra en las capas hondas
local HOLE = rgb(44, 28, 24)
local WOOD = rgb(132, 86, 52)
local TWIG = rgb(156, 108, 64)
local STONE = { rgb(170, 174, 186), rgb(148, 152, 168), rgb(190, 188, 194) }
local GRASS = { rgb(62, 166, 70), rgb(86, 190, 78), rgb(46, 146, 66) }
local LEAF = rgb(112, 196, 80)
local GOLD = rgb(255, 200, 60)
local RED = rgb(230, 57, 70)
local GLOW = rgb(255, 200, 100)
local POT = rgb(204, 108, 64)
local CRYSTAL = { rgb(170, 120, 255), rgb(120, 220, 255) }

-- Perfil del cono: radio 8 en el suelo, 2.5 arriba, a 7.6 de altura (escala 1)
local BASE_R = 8
local TOP_R = 2.5
local TOP_Y = 7.6
local RIM_Y = 8.05
local DOOR_ANGLE = math.pi / 2 -- la puerta mira al jardín
local SIGN_ANGLE = math.pi / 4 -- el cartel está en (inward + side) * 8
-- Huevo dorado y corro de hongos (Nest): en (inward * 6 - side * 9.5) y (-inward - side * 11)
local EGG_ANGLE = math.atan2(6, -9.5)
local FUNGUS_ANGLE = math.atan2(-1, -11)
local WIND = Vector3.new(0.8, 0, -0.6).Unit -- todas las banderolas ondean hacia el mismo lado

local function angleGap(a: number, b: number): number
	return math.abs((a - b + math.pi) % (math.pi * 2) - math.pi)
end

local function coneR(y: number): number
	return BASE_R + (TOP_R - BASE_R) * (y / TOP_Y)
end

function HillModel.build(mound: Model, info)
	local center: Vector3 = info.center
	local inward: Vector3 = info.inward
	local side: Vector3 = info.side
	local s: number = info.scale or 1
	local depth = math.max(1, math.floor(info.depth or 1))
	local rebirths = math.max(0, math.floor(info.rebirths or 0))
	local up = Vector3.yAxis

	-- La forma base sólo depende del sitio (no se baraja al crecer); los extras, de todo
	local seed = math.floor(center.X * 13.7) * 7919 + math.floor(center.Z * 7.3) * 104729
	local shape = Random.new(seed)
	local rng = Random.new(seed + depth * 1009 + rebirths * 30011)

	local warmth = math.clamp((depth - 1) / 13, 0, 1) * 0.35
	local tint: Color3? = info.tint -- hormigueros de zona: la tierra toma el color de su zona
	local function earth(color: Color3): Color3
		local c = color:Lerp(WARM, warmth)
		return if tint then c:Lerp(tint, 0.5) else c
	end
	local palette = { earth(SAND), earth(OCHRE), earth(TAN), earth(CLAY) }

	local function part(props): BasePart
		local p: BasePart = if props.wedge then Instance.new("WedgePart") else Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = if props.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CastShadow = props.shadow ~= false
		if props.cylinder then
			(p :: Part).Shape = Enum.PartType.Cylinder
		end
		p.Size = props.size
		p.CFrame = props.cframe
		p.Color = props.color
		if props.blob then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Name = props.name or "Part"
		p.Parent = mound
		return p
	end

	local function radial(theta: number): Vector3
		return side * math.cos(theta) + inward * math.sin(theta)
	end
	local function polar(theta: number, r: number, y: number): Vector3
		return center + (radial(theta) * r + up * y) * s
	end
	-- Marco sobre la ladera del cono: Y = normal de la superficie, X = tangente horizontal
	local function onSlope(theta: number, y: number, lift: number): CFrame
		local n = (radial(theta) * TOP_Y + up * (BASE_R - TOP_R)).Unit
		local tangent = up:Cross(radial(theta))
		return CFrame.fromMatrix(polar(theta, coneR(y), y) + n * lift * s, tangent, n)
	end
	-- Ramita (cilindro) entre dos puntos del mundo
	local function stick(a: Vector3, b: Vector3, diameter: number, color: Color3, shadow: boolean?)
		local dir = b - a
		local upHint = if math.abs(dir.Unit.Y) > 0.95 then Vector3.xAxis else up
		return part({
			cylinder = true,
			size = Vector3.new(dir.Magnitude, diameter * s, diameter * s),
			color = color,
			cframe = CFrame.lookAt((a + b) / 2, b, upHint) * CFrame.Angles(0, math.pi / 2, 0),
			shadow = shadow,
		})
	end
	local function disc(diameter: number, height: number, color: Color3, position: Vector3, shadow: boolean?)
		return part({
			cylinder = true,
			size = Vector3.new(height * s, diameter * s, diameter * s),
			color = color,
			cframe = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2),
			shadow = shadow,
		})
	end
	-- Un ángulo libre para los adornos del suelo: lejos del cartel, del pasillo de las obreras,
	-- del huevo dorado y de los hongos
	local function freeAngle(source: Random): number
		local theta = 0
		for _ = 1, 24 do
			theta = source:NextNumber(0, math.pi * 2)
			if
				angleGap(theta, SIGN_ANGLE) > 0.5
				and angleGap(theta, DOOR_ANGLE) > 0.45
				and angleGap(theta, EGG_ANGLE) > 0.45
				and angleGap(theta, FUNGUS_ANGLE) > 0.5
			then
				break
			end
		end
		return theta
	end
	local function pick(list, source: Random)
		return list[source:NextInteger(1, #list)]
	end

	-- Suelo: un derrame de tierra clara alrededor --------------------------------------------
	disc(19, 0.1, earth(SPILL), center + up * 0.07, false)

	-- Cuerpo del cono: base ancha y achatada, y dos cuerpos que se estrechan
	part({ size = Vector3.new(16.4, 2.4, 15.4) * s, color = palette[3], cframe = CFrame.new(center + up * 0.35 * s) * CFrame.Angles(0, shape:NextNumber(0, math.pi), 0), blob = true })
	part({ size = Vector3.new(13.4, 6.2, 12.8) * s, color = palette[4], cframe = CFrame.new(center + up * 1.7 * s) * CFrame.Angles(0, shape:NextNumber(0, math.pi), 0), blob = true })
	part({ size = Vector3.new(9, 5.2, 8.6) * s, color = palette[2], cframe = CFrame.new(center + up * 4.3 * s), blob = true })
	part({ size = Vector3.new(5.8, 3.4, 5.8) * s, color = palette[1], cframe = CFrame.new(center + up * 6.5 * s), blob = true })

	-- Terrones sueltos sobre la ladera: rompen la superficie lisa en bultos de tierra
	local rings = {
		{ y = 0.9, n = 6, w = 3.4, h = 1.8, lift = -0.25 },
		{ y = 3.1, n = 5, w = 2.9, h = 1.6, lift = -0.2 },
		{ y = 5.3, n = 4, w = 2.4, h = 1.4, lift = -0.15 },
	}
	for index, ring in rings do
		local offset = shape:NextNumber(0, math.pi * 2)
		for k = 1, ring.n do
			local theta = offset + k / ring.n * math.pi * 2 + shape:NextNumber(-0.25, 0.25)
			local size = Vector3.new(ring.w * shape:NextNumber(0.85, 1.15), ring.h * shape:NextNumber(0.85, 1.2), ring.w * shape:NextNumber(0.7, 0.95))
			local tone = pick(palette, shape)
			local cframe = onSlope(theta, ring.y + shape:NextNumber(-0.3, 0.3), ring.lift) * CFrame.Angles(0, shape:NextNumber(-0.4, 0.4), 0)
			if index == 1 and angleGap(theta, DOOR_ANGLE) < 0.5 then
				continue -- la puerta necesita la ladera despejada
			end
			if index == 2 and depth >= 7 then
				continue -- en las capas hondas, la terraza de piedras ocupa este anillo
			end
			part({ size = size * s, color = tone, cframe = cframe, blob = true })
		end
	end

	-- Lado vencido: una lengua de tierra que se ha escurrido hacia atrás (sin llegar a los hongos)
	local slump = shape:NextNumber(math.pi * 1.2, math.pi * 1.85)
	local lobeAt = polar(slump, 4.9, 1.1)
	part({ size = Vector3.new(7, 3, 5.2) * s, color = palette[2], cframe = CFrame.lookAt(lobeAt, lobeAt + radial(slump)) * CFrame.Angles(-0.15, 0, 0), blob = true })
	part({ size = Vector3.new(2.6, 1.4, 2.2) * s, color = palette[1], cframe = CFrame.new(polar(slump + 0.3, 6.1, 1.9)) * CFrame.Angles(0.2, shape:NextNumber(0, 3), 0), blob = true })

	-- Granos rodando: dos al pie del lado vencido y uno a media ladera
	for k = 1, 2 do
		local size = shape:NextNumber(0.55, 0.85)
		part({ size = Vector3.new(size, size * 0.85, size) * s, color = pick(palette, shape), cframe = CFrame.new(polar(slump + (k - 1.5) * 0.35, shape:NextNumber(8.4, 9.6), size * 0.35)), blob = true, shadow = false })
	end
	part({ size = Vector3.new(0.7, 0.6, 0.7) * s, color = palette[1], cframe = onSlope(slump - 0.6, 3.6, 0.3), blob = true, shadow = false })

	-- Cráter: anillo de bolitas de tierra y la boca oscura ------------------------------------
	local rimCenter = center + up * RIM_Y * s
	local pellets = 8
	local rimOffset = shape:NextNumber(0, math.pi * 2)
	for k = 1, pellets do
		local theta = rimOffset + k / pellets * math.pi * 2
		local at = polar(theta, 2.45, RIM_Y + shape:NextNumber(-0.1, 0.15))
		local gilded = depth >= 9 and k % 2 == 0
		local color = if gilded then GOLD elseif k % 2 == 0 then palette[1] else palette[2]
		local k2 = shape:NextNumber(0.85, 1.15)
		part({
			size = Vector3.new(1.7, 1.2, 1.4) * k2 * s,
			color = color,
			cframe = CFrame.lookAt(at, Vector3.new(rimCenter.X, at.Y, rimCenter.Z)) * CFrame.Angles(-0.25, 0, 0),
			blob = true,
		})
	end
	part({ name = "Hole", size = Vector3.new(3.4, 0.7, 3.4) * s, color = HOLE, cframe = CFrame.new(center + up * 8.1 * s), blob = true, shadow = false })

	-- Puerta: boca de túnel en arco al pie, enmarcada con guijarros y una ramita de dintel ------
	local doorAt = polar(DOOR_ANGLE, 7.3, 0.85)
	local doorFrame = CFrame.lookAt(doorAt, doorAt + inward) * CFrame.Angles(0.2, 0, 0)
	part({ name = "Door", size = Vector3.new(3, 3.6, 1.3) * s, color = HOLE, cframe = doorFrame, blob = true, shadow = false })
	for _, phi in { 0.12, 0.95, 2.2, 3.02 } do
		local k = shape:NextNumber(0.8, 1.1)
		part({
			size = Vector3.new(1, 0.8, 0.8) * k * s,
			color = pick(STONE, shape),
			cframe = doorFrame * CFrame.new(Vector3.new(math.cos(phi) * 1.85, math.sin(phi) * 1.95 - 0.1, -0.35) * s) * CFrame.Angles(0, 0, phi),
			blob = true,
		})
	end
	stick((doorFrame * CFrame.new(Vector3.new(-2.3, 1.95, -0.5) * s)).Position, (doorFrame * CFrame.new(Vector3.new(2.3, 2.3, -0.5) * s)).Position, 0.38, TWIG)

	-- Adornos del suelo: matas, guijarros, una hoja caída y una ramita apoyada ------------------
	for _ = 1, 2 do
		local theta = freeAngle(shape)
		local spot = polar(theta, shape:NextNumber(8.4, 10.5), 0)
		for _ = 1, 2 do
			local height = shape:NextNumber(1.8, 3.2)
			part({
				wedge = true,
				size = Vector3.new(0.25, height, shape:NextNumber(0.9, 1.4)) * s,
				color = pick(GRASS, shape),
				cframe = CFrame.new(spot + Vector3.new(shape:NextNumber(-0.5, 0.5), height / 2 - 0.1, shape:NextNumber(-0.5, 0.5)) * s)
					* CFrame.Angles(0, shape:NextNumber(0, math.pi * 2), 0)
					* CFrame.Angles(shape:NextNumber(-0.3, 0.3), 0, 0),
				shadow = false,
			})
		end
	end
	for _ = 1, 2 do
		local k = shape:NextNumber(0.8, 1.3)
		part({ size = Vector3.new(1.5, 0.8, 1.2) * k * s, color = pick(STONE, shape), cframe = CFrame.new(polar(freeAngle(shape), shape:NextNumber(9, 11.5), 0.25 * k)) * CFrame.Angles(0, shape:NextNumber(0, 3), 0), blob = true })
	end
	part({ name = "Leaf", size = Vector3.new(3, 0.22, 1.5) * s, color = LEAF, cframe = CFrame.new(polar(freeAngle(shape), 9.6, 0.2)) * CFrame.Angles(0, shape:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(0, 0, 0.12), blob = true, shadow = false })
	local twigAngle = freeAngle(shape)
	stick(polar(twigAngle, 10.8, 0.15), polar(twigAngle + 0.12, 6.4, 2.6), 0.42, TWIG)

	-- Capa 2: un montón de tierra recién sacada ----------------------------------------------
	if depth >= 2 then
		local theta = freeAngle(rng)
		local heap = polar(theta, 10, 0.3)
		part({ size = Vector3.new(2.6, 1.3, 2.4) * s, color = palette[1], cframe = CFrame.new(heap) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), blob = true })
		part({ size = Vector3.new(1.4, 0.9, 1.3) * s, color = palette[2], cframe = CFrame.new(heap + (radial(theta) * 1.4 + up * 0.15) * s), blob = true })
	end

	-- Capa 3+: chimeneas de ventilación y una segunda entrada --------------------------------
	local function vent(theta: number, y: number)
		local foot = polar(theta, coneR(y) - 0.2, y)
		part({ size = Vector3.new(2.6, 1.9, 2.6) * s, color = palette[1], cframe = CFrame.new(foot + up * 0.5 * s), blob = true })
		part({ size = Vector3.new(1.7, 1.6, 1.7) * s, color = palette[2], cframe = CFrame.new(foot + up * 1.5 * s), blob = true })
		part({ size = Vector3.new(1, 0.3, 1) * s, color = HOLE, cframe = CFrame.new(foot + up * 2.3 * s), blob = true, shadow = false })
	end
	if depth >= 3 then
		vent(DOOR_ANGLE + 1, 3.4)
		vent(DOOR_ANGLE - 1.15, 4.4)
		local theta = DOOR_ANGLE + 1.55
		local at = polar(theta, 7.35, 0.6)
		local frame = CFrame.lookAt(at, at + radial(theta)) * CFrame.Angles(0.2, 0, 0)
		part({ size = Vector3.new(2, 2.4, 1) * s, color = HOLE, cframe = frame, blob = true, shadow = false })
		for _, x in { -1.25, 1.25 } do
			part({ size = Vector3.new(0.8, 0.7, 0.7) * s, color = pick(STONE, rng), cframe = frame * CFrame.new(Vector3.new(x, -0.1, -0.3) * s), blob = true })
		end
	end
	if depth >= 6 then
		vent(DOOR_ANGLE + 2.4, 2.4)
	end

	-- Capa 5+: ventanas con luz, balcón de ramitas y escalera --------------------------------
	if depth >= 5 then
		for _, spot in { { DOOR_ANGLE + 0.45, 2.4 }, { DOOR_ANGLE - 0.35, 5 }, { DOOR_ANGLE - 1.6, 2.2 } } do
			local frame = onSlope(spot[1], spot[2], 0)
			local n = frame.UpVector
			local facing = CFrame.fromMatrix(frame.Position, n, frame.RightVector)
			part({ cylinder = true, size = Vector3.new(0.25, 1.65, 1.65) * s, color = WOOD, cframe = facing + n * 0.4 * s })
			part({ cylinder = true, neon = true, size = Vector3.new(0.3, 1.15, 1.15) * s, color = GLOW, cframe = facing + n * 0.5 * s, shadow = false })
		end

		local theta = DOOR_ANGLE - 1.9
		local deckY = 3.6
		local r = coneR(deckY)
		local out = radial(theta)
		local along = up:Cross(out)
		-- Puertecita al balcón
		local nook = polar(theta, r - 0.1, deckY + 1)
		part({ size = Vector3.new(1.3, 1.7, 0.8) * s, color = HOLE, cframe = CFrame.lookAt(nook, nook + out) * CFrame.Angles(0.25, 0, 0), blob = true, shadow = false })
		-- Plataforma redonda de madera
		local deck = polar(theta, r + 0.6, deckY)
		disc(3.2, 0.3, WOOD, deck)
		-- Barandilla: dos postes y un pasamanos de ramita
		local postA = deck + (out * 1.2 + along * 1) * s
		local postB = deck + (out * 1.2 - along * 1) * s
		stick(postA, postA + up * 1.3 * s, 0.22, TWIG, false)
		stick(postB, postB + up * 1.3 * s, 0.22, TWIG, false)
		stick(postA + up * 1.2 * s, postB + up * 1.2 * s, 0.22, TWIG, false)
		-- Escalera apoyada en la ladera hasta el balcón
		local bottom = polar(theta + 0.33, 8.3, 0)
		local top = polar(theta + 0.2, r + 0.9, deckY)
		local across = (top - bottom):Cross(up).Unit * 0.45 * s
		stick(bottom + across, top + across, 0.2, TWIG, false)
		stick(bottom - across, top - across, 0.2, TWIG, false)
		for _, t in { 0.33, 0.66 } do
			local mid = bottom:Lerp(top, t)
			stick(mid + across, mid - across, 0.16, TWIG, false)
		end
	end

	-- Capa 7+: terraza de piedras y dos torrecillas ------------------------------------------
	if depth >= 7 then
		local stones = 7
		local offset = rng:NextNumber(0, math.pi * 2)
		for k = 1, stones do
			local theta = offset + k / stones * math.pi * 2
			if angleGap(theta, DOOR_ANGLE + 1.55) < 0.3 then
				theta += 0.35 -- no tapar la segunda entrada
			end
			local kk = rng:NextNumber(0.85, 1.15)
			part({
				size = Vector3.new(1.9, 1.1, 1.4) * kk * s,
				color = pick(STONE, rng),
				cframe = onSlope(theta, 2.9, 0.1) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
				blob = true,
			})
		end
		for _, theta in { DOOR_ANGLE + 2.2, DOOR_ANGLE - 2.4 } do
			local foot = polar(theta, coneR(4.5) - 0.3, 4.5)
			local tip = if depth >= 10 then GOLD else palette[1]
			part({ size = Vector3.new(1.9, 4.6, 1.9) * s, color = palette[2], cframe = CFrame.new(foot + up * 1.8 * s), blob = true })
			part({ size = Vector3.new(1, 1.8, 1) * s, color = tip, cframe = CFrame.new(foot + up * 4.4 * s), blob = true })
		end
	end

	-- Capa 9+: farolillos a la entrada (el borde del cráter ya lleva oro) ----------------------
	if depth >= 9 then
		for _, theta in { DOOR_ANGLE - 0.32, DOOR_ANGLE + 0.32, slump + math.pi * 0.15 } do
			local foot = polar(theta, 9.6, 0)
			stick(foot, foot + up * 3.4 * s, 0.3, WOOD)
			part({ neon = true, size = Vector3.new(0.9, 1.1, 0.9) * s, color = GLOW, cframe = CFrame.new(foot + up * 3.9 * s), blob = true, shadow = false })
		end
	end

	-- Capa 11+: tinajas de reserva a los lados de la puerta -----------------------------------
	if depth >= 11 then
		for _, theta in { DOOR_ANGLE + 0.62, DOOR_ANGLE - 0.6 } do
			local foot = polar(theta, 9.2, 0)
			part({ size = Vector3.new(1.9, 2.2, 1.9) * s, color = POT, cframe = CFrame.new(foot + up * 1.05 * s), blob = true })
			disc(1.3, 0.35, POT:Lerp(HOLE, 0.3), foot + up * 2.1 * s)
			part({ size = Vector3.new(1.1, 0.5, 1.1) * s, color = GOLD, cframe = CFrame.new(foot + up * 2.3 * s), blob = true, shadow = false })
		end
	end

	-- Capa 12+: arco de piedras sobre la puerta, con la clave de oro -------------------------
	if depth >= 12 then
		for _, phi in { 0.55, math.pi / 2, math.pi - 0.55 } do
			local key = phi == math.pi / 2
			part({
				size = Vector3.new(1.3, 1.1, 0.9) * s,
				color = if key then GOLD else pick(STONE, rng),
				cframe = doorFrame * CFrame.new(Vector3.new(math.cos(phi) * 2.3, math.sin(phi) * 2.6 - 0.1, -0.45) * s) * CFrame.Angles(0, 0, phi - math.pi / 2),
				blob = true,
			})
		end
	end

	-- Capa 13+: cristales brotando de la ladera baja ------------------------------------------
	if depth >= 13 then
		for _ = 1, 3 do
			local base = onSlope(freeAngle(rng), 1.3, 0.1)
			for j = 1, 3 do
				local h = if j == 2 then 2.6 else 1.7
				part({
					size = Vector3.new(0.7, h, 0.7) * s,
					color = CRYSTAL[if j == 2 then 1 else 2],
					cframe = base * CFrame.new(Vector3.new((j - 2) * 0.55, h / 2 - 0.2, 0) * s) * CFrame.Angles(0, 0, (j - 2) * -0.35),
					shadow = false,
				})
			end
		end
	end

	-- Capa 14: faro en la punta de la primera torrecilla ---------------------------------------
	if depth >= 14 then
		local foot = polar(DOOR_ANGLE + 2.2, coneR(4.5) - 0.3, 4.5)
		local star = foot + up * 6.3 * s
		stick(foot + up * 5.1 * s, star, 0.2, GOLD, false)
		local lamp = part({ neon = true, size = Vector3.new(1.4, 1.4, 1.4) * s, color = GLOW, cframe = CFrame.new(star), blob = true, shadow = false })
		local light = Instance.new("PointLight")
		light.Color = GLOW
		light.Range = 14
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = lamp
	end

	-- Enjambres: banderolas alrededor del cráter, oro y rojo --------------------------------
	local flags = math.min(rebirths, 8)
	local flagH, flagL = 1.5, 2.3
	for i = 1, flags do
		local theta = DOOR_ANGLE + (i - 0.5) / flags * math.pi * 2
		local footY = (BASE_R - 3.3) / (BASE_R - TOP_R) * TOP_Y
		local foot = polar(theta, 3.3, footY - 0.3)
		local top = foot + up * 3.9 * s
		stick(foot, top, 0.22, WOOD)
		local hinge = top - up * (flagH / 2) * s
		local middle = hinge + WIND * (flagL / 2) * s
		local flag = part({
			name = "Flag",
			wedge = true,
			size = Vector3.new(0.12, flagH, flagL) * s,
			color = if i % 2 == 1 then GOLD else RED,
			cframe = CFrame.lookAt(middle, middle + WIND) * CFrame.Angles(0, 0, math.pi),
			shadow = false,
		})
		flag:SetAttribute("Hinge", hinge)
	end

	-- Diez enjambres o más: corona de oro alrededor del cráter
	if rebirths >= 10 then
		for k = 1, 6 do
			local theta = rimOffset + (k + 0.5) / 6 * math.pi * 2
			local at = polar(theta, 2.75, RIM_Y + 0.9)
			part({
				wedge = true,
				size = Vector3.new(0.35, 1.6, 1) * s,
				color = GOLD,
				cframe = CFrame.lookAt(at, Vector3.new(rimCenter.X, at.Y, rimCenter.Z)),
			})
		end
	end
end

return HillModel
