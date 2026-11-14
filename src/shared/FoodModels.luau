-- Construye cada comida con piezas sueltas. Al comerla, el servidor quita piezas
-- de la última a la primera, así la comida se desmonta de verdad en vez de encoger.
-- Cada modelo se arma con el suelo en y = 0 y el centro en el origen.

local FoodModels = {}

local rng = Random.new(7)

local function base(model: Model, order: number, props): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = props.shadow ~= false
	part.Size = props.size
	part.Color = props.color
	part.CFrame = props.cframe
	if props.shape then
		part.Shape = props.shape
	end
	part.Name = "Piece"
	part:SetAttribute("Order", order)
	part.Parent = model
	return part
end

local function block(model, order, size, color, cframe)
	return base(model, order, { size = size, color = color, cframe = cframe })
end

local function ball(model, order, diameter, color, position)
	return base(model, order, {
		size = Vector3.new(diameter, diameter, diameter),
		color = color,
		cframe = CFrame.new(position),
		shape = Enum.PartType.Ball,
	})
end

-- Elipsoide: bloque con malla de esfera, así puede no ser redondo
local function blob(model, order, size, color, position)
	local part = base(model, order, { size = size, color = color, cframe = CFrame.new(position) })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Cilindro de pie (eje vertical)
local function disc(model, order, diameter, height, color, position)
	return base(model, order, {
		size = Vector3.new(height, diameter, diameter),
		color = color,
		cframe = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		shape = Enum.PartType.Cylinder,
	})
end

-- Cilindro tumbado o inclinado: el eje sigue el eje X del CFrame
local function rod(model, order, diameter, length, color, cframe)
	return base(model, order, {
		size = Vector3.new(length, diameter, diameter),
		color = color,
		cframe = cframe,
		shape = Enum.PartType.Cylinder,
	})
end

-- Cuña: el ángulo recto queda abajo y atrás (-Y, +Z) y la rampa baja hacia -Z
local function wedge(model, order, size, color, cframe)
	local part = Instance.new("WedgePart")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.CFrame = cframe
	part.Name = "Piece"
	part:SetAttribute("Order", order)
	part.Parent = model
	return part
end

-- Prisma triangular a partir de sus tres vértices. `corner` es el del ángulo recto;
-- el grosor se reparte a los dos lados del plano del triángulo.
local function triangle(model, order, thickness, color, corner, tip, toe)
	local up = tip - corner
	local back = corner - toe
	local right = up.Unit:Cross(back.Unit)
	return wedge(model, order, Vector3.new(thickness, up.Magnitude, back.Magnitude), color, CFrame.fromMatrix((tip + toe) / 2, right, up.Unit, back.Unit))
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local BUILDERS = {}

function BUILDERS.Miga(model)
	local crumb = rgb(252, 226, 170)
	local crumbLight = rgb(255, 240, 200)
	local crust = rgb(204, 126, 52)
	local crustLight = rgb(226, 152, 72)
	local hole = rgb(222, 184, 120)
	-- Un pellizco de pan arrancado: miga esponjosa por delante, corteza tostada detrás y arriba
	blob(model, 1, Vector3.new(2, 1.4, 1.8), crumb, Vector3.new(0, 0.7, 0))
	blob(model, 2, Vector3.new(1.4, 1.2, 1.3), crumbLight, Vector3.new(0.55, 0.6, 0.35))
	blob(model, 3, Vector3.new(2.3, 1.15, 0.7), crust, Vector3.zero).CFrame = CFrame.new(0, 0.72, -0.78) * CFrame.Angles(0, math.rad(-8), 0)
	blob(model, 4, Vector3.new(2, 0.55, 1.4), crustLight, Vector3.new(-0.1, 1.3, -0.35))
	blob(model, 5, Vector3.new(0.7, 1.05, 1.6), crust, Vector3.new(-0.98, 0.62, -0.15))
	-- Bordes desgarrados: grumos de miga sueltos
	local order = 5
	for _, spot in { Vector3.new(0.95, 0.95, 0.55), Vector3.new(0.3, 1.18, 0.72), Vector3.new(1.05, 0.42, -0.2) } do
		order += 1
		blob(model, order, Vector3.new(0.6, 0.48, 0.55), crumbLight, spot)
	end
	-- Agujeritos de aire en las caras de miga (posición y hacia dónde mira la cara)
	local holes = {
		{ Vector3.new(0.55, 0.62, 1.0), Vector3.new(0, 0, 1) },
		{ Vector3.new(0.92, 0.85, 0.86), Vector3.new(0.76, 0.7, 1.2) },
		{ Vector3.new(1.25, 0.55, 0.35), Vector3.new(1, 0, 0) },
		{ Vector3.new(-0.4, 0.91, 0.78), Vector3.new(-0.4, 0.43, 0.97) },
	}
	for _, spot in holes do
		order += 1
		local pos = spot[1]
		blob(model, order, Vector3.new(0.36, 0.28, 0.12), hole, pos).CFrame = CFrame.lookAt(pos, pos + spot[2])
	end
	-- Una semilla de sésamo sobre la corteza
	order += 1
	blob(model, order, Vector3.new(0.32, 0.12, 0.18), crumbLight, Vector3.zero).CFrame = CFrame.new(-0.45, 1.56, -0.4) * CFrame.Angles(0, 0.6, 0)
	return 1.25, 1.6
end

function BUILDERS.Azucar(model)
	local order = 0
	local s = 1.15
	for y = 0, 2 do
		for x = -1, 1 do
			for z = -1, 1 do
				order += 1
				local tone = if (x + y + z) % 2 == 0 then rgb(252, 250, 244) else rgb(236, 234, 226)
				block(model, order, Vector3.new(s, s, s), tone, CFrame.new(x * s, s / 2 + y * s, z * s))
			end
		end
	end
	return 2.5, 3.5
end

function BUILDERS.Galleta(model)
	local dough = rgb(214, 160, 96)
	local doughDark = rgb(196, 142, 82)
	local chip = rgb(74, 44, 30)
	disc(model, 1, 4.4, 0.9, dough, Vector3.new(0, 0.45, 0))
	ball(model, 2, 0.8, chip, Vector3.new(0.5, 0.95, -0.4))
	local order = 2
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		order += 1
		block(model, order, Vector3.new(2.7, 0.9, 2.5), if i % 2 == 0 then dough else doughDark, CFrame.lookAt(dir * 3.1 + Vector3.new(0, 0.45, 0), dir * 9 + Vector3.new(0, 0.45, 0)))
		if i % 3 == 0 then
			order += 1
			ball(model, order, 0.85, chip, dir * 3.2 + Vector3.new(0, 0.95, 0))
		end
	end
	return 4.6, 1
end

function BUILDERS.Manzana(model)
	local red = rgb(222, 44, 52)
	local redDark = rgb(196, 34, 46)
	-- El corazón es la primera pieza: es lo último que queda
	disc(model, 1, 1.5, 6.4, rgb(250, 236, 196), Vector3.new(0, 3.3, 0))
	-- Cinco gajos gordos que se solapan: silueta de manzana, y cada mordida grande se lleva uno
	local order = 1
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2
		order += 1
		blob(model, order, Vector3.new(5.6, 6.6, 5.6), if i % 2 == 0 then red else redDark, Vector3.new(math.cos(angle) * 1.5, 3.5, math.sin(angle) * 1.5))
	end
	order += 1
	block(model, order, Vector3.new(0.4, 1.8, 0.4), rgb(96, 62, 38), CFrame.new(0, 7.3, 0) * CFrame.Angles(0, 0, math.rad(12)))
	order += 1
	block(model, order, Vector3.new(2, 0.2, 1), rgb(96, 190, 84), CFrame.new(0.9, 7.6, 0) * CFrame.Angles(0, math.rad(20), math.rad(-25)))
	return 4.6, 7
end

function BUILDERS.Sandwich(model)
	local layers = {
		{ h = 1.3, half = 4.2, colors = { rgb(232, 190, 128), rgb(222, 178, 116) } }, -- pan
		{ h = 0.5, half = 4.35, colors = { rgb(240, 150, 150), rgb(230, 136, 138) } }, -- jamón
		{ h = 0.4, half = 4.6, colors = { rgb(252, 208, 70), rgb(246, 196, 56) } }, -- queso
		{ h = 0.5, half = 4.8, colors = { rgb(120, 200, 90), rgb(104, 184, 78) } }, -- lechuga
		{ h = 0.5, half = 4.1, colors = { rgb(226, 60, 54), rgb(210, 48, 46) } }, -- tomate
		{ h = 1.5, half = 4.2, colors = { rgb(232, 190, 128), rgb(222, 178, 116) } }, -- pan
	}
	local order = 0
	local y = 0
	for index, layer in layers do
		local turn = CFrame.Angles(0, math.rad((index % 3 - 1) * 5), 0)
		for qx = 0, 1 do
			for qz = 0, 1 do
				order += 1
				local offset = Vector3.new((qx - 0.5) * layer.half, y + layer.h / 2, (qz - 0.5) * layer.half)
				block(model, order, Vector3.new(layer.half, layer.h, layer.half), layer.colors[(qx + qz) % 2 + 1], turn * CFrame.new(offset))
			end
		end
		y += layer.h
	end
	return 6.4, 4.7
end

function BUILDERS.Lata(model)
	local red = rgb(226, 46, 56)
	local white = rgb(250, 248, 244)
	local metal = rgb(196, 200, 206)
	local bands = { metal, red, red, white, red, white, red, red, metal }
	local order = 0
	for i, color in bands do
		order += 1
		disc(model, order, if color == metal then 5.6 else 6, 1, color, Vector3.new(0, i - 0.5, 0))
	end
	order += 1
	block(model, order, Vector3.new(1.6, 0.2, 0.9), metal, CFrame.new(0.6, 9.1, 0))
	return 3.2, 9
end

function BUILDERS.Tarta(model)
	local sponge = rgb(250, 214, 150)
	local frosting = rgb(255, 150, 186)
	local cream = rgb(255, 250, 240)
	local cherry = rgb(214, 30, 52)
	local tiers = {
		{ d = 22, dollops = 14 },
		{ d = 16, dollops = 10 },
		{ d = 10, dollops = 7 },
	}
	local order = 0
	local y = 0
	for _, tier in tiers do
		for _, slab in { { 2.2, sponge }, { 0.8, cream }, { 2.2, sponge }, { 1, frosting } } do
			order += 1
			disc(model, order, tier.d, slab[1], slab[2], Vector3.new(0, y + slab[1] / 2, 0))
			y += slab[1]
		end
		for i = 0, tier.dollops - 1 do
			local angle = i / tier.dollops * math.pi * 2
			order += 1
			ball(model, order, 1.7, cream, Vector3.new(math.cos(angle) * (tier.d / 2 - 1.1), y + 0.5, math.sin(angle) * (tier.d / 2 - 1.1)))
		end
	end
	order += 1
	ball(model, order, 2.6, cherry, Vector3.new(0, y + 1.2, 0))
	return 11.4, y
end

function BUILDERS.Semilla(model)
	local shell = rgb(54, 48, 52)
	local shellDark = rgb(38, 34, 38)
	local cream = rgb(246, 236, 210)
	local grey = rgb(118, 112, 116)
	-- Pipa tumbada: panza gorda, culito redondo y punta fina hacia +X
	blob(model, 1, Vector3.new(1.9, 0.85, 1.35), shell, Vector3.new(-0.2, 0.43, 0))
	blob(model, 2, Vector3.new(1.3, 0.62, 0.85), shellDark, Vector3.new(0.72, 0.33, 0))
	blob(model, 3, Vector3.new(0.8, 0.74, 1.12), shell, Vector3.new(-0.95, 0.4, 0))
	-- Raya clara por el lomo, dos más que se juntan hacia la punta y dos grises por fuera
	blob(model, 4, Vector3.new(1.9, 0.2, 0.22), cream, Vector3.new(-0.12, 0.8, 0))
	local order = 4
	for _, side in { -1, 1 } do
		order += 1
		blob(model, order, Vector3.new(1.45, 0.18, 0.18), cream, Vector3.zero).CFrame = CFrame.new(-0.22, 0.73, side * 0.38) * CFrame.Angles(side * 0.5, side * math.rad(9), 0)
	end
	for _, side in { -1, 1 } do
		order += 1
		blob(model, order, Vector3.new(1.15, 0.16, 0.14), grey, Vector3.zero).CFrame = CFrame.new(-0.3, 0.6, side * 0.58) * CFrame.Angles(side * 0.95, side * math.rad(6), 0)
	end
	-- Brillo en el lomo y un pétalo de girasol caído debajo
	order += 1
	blob(model, order, Vector3.new(0.6, 0.1, 0.26), rgb(156, 150, 158), Vector3.new(-0.55, 0.83, -0.2))
	order += 1
	blob(model, order, Vector3.new(2.2, 0.1, 0.75), rgb(255, 196, 40), Vector3.zero).CFrame = CFrame.new(0.3, 0.05, 0.6) * CFrame.Angles(0, 0.5, 0)
	return 1.35, 0.9
end

function BUILDERS.Arandano(model)
	local blue = rgb(64, 82, 204)
	local blueDark = rgb(48, 62, 176)
	local bloom = rgb(132, 150, 222)
	local crown = rgb(36, 40, 100)
	ball(model, 1, 2.6, blue, Vector3.new(0, 1.95, 0))
	blob(model, 2, Vector3.new(2.6, 1.5, 2.6), blue, Vector3.new(0, 0.8, 0))
	-- Seis gajos alrededor del corazón forman la esfera
	local order = 2
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		order += 1
		blob(model, order, Vector3.new(2.7, 3.7, 2.7), if i % 2 == 0 then blue else blueDark, Vector3.new(math.cos(angle) * 0.65, 1.95, math.sin(angle) * 0.65))
	end
	order += 1
	blob(model, order, Vector3.new(2.6, 1.5, 2.6), blue, Vector3.new(0, 3.1, 0))
	-- Pruina: el velo claro y mate de los arándanos de verdad, a manchas
	for _, angle in { 2.4, 4.1, 5.6 } do
		local pos = Vector3.new(math.cos(angle) * 1.95, 2.35, math.sin(angle) * 1.95)
		order += 1
		blob(model, order, Vector3.new(1.4, 1.1, 0.22), bloom, pos).CFrame = CFrame.lookAt(pos, pos + Vector3.new(math.cos(angle), 0.25, math.sin(angle)))
	end
	-- Coronita de cinco puntas
	order += 1
	disc(model, order, 1.5, 0.3, crown, Vector3.new(0, 3.85, 0))
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local pos = dir * 0.7 + Vector3.new(0, 3.95, 0)
		order += 1
		blob(model, order, Vector3.new(0.45, 0.26, 0.8), crown, pos).CFrame = CFrame.lookAt(pos, pos + dir + Vector3.new(0, 0.45, 0))
	end
	-- Brillo pegado a la piel
	order += 1
	local shinePos = Vector3.new(1.36, 3.17, 0.68)
	blob(model, order, Vector3.new(1, 0.6, 0.3), rgb(176, 194, 255), shinePos).CFrame = CFrame.lookAt(shinePos, shinePos + Vector3.new(0.7, 0.63, 0.35))
	-- Rabito con una hojita y su nervio
	order += 1
	block(model, order, Vector3.new(0.22, 0.7, 0.22), rgb(110, 76, 44), CFrame.new(-0.25, 4.2, 0.1) * CFrame.Angles(0, 0, math.rad(15)))
	local leafFrame = CFrame.new(-1.05, 3.95, 0.25) * CFrame.Angles(0, math.rad(-20), math.rad(20))
	order += 1
	blob(model, order, Vector3.new(2.2, 0.18, 1.1), rgb(98, 184, 82), Vector3.zero).CFrame = leafFrame
	order += 1
	blob(model, order, Vector3.new(1.8, 0.2, 0.14), rgb(70, 150, 62), Vector3.zero).CFrame = leafFrame * CFrame.new(0, 0.02, 0)
	return 2.1, 4.4
end

function BUILDERS.Platano(model)
	local yellow = rgb(255, 216, 60)
	local yellowDark = rgb(246, 200, 44)
	local brown = rgb(104, 68, 40)
	local arc = 4.4 -- radio del arco que dibuja el plátano sobre el suelo
	local depth = 3.7 -- adelanta el arco para dejarlo centrado en el origen
	local step = math.rad(10.5)
	local widths = { 2.25, 2.2, 2.05, 1.8, 1.4 } -- del centro a las puntas

	local function at(angle, y)
		return CFrame.new(math.sin(angle) * arc, y, math.cos(angle) * arc - depth) * CFrame.Angles(0, angle, 0)
	end

	-- El tramo central es el corazón; los demás salen por parejas hacia las puntas
	rod(model, 1, widths[1], 1.05, yellow, at(0, widths[1] / 2))
	local order = 1
	for k = 1, 4 do
		local d = widths[k + 1]
		for _, side in { -1, 1 } do
			order += 1
			rod(model, order, d, 1.05, if k % 2 == 0 then yellow else yellowDark, at(side * k * step, d / 2))
		end
	end
	order += 1
	rod(model, order, 0.85, 0.6, brown, at(-4.7 * step, 0.7))
	order += 1
	rod(model, order, 0.95, 1.1, rgb(196, 190, 60), at(4.65 * step, 0.7))
	order += 1
	rod(model, order, 1.1, 0.4, brown, at(5.35 * step, 0.7))
	-- Pecas maduras en el lomo
	for _, spot in { { -2, 2.05 }, { 0.5, 2.25 }, { 3, 1.8 } } do
		order += 1
		local mark = blob(model, order, Vector3.new(0.6, 0.14, 0.4), brown, Vector3.zero)
		mark.CFrame = at(spot[1] * step, spot[2])
	end
	return 4.4, 2.3
end

function BUILDERS.Coco(model)
	local shell = rgb(126, 82, 48)
	local shellDark = rgb(108, 68, 40)
	local flesh = rgb(253, 251, 245)
	local fleshDark = rgb(240, 236, 226)
	local hollow = rgb(226, 220, 206)
	local eye = rgb(54, 34, 24)
	-- Cuenco: panza redonda, fondo de pulpa hundido y un anillo de cáscara con otro de pulpa por dentro
	blob(model, 1, Vector3.new(7.5, 4.4, 7.5), shell, Vector3.new(0, 2.2, 0))
	disc(model, 2, 5.4, 0.6, hollow, Vector3.new(0, 4.15, 0))
	local order = 2
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		order += 1
		block(model, order, Vector3.new(2.5, 2.75, 0.6), if i % 2 == 0 then shell else shellDark, CFrame.lookAt(dir * 3.5 + Vector3.new(0, 3.375, 0), dir * 9 + Vector3.new(0, 3.375, 0)))
		local mid = angle + math.pi / 10
		local midDir = Vector3.new(math.cos(mid), 0, math.sin(mid))
		order += 1
		block(model, order, Vector3.new(2.2, 1.9, 0.9), if i % 2 == 0 then flesh else fleshDark, CFrame.lookAt(midDir * 2.85 + Vector3.new(0, 3.95, 0), midDir * 9 + Vector3.new(0, 3.95, 0)))
	end
	-- Los tres ojos, medio hundidos en la panza
	for _, spot in { { -0.24, 1.6 }, { 0.24, 1.6 }, { 0, 0.8 } } do
		local y = spot[2]
		local r = 3.75 * math.sqrt(1 - ((y - 2.2) / 2.2) ^ 2)
		order += 1
		ball(model, order, 0.8, eye, Vector3.new(math.cos(spot[1]) * r, y, math.sin(spot[1]) * r))
	end
	-- Pelos de la cáscara
	for _, angle in { 1.2, 2.5, 3.8, 5.1 } do
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local pos = dir * 3.8 + Vector3.new(0, 1.9, 0)
		order += 1
		block(model, order, Vector3.new(0.28, 0.28, 0.9), shellDark, CFrame.lookAt(pos, pos + dir + Vector3.new(0, 0.7, 0)))
	end
	return 4, 4.9
end

function BUILDERS.Sushi(model)
	local rice = rgb(246, 242, 232)
	local riceLight = rgb(255, 254, 250)
	local nori = rgb(34, 46, 42)
	local noriDark = rgb(24, 34, 32)
	disc(model, 1, 5.6, 3.3, rice, Vector3.new(0, 1.65, 0))
	-- Relleno: salmón y aguacate asomando por arriba
	block(model, 2, Vector3.new(1.3, 0.5, 1.7), rgb(255, 140, 104), CFrame.new(-0.45, 3.3, 0))
	block(model, 3, Vector3.new(0.9, 0.5, 1.5), rgb(150, 204, 92), CFrame.new(0.7, 3.3, 0))
	local order = 3
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		order += 1
		block(model, order, Vector3.new(1.75, 3.2, 0.5), if i % 2 == 0 then nori else noriDark, CFrame.lookAt(dir * 2.95 + Vector3.new(0, 1.6, 0), dir * 9 + Vector3.new(0, 1.6, 0)))
	end
	-- Corona de arroz apelmazado alrededor del relleno
	for i = 0, 7 do
		local angle = (i + 0.5) / 8 * math.pi * 2
		order += 1
		ball(model, order, 1.3, if i % 2 == 0 then riceLight else rice, Vector3.new(math.cos(angle) * 1.95, 3, math.sin(angle) * 1.95))
	end
	-- Granos sueltos encima
	for i = 0, 3 do
		local angle = (2 * i + 1.5) / 8 * math.pi * 2
		local pos = Vector3.new(math.cos(angle) * 2, 3.68, math.sin(angle) * 2)
		order += 1
		local grain = blob(model, order, Vector3.new(0.6, 0.3, 0.3), riceLight, pos)
		grain.CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 3), 0)
	end
	return 3.3, 3.8
end

function BUILDERS.Helado(model)
	local pink = rgb(255, 150, 184)
	local pinkDark = rgb(244, 126, 166)
	local pinkMelt = rgb(255, 184, 206)
	local mint = rgb(140, 226, 190)
	local mintDark = rgb(116, 208, 170)
	local mintMelt = rgb(178, 238, 214)
	local waffle = rgb(228, 172, 100)
	local waffleDark = rgb(208, 150, 82)

	-- Bola de fresa aplastada contra el suelo, la de menta al lado y los charcos de lo derretido
	blob(model, 1, Vector3.new(4.2, 3.2, 4.2), pink, Vector3.new(-0.8, 1.6, 0))
	blob(model, 2, Vector3.new(5.2, 1.3, 5.2), pinkDark, Vector3.new(-0.8, 0.65, 0))
	disc(model, 3, 6.4, 0.16, pinkMelt, Vector3.new(-0.5, 0.08, 0))
	blob(model, 4, Vector3.new(4, 1.1, 4), mintDark, Vector3.new(1.8, 0.55, 0.6))
	disc(model, 5, 4.2, 0.24, mintMelt, Vector3.new(2.2, 0.12, 0.9))
	blob(model, 6, Vector3.new(3.4, 2.8, 3.4), mint, Vector3.new(1.7, 1.4, 0.6))
	disc(model, 7, 2.6, 0.32, pinkMelt, Vector3.new(0.9, 0.16, -2.6))

	-- Cucurucho boca abajo, clavado en la bola de fresa y ladeado
	local cone = CFrame.new(-1.1, 2, 0) * CFrame.Angles(0, 0, math.rad(37))
	local upright = CFrame.Angles(0, 0, math.rad(90))
	rod(model, 8, 3.1, 0.4, waffleDark, cone * CFrame.new(0, 0.1, 0) * upright)
	local order = 8
	for k = 1, 6 do
		order += 1
		rod(model, order, 3.1 - k * 0.4, 0.66, if k % 2 == 0 then waffleDark else waffle, cone * CFrame.new(0, 0.6 * (k - 0.5), 0) * upright)
	end

	-- Salpicaduras
	for i, spot in { Vector3.new(-3.3, 0.2, 2.3), Vector3.new(-2.6, 0.2, -2.9), Vector3.new(3.4, 0.2, -1.9) } do
		order += 1
		blob(model, order, Vector3.new(0.9, 0.4, 0.9), if i == 3 then mint else pink, spot)
	end
	return 4.5, 5.1
end

function BUILDERS.Sandia(model)
	local red = rgb(240, 62, 74)
	local redDark = rgb(226, 48, 62)
	local white = rgb(244, 248, 226)
	local green = rgb(64, 160, 72)
	local greenDark = rgb(44, 128, 58)
	local apex = Vector3.new(0, 7.95, 0)
	local half = math.rad(12)
	local reach = 6.7 -- hasta dónde llega la pulpa desde la punta
	local thick = 3

	-- Cuatro gajos en abanico desde la punta, cada uno con su trozo de corteza.
	-- Primero los dos centrales (el corazón) y luego los de los lados.
	local order = 0
	for _, turn in { -1, 1, -3, 3 } do
		local angle = turn * half
		local down = Vector3.new(math.sin(angle), -math.cos(angle), 0)
		local side = Vector3.new(math.cos(angle), math.sin(angle), 0)
		local tilt = CFrame.Angles(0, 0, angle)
		local foot = apex + down * (reach * math.cos(half))
		local spread = side * (reach * math.sin(half))
		local alt = ((turn + 3) / 2) % 2 == 0
		local tone = if alt then redDark else red
		order += 1
		triangle(model, order, thick, tone, foot, apex, foot - spread)
		order += 1
		block(model, order, Vector3.new(3.3, 0.8, thick + (if alt then 0.5 else 0.4)), if alt then greenDark else green, CFrame.new(apex + down * 7.35) * tilt)
		order += 1
		block(model, order, Vector3.new(3, 0.5, thick + 0.2), white, CFrame.new(apex + down * 6.75) * tilt)
		order += 1
		triangle(model, order, thick, tone, foot, apex, foot + spread)
	end
	-- Pepitas en las dos caras
	for _, spot in { { 3, -14 }, { 3.2, 16 }, { 5.1, -30 }, { 5.3, 0 }, { 5.1, 30 } } do
		local angle = math.rad(spot[2])
		local center = apex + Vector3.new(math.sin(angle), -math.cos(angle), 0) * spot[1]
		for _, face in { -1, 1 } do
			order += 1
			local pip = blob(model, order, Vector3.new(0.4, 0.65, 0.3), rgb(36, 28, 30), center)
			pip.CFrame = CFrame.new(center + Vector3.new(0, 0, face * thick / 2)) * CFrame.Angles(0, 0, angle)
		end
	end
	return 6.2, 8
end

function BUILDERS.Donut(model)
	local dough = rgb(226, 168, 100)
	local doughDark = rgb(210, 150, 84)
	local icing = rgb(255, 138, 190)
	local icingDark = rgb(246, 116, 174)
	local sprinkles = { rgb(255, 222, 70), rgb(96, 200, 255), rgb(255, 255, 255), rgb(140, 226, 120) }
	local ring = 3.3 -- radio del centro de la masa

	-- Diez tramos de masa, cada uno con su glaseado encima: cada mordida se lleva un trozo del aro.
	-- El glaseado alterna dos alturas para que el borde quede ondulado.
	local order = 0
	for i = 0, 9 do
		local angle = i / 10 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local even = i % 2 == 0
		local lift = if even then 1.48 else 1.56
		order += 1
		rod(model, order, 2.3, 2.9, if even then dough else doughDark, CFrame.lookAt(dir * ring + Vector3.new(0, 1.15, 0), dir * 9 + Vector3.new(0, 1.15, 0)))
		order += 1
		rod(model, order, if even then 2.25 else 2.12, 2.9, if even then icing else icingDark, CFrame.lookAt(dir * ring + Vector3.new(0, lift, 0), dir * 9 + Vector3.new(0, lift, 0)))
	end
	-- Fideos de colores apoyados en el glaseado
	local count = 0
	for i = 0, 9 do
		if i % 5 ~= 2 then
			local even = i % 2 == 0
			local lift = if even then 1.48 else 1.56
			local r = if even then 1.125 else 1.06
			local angle = i / 10 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local off = rng:NextNumber(-0.5, 0.5)
			local pos = Vector3.new(math.cos(angle) * (ring + off), lift + math.sqrt(r * r - off * off) + 0.04, math.sin(angle) * (ring + off))
			count += 1
			order += 1
			block(model, order, Vector3.new(0.6, 0.18, 0.18), sprinkles[count % 4 + 1], CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 3), 0))
		end
	end
	return 4.7, 2.7
end

function BUILDERS.Cupcake(model)
	local cake = rgb(236, 190, 122)
	local cakeDark = rgb(222, 172, 104)
	local paper = rgb(96, 190, 232)
	local paperDark = rgb(66, 160, 212)
	local icing = rgb(255, 158, 198)
	local icingDark = rgb(246, 134, 180)
	disc(model, 1, 5.4, 3.3, cake, Vector3.new(0, 1.75, 0))
	disc(model, 2, 7.6, 0.8, cakeDark, Vector3.new(0, 3.5, 0))
	-- Papel plisado: tablillas inclinadas hacia fuera, una sí y una no más metida
	local order = 2
	local lean = math.atan(0.9 / 3.2)
	for i = 0, 11 do
		local angle = i / 12 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local even = i % 2 == 0
		local pos = dir * (if even then 3.4 else 3.25) + Vector3.new(0, 1.7, 0)
		order += 1
		block(model, order, Vector3.new(2.25, 3.32, 0.5), if even then paper else paperDark, CFrame.lookAt(pos, pos + dir) * CFrame.Angles(-lean, 0, 0))
	end
	-- Tres pisos de crema, cada uno más pequeño y girado respecto al de abajo
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		order += 1
		blob(model, order, Vector3.new(4.3, 1.8, 4.3), if i % 2 == 0 then icing else icingDark, Vector3.new(math.cos(angle) * 2.1, 4.3, math.sin(angle) * 2.1))
	end
	for i = 0, 3 do
		local angle = (i + 0.5) / 4 * math.pi * 2
		order += 1
		blob(model, order, Vector3.new(3.3, 1.6, 3.3), if i % 2 == 0 then icingDark else icing, Vector3.new(math.cos(angle) * 1.35, 5.35, math.sin(angle) * 1.35))
	end
	order += 1
	blob(model, order, Vector3.new(3, 1.3, 3), icing, Vector3.new(0, 6.2, 0))
	-- Guinda con su rabito
	order += 1
	ball(model, order, 1.4, rgb(214, 30, 52), Vector3.new(0, 7.3, 0))
	order += 1
	block(model, order, Vector3.new(0.14, 0.8, 0.14), rgb(96, 62, 38), CFrame.new(0.12, 8.25, 0) * CFrame.Angles(0, 0, math.rad(-14)))
	return 4.3, 8.6
end

function BUILDERS.Chocolate(model)
	local choc = rgb(124, 76, 48)
	local chocDark = rgb(108, 64, 40)
	local slab = rgb(92, 54, 34)
	local pitch = 1.65
	-- Tableta de 4x6 onzas sobre tres tramos de base. El tramo envuelto es el corazón;
	-- se come desde el extremo libre hacia el envoltorio.
	local order = 0
	for strip = 0, 2 do
		local stripZ = (1 - strip) * pitch * 2
		order += 1
		block(model, order, Vector3.new(pitch * 4, 0.6, pitch * 2), slab, CFrame.new(0, 0.3, stripZ))
		for row = 0, 1 do
			for col = 0, 3 do
				order += 1
				block(model, order, Vector3.new(1.4, 0.5, 1.4), if (row + col) % 2 == 0 then choc else chocDark, CFrame.new((col - 1.5) * pitch, 0.8, stripZ + (0.5 - row) * pitch))
			end
		end
		if strip == 0 then
			-- Papel de plata, envoltorio rojo y franja de la etiqueta tapando ese extremo
			order += 1
			block(model, order, Vector3.new(6.9, 1.25, 3.8), rgb(206, 210, 218), CFrame.new(0, 0.625, 3.15))
			order += 1
			block(model, order, Vector3.new(7.1, 1.45, 3.05), rgb(214, 40, 48), CFrame.new(0, 0.725, 3.575))
			order += 1
			block(model, order, Vector3.new(7.2, 1.52, 1.1), rgb(255, 232, 150), CFrame.new(0, 0.76, 3.7))
		end
	end
	return 6.2, 1.5
end

function BUILDERS.Queso(model)
	local cheese = rgb(255, 210, 66)
	local cheeseDark = rgb(250, 198, 50)
	local hole = rgb(228, 160, 30)
	local rind = rgb(240, 132, 38)
	local rindDark = rgb(226, 116, 28)
	local tipZ, midZ, backZ = -5.6, -0.7, 4.2
	local wide, narrow = 4, 2 -- media anchura atrás y a mitad de la cuña

	-- Tres pisos; cada uno es un bloque central, dos cuñas a los lados, la corteza y dos cuñas de punta
	local order = 0
	for layer = 0, 2 do
		local y = 1 + layer * 2
		local a = if layer % 2 == 0 then cheese else cheeseDark
		local b = if layer % 2 == 0 then cheeseDark else cheese
		order += 1
		block(model, order, Vector3.new(narrow * 2, 2, backZ - midZ), a, CFrame.new(0, y, (midZ + backZ) / 2))
		for _, side in { -1, 1 } do
			order += 1
			triangle(model, order, 2, b, Vector3.new(side * narrow, y, backZ), Vector3.new(side * narrow, y, midZ), Vector3.new(side * wide, y, backZ))
		end
		order += 1
		block(model, order, Vector3.new(wide * 2 + 0.3, 2, 0.5), if layer % 2 == 0 then rind else rindDark, CFrame.new(0, y, backZ + 0.25))
		for _, side in { -1, 1 } do
			order += 1
			triangle(model, order, 2, a, Vector3.new(0, y, midZ), Vector3.new(0, y, tipZ), Vector3.new(side * narrow, y, midZ))
		end
	end

	-- Agujeros: dos arriba y tres en cada cara inclinada (posición a lo largo de la cara, altura, diámetro)
	for _, spot in { { 0.8, 1.5, 1.6 }, { -0.9, -1.4, 1.1 } } do
		order += 1
		blob(model, order, Vector3.new(spot[3], 0.24, spot[3]), hole, Vector3.new(spot[1], 6, spot[2]))
	end
	local dents = {
		[-1] = { { 0.4, 3.8, 1.3 }, { 0.65, 1.7, 1.7 }, { 0.85, 4.4, 1.2 } },
		[1] = { { 0.45, 1.6, 1.5 }, { 0.7, 4, 1.9 }, { 0.86, 1.9, 1.1 } },
	}
	for _, side in { -1, 1 } do
		local along = Vector3.new(side * wide, 0, backZ - tipZ)
		local normal = Vector3.new(side * (backZ - tipZ), 0, -wide).Unit
		for _, spot in dents[side] do
			local pos = Vector3.new(0, spot[2], tipZ) + along * spot[1]
			order += 1
			local dent = blob(model, order, Vector3.new(spot[3], spot[3], 0.24), hole, pos)
			dent.CFrame = CFrame.lookAt(pos, pos + normal)
		end
	end
	return 6.3, 6.1
end

function BUILDERS.Hamburguesa(model)
	local bun = rgb(234, 164, 78)
	local bunDark = rgb(222, 148, 64)
	local order = 0

	-- Cada capa redonda es un trébol de cuatro discos solapados: cada mordida se lleva un lóbulo.
	-- Los impares son un pelín más bajos para que las tapas no coincidan en el mismo plano.
	local function clover(diameter, offset, bottom, top, turn, colors)
		for i = 0, 3 do
			local angle = turn + i / 4 * math.pi * 2
			local trim = if i % 2 == 0 then 0 else 0.12
			order += 1
			disc(model, order, diameter, top - bottom - trim, colors[i % 2 + 1], Vector3.new(math.cos(angle) * offset, (bottom + top) / 2, math.sin(angle) * offset))
		end
	end

	clover(10, 2, 0, 1.6, math.pi / 4, { bun, bunDark }) -- pan de abajo
	clover(9.6, 2, 1.5, 2.8, 0, { rgb(112, 64, 42), rgb(98, 54, 36) }) -- carne

	-- Loncha de queso: las esquinas asoman entre los lóbulos de la carne y cuelgan
	order += 1
	block(model, order, Vector3.new(8.5, 0.42, 8.5), rgb(255, 206, 60), CFrame.new(0, 2.96, 0))
	local droop = math.rad(40)
	for i = 0, 3 do
		local angle = math.pi / 4 + i / 4 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local side = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local fold = dir * 6 + Vector3.new(0, 2.96, 0)
		local corner = fold + dir * (1.9 * math.cos(droop)) - Vector3.new(0, 1.9 * math.sin(droop), 0)
		order += 1
		triangle(model, order, 0.36, rgb(250, 194, 46), corner, fold + side * 1.9, fold - side * 1.9)
	end

	clover(7, 3, 3.1, 3.8, math.pi / 4, { rgb(226, 60, 54), rgb(210, 48, 46) }) -- tomate

	-- Lechuga: cuatro hojas anchas, unas con el borde hacia arriba y otras caídas
	for i = 0, 3 do
		local angle = 0.35 + i / 4 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local pos = dir * 3.4 + Vector3.new(0, 4.1, 0)
		order += 1
		local leaf = blob(model, order, Vector3.new(8.8, 0.9, 7.4), if i % 2 == 0 then rgb(120, 200, 90) else rgb(104, 184, 78), pos)
		leaf.CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(math.rad(if i % 2 == 0 then 8 else -6), 0, 0)
	end

	-- Pan de arriba: una base y cuatro lóbulos que hacen la cúpula
	order += 1
	disc(model, order, 13.6, 2, bunDark, Vector3.new(0, 5.4, 0))
	for i = 0, 3 do
		local angle = math.pi / 4 + i / 4 * math.pi * 2
		order += 1
		blob(model, order, Vector3.new(9.8, 5, 9.8), if i % 2 == 0 then bun else bunDark, Vector3.new(math.cos(angle) * 1.9, 6.4, math.sin(angle) * 1.9))
	end
	-- Una semilla de sésamo sobre cada lóbulo
	for i = 0, 3 do
		local angle = math.pi / 4 + i / 4 * math.pi * 2
		local out = 1.2 + (i % 2) * 1.4
		local pos = Vector3.new(math.cos(angle) * (1.9 + out), 6.45 + 2.5 * math.sqrt(1 - (out / 4.9) ^ 2), math.sin(angle) * (1.9 + out))
		order += 1
		local seed = blob(model, order, Vector3.new(0.95, 0.36, 0.55), rgb(252, 238, 200), pos)
		seed.CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 3), 0)
	end
	return 7.4, 9
end

function BUILDERS.Fresa(model)
	local red = rgb(236, 44, 60)
	local redDark = rgb(214, 32, 52)
	local seed = rgb(255, 226, 96)
	local leaf = rgb(86, 180, 70)
	local leafDark = rgb(66, 156, 60)
	-- Corazón de la punta a los hombros y un lóbulo que hace la punta
	blob(model, 1, Vector3.new(1.8, 3.8, 1.8), red, Vector3.new(0, 1.9, 0))
	blob(model, 2, Vector3.new(1.6, 1.8, 1.6), red, Vector3.new(0, 0.9, 0))
	local order = 2

	-- Anillo de lóbulos, cada uno con su pepita pegada a la piel
	local function ring(count, turn, offset, y, size, tilts)
		for i = 0, count - 1 do
			local angle = turn + i / count * math.pi * 2
			local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local center = dir * offset + Vector3.new(0, y, 0)
			order += 1
			blob(model, order, size, if i % 2 == 0 then red else redDark, center)
			local tilt = tilts[i % 2 + 1]
			local out = dir * math.cos(tilt) + Vector3.new(0, math.sin(tilt), 0)
			local pos = center + out * (size / 2)
			order += 1
			local pip = blob(model, order, Vector3.new(0.3, 0.46, 0.2), seed, pos)
			pip.CFrame = CFrame.lookAt(pos, pos + out)
		end
	end
	ring(4, math.pi / 4, 0.65, 1.7, Vector3.new(2.2, 2.2, 2.2), { -0.45, -0.12 }) -- cintura
	ring(5, 0, 1.15, 2.75, Vector3.new(2.6, 2.5, 2.6), { -0.35, 0.15 }) -- hombros

	-- Corona: cinco hojas caídas sobre los hombros y el rabito
	order += 1
	blob(model, order, Vector3.new(1.5, 0.6, 1.5), leafDark, Vector3.new(0, 4.1, 0))
	for i = 0, 4 do
		local angle = i / 5 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local pos = dir * 1.05 + Vector3.new(0, 4.08, 0)
		order += 1
		local sepal = blob(model, order, Vector3.new(1, 0.3, 1.9), if i % 2 == 0 then leaf else leafDark, pos)
		sepal.CFrame = CFrame.lookAt(pos, pos + dir + Vector3.new(0, -0.3, 0))
	end
	order += 1
	block(model, order, Vector3.new(0.34, 0.5, 0.34), leafDark, CFrame.new(0.05, 4.4, 0) * CFrame.Angles(0, 0, math.rad(-12)))
	return 2.5, 4.7
end

function BUILDERS.Tomate(model)
	local red = rgb(232, 52, 44)
	local redDark = rgb(212, 40, 40)
	local leaf = rgb(76, 170, 66)
	local leafDark = rgb(58, 146, 58)
	blob(model, 1, Vector3.new(3.4, 4.2, 3.4), red, Vector3.new(0, 2.1, 0))
	-- Seis gajos achatados alrededor del corazón
	local order = 1
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		order += 1
		blob(model, order, Vector3.new(3.6, 4.4, 3.6), if i % 2 == 0 then red else redDark, Vector3.new(math.cos(angle) * 1.35, 2.2, math.sin(angle) * 1.35))
	end
	-- Cáliz en estrella y rabito
	order += 1
	disc(model, order, 1.4, 0.3, leafDark, Vector3.new(0, 4.35, 0))
	for i = 0, 4 do
		local angle = (i + 0.5) / 5 * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local pos = dir * 1.05 + Vector3.new(0, 4.5, 0)
		order += 1
		local sepal = blob(model, order, Vector3.new(0.75, 0.26, 2), if i % 2 == 0 then leaf else leafDark, pos)
		sepal.CFrame = CFrame.lookAt(pos, pos + dir + Vector3.new(0, -0.32, 0))
	end
	order += 1
	block(model, order, Vector3.new(0.4, 0.7, 0.4), leafDark, CFrame.new(0.06, 4.8, 0) * CFrame.Angles(0, 0, math.rad(-14)))
	-- Brillo pegado a la piel del primer gajo
	order += 1
	local shinePos = Vector3.new(2.71, 3.37, 0.68)
	local shine = blob(model, order, Vector3.new(1, 0.55, 0.26), rgb(255, 150, 140), shinePos)
	shine.CFrame = CFrame.lookAt(shinePos, shinePos + Vector3.new(0.22, 0.126, 0.11))
	return 3.2, 5.2
end

function BUILDERS.Zanahoria(model)
	local orange = rgb(255, 140, 36)
	local orangeDark = rgb(244, 122, 24)
	local groove = rgb(214, 100, 18)
	local leaf = rgb(92, 190, 72)
	local leafDark = rgb(70, 164, 62)
	local widths = { 2.2, 2.15, 2, 1.8, 1.55, 1.25, 0.95, 0.6 } -- del extremo gordo a la punta

	-- Tumbada a lo largo de X: el tramo gordo es el corazón y se come desde la punta
	rod(model, 1, widths[1], 0.84, orange, CFrame.new(1.6, widths[1] / 2, 0))
	blob(model, 2, Vector3.new(0.9, 2.1, 2.1), orangeDark, Vector3.new(2.05, 1.1, 0))
	local order = 2
	for k = 2, #widths do
		local d = widths[k]
		order += 1
		rod(model, order, d, 0.84, if k % 2 == 1 then orange else orangeDark, CFrame.new(2.4 - k * 0.8, d / 2, 0))
	end
	-- Arrugas en el lomo
	for _, mark in { { 2, 0.25 }, { 4, -0.2 }, { 6, 0.1 } } do
		local d = widths[mark[1]]
		order += 1
		blob(model, order, Vector3.new(0.16, 0.14, d * 0.45), groove, Vector3.new(2.5 - mark[1] * 0.8, d - 0.04, mark[2]))
	end
	-- Penacho: un tallo corto y cinco hojas en abanico (giro, inclinación, largo)
	order += 1
	rod(model, order, 1, 0.5, leafDark, CFrame.new(2.6, 1.1, 0))
	for i, frond in { { 0, 10, 1.9 }, { 30, 45, 2 }, { -30, 38, 1.8 }, { 55, 5, 1.5 }, { -55, -12, 1.5 } } do
		order += 1
		local part = blob(model, order, Vector3.new(frond[3], 0.44, 0.8), if i % 2 == 1 then leaf else leafDark, Vector3.zero)
		part.CFrame = CFrame.new(2.7, 1.1, 0) * CFrame.Angles(0, math.rad(frond[1]), math.rad(frond[2])) * CFrame.new(frond[3] / 2 - 0.15, 0, 0)
	end
	return 4.5, 2.4
end

function BUILDERS.Uvas(model)
	local purple = rgb(136, 62, 190)
	local purpleDark = rgb(116, 48, 170)
	local brown = rgb(112, 74, 44)
	local floors = { 0, 2.1, 3.1 }
	-- Racimo tumbado: ancho junto al rabo (+X) y en punta hacia -X. Cada uva: x, piso, z
	local spots = {
		{ 0.3, 1, 0 }, { 1.7, 1, 0 }, { 0.3, 1, -1.5 }, { 0.3, 1, 1.5 }, { 1.7, 1, -1.5 }, { 1.7, 1, 1.5 },
		{ -1.1, 1, -0.75 }, { -1.1, 1, 0.75 }, { -2.4, 1, 0 },
		{ 1.1, 2, -0.8 }, { 1.1, 2, 0.8 }, { -0.3, 2, -0.8 }, { -0.3, 2, 0.8 }, { -1.6, 2, 0 },
		{ 0.5, 3, 0 },
	}
	local centers = {}
	for i, spot in spots do
		local d = 1.75 + rng:NextNumber(0, 0.15)
		local pos = Vector3.new(spot[1], if spot[2] == 1 then d / 2 else floors[spot[2]], spot[3])
		centers[i] = pos
		ball(model, i, d, if i % 2 == 1 then purple else purpleDark, pos)
	end
	local order = #spots
	-- Rabo con su travesaño y una hoja
	order += 1
	rod(model, order, 0.45, 1.75, brown, CFrame.new(2.3, 2.7, 0) * CFrame.Angles(0, 0, math.rad(35)))
	order += 1
	rod(model, order, 0.45, 0.9, brown, CFrame.new(3, 3.2, 0) * CFrame.Angles(0, 0, math.rad(125)))
	order += 1
	local leaf = blob(model, order, Vector3.new(2, 0.24, 1.5), rgb(96, 190, 84), Vector3.zero)
	leaf.CFrame = CFrame.new(1.7, 3, -1) * CFrame.Angles(math.rad(-18), math.rad(25), math.rad(-10))
	-- Brillos en las uvas de arriba
	for _, index in { 15, 14, 11 } do
		order += 1
		ball(model, order, 0.42, rgb(204, 160, 246), centers[index] + Vector3.new(-0.34, 0.62, 0.42))
	end
	return 3.4, 4
end

function BUILDERS.Patatas(model)
	local fry = rgb(255, 214, 80)
	local fryDark = rgb(248, 196, 58)
	local red = rgb(228, 44, 50)
	local redDark = rgb(204, 32, 44)
	local low, high, top = 1.6, 2.4, 3.4 -- media anchura del cartón abajo y arriba, y su altura

	-- El corazón es el taco de patatas de dentro; el cartón lo envuelve
	block(model, 1, Vector3.new(3, 4, 1.4), fry, CFrame.new(0, 2, 0))
	block(model, 2, Vector3.new(4.3, 0.5, 1.5), fryDark, CFrame.new(0, 3.6, 0))
	block(model, 3, Vector3.new(low * 2, top, 2), red, CFrame.new(0, top / 2, 0))
	for i, side in { -1, 1 } do
		triangle(model, 3 + i, 2, redDark, Vector3.new(side * low, top, 0), Vector3.new(side * low, 0, 0), Vector3.new(side * high, top, 0))
	end
	-- Solapa trasera redondeada y el sello de delante
	rod(model, 6, 4.2, 0.38, redDark, CFrame.new(0, 2.6, -0.79) * CFrame.Angles(0, math.rad(90), 0))
	rod(model, 7, 1.4, 0.14, fry, CFrame.new(0, 1.9, 1) * CFrame.Angles(0, math.rad(90), 0))

	-- Doce patatas en dos filas: las de atrás más largas, todas abiertas en abanico
	local order = 7
	for i = 0, 11 do
		local rear = i % 2 == 0
		local slot = math.floor(i / 2)
		local x = if rear then -1.5 + slot * 0.6 else -1.65 + slot * 0.66
		local z = if rear then -0.3 else 0.36
		local length = if rear then 3.7 + rng:NextNumber(0, 0.6) else 3 + rng:NextNumber(0, 0.5)
		local lean = -(x / 1.65) * math.rad(15) + rng:NextNumber(-0.05, 0.05)
		local nod = if rear then rng:NextNumber(-0.03, 0.03) else math.rad(6) + rng:NextNumber(-0.04, 0.04)
		order += 1
		block(model, order, Vector3.new(0.5, length, 0.5), if slot % 2 == 0 then fry else fryDark, CFrame.new(x, 2.6, z) * CFrame.Angles(nod, 0, lean) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0) * CFrame.new(0, length / 2, 0))
	end
	return 3.2, 7
end

function BUILDERS.Huevo(model)
	local white = rgb(252, 250, 244)
	local whiteDark = rgb(238, 236, 228)
	-- La clara del centro, la yema encima y su brillo son lo último: se come de fuera hacia dentro
	blob(model, 1, Vector3.new(5.6, 1.1, 5.2), white, Vector3.new(0.2, 0.55, -0.1))
	blob(model, 2, Vector3.new(2.8, 1.3, 2.8), rgb(255, 196, 40), Vector3.new(0.5, 0.95, -0.3))
	local shine = blob(model, 3, Vector3.new(0.8, 0.14, 0.45), rgb(255, 240, 170), Vector3.zero)
	shine.CFrame = CFrame.new(0.155, 1.56, 0) * CFrame.Angles(0, math.rad(35), 0)
	-- Borde irregular de clara: ángulo, distancia, largo, ancho y alto de cada lóbulo
	local lobes = {
		{ 8, 2.7, 4.4, 3.6, 0.8 }, { 50, 2.3, 3.6, 3.4, 0.66 }, { 92, 2.9, 4, 3.4, 0.84 },
		{ 135, 2.2, 3.4, 3.8, 0.7 }, { 172, 3, 4, 3.2, 0.8 }, { 215, 2.4, 3.6, 3.6, 0.68 },
		{ 255, 2.9, 4.2, 3.4, 0.86 }, { 298, 2.2, 3.4, 3.4, 0.7 }, { 335, 2.8, 3.8, 3.2, 0.78 },
	}
	for i, lobe in lobes do
		local angle = math.rad(lobe[1])
		local pos = Vector3.new(math.cos(angle) * lobe[2], lobe[5] / 2, math.sin(angle) * lobe[2])
		local part = blob(model, 3 + i, Vector3.new(lobe[3], lobe[5], lobe[4]), if i % 2 == 1 then whiteDark else white, pos)
		part.CFrame = CFrame.new(pos) * CFrame.Angles(0, -angle, 0)
	end
	return 5, 1.6
end

function BUILDERS.Yogur(model)
	local white = rgb(250, 248, 244)
	local whiteDark = rgb(236, 234, 228)
	local band = rgb(240, 84, 116)
	local bandDark = rgb(224, 64, 100)
	local pink = rgb(255, 176, 204)
	local pinkDark = rgb(250, 154, 188)
	local foil = rgb(206, 212, 222)
	-- Vaso que se abre hacia arriba, con su franja de color
	local order = 0
	for i, color in { white, whiteDark, band, bandDark, white } do
		order += 1
		disc(model, order, 3.8 + i * 0.4, 0.76, color, Vector3.new(0, (i - 0.5) * 0.76, 0))
	end
	order += 1
	disc(model, order, 6.3, 0.3, white, Vector3.new(0, 3.95, 0))
	-- Resto de la tapa pegado al borde y la tapa de aluminio levantada a un lado
	order += 1
	disc(model, order, 6, 0.1, foil, Vector3.new(0, 4.13, 0))
	order += 1
	rod(model, order, 2.4, 0.12, foil, CFrame.new(-3.2, 4.85, 0) * CFrame.Angles(0, 0, math.rad(15)))
	-- Espiral de yogur
	for i, swirl in { { 5.6, 1.3, 0, 4.25, 0 }, { 3.9, 1.1, 0.2, 4.8, 0.1 }, { 2.4, 0.95, -0.15, 5.25, -0.1 }, { 1, 0.8, 0.1, 5.62, 0.1 } } do
		order += 1
		blob(model, order, Vector3.new(swirl[1], swirl[2], swirl[1]), if i % 2 == 1 then pink else pinkDark, Vector3.new(swirl[3], swirl[4], swirl[5]))
	end
	-- Trozo de fresa hundido en el yogur, con dos pepitas y su hojita
	local berry = CFrame.new(1.7, 5.15, 0.9) * CFrame.Angles(math.rad(20), 0, math.rad(-25))
	order += 1
	blob(model, order, Vector3.new(1.3, 1.5, 1.1), rgb(232, 44, 60), Vector3.zero).CFrame = berry
	for _, spot in { Vector3.new(0.25, 0.1, 0.5), Vector3.new(-0.2, -0.2, 0.5) } do
		order += 1
		blob(model, order, Vector3.new(0.16, 0.24, 0.12), rgb(255, 226, 96), Vector3.zero).CFrame = berry * CFrame.new(spot)
	end
	order += 1
	blob(model, order, Vector3.new(0.9, 0.24, 0.9), rgb(86, 180, 70), Vector3.zero).CFrame = berry * CFrame.new(0, 0.72, 0)
	return 3.4, 6
end

function BUILDERS.Palomita(model)
	local cream = rgb(255, 246, 214)
	local creamDark = rgb(246, 232, 190)
	local hull = rgb(214, 160, 84)
	local order = 0
	local count = 0

	-- Una palomita: un grumo ladeado al azar y, en algunas, la cascarilla tostada asomando
	local function kernel(pos, out)
		count += 1
		order += 1
		local scale = 1 + rng:NextNumber(-0.06, 0.06)
		local puff = blob(model, order, Vector3.new(1.9, 1.5, 1.7) * scale, if count % 2 == 1 then cream else creamDark, pos)
		puff.CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4))
		if out then
			order += 1
			blob(model, order, Vector3.new(0.75, 0.55, 0.65), hull, pos + out * 0.62 + Vector3.new(0, 0.4, 0))
		end
	end

	-- Montón: una en el centro, siete alrededor, cinco encima y la de la cima
	kernel(Vector3.new(0, 0.9, 0), nil)
	for i = 0, 6 do
		local angle = i / 7 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		kernel(dir * (2.2 + rng:NextNumber(-0.1, 0.1)) + Vector3.new(0, 0.9, 0), if i % 2 == 0 then dir else nil)
	end
	for i = 0, 4 do
		local angle = (i + 0.5) / 5 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		kernel(dir * 1.3 + Vector3.new(0, 1.9, 0), if i % 2 == 1 then dir else nil)
	end
	kernel(Vector3.new(0.1, 2.75, 0), Vector3.new(0.6, 0, 0.6))
	return 3.3, 3.6
end

function BUILDERS.HotDog(model)
	local bun = rgb(238, 178, 96)
	local bunDark = rgb(226, 160, 78)
	local sausage = rgb(206, 84, 52)
	local sausageDark = rgb(190, 70, 44)
	local mustard = rgb(255, 214, 50)
	local mustardDark = rgb(250, 198, 34)
	local seg = 2.12 -- largo de cada tramo de salchicha

	-- Tumbado a lo largo de X. El corazón es la miga que une las dos mitades del pan, con el tramo
	-- central de salchicha encima; se come desde los dos extremos hacia el centro.
	block(model, 1, Vector3.new(2.8, 1.5, 1.4), bun, CFrame.new(0, 0.75, 0))
	rod(model, 2, 1.7, seg, sausage, CFrame.new(0, 2.3, 0))
	local order = 2
	for i, side in { -1, 1 } do
		order += 1
		rod(model, order, 2.5, 2.8, if i == 1 then bun else bunDark, CFrame.new(0, 1.25, side * 1.1))
	end
	for k = 1, 2 do
		for _, tip in { -1, 1 } do
			order += 1
			rod(model, order, 1.7, seg, if k == 1 then sausageDark else sausage, CFrame.new(tip * k * seg, 2.3, 0))
		end
		for _, tip in { -1, 1 } do
			for i, side in { -1, 1 } do
				local tone = if (k + i) % 2 == 0 then bunDark else bun
				order += 1
				if k == 1 then
					rod(model, order, 2.5, 2.8, tone, CFrame.new(tip * 2.8, 1.25, side * 1.1))
				else
					blob(model, order, Vector3.new(2.2, 2.5, 2.5), tone, Vector3.new(tip * 4.2, 1.25, side * 1.1))
				end
			end
		end
	end
	-- Puntas redondas de la salchicha, asomando del pan
	for _, tip in { -1, 1 } do
		order += 1
		ball(model, order, 1.7, sausageDark, Vector3.new(tip * 5.3, 2.3, 0))
	end
	-- Mostaza en zigzag
	local last = Vector3.new(-4.5, 3.2, -0.35)
	for i = 1, 9 do
		local point = Vector3.new(-4.5 + i, 3.2, if i % 2 == 0 then -0.35 else 0.35)
		local mid = (last + point) / 2
		order += 1
		local squirt = blob(model, order, Vector3.new(0.42, 0.36, 1.5), if i % 2 == 0 then mustardDark else mustard, mid)
		squirt.CFrame = CFrame.lookAt(mid, point)
		last = point
	end
	return 6.2, 3.4
end

function BUILDERS.Gominola(model)
	local green = rgb(72, 214, 96)
	local greenDark = rgb(54, 192, 82)
	local light = rgb(156, 240, 152)
	local ink = rgb(24, 74, 42)
	local back = 0.35 -- el osito mira hacia -Z; se retrasa un poco para centrar la huella

	local function jelly(part)
		part.Transparency = 0.15
		return part
	end

	-- Sentado: barriga, cabeza, patas hacia delante, brazos y orejas
	jelly(blob(model, 1, Vector3.new(4.4, 4.4, 3.8), green, Vector3.new(0, 2.2, back)))
	jelly(blob(model, 2, Vector3.new(3.6, 3, 3.2), green, Vector3.new(0, 5.3, back - 0.1)))
	local order = 2
	local feet = {}
	for i, side in { -1, 1 } do
		local at = CFrame.new(side * 1.3, 0.85, back - 1.9) * CFrame.Angles(0, -side * math.rad(15), 0)
		feet[i] = at * CFrame.new(0, 0, -1.1)
		order += 1
		jelly(blob(model, order, Vector3.new(1.7, 1.7, 2.4), greenDark, Vector3.zero)).CFrame = at
	end
	for _, side in { -1, 1 } do
		order += 1
		jelly(blob(model, order, Vector3.new(1.4, 1.3, 2), greenDark, Vector3.zero)).CFrame = CFrame.new(side * 2, 3.3, back - 0.9) * CFrame.Angles(math.rad(15), side * math.rad(18), 0)
	end
	for _, side in { -1, 1 } do
		order += 1
		jelly(ball(model, order, 1.2, green, Vector3.new(side * 1.35, 6.4, back)))
	end
	-- Hocico, tripa clara y almohadillas
	order += 1
	blob(model, order, Vector3.new(1.5, 1.1, 0.9), light, Vector3.new(0, 5, back - 1.65))
	order += 1
	blob(model, order, Vector3.new(2.4, 2.5, 0.7), light, Vector3.new(0, 2.4, back - 1.65))
	for i = 1, 2 do
		order += 1
		blob(model, order, Vector3.new(1.15, 1.15, 0.35), light, Vector3.zero).CFrame = feet[i]
	end
	-- Ojos, nariz y un brillo en la frente
	for _, side in { -1, 1 } do
		order += 1
		ball(model, order, 0.42, ink, Vector3.new(side * 0.65, 5.65, back - 1.55))
	end
	order += 1
	ball(model, order, 0.36, ink, Vector3.new(0, 5.25, back - 2.05))
	order += 1
	local shinePos = Vector3.new(-0.8, 6.26, back - 1.1)
	local shine = blob(model, order, Vector3.new(0.9, 0.5, 0.25), rgb(214, 255, 204), shinePos)
	shine.CFrame = CFrame.lookAt(shinePos, shinePos + Vector3.new(-0.154, 0.267, -0.242))
	return 3.3, 7
end

function BUILDERS.Pizza(model)
	local dough = rgb(236, 190, 120)
	local crust = rgb(218, 152, 78)
	local crustDark = rgb(202, 134, 64)
	local cheese = rgb(255, 204, 72)
	local cheeseDark = rgb(250, 188, 54)
	local pepperoni = rgb(206, 52, 44)
	local pepperoniDark = rgb(184, 40, 38)
	local tipZ, midZ, backZ = -7.4, -1, 5.4
	local wide, narrow = 4.6, 2.3 -- media anchura junto al borde y a mitad de la porción
	local top = 0.95 -- altura del queso

	-- Porción tumbada con la punta hacia -Z. El corazón es el centro; el borde es lo penúltimo
	-- (como quien se deja la corteza) y se come empezando por la punta.
	block(model, 1, Vector3.new(narrow * 2, top, backZ - midZ), cheese, CFrame.new(0, top / 2, (midZ + backZ) / 2))
	for i = -1, 1 do
		rod(model, 3 + i, 1.56, 3.2, if i == 0 then crust else crustDark, CFrame.new(i * 3.2, 0.78, backZ + 0.7))
	end
	-- Los lados y luego la punta: cada trozo es masa abajo y queso encima
	local order = 4
	for _, side in { -1, 1 } do
		order += 1
		triangle(model, order, 0.5, dough, Vector3.new(side * narrow, 0.25, backZ), Vector3.new(side * narrow, 0.25, midZ), Vector3.new(side * wide, 0.25, backZ))
		order += 1
		triangle(model, order, 0.45, cheeseDark, Vector3.new(side * narrow, 0.725, backZ), Vector3.new(side * narrow, 0.725, midZ), Vector3.new(side * wide, 0.725, backZ))
	end
	for _, side in { -1, 1 } do
		order += 1
		triangle(model, order, 0.5, dough, Vector3.new(0, 0.25, midZ), Vector3.new(0, 0.25, tipZ), Vector3.new(side * narrow, 0.25, midZ))
		order += 1
		triangle(model, order, 0.45, if side == -1 then cheeseDark else cheese, Vector3.new(0, 0.725, midZ), Vector3.new(0, 0.725, tipZ), Vector3.new(side * narrow, 0.725, midZ))
	end
	-- Queso que chorrea por la punta y por un lado, con su gota en el suelo
	order += 1
	blob(model, order, Vector3.new(1, 0.8, 1.3), cheese, Vector3.new(0, 0.5, tipZ + 0.3))
	order += 1
	local drip = blob(model, order, Vector3.new(1.2, 0.8, 1.5), cheeseDark, Vector3.zero)
	drip.CFrame = CFrame.new(-3.33, 0.5, 1.12) * CFrame.Angles(0, math.rad(-20), 0)
	order += 1
	blob(model, order, Vector3.new(0.8, 0.3, 0.8), cheese, Vector3.new(-4, 0.15, 0.8))
	-- Pepperoni y aceitunas
	for i, spot in { { 0.1, -3.9 }, { -1.3, -0.6 }, { 1.5, 0.9 }, { -2, 3.3 }, { 1.9, 3.9 } } do
		order += 1
		disc(model, order, 1.6, 0.24, if i % 2 == 1 then pepperoni else pepperoniDark, Vector3.new(spot[1], top + 0.09, spot[2]))
	end
	for _, spot in { { 0.2, -1.9 }, { -0.1, 1.8 }, { -3, 4.6 }, { 2.9, 2.4 } } do
		order += 1
		disc(model, order, 0.6, 0.3, rgb(44, 40, 52), Vector3.new(spot[1], top + 0.11, spot[2]))
	end
	return 8, 1.6
end

-- Comidas de las zonas nuevas: Barbacoa, Despensa, Cuarto de juguetes y Escritorio

-- Rod con el eje X tendido entre dos puntos
local function between(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
end

function BUILDERS.Mazorca(model)
	local corn = rgb(255, 206, 60)
	local cornLight = rgb(255, 226, 110)
	local char = rgb(110, 66, 34)
	local husk = rgb(206, 220, 128)
	local huskDark = rgb(176, 198, 100)
	local butter = rgb(255, 236, 150)
	local widths = { 2.6, 2.6, 2.5, 2.3, 1.9 } -- del centro a las puntas
	local seg = 1.15
	-- Tumbada a lo largo de X: el tramo central es el corazón; se come por los dos extremos
	rod(model, 1, widths[1], seg + 0.05, corn, CFrame.new(0, widths[1] / 2, 0))
	local order = 1
	for k = 1, 4 do
		local d = widths[k + 1]
		for _, side in { -1, 1 } do
			order += 1
			rod(model, order, d, seg, if k % 2 == 0 then corn else cornLight, CFrame.new(side * k * seg, d / 2, 0))
		end
	end
	-- Punta redonda, el tallo y las hojas abiertas hacia atrás
	order += 1
	ball(model, order, 1.7, cornLight, Vector3.new(-5.1, 0.95, 0))
	order += 1
	rod(model, order, 1.2, 0.9, rgb(196, 176, 110), CFrame.new(5.3, 1.1, 0))
	for i, side in { -1, 1 } do
		order += 1
		blob(model, order, Vector3.new(3.4, 0.35, 1.6), if i == 1 then husk else huskDark, Vector3.zero).CFrame = CFrame.new(6.4, 0.55, side * 0.95) * CFrame.Angles(side * 0.25, side * -0.35, math.rad(-6))
	end
	-- Granos en relieve por el lomo
	for i = 0, 7 do
		local x = -3.85 + i * 1.1
		local k = math.min(4, math.floor(math.abs(x) / seg + 0.5))
		order += 1
		ball(model, order, 0.75, cornLight, Vector3.new(x, widths[k + 1] - 0.2, if i % 2 == 0 then -0.45 else 0.45))
	end
	-- Franjas tostadas de la parrilla, en diagonal
	for _, x in { -3.4, -1.15, 1.15, 3.4 } do
		local k = math.min(4, math.floor(math.abs(x) / seg + 0.5))
		local d = widths[k + 1]
		order += 1
		rod(model, order, d + 0.08, 0.32, char, CFrame.new(x, d / 2, 0) * CFrame.Angles(0, 0.3, 0))
	end
	-- Un trozo de mantequilla derritiéndose encima
	order += 1
	block(model, order, Vector3.new(1.2, 0.45, 1), butter, CFrame.new(0.3, 2.75, 0.1) * CFrame.Angles(0.1, 0.4, 0.08))
	order += 1
	blob(model, order, Vector3.new(1.2, 0.9, 0.5), butter, Vector3.new(0.4, 2.1, -1.15))
	return 5.4, 2.8
end

function BUILDERS.Brocheta(model)
	local wood = rgb(214, 170, 110)
	local meat = rgb(156, 86, 50)
	local meatDark = rgb(136, 72, 40)
	local seared = rgb(92, 50, 30)
	local y = 1.3
	-- El palo es el corazón; los trozos del centro salen antes que los de las puntas
	rod(model, 1, 0.34, 12.6, wood, CFrame.new(0, y, 0))
	local order = 1
	local function chunk(kind: string, x: number)
		if kind == "meat" then
			order += 1
			blob(model, order, Vector3.new(1.45, 2.4, 2.3), if x < 0 then meatDark else meat, Vector3.new(x, y, 0))
			order += 1
			blob(model, order, Vector3.new(1.1, 0.35, 1.5), seared, Vector3.new(x, y + 1.08, 0))
		elseif kind == "onion" then
			order += 1
			rod(model, order, 2.3, 0.75, rgb(244, 226, 240), CFrame.new(x, y, 0))
			order += 1
			rod(model, order, 1.5, 0.8, rgb(196, 126, 190), CFrame.new(x, y, 0))
		elseif kind == "tomato" then
			order += 1
			ball(model, order, 2.2, rgb(236, 62, 50), Vector3.new(x, y + 0.02, 0))
			order += 1
			blob(model, order, Vector3.new(0.5, 0.28, 0.5), rgb(255, 160, 150), Vector3.new(x - 0.3, y + 0.75, -0.55))
		else
			order += 1
			blob(model, order, Vector3.new(0.85, 2.3, 2.4), if kind == "red" then rgb(232, 52, 44) else rgb(96, 184, 72), Vector3.new(x, y, 0))
		end
	end
	chunk("meat", 0)
	chunk("red", 1.35)
	chunk("green", -1.35)
	chunk("meat", 2.7)
	chunk("meat", -2.7)
	chunk("onion", 4.05)
	chunk("tomato", -4.05)
	-- Punta afilada, el remate del palo y unas hierbas por encima
	order += 1
	blob(model, order, Vector3.new(1.3, 0.3, 0.3), wood, Vector3.new(6.6, y, 0))
	order += 1
	ball(model, order, 0.6, rgb(190, 146, 90), Vector3.new(-6.35, y, 0))
	for _, spot in { { -2.85, 0.4 }, { 0.2, -0.45 }, { 2.55, 0.3 } } do
		order += 1
		blob(model, order, Vector3.new(0.4, 0.12, 0.26), rgb(60, 150, 60), Vector3.new(spot[1], y + 1.22, spot[2]))
	end
	return 5.6, 2.6
end

function BUILDERS.Costillas(model)
	local glaze = rgb(178, 64, 40)
	local glazeDark = rgb(156, 50, 32)
	local bone = rgb(252, 242, 222)
	local pitch = 1.9
	-- La base de carne es el corazón; encima, seis costillas glaseadas con su hueso asomando
	blob(model, 1, Vector3.new(11, 2, 4.8), rgb(150, 56, 36), Vector3.new(0, 1, 0))
	local order = 1
	local slots = { 3, 4, 2, 5, 1, 6 } -- primero las del centro: se come desde los extremos
	for _, i in slots do
		order += 1
		blob(model, order, Vector3.new(2.2, 2.6, 4.9), if i % 2 == 0 then glaze else glazeDark, Vector3.new((i - 3.5) * pitch, 1.4, 0))
	end
	for _, i in slots do
		local x = (i - 3.5) * pitch
		order += 1
		rod(model, order, 0.75, 1.6, bone, CFrame.new(x, 1.3, 2.9) * CFrame.Angles(0, math.rad(90), 0))
		order += 1
		blob(model, order, Vector3.new(1, 0.9, 0.8), bone, Vector3.new(x, 1.3, 3.75))
	end
	-- Marcas de la parrilla sobre tres costillas y salsa chorreando por delante
	for _, x in { -2.85, 0.95, 2.85 } do
		order += 1
		blob(model, order, Vector3.new(0.45, 0.16, 2.4), rgb(80, 34, 24), Vector3.zero).CFrame = CFrame.new(x, 2.62, 0) * CFrame.Angles(0, 0.5, 0)
	end
	for _, x in { -2.2, 2.9 } do
		order += 1
		blob(model, order, Vector3.new(0.7, 1.1, 0.45), glazeDark, Vector3.new(x, 1.5, -2.35))
		order += 1
		disc(model, order, 1.6, 0.25, glazeDark, Vector3.new(x + 0.3, 0.125, -3))
	end
	return 6.2, 2.8
end

function BUILDERS.Cereales(model)
	local honey = rgb(236, 172, 72)
	local honeyDark = rgb(216, 148, 54)
	local fruity = { rgb(255, 120, 150), rgb(255, 166, 60), rgb(140, 210, 90), rgb(120, 170, 255) }
	local flake = rgb(244, 196, 110)
	local milk = rgb(255, 252, 244)
	local order = 0
	local count = 0
	-- Una bolita de cereal; una de cada cuatro, de colores
	local function puff(pos: Vector3)
		count += 1
		order += 1
		local tone = if count % 4 == 0 then fruity[(count // 4 - 1) % #fruity + 1] elseif count % 2 == 0 then honeyDark else honey
		local d = 1.6 + rng:NextNumber(-0.1, 0.15)
		blob(model, order, Vector3.new(d, d * 0.9, d), tone, pos)
	end
	-- Montoncito: una en el centro, ocho alrededor, cinco encima y dos en la cima
	puff(Vector3.new(0, 0.75, 0))
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		puff(Vector3.new(math.cos(angle) * 1.7, 0.72, math.sin(angle) * 1.7))
	end
	for i = 0, 4 do
		local angle = (i + 0.5) / 5 * math.pi * 2
		puff(Vector3.new(math.cos(angle) * 0.95, 1.95, math.sin(angle) * 0.95))
	end
	puff(Vector3.new(0.3, 3, 0.1))
	puff(Vector3.new(-0.45, 2.9, -0.35))
	-- Copos tostados apoyados en el montón y alguno caído (x, y, z, inclinación)
	for i, spot in { { 2.9, 0.3, 0.4, 0.3 }, { -2.8, 0.35, -0.6, -0.4 }, { 0.9, 1.2, 2.4, 0.5 }, { -1, 1.3, -2.2, -0.5 }, { 3.4, 0.15, -1.9, 0 } } do
		order += 1
		blob(model, order, Vector3.new(1.9, 0.28, 1.5), if i % 2 == 0 then flake else honeyDark, Vector3.zero).CFrame = CFrame.new(spot[1], spot[2], spot[3]) * CFrame.Angles(spot[4], rng:NextNumber(0, 3), spot[4] * 0.5)
	end
	-- Unas gotas de leche
	order += 1
	disc(model, order, 2.2, 0.25, milk, Vector3.new(-2.6, 0.125, 2.1))
	order += 1
	disc(model, order, 1.1, 0.25, milk, Vector3.new(-1.4, 0.125, 2.9))
	return 3.4, 3.8
end

function BUILDERS.Pan(model)
	local crust = rgb(206, 140, 70)
	local crustDark = rgb(188, 122, 56)
	local crumb = rgb(252, 234, 190)
	local flour = rgb(255, 250, 240)
	local w, h = 4.4, 3 -- ancho y alto del cuerpo de cada rebanada
	-- Pan de molde en rebanadas a lo largo de X: cuerpo y copete redondo. La del medio es el
	-- corazón; se come desde las puntas
	local order = 0
	for _, k in { 0, 1, -1, 2, -2, 3, -3 } do
		local x = k * 1.02
		local tone = if k % 2 == 0 then crust else crustDark
		order += 1
		block(model, order, Vector3.new(1, h, w), tone, CFrame.new(x, h / 2, 0))
		order += 1
		rod(model, order, w + 0.3, 1, tone, CFrame.new(x, h, 0))
	end
	-- La cara cortada deja ver la miga
	order += 1
	block(model, order, Vector3.new(0.12, h - 0.5, w - 0.5), crumb, CFrame.new(3.58, h / 2 + 0.15, 0))
	order += 1
	rod(model, order, w - 0.3, 0.12, crumb, CFrame.new(3.58, h, 0))
	-- Una rebanada suelta, apoyada contra la cara cortada
	local slice = CFrame.new(4.4, 2.2, 0) * CFrame.Angles(0, 0, math.rad(18))
	order += 1
	block(model, order, Vector3.new(0.5, 4, 4.6), crust, slice)
	order += 1
	rod(model, order, 4.8, 0.5, crust, slice * CFrame.new(0, 2, 0))
	order += 1
	block(model, order, Vector3.new(0.56, 3.5, 4), crumb, slice * CFrame.new(0, 0.1, 0))
	order += 1
	rod(model, order, 4.2, 0.56, crumb, slice * CFrame.new(0, 2, 0))
	-- Harina sobre el copete y dos migas en el suelo
	for _, spot in { { 0, 0.5 }, { 2.04, -0.6 }, { -2.04, 0.3 } } do
		order += 1
		blob(model, order, Vector3.new(0.9, 0.12, 0.6), flour, Vector3.new(spot[1], h + (w + 0.3) / 2 - 0.08, spot[2]))
	end
	for _, spot in { { -4.4, 1.6 }, { 5.6, -2.2 } } do
		order += 1
		blob(model, order, Vector3.new(0.7, 0.5, 0.6), crumb, Vector3.new(spot[1], 0.25, spot[2]))
	end
	return 5.2, 5.4
end

function BUILDERS.Miel(model)
	local honey = rgb(255, 168, 28)
	local honeyLight = rgb(255, 196, 70)
	local glass = rgb(214, 238, 255)
	local wood = rgb(206, 146, 70)
	local ink = rgb(40, 32, 30)
	local function clear(part: BasePart)
		part.Transparency = 0.55
		part.CastShadow = false
	end
	-- La miel es el corazón; el tarro de cristal la envuelve
	disc(model, 1, 5.2, 5.2, honey, Vector3.new(0, 2.7, 0))
	blob(model, 2, Vector3.new(5, 1.3, 5), honeyLight, Vector3.new(0, 5.3, 0))
	clear(disc(model, 3, 5.8, 5.6, glass, Vector3.new(0, 2.8, 0)))
	clear(blob(model, 4, Vector3.new(5.8, 1.8, 5.8), glass, Vector3.new(0, 5.6, 0)))
	disc(model, 5, 4.4, 0.8, rgb(236, 246, 255), Vector3.new(0, 6.5, 0))
	disc(model, 6, 4.8, 0.8, rgb(250, 196, 56), Vector3.new(0, 7.1, 0))
	-- Tela de cuadros sobre la tapa, atada con un cordel
	blob(model, 7, Vector3.new(6.4, 0.8, 6.4), rgb(228, 58, 62), Vector3.new(0, 7.5, 0))
	local order = 7
	for _, spot in { { -1.1, -1.1 }, { 1.1, -1.1 }, { -1.1, 1.1 }, { 1.1, 1.1 }, { 0, 0 } } do
		order += 1
		block(model, order, Vector3.new(0.95, 0.14, 0.95), rgb(255, 250, 244), CFrame.new(spot[1], 7.84, spot[2]))
	end
	order += 1
	disc(model, order, 4.9, 0.3, rgb(250, 236, 206), Vector3.new(0, 6.95, 0))
	-- Etiqueta alrededor del tarro con una abeja delante (-Z)
	order += 1
	disc(model, order, 6, 2.4, rgb(255, 244, 214), Vector3.new(0, 3, 0))
	order += 1
	blob(model, order, Vector3.new(1.3, 1, 0.3), rgb(255, 210, 50), Vector3.new(0, 3.1, -3.02))
	for _, x in { -0.25, 0.25 } do
		order += 1
		blob(model, order, Vector3.new(0.22, 0.95, 0.34), ink, Vector3.new(x, 3.1, -3.04))
	end
	for _, x in { -0.35, 0.35 } do
		order += 1
		blob(model, order, Vector3.new(0.7, 0.5, 0.15), rgb(255, 255, 255), Vector3.new(x, 3.75, -3.05))
	end
	-- Un chorrito que cae por el cristal
	order += 1
	blob(model, order, Vector3.new(0.8, 1.8, 0.5), honey, Vector3.new(2.08, 5.3, -2.08))
	order += 1
	ball(model, order, 0.85, honey, Vector3.new(2.11, 4.45, -2.11))
	-- Cuchara de miel apoyada en el tarro, con su charquito
	local head = Vector3.new(3.9, 0.95, 1.7)
	local tip = Vector3.new(2.3, 6.4, 1)
	order += 1
	rod(model, order, 0.4, (tip - head).Magnitude, wood, between(head, tip))
	order += 1
	blob(model, order, Vector3.new(2, 1.4, 1.4), honeyLight, Vector3.zero).CFrame = CFrame.lookAt(head, tip) * CFrame.Angles(0, math.pi / 2, 0)
	for _, t in { -0.45, 0.45 } do
		order += 1
		rod(model, order, 1.5, 0.25, wood, CFrame.lookAt(head, tip) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(t, 0, 0))
	end
	order += 1
	disc(model, order, 2.6, 0.25, honey, Vector3.new(3.8, 0.125, 0.6))
	return 3.6, 8
end

function BUILDERS.Ganchitos(model)
	local orange = rgb(255, 146, 36)
	local orangeLight = rgb(255, 178, 74)
	local turn = CFrame.Angles(0, 0.3, 0)
	-- Un ganchito en la boca de la bolsa es el corazón
	blob(model, 1, Vector3.new(2.8, 1.15, 1.2), orange, Vector3.zero).CFrame = turn * CFrame.new(0.4, 0.95, -0.9) * CFrame.Angles(0, 0, 0.2)
	-- La bolsa tumbada detrás, abierta hacia +X, con su franja y el cierre plateado
	local bag = turn * CFrame.new(-2.2, 1.3, -1.2)
	blob(model, 2, Vector3.new(5, 2.6, 3.8), rgb(60, 116, 224), Vector3.zero).CFrame = bag
	blob(model, 3, Vector3.new(1.4, 2.72, 3.9), rgb(255, 214, 60), Vector3.zero).CFrame = bag * CFrame.new(-0.4, 0, 0)
	blob(model, 4, Vector3.new(0.8, 2.2, 3.5), rgb(206, 212, 222), Vector3.zero).CFrame = bag * CFrame.new(-2.5, 0, 0)
	blob(model, 5, Vector3.new(0.4, 1.9, 3), rgb(150, 70, 24), Vector3.zero).CFrame = bag * CFrame.new(2.4, 0.05, 0)
	-- Ganchitos desparramados por el suelo y alguno encima de otro
	local spots = {
		{ 1.6, 0.5, 0.4 }, { 2.4, 0.5, -1.4 }, { 3.2, 0.5, 0.9 }, { 1.4, 0.5, 2 }, { 3.6, 0.5, -0.4 },
		{ 2.4, 1.3, 0.3 }, { 0.2, 0.5, 1.1 }, { 4.2, 0.5, 1.9 }, { 1, 1.2, -0.6 }, { 2.9, 1.25, -0.9 },
		{ -0.6, 0.5, 2.6 }, { 4.6, 0.5, -1.6 }, { 0.9, 0.5, 3.4 }, { 2.6, 0.5, 2.9 },
	}
	local order = 5
	for i, spot in spots do
		order += 1
		local length = 2.3 + rng:NextNumber(-0.3, 0.4)
		blob(model, order, Vector3.new(length, 0.95, 1.05), if i % 2 == 0 then orangeLight else orange, Vector3.zero).CFrame = turn
			* CFrame.new(spot[1] - 0.6, spot[2], spot[3] - 0.9)
			* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
	end
	-- Polvo de queso por el suelo
	for _, spot in { { 2.2, 1.2 }, { 3.6, -1 }, { 0.4, 2.4 } } do
		order += 1
		disc(model, order, 0.9, 0.25, rgb(255, 196, 90), (turn * CFrame.new(spot[1] - 0.6, 0.125, spot[2] - 0.9)).Position)
	end
	return 4.8, 2.8
end

function BUILDERS.Zumo(model)
	local white = rgb(252, 250, 244)
	local orange = rgb(255, 140, 30)
	local green = rgb(90, 190, 80)
	local pink = rgb(255, 96, 140)
	-- El brick es el corazón (las cajas son cajas)
	block(model, 1, Vector3.new(4.2, 7.2, 2.8), white, CFrame.new(0, 3.6, 0))
	block(model, 2, Vector3.new(4.26, 4.4, 2.86), rgb(255, 226, 120), CFrame.new(0, 3.1, 0))
	block(model, 3, Vector3.new(4.26, 0.9, 2.86), green, CFrame.new(0, 6.25, 0))
	-- Naranja dibujada en la cara de delante (-Z), con brillo y hoja
	rod(model, 4, 2.7, 0.2, orange, CFrame.new(0, 3.3, -1.45) * CFrame.Angles(0, math.rad(90), 0))
	blob(model, 5, Vector3.new(0.7, 0.45, 0.12), rgb(255, 214, 160), Vector3.new(-0.55, 3.85, -1.57))
	blob(model, 6, Vector3.new(1.1, 0.55, 0.14), green, Vector3.zero).CFrame = CFrame.new(0.55, 4.75, -1.5) * CFrame.Angles(0, 0, 0.5)
	-- Solapas dobladas a los lados de la tapa
	for i, side in { -1, 1 } do
		block(model, 6 + i, Vector3.new(0.45, 1.1, 2.4), white, CFrame.new(side * 2.3, 6.7, 0) * CFrame.Angles(0, 0, side * -0.25))
	end
	-- Pajita doblada en su agujerito
	disc(model, 9, 0.8, 0.1, rgb(200, 206, 216), Vector3.new(1.1, 7.25, 0.5))
	disc(model, 10, 0.45, 3.4, rgb(255, 255, 255), Vector3.new(1.1, 8.9, 0.5))
	ball(model, 11, 0.55, pink, Vector3.new(1.1, 10.6, 0.5))
	rod(model, 12, 0.45, 1.6, pink, CFrame.new(1.75, 11, 0.5) * CFrame.Angles(0, 0, math.rad(32)))
	for i, y in { 8, 9.5 } do
		disc(model, 12 + i, 0.5, 0.25, pink, Vector3.new(1.1, y, 0.5))
	end
	-- Una gota y un charquito de zumo
	blob(model, 15, Vector3.new(0.4, 0.6, 0.35), orange, Vector3.new(-1.7, 1.2, -1.5))
	disc(model, 16, 1.8, 0.25, orange, Vector3.new(-2.7, 0.125, -1.3))
	return 3.2, 11.4
end

function BUILDERS.Sorpresa(model)
	local choc = rgb(122, 72, 44)
	local foil = rgb(252, 250, 246)
	local foilDark = rgb(236, 232, 226)
	local orange = rgb(255, 128, 40)
	-- El chocolate es el corazón; el papel de aluminio lo envuelve en seis gajos
	blob(model, 1, Vector3.new(4.8, 6.2, 4.8), choc, Vector3.new(0, 3.1, 0))
	local order = 1
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		order += 1
		blob(model, order, Vector3.new(4.4, 6.5, 4.4), if i % 2 == 0 then foil else foilDark, Vector3.new(math.cos(angle) * 0.75, 3.25, math.sin(angle) * 0.75))
	end
	-- Banda naranja con su raya roja
	order += 1
	disc(model, order, 6.05, 1.1, orange, Vector3.new(0, 3.1, 0))
	order += 1
	disc(model, order, 6.1, 0.3, rgb(226, 48, 50), Vector3.new(0, 3.1, 0))
	-- Retorcido del papel en la punta
	order += 1
	blob(model, order, Vector3.new(1.3, 0.9, 1.3), foil, Vector3.new(0, 6.55, 0))
	for _, side in { -1, 1 } do
		order += 1
		blob(model, order, Vector3.new(1.1, 0.35, 0.7), orange, Vector3.zero).CFrame = CFrame.new(side * 0.6, 6.95, 0) * CFrame.Angles(0, 0, side * 0.6)
	end
	-- Lunares pegados al papel, encima y debajo de la banda
	for i = 0, 5 do
		local angle = i / 6 * math.pi * 2
		local y = if i % 2 == 0 then 4.6 else 1.8
		local pos = Vector3.new(math.cos(angle) * 2.72, y, math.sin(angle) * 2.72)
		order += 1
		blob(model, order, Vector3.new(0.8, 0.8, 0.15), orange, pos).CFrame = CFrame.lookAt(pos, pos + Vector3.new(math.cos(angle), if y > 3 then 0.45 else -0.45, math.sin(angle)))
	end
	-- Un roto en el papel: asoma el chocolate y la esquina del papel se levanta
	local angle = math.rad(330)
	local pos = Vector3.new(math.cos(angle) * 2.46, 5.2, math.sin(angle) * 2.46)
	local out = Vector3.new(math.cos(angle), 0.6, math.sin(angle))
	order += 1
	blob(model, order, Vector3.new(1.5, 1.3, 0.3), choc, pos).CFrame = CFrame.lookAt(pos, pos + out)
	order += 1
	blob(model, order, Vector3.new(1.2, 0.8, 0.15), foil, Vector3.zero).CFrame = CFrame.lookAt(pos, pos + out) * CFrame.new(0.7, 0.5, -0.35) * CFrame.Angles(0.7, 0, 0.3)
	return 3.1, 7.2
end

function BUILDERS.Cruasan(model)
	local gold = rgb(232, 164, 70)
	local goldDark = rgb(212, 140, 52)
	local seam = rgb(176, 104, 40)
	local glaze = rgb(255, 214, 140)
	local arc = 3.8 -- radio de la media luna
	local depth = 1.5 -- adelanta el arco para dejarlo centrado en el origen
	local step = math.rad(25)
	local lengths = { 2.7, 2.5, 2.2, 1.9, 1.5 } -- del centro a las puntas
	local heights = { 3, 2.7, 2.3, 1.8, 1.3 }
	local widths = { 3.6, 3.3, 2.8, 2.2, 1.6 }
	local function at(angle: number, y: number): CFrame
		return CFrame.new(math.sin(angle) * arc, y, math.cos(angle) * arc - depth) * CFrame.Angles(0, angle, 0)
	end
	-- El rollo gordo del centro es el corazón; se come desde las puntas
	blob(model, 1, Vector3.new(lengths[1], heights[1], widths[1]), gold, Vector3.zero).CFrame = at(0, heights[1] / 2)
	local order = 1
	for k = 1, 4 do
		for _, side in { -1, 1 } do
			order += 1
			-- Las puntas se curvan un poco más hacia dentro
			local angle = side * (k * step + (if k == 4 then math.rad(6) else 0))
			blob(model, order, Vector3.new(lengths[k + 1], heights[k + 1], widths[k + 1]), if k % 2 == 0 then gold else goldDark, Vector3.zero).CFrame = at(angle, heights[k + 1] / 2)
		end
	end
	-- Pliegues oscuros entre rollo y rollo
	for k = 1, 3 do
		for _, side in { -1, 1 } do
			order += 1
			blob(model, order, Vector3.new(0.3, heights[k] * 0.92, widths[k] * 0.96), seam, Vector3.zero).CFrame = at(side * (k - 0.5) * step, heights[k] * 0.46)
		end
	end
	-- Brillo del huevo batido en lo alto
	for k, angle in { 0, -step, step } do
		local index = if k == 1 then 1 else 2
		order += 1
		blob(model, order, Vector3.new(lengths[index] * 0.55, 0.22, widths[index] * 0.35), glaze, Vector3.zero).CFrame = at(angle, heights[index] - 0.08)
	end
	-- Escamas de hojaldre caídas
	for _, spot in { { 0.8, 1.6 }, { -1.6, 2.2 }, { 2.4, -2.7 } } do
		order += 1
		blob(model, order, Vector3.new(0.7, 0.18, 0.5), goldDark, Vector3.new(spot[1], 0.09, spot[2]))
	end
	return 5.2, 3
end

function BUILDERS.Barrita(model)
	local oat = rgb(216, 170, 98)
	local oatDark = rgb(196, 148, 80)
	local wrap = rgb(70, 170, 90)
	local h, w = 1.6, 3
	-- Tumbada a lo largo de X. El tramo envuelto es el corazón; se come desde el extremo libre
	block(model, 1, Vector3.new(2.6, h, w), oat, CFrame.new(3.1, h / 2, 0))
	block(model, 2, Vector3.new(3, h + 0.5, w + 0.4), wrap, CFrame.new(3.3, h / 2 + 0.1, 0))
	block(model, 3, Vector3.new(0.7, h + 0.56, w + 0.46), rgb(255, 220, 70), CFrame.new(3.4, h / 2 + 0.1, 0))
	block(model, 4, Vector3.new(0.5, h + 0.2, w + 0.7), rgb(50, 140, 70), CFrame.new(5, h / 2 + 0.1, 0))
	-- Borde rasgado del envoltorio: picos girados 45 grados
	for i, z in { -1.1, 0, 1.1 } do
		block(model, 4 + i, Vector3.new(0.6, h + 0.5, 0.6), wrap, CFrame.new(1.85, h / 2 + 0.1, z) * CFrame.Angles(0, math.rad(45), 0))
	end
	-- Tres tramos de avena al aire, un lomo abombado y el extremo redondeado
	local order = 7
	for i, x in { 0.75, -1.45, -3.65 } do
		order += 1
		block(model, order, Vector3.new(2.2, h, w), if i % 2 == 0 then oatDark else oat, CFrame.new(x, h / 2, 0))
	end
	order += 1
	blob(model, order, Vector3.new(6.8, 0.7, w - 0.1), rgb(230, 188, 112), Vector3.new(-1.45, h, 0))
	order += 1
	blob(model, order, Vector3.new(0.9, h, w), oat, Vector3.new(-4.75, h / 2, 0))
	-- Tropezones sobre el lomo: copos de avena, almendras y pepitas de chocolate
	local toppings = {
		{ "oat", -4, 0.6 }, { "nut", -3.2, -0.7 }, { "chip", -2.6, 0.9 }, { "oat", -1.9, -0.2 }, { "chip", -1.2, -1 }, { "nut", -0.6, 0.6 },
		{ "oat", 0.2, -0.8 }, { "chip", 0.8, 0.3 }, { "oat", 1.2, 1 }, { "nut", -4.3, -0.9 }, { "chip", -3.3, 0.2 },
	}
	for _, t in toppings do
		local x, z = t[2], t[3]
		local lift = 0.35 * math.sqrt(math.max(0, 1 - ((x + 1.45) / 3.4) ^ 2 - (z / 1.45) ^ 2))
		local pos = Vector3.new(x, h + lift + 0.05, z)
		order += 1
		if t[1] == "oat" then
			blob(model, order, Vector3.new(0.8, 0.22, 0.55), rgb(246, 228, 180), Vector3.zero).CFrame = CFrame.new(pos) * CFrame.Angles(0.15, rng:NextNumber(0, 3), 0)
		elseif t[1] == "nut" then
			blob(model, order, Vector3.new(1, 0.45, 0.6), rgb(170, 104, 56), Vector3.zero).CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0)
		else
			ball(model, order, 0.5, rgb(74, 44, 30), pos + Vector3.new(0, 0.1, 0))
		end
	end
	return 5.2, 2.4
end

function BUILDERS.Nuez(model)
	local shell = { rgb(184, 132, 82), rgb(164, 114, 68), rgb(198, 148, 96) }
	local seam = rgb(130, 88, 50)
	local kernel = rgb(214, 160, 96)
	-- La pulpa de dentro es el corazón; la cáscara son dos mitades con su costura
	blob(model, 1, Vector3.new(3.6, 4.2, 4.6), kernel, Vector3.new(0, 2.5, 0))
	blob(model, 2, Vector3.new(3.8, 5, 5.8), shell[1], Vector3.new(-0.9, 2.55, 0))
	blob(model, 3, Vector3.new(3.8, 5, 5.8), shell[2], Vector3.new(0.9, 2.55, 0))
	blob(model, 4, Vector3.new(0.7, 5.3, 6.1), seam, Vector3.new(0, 2.6, 0))
	blob(model, 5, Vector3.new(0.6, 0.9, 0.6), seam, Vector3.new(0, 5.25, 0))
	-- Arrugas: bultos pegados a cada mitad (giro alrededor y altura sobre la superficie)
	local order = 5
	for _, side in { -1, 1 } do
		local center = Vector3.new(side * 0.9, 2.55, 0)
		local radii = Vector3.new(1.9, 2.5, 2.9)
		for _, spot in { { -0.9, 0.5 }, { -0.2, 0.75 }, { 0.6, 0.45 }, { -0.5, -0.35 }, { 0.3, -0.3 }, { 1, -0.1 } } do
			local t, e = spot[1], spot[2]
			local dir = Vector3.new(side * math.cos(e) * math.cos(t), math.sin(e), math.cos(e) * math.sin(t))
			local pos = center + dir * radii
			order += 1
			blob(model, order, Vector3.new(1.4, 1.5, 0.7), shell[order % 3 + 1], pos).CFrame = CFrame.lookAt(pos, pos + (dir / radii).Unit)
		end
	end
	-- En el suelo, un trozo de cáscara y dos de pulpa
	order += 1
	blob(model, order, Vector3.new(2.2, 0.9, 1.7), shell[2], Vector3.zero).CFrame = CFrame.new(3.7, 0.4, 1.4) * CFrame.Angles(0.3, 0.6, 0.2)
	order += 1
	blob(model, order, Vector3.new(1.3, 0.9, 1.1), kernel, Vector3.new(3.3, 0.45, -1.7))
	order += 1
	blob(model, order, Vector3.new(0.8, 0.5, 0.6), kernel, Vector3.new(4.2, 0.25, -0.8))
	return 4, 5.3
end

-- Devuelve el modelo listo para colocar con PivotTo. El pivote está en el centro, a ras de suelo.
function FoodModels.build(def): Model
	local model = Instance.new("Model")
	model.Name = def.id

	local radius, height = BUILDERS[def.id](model)

	local count = 0
	local sum = Vector3.zero
	for _, piece in model:GetChildren() do
		count += 1
		sum += piece.Position
	end

	-- Las comidas grandes estorban el paso: un colisionador invisible simple en vez de chocar con cada pieza
	if radius >= 2 then
		local collider = Instance.new("Part")
		collider.Name = "Collider"
		collider.Anchored = true
		collider.Transparency = 1
		collider.CanQuery = false
		collider.CanTouch = false
		collider.Shape = Enum.PartType.Cylinder
		collider.Size = Vector3.new(height, radius * 1.7, radius * 1.7)
		collider.CFrame = CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		collider.Parent = model
	end

	model.WorldPivot = CFrame.new()
	model:SetAttribute("FoodId", def.id)
	model:SetAttribute("Hp", def.hp)
	model:SetAttribute("MaxHp", def.hp)
	model:SetAttribute("Radius", radius)
	model:SetAttribute("Pieces", count)
	model:SetAttribute("Color", (model:FindFirstChild("Piece") :: Part).Color)
	return model
end

return FoodModels
