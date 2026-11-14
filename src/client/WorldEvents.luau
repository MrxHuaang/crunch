-- Eventos del servidor en el cliente: tira de aviso con cuenta atrás, migas doradas que caen
-- y rebotan, y el banquete gigante con su barra compartida. Todo se anima aquí a partir de
-- los tiempos y posiciones que manda el servidor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)

local WorldEvents = {}

local player = Players.LocalPlayer
local rng = Random.new()

local FLAT = Vector3.new(1, 0, 1)
local GROUND = Config.GroundY
local GOLD = Color3.fromRGB(255, 196, 40)
local GOLD_DARK = Color3.fromRGB(236, 158, 24)
local GOLD_SHINE = Color3.fromRGB(255, 246, 190)
local FALL_HEIGHT = 70
local CAPTION = 102 -- alto de la cabecera del HUD (diseño, misma escala): la tira cae justo debajo
local STRIP_TIME = 4 -- la tira grande se ve como mucho esto; luego queda la pastilla de arriba
local RESULT_TIME = 5 -- el resultado se ve esto y se va

local remote: RemoteEvent

-- Tira de aviso
local holder: Frame
local slide: Frame
local fit: UIScale
local title: TextLabel
local sub: TextLabel
local shown = false
local stripUntil = 0 -- hasta cuándo se ve la tira grande (os.clock)

-- Pastilla compacta junto a la caja de Comida: nombre · tiempo · lo tuyo
local pill: TextLabel
local pillPunch: UIScale
local pillCount = 0

local phase = "idle" -- "idle" | "announce" | "live" | "result"
local info = nil
local resultUntil = 0
local myCrumbs = 0
local myBites = 0

-- Migas
local crumbFolder: Model
local crumbs: { [number]: any } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function inLobby(): boolean
	local root = rootPart()
	return root ~= nil and (root.Position * FLAT).Magnitude <= Config.Map.LobbyRadius + 5
end

local function nearCamera(position: Vector3, distance: number): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude < distance
end

local function shake(seconds: number, power: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	task.spawn(function()
		local finish = os.clock() + seconds
		while os.clock() < finish and humanoid.Parent do
			local k = (finish - os.clock()) / seconds
			humanoid.CameraOffset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), 0) * power * k
			RunService.RenderStepped:Wait()
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

------------------------------------------------------------------------------------------
-- Tira de aviso: papel torcido que entra por la izquierda bajo el rótulo de comida
------------------------------------------------------------------------------------------

local function place()
	holder.Position = UDim2.new(0.5, 0, 0, 6 + CAPTION * fit.Scale)
end

local function buildStrip()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldEventGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")

	holder = Comic.frame(gui)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Size = UDim2.fromOffset(400, 58)
	fit = Hud.fitScale(holder)
	fit:GetPropertyChangedSignal("Scale"):Connect(place)
	place()

	slide = Comic.frame(holder)
	slide.Size = UDim2.fromScale(1, 1)
	slide.Position = UDim2.fromScale(-3, 0)
	slide.Visible = false

	local box, face = Comic.box(slide, UDim2.fromScale(1, 1), Comic.Paper, 4)
	box.Rotation = -2
	Comic.halftone(face, Comic.Yellow, 0)

	-- Pegatina roja en la esquina
	local tag = Comic.frame(box, Comic.Red)
	tag.Size = UDim2.fromOffset(70, 22)
	tag.Position = UDim2.fromOffset(-12, -11)
	tag.Rotation = -8
	tag.ZIndex = 3
	Comic.ink(tag, 3)
	local tagLabel = Comic.label(tag, "¡Evento!", Comic.Display, 16, Comic.Paper)
	tagLabel.Size = UDim2.fromScale(1, 1)
	tagLabel.ZIndex = 4
	Comic.ink(tagLabel, 2)
	Comic.boil(tag, 2)

	title = Comic.label(face, "", Comic.Display, 24, Comic.Ink)
	title.Position = UDim2.fromOffset(14, 4)
	title.Size = UDim2.new(1, -28, 0, 28)
	title.TextScaled = true
	title.ZIndex = 2
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MaxTextSize = 24
	titleLimit.Parent = title

	sub = Comic.label(face, "", Comic.Body, 16, Comic.Ink)
	sub.Position = UDim2.fromOffset(14, 32)
	sub.Size = UDim2.new(1, -28, 0, 20)
	sub.TextScaled = true
	sub.ZIndex = 2
	local subLimit = Instance.new("UITextSizeConstraint")
	subLimit.MaxTextSize = 16
	subLimit.Parent = sub

	-- Pastilla: vive en el hueco a la derecha de la Comida (fuera del centro de la pantalla)
	pill = Comic.label(Hud.dock(), "", Comic.Display, 17, Comic.Ink)
	pill.Name = "EventPill"
	pill.Size = UDim2.fromOffset(0, 24)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundTransparency = 0
	pill.BackgroundColor3 = Comic.Yellow
	pill.Rotation = 2
	pill.Visible = false
	Comic.ink(pill, 3, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = pill
	local pillLimit = Instance.new("UISizeConstraint")
	pillLimit.MaxSize = Vector2.new(260, 24)
	pillLimit.Parent = pill
	pillPunch = Instance.new("UIScale")
	pillPunch.Parent = pill
end

local function slideIn()
	if shown then
		return
	end
	shown = true
	slide.Visible = true
	slide.Position = UDim2.fromScale(-3, 0)
	TweenService:Create(slide, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
end

local function slideOut()
	if not shown then
		return
	end
	shown = false
	local tween = TweenService:Create(slide, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Position = UDim2.fromScale(3, 0) })
	tween.Completed:Once(function()
		if not shown then
			slide.Visible = false
		end
	end)
	tween:Play()
end

local function secondsTo(t: number): number
	return math.max(0, math.ceil(t - now()))
end

-- Tira grande solo unos segundos (anuncio, inicio, resultado); el resto del evento,
-- una pastilla pequeña arriba con lo esencial: nombre, tiempo y lo que llevas.
local function refreshStrip()
	local pillText = nil
	if phase == "announce" and info then
		local startsIn = secondsTo(info.startAt)
		sub.Text = "Empieza en " .. startsIn .. " s · ven al jardín"
		pillText = info.name .. " · en " .. startsIn .. " s"
	elseif phase == "live" and info then
		local left = secondsTo(info.endAt)
		local count = if info.kind == "rain" then myCrumbs else myBites
		if info.kind == "rain" then
			sub.Text = "Pisa las migas doradas · llevas " .. myCrumbs .. " · " .. left .. " s"
		else
			sub.Text = "Ponte al lado y come · tus bocados: " .. myBites .. " · " .. left .. " s"
		end
		pillText = info.name .. " · " .. left .. " s · " .. count .. (if info.kind == "rain" then " migas" else " ñam")
		if count > pillCount and pill.Visible then
			Comic.punch(pillPunch, 1.25)
		end
		pillCount = count
	elseif phase == "result" and os.clock() > resultUntil then
		phase = "idle"
		slideOut()
	end

	if phase == "announce" or phase == "live" then
		if os.clock() > stripUntil then
			slideOut()
		end
	end
	local showPill = pillText ~= nil and not shown
	if showPill then
		pill.Text = pillText
	end
	if pill.Visible ~= showPill then
		pill.Visible = showPill
	end
end

------------------------------------------------------------------------------------------
-- Migas doradas
------------------------------------------------------------------------------------------

local function bit(parent: Instance, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

local function addCrumb(id: number, pos: Vector3, landAt: number)
	if crumbs[id] then
		return
	end
	local model = Instance.new("Model")
	model.Name = "MigaDorada"
	local body = bit(model, Vector3.new(2, 1.6, 1.8), GOLD)
	local chip = bit(model, Vector3.new(1, 0.8, 0.9), GOLD_DARK)
	chip.CFrame = body.CFrame * CFrame.new(0.7, -0.25, 0.45)
	local shine = bit(model, Vector3.new(0.7, 0.3, 0.55), GOLD_SHINE)
	shine.CFrame = body.CFrame * CFrame.new(-0.4, 0.62, -0.2) * CFrame.Angles(0, 0, math.rad(18))
	model.PrimaryPart = body

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 9
	light.Brightness = 2
	light.Parent = body

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(GOLD_SHINE)
	sparkle.LightEmission = 1
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Lifetime = NumberRange.new(0.5, 0.8)
	sparkle.Rate = 5
	sparkle.Speed = NumberRange.new(2, 4)
	sparkle.SpreadAngle = Vector2.new(60, 60)
	sparkle.Parent = body

	model:PivotTo(CFrame.new(pos + Vector3.new(0, FALL_HEIGHT, 0)))
	model.Parent = crumbFolder
	crumbs[id] = {
		model = model,
		parts = { body, chip, shine },
		pos = pos,
		landAt = landAt,
		seed = rng:NextNumber(0, 10),
		fall = if info and info.fall then info.fall else 1.4,
		life = if info and info.life then info.life else 20,
		landed = false,
	}
end

local function removeCrumb(id: number, pop: boolean)
	local crumb = crumbs[id]
	if not crumb then
		return
	end
	crumbs[id] = nil
	if not pop then
		crumb.model:Destroy()
		return
	end
	local quick = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	for _, part in crumb.parts do
		TweenService:Create(part, quick, { Size = Vector3.zero }):Play()
	end
	task.delay(0.2, function()
		crumb.model:Destroy()
	end)
end

local function clearCrumbs()
	for id in crumbs do
		removeCrumb(id, true)
	end
end

-- Caída con aceleración, dos botecitos y luego flotar girando
local function animateCrumbs()
	local t0 = now()
	local clock = os.clock()
	for id, crumb in crumbs do
		local t = t0 - crumb.landAt
		if t > crumb.life then
			removeCrumb(id, true)
			continue
		end
		local y
		if t < 0 then
			local k = math.clamp(1 + t / crumb.fall, 0, 1)
			y = FALL_HEIGHT * (1 - k * k)
		elseif t < 1.3 then
			if not crumb.landed then
				crumb.landed = true
				if nearCamera(crumb.pos, 70) then
					Sfx.pop(1.6 + rng:NextNumber(0, 0.3))
				end
			end
			y = 3 * math.abs(math.sin(t * math.pi / 0.42)) * math.exp(-t * 2.4)
		else
			y = 0.35 + 0.25 * math.sin(clock * 3 + crumb.seed)
		end
		-- Parpadea los últimos 3 segundos
		local blink = t > crumb.life - 3 and math.floor(clock * 8) % 2 == 0
		for _, part in crumb.parts do
			part.LocalTransparencyModifier = if blink then 0.7 else 0
		end
		crumb.model:PivotTo(CFrame.new(crumb.pos + Vector3.new(0, 0.9 + y, 0)) * CFrame.Angles(0, clock * 1.6 + crumb.seed, 0.25))
	end
end

------------------------------------------------------------------------------------------
-- Banquete
------------------------------------------------------------------------------------------

local function watchFeast(feast)
	local folder = Workspace:WaitForChild("WorldEvents", 10)
	local model = folder and folder:WaitForChild("Banquete", 10)
	if not model or not model:IsA("Model") then
		return
	end
	local home = CFrame.new(model:GetAttribute("Home") or Vector3.new(0, GROUND, 0))
	local landAt = feast.startAt + (feast.land or 1)
	local connections = {}

	-- Cartel con la barra compartida, sobre la comida
	local anchor = Instance.new("Part")
	anchor.Name = "BanqueteCartel"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = Workspace

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(200, 56)
	sign.AlwaysOnTop = true
	sign.LightInfluence = 0
	sign.MaxDistance = 400
	sign.Adornee = anchor
	sign.Parent = anchor

	local label = Comic.label(sign, "", Comic.Display, 21, Comic.Paper)
	label.Size = UDim2.new(1, 0, 0, 27)
	Comic.ink(label, 3)

	local bar, barFace = Comic.box(sign, UDim2.new(1, -12, 0, 16), Comic.Paper, 3)
	bar.Position = UDim2.fromOffset(4, 33)
	local fill = Comic.frame(barFace, Comic.Yellow)
	fill.Size = UDim2.fromScale(1, 1)

	local total = model:GetAttribute("Total") or 1
	local function update()
		local left = model:GetAttribute("Left") or total
		fill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
		label.Text = if left > 0 then "Quedan " .. left .. " bocados" else "¡Ni las migas!"
	end
	update()
	table.insert(connections, model:GetAttributeChangedSignal("Left"):Connect(update))

	-- Tus bocados: cada uno, un ñam junto a ti
	local key = "B_" .. player.UserId
	table.insert(connections, model:GetAttributeChangedSignal(key):Connect(function()
		local count = model:GetAttribute(key) or 0
		if count > myBites then
			myBites = count
			local root = rootPart()
			if root then
				local toward = ((home.Position - root.Position) * FLAT)
				local nudge = if toward.Magnitude > 0.1 then toward.Unit * 2 else Vector3.zero
				Fx.nibble(root.Position + nudge + Vector3.new(0, 1, 0))
			end
			Sfx.bite(false)
		end
	end))

	-- Cada pieza que pierde sale volando (física local, nada en el servidor)
	table.insert(connections, model.DescendantRemoving:Connect(function(instance)
		if instance:IsA("BasePart") and instance.Name == "Piece" and nearCamera(instance.Position, 160) then
			Fx.chunk(instance)
		end
	end))

	local function placeSign()
		local ok, size = pcall(function()
			return model:GetExtentsSize()
		end)
		local height = if ok then size.Y else 20
		anchor.Position = home.Position + Vector3.new(0, height + 5, 0)
	end

	local function land()
		model:PivotTo(home)
		placeSign()
		if nearCamera(home.Position, 260) then
			Fx.burst(home.Position + Vector3.new(0, 10, 0), "¡BANQUETE!", Comic.Yellow, 320)
			Sfx.fanfare()
		end
		local root = rootPart()
		if root and ((root.Position - home.Position) * FLAT).Magnitude < 90 then
			shake(0.45, 1.2)
		end
	end

	-- Cae del cielo con aceleración (el servidor lo deja en su sitio al aterrizar)
	if now() < landAt then
		local fall = feast.land or 1
		anchor.Position = home.Position + Vector3.new(0, 200, 0)
		local drop
		drop = RunService.RenderStepped:Connect(function()
			if not model.Parent then
				drop:Disconnect()
				return
			end
			local k = math.clamp(1 - (landAt - now()) / fall, 0, 1)
			if k >= 1 then
				drop:Disconnect()
				land()
				return
			end
			model:PivotTo(home + Vector3.new(0, 90 * (1 - k * k), 0))
		end)
		table.insert(connections, drop)
	else
		placeSign()
	end

	while model.Parent do
		task.wait(0.5)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	anchor:Destroy()
end

------------------------------------------------------------------------------------------
-- Mensajes del servidor
------------------------------------------------------------------------------------------

local function podiumText(list): string
	local parts = {}
	for i, entry in list do
		table.insert(parts, i .. ". " .. entry.name .. " " .. entry.count)
	end
	return table.concat(parts, " · ")
end

local function onAnnounce(payload)
	info = payload
	phase = "announce"
	myCrumbs = 0
	myBites = 0
	title.Text = payload.name
	stripUntil = os.clock() + STRIP_TIME
	pillCount = 0
	slideIn()
	refreshStrip()
	Sfx.pop(1.3)
end

local function onStart(payload)
	local fresh = phase ~= "live"
	info = payload
	phase = "live"
	title.Text = payload.name
	if fresh then
		stripUntil = os.clock() + STRIP_TIME
		pillCount = 0
		slideIn()
	end
	refreshStrip()
	if fresh then
		Sfx.fanfare()
		Fx.speed(0.6)
		if not inLobby() then
			Bubble.flash(if payload.kind == "rain" then "¡Llueven migas doradas en el jardín!" else "¡Banquete gigante en el jardín!", 5)
		end
	end
	if fresh and payload.kind == "feast" then
		task.spawn(watchFeast, payload)
	end
end

local function onEnd(result)
	clearCrumbs()
	phase = "result"
	resultUntil = os.clock() + RESULT_TIME
	pill.Visible = false
	slideIn()
	local mine = result.mine
	if result.failed then
		title.Text = "Evento cancelado"
		sub.Text = "Algo salió mal. ¡A la próxima!"
	elseif result.kind == "rain" then
		title.Text = if mine then "¡Fin de la lluvia! +" .. Format.short(mine.gain) else "¡Fin de la lluvia!"
		local podium = podiumText(result.ranking)
		if mine then
			sub.Text = "Cogiste " .. mine.count .. (if mine.count == 1 then " miga" else " migas") .. (if podium ~= "" then " · " .. podium else "")
		else
			sub.Text = if podium ~= "" then podium else "Nadie pilló ninguna. ¡A la próxima!"
		end
	else
		local head = if result.finished then "¡Banquete terminado!" else "¡Se acabó el tiempo!"
		title.Text = if mine then head .. " +" .. Format.short(mine.gain) else head
		local podium = podiumText(result.ranking)
		sub.Text = if podium ~= "" then podium else "Nadie llegó a probarlo"
		if mine then
			local root = rootPart()
			if root then
				Fx.burst(root.Position + Vector3.new(0, 3, 0), (if mine.top then "¡GLOTONA!\n+" else "+") .. Format.short(mine.gain), Comic.Yellow, 260)
			end
			Sfx.fanfare()
		end
	end
end

local function onCrumbTaken(id: number, userId: number, amount: number)
	local crumb = crumbs[id]
	local position = if crumb then crumb.pos + Vector3.new(0, 1, 0) else nil
	removeCrumb(id, true)
	if userId == player.UserId then
		myCrumbs += 1
		refreshStrip()
		local root = rootPart()
		local at = position or (root and root.Position)
		if at then
			Fx.burst(at, "+" .. Format.short(amount), Comic.Yellow, 170)
		end
		Sfx.pop(1.5)
	elseif position and nearCamera(position, 60) then
		Sfx.pop(1.2)
	end
end

function WorldEvents.start(remotes: Folder)
	remote = remotes:WaitForChild("WorldEvent") :: RemoteEvent

	buildStrip()

	crumbFolder = Instance.new("Model")
	crumbFolder.Name = "MigasDoradas"
	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(20, 16, 16)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = crumbFolder
	crumbFolder.Parent = Workspace

	remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
		if kind == "Announce" then
			onAnnounce(a)
		elseif kind == "Start" then
			onStart(a)
		elseif kind == "Crumb" then
			addCrumb(a, b, c)
		elseif kind == "CrumbTaken" then
			onCrumbTaken(a, b, c)
		elseif kind == "End" then
			onEnd(a)
		end
	end)
	remote:FireServer("Hello")

	RunService.RenderStepped:Connect(function()
		if next(crumbs) ~= nil then
			animateCrumbs()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			refreshStrip()
		end
	end)
end

return WorldEvents
