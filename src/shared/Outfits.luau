-- Trajes del vestidor: conjuntos de piezas que se montan sobre la hormiga (ver AntLook).
-- Cada traje ocupa huecos ("head", "face", "body", "back"). Regla de mezcla:
--   head  -> no se dibuja el sombrero del vestidor (salvo "gafas") ni las púas de la cabeza;
--            la corona de enjambre flota por encima de `top`
--   face  -> no se dibujan las "gafas" del vestidor
--   body  -> no se dibujan las placas de armadura ni las púas del tórax (las del abdomen siguen)
--   back  -> no se dibuja la capa de enjambre
-- Los colores de piel, las alas, las mandíbulas, los zapatos y el abdomen siempre se ven.
--
-- `build(k)` recibe el kit de AntLook (se ejecuta solo en el servidor): todo a escala 1, frente -Z.
-- `icon` dibuja la percha del vestidor: { forma, x, y, ancho, alto, color, giro } sobre el torso
-- (46 x 58, origen arriba a la izquierda). Formas: "o" óvalo, "r" rectángulo redondeado, "d" rombo.

local Outfits = {}

local V3, CF, ANG, rad, rgb = Vector3.new, CFrame.new, CFrame.Angles, math.rad, Color3.fromRGB
local UP = ANG(0, 0, math.pi / 2) -- pone de pie un cilindro (su eje es X)

local INK = rgb(30, 26, 32)
local WHITE = rgb(255, 255, 255)
local GOLD = rgb(255, 196, 52)
local RED = rgb(214, 40, 48)
local NAVY = rgb(52, 84, 170)
local STEEL = rgb(120, 126, 140)
local GLASS = rgb(190, 235, 255)

-- Partes del torso que comparten varios trajes: chaqueta sobre las dos jorobas del tórax
local function coat(k, color: Color3)
	if k.thorax then
		k.add(k.thorax, "Coat", V3(1.42, 0.82, 1.38), color, CF(0, 0.24, 0.02), "ball")
	end
	if k.back then
		k.add(k.back, "CoatBack", V3(1.1, 0.66, 1), color, CF(0, 0.18, 0), "ball")
	end
end

-- Nudo bajo la barbilla (pañuelo, corbata), justo por debajo de la cabeza
local function knot(k, color: Color3)
	if k.thorax then
		k.add(k.thorax, "Knot", V3(0.26, 0.22, 0.18), color, CF(0, -0.24, -0.64), "ball")
	end
end

-- Espada envainada tumbada en el lomo: de la punta `a` a la guarda `t` (espacio del tórax)
local function sword(k, a: Vector3, t: Vector3, sheath: Color3, guard: Color3, grip: Color3, square: boolean)
	local th = k.thorax
	if not th then
		return
	end
	local d = (t - a).Unit
	k.rod(th, "Saya", a, t, 0.14, sheath)
	if square then
		k.add(th, "Tsuba", V3(0.28, 0.28, 0.05), guard, CFrame.lookAt(t, t + d))
	else
		k.disc(th, "Tsuba", t, d, 0.3, 0.05, guard)
	end
	k.rod(th, "Tsuka", t + d * 0.03, t + d * 0.5, 0.13, grip)
end

local LIST = {
	{
		id = "ninguno",
		name = "Sin traje",
		cost = 0,
		slots = {},
		colors = { rgb(255, 250, 235) },
		icon = {},
	},
	{
		-- Diadema de gata, corazones en las mejillas y un lazo enorme en el abdomen
		id = "kawaii",
		name = "Kawaii",
		cost = 5e3,
		slots = { "head" },
		top = 1.35,
		colors = { rgb(255, 182, 214), rgb(196, 170, 255), rgb(150, 232, 200) },
		icon = {
			{ "d", 8, -4, 12, 12, rgb(196, 170, 255) },
			{ "d", 38, -4, 12, 12, rgb(196, 170, 255) },
			{ "o", 13, 14, 18, 13, rgb(150, 232, 200), -15 },
			{ "o", 33, 14, 18, 13, rgb(150, 232, 200), 15 },
			{ "o", 23, 14, 9, 9, rgb(255, 92, 160) },
			{ "o", 19, 36, 10, 10, rgb(255, 92, 160) },
			{ "o", 27, 36, 10, 10, rgb(255, 92, 160) },
			{ "d", 23, 41, 10, 10, rgb(255, 92, 160) },
		},
		build = function(k)
			local lav, pink, mint, hot = rgb(196, 170, 255), rgb(255, 182, 214), rgb(150, 232, 200), rgb(255, 92, 160)
			local h = k.head
			if h then
				-- Diadema: un arco que asoma por encima de la coronilla y se hunde en las sienes
				k.add(h, "Headband", V3(2.3, 1, 0.22), lav, CF(0, 0.5, 0.15), "ball")
				for _, s in { -1, 1 } do
					-- Orejas: rombos medio hundidos en la diadema, detrás de las antenas
					local ear = CF(s * 0.62, 0.9, 0.15) * ANG(0, 0, rad(45) - s * rad(12))
					k.add(h, "CatEar", V3(0.52, 0.52, 0.16), lav, ear)
					k.add(h, "CatEarInner", V3(0.3, 0.3, 0.06), pink, ear * CF(0.07, 0.07, -0.08))
					-- Corazón sobre la mejilla (dos bolas y un rombo)
					local cheek = CF(s * 0.78, -0.25, -0.58) * ANG(0, -s * rad(35), 0) * CF(0, 0.02, -0.11)
					k.add(h, "Blush", V3(0.17, 0.17, 0.07), hot, cheek * CF(-0.065, 0.04, 0), "ball")
					k.add(h, "Blush", V3(0.17, 0.17, 0.07), hot, cheek * CF(0.065, 0.04, 0), "ball")
					k.add(h, "Blush", V3(0.15, 0.15, 0.07), hot, cheek * CF(0, -0.03, 0) * ANG(0, 0, rad(45)))
				end
			end
			local a = k.abdomen
			if a then
				-- Cinta alrededor del abdomen (sigue su silueta y crece con él) y lazo grande encima
				local z0, z1 = k.span(a)
				local z = z0 + 0.32 * (z1 - z0)
				local rx, ry, cy = k.section(a, z)
				if rx > 0 then
					k.add(a, "Ribbon", V3(rx * 2.3, ry * 2.3, 0.26), mint, CF(0, cy, z), "ball")
					local top = CF(0, cy + ry * 1.12, z)
					for _, s in { -1, 1 } do
						k.add(a, "RibbonBow", V3(0.8, 0.56, 0.24), pink, top * CF(s * 0.4, 0.14, 0) * ANG(0, 0, s * rad(18)), "ball")
					end
					k.add(a, "RibbonKnot", V3(0.32, 0.34, 0.3), hot, top * CF(0, 0.06, 0), "ball")
				end
			end
		end,
	},
	{
		-- Chaqueta, cuello, corbata, gafas de pasta y maletín en la pata delantera derecha
		id = "oficinista",
		name = "Oficinista",
		cost = 1e6,
		slots = { "face", "body" },
		colors = { rgb(54, 62, 92), WHITE, RED },
		icon = {
			{ "d", 15, 3, 14, 14, WHITE },
			{ "d", 31, 3, 14, 14, WHITE },
			{ "r", 23, 9, 8, 7, RED },
			{ "r", 23, 27, 8, 28, RED },
			{ "r", 48, 50, 20, 15, rgb(132, 78, 44) },
			{ "r", 48, 41, 8, 4, INK },
		},
		build = function(k)
			local navy, dark, leather = rgb(54, 62, 92), rgb(40, 34, 40), rgb(132, 78, 44)
			coat(k, navy)
			local th, h = k.thorax, k.head
			if th then
				-- Puntas del cuello de la camisa, tumbadas sobre la chaqueta detrás de la cabeza
				for _, s in { -1, 1 } do
					k.add(th, "Collar", V3(0.36, 0.36, 0.06), WHITE, k.lay(V3(s * 0.26, 0.56, -0.38), V3(0.254 * s, 0.874, -0.414), rad(45)))
				end
				-- Corbata: nudo bajo la barbilla y pala apoyada en el pecho
				knot(k, RED)
				k.add(th, "Tie", V3(0.22, 0.48, 0.08), RED, CF(0, -0.45, -0.53) * ANG(rad(-33.5), 0, 0), "ball")
			end
			if h then
				-- Gafas de pasta: cristales claros, ceja negra y patillas hasta las sienes
				for _, s in { -1, 1 } do
					local lens = k.add(h, "Lens", V3(0.72, 0.84, 0.08), GLASS, CF(s * 0.42, 0.28, -1.1), "ball")
					lens.Transparency = 0.55
					k.add(h, "GlassesArm", V3(0.07, 0.09, 1), dark, CF(s * 0.9, 0.62, -0.62) * ANG(0, s * rad(9), 0))
				end
				k.add(h, "Browline", V3(1.68, 0.12, 0.1), dark, CF(0, 0.66, -1.1))
			end
			-- Maletín pegado a la tibia delantera derecha, paralelo a ella (se balancea al andar)
			local shin = k.part("Shin2")
			if shin then
				local case = CF(1.553, -0.564, -1.346) * ANG(0, 0, rad(15.2))
				k.at(shin, "Briefcase", V3(0.18, 0.5, 0.6), leather, case)
				k.at(shin, "BriefcaseHandle", V3(0.06, 0.12, 0.26), dark, case * CF(0, 0.31, 0))
				k.at(shin, "BriefcaseClasp", V3(0.06, 0.1, 0.1), GOLD, case * CF(0.1, 0.13, 0), "ball")
			end
		end,
	},
	{
		-- Kabuto con cuernos dorados, hombreras, coraza lacada con cordón y katana en el lomo
		id = "samurai",
		name = "Samurái",
		cost = 2e8,
		slots = { "head", "body", "back" },
		top = 1.75,
		colors = { rgb(196, 36, 44), GOLD, INK },
		icon = {
			{ "r", 15, -9, 5, 20, GOLD, -20 },
			{ "r", 31, -9, 5, 20, GOLD, 20 },
			{ "r", 23, 22, 46, 4, NAVY },
			{ "r", 23, 38, 46, 4, NAVY },
			{ "r", 23, 30, 6, 66, INK, 35 },
			{ "r", 3, 51, 6, 14, rgb(240, 236, 226), 35 },
		},
		build = function(k)
			local lacquer, iron, wrap = rgb(196, 36, 44), rgb(44, 46, 62), rgb(240, 236, 226)
			local h, th, back = k.head, k.thorax, k.back
			if h then
				local seat = k.seat
				k.add(h, "Kabuto", V3(1.36, 1, 1.44), iron, seat * CF(0, 0.02, 0.02), "ball")
				-- Faldón de nuca (shikoro): disco ancho detrás de las antenas
				k.add(h, "Shikoro", V3(1.95, 0.36, 1.5), lacquer, seat * CF(0, -0.14, 0.24), "ball")
				-- Cuernos en V (kuwagata) entre las antenas y placa dorada en su base
				for _, s in { -1, 1 } do
					k.add(h, "Kuwagata", V3(0.12, 0.8, 0.06), GOLD, CF(s * 0.27, 1.32, -0.44) * ANG(0, 0, -s * rad(22)))
				end
				k.add(h, "Maedate", V3(0.3, 0.3, 0.12), GOLD, CF(0, 0.98, -0.47), "ball")
			end
			if th then
				-- Coraza (dō) con un cordón azul
				k.add(th, "Do", V3(1.42, 0.82, 1.38), lacquer, CF(0, 0.24, 0.02), "ball")
				k.add(th, "Odoshi", V3(1.4, 0.82, 0.1), NAVY, CF(0, 0.24, -0.2), "ball")
				-- Hombreras de dos láminas, por encima de los muslos
				for _, s in { -1, 1 } do
					local pad = CF(s * 0.66, 0.42, -0.05) * ANG(0, 0, s * rad(35))
					k.add(th, "Sode", V3(0.18, 0.32, 0.86), lacquer, pad * CF(0, 0.13, 0), "ball")
					k.add(th, "Sode", V3(0.18, 0.32, 0.86), lacquer, pad * CF(0, -0.11, 0), "ball")
				end
			end
			if back then
				k.add(back, "DoBack", V3(1.1, 0.66, 1), lacquer, CF(0, 0.18, 0), "ball")
			end
			-- Katana en diagonal sobre la coraza, empuñadura alzada detrás a la derecha
			sword(k, V3(-0.36, 0.64, -0.25), V3(0.4, 0.76, 0.9), INK, GOLD, wrap, false)
		end,
	},
	{
		-- Gorro alto, chaquetilla blanca con botones, pañuelo rojo y bigote
		id = "chef",
		name = "Chef",
		cost = 4e10,
		slots = { "head", "body" },
		top = 2,
		colors = { WHITE, RED, rgb(110, 66, 40) },
		icon = {
			{ "o", 23, -10, 32, 22, WHITE },
			{ "r", 23, 4, 30, 8, RED },
			{ "o", 16, 22, 6, 6, INK },
			{ "o", 30, 22, 6, 6, INK },
			{ "o", 16, 36, 6, 6, INK },
			{ "o", 30, 36, 6, 6, INK },
		},
		build = function(k)
			local brown = rgb(110, 66, 40)
			local h, th = k.head, k.thorax
			if h then
				local seat = k.seat
				k.add(h, "ToqueBand", V3(0.4, 1, 1), WHITE, seat * CF(0, 0.2, 0) * UP, "cyl")
				k.add(h, "Toque", V3(1.3, 0.9, 1.3), WHITE, seat * CF(0, 0.78, 0), "ball")
				for _, s in { -1, 1 } do
					k.add(h, "ToquePuff", V3(0.7, 0.7, 0.7), WHITE, seat * CF(s * 0.42, 0.66, 0.05), "ball")
					-- Bigote sobre el hocico, con las puntas hacia arriba y atrás
					k.add(h, "Mustache", V3(0.5, 0.2, 0.2), brown, CF(s * 0.22, -0.08, -1) * ANG(0, -s * rad(20), s * rad(12)), "ball")
					k.add(h, "MustacheCurl", V3(0.18, 0.18, 0.18), brown, CF(s * 0.47, 0, -0.92), "ball")
				end
			end
			coat(k, WHITE)
			if th then
				for _, s in { -1, 1 } do
					k.add(th, "Button", V3(0.13, 0.09, 0.13), INK, CF(s * 0.2, 0.58, -0.32), "ball")
					k.add(th, "ScarfTail", V3(0.16, 0.32, 0.08), RED, CF(s * 0.08, -0.42, -0.54) * ANG(rad(-30), 0, s * rad(14)), "ball")
				end
				knot(k, RED)
			end
		end,
	},
	{
		-- Bicornio con calavera, parche en el ojo y loro en el hombro
		id = "pirata",
		name = "Pirata",
		cost = 8e12,
		slots = { "head", "face", "back" },
		top = 1.45,
		colors = { rgb(150, 34, 40), INK, GOLD },
		icon = {
			{ "o", 23, -8, 50, 16, INK },
			{ "o", 23, -8, 8, 8, WHITE },
			{ "o", 42, 6, 12, 17, RED },
			{ "o", 47, 1, 6, 5, rgb(255, 210, 63) },
			{ "o", 16, 26, 6, 6, GOLD },
			{ "o", 16, 40, 6, 6, GOLD },
		},
		build = function(k)
			local black, yellow, blue = rgb(34, 30, 36), rgb(255, 210, 63), rgb(52, 120, 232)
			local h, th = k.head, k.thorax
			if h then
				local hat = k.seat * CF(0, 0.25, 0)
				k.add(h, "Bicorne", V3(1.9, 0.75, 0.5), black, hat, "ball")
				k.add(h, "BicorneTrim", V3(2, 0.82, 0.4), GOLD, hat, "ball")
				k.add(h, "Skull", V3(0.3, 0.28, 0.08), WHITE, hat * CF(0, 0.1, -0.25), "ball")
				for _, s in { -1, 1 } do
					k.add(h, "Bone", V3(0.4, 0.07, 0.05), WHITE, hat * CF(0, 0.1, -0.24) * ANG(0, 0, s * rad(35)))
				end
				-- Parche sobre el ojo izquierdo (tapa pupila y brillo; asoma el blanco alrededor)
				k.add(h, "EyePatch", V3(0.62, 0.74, 0.12), black, CF(-0.4, 0.3, -0.99), "ball")
			end
			if th then
				-- Loro en el hombro derecho; con armadura se sube encima de la hombrera
				local lift = if k.armor > 0 then 0.16 else 0
				k.add(th, "Parrot", V3(0.34, 0.48, 0.34), RED, CF(0.45, 0.63 + lift, -0.05) * ANG(rad(-12), 0, 0), "ball")
				k.add(th, "ParrotHead", V3(0.3, 0.3, 0.3), RED, CF(0.45, 0.92 + lift, -0.12), "ball")
				k.add(th, "ParrotBeak", V3(0.12, 0.14, 0.18), yellow, CF(0.45, 0.89 + lift, -0.28), "ball")
				k.add(th, "ParrotWing", V3(0.1, 0.34, 0.26), blue, CF(0.6, 0.62 + lift, 0) * ANG(rad(-15), 0, 0), "ball")
				k.add(th, "ParrotTail", V3(0.14, 0.06, 0.42), blue, CF(0.45, 0.42 + lift, 0.22) * ANG(rad(35), 0, 0), "ball")
			end
		end,
	},
	{
		-- Sombrero echado atrás, chaleco con estrella, pañuelo y espuelas
		id = "vaquero",
		name = "Vaquero",
		cost = 2e15,
		slots = { "head", "body" },
		top = 1.55,
		colors = { rgb(150, 92, 52), rgb(206, 150, 90), RED },
		icon = {
			{ "o", 23, -6, 58, 10, rgb(206, 150, 90) },
			{ "r", 23, -13, 26, 14, rgb(206, 150, 90) },
			{ "r", 23, -8, 26, 3, rgb(92, 54, 30) },
			{ "d", 23, 8, 16, 16, RED },
			{ "d", 13, 26, 11, 11, GOLD },
			{ "r", 13, 26, 9, 9, GOLD },
		},
		build = function(k)
			local tan, darkBrown, vest = rgb(206, 150, 90), rgb(92, 54, 30), rgb(150, 92, 52)
			local h, th = k.head, k.thorax
			if h then
				-- Inclinado 25° hacia atrás: el ala queda detrás de los codos de las antenas
				local hat = CF(0, 0.9, 0.32) * ANG(rad(25), 0, 0)
				k.add(h, "HatBrim", V3(2.3, 0.12, 1.6), tan, hat * CF(0, 0.05, 0.3), "ball")
				for _, s in { -1, 1 } do
					k.add(h, "BrimCurl", V3(0.3, 0.42, 1), tan, hat * CF(s * 0.95, 0.16, 0.3) * ANG(0, 0, -s * rad(25)), "ball")
				end
				k.add(h, "HatCrown", V3(1.05, 0.9, 1.15), tan, hat * CF(0, 0.38, 0.3), "ball")
				k.add(h, "HatBand", V3(0.9, 0.16, 0.98), darkBrown, hat * CF(0, 0.14, 0.3), "ball")
			end
			coat(k, vest)
			if th then
				knot(k, RED)
				k.add(th, "Bandana", V3(0.36, 0.36, 0.06), RED, CF(0, -0.36, -0.6) * ANG(rad(-30), 0, 0) * ANG(0, 0, rad(45)))
				local n = V3(-0.44, 0.86, -0.23).Unit
				k.star(th, k.lay(V3(-0.45, 0.53, -0.22) + n * 0.03, n, 0), 0.24, GOLD)
			end
			-- Espuelas: ruedecita dorada en el talón de las patas traseras, por fuera
			for _, shoe in k.shoes do
				if shoe.index >= 5 then
					k.add(shoe.part, "Spur", V3(0.04, 0.22, 0.22), GOLD, CF(shoe.side * 0.17, 0.04, 0.3), "cyl")
				end
			end
		end,
	},
	{
		-- Capucha y máscara, cinta roja con colas, ropa oscura y espada corta en el lomo
		id = "ninja",
		name = "Ninja",
		cost = 4e17,
		slots = { "head", "face", "body", "back" },
		top = 1.1,
		colors = { rgb(36, 38, 58), RED, INK },
		icon = {
			{ "o", 23, -8, 34, 20, rgb(36, 38, 58) },
			{ "r", 23, -10, 34, 6, RED },
			{ "r", 23, 42, 46, 6, RED },
			{ "r", 23, 26, 6, 60, INK, -35 },
			{ "r", 43, 51, 6, 14, RED, -35 },
		},
		build = function(k)
			local navy = rgb(36, 38, 58)
			local h = k.head
			if h then
				-- Capucha algo mayor que cabeza y lóbulos: los ojos y el hocico asoman por delante
				k.add(h, "Hood", V3(2.4, 1.9, 1.75), navy, CF(0, 0.1, 0.15), "ball")
				k.add(h, "Mask", V3(1.64, 1.02, 0.92), navy, CF(0, -0.3, -0.62), "ball")
				k.add(h, "Hachimaki", V3(2.46, 0.22, 1.82), RED, CF(0, 0.5, 0.15), "ball")
				k.add(h, "HachimakiKnot", V3(0.28, 0.28, 0.22), RED, CF(0, 0.5, 1.06), "ball")
				for _, s in { -1, 1 } do
					-- Colas hacia atrás y algo abajo, por encima del tórax
					local dir = V3(0.242 * s, -0.41, 0.879)
					k.add(h, "HachimakiTail", V3(0.16, 0.07, 0.8), RED, CFrame.lookAt(V3(0, 0.5, 1.06) + dir * 0.4, V3(0, 0.5, 1.06) + dir), "ball")
				end
			end
			coat(k, navy)
			sword(k, V3(0.36, 0.64, -0.25), V3(-0.4, 0.76, 0.9), INK, rgb(70, 72, 84), RED, true)
		end,
	},
	{
		-- Gafas de buceo con tubo, botellas en el lomo y aletas en las seis patas
		id = "buzo",
		name = "Buzo",
		cost = 8e19,
		slots = { "face", "back" },
		colors = { rgb(40, 44, 56), rgb(255, 210, 63), GLASS },
		icon = {
			{ "r", 14, 28, 12, 42, rgb(255, 210, 63) },
			{ "r", 32, 28, 12, 42, rgb(255, 210, 63) },
			{ "o", 23, -8, 30, 16, GLASS },
			{ "r", 23, -16, 32, 4, rgb(255, 210, 63) },
			{ "r", 41, -14, 4, 22, rgb(255, 140, 40) },
		},
		build = function(k)
			local yellow, orange = rgb(255, 210, 63), rgb(255, 140, 40)
			local h, th = k.head, k.thorax
			if h then
				local lens = k.add(h, "MaskLens", V3(1.6, 0.95, 0.12), GLASS, CF(0, 0.3, -1.1), "ball")
				lens.Transparency = 0.5
				k.add(h, "MaskRim", V3(1.7, 0.14, 0.18), yellow, CF(0, 0.77, -1.04), "ball")
				k.add(h, "MaskRim", V3(1.3, 0.14, 0.18), yellow, CF(0, -0.17, -1.06), "ball")
				k.add(h, "MaskStrap", V3(2.36, 0.16, 2), INK, CF(0, 0.32, 0.12), "ball")
				-- Tubo de respirar en el costado derecho, metido en la correa
				k.add(h, "Snorkel", V3(1.25, 0.14, 0.14), yellow, CF(1.1, 0.9, -0.1) * UP, "cyl")
				k.add(h, "SnorkelTop", V3(0.22, 0.22, 0.22), orange, CF(1.1, 1.55, -0.1), "ball")
			end
			if th then
				local lift = if k.armor > 0 then 0.12 else 0
				for _, s in { -1, 1 } do
					k.add(th, "Tank", V3(1.1, 0.42, 0.42), yellow, CF(s * 0.22, 0.71 + lift, 0.3) * ANG(0, rad(90), 0), "cyl")
					k.add(th, "TankValve", V3(0.2, 0.2, 0.2), STEEL, CF(s * 0.22, 0.71 + lift, -0.27), "ball")
				end
			end
			for _, shoe in k.shoes do
				k.add(shoe.part, "Flipper", V3(0.66, 0.08, 0.95), yellow, CF(0, -0.19, -0.42), "ball")
			end
		end,
	},
	{
		-- Sombrero picudo con estrella, barba, capa y bastón con orbe brillante
		id = "mago",
		name = "Mago",
		cost = 2e22,
		slots = { "head", "back" },
		top = 2.5,
		colors = { rgb(110, 60, 190), GOLD, WHITE },
		icon = {
			{ "d", 23, -14, 20, 20, rgb(110, 60, 190) },
			{ "o", 23, -4, 40, 8, rgb(110, 60, 190) },
			{ "o", 23, 10, 22, 24, WHITE },
			{ "d", 12, 34, 10, 10, GOLD },
			{ "d", 34, 44, 8, 8, GOLD },
			{ "r", 50, 30, 4, 50, rgb(140, 96, 56) },
			{ "o", 50, 4, 10, 10, rgb(110, 240, 255) },
		},
		build = function(k)
			local purple, wood, glow = rgb(110, 60, 190), rgb(140, 96, 56), rgb(110, 240, 255)
			local h, th = k.head, k.thorax
			if h then
				-- Echado atrás y con ala pequeña para no tocar las antenas
				local hat = CF(0, 0.8, 0.4) * ANG(rad(18), 0, 0)
				k.add(h, "WizardBrim", V3(0.1, 1.5, 1.5), purple, hat * CF(0, 0.05, 0.15) * UP, "cyl")
				k.add(h, "WizardHat", V3(0.55, 1.05, 1.05), purple, hat * CF(0, 0.33, 0.15) * UP, "cyl")
				k.add(h, "WizardHat", V3(0.5, 0.78, 0.78), purple, hat * CF(0, 0.84, 0.21) * UP, "cyl")
				k.add(h, "WizardHat", V3(0.45, 0.5, 0.5), purple, hat * CF(0, 1.29, 0.29) * UP, "cyl")
				k.add(h, "WizardTip", V3(0.32, 0.42, 0.32), purple, hat * CF(0, 1.6, 0.38), "ball")
				k.star(h, hat * CF(0, 0.36, -0.39), 0.26, GOLD)
				-- Barba estrecha bajo el hocico, entre las bisagras de las pinzas
				k.add(h, "Beard", V3(0.62, 0.86, 0.46), WHITE, CF(0, -0.95, -0.76), "ball")
			end
			if th then
				-- Capa como la de enjambre: se levanta más cuanto mayor es el abdomen
				local hinge = CF(0, 0.6, 0) * ANG(-rad(24 + 5.5 * k.belly), 0, 0)
				k.add(th, "Cloak", V3(1.5, 0.1, 1.6), purple, hinge * CF(0, 0, 0.78), "ball")
				k.add(th, "CloakClasp", V3(0.3, 0.3, 0.3), GOLD, hinge, "ball")
			end
			-- Bastón cruzando la tibia media izquierda, inclinado hacia fuera
			local shin = k.part("Shin3")
			if shin then
				local q = V3(-1.504, -0.464, -0.052)
				local u = V3(-math.sin(rad(25)), math.cos(rad(25)), 0)
				local top = q + u * 1.45
				k.rodAt(shin, "Staff", q - u * 0.35, top, 0.14, wood)
				k.at(shin, "StaffRing", V3(0.06, 0.3, 0.3), GOLD, CFrame.lookAt(top - u * 0.05, top + u) * ANG(0, rad(90), 0), "cyl")
				local orb = k.at(shin, "StaffOrb", V3(0.36, 0.36, 0.36), glow, CF(top + u * 0.15), "ball")
				if orb then
					orb.Material = Enum.Material.Neon
				end
			end
		end,
	},
	{
		-- Casco blanco con visor que brilla, cuello de traje, mochila y panel en el pecho
		id = "astronauta",
		name = "Astronauta",
		cost = 1e24,
		slots = { "head", "face", "body", "back" },
		top = 1.1,
		colors = { WHITE, rgb(120, 230, 255), rgb(180, 186, 198) },
		icon = {
			{ "o", 23, -10, 32, 26, WHITE },
			{ "o", 23, -10, 22, 14, rgb(120, 230, 255) },
			{ "r", 23, 24, 22, 13, rgb(180, 186, 198) },
			{ "o", 19, 24, 5, 5, RED },
			{ "o", 27, 24, 5, 5, rgb(110, 200, 90) },
		},
		build = function(k)
			local gray, visorColor = rgb(180, 186, 198), rgb(120, 230, 255)
			local h, th, back = k.head, k.thorax, k.back
			if h then
				k.add(h, "SpaceHelmet", V3(2.4, 1.9, 1.75), WHITE, CF(0, 0.1, 0.15), "ball")
				for _, s in { -1, 1 } do
					k.add(h, "HelmetEar", V3(0.2, 0.6, 0.6), gray, CF(s * 1.2, 0.2, 0.12), "cyl")
				end
				-- Visor delante de los ojos: neón translúcido, los ojos se ven a través
				local visor = k.add(h, "Visor", V3(1.7, 1, 0.5), visorColor, CF(0, 0.3, -0.9), "ball")
				visor.Material = Enum.Material.Neon
				visor.Transparency = 0.45
			end
			coat(k, WHITE)
			if th then
				k.disc(th, "SuitCollar", V3(0, 0.2, -0.55), V3(0, 0, -1), 1.5, 0.3, gray)
				k.add(th, "ChestPack", V3(0.5, 0.16, 0.36), gray, CF(0, 0.66, -0.12))
				for i, color in { RED, rgb(110, 200, 90) } do
					local light = k.add(th, "ChestLight", V3(0.1, 0.1, 0.1), color, CF((i - 1.5) * 0.24, 0.74, -0.14), "ball")
					light.Material = Enum.Material.Neon
				end
			end
			if back then
				k.add(back, "LifePack", V3(1, 0.5, 0.9), WHITE, CF(0, 0.55, 0), "ball")
				for _, s in { -1, 1 } do
					k.add(back, "Nozzle", V3(0.3, 0.22, 0.22), gray, CF(s * 0.25, 0.45, 0.5) * ANG(0, rad(90), 0), "cyl")
				end
			end
		end,
	},
	{
		-- Solo VIP: nemes dorado a rayas con cobra, collar ancho y cayado
		id = "faraon",
		name = "Faraón",
		cost = 0,
		pass = "vip",
		slots = { "head", "body" },
		top = 1.15,
		colors = { GOLD, rgb(40, 90, 200), rgb(250, 244, 228) },
		icon = {
			{ "o", 23, -8, 38, 22, GOLD },
			{ "r", 23, -8, 38, 4, rgb(40, 90, 200) },
			{ "o", 23, 4, 44, 16, rgb(40, 90, 200) },
			{ "o", 23, 2, 30, 9, GOLD },
			{ "r", 23, 26, 46, 5, rgb(40, 90, 200) },
			{ "r", 23, 40, 46, 5, rgb(40, 90, 200) },
		},
		build = function(k)
			local blue, linen = rgb(40, 90, 200), rgb(250, 244, 228)
			local h, th = k.head, k.thorax
			if h then
				k.add(h, "Nemes", V3(2.36, 1.8, 1.7), GOLD, CF(0, 0.16, 0.2), "ball")
				k.add(h, "NemesStripe", V3(2.4, 0.12, 1.72), blue, CF(0, 0.35, 0.2), "ball")
				k.add(h, "NemesStripe", V3(1.96, 0.12, 1.4), blue, CF(0, 0.7, 0.2), "ball")
				for _, s in { -1, 1 } do
					k.add(h, "Lappet", V3(0.34, 1.2, 0.5), GOLD, CF(s * 1.08, -0.4, 0), "ball")
				end
				k.add(h, "Uraeus", V3(0.16, 0.34, 0.14), GOLD, CF(0, 0.92, -0.3) * ANG(rad(-10), 0, 0), "ball")
				k.add(h, "UraeusGem", V3(0.1, 0.1, 0.06), RED, CF(0, 0.88, -0.38), "ball")
			end
			coat(k, linen)
			if th then
				-- Collar ancho: tres anillos concéntricos oro-azul-oro
				k.add(th, "Usekh", V3(1.55, 0.26, 1), GOLD, CF(0, 0.54, -0.3), "ball")
				k.add(th, "Usekh", V3(1.25, 0.3, 0.8), blue, CF(0, 0.56, -0.3), "ball")
				k.add(th, "Usekh", V3(0.9, 0.34, 0.6), GOLD, CF(0, 0.58, -0.3), "ball")
			end
			-- Cayado cruzando la tibia media derecha
			local shin = k.part("Shin4")
			if shin then
				local q = V3(1.504, -0.464, -0.052)
				local u = V3(math.sin(rad(25)), math.cos(rad(25)), 0)
				local top = q + u * 1.2
				local bend = V3(1.8, 0.98, -0.052)
				local tip = V3(1.62, 0.72, -0.052)
				k.rodAt(shin, "Crook", q - u * 0.3, top, 0.12, blue)
				k.rodAt(shin, "CrookHook", top, bend, 0.12, GOLD)
				k.rodAt(shin, "CrookHook", bend, tip, 0.12, GOLD)
				k.at(shin, "CrookBend", V3(0.14, 0.14, 0.14), GOLD, CF(bend), "ball")
			end
		end,
	},
}

Outfits.list = LIST
Outfits.byId = {}
for _, def in LIST do
	local covers = {}
	for _, slot in def.slots do
		covers[slot] = true
	end
	def.covers = covers
	Outfits.byId[def.id] = def
end

-- ¿El traje ocupa ese hueco?
function Outfits.covers(id: any, slot: string): boolean
	local def = Outfits.byId[id]
	return def ~= nil and def.covers[slot] == true
end

-- ¿El traje tapa el sombrero del vestidor? Las gafas cuentan como cara; el resto, como cabeza.
function Outfits.hidesHat(id: any, hat: any): boolean
	if type(hat) ~= "string" or hat == "ninguno" then
		return false
	end
	return Outfits.covers(id, if hat == "gafas" then "face" else "head")
end

return Outfits
