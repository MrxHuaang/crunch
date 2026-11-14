-- Comandante: manda a las obreras y a los soldados. Lógica en server/Castes/general, efectos en client/Castes/general.
-- Los parámetros en tanto por ciento (pct) se dividen entre 100 en la lógica.

return {
	id = "general",
	name = "Comandante",
	motto = "¡Colonia, a mi señal!",
	color = Color3.fromRGB(34, 52, 112), -- azul marino
	accent = Color3.fromRGB(255, 196, 48), -- oro
	depth = 6,
	style = {
		"Tu colonia rinde más si vas con ella",
		"Marca la comida grande y deja que la asalten",
		"Mejor con muchas obreras",
	},
	passive = {
		id = "estandarte",
		name = "Estandarte",
		desc = "Tus obreras a menos de {radius} studs de ti trabajan x{mult}.",
		params = { radius = 40, mult = 1.5 },
	},
	abilities = {
		{
			id = "general1",
			slot = 1,
			rank = 1,
			name = "¡A por esa!",
			cooldown = 12,
			aim = "food",
			range = 50,
			desc = "Marcas una comida: hasta {crew} obreras la asaltan {duration} s y lo que saquen vale x{worth}.",
			params = { crew = 12, duration = 8, worth = 2, chain = 4 },
		},
		{
			id = "general2",
			slot = 2,
			rank = 3,
			name = "Falange",
			cooldown = 25,
			aim = "self",
			range = 0,
			desc = "{soldiers} soldados en formación {duration} s: cada vez que muerdes, cada uno muerde lo más cercano con el {sharePct} % de tu mordisco.",
			params = { soldiers = 6, sharePct = 60, duration = 12, reach = 16, every = 0.8 },
		},
		{
			id = "general3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Marabunta",
			cooldown = 90,
			aim = "direction",
			range = 100,
			desc = "Una ola de hormigas de {width} de ancho barre {length} studs: {bites} mordiscos a todo lo que pilla.",
			params = { width = 30, length = 100, bites = 12, speed = 60 },
		},
	},
	mutations = {
		{ rank = 2, options = {
			{ id = "general_2a", name = "Estandarte alto", desc = "El estandarte llega a 70 studs, pero solo da x1.25.",
				mods = { { key = "estandarte.radius", set = 70 }, { key = "estandarte.mult", set = 1.25 } } },
			{ id = "general_2b", name = "A mi lado", desc = "Solo 20 studs, pero tus obreras trabajan x2.2.",
				mods = { { key = "estandarte.radius", set = 20 }, { key = "estandarte.mult", set = 2.2 } } },
		} },
		{ rank = 4, options = {
			{ id = "general_4a", name = "Asalto total", desc = "¡A por esa! lanza a TODA la colonia, 5 s y x1.5.",
				mods = { { key = "general1.duration", set = 5 }, { key = "general1.worth", set = 1.5 } }, flags = { "rushAll" } },
			{ id = "general_4b", name = "Botín de guerra", desc = "Solo 6 obreras, pero al acabar la comida la orden salta a la más cercana y dura 4 s más.",
				mods = { { key = "general1.crew", set = 6 } }, flags = { "rushChain" } },
		} },
		{ rank = 5, options = {
			{ id = "general_5a", name = "Tortuga", desc = "La Falange forma un anillo a tu alrededor y todos muerden lo mismo que tú, al 40 %.",
				mods = { { key = "general2.sharePct", set = 40 } }, flags = { "phalanxRing" } },
			{ id = "general_5b", name = "Lanceros", desc = "4 soldados que atacan solos cada 0.8 s aunque no muerdas, al 50 %.",
				mods = { { key = "general2.soldiers", set = 4 }, { key = "general2.sharePct", set = 50 } }, flags = { "phalanxLance" } },
		} },
		{ rank = 7, options = {
			{ id = "general_7a", name = "Remolino", desc = "La Marabunta gira a tu alrededor en un círculo de radio 26: 10 mordiscos.",
				mods = { { key = "general3.bites", set = 10 } }, flags = { "swarmVortex" } },
			{ id = "general_7b", name = "Doble ola", desc = "Dos olas en V, más estrechas (18) y de 9 mordiscos.",
				mods = { { key = "general3.width", set = 18 }, { key = "general3.bites", set = 9 } }, flags = { "swarmTwin" } },
		} },
		{ rank = 9, options = {
			{ id = "general_9a", name = "Veteranas", desc = "La Falange lleva 2 soldados más y dura 6 s más.",
				mods = { { key = "general2.soldiers", add = 2 }, { key = "general2.duration", add = 6 } } },
			{ id = "general_9b", name = "Corneta", desc = "Cada habilidad que lanzas hace que toda tu colonia trabaje x2 durante 4 s.",
				mods = {}, flags = { "hornRally" } },
		} },
	},
}
