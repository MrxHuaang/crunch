-- El jardín vivo (ver src/server/Garden.luau): mariposas con regalo, hora feliz, pan gigante y los
-- juguetes (setas saltarinas y dientes de león). Nada de interfaz fija: todo pasa en el mundo, con
-- estallidos, sonidos y frases cortas de la hormiga.
-- Los juguetes se animan aquí con las posiciones de todas las hormigas, así todo el mundo ve el
-- mismo salto; el empujón hacia arriba solo se lo da cada cliente a su propia hormiga.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local Abilities = require(script.Parent.Abilities)
local Bubble = require(script.Parent.Bubble)
local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local Garden = {}

local G = Config.Garden
local FLAT = Vector3.new(1, 0, 1)
local GROUND = Config.GroundY
local GIFT_DROP = 1 -- igual que en el servidor
local NEAR = 140 -- studs de la cámara a los que se ven y oyen los momentos
local GOLD = Color3.fromRGB(255, 196, 40)

local player = Players.LocalPlayer
local rng = Random.new()
local fxFolder: Folder
local gifts: { [number]: any } = {}

local function camDistance(position: Vector3): number
	local camera = Workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - position).Magnitude else math.huge
end

local function myRoot(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function inGarden(): boolean
	local root = myRoot()
	return root ~= nil and (root.Position * FLAT).Magnitude < Config.Map.LobbyRadius + 8
end

local function bit(parent: Instance, size: Vector3, color: Color3, sphere: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	if sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------------------------------
-- Mariposa con regalo

local WING_COLORS = {
	{ Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 210, 63) },
	{ Color3.fromRGB(62, 193, 243), Color3.fromRGB(160, 96, 230) },
	{ Color3.fromRGB(255, 130, 180), Color3.fromRGB(255, 250, 235) },
}
local BOX_COLORS = { Color3.fromRGB(230, 57, 70), Color3.fromRGB(62, 140, 243), Color3.fromRGB(110, 200, 90) }

local function buildButterfly(): any
	local model = Instance.new("Model")
	model.Name = "Butterfly"
	local colors = WING_COLORS[rng:NextInteger(1, #WING_COLORS)]
	local body = bit(model, Vector3.new(0.6, 0.6, 2.4), Color3.fromRGB(46, 34, 46), true)
	local wings = {}
	for _, side in { -1, 1 } do
		table.insert(wings, { part = bit(model, Vector3.new(3, 0.12, 2.4), colors[1], true), side = side, offset = Vector3.new(1.5, 0, -0.5) })
		table.insert(wings, { part = bit(model, Vector3.new(2.2, 0.12, 1.8), colors[2], true), side = side, offset = Vector3.new(1.1, 0, 1.1) })
	end
	model.Parent = fxFolder
	return { model = model, body = body, wings = wings }
end

local function poseButterfly(b, cframe: CFrame, flap: number)
	b.body.CFrame = cframe
	for _, wing in b.wings do
		local hinge = cframe * CFrame.Angles(0, 0, wing.side * flap)
		wing.part.CFrame = hinge * CFrame.new(wing.offset.X * wing.side, wing.offset.Y, wing.offset.Z)
	end
end

local function buildBox(): any
	local model = Instance.new("Model")
	model.Name = "Gift"
	local color = BOX_COLORS[rng:NextInteger(1, #BOX_COLORS)]
	local ribbon = Color3.fromRGB(255, 210, 63)
	local parts = {}
	local function add(size: Vector3, c: Color3, offset: CFrame, sphere: boolean?)
		table.insert(parts, { part = bit(model, size, c, sphere), offset = offset })
	end
	add(Vector3.new(2.2, 2.2, 2.2), color, CFrame.new())
	add(Vector3.new(2.3, 2.3, 0.45), ribbon, CFrame.new())
	add(Vector3.new(0.45, 2.3, 2.3), ribbon, CFrame.new())
	add(Vector3.new(0.9, 0.7, 0.9), ribbon, CFrame.new(-0.45, 1.4, 0) * CFrame.Angles(0, 0, 0.5), true)
	add(Vector3.new(0.9, 0.7, 0.9), ribbon, CFrame.new(0.45, 1.4, 0) * CFrame.Angles(0, 0, -0.5), true)
	parts[1].part.CastShadow = true
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 230, 150)
	light.Range = 10
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = parts[1].part
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = Color3.fromRGB(255, 236, 140)
	sparkles.Parent = parts[1].part
	model.Parent = fxFolder
	return { model = model, parts = parts }
end

local function poseBox(box, cframe: CFrame)
	for _, item in box.parts do
		item.part.CFrame = cframe * item.offset
	end
end

local function dropGift(id: number)
	local gift = gifts[id]
	if not gift then
		return
	end
	gifts[id] = nil
	if gift.conn then
		gift.conn:Disconnect()
	end
	if gift.box then
		gift.box.model:Destroy()
	end
	if gift.fly then
		gift.fly.model:Destroy()
	end
end

local function startGift(id: number, from: Vector3, to: Vector3, flyTime: number, landAt: number)
	dropGift(id)
	local gift = { pos = to, box = buildBox(), fly = nil, landed = false }
	gifts[id] = gift
	local hover = to + Vector3.new(0, 12, 0)
	local flyStart = landAt - GIFT_DROP - flyTime
	local late = State.now() >= landAt
	if not late then
		gift.fly = buildButterfly()
	end
	local away = (hover + (hover - from).Unit * 60 * FLAT + Vector3.new(0, 30, 0))
	local seed = rng:NextNumber(0, 10)
	gift.conn = RunService.RenderStepped:Connect(function()
		local now = State.now()
		local flap = math.sin(os.clock() * 22) * 0.9
		local b = gift.fly
		if now < landAt - GIFT_DROP then
			-- Vuela hacia el sitio con un vaivén, el regalo colgando debajo
			local a = math.clamp((now - flyStart) / flyTime, 0, 1)
			local eased = a * a * (3 - 2 * a)
			local position = from:Lerp(hover, eased) + Vector3.new(math.sin(os.clock() * 2 + seed) * 2, math.sin(os.clock() * 5) * 1.2, 0)
			local look = ((hover - from) * FLAT)
			local cframe = CFrame.lookAt(position, position + (if look.Magnitude > 0.1 then look else Vector3.new(0, 0, -1)))
			if b then
				poseButterfly(b, cframe, flap)
			end
			poseBox(gift.box, CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, os.clock() * 1.5, 0))
		else
			-- Suelta el regalo y se va volando
			if b then
				local a = math.clamp((now - (landAt - GIFT_DROP)) / 3, 0, 1)
				local position = hover:Lerp(away, a * a)
				poseButterfly(b, CFrame.lookAt(position, position + (away - hover)), flap)
				if a >= 1 then
					b.model:Destroy()
					gift.fly = nil
				end
			end
			local fall = math.clamp((now - (landAt - GIFT_DROP)) / GIFT_DROP, 0, 1)
			local height = 1.1 + (1 - fall * fall) * (12 - 2.6 - 1.1)
			local bob = if fall >= 1 then math.sin(os.clock() * 3) * 0.15 else 0
			poseBox(gift.box, CFrame.new(to + Vector3.new(0, height + bob, 0)) * CFrame.Angles(0, os.clock() * 1.2, 0))
			if fall >= 1 and not gift.landed then
				gift.landed = true
				if not late and camDistance(to) < NEAR then
					Sfx.pop(0.8)
					Fx.crumbs(to + Vector3.new(0, 0.5, 0), Comic.Yellow, 8)
					Fx.burst(to + Vector3.new(0, 2, 0), "¡UN REGALO!", Comic.Red, 220)
				end
				local root = myRoot()
				if not late and root and ((root.Position - to) * FLAT).Magnitude < 80 then
					Bubble.flash("¡Un regalo! Para quien llegue primero", 3)
				end
			end
		end
	end)
end

local function giftTaken(id: number, userId: number, amount: number, surprise: string?)
	local gift = gifts[id]
	local position = if gift then gift.pos else nil
	dropGift(id)
	if position and camDistance(position) < NEAR then
		Fx.burst(position + Vector3.new(0, 2, 0), "¡REGALO!", Comic.Red, 220)
		Fx.crumbs(position + Vector3.new(0, 1, 0), Comic.Yellow, 14)
	end
	if userId ~= player.UserId then
		if position and camDistance(position) < NEAR then
			Sfx.pop(1.2)
		end
		return
	end
	local root = myRoot()
	if root then
		Fx.burst(root.Position + Vector3.new(0, 3, 0), "+" .. Format.short(amount), Comic.Yellow, 240)
	end
	Sfx.fanfare()
	Hud.punchFood()
	if surprise == "speed" then
		Fx.speed(1.5)
		Bubble.flash("¡Patas ligeras! Corro más durante " .. G.Gift.SpeedTime .. " s", 4)
	elseif surprise == "jelly" then
		Bubble.flash("¡Sorpresa! Una gota de jalea real", 4)
	else
		Bubble.flash("¡Un regalo para mí!", 3)
	end
end

---------------------------------------------------------------------------------------------------
-- Hora feliz

local happyToken = 0

local function startHappy(untilTime: number)
	if untilTime <= State.now() then
		return
	end
	happyToken += 1
	local token = happyToken
	local foods = Workspace:FindFirstChild("Food")
	local found = foods and foods:FindFirstChild("InkOutline")
	local outline: Highlight? = if found and found:IsA("Highlight") then found else nil
	local original = if outline then outline.OutlineColor else nil
	if inGarden() then
		local root = myRoot()
		if root then
			Fx.burst(root.Position + Vector3.new(0, 3, 0), "¡HORA FELIZ!", Comic.Yellow, 300)
		end
		Sfx.fanfare()
		Bubble.flash("¡Hora feliz! La comida del jardín vale doble", 4)
	end
	task.spawn(function()
		if outline then
			outline.OutlineColor = GOLD -- la comida se perfila en oro mientras dura
		end
		while happyToken == token and State.now() < untilTime do
			-- Un "x2" sobre la comida del jardín más cercana, para que se note dónde rinde
			local root = myRoot()
			if root and foods and inGarden() then
				local best, bestDistance = nil, 45
				for _, food in foods:GetChildren() do
					if food:IsA("Model") then
						local def = Config.FoodById[food:GetAttribute("FoodId") or ""]
						if def and def.zone == 1 then
							local distance = ((food:GetPivot().Position - root.Position) * FLAT).Magnitude
							if distance < bestDistance then
								best = food
								bestDistance = distance
							end
						end
					end
				end
				if best then
					Fx.burst(best:GetPivot().Position + Vector3.new(0, 2, 0), "x2", Comic.Yellow, 150)
				end
			end
			task.wait(2.5)
		end
		if happyToken == token and outline and original then
			outline.OutlineColor = original
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Pan gigante

local function loafLanded(position: Vector3)
	task.delay(0.65, function()
		if camDistance(position) < NEAR + 40 then
			Fx.shake(math.clamp(0.45 - camDistance(position) / 400, 0.1, 0.4))
			Fx.burst(position + Vector3.new(0, 7, 0), "¡PAN GIGANTE!", Comic.Yellow, 300)
			Fx.crumbs(position + Vector3.new(0, 1, 0), Comic.Crumb, 20)
			Sfx.bite(true)
			Sfx.pop(0.6)
		end
		if inGarden() then
			Bubble.flash("¡Un pan gigante! A morderlo antes de que vuele", 4)
		end
	end)
end

local function loafGone(position: Vector3, eaten: boolean)
	if camDistance(position) < NEAR then
		Fx.burst(position + Vector3.new(0, 4, 0), if eaten then "¡NI LAS MIGAS!" else "¡ADIÓS, PAN!", if eaten then Comic.Green else Comic.Cyan, 220)
		Fx.crumbs(position + Vector3.new(0, 1, 0), Comic.Crumb, 12)
		Sfx.pop(if eaten then 1.4 else 0.8)
	end
end

---------------------------------------------------------------------------------------------------
-- Juguetes

local mushrooms = {}
local dandelions = {}

local function readMushroom(model: Model)
	local base = model:GetPivot().Position
	local entry = {
		base = base,
		radius = (model:GetAttribute("Radius") :: number?) or 3.5,
		top = (model:GetAttribute("Top") :: number?) or 4,
		parts = {},
		t0 = -math.huge,
		on = {} :: { [Player]: boolean },
		burstAt = 0,
	}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (child.Name == "Cap" or child.Name == "Spot") then
			table.insert(entry.parts, { part = child, cframe = child.CFrame, size = child.Size })
		end
	end
	table.insert(mushrooms, entry)
end

local function readDandelion(model: Model)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	table.insert(dandelions, {
		base = model:GetPivot().Position,
		head = head,
		size = head.Size,
		alpha = head.Transparency,
		blownUntil = 0,
	})
end

local function squash(entry, now: number)
	local tau = now - entry.t0
	if tau > 1.3 then
		if entry.resting ~= true then
			entry.resting = true
			for _, item in entry.parts do
				item.part.CFrame = item.cframe
				item.part.Size = item.size
			end
		end
		return
	end
	entry.resting = false
	local s = 0.45 * math.exp(-5 * tau) * math.cos(16 * tau)
	local wide = 1 + 0.35 * s
	local stretch = Vector3.new(wide, 1 - s, wide)
	for _, item in entry.parts do
		local rel = item.cframe.Position - entry.base
		item.part.CFrame = CFrame.new(entry.base + rel * stretch) * item.cframe.Rotation
		item.part.Size = item.size * stretch
	end
end

local function launch(root: BasePart)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X * 1.2, G.Mushroom.Launch, v.Z * 1.2)
end

local function blow(entry, now: number)
	entry.blownUntil = now + 25
	local head = entry.head
	local from = head.Position
	head.Transparency = 1
	if camDistance(from) < NEAR then
		Sfx.pop(1.7)
		for _ = 1, 14 do
			local seedPart = bit(fxFolder, Vector3.new(0.35, 0.35, 0.35), Color3.fromRGB(255, 255, 250), true)
			seedPart.Position = from + Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.6, 0.8), rng:NextNumber(-1, 1))
			local time = rng:NextNumber(2.4, 3.6)
			local goal = seedPart.Position + Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(6, 14), rng:NextNumber(-9, 9))
			TweenService:Create(seedPart, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Position = goal, Transparency = 1 }):Play()
			task.delay(time + 0.1, function()
				seedPart:Destroy()
			end)
		end
	end
end

local function regrow(entry)
	local head = entry.head
	head.Size = entry.size * 0.25
	head.Transparency = entry.alpha
	TweenService:Create(head, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = entry.size }):Play()
end

local function updateToys()
	local now = os.clock()
	local roots = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			roots[other] = root
		end
	end
	for _, entry in mushrooms do
		for other, root in roots do
			local offset = root.Position - entry.base
			local on = (offset * FLAT).Magnitude <= entry.radius * 0.9 and offset.Y <= entry.top + 2.5 and offset.Y > -2
			if on and not entry.on[other] then
				entry.t0 = now
				if other == player then
					launch(root)
				end
				if now >= entry.burstAt and camDistance(entry.base) < NEAR then
					entry.burstAt = now + 0.4
					Fx.burst(entry.base + Vector3.new(0, entry.top + 2, 0), "¡BOING!", Comic.Green, 170)
					Sfx.pop(0.55)
					task.delay(0.08, Sfx.pop, 1.5)
				end
			end
			entry.on[other] = on or nil
		end
		for other in entry.on do
			if not roots[other] then
				entry.on[other] = nil
			end
		end
		squash(entry, now)
	end
	for _, entry in dandelions do
		if entry.blownUntil > 0 then
			if now >= entry.blownUntil then
				entry.blownUntil = 0
				regrow(entry)
			end
			continue
		end
		for _, root in roots do
			if ((root.Position - entry.base) * FLAT).Magnitude <= 2.4 and root.Position.Y - entry.base.Y < 9 then
				blow(entry, now)
				break
			end
		end
	end
end

---------------------------------------------------------------------------------------------------

function Garden.start(remotes: Folder)
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "GardenFx"
	fxFolder.Parent = Workspace

	-- Regalo de patas ligeras: anda más rápido un rato (encima de lo que ya pusiera Extras)
	task.delay(1, function()
		local base = Abilities.speedBoost
		Abilities.speedBoost = function(): number
			local boost = base()
			local untilTime = player:GetAttribute("GiftSpeedUntil")
			if type(untilTime) == "number" and State.now() < untilTime then
				boost *= G.Gift.SpeedMult
			end
			return boost
		end
	end)

	local remote = remotes:WaitForChild("Garden", 30) :: RemoteEvent?
	if remote then
		remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any, e: any)
			if kind == "Butterfly" then
				startGift(a, b, c, d, e)
			elseif kind == "GiftTaken" then
				giftTaken(a, b, tonumber(c) or 0, d)
			elseif kind == "GiftGone" then
				dropGift(a)
			elseif kind == "Happy" then
				startHappy(a)
			elseif kind == "Loaf" then
				loafLanded(b)
			elseif kind == "LoafGone" then
				loafGone(a, b == true)
			end
		end)
	end
	local happy = Workspace:GetAttribute("HappyUntil")
	if type(happy) == "number" then
		startHappy(happy)
	end

	local toys = Workspace:WaitForChild("GardenToys", 60)
	if not toys then
		return
	end
	local function read(child: Instance)
		if child:IsA("Model") then
			if child.Name == "Mushroom" then
				readMushroom(child)
			elseif child.Name == "Dandelion" then
				readDandelion(child)
			end
		end
	end
	for _, child in toys:GetChildren() do
		read(child)
	end
	toys.ChildAdded:Connect(function(child)
		task.wait() -- sus piezas llegan con él; un fotograma de margen
		read(child)
	end)
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(updateToys)
		if not ok then
			warn("[CRUNCH!] Garden juguetes:", err)
		end
	end)
end

return Garden
