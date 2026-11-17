local ReplicatedStorage = game:GetService("ReplicatedStorage")
local started = os.clock() -- cuánto tarda en levantarse el mundo (ver el mensaje del final)

local World = require(script.World)
local FoodService = require(script.FoodService)
local Profiles = require(script.Profiles)
local PlayerService = require(script.PlayerService)
local Colony = require(script.Colony)
local Nest = require(script.Nest)
local Leaderboard = require(script.Leaderboard)
local Shop = require(script.Shop)
local DevTools = require(script.DevTools)

-- El mundo y los remotos existen antes de aceptar jugadores
World.build()
-- Hormigueros de zona: después del decorado (lo despejan) y sin retrasar el arranque; la entrega
-- solo usa Config.depotPos, no el modelo
task.spawn(require(script.Depots).build)

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
Colony.start(remotes)
Shop.start(remotes)
Nest.start(remotes)
Leaderboard.start()
require(script.Monetize).start()
PlayerService.start(remotes)
DevTools.start(remotes) -- panel DEV y CrunchDebug: solo en Studio, fuera de Studio no crea nada

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
	end
end

print(string.format("[CRUNCH!] servidor listo en %.1f s", os.clock() - started))
