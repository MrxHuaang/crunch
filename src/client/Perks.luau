-- Aviso de las reglas con nombre de las galerías (src/server/Perks.luau): cuando una salta, un
-- estallido corto con su nombre donde pasó y, si dio comida, el número. Nada se queda en pantalla.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Sfx = require(script.Parent.Sfx)

local Perks = {}

-- Color del estallido según la rama de la regla
local COLORS = { M = Comic.Red, P = Comic.Cyan, C = Comic.Green, F = Comic.Yellow }
local branchOf = {}
for key, list in Config.MiniTune.PerkOrder do
	for _, id in list do
		branchOf[id] = key
	end
end

function Perks.start(remotes: Folder)
	local fx = remotes:WaitForChild("Fx") :: RemoteEvent
	fx.OnClientEvent:Connect(function(kind: string, position: any, id: any, amount: any)
		if kind ~= "Perk" or typeof(position) ~= "Vector3" or type(id) ~= "string" then
			return
		end
		local perk = Config.MiniTune.Perks[id]
		if not perk then
			return
		end
		Fx.burst(position, "¡" .. perk.name .. "!", COLORS[branchOf[id]] or Comic.Yellow, 170)
		if type(amount) == "number" and amount > 0 then
			Fx.number(position + Vector3.new(0, 1.5, 0), amount, false, branchOf[id] == "F")
		end
		Sfx.pop(1.45)
	end)
end

return Perks
