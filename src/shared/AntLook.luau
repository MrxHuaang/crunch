-- Aspecto de la hormiga: las mejoras compradas y los cosméticos se ven en el cuerpo.
-- Se aplica en el SERVIDOR sobre el personaje (vivo o aún sin padre). Es idempotente: cada llamada
-- devuelve el modelo a su estado base (guardado en atributos Orig*) y vuelve a montar todo lo
-- añadido dentro de la carpeta "Look". Todo se construye a escala 1 y al final se escala el modelo.
--
-- El cuerpo es de varios elipsoides por segmento (ver AntModel): cabeza + lóbulos, tórax de dos
-- jorobas, abdomen + cola + punta. Púas, placas y rayas siguen la silueta real de cada segmento.

local AntModel = require(script.Parent.AntModel)
local Outfits = require(script.Parent.Outfits)

local AntLook = {}

export type Look = {
	skin: string?,
	hat: string?,
	outfit: string?,
	jaws: number?,
	saw: boolean?,
	spikes: number?,
	belly: number?,
	shoes: number?,
	wings: boolean?,
	armor: number?,
	crown: number?,
	scale: number?,
}

local V3, CF, ANG, rad, rgb = Vector3.new, CFrame.new, CFrame.Angles, math.rad, Color3.fromRGB

local INK = AntModel.Ink
local WHITE = Color3.new(1, 1, 1)
local GOLD = rgb(255, 200, 40)
local RED = rgb(214, 40, 48)
local STEEL = rgb(66, 70, 86)
local UP = ANG(0, 0, math.pi / 2) -- pone de pie un cilindro (su eje es X)
local HAT_SEAT = CF(0, 0.78, 0.28) * ANG(rad(12), 0, 0) -- coronilla, detrás de las antenas, algo echada atrás
local HEAD_TOP = 0.9 -- altura (en la cabeza) de la coronilla sin sombrero

-- "ink" (opcional) sustituye el color de patas, antenas, mandíbulas, púas y bandas
AntLook.Skins = {
	rojo = { body = rgb(232, 62, 48), dark = rgb(202, 44, 44), shine = rgb(255, 156, 132) },
	negra = { body = rgb(48, 44, 52), dark = rgb(32, 29, 36), shine = rgb(126, 120, 136), ink = rgb(96, 82, 76) },
	azul = { body = rgb(52, 120, 232), dark = rgb(36, 88, 196), shine = rgb(150, 200, 255) },
	verde = { body = rgb(76, 184, 72), dark = rgb(48, 146, 60), shine = rgb(176, 240, 150) },
	morada = { body = rgb(150, 82, 214), dark = rgb(116, 56, 180), shine = rgb(212, 170, 255) },
	rosa = { body = rgb(255, 120, 170), dark = rgb(232, 86, 140), shine = rgb(255, 200, 220) },
	dorada = { body = rgb(240, 184, 40), dark = rgb(206, 146, 24), shine = rgb(255, 246, 190) },
}

AntLook.Hats = { "ninguno", "hoja", "lazo", "chistera", "gafas", "casco", "corona" }

local SHOE_COLORS = { rgb(255, 214, 64), rgb(255, 150, 50), rgb(226, 54, 54), rgb(60, 130, 240), rgb(156, 90, 220), GOLD }
local HAT_TOP = { hoja = 1.3, lazo = 1.6, chistera = 1.85, casco = 1.35 } -- altura (en la cabeza) donde acaba el sombrero
local HAT_COVERS = { hoja = true, chistera = true, casco = true, corona = true } -- tapan la coronilla: sin púas ahí

-- Piezas por papel, para recolorear con la piel
local BODY_PARTS = { Thorax = true, ThoraxBack = true, Neck = true, Waist = true, Petiole = true, Head = true, HeadLobe = true }
local DARK_PARTS = { Abdomen = true, AbdomenTail = true, AbdomenTip = true }
local INK_PARTS = { Mandible = true, MandibleHook = true, Antenna = true, AntennaWhip = true, AntennaBend = true, AntennaTip = true, LegKnee = true }
-- Elipsoides (sin girar) que forman la silueta de cada segmento junto con la pieza principal
local SHAPES = { HeadLobe = true, ThoraxBack = true, AbdomenTail = true, AbdomenTip = true }

-- Orden en que salen las púas: segmento, posición a lo largo (-1 frente .. 1 atrás), tamaño relativo
local SPIKES = {
	{ "Abdomen", -0.35, 1 },
	{ "Abdomen", 0.15, 1 },
	{ "Abdomen", 0.6, 0.9 },
	{ "Head", 0.62, 0.8 },
	{ "Abdomen", -0.7, 0.8 },
	{ "Thorax", 0.15, 0.6 },
	{ "Abdomen", 0.88, 0.7 },
	{ "Head", 0.86, 0.65 },
	{ "Abdomen", -0.1, 1.1 },
	{ "Abdomen", 0.38, 1.05 },
}

local function level(value: any, max: number): number
	local n = tonumber(value) or 0
	if n ~= n then
		n = 0
	end
	return math.clamp(math.floor(n), 0, max)
end

local function bodyPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

-- Pieza añadida: soldada a `host` con `offset` y colocada ya en su sitio. shape: nil | "ball" | "cyl" | "wedge"
local function add(folder: Folder, host: BasePart, name: string, size: Vector3, color: Color3, offset: CFrame, shape: string?)
	local part: BasePart = if shape == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Anchored = false
	if shape == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif shape == "cyl" then
		(part :: Part).Shape = Enum.PartType.Cylinder
	end
	part.CFrame = host.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = host
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	part.Parent = folder
	return part
end

-- Silueta de un segmento: su elipsoide y los de forma soldados a él, cortados por el plano medio
-- (x = 0). Cada entrada: centro (Y, Z) y semiejes efectivos (Y, Z) en ese plano y semieje X.
type Shape = { y: number, z: number, hx: number, hy: number, hz: number }
local function outline(host: BasePart): { Shape }
	local list: { Shape } = {}
	local function push(at: Vector3, size: Vector3)
		local h = size / 2
		local k = 1 - (at.X / h.X) ^ 2
		if k > 0.01 then
			local r = math.sqrt(k)
			table.insert(list, { y = at.Y, z = at.Z, hx = h.X * r, hy = h.Y * r, hz = h.Z * r })
		end
	end
	push(Vector3.zero, host.Size)
	for _, w in host:GetChildren() do
		if w:IsA("Weld") and w.Part0 == host and w.Part1 and SHAPES[w.Part1.Name] then
			push(w.C0.Position, w.Part1.Size)
		end
	end
	return list
end

local function span(list: { Shape }): (number, number)
	local z0, z1 = math.huge, -math.huge
	for _, e in list do
		z0 = math.min(z0, e.z - e.hz)
		z1 = math.max(z1, e.z + e.hz)
	end
	return z0, z1
end

-- Sección más gruesa en z: semiejes X, Y y centro Y
local function sectionAt(list: { Shape }, z: number): (number, number, number)
	local bx, by, cy = 0, 0, 0
	for _, e in list do
		local d = (z - e.z) / e.hz
		if math.abs(d) < 1 then
			local r = math.sqrt(1 - d * d)
			if e.hx * r > bx then
				bx, by, cy = e.hx * r, e.hy * r, e.y
			end
		end
	end
	return bx, by, cy
end

-- Punto de la línea superior del segmento (u: -1 frente .. 1 atrás sobre todo su largo),
-- con el eje Y siguiendo la normal de la superficie
local function onTop(host: BasePart, u: number): CFrame
	local list = outline(host)
	local z0, z1 = span(list)
	local margin = 0.07 * (z1 - z0) -- no caer en la punta, donde la pendiente es vertical
	local z = z0 + margin + (u + 1) / 2 * (z1 - z0 - 2 * margin)
	local top, slope = -math.huge, 0
	for _, e in list do
		local d = (z - e.z) / e.hz
		if math.abs(d) < 0.995 then
			local r = math.sqrt(1 - d * d)
			local y = e.y + e.hy * r
			if y > top then
				top = y
				slope = -e.hy * d / (e.hz * r)
			end
		end
	end
	if top == -math.huge then
		top = host.Size.Y / 2
	end
	return CF(0, top, z) * ANG(math.atan(-slope), 0, 0)
end

-- Vuelve al estado base; la primera vez lo guarda en atributos
local function reset(character: Model)
	local old = character:FindFirstChild("Look")
	if old then
		old:Destroy()
	end
	character:ScaleTo(1)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			local size = d:GetAttribute("OrigSize")
			if size then
				d.Size = size
				d.Color = d:GetAttribute("OrigColor")
			else
				d:SetAttribute("OrigSize", d.Size)
				d:SetAttribute("OrigColor", d.Color)
			end
		elseif d:IsA("JointInstance") then
			local c0 = d:GetAttribute("OrigC0")
			if c0 then
				d.C0 = c0
				d.C1 = d:GetAttribute("OrigC1")
			else
				d:SetAttribute("OrigC0", d.C0)
				d:SetAttribute("OrigC1", d.C1)
			end
		end
	end
end

-- Fuera de Workspace las uniones no mueven nada: recoloca las piezas a mano siguiendo las uniones
local function settle(root: BasePart)
	local queue = { root }
	local i = 1
	while queue[i] do
		local part = queue[i]
		i += 1
		for _, j in part:GetChildren() do
			if j:IsA("JointInstance") and j.Part0 == part and j.Part1 then
				j.Part1.CFrame = part.CFrame * j.C0 * j.C1:Inverse()
				table.insert(queue, j.Part1)
			end
		end
	end
end

local function hookOf(jaw: BasePart): Weld?
	for _, w in jaw:GetChildren() do
		if w:IsA("Weld") and w.Part1 and w.Part1.Name == "MandibleHook" then
			return w
		end
	end
	return nil
end

-- Pinzas más largas, gruesas y abiertas (misma fórmula que la de serie, AntModel.jawPose).
-- Devuelve { { mandíbula, lado, gancho? } }
local function growJaws(head: BasePart, tier: number)
	local list = {}
	for _, w in head:GetChildren() do
		local jaw = if w:IsA("Weld") then w.Part1 else nil
		if not jaw or jaw.Name ~= "Mandible" then
			continue
		end
		local s = if w.C0.X < 0 then -1 else 1
		local hookWeld = hookOf(jaw)
		if tier > 0 then
			local jawC0, jawSize, hookC0, hookSize = AntModel.jawPose(s, tier)
			jaw.Size = jawSize
			w.C0 = jawC0
			if hookWeld and hookWeld.Part1 then
				hookWeld.Part1.Size = hookSize
				hookWeld.C0 = hookC0
			end
		end
		table.insert(list, { jaw, s, if hookWeld then hookWeld.Part1 else nil })
	end
	return list
end

local function dressJaws(folder: Folder, list, tier: number, saw: boolean)
	for _, entry in list do
		local jaw, s, hook = entry[1], entry[2], entry[3]
		if tier >= 4 then
			-- Punta de oro en el extremo del gancho
			local host = hook or jaw
			local size = host.Size
			local tip = 0.22 + 0.04 * tier
			add(folder, host, "JawTip", V3(size.X * 0.85, size.Y * 0.85, tip * 2.2), GOLD, CF(0, 0, -size.Z / 2 + tip * 0.5), "ball")
		end
		if saw then
			-- Dientes por el borde interior (lado -s en los dos tramos), medio hundidos en la superficie
			for _, host in { jaw, hook } do
				if not host then
					continue
				end
				local size = host.Size
				local count = 2 + tier // 3
				local d = 0.1 + 0.012 * tier
				for i = 1, count do
					local z = (-0.36 + 0.66 * (i - 0.5) / count) * size.Z
					local edge = size.X / 2 * math.sqrt(math.max(0, 1 - (2 * z / size.Z) ^ 2))
					add(folder, host, "Tooth", V3(d, size.Y * 0.55, d), WHITE, CF(-s * (edge - d * 0.15), 0, z) * ANG(0, rad(45), 0))
				end
			end
		end
	end
end

-- El abdomen crece hacia atrás y algo hacia arriba sobre su punto de giro (dentro del pecíolo):
-- ese punto sigue dentro del abdomen a cualquier tamaño, así que nunca se despega de la cintura
local function growBelly(root: BasePart?, abdomen: BasePart, k: number)
	abdomen.Size *= k
	local motor = root and root:FindFirstChild("AbdomenJoint")
	if motor and motor:IsA("Motor6D") then
		local c1 = motor.C1
		motor.C1 = c1.Rotation + V3(c1.X * k, c1.Y * k - 0.35 * (k - 1), c1.Z * k)
	end
	for _, w in abdomen:GetChildren() do
		if w:IsA("Weld") and w.Part1 then -- cola, punta, bandas y brillo crecen con él
			w.C0 = w.C0.Rotation + w.C0.Position * k
			w.Part1.Size *= k
		end
	end
end

-- Rayas gruesas de cómic: primero encima de las dos bandas de serie, luego hacia delante
local function addStripes(folder: Folder, abdomen: BasePart, belly: number, color: Color3)
	local list = outline(abdomen)
	local z0, z1 = span(list)
	local zs = {}
	for _, w in abdomen:GetChildren() do
		if w:IsA("Weld") and w.Part1 and w.Part1.Name == "AbdomenBand" then
			table.insert(zs, w.C0.Z)
		end
	end
	table.sort(zs)
	for _, f in { 0.37, 0.21 } do
		table.insert(zs, z0 + f * (z1 - z0))
	end
	for i = 1, math.min(#zs, belly - 1, 4) do
		local rx, ry, cy = sectionAt(list, zs[i])
		if rx > 0 then
			add(folder, abdomen, "Stripe", V3(rx * 2.2, ry * 2.2, (z1 - z0) * 0.2), color, CF(0, cy, zs[i]), "ball")
		end
	end
end

local function addSpikes(folder: Folder, character: Model, n: number, color: Color3, skipHead: boolean, skipThorax: boolean)
	for i = 1, math.min(#SPIKES, n * 2) do
		local spec = SPIKES[i]
		local host = bodyPart(character, spec[1])
		if host and not (skipHead and spec[1] == "Head") and not (skipThorax and spec[1] == "Thorax") then
			local h, w = (0.4 + 0.13 * n) * spec[3], (0.24 + 0.05 * n) * spec[3]
			-- Medio elipsoide enterrado: asoma una púa redondeada, algo peinada hacia atrás
			add(folder, host, "Spike", V3(w, h * 2, w), color, onTop(host, spec[2]) * ANG(rad(12), 0, 0), "ball")
		end
	end
end

-- skipThorax: un traje cubre el tórax y va por encima; solo quedan las placas del abdomen
local function addArmor(folder: Folder, character: Model, n: number, skipThorax: boolean)
	local thorax = bodyPart(character, "Thorax")
	local back = bodyPart(character, "ThoraxBack")
	local abdomen = bodyPart(character, "Abdomen")
	if thorax and not skipThorax then
		add(folder, thorax, "Plate", V3(1.42, 0.72, 1.36), STEEL, CF(0, 0.3, 0), "ball")
		if back then
			add(folder, back, "Plate", V3(1.1, 0.56, 1), STEEL, CF(0, 0.22, 0), "ball")
		end
		if n >= 3 then
			for _, s in { -1, 1 } do
				local pad = CF(s * 0.6, 0.25, -0.05) * ANG(0, 0, -s * rad(25))
				add(folder, thorax, "ShoulderPad", V3(0.7, 0.55, 0.85), STEEL, pad, "ball")
				if n >= 5 then
					add(folder, thorax, "PadStud", V3(0.22, 0.22, 0.22), GOLD, pad * CF(0, 0.28, 0), "ball")
				end
			end
		end
	end
	if abdomen then
		local list = outline(abdomen)
		local z0, z1 = span(list)
		for i = 1, n - 1 do
			local at = onTop(abdomen, -0.55 + (i - 1) * 0.4)
			local rx = sectionAt(list, at.Z)
			add(folder, abdomen, "Plate", V3(math.max(rx, 0.3) * 1.4, 0.34, (z1 - z0) * 0.15), STEEL, at * CF(0, -0.06, 0), "ball")
		end
	end
end

local function dressShoes(folder: Folder, character: Model, tier: number)
	for _, shoe in character:GetChildren() do
		if not shoe:IsA("BasePart") or shoe.Name ~= "Shoe" then
			continue
		end
		shoe.Color = SHOE_COLORS[tier]
		if tier >= 3 then
			add(folder, shoe, "ToeCap", V3(0.5, 0.36, 0.4), WHITE, CF(0, -0.03, -0.24), "ball")
		end
		if tier >= 5 then
			-- Aleta de velocidad en el talón (el zapato ya va plano en el suelo)
			add(folder, shoe, "Fin", V3(0.08, 0.34, 0.42), WHITE, CF(0, 0.2, 0.26), "wedge")
		end
	end
end

local function addWings(folder: Folder, thorax: BasePart, belly: number)
	local color = rgb(190, 225, 255)
	for _, s in { -1, 1 } do
		-- largo, ancho, apertura, elevación: par delantero y par trasero. Salen del lomo del tórax y
		-- se levantan más cuanto mayor es el abdomen, para pasar por encima
		for _, w in { { 3.2, 1, 40, 32 }, { 2.3, 0.8, 62, 14 } } do
			local pose = CF(s * 0.22, 0.45, 0.3) * ANG(0, s * rad(w[3]), 0) * ANG(-rad(w[4] + belly * 4), 0, s * rad(16))
			add(folder, thorax, "Wing", V3(w[2], 0.07, w[1]), color, pose * CF(0, 0, w[1] / 2 - 0.15), "ball").Transparency = 0.45
		end
	end
end

local function addCrown(folder: Folder, head: BasePart, at: CFrame, r: number, h: number, royal: boolean)
	add(folder, head, "Crown", V3(h, r * 2, r * 2), GOLD, at * UP, "cyl")
	if royal then
		add(folder, head, "CrownCushion", V3(r * 1.8, h * 1.3, r * 1.8), RED, at * CF(0, h / 2, 0), "ball")
	end
	for i = 1, 5 do
		local spoke = at * ANG(0, i * math.pi * 0.4, 0) * CF(0, h / 2, -r * 0.92)
		add(folder, head, "CrownPoint", V3(r * 0.62, r * 0.62, r * 0.14), GOLD, spoke * ANG(0, 0, math.pi / 4))
		if royal then
			add(folder, head, "Gem", V3(r * 0.3, r * 0.3, r * 0.3), RED, spoke * CF(0, -h / 2, -r * 0.08), "ball")
		end
	end
end

local function addHat(folder: Folder, head: BasePart, hat: string)
	local seat = HAT_SEAT
	if hat == "hoja" then
		local leaf = seat * CF(0, 0.14, 0.2)
		add(folder, head, "Leaf", V3(1.2, 0.3, 1.7), rgb(96, 190, 70), leaf, "ball")
		add(folder, head, "LeafRib", V3(0.1, 0.34, 1.5), rgb(58, 140, 52), leaf, "ball")
		add(folder, head, "LeafStem", V3(0.5, 0.1, 0.1), rgb(58, 140, 52), leaf * CF(0, 0.2, -0.9) * ANG(rad(-35), 0, 0) * UP, "cyl")
	elseif hat == "lazo" then
		for _, s in { -1, 1 } do
			local loop = seat * CF(s * 0.5, 0.34, 0) * ANG(0, 0, s * rad(20))
			add(folder, head, "BowLoop", V3(0.9, 0.62, 0.36), rgb(255, 105, 170), loop, "ball")
		end
		add(folder, head, "BowKnot", V3(0.36, 0.4, 0.42), rgb(230, 70, 140), seat * CF(0, 0.26, 0), "ball")
	elseif hat == "chistera" then
		local black = rgb(30, 28, 34)
		add(folder, head, "HatBrim", V3(0.08, 1.24, 1.24), black, seat * CF(0, 0.14, 0) * UP, "cyl")
		add(folder, head, "HatTop", V3(1.25, 0.84, 0.84), black, seat * CF(0, 0.375, 0) * UP, "cyl")
		add(folder, head, "HatBand", V3(0.2, 0.9, 0.9), RED, seat * CF(0, 0.29, 0) * UP, "cyl")
	elseif hat == "gafas" then
		-- Delante de los ojos (que asoman hasta z ≈ -1,05 con pupila y brillo)
		local dark = rgb(20, 20, 28)
		for _, s in { -1, 1 } do
			add(folder, head, "Lens", V3(0.84, 0.6, 0.14), dark, CF(s * 0.42, 0.3, -1.12), "ball")
			add(folder, head, "LensGlint", V3(0.24, 0.07, 0.04), WHITE, CF(s * 0.42 - 0.14, 0.42, -1.2) * ANG(0, 0, rad(35)))
			add(folder, head, "GlassesArm", V3(0.07, 0.09, 1), dark, CF(s * 0.9, 0.34, -0.62) * ANG(0, s * rad(9), 0))
		end
		add(folder, head, "GlassesBridge", V3(0.24, 0.1, 0.08), dark, CF(0, 0.38, -1.12))
	elseif hat == "casco" then
		add(folder, head, "Helmet", V3(1.36, 1, 1.44), rgb(132, 138, 130), seat * CF(0, 0.02, 0.02), "ball")
		add(folder, head, "HelmetRim", V3(1.72, 0.16, 1.86), rgb(104, 110, 104), seat * CF(0, 0.04, 0.02), "ball")
	elseif hat == "corona" then
		addCrown(folder, head, seat * CF(0, 0.05, -0.03), 0.62, 0.5, true)
	end
end

-- Kit que reciben los trajes (Outfits.build). Además de `add` en el espacio de cada pieza, sabe
-- colocar en el espacio de la raíz en reposo (`at`): recorre las uniones desde la pieza hasta la
-- raíz, así un objeto pensado en coordenadas del cuerpo se suelda a una tibia y la sigue al andar.
local function outfitKit(folder: Folder, character: Model, root: BasePart?, armor: number, belly: number)
	local joints = {}
	for _, d in character:GetDescendants() do
		if d:IsA("JointInstance") and d.Part1 then
			joints[d.Part1] = d
		end
	end
	local function rest(part: BasePart, depth: number?): CFrame?
		if part == root then
			return CFrame.identity
		end
		local j = joints[part]
		if not j or not j.Part0 or (depth or 0) > 12 then
			return nil
		end
		local parent = rest(j.Part0, (depth or 0) + 1)
		return if parent then parent * j.C0 * j.C1:Inverse() else nil
	end

	local k: any = {
		head = bodyPart(character, "Head"),
		thorax = bodyPart(character, "Thorax"),
		back = bodyPart(character, "ThoraxBack"),
		abdomen = bodyPart(character, "Abdomen"),
		root = root,
		seat = HAT_SEAT,
		armor = armor,
		belly = belly,
		shoes = {},
	}
	function k.part(name: string): BasePart?
		return bodyPart(character, name)
	end
	function k.add(host: BasePart, name: string, size: Vector3, color: Color3, offset: CFrame, shape: string?)
		return add(folder, host, name, size, color, offset, shape)
	end
	-- Igual que add, pero `cf` está en el espacio de la raíz con el cuerpo en reposo
	function k.at(host: BasePart, name: string, size: Vector3, color: Color3, cf: CFrame, shape: string?)
		local hostRest = rest(host)
		if not hostRest then
			return nil
		end
		return add(folder, host, name, size, color, hostRest:Inverse() * cf, shape)
	end
	local function rodFrame(a: Vector3, b: Vector3): CFrame
		-- lookAt pone -Z hacia b; girar 90° en Y lleva el eje X del cilindro a esa dirección
		return CFrame.lookAt((a + b) / 2, b) * ANG(0, rad(90), 0)
	end
	-- Cilindro de `a` a `b` (espacio de host)
	function k.rod(host: BasePart, name: string, a: Vector3, b: Vector3, dia: number, color: Color3)
		return add(folder, host, name, V3((b - a).Magnitude, dia, dia), color, rodFrame(a, b), "cyl")
	end
	-- Cilindro de `a` a `b` (espacio de la raíz en reposo)
	function k.rodAt(host: BasePart, name: string, a: Vector3, b: Vector3, dia: number, color: Color3)
		return k.at(host, name, V3((b - a).Magnitude, dia, dia), color, rodFrame(a, b), "cyl")
	end
	-- Disco con su eje en `dir`
	function k.disc(host: BasePart, name: string, center: Vector3, dir: Vector3, dia: number, thick: number, color: Color3)
		return add(folder, host, name, V3(thick, dia, dia), color, rodFrame(center - dir, center + dir), "cyl")
	end
	-- Estrella de ocho puntas en el plano XY de `cf` (dos cuadrados girados 45°)
	function k.star(host: BasePart, cf: CFrame, size: number, color: Color3)
		add(folder, host, "Star", V3(size, size, 0.05), color, cf)
		add(folder, host, "Star", V3(size, size, 0.05), color, cf * ANG(0, 0, rad(45)))
	end
	-- Marco tumbado sobre una superficie: -Z sigue la normal `n`, luego gira `spin` sobre ella
	function k.lay(pos: Vector3, n: Vector3, spin: number?): CFrame
		local up = if math.abs(n.Unit.Y) > 0.9 then V3(0, 0, -1) else Vector3.yAxis
		return CFrame.lookAt(pos, pos + n, up) * ANG(0, 0, spin or 0)
	end
	function k.span(host: BasePart): (number, number)
		return span(outline(host))
	end
	function k.section(host: BasePart, z: number): (number, number, number)
		return sectionAt(outline(host), z)
	end
	-- Zapatos con su número de pata (1-2 delanteras, 3-4 medias, 5-6 traseras) y lado
	for _, part in character:GetChildren() do
		local j = part:IsA("BasePart") and part.Name == "Shoe" and joints[part]
		local shin = j and j.Part0
		if shin then
			local index = tonumber(shin.Name:match("^Shin(%d)$")) or 0
			local at = rest(part)
			table.insert(k.shoes, { part = part, index = index, side = if at and at.X < 0 then -1 else 1 })
		end
	end
	return k
end

function AntLook.apply(character: Model, look: Look?)
	local l: any = look or {}
	local skin = AntLook.Skins[l.skin] or AntLook.Skins.rojo
	local hat: string = if table.find(AntLook.Hats, l.hat) then l.hat else "ninguno"
	-- Traje: el sombrero que tapa no se dibuja (ver la regla en Outfits)
	local outfit = Outfits.byId[l.outfit]
	if outfit and not outfit.build then
		outfit = nil
	end
	local function covers(slot: string): boolean
		return outfit ~= nil and outfit.covers[slot] == true
	end
	if outfit and Outfits.hidesHat(outfit.id, hat) then
		hat = "ninguno"
	end
	local jaws, spikes, belly = level(l.jaws, 6), level(l.spikes, 5), level(l.belly, 6)
	local shoes, armor, crown = level(l.shoes, 6), level(l.armor, 5), level(l.crown, math.huge)
	local scale = math.clamp(tonumber(l.scale) or 1, 1, 2)
	local ink = skin.ink or INK
	local band = skin.ink or skin.dark:Lerp(INK, 0.4)

	reset(character)

	local root = bodyPart(character, "HumanoidRootPart")
	local thorax = bodyPart(character, "Thorax")
	local abdomen = bodyPart(character, "Abdomen")
	local head = bodyPart(character, "Head")

	-- 1) Cambios sobre las piezas base: colores, mandíbulas y abdomen
	for _, part in character:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local name = part.Name
		if BODY_PARTS[name] then
			part.Color = skin.body
		elseif DARK_PARTS[name] then
			part.Color = skin.dark
		elseif name == "AbdomenBand" then
			part.Color = band
		elseif name == "Shine" then
			part.Color = skin.shine
		elseif name == "AntennaTip" and crown >= 1 then
			part.Color = GOLD
		elseif skin.ink and (INK_PARTS[name] or name:match("^Leg%d$") or name:match("^Shin%d$")) then
			part.Color = skin.ink
		end
	end
	local jawList = if head then growJaws(head, jaws) else {}
	if abdomen and belly > 0 then
		growBelly(root, abdomen, 1 + 0.09 * belly)
	end
	if root and not character:IsDescendantOf(workspace) then
		settle(root)
	end

	-- 2) Piezas añadidas, todas dentro de "Look"
	local folder = Instance.new("Folder")
	folder.Name = "Look"

	dressJaws(folder, jawList, jaws, l.saw == true)
	if abdomen and belly >= 3 then
		addStripes(folder, abdomen, belly, skin.ink or skin.dark:Lerp(Color3.new(0, 0, 0), 0.45))
	end
	if armor > 0 then
		addArmor(folder, character, armor, covers("body"))
	end
	if spikes > 0 then
		addSpikes(folder, character, spikes, ink, HAT_COVERS[hat] == true or covers("head"), covers("body"))
	end
	if shoes > 0 then
		dressShoes(folder, character, shoes)
	end
	if thorax and l.wings == true then
		addWings(folder, thorax, belly)
	end
	if thorax and crown >= 5 and not covers("back") then
		-- Capa corta: sale de la nuca (lomo de la joroba delantera) y se levanta más cuanto mayor es
		-- el abdomen, para no atravesarlo
		local hinge = CF(0, 0.6, 0) * ANG(-rad(24 + 5.5 * belly), 0, 0)
		add(folder, thorax, "Cape", V3(1.3, 0.08, 1.3), RED, hinge * CF(0, 0, 0.65))
		add(folder, thorax, "CapeClasp", V3(0.3, 0.3, 0.3), GOLD, hinge, "ball")
	end
	if outfit then
		-- Un fallo en un traje no debe dejar a la hormiga a medio vestir
		local ok, err = pcall(outfit.build, outfitKit(folder, character, root, armor, belly))
		if not ok then
			warn("[CRUNCH!] Traje " .. outfit.id .. ":", err)
		end
	end
	if head then
		addHat(folder, head, hat)
		if crown >= 1 and hat ~= "corona" then
			-- La corona de enjambre flota siempre por encima de lo que lleve en la cabeza
			local top = HAT_TOP[hat] or HEAD_TOP
			if covers("head") then
				top = math.max(top, outfit.top or HEAD_TOP)
			end
			addCrown(folder, head, CF(0, top + 0.5, 0.25), 0.3, 0.22, false)
		end
	end
	folder.Parent = character

	-- 3) Tamaño global y pose de reposo para el animador del cliente
	character:ScaleTo(scale)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.HipHeight = AntModel.HipHeight * scale
	end
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			d:SetAttribute("Base", d.C0)
		end
	end
	character:SetAttribute("LookVersion", (tonumber(character:GetAttribute("LookVersion")) or 0) + 1)
end

return AntLook
