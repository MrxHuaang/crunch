-- Casta Ácida: charcos y lluvia que disuelven la comida solos.
-- Lógica en src/server/Castes/acid.luau, efectos en src/client/Castes/acid.luau.

return {
	id = "acid",
	name = "Ácida",
	motto = "Tú muerdes. El ácido termina.",
	color = Color3.fromRGB(150, 230, 30),
	accent = Color3.fromRGB(140, 60, 200),
	depth = 4,
	style = {
		"Lo que muerdes se sigue deshaciendo después",
		"Deja charcos donde va a pasar la comida y sigue a lo tuyo",
		"Mucho daño, pero sin prisa",
	},
	passive = {
		id = "corrode",
		name = "Corrosión",
		desc = "Lo que muerdes sigue disolviéndose: el {pct} % del daño en {time} s, hasta {max} comidas a la vez.",
		params = { share = 0.5, pct = 50, time = 3, max = 3, spread = 12, popDelay = 1.5, popRadius = 6, popSplash = 0.3 },
	},
	abilities = {
		{
			id = "acid1",
			slot = 1,
			rank = 1,
			name = "Escupitajo",
			cooldown = 8,
			aim = "ground",
			range = 40,
			desc = "Una bola en arco que deja un charco de radio {radius} durante {life} s: {bites} mordisco cada 0,5 s a lo que pise.",
			params = { radius = 11, life = 6, every = 0.5, bites = 1, flight = 0.55, fan = 20, geyserBites = 6 },
		},
		{
			id = "acid2",
			slot = 2,
			rank = 3,
			name = "Estela cáustica",
			cooldown = 18,
			aim = "self",
			range = 0,
			desc = "Durante {life} s dejas un charco cada {spacing} studs que dura {puddleLife} s.",
			params = { life = 5, spacing = 4, puddleLife = 4, radius = 4.5, every = 0.5, bites = 0.8, cloudRadius = 9 },
		},
		{
			id = "acid3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Diluvio fórmico",
			cooldown = 80,
			aim = "ground",
			range = 50,
			desc = "Lluvia ácida en radio {radius} durante {life} s ({bites} mordiscos cada 0,5 s). Lo que termina revienta en burbujas.",
			params = { radius = 32, life = 9, every = 0.5, bites = 1.5, bubbleRadius = 9, bubbleBites = 3, followRadius = 20, shrinkTo = 12, growTo = 2.5 },
		},
	},
	mutations = {
		{
			rank = 2,
			options = {
				{
					id = "acid_2a",
					name = "Ácido contagioso",
					desc = "Si una comida corroída se acaba, el ácido salta a la más cercana con lo que le quedaba.",
					mods = {},
					flags = { "spread" },
				},
				{
					id = "acid_2b",
					name = "Quemadura",
					desc = "Sin goteo: el ácido aguanta 1,5 s y revienta de golpe, salpicando a las vecinas.",
					mods = { { key = "corrode.share", set = 0.6 }, { key = "corrode.pct", set = 60 } },
					flags = { "burst" },
				},
			},
		},
		{
			rank = 4,
			options = {
				{
					id = "acid_4a",
					name = "Ráfaga",
					desc = "Escupes tres bolas en abanico; cada charco es más pequeño y dura menos.",
					mods = { { key = "acid1.radius", set = 6 }, { key = "acid1.life", set = 4 } },
					flags = { "spitFan" },
				},
				{
					id = "acid_4b",
					name = "Géiser",
					desc = "El charco dura solo 3 s, pero al secarse estalla en un chorro que arranca 6 mordiscos.",
					mods = { { key = "acid1.life", set = 3 } },
					flags = { "geyser" },
				},
			},
		},
		{
			rank = 5,
			options = {
				{
					id = "acid_5a",
					name = "Nube cáustica",
					desc = "En vez de charcos, una nube tóxica te envuelve y disuelve todo lo que roza.",
					mods = {},
					flags = { "cloud" },
				},
				{
					id = "acid_5b",
					name = "Pisadas",
					desc = "Charcos grandes cada 10 studs que duran el doble: siembra el camino.",
					mods = { { key = "acid2.spacing", set = 10 }, { key = "acid2.radius", set = 7 }, { key = "acid2.puddleLife", mul = 2 } },
					flags = { "bigSteps" },
				},
			},
		},
		{
			rank = 7,
			options = {
				{
					id = "acid_7a",
					name = "Tifón ácido",
					desc = "El Diluvio te sigue a todas partes, con un radio más pequeño.",
					mods = {},
					flags = { "rainFollow" },
				},
				{
					id = "acid_7b",
					name = "Monzón",
					desc = "La lluvia se cierra poco a poco sobre el centro y pega cada vez más fuerte.",
					mods = {},
					flags = { "monsoon" },
				},
			},
		},
		{
			rank = 9,
			options = {
				{
					id = "acid_9a",
					name = "Empapada",
					desc = "Lo que pisa tus charcos queda corroído y recibe un 50 % más de tus habilidades.",
					mods = {},
					flags = { "soak" },
				},
				{
					id = "acid_9b",
					name = "Charcos volátiles",
					desc = "Cada charco, al secarse, revienta y arranca 3 mordiscos a lo que tenga encima.",
					mods = {},
					flags = { "volatile" },
				},
			},
		},
	},
}
