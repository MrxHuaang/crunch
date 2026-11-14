-- Mascotas: bichos del jardín que salen de huevos y te siguen. Aquí viven los números
-- (precios, rarezas, bonos) y las fórmulas que comparten servidor y cliente.
-- El poder de un bicho = bono base x rareza x capa del huevo x peso de su tipo de bono.

local Config = require(script.Parent.Config)

local PetDefs = {}

PetDefs.MaxPets = 30
PetDefs.MaxEquipped = 3
PetDefs.MaxLayer = #Config.Layers

-- Huevo: EggBase x StageGrowth^(capa - 1) x CostScale. Con CostScale 0.5 el primero cuesta 300.
PetDefs.EggBase = 600
PetDefs.EggGrowth = 1.12 -- cada huevo más en la misma capa (y la misma partida) cuesta un 12 % más
PetDefs.EggsPerSecond = 4

-- Tres comunes de la misma capa suman +25 %; tres legendarias, x2.5 (calibrado en capa 1, bono de comida)
PetDefs.BaseBonus = 0.25 / 3
PetDefs.LayerGrowth = 0.15 -- cada capa del huevo, un 15 % más de poder (capa 14: x2.95)
PetDefs.MaxMult = 4 -- tope de lo que suman las mascotas a una misma estadística

PetDefs.Rarities = {
	{ name = "Común", chance = 60, mult = 1, color = Color3.fromRGB(214, 206, 188) },
	{ name = "Rara", chance = 27, mult = 2, color = Color3.fromRGB(62, 193, 243) },
	{ name = "Épica", chance = 10, mult = 3.5, color = Color3.fromRGB(170, 104, 236) },
	{ name = "Legendaria", chance = 2.7, mult = 6, color = Color3.fromRGB(255, 210, 63) },
	{ name = "Mítica", chance = 0.3, mult = 12, color = Color3.fromRGB(255, 84, 160) },
}

-- Tipos de bono. stat: campo de profile.stats que multiplican. weight: la comida ya sube
-- también lo que traen las obreras, así que los demás tipos pesan algo más (y la jalea, menos).
PetDefs.Bonuses = {
	food = { name = "comida", stat = "foodMult", weight = 1, color = Color3.fromRGB(255, 210, 63) },
	colony = { name = "colonia", stat = "colonyMult", weight = 1.3, color = Color3.fromRGB(110, 200, 90) },
	bite = { name = "mordida", stat = "biteDamage", weight = 1.5, color = Color3.fromRGB(230, 57, 70) },
	jelly = { name = "jalea", stat = "jellyMult", weight = 0.5, color = Color3.fromRGB(62, 193, 243) },
}
PetDefs.BonusOrder = { "food", "colony", "bite", "jelly" }

-- gait: cómo sigue a su dueña. "hop" saltitos, "crawl" se arrastra, "fly" vuela.
PetDefs.Species = {
	{ id = "mariquita", name = "Mariquita", bonus = "food", gait = "hop" },
	{ id = "pulgon", name = "Pulgón", bonus = "food", gait = "hop" },
	{ id = "oruga", name = "Oruga", bonus = "food", gait = "crawl" },
	{ id = "escarabajoOro", name = "Escarabajo de oro", bonus = "food", gait = "hop" },
	{ id = "caracol", name = "Caracol", bonus = "colony", gait = "crawl" },
	{ id = "bichoBola", name = "Bicho bola", bonus = "colony", gait = "crawl" },
	{ id = "grillo", name = "Grillo", bonus = "colony", gait = "hop" },
	{ id = "arana", name = "Arañita", bonus = "colony", gait = "crawl" },
	{ id = "escarabajo", name = "Escarabajo rino", bonus = "bite", gait = "hop" },
	{ id = "libelula", name = "Libélula", bonus = "bite", gait = "fly" },
	{ id = "rana", name = "Ranita", bonus = "bite", gait = "hop" },
	{ id = "abeja", name = "Abeja", bonus = "jelly", gait = "fly" },
	{ id = "luciernaga", name = "Luciérnaga", bonus = "jelly", gait = "fly" },
	{ id = "mariposa", name = "Mariposa", bonus = "jelly", gait = "fly" },
}

PetDefs.SpeciesById = {}
for _, def in PetDefs.Species do
	PetDefs.SpeciesById[def.id] = def
end

function PetDefs.eggPrice(depth: number, bought: number?): number
	local layer = math.clamp(math.floor(depth), 1, PetDefs.MaxLayer)
	return math.floor(PetDefs.EggBase * Config.StageGrowth ^ (layer - 1) * Config.CostScale * PetDefs.EggGrowth ^ (bought or 0))
end

-- Una entrada de mascota: { id = número, s = especie, r = rareza 1..5, l = capa del huevo }
function PetDefs.valid(entry: any): boolean
	return type(entry) == "table"
		and PetDefs.SpeciesById[entry.s] ~= nil
		and type(entry.r) == "number"
		and PetDefs.Rarities[entry.r] ~= nil
		and type(entry.l) == "number"
		and entry.l >= 1
		and entry.l <= PetDefs.MaxLayer
end

function PetDefs.factor(layer: number): number
	return 1 + PetDefs.LayerGrowth * (layer - 1)
end

-- Lo que suma este bicho a su estadística (0.08 = +8 %)
function PetDefs.power(entry): number
	local species = PetDefs.SpeciesById[entry.s]
	local rarity = PetDefs.Rarities[entry.r]
	if not species or not rarity then
		return 0
	end
	return PetDefs.BaseBonus * rarity.mult * PetDefs.factor(entry.l or 1) * PetDefs.Bonuses[species.bonus].weight
end

function PetDefs.bonusOf(entry)
	local species = PetDefs.SpeciesById[entry.s]
	return if species then PetDefs.Bonuses[species.bonus] else nil
end

-- Multiplicador por tipo de bono de una lista de bichos puestos, con tope.
function PetDefs.totals(entries): { [string]: number }
	local sums = { food = 0, colony = 0, bite = 0, jelly = 0 }
	for _, entry in entries do
		local species = PetDefs.SpeciesById[entry.s]
		if species then
			sums[species.bonus] += PetDefs.power(entry)
		end
	end
	local totals = {}
	for kind, sum in sums do
		totals[kind] = math.min(1 + sum, PetDefs.MaxMult)
	end
	return totals
end

-- Mismo bicho a efectos de fusión: especie y rareza. La capa del huevo no cuenta: exigirla
-- dejaba el inventario lleno de bichos "casi iguales" que no se podían juntar, sin explicación.
function PetDefs.kind(entry): string
	return entry.s .. "|" .. entry.r
end

function PetDefs.roll(rng: Random): (string, number)
	local species = PetDefs.Species[rng:NextInteger(1, #PetDefs.Species)].id
	local total = 0
	for _, rarity in PetDefs.Rarities do
		total += rarity.chance
	end
	local pick = rng:NextNumber() * total
	for index, rarity in PetDefs.Rarities do
		pick -= rarity.chance
		if pick < 0 then
			return species, index
		end
	end
	return species, 1
end

-- "+8 %"
function PetDefs.percent(x: number): string
	return "+" .. math.floor(x * 100 + 0.5) .. " %"
end

-- "x1.25"
function PetDefs.times(x: number): string
	return "x" .. (string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", ""))
end

-- "2,7 %"
function PetDefs.chance(x: number): string
	local text = if x == math.floor(x) then tostring(x) else (string.format("%.1f", x):gsub("%.", ","))
	return text .. " %"
end

-- Atributo PetsEquipped: "mariquita:2,abeja:1" (especie:rareza, en orden de hueco)
function PetDefs.encode(entries): string
	local parts = {}
	for _, entry in entries do
		table.insert(parts, entry.s .. ":" .. entry.r)
	end
	return table.concat(parts, ",")
end

function PetDefs.decode(text: any): { { s: string, r: number } }
	local list = {}
	if type(text) ~= "string" then
		return list
	end
	for species, rarity in text:gmatch("([%w_]+):(%d+)") do
		local r = tonumber(rarity)
		if PetDefs.SpeciesById[species] and r and PetDefs.Rarities[r] then
			table.insert(list, { s = species, r = r })
		end
		if #list >= PetDefs.MaxEquipped then
			break
		end
	end
	return list
end

return PetDefs
