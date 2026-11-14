-- Decorado temático por zona (parte 2): Huerto, Cocina, Nevera y Feria.
-- Solo Parts de color plano; el contorno de tinta lo pone quien llama con un Highlight en `parent`.
-- El centro del camino queda libre (solo detalles planos); lo alto vive en las bandas laterales
-- y forma un muro continuo a cada lado para que no se vea el vacío.

local Decor2 = {}
Decor2.Themes = { Huerto = true, Cocina = true, Nevera = true, Feria = true }

local PI = math.pi
local V3 = Vector3.new
local ANG = CFrame.Angles
local INK = Color3.fromRGB(20, 16, 16)
local SEEDS = { Huerto = 4101, Cocina = 4202, Nevera = 4303, Feria = 4404 }
local AXIS = { x = CFrame.identity, y = ANG(0, 0, PI / 2), z = ANG(0, PI / 2, 0) }
-- Cuñas boca abajo vistas desde el camino: la punta queda en +x o en -x del marco local
local DOWN_R = ANG(0, PI / 2, 0) * ANG(0, 0, PI)
local DOWN_L = ANG(0, -PI / 2, 0) * ANG(0, 0, PI)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function part(parent: Instance, props): Part
	local p = if props.wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.CanCollide = props.collide == true
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
local function disc(parent, diameter, height, color, position, extra)
	local props = extra or {}
	props.size = V3(height, diameter, diameter)
	props.color = color
	props.cframe = CFrame.new(position) * ANG(0, 0, math.rad(90))
	props.shape = Enum.PartType.Cylinder
	return part(parent, props)
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

-- Detalles planos de suelo: `top` es cuánto asoman sobre el suelo (máx. 0.12)
local function flat(c, x, t, sx, sz, color, top)
	return part(c.parent, { size = V3(sx, 0.2, sz), color = color, cframe = CFrame.new(c.cx + x, c.gy + (top or 0.06) - 0.1, c.z0 - t), shadow = false })
end

local function spot(c, x, t, diameter, color, top)
	return disc(c.parent, diameter, 0.2, color, V3(c.cx + x, c.gy + (top or 0.08) - 0.1, c.z0 - t), { shadow = false })
end

-- Miguitas / piedrecitas diminutas repartidas por el centro
local function bits(c, count, colors, sMin, sMax)
	local r = c.rng
	for _ = 1, count do
		local s = r:NextNumber(sMin, sMax)
		local cframe = CFrame.new(c.cx + r:NextNumber(-48, 48), c.gy + s * 0.2, c.z0 - r:NextNumber(4, c.len - 4)) * ANG(0, r:NextNumber(0, 6), 0)
		part(c.parent, { size = V3(s * 1.3, s * 0.7, s), color = colors[r:NextInteger(1, #colors)], cframe = cframe, blob = true, shadow = false })
	end
end

-- Recorre los huecos de ambos laterales: `marks[side][i]` es un hito único; si no hay, va `filler`.
local function slots(c, d, lift, marks, filler)
	for _, side in { 1, -1 } do
		for i = 1, c.n do
			local f = frame(c, side, d, (i - 0.5) * c.step, c.rng:NextNumber(-0.1, 0.1)) * CFrame.new(0, lift, 0)
			local build = marks[side][i] or filler
			build(f, side, i)
		end
	end
end

-- HUERTO: valla de madera + seto, bancal con zanahorias, tomateras y lechugas
local function huerto(c)
	local m, r, W = c.parent, c.rng, c.half
	local wood = { rgb(196, 140, 84), rgb(176, 120, 70), rgb(212, 158, 98) }
	local leaf = { rgb(62, 166, 70), rgb(96, 196, 78), rgb(44, 140, 64) }
	local soilDark = rgb(92, 58, 38)

	for i = 1, math.floor(c.len / 10) do
		flat(c, 0, (i - 0.5) * 10 + r:NextNumber(-0.6, 0.6), 2 * W, r:NextNumber(2.6, 3.6), soilDark, 0.05)
	end
	bits(c, 10, { rgb(172, 164, 156), rgb(124, 80, 52) }, 0.9, 1.7)
	for _ = 1, 6 do -- brotes
		local f = CFrame.new(c.cx + r:NextNumber(-46, 46), c.gy, c.z0 - r:NextNumber(6, c.len - 6)) * ANG(0, r:NextNumber(0, 6), 0)
		ball(m, f, -0.45, 0.7, 0, 0.5, 1.5, 0.9, leaf[2], ANG(0, 0, 0.5), true)
		ball(m, f, 0.45, 0.7, 0, 0.5, 1.5, 0.9, leaf[1], ANG(0, 0, -0.5), true)
	end

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 18, W + 12, c.len, 36, 6, rgb(40, 124, 62), nil, true) -- seto de fondo
		box(m, wf, 0, 0.5, W - 1, c.len, 1.6, 14, soilDark, nil, true) -- bancal (tapa el hueco hasta la valla)
		box(m, wf, 0, 8, W + 5.4, c.len, 1.8, 0.8, rgb(150, 98, 58))
		box(m, wf, 0, 20, W + 5.4, c.len, 1.8, 0.8, rgb(150, 98, 58))
		for k = 1, math.ceil(c.n / 2) do
			ball(m, wf, (k - 0.5) * 2 * c.step - c.len / 2 + r:NextNumber(-4, 4), 33, W + 12, c.step * 2.2, r:NextNumber(10, 13), 9, rgb(52, 142, 66), nil, true)
		end
		local pw = c.step / 3
		for k = 1, c.n * 3 do -- tablas con punta
			local h, tone = r:NextNumber(24, 30), wood[r:NextInteger(1, 3)]
			local pf = wf * CFrame.new((k - 0.5) * pw - c.len / 2, 0, W + 6.4) * ANG(0, 0, r:NextNumber(-0.03, 0.03))
			box(m, pf, 0, h / 2, 0, pw - 0.6, h, 1.2, tone)
			box(m, pf, 0, h, 0, (pw - 0.6) * 0.707, (pw - 0.6) * 0.707, 1.2, tone, ANG(0, 0, PI / 4))
		end
	end

	local function fronds(f, count, y, hMin, hMax, wide, tilt)
		for k = 1, count do
			local h = r:NextNumber(hMin, hMax)
			local lf = f * CFrame.new(0, y, 0) * ANG(0, k / count * PI * 2 + r:NextNumber(-0.3, 0.3), 0) * ANG(tilt + r:NextNumber(-0.08, 0.08), 0, 0)
			ball(m, lf, 0, h / 2, 0, wide, h, wide * 0.4, leaf[k % 3 + 1])
		end
	end
	local function carrot(f, s)
		cyl(m, f, 0, 1.2 * s, 0, 7 * s, 3 * s, rgb(255, 136, 32))
		ball(m, f, 0, 2.7 * s, 0, 7 * s, 3.4 * s, 7 * s, rgb(255, 162, 58))
		fronds(f, 3, 3.6 * s, 11 * s, 16 * s, 3.4 * s, 0.3)
	end
	local function tomato(f)
		box(m, f, 0, 13, 1.5, 1, 26, 1, wood[2]) -- estaca
		cyl(m, f, 0.4, 11, 0, 1.3, 22, leaf[3])
		for k = 1, 3 do
			local y, sgn, d = 5 + k * 5.2, (if k % 2 == 0 then 1 else -1), r:NextNumber(4.4, 5.8)
			ball(m, f, sgn * 3.6, y + 1.5, 0, 7, 1.4, 4, leaf[k], ANG(0, 0, sgn * 0.45))
			ball(m, f, -sgn * 3.2, y - 1, -1.5, d, d * 0.9, d, if k == 3 then rgb(255, 150, 60) else rgb(232, 48, 52))
			ball(m, f, -sgn * 3.2, y - 1 + d * 0.45, -1.5, d * 0.5, d * 0.14, d * 0.5, leaf[3])
		end
	end
	local function lettuce(f, s)
		ball(m, f, 0, 3.6 * s, 0, 8 * s, 7 * s, 8 * s, rgb(196, 236, 116))
		for k = 1, 6 do
			local lf = f * ANG(0, k / 6 * PI * 2 + r:NextNumber(-0.2, 0.2), 0) * CFrame.new(0, 3.2 * s, 3.4 * s) * ANG(0.5, 0, 0)
			ball(m, lf, 0, 0, 0, 8.5 * s, 7.5 * s, 2.6 * s, if k % 2 == 0 then rgb(120, 204, 84) else rgb(150, 218, 96))
		end
	end
	local planted = 0
	local function crop(f)
		planted += 1
		if planted % 3 == 1 then
			carrot(f * CFrame.new(-4.8, 0, r:NextNumber(-1, 1)), r:NextNumber(0.9, 1.2))
			carrot(f * CFrame.new(4.8, 0, r:NextNumber(-1, 1)), r:NextNumber(0.9, 1.2))
		elseif planted % 3 == 2 then
			tomato(f)
		else
			lettuce(f, r:NextNumber(1.4, 1.7))
		end
	end

	local function wateringCan(f)
		local blue, dark = rgb(64, 176, 214), rgb(40, 132, 180)
		cyl(m, f, -2, 8, 0, 12, 16, blue)
		cyl(m, f, -2, 15.6, 0, 12.8, 1.4, dark)
		cyl(m, f, -2, 0.8, 0, 12.8, 1.6, dark)
		rod(m, f, V3(3, 4, 0), V3(11, 15, 0), 2.6, blue)
		rod(m, f, V3(11, 15, 0), V3(12.4, 17, 0), 5.4, dark) -- alcachofa
		rod(m, f, V3(-7, 14, 0), V3(-12.5, 12.5, 0), 1.6, dark)
		rod(m, f, V3(-12.5, 12.5, 0), V3(-12.5, 5.5, 0), 1.6, dark)
		rod(m, f, V3(-12.5, 5.5, 0), V3(-7, 4, 0), 1.6, dark)
		ball(m, f, 14.2, 15, 0, 1.6, 2.6, 1.6, rgb(120, 210, 255))
		ball(m, f, 15.6, 11.5, 0.6, 1.8, 3, 1.8, rgb(120, 210, 255))
	end
	local function gnome(f)
		local coat, red = rgb(52, 120, 220), rgb(226, 52, 56)
		ball(m, f, 0, 5.5, 0, 9.5, 11, 8.5, coat)
		for k = -1, 1, 2 do
			ball(m, f, k * 2.3, 1, -2.4, 3.6, 2.2, 5, rgb(70, 50, 44))
			ball(m, f, k * 4.8, 7, 0, 2.6, 6.5, 2.8, rgb(40, 100, 200), ANG(0, 0, k * 0.3))
			ball(m, f, k * 1.3, 13.5, -2.75, 0.8, 0.9, 0.6, INK)
		end
		ball(m, f, 0, 12.6, 0, 6.4, 6.2, 6.2, rgb(255, 206, 170))
		ball(m, f, 0, 10.4, -2.2, 6.6, 6.5, 3.6, rgb(255, 255, 255)) -- barba
		ball(m, f, 0, 12.4, -3.3, 2, 1.8, 2, rgb(255, 150, 140))
		for k = 0, 2 do -- gorro escalonado
			cyl(m, f, 0, 16 + k * 2.8, 0, 6.6 - k * 2, 3, if k == 1 then rgb(196, 36, 48) else red)
		end
		ball(m, f, 0, 23.4, 0, 1.8, 1.8, 1.8, rgb(255, 255, 255))
	end
	local function clayPot(f)
		cyl(m, f, 0, 4.2, 0, 11, 8.4, rgb(204, 100, 58))
		cyl(m, f, 0, 9.4, 0, 13.6, 2.8, rgb(226, 122, 72))
		cyl(m, f, 0, 10.9, 0, 11.6, 0.4, soilDark)
		fronds(f, 5, 10.6, 9, 14, 4.4, 0.42)
	end
	local function hose(f) -- rollo colgado de la valla
		local g1, g2 = rgb(52, 168, 96), rgb(110, 214, 120)
		box(m, f, 0, 22.4, 6, 2.2, 2.2, 3.4, wood[2])
		cyl(m, f, 0, 14.5, 5.6, 17, 2.6, g1, "z")
		cyl(m, f, 0, 14.5, 5.2, 12, 2.8, g2, "z")
		cyl(m, f, 0, 14.5, 4.8, 6.5, 3, rgb(60, 40, 30), "z")
		rod(m, f, V3(6.5, 9, 4.4), V3(8, 0.6, 2), 1.8, g1)
		rod(m, f, V3(8, 0.6, 2), V3(13, 0.6, -2.5), 1.8, g1)
		rod(m, f, V3(13, 0.6, -2.5), V3(15, 1, -4.2), 2.4, rgb(250, 200, 60))
	end
	local function seedSign(f)
		box(m, f, 0, 8, 0.6, 1.2, 16, 1.2, wood[2])
		local pf = f * CFrame.new(0, 18, 0) * ANG(0, 0, 0.07)
		box(m, pf, 0, 0, 0, 11, 14, 0.8, rgb(255, 244, 214))
		box(m, pf, 0, 5.4, -0.1, 11, 3.2, 0.9, rgb(232, 60, 60))
		ball(m, pf, 0, -1.8, -0.5, 3.2, 6.4, 0.6, rgb(255, 136, 32), nil, true)
		ball(m, pf, 0, 2.2, -0.5, 4.6, 2.6, 0.6, leaf[1], nil, true)
	end
	local function pumpkin(f)
		ball(m, f, -4, 5, 0, 8, 10, 11, rgb(238, 116, 20))
		ball(m, f, 0, 5.3, 0, 9, 10.6, 12, rgb(255, 140, 26))
		ball(m, f, 4, 5, 0, 8, 10, 11, rgb(238, 116, 20))
		cyl(m, f, 0.3, 11.2, 0, 1.8, 3, rgb(110, 140, 50))
		ball(m, f, 3.4, 10.6, 0, 5, 1, 3.4, leaf[2], ANG(0, 0, 0.25))
	end

	slots(c, W - 2, 1.3, {
		[1] = { [2] = wateringCan, [5] = clayPot, [8] = pumpkin },
		[-1] = { [3] = gnome, [6] = hose, [9] = seedSign },
	}, crop)
end

-- COCINA: salpicadero de azulejos a dos tonos, barra con utensilios colgados y menaje gigante
local function cocina(c)
	local m, r, W = c.parent, c.rng, c.half
	local steel, steelDark, black, white = rgb(206, 214, 224), rgb(150, 160, 176), rgb(44, 40, 46), rgb(255, 255, 255)
	local wood = { rgb(214, 160, 100), rgb(180, 122, 72) }
	local enamel = { rgb(232, 60, 62), rgb(60, 150, 230), rgb(255, 196, 40), rgb(70, 190, 120), rgb(255, 130, 50) }
	local grout = rgb(198, 182, 160)

	for i = 1, c.n do
		flat(c, 0, (i - 0.5) * c.step, 2 * W, 0.6, grout, 0.05)
	end
	for x = -40, 40, 20 do
		flat(c, x, c.len / 2, 0.6, c.len, grout, 0.05)
	end
	for _ = 1, 5 do -- harina
		spot(c, r:NextNumber(-44, 44), r:NextNumber(8, c.len - 8), r:NextNumber(5, 10), white, 0.08)
	end
	bits(c, 12, { rgb(226, 172, 104), rgb(176, 116, 66) }, 0.6, 1.3)

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 16, W + 7, c.len, 32, 4, rgb(70, 190, 186), nil, true)
		box(m, wf, 0, 35, W + 5, c.len, 6, 8, wood[2], nil, true) -- bajo del armario
		box(m, wf, 0, -0.35, W + 2.6, c.len, 1, 6, rgb(226, 212, 188), nil, true) -- encimera hasta la pared
		cyl(m, wf, 0, 28, W + 3, 0.9, c.len, steelDark, "x") -- barra
		local tw = c.step / 2
		for col = 1, c.n * 2 do
			for row = 1, 4 do
				if (col + row) % 2 == 0 then
					box(m, wf, (col - 0.5) * tw - c.len / 2, (row - 0.5) * 8, W + 4.9, tw - 0.5, 7.5, 0.4, rgb(244, 250, 246), nil, true)
				end
			end
		end
		for i = 1, c.n - 1 do -- cucharones y espátulas colgando entre hueco y hueco
			local hf = wf * CFrame.new(i * c.step - c.len / 2, 28, W + 3) * ANG(0, 0, r:NextNumber(-0.08, 0.08))
			local tint = enamel[(i + side + 1) % 5 + 1]
			ball(m, hf, 0, 0, 0, 1.6, 1.6, 1.6, steelDark)
			if i % 2 == 0 then
				box(m, hf, 0, -6.5, 0, 1, 12, 0.5, tint)
				ball(m, hf, 0, -14, -0.6, 6, 4.6, 3.4, steel)
			else
				box(m, hf, 0, -5, 0, 1.1, 9, 0.6, tint)
				box(m, hf, 0, -13.2, 0, 5, 7.6, 0.4, steel)
			end
		end
	end

	local function pot(f)
		local tint, s = enamel[r:NextInteger(1, 5)], r:NextNumber(1, 1.45)
		cyl(m, f, 0, 5 * s, 0, 12 * s, 10 * s, tint)
		cyl(m, f, 0, 10 * s, 0, 12.8 * s, 0.9 * s, steel)
		ball(m, f, 0, 10.6 * s, 0, 11.4 * s, 3.4 * s, 11.4 * s, steelDark)
		ball(m, f, 0, 12.8 * s, 0, 2.2 * s, 1.8 * s, 2.2 * s, black)
		box(m, f, -7 * s, 8 * s, 0, 2.6 * s, s, 3.2 * s, black)
		box(m, f, 7 * s, 8 * s, 0, 2.6 * s, s, 3.2 * s, black)
	end
	local function pan(f) -- apoyada en la pared
		local pf = f * CFrame.new(0, 0, 3.2) * ANG(0.12, 0, r:NextNumber(-0.2, 0.2))
		cyl(m, pf, 0, 8.5, 0, 17, 2, black, "z")
		cyl(m, pf, 0, 8.5, -0.3, 14.4, 2, enamel[r:NextInteger(1, 5)], "z")
		box(m, pf, 0, 22, 0.2, 2.2, 11, 1.2, black)
		cyl(m, pf, 0, 26, 0.2, 1.2, 1.4, steel, "z")
	end
	local function jars(f)
		for k = -1, 1, 2 do
			local s, tint = r:NextNumber(0.9, 1.3), enamel[r:NextInteger(1, 5)]
			local jf = f * CFrame.new(k * 4.6, 0, r:NextNumber(-1, 2))
			cyl(m, jf, 0, 4.5 * s, 0, 7 * s, 9 * s, rgb(250, 240, 220))
			cyl(m, jf, 0, 9.7 * s, 0, 7.5 * s, 1.6 * s, tint)
			box(m, jf, 0, 4.6 * s, -3.4 * s, 4.4 * s, 3.6 * s, 0.4, tint, nil, true)
		end
	end
	local fillers, filled = { pot, jars, pan }, 0
	local function filler(f)
		fillers[filled % 3 + 1](f)
		filled += 1
	end

	local function knifeBlock(f)
		local kf = f * CFrame.new(0, 0, 1) * ANG(0.25, 0, 0)
		box(m, kf, 0, 6.5, 0, 11, 13, 7.5, wood[2])
		box(m, kf, 0, 13.2, 0, 11.2, 0.6, 7.7, wood[1])
		for k = 1, 5 do
			local h = 3.5 + (k % 3) * 1.4
			box(m, kf, (k - 3) * 1.9, 13.4 + h / 2, if k % 2 == 0 then 1.4 else -1.4, 1.3, h, 1.8, black)
		end
	end
	local function toaster(f)
		box(m, f, 0, 0.6, 0, 15, 1.2, 8.4, black)
		box(m, f, 0, 6.2, 0, 16, 10, 9, enamel[1])
		cyl(m, f, 0, 11.2, 0, 9, 16, enamel[1], "x")
		for k = -1, 1, 2 do
			box(m, f, 0, 15.4, k * 2, 12.5, 0.5, 1.7, black, nil, true)
			box(m, f, k * 0.6, 17.5 + (k + 1) * 0.9, k * 2, 9, 8, 1.2, rgb(232, 178, 104), ANG(0, 0, k * 0.06)) -- tostada saltando
		end
		box(m, f, 8.4, 8, 0, 1.2, 2.2, 2.6, black)
		cyl(m, f, -5, 4.6, -4.6, 2.6, 0.8, steel, "z")
		box(m, f, 0, 9.6, -4.6, 16.1, 0.8, 0.3, steel, nil, true)
	end
	local function shakers(f)
		for k = -1, 1, 2 do
			local sf = f * CFrame.new(k * 4.4, 0, 0)
			cyl(m, sf, 0, 5.5, 0, 6.4, 11, if k < 0 then white else rgb(70, 64, 70))
			cyl(m, sf, 0, 5, 0, 6.7, 3, if k < 0 then enamel[2] else enamel[1])
			ball(m, sf, 0, 11, 0, 6.6, 4.4, 6.6, steel)
			for h = -1, 1 do
				ball(m, sf, h * 1.3, 13, if h == 0 then -0.8 else 0.5, 0.7, 0.5, 0.7, black, nil, true)
			end
		end
	end
	local function rollingPin(f) -- apoyado en diagonal
		local pf = f * CFrame.new(-6, 1, 4) * ANG(0, 0, math.rad(62))
		cyl(m, pf, 13, 0, 0, 6, 18, wood[1], "x")
		cyl(m, pf, 1.6, 0, 0, 2.4, 5, wood[2], "x")
		cyl(m, pf, 24.4, 0, 0, 2.4, 5, wood[2], "x")
		cyl(m, f, 0, 0.03, -2, 11, 0.16, white, "y", true)
	end
	local function plates(f)
		for k = 0, 5 do
			cyl(m, f, r:NextNumber(-0.4, 0.4), 0.7 + k * 1.3, r:NextNumber(-0.4, 0.4), 15 - k % 2, 1.3, if k % 2 == 0 then white else rgb(120, 190, 240))
		end
		cyl(m, f, 0, 10.15, 0.5, 5.6, 4.6, enamel[3]) -- taza
		ball(m, f, 3.4, 10.2, 0.5, 2.6, 3, 1, enamel[3])
		local pf = f * CFrame.new(-9.5, 0, 4.5) * ANG(0.16, 0, 0)
		cyl(m, pf, 0, 7, 0, 13, 1, white, "z")
		cyl(m, pf, 0, 7, -0.2, 8.5, 1, rgb(120, 190, 240), "z")
	end
	local function cuttingBoard(f)
		local bf = f * CFrame.new(0, 0, 3.2) * ANG(0.14, 0, 0.05)
		box(m, bf, 0, 11, 0, 15, 22, 1.6, wood[1])
		box(m, bf, 0, 15.5, -0.1, 15, 1.6, 1.7, wood[2])
		cyl(m, bf, 0, 19.5, 0, 2.6, 1.8, black, "z")
		local kf = f * CFrame.new(5.5, 0, 0.8) * ANG(0.2, 0, -0.3)
		box(m, kf, 0, 6, 0, 2.8, 12, 0.4, steel)
		box(m, kf, 0, 15, 0, 2.2, 6, 1.1, black)
		wedge(m, f, -4.5, 2.5, -2.5, 6, 5, 7, rgb(255, 210, 60)) -- queso
	end
	local function kettle(f)
		local tint = enamel[3]
		cyl(m, f, 0, 0.6, 0, 12.6, 1.2, black)
		cyl(m, f, 0, 4, 0, 12, 6, tint)
		ball(m, f, 0, 7, 0, 12, 10, 12, tint)
		cyl(m, f, 0, 12, 0, 5, 0.8, steel)
		ball(m, f, 0, 13, 0, 1.9, 1.9, 1.9, black)
		rod(m, f, V3(4.6, 6, 0), V3(10, 11, 0), 2.3, tint)
		rod(m, f, V3(-4.6, 10.4, 0), V3(-4, 16, 0), 1.3, black)
		rod(m, f, V3(-4, 16, 0), V3(3.6, 16, 0), 1.3, black)
		rod(m, f, V3(3.6, 16, 0), V3(4.2, 10.6, 0), 1.3, black)
		ball(m, f, 11.6, 13.6, 0, 2.6, 2.2, 2.2, white, nil, true) -- vapor
		ball(m, f, 13.4, 16.4, 0, 3.6, 3, 3, white, nil, true)
	end

	slots(c, W - 2, 0, {
		[1] = { [2] = knifeBlock, [4] = toaster, [6] = rollingPin, [8] = kettle },
		[-1] = { [3] = shakers, [5] = plates, [7] = cuttingBoard },
	}, filler)
end

-- NEVERA: paredes blancas con guías, balda de cristal con carámbanos y comida fría
local function nevera(c)
	local m, r, W = c.parent, c.rng, c.half
	local white, ice, rail = rgb(240, 247, 252), rgb(170, 226, 250), rgb(186, 208, 226)
	local frost = rgb(250, 254, 255)

	for i = 1, math.floor(c.len / 12.5) do -- juntas de la balda de cristal
		flat(c, 0, (i - 0.5) * 12.5, 2 * W, 0.7, rgb(226, 246, 255), 0.05)
	end
	flat(c, -W + 9, c.len / 2, 1.2, c.len, rgb(226, 246, 255), 0.06)
	flat(c, W - 9, c.len / 2, 1.2, c.len, rgb(226, 246, 255), 0.06)
	for _ = 1, 8 do -- escarcha
		local x, t, d = r:NextNumber(-42, 42), r:NextNumber(10, c.len - 10), r:NextNumber(7, 13)
		spot(c, x, t, d, frost, 0.09)
		spot(c, x + d * 0.45, t + d * 0.3, d * 0.6, frost, 0.09)
	end
	bits(c, 6, { ice, frost }, 0.7, 1.3)

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 19, W + 7, c.len, 38, 4, white, nil, true)
		box(m, wf, 0, -0.35, W + 2.6, c.len, 1, 6, rgb(226, 246, 255), nil, true) -- suelo hasta la pared
		for _, y in { 8, 16, 24 } do
			box(m, wf, 0, y, W + 4.6, c.len, 1.2, 1.2, rail, nil, true)
		end
		box(m, wf, 0, 30, W - 1, c.len, 1, 12, ice, nil, true).Transparency = 0.45 -- balda superior
		box(m, wf, 0, 30, W - 7.2, c.len, 2.2, 1, rgb(120, 190, 230), nil, true)
		for i = 1, c.n - 1 do
			box(m, wf, i * c.step - c.len / 2, 15, W + 4.8, 1.4, 30, 0.8, rail, nil, true)
		end
		for i = 1, c.n do
			local x0 = (i - 1) * c.step - c.len / 2
			for k = 1, 4 do -- carámbanos bajo el canto de la balda
				local h, w = r:NextNumber(3, 8.5), r:NextNumber(1.6, 2.8)
				wedge(m, wf, x0 + (k - 0.5) * c.step / 4 + r:NextNumber(-1.2, 1.2), 28.9 - h / 2, W - 7.2, 0.8, h, w, if k % 2 == 0 then ice else rgb(214, 242, 255), if r:NextNumber() < 0.5 then DOWN_R else DOWN_L, true)
			end
			ball(m, wf, x0 + c.step / 2 + r:NextNumber(-4, 4), 0.6, W + 3.5, r:NextNumber(10, 17), r:NextNumber(3, 5.5), 6, frost, nil, true)
		end
		for t = (if side == 1 then 30 else 50), c.len - 10, 60 do -- luz de nevera cada ~60 studs
			local x = side * (t - c.len / 2)
			box(m, wf, x, 27, W + 4.6, 10.4, 3.4, 0.8, rail, nil, true)
			local lamp = box(m, wf, x, 27, W + 4.3, 9, 2.2, 0.8, rgb(226, 244, 255), nil, true)
			lamp.Material = Enum.Material.Neon
			local light = Instance.new("PointLight")
			light.Color = rgb(214, 236, 255)
			light.Range = 45
			light.Brightness = 1.1
			light.Shadows = false
			light.Parent = lamp
		end
	end

	local function milk(f, side)
		local tint = if side == 1 then rgb(60, 140, 230) else rgb(232, 60, 62)
		box(m, f, 0, 8, 0, 11, 16, 10, white)
		box(m, f, 0, 5, 0, 11.2, 5, 10.2, tint)
		wedge(m, f, 0, 18.5, -2.5, 11, 5, 5, white)
		wedge(m, f, 0, 18.5, 2.5, 11, 5, 5, white, ANG(0, PI, 0))
		box(m, f, 0, 21.6, 0, 11, 2, 0.8, tint)
		ball(m, f, -2.4, 11.5, -5, 3.4, 2.6, 0.5, INK, nil, true)
		ball(m, f, 2.6, 13.2, -5, 2.4, 2, 0.5, INK, nil, true)
	end
	local function juice(f, side)
		local tint = if side == 1 then rgb(255, 150, 30) else rgb(150, 70, 190)
		cyl(m, f, 0, 7, 0, 9, 14, tint)
		ball(m, f, 0, 14, 0, 9, 7, 9, tint)
		cyl(m, f, 0, 18.4, 0, 3.6, 4, tint)
		cyl(m, f, 0, 21, 0, 4.6, 2, rgb(60, 180, 90))
		cyl(m, f, 0, 7.5, 0, 9.3, 6, white)
		ball(m, f, 0, 7.5, -4.6, 3.6, 3.6, 0.6, tint, nil, true)
	end
	local function tub(f, side)
		local tint = if side == 1 then rgb(255, 120, 170) else rgb(110, 220, 190)
		cyl(m, f, 0, 5, 0, 13, 10, tint)
		cyl(m, f, 0, 5, 0, 13.3, 3.4, white)
		cyl(m, f, 0, 10.2, 0, 13.8, 0.8, white)
		ball(m, f, -2.6, 12, 0, 6.4, 5.6, 6.4, rgb(255, 170, 200))
		ball(m, f, 2.8, 12, 0.6, 6.4, 5.6, 6.4, rgb(150, 96, 70))
		ball(m, f, 0.2, 15, -0.2, 5.8, 5.2, 5.8, rgb(255, 244, 214))
	end
	local function eggs(f)
		box(m, f, 0, 1.2, 0, 19, 2.4, 12.5, rgb(140, 150, 176))
		for k = 0, 5 do
			ball(m, f, (k % 3 - 1) * 6, 4.9, if k < 3 then -3 else 3, 4.8, 6.2, 4.8, if k % 2 == 0 then rgb(255, 250, 240) else rgb(255, 222, 186))
		end
	end
	local function butter(f)
		box(m, f, 0, 0.6, 0, 17, 1.2, 10, white)
		box(m, f, 1.5, 4.4, 0, 11, 6.4, 7, rgb(255, 214, 70))
		box(m, f, -6, 4.4, 0, 4.4, 6.8, 7.4, rgb(120, 190, 240)) -- envoltorio
		box(m, f, 9.2, 2.2, -0.5, 1.8, 6.4, 7, rgb(255, 226, 110), ANG(0, 0, -1.2)) -- loncha caída
	end
	local function cubes(f)
		for _, s in { { -3.4, 3.6, 0.5, 7.2, 0.2 }, { 4.2, 3.2, 1.5, 6.4, -0.35 }, { 0.4, 9.6, 1, 6, 0.6 }, { 6, 1.8, -4, 3.6, 1 } } do
			box(m, f, s[1], s[2], s[3], s[4], s[4], s[4], ice, ANG(0, s[5] + r:NextNumber(-0.2, 0.2), 0)).Transparency = 0.25
		end
	end
	local jams = { rgb(214, 40, 70), rgb(140, 60, 170), rgb(255, 150, 40), rgb(200, 30, 110) }
	local function jam(f)
		for k = -1, 1, 2 do
			local s, tint = r:NextNumber(1, 1.5), jams[r:NextInteger(1, 4)]
			local jf = f * CFrame.new(k * 5, 0, r:NextNumber(-1, 2))
			cyl(m, jf, 0, 4.2 * s, 0, 7.6 * s, 8.4 * s, tint)
			cyl(m, jf, 0, 9.2 * s, 0, 8 * s, 1.8 * s, if k < 0 then white else rgb(255, 210, 70))
			box(m, jf, 0, 4.4 * s, -3.7 * s, 4.6 * s, 3.6 * s, 0.4, white, nil, true)
		end
	end

	slots(c, W - 2, 0, {
		[1] = { [1] = milk, [3] = cubes, [4] = eggs, [6] = juice, [7] = cubes, [8] = butter, [10] = tub },
		[-1] = { [2] = tub, [3] = juice, [4] = cubes, [5] = butter, [7] = milk, [8] = cubes, [9] = eggs },
	}, jam)
end

-- FERIA: carpas a rayas con festón, banderines, bombillas y atracciones
local function feria(c)
	local m, r, W = c.parent, c.rng, c.half
	local red, redDark, white, yellow = rgb(230, 50, 56), rgb(196, 36, 48), rgb(255, 250, 240), rgb(255, 204, 40)
	local dark = rgb(60, 52, 66)
	local party = { rgb(255, 204, 40), rgb(60, 190, 240), rgb(255, 110, 170), rgb(90, 210, 110), rgb(255, 140, 40), rgb(160, 110, 255) }

	for i = 1, 40 do -- confeti pintado
		spot(c, r:NextNumber(-54, 54), r:NextNumber(3, c.len - 3), r:NextNumber(1.4, 3.6), party[i % 6 + 1], 0.07)
	end
	bits(c, 8, { rgb(255, 244, 196), rgb(255, 226, 140) }, 0.6, 1.1) -- palomitas caídas

	for _, side in { 1, -1 } do
		local wf = frame(c, side, 0, c.len / 2)
		box(m, wf, 0, 12, W + 6, c.len, 24, 2, white, nil, true)
		box(m, wf, 0, -0.35, W + 2.6, c.len, 1, 6, rgb(112, 104, 110), nil, true) -- bordillo hasta la lona
		box(m, wf, 0, 26.5, W + 4.4, c.len, 6, 1.2, yellow, nil, true) -- faldón
		box(m, wf, 0, 33.2, W + 10, c.len, 1.6, 14.4, redDark, ANG(-0.56, 0, 0), true) -- techo
		cyl(m, wf, 0, 17, W + 2.5, 0.35, c.len, dark, "x", true) -- cuerda de banderines
		local hw = c.step / 2
		for k = 1, c.n * 2 do
			local x, tint = (k - 0.5) * hw - c.len / 2, party[k % 6 + 1]
			if k % 2 == 0 then
				box(m, wf, x, 12, W + 5.9, hw, 24, 2, red, nil, true)
			end
			cyl(m, wf, x, 23.5, W + 4.8, hw, 0.8, if k % 2 == 0 then white else red, "z", true) -- festón
			wedge(m, wf, x - 1.25, 14.25, W + 2.5, 0.3, 5.5, 2.5, tint, DOWN_R, true)
			wedge(m, wf, x + 1.25, 14.25, W + 2.5, 0.3, 5.5, 2.5, tint, DOWN_L, true)
			put(m, wf, x + hw / 2, 26.5, W + 3.5, V3(1.5, 1.5, 1.5), party[(k + 2) % 6 + 1], nil, "ball", true).Material = Enum.Material.Neon
		end
		for j = 1, math.ceil(c.n / 2) do -- mástiles con gallardete
			local x = (j - 0.5) * 2 * c.step - c.len / 2
			cyl(m, wf, x, 37, W + 12, 1.3, 14, white)
			ball(m, wf, x, 44.6, W + 12, 2.2, 2.2, 2.2, yellow)
			wedge(m, wf, x - 3, 41.6, W + 12, 0.3, 3.6, 6, party[(j + side + 1) % 6 + 1], ANG(0, PI / 2, 0), true)
		end
	end

	local function filler(f, side, i)
		if i % 2 == 0 then -- barril
			local x = r:NextNumber(-3, 3)
			cyl(m, f, x, 4, 3, 6.4, 8, party[(i + side + 1) % 6 + 1])
			cyl(m, f, x, 4, 3, 6.7, 1.8, white)
			ball(m, f, x, 8.3, 3, 4.4, 1.6, 4.4, yellow)
		else -- cajas de premios
			box(m, f, -2.2, 2.5, 3, 5, 5, 5, party[(i + 2) % 6 + 1], ANG(0, 0.2, 0))
			box(m, f, 2.8, 2, 2.4, 4, 4, 4, party[(i + 4) % 6 + 1], ANG(0, -0.3, 0))
			box(m, f, -1.4, 6.8, 3, 3.6, 3.6, 3.6, party[i % 6 + 1], ANG(0, 0.6, 0))
		end
	end
	local function wheel(f, side, i) -- noria asomando por detrás de la carpa
		local hub, blue = f * CFrame.new(0, 44, 24), rgb(60, 110, 220)
		for k = 1, 12 do
			local a0, a1 = k / 12 * PI * 2, (k + 1) / 12 * PI * 2
			local p0, p1 = V3(math.cos(a0) * 20, math.sin(a0) * 20, 0), V3(math.cos(a1) * 20, math.sin(a1) * 20, 0)
			rod(m, hub, p0, p1, 1.8, blue)
			if k <= 6 then
				rod(m, hub, p0, -p0, 1, white)
			end
			if k % 2 == 0 then
				box(m, hub, p0.X, p0.Y - 2.6, -1.6, 5, 4.4, 3.4, party[k / 2])
			end
		end
		cyl(m, hub, 0, 0, -0.6, 6, 3, yellow, "z")
		rod(m, hub, V3(0, 0, 1.4), V3(-13, -26, 1.4), 2, rgb(40, 76, 170))
		rod(m, hub, V3(0, 0, 1.4), V3(13, -26, 1.4), 2, rgb(40, 76, 170))
		filler(f, side, i)
	end
	local function popcorn(f)
		box(m, f, 0, 7.5, 0, 14, 8, 8, red)
		box(m, f, -3.5, 7.5, 0, 2.4, 8.1, 8.2, white)
		box(m, f, 3.5, 7.5, 0, 2.4, 8.1, 8.2, white)
		for k = -1, 1, 2 do
			cyl(m, f, k * 5, 3.6, -4.6, 7.2, 1.2, dark, "z")
			cyl(m, f, k * 5, 3.6, -5, 2.6, 1, yellow, "z")
		end
		box(m, f, 0, 15.5, 0, 13, 8, 7.4, rgb(190, 235, 255)).Transparency = 0.5
		for k = -1, 1 do
			ball(m, f, k * 3.6, if k == 0 then 15 else 13.4, 0, 5.4, 4.6, 5, rgb(255, 240, 180))
		end
		box(m, f, 0, 20.4, 0, 16, 1.8, 10, red)
		box(m, f, 0, 22, 0, 10, 1.6, 6, yellow)
		rod(m, f, V3(7, 9.5, 0), V3(11.5, 11.5, 0), 1.2, dark)
	end
	local function balloons(f)
		box(m, f, 0, 1.2, 0, 3.4, 2.4, 3.4, dark)
		for k, s in { { -5, 20, 0 }, { 5, 21.5, 1 }, { 0, 25.5, -1.5 }, { -3.6, 29, 2 }, { 4, 30, 0 }, { 0.5, 19, 3 } } do
			ball(m, f, s[1], s[2], s[3], 6.4, 7.8, 6.4, party[k])
			rod(m, f, V3(0, 2.4, 0), V3(s[1], s[2] - 3.8, s[3]), 0.25, white)
		end
	end
	local function booth(f)
		box(m, f, 0, 8, 1, 12, 16, 9, rgb(60, 130, 230))
		box(m, f, 0, 10.6, -3.6, 7.4, 5.2, 0.5, rgb(40, 40, 70), nil, true) -- ventanilla
		box(m, f, 0, 7.4, -4.4, 9.4, 1, 2.6, white)
		box(m, f, -3.2, 3.5, -3.6, 1.8, 6.8, 0.5, white, nil, true)
		box(m, f, 3.2, 3.5, -3.6, 1.8, 6.8, 0.5, white, nil, true)
		box(m, f, 0, 14.6, -3.7, 9, 2.4, 0.6, yellow, nil, true)
		wedge(m, f, 0, 18.2, -1.75, 14, 4.4, 5.5, red)
		wedge(m, f, 0, 18.2, 3.75, 14, 4.4, 5.5, red, ANG(0, PI, 0))
		ball(m, f, 0, 21, 1, 2, 2, 2, yellow)
	end
	local function horse(f) -- caballito de tiovivo en su barra
		local pink = party[3]
		cyl(m, f, 0, 0.7, 0, 15, 1.4, red)
		cyl(m, f, 0, 1.7, 0, 12, 0.8, yellow)
		cyl(m, f, 0, 14.5, 0, 1.2, 25, yellow)
		ball(m, f, 0, 27.6, 0, 2.6, 2.6, 2.6, red)
		ball(m, f, 0, 11.5, 0, 9.5, 5, 4.2, white)
		ball(m, f, 4.2, 14.4, 0, 3, 6.4, 3, white, ANG(0, 0, -0.5))
		ball(m, f, 6.6, 16.6, 0, 5, 2.8, 2.6, white, ANG(0, 0, -0.5))
		ball(m, f, 3.4, 15.6, 0, 1.6, 6, 1.2, pink, ANG(0, 0, -0.5))
		ball(m, f, -5.2, 11, 0, 2, 5.6, 2, pink, ANG(0, 0, -0.5))
		ball(m, f, -0.4, 13.6, 0, 4.4, 1.8, 4.5, red)
		for k = -1, 1, 2 do
			box(m, f, 3.2, 7.4, k * 1.1, 1.1, 5, 1.1, white, ANG(0, 0, 0.5))
			box(m, f, -3.2, 7.4, k * 1.1, 1.1, 5, 1.1, white, ANG(0, 0, -0.4))
		end
	end
	local function striker(f) -- martillo de fuerza
		box(m, f, 0, 1, 0, 9, 2, 6, red)
		box(m, f, 0, 14.5, 1, 3.6, 26, 1, white)
		for k = 1, 3 do
			box(m, f, 0, 1.5 + k * 6.5, 0.45, 3.7, 1.6, 0.4, party[k], nil, true)
		end
		ball(m, f, 0, 29, 1, 4.6, 4.6, 4.6, yellow)
		box(m, f, 0, 11.5, 0.3, 2.4, 1.3, 0.5, red)
		rod(m, f, V3(4, 0.6, -4), V3(8, 6.6, -2), 0.9, rgb(150, 100, 60))
		rod(m, f, V3(7, 6.8, -3.2), V3(9.2, 6.2, -0.9), 3.2, dark)
	end

	slots(c, W - 2, 0, {
		[1] = { [2] = popcorn, [6] = wheel, [9] = balloons },
		[-1] = { [4] = booth, [7] = horse, [10] = striker },
	}, filler)
end

local BUILDERS = { Huerto = huerto, Cocina = cocina, Nevera = nevera, Feria = feria }

-- area = { x0, x1, z0, z1 } con z1 < z0 (la zona avanza hacia -Z); groundY = cara superior del suelo.
function Decor2.build(theme: string, parent: Instance, area, groundY: number)
	local builder = BUILDERS[theme]
	if not builder then
		warn(`Decor2: tema desconocido "{theme}"`)
		return
	end
	local length = math.abs(area.z0 - area.z1)
	local n = math.max(1, math.floor(length / 20 + 0.5))
	local cx, half = (area.x0 + area.x1) / 2, math.abs(area.x1 - area.x0) / 2
	-- n huecos de ~20 studs por lateral; `step` es su ancho real
	builder({ parent = parent, rng = Random.new(SEEDS[theme]), gy = groundY, cx = cx, half = half, z0 = math.max(area.z0, area.z1), len = length, n = n, step = length / n })
end

return Decor2
