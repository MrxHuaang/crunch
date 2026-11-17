local ReplicatedStorage = game:GetService("ReplicatedStorage")
local started = os.clock() -- cuánto tarda en levantarse el mundo (ver el mensaje del final)
-- Cuánto pesa cada parte del arranque, para el mismo mensaje; lo de menos de 0,05 s no se lista
local laps, lapAt = {}, started
local function lap(name: string)
	local now = os.clock()
	if now - lapAt >= 0.05 then
		table.insert(laps, string.format("%s %.1f", name, now - lapAt))
	end
	lapAt = now
end

local World = require(script.World)
local FoodService = require(script.FoodService)
local Profiles = require(script.Profiles)
local PlayerService = require(script.PlayerService)
local Colony = require(script.Colony)
local Nest = require(script.Nest)
local Leaderboard = require(script.Leaderboard)
local Shop = require(script.Shop)
local DevTools = require(script.DevTools)
lap("require")

-- El mundo y los remotos existen antes de aceptar jugadores
World.build()
lap("World.build")
-- Hormigueros de zona: después del decorado (lo despejan) y sin retrasar el arranque; la entrega
-- solo usa Config.depotPos, no el modelo
task.spawn(require(script.Depots).build)
lap("Depots")

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
for _, name in { "Bite", "Fx", "Buy", "Trail", "Frenzy", "Rebirth", "Wear" } do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
end
remotes.Parent = ReplicatedStorage
Profiles.fx = remotes.Fx

FoodService.start(World.hillCenters)
lap("FoodService.start")
Colony.start(remotes)
lap("Colony")
Shop.start(remotes)
lap("Shop")
Nest.start(remotes)
lap("Nest")
Leaderboard.start()
lap("Leaderboard")
require(script.Monetize).start()
lap("Monetize")
PlayerService.start(remotes)
lap("PlayerService")
DevTools.start(remotes) -- panel DEV y CrunchDebug: solo en Studio, fuera de Studio no crea nada
lap("DevTools")

-- Módulos opcionales (misiones, eventos, mascotas, peligros, aliadas, comida dorada, mordida en
-- cadena, túnel): se arrancan si existen.
for _, name in { "Quests", "WorldEvents", "PetService", "Hazards", "Allies", "GoldFood", "Chain", "Tunnel", "Extras", "Perks", "Garden", "Opening", "CasteService", "Social", "Orders", "Emotes", "Stalls", "Analytics" } do
	local module = script:FindFirstChild(name)
	if module then
		local ok, lib = pcall(require, module)
		if ok and type(lib) == "table" and lib.start then
			task.spawn(lib.start, remotes)
		elseif not ok then
			warn("[CRUNCH!] No se pudo cargar", name, lib)
		end
		lap(name)
	end
end

print(string.format("[CRUNCH!] servidor listo en %.1f s (%s)", os.clock() - started, table.concat(laps, ", ")))
