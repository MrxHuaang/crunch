-- Casta Exploradora: velocidad, embestidas en línea y saltos.
-- Lógica en src/server/Castes/scout.luau, efectos en src/client/Castes/scout.luau.

return {
	id = "scout",
	name = "Exploradora",
	motto = "Si corres, muerdes más fuerte.",
	color = Color3.fromRGB(255, 140, 30),
	accent = Color3.fromRGB(255, 255, 255),
	depth = 3,
	style = {
		"Corre para cargar impulso y suéltalo en un mordisco",
		"Embiste en línea por las filas de comida",
		"Nunca te quedes quieta",
	},
	passive = {
		id = "draft",
		name = "Rebufo",
		desc = "Correr carga impulso en {time} s; el siguiente mordisco lo gasta: hasta ×{max} y atraviesa {pierce} studs.",
		params = { time = 3, max = 4, pierce = 10, pierceWidth = 4, pierceShare = 0.7, sparkRadius = 5, sparkBites = 1, sparkEvery = 0.5 },
	},
	abilities = {
		{
			id = "scout1",
			slot = 1,
			rank = 1,
			name = "Embestida",
			cooldown = 6,
			aim = "direction",
			range = 32,
			desc = "Un acelerón de {length} studs que muerde todo en la línea con {bites} mordiscos.",
			params = { length = 32, width = 7, bites = 4, time = 0.28, zigAngle = 35, ramMult = 4, ramRadius = 8, ramBites = 2, refund = 1.5 },
		},
		{
			id = "scout2",
			slot = 2,
			rank = 3,
			name = "Salto de pulga",
			cooldown = 20,
			aim = "ground",
			range = 70,
			desc = "Saltas al punto y al caer sueltas una onda de {bites} mordiscos en radio {radius}. Reinicia la Embestida.",
			params = { radius = 9, bites = 3, hops = 2, hopRange = 22, hopBites = 2 },
		},
		{
			id = "scout3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Estampida",
			cooldown = 75,
			aim = "self",
			range = 0,
			desc = "{life} s a velocidad ×{speed} con una manada fantasma: todo lo que tocas (radio {radius}) recibe {bites} mordiscos cada 0,2 s.",
			params = { life = 7, speed = 2, radius = 8, every = 0.2, bites = 2, herdEvery = 0.5, herdLength = 22, herdBites = 2, blast = 6, blastBites = 3 },
		},
	},
	mutations = {
		{
			rank = 2,
			options = {
				{
					id = "scout_2a",
					name = "Rebufo largo",
					desc = "El impulso tarda el doble en cargarse, pero llega hasta ×7.",
					mods = { { key = "draft.time", set = 6 }, { key = "draft.max", set = 7 } },
				},
				{
					id = "scout_2b",
					name = "Chispazo",
					desc = "Con el impulso al máximo muerdes todo lo que adelantas corriendo, sin pararte.",
					mods = {},
					flags = { "sparkRun" },
				},
			},
		},
		{
			rank = 4,
			options = {
				{
					id = "scout_4a",
					name = "Zigzag",
					desc = "La Embestida da dos quiebros en zeta: barre mucho más ancho.",
					mods = {},
					flags = { "zigzag" },
				},
				{
					id = "scout_4b",
					name = "Ariete",
					desc = "La Embestida se estrella contra la primera comida: cuatro veces más fuerte y una onda alrededor.",
					mods = {},
					flags = { "ram" },
				},
			},
		},
		{
			rank = 5,
			options = {
				{
					id = "scout_5a",
					name = "Rebote",
					desc = "Al caer del Salto rebotas dos veces más hacia las comidas más cercanas.",
					mods = {},
					flags = { "bounce" },
				},
				{
					id = "scout_5b",
					name = "Aterrizaje sísmico",
					desc = "Saltas menos lejos, pero caes como una roca: onda mucho más ancha y fuerte.",
					mods = { { key = "scout2.range", set = 45 }, { key = "scout2.radius", set = 16 }, { key = "scout2.bites", set = 4.5 } },
					flags = { "quake" },
				},
			},
		},
		{
			rank = 7,
			options = {
				{
					id = "scout_7a",
					name = "Manada suelta",
					desc = "Las fantasmas se separan y embisten solas en todas direcciones; tú corres algo menos.",
					mods = { { key = "scout3.speed", set = 1.5 } },
					flags = { "herd" },
				},
				{
					id = "scout_7b",
					name = "Cometa",
					desc = "Mucho más rápida y de cerca: cada comida que tocas estalla y salpica a las vecinas.",
					mods = { { key = "scout3.speed", set = 2.6 }, { key = "scout3.radius", set = 5 } },
					flags = { "comet" },
				},
			},
		},
		{
			rank = 9,
			options = {
				{
					id = "scout_9a",
					name = "Segundo aire",
					desc = "Cada comida que termina tu Embestida le quita 1,5 s de enfriamiento.",
					mods = {},
					flags = { "secondWind" },
				},
				{
					id = "scout_9b",
					name = "Viento de cola",
					desc = "La Embestida y el Salto te llenan el impulso: el siguiente mordisco sale al máximo.",
					mods = {},
					flags = { "tailwind" },
				},
			},
		},
	},
}
