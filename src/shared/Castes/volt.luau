-- Casta Voltaica: rayos que saltan entre muchas comidas. Mejor donde la comida está junta.
-- Lógica en src/server/Castes/volt.luau, efectos en src/client/Castes/volt.luau.

return {
	id = "volt",
	name = "Voltaica",
	motto = "Muerde una, caen ocho.",
	color = Color3.fromRGB(255, 221, 51),
	accent = Color3.fromRGB(64, 196, 255),
	depth = 2,
	style = {
		"Muchas comidas a la vez: cada mordisco salta a las de al lado",
		"Brilla donde la comida está apiñada",
		"Planta bobinas y muerde dentro de ellas para que resuenen",
	},
	passive = {
		id = "arc",
		name = "Arco",
		desc = "Cada mordisco salta a {targets} comidas a menos de {range} studs con el {pct} % del daño.",
		params = { targets = 2, range = 14, share = 0.4, pct = 40, novaEvery = 10, novaRadius = 16, novaBites = 3, staticTime = 4 },
	},
	abilities = {
		{
			id = "volt1",
			slot = 1,
			rank = 1,
			name = "Descarga",
			cooldown = 7,
			aim = "food",
			range = 45,
			desc = "Un rayo que encadena {jumps} comidas y arranca {bites} mordiscos a cada una.",
			params = { jumps = 8, bites = 3, hop = 18, lance = 15, width = 6 },
		},
		{
			id = "volt2",
			slot = 2,
			rank = 3,
			name = "Bobina",
			cooldown = 18,
			aim = "ground",
			range = 30,
			desc = "Planta una bobina {life} s que lanza rayos a {targets} comidas en radio {radius} ({bites} mordiscos). Muerde dentro y resuena.",
			params = { life = 8, every = 0.6, targets = 3, radius = 22, bites = 1.2, pairBites = 1.5 },
		},
		{
			id = "volt3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Tormenta",
			cooldown = 75,
			aim = "self",
			range = 0,
			desc = "Una nube te sigue {life} s y suelta {rate} rayos por segundo en radio {radius} ({bites} mordiscos). Lo que termina, estalla.",
			params = { life = 8, rate = 4, radius = 35, bites = 4, sparkRadius = 9, sparkBites = 1.5, forks = 2 },
		},
	},
	mutations = {
		{
			rank = 2,
			options = {
				{
					id = "volt_2a",
					name = "Arco largo",
					desc = "El arco salta a 2 comidas más y llega 4 studs más lejos.",
					mods = { { key = "arc.targets", add = 2 }, { key = "arc.range", add = 4 } },
				},
				{
					id = "volt_2b",
					name = "Alto voltaje",
					desc = "Un solo arco grueso que pega dos veces y media más fuerte.",
					mods = { { key = "arc.share", mul = 2.5 }, { key = "arc.pct", mul = 2.5 }, { key = "arc.targets", set = 1 } },
					flags = { "arcHeavy" },
				},
			},
		},
		{
			rank = 4,
			options = {
				{
					id = "volt_4a",
					name = "Rayo bifurcado",
					desc = "La Descarga se parte en dos en cada salto: un árbol de rayos, cada rama algo más floja.",
					mods = { { key = "volt1.bites", mul = 0.7 } },
					flags = { "forkBolt" },
				},
				{
					id = "volt_4b",
					name = "Lanza de rayo",
					desc = "La Descarga no salta: atraviesa en línea recta todo lo que pilla, más lejos y más fuerte.",
					mods = { { key = "volt1.bites", mul = 1.5 } },
					flags = { "lanceBolt" },
				},
			},
		},
		{
			rank = 5,
			options = {
				{
					id = "volt_5a",
					name = "Bobina orbital",
					desc = "La Bobina deja de estar fija: te orbita con la mitad de radio y dispara más rápido.",
					mods = { { key = "volt2.radius", mul = 0.5 }, { key = "volt2.every", mul = 0.75 } },
					flags = { "coilOrbit" },
				},
				{
					id = "volt_5b",
					name = "Par de bobinas",
					desc = "Plantas dos bobinas que se pasan el rayo: todo lo que cruza entre ellas se fríe.",
					mods = { { key = "volt2.targets", set = 2 } },
					flags = { "coilPair" },
				},
			},
		},
		{
			rank = 7,
			options = {
				{
					id = "volt_7a",
					name = "Ojo del huracán",
					desc = "La Tormenta se queda donde la llamas, más pequeña pero con casi el doble de rayos.",
					mods = { { key = "volt3.radius", mul = 0.7 }, { key = "volt3.rate", mul = 1.75 } },
					flags = { "stormFixed" },
				},
				{
					id = "volt_7b",
					name = "Supercélula",
					desc = "Menos rayos, pero cada uno salta a 2 comidas más antes de apagarse.",
					mods = { { key = "volt3.rate", set = 2.5 } },
					flags = { "stormChain" },
				},
			},
		},
		{
			rank = 9,
			options = {
				{
					id = "volt_9a",
					name = "Sobrecarga",
					desc = "Cada 10 mordiscos sueltas una nova que muerde todo a tu alrededor.",
					mods = {},
					flags = { "overload" },
				},
				{
					id = "volt_9b",
					name = "Electricidad estática",
					desc = "Lo que toca tu arco queda cargado 4 s: tus habilidades le pegan el doble y lo hacen estallar.",
					mods = {},
					flags = { "staticMark" },
				},
			},
		},
	},
}
