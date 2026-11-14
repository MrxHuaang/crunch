-- Decorado temático de cada zona del túnel, hecho por código con piezas simples (bloques, bolas,
-- cilindros, cuñas y elipsoides). Todo es gigante porque eres una hormiga.
--   · Centro (|x| <= 50): solo detalles planos de suelo (<= 0.12 studs) y cositas de menos de 2 studs.
--   · Bandas laterales (|x| >= 50): un módulo de pared repetido con variación + hitos únicos alternando lado.
--   · Nada colisiona (los muros invisibles los pone quien llama) y el contorno de tinta va en el modelo padre.
-- Se asume el pasillo centrado en x = 0 con muros en x = ±60.

local Decor = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder
local NEON = Enum.Material.Neon

local rgb = Color3.fromRGB

-- ── Piezas básicas (mismas convenciones que World.luau). Ojo: `extra` se muta, pásalo siempre literal ──
local function part(parent: Instance, props): Part
	local p = if props.wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide == true
	p.CanTouch = false
	p.CanQuery = props.collide == true
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = props.shadow ~= false
	p.Size = props.size
	p.Color = props.color
	p.CFrame = props.cframe
	p.Transparency = props.transparency or 0
	if props.shape then (p :: Part).Shape = props.shape end
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
	props.size, props.color, props.shape = Vector3.new(height, diameter, diameter), color, CYLINDER
	props.cframe = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return part(parent, props)
end

-- Elipsoide
local function blob(parent, size: Vector3, color, cframe: CFrame, extra)
	local props = extra or {}
	props.size, props.color, props.cframe, props.blob = size, color, cframe, true
	return part(parent, props)
end

local function ball(parent, diameter, color, position: Vector3, extra)
	local props = extra or {}
	props.size, props.color, props.cframe, props.shape = Vector3.one * diameter, color, CFrame.new(position), BALL
	return part(parent, props)
end

-- Cilindro tendido entre dos puntos
local function rod(parent, a: Vector3, b: Vector3, thickness, color, extra)
	local props = extra or {}
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	props.size, props.color, props.shape = Vector3.new((b - a).Magnitude, thickness, thickness), color, CYLINDER
	props.cframe = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.rad(90), 0)
	return part(parent, props)
end

-- Palo a rayas: tramos de cilindro alternando colores
local function stripedPole(parent, a: Vector3, b: Vector3, thickness, colors, segments)
	for i = 1, segments do rod(parent, a:Lerp(b, (i - 1) / segments), a:Lerp(b, i / segments), thickness, colors[(i - 1) % #colors + 1]) end
end

-- Mancha pegada a la superficie de un elipsoide (lunares, cráteres, agujeros de queso)
local function spot(parent, center: Vector3, radii: Vector3, dir: Vector3, size, color)
	local u = dir.Unit
	local p = center + u * radii
	return blob(parent, Vector3.new(size, size, size * 0.4), color, CFrame.lookAt(p, p + (u / radii).Unit), { shadow = false })
end

-- Hoja: elipsoide plano que nace en `base` y apunta hacia su -Z
local function leaf(parent, base: CFrame, length, width, color)
	return blob(parent, Vector3.new(width, 1.4, length), color, base * CFrame.new(0, 0, -length / 2))
end

local function pick(rng: Random, list)
	return list[rng:NextInteger(1, #list)]
end

-- ── Composición. `c` = { parent, gy, z0, z1, len, zc, rng, marks } ──
-- Detalles planos de suelo; layer 0..2 apila sin z-fighting (tope en groundY + 0.12)
local function decal(c, diameter, color, x, z, layer)
	return disc(c.parent, diameter, 0.04, color, Vector3.new(x, c.gy + 0.02 + (layer or 0) * 0.04, z), { shadow = false })
end

local function tile(c, sx, sz, color, x, z, layer, yaw)
	local cframe = CFrame.new(x, c.gy + 0.02 + (layer or 0) * 0.04, z) * CFrame.Angles(0, yaw or 0, 0)
	return part(c.parent, { size = Vector3.new(sx, 0.04, sz), color = color, cframe = cframe, shadow = false })
end

-- Repite un módulo a lo largo de la zona en los dos lados: fn(z, side, i, step).
-- `stagger` (fracción de paso) desfasa un lado respecto al otro.
local function along(c, spacing: number, fn, stagger: number?)
	local n = math.max(1, math.floor(c.len / spacing))
	local step = c.len / n
	for side = -1, 1, 2 do
		for i = 1, n do fn(c.z0 - (i - 0.5 + side * (stagger or 0)) * step, side, i, step) end
	end
end

-- Reparte detalles de suelo sin que se pisen: una celda por paso en cada mitad del pasillo.
-- Lo que se dibuje en fn(x, z, k) debe caber en un círculo de diámetro `cell`.
local function scatter(c, cell: number, fn)
	local n = math.max(1, math.floor(c.len / cell))
	local step = c.len / n
	for i = 1, n do
		for lane = -1, 1, 2 do fn(lane * c.rng:NextNumber(cell / 2, 50 - cell / 2), c.z0 - (i - 0.5) * step, i + (lane + 1) / 2) end
	end
end

-- Cositas diminutas (menos de 2 studs) sueltas por el centro
local function pebbles(c, count, colors)
	for _ = 1, count do
		local s = c.rng:NextNumber(0.9, 1.9)
		local pos = Vector3.new(c.rng:NextNumber(-46, 46), c.gy + s * 0.22, c.rng:NextNumber(c.z1 + 6, c.z0 - 6))
		blob(c.parent, Vector3.new(s, s * 0.6, s), pick(c.rng, colors), CFrame.new(pos), { shadow = false })
	end
end

-- Telón continuo detrás del decorado para que no se vea el vacío
local function backdrop(c, x, height, colors, seg, vary)
	local n = math.max(1, math.floor(c.len / seg))
	local step = c.len / n
	for side = -1, 1, 2 do
		for i = 1, n do
			local h = height + (if (i + side) % 4 < 2 then vary else 0)
			local color = colors[(i + (side + 1) / 2) % #colors + 1]
			part(c.parent, { name = "Backdrop", size = Vector3.new(2, h, step), color = color, cframe = CFrame.new(side * x, c.gy + h / 2, c.z0 - (i - 0.5) * step) })
		end
	end
end

-- Hitos únicos a intervalos regulares, alternando lado: build(pos, side) con pos en x = ±56
local function landmarks(c, builders)
	for i, build in builders do
		local side = if i % 2 == 1 then -1 else 1
		local z = c.z0 - (i - 0.5) * c.len / #builders
		table.insert(c.marks, { z = z, side = side })
		build(Vector3.new(side * 56, c.gy, z), side)
	end
end

-- ¿Queda libre este tramo de la banda lateral (sin hitos cerca)?
local function free(c, z: number, side: number, margin: number): boolean
	for _, mark in c.marks do
		if mark.side == side and math.abs(mark.z - z) < margin then return false end
	end
	return true
end

-- ── Picnic ──
local function picnic(c)
	local P, gy, rng = c.parent, c.gy, c.rng
	local cream, red, deep = rgb(255, 244, 222), rgb(238, 92, 88), rgb(200, 40, 50)
	local wicker = { rgb(222, 170, 98), rgb(204, 148, 78), rgb(238, 192, 122) }
	local steel, shine = rgb(196, 204, 220), rgb(232, 238, 248)
	local greens = { rgb(62, 166, 70), rgb(86, 190, 78), rgb(46, 146, 66) }
	local ROW_H, ROWS = 6.5, 4
	local wallH = ROW_H * ROWS

	-- Mantel vichy: base crema, franjas rojas de 10 studs y cuadro oscuro en cada cruce
	tile(c, 120, c.len, cream, 0, c.zc, 0)
	for x = -50, 50, 20 do tile(c, 10, c.len, red, x, c.zc, 1) end
	local rows = math.max(1, math.floor(c.len / 20))
	for i = 1, rows do
		local z = c.z0 - (i - 0.5) * c.len / rows
		tile(c, 120, 10, red, 0, z, 1)
		for x = -50, 50, 20 do tile(c, 10, 10, deep, x, z, 2) end
	end
	pebbles(c, 6, { rgb(232, 180, 110), rgb(250, 214, 150) }) -- migas

	-- Paredes: cesta de mimbre gigante. Tiras gordas y finas alternadas sobre fondo oscuro + estacas.
	backdrop(c, 67, wallH, { rgb(118, 76, 44) }, c.len, 0)
	for side = -1, 1, 2 do rod(P, Vector3.new(side * 65, gy + wallH + 0.5, c.z0), Vector3.new(side * 65, gy + wallH + 0.5, c.z1), 4.5, wicker[2]) end
	along(c, 14, function(z, side, i, step)
		for row = 1, ROWS do
			local over = (i + row) % 2 == 0
			local cframe = CFrame.new(side * (if over then 64.6 else 65.4), gy + (row - 0.5) * ROW_H, z + (row % 2 - 0.5) * step / 2)
			blob(P, Vector3.new(if over then 5 else 3.4, ROW_H + 0.6, step + 3), wicker[(i + row * 2) % 3 + 1], cframe * CFrame.Angles(rng:NextNumber(-0.03, 0.03), 0, 0))
		end
		if i % 2 == 0 then disc(P, 2.4, wallH + 2, rgb(168, 114, 60), Vector3.new(side * 63.4, gy + wallH / 2 + 1, z - step / 2)) end
	end)

	-- Hierba gigante asomando por encima de la cesta
	along(c, 16, function(z, side)
		for _ = 1, 2 do
			local h = rng:NextNumber(34, 46)
			local cframe = CFrame.new(side * rng:NextNumber(70, 74), gy + h / 2, z + rng:NextNumber(-6, 6))
				* CFrame.Angles(0, if rng:NextNumber() < 0.5 then 0 else math.pi, 0)
				* CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, 0)
			part(P, { wedge = true, size = Vector3.new(1.2, h, rng:NextNumber(5, 8)), color = pick(rng, greens), cframe = cframe })
		end
	end, 0.25)

	landmarks(c, {
		function(pos, side) -- tenedor apoyado en la cesta
			local cf = CFrame.lookAt(pos + Vector3.new(-side * 3, 0.5, 0), pos + Vector3.new(side * 7, 31, 4))
			part(P, { size = Vector3.new(2.2, 0.9, 20), color = steel, cframe = cf * CFrame.new(0, 0, -10) })
			part(P, { size = Vector3.new(6.6, 0.9, 5), color = steel, cframe = cf * CFrame.new(0, 0, -22.5) })
			for t = -1.5, 1.5 do part(P, { size = Vector3.new(1.1, 0.9, 9), color = shine, cframe = cf * CFrame.new(t * 1.8, 0, -29.5) }) end
		end,
		function(pos) -- pila de platos con una cereza
			for i = 0, 4 do
				local p = pos + Vector3.new(rng:NextNumber(-0.5, 0.5), 0.7 + i * 1.7, rng:NextNumber(-0.5, 0.5))
				disc(P, 12, 1.1, WHITE, p)
				disc(P, 8.5, 0.5, rgb(170, 206, 240), p + Vector3.new(0, 0.6, 0))
			end
			ball(P, 4, rgb(220, 30, 60), pos + Vector3.new(0, 10.4, 0))
		end,
		function(pos, side) -- cuchara
			local cf = CFrame.lookAt(pos + Vector3.new(-side * 3, 0.5, 0), pos + Vector3.new(side * 7, 30, -4))
			part(P, { size = Vector3.new(2, 0.9, 22), color = steel, cframe = cf * CFrame.new(0, 0, -11) })
			blob(P, Vector3.new(8.5, 2.6, 12), steel, cf * CFrame.new(0, 0, -27))
			blob(P, Vector3.new(6, 2, 9), shine, cf * CFrame.new(0, 0.6, -27))
		end,
		function(pos, side) -- vaso con pajita
			local p = pos + Vector3.new(side * 0.5, 0, 0)
			disc(P, 11, 16, rgb(255, 196, 40), p + Vector3.new(0, 8, 0))
			disc(P, 11.4, 3, WHITE, p + Vector3.new(0, 7, 0))
			disc(P, 12, 1, WHITE, p + Vector3.new(0, 16, 0))
			local bend = p + Vector3.new(-side * 1.5, 25, 1)
			stripedPole(P, p + Vector3.new(0, 15, 0), bend, 1.4, { red, cream }, 5)
			stripedPole(P, bend, bend + Vector3.new(-side * 4.5, 2.5, 1), 1.4, { cream, red }, 2)
		end,
		function(pos, side) -- servilleta doblada en tienda
			tile(c, 14, 14, WHITE, pos.X + side, pos.Z, 2, 0.4)
			for k = -1, 1, 2 do
				local cframe = CFrame.new(pos + Vector3.new(side, 6.5, k * 2.5)) * CFrame.Angles(0, if k == 1 then math.pi else 0, 0)
				part(P, { wedge = true, size = Vector3.new(11, 13, 5), color = if k == 1 then WHITE else shine, cframe = cframe })
			end
		end,
		function(pos, side) -- botella
			local p, glass = pos + Vector3.new(side, 0, 0), rgb(64, 170, 110)
			disc(P, 10, 19, glass, p + Vector3.new(0, 9.5, 0))
			blob(P, Vector3.new(10, 9, 10), glass, CFrame.new(p + Vector3.new(0, 19, 0)))
			disc(P, 4, 9, glass, p + Vector3.new(0, 25.5, 0))
			disc(P, 4.8, 1.8, deep, p + Vector3.new(0, 30.5, 0))
			disc(P, 10.3, 7, cream, p + Vector3.new(0, 10, 0))
		end,
	})
end

-- ── Jungla ──
local function mushroom(parent, pos: Vector3, height, capD, color, side)
	disc(parent, capD * 0.28, height, rgb(255, 240, 214), pos + Vector3.new(0, height / 2, 0))
	local cap = pos + Vector3.new(0, height + capD * 0.1, 0)
	local radii = Vector3.new(capD / 2, capD * 0.3, capD / 2)
	blob(parent, radii * 2, color, CFrame.new(cap))
	for k = -2, 2 do spot(parent, cap, radii, Vector3.new(-side * (1 - math.abs(k) * 0.25), 0.55 + (k % 2) * 0.5, k * 0.45), capD * 0.17, WHITE) end
end

-- Flor tropical: tallo, seis pétalos de cara al pasillo, corazón y una hoja
local function flower(parent, base: Vector3, top: Vector3, side, petal, heart, green)
	rod(parent, base, top, 1.6, green)
	local face = CFrame.lookAt(top, top + Vector3.new(-side, 0.4, 0))
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		blob(parent, Vector3.new(7, 7, 2), petal, face * CFrame.new(math.cos(a) * 5.5, math.sin(a) * 5.5, 0))
	end
	blob(parent, Vector3.new(6.5, 6.5, 3.4), heart, face)
	local mid = base:Lerp(top, 0.4)
	leaf(parent, CFrame.lookAt(mid, mid + Vector3.new(0, 0.5, 1), Vector3.new(-side, 0, 0)), 10, 5, green)
end

-- Liana: cadena de cilindros que cuelga; devuelve la punta
local function vine(parent, top: Vector3, length, segments, color, rng: Random): Vector3
	local a = top
	for i = 1, segments do
		local b = top + Vector3.new(rng:NextNumber(-0.9, 0.9), -length * i / segments, rng:NextNumber(-0.9, 0.9))
		rod(parent, a, b, 0.9, color)
		a = b
	end
	return a
end

local function jungla(c)
	local P, gy, rng = c.parent, c.gy, c.rng
	local greens = { rgb(40, 140, 66), rgb(70, 176, 70), rgb(122, 208, 70), rgb(168, 226, 78) }
	local bark = { rgb(120, 78, 46), rgb(150, 100, 60) }

	local function roots(from: Vector3, reach, thick, side)
		for k = -1, 1 do
			local a = (if side == 1 then math.pi else 0) + k * 1.15
			rod(P, from, Vector3.new(from.X + math.cos(a) * reach, gy - 0.5, from.Z + math.sin(a) * reach), thick, bark[2])
		end
	end

	-- Suelo: manchas de musgo oscuro con un brote lima dentro
	scatter(c, 24, function(x, z)
		local d = rng:NextNumber(13, 22)
		decal(c, d, rgb(52, 140, 62), x, z, 0)
		decal(c, d * rng:NextNumber(0.35, 0.55), rgb(160, 222, 80), x + rng:NextNumber(-0.2, 0.2) * d, z + rng:NextNumber(-0.2, 0.2) * d, 1)
	end)
	pebbles(c, 6, { rgb(230, 60, 60), rgb(255, 214, 80) }) -- bayas caídas
	backdrop(c, 75, 34, { rgb(20, 84, 56), rgb(26, 98, 60) }, 40, 5)

	landmarks(c, {
		function(pos, side) -- flor naranja
			flower(P, pos + Vector3.new(side * 4, 0, 0), pos + Vector3.new(0, 24, 0), side, rgb(255, 140, 40), rgb(255, 214, 80), greens[2])
		end,
		function(pos, side) -- setas rojas
			mushroom(P, pos + Vector3.new(side * 3, 0, 0), 13, 18, rgb(230, 52, 56), side)
			mushroom(P, pos + Vector3.new(-side * 2, 0, 11), 5, 8, rgb(255, 150, 60), side)
		end,
		function(pos, side) -- flor rosa
			flower(P, pos + Vector3.new(side * 5, 0, 0), pos + Vector3.new(side, 28, 0), side, rgb(255, 110, 170), rgb(255, 236, 150), greens[3])
		end,
		function(pos, side) -- tocón con una seta encima
			local p = pos + Vector3.new(side * 2, 0, 0)
			disc(P, 14, 8, bark[1], p + Vector3.new(0, 4, 0))
			disc(P, 12.4, 0.6, rgb(232, 190, 124), p + Vector3.new(0, 8.2, 0))
			disc(P, 6.4, 0.7, rgb(200, 152, 92), p + Vector3.new(0, 8.3, 0))
			roots(p + Vector3.new(0, 4, 0), 7.5, 3.4, side)
			mushroom(P, p + Vector3.new(-side * 2, 8.4, 2), 4, 7, rgb(255, 150, 60), side)
		end,
		function(pos, side) -- setas moradas
			mushroom(P, pos + Vector3.new(side * 3, 0, 0), 16, 16, rgb(170, 90, 230), side)
			mushroom(P, pos + Vector3.new(-side, 0, -10), 7, 10, rgb(214, 130, 255), side)
		end,
	})

	-- Pared de hojas gigantes: abanico de tres hojas saliendo de un arbusto
	along(c, 16, function(z, side, i)
		local x = side * rng:NextNumber(65, 69)
		blob(P, Vector3.new(12, rng:NextNumber(14, 20), 18), greens[1], CFrame.new(x + side * 2, gy, z))
		for k = -1, 1 do
			local base = Vector3.new(x + side * (1 - math.abs(k)), gy + 2, z + k * 3)
			local tilt = Vector3.new(-side * 0.22, 1, k * 0.7 + rng:NextNumber(-0.15, 0.15))
			local length = if k == 0 then rng:NextNumber(27, 33) else rng:NextNumber(19, 25)
			leaf(P, CFrame.lookAt(base, base + tilt, Vector3.new(-side, 0, 0)), length, rng:NextNumber(10, 14), greens[(i + k) % 3 + 2])
		end
	end, 0.25)

	-- Troncos con raíces, copa y lianas colgando (se saltan donde hay un hito)
	along(c, 48, function(z, side)
		if not free(c, z, side, 13) then return end
		local x, d, h = side * rng:NextNumber(62, 64), rng:NextNumber(9, 12), rng:NextNumber(38, 46)
		disc(P, d, h, bark[1], Vector3.new(x, gy + h / 2, z))
		roots(Vector3.new(x, gy + 7, z), d * 0.85, d * 0.42, side)
		blob(P, Vector3.new(24, 13, 30), greens[1], CFrame.new(x + side * 5, gy + h, z))
		blob(P, Vector3.new(15, 9, 20), greens[3], CFrame.new(x - side, gy + h + 3.5, z + rng:NextNumber(-4, 4)))
		for k = -1, 1, 2 do
			local top = Vector3.new(x - side * rng:NextNumber(3.5, 5.5), gy + h - 2.5, z + k * rng:NextNumber(6, 10))
			local tip = vine(P, top, rng:NextNumber(14, 24), 3, greens[2], rng)
			ball(P, 2.6, pick(rng, { rgb(255, 120, 170), rgb(255, 150, 60) }), tip)
		end
	end, -0.25)
end

-- ── Mar ──
local function mar(c)
	local P, gy, rng = c.parent, c.gy, c.rng
	local deep = { rgb(30, 104, 200), rgb(40, 122, 214) }
	local water = { rgb(52, 150, 232), rgb(70, 168, 240) }
	local cyan = { rgb(120, 214, 240), rgb(152, 228, 246) }
	local sand = { rgb(240, 206, 130), rgb(226, 186, 110), rgb(250, 224, 158) }
	local coralRed, starfish = rgb(240, 70, 70), rgb(255, 120, 70)
	local shellPink = { rgb(255, 170, 190), rgb(255, 204, 214) }

	-- Suelo: charcos con anillo de espuma y manchas de arena mojada
	scatter(c, 20, function(x, z, k)
		local d = rng:NextNumber(10, 18)
		if k % 2 == 0 then
			decal(c, d, WHITE, x, z, 0)
			decal(c, d - 2.4, water[2], x, z, 1)
			decal(c, d * 0.32, cyan[1], x - d * 0.16, z + d * 0.14, 2)
		else
			decal(c, d, rgb(224, 186, 118), x, z, 0)
			decal(c, d * 0.45, sand[3], x + d * 0.12, z - d * 0.1, 1)
		end
	end)
	pebbles(c, 8, { shellPink[1], WHITE, rgb(255, 196, 120) }) -- conchitas

	-- Paredes: olas en tres capas (azul hondo, azul, cian) con cresta, rizo y espuma en la orilla
	along(c, 18, function(z, side, i, step)
		local h = rng:NextNumber(29, 38)
		blob(P, Vector3.new(18, h * 2, step + 13), deep[i % 2 + 1], CFrame.new(side * 75, gy, z))
		blob(P, Vector3.new(14, h * 1.45, step + 9), water[i % 2 + 1], CFrame.new(side * 70, gy, z + step / 2))
		blob(P, Vector3.new(10, h * 0.8, step + 5), cyan[i % 2 + 1], CFrame.new(side * 66, gy, z + rng:NextNumber(-3, 3)))
		blob(P, Vector3.new(8, 5, 13), WHITE, CFrame.new(side * 72, gy + h - 1.5, z) * CFrame.Angles(0, 0, side * 0.3))
		blob(P, Vector3.new(7, 6, 9), WHITE, CFrame.new(side * 68, gy + h * 0.7 - 1, z + step / 2))
		blob(P, Vector3.new(6, 2.2, 13), WHITE, CFrame.new(side * 61, gy + 0.5, z + rng:NextNumber(-4, 4)), { shadow = false })
	end)

	-- Burbujas flotando sobre la orilla
	for i = 1, math.floor(c.len / 8) do
		local pos = Vector3.new((if i % 2 == 0 then 1 else -1) * rng:NextNumber(51, 60), gy + rng:NextNumber(4, 34), rng:NextNumber(c.z1 + 2, c.z0 - 2))
		ball(P, rng:NextNumber(1, 3.2), if i % 3 == 0 then cyan[2] else WHITE, pos, { shadow = false })
	end

	local function coral(pos: Vector3, color, tip)
		rod(P, pos + Vector3.new(0, -0.5, 0), pos + Vector3.new(0, 9, 0), 3.2, color)
		for k = 1, 5 do
			local a = k * 1.26 + rng:NextNumber(-0.3, 0.3)
			local from = pos + Vector3.new(0, 3 + k * 1.2, 0)
			local to = from + Vector3.new(math.cos(a) * 4.5, rng:NextNumber(6, 11), math.sin(a) * 4.5)
			rod(P, from, to, 2, color)
			ball(P, 3, tip, to)
		end
	end

	landmarks(c, {
		function(pos, side) -- sombrilla de playa
			local top = pos + Vector3.new(side * 2, 27, 2)
			stripedPole(P, pos, top, 1.6, { WHITE, coralRed }, 5)
			local cf = CFrame.lookAt(top, top + (top - pos))
			blob(P, Vector3.new(20, 20, 9), coralRed, cf)
			blob(P, Vector3.new(11, 11, 5), WHITE, cf * CFrame.new(0, 0, -3.4))
			ball(P, 2.2, rgb(255, 214, 80), (cf * CFrame.new(0, 0, -6.4)).Position)
			for k = 1, 6 do
				local a = k / 6 * math.pi * 2
				blob(P, Vector3.new(5, 5, 3), WHITE, cf * CFrame.new(math.cos(a) * 9, math.sin(a) * 9, 1.2))
			end
		end,
		function(pos, side) coral(pos + Vector3.new(side, 0, 0), rgb(255, 110, 160), rgb(255, 180, 206)) end, -- coral rosa
		function(pos, side) -- castillo de arena
			local p = pos + Vector3.new(side * 2, 0, 0)
			part(P, { size = Vector3.new(11, 6, 11), color = sand[1], cframe = CFrame.new(p + Vector3.new(0, 3, 0)) })
			for i = 0, 3 do
				local corner = p + Vector3.new((i % 2 - 0.5) * 10, 0, (math.floor(i / 2) - 0.5) * 10)
				disc(P, 4.4, 11, sand[2], corner + Vector3.new(0, 5.5, 0))
				disc(P, 5.4, 1.6, sand[3], corner + Vector3.new(0, 11.4, 0))
			end
			disc(P, 7, 17, sand[3], p + Vector3.new(0, 8.5, 0))
			disc(P, 8.4, 2, sand[2], p + Vector3.new(0, 17.6, 0))
			rod(P, p + Vector3.new(0, 18, 0), p + Vector3.new(0, 25, 0), 0.5, rgb(132, 86, 52))
			part(P, { wedge = true, size = Vector3.new(0.4, 2.6, 4), color = coralRed, cframe = CFrame.new(p + Vector3.new(0, 23.6, 2.1)) })
			part(P, { size = Vector3.new(0.5, 4.4, 3), color = rgb(150, 110, 60), cframe = CFrame.new(p + Vector3.new(-side * 5.6, 2.2, 0)) })
		end,
		function(pos, side) -- estrella de mar
			local cf = CFrame.lookAt(pos + Vector3.new(side * 3, 9.5, 0), pos + Vector3.new(-side * 4, 13, 0))
			blob(P, Vector3.new(7.5, 7.5, 3.6), starfish, cf)
			for k = 0, 4 do
				local arm = cf * CFrame.Angles(0, 0, k * math.rad(72))
				blob(P, Vector3.new(4.6, 11, 3), starfish, arm * CFrame.new(0, 5.6, 0))
				blob(P, Vector3.new(1.5, 1.5, 1), rgb(255, 204, 160), arm * CFrame.new(0, 4.5, -1.5), { shadow = false })
			end
		end,
		function(pos, side) coral(pos + Vector3.new(side, 0, 0), rgb(255, 150, 60), rgb(255, 206, 120)) end, -- coral naranja
		function(pos, side) -- concha con perla
			local cf = CFrame.lookAt(pos + Vector3.new(side * 2, 1.5, 0), pos + Vector3.new(-side * 5, 6, 0))
			for k = -2, 2 do blob(P, Vector3.new(4, 12, 2.6), shellPink[k % 2 + 1], cf * CFrame.Angles(0, 0, k * 0.42) * CFrame.new(0, 6, 0)) end
			blob(P, Vector3.new(6, 3.4, 3.4), shellPink[1], cf)
			ball(P, 3.2, WHITE, (cf * CFrame.new(0, 2.6, -2.4)).Position)
		end,
	})
end

-- ── Dulce ──
-- Bastón de caramelo: tramo recto a rayas + gancho que se curva hacia `bend`
local function candyCane(parent, base: Vector3, height, thick, bend: Vector3, colors)
	local top = base + Vector3.new(0, height, 0)
	stripedPole(parent, base, top, thick, colors, 4)
	local pts = { top, top + bend * 0.28 + Vector3.new(0, thick, 0), top + bend * 0.72 + Vector3.new(0, thick * 1.2, 0), top + bend + Vector3.new(0, thick * 0.3, 0) }
	for i = 1, 3 do
		local pad = (pts[i + 1] - pts[i]).Unit * thick * 0.25 -- solapa los tramos para tapar las esquinas
		rod(parent, pts[i] - pad, pts[i + 1] + pad, thick, colors[i % #colors + 1])
	end
end

-- Piruleta: palo + disco de cara al pasillo con anillos concéntricos
local function lollipop(parent, base: Vector3, top: Vector3, diameter, rings, colors)
	rod(parent, base, top, diameter * 0.1, WHITE)
	for k = 0, rings - 1 do
		local d = diameter * (1 - k / rings)
		part(parent, { shape = CYLINDER, size = Vector3.new(1.6 + k * 0.5, d, d), color = colors[k % #colors + 1], cframe = CFrame.new(top) })
	end
end

-- Caramelo envuelto: cuerpo, franja y los dos lazos del papel a lo largo del eje Z de `axis`
local function wrappedCandy(parent, axis: CFrame, color, stripe)
	blob(parent, Vector3.new(10, 10, 14), color, axis)
	blob(parent, Vector3.new(10.8, 10.8, 6), stripe, axis)
	for k = -1, 1, 2 do
		blob(parent, Vector3.new(3, 3, 3), color, axis * CFrame.new(0, 0, k * 7.4))
		blob(parent, Vector3.new(2, 9, 6), stripe, axis * CFrame.new(0, 0, k * 10))
	end
end

local function dulce(c)
	local P, gy, rng = c.parent, c.gy, c.rng
	local pink = { rgb(255, 150, 190), rgb(255, 110, 160) }
	local strawberry = { rgb(255, 196, 214), rgb(255, 176, 202) }
	local cream = { rgb(255, 250, 240), rgb(255, 236, 216) }
	local choc = { rgb(120, 72, 44), rgb(92, 52, 34) }
	local red, mint, cherry = rgb(232, 48, 62), rgb(60, 200, 150), rgb(220, 30, 60)
	local candy = { rgb(255, 196, 40), rgb(90, 190, 255), rgb(170, 110, 240), rgb(120, 214, 90), rgb(255, 130, 60) }

	-- Suelo: remolinos rosa/blanco y virutas de colores
	scatter(c, 24, function(x, z, k)
		if k % 2 == 0 then
			local d = rng:NextNumber(14, 21)
			decal(c, d, pink[1], x, z, 0)
			decal(c, d * 0.66, WHITE, x, z, 1)
			decal(c, d * 0.33, pink[2], x, z, 2)
		else
			for layer = 0, 2 do tile(c, 3.2, 1, pick(rng, candy), x + rng:NextNumber(-7, 7), z + rng:NextNumber(-7, 7), layer, rng:NextNumber(0, math.pi)) end
		end
	end)
	pebbles(c, 8, candy) -- perlitas de azúcar

	-- Paredes: colinas de nata (fresa detrás, nata blanca delante) con copete y alguna guinda
	along(c, 20, function(z, side, i, step)
		local h = rng:NextNumber(26, 34)
		blob(P, Vector3.new(18, h * 2, step + 12), strawberry[i % 2 + 1], CFrame.new(side * 76, gy, z))
		blob(P, Vector3.new(12, h * 1.1, step + 8), cream[i % 2 + 1], CFrame.new(side * 69.5, gy, z + step / 2))
		blob(P, Vector3.new(8, 7, 8), cream[1], CFrame.new(side * 74, gy + h + 1, z))
		if i % 3 == 0 then ball(P, 4, cherry, Vector3.new(side * 74, gy + h + 5.5, z)) end
	end)

	-- Valla de onzas de chocolate
	along(c, 14, function(z, side, i, step)
		local h = 8 + (i % 2) * 1.5
		part(P, { size = Vector3.new(1.6, h, step - 2), color = choc[i % 2 + 1], cframe = CFrame.new(side * 63, gy + h / 2, z) })
	end)

	-- Bastones de caramelo y piruletas intercalados, clavados en la nata
	along(c, 44, function(z, side, i)
		local colors = if (i + (side + 1) / 2) % 2 == 0 then { red, WHITE } else { mint, WHITE }
		candyCane(P, Vector3.new(side * 66, gy, z), rng:NextNumber(24, 29), 3.4, Vector3.new(0, 0, if i % 2 == 0 then 8 else -8), colors)
	end, 0.25)
	along(c, 44, function(z, side)
		local base = Vector3.new(side * 66, gy, z)
		lollipop(P, base, base + Vector3.new(0, rng:NextNumber(19, 25), 0), rng:NextNumber(12, 16), 2, { pick(rng, candy), WHITE })
	end, -0.25)

	landmarks(c, {
		function(pos) wrappedCandy(P, CFrame.new(pos + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0.2, 0), red, WHITE) end, -- caramelo envuelto tumbado
		function(pos) -- magdalena con nata y guinda
			disc(P, 11, 8, rgb(110, 196, 232), pos + Vector3.new(0, 4, 0))
			disc(P, 11.6, 1.2, rgb(70, 160, 210), pos + Vector3.new(0, 7.6, 0))
			for k = 0, 2 do blob(P, Vector3.new(12 - k * 3.4, 6, 12 - k * 3.4), cream[k % 2 + 1], CFrame.new(pos + Vector3.new(0, 10 + k * 3.8, 0))) end
			ball(P, 3.6, cherry, pos + Vector3.new(0, 21.6, 0))
			rod(P, pos + Vector3.new(0, 23, 0), pos + Vector3.new(1, 26, 0.6), 0.5, choc[2])
		end,
		function(pos, side) lollipop(P, pos + Vector3.new(side * 3, 0, 2), pos + Vector3.new(side * 2, 24, 0), 20, 4, { pink[2], WHITE }) end, -- piruleta gigante
		function(pos, side) -- tableta de chocolate a medio desenvolver, apoyada en la valla
			local cf = CFrame.lookAt(pos + Vector3.new(-side * 2, 0, 0), pos + Vector3.new(side * 5.5, 20, 0))
			part(P, { size = Vector3.new(13, 2, 22), color = choc[2], cframe = cf * CFrame.new(0, 0, -11) })
			for i = 0, 3 do
				part(P, { size = Vector3.new(5.4, 1, 5.4), color = choc[1], cframe = cf * CFrame.new((i % 2 - 0.5) * 6.2, 1.2, -12.3 - math.floor(i / 2) * 6.4) })
			end
			part(P, { size = Vector3.new(13.6, 2.8, 9), color = rgb(90, 190, 255), cframe = cf * CFrame.new(0, 0, -4.5) })
		end,
		function(pos, side) wrappedCandy(P, CFrame.new(pos + Vector3.new(side, 11.5, 0)) * CFrame.Angles(math.rad(55), 0, 0), candy[3], WHITE) end, -- caramelo envuelto de pie
	})

	-- Gominolas delante de la valla, con brillo de azúcar (se saltan donde hay un hito)
	along(c, 30, function(z, side)
		if not free(c, z, side, 14) then return end
		local s = rng:NextNumber(5.5, 8)
		local center = Vector3.new(side * 56, gy, z + rng:NextNumber(-3, 3))
		blob(P, Vector3.new(s, s * 1.5, s), pick(rng, candy), CFrame.new(center))
		spot(P, center, Vector3.new(s / 2, s * 0.75, s / 2), Vector3.new(-side, 1.4, 0.5), s * 0.3, WHITE)
	end)
end

-- ── Espacio ──
local function planet(parent, center: Vector3, d, colors, side, rng: Random)
	local ring = CFrame.new(center) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, math.rad(90) + rng:NextNumber(-0.35, 0.35))
	ball(parent, d, colors[1], center)
	part(parent, { shape = CYLINDER, size = Vector3.new(0.7, d * 1.7, d * 1.7), color = colors[2], cframe = ring })
	for _ = 1, 2 do
		spot(parent, center, Vector3.one * d / 2, Vector3.new(-side, rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.7, 0.7)), d * rng:NextNumber(0.2, 0.32), colors[2])
	end
	ball(parent, d * 0.22, colors[2], center + Vector3.new(-side * d * 0.3, d * 0.75, d * 0.8)) -- luna
end

local function espacio(c)
	local P, gy, rng = c.parent, c.gy, c.rng
	local navy = { rgb(16, 20, 54), rgb(24, 28, 72) }
	local greys = { rgb(176, 180, 192), rgb(140, 146, 164), rgb(108, 114, 136) }
	local starColors = { rgb(255, 244, 170), WHITE }
	local rocketRed = rgb(236, 60, 70)

	-- Suelo lunar: cráteres con borde claro
	scatter(c, 24, function(x, z)
		local d = rng:NextNumber(11, 22)
		decal(c, d, greys[1], x, z, 0)
		decal(c, d - 3, greys[3], x, z, 1)
		decal(c, d * 0.42, greys[2], x + d * 0.12, z - d * 0.1, 2)
	end)
	pebbles(c, 8, greys)

	-- Paneles estrellados de 40 de alto, franja alta hasta el techo y techo en groundY + 55
	backdrop(c, 74, 40, navy, 40, 0)
	for side = -1, 1, 2 do part(P, { name = "Backdrop", size = Vector3.new(2, 16, c.len), color = rgb(44, 30, 96), cframe = CFrame.new(side * 74, gy + 48, c.zc) }) end
	part(P, { name = "Ceiling", size = Vector3.new(156, 2, c.len), color = navy[1], cframe = CFrame.new(0, gy + 56, c.zc) })

	-- Nebulosas pintadas en la pared
	along(c, 40, function(z, side, i)
		local cframe = CFrame.new(side * 72.9, gy + rng:NextNumber(14, 34), z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, 0)
		blob(P, Vector3.new(1, rng:NextNumber(12, 20), rng:NextNumber(30, 44)), if i % 2 == 0 then rgb(70, 40, 130) else rgb(104, 46, 140), cframe, { shadow = false })
	end, 0.25)

	-- Estrellas de neón en paredes y techo (máximo 90)
	for i = 1, math.min(90, math.floor(c.len / 2.4)) do
		local z = rng:NextNumber(c.z1 + 2, c.z0 - 2)
		local wall = if i % 3 == 1 then -72.2 else 72.2
		local pos = if i % 3 == 0 then Vector3.new(rng:NextNumber(-70, 70), gy + 54.7, z) else Vector3.new(wall, gy + rng:NextNumber(5, 53), z)
		ball(P, rng:NextNumber(0.7, 1.8), starColors[i % 2 + 1], pos, { name = "Star", material = NEON, shadow = false })
	end

	-- Horizonte lunar al pie de cada pared
	along(c, 14, function(z, side, i, step)
		blob(P, Vector3.new(12, rng:NextNumber(14, 26), step + 9), greys[i % 3 + 1], CFrame.new(side * rng:NextNumber(68, 71), gy, z))
	end)

	local function cheese(pos: Vector3, side, s)
		local center = pos + Vector3.new(side * 2, s * 0.32, 0)
		local radii = Vector3.new(s * 0.55, s * 0.4, s * 0.5)
		blob(P, radii * 2, rgb(255, 214, 70), CFrame.new(center))
		for k = 1, 4 do spot(P, center, radii, Vector3.new(-side, rng:NextNumber(0, 0.9), (k - 2.5) * 0.55), s * rng:NextNumber(0.14, 0.22), rgb(232, 170, 40)) end
	end

	landmarks(c, {
		function(pos, side) -- cohete despegando
			local p = pos + Vector3.new(side * 2, 10, 0)
			local window = CFrame.new(p + Vector3.new(-side * 3.8, 9, 0))
			blob(P, Vector3.new(5, 9, 5), rgb(255, 140, 40), CFrame.new(p + Vector3.new(0, -3.5, 0)), { shadow = false })
			blob(P, Vector3.new(3, 7, 3), rgb(255, 226, 90), CFrame.new(p + Vector3.new(0, -6.5, 0)), { shadow = false })
			disc(P, 5, 2, greys[2], p)
			disc(P, 8, 15, rgb(244, 246, 252), p + Vector3.new(0, 8.5, 0))
			disc(P, 8.4, 2, rocketRed, p + Vector3.new(0, 13.5, 0))
			blob(P, Vector3.new(8, 13, 8), rocketRed, CFrame.new(p + Vector3.new(0, 16, 0)))
			part(P, { shape = CYLINDER, size = Vector3.new(1, 4, 4), color = greys[2], cframe = window })
			part(P, { shape = CYLINDER, size = Vector3.new(1.3, 2.8, 2.8), color = rgb(90, 190, 255), cframe = window })
			for k = 0, 2 do
				local fin = CFrame.new(p + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, k * math.rad(120) + 0.5, 0) * CFrame.new(0, 0, -6)
				part(P, { wedge = true, size = Vector3.new(1.2, 7, 4.5), color = rocketRed, cframe = fin })
			end
		end,
		function(pos, side) cheese(pos, side, 12) end, -- roca de queso lunar
		function(pos, side) -- ovni con rayo
			local p = pos + Vector3.new(side * 2, 19, 0)
			disc(P, 7, 17, rgb(170, 255, 190), p + Vector3.new(0, -10.5, 0), { transparency = 0.6, shadow = false })
			blob(P, Vector3.new(16, 4.6, 16), greys[1], CFrame.new(p))
			blob(P, Vector3.new(9, 4, 9), greys[3], CFrame.new(p + Vector3.new(0, -1.6, 0)))
			blob(P, Vector3.new(8, 7, 8), rgb(120, 220, 255), CFrame.new(p + Vector3.new(0, 1.8, 0)))
			for k = 1, 6 do
				local a = k / 6 * math.pi * 2
				ball(P, 1.5, starColors[1], p + Vector3.new(math.cos(a) * 7.8, 0, math.sin(a) * 7.8), { material = NEON, shadow = false })
			end
		end,
		function(pos, side) cheese(pos, side, 9) end, -- otra roca de queso, más pequeña
	})

	-- Planetas con anillo flotando en las bandas, en el lado contrario al hito más cercano
	local palettes = {
		{ rgb(255, 150, 70), rgb(255, 214, 120) }, { rgb(90, 190, 255), WHITE }, { rgb(190, 120, 255), rgb(255, 170, 220) },
		{ rgb(110, 220, 150), rgb(240, 240, 160) }, { rgb(255, 110, 130), rgb(255, 220, 200) },
	}
	for i, colors in palettes do
		local side = if i % 2 == 1 then 1 else -1
		local center = Vector3.new(side * rng:NextNumber(58, 62), gy + rng:NextNumber(30, 40), c.z0 - (i - 0.5) * c.len / #palettes)
		planet(P, center, rng:NextNumber(11, 16), colors, side, rng)
		table.insert(c.marks, { z = center.Z, side = side })
	end

	-- Asteroides flotando donde no hay hito ni planeta
	along(c, 30, function(z, side)
		if not free(c, z, side, 13) then return end
		local s = rng:NextNumber(4, 7.5)
		local size = Vector3.new(s, s * 0.8, s * 1.1)
		local center = Vector3.new(side * rng:NextNumber(54, 61), gy + rng:NextNumber(10, 30), z)
		blob(P, size, greys[2], CFrame.new(center))
		spot(P, center, size / 2, Vector3.new(-side, 0.3, rng:NextNumber(-0.5, 0.5)), s * 0.3, greys[3])
	end, 0.25)

	-- Lámparas colgadas del techo sobre el eje del pasillo para que la zona no quede a oscuras
	local lamps = math.max(3, math.floor(c.len / 55))
	for i = 1, lamps do
		local pos = Vector3.new(0, gy + 28, c.z0 - (i - 0.5) * c.len / lamps)
		rod(P, pos, Vector3.new(0, gy + 55, pos.Z), 0.3, greys[3], { shadow = false })
		local light = Instance.new("PointLight")
		light.Range = 40
		light.Brightness = 1.2
		light.Color = rgb(255, 236, 200)
		light.Parent = ball(P, 2.4, rgb(255, 236, 190), pos, { name = "Lamp", material = NEON, shadow = false })
	end
end

local THEMES = {
	Picnic = { build = picnic, seed = 101 },
	Jungla = { build = jungla, seed = 202 },
	Mar = { build = mar, seed = 303 },
	Dulce = { build = dulce, seed = 404 },
	Espacio = { build = espacio, seed = 505 },
}

-- area = { x0 = -60, x1 = 60, z0, z1 } con z1 < z0 (la zona avanza hacia -Z). groundY = cara superior del suelo.
-- Construye todo el decorado de una zona dentro de `parent`. Determinista: Random con semilla fija por tema.
function Decor.build(theme: string, parent: Instance, area, groundY: number)
	local entry = THEMES[theme]
	if not entry then
		warn("[Decor] Tema desconocido: " .. tostring(theme))
		return
	end
	local z0, z1 = math.max(area.z0, area.z1), math.min(area.z0, area.z1)
	entry.build({ parent = parent, gy = groundY, z0 = z0, z1 = z1, len = z0 - z1, zc = (z0 + z1) / 2, rng = Random.new(entry.seed), marks = {} })
end

return Decor
