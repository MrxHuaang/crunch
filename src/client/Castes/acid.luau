-- Ácida (cliente): goteo de corrosión, escupitajos en arco, charcos que burbujean, la nube cáustica,
-- el Diluvio con su lluvia, el aura de glándula que gotea y el emblema.
-- El servidor manda en cada efecto los puntos exactos que golpeó; aquí solo se pinta.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Fx = require(script.Parent.Parent.CasteFx)
local OldFx = require(script.Parent.Parent.Fx)
local Config = require(ReplicatedStorage.Shared.Config)

local rng = Random.new()
local UP = Vector3.new(0, 1, 0)
local INK = Color3.fromRGB(20, 16, 16)
local LIME = Color3.fromRGB(150, 230, 30)
local TOXIC = Color3.fromRGB(200, 255, 80)
local PURPLE = Color3.fromRGB(140, 60, 200)
local GOLD = Color3.fromRGB(255, 196, 40)
local SEEN = 260
local GROUND = Config.GroundY + 0.06

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
			pcall(OldFx.squash, food, amount or 0.16, from)
		end
	end
end

local function loot(caster: Player, pts: { Vector3 }, color: Color3?)
	if #pts == 0 then
		return
	end
	local hill = Fx.hillOf(caster)
	if hill then
		Fx.orbs(pts, hill, { color = color or LIME })
	end
end

local function rootOf(who: Player): BasePart?
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Gotas que caen de un punto (o de una pieza), verdes y moradas
local function dripper(parent: Instance, rate: number, size: number): ParticleEmitter
	local drops = Instance.new("ParticleEmitter")
	drops.Name = "AcidDrip"
	drops.Color = ColorSequence.new(TOXIC, PURPLE)
	drops.LightEmission = 0.5
	drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.4) })
	drops.Transparency = NumberSequence.new(0, 0.3)
	drops.Lifetime = NumberRange.new(0.4, 0.7)
	drops.Speed = NumberRange.new(0.5, 2)
	drops.SpreadAngle = Vector2.new(25, 25)
	drops.EmissionDirection = Enum.NormalId.Bottom
	drops.Acceleration = Vector3.new(0, -30, 0)
	drops.Rate = rate
	drops.Parent = parent
	return drops
end

-- Humo tóxico que sube
local function fumes(parent: Instance, rate: number, size: number): ParticleEmitter
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "AcidFumes"
	smoke.Color = ColorSequence.new(LIME, PURPLE)
	smoke.LightEmission = 0.3
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.4), NumberSequenceKeypoint.new(1, size) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.6, 1.1)
	smoke.Speed = NumberRange.new(2, 4)
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Rate = rate
	smoke.Parent = parent
	return smoke
end

-- Corrosión pegada a una comida: gotea y echa humo `life` segundos
local function corrodeAt(pos: Vector3, life: number, strong: boolean)
	local holder = part({ Name = "Corrode", Transparency = 1, Size = Vector3.new(1.5, 0.2, 1.5), CFrame = CFrame.new(pos + UP * 0.8) })
	dripper(holder, if strong then 18 else 10, 0.3)
	fumes(holder, if strong then 8 else 4, 1.2)
	task.delay(life, function()
		for _, child in holder:GetChildren() do
			if child:IsA("ParticleEmitter") then
				child.Enabled = false
			end
		end
		Debris:AddItem(holder, 1.2)
	end)
end

-- Burbuja que se hincha y revienta
local function bubble(pos: Vector3, size: number, grow: number, color: Color3?)
	local ball = part({
		Name = "AcidBubble",
		Shape = Enum.PartType.Ball,
		Color = color or TOXIC,
		Transparency = 0.35,
		Size = Vector3.one * size * 0.3,
		CFrame = CFrame.new(pos),
	})
	tween(ball, grow, { Size = Vector3.one * size }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(grow, function()
		if ball.Parent then
			Fx.burst(ball.Position, { color = color or TOXIC, count = 8, speed = 10, size = 0.4, life = 0.3, up = 4 })
			ball:Destroy()
		end
	end)
end

----------------------------------------------------------------------------------------------------
-- Efectos

local fx = {}

-- Corrosión: la comida mordida gotea (o se hincha, con Quemadura)
function fx.passive(_caster: Player, p: any, mine: boolean)
	local pos = vec(p.p)
	if not pos or (not mine and not seen(pos)) then
		return
	end
	local life = tonumber(p.life) or 3
	if p.burst then
		bubble(pos + UP * 0.6, 2.4, life, TOXIC)
		Fx.sound("pop", pos, 0.7)
	else
		corrodeAt(pos, life, false)
		if mine then
			Fx.sound("splash", pos, rng:NextNumber(1.5, 1.8))
		end
	end
end

-- Ácido contagioso: salta a otra comida
function fx.acid_spread(_caster: Player, p: any, mine: boolean)
	local a, b = vec(p.a), vec(p.b)
	if not a or not b or (not mine and not seen(a)) then
		return
	end
	local life = tonumber(p.life) or 2
	Fx.lob(a, b, {
		color = TOXIC,
		size = 0.6,
		time = 0.3,
		height = 3,
		land = function()
			corrodeAt(b, life, true)
			Fx.burst(b, { color = LIME, count = 6, speed = 8, size = 0.35, life = 0.3 })
		end,
	})
end

-- Revientón: Quemadura (pasiva) o charco volátil
function fx.acid_pop(caster: Player, p: any, mine: boolean)
	local at = vec(p.p)
	if not at or (not mine and not seen(at)) then
		return
	end
	local r = tonumber(p.r) or 6
	local pts = list(p.pts)
	local small = p.small == true
	ring(at, r, { color = LIME, life = 0.35, thickness = if small then 0.6 else 1.2 })
	Fx.burst(at, { color = TOXIC, count = if small then 10 else 20, speed = if small then 12 else 18, size = 0.5, life = 0.35, up = 6 })
	Fx.burst(at, { color = PURPLE, count = if small then 4 else 10, speed = 10, size = 0.45, life = 0.35, up = 4 })
	word(at + UP * 3, if small then "¡PLOP!" else "¡BLOP!", { color = TOXIC, size = if small then 0.8 else 1.1, life = 0.5 })
	react(pts, at, if small then 0.18 else 0.26)
	if not small then
		loot(caster, pts, LIME) -- lo de la pasiva va a la carga, no vuela
	end
	Fx.sound("pop", at, if small then 1.2 else 0.8)
	if mine and not small then
		Fx.shake(0.15, 0.15)
	end
end

-- Mordisco de charco o nube: burbujitas y botín
function fx.acid_tick(caster: Player, p: any, mine: boolean)
	local pts = list(p.pts)
	if #pts == 0 or (not mine and not seen(pts[1])) then
		return
	end
	for i, pt in pts do
		if i > 10 then
			break
		end
		Fx.burst(pt, { color = if i % 2 == 0 then PURPLE else TOXIC, count = 4, speed = 5, size = 0.35, life = 0.35, up = 5 })
	end
	react(pts, vec(p.c), 0.12)
	loot(caster, pts, LIME)
	if mine then
		Fx.sound("splash", pts[1], rng:NextNumber(1.4, 1.7))
	end
end

-- Escupitajo: se hinchan los carrillos, sale la bola en arco y estalla en charco
local function landPuddle(at: Vector3, r: number, life: number, geyser: boolean, mine: boolean)
	local ground = Vector3.new(at.X, GROUND, at.Z)
	local puddle = Fx.puddle(ground, r, life, { color = LIME })
	if geyser and puddle then
		-- El charco del géiser hierve más fuerte cuanto más se acerca el chorro
		local holder = part({ Name = "GeyserBoil", Transparency = 1, Size = Vector3.new(r, 0.2, r), CFrame = CFrame.new(ground + UP * 0.3) })
		local boil = fumes(holder, 6, 2)
		task.delay(life * 0.6, function()
			boil.Rate = 25
		end)
		Debris:AddItem(holder, life + 0.2)
	end
	ring(ground, r, { color = TOXIC, life = 0.4, thickness = 1.2 })
	Fx.burst(ground + UP, { color = TOXIC, count = 18, speed = 18, size = 0.55, life = 0.4, up = 8 })
	Fx.burst(ground + UP, { color = PURPLE, count = 8, speed = 12, size = 0.45, life = 0.35, up = 6 })
	word(ground + UP * 4, "¡SPLASH!", { color = TOXIC, size = 1.1 })
	Fx.light(ground + UP * 2, { color = LIME, range = r * 1.6, life = 0.25 })
	Fx.sound("splash", ground, 0.9)
	if mine then
		Fx.shake(0.2, 0.18)
	end
end

function fx.acid1(_caster: Player, p: any, mine: boolean)
	local a = vec(p.a)
	local targets = list(p.bs)
	if not a or #targets == 0 or (not mine and not seen(a)) then
		return
	end
	local r = tonumber(p.r) or 11
	local life = tonumber(p.life) or 6
	local flight = tonumber(p.flight) or 0.55
	-- Anticipación: un sorbo hacia dentro y una gárgara
	Fx.burst(a, { color = TOXIC, count = 8, speed = 3, size = 0.4, life = 0.12 })
	Fx.sound("pop", a, 0.6)
	for i, b in targets do
		Fx.lob(a, b, {
			color = TOXIC,
			size = if #targets > 1 then 1.1 else 1.6,
			time = flight,
			height = 6 + (b - a).Magnitude * 0.15,
			land = function()
				landPuddle(b, r, life, p.geyser == true, mine and i == 1)
			end,
		})
	end
end

function fx.acid1_geyser(caster: Player, p: any, mine: boolean)
	local at = vec(p.p)
	if not at or (not mine and not seen(at)) then
		return
	end
	local r = tonumber(p.r) or 11
	local pts = list(p.pts)
	local ground = Vector3.new(at.X, GROUND, at.Z)
	Fx.pillar(ground, { color = TOXIC, height = 18, width = math.max(r * 0.6, 3), life = 0.55 })
	Fx.burst(ground + UP * 2, { color = TOXIC, count = 30, speed = 30, size = 0.7, life = 0.6, up = 22 })
	Fx.burst(ground + UP * 2, { color = PURPLE, count = 12, speed = 18, size = 0.55, life = 0.5, up = 14 })
	ring(ground, r, { color = LIME, life = 0.4, thickness = 1.6 })
	word(ground + UP * 8, "¡FSSSH!", { color = TOXIC, size = 1.5 })
	Fx.light(ground + UP * 4, { color = LIME, range = r * 2.2, life = 0.35 })
	react(pts, ground, 0.35)
	loot(caster, pts, LIME)
	Fx.sound("splash", ground, 0.6)
	if mine then
		Fx.shake(0.38, 0.3)
		Fx.flash(LIME, 0.18, 0.12)
	end
end

-- Estela cáustica: nube que envuelve a la dueña, o aviso de que empieza la estela
function fx.acid2(caster: Player, p: any, mine: boolean)
	local life = tonumber(p.life) or 5
	local root = rootOf(caster)
	if not root or (not mine and not seen(root.Position)) then
		return
	end
	word(root.Position + UP * 4, "¡FSSS!", { color = TOXIC, size = 1 })
	Fx.sound("splash", root.Position, 1.2)
	if not p.cloud then
		-- La estela: gotea de la dueña mientras dura
		local holder = part({ Name = "TrailDrip", Transparency = 1, Size = Vector3.one * 0.3 })
		local drip = dripper(holder, 30, 0.45)
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local here = rootOf(caster)
			if not here or os.clock() - started > life then
				connection:Disconnect()
				drip.Enabled = false
				Debris:AddItem(holder, 1)
				return
			end
			holder.CFrame = here.CFrame * CFrame.new(0, 0, 1.6)
		end)
		return
	end
	local r = tonumber(p.r) or 9
	local model = Instance.new("Model")
	model.Name = "AcidCloud"
	for i = 1, 7 do
		local angle = i / 7 * math.pi * 2
		part({
			Name = "Puff",
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.SmoothPlastic,
			Color = if i % 3 == 0 then PURPLE else LIME,
			Transparency = 0.6,
			Size = Vector3.one * rng:NextNumber(r * 0.5, r * 0.8),
			CFrame = CFrame.new(math.cos(angle) * r * 0.55, rng:NextNumber(-0.5, 1.5), math.sin(angle) * r * 0.55),
		}, model)
	end
	local hub = part({ Name = "Hub", Transparency = 1, Size = Vector3.one * 0.3 }, model)
	fumes(hub, 14, 3)
	model.PrimaryPart = hub
	model.Parent = Fx.folder()
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local here = rootOf(caster)
		if not here or t > life then
			connection:Disconnect()
			for _, child in model:GetDescendants() do
				if child:IsA("BasePart") then
					tween(child, 0.4, { Transparency = 1 })
				elseif child:IsA("ParticleEmitter") then
					child.Enabled = false
				end
			end
			Debris:AddItem(model, 0.5)
			return
		end
		model:PivotTo(CFrame.new(here.Position) * CFrame.Angles(0, t * 1.2, 0))
	end)
end

function fx.acid2_drop(_caster: Player, p: any, mine: boolean)
	local at = vec(p.p)
	if not at or (not mine and not seen(at)) then
		return
	end
	local r = tonumber(p.r) or 4.5
	local life = tonumber(p.life) or 4
	local ground = Vector3.new(at.X, GROUND, at.Z)
	Fx.puddle(ground, r, life, { color = LIME })
	Fx.burst(ground + UP * 0.5, { color = TOXIC, count = 5, speed = 6, size = 0.35, life = 0.25, up = 3 })
end

-- Diluvio fórmico: nubarrón, lluvia y el charco grande debajo
local rains: { [Player]: Model } = {}

function fx.acid3(caster: Player, p: any, mine: boolean)
	local home = vec(p.c)
	if not home or (not mine and not seen(home)) then
		return
	end
	local r = tonumber(p.r) or 32
	local r2 = tonumber(p.r2) or r
	local life = tonumber(p.life) or 9
	local follow = p.follow == true
	local monsoon = p.monsoon == true
	local old = rains[caster]
	if old then
		old:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "AcidRain"
	local cloud = part({
		Name = "Cloud",
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(60, 80, 40),
		Transparency = 0.25,
		Size = Vector3.new(4, r * 2.1, r * 2.1),
	}, model)
	local puffs = {}
	for i = 1, 8 do
		local angle = i / 8 * math.pi * 2
		table.insert(
			puffs,
			part({
				Name = "Puff",
				Shape = Enum.PartType.Ball,
				Material = Enum.Material.SmoothPlastic,
				Color = if i % 2 == 0 then Color3.fromRGB(80, 60, 110) else Color3.fromRGB(70, 100, 45),
				Transparency = 0.2,
				Size = Vector3.one * r * 0.55,
			}, model)
		)
		puffs[i]:SetAttribute("Angle", angle)
	end
	local sky = part({ Name = "Sky", Transparency = 1, Size = Vector3.new(r * 1.8, 0.5, r * 1.8) }, model)
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "AcidRainDrops"
	rain.Color = ColorSequence.new(TOXIC, LIME)
	rain.LightEmission = 0.6
	rain.Size = NumberSequence.new(0.35)
	rain.Squash = NumberSequence.new(2.5)
	rain.Lifetime = NumberRange.new(0.5, 0.6)
	rain.Speed = NumberRange.new(55, 65)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Rate = math.min(r * 7, 240)
	rain.Parent = sky
	local floor = part({
		Name = "Soak",
		Shape = Enum.PartType.Cylinder,
		Color = LIME,
		Transparency = 0.75,
		Size = Vector3.new(0.12, r * 2, r * 2),
	}, model)
	local hissing = fumes(floor, math.min(r, 30), 3)
	model.PrimaryPart = sky
	model.Parent = Fx.folder()
	rains[caster] = model

	word(home + UP * 10, "¡FSSSHHH!", { color = TOXIC, size = 1.7 })
	Fx.sound("splash", home, 0.5)
	if mine then
		Fx.shake(0.4, 0.4)
		Fx.flash(LIME, 0.2, 0.2)
	end

	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if not model.Parent then
			connection:Disconnect()
			return
		end
		if t > life then
			connection:Disconnect()
			rain.Enabled = false
			hissing.Enabled = false
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") and child ~= sky then
					tween(child, 0.8, { Transparency = 1 })
				end
			end
			Debris:AddItem(model, 1)
			if rains[caster] == model then
				rains[caster] = nil
			end
			return
		end
		local c = home
		if follow then
			local root = rootOf(caster)
			if root then
				c = root.Position
			end
		end
		local k = math.clamp(t / life, 0, 1)
		local radius = if monsoon then r + (r2 - r) * k else r
		local ground = Vector3.new(c.X, GROUND, c.Z)
		local height = 30 + (1 - math.min(t / 0.5, 1)) * 20
		cloud.Size = Vector3.new(4, radius * 2.1, radius * 2.1)
		cloud.CFrame = CFrame.new(ground + UP * (height + 2)) * CFrame.Angles(0, 0, math.pi / 2)
		for i, puff in puffs do
			local angle = (puff:GetAttribute("Angle") :: number) + t * 0.3
			puff.Size = Vector3.one * radius * 0.55
			puff.CFrame = CFrame.new(ground + Vector3.new(math.cos(angle) * radius * 0.7, height + 3 + (i % 3), math.sin(angle) * radius * 0.7))
		end
		sky.Size = Vector3.new(radius * 1.8, 0.5, radius * 1.8)
		sky.CFrame = CFrame.new(ground + UP * height)
		floor.Size = Vector3.new(0.12, radius * 2, radius * 2)
		floor.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2)
		floor.Transparency = 0.75 - 0.1 * math.sin(t * 5)
		if monsoon then
			-- El Monzón se oscurece al cerrarse
			rain.Rate = math.min(radius * 7, 240) * (1 + k)
			floor.Color = LIME:Lerp(PURPLE, k * 0.6)
		end
	end)
end

function fx.acid3_tick(caster: Player, p: any, mine: boolean)
	local pts, pops = list(p.pts), list(p.pops)
	local c = vec(p.c)
	if (#pts == 0 and #pops == 0) or (not mine and not seen(c or pts[1])) then
		return
	end
	for i, pt in pts do
		if i > 12 then
			break
		end
		Fx.burst(pt, { color = if i % 2 == 0 then PURPLE else TOXIC, count = 4, speed = 6, size = 0.35, life = 0.3, up = 4 })
	end
	for i, pop in pops do
		bubble(pop + UP * 0.8, 3.2, 0.25, if i % 2 == 0 then PURPLE else TOXIC)
		ring(pop, 6, { color = LIME, life = 0.3, thickness = 0.8 })
		if i == 1 then
			word(pop + UP * 3.5, "¡BLUB!", { color = TOXIC, size = 1, life = 0.5 })
			Fx.sound("pop", pop, 0.9)
		end
	end
	react(pts, c, 0.14)
	loot(caster, pts, LIME)
	if mine and #pops > 0 then
		Fx.shake(0.12, 0.12)
	end
end

----------------------------------------------------------------------------------------------------
-- Aura: glándula ácida que brilla en la punta del abdomen, gotea y echa humo; motas moradas

local function weld(host: BasePart, folder: Instance, props: { [string]: any }, offset: CFrame): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.Neon
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
	folder.Name = "AcidAura"
	folder.Parent = Fx.folder()
	local scale = character:GetScale()
	local grow = 1 + (math.clamp(rank, 1, 10) - 1) * 0.05

	local tip = character:FindFirstChild("AbdomenTip")
	if tip and tip:IsA("BasePart") then
		local gland = weld(tip, folder, {
			Name = "AcidGland",
			Shape = Enum.PartType.Ball,
			Color = LIME,
			Transparency = 0.1,
			Size = Vector3.one * 0.62 * scale * grow,
		}, CFrame.new(0, -0.05 * scale, 0.18 * scale))
		local light = Instance.new("PointLight")
		light.Color = LIME
		light.Range = 5 + rank * 0.4
		light.Brightness = 1.2
		light.Shadows = false
		light.Parent = gland
		dripper(gland, 3 + rank * 0.9, 0.22 * scale)
		fumes(gland, 1 + rank * 0.4, 0.8 * scale)
		if mastered then
			local gold = Instance.new("ParticleEmitter")
			gold.Name = "GoldBubbles"
			gold.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			gold.Color = ColorSequence.new(GOLD)
			gold.LightEmission = 1
			gold.Size = NumberSequence.new(0.25 * scale, 0)
			gold.Lifetime = NumberRange.new(0.5, 0.9)
			gold.Speed = NumberRange.new(1, 2)
			gold.Rate = 5
			gold.Parent = gland
		end
	end

	-- Motas moradas en el abdomen (más con rango)
	local abdomen = character:FindFirstChild("Abdomen")
	if abdomen and abdomen:IsA("BasePart") then
		local spots = math.clamp(2 + math.floor(rank / 3), 2, 5)
		for i = 1, spots do
			local angle = math.rad(-60 + 120 * (i - 1) / math.max(spots - 1, 1))
			weld(abdomen, folder, {
				Name = "AcidSpot",
				Shape = Enum.PartType.Ball,
				Color = if mastered and i == 1 then GOLD else PURPLE,
				Size = Vector3.one * (0.3 + 0.06 * (i % 2)) * scale,
			}, CFrame.new(math.sin(angle) * 0.8 * scale, math.cos(angle) * 0.72 * scale, (-0.1 + 0.25 * (i % 2)) * scale))
		end
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
-- Emblema: una gota verde con burbujas moradas

local function emblem(parent: GuiObject, color: Color3)
	local holder = Instance.new("Frame")
	holder.Name = "AcidEmblem"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = parent

	local function shape(size: Vector2, pos: Vector2, fill: Color3, rotation: number, radius: UDim, stroke: number?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromScale(size.X, size.Y)
		f.Position = UDim2.fromScale(pos.X, pos.Y)
		f.Rotation = rotation
		f.BackgroundColor3 = fill
		f.BorderSizePixel = 0
		f.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = radius
		c.Parent = f
		if stroke then
			local s = Instance.new("UIStroke")
			s.Color = INK
			s.Thickness = stroke
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = f
		end
		return f
	end
	-- Punta de la gota (un cuadrado girado) y su panza redonda encima, tapando la costura
	shape(Vector2.new(0.42, 0.42), Vector2.new(0.5, 0.42), color, 45, UDim.new(0.12, 0), 3)
	shape(Vector2.new(0.62, 0.62), Vector2.new(0.5, 0.6), color, 0, UDim.new(1, 0), 3)
	shape(Vector2.new(0.36, 0.3), Vector2.new(0.5, 0.52), color, 45, UDim.new(0.1, 0))
	-- Brillo y burbujas
	shape(Vector2.new(0.12, 0.2), Vector2.new(0.36, 0.56), Color3.fromRGB(240, 255, 210), 20, UDim.new(1, 0))
	shape(Vector2.new(0.16, 0.16), Vector2.new(0.62, 0.68), PURPLE, 0, UDim.new(1, 0), 2)
	shape(Vector2.new(0.1, 0.1), Vector2.new(0.52, 0.8), PURPLE, 0, UDim.new(1, 0), 2)
end

return {
	fx = fx,
	aura = aura,
	emblem = emblem,
}
