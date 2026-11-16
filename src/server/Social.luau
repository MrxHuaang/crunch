-- Vecinas: formas de jugar con las demás sin que nadie pierda progreso (números en Config.Social).
--
-- 1. Despensa y asalto. Junto a cada hormiguero ocupado hay una despensa que se llena sola con un
--    EXTRA de lo que entrega su dueña (comida creada, no quitada). La dueña la cobra entera al pisarla.
--    Las demás pueden asaltarla a mordiscos: lo arrancado va a un saco de "botín" aparte de la carga,
--    que solo se cobra al llegar al hormiguero propio. Al primer mordisco salen guardianas del
--    hormiguero asaltado y persiguen a la ladrona (simuladas aquí, dibujadas en los clientes): si la
--    alcanzan, sale volando, el botín vuelve a la despensa y queda fichada un rato. Si la dueña muerde
--    a la ladrona, cobra el botín con premio. Antiabuso: tope por asalto, despensas protegidas para
--    quien acaba de llegar o va por la capa 1, enfriamientos y modo pacífico.
-- 2. Regalos: con carga, junto a otra jugadora, le lanzas un paquete. Ella cobra a SU nivel (con hucha
--    para que no se dispare), tú recuperas parte y sube la amistad (bonus de comida mientras estéis).
-- 3. Dúo: morder la misma comida a la vez da un extra a las dos.
-- 4. Saludo de antenas: quietas cara a cara un momento, las dos andan más rápido un rato.
--
-- Guardado (perezoso): data.social = { peace = bool, friends = { [UserId texto] = mejor nivel } }.
-- Atributos del hormiguero: PantryPos (Vector3), PantryFill (0..1), PantryValue, PantryOpen (se puede
--   asaltar), Peace, PantryColor1..3.
-- Atributos de la jugadora: Peace, Loot, LootFrom (UserId), LootFill (0..1), SocialBonus (amistad),
--   GreetSpeedUntil (hora del servidor), SocialStolen, SocialGifted, SocialCaught.
-- Remoto "Social":
--   cliente -> servidor: "Raid" (hormiguero), "Catch" (jugadora), "Gift" (jugadora), "Peace" (bool), "Sync"
--   servidor -> clientes: "Raid", "RaidBite", "GuardsEnd", "Caught", "Stolen", "Collect", "Gift",
--   "Welcome", "Duo", "DuoFinish", "Greet", "Friends", "Peace"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Events = require(script.Parent.Events)
local FoodService = require(script.Parent.FoodService)
local PlayerService = require(script.Parent.PlayerService)
local Profiles = require(script.Parent.Profiles)

local Social = {}

local S = Config.Social
local R = S.Raid
local G = S.Guard
local GF = S.Gift
local F = S.Friend
local D = S.Duo
local GR = S.Greet

local FLAT = Vector3.new(1, 0, 1)
local TICK = 0.1

local remote: RemoteEvent
local states: { [any]: any } = {} -- [profile] = estado social de la sesión
local giftCooldown: { [string]: number } = {} -- [pareja] = os.clock() hasta el que no se puede
local greetCooldown: { [string]: number } = {}
local greetHold: { [string]: number } = {} -- [pareja] = desde cuándo están cara a cara
local bonds: { [string]: number } = {} -- [pareja] = nivel de amistad de esta sesión
local raids: { [any]: any } = {} -- [profile víctima] = asalto en marcha
local foodBites: { [Model]: { [any]: number } } = {} -- [comida] = { [profile] = cuándo la mordió }
local startedAt = os.clock()

local function now(): number
	return os.clock()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function pairKey(a: Player, b: Player): string
	local x, y = a.UserId, b.UserId
	if x > y then
		x, y = y, x
	end
	return x .. ":" .. y
end

-- Campo guardado perezoso
local function saved(data)
	if type(data.social) ~= "table" then
		data.social = {}
	end
	local t = data.social
	if type(t.friends) ~= "table" then
		t.friends = {}
	end
	t.peace = t.peace == true
	return t
end

-- Suma comida ya calculada (sin volver a aplicar multiplicadores)
local function grant(profile, amount: number): number
	if amount ~= amount or amount <= 0 then
		return 0
	end
	local data = profile.data
	data.food += amount
	data.runFood += amount
	data.totalFood += amount
	return amount
end

local function tell(st, profile, text: string)
	local t = now()
	if st.toldText == text and t - st.toldAt < 4 then
		return
	end
	if t - st.toldAt < 1.5 then
		return
	end
	st.toldText = text
	st.toldAt = t
	Profiles.say(profile, text, 3)
end

-- Lo entregado en los últimos PantryCapSeconds s (y se olvida lo más viejo)
local function recentDeposits(st): number
	local cutoff = now() - S.PantryCapSeconds
	local list = st.deposits
	local total = 0
	local keep = 0
	for i = 1, #list do
		local entry = list[i]
		if entry.t >= cutoff then
			keep += 1
			list[keep] = entry
			total += entry.v
		end
	end
	for i = #list, keep + 1, -1 do
		list[i] = nil
	end
	return total
end

-- Ingreso por segundo de una jugadora (ver Config.Social)
local function income(profile): number
	local st = states[profile]
	local stats = profile.stats
	local zoneFood = Config.Foods[(stats.depth - 1) * 3 + 1] or Config.Foods[1]
	local floor = 0.5 * stats.biteDamage * zoneFood.value * (stats.foodMult or 1)
	local delivered = if st then recentDeposits(st) / S.PantryCapSeconds else 0
	return math.max(profile.data.rate or 0, delivered, floor)
end

local function shareOf(st): number
	return S.PantryShare * (if st.peace then S.PeaceShare else 1)
end

local function hillFrame(hill: Model): (Vector3, Vector3, Vector3, number)
	local center = hill:GetPivot().Position
	local inward = Vector3.new(0, center.Y, 0) - center
	inward = if inward.Magnitude > 0.01 then inward.Unit else Vector3.zAxis
	local side = inward:Cross(Vector3.yAxis)
	local scale = hill:GetAttribute("Scale")
	return center, inward, side, if type(scale) == "number" then scale else 1
end

local function pantrySpot(hill: Model): (Vector3, number)
	local center, inward, side, scale = hillFrame(hill)
	return center + (inward * S.PantrySpot[1] + side * S.PantrySpot[2]) * scale, scale
end

local function victimOf(hill: Model)
	for profile in states do
		if profile.hill == hill then
			return profile
		end
	end
	return nil
end

-- ¿Se puede asaltar la despensa de esta jugadora?
local function isOpen(profile, st): boolean
	return not st.peace and profile.data.depth >= R.MinDepth and now() - st.joinedAt >= R.MinTenure
end

local function setAttr(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function syncLoot(profile)
	local st = states[profile]
	if not st then
		return
	end
	local player = profile.player
	setAttr(player, "Loot", st.loot)
	setAttr(player, "LootFrom", if st.loot > 0 and st.lootFrom then st.lootFrom.player.UserId else 0)
	setAttr(player, "LootFill", if st.loot > 0 then math.clamp(st.loot / math.max(st.lootCap, 1e-9), 0, 1) else 0)
end

local function syncScore(profile, st)
	local player = profile.player
	setAttr(player, "SocialStolen", st.stolen)
	setAttr(player, "SocialGifted", st.gifted)
	setAttr(player, "SocialCaught", st.caught)
	setAttr(player, "Peace", st.peace)
end

-- Amistad ------------------------------------------------------------------------------------------

local function friendBonus(profile): number
	local total = 0
	for other in states do
		if other ~= profile and other.player.Parent then
			total += (bonds[pairKey(profile.player, other.player)] or 0) * F.PerLevel
		end
	end
	return math.min(total, F.MaxBonus)
end

local function friendsMap(profile)
	local map = {}
	for other in states do
		if other ~= profile then
			local level = bonds[pairKey(profile.player, other.player)]
			if level and level > 0 then
				map[tostring(other.player.UserId)] = level
			end
		end
	end
	return map
end

local function sendFriends(profile)
	if remote and profile.player.Parent then
		remote:FireClient(profile.player, "Friends", friendsMap(profile))
	end
end

-- Guarda el mejor nivel alcanzado con esa UserId (como mucho F.Keep amigas)
local function remember(profile, other, level: number)
	local friends = saved(profile.data).friends
	local id = tostring(other.player.UserId)
	if (friends[id] or 0) >= level then
		return
	end
	friends[id] = level
	local count = 0
	local lowestId, lowest = nil, math.huge
	for key, value in friends do
		count += 1
		if key ~= id and value < lowest then
			lowestId, lowest = key, value
		end
	end
	if count > F.Keep and lowestId then
		friends[lowestId] = nil
	end
end

-- Profiles.onRefresh: la amistad multiplica la comida mientras las amigas estén en el servidor
local function onRefresh(profile)
	if not states[profile] then
		return
	end
	local bonus = friendBonus(profile)
	if bonus > 0 then
		profile.stats.foodMult *= 1 + bonus
	end
	setAttr(profile.player, "SocialBonus", bonus)
end

-- Despensa -----------------------------------------------------------------------------------------

local function pushColor(st, color: any)
	if typeof(color) ~= "Color3" then
		return
	end
	for _, c in st.colors do
		if (Vector3.new(c.R, c.G, c.B) - Vector3.new(color.R, color.G, color.B)).Magnitude < 0.08 then
			return
		end
	end
	table.insert(st.colors, 1, color)
	if #st.colors > 3 then
		table.remove(st.colors)
	end
end

local function onDeposit(profile, credited: number)
	local st = states[profile]
	if not st or type(credited) ~= "number" or credited <= 0 or not profile.hill then
		return
	end
	table.insert(st.deposits, { t = now(), v = credited })
	local share = shareOf(st)
	local cap = recentDeposits(st) * share
	st.pantry = math.min(st.pantry + credited * share, math.max(cap, st.pantry))
	pushColor(st, profile.carryColor)
end

local function syncHill(profile, st)
	local hill = profile.hill
	if st.hill and st.hill ~= hill then
		for _, name in { "PantryPos", "PantryFill", "PantryValue", "PantryOpen", "Peace", "PantryColor1", "PantryColor2", "PantryColor3" } do
			st.hill:SetAttribute(name, nil)
		end
	end
	st.hill = hill
	if not hill then
		return
	end
	local spot = pantrySpot(hill)
	setAttr(hill, "PantryPos", spot)
	local cap = math.max(recentDeposits(st) * shareOf(st), st.pantry, 1e-9)
	local fill = if st.pantry > 0 then math.clamp(st.pantry / cap, 0.05, 1) else 0
	setAttr(hill, "PantryFill", math.floor(fill * 20 + 0.5) / 20)
	-- El valor solo se reescribe si cambió más de un 2 % (no inunda la red)
	local shown = hill:GetAttribute("PantryValue")
	if type(shown) ~= "number" or math.abs(shown - st.pantry) > math.max(shown, st.pantry) * 0.02 or (st.pantry == 0) ~= (shown == 0) then
		hill:SetAttribute("PantryValue", st.pantry)
	end
	setAttr(hill, "PantryOpen", isOpen(profile, st))
	setAttr(hill, "Peace", st.peace)
	for i = 1, 3 do
		setAttr(hill, "PantryColor" .. i, st.colors[i])
	end
end

-- Asalto -------------------------------------------------------------------------------------------

local function launchGuards(raid)
	local t = now()
	local center, inward, side, scale = hillFrame(raid.hill)
	local door = center + inward * 8.5 * scale
	raid.guards = {}
	for i = 1, raid.count do
		local offset = (i - (raid.count + 1) / 2) * 1.6
		raid.guards[i] = door + side * offset
	end
	raid.guardsAt = t + G.Delay
	raid.endAt = raid.guardsAt + G.ChaseTime
	raid.chasing = true
	remote:FireAllClients("Raid", raid.thief.player, raid.hill, raid.count, raid.speed, G.Delay, G.ChaseTime)
end

local function startRaid(thief, tst, victim, vst, hill: Model)
	local soldiers = math.max(0, victim.stats.soldiers or 0)
	local raid = {
		thief = thief,
		victim = victim,
		hill = hill,
		cap = math.min(income(thief) * R.CapSeconds, vst.pantry),
		taken = 0,
		count = math.clamp(G.Min + math.floor(soldiers / G.PerSoldiers), G.Min, G.Max),
		speed = thief.stats.walkSpeed * math.min(G.SpeedBase + G.SpeedPerSoldier * soldiers, G.SpeedMax),
		guards = {},
		chasing = false,
		guardsAt = 0,
		endAt = 0,
	}
	raids[victim] = raid
	tst.lastRaidAt = now()
	launchGuards(raid)
	return raid
end

-- Termina un asalto (escapada o entrega): esa despensa se cierra un rato para esa ladrona
local function finishRaid(victim, raid, reason: string)
	if raids[victim] ~= raid then
		return
	end
	raids[victim] = nil
	local tst = states[raid.thief]
	if tst then
		tst.blocks[victim.player.UserId] = now() + R.Protect
	end
	if raid.chasing then
		raid.chasing = false
		remote:FireAllClients("GuardsEnd", raid.hill, reason)
	end
end

-- La ladrona suelta el botín: si la pillan las guardianas vuelve a la despensa; si la muerde la dueña,
-- la dueña lo cobra con premio.
local function catchThief(victim, thief, by: string)
	local tst = states[thief]
	local vst = states[victim]
	if not tst or not vst or tst.loot <= 0 or tst.lootFrom ~= victim then
		return
	end
	local loot = tst.loot
	tst.loot = 0
	tst.lootFrom = nil
	tst.blocks[victim.player.UserId] = now() + R.CaughtBlock
	tst.caught += 1
	local amount
	if by == "owner" then
		amount = grant(victim, loot * R.OwnerMult)
		vst.prized = (vst.prized or 0) + amount
		Profiles.push(victim)
	else
		vst.pantry += loot
		amount = loot
	end
	local raid = raids[victim]
	if raid then
		raids[victim] = nil
	end
	local hill = victim.hill
	local dir = Vector3.zAxis
	local root = rootOf(thief.player)
	if root and hill then
		local away = (root.Position - hill:GetPivot().Position) * FLAT
		if away.Magnitude > 0.1 then
			dir = away.Unit
		end
	end
	syncLoot(thief)
	syncScore(thief, tst)
	remote:FireAllClients("Caught", thief.player, hill, by, amount, dir)
end

local function onRaid(profile, st, hill: any)
	local anthills = Workspace:FindFirstChild("Anthills")
	if typeof(hill) ~= "Instance" or not hill:IsA("Model") or hill.Parent ~= anthills then
		return
	end
	local victim = victimOf(hill)
	if not victim or victim == profile then
		return
	end
	local vst = states[victim]
	local root = rootOf(profile.player)
	if not vst or not root then
		return
	end
	local spot, scale = pantrySpot(hill)
	if ((root.Position - spot) * FLAT).Magnitude > R.Reach * math.max(1, scale) + 2 then
		return
	end
	local t = now()
	local stats = profile.stats
	if t - profile.lastBite < stats.biteCooldown * 0.9 then
		return
	end
	profile.lastBite = t

	if st.peace then
		tell(st, profile, "En modo pacífico no asalto despensas")
		return
	elseif vst.peace then
		tell(st, profile, "Es pacífica: su despensa no se toca")
		return
	elseif not isOpen(victim, vst) then
		tell(st, profile, "Esa despensa aún está protegida")
		return
	elseif st.loot > 0 and st.lootFrom ~= victim then
		tell(st, profile, "Primero llevo este botín a casa")
		return
	end
	local block = st.blocks[victim.player.UserId]
	if block and block > t then
		tell(st, profile, "Me tienen fichada: " .. math.ceil(block - t) .. " s")
		return
	end
	local raid = raids[victim]
	if raid and raid.thief ~= profile then
		tell(st, profile, "Ya la está asaltando otra")
		return
	end
	if not raid then
		if t - st.lastRaidAt < R.Gap then
			tell(st, profile, "Tomo aire antes del próximo asalto")
			return
		end
		if vst.pantry <= 0 then
			tell(st, profile, "Está vacía")
			return
		end
		raid = startRaid(profile, st, victim, vst, hill)
	elseif not raid.chasing then
		launchGuards(raid) -- vuelve a por más: vuelven las guardianas
	end

	local take = math.min(raid.cap * R.BiteShare, raid.cap - raid.taken, vst.pantry)
	if take <= 0 then
		tell(st, profile, "¡El saco no da para más! A casa")
		return
	end
	vst.pantry -= take
	raid.taken += take
	st.loot += take
	st.lootFrom = victim
	st.lootFromName = victim.player.DisplayName
	st.lootCap = raid.cap
	syncLoot(profile)
	remote:FireAllClients("RaidBite", profile.player, hill, take, st.loot / math.max(raid.cap, 1e-9))
end

local function onCatch(profile, st, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		return
	end
	local thief = Profiles.get(target)
	local tst = thief and states[thief]
	if not tst or thief == profile or tst.lootFrom ~= profile or tst.loot <= 0 then
		return
	end
	local a, b = rootOf(profile.player), rootOf(target)
	if not a or not b or ((a.Position - b.Position) * FLAT).Magnitude > R.CatchReach + 2 then
		return
	end
	local t = now()
	if t - profile.lastBite < profile.stats.biteCooldown * 0.9 then
		return
	end
	profile.lastBite = t
	catchThief(profile, thief, "owner")
end

-- Devuelve a su despensa el botín que llevaba (muerte, salida)
local function dropLoot(profile, st)
	if st.loot <= 0 then
		return
	end
	local victim = st.lootFrom
	local vst = victim and states[victim]
	if vst then
		vst.pantry += st.loot
	end
	st.loot = 0
	st.lootFrom = nil
	for v, raid in raids do
		if raid.thief == profile then
			finishRaid(v, raid, "gone")
		end
	end
	syncLoot(profile)
end

local function updateRaids(dt: number)
	local t = now()
	for victim, raid in raids do
		local thief = raid.thief
		local tst = states[thief]
		if not tst or not states[victim] or not thief.player.Parent or victim.hill ~= raid.hill then
			raids[victim] = nil
			if raid.chasing then
				remote:FireAllClients("GuardsEnd", raid.hill, "gone")
			end
			continue
		end
		local root = rootOf(thief.player)
		local center = raid.hill:GetPivot().Position
		local away = if root then ((root.Position - center) * FLAT).Magnitude else math.huge
		if raid.chasing and t >= raid.guardsAt then
			if not root or away > G.Leash or t > raid.endAt then
				raid.chasing = false
				remote:FireAllClients("GuardsEnd", raid.hill, "lost")
			else
				local target = root.Position
				local step = raid.speed * dt
				local caught = false
				for i, pos in raid.guards do
					local delta = (target - pos) * FLAT
					local distance = delta.Magnitude
					if distance > 0.01 then
						pos += delta.Unit * math.min(step, distance)
						raid.guards[i] = pos
					end
					if distance - step <= G.CatchRange and math.abs(target.Y - pos.Y) < 7 then
						caught = true
					end
				end
				if caught and tst.loot > 0 and tst.lootFrom == victim then
					catchThief(victim, thief, "guards")
					continue
				end
			end
		end
		if not raid.chasing and (tst.loot <= 0 or tst.lootFrom ~= victim or away > R.Leave) then
			finishRaid(victim, raid, "done")
		end
	end
end

-- Botín a casa, despensa a la dueña
local function updateHome(profile, st)
	local hill = profile.hill
	local root = rootOf(profile.player)
	if not hill or not root then
		return
	end
	local center = hill:GetPivot().Position
	if st.loot > 0 then
		local flat = ((center - root.Position) * FLAT).Magnitude
		if flat <= Config.Anthill.DepositRadius * (profile.stats.hillScale or 1) then
			local victim = st.lootFrom
			local amount = grant(profile, st.loot)
			st.stolen += amount
			st.loot = 0
			st.lootFrom = nil
			if victim then
				local raid = raids[victim]
				if raid and raid.thief == profile then
					finishRaid(victim, raid, "home")
				else
					st.blocks[victim.player.UserId] = now() + R.Protect
				end
			end
			syncLoot(profile)
			syncScore(profile, st)
			Profiles.push(profile)
			remote:FireAllClients("Stolen", profile.player, if victim then victim.player else false, amount, st.lootFromName or "")
		end
	end
	if st.pantry > 0.5 and now() - st.collectAt > 1 then
		local spot, scale = pantrySpot(hill)
		if ((spot - root.Position) * FLAT).Magnitude <= S.PantryReach * math.max(1, scale) then
			st.collectAt = now()
			local amount = grant(profile, st.pantry)
			st.pantry = 0
			Profiles.push(profile)
			remote:FireClient(profile.player, "Collect", spot, amount)
		end
	end
end

-- Regalo -------------------------------------------------------------------------------------------

local function onGift(giver, gst, target: any)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		return
	end
	local recv = Profiles.get(target)
	local rst = recv and states[recv]
	if not rst or recv == giver then
		return
	end
	if giver.carry <= 0 then
		tell(gst, giver, "Para regalar tengo que llevar comida")
		return
	end
	local a, b = rootOf(giver.player), rootOf(target)
	if not a or not b or ((a.Position - b.Position) * FLAT).Magnitude > GF.Range + 3 then
		return
	end
	local t = now()
	local key = pairKey(giver.player, target)
	local cooldown = giftCooldown[key]
	if cooldown and cooldown > t then
		tell(gst, giver, "Ya le regalé hace poco (" .. math.ceil(cooldown - t) .. " s)")
		return
	end
	giftCooldown[key] = t + GF.Cooldown

	local stats = giver.stats
	local fill = math.clamp(giver.carry / math.max(stats.capacity, 1), 0, 1)
	local seconds = math.clamp(fill * GF.CapSeconds, GF.FloorSeconds, GF.CapSeconds)
	local welcome = not rst.welcomed and t < rst.newUntil
	local paid
	if welcome then
		rst.welcomed = true
		paid = seconds * GF.WelcomeMult
	else
		paid = math.min(seconds, rst.budget)
		rst.budget -= paid
	end
	local received = grant(recv, paid * income(recv))

	-- Quien regala recupera parte de su carga y un poco de gratitud
	local value = giver.carryValue * (stats.depositMult or 1)
	local back = Profiles.addFood(giver, value * (GF.Refund + GF.Gratitude * (if welcome then GF.WelcomeMult else 1)))
	giver.carry = 0
	giver.carryValue = 0
	PlayerService.refreshCarry(giver)
	gst.gifted += received

	local level = math.min((bonds[key] or 0) + 1, F.Max)
	bonds[key] = level
	remember(giver, recv, level)
	remember(recv, giver, level)
	Profiles.refresh(giver)
	Profiles.refresh(recv)
	syncScore(giver, gst)
	sendFriends(giver)
	sendFriends(recv)
	remote:FireAllClients("Gift", giver.player, target, received, back, welcome, level)
end

-- Dúo ----------------------------------------------------------------------------------------------

local function onAte(profile, def, taken: number, byWorkers: boolean)
	if byWorkers then
		return
	end
	local st = states[profile]
	if not st then
		return
	end
	local t = now()
	if t - st.pendingAt > 0.05 then
		st.pending = 0
	end
	st.pending += taken
	st.pendingAt = t
	st.pendingDef = def
end

local function crewOf(food: Model, t: number): { any }
	local crew = {}
	local bites = foodBites[food]
	if bites then
		for other, at in bites do
			if t - at <= D.Window and states[other] and other.player.Parent then
				table.insert(crew, other)
			end
		end
	end
	return crew
end

local function onBite(profile, food: Model)
	local st = states[profile]
	if not st or typeof(food) ~= "Instance" then
		return
	end
	local t = now()
	local bites = foodBites[food]
	if not bites then
		bites = {}
		foodBites[food] = bites
	end
	bites[profile] = t
	local amount = if t - st.pendingAt <= 0.05 then st.pending else 0
	local def = st.pendingDef
	st.pending = 0
	local crew = crewOf(food, t)
	if #crew < 2 then
		return
	end
	if amount > 0 and def then
		local stats = profile.stats
		local piece = if FoodService.isFood(food) then FoodService.pieceValue(food, def, stats) else def.value * (stats.zoneMult[def.zone] or 1)
		profile.carryValue += amount * piece * D.Bonus
	end
	st.duo = if t - st.duoAt <= D.Reset then st.duo + 1 else 1
	st.duoAt = t
	local players = {}
	for _, member in crew do
		table.insert(players, member.player)
	end
	remote:FireAllClients("Duo", profile.player, players, st.duo)
end

local function onFinalBite(_profile, food: Model, position: Vector3)
	local crew = crewOf(food, now())
	foodBites[food] = nil
	if #crew < 2 then
		return
	end
	local players = {}
	for _, member in crew do
		table.insert(players, member.player)
	end
	remote:FireAllClients("DuoFinish", position, players)
end

-- Saludo de antenas --------------------------------------------------------------------------------

local function updateGreetings()
	local t = now()
	local still = {}
	for profile in states do
		local root = rootOf(profile.player)
		local character = profile.player.Character
		if root and character and (root.AssemblyLinearVelocity * FLAT).Magnitude < GR.Still then
			table.insert(still, { profile = profile, root = root, scale = character:GetScale() })
		end
	end
	local holding = {}
	for i = 1, #still do
		for j = i + 1, #still do
			local a, b = still[i], still[j]
			local key = pairKey(a.profile.player, b.profile.player)
			local cd = greetCooldown[key]
			if cd and cd > t then
				continue
			end
			local delta = (b.root.Position - a.root.Position) * FLAT
			local distance = delta.Magnitude
			if distance < 0.5 or distance > GR.Range * math.max(a.scale, b.scale, 1) then
				continue
			end
			local dir = delta.Unit
			local lookA = (a.root.CFrame.LookVector * FLAT)
			local lookB = (b.root.CFrame.LookVector * FLAT)
			if lookA.Magnitude < 0.1 or lookB.Magnitude < 0.1 then
				continue
			end
			if lookA.Unit:Dot(dir) < GR.Facing or lookB.Unit:Dot(-dir) < GR.Facing then
				continue
			end
			local since = greetHold[key] or t
			holding[key] = since
			if t - since >= GR.Hold then
				holding[key] = nil
				greetCooldown[key] = t + GR.Cooldown
				local untilTime = Workspace:GetServerTimeNow() + GR.Duration
				a.profile.player:SetAttribute("GreetSpeedUntil", untilTime)
				b.profile.player:SetAttribute("GreetSpeedUntil", untilTime)
				remote:FireAllClients("Greet", a.profile.player, b.profile.player)
			end
		end
	end
	greetHold = holding
end

-- Vida de cada jugadora ----------------------------------------------------------------------------

local function ensure(profile)
	local st = states[profile]
	if st then
		return st
	end
	local data = saved(profile.data)
	st = {
		joinedAt = now(),
		pantry = 0,
		deposits = {},
		colors = {},
		peace = data.peace,
		peaceAt = -math.huge,
		loot = 0,
		lootFrom = nil,
		lootFromName = nil,
		lootCap = 0,
		blocks = {},
		lastRaidAt = -math.huge,
		budget = GF.BudgetStart,
		newUntil = now() + GF.WelcomeWindow,
		welcomed = false,
		stolen = 0,
		gifted = 0,
		caught = 0,
		duo = 0,
		duoAt = -math.huge,
		pending = 0,
		pendingAt = -math.huge,
		pendingDef = nil,
		collectAt = 0,
		toldAt = -math.huge,
		toldText = "",
		hill = nil,
	}
	states[profile] = st
	local player = profile.player

	-- Si muere, el botín vuelve a su despensa
	st.charConn = player.CharacterAdded:Connect(function()
		local current = states[profile]
		if current then
			dropLoot(profile, current)
		end
	end)

	-- Amistades guardadas con quien ya está en el servidor
	local mine = data.friends
	local touched = {}
	for other in states do
		if other ~= profile then
			local theirs = saved(other.data).friends
			local level = math.max(mine[tostring(other.player.UserId)] or 0, theirs[tostring(player.UserId)] or 0)
			level = math.clamp(math.floor(level), 0, F.Max)
			if level > 0 then
				bonds[pairKey(player, other.player)] = level
				table.insert(touched, other)
			end
		end
	end

	syncScore(profile, st)
	syncLoot(profile)
	Profiles.refresh(profile)
	sendFriends(profile)
	for _, other in touched do
		Profiles.refresh(other)
		sendFriends(other)
	end

	-- Bienvenida: las veteranas se enteran (no al abrir el servidor, cuando entran todas a la vez)
	if now() - startedAt > 20 then
		for other in states do
			if other ~= profile and other.player.Parent then
				remote:FireClient(other.player, "Welcome", player)
			end
		end
	end
	return st
end

local function cleanup(profile, st)
	states[profile] = nil
	if st.charConn then
		st.charConn:Disconnect()
	end
	-- Su botín vuelve a la despensa de la que salió
	if st.loot > 0 and st.lootFrom and states[st.lootFrom] then
		states[st.lootFrom].pantry += st.loot
	end
	for victim, raid in raids do
		if raid.thief == profile or victim == profile then
			raids[victim] = nil
			if raid.chasing then
				remote:FireAllClients("GuardsEnd", raid.hill, "gone")
			end
		end
	end
	-- Quien llevaba botín suyo se lo queda (puede cobrarlo igual)
	if st.hill then
		for _, name in { "PantryPos", "PantryFill", "PantryValue", "PantryOpen", "Peace", "PantryColor1", "PantryColor2", "PantryColor3" } do
			st.hill:SetAttribute(name, nil)
		end
	end
	local userId = profile.player.UserId
	for key in bonds do
		local a, b = string.match(key, "^(%-?%d+):(%-?%d+)$")
		if tonumber(a) == userId or tonumber(b) == userId then
			bonds[key] = nil
		end
	end
	for other in states do
		if other.player.Parent then
			Profiles.refresh(other)
			sendFriends(other)
		end
	end
end

local function onRequest(player: Player, action: any, arg: any)
	local profile = Profiles.get(player)
	local st = profile and states[profile]
	if not st then
		return
	end
	if action == "Raid" then
		onRaid(profile, st, arg)
	elseif action == "Catch" then
		onCatch(profile, st, arg)
	elseif action == "Gift" then
		onGift(profile, st, arg)
	elseif action == "Peace" then
		local want = arg == true
		if want == st.peace then
			return
		end
		local t = now()
		if t - st.peaceAt < S.PeaceCooldown then
			tell(st, profile, "Espera un poco para cambiar de modo (" .. math.ceil(S.PeaceCooldown - (t - st.peaceAt)) .. " s)")
			remote:FireClient(player, "Peace", st.peace)
			return
		end
		if st.loot > 0 or raids[profile] then
			tell(st, profile, "Ahora no: hay un asalto en marcha")
			remote:FireClient(player, "Peace", st.peace)
			return
		end
		for _, raid in raids do
			if raid.thief == profile then
				tell(st, profile, "Ahora no: hay un asalto en marcha")
				remote:FireClient(player, "Peace", st.peace)
				return
			end
		end
		st.peace = want
		st.peaceAt = t
		saved(profile.data).peace = want
		-- La despensa nunca pasa del nuevo tope
		st.pantry = math.min(st.pantry, math.max(recentDeposits(st) * shareOf(st), 0))
		syncScore(profile, st)
		remote:FireClient(player, "Peace", want)
		Profiles.say(profile, if want then "Modo pacífico: ni asalto ni me asaltan" else "Vuelvo al barrio: ¡a por despensas!", 4)
	elseif action == "Sync" then
		sendFriends(profile)
		remote:FireClient(player, "Peace", st.peace)
	end
end

-- Una vuelta del bucle social. Va aparte para protegerla: un fallo no apaga Vecinas para siempre
local function step(t: number, dt: number, ticks: number)
	-- Altas y bajas (sin depender del orden de los demás módulos)
	local all = Profiles.all()
	for profile, st in states do
		if all[profile.player] ~= profile or not profile.player.Parent then
			local ok, err = pcall(cleanup, profile, st)
			if not ok then
				states[profile] = nil -- que una limpieza rota no se repita en cada vuelta
				warn("[CRUNCH!] Vecinas (salida):", err)
			end
		end
	end
	for player, profile in all do
		if not states[profile] and player.Parent and player:GetAttribute("Loaded") then
			ensure(profile)
		end
	end

	for profile, st in states do
		st.budget = math.min(GF.BudgetMax, st.budget + GF.BudgetRate * dt)
		-- Por jugadora: un hormiguero en mal estado no congela Vecinas para las demás
		local ok, err = pcall(updateHome, profile, st)
		if not ok and ticks % 50 == 0 then
			warn("[CRUNCH!] Vecinas:", err)
		end
	end
	updateRaids(dt)

	if ticks % 2 == 0 then
		for profile, st in states do
			pcall(syncHill, profile, st) -- solo pinta el cartel: si falla, ya lo dirá updateHome
		end
	end
	if ticks % 3 == 0 then
		updateGreetings()
	end
	if ticks % 10 == 0 then
		-- Olvida mordiscos viejos y comidas que ya no existen
		for food, bites in foodBites do
			local alive = false
			for who, at in bites do
				if t - at > D.Window or not states[who] then
					bites[who] = nil
				else
					alive = true
				end
			end
			if not alive or not food.Parent then
				foodBites[food] = nil
			end
		end
		for key, untilTime in giftCooldown do
			if untilTime < t then
				giftCooldown[key] = nil
			end
		end
		for key, untilTime in greetCooldown do
			if untilTime < t then
				greetCooldown[key] = nil
			end
		end
	end
end

local function loop()
	local last = os.clock()
	local ticks = 0
	while true do
		task.wait(TICK)
		local t = os.clock()
		local dt = math.min(t - last, 0.5)
		last = t
		ticks += 1
		local ok, err = pcall(step, t, dt, ticks)
		if not ok then
			warn("[CRUNCH!] Vecinas:", err)
		end
	end
end

function Social.start(remotes: Folder)
	remote = Instance.new("RemoteEvent")
	remote.Name = "Social"
	remote.Parent = remotes
	remote.OnServerEvent:Connect(onRequest)

	table.insert(Profiles.onRefresh, onRefresh)
	Events.on("Deposit", onDeposit)
	Events.on("Ate", onAte)
	Events.on("Bite", onBite)
	Events.on("FinalBite", onFinalBite)

	Players.PlayerRemoving:Connect(function(player)
		for profile, st in states do
			if profile.player == player then
				cleanup(profile, st)
			end
		end
	end)

	task.spawn(loop)
end

return Social
