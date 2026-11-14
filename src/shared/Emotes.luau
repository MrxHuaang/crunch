-- Emotes de memes: gestos y frases genéricas de meme hechos con una hormiga de seis patas y
-- antenas. Aquí solo van los datos que comparten servidor y cliente: nombre, cómo se consigue,
-- si es un bucle, cuánto dura y el pictograma de su cromo. La animación vive en client/Emotes.
--
-- unlock = { kind = "free" }                         gratis desde el principio
--          { kind = "depth", value = capa }          al excavar esa capa (se queda aunque enjambres)
--          { kind = "rebirths", value = n }          tras n enjambres
--          { kind = "trophies", value = n }          al dominar n tipos de comida (trofeos)
--          { kind = "food", value = capa }           se compra con comida al precio de esa capa
--
-- Pictograma: formas en una caja de 64 × 64 (como los iconos de Outfits):
--   { "o", x, y, w, h, color, giro }  óvalo        { "r", ... } rectángulo redondeado
--   { "d", x, y, w, _, color, giro }  rombo        { "l", ... } trazo fino sin borde (patas)
--   { "c", x, y, w, h, color }        aro (solo borde)
--   { "t", x, y, w, h, color, giro, texto }  letras de cómic

local Config = require(script.Parent.Config)

local Emotes = {}

Emotes.Cooldown = 1.5 -- segundos entre dos emotes de la misma jugadora
Emotes.ComboRange = 12 -- studs: tan cerca tiene que estar la otra para el combo
Emotes.ComboWindow = 4 -- segundos que tiene la otra para responder
Emotes.WheelSize = 8

local rgb = Color3.fromRGB
local RED = rgb(232, 62, 48)
local DARK = rgb(202, 44, 44)
local INK = rgb(26, 20, 22)
local WHITE = rgb(255, 255, 255)
local CREAM = rgb(255, 236, 204)
local YELLOW = rgb(255, 210, 63)
local GREEN = rgb(70, 200, 90)
local ORANGE = rgb(255, 140, 40)
local PURPLE = rgb(150, 90, 230)
local PINK = rgb(255, 120, 200)
local BLUE = rgb(62, 150, 243)
local GREY = rgb(150, 150, 160)

-- Patas por defecto de la hormiga de frente, solo el lado izquierdo (el derecho se refleja):
-- { ángulo del muslo, ángulo de la tibia } en grados de pantalla (0 = derecha, 90 = abajo)
local REST_LEGS = { { 200, 115 }, { 185, 100 }, { 165, 85 } }

local function push(list, shape)
	table.insert(list, shape)
end

-- Trazo de `from` en la dirección `angle` (grados de pantalla) y largo `len`; devuelve el final
local function stroke(list, x: number, y: number, angle: number, len: number, width: number, color: Color3): (number, number)
	local a = math.rad(angle)
	local ex, ey = x + math.cos(a) * len, y + math.sin(a) * len
	push(list, { "l", (x + ex) / 2, (y + ey) / 2, len + width * 0.6, width, color, angle })
	return ex, ey
end

-- Hormiga de frente para los cromos. o = {
--   x, y: desplazamiento; legs = { [i] = { muslo, tibia } } (1..3 izquierda, 4..6 derecha; si
--   falta una, en reposo); ant = { izq, der } ángulos de las antenas; headX/headY/headScale;
--   eyes = "look" | "side" | "closed" | "cool"; tilt de la cabeza }
function Emotes.ant(o): { any }
	o = o or {}
	local list = {}
	local x0, y0 = o.x or 0, o.y or 0
	local hs = o.headScale or 1
	local hx, hy = 32 + x0 + (o.headX or 0), 21 + y0 + (o.headY or 0)
	-- Patas detrás del cuerpo
	for i = 1, 6 do
		local left = i <= 3
		local row = if left then i else i - 3
		local pair = o.legs and o.legs[i]
		local thigh, shin
		if pair then
			thigh, shin = pair[1], pair[2]
		else
			local rest = REST_LEGS[row]
			thigh = if left then rest[1] else 180 - rest[1]
			shin = if left then rest[2] else 180 - rest[2]
		end
		local sx = 32 + x0 + (if left then -5 else 5)
		local sy = 35 + y0 + (row - 1) * 4
		local kx, ky = stroke(list, sx, sy, thigh, 10, 3, INK)
		local fx, fy = stroke(list, kx, ky, shin, 10, 3, INK)
		push(list, { "o", fx, fy, 6, 5, CREAM })
	end
	-- Abdomen, tórax
	push(list, { "o", 32 + x0 + (o.bellyX or 0), 50 + y0, 20, 16, DARK, o.bellyTilt or 0 })
	push(list, { "o", 32 + x0, 38 + y0, 15, 13, RED })
	-- Antenas
	local ants = o.ant or { 250, 290 }
	for k, angle in ants do
		local bx = hx + (if k == 1 then -4 else 4) * hs
		local ex, ey = stroke(list, bx, hy - 7 * hs, angle, 9 * hs, 2, INK)
		push(list, { "o", ex, ey, 5, 5, INK })
	end
	-- Cabeza con ojos y hocico
	local tilt = o.tilt or 0
	push(list, { "o", hx, hy, 24 * hs, 19 * hs, RED, tilt })
	push(list, { "o", hx, hy + 5 * hs, 15 * hs, 8 * hs, CREAM, tilt })
	local eyes = o.eyes or "look"
	for _, s in { -1, 1 } do
		local ex, ey = hx + s * 4.5 * hs, hy - 2 * hs
		if eyes == "closed" then
			push(list, { "l", ex, ey, 6 * hs, 2, INK, tilt })
		elseif eyes == "cool" then
			push(list, { "r", ex, ey, 7 * hs, 5 * hs, INK, tilt })
		else
			push(list, { "o", ex, ey, 6 * hs, 8 * hs, WHITE, tilt })
			local dx = if eyes == "side" then 1.5 else 0
			push(list, { "o", ex + dx, ey + 1, 3 * hs, 4 * hs, INK, tilt })
		end
	end
	return list
end

local function with(base: { any }, extra: { any }): { any }
	for _, shape in extra do
		table.insert(base, shape)
	end
	return base
end

-- Precio de un emote que se compra: la mitad de lo que cuesta excavar hasta esa capa
function Emotes.price(def): number
	local unlock = def.unlock
	if unlock.kind ~= "food" then
		return 0
	end
	local layer = math.max(2, tonumber(unlock.value) or 2)
	return math.floor(Config.DigBase * 0.5 * Config.StageGrowth ^ (layer - 2))
end

-- Cómo se consigue, en corto, para el cromo que falta
function Emotes.howTo(def): string
	local u = def.unlock
	if u.kind == "depth" then
		return "Excava la capa " .. u.value
	elseif u.kind == "rebirths" then
		return if u.value == 1 then "Enjambra 1 vez" else "Enjambra " .. u.value .. " veces"
	elseif u.kind == "trophies" then
		return "Domina " .. u.value .. " comidas"
	elseif u.kind == "food" then
		return "Cómpralo con comida"
	end
	return "Gratis"
end

-- ¿Lo consigue ya jugando? (no cuenta la compra)
function Emotes.earned(def, depth: number, rebirths: number, trophies: number): boolean
	local u = def.unlock
	if u.kind == "free" then
		return true
	elseif u.kind == "depth" then
		return depth >= u.value
	elseif u.kind == "rebirths" then
		return rebirths >= u.value
	elseif u.kind == "trophies" then
		return trophies >= u.value
	end
	return false
end

Emotes.list = {
	{
		id = "dab",
		name = "Dab",
		quote = "Dos patas y dos antenas a la vez",
		length = 2.6,
		color = rgb(120, 210, 255),
		unlock = { kind = "free" },
		icon = Emotes.ant({
			legs = { { 225, 225 }, nil, nil, { 200, 165 } },
			ant = { 215, 230 },
			headX = 4,
			headY = 3,
			tilt = 18,
			eyes = "closed",
		}),
	},
	{
		id = "tpose",
		name = "Pose en T",
		quote = "Seis patas en cruz: DOMINANCIA",
		length = 3.6,
		color = rgb(255, 120, 110),
		unlock = { kind = "free" },
		icon = with(
			Emotes.ant({
				y = -3,
				legs = { { 180, 180 }, { 175, 175 }, { 170, 170 }, { 0, 0 }, { 5, 5 }, { 10, 10 } },
				ant = { 240, 300 },
			}),
			{ { "o", 32, 61, 26, 4, rgb(0, 0, 0) } }
		),
	},
	{
		id = "floss",
		name = "Hilo dental",
		quote = "Abdomen a un lado, patas al otro",
		loop = true,
		color = rgb(170, 240, 140),
		unlock = { kind = "free" },
		icon = with(
			Emotes.ant({
				bellyX = 7,
				bellyTilt = 20,
				legs = { { 160, 120 }, nil, nil, { 160, 120 } },
				ant = { 235, 270 },
			}),
			{ { "l", 54, 46, 8, 2, INK, -30 }, { "l", 56, 52, 8, 2, INK, -10 }, { "l", 9, 30, 8, 2, INK, 30 } }
		),
	},
	{
		id = "bruh",
		name = "Bruh",
		quote = "Tiesa como una tabla. Y al suelo",
		length = 3.6,
		color = rgb(200, 200, 215),
		unlock = { kind = "free" },
		tilt = 75,
		icon = with(
			Emotes.ant({
				legs = { { 100, 100 }, { 95, 95 }, { 90, 90 }, { 80, 80 }, { 85, 85 }, { 90, 90 } },
				ant = { 268, 272 },
				eyes = "closed",
			}),
			{ { "t", 50, 10, 26, 14, INK, -75, "bruh" } }
		),
	},
	{
		id = "clap",
		name = "Aplauso lento",
		quote = "Cuatro patas. Clap. Clap. Clap",
		length = 4.2,
		color = rgb(255, 225, 120),
		unlock = { kind = "free" },
		icon = with(
			Emotes.ant({
				legs = { { 300, 20 }, { 240, 160 }, { 320, 10 }, { 220, 170 } },
				ant = { 235, 305 },
				eyes = "closed",
			}),
			{ { "l", 32, 9, 7, 2, INK, 90 }, { "l", 25, 11, 7, 2, INK, 60 }, { "l", 39, 11, 7, 2, INK, 120 } }
		),
	},
	{
		id = "npc",
		name = "NPC",
		quote = "Saludo en bucle. Bonito día",
		loop = true,
		color = rgb(180, 230, 230),
		unlock = { kind = "free" },
		icon = with(
			Emotes.ant({
				legs = { nil, nil, nil, { 270, 270 } },
				ant = { 270, 270 },
			}),
			{ { "t", 14, 8, 22, 12, INK, 0, "..." } }
		),
	},
	{
		id = "sigma",
		name = "Sigma",
		quote = "Mirada lenta. Mandíbula. Cine",
		length = 5,
		color = rgb(90, 90, 110),
		unlock = { kind = "depth", value = 3 },
		icon = with(
			Emotes.ant({ legs = { nil, nil, nil, { 230, 160 } }, eyes = "side", ant = { 250, 280 } }),
			{ { "r", 32, 4, 64, 8, INK }, { "r", 32, 60, 64, 8, INK } }
		),
	},
	{
		id = "ggez",
		name = "GG EZ",
		quote = "Gafas de píxeles caídas del cielo",
		length = 4,
		color = rgb(255, 170, 230),
		unlock = { kind = "food", value = 2 },
		icon = with(Emotes.ant({ eyes = "cool", ant = { 235, 305 } }), {
			{ "r", 32, 19, 26, 3, INK },
			{ "r", 25, 6, 4, 4, INK },
			{ "r", 32, 2, 4, 4, INK },
			{ "r", 39, 6, 4, 4, INK },
		}),
	},
	{
		id = "fine",
		name = "Todo bien",
		quote = "Una tacita. Todo arde. Todo bien",
		length = 6,
		color = rgb(255, 190, 120),
		unlock = { kind = "depth", value = 4 },
		icon = with(Emotes.ant({ y = 4, legs = { { 300, 40 }, { 240, 140 } }, eyes = "closed", ant = { 250, 290 } }), {
			{ "r", 32, 30, 9, 7, WHITE },
			{ "o", 7, 52, 9, 14, ORANGE },
			{ "o", 57, 50, 9, 16, ORANGE },
			{ "o", 7, 54, 5, 8, YELLOW },
			{ "o", 57, 52, 5, 9, YELLOW },
			{ "o", 14, 12, 8, 12, ORANGE },
		}),
	},
	{
		id = "stonks",
		name = "Stonks",
		quote = "La flecha verde solo sube",
		length = 4.5,
		color = rgb(120, 140, 230),
		unlock = { kind = "food", value = 3 },
		icon = with(Emotes.ant({ x = -10, y = 6, headScale = 0.9, legs = { { 160, 20 }, nil, nil, { 300, 300 } } }), {
			{ "l", 37, 40, 14, 3, GREEN, -50 },
			{ "l", 46, 36, 10, 3, GREEN, 40 },
			{ "l", 54, 24, 22, 3, GREEN, -60 },
			{ "d", 60, 13, 8, 8, GREEN },
		}),
	},
	{
		id = "sus",
		name = "¿Sus?",
		quote = "Agachada. Antenas de periscopio",
		length = 4.5,
		color = rgb(255, 110, 110),
		unlock = { kind = "rebirths", value = 1 },
		icon = with(
			Emotes.ant({
				y = 8,
				headY = -2,
				legs = { { 150, 150 }, { 180, 160 }, { 200, 170 }, { 30, 30 }, { 0, 20 }, { 340, 10 } },
				ant = { 265, 275 },
				eyes = "side",
			}),
			{ { "t", 52, 8, 16, 18, INK, 10, "?" } }
		),
	},
	{
		id = "f",
		name = "F",
		quote = "Saludo solemne. Una F gigante",
		length = 4.5,
		color = rgb(255, 214, 80),
		unlock = { kind = "trophies", value = 3 },
		icon = with(Emotes.ant({ x = -12, headScale = 0.85, legs = { nil, nil, nil, { 250, 200 } }, ant = { 230, 310 }, eyes = "closed" }), {
			{ "r", 50, 32, 6, 40, YELLOW },
			{ "r", 56, 14, 18, 6, YELLOW },
			{ "r", 55, 30, 14, 6, YELLOW },
		}),
	},
	{
		id = "heli",
		name = "Helicóptero",
		quote = "Antenas de hélice. Despega un poco",
		loop = true,
		color = rgb(140, 220, 200),
		unlock = { kind = "depth", value = 6 },
		icon = with(Emotes.ant({ y = 2, ant = { 180, 0 }, legs = { { 130, 100 }, { 110, 95 }, { 100, 90 } } }), {
			{ "c", 32, 7, 50, 10, INK },
		}),
	},
	{
		id = "breakdance",
		name = "Breakdance",
		quote = "Gira sobre el lomo, patas al aire",
		loop = true,
		color = rgb(255, 150, 60),
		unlock = { kind = "rebirths", value = 3 },
		tilt = 180,
		icon = with(Emotes.ant({ legs = { { 240, 280 }, { 220, 250 }, { 200, 230 }, { 300, 260 }, { 320, 290 }, { 340, 310 } } }), {
			{ "c", 32, 34, 58, 58, INK },
		}),
	},
	{
		id = "mind",
		name = "Cabeza explotando",
		quote = "La cabeza se hincha. ¡Galaxia!",
		length = 4,
		color = rgb(130, 100, 220),
		unlock = { kind = "food", value = 5 },
		icon = with(Emotes.ant({ y = 8, headScale = 1.25, eyes = "look" }), {
			{ "o", 22, 7, 16, 12, PURPLE },
			{ "o", 40, 5, 18, 12, PINK },
			{ "o", 31, 3, 12, 9, BLUE },
			{ "o", 14, 4, 4, 4, WHITE },
			{ "o", 50, 9, 4, 4, WHITE },
			{ "o", 33, 9, 3, 3, YELLOW },
		}),
	},
	{
		id = "worthy",
		name = "No somos dignas",
		quote = "Reverencias ante otra jugadora",
		length = 4.5,
		color = rgb(255, 240, 170),
		unlock = { kind = "trophies", value = 8 },
		icon = with(
			Emotes.ant({
				y = 10,
				headY = 10,
				legs = { { 250, 250 }, { 290, 290 } },
				ant = { 200, 340 },
				eyes = "closed",
			}),
			{ { "d", 12, 8, 6, 6, YELLOW }, { "d", 52, 6, 6, 6, YELLOW }, { "d", 32, 4, 4, 4, YELLOW } }
		),
	},
}

Emotes.byId = {}
for i, def in Emotes.list do
	def.index = i
	def.loop = def.loop == true
	Emotes.byId[def.id] = def
end

-- Rueda de serie: los gratis y dos huecos libres que se llenan con lo que vayas consiguiendo
Emotes.DefaultWheel = { "dab", "tpose", "floss", "bruh", "clap", "npc", "", "" }

-- Lista "a,b,,c" → tabla de 8 ids ("" = hueco vacío). Sirve para los atributos.
function Emotes.decode(text: any, size: number?): { string }
	local out = {}
	if type(text) == "string" and text ~= "" then
		for id in (text .. ","):gmatch("([^,]*),") do
			table.insert(out, id)
		end
	end
	if size then
		for i = 1, size do
			out[i] = out[i] or ""
		end
		for i = #out, size + 1, -1 do
			out[i] = nil
		end
	end
	return out
end

return Emotes
