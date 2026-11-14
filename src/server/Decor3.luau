-- Decorado temático por zona (parte 3): Barbacoa, Despensa, Cuarto de juguetes y Escritorio.
-- Mismas reglas que Decor2: solo Parts de color plano y sin colisión; el contorno de tinta lo pone
-- quien llama con un Highlight en `parent`. En el centro del camino (|x| <= 50) solo hay detalles
-- planos de suelo, cada tipo a su altura para que no parpadeen; lo alto vive en las bandas
-- laterales, con un muro continuo a cada lado y seis hitos por zona. Determinista: semilla por tema.

local Decor3 = {}
Decor3.Themes = { Barbacoa = true, Despensa = true, Juguetes = true, Escritorio = true }

local PI = math.pi
local V3 = Vector3.new
local ANG = CFrame.Angles
local SEEDS = { Barbacoa = 4505, Despensa = 4606, Juguetes = 4707, Escritorio = 4808 }
local AXIS = { x = CFrame.identity, y = ANG(0, 0, PI / 2), z = ANG(0, PI / 2, 0) }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function part(parent: Instance, props): Part
	local p = if props.wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = props.shadow ~= false
	p.Size = props.size
	p.Color = props.color
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
local function disc(parent, diameter, height, color, position)
	return part(parent, { size = V3(height, diameter, diameter), color = color, cframe = CFrame.new(position) * ANG(0, 0, PI / 2), shape = Enum.PartType.Cylinder, shadow = false })
end

-- Marco local de un lateral: origen en el suelo, -Z mira al camino, +X corre a lo largo de la zona.
local function frame(c, side, d, t, yaw)
	return CFrame.new(c.cx + side * d, c.gy, c.z0 - t) * ANG(0, side * PI / 2 + (yaw or 0), 0)
end

local function put(m, f, x, y, z, size, color, rot, kind, noShadow)
	local shape = if kind == "cyl" then Enum.PartType.Cylinder elseif kind == "ball" then Enum.PartType.Ball else nil
	local cframe = f * CFrame.new(x, y, z) * (rot or CFrame.identity)
	return part(m, { size = size, color = color, cframe = cframe, blob = kind == "blob", wedge = kind == "wedge", shape = shape, shadow = not noShadow })
end

local function box(m, f, x, y, z, sx, sy, sz, color, rot, noShadow)
	return put(m, f, x, y, z, V3(sx, sy, sz), color, rot, nil, noShadow)
end

local function ball(m, f, x, y, z, sx, sy, sz, color, rot, noShadow)
	return put(m, f, x, y, z, V3(sx, sy, sz), color, rot, "blob", noShadow)
end

local function wedge(m, f, x, y, z, sx, sy, sz, color, rot, noShadow)
	return put(m, f, x, y, z, V3(sx, sy, sz), color, rot, "wedge", noShadow)
end

-- Cilindro con eje "y" (de pie), "x" (a lo largo del camino) o "z" (de cara al camino)
local function cyl(m, f, x, y, z, diameter, length, color, axis, noShadow)
	return put(m, f, x, y, z, V3(length, diameter, diameter), color, AXIS[axis or "y"], "cyl", noShadow)
end

-- Cilindro entre dos puntos locales
local function rod(m, f, a: Vector3, b: Vector3, diameter, color)
	local dir = b - a
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local cframe = f * CFrame.lookAt((a + b) / 2, b, up) * ANG(0, PI / 2, 0)
	return part(m, { size = V3(dir.Magnitude, diameter, diameter), color = color, shape = Enum.PartType.Cylinder, cframe = cframe })
end

-- Detalles planos de suelo: `top` es cuánto asoman sobre el suelo (máx. 0.12). Cada tipo de
-- detalle usa su propia altura, y los del mismo tipo van en celdas que no se pisan.
local function flat(c, x, t, sx, sz, color, top)
	return part(c.parent, { size = V3(sx, 0.2, sz), color = color, cframe = CFrame.new(c.cx + x, c.gy + top - 0.1, c.z0 - t), shadow = false })
end

local function spot(c, x, t, diameter, color, top)
	return disc(c.parent, diameter, 0.2, color, V3(c.cx + x, c.gy + top - 0.1, c.z0 - t))
end

local function neon(p: BasePart): BasePart
	p.Material = Enum.Material.Neon
	p.CastShadow = false
	return p
end

-- Recorre los huecos de ambos laterales: `marks[side][i]` es un hito único; si no hay, va `filler`.
local function slots(c, d, marks, filler)
	for _, side in { 1, -1 } do
		for i = 1, c.n do
			local f = frame(c, side, d, (i - 0.5) * c.step, c.rng:NextNumber(-0.1, 0.1))
			local build = marks[side][i] or filler
			build(f, side, i)
		end
	end
end

-- Celdas a lo largo de la zona: una por tramo de len / count, así los detalles no se pisan
local function cells(c, count: number, fn)
	for i = 1, count do
		fn((i - 0.5) * c.len / count, i)
	end
end

-- BARBACOA: patio de barro, obra de ladrillo con parrilla y brasas, chimeneas y humo
local function barbacoa(c)
	local m, r, W = c.parent, c.rng, c.half
	local brick, brickDark, mortar = rgb(196, 84, 60), rgb(168, 66, 48), rgb(226, 206, 184)
	local black, steel, wood = rgb(46, 42, 48), rgb(150, 156, 168), rgb(150, 100, 60)
	local coal = { rgb(255, 120, 30), rgb(255, 176, 50), rgb(240, 70, 30) }
	local white = rgb(250, 248, 244)

	-- Baldosas de barro: juntas a lo largo y a lo ancho, a dos alturas
	for x = -48, 48, 12 do
		flat(c, x, c.len / 2, 0.5, c.len, rgb(186, 108, 74), 0.04)
	end
	cells(c, math.floor(c.len / 12.5), function(t)
		flat(c, 0, t, 2 * W - 20, 0.5, rgb(186, 108, 74), 0.06)
	end)
	-- Manchas de carbón (con su centro más oscuro) y gotas de salsa
	cells(c, 8, function(t)
		local x, d = r:NextNumber(-40, 40), r:NextNumber(6, 10)
		spot(c, x, t, d, rgb(130, 86, 70), 0.08)
		spot(c, x + d * 0.15, t - d * 0.1, d * 0.5, rgb(80, 60, 56), 0.1)
	end)
	cells(c, 5, function(t)
		spot(c, r:NextNumber(-44, 44), t + r:NextNumber(-2, 2), r:NextNumber(2.5, 4), rgb(200, 40, 36), 0.12)
	end)

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 22, W + 14, c.len, 44, 4, brickDark, nil, true) -- muro de fondo
		box(m, wf, 0, 6, W + 7, c.len, 12, 9, brick, nil, true) -- obra de la barbacoa
		box(m, wf, 0, 12.6, W + 7, c.len, 1.2, 10, mortar, nil, true) -- encimera
		for k = 0, 3 do -- parrilla
			cyl(m, wf, 0, 14.6, W + 3.6 + k * 2.2, 0.6, c.len, black, "x", true)
		end
		local bw = c.step / 2
		for col = 1, c.n * 2 do -- ladrillos en relieve, al tresbolillo
			for row = 1, 3 do
				if (col + row) % 2 == 0 then
					box(m, wf, (col - 0.5) * bw - c.len / 2, (row - 0.5) * 4, W + 2.35, bw - 0.6, 3.4, 0.5, if row == 2 then brickDark else brick, nil, true)
				end
			end
		end
		for k = 1, math.floor(c.len / 10) do -- brasas bajo la parrilla
			neon(put(m, wf, (k - 0.5) * 10 - c.len / 2 + r:NextNumber(-2, 2), 13.6, W + 4 + (k % 3) * 2.6, V3(3.2, 1.8, 3), coal[k % 3 + 1], nil, "blob", true))
		end
		for j = 1, math.ceil(c.n / 2) do -- chimeneas con su humo
			local x = (j - 0.5) * 2 * c.step - c.len / 2
			box(m, wf, x, 30, W + 11, 8, 36, 6, brick)
			box(m, wf, x, 48.6, W + 11, 9.6, 1.4, 7.6, mortar)
			ball(m, wf, x + 2, 53, W + 10, 9, 6, 7, rgb(236, 232, 228), nil, true).Transparency = 0.3
		end
		for i = 1, c.n do -- humo sobre la parrilla
			ball(m, wf, (i - 0.5) * c.step - c.len / 2 + r:NextNumber(-3, 3), r:NextNumber(19, 26), W + 6, r:NextNumber(7, 10), r:NextNumber(4, 6), 6, rgb(240, 236, 232), nil, true).Transparency = 0.35
		end
	end

	local function bottle(f, color, cap)
		cyl(m, f, 0, 7, 0, 6.4, 14, color)
		ball(m, f, 0, 14, 0, 6.4, 4, 6.4, color)
		cyl(m, f, 0, 16.6, 0, 3.4, 3, cap)
		cyl(m, f, 0, 19.6, 0, 1.2, 3.2, cap)
		cyl(m, f, 0, 7, 0, 6.6, 4, white)
		ball(m, f, 0, 7, -3.3, 2.6, 2.6, 0.4, color, nil, true)
	end
	local function sauces(f)
		bottle(f * CFrame.new(-4.2, 0, 0), rgb(220, 40, 40), white)
		bottle(f * CFrame.new(4, 0, 1.5), rgb(255, 200, 40), rgb(220, 40, 40))
		ball(m, f, -1, 0.3, -6, 5, 0.6, 3, rgb(220, 40, 40), nil, true) -- chorretón de kétchup
	end
	local function skewer(f) -- brocheta gigante clavada de pie
		cyl(m, f, 0, 17, 0, 1.2, 34, rgb(214, 170, 110))
		ball(m, f, 0, 34.6, 0, 1, 2.4, 1, rgb(214, 170, 110))
		for _, piece in { { "meat", 7 }, { "pepper", 11.5 }, { "onion", 15 }, { "meat", 19.5 }, { "tomato", 24 }, { "meat", 28.5 } } do
			local kind, y = piece[1], piece[2]
			if kind == "meat" then
				ball(m, f, 0, y, 0, 6, 4.2, 5.6, rgb(150, 82, 48))
				ball(m, f, 0, y + 1.9, 0, 4.4, 1, 4, rgb(92, 50, 30))
			elseif kind == "pepper" then
				ball(m, f, 0, y, 0, 6.2, 2.4, 6, rgb(90, 180, 70))
			elseif kind == "onion" then
				cyl(m, f, 0, y, 0, 6, 2.2, rgb(244, 226, 240))
			else
				put(m, f, 0, y, 0, V3(5, 5, 5), rgb(236, 62, 50), nil, "ball")
			end
		end
		cyl(m, f, 0, 0.4, 0, 6, 0.8, steel)
	end
	local function cooler(f) -- nevera portátil con dos latas al lado
		box(m, f, 0, 5.5, 1, 15, 11, 10, rgb(60, 130, 220))
		box(m, f, 0, 11.8, 1, 15.6, 1.8, 10.6, white)
		box(m, f, 0, 5.5, -4.05, 15.1, 2, 0.3, white, nil, true)
		rod(m, f, V3(-5, 12.7, 1), V3(-4, 15, 1), 0.9, rgb(60, 60, 70))
		rod(m, f, V3(-4, 15, 1), V3(4, 15, 1), 0.9, rgb(60, 60, 70))
		rod(m, f, V3(4, 15, 1), V3(5, 12.7, 1), 0.9, rgb(60, 60, 70))
		for k, tint in { rgb(230, 50, 60), rgb(90, 200, 110) } do
			local x, z = 8 - k * 0.2, -2.5 + k * 1.8
			cyl(m, f, x, 3.4, z, 3.6, 6.8, tint)
			cyl(m, f, x, 6.9, z, 3, 0.3, steel)
		end
	end
	local function sack(f) -- saco de carbón con briquetas por el suelo
		ball(m, f, 0, 8, 1, 12, 16, 9, rgb(70, 64, 70))
		box(m, f, 0, 15.5, 1, 9.4, 2.6, 6, rgb(56, 52, 58), ANG(0, 0, 0.08))
		ball(m, f, 0, 8.5, -3.6, 7, 6, 1.2, rgb(255, 150, 40), nil, true)
		ball(m, f, 0, 8.8, -4.1, 3, 4, 0.6, rgb(255, 220, 70), nil, true)
		for k = 1, 4 do
			ball(m, f, -6 + k * 2.6, 0.9, -5 + (k % 2) * 1.6, 2.2, 1.6, 2.2, rgb(50, 46, 50))
		end
	end
	local function tools(f) -- espátula y pinzas apoyadas en la obra
		rod(m, f, V3(-4, 0.6, -4), V3(-4, 16, 3), 1.4, rgb(60, 50, 50))
		box(m, f, -4, 19.3, 4.5, 5.5, 7, 0.4, steel, ANG(0.427, 0, 0))
		for _, x in { 3, 5 } do
			rod(m, f, V3(x, 0.6, -4), V3(4 + (x - 4) * 0.4, 20, 3.8), 0.8, steel)
			box(m, f, x, 0.8, -4.3, 1.6, 1, 2, steel)
		end
		ball(m, f, 4, 20.2, 3.8, 2, 2, 2, black)
	end
	local function sausage(f) -- salchicha gigante con un tenedor clavado
		local s = rgb(200, 86, 52)
		cyl(m, f, 0, 3.4, 0, 6.8, 13, s, "x")
		for k = -1, 1, 2 do
			ball(m, f, k * 6.5, 3.4, 0, 6.8, 6.8, 6.8, s)
		end
		for _, x in { -3.5, 0, 3.5 } do
			cyl(m, f, x, 3.4, 0, 7, 0.7, rgb(110, 50, 30), "x")
		end
		for _, x in { -1, 0, 1 } do
			rod(m, f, V3(x, 4.5, 0), V3(x, 10, 0), 0.5, steel)
		end
		rod(m, f, V3(-1.3, 10, 0), V3(1.3, 10, 0), 0.8, steel)
		rod(m, f, V3(0, 10, 0), V3(2, 26, 2.5), 1.4, rgb(110, 70, 40))
	end

	local fillers = {
		function(f) -- montón de briquetas, una todavía encendida
			for k = 1, 5 do
				local p = ball(m, f, r:NextNumber(-5, 5), 1 + (if k > 3 then 1.6 else 0), r:NextNumber(-3, 3), 3, 2.2, 3, if k == 5 then coal[1] else rgb(54, 50, 54))
				if k == 5 then
					neon(p)
				end
			end
		end,
		function(f) -- leña apilada
			for k, at in { { 2, -2.2 }, { 2, 2.2 }, { 5.4, 0 } } do
				local x = r:NextNumber(-1, 1)
				cyl(m, f, x, at[1], at[2], 4, 14, if k == 3 then rgb(170, 116, 70) else wood, "x")
				cyl(m, f, x + 7.05, at[1], at[2], 3.2, 0.2, rgb(226, 190, 140), "x", true)
			end
		end,
		function(f) -- plato con dos mazorcas
			cyl(m, f, 0, 0.5, 0, 14, 1, white)
			for k = -1, 1, 2 do
				cyl(m, f, 0, 2.6, k * 2.2, 3.2, 9, rgb(255, 206, 60), "x")
			end
		end,
	}
	local filled = 0
	local function filler(f)
		filled += 1
		fillers[filled % #fillers + 1](f)
	end

	slots(c, W - 2, {
		[1] = { [2] = sauces, [5] = skewer, [7] = cooler },
		[-1] = { [3] = sack, [5] = tools, [8] = sausage },
	}, filler)
end

-- DESPENSA: balda de madera, pared con la balda de arriba llena de botes y paquetes gigantes
local function despensa(c)
	local m, r, W = c.parent, c.rng, c.half
	local wood, woodDark, woodLight = rgb(214, 172, 116), rgb(186, 140, 90), rgb(236, 210, 160)
	local tint = { rgb(230, 60, 62), rgb(60, 150, 230), rgb(255, 196, 40), rgb(70, 190, 120), rgb(255, 130, 50), rgb(170, 100, 220) }
	local white, cream, steel = rgb(255, 252, 244), rgb(250, 236, 200), rgb(196, 200, 210)

	-- Vetas de la madera a lo largo
	for k = 1, 8 do
		flat(c, -49 + k * 11 + r:NextNumber(-2, 2), c.len / 2, 0.5, c.len, rgb(214, 186, 136), 0.04)
	end
	-- Lentejas sueltas, harina derramada y cercos de café (anillo y hueco)
	cells(c, 10, function(t)
		flat(c, r:NextNumber(-46, 46), t, 1.3, 0.9, rgb(176, 110, 60), 0.06)
	end)
	cells(c, 6, function(t, i)
		local x = r:NextNumber(-40, 40)
		spot(c, x, t, r:NextNumber(6, 10), white, 0.08)
		spot(c, x + r:NextNumber(4, 7) * (if i % 2 == 0 then 1 else -1), t + 3, r:NextNumber(2, 3.5), white, 0.1)
	end)
	cells(c, 5, function(t)
		local x, d = r:NextNumber(-42, 42), r:NextNumber(7, 9)
		spot(c, x, t, d, rgb(140, 92, 56), 0.11)
		spot(c, x, t, d - 1.4, woodLight, 0.12)
	end)

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 24, W + 12, c.len, 48, 4, rgb(250, 240, 220), nil, true) -- pared
		box(m, wf, 0, 1.5, W + 9.6, c.len, 3, 1.2, woodDark, nil, true) -- rodapié
		box(m, wf, 0, 34, W + 4, c.len, 2, 16, wood, nil, true) -- balda de arriba
		box(m, wf, 0, 33.6, W - 3.9, c.len, 2.8, 0.4, white, nil, true) -- canto
		for j = 1, math.ceil(c.n / 2) do -- escuadras bajo la balda
			wedge(m, wf, (j - 0.5) * 2 * c.step - c.len / 2, 28.5, W + 6.5, 1.2, 9, 7, woodDark, ANG(0, 0, PI))
		end
		local scallops = math.floor(c.len / 5)
		for k = 1, scallops do -- puntilla de papel colgando del canto
			ball(m, wf, (k - 0.5) * c.len / scallops - c.len / 2, 32, W - 4.15, 4.6, 2.6, 0.4, if k % 2 == 0 then tint[1] else white, nil, true)
		end
		for i = 1, c.n do -- etiqueta de precio y lo que hay en la balda de arriba
			local x = (i - 0.5) * c.step - c.len / 2
			box(m, wf, x, 33.6, W - 4.2, 5, 2, 0.3, tint[(i + side + 1) % 6 + 1], nil, true)
			if i % 2 == 0 then
				cyl(m, wf, x - 4, 39, W + 4, 7, 8, cream)
				cyl(m, wf, x - 4, 43.8, W + 4, 7.4, 1.6, tint[i % 6 + 1])
				box(m, wf, x + 4, 41, W + 6, 7, 12, 4.5, tint[(i + 3) % 6 + 1])
			else
				box(m, wf, x - 3, 42, W + 6, 8, 14, 5, tint[(i + 1) % 6 + 1])
				cyl(m, wf, x + 4.5, 38.5, W + 4, 6, 7, steel)
				cyl(m, wf, x + 4.5, 38.5, W + 4, 6.2, 4, tint[(i + 4) % 6 + 1])
			end
		end
	end

	local function cerealBox(f) -- caja de cereales abierta, con bolitas caídas
		local bf = f * CFrame.new(0, 0, 2) * ANG(0, 0.15, 0)
		box(m, bf, 0, 13, 0, 14, 26, 6, rgb(255, 196, 40))
		box(m, bf, 0, 21, 0, 14.1, 6, 6.1, rgb(226, 52, 50))
		ball(m, bf, 0, 9, -3.1, 9, 4.5, 0.6, white, nil, true) -- tazón dibujado
		for k = -1, 1 do
			ball(m, bf, k * 2.2, 11.6, -3.2, 2.2, 2, 0.6, rgb(236, 160, 60), nil, true)
		end
		box(m, bf, 0, 27.6, 1.6, 14, 0.4, 5, rgb(255, 210, 70), ANG(0.9, 0, 0)) -- solapa abierta
		for k = 1, 4 do
			ball(m, f, -6 + k * 3, 0.8, -5 - (k % 2) * 1.5, 1.8, 1.6, 1.8, rgb(236, 172, 72))
		end
	end
	local function jamJars(f) -- dos tarros de mermelada con tela de cuadros
		for k, jam in { rgb(200, 30, 70), rgb(255, 150, 40) } do
			local x, s = (k - 1.5) * 9, if k == 1 then 1.2 else 1
			cyl(m, f, x, 5 * s, 0, 8 * s, 10 * s, jam)
			cyl(m, f, x, 10.6 * s, 0, 7 * s, 1.4 * s, rgb(250, 196, 56))
			ball(m, f, x, 11.6 * s, 0, 10 * s, 1.4 * s, 10 * s, if k == 1 then rgb(226, 58, 62) else rgb(60, 150, 230))
			cyl(m, f, x, 10.9 * s, 0, 7.4 * s, 0.4 * s, white)
			cyl(m, f, x, 4.6 * s, 0, 8.3 * s, 3.4 * s, cream)
		end
	end
	local function oil(f) -- botella de aceite con una rama de olivo pintada
		local glass = cyl(m, f, 0, 11, 1, 8, 22, rgb(250, 210, 60))
		glass.Transparency = 0.15
		ball(m, f, 0, 22, 1, 8, 5, 8, rgb(250, 210, 60)).Transparency = 0.15
		cyl(m, f, 0, 26, 1, 3, 4, rgb(250, 210, 60)).Transparency = 0.15
		cyl(m, f, 0, 28.6, 1, 3.6, 1.6, rgb(60, 130, 60))
		cyl(m, f, 0, 10, 1, 8.3, 7, cream)
		for k = -1, 1, 2 do
			ball(m, f, k * 1.2, 10.2 + k * 0.8, -3.2, 2.4, 1.2, 0.5, rgb(90, 150, 60), ANG(0, 0, k * 0.5), true)
		end
		ball(m, f, 0.3, 9.2, -3.25, 1.2, 1.5, 0.5, rgb(60, 90, 40), nil, true) -- aceituna
	end
	local function cans(f) -- pirámide de latas
		for k, at in { { -4, 4.5 }, { 4, 4.5 }, { 0, 13.5 } } do
			cyl(m, f, at[1], at[2], 1, 8, 9, steel)
			cyl(m, f, at[1], at[2], 1, 8.3, 5, tint[k + 1])
			ball(m, f, at[1], at[2], -3.2, 3, 3, 0.6, white, nil, true)
		end
	end
	local function pasta(f) -- paquete de espaguetis con la pasta asomando
		local pf = f * CFrame.new(0, 0, 2) * ANG(0, 0, 0.12)
		box(m, pf, 0, 10, 0, 8, 20, 3, rgb(250, 236, 180))
		box(m, pf, 0, 6, 0, 8.1, 6, 3.1, rgb(40, 90, 200))
		for k = -2, 3 do
			rod(m, pf, V3(k * 1.1 - 0.5, 18, 0), V3(k * 1.6 - 0.8, 28 + (k % 2) * 2, 0.3 * k), 0.5, rgb(250, 214, 110))
		end
		rod(m, f, V3(-2, 0.3, -6), V3(9, 0.3, -3), 0.5, rgb(250, 214, 110))
	end
	local function flour(f) -- saco de harina atado, con un montoncito derramado
		ball(m, f, 0, 7, 1, 13, 14, 10, cream)
		ball(m, f, 0, 15, 1, 6, 5, 5, cream)
		cyl(m, f, 0, 13.2, 1, 6.4, 1, woodDark)
		ball(m, f, 0, 7.5, -3.9, 6, 5, 0.8, rgb(60, 120, 210), nil, true)
		ball(m, f, -1, 8.2, -4.3, 1.4, 3.6, 0.5, rgb(255, 214, 90), ANG(0, 0, 0.3), true) -- espiga
		ball(m, f, 1, 8.2, -4.3, 1.4, 3.6, 0.5, rgb(255, 214, 90), ANG(0, 0, -0.3), true)
		ball(m, f, 5, 0.6, -5, 7, 1.6, 5, white)
	end

	local fillers = {
		function(f) -- caja de té con su etiqueta
			box(m, f, 0, 4, 1, 9, 8, 6, tint[4], ANG(0, 0.2, 0))
			box(m, f, 0, 4, 1, 9.1, 3, 6.1, cream, ANG(0, 0.2, 0))
			box(m, f, -1.5, 1.6, -2.4, 1.4, 2, 0.2, white, ANG(0, 0.2, 0), true)
		end,
		function(f) -- bolsa de arroz
			ball(m, f, 0, 4.5, 1, 9, 9, 7, white)
			ball(m, f, 0, 9.4, 1, 4, 2.4, 3, white)
			cyl(m, f, 0, 8.5, 1, 3.4, 0.6, tint[1])
		end,
		function(f) -- dos botes de especias
			for k = -1, 1, 2 do
				cyl(m, f, k * 3.4, 3.5, 0, 4.4, 7, rgb(236, 230, 214))
				cyl(m, f, k * 3.4, 7.4, 0, 4.6, 1, if k < 0 then tint[1] else tint[6])
			end
		end,
	}
	local filled = 0
	local function filler(f)
		filled += 1
		fillers[filled % #fillers + 1](f)
	end

	slots(c, W - 2, {
		[1] = { [2] = cerealBox, [5] = jamJars, [8] = oil },
		[-1] = { [3] = cans, [6] = pasta, [8] = flour },
	}, filler)
end

-- CUARTO DE JUGUETES: alfombra de carreteras, muro de bloques de construcción y juguetes gigantes
local function juguetes(c)
	local m, r, W = c.parent, c.rng, c.half
	local toy = { rgb(230, 57, 70), rgb(255, 204, 40), rgb(60, 140, 240), rgb(90, 200, 100), rgb(255, 140, 40), rgb(170, 100, 230) }
	local white, ink, road = rgb(255, 255, 255), rgb(40, 40, 50), rgb(84, 88, 100)

	-- Carretera larga por el centro, tres cruces y las rayas discontinuas
	flat(c, 0, c.len / 2, 16, c.len, road, 0.04)
	cells(c, 3, function(t)
		flat(c, 0, t, 96, 12, road, 0.06)
		for x = -44, 44, 10 do
			if math.abs(x) > 10 then
				flat(c, x, t, 5, 1, white, 0.08)
			end
		end
	end)
	cells(c, math.floor(c.len / 10), function(t)
		flat(c, 0, t, 1, 5, white, 0.1)
	end)
	-- Garabatos de cera de colores
	cells(c, 6, function(t, i)
		spot(c, (if i % 2 == 0 then 1 else -1) * r:NextNumber(18, 42), t, r:NextNumber(4, 8), toy[i % 6 + 1], 0.12)
	end)

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 26, W + 14, c.len, 52, 4, rgb(255, 242, 200), nil, true) -- papel pintado
		box(m, wf, 0, 2, W + 11.5, c.len, 4, 1, white, nil, true) -- rodapié
		-- Muro de bloques de construcción: tres hileras al tresbolillo, con botones arriba
		local bw = 12.5
		for row = 0, 2 do
			local offset = if row % 2 == 1 then bw / 2 else 0
			for k = 0, math.floor(c.len / bw) - 1 do
				local x = k * bw + bw / 2 + offset - c.len / 2
				if x + bw / 2 <= c.len / 2 + 0.01 then
					local color = toy[(k + row * 2 + side + 1) % 6 + 1]
					box(m, wf, x, 3.5 + row * 7, W + 6, bw - 0.4, 7, 7, color)
					if row == 2 then
						for s = -1, 1, 2 do
							cyl(m, wf, x + s * bw / 4, 21.6, W + 6, 3.4, 1.2, color)
						end
					end
				end
			end
		end
		for k = 1, 8 do -- lunares del papel pintado
			ball(m, wf, (k - 0.5) * c.len / 8 - c.len / 2, if k % 2 == 0 then 32 else 42, W + 11.9, 5, 5, 0.5, toy[(k + side + 1) % 6 + 1], nil, true)
		end
	end

	local function car(f) -- cochecito rojo
		local red = toy[1]
		box(m, f, 0, 4.5, 0, 15, 5, 8, red)
		box(m, f, -1, 9, 0, 8, 4.5, 7, red)
		for k = -1, 1, 2 do
			box(m, f, -1, 9.2, k * 3.55, 6.4, 3, 0.2, rgb(150, 210, 255), nil, true)
		end
		for _, x in { -4.8, 4.8 } do
			for k = -1, 1, 2 do
				cyl(m, f, x, 2.5, k * 3.9, 5, 1.6, ink, "z")
			end
		end
		for k = -1, 1, 2 do
			ball(m, f, 7.5, 5, k * 2.6, 0.8, 1.6, 1.6, rgb(255, 240, 160), nil, true)
		end
	end
	local function rings(f) -- torre de aros apilables
		cyl(m, f, 0, 1, 0, 14, 2, toy[3])
		cyl(m, f, 0, 11, 0, 2.4, 20, rgb(250, 230, 190))
		for k, d in { 12, 10.5, 9, 7.5, 6 } do
			cyl(m, f, 0, 2 + (k - 0.5) * 3.2, 0, d, 3.2, toy[(k + 1) % 6 + 1])
		end
		ball(m, f, 0, 21.6, 0, 4, 4, 4, toy[1])
	end
	local function teddy(f) -- osito sentado
		local fur, light = rgb(196, 136, 84), rgb(236, 200, 150)
		ball(m, f, 0, 6, 1, 11, 12, 10, fur)
		ball(m, f, 0, 6, -3.6, 6, 7, 3, light, nil, true) -- barriga
		ball(m, f, 0, 15, 1, 9, 8.5, 8.5, fur)
		for k = -1, 1, 2 do
			ball(m, f, k * 3.6, 19, 1, 3.4, 3.4, 2.4, fur) -- orejas
			ball(m, f, k * 6, 8, 0, 3.6, 7, 3.6, fur, ANG(0, 0, k * 0.5)) -- brazos
			ball(m, f, k * 3.4, 2, -4, 4, 4, 6, fur) -- piernas
			ball(m, f, k * 3.4, 2, -7, 2.6, 2.6, 0.6, light, nil, true) -- almohadillas
			ball(m, f, k * 1.6, 16, -3.3, 0.9, 1, 0.6, ink, nil, true) -- ojos
		end
		ball(m, f, 0, 13.6, -3.6, 3.4, 2.6, 2, light)
		ball(m, f, 0, 14.2, -4.6, 1.2, 0.8, 0.6, ink, nil, true)
	end
	local function blocks(f) -- cubos de letras de madera
		for k, at in { { -3.4, 3, 0, 0.1 }, { 3.4, 3, 0.5, -0.2 }, { 0, 9, 0.2, 0.4 } } do
			local rot = ANG(0, at[4], 0)
			box(m, f, at[1], at[2], at[3], 6, 6, 6, rgb(250, 232, 190), rot)
			put(m, f * CFrame.new(at[1], at[2], at[3]) * rot, 0, 0, -3.05, V3(3.6, 3.6, 0.3), toy[k + 1], nil, nil, true)
		end
	end
	local function duck(f) -- patito de goma
		local yellow = rgb(255, 214, 40)
		ball(m, f, 0, 5, 1, 14, 9, 10, yellow)
		ball(m, f, -4, 12.5, 1, 7.5, 7.5, 7.5, yellow)
		ball(m, f, -8.2, 12, 1, 3.4, 1.4, 2.6, rgb(255, 130, 30))
		ball(m, f, 4, 7, -4.4, 6, 4, 1.6, rgb(250, 196, 30), nil, true) -- ala
		ball(m, f, 6.6, 8.5, 1, 3.4, 3, 3.4, yellow) -- cola
		for k = -1, 1, 2 do
			ball(m, f, -6.3, 14, 1 + k * 2.2, 1.2, 1.4, 0.8, ink, ANG(0, PI / 2, 0), true)
		end
	end
	local function train(f) -- locomotora de madera
		box(m, f, 0, 3.5, 0, 16, 3, 7, toy[3])
		cyl(m, f, -2, 8, 0, 6, 9, toy[1], "x")
		box(m, f, 4.5, 9, 0, 6, 8, 7, toy[2])
		box(m, f, 4.5, 13.6, 0, 7.4, 1.2, 8, toy[1])
		cyl(m, f, -4.5, 13, 0, 2.6, 4, ink)
		for _, x in { -5, 0, 5 } do
			cyl(m, f, x, 2.4, -3.8, 4.4, 1.4, toy[4], "z")
		end
	end

	local fillers = {
		function(f) -- canicas
			for k = 1, 3 do
				local p = put(m, f, r:NextNumber(-5, 5), 1.6, r:NextNumber(-4, 3), V3(3.2, 3.2, 3.2), toy[(k + 2) % 6 + 1], nil, "ball")
				p.Transparency = 0.15
			end
		end,
		function(f) -- ceras tiradas
			for k = -1, 1, 2 do
				local cf = f * CFrame.new(0, 1, k * 2.4) * ANG(0, k * 0.3, 0)
				cyl(m, cf, 0, 0, 0, 2, 10, toy[k + 3], "x")
				ball(m, cf, 5.6, 0, 0, 2.4, 1.6, 1.6, toy[k + 3])
			end
		end,
		function(f) -- bloques sueltos
			for k = 1, 3 do
				box(m, f, -5 + k * 3.2, 1.5 + (if k == 2 then 3 else 0), r:NextNumber(-1, 1), 4, 3, 3, toy[(k * 2) % 6 + 1], ANG(0, r:NextNumber(-0.4, 0.4), 0))
			end
		end,
	}
	local filled = 0
	local function filler(f)
		filled += 1
		fillers[filled % #fillers + 1](f)
	end

	slots(c, W - 2, {
		[1] = { [2] = car, [5] = teddy, [8] = duck },
		[-1] = { [3] = rings, [5] = blocks, [7] = train },
	}, filler)
end

-- ESCRITORIO: alfombrilla de corte cuadriculada, una pared de libros y material de oficina gigante
local function escritorio(c)
	local m, r, W = c.parent, c.rng, c.half
	local books = { rgb(196, 60, 60), rgb(60, 110, 190), rgb(70, 160, 100), rgb(240, 180, 50), rgb(130, 80, 170), rgb(230, 120, 60), rgb(70, 70, 90) }
	local white, ink, steel = rgb(255, 255, 255), rgb(36, 36, 48), rgb(190, 196, 206)
	local grid = rgb(96, 112, 136)
	local mat = rgb(70, 84, 104)

	-- Cuadrícula de la alfombrilla: líneas a lo largo y a lo ancho, a dos alturas
	for x = -45, 45, 10 do
		flat(c, x, c.len / 2, 0.4, c.len, grid, 0.04)
	end
	cells(c, 15, function(t)
		flat(c, 0, t, 96, 0.4, grid, 0.06)
	end)
	-- Cercos de taza, notas adhesivas y gotas de tinta
	cells(c, 4, function(t)
		local x, d = r:NextNumber(-40, 40), r:NextNumber(8, 11)
		spot(c, x, t, d, rgb(130, 86, 56), 0.08)
		spot(c, x, t, d - 1.4, mat, 0.1)
	end)
	cells(c, 5, function(t, i)
		flat(c, (if i % 2 == 0 then 1 else -1) * r:NextNumber(14, 40), t + 6, 7, 7, if i % 2 == 0 then rgb(255, 230, 90) else rgb(255, 150, 190), 0.12)
	end)
	cells(c, 6, function(t)
		spot(c, r:NextNumber(-44, 44), t, r:NextNumber(1.5, 3), rgb(40, 60, 140), 0.11)
	end)

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 28, W + 16, c.len, 56, 4, rgb(214, 180, 130), nil, true) -- corcho
		box(m, wf, 0, 0.3, W + 1.5, c.len, 0.6, 5, rgb(240, 236, 220), nil, true) -- regla
		for k = 1, math.floor(c.len / 10) do
			box(m, wf, (k - 0.5) * 10 - c.len / 2, 0.62, W + 0.4, 0.4, 0.1, if k % 5 == 0 then 2.4 else 1.4, ink, nil, true)
		end
		-- Pared de libros de pie, con franja en el lomo uno sí y uno no
		local x = -c.len / 2
		local k = 0
		while x < c.len / 2 - 2 do
			k += 1
			local thick = math.min(r:NextNumber(3.5, 6.5), c.len / 2 - x)
			local h = r:NextNumber(30, 44)
			local lean = if k % 9 == 0 then 0.1 else 0
			box(m, wf, x + thick / 2, h / 2, W + 8, thick - 0.3, h, 11, books[(k + side + 1) % #books + 1], ANG(0, 0, lean))
			if k % 2 == 0 then
				box(m, wf, x + thick / 2, h * 0.78, W + 2.45, thick - 0.2, 2.2, 0.3, rgb(255, 214, 90), ANG(0, 0, lean), true)
			end
			x += thick
		end
		for j = 1, 6 do -- notas clavadas en el corcho
			local nx = (j - 0.5) * c.len / 6 - c.len / 2 + r:NextNumber(-3, 3)
			local tilt = ANG(0, 0, r:NextNumber(-0.15, 0.15))
			box(m, wf, nx, 50, W + 13.85, 8, 8, 0.3, if j % 2 == 0 then rgb(255, 230, 90) else rgb(150, 220, 255), tilt, true)
			ball(m, wf, nx, 53, W + 13.4, 1.2, 1.2, 1.2, books[j % #books + 1])
		end
	end

	local function mug(f) -- taza de café humeante
		local tint = rgb(230, 70, 70)
		cyl(m, f, 0, 8, 1, 14, 16, tint)
		cyl(m, f, 0, 16.05, 1, 12.4, 0.3, rgb(110, 64, 40))
		cyl(m, f, 0, 8, 1, 14.3, 3, white)
		rod(m, f, V3(6.6, 13, 1), V3(10, 12, 1), 2, tint)
		rod(m, f, V3(10, 12, 1), V3(10, 5, 1), 2, tint)
		rod(m, f, V3(10, 5, 1), V3(6.6, 4, 1), 2, tint)
		ball(m, f, -1, 20, 1, 4, 3.4, 4, white, nil, true).Transparency = 0.35
		ball(m, f, 1.5, 24, 1, 5, 4, 5, white, nil, true).Transparency = 0.5
	end
	local function pencil(f) -- lápiz tumbado
		local pf = f * CFrame.new(0, 1.8, -1) * ANG(0, 0.3, 0)
		cyl(m, pf, 0, 0, 0, 3.6, 16, rgb(255, 200, 40), "x")
		ball(m, pf, 9.5, 0, 0, 5, 3.6, 3.6, rgb(240, 200, 150))
		ball(m, pf, 11.6, 0, 0, 1.4, 1, 1, ink)
		cyl(m, pf, -8.6, 0, 0, 3.7, 1.2, steel, "x")
		cyl(m, pf, -10.2, 0, 0, 3.4, 2, rgb(255, 140, 160), "x")
	end
	local function keys(f) -- un trozo de teclado
		box(m, f, 0, 1.5, 1, 19, 3, 13, rgb(60, 62, 72))
		for row = 0, 1 do
			for col = -1, 1 do
				local x, z = col * 6, row * 6 - 2
				box(m, f, x, 4.2, z, 5, 2.4, 5, rgb(236, 236, 240))
				ball(m, f, x, 5.45, z, 2, 0.2, 2, ink, nil, true)
			end
		end
	end
	local function lamp(f) -- flexo encendido
		cyl(m, f, 0, 1, 2, 10, 2, ink)
		rod(m, f, V3(0, 2, 2), V3(-3, 15, 2), 1.4, steel)
		ball(m, f, -3, 15, 2, 2.2, 2.2, 2.2, ink)
		rod(m, f, V3(-3, 15, 2), V3(4, 22, 0), 1.4, steel)
		ball(m, f, 5, 21, -0.5, 7, 5, 7, ink, ANG(0, 0, -0.6))
		local bulb = neon(ball(m, f, 5.6, 19.2, -1, 3, 3, 3, rgb(255, 240, 180), nil, true))
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 236, 190)
		light.Range = 30
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = bulb
	end
	local function stapler(f) -- grapadora
		box(m, f, 0, 1, 0, 16, 2, 5, ink)
		box(m, f, 0.5, 3.8, 0, 15, 3, 4.4, rgb(220, 50, 50), ANG(0, 0, -0.06))
		ball(m, f, -7.4, 3.4, 0, 2.6, 3, 4.4, rgb(220, 50, 50))
		cyl(m, f, 7.6, 2.6, 0, 2.4, 5, steel, "z")
	end
	local function clips(f) -- clip gigante y una goma de borrar
		local cf = f * CFrame.new(-2, 0.4, -1) * ANG(0, 0.2, 0)
		local path = { V3(-6, 0, -2), V3(6, 0, -2), V3(6, 0, 2), V3(-4, 0, 2), V3(-4, 0, -0.6), V3(4, 0, -0.6) }
		for i = 1, #path - 1 do
			rod(m, cf, path[i], path[i + 1], 0.8, steel)
		end
		box(m, f, 6, 1.5, 2.5, 6, 3, 4, rgb(255, 150, 170), ANG(0, -0.3, 0))
		box(m, f, 6, 1.5, 2.5, 3, 3.1, 4.1, rgb(60, 110, 200), ANG(0, -0.3, 0))
	end

	local fillers = {
		function(f) -- bola de papel arrugado
			ball(m, f, 0, 3, 0, 6, 5.6, 6, white)
			ball(m, f, 1.6, 4, -1.4, 3, 2.6, 3, rgb(236, 236, 240))
			ball(m, f, -1.8, 4.6, 0.8, 2.6, 2.4, 2.6, rgb(244, 244, 248))
		end,
		function(f) -- bolígrafo con su capuchón
			local pf = f * CFrame.new(0, 1, 0) * ANG(0, r:NextNumber(-0.4, 0.4), 0)
			cyl(m, pf, 0, 0, 0, 1.8, 12, rgb(60, 110, 200), "x")
			cyl(m, pf, -6.8, 0, 0, 2, 2.4, white, "x")
			ball(m, pf, 6.6, 0, 0, 1.6, 1, 1, ink)
		end,
		function(f) -- chinchetas
			for k = -1, 1, 2 do
				cyl(m, f, k * 3, 0.4, k * 1.5, 4, 0.8, books[k + 3])
				ball(m, f, k * 3, 1.8, k * 1.5, 2.4, 2.4, 2.4, books[k + 3])
			end
		end,
	}
	local filled = 0
	local function filler(f)
		filled += 1
		fillers[filled % #fillers + 1](f)
	end

	slots(c, W - 2, {
		[1] = { [2] = mug, [5] = keys, [8] = lamp },
		[-1] = { [2] = pencil, [4] = stapler, [7] = clips },
	}, filler)
end

local BUILDERS = { Barbacoa = barbacoa, Despensa = despensa, Juguetes = juguetes, Escritorio = escritorio }

-- area = { x0, x1, z0, z1 } con z1 < z0 (la zona avanza hacia -Z); groundY = cara superior del suelo.
function Decor3.build(theme: string, parent: Instance, area, groundY: number)
	local builder = BUILDERS[theme]
	if not builder then
		warn(`Decor3: tema desconocido "{theme}"`)
		return
	end
	local length = math.abs(area.z0 - area.z1)
	local n = math.max(1, math.floor(length / 20 + 0.5))
	local cx, half = (area.x0 + area.x1) / 2, math.abs(area.x1 - area.x0) / 2
	-- n huecos de ~20 studs por lateral; `step` es su ancho real
	builder({ parent = parent, rng = Random.new(SEEDS[theme]), gy = groundY, cx = cx, half = half, z0 = math.max(area.z0, area.z1), len = length, n = n, step = length / n })
end

return Decor3
