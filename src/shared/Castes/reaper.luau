-- Casta Segadora: tajos en área y golpes pesados, con mandíbulas de guadaña.
-- Lógica en src/server/Castes/reaper.luau, efectos en src/client/Castes/reaper.luau.

return {
	id = "reaper",
	name = "Segadora",
	motto = "Lo que está delante, cae.",
	color = Color3.fromRGB(178, 24, 38),
	accent = Color3.fromRGB(240, 228, 200),
	depth = 2,
	style = {
		"Cada mordisco corta todo lo que tienes delante",
		"Cuenta los golpes: el quinto es un tajo pesado",
		"Métete en medio del montón y gira",
	},
	passive = {
		id = "slash",
		name = "Tajo",
		desc = "Tus mordiscos cortan todo en un cono de {angle}° delante de ti al {pct} %. Cada {heavyEvery}.º es un tajo pesado ×{heavyMult}.",
		params = { angle = 70, extra = 4, share = 0.6, pct = 60, heavyEvery = 5, heavyMult = 3, heavyAngle = 140, heavyExtra = 3, executeAt = 0.3, executeMult = 3 },
	},
	abilities = {
		{
			id = "reaper1",
			slot = 1,
			rank = 1,
			name = "Guillotina",
			cooldown = 9,
			aim = "ground",
			range = 28,
			desc = "Saltas y caes como una hoja: {bites} mordiscos en radio {radius}, el doble en el centro.",
			params = { radius = 12, bites = 6, core = 4, coreMult = 2, land = 0.45, boomWidth = 7, boomBites = 3, boomTime = 0.5, shocks = 2, shockBites = 2 },
		},
		{
			id = "reaper2",
			slot = 2,
			rank = 3,
			name = "Torbellino",
			cooldown = 16,
			aim = "self",
			range = 0,
			desc = "Giras {life} s cortando {bites} mordiscos cada 0,25 s en radio {radius}, y vas un 30 % más rápida.",
			params = { life = 3.5, every = 0.25, radius = 10, bites = 1.5, speed = 1.3, travel = 32, extend = 0.4, extendMax = 3 },
		},
		{
			id = "reaper3",
			slot = 3,
			rank = 6,
			ultimate = true,
			name = "Gran Siega",
			cooldown = 70,
			aim = "direction",
			range = 90,
			desc = "Una media luna gigante avanza {length} studs y {width} de ancho: {bites} mordiscos a todo lo que cruza.",
			params = { length = 90, width = 26, bites = 10, time = 1.1, scar = 5, spread = 25, ringRadius = 40 },
		},
	},
	mutations = {
		{
			rank = 2,
			options = {
				{
					id = "reaper_2a",
					name = "Siega ancha",
					desc = "El tajo barre media vuelta (140°), aunque pega algo menos.",
					mods = { { key = "slash.angle", set = 140 }, { key = "slash.share", set = 0.45 }, { key = "slash.pct", set = 45 } },
					flags = { "wideSlash" },
				},
				{
					id = "reaper_2b",
					name = "Estocada",
					desc = "El tajo se vuelve una estocada: una línea estrecha que llega 10 studs más lejos y pega entero.",
					mods = { { key = "slash.angle", set = 20 }, { key = "slash.extra", add = 10 }, { key = "slash.share", set = 1 }, { key = "slash.pct", set = 100 } },
					flags = { "thrust" },
				},
			},
		},
		{
			rank = 4,
			options = {
				{
					id = "reaper_4a",
					name = "Bumerán",
					desc = "La Guillotina ya no salta: lanzas las mandíbulas como un bumerán que corta a la ida y a la vuelta.",
					mods = {},
					flags = { "boomerang" },
				},
				{
					id = "reaper_4b",
					name = "Réplicas",
					desc = "Al caer, el suelo tiembla dos veces más con ondas cada vez más anchas.",
					mods = {},
					flags = { "aftershock" },
				},
			},
		},
		{
			rank = 5,
			options = {
				{
					id = "reaper_5a",
					name = "Tornado errante",
					desc = "No giras tú: sueltas un torbellino que avanza solo hacia delante cortando a su paso.",
					mods = { { key = "reaper2.radius", mul = 0.8 } },
					flags = { "tornado" },
				},
				{
					id = "reaper_5b",
					name = "Danza de cuchillas",
					desc = "Giro más cerrado y mucho más rápido; cada comida que terminas alarga el baile.",
					mods = { { key = "reaper2.radius", set = 7 }, { key = "reaper2.speed", set = 1.6 } },
					flags = { "bladeDance" },
				},
			},
		},
		{
			rank = 7,
			options = {
				{
					id = "reaper_7a",
					name = "Siega en cruz",
					desc = "Dos medias lunas abiertas en aspa, más estrechas, que cubren mucho más suelo.",
					mods = { { key = "reaper3.width", set = 16 }, { key = "reaper3.bites", mul = 0.8 } },
					flags = { "crossReap" },
				},
				{
					id = "reaper_7b",
					name = "Siega circular",
					desc = "La hoja no avanza: sale de ti en un anillo que crece hasta 40 studs.",
					mods = { { key = "reaper3.bites", mul = 0.9 } },
					flags = { "ringReap" },
				},
			},
		},
		{
			rank = 9,
			options = {
				{
					id = "reaper_9a",
					name = "Racha de sangre",
					desc = "El tajo pesado llega cada 3 mordiscos en vez de cada 5.",
					mods = { { key = "slash.heavyEvery", set = 3 } },
				},
				{
					id = "reaper_9b",
					name = "Ejecución",
					desc = "Lo que está por debajo del 30 % de vida recibe el triple de tus tajos y habilidades.",
					mods = {},
					flags = { "execute" },
				},
			},
		},
	},
}
