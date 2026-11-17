-- Sonidos. Pocos y con el tono variado, para que morder mil veces no canse.
-- También la música de fondo: suave, barajada y con silencios entre tema y tema.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)

local Sfx = {}

local rng = Random.new()
local bites: { Sound } = {}
local pop: Sound
local streak = 0
local lastDeposit = 0

-- Efectos: todos pasan por Sfx.emit, que pone el límite de voces y el grupo "Efectos"
local MAX_COPIES = 6 -- copias del mismo sonido sonando a la vez
local REPEAT_GAP = 0.035 -- una copia igual (mismo sonido y casi mismo tono) más seguida se descarta
local CROWD = 4 -- desde aquí la copia nueva entra más baja en vez de apilarse a tope
local CROWD_VOLUME = 0.8
local ROLL_MIN, ROLL_MAX = 12, 150 -- 3D: a tope hasta 12 studs, nada más allá de 150

local effectsGroup: SoundGroup? = nil
local effectsMuted = false
local live: { [string]: number } = {}
local lastAt: { [string]: number } = {}
local lastPitch: { [string]: number } = {}
local spot: Vector3? = nil -- mientras Sfx.at corre, lo que suene sale de este punto

-- Música
local MUSIC_VOLUME = 0.16
local FADE_IN = 3
local FADE_OUT = 4
local LOAD_TIMEOUT = 10
local GAP_MIN, GAP_MAX = 6, 18
local MUTE_TIME = 0.4
local MUFFLE_TIME = 0.8

local musicGroup: SoundGroup? = nil
local muffle: EqualizerSoundEffect? = nil
local muted = false
local indoors = false

-- Grupo de los efectos: el interruptor "Efectos" del HUD lo baja sin tocar la música
local function effects(): SoundGroup
	if effectsGroup then
		return effectsGroup
	end
	local created = Instance.new("SoundGroup")
	created.Name = "Efectos"
	created.Volume = if effectsMuted then 0 else 1
	created.Parent = SoundService
	effectsGroup = created
	return created
end

local function make(asset: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = asset
	sound.Volume = volume
	sound.SoundGroup = effects()
	sound.Parent = SoundService
	return sound
end

-- Grupo propio de la música: el silencio y el efecto de "dentro del hormiguero" van aquí
local function group(): SoundGroup
	if musicGroup then
		return musicGroup
	end
	local created = Instance.new("SoundGroup")
	created.Name = "Music"
	created.Volume = if muted then 0 else 1
	created.Parent = SoundService

	local eq = Instance.new("EqualizerSoundEffect")
	eq.Name = "Muffle"
	eq.LowGain = 0
	eq.MidGain = 0
	eq.HighGain = 0
	eq.Parent = created

	musicGroup = created
	muffle = eq
	return created
end

local function tracks(): { string }
	local list = (Assets :: any).Music
	local valid = {}
	if type(list) == "table" then
		for _, asset in list do
			if type(asset) == "string" and asset ~= "" then
				table.insert(valid, asset)
			end
		end
	end
	return valid
end

local function waitLoaded(sound: Sound, timeout: number): boolean
	if sound.IsLoaded then
		return true
	end
	local done = false
	local connection = sound.Loaded:Once(function()
		done = true
	end)
	local started = os.clock()
	while not done and not sound.IsLoaded and os.clock() - started < timeout do
		task.wait(0.1)
	end
	connection:Disconnect()
	return sound.IsLoaded
end

local function fade(sound: Sound, volume: number, seconds: number)
	TweenService:Create(sound, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Volume = volume }):Play()
end

-- Bucle de la música: lista barajada, nunca el mismo tema dos veces seguidas, silencio entre temas
local function musicLoop()
	local list = tracks()
	if #list == 0 then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Looped = false
	sound.Volume = 0
	sound.SoundGroup = group()
	sound.Parent = SoundService

	local bag: { string } = {}
	local last: string? = nil
	local function nextTrack(): string
		if #bag == 0 then
			for _, asset in list do
				table.insert(bag, asset)
			end
			for i = #bag, 2, -1 do
				local j = rng:NextInteger(1, i)
				bag[i], bag[j] = bag[j], bag[i]
			end
			-- Se saca del final: que el primero de la nueva vuelta no repita el último
			if #bag > 1 and bag[#bag] == last then
				bag[#bag], bag[1] = bag[1], bag[#bag]
			end
		end
		return table.remove(bag) :: string
	end

	while true do
		local asset = nextTrack()
		last = asset
		sound.Volume = 0
		sound.SoundId = asset

		local length = 0
		if waitLoaded(sound, LOAD_TIMEOUT) then
			length = sound.TimeLength
		end
		if length <= 0 then
			-- No cargó: se salta sin ruido (y sin girar en vacío si fallan todos)
			task.wait(2)
			continue
		end

		local fadeIn = math.min(FADE_IN, length * 0.3)
		local fadeOut = math.min(FADE_OUT, length * 0.3)
		sound.TimePosition = 0
		sound:Play()
		fade(sound, MUSIC_VOLUME, fadeIn)

		-- Espera hasta el momento de empezar a apagarse (o a que acabe por su cuenta)
		while sound.IsPlaying and sound.TimePosition < length - fadeOut do
			task.wait(0.25)
		end
		if sound.IsPlaying then
			fade(sound, 0, fadeOut)
			task.wait(fadeOut)
		end
		sound:Stop()
		sound.Volume = 0

		task.wait(rng:NextNumber(GAP_MIN, GAP_MAX))
	end
end

-- Los sonidos de personaje de Roblox (pasos, salto, caída, aterrizaje) son de humano: en una hormiga
-- sobran. Los crea en local el script RbxCharacterSounds dentro de la HumanoidRootPart; aquí se dejan
-- a volumen 0 (no se borran: ese script los sigue usando y fallaría).
local CHARACTER_SOUNDS = {
	Climbing = true,
	Died = true,
	FreeFalling = true,
	GettingUp = true,
	Jumping = true,
	Landing = true,
	Running = true,
	Splash = true,
	Swimming = true,
}

local function hush(child: Instance)
	if child:IsA("Sound") and CHARACTER_SOUNDS[child.Name] then
		child.Volume = 0
		-- La caída sube su volumen con la velocidad: se vuelve a dejar en 0
		child:GetPropertyChangedSignal("Volume"):Connect(function()
			if child.Volume ~= 0 then
				child.Volume = 0
			end
		end)
	end
end

local function hushCharacter(character: Model)
	local function watch(root: Instance)
		root.ChildAdded:Connect(hush)
		for _, child in root:GetChildren() do
			hush(child)
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		watch(root)
		return
	end
	-- La raíz puede llegar tarde (carga lenta): se espera sin tope de tiempo
	local waiting: RBXScriptConnection
	waiting = character.ChildAdded:Connect(function(child)
		if child.Name == "HumanoidRootPart" then
			waiting:Disconnect()
			watch(child)
		end
	end)
end

local function hushPlayer(who: Player)
	who.CharacterAdded:Connect(hushCharacter)
	if who.Character then
		task.spawn(hushCharacter, who.Character)
	end
end

function Sfx.start()
	for _, asset in Assets.Sounds.Bite do
		table.insert(bites, make(asset, 0.35))
	end
	pop = make(Assets.Sounds.Pop, 0.5)

	Players.PlayerAdded:Connect(hushPlayer)
	for _, who in Players:GetPlayers() do
		hushPlayer(who)
	end

	group()
	task.delay(4, musicLoop)
end

-- Único punto por el que sale un efecto (también los de CasteFx). `copy` llega listo (tono, volumen,
-- efectos) y sin padre. Con `at` suena en 3D en ese punto del mundo. Devuelve si sonó.
function Sfx.emit(copy: Sound, at: Vector3?, important: boolean?): boolean
	local id = copy.SoundId
	local now = os.clock()
	local count = live[id] or 0
	-- En 3D y fuera de oído: ni suena ni ocupa hueco del límite
	local camera = Workspace.CurrentCamera
	if at and camera and (camera.CFrame.Position - at).Magnitude > ROLL_MAX then
		copy:Destroy()
		return false
	end
	local twin = lastAt[id] ~= nil and now - lastAt[id] < REPEAT_GAP and math.abs(copy.PlaybackSpeed / lastPitch[id] - 1) < 0.06
	-- Los avisos con nombre (error, compra, capa, enjambrar) nunca se recortan: son pocos y cuentan algo
	if not important and (count >= MAX_COPIES or twin) then
		copy:Destroy()
		return false
	end
	lastAt[id] = now
	lastPitch[id] = math.max(copy.PlaybackSpeed, 0.01)
	if count >= CROWD then
		copy.Volume *= CROWD_VOLUME
	end
	live[id] = count + 1
	copy.SoundGroup = effects()

	local holder: Instance = copy
	if at then
		-- Bajo Terrain la posición local de un Attachment es la del mundo
		local attachment = Instance.new("Attachment")
		attachment.Name = "Sfx"
		attachment.Position = at
		attachment.Parent = Workspace.Terrain
		copy.RollOffMode = Enum.RollOffMode.InverseTapered
		copy.RollOffMinDistance = ROLL_MIN
		copy.RollOffMaxDistance = ROLL_MAX
		copy.Parent = attachment
		holder = attachment
	else
		copy.Parent = SoundService
	end

	local released = false
	local function release()
		if released then
			return
		end
		released = true
		live[id] = math.max(0, (live[id] or 1) - 1)
		holder:Destroy()
	end
	copy.Ended:Once(release)
	task.delay(3, release)
	copy:Play()
	return true
end

local function play(sound: Sound, pitch: number, volume: number?, at: Vector3?, important: boolean?)
	if not sound then
		return
	end
	local copy = sound:Clone()
	copy.PlaybackSpeed = pitch
	if volume then
		copy.Volume = volume
	end
	Sfx.emit(copy, at, important)
end

local function anyBite(): Sound
	return bites[rng:NextInteger(1, #bites)]
end

-- Lo que suene dentro de `fn` (también sus notas con retraso) sale en 3D desde `position`: para lo
-- que hace otra jugadora cerca. Se lee `spot` al llamar, por eso las notas con retraso lo llevan.
function Sfx.at(position: Vector3, fn: (...any) -> (), ...: any)
	spot = position
	local ok, err = pcall(fn, ...)
	spot = nil
	if not ok then
		warn("[CRUNCH!] Sfx.at:", err)
	end
end

-- Un sonido suelto en 3D, con atenuación por distancia. kind: "pop" | "bite"
function Sfx.near(position: Vector3, kind: string, pitch: number?)
	if typeof(position) ~= "Vector3" then
		return
	end
	if kind == "bite" then
		if #bites > 0 then
			play(anyBite(), pitch or rng:NextNumber(1.15, 1.5), nil, position)
		end
	else
		play(pop, pitch or rng:NextNumber(0.95, 1.1), nil, position)
	end
end

-- `boost` (opcional) multiplica el tono: la racha lo va subiendo
function Sfx.bite(big: boolean, boost: number?, volume: number?)
	if #bites == 0 then
		return
	end
	local pitch = if big then rng:NextNumber(0.7, 0.8) else rng:NextNumber(1.15, 1.5)
	play(anyBite(), pitch * (boost or 1), volume, spot)
end

function Sfx.pop(pitch: number?, volume: number?)
	play(pop, pitch or rng:NextNumber(0.95, 1.1), volume, spot)
end

-- Golpecito flojo (contador que rueda, medidor que se llena)
function Sfx.tick(pitch: number?)
	play(pop, pitch or 1.6, 0.14, spot)
end

-- Zumbido eléctrico de un salto del rayo: tres chasquidos muy seguidos que suben con cada salto
function Sfx.zap(step: number)
	local base = 1.3 + 0.16 * step
	for i = 0, 2 do
		task.delay(i * 0.025, play, pop, base + i * 0.22, 0.32 - i * 0.07, spot)
	end
	if #bites > 0 then
		play(anyBite(), 1.9 + 0.1 * step, 0.18, spot)
	end
end

-- Mini fanfarria de remate: más notas cuanto más grande era la comida (1..3)
function Sfx.finish(size: number)
	local notes = math.clamp(math.floor(size + 0.5), 1, 3)
	for i = 0, notes do
		task.delay(i * 0.06, play, pop, 0.95 + i * 0.2, 0.42, spot)
	end
end

-- El tono sube con cada depósito seguido
function Sfx.deposit()
	local now = os.clock()
	streak = if now - lastDeposit < 12 then math.min(streak + 1, 10) else 0
	lastDeposit = now
	play(pop, 0.9 + streak * 0.07, nil, spot)
end

function Sfx.fanfare()
	for i = 0, 4 do
		task.delay(i * 0.09, play, pop, 0.8 + i * 0.18, 0.5, spot)
	end
end

-- Sonidos con nombre (solo con los mordiscos y el pop, cambiando tono y ritmo para que no se
-- confundan). Tonos de acorde mayor: 1, 1.25, 1.5, 2.

-- "No puedes": golpe grave y corto, dos notas que bajan
function Sfx.error()
	local at = spot
	if #bites > 0 then
		play(bites[1], 0.5, 0.4, at, true)
	end
	task.delay(0.06, play, pop, 0.42, 0.45, at, true)
end

-- Compra hecha: chasquido seco ("ka") y tres notas altas que suben rápido ("ching")
function Sfx.buy()
	local at = spot
	if #bites > 0 then
		play(bites[#bites], 2.1, 0.25, at, true)
	end
	for i, pitch in { 1.6, 2, 2.4 } do
		task.delay(0.04 + (i - 1) * 0.055, play, pop, pitch, 0.42, at, true)
	end
end

-- Subir de capa / excavar: fanfarria media, arpegio y acorde final
function Sfx.levelUp()
	local at = spot
	if #bites > 0 then
		play(bites[1], 0.7, 0.3, at, true)
	end
	for i, pitch in { 1, 1.25, 1.5 } do
		task.delay((i - 1) * 0.08, play, pop, pitch, 0.45, at, true)
	end
	task.delay(0.26, play, pop, 2, 0.48, at, true)
	task.delay(0.26, play, pop, 1.5, 0.3, at, true)
end

-- Enjambrar: la más grande. Golpe grave, arpegio largo de dos octavas y acorde con otro golpe
function Sfx.rebirth()
	local at = spot
	if #bites > 0 then
		play(bites[1], 0.45, 0.5, at, true)
	end
	for i, pitch in { 0.75, 1, 1.25, 1.5, 2 } do
		task.delay(0.1 + (i - 1) * 0.08, play, pop, pitch, 0.45, at, true)
	end
	for _, pitch in { 1.5, 2, 3 } do
		task.delay(0.62, play, pop, pitch, 0.4, at, true)
	end
	if #bites > 0 then
		task.delay(0.62, play, bites[#bites], 0.55, 0.45, at, true)
	end
end

-- Silencia solo la música (sigue sonando por debajo y conserva su posición)
function Sfx.setMuted(value: boolean)
	muted = value
	TweenService:Create(group(), TweenInfo.new(MUTE_TIME), { Volume = if value then 0 else 1 }):Play()
end

function Sfx.isMuted(): boolean
	return muted
end

-- Silencia los efectos (grupo "Efectos"); la música no se toca
function Sfx.setEffectsMuted(value: boolean)
	effectsMuted = value
	TweenService:Create(effects(), TweenInfo.new(MUTE_TIME), { Volume = if value then 0 else 1 }):Play()
end

function Sfx.isEffectsMuted(): boolean
	return effectsMuted
end

-- Dentro del hormiguero la música se oye apagada, como a través de la tierra
function Sfx.setIndoors(inside: boolean)
	if inside == indoors and muffle then
		return
	end
	indoors = inside
	group()
	local eq = muffle :: EqualizerSoundEffect
	local goal = if inside then { LowGain = -2, MidGain = -8, HighGain = -30 } else { LowGain = 0, MidGain = 0, HighGain = 0 }
	TweenService:Create(eq, TweenInfo.new(MUFFLE_TIME, Enum.EasingStyle.Sine), goal):Play()
end

return Sfx
