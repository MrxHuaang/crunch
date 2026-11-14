-- Herramientas de desarrollo, solo en Studio: el panel DEV (cliente DevPanel, RemoteEvent "Dev") y la
-- barra de comandos (BindableEvent CrunchDebug). Fuera de Studio no se crea nada y register no hace nada.
--
-- Para que un evento nuevo salga en el panel, su módulo llama al arrancar:
--   DevTools.register("id", "Nombre en el panel", function(profile) ... return "mensaje" end)
-- run devuelve el texto que verá el panel (nil = "Hecho"). Las zonas, capas, pases y productos el panel
-- los lee de Config: no hay que tocar nada aquí al añadirlos.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Monetize = require(script.Parent.Monetize)
local PlayerService = require(script.Parent.PlayerService)
local Profiles = require(script.Parent.Profiles)
local Shop = require(script.Parent.Shop)

local DevTools = {}

local BAD = "Valor no válido"
local events = {} :: { { id: string, label: string, run: (any) -> string? } }

function DevTools.register(id: string, label: string, run: (any) -> string?)
	if not RunService:IsStudio() then
		return
	end
	table.insert(events, { id = id, label = label, run = run })
end

local function number(a: any, min: number, max: number): number?
	if type(a) ~= "number" or a ~= a or a < min or a > max then
		return nil
	end
	return a
end

-- Árbol al tope de la capa `depth` (lo que se puede comprar hasta ahí)
local function maxTree(data, depth: number)
	data.depth = depth
	for _, def in Config.Tree do
		if not def.unit then
			data.nodes[def.id] = if def.layer > depth then 0 else Stats.available(def, depth)
		end
	end
end

-- Galerías de las capas ya excavadas
local function allMinis(data)
	for _, def in Config.Minis do
		if def.layer <= data.depth then
			data.minis[def.id] = true
		end
	end
end

-- Comandos de la barra de comandos (CrunchDebug), los mismos de siempre
local function apply(profile, command: string, a: any, b: any)
	local data = profile.data
	if command == "food" then
		Profiles.addFood(profile, a)
	elseif command == "node" then
		data.nodes[a] = b
	elseif command == "royal" then
		data.royal[a] = b
	elseif command == "workers" then
		data.workers = a
	elseif command == "jelly" then
		data.jelly = a
	elseif command == "depth" then
		data.depth = math.clamp(a, 1, Stats.MaxDepth)
	elseif command == "rebirths" then
		data.rebirths = a
	elseif command == "tarta" then
		data.tartaDone = true
	elseif command == "grant" then
		Monetize.debugGrant(profile, a) -- pase o producto, por su id de Config
	elseif command == "minis" then
		allMinis(data)
	elseif command == "max" then
		maxTree(data, math.clamp(a, 1, Stats.MaxDepth))
	end
	Profiles.refresh(profile)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function travel(profile, position: Vector3): boolean
	local root = rootOf(profile.player)
	if not root then
		return false
	end
	local character = profile.player.Character :: Model
	character:PivotTo(CFrame.new(position + Vector3.new(0, 1.5 * character:GetScale(), 0)))
	root.AssemblyLinearVelocity = Vector3.zero
	PlayerService.moved(profile, position)
	return true
end

-- Acciones del panel, solo para quien pulsa. Devuelven el mensaje que se muestra.
local actions: { [string]: (any, any) -> string } = {}

function actions.food(profile, a)
	local amount = number(a, 1, 1e300)
	if not amount then
		return BAD
	end
	Profiles.addFood(profile, amount)
	Profiles.refresh(profile)
	return "+" .. Format.short(amount) .. " de comida"
end

function actions.jelly(profile, a)
	local amount = number(a, 1, 1e300)
	if not amount then
		return BAD
	end
	profile.data.jelly += amount
	Profiles.refresh(profile)
	return "+" .. Format.short(amount) .. " de jalea"
end

function actions.rebirths(profile, a)
	local n = number(a, 0, 100)
	if not n or n % 1 ~= 0 then
		return BAD
	end
	profile.data.rebirths = n
	Profiles.refresh(profile)
	return "Enjambres: " .. n
end

function actions.prepare(profile, a)
	local depth = number(a, 1, Stats.MaxDepth)
	if not depth or depth % 1 ~= 0 then
		return BAD
	end
	-- Desde una partida limpia: bajar de capa no deja mejoras ni galerías de capas más hondas
	Shop.resetRun(profile)
	maxTree(profile.data, depth)
	allMinis(profile.data)
	Profiles.refresh(profile)
	profile.player:LoadCharacter()
	return "Capa " .. depth .. " lista"
end

function actions.reset(profile)
	Shop.resetRun(profile)
	profile.player:LoadCharacter()
	return "Partida reiniciada"
end

function actions.grant(profile, a)
	local def = Monetize.find(a)
	if not def then
		return BAD
	end
	Monetize.debugGrant(profile, a)
	Profiles.refresh(profile)
	return "Entregado: " .. def.name
end

function actions.zone(profile, a)
	local zone = type(a) == "number" and Config.Zones[a] or nil
	if not zone then
		return BAD
	end
	-- El mismo punto al que llevan las alas: la entrada de la zona
	if not travel(profile, Vector3.new(0, Config.GroundY + 3, zone.z0 - 12)) then
		return "Sin personaje"
	end
	return "Viajando a " .. zone.name
end

function actions.home(profile)
	local spawn = profile.hill and profile.hill:FindFirstChild("Spawn")
	if not spawn or not spawn:IsA("BasePart") then
		return "Sin hormiguero"
	end
	if not travel(profile, spawn.Position) then
		return "Sin personaje"
	end
	return "En casa"
end

function actions.event(profile, a)
	for _, entry in events do
		if entry.id == a then
			local ok, result = pcall(entry.run, profile)
			if not ok then
				warn("[CRUNCH!] DEV: el evento", a, "falló:", result)
				return "El evento falló (mira la consola)"
			end
			return if type(result) == "string" then result else "Hecho"
		end
	end
	return BAD
end

local function onDev(player: Player, kind: any, action: any, a: any)
	if not RunService:IsStudio() then
		return
	end
	local remote = ReplicatedStorage.Remotes:FindFirstChild("Dev") :: RemoteEvent
	if kind == "List" then
		local list = {}
		for _, entry in events do
			table.insert(list, { id = entry.id, label = entry.label })
		end
		remote:FireClient(player, "List", list)
		return
	end
	if kind ~= "Do" then
		return
	end
	local profile = Profiles.get(player)
	if not profile then
		remote:FireClient(player, "Done", "Sin perfil")
		return
	end
	local handler = type(action) == "string" and actions[action] or nil
	remote:FireClient(player, "Done", if handler then handler(profile, a) else BAD)
end

function DevTools.start(remotes: Folder)
	if not RunService:IsStudio() then
		return
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = "Dev"
	remote.OnServerEvent:Connect(onDev)
	remote.Parent = remotes

	-- Barra de comandos de Studio, en vista de servidor (aplica a todos los jugadores):
	-- game.ServerScriptService.CrunchDebug:Fire("food", 5000)
	local debug = Instance.new("BindableEvent")
	debug.Name = "CrunchDebug"
	debug.Event:Connect(function(command: string, a: any, b: any)
		for _, profile in Profiles.all() do
			apply(profile, command, a, b)
		end
	end)
	debug.Parent = ServerScriptService
end

return DevTools
