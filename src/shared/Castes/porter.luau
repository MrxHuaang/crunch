-- Porteadora: carga enorme y entregas a distancia. Lógica en server/Castes/porter, efectos en client/Castes/porter.
-- Los parámetros en tanto por ciento (pct) se dividen entre 100 en la lógica: así el panel los lee bien.

return {
	id = "porter",
	name = "Porteadora",
	motto = "Si cabe en el cesto, llega a casa.",
	color = Color3.fromRGB(150, 96, 56), -- cuero
	accent = Color3.fromRGB(48, 214, 200), -- turquesa
	depth = 2,
	style = {
		"Llena el cesto hasta arriba y entrega desde lejos",
		"Cuanto más cargas, más rinde cada viaje",
		"Mejor con comidas grandes y trayectos largos",
	},
	passive = {
		id = "lomo",
		name = "Lomo de hierro",
		desc = "Cargas x{carry}. Entregar con la carga llena vale un {fullPct} % más.",
		params = { carry = 2.5, fullPct = 15 },
	},
	abilities = {
		{
			id = "porter1",
			slot = 1,
			rank = 1,
			name = "Catapulta",
			cooldown = 14,
			aim = "self",
			range = 0,
			desc = "Lanzas toda tu carga al hormiguero desde donde estés. Vuela {flight} s y cuenta como una entrega.",
			params = { flight = 1.3, smashBites = 10, basketTime = 10, basketRadius = 12, cannonPct = 30 },
		},
		{
			id = "porter2",
			slot = 2,
			rank = 3,
			name = "Caravana",
			cooldown = 30,
			aim = "self",
			range = 0,
			desc = "{porters} porteadoras te siguen {duration} s. Cada una repite tu mordisco al {sharePct} % y lo lleva a casa.",
			params = { porters = 4, sharePct = 50, duration = 15, reach = 18, fetchBites = 1.5, fetchEvery = 1.2 },
		},
		{
			id = "porter3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Convoy",
			cooldown = 90,
			aim = "ground",
			range = 80,
			desc = "Un escarabajo-vagón sale del hormiguero hasta el punto: {bites} mordiscos a cada comida a su paso (ancho {width}) y la entrega vale x{worth}.",
			params = { width = 16, bites = 8, worth = 1.5, speed = 45 },
		},
	},
	mutations = {
		{ rank = 2, options = {
			{ id = "porter_2a", name = "Saco sin fondo", desc = "Cargas x3.5, pero la carga llena ya no da extra.",
				mods = { { key = "lomo.carry", set = 3.5 }, { key = "lomo.fullPct", set = 0 } } },
			{ id = "porter_2b", name = "Cuenta justa", desc = "Cargas solo x2, pero la carga llena vale un 40 % más.",
				mods = { { key = "lomo.carry", set = 2 }, { key = "lomo.fullPct", set = 40 } } },
		} },
		{ rank = 4, options = {
			{ id = "porter_4a", name = "Asedio", desc = "La Catapulta cae primero sobre la comida más cercana y la revienta; luego rebota a casa.",
				mods = {}, flags = { "catSiege" } },
			{ id = "porter_4b", name = "Cesto plantado", desc = "La Catapulta deja un cesto en el suelo que sigue recogiendo comida 10 s.",
				mods = {}, flags = { "catBasket" } },
		} },
		{ rank = 5, options = {
			{ id = "porter_5a", name = "Recua larga", desc = "7 porteadoras en la Caravana, cada una al 30 %.",
				mods = { { key = "porter2.porters", set = 7 }, { key = "porter2.sharePct", set = 30 } } },
			{ id = "porter_5b", name = "Mulas sueltas", desc = "Las porteadoras no copian tus mordiscos: forrajean solas a tu alrededor.",
				mods = {}, flags = { "caravanFetch" } },
		} },
		{ rank = 7, options = {
			{ id = "porter_7a", name = "Tren de vagones", desc = "El Convoy son tres vagones seguidos, más estrechos y de 4 mordiscos cada uno.",
				mods = { { key = "porter3.width", set = 11 }, { key = "porter3.bites", set = 4 } }, flags = { "convoyTrain" } },
			{ id = "porter_7b", name = "Arrollar", desc = "El vagón sale desde ti y arrasa el camino: más ancho y 12 mordiscos, pero sin extra de entrega.",
				mods = { { key = "porter3.width", set = 22 }, { key = "porter3.bites", set = 12 }, { key = "porter3.worth", set = 1 } },
				flags = { "convoyRam" } },
		} },
		{ rank = 9, options = {
			{ id = "porter_9a", name = "Gatillo fácil", desc = "Al llenarse la carga, la Catapulta se dispara sola si está lista. Se recarga 4 s antes.",
				mods = { { key = "porter1.cooldown", add = -4 } }, flags = { "catAuto" } },
			{ id = "porter_9b", name = "Bala de cañón", desc = "La Catapulta solo sale con la carga llena, pero la entrega vale un 30 % más.",
				mods = {}, flags = { "catCannon" } },
		} },
	},
}
