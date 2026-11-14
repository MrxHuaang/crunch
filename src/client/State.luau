-- Lo que el cliente sabe de tu partida. Todo llega del servidor como atributos del jugador.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)

local State = {}

local player = Players.LocalPlayer
local listeners: { () -> () } = {}
local dirty = true
local cachedNodes, cachedRoyal, cachedStats
local cachedMinis, minisSource -- galerías: el conjunto y el texto del que salió

function State.num(name: string): number
	return player:GetAttribute(name) or 0
end

function State.flag(name: string): boolean
	return player:GetAttribute(name) == true
end

function State.depth(): number
	return player:GetAttribute("Depth") or 1
end

-- ¿Tienes ya esta prenda del vestidor?
function State.owns(id: string): boolean
	local owned = player:GetAttribute("Owned") or ""
	return ("," .. owned .. ","):find("," .. id .. ",", 1, true) ~= nil
end

-- Jalea que daría enjambrar ahora mismo (misma cuenta que el servidor).
function State.jellyNow(): number
	-- El multiplicador llega del servidor: incluye los pases de juego
	local gain = Stats.jellyFor(State.num("RunFood"), player:GetAttribute("JellyMult") or 1)
	if State.flag("TartaDone") then
		gain *= Config.Rebirth.TartaMult
	end
	return gain
end

-- Galerías: llegan en un solo atributo, un carácter por galería en el orden de Config.Minis.
-- Sin atributo (los primeros fotogramas) o vacío: ninguna. Solo se decodifica si cambió.
function State.minis(): { [string]: boolean }
	local raw = player:GetAttribute("Minis")
	if type(raw) ~= "string" then
		raw = ""
	end
	if cachedMinis and raw == minisSource then
		return cachedMinis
	end
	local set = {}
	for i, def in Config.Minis do
		if string.byte(raw, i) == 49 then -- "1"
			set[def.id] = true
		end
	end
	cachedMinis = set
	minisSource = raw
	return set
end

local function rebuild()
	cachedNodes = {}
	for _, def in Config.Tree do
		if not def.unit then
			cachedNodes[def.id] = State.num("N_" .. def.id)
		end
	end
	cachedRoyal = {}
	for _, def in Config.Royal do
		cachedRoyal[def.id] = State.num("R_" .. def.id)
	end
	cachedStats = Stats.derive(cachedNodes, cachedRoyal, State.depth(), State.minis())
	-- La carga real la decide el servidor (las castas pueden cambiarla): manda su atributo
	local capacity = player:GetAttribute("Capacity")
	if type(capacity) == "number" and capacity > 0 then
		cachedStats.capacity = capacity
	end
end

function State.nodes()
	if not cachedNodes then
		rebuild()
	end
	return cachedNodes
end

function State.royal()
	if not cachedRoyal then
		rebuild()
	end
	return cachedRoyal
end

function State.stats()
	if not cachedStats then
		rebuild()
	end
	return cachedStats
end

function State.now(): number
	return Workspace:GetServerTimeNow()
end

-- Tu hormiguero en el mapa, o nil si aún no te asignaron uno.
function State.hill(): Model?
	local hills = Workspace:FindFirstChild("Anthills")
	if not hills then
		return nil
	end
	for _, hill in hills:GetChildren() do
		if hill:IsA("Model") and hill:GetAttribute("OwnerId") == player.UserId then
			return hill
		end
	end
	return nil
end

-- Avisa, como mucho una vez por fotograma, cuando cambia cualquier dato de la partida.
function State.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

-- Solo los niveles, la jalea real, la profundidad y las galerías cambian las estadísticas:
-- la comida cambia a cada rato y no hace falta recalcularlas por ella.
local STAT_ATTRIBUTES = { Depth = true, Minis = true, Capacity = true }

player.AttributeChanged:Connect(function(name: string)
	local head = string.sub(name, 1, 2)
	if head == "N_" or head == "R_" or STAT_ATTRIBUTES[name] then
		cachedNodes = nil
		cachedRoyal = nil
		cachedStats = nil
	end
	dirty = true
end)

RunService.Heartbeat:Connect(function()
	if dirty then
		dirty = false
		for _, fn in listeners do
			task.spawn(fn)
		end
	end
end)

return State
