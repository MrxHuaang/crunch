-- Jugo: lo que hace que moverse, llenarse y comprar se sienta bien y no encaja en Fx.
--   · Carga llena: la carga rebota, "¡LLENA!", las casillas hacen la ola y una flecha discreta
--     flota delante de tu hormiga apuntando al hormiguero hasta que entregas.
--   · Caminar y correr: polvo en las patas al arrancar, al frenar y al aterrizar; huellas y
--     polvillo a cada paso al correr.
--   · Compras: en el mundo, chispas y anillo a tus pies; al cruzar un hito, momento grande.
-- Solo efectos locales de tu hormiga: con 6 jugadoras cada una pinta lo suyo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local AntAnim = require(script.Parent.AntAnim)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local Tree = require(script.Parent.Tree)

local Juice = {}

local player = Players.LocalPlayer
local rng = Random.new()
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- textura incluida en Roblox
local folder: Folder

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function head(): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("Head")
	return if part and part:IsA("BasePart") then part else nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- Suelo bajo tu hormiga: (punto, color del suelo) o nil
local function groundBelow(from: Vector3, depth: number): (Vector3?, Color3?)
	local ignore: { Instance } = { folder }
	for _, extra in { player.Character, Workspace:FindFirstChild("FxCrumbs"), Workspace:FindFirstChild("FxWorld") } do
		table.insert(ignore, extra)
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(from, Vector3.new(0, -depth, 0), rayParams)
	if not hit then
		return nil, nil
	end
	local color = if hit.Instance:IsA("Terrain") then Comic.DirtLight else (hit.Instance :: BasePart).Color
	return hit.Position, color
end

---------------------------------------------------------------------------------------------------
-- Polvo: un emisor compartido que se mueve a cada punto y dispara.

local dustAttachment: Attachment
local dustEmitter: ParticleEmitter

local function dust(position: Vector3, count: number, color: Color3?, push: Vector3?)
	dustAttachment.Position = position
	local tint = (color or Comic.DirtLight):Lerp(Comic.Paper, 0.35)
	dustEmitter.Color = ColorSequence.new(tint)
	if push and push.Magnitude > 0.01 then
		dustEmitter.Acceleration = push + Vector3.new(0, 2, 0)
	else
		dustEmitter.Acceleration = Vector3.new(0, 2, 0)
	end
	dustEmitter:Emit(math.clamp(count, 1, 14))
end

---------------------------------------------------------------------------------------------------
-- Huellas al correr: óvalos planos oscuros que se desvanecen (piscina fija).

type Print = { part: Part, born: number, active: boolean }
local PRINT_POOL = 18
local PRINT_LIFE = 1.3
local prints: { Print } = {}
local nextPrint = 0

local function makePrint(): Print
	local part = Instance.new("Part")
	part.Name = "Footprint"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1
	part.Size = Vector3.new(0.05, 0.55, 0.38)
	part.CFrame = CFrame.new(0, -500, 0)
	part.Parent = folder
	return { part = part, born = 0, active = false }
end

local function footprint(position: Vector3, forward: Vector3, color: Color3, scale: number)
	if #prints == 0 then
		return
	end
	nextPrint = nextPrint % #prints + 1
	local p = prints[nextPrint]
	local flat = (forward * Vector3.new(1, 0, 1))
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	p.part.Color = color:Lerp(Comic.Ink, 0.45)
	p.part.Size = Vector3.new(0.05, 0.6 * scale, 0.4 * scale)
	-- El eje X del cilindro (su cara) mira arriba y el largo del óvalo va hacia delante
	p.part.CFrame = CFrame.fromMatrix(position + Vector3.new(0, 0.03, 0), Vector3.yAxis, flat)
	p.part.Transparency = 0.25
	p.born = os.clock()
	p.active = true
end

local function updatePrints(now: number)
	for _, p in prints do
		if p.active then
			local u = (now - p.born) / PRINT_LIFE
			if u >= 1 then
				p.active = false
				p.part.Transparency = 1
				p.part.CFrame = CFrame.new(0, -500, 0)
			elseif u > 0.4 then
				p.part.Transparency = 0.25 + 0.75 * (u - 0.4) / 0.6
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Caminar: arranque, frenazo, aterrizaje y pasos de carrera.

local moving = false
local peakSpeed = 0
local stepAt = 0
local stepSide = 1
local hookedHumanoid: Humanoid? = nil

local function feet(root: BasePart): (Vector3?, Color3?)
	return groundBelow(root.Position, root.Size.Y / 2 + 8)
end

local function hookLanding(humanoid: Humanoid)
	if hookedHumanoid == humanoid then
		return
	end
	hookedHumanoid = humanoid
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			local root = rootPart()
			if root then
				local ground, color = feet(root)
				if ground then
					dust(ground, 9, color)
					Sfx.tick(0.8)
				end
			end
		end
	end)
end

local function updateWalk(now: number)
	local root = rootPart()
	if not root then
		return
	end
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		hookLanding(humanoid)
	end
	local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local speed = velocity.Magnitude
	local walk = math.max(tonumber(player:GetAttribute("WalkSpeed")) or 10, 1)
	local airborne = humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air
	local scale = character:GetScale()

	if not moving and speed > walk * 0.55 then
		moving = true
		peakSpeed = speed
		if not airborne then
			local ground, color = feet(root)
			if ground then
				-- Arranque: polvo hacia atrás
				dust(ground - root.CFrame.LookVector * 0.6 * scale, 6, color, -velocity.Unit * 6)
			end
		end
	elseif moving then
		peakSpeed = math.max(peakSpeed, speed)
		if speed < 0.8 then
			moving = false
			if not airborne and peakSpeed > walk * 0.7 then
				local ground, color = feet(root)
				if ground then
					-- Frenazo: polvo hacia delante
					dust(ground + root.CFrame.LookVector * 0.8 * scale, 7, color, root.CFrame.LookVector * 5)
				end
			end
			peakSpeed = 0
		end
	end

	-- Corriendo: huella y polvillo a cada paso, alternando patas
	if moving and not airborne and speed > walk * 1.3 then
		local interval = math.clamp(2.4 / speed, 0.1, 0.2)
		if now - stepAt >= interval then
			stepAt = now
			stepSide = -stepSide
			local side = root.CFrame.RightVector * 0.45 * scale * stepSide
			local ground, color = groundBelow(root.Position + side, root.Size.Y / 2 + 8)
			if ground and color then
				footprint(ground, root.CFrame.LookVector, color, scale)
				dust(ground, 1, color, -velocity.Unit * 3)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Carga llena: momento claro y agradable, y una flecha discreta hacia el hormiguero.

local wasFull = false
local fullAt = 0

-- Flecha: un chevron de dos trazos (tinta + amarillo) que mira a la cámara y flota delante de ti
local arrowPart: Part
local arrowTip: Attachment
local arrowLeft: Attachment
local arrowRight: Attachment
local arrowBeams: { Beam } = {}
local arrowShown = 0 -- 0..1 (aparece y desaparece suave)

local function makeArrow()
	arrowPart = Instance.new("Part")
	arrowPart.Name = "HomeArrow"
	arrowPart.Anchored = true
	arrowPart.CanCollide = false
	arrowPart.CanQuery = false
	arrowPart.CanTouch = false
	arrowPart.Transparency = 1
	arrowPart.Size = Vector3.new(0.2, 0.2, 0.2)
	arrowPart.CFrame = CFrame.new(0, -500, 0)
	arrowPart.Parent = folder
	arrowTip = Instance.new("Attachment")
	arrowTip.Parent = arrowPart
	arrowLeft = Instance.new("Attachment")
	arrowLeft.Parent = arrowPart
	arrowRight = Instance.new("Attachment")
	arrowRight.Parent = arrowPart
	local function stroke(a0: Attachment, a1: Attachment, color: Color3, width: number, z: number, emission: number)
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.Color = ColorSequence.new(color)
		b.FaceCamera = true
		b.Segments = 1
		b.LightInfluence = 0
		b.LightEmission = emission
		b.ZOffset = z
		b.Width0 = 0
		b.Width1 = 0
		b:SetAttribute("Full", width)
		b.Parent = arrowPart
		table.insert(arrowBeams, b)
	end
	stroke(arrowLeft, arrowTip, Comic.Ink, 0.62, 0, 0)
	stroke(arrowRight, arrowTip, Comic.Ink, 0.62, 0, 0)
	stroke(arrowLeft, arrowTip, Comic.Yellow, 0.34, 0.04, 0.4)
	stroke(arrowRight, arrowTip, Comic.Yellow, 0.34, 0.04, 0.4)
end

local function updateArrow(now: number, dt: number)
	local root = rootPart()
	local hill = State.hill()
	local capacity = State.stats().capacity
	local full = capacity > 0 and State.num("Carry") >= capacity
	local want = false
	local dir = Vector3.zero
	if full and root and hill then
		-- Al punto de entrega más cercano: casa o el hormiguero de una zona abierta
		local toHill = (hill:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)
		local radius = Config.Anthill.DepositRadius * (State.stats().hillScale or 1)
		for zone = 2, math.min(State.depth(), #Config.Zones) do
			local at = Config.depotPos(zone)
			local toDepot = at and (at - root.Position) * Vector3.new(1, 0, 1)
			if toDepot and toDepot.Magnitude < toHill.Magnitude then
				toHill, radius = toDepot, Config.Depot.Radius
			end
		end
		-- Aparece medio segundo después del "¡LLENA!" y se calla al llegar
		want = toHill.Magnitude > radius + 4 and now - fullAt > 0.5
		if toHill.Magnitude > 0.01 then
			dir = toHill.Unit
		end
	end
	arrowShown = math.clamp(arrowShown + (if want then dt * 4 else -dt * 6), 0, 1)
	if arrowShown <= 0 then
		if arrowPart.Position.Y > -400 then
			arrowPart.CFrame = CFrame.new(0, -500, 0)
		end
		return
	end
	if not root or dir == Vector3.zero then
		return
	end
	local scale = (player.Character :: Model):GetScale()
	local bob = math.sin(now * 6) * 0.3
	local center = root.Position + dir * (4 + bob) * scale + Vector3.new(0, -0.2 * scale, 0)
	arrowPart.CFrame = CFrame.new(center)
	local side = dir:Cross(Vector3.yAxis) * 0.75 * scale
	arrowTip.Position = dir * 0.7 * scale
	arrowLeft.Position = -dir * 0.3 * scale + side
	arrowRight.Position = -dir * 0.3 * scale - side
	for _, b in arrowBeams do
		local w = (b:GetAttribute("Full") :: number) * scale * arrowShown
		b.Width0 = w
		b.Width1 = w
	end
end

-- El trozo que llevas entre las mandíbulas rebota (escritura local; se devuelve el tamaño exacto)
local function bounceChunk()
	local character = player.Character
	local chunk = character and character:FindFirstChild("CarryChunk")
	if not chunk or not chunk:IsA("BasePart") then
		return
	end
	local original = chunk.Size
	local up = TweenService:Create(chunk, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = original * 1.45 })
	up:Play()
	up.Completed:Once(function()
		if not chunk.Parent then
			return
		end
		local down = TweenService:Create(chunk, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Size = original })
		down:Play()
		down.Completed:Once(function()
			if chunk.Parent then
				chunk.Size = original
			end
		end)
	end)
end

local function onFull()
	fullAt = os.clock()
	Hud.carryFull()
	bounceChunk()
	local top = head()
	if top then
		Fx.word(top.Position + Vector3.new(0, 2.6, 0), "¡LLENA!", Comic.Yellow, 40, { life = 0.8, side = 0, rise = 1.5, tilt = -6, force = true })
		Fx.sparks(top.Position + Vector3.new(0, 1, 0), 8, Comic.Yellow)
	end
	for i = 0, 2 do
		task.delay(i * 0.07, Sfx.pop, 1.2 + i * 0.25, 0.4)
	end
end

local function watchCarry()
	local capacity = State.stats().capacity
	local full = capacity > 0 and State.num("Carry") >= capacity
	if full and not wasFull and State.flag("Loaded") then
		onFull()
	end
	wasFull = full
end

---------------------------------------------------------------------------------------------------
-- Compras: celebración en el mundo (si no estás mirando el árbol) y momento grande en los hitos.

local function celebrateWorld(kind: string, id: any)
	if kind ~= "node" and kind ~= "node-max" and kind ~= "royal" then
		return
	end
	if type(id) ~= "string" then
		return
	end
	local treeKind = if kind == "royal" then "royal" else "node"
	local old, new = Tree.levelChange(treeKind, id)
	if not old then
		task.wait(0.15)
		old, new = Tree.levelChange(treeKind, id)
	end
	local milestone = treeKind == "node" and old ~= nil and Tree.milestones(new) > Tree.milestones(old)
	local root = rootPart()
	local top = head()
	if milestone then
		-- Segundo saltito y la cámara lo nota aunque el árbol esté abierto
		task.delay(0.7, AntAnim.cheer)
		Fx.shake(0.3)
	end
	if Tree.isOpen() or not root or not top then
		return -- el árbol tapa el mundo: ahí celebra el propio árbol
	end
	local ground = root.Position - Vector3.new(0, root.Size.Y / 2 + 0.5, 0)
	if milestone then
		local m = (Config :: any).Milestones
		local mult = type(m) == "table" and tonumber(m.Mult or m.mult or m.Multiplier or m.multiplier) or nil
		Fx.ring(ground, 9, Comic.Red, 0.5)
		task.delay(0.1, Fx.ring, ground, 6, Comic.Yellow, 0.45)
		Fx.flash(top.Position, Comic.Yellow, 6)
		Fx.confetti(top.Position + Vector3.new(0, 1, 0), { Comic.Yellow, Comic.Red, Comic.Cyan, Comic.Paper }, 24, 1.2)
		Fx.word(top.Position + Vector3.new(0, 3.5, 0), if mult then "¡HITO! ×" .. mult else "¡HITO!", Comic.Red, 64, {
			life = 1.1,
			side = 0,
			rise = 2.5,
			tilt = -8,
			force = true,
		})
		Fx.kick(4)
	else
		local strength = math.clamp(0.4 + (if old then new - old else 1) * 0.15, 0.4, 1)
		Fx.ring(ground, 3 + 3 * strength, Comic.Yellow, 0.35)
		Fx.sparks(top.Position + Vector3.new(0, 1, 0), math.floor(6 + 8 * strength), Comic.Yellow)
		if old then
			Fx.word(top.Position + Vector3.new(0, 2.5, 0), old .. " → " .. new, Comic.Paper, 32, { life = 0.7, side = 0 })
		end
	end
end

---------------------------------------------------------------------------------------------------

function Juice.start(remotes: Folder)
	folder = Instance.new("Folder")
	folder.Name = "JuiceFx"
	folder.Parent = Workspace

	dustAttachment = Instance.new("Attachment")
	dustAttachment.Name = "JuiceDust"
	dustAttachment.Parent = Workspace.Terrain
	dustEmitter = Instance.new("ParticleEmitter")
	dustEmitter.Texture = DUST_TEXTURE
	dustEmitter.Enabled = false
	dustEmitter.Rate = 0
	dustEmitter.Lifetime = NumberRange.new(0.35, 0.6)
	dustEmitter.Speed = NumberRange.new(2, 5)
	dustEmitter.SpreadAngle = Vector2.new(70, 20)
	dustEmitter.EmissionDirection = Enum.NormalId.Top
	dustEmitter.Drag = 4
	dustEmitter.RotSpeed = NumberRange.new(-90, 90)
	dustEmitter.Rotation = NumberRange.new(0, 360)
	dustEmitter.LightInfluence = 0.6
	dustEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.4) })
	dustEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dustEmitter.Parent = dustAttachment

	for _ = 1, PRINT_POOL do
		table.insert(prints, makePrint())
	end
	makeArrow()

	State.onChange(watchCarry)
	remotes.Fx.OnClientEvent:Connect(function(kind: string, a: any, b: any)
		if kind == "Bought" then
			task.spawn(celebrateWorld, a, b)
		elseif kind == "Deposit" then
			wasFull = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		dt = math.min(dt, 0.1)
		updateWalk(now)
		updatePrints(now)
		updateArrow(now, dt)
	end)
end

return Juice
