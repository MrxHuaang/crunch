-- Primeros pasos (ver src/server/Opening.luau): el texto de la meta de ahora para la tira de
-- narración (init.client la consulta en refreshHint y, mientras dura, la tira es suya), la fiesta
-- de cada meta cumplida y el aviso de "ya corrí" al servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)

local AntAnim = require(script.Parent.AntAnim)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Opening = {}

local player = Players.LocalPlayer
local keyboard = UserInputService.KeyboardEnabled
local RUN_TIME = 1.2 -- segundos corriendo (sumados) para dar el paso 4 por hecho

-- Fiesta de cada paso: texto del estallido y frase de la hormiga
local PARTY = {
	{ "¡ÑAM!", "¡Mandíbulas llenas! Ahora, a casa" },
	{ "¡PRIMERA ENTREGA!", "¡Mi primera comida en casa!" },
	{ "¡MEJORA!", "¡Ya muerdo mejor!" },
	{ "¡ZOOM!", "¡Qué velocidad!" },
	{ "¡OBRERA!", "¡Mi primera obrera ya trabaja!" },
	{ "¡CAPA 2!", nil },
}

local function step(): number?
	local value = player:GetAttribute("Opening")
	return if type(value) == "number" and value >= 1 and value <= 6 then value else nil
end

-- Texto de la meta de ahora y si se queda fija (nil: la cadena terminó o no le toca hablar)
function Opening.hint(): (string?, boolean?)
	local current = step()
	if not current then
		return nil, nil
	end
	if current == 1 then
		local count = math.min(tonumber(player:GetAttribute("OpeningCount")) or 0, Config.Opening.Bites)
		local tally = " (" .. count .. "/" .. Config.Opening.Bites .. ")"
		if State.flag("P_autoBite") then
			return "Acércate a una miga: muerdo yo sola" .. tally, true
		end
		return (if keyboard then "Mantén clic junto a una miga" else "Mantén pulsado junto a una miga") .. tally, true
	elseif current == 2 then
		if State.num("Carry") > 0 then
			return "Lleva las migas a tu hormiguero", true
		end
		return "Muerde unas migas y llévalas a tu hormiguero", true
	elseif current == 3 then
		return if keyboard then "Pulsa Q y compra tu primera mejora" else "Toca Hormiguero y compra una mejora", true
	elseif current == 4 then
		return if keyboard then "Mantén Shift para correr" else "Toca Correr y corre por el jardín", true
	elseif current == 5 then
		return if keyboard then "Pulsa Q y cría tu primera obrera" else "Toca Hormiguero y cría una obrera", true
	end
	-- Paso 6: siempre a la vista la meta de la capa 2. Mismo coste que Tree.luau (con la Pala dorada,
	-- atributo HalfDig, a mitad); refreshHint lo vuelve a pedir cada vez que cambia Food.
	local cost = Stats.digCost(1) * (if State.num("HalfDig") > 0 then 0.5 else 1)
	local food = State.num("Food")
	if food >= cost then
		return if keyboard then "¡Ya puedo excavar la capa 2! Pulsa Q" else "¡Ya puedo excavar la capa 2! Toca Hormiguero", true
	end
	return "Capa 2: te faltan " .. Format.short(cost - food) .. " de comida", true
end

local function celebrate(done: number, prize: number)
	local character = player.Character
	local position = if character then character:GetPivot().Position + Vector3.new(0, 3, 0) else nil
	local party = PARTY[done] or PARTY[1]
	local text = party[1] .. (if prize > 0 then "\n+" .. Format.short(prize) else "")
	if position then
		local big = done == 2 or done == 6
		Fx.burst(position, text, if big then Comic.Yellow else Comic.Cyan, if big then 300 else 230)
		Fx.crumbs(position, Comic.Yellow, if big then 18 else 8)
		if big then
			Fx.shake(0.4)
		end
	end
	Sfx.fanfare()
	Hud.punchFood()
	AntAnim.cheer()
	if party[2] then
		Bubble.flash(party[2], 3)
	end
end

function Opening.start(remotes: Folder)
	local remote = remotes:WaitForChild("Opening", 30) :: RemoteEvent?
	if not remote then
		return
	end
	remote.OnClientEvent:Connect(function(kind: string, done: any, prize: any)
		if kind == "Step" and type(done) == "number" then
			celebrate(done, tonumber(prize) or 0)
		end
	end)

	-- Paso 4: correr (lo decide Abilities poniendo la velocidad; aquí se mide)
	local ran = 0
	local sentAt = -math.huge
	RunService.Heartbeat:Connect(function(dt)
		if step() ~= 4 then
			ran = 0
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local walk = State.num("WalkSpeed")
		if walk <= 0 then
			walk = Config.Player.WalkSpeed
		end
		if humanoid.MoveDirection.Magnitude > 0.1 and humanoid.WalkSpeed > walk * 1.2 then
			ran += dt
			if ran >= RUN_TIME and os.clock() - sentAt > 2 then
				sentAt = os.clock()
				remote:FireServer("Ran")
			end
		end
	end)
end

return Opening
