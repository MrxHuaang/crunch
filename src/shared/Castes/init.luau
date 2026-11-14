-- Castas: índice de las ocho definiciones (cada una es un hijo de este módulo, `<id>.luau`) y las
-- utilidades que comparten servidor y cliente. Una definición que falte o falle al cargarse no
-- rompe las demás: simplemente no sale. Esquema de cada definición: ver la cabecera de volt.luau.
--
--   Castes.get(id)            definición o nil
--   Castes.list()             definiciones cargadas, en el orden del juego
--   Castes.rankOf(xp)         rango 1..MaxRank con esa experiencia acumulada
--   Castes.xpFor(rank)        experiencia acumulada que pide ese rango
--   Castes.ability(def, slot) habilidad del hueco 1, 2 o 3
--   Castes.resolve(def, muts, rank?) -> objeto con .param(id, key) y .has(flag)
--        (también vale `local param, has = Castes.resolve(...)`). muts = { ["2"] = 1, ["4"] = 2 }
--        con la opción elegida (1 = A, 2 = B) de cada rango; con `rank`, se ignoran las de más arriba.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Castes = {}

Castes.Order = { "volt", "reaper", "porter", "scout", "acid", "weaver", "general", "honey" }

local C = Config.Castes or {}
local MAX_RANK = C.MaxRank or 10
Castes.MaxRank = MAX_RANK
Castes.MutationRanks = C.MutationRanks or { 2, 4, 5, 7, 9 }

local byId: { [string]: any } = {}
local list: { any } = {}

-- Lo mínimo para que el panel y el servidor no tropiecen con una definición a medias
local function valid(def: any, id: string): (boolean, string?)
	if type(def) ~= "table" then
		return false, "no devuelve una tabla"
	end
	if def.id ~= id then
		return false, "su id no coincide con el nombre del archivo"
	end
	if type(def.name) ~= "string" or typeof(def.color) ~= "Color3" then
		return false, "le falta name o color"
	end
	if type(def.abilities) ~= "table" or type(def.passive) ~= "table" then
		return false, "le faltan passive o abilities"
	end
	return true, nil
end

for _, id in Castes.Order do
	local child = script:FindFirstChild(id)
	if child and child:IsA("ModuleScript") then
		local ok, def = pcall(require, child)
		local good, why = false, tostring(def)
		if ok then
			good, why = valid(def, id)
		end
		if good then
			def.accent = if typeof(def.accent) == "Color3" then def.accent else def.color
			def.depth = tonumber(def.depth) or 2
			def.style = if type(def.style) == "table" then def.style else {}
			def.mutations = if type(def.mutations) == "table" then def.mutations else {}
			def.motto = if type(def.motto) == "string" then def.motto else ""
			byId[id] = def
			table.insert(list, def)
		else
			warn("[CRUNCH!] Casta", id, "no se pudo cargar:", why)
		end
	end
end

function Castes.get(id: any)
	return if type(id) == "string" then byId[id] else nil
end

function Castes.list(): { any }
	return list
end

-- Experiencia acumulada que pide el rango `rank` (el 1 no pide nada)
function Castes.xpFor(rank: number): number
	local r = math.clamp(math.floor(rank), 1, MAX_RANK)
	if r <= 1 then
		return 0
	end
	return math.floor((C.XpBase or 40) * (r - 1) ^ (C.XpPow or 2.2) + 0.5)
end

function Castes.rankOf(xp: number?): number
	local value = tonumber(xp) or 0
	local rank = 1
	for r = 2, MAX_RANK do
		if value >= Castes.xpFor(r) then
			rank = r
		else
			break
		end
	end
	return rank
end

function Castes.ability(def: any, slot: number)
	if type(def) ~= "table" or type(def.abilities) ~= "table" then
		return nil
	end
	for _, ability in def.abilities do
		if ability.slot == slot then
			return ability
		end
	end
	return def.abilities[slot]
end

-- Busca una habilidad por su id
function Castes.abilityById(def: any, id: string)
	if type(def) ~= "table" then
		return nil
	end
	for _, ability in def.abilities or {} do
		if ability.id == id then
			return ability
		end
	end
	return nil
end

-- Las opciones elegidas, en orden de rango (las de rango por encima de `rank` no cuentan)
local function chosen(def, muts: any, rank: number?): { any }
	local picked = {}
	if type(muts) ~= "table" then
		return picked
	end
	local levels = table.clone(def.mutations or {})
	table.sort(levels, function(a, b)
		return (a.rank or 0) < (b.rank or 0)
	end)
	for _, level in levels do
		if rank and (level.rank or 0) > rank then
			continue
		end
		local choice = tonumber(muts[tostring(level.rank)] or muts[level.rank])
		local option = choice and level.options and level.options[choice]
		if option then
			table.insert(picked, option)
		end
	end
	return picked
end

-- Valor base de un parámetro de la pasiva o de una habilidad. `cooldown` y `range` son campos de la
-- habilidad; cualquier otra clave sale de `params`.
local function baseValue(def, id: string, key: string): any
	local passive = def.passive
	if passive and passive.id == id then
		local params = passive.params or {}
		if params[key] ~= nil then
			return params[key]
		end
		return passive[key]
	end
	local ability = Castes.abilityById(def, id)
	if ability then
		local params = ability.params or {}
		if key == "cooldown" or key == "range" then
			if ability[key] ~= nil then
				return ability[key]
			end
			return params[key]
		end
		if params[key] ~= nil then
			return params[key]
		end
		return ability[key]
	end
	return nil
end

function Castes.resolve(def: any, muts: any, rank: number?)
	local options = if type(def) == "table" then chosen(def, muts, rank) else {}
	local cache: { [string]: any } = {}
	local flags: { [string]: boolean } = {}
	for _, option in options do
		for _, flag in option.flags or {} do
			flags[flag] = true
		end
	end

	local resolved = {}

	local function param(a: any, b: any, c: any): any
		-- Admite resolved.param(id, key), resolved:param(id, key) y param(id, key)
		if a == resolved then
			a, b = b, c
		end
		local id, key = tostring(a), tostring(b)
		local full = id .. "." .. key
		local hit = cache[full]
		if hit ~= nil then
			return hit
		end
		local value = if type(def) == "table" then baseValue(def, id, key) else nil
		if value == nil or type(value) == "number" then
			local n = value or 0
			local touched = value ~= nil
			for _, option in options do
				for _, mod in option.mods or {} do
					if mod.key == full then
						touched = true
						if mod.set ~= nil then
							n = tonumber(mod.set) or n
						end
						if mod.add ~= nil then
							n += tonumber(mod.add) or 0
						end
						if mod.mul ~= nil then
							n *= tonumber(mod.mul) or 1
						end
					end
				end
			end
			value = if touched then n else 0
		end
		cache[full] = value
		return value
	end

	local function has(a: any, b: any): boolean
		if a == resolved then
			a = b
		end
		return flags[tostring(a)] == true
	end

	resolved.param = param
	resolved.has = has
	resolved.options = options -- opciones elegidas que cuentan (para el panel)
	setmetatable(resolved, {
		__call = function(_, id, key)
			return param(id, key)
		end,
	})
	return resolved, has
end

-- Sustituye {clave} en un texto con el valor ya resuelto (para el panel)
function Castes.fill(text: string?, resolved: any, id: string): string
	if type(text) ~= "string" then
		return ""
	end
	return (text:gsub("{([%w_]+)}", function(key)
		local value = resolved.param(id, key)
		if type(value) ~= "number" then
			return tostring(value)
		end
		if math.abs(value - math.floor(value + 0.5)) < 1e-6 then
			return tostring(math.floor(value + 0.5))
		end
		local text2 = string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
		return (text2:gsub("%.", ","))
	end))
end

return Castes
