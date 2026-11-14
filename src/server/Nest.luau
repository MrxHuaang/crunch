-- Huevo dorado y jardín de hongos: dos mejoras del árbol que viven en el suelo, junto al montículo
-- de su dueña. El huevo sale cada cierto tiempo al lado contrario del cartel; los hongos crecen en
-- tres tamaños y, maduros, brillan. Solo la dueña los coge, pisándolos.
-- Sus piezas cuelgan del modelo del hormiguero, así las contornea la misma tinta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Profiles = require(script.Parent.Profiles)

local Nest = {}

local TICK = 0.25
local EGG_REACH = 4.5
local FUNGUS_REACH = 4
local FUNGUS_GAP = 1.75 -- radio del corro de hongos (quedan a unos 3 studs entre sí)
local STAGES = { 0.3, 0.65, 1 } -- tamaño de un hongo según lo que le falta para madurar
local FLAT = Vector3.new(1, 0, 1)
local GOLD = Color3.fromRGB(255, 200, 60)
local CAP = Color3.fromRGB(190, 110, 230)
local CAP_RIPE = Color3.fromRGB(255, 120, 220)

local nests: { [Model]: any } = {} -- hormiguero -> lo que hay junto a él
local fxRemote: RemoteEvent

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function part(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, blob: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Color = color
	p.CFrame = cframe
	if blob then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

local function glow(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Sitio del huevo y de los hongos según el tamaño actual del hormiguero
local function place(nest)
	local hill = nest.hill
	local center = hill:GetPivot().Position
	local inward = (Vector3.new(0, center.Y, 0) - center).Unit
	local side = inward:Cross(Vector3.yAxis)
	local scale = hill:GetAttribute("Scale") or 1
	nest.scale = scale
	nest.eggSpot = center + (inward * 6 - side * 9.5) * scale
	local patch = center + (inward * -1 - side * 11) * scale
	nest.patch = patch
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + 0.4
		nest.spots[i] = patch + (inward * math.cos(a) + side * math.sin(a)) * FUNGUS_GAP
	end
end

-- Huevo dorado en un nido de paja: brilla de lejos
local function buildEgg(nest): Model
	local model = Instance.new("Model")
	model.Name = "GoldenEgg"
	local spot = nest.eggSpot
	local straw = { rgb(214, 168, 96), rgb(190, 140, 74), rgb(232, 196, 120) }
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part(model, Vector3.new(2.2, 1.1, 1.6), straw[i % 3 + 1], CFrame.new(spot + Vector3.new(math.cos(a) * 2.1, 0.45, math.sin(a) * 2.1)) * CFrame.Angles(0, -a, 0.2), true)
	end
	local egg = part(model, Vector3.new(3.6, 4.8, 3.6), GOLD, CFrame.new(spot + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0.1, 0, 0.12), true)
	egg.Name = "Egg"
	egg.Material = Enum.Material.Neon
	glow(egg, rgb(255, 214, 110), 20, 2.5)
	-- Brillo de juguete y unas chispas quietas alrededor
	local shine = part(model, Vector3.new(0.9, 1.5, 0.5), rgb(255, 252, 230), CFrame.new(spot + Vector3.new(-0.8, 3.4, 0)) * CFrame.Angles(0, 0, 0.4), true)
	shine.Material = Enum.Material.Neon
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + 0.6
		local spark = part(model, Vector3.new(0.6, 0.6, 0.6), rgb(255, 240, 150), CFrame.new(spot + Vector3.new(math.cos(a) * 3, 4 + (i % 2) * 1.6, math.sin(a) * 3)), true)
		spark.Material = Enum.Material.Neon
	end
	model.Parent = nest.model
	return model
end

-- Hongo de cómic: pie blanco, sombrero redondo con motas. Se construye a tamaño 1 y se escala por fase.
local function buildFungus(nest, index: number)
	local spot = nest.spots[index]
	local model = Instance.new("Model")
	model.Name = "Fungus"
	local pieces = {}
	local function piece(size: Vector3, color: Color3, offset: Vector3, blob: boolean, rotation: CFrame?)
		local p = part(model, size, color, CFrame.new(spot + offset), blob)
		table.insert(pieces, { part = p, size = size, offset = offset, rotation = rotation or CFrame.identity })
		return p
	end
	piece(Vector3.new(1.6, 2.8, 1.6), rgb(255, 240, 214), Vector3.new(0, 1.4, 0), true)
	local cap = piece(Vector3.new(4.6, 2.8, 4.6), CAP, Vector3.new(0, 3.4, 0), true)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		piece(Vector3.new(1, 0.5, 1), rgb(255, 255, 255), Vector3.new(math.cos(a) * 1.3, 4.5, math.sin(a) * 1.3), true, CFrame.Angles(math.sin(a) * 0.4, 0, -math.cos(a) * 0.4))
	end
	local light = glow(cap, rgb(255, 160, 230), 12, 1.6)
	light.Enabled = false
	model.Parent = nest.model
	return { model = model, pieces = pieces, cap = cap, light = light, spot = spot }
end

local function setStage(fungus, stage: number)
	fungus.stage = stage
	local look = fungus.look
	local k = STAGES[stage]
	for _, item in look.pieces do
		item.part.Size = item.size * k
		item.part.CFrame = CFrame.new(look.spot + item.offset * k) * item.rotation
	end
	local ripe = stage == 3
	look.cap.Material = if ripe then Enum.Material.Neon else Enum.Material.SmoothPlastic
	look.cap.Color = if ripe then CAP_RIPE else CAP
	look.light.Enabled = ripe
end

local function dropEgg(nest)
	if nest.egg then
		nest.egg:Destroy()
		nest.egg = nil
	end
	nest.hill:SetAttribute("Egg", false)
end

local function dropFungi(nest)
	for _, fungus in nest.fungi do
		if fungus.look then
			fungus.look.model:Destroy()
		end
	end
	table.clear(nest.fungi)
	if nest.soil then
		nest.soil:Destroy()
		nest.soil = nil
	end
end

local function release(hill: Model)
	local nest = nests[hill]
	if not nest then
		return
	end
	nests[hill] = nil
	nest.model:Destroy()
	if hill.Parent then
		hill:SetAttribute("Egg", false)
	end
end

local function create(hill: Model, profile)
	local model = Instance.new("Model")
	model.Name = "Nest"
	model.Parent = hill
	local nest = { hill = hill, profile = profile, model = model, spots = {}, fungi = {}, egg = nil, soil = nil }
	place(nest)
	nests[hill] = nest
	return nest
end

-- El hormiguero creció: todo se rehace en su sitio nuevo sin perder los tiempos
local function relocate(nest)
	place(nest)
	if nest.egg then
		nest.egg:Destroy()
		nest.egg = buildEgg(nest)
	end
	for i, fungus in nest.fungi do
		if fungus.look then
			fungus.look.model:Destroy()
		end
		fungus.look = buildFungus(nest, i)
		if fungus.stage > 0 then
			setStage(fungus, fungus.stage)
		end
	end
	if nest.soil then
		nest.soil.CFrame = CFrame.new(nest.patch + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
end

local function eggValue(profile): number
	local stats = profile.stats
	local zoneFood = Config.Foods[(stats.depth - 1) * 3 + 1]
	return math.max(profile.data.rate * stats.eggSeconds, 20 * stats.biteDamage * zoneFood.value) * stats.eggMult
end

local function updateEgg(nest, profile, now: number, root: BasePart?)
	local stats = profile.stats
	if stats.eggs <= 0 and not profile.eggGift then
		-- Sin la mejora (p. ej. tras enjambrar) no hay huevo
		if nest.egg then
			dropEgg(nest)
		end
		return
	end
	profile.eggAt = profile.eggAt or (now + 45)
	if not nest.egg and now >= profile.eggAt then
		nest.egg = buildEgg(nest)
		nest.hill:SetAttribute("Egg", true)
		Profiles.say(profile, "¡Hay un huevo dorado junto a mi hormiguero!", 5)
	end
	if nest.egg and root and ((root.Position - nest.eggSpot) * FLAT).Magnitude < EGG_REACH then
		local position = nest.eggSpot + Vector3.new(0, 2.5, 0)
		dropEgg(nest)
		profile.eggAt = now + stats.eggInterval
		profile.eggGift = false
		local credited = Profiles.addFood(profile, eggValue(profile))
		Profiles.push(profile)
		fxRemote:FireClient(profile.player, "Egg", position, credited)
	end
end

local function updateFungi(nest, profile, now: number, root: BasePart?)
	local stats = profile.stats
	if stats.fungus <= 0 then
		if #nest.fungi > 0 then
			dropFungi(nest)
		end
		return
	end
	if not nest.soil then
		nest.soil = part(nest.model, Vector3.new(0.12, 8.4, 8.4), rgb(96, 62, 42), CFrame.new(nest.patch + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)))
		nest.soil.Shape = Enum.PartType.Cylinder
	end
	for i = 1, 3 do
		local fungus = nest.fungi[i]
		if not fungus then
			fungus = { readyAt = now + Config.Fungus.Regrow * (0.4 + 0.3 * i), stage = 0, look = buildFungus(nest, i) }
			nest.fungi[i] = fungus
		end
		-- Crece en tres tamaños; maduro brilla
		local left = fungus.readyAt - now
		local stage = if left <= 0 then 3 elseif left < Config.Fungus.Regrow / 2 then 2 else 1
		if stage ~= fungus.stage then
			setStage(fungus, stage)
		end
		if stage == 3 and root and ((root.Position - nest.spots[i]) * FLAT).Magnitude < FUNGUS_REACH then
			fungus.readyAt = now + Config.Fungus.Regrow
			profile.buffUntil = math.max(profile.buffUntil, now) + stats.buffDuration
			Profiles.push(profile)
			fxRemote:FireClient(profile.player, "Fungus", nest.spots[i] + Vector3.new(0, 4, 0), stats.buffDuration)
			setStage(fungus, 1)
		end
	end
end

local function tick()
	-- Hormigueros que cambiaron de dueña o se quedaron libres
	for hill, nest in nests do
		local profile = nest.profile
		if Profiles.get(profile.player) ~= profile or profile.hill ~= hill then
			release(hill)
		end
	end

	local now = Workspace:GetServerTimeNow()
	for player, profile in Profiles.all() do
		local hill = profile.hill
		if not hill or not profile.stats then
			continue
		end
		local nest = nests[hill] or create(hill, profile)
		if (hill:GetAttribute("Scale") or 1) ~= nest.scale then
			relocate(nest)
		end
		local root = getRoot(player)
		updateEgg(nest, profile, now, root)
		updateFungi(nest, profile, now, root)
	end
end

function Nest.start(remotes: Folder)
	fxRemote = remotes.Fx
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[CRUNCH!] Nido:", err)
			end
		end
	end)
end

return Nest
