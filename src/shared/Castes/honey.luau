-- Melera: miel que hace valer más la comida y una carga que fermenta. Lógica en server/Castes/honey,
-- efectos en client/Castes/honey. Los parámetros en tanto por ciento (pct) se dividen entre 100 en la lógica.

return {
	id = "honey",
	name = "Melera",
	motto = "Paciencia: lo bueno se fermenta.",
	color = Color3.fromRGB(255, 170, 30), -- ámbar
	accent = Color3.fromRGB(255, 226, 92), -- miel dorada
	depth = 8,
	style = {
		"Cuanto más tiempo llevas la carga, más vale",
		"Baña la comida en miel antes de que la coma tu colonia",
		"Mejor con viajes largos y comida cara",
	},
	passive = {
		id = "fermento",
		name = "Fermento",
		desc = "Tu carga fermenta: +{ratePct} % de valor por segundo, hasta +{maxPct} %. Se reinicia al entregar.",
		params = { ratePct = 4, maxPct = 100, keepPct = 0, bitePct = 0 },
	},
	abilities = {
		{
			id = "honey1",
			slot = 1,
			rank = 1,
			name = "Néctar",
			cooldown = 10,
			aim = "ground",
			range = 35,
			desc = "Bola de miel de radio {radius}: las comidas bañadas valen x{mult} durante {duration} s para ti y tu colonia.",
			params = { radius = 12, mult = 2.5, duration = 8, poolBites = 1 },
		},
		{
			id = "honey2",
			slot = 2,
			rank = 3,
			name = "Bola de miel",
			cooldown = 20,
			aim = "self",
			range = 0,
			desc = "Te haces bola {duration} s y ruedas x{speed}: aplastas en radio {radius} y lo aplastado se te pega (hasta x{over} de tu carga).",
			params = { duration = 4, speed = 1.8, radius = 7, bites = 2, over = 1.5, hopBites = 4, hopRadius = 10 },
		},
		{
			id = "honey3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Reventón dorado",
			cooldown = 90,
			aim = "self",
			range = 0,
			desc = "Explosión de néctar de radio {radius}: {bites} mordiscos a todo y lo que quede en pie vale x{gold} durante {duration} s.",
			params = { radius = 28, bites = 8, gold = 3, duration = 10 },
		},
	},
	mutations = {
		{ rank = 2, options = {
			{ id = "honey_2a", name = "Hidromiel", desc = "Fermenta despacio (+2 %/s), pero llega hasta +200 %.",
				mods = { { key = "fermento.ratePct", set = 2 }, { key = "fermento.maxPct", set = 200 } } },
			{ id = "honey_2b", name = "Miel fresca", desc = "Fermenta rapidísimo (+10 %/s), pero solo hasta +50 %.",
				mods = { { key = "fermento.ratePct", set = 10 }, { key = "fermento.maxPct", set = 50 } } },
		} },
		{ rank = 4, options = {
			{ id = "honey_4a", name = "Charco de miel", desc = "El Néctar deja un charco que muerde a lo que hay dentro cada segundo.",
				mods = {}, flags = { "nectarPool" } },
			{ id = "honey_4b", name = "Gota concentrada", desc = "El Néctar baña solo la comida más cercana, pero x5.",
				mods = { { key = "honey1.radius", set = 5 }, { key = "honey1.mult", set = 5 } }, flags = { "nectarDrop" } },
		} },
		{ rank = 5, options = {
			{ id = "honey_5a", name = "Bola gigante", desc = "Bola de radio 11 y 5 s, pero ruedas x1.4.",
				mods = { { key = "honey2.radius", set = 11 }, { key = "honey2.duration", set = 5 }, { key = "honey2.speed", set = 1.4 } } },
			{ id = "honey_5b", name = "Bola rebotona", desc = "No ruedas: botas. Cada bote aplasta en radio 10 con 4 mordiscos.",
				mods = {}, flags = { "ballBounce" } },
		} },
		{ rank = 7, options = {
			{ id = "honey_7a", name = "Lluvia de miel", desc = "Sin explosión: llueve oro 10 s sobre las comidas de alrededor, que se vuelven doradas una a una.",
				mods = {}, flags = { "burstRain" } },
			{ id = "honey_7b", name = "Corazón de oro", desc = "Explosión de radio 14, pero 16 mordiscos y lo que quede vale x5.",
				mods = { { key = "honey3.radius", set = 14 }, { key = "honey3.bites", set = 16 }, { key = "honey3.gold", set = 5 } } },
		} },
		{ rank = 9, options = {
			{ id = "honey_9a", name = "Madre de la miel", desc = "Al entregar, tu carga nueva empieza con la mitad del fermento.",
				mods = { { key = "fermento.keepPct", set = 50 } } },
			{ id = "honey_9b", name = "Miel ácida", desc = "Tus mordiscos pegan más cuanto más fermentada va tu carga (hasta +60 %).",
				mods = { { key = "fermento.bitePct", set = 60 } } },
		} },
	},
}
