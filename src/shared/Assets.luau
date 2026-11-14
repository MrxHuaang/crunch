-- Ids de las imágenes y sonidos. Las imágenes salen de art/gen_art.py y se subieron desde Studio.

local function id(n: number): string
	return "rbxassetid://" .. n
end

local Assets = {
	Halftone = id(111311200815805),
	Burst = id(121672764284650),
	Vignette = id(129151109977736),
	SpeedLines = id(132816261715925),
	SkySide = id(81040033707191),
	SkyTop = id(81600058838220),
	SkyBottom = id(123530089434509),

	Icons = {
		bite = id(125595171366059),
		crit = id(110462204616068),
		saw = id(96955688572988),
		area = id(89458801613751),
		speed = id(137178184621097),
		carry = id(120382697661702),
		sprint = id(95334513161864),
		wings = id(132094963473001),
		nursery = id(87432738540664),
		workers = id(133988829777781),
		workerSpeed = id(131123345679973),
		workerCarry = id(77894406548190),
		barracks = id(125911543202975),
		queen = id(101036629953844),
		storage = id(96001986496180),
		trail = id(139657336830623),
		frenzy = id(77586512216169),
		smart = id(118414119966081),
		royalFood = id(81342642311807),
		royalBite = id(123976685468926),
		royalColony = id(100669123007773),
		royalStart = id(124901877208727),
		royalSpeed = id(130818636316249),
		anthill = id(126658414702390),
	},

	-- Música de fondo, del catálogo libre de Roblox. Se reproduce en orden aleatorio con silencios entre temas.
	-- Para cambiarla, busca audio en la Creator Store y pega aquí el id.
	-- La idea es música de fogata, acústica y tranquila (guitarra, banjo), al estilo de Outer Wilds.
	-- Son temas del catálogo de APM elegidos por búsqueda: escúchalos y quita los que no encajen.
	Music = {
		id(1845854912), -- Moonrise
		id(1840540809), -- Sunset Song
		id(1845854860), -- After The Rain
		id(1840471940), -- A Delicate Art
		id(1837127200), -- High Chords
		id(1840970401), -- Tranquil Time
	},

	Sounds = {
		Bite = { id(9125467298), id(9125466463) },
		Pop = id(106984966606682),
	},
}

return Assets
