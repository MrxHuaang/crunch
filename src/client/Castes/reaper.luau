-- Segadora (cliente): tajos en media luna, la Guillotina (salto de la dueña), el Torbellino, la Gran
-- Siega con su surco, el aura de mandíbulas de guadaña y el emblema.
-- El servidor manda en cada efecto los puntos exactos que golpeó; aquí solo se pinta.

local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Fx = require(script.Parent.Parent.CasteFx)
local OldFx = require(script.Parent.Parent.Fx)
local Abilities = require(script.Parent.Parent.Abilities)
local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local rng = Random.new()
local UP = Vector3.new(0, 1, 0)
local FLAT = Vector3.new(1, 0, 1)
local INK = Color3.fromRGB(20, 16, 16)
local RED = Color3.fromRGB(178, 24, 38)
local BLOOD = Color3.fromRGB(230, 40, 50)
local BONE = Color3.fromRGB(240, 228, 200)
local GOLD = Color3.fromRGB(255, 196, 40)
local SEEN = 260
local GROUND = Config.GroundY + 0.06 -- el suelo del jardín

----------------------------------------------------------------------------------------------------
-- Ayudas

-- Onomatopeya: los tamaños de este archivo van en "veces lo normal" (CasteFx.word mide en píxeles);
-- las grandes llevan estallido de cómic detrás
local function word(pos: Vector3, text: string, opts: any?)
	local o = table.clone(opts or {})
	local k = tonumber(o.size) or 1
	o.size = 46 * k
	if o.burst == nil then
		o.burst = k >= 1.2
	end
	Fx.word(pos, text, o)
end

-- Onda pegada al suelo (los puntos del servidor van a media altura) y con grosor razonable
local function ring(pos: Vector3, radius: number, opts: any?)
	local o = table.clone(opts or {})
	if o.thickness then
		o.thickness = math.min(o.thickness, 1.4)
	end
	Fx.ring(Vector3.new(pos.X, Config.GroundY + 0.06, pos.Z), radius, o)
end

local function seen(pos: Vector3?): boolean
	local camera = Workspace.CurrentCamera
	return pos == nil or camera == nil or (camera.CFrame.Position - pos).Magnitude < SEEN
end

local function vec(v: any, fallback: Vector3?): Vector3?
	return if typeof(v) == "Vector3" then v else fallback
end

local function list(v: any): { Vector3 }
	local out = {}
	if type(v) == "table" then
		for _, p in v do
			if typeof(p) == "Vector3" then
				table.insert(out, p)
			end
		end
	end
	return out
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = v * FLAT
	return if f.Magnitude > 0.05 then f.Unit else fallback
end

local function turn(dir: Vector3, degrees: number): Vector3
	return CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(dir)
end

local function tween(obj: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then
		p.Shape = props.Shape -- antes que Size: una bola fuerza tamaño uniforme
	end
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent or Fx.folder()
	return p
end

local function fadeOut(p: BasePart, time: number)
	tween(p, time, { Transparency = 1 })
	Debris:AddItem(p, time + 0.05)
end

local function foodAt(pt: Vector3): Model?
	local folder = Workspace:FindFirstChild("Food")
	if not folder then
		return nil
	end
	local best, bestGap = nil, 2.5
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			local gap = (model:GetPivot().Position + UP - pt).Magnitude
			if gap < bestGap then
				best, bestGap = model, gap
			end
		end
	end
	return best
end

local function react(pts: { Vector3 }, from: Vector3?, amount: number?)
	for i, pt in pts do
		if i > 14 then
			break
		end
		local food = foodAt(pt)
		if food then
			pcall(OldFx.squash, food, amount or 0.24, from)
		end
	end
end

local function loot(caster: Player, pts: { Vector3 }, color: Color3?)
	if #pts == 0 then
		return
	end
	local hill = Fx.hillOf(caster)
	if hill then
		Fx.orbs(pts, hill, { color = color or BONE })
	end
end

local function rootOf(who: Player): BasePart?
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Mutaciones de la dueña (para lo que hace el cliente al lanzar)
local function myFlags(): (string) -> boolean
	local ok, has = pcall(function()
		local Castes = require(ReplicatedStorage.Shared.Castes)
		local def = Castes.get("reaper")
		local raw = player:GetAttribute("CasteData")
		local data = if type(raw) == "string" and raw ~= "" then HttpService:JSONDecode(raw) else {}
		local muts = data.muts and data.muts.reaper or {}
		local xp = data.xp and data.xp.reaper or 0
		local resolved = Castes.resolve(def, muts, Castes.rankOf(xp))
		return resolved.has
	end)
	if ok and type(has) == "function" then
		return has
	end
	return function()
		return false
	end
end

-- Velocidad temporal de la dueña: se engancha una vez a Abilities.speedBoost (encima de lo que haya)
local boostUntil, boostMult = 0, 1
local wrapped = false
local function speedFor(mult: number, seconds: number)
	if not wrapped then
		wrapped = true
		local before = Abilities.speedBoost
		Abilities.speedBoost = function(): number
			local value = before()
			if os.clock() < boostUntil then
				value *= boostMult
			end
			return value
		end
	end
	boostMult = mult
	boostUntil = os.clock() + seconds
end

----------------------------------------------------------------------------------------------------
-- Formas

-- Media luna de piezas finas: arco de `angle` grados centrado en `dir`, a `radius` de `o`
local function crescent(o: Vector3, dir: Vector3, angle: number, radius: number, color: Color3, width: number, life: number, push: number?)
	local count = math.clamp(math.floor(angle / 12), 4, 14)
	local parts = {}
	for i = 1, count do
		local a0 = -angle / 2 + angle * (i - 1) / count
		local a1 = -angle / 2 + angle * i / count
		local p0 = o + turn(dir, a0) * radius
		local p1 = o + turn(dir, a1) * radius
		local mid = (p0 + p1) / 2
		-- Más gruesa en el centro, afilada en las puntas
		local k = 1 - math.abs((i - 0.5) / count - 0.5) * 1.6
		local seg = part({
			Name = "Slash",
			Color = color,
			Size = Vector3.new(width * math.max(k, 0.25), 0.22, (p1 - p0).Magnitude + 0.15),
			CFrame = CFrame.lookAt(mid, p1),
		})
		local out = flatUnit(mid - o, dir)
		tween(seg, life, { Transparency = 1, CFrame = seg.CFrame + out * (push or 1.5) })
		Debris:AddItem(seg, life + 0.05)
		table.insert(parts, seg)
	end
	return parts
end

-- Grietas que salen de un punto en el suelo
local function cracks(at: Vector3, radius: number, life: number)
	local ground = Vector3.new(at.X, GROUND, at.Z)
	for i = 1, 7 do
		local dir = turn(Vector3.zAxis, i * 360 / 7 + rng:NextNumber(-15, 15))
		local length = radius * rng:NextNumber(0.5, 0.95)
		local crack = part({
			Name = "Crack",
			Material = Enum.Material.SmoothPlastic,
			Color = INK,
			Size = Vector3.new(0.35, 0.1, length),
			CFrame = CFrame.lookAt(ground + dir * length / 2, ground + dir * length),
		})
		task.delay(life * 0.6, function()
			fadeOut(crack, life * 0.4)
		end)
	end
end

-- Mandíbulas sueltas (bumerán): disco de hueso con filo rojo que gira
local function jawsDisc(): Model
	local model = Instance.new("Model")
	model.Name = "ReaperBoomerang"
	local core = part({
		Name = "Core",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = BONE,
		Size = Vector3.new(0.35, 2.6, 2.6),
	}, model)
	model.PrimaryPart = core
	-- Dos ganchos curvos en el plano del disco (perpendicular a su eje X)
	local function at(angle: number, r: number): Vector3
		return Vector3.new(0, math.cos(angle) * r, math.sin(angle) * r)
	end
	for _, start in { 0, math.pi } do
		for i = 1, 4 do
			local p0 = at(start + (i - 1) * 0.45, 1.2 + (i - 1) * 0.28)
			local p1 = at(start + i * 0.45, 1.2 + i * 0.28)
			part({
				Name = "Blade",
				Color = if i == 4 then BLOOD else BONE,
				Material = if i == 4 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				Size = Vector3.new(0.2, 0.55 - i * 0.08, (p1 - p0).Magnitude + 0.2),
				CFrame = CFrame.lookAt((p0 + p1) / 2, p1, Vector3.xAxis),
			}, model)
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.4, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.4, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(BLOOD, BONE)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.25
	trail.LightEmission = 0.6
	trail.Parent = core
	model.Parent = Fx.folder()
	return model
end

----------------------------------------------------------------------------------------------------
-- Movimiento de la dueña (Guillotina)

local moving = false

local function leap(to: Vector3, duration: number, height: number): boolean
	local root = rootOf(player)
	if not root or moving then
		return false
	end
	local from = root.Position
	local target = Vector3.new(to.X, from.Y, to.Z)
	local facing = flatUnit(target - from, root.CFrame.LookVector)
	local rotation = CFrame.lookAt(Vector3.zero, facing).Rotation
	moving = true
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local now = rootOf(player)
		local t = math.min((os.clock() - started) / duration, 1)
		if not now then
			connection:Disconnect()
			moving = false
			return
		end
		-- Sube rápido, cuelga un instante y cae en picado: la hoja que baja
		local up = math.sin(math.min(t * 1.25, 1) * math.pi) * height
		now.CFrame = CFrame.new(from:Lerp(target, t * t * (3 - 2 * t)) + UP * up) * rotation * CFrame.Angles(-t * math.pi * 2, 0, 0)
		now.AssemblyLinearVelocity = Vector3.zero
		if t >= 1 then
			connection:Disconnect()
			now.CFrame = CFrame.new(target) * rotation
			moving = false
		end
	end)
	return true
end

local cast = {}

function cast.reaper1(aim: Vector3, _aimFood: Model?, def: any): boolean
	local has = myFlags()
	if has("boomerang") then
		return true -- las mandíbulas vuelan solas; la dueña se queda
	end
	local root = rootOf(player)
	if not root then
		return true
	end
	local range = (type(def) == "table" and tonumber(def.range)) or 28
	local offset = (aim - root.Position) * FLAT
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	local land = (type(def) == "table" and type(def.params) == "table" and tonumber(def.params.land)) or 0.45
	leap(root.Position + offset, land, 7)
	return true
end

----------------------------------------------------------------------------------------------------
-- Efectos

local fx = {}

-- Tajo de la pasiva: media luna delante (o estocada); el pesado, grande y con onomatopeya
function fx.passive(caster: Player, p: any, mine: boolean)
	local o = vec(p.o)
	if not o or (not mine and not seen(o)) then
		return
	end
	local dir = flatUnit(vec(p.dir, Vector3.zAxis) :: Vector3, Vector3.zAxis)
	local r = tonumber(p.r) or 10
	local angle = tonumber(p.ang) or 70
	local heavy = p.heavy == true
	local pts = list(p.pts)
	local at = o + UP * 0.6
	if p.thrust then
		local tip = at + dir * r
		local spike = part({
			Name = "Thrust",
			Color = if heavy then BLOOD else BONE,
			Size = Vector3.new(if heavy then 0.8 else 0.45, if heavy then 0.8 else 0.45, r),
			CFrame = CFrame.lookAt(at + dir * r / 2, tip),
		})
		tween(spike, 0.18, { Size = Vector3.new(0.05, 0.05, r * 1.15), Transparency = 1 })
		Debris:AddItem(spike, 0.2)
		Fx.burst(tip, { color = BONE, count = if heavy then 10 else 4, speed = 12, size = 0.4, life = 0.25 })
	else
		crescent(at, dir, angle, r * 0.8, if heavy then BLOOD else BONE, if heavy then 1.1 else 0.55, if heavy then 0.25 else 0.15, if heavy then 3 else 1.5)
		if heavy then
			crescent(at, dir, angle * 0.9, r * 0.6, BONE, 0.4, 0.2, 2)
		end
	end
	for _, pt in pts do
		Fx.burst(pt, { color = if heavy then BLOOD else BONE, count = if heavy then 8 else 4, speed = 10, size = 0.4, life = 0.25 })
	end
	react(pts, o, if heavy then 0.32 else 0.18)
	if heavy then
		word(at + dir * r * 0.6 + UP * 3, if p.thrust then "¡TSHK!" else "¡SLASH!", { color = BLOOD, size = 1.1 })
		Fx.light(at + dir * 3, { color = BLOOD, range = 12, life = 0.15 })
		Fx.sound("slash", o, 0.8)
		if mine then
			Fx.shake(0.22, 0.15)
		end
	elseif mine then
		Fx.sound("slash", o, rng:NextNumber(1.3, 1.6))
	end
end

-- Guillotina: marca en el suelo (o bumerán que sale)
function fx.reaper1(caster: Player, p: any, mine: boolean)
	if p.boom then
		local a, b = vec(p.a), vec(p.b)
		local travel = tonumber(p.time) or 0.5
		if not a or not b or (not mine and not seen(a)) then
			return
		end
		local model = jawsDisc()
		local started = os.clock()
		Fx.sound("whoosh", a, 1.2)
		word(a + UP * 3, "¡FWISH!", { color = BONE, size = 0.9, life = 0.5 })
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			if t >= travel * 2 or not model.Parent then
				connection:Disconnect()
				model:Destroy()
				return
			end
			local where
			if t < travel then
				local k = t / travel
				where = a:Lerp(b, 1 - (1 - k) * (1 - k))
			else
				local root = rootOf(caster)
				local back = if root then root.Position + UP else a
				local k = (t - travel) / travel
				where = b:Lerp(back, k * k)
			end
			model:PivotTo(CFrame.new(where) * CFrame.Angles(0, t * 22, 0) * CFrame.Angles(0, 0, math.pi / 2))
		end)
		return
	end

	local a, b = vec(p.a), vec(p.b)
	local land = tonumber(p.land) or 0.45
	local r = tonumber(p.r) or 12
	if not b or (not mine and not seen(b)) then
		return
	end
	-- Anticipación: un círculo rojo que se cierra donde vas a caer
	local ground = Vector3.new(b.X, GROUND, b.Z)
	local marker = part({
		Name = "GuillotineMark",
		Shape = Enum.PartType.Cylinder,
		Color = BLOOD,
		Transparency = 0.55,
		Size = Vector3.new(0.12, r * 2, r * 2),
		CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2),
	})
	tween(marker, land, { Size = Vector3.new(0.12, 3, 3), Transparency = 0.15 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(marker, land + 0.05)
	local character = caster.Character
	if character then
		Fx.ghosts(character, land, { color = BLOOD })
	end
	Fx.sound("whoosh", a or b, 0.9)
end

function fx.reaper1_hit(caster: Player, p: any, mine: boolean)
	local at = vec(p.p)
	if not at or (not mine and not seen(at)) then
		return
	end
	local r = tonumber(p.r) or 12
	local pts, core = list(p.pts), list(p.core)
	ring(at, r, { color = BLOOD, life = 0.45, thickness = 2 })
	ring(at, r * 0.45, { color = BONE, life = 0.3, thickness = 1.2 })
	Fx.burst(at, { color = BONE, count = 28, speed = 26, size = 0.7, life = 0.45, up = 10 })
	Fx.burst(at, { color = BLOOD, count = 16, speed = 18, size = 0.6, life = 0.4, up = 6 })
	Fx.light(at, { color = BLOOD, range = r * 2, life = 0.25 })
	word(at + UP * 5, "¡CHOP!", { color = BLOOD, size = 1.5 })
	crescent(at, Vector3.zAxis, 360, r * 0.7, BONE, 0.7, 0.3, 4)
	cracks(at, r, 1.2)
	for _, pt in core do
		Fx.burst(pt, { color = BLOOD, count = 12, speed = 14, size = 0.6, life = 0.35, up = 6 })
	end
	react(pts, at, 0.4)
	loot(caster, pts, BONE)
	Fx.sound("thud", at, 0.7)
	Fx.sound("slash", at, 0.7)
	if mine then
		Fx.shake(0.55, 0.35)
		Fx.flash(BLOOD, 0.2, 0.12)
	end
end

function fx.reaper1_shock(caster: Player, p: any, mine: boolean)
	local at = vec(p.p)
	if not at or (not mine and not seen(at)) then
		return
	end
	local r = tonumber(p.r) or 16
	local pts = list(p.pts)
	ring(at, r, { color = BONE, life = 0.4, thickness = 1.2 })
	Fx.burst(at, { color = Color3.fromRGB(190, 150, 110), count = 14, speed = 16, size = 0.6, life = 0.4, up = 3 })
	word(at + UP * 3, "¡TUM!", { color = BONE, size = 0.9, life = 0.5 })
	react(pts, at, 0.25)
	loot(caster, pts, BONE)
	Fx.sound("thud", at, 1)
	if mine then
		Fx.shake(0.22, 0.2)
	end
end

function fx.reaper1_boom(caster: Player, p: any, mine: boolean)
	local pts = list(p.pts)
	local at = vec(p.p)
	if at and (mine or seen(at)) then
		for _, pt in pts do
			Fx.burst(pt, { color = BLOOD, count = 8, speed = 14, size = 0.5, life = 0.3 })
			crescent(pt, turn(Vector3.zAxis, rng:NextNumber(0, 360)), 120, 1.8, BONE, 0.4, 0.15)
		end
		if not p.back then
			word(at + UP * 3, "¡SHING!", { color = BONE, size = 1 })
		end
		react(pts, at, 0.28)
		loot(caster, pts, BONE)
		Fx.sound("slash", at, if p.back then 1.2 else 1)
		if mine and #pts > 0 then
			Fx.shake(0.2, 0.15)
		end
	end
end

-- Torbellino: tres guadañas girando alrededor (o un tornado que avanza)
local spins: { [Player]: { model: Model, endAt: number } } = {}

local function spinBlades(r: number, dance: boolean): Model
	local model = Instance.new("Model")
	model.Name = "ReaperSpin"
	local hub = part({ Name = "Hub", Transparency = 1, Size = Vector3.one * 0.2 }, model)
	model.PrimaryPart = hub
	for k = 0, 2 do
		local base = k * 120
		for i = 1, 5 do
			local a0, a1 = math.rad(base + (i - 1) * 14), math.rad(base + i * 14)
			local p0 = Vector3.new(math.cos(a0), 0, math.sin(a0)) * r * 0.85
			local p1 = Vector3.new(math.cos(a1), 0, math.sin(a1)) * r * 0.85
			part({
				Name = "Blade",
				Color = if i >= 4 then BLOOD else BONE,
				Size = Vector3.new(0.75 - i * 0.1, 0.25, (p1 - p0).Magnitude + 0.2),
				CFrame = CFrame.lookAt((p0 + p1) / 2, p1),
			}, model)
		end
	end
	local disc = part({
		Name = "Reach",
		Shape = Enum.PartType.Cylinder,
		Color = if dance then BLOOD else RED,
		Transparency = 0.85,
		Size = Vector3.new(0.1, r * 2, r * 2),
		CFrame = CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.pi / 2),
	}, model)
	disc.Name = "Reach"
	model.Parent = Fx.folder()
	return model
end

local function tornadoModel(r: number): Model
	local model = Instance.new("Model")
	model.Name = "ReaperTornado"
	local hub = part({ Name = "Hub", Transparency = 1, Size = Vector3.one * 0.2 }, model)
	model.PrimaryPart = hub
	for i = 1, 6 do
		local d = r * 2 * (0.35 + i * 0.11)
		part({
			Name = "Swirl",
			Shape = Enum.PartType.Cylinder,
			Color = if i % 2 == 0 then BLOOD else BONE,
			Transparency = 0.45 + i * 0.05,
			Size = Vector3.new(0.5, d, d),
			CFrame = CFrame.new(0, -0.5 + i * 1.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
		}, model)
	end
	model.Parent = Fx.folder()
	return model
end

function fx.reaper2(caster: Player, p: any, mine: boolean)
	local life = tonumber(p.life) or 3.5
	local r = tonumber(p.r) or 10
	if p.mode == "tornado" then
		local a, b = vec(p.a), vec(p.b)
		if not a or not b or (not mine and not seen(a)) then
			return
		end
		local model = tornadoModel(r)
		local started = os.clock()
		word(a + UP * 4, "¡FWOOOSH!", { color = BONE, size = 1.2 })
		Fx.sound("whoosh", a, 0.7)
		local nextWhoosh = 0.5
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			if t >= life or not model.Parent then
				connection:Disconnect()
				Fx.burst(model:GetPivot().Position, { color = BONE, count = 14, speed = 12, size = 0.5, life = 0.35 })
				model:Destroy()
				return
			end
			local here = a:Lerp(b, t / life)
			model:PivotTo(CFrame.new(here.X, GROUND + 0.6, here.Z) * CFrame.Angles(0, t * 16, 0))
			if t > nextWhoosh then
				nextWhoosh += 0.6
				Fx.sound("whoosh", model:GetPivot().Position, rng:NextNumber(0.8, 1.1))
			end
		end)
		return
	end

	local root = rootOf(caster)
	if not root or (not mine and not seen(root.Position)) then
		if mine then
			speedFor(tonumber(p.speed) or 1.3, life)
		end
		return
	end
	local old = spins[caster]
	if old then
		old.model:Destroy()
	end
	local model = spinBlades(r, p.dance == true)
	local entry = { model = model, endAt = os.clock() + life }
	spins[caster] = entry
	word(root.Position + UP * 4, "¡WHIRR!", { color = BONE, size = 1.1 })
	ring(root.Position, r, { color = BLOOD, life = 0.3, thickness = 1 })
	if mine then
		speedFor(tonumber(p.speed) or 1.3, life)
		Fx.shake(0.18, 0.2)
	end
	local started = os.clock()
	local nextWhoosh = 0
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local here = rootOf(caster)
		if not model.Parent or not here or now >= entry.endAt + 0.3 then
			connection:Disconnect()
			if model.Parent then
				for _, child in model:GetChildren() do
					if child:IsA("BasePart") then
						tween(child, 0.2, { Transparency = 1 })
					end
				end
				Debris:AddItem(model, 0.25)
			end
			if spins[caster] == entry then
				spins[caster] = nil
			end
			return
		end
		local t = now - started
		local speed = if p.dance then 24 else 15
		model:PivotTo(CFrame.new(here.Position + UP * 0.2) * CFrame.Angles(0, t * speed, 0))
		local reach = model:FindFirstChild("Reach")
		if reach and reach:IsA("BasePart") then
			reach.CFrame = CFrame.new(here.Position.X, GROUND, here.Position.Z) * CFrame.Angles(0, 0, math.pi / 2)
		end
		if now > started + nextWhoosh then
			nextWhoosh += 0.45
			Fx.sound("whoosh", here.Position, rng:NextNumber(1.1, 1.4))
		end
	end)
end

-- Danza de cuchillas: cada comida terminada alarga el giro
function fx.reaper2_ext(caster: Player, p: any, mine: boolean)
	local entry = spins[caster]
	local add = tonumber(p.add) or 0
	if entry then
		entry.endAt += add
		local root = rootOf(caster)
		if root then
			word(root.Position + UP * 5, "¡OLÉ!", { color = BLOOD, size = 0.8, life = 0.45 })
		end
	end
	if mine then
		boostUntil += add
	end
end

function fx.reaper2_end(caster: Player, _p: any, mine: boolean)
	local entry = spins[caster]
	if entry then
		entry.endAt = math.min(entry.endAt, os.clock())
	end
	if mine then
		boostUntil = math.min(boostUntil, os.clock())
	end
end

function fx.reaper2_tick(caster: Player, p: any, mine: boolean)
	local pts = list(p.pts)
	local c = vec(p.c)
	if #pts == 0 or (not mine and not seen(pts[1])) then
		return
	end
	for _, pt in pts do
		Fx.burst(pt, { color = if rng:NextNumber() < 0.5 then BLOOD else BONE, count = 5, speed = 12, size = 0.4, life = 0.25 })
	end
	if rng:NextNumber() < 0.3 then
		word(pts[1] + UP * 2.5, "¡ZAS!", { color = BONE, size = 0.7, life = 0.4 })
	end
	react(pts, c, 0.2)
	loot(caster, pts, BONE)
	if mine then
		Fx.sound("slash", pts[1], rng:NextNumber(1.2, 1.5))
	end
end

-- Gran Siega: una (o dos) medias lunas gigantes que avanzan, o un anillo que crece; deja surco
local function bigCrescent(width: number): Model
	local model = Instance.new("Model")
	model.Name = "ReaperSiege"
	local hub = part({ Name = "Hub", Transparency = 1, Size = Vector3.one * 0.2 }, model)
	model.PrimaryPart = hub
	local arc = 110
	local radius = width / 2 / math.sin(math.rad(arc / 2))
	local count = 12
	for i = 1, count do
		local a0 = math.rad(-arc / 2 + arc * (i - 1) / count)
		local a1 = math.rad(-arc / 2 + arc * i / count)
		-- El arco abomba hacia delante (-Z del modelo)
		local p0 = Vector3.new(math.sin(a0) * radius, 0, -math.cos(a0) * radius + radius * 0.75)
		local p1 = Vector3.new(math.sin(a1) * radius, 0, -math.cos(a1) * radius + radius * 0.75)
		local k = 1 - math.abs((i - 0.5) / count - 0.5) * 1.7
		local mid = (p0 + p1) / 2
		part({
			Name = "Edge",
			Color = BLOOD,
			Size = Vector3.new(0.5, 3.2 * math.max(k, 0.3), (p1 - p0).Magnitude + 0.3),
			CFrame = CFrame.lookAt(mid, p1) + Vector3.new(0, 2, 0),
		}, model)
		part({
			Name = "Bone",
			Material = Enum.Material.SmoothPlastic,
			Color = BONE,
			Size = Vector3.new(2.2 * math.max(k, 0.25), 0.6, (p1 - p0).Magnitude + 0.3),
			CFrame = CFrame.lookAt(mid + Vector3.new(0, 0, 1.2), p1 + Vector3.new(0, 0, 1.2)) + Vector3.new(0, 0.4, 0),
		}, model)
	end
	local light = Instance.new("PointLight")
	light.Color = BLOOD
	light.Range = 30
	light.Brightness = 3
	light.Shadows = false
	light.Parent = hub
	model.Parent = Fx.folder()
	return model
end

local function scar(a: Vector3, b: Vector3, width: number, life: number)
	local from = Vector3.new(a.X, GROUND, a.Z)
	local to = Vector3.new(b.X, GROUND, b.Z)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local groove = part({
		Name = "Scar",
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(70, 20, 24),
		Transparency = 0.15,
		Size = Vector3.new(width * 0.18, 0.12, length),
		CFrame = CFrame.lookAt((from + to) / 2, to),
	})
	local glow = part({
		Name = "ScarGlow",
		Color = BLOOD,
		Transparency = 0.4,
		Size = Vector3.new(width * 0.06, 0.14, length),
		CFrame = groove.CFrame + UP * 0.02,
	})
	task.delay(life, function()
		fadeOut(groove, 0.8)
		fadeOut(glow, 0.8)
	end)
end

function fx.reaper3(caster: Player, p: any, mine: boolean)
	local a = vec(p.a)
	if not a or (not mine and not seen(a)) then
		return
	end
	local travel = tonumber(p.time) or 1.1
	local scarLife = tonumber(p.scar) or 5
	local width = tonumber(p.w) or 26

	-- Anticipación: la dueña se agacha (destello) y un relámpago rojo en el suelo
	Fx.light(a, { color = BLOOD, range = 20, life = 0.25 })
	Fx.burst(a, { color = BLOOD, count = 12, speed = 3, size = 0.6, life = 0.2 })
	word(a + UP * 6, "¡SHHRAAK!", { color = BLOOD, size = 1.7 })
	Fx.sound("slash", a, 0.5)
	if mine then
		Fx.shake(0.6, 0.5)
		Fx.flash(BLOOD, 0.25, 0.15)
	end

	if p.mode == "ring" then
		local r = tonumber(p.r) or 40
		ring(a, r, { color = BLOOD, life = travel, thickness = 3 })
		ring(a, r * 0.95, { color = BONE, life = travel * 0.9, thickness = 1.5 })
		local blades = {}
		for i = 1, 16 do
			local dir = turn(Vector3.zAxis, i * 22.5)
			local blade = part({
				Name = "RingBlade",
				Color = if i % 2 == 0 then BLOOD else BONE,
				Size = Vector3.new(0.5, 2.4, 4),
				CFrame = CFrame.lookAt(a, a + dir:Cross(UP)) + dir * 2,
			})
			tween(blade, travel, { CFrame = blade.CFrame + dir * (r - 2) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			table.insert(blades, blade)
		end
		task.delay(travel, function()
			for _, blade in blades do
				fadeOut(blade, 0.2)
			end
		end)
		-- Surco circular
		for i = 1, 16 do
			local a0 = a + turn(Vector3.zAxis, i * 22.5) * r * 0.97
			local a1 = a + turn(Vector3.zAxis, (i + 1) * 22.5) * r * 0.97
			scar(a0, a1, 10, scarLife)
		end
		return
	end

	local length = tonumber(p.len) or 90
	local dirs = { flatUnit(vec(p.d1, Vector3.zAxis) :: Vector3, Vector3.zAxis) }
	if p.mode == "cross" then
		table.insert(dirs, flatUnit(vec(p.d2, Vector3.zAxis) :: Vector3, Vector3.zAxis))
	end
	for _, dir in dirs do
		local b = a + dir * length
		local model = bigCrescent(width)
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - started) / travel
			if t >= 1 or not model.Parent then
				connection:Disconnect()
				for _, child in model:GetChildren() do
					if child:IsA("BasePart") then
						tween(child, 0.25, { Transparency = 1 })
					end
				end
				Debris:AddItem(model, 0.3)
				return
			end
			local here = a:Lerp(b, t)
			here = Vector3.new(here.X, GROUND, here.Z)
			model:PivotTo(CFrame.lookAt(here, here + dir))
		end)
		Fx.wave(a, b, width, { color = BLOOD, time = travel, height = 2 })
		task.delay(travel * 0.15, function()
			scar(a, b, width, scarLife)
		end)
	end
end

function fx.reaper3_hit(caster: Player, p: any, mine: boolean)
	local pts = list(p.pts)
	if #pts == 0 or (not mine and not seen(pts[1])) then
		return
	end
	for _, pt in pts do
		Fx.burst(pt, { color = BLOOD, count = 12, speed = 18, size = 0.6, life = 0.35, up = 6 })
		Fx.burst(pt, { color = BONE, count = 6, speed = 12, size = 0.4, life = 0.3 })
	end
	Fx.light(pts[1], { color = BLOOD, range = 16, life = 0.15 })
	react(pts, nil, 0.4)
	loot(caster, pts, BONE)
	Fx.sound("slash", pts[1], rng:NextNumber(0.8, 1))
	if mine then
		Fx.shake(0.18, 0.12)
	end
end

----------------------------------------------------------------------------------------------------
-- Aura: mandíbulas de guadaña enormes, de hueso con filo rojo (dorado con Maestría)

local function weld(host: BasePart, folder: Instance, props: { [string]: any }, offset: CFrame): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	if props.Shape then
		p.Shape = props.Shape -- antes que Size: una bola fuerza tamaño uniforme
	end
	for key, value in props do
		(p :: any)[key] = value
	end
	p.CFrame = host.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = host
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = folder
	return p
end

local function aura(character: Model, rank: number, mastered: boolean): () -> ()
	local folder = Instance.new("Folder")
	folder.Name = "ReaperAura"
	folder.Parent = Fx.folder()
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return function()
			folder:Destroy()
		end
	end
	local scale = character:GetScale()
	local grow = 1 + (math.clamp(rank, 1, 10) - 1) * 0.045
	local edgeColor = if mastered then GOLD else BLOOD

	for _, s in { -1, 1 } do
		local R = 1.5 * grow
		local center = Vector3.new(s * (1.0 - R), -0.35, -0.9)
		local count = 6
		for i = 1, count do
			local a0 = math.rad(72 * (i - 1) / count)
			local a1 = math.rad(72 * i / count)
			local p0 = (center + Vector3.new(s * R * math.cos(a0), 0, -R * math.sin(a0))) * scale
			local p1 = (center + Vector3.new(s * R * math.cos(a1), 0, -R * math.sin(a1))) * scale
			local mid = (p0 + p1) / 2
			local width = (0.6 - 0.07 * i) * scale * grow
			local length = (p1 - p0).Magnitude + 0.08 * scale
			local frame = CFrame.lookAt(mid, p1)
			weld(head, folder, {
				Name = "ScytheJaw",
				Color = BONE,
				Size = Vector3.new(width, 0.2 * scale, length),
			}, frame)
			-- Filo por dentro de la curva
			local inward = ((center * scale - mid) * FLAT)
			inward = if inward.Magnitude > 0.01 then inward.Unit else Vector3.xAxis
			weld(head, folder, {
				Name = "ScytheEdge",
				Material = Enum.Material.Neon,
				Color = edgeColor,
				Size = Vector3.new(0.09 * scale, 0.24 * scale, length),
			}, CFrame.lookAt(mid + inward * width / 2, p1 + inward * width / 2))
		end
	end

	local glow = Instance.new("PointLight")
	glow.Color = edgeColor
	glow.Range = 4 + rank * 0.4
	glow.Brightness = 0.9
	glow.Shadows = false
	local holder = weld(head, folder, { Name = "ReaperGlow", Transparency = 1, Size = Vector3.one * 0.2 }, CFrame.new(0, -0.3 * scale, -1.8 * scale))
	glow.Parent = holder
	if mastered or rank >= 5 then
		local wisps = Instance.new("ParticleEmitter")
		wisps.Color = ColorSequence.new(edgeColor, INK)
		wisps.LightEmission = 0.4
		wisps.Size = NumberSequence.new(0.25 * scale, 0)
		wisps.Transparency = NumberSequence.new(0.3, 1)
		wisps.Lifetime = NumberRange.new(0.3, 0.6)
		wisps.Speed = NumberRange.new(0.5, 1.5)
		wisps.Rate = 3 + rank
		wisps.Parent = holder
	end

	local gone = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			folder:Destroy()
		end
	end)
	return function()
		gone:Disconnect()
		folder:Destroy()
	end
end

----------------------------------------------------------------------------------------------------
-- Emblema: media luna de hueso (guadaña) sobre un disco rojo

local function emblem(parent: GuiObject, color: Color3)
	local function circle(size: number, x: number, y: number, fill: Color3, stroke: boolean, holder: GuiObject): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromScale(size, size)
		f.Position = UDim2.fromScale(x, y)
		f.BackgroundColor3 = fill
		f.BorderSizePixel = 0
		f.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		if stroke then
			local s = Instance.new("UIStroke")
			s.Color = INK
			s.Thickness = 3
			s.Parent = f
		end
		return f
	end
	local disc = circle(0.86, 0.5, 0.5, color, true, parent)
	disc.Name = "ReaperEmblem"
	disc.ClipsDescendants = false
	-- Mango de la guadaña
	local handle = Instance.new("Frame")
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Size = UDim2.fromScale(0.1, 0.62)
	handle.Position = UDim2.fromScale(0.42, 0.58)
	handle.Rotation = -32
	handle.BackgroundColor3 = BONE
	handle.BorderSizePixel = 0
	handle.Parent = disc
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(1, 0)
	hc.Parent = handle
	local hs = Instance.new("UIStroke")
	hs.Color = INK
	hs.Thickness = 2
	hs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hs.Parent = handle
	-- Hoja en media luna: un círculo de hueso tapado en parte por otro del color del disco
	circle(0.58, 0.5, 0.38, BONE, true, disc)
	circle(0.52, 0.58, 0.48, color, false, disc)
end

return {
	fx = fx,
	cast = cast,
	aura = aura,
	emblem = emblem,
}
