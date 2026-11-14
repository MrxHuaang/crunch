-- La hormiga del jugador, al estilo de dibujo animado antiguo (cara de manguera de los años 30:
-- ojos altos con brillo, hocico crema, mejillas rosas) pero con cuerpo de hormiga de verdad:
-- cabeza ancha en forma de corazón, tórax de dos jorobas, cintura de cuentas (pecíolo) y abdomen
-- en forma de gota con bandas. Patas de dos tramos con rodilla y antenas acodadas. El frente es -Z.
--
-- Las partes móviles van con Motor6D para que el cliente las anime (ver client/AntAnim).
-- Regla de diseño: cada unión gira sobre un punto que queda DENTRO de las dos piezas que une
-- (cuello dentro de cabeza y cuello; pecíolo dentro de pecíolo y abdomen), así ninguna pose
-- puede abrir un hueco entre segmentos.

local AntModel = {}

AntModel.Ink = Color3.fromRGB(26, 20, 22)
AntModel.Body = Color3.fromRGB(232, 62, 48)
AntModel.BodyDark = Color3.fromRGB(202, 44, 44)
AntModel.Shine = Color3.fromRGB(255, 156, 132)
AntModel.Cream = Color3.fromRGB(255, 236, 204)
AntModel.Band = AntModel.BodyDark:Lerp(AntModel.Ink, 0.4) -- bandas del abdomen
AntModel.Cheek = Color3.fromRGB(255, 150, 150)

-- Distancia del fondo de la raíz al suelo a escala 1 (los zapatos apoyan a y = -0.5 - 0.82)
AntModel.HipHeight = 0.82
-- Lo que la mandíbula sobresale por detrás de su bisagra (para que AntAnim gire sobre ella)
AntModel.JawOverlap = 0.12

local V3, CF, ANG, rad = Vector3.new, CFrame.new, CFrame.Angles, math.rad

local function newPart(model: Model, name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Elipsoide: bloque con malla de esfera, así puede no ser redondo
local function blob(model, name, size, color): Part
	local part = newPart(model, name, size, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Tramo de manguera: cilindro con el eje en X
local function rod(model, name, length, thickness, color): Part
	local part = newPart(model, name, V3(length, thickness, thickness), color)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = offset
	w.Parent = a
	b.CFrame = a.CFrame * offset
end

local function joint(name: string, a: BasePart, b: BasePart, c0: CFrame, c1: CFrame): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = a
	m.Part1 = b
	m.C0 = c0
	m.C1 = c1
	m:SetAttribute("Base", c0)
	m.Parent = a
	b.CFrame = a.CFrame * c0 * c1:Inverse()
	return m
end

-- Marco con X a lo largo de `x` y Z lo más parecido a `z` (Z es el eje de bisagra de rodillas y codos)
local function frame(pos: Vector3, x: Vector3, z: Vector3): CFrame
	local xu = x.Unit
	local zu = (z - xu * z:Dot(xu)).Unit
	return CFrame.fromMatrix(pos, xu, zu:Cross(xu), zu)
end

-- Sección más gruesa de un grupo de elipsoides (sin girar) en z: semiejes X, Y y centro Y
local function section(shapes, z: number): Vector3?
	local best: Vector3? = nil
	for _, s in shapes do
		local h = s.size / 2
		local d = (z - s.at.Z) / h.Z
		if math.abs(d) < 1 then
			local r = math.sqrt(1 - d * d)
			if not best or h.X * r > best.X then
				best = V3(h.X * r, h.Y * r, s.at.Y)
			end
		end
	end
	return best
end

-- Mandíbula en pinza: tramo base que sale de la boca algo abierto y gancho curvado hacia dentro.
-- tier 0 es la de serie; AntLook usa la misma función para hacerlas crecer.
-- Devuelve: C0 del tramo base (en la cabeza), su tamaño, C0 del gancho (en el tramo base), su tamaño.
function AntModel.jawPose(s: number, tier: number): (CFrame, Vector3, CFrame, Vector3)
	local big = if tier >= 6 then 1 else 0
	local len = 0.5 + 0.1 * tier + 0.25 * big
	local hook = 0.42 + 0.08 * tier + 0.2 * big
	local thick = 1 + 0.12 * tier + 0.25 * big
	-- Cuanto más largas, más abiertas y menos curvadas, para que las puntas no se crucen
	local open = rad(10 + 2.5 * tier)
	local bend = rad(62 - 2 * tier)
	local hinge = V3(s * (0.4 + 0.03 * tier), -0.6 - 0.02 * tier, -0.8)
	local jawC0 = CF(hinge) * ANG(0, -s * open, 0) * CF(0, 0, -len / 2)
	local hookC0 = CF(0, 0, -len / 2) * ANG(0, s * bend, 0) * CF(0, 0, -(hook / 2 - 0.12))
	return jawC0, V3(0.28 * thick, 0.25 * thick, len + AntModel.JawOverlap), hookC0, V3(0.24 * thick, 0.21 * thick, hook)
end

-- Patas (lado derecho; el izquierdo se refleja en X), en el espacio de la raíz: cadera dentro del
-- tórax, rodilla por encima del cuerpo y pie (fin de la tibia, dentro del zapato) cerca del suelo.
local LEGS = {
	{ hip = V3(0.42, -0.22, -0.62), knee = V3(1.08, 0.36, -0.95), foot = V3(1.45, -1, -1.5), toe = 15 },
	{ hip = V3(0.4, -0.18, -0.15), knee = V3(1.18, 0.34, -0.1), foot = V3(1.72, -1, -0.02), toe = 40 },
	{ hip = V3(0.32, -0.12, 0.35), knee = V3(1.05, 0.36, 0.7), foot = V3(1.55, -1, 1.42), toe = 20 },
}

function AntModel.build(): Model
	local model = Instance.new("Model")
	model.Name = "StarterCharacter"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3(2, 1, 3)
	root.Transparency = 1
	root.CanCollide = true
	root.CFrame = CF(0, 5, 0)
	root.Parent = model
	model.PrimaryPart = root

	-- Tórax: joroba delantera grande y trasera pequeña, fundidas; cuello y cintura cuelgan de él
	local thorax = blob(model, "Thorax", V3(1.3, 1.2, 1.25), AntModel.Body)
	weld(root, thorax, CF(0, 0.12, -0.4))
	weld(thorax, blob(model, "ThoraxBack", V3(1, 0.95, 0.9), AntModel.Body), CF(0, 0.03, 0.7))
	-- El cuello rodea el punto de giro de la cabeza: la cabeza nunca se separa al cabecear
	weld(thorax, blob(model, "Neck", V3(0.8, 0.72, 0.8), AntModel.Body), CF(0, 0.19, -0.62))
	-- Cintura de dos cuentas: entra en la joroba trasera y el pecíolo entra en el abdomen
	weld(thorax, blob(model, "Waist", V3(0.44, 0.42, 0.6), AntModel.Body), CF(0, 0.1, 1.2))
	weld(thorax, blob(model, "Petiole", V3(0.6, 0.76, 0.42), AntModel.Body), CF(0, 0.18, 1.48))
	weld(thorax, blob(model, "Shine", V3(0.36, 0.2, 0.5), AntModel.Shine), CF(-0.28, 0.5, -0.12) * ANG(0, 0, rad(20)))

	-- Abdomen en gota: elipsoide ancho delante, cola más estrecha y punta suave, con dos bandas.
	-- Gira sobre un punto dentro del pecíolo y dentro del abdomen (C1 normalizado ≈ 0,71 < 1).
	local abdomen = blob(model, "Abdomen", V3(1.95, 1.7, 1.84), AntModel.BodyDark)
	joint("AbdomenJoint", root, abdomen, CF(0, 0.3, 1.2), CF(0, -0.08, -0.77))
	local gaster = {
		{ at = Vector3.zero, size = abdomen.Size },
		{ at = V3(0, -0.05, 0.58), size = V3(1.3, 1.1, 1.24) },
		{ at = V3(0, -0.1, 1.06), size = V3(0.5, 0.46, 0.48) },
	}
	weld(abdomen, blob(model, "AbdomenTail", gaster[2].size, AntModel.BodyDark), CF(gaster[2].at))
	weld(abdomen, blob(model, "AbdomenTip", gaster[3].size, AntModel.BodyDark), CF(gaster[3].at))
	for _, z in { 0.28, 0.78 } do
		local cut = section(gaster, z) :: Vector3
		-- Disco algo más ancho que el cuerpo: solo asoma su borde, como un anillo
		weld(abdomen, blob(model, "AbdomenBand", V3(cut.X * 2.16, cut.Y * 2.16, 0.4), AntModel.Band), CF(0, cut.Z, z))
	end
	weld(abdomen, blob(model, "Shine", V3(0.5, 0.26, 0.85), AntModel.Shine), CF(-0.45, 0.66, -0.25) * ANG(0, 0, rad(20)))

	-- Cabeza: más ancha que alta, dos lóbulos atrás (corazón visto desde arriba) y hocico delante.
	-- El cuello (punto de giro) queda dentro de la cabeza (normalizado ≈ 0,71) y dentro de "Neck".
	local head = blob(model, "Head", V3(2.1, 1.65, 1.6), AntModel.Body)
	joint("HeadJoint", root, head, CF(0, 0.32, -1.05), CF(0, -0.18, 0.65))
	for _, s in { -1, 1 } do
		weld(head, blob(model, "HeadLobe", V3(1.2, 1.45, 1.3), AntModel.Body), CF(s * 0.5, 0.12, 0.28))
	end
	weld(head, blob(model, "Shine", V3(0.5, 0.24, 0.6), AntModel.Shine), CF(-0.52, 0.8, 0.22) * ANG(0, 0, rad(15)))
	weld(head, blob(model, "Muzzle", V3(1.55, 0.95, 0.85), AntModel.Cream), CF(0, -0.3, -0.6))

	for i, s in { -1, 1 } do
		weld(head, blob(model, "Eye", V3(0.7, 1, 0.45), Color3.new(1, 1, 1)), CF(s * 0.4, 0.28, -0.7))
		weld(head, blob(model, "Pupil", V3(0.32, 0.56, 0.24), AntModel.Ink), CF(s * 0.37, 0.15, -0.88))
		weld(head, blob(model, "Glint", V3(0.13, 0.17, 0.1), Color3.new(1, 1, 1)), CF(s * 0.32, 0.26, -0.98))
		weld(head, blob(model, "Cheek", V3(0.38, 0.24, 0.18), AntModel.Cheek), CF(s * 0.78, -0.25, -0.58) * ANG(0, -s * rad(35), 0))

		-- Pinza: tramo base + gancho soldado a él (se mueve con él al morder)
		local jawC0, jawSize, hookC0, hookSize = AntModel.jawPose(s, 0)
		local jaw = blob(model, "Mandible", jawSize, AntModel.Ink)
		weld(head, jaw, jawC0)
		weld(jaw, blob(model, "MandibleHook", hookSize, AntModel.Ink), hookC0)

		-- Antena acodada: escapo corto hacia arriba y fuera, codo, y flagelo largo hacia delante
		local socket = V3(s * 0.36, 0.6, -0.3)
		local up = V3(s * 0.35, 0.9, 0.22)
		local fwd = V3(s * 0.38, 0.5, -0.78)
		local hinge = up:Cross(fwd).Unit
		local scapeLen, whipLen = 0.62, 0.95
		local scapeFrame = frame(socket, up, hinge)
		local scape = rod(model, "Antenna", scapeLen + 0.06, 0.14, AntModel.Ink)
		joint("Antenna" .. i, head, scape, scapeFrame, CF(-scapeLen / 2, 0, 0))
		local elbowFrame = frame(socket + up.Unit * scapeLen, fwd, hinge)
		local scapeCF = scapeFrame * CF(scapeLen / 2, 0, 0)
		local whip = rod(model, "AntennaWhip", whipLen + 0.04, 0.12, AntModel.Ink)
		joint("AntennaElbow" .. i, scape, whip, scapeCF:Inverse() * elbowFrame, CF(-whipLen / 2, 0, 0))
		weld(scape, blob(model, "AntennaBend", V3(0.2, 0.2, 0.2), AntModel.Ink), CF(scapeLen / 2, 0, 0))
		weld(whip, blob(model, "AntennaTip", V3(0.38, 0.38, 0.38), AntModel.Ink), CF(whipLen / 2 + 0.1, 0, 0))
	end

	-- Patas: muslo (LegN, motor LegN en la cadera) que sube hasta la rodilla y tibia (ShinN, motor
	-- KneeN) que baja al zapato. Las seis salen del tórax. Orden: delantera izq/der, media, trasera.
	local index = 0
	for _, leg in LEGS do
		for _, s in { -1, 1 } do
			index += 1
			local m = V3(s, 1, 1)
			local hip, knee, foot = leg.hip * m, leg.knee * m, leg.foot * m
			-- Eje de bisagra de la rodilla: girar en + sobre él dobla más la pata
			local bend = (knee - hip):Cross(foot - knee).Unit
			local upperLen, lowerLen = (knee - hip).Magnitude, (foot - knee).Magnitude

			local hipFrame = frame(hip, knee - hip, bend)
			local upper = rod(model, "Leg" .. index, upperLen + 0.06, 0.24, AntModel.Ink)
			local hipMotor = joint("Leg" .. index, root, upper, hipFrame, CF(-upperLen / 2, 0, 0))
			hipMotor:SetAttribute("Foot", foot) -- pie en reposo (raíz, escala 1): AntAnim lo mantiene en el suelo

			local upperCF = hipFrame * CF(upperLen / 2, 0, 0)
			local kneeFrame = frame(knee, foot - knee, bend)
			local lower = rod(model, "Shin" .. index, lowerLen + 0.04, 0.21, AntModel.Ink)
			joint("Knee" .. index, upper, lower, upperCF:Inverse() * kneeFrame, CF(-lowerLen / 2, 0, 0))
			weld(upper, blob(model, "LegKnee", V3(0.31, 0.31, 0.31), AntModel.Ink), CF(upperLen / 2, 0, 0))

			-- Zapato plano en el suelo, puntera hacia delante y algo hacia fuera; la tibia entra por el talón
			local shoeCF = CF(foot + V3(0, -0.1, 0)) * ANG(0, -s * rad(leg.toe), 0) * CF(0, 0, -0.12)
			local lowerCF = kneeFrame * CF(lowerLen / 2, 0, 0)
			weld(lower, blob(model, "Shoe", V3(0.56, 0.44, 0.72), AntModel.Cream), lowerCF:Inverse() * shoeCF)
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = AntModel.HipHeight
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	-- Evita que Roblox inyecte el script de animación humanoide
	local animate = Instance.new("LocalScript")
	animate.Name = "Animate"
	animate.Parent = model

	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(20, 16, 16)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model

	return model
end

return AntModel
