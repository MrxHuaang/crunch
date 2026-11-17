local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local Abilities = require(script.Abilities)
local AntAnim = require(script.AntAnim)
local Bubble = require(script.Bubble)
local Comic = require(script.Comic)
local Fx = require(script.Fx)
local Hud = require(script.Hud)
local Places = require(script.Places)
local Sfx = require(script.Sfx)
local State = require(script.State)
local Store = require(script.Store)
local Swarm = require(script.Swarm)
local Targeting = require(script.Targeting)
local Tree = require(script.Tree)
local Wardrobe = require(script.Wardrobe)
local Chain = require(script.Chain)
local Tunnel = require(script.Tunnel)
-- Primeros pasos (opcional): mientras dura su cadena de metas, la tira de narración es suya
local Opening = if script:FindFirstChild("Opening") then require(script.Opening) :: any else nil

local player = Players.LocalPlayer
-- El servidor tarda unos segundos en levantar el mundo: se espera con margen, sin aviso de espera infinita
local remotes = ReplicatedStorage:WaitForChild("Remotes", 180) :: Folder
local foods = Workspace:WaitForChild("Food", 180) :: Instance

-- Límites de zoom y distancia al aparecer para una hormiga de escala 1. Crecen con ella (fitCamera).
local ZOOM_MIN, ZOOM_MAX, ZOOM_START = 8, 45, 12.5
player.CameraMaxZoomDistance = ZOOM_MAX
player.CameraMinZoomDistance = ZOOM_MIN

-- Una hormiga no tiene barra de vida ni mochila
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- El tamaño real de la pantalla decide la distribución de celular (Hud.compact): al primer instante
-- la cámara aún puede medir 1x1
while not workspace.CurrentCamera or workspace.CurrentCamera.ViewportSize.X <= 1 do
	task.wait()
end

Sfx.start()
Fx.start()
local hud = Hud.start()

-- Calidad: en celular o con la calidad gráfica en baja (1-3), el decorado pierde el contorno de tinta:
-- cada Highlight vuelve a dibujar todo lo que contiene. La comida, los hormigueros, las puertas y el
-- enjambre lo conservan, porque es lo que se busca y se toca.
local DECOR_OUTLINES = { { "Zones" }, { "Props" }, { "Life", "Clouds" }, { "Life", "Critters" }, { "GardenToys" }, { "Board" } }
local function lowQuality(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return Hud.compact() or (ok and level >= 1 and level <= 3)
end
task.spawn(function()
	while true do -- barato (seis búsquedas) y sigue al ajuste de calidad y a lo que aparece tarde
		local on = not lowQuality()
		for _, path in DECOR_OUTLINES do
			local holder: Instance? = Workspace
			for _, name in path do
				holder = holder and holder:FindFirstChild(name)
			end
			local outline = holder and holder:FindFirstChildOfClass("Highlight")
			if outline and outline.Enabled ~= on then
				outline.Enabled = on
			end
		end
		task.wait(3)
	end
end)
Bubble.start()
Places.start()
AntAnim.start()
Swarm.start()
Targeting.start()
Tree.start(remotes)
Store.start()
Wardrobe.start(remotes)
Tunnel.start(remotes)
Abilities.start(hud, remotes)

-- Módulos opcionales: cada uno trae su propia interfaz y se arranca solo si existe.
-- Un fallo en uno no debe tumbar el resto del juego.
for _, name in { "Life", "Ambience", "Quests", "WorldEvents", "Pets", "Hazards", "Allies", "Extras", "Perks", "Garden", "Opening", "Juice", "CasteClient", "Social", "Emotes", "Orders", "Stalls" } do
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

-- Panel DEV, solo en Studio. El servidor crea Remotes.Dev después de la carpeta, así que se espera un poco.
if RunService:IsStudio() and script:FindFirstChild("DevPanel") then
	task.spawn(function()
		if not remotes:WaitForChild("Dev", 20) then
			return
		end
		local ok, err = pcall(function()
			require(script.DevPanel).start(remotes)
		end)
		if not ok then
			warn("[CRUNCH!] No se pudo cargar DevPanel", err)
		end
	end)
end

local keyboard = UserInputService.KeyboardEnabled
local HOW_TO_BITE = if keyboard
	then "Acércate a una miga y mantén clic para morder"
	else "Junto a una miga, mantén pulsado para morder"
local HOW_TO_AUTOBITE = "Acércate a una miga: muerdo yo sola"
local HOW_TO_UPGRADE = if keyboard
	then "Tengo comida de sobra. Pulsa Q para excavar"
	else "Tengo comida de sobra. Toca Hormiguero"
local EGG_HINT = "Hay un huevo dorado junto a tu hormiguero"

local hasBitten = false
local carryColor: Color3? = nil
local canUpgrade = false
local eggWaiting = false
local knownDepth: number? = nil -- capa con la que empezó la sesión (o la última vista)
local newZone: number? = nil -- zona recién abierta en la que aún no has entrado

local function rootPart(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

-- Paneles opcionales: se miran solo si el módulo existe y expone isOpen (con pcall: uno roto no
-- deja a la hormiga sin morder)
local OPTIONAL_PANELS = { "CasteClient", "Orders", "Social", "Emotes", "DevPanel" } -- Castas, Órdenes, Vecinas, álbum de memes, panel DEV
local optionalPanels: { any } = {}
for _, name in OPTIONAL_PANELS do
	local module = script:FindFirstChild(name)
	if module then
		local ok, lib = pcall(require, module)
		if ok and type(lib) == "table" and type(lib.isOpen) == "function" then
			table.insert(optionalPanels, lib)
		end
	end
end

local function panelOpen(): boolean
	if Tree.isOpen() or Store.isOpen() or Wardrobe.isOpen() then
		return true
	end
	-- Mapa del túnel
	local okTunnel, tunnelOpen = pcall(Tunnel.isOpen)
	if okTunnel and tunnelOpen then
		return true
	end
	for _, lib in optionalPanels do
		local ok, open = pcall(lib.isOpen)
		if ok and open then
			return true
		end
	end
	return false
end

local function nothingBought(): boolean
	if State.num("Workers") > 0 or next(State.minis()) ~= nil then
		return false
	end
	for _, level in State.nodes() do
		if level > 0 then
			return false
		end
	end
	return true
end

-- Lo que toca hacer, en orden de prioridad, en la tira de narración del HUD
local function refreshHint()
	if panelOpen() then
		Bubble.say(nil)
		return
	end
	local carry = State.num("Carry")
	local fresh = State.num("RunFood") == 0 and State.num("Rebirths") == 0
	local opening, openingUrgent = nil, nil
	if Opening then
		opening, openingUrgent = Opening.hint()
	end

	if carry >= State.stats().capacity then
		-- Al principio es urgente (no se esconde sola); luego basta con el "¡LLENA!" y la flecha (Juice)
		Bubble.say("¡Voy llena! Al hormiguero", fresh)
	elseif opening then
		Bubble.say(opening, openingUrgent)
	elseif fresh and carry == 0 and not hasBitten then
		Bubble.say(if State.flag("P_autoBite") then HOW_TO_AUTOBITE else HOW_TO_BITE)
	elseif fresh and carry > 0 then
		Bubble.say(if State.depth() >= 2 then "Lleva las migas a un hormiguero: el de casa o el de la zona" else "Lleva las migas a tu hormiguero")
	elseif canUpgrade and nothingBought() then
		Bubble.say(HOW_TO_UPGRADE)
	elseif newZone and Config.Zones[newZone] then
		Bubble.say("Zona nueva: " .. Config.Zones[newZone].name .. ". Sigue el camino hacia delante")
	elseif eggWaiting then
		Bubble.say(EGG_HINT)
	else
		Bubble.say(nil)
	end
end

-- Al desbloquear una habilidad, la hormiga explica cómo se usa.
-- Las alas pueden llegar también por un pase: se miran en el atributo HasWings.
local known: { [string]: boolean } = {}
local primed = false
local function announceUnlocks()
	if not State.flag("Loaded") then
		return
	end
	local nodes = State.nodes()
	for _, def in Config.Tree do
		if def.hint then
			local has = if def.id == "wings" then State.flag("HasWings") else (nodes[def.id] or 0) > 0
			if primed and has and not known[def.id] then
				local how = if keyboard then "Pulsa " .. def.key else "Toca " .. def.button
				Bubble.flash((def.hint:gsub("{tecla}", how)), 7)
			end
			known[def.id] = has
		end
	end
	primed = true
end

-- Capas: al excavar una, su zona queda "nueva" hasta que la pisas
local function trackDepth()
	if not State.flag("Loaded") then
		return
	end
	local depth = State.depth()
	if knownDepth == nil then
		knownDepth = depth
	elseif depth > knownDepth then
		knownDepth = depth
		newZone = depth
	elseif depth < knownDepth then
		-- Enjambraste: las capas vuelven a empezar
		knownDepth = depth
		if newZone and newZone > depth then
			newZone = nil
		end
	end
end

local function refresh()
	local stats = State.stats()
	Hud.setFood(State.num("Food"))
	Hud.setTags(State.num("Jelly"), State.num("Rebirths"), State.num("Workers"), stats.workerCap)
	Hud.setCarry(State.num("Carry"), stats.capacity, carryColor)
	Hud.setDepth(State.depth())
	Hud.setBuff(State.num("BuffUntil"))
	canUpgrade = Tree.refresh()
	Hud.setBadge(canUpgrade and not Tree.isOpen())
	trackDepth()
	announceUnlocks()
	refreshHint()
end

-- Cámara a la medida de la hormiga: AntLook la reescala (ScaleTo) al excavar capas y con 12 studs
-- acababa tapando media pantalla. Solo se tocan los límites de zoom y, al aparecer o crecer, la
-- distancia; entre medias el zoom es de la jugadora.
local zoomCharacter: Model? = nil
local zoomScale = 1

local function setZoomLimits(min: number, max: number)
	-- En este orden el mínimo nunca queda por encima del máximo
	if min > player.CameraMaxZoomDistance then
		player.CameraMaxZoomDistance = max
		player.CameraMinZoomDistance = min
	else
		player.CameraMinZoomDistance = min
		player.CameraMaxZoomDistance = max
	end
end

local function fitCamera()
	local character = player.Character
	if not character then
		return
	end
	local scale = math.max(character:GetScale(), 1) -- nunca más cerca que hoy
	local spawned = character ~= zoomCharacter
	if not spawned and math.abs(scale - zoomScale) < 0.05 then
		return
	end
	-- Al aparecer, la distancia de partida; al crecer, la que tenías, en proporción
	local camera = Workspace.CurrentCamera
	local distance = ZOOM_START * scale
	if not spawned and camera then
		distance = (camera.CFrame.Position - camera.Focus.Position).Magnitude * scale / zoomScale
	end
	zoomCharacter, zoomScale = character, scale
	distance = math.clamp(distance, ZOOM_MIN * scale, ZOOM_MAX * scale)
	-- Mínimo = máximo durante un fotograma deja la cámara a esa distancia; luego se sueltan
	setZoomLimits(distance, distance)
	task.wait()
	setZoomLimits(ZOOM_MIN * scale, ZOOM_MAX * scale)
end

-- Bucle ligero para lo que no avisa con atributos del jugador: el huevo dorado (atributo del
-- hormiguero), si ya pisaste la zona nueva y los paneles abiertos.
local function updateContext()
	local hill = State.hill()
	local root = rootPart()
	eggWaiting = hill ~= nil and hill:GetAttribute("Egg") == true

	if newZone and root then
		local zone = Config.Zones[newZone]
		if not zone or root.Position.Z < zone.z0 then
			newZone = nil
		end
	end
	refreshHint()
end

State.onChange(refresh)
refresh()

task.spawn(function()
	while true do
		task.wait(0.25)
		updateContext()
		fitCamera() -- comprueba a ritmo bajo si apareciste o creciste
	end
end)

Hud.onAnthill = Tree.toggle
Hud.onStore = Store.open
Hud.onWardrobe = Wardrobe.toggle
Hud.showStore(Store.enabled())

remotes.Fx.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any, f: any, g: any)
	if kind == "Bite" then
		hasBitten = true
		Hud.setCombo(e or 0)
		-- c: remate; d: crítico; e: racha; f: mordisco dorado (galerías); g: la comida era dorada.
		-- Fx.bite pone impacto, palabra, sonido, racha, remate y la ráfaga del área.
		Fx.bite(a, b, c, d, e, f == true, g == true)
	elseif kind == "Deposit" then
		-- Chorro de migajas, el hormiguero traga y palabra con lo acreditado (Fx.deposit)
		Sfx.deposit()
		Fx.deposit(a, c, tonumber(b))
		Hud.punchFood()
	elseif kind == "Egg" then
		Fx.burst(a, "¡HUEVO DORADO!\n+" .. Format.short(b), Comic.Yellow, 300)
		Sfx.fanfare()
		Hud.punchFood()
	elseif kind == "Fungus" then
		Fx.burst(a, "¡Comida x2!", Comic.Green, 240)
		Sfx.pop(1.3)
		Bubble.flash("¡Qué hongo! Comida doble durante " .. math.floor(tonumber(b) or 0) .. " s", 4)
	elseif kind == "Say" then
		Bubble.flash(a, b or 4)
	elseif kind == "Bought" then
		Tree.celebrate(a, b)
		AntAnim.cheer()
		if a == "dig" then
			local depth = if type(b) == "number" then b else State.depth()
			local zone = Config.Zones[depth]
			if zone then
				Bubble.flash("¡Capa nueva! Ya puedo entrar en " .. zone.name, 5)
			end
			Fx.speed(1)
		end
	elseif kind == "Worn" then
		Sfx.pop(1.2)
	elseif kind == "Trail" then
		if b then
			Fx.burst(a, "¡Por aquí!", Comic.Cyan, 180)
		end
		Sfx.pop(if b then 1.3 else 0.7)
	elseif kind == "Frenzy" then
		Fx.speed(1.5)
		Sfx.fanfare()
		local character = player.Character
		if character then
			Fx.burst(character:GetPivot().Position + Vector3.new(0, 3, 0), "¡FRENESÍ!", Comic.Red, 260)
		end
	elseif kind == "Chain" then
		Chain.play(a, b, c)
	elseif kind == "Tunnel" then
		Tunnel.travel(a, b)
	elseif kind == "Rebirth" then
		Hud.setCombo(0)
		Fx.rebirth(a)
		Sfx.rebirth()
	end
	refreshHint()
end)

-- Cada pieza que pierde una comida sale volando, la muerdas tú o tus obreras
foods.DescendantRemoving:Connect(function(instance)
	if instance:IsA("BasePart") and instance.Name == "Piece" then
		local camera = Workspace.CurrentCamera
		if camera and (camera.CFrame.Position - instance.Position).Magnitude < 140 then
			Fx.chunk(instance)
		end
	end
end)

-- Progreso propio con la tarta, encima de ella. Solo cuando ya llegas a su zona.
local tartaSign = Instance.new("BillboardGui")
tartaSign.Size = UDim2.fromOffset(190, 40)
tartaSign.AlwaysOnTop = true
tartaSign.LightInfluence = 0
tartaSign.MaxDistance = 110
tartaSign.ResetOnSpawn = false
tartaSign.Enabled = false
tartaSign.Parent = player:WaitForChild("PlayerGui")
local tartaLabel = Comic.label(tartaSign, "", Comic.Display, 26, Comic.Paper)
tartaLabel.Size = UDim2.fromScale(1, 1)
Comic.ink(tartaLabel, 3)

task.spawn(function()
	local total = Config.FoodById.Tarta.hp
	local tartaZone = Config.FoodById.Tarta.zone
	while true do
		local tarta = foods:FindFirstChild("Tarta")
		local show = tarta ~= nil and State.depth() >= tartaZone
		tartaSign.Enabled = show
		if show then
			tartaSign.Adornee = tarta
			tartaSign.StudsOffsetWorldSpace = Vector3.new(0, 24, 0)
			tartaLabel.Text = if State.flag("TartaDone")
				then "¡Tarta comida!"
				else "Tarta " .. math.floor(math.min(1, State.num("TartaDamage") / total) * 100) .. " %"
		end
		task.wait(0.5)
	end
end)

-- Solo en Studio: abrir paneles desde la barra de comandos para revisarlos sin teclado
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("DevTree"):Connect(Tree.toggle)
	player:GetAttributeChangedSignal("DevWardrobe"):Connect(Wardrobe.toggle)
	player:GetAttributeChangedSignal("DevSplash"):Connect(function()
		Fx.rebirth(12)
	end)
end

-- Tecla V: el vestidor
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.V then
		Wardrobe.toggle()
	end
end)

-- Morder: mantener clic, toque, E o el botón X del mando. Con el pase de mordida automática,
-- muerde sola en cuanto hay comida a tiro.
local holding = false
local lastBite = 0

local function isBiteInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.ButtonX
end

-- En táctil solo cuenta el dedo que empezó a morder: soltar el joystick o el salto no lo corta,
-- y si ese dedo se arrastra es que está girando la cámara.
local biteTouch: InputObject? = nil
local biteTouchFrom = Vector3.zero
local DRAG_PX = 12

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and isBiteInput(input) then
		holding = true
		if input.UserInputType == Enum.UserInputType.Touch then
			biteTouch, biteTouchFrom = input, input.Position
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input == biteTouch and (input.Position - biteTouchFrom).Magnitude > DRAG_PX then
		holding, biteTouch = false, nil
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		if input == biteTouch then
			holding, biteTouch = false, nil
		end
	elseif isBiteInput(input) then
		holding = false
	end
end)

RunService.Heartbeat:Connect(function()
	local auto = State.flag("P_autoBite")
	if not holding and not auto then
		return
	end
	if panelOpen() then
		return
	end
	local now = os.clock()
	if now - lastBite < State.stats().biteCooldown then
		return
	end

	local target = Targeting.current()
	if State.num("Carry") >= State.stats().capacity then
		-- Solo sacude si lo intentas tú; la automática espera a que vuelvas a casa
		if holding then
			lastBite = now
			Hud.shakeCarry()
		end
	elseif target then
		lastBite = now
		carryColor = target:GetAttribute("Color")
		remotes.Bite:FireServer(target)
		AntAnim.bite()
		Fx.squash(target)
	end
end)
