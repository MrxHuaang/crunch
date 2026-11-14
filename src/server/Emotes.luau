-- Emotes de memes (servidor): valida y reenvía a todas. El cliente pide "Play"; aquí se mira que
-- lo tengas, que hayan pasado Emotes.Cooldown s desde el anterior y que no vayas por el aire
-- (seta, alas, pisotón…). Si vale, se reenvía a todos los clientes y cada uno anima tu hormiga.
-- Morder corta el emote; moverse lo corta cada cliente por su cuenta.
--
-- Combo: si una jugadora responde con cualquier emote en Emotes.ComboWindow s a otra que lo hizo a
-- menos de Emotes.ComboRange studs, todos ven "¡COMBO DE MEMES!" sobre las dos. Solo visual.
--
-- Guardado (perezoso): data.emotes = { [id] = true } emotes conseguidos o comprados (los gratis no
-- hace falta guardarlos); data.emoteWheel = { 8 ids } la rueda elegida ("" = hueco vacío).
-- Atributos de la jugadora: "Emotes" (ids que tiene, separados por comas, gratis incluidos) y
-- "EmoteWheel" (los 8 de la rueda, separados por comas).
-- Remoto "Emote":
--   cliente -> servidor: "Play" id · "Stop" · "Buy" id · "Wheel" { ids }
--   servidor -> todos:   "Play" jugadora id semilla · "Stop" jugadora · "Combo" jugadoraA jugadoraB
--   servidor -> dueña:   "Unlocked" id (conseguido jugando) · "Bought" id

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage.Shared.Emotes)
local Events = require(script.Parent.Events)
local Profiles = require(script.Parent.Profiles)

local Emotes = {}

local remote: RemoteEvent
-- [jugadora] = { id, at, loop, length, done = { [otra] = true } }: el último emote, para cortarlo y
-- para el combo. Se borra al salir.
local last: { [Player]: any } = {}
local lastAt: { [Player]: number } = {}
local primed: { [Player]: boolean } = {} -- ya se sincronizó una vez (no avisar de lo de siempre)

local function trophyCount(data): number
	local n = 0
	if type(data.trophies) == "table" then
		for _ in data.trophies do
			n += 1
		end
	end
	return n
end

local function ensure(profile)
	local data = profile.data
	if type(data.emotes) ~= "table" then
		data.emotes = {}
	end
	if type(data.emoteWheel) ~= "table" then
		data.emoteWheel = table.clone(Defs.DefaultWheel)
	end
end

local function owns(profile, def): boolean
	return def.unlock.kind == "free" or profile.data.emotes[def.id] == true
end

local function inWheel(wheel, id: string): boolean
	return table.find(wheel, id) ~= nil
end

-- Lo nuevo entra solo en el primer hueco libre de la rueda
local function addToWheel(profile, id: string)
	local wheel = profile.data.emoteWheel
	if inWheel(wheel, id) then
		return
	end
	for i = 1, Defs.WheelSize do
		if wheel[i] == nil or wheel[i] == "" then
			wheel[i] = id
			return
		end
	end
end

local function sync(profile)
	local data = profile.data
	local have = {}
	for _, def in Defs.list do
		if owns(profile, def) then
			table.insert(have, def.id)
		end
	end
	local wheel = {}
	for i = 1, Defs.WheelSize do
		local id = data.emoteWheel[i]
		wheel[i] = if type(id) == "string" and Defs.byId[id] and owns(profile, Defs.byId[id]) then id else ""
	end
	profile.player:SetAttribute("Emotes", table.concat(have, ","))
	profile.player:SetAttribute("EmoteWheel", table.concat(wheel, ","))
end

-- Lo que se consigue jugando (capa, enjambres, trofeos) se queda para siempre
local function grant(profile)
	ensure(profile)
	local data = profile.data
	local trophies = trophyCount(data)
	local player = profile.player
	for _, def in Defs.list do
		local kind = def.unlock.kind
		if kind ~= "free" and kind ~= "food" and not data.emotes[def.id] and Defs.earned(def, data.depth, data.rebirths, trophies) then
			data.emotes[def.id] = true
			addToWheel(profile, def.id)
			if primed[player] then
				remote:FireClient(player, "Unlocked", def.id)
			end
		end
	end
	sync(profile)
	primed[player] = true
end

local function airborne(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return true
	end
	return humanoid.FloorMaterial == Enum.Material.Air and math.abs(root.AssemblyLinearVelocity.Y) > 8
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- ¿Responde `player` al emote reciente de otra que está cerca?
local function checkCombo(player: Player, now: number)
	local mine = rootOf(player)
	if not mine then
		return
	end
	for other, record in last do
		if other ~= player and other.Parent and now - record.at <= Defs.ComboWindow and not record.done[player] then
			local theirs = rootOf(other)
			if theirs and (theirs.Position - mine.Position).Magnitude <= Defs.ComboRange then
				record.done[player] = true
				-- La respuesta tampoco puede volver a encadenar con la misma
				local answer = last[player]
				if answer then
					answer.done[other] = true
				end
				remote:FireAllClients("Combo", other, player)
				return
			end
		end
	end
end

local function play(player: Player, id: any)
	local profile = Profiles.get(player)
	local def = type(id) == "string" and Defs.byId[id]
	if not profile or not def then
		return
	end
	ensure(profile)
	if not owns(profile, def) then
		return
	end
	local now = os.clock()
	if now - (lastAt[player] or -math.huge) < Defs.Cooldown then
		return
	end
	local character = player.Character
	if not character or airborne(character) then
		return
	end
	lastAt[player] = now
	last[player] = { id = def.id, at = now, loop = def.loop, length = def.length or 0, done = {} }
	remote:FireAllClients("Play", player, def.id, math.random(1, 1e6))
	checkCombo(player, now)
end

-- Corta el emote que siga en marcha (pulsar otra vez o morder)
local function stop(player: Player)
	local record = last[player]
	if not record or record.stopped then
		return
	end
	if record.loop or os.clock() - record.at < record.length then
		record.stopped = true
		remote:FireAllClients("Stop", player)
	end
end

local function buy(player: Player, id: any)
	local profile = Profiles.get(player)
	local def = type(id) == "string" and Defs.byId[id]
	if not profile or not def or def.unlock.kind ~= "food" then
		return
	end
	ensure(profile)
	local data = profile.data
	if data.emotes[def.id] then
		return
	end
	local cost = Defs.price(def)
	if data.food < cost then
		return
	end
	data.food -= cost
	data.emotes[def.id] = true
	addToWheel(profile, def.id)
	Profiles.refresh(profile) -- comida y atributos (este módulo se apunta a onRefresh)
	remote:FireClient(player, "Bought", def.id)
end

local function setWheel(player: Player, list: any)
	local profile = Profiles.get(player)
	if not profile or type(list) ~= "table" then
		return
	end
	ensure(profile)
	local wheel = {}
	local seen = {}
	for i = 1, Defs.WheelSize do
		local id = list[i]
		local def = type(id) == "string" and Defs.byId[id]
		if def and owns(profile, def) and not seen[id] then
			seen[id] = true
			wheel[i] = id
		else
			wheel[i] = ""
		end
	end
	profile.data.emoteWheel = wheel
	sync(profile)
end

local function onRequest(player: Player, action: any, a: any)
	if action == "Play" then
		play(player, a)
	elseif action == "Stop" then
		stop(player)
	elseif action == "Buy" then
		buy(player, a)
	elseif action == "Wheel" then
		setWheel(player, a)
	end
end

function Emotes.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Emote"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	table.insert(Profiles.onRefresh, grant)
	Events.on("Bite", function(profile)
		stop(profile.player)
	end)

	for _, profile in Profiles.all() do
		grant(profile)
	end

	Players.PlayerRemoving:Connect(function(player)
		last[player] = nil
		lastAt[player] = nil
		primed[player] = nil
		for _, record in last do
			record.done[player] = nil
		end
	end)
end

return Emotes
