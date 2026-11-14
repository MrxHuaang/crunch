-- Tejedora: hilos que atan, arrastran y reparten. Lógica en server/Castes/weaver, efectos en client/Castes/weaver.
-- Los parámetros en tanto por ciento (pct) se dividen entre 100 en la lógica.

return {
	id = "weaver",
	name = "Tejedora",
	motto = "Todo lo que toco, lo ato. Todo lo que ato, es mío.",
	color = Color3.fromRGB(250, 246, 255), -- seda
	accent = Color3.fromRGB(220, 96, 220), -- rosa violeta
	depth = 5,
	style = {
		"Muerde una y las atadas también pierden trozos",
		"Junta la comida en montones antes de morder",
		"Mejor donde hay muchas comidas medianas",
	},
	passive = {
		id = "hilo",
		name = "Hilo",
		desc = "Cada comida que muerdes queda atada a ti {life} s (hasta {max}). Las atadas reciben el {sharePct} % de cada mordisco.",
		params = { max = 3, life = 6, sharePct = 35, pull = 3 },
	},
	abilities = {
		{
			id = "weaver1",
			slot = 1,
			rank = 1,
			name = "Red",
			cooldown = 10,
			aim = "ground",
			range = 40,
			desc = "Una red de radio {radius} arrastra las comidas al centro en un montón y las ata {tie} s.",
			params = { radius = 14, tie = 6, snapBites = 3 },
		},
		{
			id = "weaver2",
			slot = 2,
			rank = 3,
			name = "Capullo",
			cooldown = 22,
			aim = "food",
			range = 30,
			desc = "Envuelves una comida y un hilo la remolca a tu hormiguero en {time} s (hasta {cap} mordiscos de valor).",
			params = { cap = 40, time = 4, count = 1, burstBites = 4, burstRadius = 10 },
		},
		{
			id = "weaver3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Telaraña",
			cooldown = 80,
			aim = "ground",
			range = 45,
			desc = "Telaraña de radio {radius} durante {duration} s: tu daño a una comida de la tela pega el {sharePct} % a las demás. Sobre ella corres x{speed}.",
			params = { radius = 30, duration = 12, sharePct = 50, speed = 1.5, maxSpread = 8 },
		},
	},
	mutations = {
		{ rank = 2, options = {
			{ id = "weaver_2a", name = "Madeja", desc = "Hasta 6 hilos a la vez, pero cada uno lleva el 20 %.",
				mods = { { key = "hilo.max", set = 6 }, { key = "hilo.sharePct", set = 20 } } },
			{ id = "weaver_2b", name = "Hilo de acero", desc = "Un solo hilo, pero lleva el 90 % y dura 10 s.",
				mods = { { key = "hilo.max", set = 1 }, { key = "hilo.sharePct", set = 90 }, { key = "hilo.life", set = 10 } } },
		} },
		{ rank = 4, options = {
			{ id = "weaver_4a", name = "Red de pesca", desc = "La Red no hace montón donde cae: tira de la comida hasta tus patas.",
				mods = { { key = "weaver1.radius", add = 4 } }, flags = { "netHaul" } },
			{ id = "weaver_4b", name = "Red pegajosa", desc = "Red más pequeña que al cerrarse muerde 3 veces cada comida y la ata 10 s.",
				mods = { { key = "weaver1.radius", set = 9 }, { key = "weaver1.tie", set = 10 } }, flags = { "netSnap" } },
		} },
		{ rank = 5, options = {
			{ id = "weaver_5a", name = "Tres capullos", desc = "El Capullo envuelve las tres comidas más cercanas (hasta 15 mordiscos cada una).",
				mods = { { key = "weaver2.count", set = 3 }, { key = "weaver2.cap", set = 15 } }, flags = { "cocoonTriple" } },
			{ id = "weaver_5b", name = "Capullo bomba", desc = "El Capullo no viaja: revienta donde está y salpica 4 mordiscos alrededor.",
				mods = {}, flags = { "cocoonBurst" } },
		} },
		{ rank = 7, options = {
			{ id = "weaver_7a", name = "Tela tensa", desc = "Telaraña de radio 18, pero cada golpe pega el 80 % a las demás.",
				mods = { { key = "weaver3.radius", set = 18 }, { key = "weaver3.sharePct", set = 80 } } },
			{ id = "weaver_7b", name = "Tela viajera", desc = "La Telaraña va contigo: radio 20, 9 s, centrada en ti.",
				mods = { { key = "weaver3.radius", set = 20 }, { key = "weaver3.duration", set = 9 } }, flags = { "webFollow" } },
		} },
		{ rank = 9, options = {
			{ id = "weaver_9a", name = "Hilos que tiran", desc = "Las comidas atadas se arrastran despacio hacia ti.",
				mods = {}, flags = { "threadPull" } },
			{ id = "weaver_9b", name = "Nudo final", desc = "Al terminar una comida, sus hilos se rompen de golpe: 3 mordiscos a cada atada.",
				mods = {}, flags = { "threadSnap" } },
		} },
	},
}
