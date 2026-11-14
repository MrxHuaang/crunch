-- Exploradora (cliente): el impulso visible en la hormiga, la Embestida y el Salto de pulga (los mueve
-- el cliente de la dueña), la Estampida con su manada fantasma, el aura de visera y estela, y el emblema.
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
local ORANGE = Color3.fromRGB(255, 140, 30)
local HOT = Color3.fromRGB(255, 196, 90)
local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 196, 40)
local GHOST = Color3.fromRGB(255, 236, 210)
local SEEN = 260
local GROUND = Config.GroundY + 0.06
local CHARGE_ATTR = "ScoutCharge" -- lo publica el servidor (src/server/Castes/scout.luau)

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

local function foodFolder(): Instance?
	return Workspace:FindFirstChild("Food")
end

local function foodAt(pt: Vector3): Model?
	local folder = foodFolder()
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
		Fx.orbs(pts, hill, { color = color or ORANGE })
	end
end

local function rootOf(who: Player): BasePart?
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Mutaciones y parámetros de la dueña (para lo que hace el cliente al lanzar)
local function mine(): any
	local ok, resolved = pcall(function()
		local Castes = require(ReplicatedStorage.Shared.Castes)
		local def = Castes.get("scout")
		local raw = player:GetAttribute("CasteData")
		local data = if type(raw) == "string" and raw ~= "" then HttpService:JSONDecode(raw) else {}
		local muts = data.muts and data.muts.scout or {}
		local xp = data.xp and data.xp.scout or 0
		return Castes.resolve(def, muts, Castes.rankOf(xp))
	end)
	return if ok then resolved else nil
end

local function myParam(id: string, key: string, fallback: number): number
	local resolved = mine()
	if resolved then
		local ok, value = pcall(resolved.param, id, key)
		if ok and type(value) == "number" and value ~= 0 then
			return value
		end
	end
	return fallback
end

local function myFlag(flag: string): boolean
	local resolved = mine()
	if resolved then
		local ok, value = pcall(resolved.has, flag)
		return ok and value == true
	end
	return false
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

-- Lo que dura un salto (el servidor usa la misma cuenta para el aterrizaje)
local function jumpTime(distance: number): number
	return 0.35 + distance / 140
end

----------------------------------------------------------------------------------------------------
-- Movimiento de la dueña

local moving = false
local stopAt: Vector3? = nil -- el servidor puede acortar una embestida (Ariete)

local function blockers(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip = { Fx.folder() }
	if player.Character then
		table.insert(skip, player.Character)
	end
	local food = foodFolder()
	if food then
		table.insert(skip, food)
	end
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = true
	return params
end

-- Recorta un tramo contra paredes y troncos
local function clearPath(from: Vector3, to: Vector3): Vector3
	local hit = Workspace:Raycast(from, to - from, blockers())
	if hit then
		local back = (to - from).Unit * 1.5
		return hit.Position - back
	end
	return to
end

-- Acelerón por una lista de puntos en `duration` segundos, a la altura de partida
local function dash(points: { Vector3 }, duration: number)
	local root = rootOf(player)
	if not root or moving or #points < 2 then
		return
	end
	local y = root.Position.Y
	local path = { Vector3.new(points[1].X, y, points[1].Z) }
	for i = 2, #points do
		local to = clearPath(path[i - 1], Vector3.new(points[i].X, y, points[i].Z))
		path[i] = to
		if (to - Vector3.new(points[i].X, y, points[i].Z)).Magnitude > 0.5 then
			break -- chocó: hasta aquí
		end
	end
	local lengths, total = {}, 0
	for i = 2, #path do
		lengths[i] = (path[i] - path[i - 1]).Magnitude
		total += lengths[i]
	end
	if total < 0.5 then
		return
	end
	moving = true
	stopAt = nil
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
		-- Arranca de golpe y frena al final
		local d = (1 - (1 - t) ^ 3) * total
		local here, facing = path[#path], flatUnit(path[#path] - path[1], now.CFrame.LookVector)
		for i = 2, #path do
			if d <= lengths[i] then
				here = path[i - 1]:Lerp(path[i], d / math.max(lengths[i], 0.01))
				facing = flatUnit(path[i] - path[i - 1], facing)
				break
			end
			d -= lengths[i]
		end
		local stop = stopAt
		if stop and ((here - path[1]) * FLAT).Magnitude >= ((stop - path[1]) * FLAT).Magnitude then
			here = Vector3.new(stop.X, path[1].Y, stop.Z)
			t = 1
		end
		now.CFrame = CFrame.lookAt(here, here + facing)
		now.AssemblyLinearVelocity = facing * 30
		if t >= 1 then
			connection:Disconnect()
			now.AssemblyLinearVelocity = Vector3.zero
			moving = false
		end
	end)
end

-- Salto en arco hasta `to` en `duration` segundos
local function leap(to: Vector3, duration: number, height: number)
	local root = rootOf(player)
	if not root or moving then
		return
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
		local position = from:Lerp(target, t) + UP * math.sin(t * math.pi) * height
		-- Se encoge al despegar y se estira en el aire, como una pulga
		now.CFrame = CFrame.new(position) * rotation * CFrame.Angles(math.rad(-25 * math.sin(t * math.pi)), 0, 0)
		now.AssemblyLinearVelocity = Vector3.zero
		if t >= 1 then
			connection:Disconnect()
			now.CFrame = CFrame.new(target) * rotation
			moving = false
		end
	end)
end

-- Primera comida en la línea (para que el Ariete frene contra ella)
local function firstFoodOnLine(a: Vector3, b: Vector3, width: number): Vector3?
	local folder = foodFolder()
	if not folder then
		return nil
	end
	local fa, fb = a * FLAT, b * FLAT
	local seg = fb - fa
	local lengthSq = seg:Dot(seg)
	if lengthSq < 1e-3 then
		return nil
	end
	local bestT, best = math.huge, nil
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			local center = model:GetPivot().Position
			local p = center * FLAT
			local t = math.clamp((p - fa):Dot(seg) / lengthSq, 0, 1)
			local radius = (model:GetAttribute("Radius") :: number?) or 2
			if (p - (fa + seg * t)).Magnitude - radius <= width / 2 and t < bestT then
				bestT = t
				local back = flatUnit(a - center, Vector3.zAxis)
				best = center + back * (radius + 1.5)
			end
		end
	end
	return best
end

local cast = {}

function cast.scout1(aim: Vector3, _aimFood: Model?, _def: any): boolean
	local root = rootOf(player)
	if not root then
		return true
	end
	local a = root.Position
	local dir = flatUnit(aim - a, root.CFrame.LookVector)
	local length = myParam("scout1", "length", 32)
	local time = myParam("scout1", "time", 0.28)
	local points = { a }
	if myFlag("zigzag") then
		local zig = myParam("scout1", "zigAngle", 35)
		local here = a
		for _, angle in { zig, -zig, zig } do
			here += turn(dir, angle) * length * 0.5
			table.insert(points, here)
		end
		time *= 1.6
	elseif myFlag("ram") then
		local width = myParam("scout1", "width", 7)
		table.insert(points, firstFoodOnLine(a, a + dir * length, width) or a + dir * length)
	else
		table.insert(points, a + dir * length)
	end
	dash(points, time)
	return true
end

function cast.scout2(aim: Vector3, _aimFood: Model?, def: any): boolean
	local root = rootOf(player)
	if not root then
		return true
	end
	local range = myParam("scout2", "range", (type(def) == "table" and tonumber(def.range)) or 70)
	local offset = (aim - root.Position) * FLAT
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	local distance = offset.Magnitude
	leap(root.Position + offset, jumpTime(distance), 6 + distance * 0.22)
	return true
end

----------------------------------------------------------------------------------------------------
-- Formas

-- Líneas de velocidad a lo largo de un tramo
local function speedLines(a: Vector3, b: Vector3, count: number, color: Color3, life: number)
	local dir = b - a
	if dir.Magnitude < 0.5 then
		return
	end
	local side = flatUnit(dir:Cross(UP), Vector3.xAxis)
	for i = 1, count do
		local offset = side * rng:NextNumber(-2.2, 2.2) + UP * rng:NextNumber(-0.6, 1.4)
		local from, to = a + offset, b + offset
		local line = part({
			Name = "SpeedLine",
			Color = if i % 3 == 0 then WHITE else color,
			Size = Vector3.new(0.18, 0.18, (to - from).Magnitude),
			CFrame = CFrame.lookAt((from + to) / 2, to),
			Transparency = 0.15,
		})
		tween(line, life, { Transparency = 1, Size = Vector3.new(0.04, 0.04, line.Size.Z * 1.2) })
		Debris:AddItem(line, life + 0.05)
	end
end

-- Silueta de hormiga fantasma: cabeza, tórax y abdomen translúcidos con antenas
local function ghostAnt(scale: number, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "GhostAnt"
	local thorax = part({ Name = "Thorax", Shape = Enum.PartType.Ball, Color = color, Transparency = 0.55, Size = Vector3.one * 1.1 * scale }, model)
	part({ Name = "Head", Shape = Enum.PartType.Ball, Color = color, Transparency = 0.5, Size = Vector3.one * 1.4 * scale, CFrame = CFrame.new(0, 0.2 * scale, -1.3 * scale) }, model)
	part({ Name = "Abdomen", Shape = Enum.PartType.Ball, Color = color, Transparency = 0.6, Size = Vector3.one * 1.8 * scale, CFrame = CFrame.new(0, 0.2 * scale, 1.4 * scale) }, model)
	for _, s in { -1, 1 } do
		part({
			Name = "Antenna",
			Color = ORANGE,
			Transparency = 0.3,
			Size = Vector3.new(0.12, 0.12, 1.3) * scale,
			CFrame = CFrame.new(s * 0.35 * scale, 0.9 * scale, -1.9 * scale) * CFrame.Angles(math.rad(35), math.rad(s * 20), 0),
		}, model)
	end
	model.PrimaryPart = thorax
	model.Parent = Fx.folder()
	return model
end

local function fadeModel(model: Model, time: number)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			tween(child, time, { Transparency = 1 })
		end
	end
	Debris:AddItem(model, time + 0.05)
end

----------------------------------------------------------------------------------------------------
-- Efectos

local fx = {}

-- Rebufo: el mordisco cargado atraviesa en línea (o chispas al adelantar, con Chispazo)
function fx.passive(_caster: Player, p: any, mine_: boolean)
	local pts = list(p.pts)
	if p.spark then
		local a = vec(p.a)
		if not a or (not mine_ and not seen(a)) then
			return
		end
		for _, pt in pts do
			Fx.bolt(a, pt, { color = HOT, width = 0.2, life = 0.1, jitter = 0.4 })
			Fx.burst(pt, { color = ORANGE, count = 5, speed = 9, size = 0.35, life = 0.25 })
		end
		react(pts, a, 0.15)
		if mine_ then
			Fx.sound("pop", a, rng:NextNumber(1.4, 1.7))
		end
		return
	end
	local a, b = vec(p.a), vec(p.b)
	if not a or not b or (not mine_ and not seen(a)) then
		return
	end
	local mult = tonumber(p.mult) or 1
	local power = math.clamp((mult - 1) / 3, 0, 1.6)
	speedLines(a, b, 2 + math.floor(power * 4), ORANGE, 0.18 + power * 0.1)
	Fx.burst(a, { color = HOT, count = 6 + math.floor(power * 14), speed = 12 + power * 10, size = 0.45, life = 0.3 })
	for _, pt in pts do
		Fx.burst(pt, { color = ORANGE, count = 8, speed = 12, size = 0.45, life = 0.3 })
	end
	react(pts, a, 0.2 + power * 0.12)
	if mult >= 2.5 then
		word(a + UP * 3, if mult >= 5 then "¡KA-ZOOM!" else "¡ZOOM!", { color = ORANGE, size = 0.8 + power * 0.4 })
		Fx.light(a, { color = HOT, range = 10 + power * 8, life = 0.15 })
	end
	if mine_ then
		Fx.sound("whoosh", a, 1.5 - power * 0.3)
		if mult >= 2.5 then
			Fx.shake(0.1 + power * 0.15, 0.15)
		end
	end
end

-- Embestida: siluetas, líneas de velocidad y los golpes en orden a lo largo del camino
function fx.scout1(caster: Player, p: any, mine_: boolean)
	local path = list(p.path)
	if #path < 2 or (not mine_ and not seen(path[1])) then
		return
	end
	local time = tonumber(p.time) or 0.28
	local pts = list(p.pts)
	local ram = vec(p.ram)
	if mine_ and ram then
		stopAt = path[2] -- el servidor dice dónde se estrella
	end
	local character = caster.Character
	if character then
		Fx.ghosts(character, time + 0.25, { color = ORANGE })
	end
	Fx.burst(path[1], { color = WHITE, count = 12, speed = 14, size = 0.5, life = 0.3, up = 2 })
	ring(path[1], 4, { color = ORANGE, life = 0.25, thickness = 0.6 })
	word(path[1] + UP * 3, "¡FIUUM!", { color = ORANGE, size = 1.1 })
	Fx.sound("whoosh", path[1], 1)
	for i = 1, #path - 1 do
		task.delay(time * (i - 1) / (#path - 1), function()
			speedLines(path[i], path[i + 1], 6, ORANGE, 0.35)
			Fx.wave(path[i], path[i + 1], 7, { color = ORANGE, time = time / (#path - 1), height = 1.5 })
		end)
	end
	-- Cada comida reacciona cuando la embestida pasa por ella
	local start = path[1]
	local total = ((path[#path] - start) * FLAT).Magnitude
	for _, pt in pts do
		local k = math.clamp(((pt - start) * FLAT).Magnitude / math.max(total, 1), 0, 1)
		task.delay(time * k, function()
			Fx.burst(pt, { color = ORANGE, count = 10, speed = 15, size = 0.5, life = 0.3, up = 4 })
			react({ pt }, start, 0.3)
		end)
	end
	task.delay(time, function()
		if ram then
			ring(ram, 8, { color = ORANGE, life = 0.35, thickness = 1.4 })
			Fx.burst(ram, { color = WHITE, count = 24, speed = 22, size = 0.6, life = 0.4, up = 8 })
			word(ram + UP * 4, "¡PAM!", { color = ORANGE, size = 1.5 })
			Fx.light(ram, { color = HOT, range = 18, life = 0.2 })
			Fx.sound("thud", ram, 0.8)
		end
		loot(caster, pts, ORANGE)
		if mine_ then
			Fx.shake(if ram then 0.45 else 0.2 + 0.02 * #pts, 0.25)
		end
	end)
end

-- Salto de pulga: despegue y marca de aterrizaje
local function landingMark(b: Vector3, r: number, flight: number)
	local ground = Vector3.new(b.X, GROUND, b.Z)
	local mark = part({
		Name = "FleaMark",
		Shape = Enum.PartType.Cylinder,
		Color = ORANGE,
		Transparency = 0.6,
		Size = Vector3.new(0.12, r * 2, r * 2),
		CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.pi / 2),
	})
	tween(mark, flight, { Size = Vector3.new(0.12, 2, 2), Transparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(mark, flight + 0.05)
end

function fx.scout2(_caster: Player, p: any, mine_: boolean)
	local a, b = vec(p.a), vec(p.b)
	if not a or not b or (not mine_ and not seen(a)) then
		return
	end
	local flight = tonumber(p.flight) or 0.8
	local r = tonumber(p.r) or 9
	local ground = Vector3.new(a.X, GROUND, a.Z)
	ring(ground, 5, { color = WHITE, life = 0.3, thickness = 0.8 })
	Fx.burst(ground + UP, { color = Color3.fromRGB(200, 160, 110), count = 12, speed = 12, size = 0.6, life = 0.35, up = 4 })
	word(a + UP * 3, "¡BOING!", { color = ORANGE, size = 1.1 })
	Fx.sound("whoosh", a, 0.8)
	landingMark(b, r, flight)
end

function fx.scout2_hop(_caster: Player, p: any, mine_: boolean)
	local a, b = vec(p.a), vec(p.b)
	if not a or not b then
		return
	end
	local flight = tonumber(p.flight) or 0.5
	if mine_ then
		local distance = ((b - a) * FLAT).Magnitude
		leap(b, flight, 4 + distance * 0.2)
	end
	if mine_ or seen(a) then
		word(a + UP * 2.5, "¡BOING!", { color = ORANGE, size = 0.8, life = 0.4 })
		landingMark(b, 5, flight)
		Fx.sound("whoosh", a, 1.2)
	end
end

function fx.scout2_land(caster: Player, p: any, mine_: boolean)
	local at = vec(p.p)
	if not at or (not mine_ and not seen(at)) then
		return
	end
	local r = tonumber(p.r) or 9
	local pts = list(p.pts)
	local small = p.small == true
	local quake = p.quake == true and not small
	local ground = Vector3.new(at.X, GROUND, at.Z)
	ring(ground, r, { color = ORANGE, life = 0.4, thickness = if quake then 2.2 else 1.2 })
	ring(ground, r * 0.5, { color = WHITE, life = 0.3, thickness = 0.8 })
	Fx.burst(ground + UP, { color = Color3.fromRGB(200, 160, 110), count = if quake then 30 else 16, speed = if quake then 26 else 16, size = 0.65, life = 0.45, up = 6 })
	Fx.burst(ground + UP, { color = ORANGE, count = 10, speed = 14, size = 0.5, life = 0.35, up = 4 })
	Fx.light(ground + UP * 2, { color = HOT, range = r * 1.8, life = 0.2 })
	word(ground + UP * 4, if quake then "¡KA-BUM!" elseif small then "¡TOC!" else "¡PLOF!", { color = ORANGE, size = if quake then 1.6 elseif small then 0.9 else 1.3 })
	if quake then
		for i = 1, 8 do
			local dir = turn(Vector3.zAxis, i * 45 + rng:NextNumber(-12, 12))
			local length = r * rng:NextNumber(0.5, 0.9)
			local crack = part({
				Name = "Crack",
				Material = Enum.Material.SmoothPlastic,
				Color = INK,
				Size = Vector3.new(0.4, 0.1, length),
				CFrame = CFrame.lookAt(ground + dir * length / 2, ground + dir * length),
			})
			task.delay(1, function()
				tween(crack, 0.5, { Transparency = 1 })
				Debris:AddItem(crack, 0.55)
			end)
		end
	end
	react(pts, ground, if quake then 0.4 else 0.3)
	loot(caster, pts, ORANGE)
	Fx.sound("thud", ground, if quake then 0.6 else 1)
	if mine_ then
		Fx.shake(if quake then 0.6 elseif small then 0.2 else 0.35, 0.3)
		if quake then
			Fx.flash(ORANGE, 0.15, 0.12)
		end
	end
end

-- Estampida: manada de hormigas fantasma corriendo con la dueña
local herds: { [Player]: { models: { Model }, endAt: number } } = {}

function fx.scout3(caster: Player, p: any, mine_: boolean)
	local life = tonumber(p.life) or 7
	local speed = tonumber(p.speed) or 2
	if mine_ then
		speedFor(speed, life)
	end
	local root = rootOf(caster)
	if not root or (not mine_ and not seen(root.Position)) then
		return
	end
	local old = herds[caster]
	if old then
		for _, model in old.models do
			model:Destroy()
		end
	end
	local character = caster.Character
	local scale = if character then character:GetScale() else 1
	local comet = p.comet == true
	local herdLoose = p.herd == true
	local models = {}
	-- Formación: a los lados y detrás; con Manada suelta no corren contigo (embisten solas)
	local slots = if herdLoose then {} else { Vector3.new(-4, 0, 1), Vector3.new(4, 0, 1), Vector3.new(-2.5, 0, 5), Vector3.new(2.5, 0, 5), Vector3.new(0, 0, 8) }
	for _ in slots do
		table.insert(models, ghostAnt(scale, GHOST))
	end
	local entry = { models = models, endAt = os.clock() + life }
	herds[caster] = entry

	-- Cometa: bola de fuego naranja alrededor de la dueña con estela
	local fireball, trail
	if comet then
		fireball = part({ Name = "Comet", Shape = Enum.PartType.Ball, Color = HOT, Transparency = 0.55, Size = Vector3.one * 6 * scale })
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 1.5, 0)
		a0.Parent = fireball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -1.5, 0)
		a1.Parent = fireball
		trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(WHITE, ORANGE)
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.Lifetime = 0.5
		trail.LightEmission = 1
		trail.Parent = fireball
	end

	-- Polvo a los pies mientras dura
	local dust = part({ Name = "StampedeDust", Transparency = 1, Size = Vector3.new(3, 0.2, 3) })
	local puff = Instance.new("ParticleEmitter")
	puff.Color = ColorSequence.new(Color3.fromRGB(210, 175, 130))
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(0.5, 0.8)
	puff.Speed = NumberRange.new(2, 5)
	puff.SpreadAngle = Vector2.new(60, 20)
	puff.Rate = 30
	puff.Parent = dust

	word(root.Position + UP * 5, "¡BRRRUM!", { color = ORANGE, size = 1.6 })
	ring(root.Position, tonumber(p.r) or 8, { color = ORANGE, life = 0.4, thickness = 1.4 })
	Fx.sound("whoosh", root.Position, 0.6)
	if mine_ then
		Fx.shake(0.35, 0.35)
		Fx.flash(ORANGE, 0.15, 0.15)
	end

	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local here = rootOf(caster)
		local now = os.clock()
		if not here or now >= entry.endAt then
			connection:Disconnect()
			for _, model in models do
				if model.Parent then
					fadeModel(model, 0.35)
				end
			end
			if fireball then
				tween(fireball, 0.3, { Transparency = 1 })
				Debris:AddItem(fireball, 0.35)
			end
			puff.Enabled = false
			Debris:AddItem(dust, 1)
			if herds[caster] == entry then
				herds[caster] = nil
			end
			return
		end
		local t = now - started
		local frame = CFrame.lookAt(here.Position, here.Position + flatUnit(here.CFrame.LookVector, Vector3.zAxis))
		for i, model in models do
			local slot = slots[i]
			local bob = math.abs(math.sin(t * 14 + i * 1.7)) * 0.8
			local spot = frame:PointToWorldSpace(slot * scale) + UP * bob
			model:PivotTo(CFrame.lookAt(spot, spot + frame.LookVector))
		end
		if fireball then
			fireball.CFrame = here.CFrame
		end
		dust.CFrame = CFrame.new(here.Position.X, GROUND + 0.2, here.Position.Z)
	end)
end

function fx.scout3_tick(caster: Player, p: any, mine_: boolean)
	local pts, blasts = list(p.pts), list(p.blasts)
	if #pts == 0 or (not mine_ and not seen(pts[1])) then
		return
	end
	for i, pt in pts do
		if i > 12 then
			break
		end
		Fx.burst(pt, { color = if i % 2 == 0 then WHITE else ORANGE, count = 5, speed = 12, size = 0.4, life = 0.25, up = 3 })
	end
	for i, at in blasts do
		ring(at, 6, { color = HOT, life = 0.3, thickness = 1 })
		Fx.burst(at, { color = HOT, count = 14, speed = 18, size = 0.55, life = 0.35, up = 6 })
		if i == 1 then
			word(at + UP * 3, "¡POW!", { color = ORANGE, size = 1, life = 0.45 })
		end
	end
	if #blasts == 0 and rng:NextNumber() < 0.2 then
		word(pts[1] + UP * 2.5, "¡PATAPAM!", { color = ORANGE, size = 0.8, life = 0.45 })
	end
	react(pts, nil, 0.22)
	loot(caster, pts, ORANGE)
	if mine_ then
		Fx.sound("pop", pts[1], rng:NextNumber(1.1, 1.4))
		if #blasts > 0 then
			Fx.shake(0.15, 0.12)
		end
	end
end

-- Manada suelta: fantasmas que salen disparadas en todas direcciones
function fx.scout3_herd(caster: Player, p: any, mine_: boolean)
	local as, bs = list(p.as), list(p.bs)
	local pts = list(p.pts)
	if #as == 0 or (not mine_ and not seen(as[1])) then
		return
	end
	local character = caster.Character
	local scale = if character then character:GetScale() else 1
	for i = 1, #as do
		local a, b = as[i], bs[i]
		if not b then
			continue
		end
		local ghost = ghostAnt(scale, GHOST)
		local dir = flatUnit(b - a, Vector3.zAxis)
		ghost:PivotTo(CFrame.lookAt(a, a + dir))
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = math.min((os.clock() - started) / 0.3, 1)
			if not ghost.Parent then
				connection:Disconnect()
				return
			end
			local here = a:Lerp(b, 1 - (1 - t) ^ 2)
			ghost:PivotTo(CFrame.lookAt(here, here + dir))
			if t >= 1 then
				connection:Disconnect()
				fadeModel(ghost, 0.2)
			end
		end)
		speedLines(a, b, 2, GHOST, 0.3)
	end
	for _, pt in pts do
		task.delay(0.15, function()
			Fx.burst(pt, { color = ORANGE, count = 8, speed = 12, size = 0.45, life = 0.3, up = 3 })
		end)
	end
	task.delay(0.15, function()
		react(pts, as[1], 0.25)
		loot(caster, pts, ORANGE)
	end)
	if mine_ then
		Fx.sound("whoosh", as[1], 1.3)
	end
end

----------------------------------------------------------------------------------------------------
-- Aura: visera aerodinámica, aletas en lugar de antenas sueltas y estela; el impulso se ve crecer

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
	folder.Name = "ScoutAura"
	folder.Parent = Fx.folder()
	local scale = character:GetScale()
	local grow = 1 + (math.clamp(rank, 1, 10) - 1) * 0.04
	local owner = Players:GetPlayerFromCharacter(character)
	local fins = {}

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		-- Visera: un ala blanca sobre los ojos con franja naranja (dorada con Maestría)
		-- (bolas achatadas con malla de esfera: una Ball no admite tamaño desigual)
		local visor = weld(head, folder, {
			Name = "ScoutVisor",
			Color = WHITE,
			Size = Vector3.new(2.1, 0.32, 1.25) * scale,
		}, CFrame.new(0, 0.78 * scale, -0.55 * scale) * CFrame.Angles(math.rad(-12), 0, 0))
		local stripe = weld(head, folder, {
			Name = "ScoutStripe",
			Material = Enum.Material.Neon,
			Color = if mastered then GOLD else ORANGE,
			Size = Vector3.new(2.15, 0.14, 0.4) * scale,
		}, CFrame.new(0, 0.86 * scale, -0.78 * scale) * CFrame.Angles(math.rad(-12), 0, 0))
		for _, piece in { visor, stripe } do
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = piece
		end
		-- Aletas barridas hacia atrás: más largas con rango
		for _, s in { -1, 1 } do
			local fin = weld(head, folder, {
				Name = "ScoutFin",
				Material = Enum.Material.Neon,
				Color = ORANGE,
				Size = Vector3.new(0.14, 0.42, 1.3 * grow) * scale,
			}, CFrame.new(s * 0.62 * scale, 1.0 * scale, 0.35 * scale) * CFrame.Angles(math.rad(22), math.rad(s * 14), math.rad(s * -18)))
			table.insert(fins, fin)
		end
	end

	-- Estela en el abdomen y el brillo del impulso
	local trail, light, sparks
	local abdomen = character:FindFirstChild("Abdomen")
	if abdomen and abdomen:IsA("BasePart") then
		local a0 = Instance.new("Attachment")
		a0.Name = "ScoutTrailTop"
		a0.Position = Vector3.new(0, 0.55 * scale, 0.6 * scale)
		a0.Parent = abdomen
		local a1 = Instance.new("Attachment")
		a1.Name = "ScoutTrailBottom"
		a1.Position = Vector3.new(0, -0.45 * scale, 0.6 * scale)
		a1.Parent = abdomen
		trail = Instance.new("Trail")
		trail.Name = "ScoutTrail"
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(if mastered then GOLD else ORANGE, WHITE)
		trail.Transparency = NumberSequence.new(0.6, 1)
		trail.Lifetime = 0.15 + rank * 0.015
		trail.LightEmission = 0.7
		trail.FaceCamera = true
		trail.Parent = folder
		local holder = weld(abdomen, folder, { Name = "ScoutGlow", Transparency = 1, Size = Vector3.one * 0.2 }, CFrame.new(0, 0, 0.9 * scale))
		light = Instance.new("PointLight")
		light.Color = HOT
		light.Range = 8
		light.Brightness = 0
		light.Shadows = false
		light.Parent = holder
		sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(WHITE, ORANGE)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.35 * scale, 0)
		sparks.Lifetime = NumberRange.new(0.2, 0.4)
		sparks.Speed = NumberRange.new(2, 5)
		sparks.SpreadAngle = Vector2.new(40, 40)
		sparks.EmissionDirection = Enum.NormalId.Back
		sparks.Rate = 0
		sparks.Parent = holder
		-- Los attachments viven en el abdomen: se van con la limpieza
		a0:SetAttribute("ScoutAura", true)
		a1:SetAttribute("ScoutAura", true)
		folder.Destroying:Connect(function()
			a0:Destroy()
			a1:Destroy()
		end)
	end

	-- El impulso (atributo de la dueña) hace crecer la estela, el brillo y las chispas
	local shown = -1
	local connection = RunService.RenderStepped:Connect(function()
		local charge = if owner then tonumber(owner:GetAttribute(CHARGE_ATTR)) or 0 else 0
		if math.abs(charge - shown) < 0.04 and charge < 1 then
			return
		end
		shown = charge
		local full = charge >= 1
		local pulse = if full then 0.5 + 0.5 * math.sin(os.clock() * 14) else 0
		if trail then
			trail.Lifetime = 0.15 + rank * 0.015 + charge * 0.55
			trail.Transparency = NumberSequence.new(0.6 - charge * 0.5, 1)
		end
		if light then
			light.Brightness = charge * 2.5 + pulse
		end
		if sparks then
			sparks.Rate = if charge > 0.2 then charge * 30 else 0
		end
		for _, fin in fins do
			fin.Color = ORANGE:Lerp(WHITE, charge * 0.6 + pulse * 0.3)
		end
	end)

	local gone = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			connection:Disconnect()
			folder:Destroy()
		end
	end)
	return function()
		connection:Disconnect()
		gone:Disconnect()
		folder:Destroy()
	end
end

----------------------------------------------------------------------------------------------------
-- Emblema: doble flecha (») naranja sobre un disco blanco

local function emblem(parent: GuiObject, color: Color3)
	local disc = Instance.new("Frame")
	disc.Name = "ScoutEmblem"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.86, 0.86)
	disc.BackgroundColor3 = WHITE
	disc.BorderSizePixel = 0
	disc.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = disc
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Parent = disc

	local function bar(x: number, y: number, rotation: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromScale(0.34, 0.13)
		f.Position = UDim2.fromScale(x, y)
		f.Rotation = rotation
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Parent = disc
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Color = INK
		s.Thickness = 2.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
	end
	for _, x in { 0.36, 0.6 } do
		bar(x, 0.39, 40)
		bar(x, 0.61, -40)
	end
end

return {
	fx = fx,
	cast = cast,
	aura = aura,
	emblem = emblem,
}
