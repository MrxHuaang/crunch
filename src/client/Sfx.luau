-- Sonidos. Pocos y con el tono variado, para que morder mil veces no canse.
-- También la música de fondo: suave, barajada y con silencios entre tema y tema.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.Assets)

local Sfx = {}

local rng = Random.new()
local bites: { Sound } = {}
local pop: Sound
local streak = 0
local lastDeposit = 0

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

local function make(asset: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = asset
	sound.Volume = volume
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

function Sfx.start()
	for _, asset in Assets.Sounds.Bite do
		table.insert(bites, make(asset, 0.35))
	end
	pop = make(Assets.Sounds.Pop, 0.5)

	group()
	task.delay(4, musicLoop)
end

local function play(sound: Sound, pitch: number, volume: number?)
	if not sound then
		return
	end
	local copy = sound:Clone()
	copy.PlaybackSpeed = pitch
	if volume then
		copy.Volume = volume
	end
	copy.Parent = SoundService
	copy:Play()
	copy.Ended:Once(function()
		copy:Destroy()
	end)
	task.delay(3, function()
		copy:Destroy()
	end)
end

-- `boost` (opcional) multiplica el tono: la racha lo va subiendo
function Sfx.bite(big: boolean, boost: number?, volume: number?)
	if #bites == 0 then
		return
	end
	local pitch = if big then rng:NextNumber(0.7, 0.8) else rng:NextNumber(1.15, 1.5)
	play(bites[rng:NextInteger(1, #bites)], pitch * (boost or 1), volume)
end

function Sfx.pop(pitch: number?, volume: number?)
	play(pop, pitch or rng:NextNumber(0.95, 1.1), volume)
end

-- Golpecito flojo (contador que rueda, medidor que se llena)
function Sfx.tick(pitch: number?)
	play(pop, pitch or 1.6, 0.14)
end

-- Zumbido eléctrico de un salto del rayo: tres chasquidos muy seguidos que suben con cada salto
function Sfx.zap(step: number)
	local base = 1.3 + 0.16 * step
	for i = 0, 2 do
		task.delay(i * 0.025, play, pop, base + i * 0.22, 0.32 - i * 0.07)
	end
	if #bites > 0 then
		play(bites[rng:NextInteger(1, #bites)], 1.9 + 0.1 * step, 0.18)
	end
end

-- Mini fanfarria de remate: más notas cuanto más grande era la comida (1..3)
function Sfx.finish(size: number)
	local notes = math.clamp(math.floor(size + 0.5), 1, 3)
	for i = 0, notes do
		task.delay(i * 0.06, play, pop, 0.95 + i * 0.2, 0.42)
	end
end

-- El tono sube con cada depósito seguido
function Sfx.deposit()
	local now = os.clock()
	streak = if now - lastDeposit < 12 then math.min(streak + 1, 10) else 0
	lastDeposit = now
	play(pop, 0.9 + streak * 0.07)
end

function Sfx.fanfare()
	for i = 0, 4 do
		task.delay(i * 0.09, play, pop, 0.8 + i * 0.18)
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
