-- Reglas con nombre de las galerías (Config.MiniTune.Perks): la tercera galería de cada fila.
-- Su nivel es cuántas galerías de esa regla tienes (profile.stats.perks). Todo va por los sucesos de
-- Events y un repaso cada cuarto de segundo: no toca la mordida, la entrega ni la colonia por dentro.
-- Cuando una regla salta, la dueña ve un estallido corto con su nombre (suceso "Perk" del remoto Fx,
-- lo pinta src/client/Perks.luau). Las de Paladar fino y Quebrantahuesos van en Stats.derive.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local PlayerService = require(script.Parent.PlayerService)
local Profiles = require(script.Parent.Profiles)

local Perks = {}

local RULES = Config.MiniTune.PerkRules
local TICK = 0.25
local SAME_BITE = 0.05 -- segundos: los trozos de un mismo mordisco llegan juntos
local FLAT = Vector3.new(1, 0, 1)

local rng = Random.new()
local fxRemote: RemoteEvent
local states = setmetatable({}, { __mode = "k" }) -- profile -> lo que recuerda cada regla

-- Las comidas grandes (la tercera de cada zona; la tarta no) para Botín
local BIG = {}
for i, def in Config.Foods do
	if (i - 1) % 3 == 2 and def.count ~= 1 then
		BIG[def.id] = true
	end
end

local function level(profile, id: string): number
	local perks = profile.stats and profile.stats.perks
	return perks and perks[id] or 0
end

local function value(profile, id: string): number
	return Config.perkValue(id, level(profile, id))
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function state(profile)
	local s = states[profile]
	if not s then
		local now = os.clock()
		s = {
			touched = setmetatable({}, { __mode = "k" }), -- comidas que ya mordiste (Primer mordisco)
			biteAte = nil, -- trozos del mordisco en curso: { def, amount, t }
			lastAte = nil, -- últimos trozos tuyos (Última miga, Botín)
			streak = 0,
			sweep = 0,
			nugget = 0,
			fever = 0,
			hungry = 0,
			lastDeposit = -math.huge,
			stack = 0,
			starAt = now + RULES.StarEvery,
			steps = 0,
			lastPos = nil,
			pantryAt = now + RULES.PantryEvery,
			cradleAt = now + RULES.CradleEvery,
			rushAt = now + RULES.RushEvery,
			boostUntil = 0, -- Hora punta y Olor a fiesta: la colonia trabaja el doble
			filled = false,
			cues = {},
			greeted = false,
		}
		states[profile] = s
	end
	return s
end

-- Estallido corto con el nombre de la regla (como mucho uno cada CueGap s por regla)
local function cue(profile, id: string, position: Vector3?, amount: number?)
	local s = state(profile)
	local now = os.clock()
	if now - (s.cues[id] or -math.huge) < RULES.CueGap then
		return
	end
	s.cues[id] = now
	if not position then
		local root = getRoot(profile.player)
		position = if root then root.Position + Vector3.new(0, 3, 0) else nil
	end
	if position and fxRemote then
		fxRemote:FireClient(profile.player, "Perk", position, id, amount)
	end
end

local function hillTop(profile): Vector3?
	local hill = profile.hill
	return if hill then hill:GetPivot().Position + Vector3.new(0, 9 * (profile.stats.hillScale or 1), 0) else nil
end

local function positionOf(food): Vector3?
	local ok, pivot = pcall(function()
		return food:GetPivot().Position
	end)
	return if ok then pivot + Vector3.new(0, 1, 0) else nil
end

-- Lo que vale un trozo de esta comida para ti (zona, comida dorada)
local function pieceValue(profile, def, food): number
	if food and FoodService.pieceValue then
		local ok, v = pcall(FoodService.pieceValue, food, def, profile.stats)
		if ok and type(v) == "number" then
			return v
		end
	end
	return def.value * (profile.stats.zoneMult[def.zone] or 1)
end

-- Comida ya con todos los multiplicadores (la de la entrega, la de la colonia): se suma tal cual
local function addCredited(profile, amount: number)
	if amount <= 0 or amount ~= amount then
		return
	end
	local data = profile.data
	data.food += amount
	data.runFood += amount
	data.totalFood += amount
end

-- Comida de la colonia: data.rate ya lleva el multiplicador de comida
local function colonySeconds(profile, seconds: number): number
	return profile.data.rate * seconds
end

-- Lo dorado de un mordisco: Pepita segura y Fiebre del oro lo suman a tu carga (Oro puro lo sube)
local function goldenBonus(profile, hit): number
	if not hit then
		return 0
	end
	local worth = math.max(value(profile, "pureGold"), Config.MiniTune.GoldMult)
	local bonus = hit.amount * hit.value * (worth - 1)
	profile.carryValue += bonus
	return bonus
end

local function extraBite(profile, food, mult: number): number
	if mult <= 0 or not FoodService.isFood(food) then
		return 0
	end
	local stats = profile.stats
	local def = FoodService.defOf(food)
	local damage = stats.biteDamage * mult * (if def and def.hard then stats.hardMult else 1)
	return (PlayerService.take(profile, food, damage))
end

local function onAte(profile, def, amount: number, byWorkers: boolean?)
	if byWorkers or not def or amount <= 0 then
		return
	end
	local s = state(profile)
	local now = os.clock()
	local entry = { def = def, amount = amount, t = now, value = def.value * (profile.stats.zoneMult[def.zone] or 1) }
	s.lastAte = entry
	if not s.biteAte or now - s.biteAte.t > SAME_BITE then
		s.biteAte = entry
	end
end

local function onBite(profile, food, chained: boolean?)
	local stats = profile.stats
	local s = state(profile)
	local now = os.clock()
	local hit = s.biteAte
	s.biteAte = nil
	if hit and now - hit.t > SAME_BITE then
		hit = nil
	end
	if hit and food then
		hit.value = pieceValue(profile, hit.def, food)
	end
	local carryBefore, valueBefore, foodBefore = profile.carry, profile.carryValue, profile.data.food
	local alive = FoodService.isFood(food)
	local position = positionOf(food)
	local fresh = not s.touched[food]
	s.touched[food] = true

	-- Primer mordisco: la primera vez que muerdes esta comida pega más
	if fresh and level(profile, "first") > 0 and alive then
		if extraBite(profile, food, value(profile, "first") - 1) > 0 then
			cue(profile, "first", position)
		end
	end

	-- Hambre voraz: los primeros mordiscos al salir de casa vacía pegan doble
	if s.hungry > 0 then
		s.hungry -= 1
		if alive and extraBite(profile, food, 1) > 0 then
			cue(profile, "hungry", position)
		end
	end

	-- Buena racha: cada tantos mordiscos seguidos, uno gratis con mordida doble
	s.streak = if chained then s.streak + 1 else 1
	if level(profile, "streak") > 0 and s.streak >= value(profile, "streak") then
		s.streak = 0
		if alive and extraBite(profile, food, stats.critMult) > 0 then
			cue(profile, "streak", position)
		end
	end

	-- Barrido: cada tantos mordiscos, un mordisco a toda la comida de alrededor
	if level(profile, "sweep") > 0 and position then
		s.sweep += 1
		if s.sweep >= value(profile, "sweep") then
			s.sweep = 0
			local nearby = {}
			for other in FoodService.list() do
				if other ~= food then
					local flat = ((other:GetPivot().Position - position) * FLAT).Magnitude - (other:GetAttribute("Radius") or 0)
					if flat <= RULES.SweepRadius then
						table.insert(nearby, other)
					end
				end
			end
			local any = false
			for _, other in nearby do
				if profile.carry >= stats.capacity then
					break
				end
				any = extraBite(profile, other, 1) > 0 or any
			end
			if any then
				cue(profile, "sweep", position)
			end
		end
	end

	-- Frenesí contagioso: durante el frenesí tú también muerdes más
	if level(profile, "frenzyBite") > 0 and alive and Workspace:GetServerTimeNow() < profile.frenzyUntil then
		if extraBite(profile, food, value(profile, "frenzyBite") - 1) > 0 then
			cue(profile, "frenzyBite", position)
		end
	end

	-- Fiebre del oro: tras un mordisco dorado, los siguientes también valen como dorados
	if s.fever > 0 then
		s.fever -= 1
		if goldenBonus(profile, hit) > 0 then
			cue(profile, "fever", position)
		end
	end

	-- Pepita segura: cada tantos mordiscos, uno vale como dorado
	if level(profile, "nugget") > 0 then
		s.nugget += 1
		if s.nugget >= value(profile, "nugget") and hit then
			s.nugget = 0
			goldenBonus(profile, hit)
			cue(profile, "nugget", position)
			s.ownGolden = true
			Events.fire("Golden", profile) -- cuenta para las misiones y enciende la Fiebre del oro
			s.ownGolden = false
		end
	end

	-- Trébol: a veces un regalo que va directo a casa
	if level(profile, "clover") > 0 and hit and rng:NextNumber() < value(profile, "clover") / 100 then
		local credited = Profiles.addFood(profile, hit.amount * hit.value * RULES.CloverBites)
		cue(profile, "clover", position, credited)
	end

	if profile.carry ~= carryBefore or profile.carryValue ~= valueBefore or profile.data.food ~= foodBefore then
		PlayerService.refreshCarry(profile)
	end
end

local function onGolden(profile)
	local s = state(profile)
	if level(profile, "fever") > 0 then
		s.fever = value(profile, "fever")
	end
	-- Oro puro sobre un mordisco dorado de verdad (los de Pepita ya lo cuentan en goldenBonus)
	if not s.ownGolden and level(profile, "pureGold") > 0 and s.lastAte then
		local hit = s.lastAte
		profile.carryValue += hit.amount * hit.value * (value(profile, "pureGold") - Config.MiniTune.GoldMult)
	end
end

local function onFinished(profile, def)
	local s = state(profile)
	local hit = s.lastAte
	if not hit or hit.def ~= def or os.clock() - hit.t > SAME_BITE then
		return -- la terminaron tus obreras u otra cosa
	end
	-- Última miga: el último bocado vale más
	if level(profile, "lastBite") > 0 then
		local piece = math.min(hit.amount, def.hp * RULES.LastShare)
		profile.carryValue += piece * hit.value * (value(profile, "lastBite") - 1)
		cue(profile, "lastBite")
	end
	-- Botín: terminar una comida grande da una parte de lo que valía entera
	if level(profile, "loot") > 0 and BIG[def.id] then
		local credited = Profiles.addFood(profile, def.hp * hit.value * value(profile, "loot") / 100)
		cue(profile, "loot", nil, credited)
	end
end

local function onDeposit(profile, credited: number, _full: boolean?)
	local stats = profile.stats
	local s = state(profile)
	local now = os.clock()
	local extra = 0

	-- Galerías de "comida en cada entrega"
	if (stats.depositFlat or 0) > 0 then
		extra += Profiles.addFood(profile, stats.depositFlat)
	end

	-- Entrega en racha: seguidas, cada una suma un poco más
	if level(profile, "depStreak") > 0 then
		s.stack = if now - s.lastDeposit <= RULES.DepositWindow then math.min(s.stack + 1, RULES.DepositStacks) else 0
		if s.stack > 0 then
			local bonus = credited * value(profile, "depStreak") / 100 * s.stack
			addCredited(profile, bonus)
			extra += bonus
			cue(profile, "depStreak", hillTop(profile))
		end
	end

	-- Entrega estrella: cada tanto, una entrega vale mucho más
	if level(profile, "starDep") > 0 and now >= s.starAt then
		s.starAt = now + RULES.StarEvery
		local bonus = credited * (value(profile, "starDep") - 1)
		addCredited(profile, bonus)
		extra += bonus
		cue(profile, "starDep", hillTop(profile), bonus)
	end

	-- Turno doble: tu entrega trae también trabajo de la colonia
	if level(profile, "shift") > 0 then
		local bonus = colonySeconds(profile, value(profile, "shift"))
		addCredited(profile, bonus)
		extra += bonus
	end

	-- Olor a fiesta: la colonia trabaja el doble un rato
	if level(profile, "party") > 0 then
		s.boostUntil = math.max(s.boostUntil, now + value(profile, "party"))
	end

	-- Hambre voraz y Recolectora se rearman al vaciar la carga
	s.hungry = if level(profile, "hungry") > 0 then value(profile, "hungry") else 0
	s.filled = false
	s.lastDeposit = now
	if extra > 0 then
		Profiles.push(profile)
	end
end

-- Madrugadora: comida doble un rato (la misma del hongo, profile.buffUntil)
local function wakeUp(profile, minutes: number)
	if minutes <= 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	profile.buffUntil = math.max(profile.buffUntil, now) + minutes * 60
	Profiles.push(profile)
	cue(profile, "early")
end

-- Al entrar: Despertador y Madrugadora si llevabas un rato fuera
local function greet(profile, s)
	s.greeted = true
	local data = profile.data
	local away = os.time() - (data.lastSeen or os.time())
	if away < RULES.WakeAway then
		return
	end
	task.delay(4, function()
		if Profiles.get(profile.player) ~= profile then
			return
		end
		if level(profile, "wake") > 0 then
			local bonus = colonySeconds(profile, value(profile, "wake") * 60)
			addCredited(profile, bonus)
			Profiles.push(profile)
			cue(profile, "wake", hillTop(profile), bonus)
		end
		wakeUp(profile, value(profile, "early"))
	end)
end

local function tickProfile(player: Player, profile, now: number)
	local stats = profile.stats
	local data = profile.data
	local s = state(profile)
	if not s.greeted then
		greet(profile, s)
	end

	-- Carga viva y Patas ligeras: la velocidad que ve el cliente (atributo WalkSpeed)
	local speed = stats.walkSpeed
	if profile.carry >= stats.capacity and level(profile, "fullSpeed") > 0 then
		speed *= 1 + value(profile, "fullSpeed") / 100
	elseif profile.carry <= 0 and level(profile, "lightSpeed") > 0 then
		speed *= 1 + value(profile, "lightSpeed") / 100
	end
	local shown = player:GetAttribute("WalkSpeed")
	if type(shown) ~= "number" or math.abs(shown - speed) > 0.01 then
		player:SetAttribute("WalkSpeed", speed)
	end

	-- Recolectora: llenar la carga del todo da un premio al momento
	if level(profile, "filler") > 0 and not s.filled and profile.carry >= stats.capacity and profile.carry > 0 then
		s.filled = true
		local credited = Profiles.addFood(profile, profile.carryValue * value(profile, "filler") / 100)
		Profiles.push(profile)
		cue(profile, "filler", nil, credited)
	end

	-- Cuentapasos: cada tantos pasos, una parte de lo que vale una carga llena
	local root = getRoot(player)
	if root then
		local pos = root.Position
		if s.lastPos and level(profile, "pedometer") > 0 then
			local moved = ((pos - s.lastPos) * FLAT).Magnitude
			if moved < 60 then -- alas, túnel o reaparecer no cuentan
				s.steps += moved
			end
			if s.steps >= RULES.Steps then
				s.steps -= RULES.Steps
				local food = Config.Foods[(stats.depth - 1) * 3 + 1]
				local credited = Profiles.addFood(profile, value(profile, "pedometer") / 100 * stats.capacity * food.value * (stats.zoneMult[food.zone] or 1))
				Profiles.push(profile)
				cue(profile, "pedometer", nil, credited)
			end
		end
		s.lastPos = pos
	end

	-- Despensa viva: la comida guardada crece cada minuto, hasta unos segundos de colonia
	if now >= s.pantryAt then
		s.pantryAt = now + RULES.PantryEvery
		if level(profile, "pantry") > 0 then
			local gain = math.min(data.food * value(profile, "pantry") / 100, colonySeconds(profile, RULES.PantryCap))
			if gain > 0 then
				addCredited(profile, gain)
				Profiles.push(profile)
				cue(profile, "pantry", hillTop(profile), gain)
			end
		end
	end

	-- Cuna rápida: obreras gratis si caben
	if now >= s.cradleAt then
		s.cradleAt = now + RULES.CradleEvery
		if level(profile, "cradle") > 0 and data.workers < stats.workerCap then
			data.workers = math.min(stats.workerCap, data.workers + value(profile, "cradle"))
			Profiles.push(profile)
			cue(profile, "cradle", hillTop(profile))
		end
	end

	-- Hora punta: cada tanto, la colonia trabaja el doble un rato
	if now >= s.rushAt then
		s.rushAt = now + RULES.RushEvery
		if level(profile, "rush") > 0 and data.workers > 0 then
			s.boostUntil = math.max(s.boostUntil, now + value(profile, "rush"))
			cue(profile, "rush", hillTop(profile))
		end
	end

	-- Colonia: Obrera estrella, Hormiguero lleno y los ratos de trabajo doble. Se aplica como factor
	-- sobre stats.colonyMult; tras cada compra las estadísticas son nuevas y el factor vuelve a 1.
	local factor = 1
	local workers = data.workers
	if workers > 0 then
		if level(profile, "star") > 0 then
			factor *= (workers + value(profile, "star") - 1) / workers
		end
		if level(profile, "fullNest") > 0 and workers >= stats.workerCap then
			factor *= 1 + value(profile, "fullNest") / 100
		end
		if now < s.boostUntil then
			factor *= 2
		end
	end
	local current = stats.perkColony or 1
	if math.abs(current - factor) > 1e-9 then
		stats.colonyMult *= factor / current
		stats.perkColony = factor
	end
end

function Perks.start(remotes: Folder)
	fxRemote = remotes:WaitForChild("Fx") :: RemoteEvent
	Events.on("Ate", onAte)
	Events.on("Bite", onBite)
	Events.on("Golden", onGolden)
	Events.on("Finished", onFinished)
	Events.on("Deposit", onDeposit)
	Events.on("Dig", function(profile)
		wakeUp(profile, value(profile, "early"))
	end)
	Events.on("Rebirth", function(profile)
		local s = states[profile]
		if s then
			-- Lo que dependía de las galerías empieza de cero (se pierden al enjambrar)
			s.streak, s.sweep, s.nugget, s.fever, s.hungry, s.stack, s.boostUntil = 0, 0, 0, 0, 0, 0, 0
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local now = os.clock()
			for player, profile in Profiles.all() do
				if profile.stats and player.Parent then
					local ok, err = pcall(tickProfile, player, profile, now)
					if not ok then
						warn("[CRUNCH!] Reglas de galerías:", err)
					end
				end
			end
		end
	end)
end

-- Por si otro módulo quiere saber el nivel de una regla
Perks.level = level

return Perks
