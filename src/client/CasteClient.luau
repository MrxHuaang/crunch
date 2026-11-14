-- Castas (cliente): el panel "Castas" (tecla K), la barra de acción con las tres habilidades
-- (teclas 1, 2 y 3), el apuntado, el despacho de los efectos "Caste" a cada casta y las auras de
-- todas las hormigas. Módulo opcional: si falta, el juego sigue igual.
--
-- El panel es una pantalla de selección de luchadoras pasada por cómic: a la izquierda una columna
-- curva de celdas de panal (las cerradas, selladas con cera); en el centro la hormiga con el aura
-- de la casta girando sobre un estallido, con el nombre enorme y el lema; a la derecha la ficha de
-- combate (pasiva, habilidades con los números ya resueltos) y el camino de rangos 1 → 10 con las
-- bifurcaciones A/B de las mutaciones y la corona de Maestría. En pantallas bajas (móvil) el centro
-- se pliega en una cabecera y la ficha se desplaza.
--
-- Cada casta trae su módulo en src/client/Castes/<id>.luau (fx, aura, emblem, cast). Si falta, se
-- usan un emblema y un aura genéricos.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AntLook = require(ReplicatedStorage.Shared.AntLook)
local AntModel = require(ReplicatedStorage.Shared.AntModel)
local Assets = require(ReplicatedStorage.Shared.Assets)
local Castes = require(ReplicatedStorage.Shared.Castes)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Bubble = require(script.Parent.Bubble)
local CasteFx = require(script.Parent.CasteFx)
local Comic = require(script.Parent.Comic)
local Hud = require(script.Parent.Hud)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)

local CasteClient = {}

local C = Config.Castes
local MAX_RANK = Castes.MaxRank
local player = Players.LocalPlayer
local KEYBOARD = UserInputService.KeyboardEnabled
local TOUCH = UserInputService.TouchEnabled
local FLAT = Vector3.new(1, 0, 1)
local UP = Vector3.new(0, 1, 0)
local GOLD = Color3.fromRGB(255, 200, 40)
local WAX = Color3.fromRGB(232, 170, 58)
local WAX_DARK = Color3.fromRGB(176, 110, 30)
local SEAL = Color3.fromRGB(196, 44, 52)
local SQRT3 = math.sqrt(3)
local SEEN = 320 -- efectos de hormigas más lejanas que esto no se despachan

local remote: RemoteEvent? = nil
local modules: { [string]: any } = {}

---------------------------------------------------------------------------------------------------
-- Datos (atributos que manda el servidor)

local dataRaw: any = false
local dataValue = { xp = {}, muts = {}, best = 0 }

local function data()
	local raw = player:GetAttribute("CasteData")
	if raw == dataRaw then
		return dataValue
	end
	dataRaw = raw
	local value = { xp = {}, muts = {}, best = 0 }
	if type(raw) == "string" and raw ~= "" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and type(decoded) == "table" then
			value.xp = if type(decoded.xp) == "table" then decoded.xp else {}
			value.muts = if type(decoded.muts) == "table" then decoded.muts else {}
			value.best = tonumber(decoded.best) or 0
		end
	end
	dataValue = value
	return value
end

local function activeId(): string?
	local id = player:GetAttribute("Caste")
	return if type(id) == "string" and Castes.get(id) then id else nil
end

local function xpOf(id: string): number
	return tonumber(data().xp[id]) or 0
end

local function rankOf(id: string): number
	return Castes.rankOf(xpOf(id))
end

local function mutsOf(id: string)
	local muts = data().muts[id]
	return if type(muts) == "table" then muts else {}
end

local function bestDepth(): number
	return math.max(data().best, State.depth())
end

local function needDepth(def): number
	return math.max(C.UnlockDepth, def.depth or 1)
end

local function unlocked(def): boolean
	return bestDepth() >= needDepth(def)
end

local function resolvedFor(id: string)
	return Castes.resolve(Castes.get(id), mutsOf(id), rankOf(id))
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(who: Player): BasePart?
	local character = who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function call(where: string, fn: any, ...: any): (boolean, any)
	if type(fn) ~= "function" then
		return false, nil
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		warn("[CRUNCH!] Casta (" .. where .. "):", result)
	end
	return ok, result
end

local function at(object: GuiObject, x: number, y: number, w: number?, h: number?)
	object.Position = UDim2.fromOffset(x, y)
	if w and h then
		object.Size = UDim2.fromOffset(w, h)
	end
end

local function tween(object: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function textLimit(label: TextLabel, max: number, min: number?)
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = max
	limit.MinTextSize = min or 8
	limit.Parent = label
end

local function pad(label: GuiObject, x: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.Parent = label
end

local function chip(parent: Instance, text: string, color: Color3, size: number, rotation: number?): TextLabel
	local label = Comic.label(parent, text, Comic.Display, size, Comic.Ink)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, size + 6)
	label.BackgroundTransparency = 0
	label.BackgroundColor3 = color
	label.Rotation = rotation or 0
	Comic.ink(label, 2.5, true)
	pad(label, 6)
	return label
end

local function seconds(value: number): string
	if math.abs(value - math.floor(value + 0.5)) < 0.05 then
		return tostring(math.floor(value + 0.5)) .. " s"
	end
	return (string.format("%.1f", value):gsub("%.", ",")) .. " s"
end

---------------------------------------------------------------------------------------------------
-- Formas: hexágono de panal (tres rectángulos girados, con su capa de tinta debajo), círculo,
-- candado y corona dibujados con marcos.

local function hexagon(parent: Instance, radius: number, fill: Color3, inkWidth: number, ink: Color3?): (Frame, { Frame }, { Frame })
	local box = Comic.frame(parent)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Size = UDim2.fromOffset(radius * 2, radius * 2)
	local function layer(r: number, color: Color3, z: number): { Frame }
		local list = {}
		for _, angle in { 0, 60, 120 } do
			local f = Comic.frame(box, color)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(0.5, 0.5)
			f.Size = UDim2.fromOffset(SQRT3 * r, r)
			f.Rotation = angle
			f.ZIndex = z
			table.insert(list, f)
		end
		return list
	end
	local inkLayer = layer(radius + inkWidth, ink or Comic.Ink, 1)
	local fillLayer = layer(radius, fill, 2)
	return box, fillLayer, inkLayer
end

local function paintLayer(list: { Frame }, color: Color3, transparency: number?)
	for _, f in list do
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency or 0
	end
end

local function circle(parent: Instance, size: number, color: Color3, stroke: number?): Frame
	local f = Comic.frame(parent, color)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	Comic.round(f)
	if stroke and stroke > 0 then
		Comic.ink(f, stroke, true)
	end
	return f
end

local function padlock(parent: Instance, size: number, color: Color3?): Frame
	local box = Comic.frame(parent)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Size = UDim2.fromOffset(size, size)
	local shackle = Comic.frame(box)
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.fromScale(0.5, 0.04)
	shackle.Size = UDim2.fromScale(0.56, 0.62)
	Comic.round(shackle)
	local ring = Instance.new("UIStroke")
	ring.Color = Comic.Ink
	ring.Thickness = math.max(2, size * 0.13)
	ring.Parent = shackle
	local body = Comic.frame(box, color or Comic.Yellow)
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 1)
	body.Size = UDim2.fromScale(0.86, 0.56)
	body.ZIndex = 2
	Comic.round(body, math.floor(size * 0.12))
	Comic.ink(body, math.max(1.5, size * 0.08), true)
	local hole = circle(body, math.max(3, size * 0.16), Comic.Ink)
	hole.Position = UDim2.fromScale(0.5, 0.45)
	hole.ZIndex = 3
	return box
end

local function crown(parent: Instance, width: number, color: Color3): (Frame, { Frame })
	local box = Comic.frame(parent)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Size = UDim2.fromOffset(width, width * 0.8)
	local tinted = {}
	local base = Comic.frame(box, color)
	base.AnchorPoint = Vector2.new(0.5, 1)
	base.Position = UDim2.fromScale(0.5, 1)
	base.Size = UDim2.fromScale(0.9, 0.36)
	base.ZIndex = 3
	Comic.ink(base, 2.5, true)
	table.insert(tinted, base)
	for i, x in { 0.18, 0.5, 0.82 } do
		local spike = Comic.frame(box, color)
		spike.AnchorPoint = Vector2.new(0.5, 0.5)
		spike.Position = UDim2.fromScale(x, if i == 2 then 0.5 else 0.56)
		spike.Size = UDim2.fromOffset(width * 0.3, width * 0.3)
		spike.Rotation = 45
		spike.ZIndex = 2
		Comic.ink(spike, 2.5, true)
		table.insert(tinted, spike)
		local gem = circle(box, width * 0.16, Comic.Red, 2)
		gem.Position = UDim2.fromScale(x, if i == 2 then 0.14 else 0.24)
		gem.ZIndex = 4
	end
	return box, tinted
end

---------------------------------------------------------------------------------------------------
-- Emblemas y auras (los de cada casta o los genéricos)

local function genericEmblem(parent: GuiObject, def, color: Color3)
	local hex = hexagon(parent, 1, color, 0.1)
	hex.Size = UDim2.fromScale(0.92, 0.92)
	hex.Position = UDim2.fromScale(0.5, 0.5)
	-- El hexágono se dibujó a radio 1: se rehace a la medida real del marco
	local side = math.max(parent.Size.X.Offset, parent.AbsoluteSize.X, 20)
	for _, f in hex:GetChildren() do
		if f:IsA("Frame") then
			local r = if f.ZIndex == 1 then side * 0.46 else side * 0.4
			f.Size = UDim2.fromOffset(SQRT3 * r, r)
		end
	end
	local letter = Comic.label(hex, string.upper(string.sub(def.name, 1, 1)), Comic.Display, 30, Comic.Ink)
	letter.AnchorPoint = Vector2.new(0.5, 0.5)
	letter.Position = UDim2.fromScale(0.5, 0.52)
	letter.Size = UDim2.fromScale(0.7, 0.7)
	letter.ZIndex = 3
	letter.TextScaled = true
end

-- Dibuja el emblema de la casta dentro de un marco cuadrado nuevo, hijo de `parent`
local function drawEmblem(parent: Instance, def, size: number, color: Color3?, z: number?): Frame
	local frame = Comic.frame(parent)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.ZIndex = z or 3
	local tint = color or def.color
	local module = modules[def.id]
	local ok = false
	if module and type(module.emblem) == "function" then
		ok = (call(def.id .. ".emblem", module.emblem, frame, tint))
	end
	if not ok then
		frame:ClearAllChildren()
		genericEmblem(frame, def, tint)
	end
	return frame
end

local function genericAura(def)
	return function(character: Model, rank: number, mastered: boolean): () -> ()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return function() end
		end
		local scale = character:GetScale()
		local made: { Instance } = {}
		local function ring(diameter: number, color: Color3, alpha: number, y: number, neon: boolean)
			local p = Instance.new("Part")
			p.Name = "CasteAura"
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.1, diameter, diameter)
			p.Color = color
			p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
			p.Transparency = alpha
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Massless = true
			p.CFrame = root.CFrame * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
			p.Parent = character
			table.insert(made, p)
		end
		local feet = -(0.5 + AntModel.HipHeight) * scale
		ring((4.4 + rank * 0.12) * scale, Comic.Ink, 0.35, feet + 0.05, false)
		ring((4 + rank * 0.12) * scale, if mastered then GOLD else def.color, 0.5, feet + 0.09, true)

		local point = Instance.new("Attachment")
		point.Name = "CasteAura"
		point.Position = Vector3.new(0, feet * 0.5, 0)
		point.Parent = root
		table.insert(made, point)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(def.color, def.accent or def.color)
		e.LightEmission = 0.7
		e.LightInfluence = 0
		e.Size = NumberSequence.new(0.35 * scale, 0)
		e.Transparency = NumberSequence.new(0.1, 1)
		e.Lifetime = NumberRange.new(0.7, 1.2)
		e.Rate = 2 + rank * 0.8
		e.Speed = NumberRange.new(1, 2.5)
		e.SpreadAngle = Vector2.new(70, 70)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, 1.5, 0)
		e.Parent = point
		if mastered then
			local g = e:Clone()
			g.Color = ColorSequence.new(GOLD)
			g.Rate = 5
			g.Parent = point
		end
		local light = Instance.new("PointLight")
		light.Color = if mastered then GOLD else def.color
		light.Range = 6 + rank * 0.4
		light.Brightness = 0.7
		light.Shadows = false
		light.Parent = point
		return function()
			for _, item in made do
				item:Destroy()
			end
			table.clear(made)
		end
	end
end

local auras: { [Player]: any } = {}

local function applyAura(who: Player, force: boolean?)
	local st = auras[who]
	if not st then
		st = { cleanup = nil, key = "", character = nil }
		auras[who] = st
	end
	local character = who.Character
	local id = who:GetAttribute("Caste")
	local rank = tonumber(who:GetAttribute("CasteRank")) or 1
	local look = character and tostring(character:GetAttribute("LookVersion")) or ""
	local key = tostring(id) .. "|" .. rank .. "|" .. look
	if not force and st.key == key and st.character == character then
		return
	end
	if st.cleanup then
		call("aura (quitar)", st.cleanup)
		st.cleanup = nil
	end
	st.key = key
	st.character = character
	local def = Castes.get(id)
	if not character or not def or not character:FindFirstChild("HumanoidRootPart") then
		return
	end
	local module = modules[def.id]
	local fn = if module and type(module.aura) == "function" then module.aura else genericAura(def)
	local ok, result = call(def.id .. ".aura", fn, character, math.clamp(rank, 1, MAX_RANK), rank >= MAX_RANK)
	if ok and type(result) == "function" then
		st.cleanup = result
	end
end

local function watchPlayer(who: Player)
	local function onCharacter(character: Model)
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2)
			if who.Character == character then
				applyAura(who, true)
			end
		end)
		-- AntLook rehace la hormiga (y la escala) cada vez que cambia su aspecto: el aura se monta otra vez
		character:GetAttributeChangedSignal("LookVersion"):Connect(function()
			task.defer(function()
				if who.Character == character then
					applyAura(who, true)
				end
			end)
		end)
	end
	who:GetAttributeChangedSignal("Caste"):Connect(function()
		applyAura(who)
	end)
	who:GetAttributeChangedSignal("CasteRank"):Connect(function()
		applyAura(who)
	end)
	who.CharacterAdded:Connect(onCharacter)
	who.CharacterRemoving:Connect(function()
		local st = auras[who]
		if st and st.cleanup then
			call("aura (quitar)", st.cleanup)
			st.cleanup = nil
			st.key = ""
		end
	end)
	if who.Character then
		onCharacter(who.Character)
	end
end

---------------------------------------------------------------------------------------------------
-- Efectos: el servidor manda ("Caste", jugadora, casta, suceso, datos)

local onRankUpMine: ((rank: number, mastered: boolean) -> ())? = nil

local function genericFx(caster: Player, def, event: string, payload: any, mine: boolean)
	local root = rootOf(caster)
	if not root then
		return
	end
	local pos = root.Position
	if event == "rankup" then
		local rank = tonumber(payload.rank) or 1
		local mastered = payload.mastered == true
		local tint = if mastered then GOLD else def.color
		CasteFx.pillar(pos - UP * 1.2, { color = tint, height = 16, width = 3.5, life = 0.8 })
		CasteFx.burst(pos + UP * 2, { color = tint, count = 24, speed = 22, size = 0.7, life = 0.7, up = true })
		CasteFx.word(pos + UP * 5, if mastered then "¡MAESTRÍA!" else "¡RANGO " .. rank .. "!", { color = tint, size = 54, life = 1.2 })
		CasteFx.sound("chime", pos, if mastered then 0.8 else 1)
	elseif event == "pick" then
		CasteFx.pillar(pos - UP * 1.2, { color = def.color, height = 12, width = 3, life = 0.6 })
		CasteFx.ring(pos - UP * 1.2, 9, { color = def.color, life = 0.5 })
		CasteFx.word(pos + UP * 4.5, "¡" .. string.upper(def.name) .. "!", { color = def.color, size = 48, life = 1 })
		CasteFx.sound("whoosh", pos, 1.1)
	end
end

local function onFx(kind: any, caster: any, id: any, event: any, payload: any)
	if kind ~= "Caste" or typeof(caster) ~= "Instance" or not caster:IsA("Player") or type(id) ~= "string" or type(event) ~= "string" then
		return
	end
	local def = Castes.get(id)
	if not def then
		return
	end
	local mine = caster == player
	local p = if type(payload) == "table" then payload else {}
	if not mine then
		local root = rootOf(caster)
		local camera = Workspace.CurrentCamera
		if root and camera and (camera.CFrame.Position - root.Position).Magnitude > SEEN then
			return
		end
	end
	if mine and event == "rankup" and onRankUpMine then
		task.spawn(onRankUpMine, tonumber(p.rank) or 1, p.mastered == true)
	end
	local module = modules[id]
	local fn = module and type(module.fx) == "table" and module.fx[event]
	if type(fn) == "function" then
		-- Mientras corre la parte síncrona de un efecto ajeno, CasteFx no sacude ni destella la pantalla
		CasteFx._quiet = not mine
		task.spawn(function()
			local ok, err = pcall(fn, caster, p, mine)
			if not ok then
				warn("[CRUNCH!] Casta " .. id .. " (fx " .. event .. "):", err)
			end
		end)
		CasteFx._quiet = false
	elseif event == "rankup" or event == "pick" then
		genericFx(caster, def, event, p, mine)
	end
end

---------------------------------------------------------------------------------------------------
-- Apuntado

local castTarget: ((slot: number) -> ())? = nil

local function foodsFolder(): Instance?
	return Workspace:FindFirstChild("Food")
end

local function edible(food: Instance?): boolean
	if not food or not food:IsA("Model") or not food.Parent then
		return false
	end
	local def = Config.FoodById[food:GetAttribute("FoodId")]
	if not def then
		return false
	end
	return def.zone <= State.depth() and (not def.hard or State.stats().canBiteHard)
end

local function radiusOf(food: Model): number
	return tonumber(food:GetAttribute("Radius")) or 1
end

local function edgeGap(from: Vector3, food: Model): number
	return ((food:GetPivot().Position - from) * FLAT).Magnitude - radiusOf(food)
end

local function ignoreList(withFood: boolean): { Instance }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(list, other.Character)
		end
	end
	table.insert(list, CasteFx.folder())
	local crumbs = Workspace:FindFirstChild("FxCrumbs")
	if crumbs then
		table.insert(list, crumbs)
	end
	if withFood then
		local foods = foodsFolder()
		if foods then
			table.insert(list, foods)
		end
	end
	return list
end

local function groundAt(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList(true)
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position else Vector3.new(pos.X, Config.GroundY or pos.Y, pos.Z)
end

local function foodOf(instance: Instance?): Model?
	local foods = foodsFolder()
	local current = instance
	while current and foods and current.Parent and current.Parent ~= foods do
		current = current.Parent
	end
	if current and foods and current.Parent == foods and current:IsA("Model") then
		return current
	end
	return nil
end

local function nearestFood(from: Vector3, range: number): Model?
	local foods = foodsFolder()
	if not foods then
		return nil
	end
	local best, bestGap = nil, range
	for _, food in foods:GetChildren() do
		if food:IsA("Model") and edible(food) then
			local gap = edgeGap(from, food)
			if gap <= bestGap then
				best, bestGap = food, gap
			end
		end
	end
	return best
end

-- PC: el punto del ratón sobre el suelo y la comida bajo el ratón (o pegada a ese punto)
local function mouseTarget(origin: Vector3, range: number): (Vector3, Model?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return origin, nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList(false)
	params.IgnoreWater = true
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 700, params)
	local food = if hit then foodOf(hit.Instance) else nil
	if food and not edible(food) then
		food = nil
	end
	local point: Vector3
	if food then
		point = groundAt(food:GetPivot().Position)
	elseif hit then
		point = hit.Position
	else
		-- Al cielo: el punto del rayo a la altura de la hormiga
		local dy = ray.Direction.Y
		local t = if math.abs(dy) > 1e-3 then (origin.Y - ray.Origin.Y) / dy else 60
		point = ray.Origin + ray.Direction * math.clamp(t, 0, 300)
	end
	if not food then
		local snap = nearestFood(point, 1.5)
		if snap then
			food = snap
		end
	end
	if food and range > 0 and edgeGap(origin, food) > range + 2 then
		food = nil
	end
	local offset = (point - origin) * FLAT
	if range > 0 and offset.Magnitude > range then
		offset = offset.Unit * range
	end
	return groundAt(origin + offset), food
end

-- Táctil (y clic en el botón): la comida comible más cercana a tiro o, si no hay, delante
local function autoTarget(ability, origin: Vector3, look: Vector3, range: number): (Vector3, Model?)
	if ability.aim == "self" then
		return groundAt(origin), nil
	end
	local reach = math.max(range, 6)
	local food = nearestFood(origin, reach)
	if food then
		return groundAt(food:GetPivot().Position), food
	end
	return groundAt(origin + look * math.min(reach, 12)), nil
end

-- Indicador en el suelo mientras mantienes la tecla
local indicator: any = nil

local function clearIndicator()
	if indicator then
		for _, item in indicator.items do
			if typeof(item) == "Instance" then
				item:Destroy()
			elseif type(item) == "table" and item.destroy then
				item.destroy()
			end
		end
		indicator = nil
	end
end

local function flatBlock(color: Color3, alpha: number, neon: boolean): Part
	return CasteFx.part({
		Size = Vector3.new(0.3, 0.06, 1),
		Color = color,
		Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		Transparency = alpha,
	})
end

local function placeBlock(block: Part, a: Vector3, b: Vector3, width: number, y: number)
	local fa, fb = Vector3.new(a.X, y, a.Z), Vector3.new(b.X, y, b.Z)
	local length = (fb - fa).Magnitude
	if length < 0.05 then
		block.Transparency = 1
		return
	end
	block.Size = Vector3.new(width, 0.06, length)
	block.CFrame = CFrame.lookAt((fa + fb) / 2, fb)
end

local function buildIndicator(def, ability, range: number, radius: number, width: number)
	clearIndicator()
	local color = def.color
	local items = {}
	local function keep(item)
		table.insert(items, item)
		return item
	end
	local kind = ability.aim or "ground"
	local self = {
		kind = kind,
		color = color,
		range = range,
		radius = radius,
		width = width,
		items = items,
		rangeRing = if range > 0 and kind ~= "self" then keep(CasteFx.groundRing(Vector3.zero, range, color, 0.22, 0.95)) else nil,
		reticle = if kind ~= "direction" then keep(CasteFx.groundRing(Vector3.zero, math.max(radius, 1.5), color, 0.35, 0.78)) else nil,
		laneInk = if kind == "direction" then keep(flatBlock(Comic.Ink, 0.3, false)) else nil,
		lane = if kind == "direction" or kind == "food" then keep(flatBlock(color, 0.45, true)) else nil,
		chevrons = {},
	}
	if self.reticle then
		-- Cruz de la retícula, dibujada en la propia superficie del aro
		for _, rot in { 0, 90 } do
			local bar = Comic.frame(self.reticle.face, Comic.Ink)
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.new(0.34, 0, 0, 6)
			bar.Rotation = rot
		end
	end
	if kind == "direction" then
		for _ = 1, 4 do
			table.insert(self.chevrons, keep(flatBlock(color, 0.15, true)))
		end
	end
	indicator = self
end

local function updateIndicator(aim: Vector3, food: Model?, origin: Vector3, ok: boolean)
	local ind = indicator
	if not ind then
		return
	end
	local floor = groundAt(origin)
	local y = floor.Y + 0.16
	local tint = if ok then nil else Comic.Red
	if ind.rangeRing then
		ind.rangeRing.part.CFrame = CFrame.new(floor + Vector3.new(0, 0.12, 0))
	end
	if ind.reticle then
		local center = if ind.kind == "self" then floor elseif food then groundAt(food:GetPivot().Position) else aim
		local r = if ind.kind == "food" and food then radiusOf(food) + 0.8 else ind.radius
		ind.reticle.setRadius(math.max(r, 1.2))
		ind.reticle.part.CFrame = CFrame.new(center + Vector3.new(0, 0.16, 0))
		ind.reticle.setColor(tint or ind.color)
	end
	if ind.kind == "food" and ind.lane then
		if food then
			ind.lane.Transparency = 0.45
			placeBlock(ind.lane, origin, food:GetPivot().Position, 0.35, y)
		else
			ind.lane.Transparency = 1
		end
	elseif ind.kind == "direction" then
		local dir = (aim - origin) * FLAT
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, -1)
		local length = math.max(ind.range, 8)
		local tip = origin + dir * length
		placeBlock(ind.laneInk, origin, tip, ind.width + 0.5, y - 0.02)
		placeBlock(ind.lane, origin, tip, ind.width, y)
		-- Dos cheurones (">") hacia el final del carril
		local arm = math.clamp(ind.width * 0.55, 1.2, 4)
		for i, block in ind.chevrons do
			local k = if i <= 2 then 0.62 else 1
			local point = origin + dir * (length * k)
			local side = if i % 2 == 0 then 1 else -1
			local armDir = CFrame.fromAxisAngle(UP, math.rad(145 * side)):VectorToWorldSpace(dir)
			local a = Vector3.new(point.X, y + 0.02, point.Z)
			local b = a + armDir * arm
			block.Size = Vector3.new(0.4, 0.07, arm)
			block.CFrame = CFrame.lookAt((a + b) / 2, b)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Barra de acción

local BTN = 58
local ULT = 74
local BAR_W = 214
local HINT_DEFAULT = -38
local HINT_LIFTED = -146

local barGui: ScreenGui
local barRoot: Frame
local barButtons: { any } = {}
local xpFill: Frame
local xpRankLabel: TextLabel
local xpNextLabel: TextLabel
local xpTrack: Frame
local tooltip: TextLabel
local barShownFor: string? = nil
local hintOriginal: UDim2? = nil

-- La tira de narración del HUD vive justo encima de las migas: con la barra puesta, sube
local function liftHint(lift: boolean)
	local hudGui = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("Hud")
	local bottom = hudGui and hudGui:FindFirstChild("Bottom")
	local hint = bottom and bottom:FindFirstChild("Hint")
	if not hint or not hint:IsA("GuiObject") then
		return
	end
	if not hintOriginal then
		hintOriginal = hint.Position
	end
	local base = hintOriginal :: UDim2
	hint.Position = if lift then UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, HINT_LIFTED) else base
end

-- Barrido radial de enfriamiento: dos mitades recortadas con un degradado de borde duro que gira
local function radialSweep(parent: GuiObject, z: number): (number) -> ()
	local holder = Comic.frame(parent)
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = z
	local sequence = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.501, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	local function half(x: number, innerX: number): UIGradient
		local clip = Comic.frame(holder)
		clip.Position = UDim2.fromScale(x, 0)
		clip.Size = UDim2.fromScale(0.5, 1)
		clip.ClipsDescendants = true
		clip.ZIndex = z
		local disc = Comic.frame(clip, Comic.Ink)
		disc.BackgroundTransparency = 0.35
		disc.Position = UDim2.fromScale(innerX, 0)
		disc.Size = UDim2.fromScale(2, 1)
		disc.ZIndex = z
		Comic.round(disc)
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = sequence
		gradient.Parent = disc
		return gradient
	end
	local right = half(0.5, -1)
	local left = half(0, 0)
	return function(f: number)
		if f <= 0.001 then
			holder.Visible = false
			return
		end
		holder.Visible = true
		right.Rotation = math.clamp(f, 0, 0.5) * 360
		left.Rotation = 180 + math.clamp(f - 0.5, 0, 0.5) * 360
	end
end

local function makeButton(slot: number, x: number)
	local ult = slot == 3
	local size = if ult then ULT else BTN
	local holder = Comic.frame(barRoot)
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.Position = UDim2.new(0, x, 1, -50)
	holder.Size = UDim2.fromOffset(size, size)
	holder.ZIndex = 2

	local burst: ImageLabel? = nil
	if ult then
		-- La definitiva: estallido detrás y doble aro dorado
		local b = Comic.burst(holder, size * 1.45, Comic.Yellow)
		b.ZIndex = 1
		b.ImageTransparency = 0.1
		burst = b
		local goldRing = circle(holder, size + 10, GOLD, 3)
		goldRing.Position = UDim2.fromScale(0.5, 0.5)
		goldRing.ZIndex = 2
	end
	local shadow = circle(holder, size, Comic.Ink)
	shadow.Position = UDim2.new(0.5, 4, 0.5, 4)
	shadow.ZIndex = 2

	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.AutoButtonColor = false
	face.Text = ""
	face.BackgroundColor3 = Comic.Paper
	face.BorderSizePixel = 0
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromOffset(size, size)
	face.ZIndex = 3
	face.Parent = holder
	Comic.round(face)
	local stroke = Comic.ink(face, if ult then 4.5 else 3.5, true)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	local punch = Instance.new("UIScale")
	punch.Parent = face

	local emblemHolder = Comic.frame(face)
	emblemHolder.Size = UDim2.fromScale(1, 1)
	emblemHolder.ZIndex = 4

	local veil = circle(face, size, Comic.Paper)
	veil.Position = UDim2.fromScale(0.5, 0.5)
	veil.BackgroundTransparency = 0.3
	veil.ZIndex = 6
	veil.Visible = false

	local sweep = radialSweep(face, 7)

	local count = Comic.label(face, "", Comic.Display, if ult then 30 else 26, Comic.Paper)
	count.Size = UDim2.fromScale(1, 1)
	count.ZIndex = 9
	Comic.ink(count, 2.5)

	local lock = padlock(face, size * 0.42)
	lock.Position = UDim2.fromScale(0.5, 0.46)
	lock.ZIndex = 10
	for _, d in lock:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 10
		end
	end
	lock.Visible = false
	local lockTag = chip(holder, "Rango 3", Comic.Paper, 12, -4)
	lockTag.AnchorPoint = Vector2.new(0.5, 0)
	lockTag.Position = UDim2.new(0.5, 0, 1, -6)
	lockTag.ZIndex = 12
	lockTag.Visible = false

	local key = nil
	if KEYBOARD then
		key = chip(holder, tostring(slot), Comic.Yellow, 14, 8)
		key.AnchorPoint = Vector2.new(0.5, 0.5)
		key.Position = UDim2.new(0, 4, 0, 4)
		key.ZIndex = 12
	end

	-- Destello al quedar lista
	local flash = circle(holder, size, Comic.Paper)
	flash.Position = UDim2.fromScale(0.5, 0.5)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 11
	local flashStroke = Instance.new("UIStroke")
	flashStroke.Color = Comic.Paper
	flashStroke.Thickness = 5
	flashStroke.Transparency = 1
	flashStroke.Parent = flash

	local button = {
		slot = slot,
		holder = holder,
		face = face,
		punch = punch,
		emblemHolder = emblemHolder,
		emblemFor = nil :: string?,
		veil = veil,
		sweep = sweep,
		count = count,
		lock = lock,
		lockTag = lockTag,
		key = key,
		flash = flash,
		flashStroke = flashStroke,
		burst = burst,
		cooling = false,
		size = size,
	}

	face.MouseButton1Click:Connect(function()
		if castTarget then
			castTarget(slot)
		end
	end)
	face.MouseEnter:Connect(function()
		local id = activeId()
		local def = id and Castes.get(id)
		local ability = def and Castes.ability(def, slot)
		if ability then
			tooltip.Text = tostring(ability.name) .. (if KEYBOARD then "  [" .. slot .. "]" else "")
			tooltip.Position = UDim2.new(0, x + size / 2, 1, -50 - size - 10)
			tooltip.Visible = true
		end
	end)
	face.MouseLeave:Connect(function()
		tooltip.Visible = false
	end)
	return button
end

local function readyFlash(button)
	Comic.punch(button.punch, 1.25)
	local f = button.flash
	local s = button.flashStroke
	f.Size = UDim2.fromOffset(button.size, button.size)
	f.BackgroundTransparency = 0.2
	s.Transparency = 0
	tween(f, 0.35, { Size = UDim2.fromOffset(button.size * 1.6, button.size * 1.6), BackgroundTransparency = 1 })
	tween(s, 0.35, { Transparency = 1 })
	Sfx.pop(1.6 + button.slot * 0.1)
end

local function buildBar()
	barGui = Instance.new("ScreenGui")
	barGui.Name = "CasteBar"
	barGui.ResetOnSpawn = false
	barGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	barGui.Enabled = false
	barGui.Parent = player:WaitForChild("PlayerGui")

	barRoot = Comic.frame(barGui)
	barRoot.Name = "Bar"
	barRoot.AnchorPoint = Vector2.new(0.5, 1)
	barRoot.Position = UDim2.new(0.5, 0, 1, -12)
	barRoot.Size = UDim2.fromOffset(BAR_W, 140)
	Hud.fitScale(barRoot, BTN)

	local gap = (BAR_W - BTN * 2 - ULT) / 2
	barButtons[1] = makeButton(1, 0)
	barButtons[2] = makeButton(2, BTN + gap)
	barButtons[3] = makeButton(3, BTN * 2 + gap * 2)

	-- Experiencia de la casta, fina, bajo los botones (y sobre las migas)
	xpTrack = Comic.frame(barRoot, Comic.Paper)
	xpTrack.AnchorPoint = Vector2.new(0.5, 1)
	xpTrack.Position = UDim2.new(0.5, 8, 1, -34)
	xpTrack.Size = UDim2.fromOffset(BAR_W - 30, 10)
	xpTrack.BackgroundTransparency = 0.15
	Comic.round(xpTrack)
	Comic.ink(xpTrack, 2.5, true)
	xpFill = Comic.frame(xpTrack, Comic.Yellow)
	xpFill.Size = UDim2.fromScale(0, 1)
	Comic.round(xpFill)
	local rankDisc = circle(barRoot, 26, Comic.Yellow, 2.5)
	rankDisc.AnchorPoint = Vector2.new(0.5, 0.5)
	rankDisc.Position = UDim2.new(0, 10, 1, -39)
	rankDisc.ZIndex = 3
	xpRankLabel = Comic.label(rankDisc, "1", Comic.Display, 18, Comic.Ink)
	xpRankLabel.Size = UDim2.fromScale(1, 1)
	xpRankLabel.ZIndex = 4
	xpNextLabel = Comic.label(xpTrack, "", Comic.Display, 12, Comic.Ink)
	xpNextLabel.Size = UDim2.fromScale(1, 1)
	xpNextLabel.ZIndex = 2

	tooltip = chip(barRoot, "", Comic.Paper, 15, -2)
	tooltip.AnchorPoint = Vector2.new(0.5, 1)
	tooltip.ZIndex = 20
	tooltip.Visible = false

	-- La definitiva gira despacio su estallido
	task.spawn(function()
		while true do
			local dt = task.wait(0.05)
			local burst = barButtons[3].burst
			if burst and barGui.Enabled then
				burst.Rotation = (burst.Rotation + dt * 12) % 360
			end
		end
	end)
end

local function refreshBarEmblems(def)
	for _, button in barButtons do
		if button.emblemFor ~= def.id then
			button.emblemFor = def.id
			button.emblemHolder:ClearAllChildren()
			local mark = drawEmblem(button.emblemHolder, def, button.size * 0.62, def.color, 5)
			for _, d in mark:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex += 5
				end
			end
		end
	end
	if barButtons[3].burst then
		barButtons[3].burst.ImageColor3 = def.color
	end
end

local function updateBar()
	local id = activeId()
	local def = id and Castes.get(id)
	local visible = def ~= nil
	if barGui.Enabled ~= visible then
		barGui.Enabled = visible
		liftHint(visible)
	end
	if not def then
		barShownFor = nil
		return
	end
	if barShownFor ~= def.id then
		barShownFor = def.id
		refreshBarEmblems(def)
	end
	local rank = rankOf(def.id)
	local resolved = resolvedFor(def.id)
	local t = now()
	for slot, button in barButtons do
		local ability = Castes.ability(def, slot)
		if not ability then
			button.holder.Visible = false
			continue
		end
		button.holder.Visible = true
		local need = ability.rank or 1
		local locked = rank < need
		button.lock.Visible = locked
		button.lockTag.Visible = locked
		button.veil.Visible = locked
		if locked then
			button.lockTag.Text = "Rango " .. need
			button.sweep(0)
			button.count.Text = ""
			button.cooling = false
			continue
		end
		local readyAt = tonumber(player:GetAttribute("CasteCd" .. slot)) or 0
		local left = readyAt - t
		local total = tonumber(resolved.param(ability.id, "cooldown")) or tonumber(ability.cooldown) or 1
		if left > 0 then
			button.sweep(math.clamp(left / math.max(total, 0.1), 0, 1))
			button.count.Text = if left < 10 then string.format("%.1f", left):gsub("%.", ",") else tostring(math.ceil(left))
			button.cooling = true
			button.face.BackgroundColor3 = Comic.DirtLight
		else
			button.sweep(0)
			button.count.Text = ""
			if button.cooling then
				button.cooling = false
				readyFlash(button)
			end
			button.face.BackgroundColor3 = Comic.Paper
		end
	end
	-- Experiencia
	local xp = xpOf(def.id)
	xpRankLabel.Text = tostring(rank)
	if rank >= MAX_RANK then
		xpFill.Size = UDim2.fromScale(1, 1)
		xpFill.BackgroundColor3 = GOLD
		xpNextLabel.Text = "MAESTRÍA"
	else
		local from, to = Castes.xpFor(rank), Castes.xpFor(rank + 1)
		local k = math.clamp((xp - from) / math.max(to - from, 1), 0, 1)
		xpFill.BackgroundColor3 = def.color
		xpFill.Size = UDim2.fromScale(math.max(k, 0.04), 1)
		xpNextLabel.Text = ""
	end
end

-- "¡RANGO 4!" sobre la barra
local function rankBanner(rank: number, mastered: boolean)
	if not barRoot then
		return
	end
	local id = activeId()
	local def = id and Castes.get(id)
	local tint = if mastered then GOLD elseif def then def.color else Comic.Yellow
	local burst = Comic.burst(barRoot, 170, tint)
	burst.AnchorPoint = Vector2.new(0.5, 1)
	burst.Position = UDim2.new(0.5, 0, 1, -130)
	burst.ZIndex = 30
	burst.Rotation = math.random(-10, 10)
	local label = Comic.label(burst, if mastered then "¡MAESTRÍA!" else "¡RANGO " .. rank .. "!", Comic.Display, 30, Comic.Ink)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.8, 0.5)
	label.ZIndex = 31
	label.TextScaled = true
	local scale = Instance.new("UIScale")
	scale.Parent = burst
	Comic.punch(scale, 0.2)
	Sfx.fanfare()
	if mastered then
		CasteFx.flash(GOLD, 0.25, 0.4)
	end
	task.delay(1.4, function()
		tween(scale, 0.15, { Scale = 0 })
		task.wait(0.16)
		burst:Destroy()
	end)
end

---------------------------------------------------------------------------------------------------
-- Lanzar

local aimingSlot: number? = nil
local aimConnection: RBXScriptConnection? = nil
local panelOpen = false

local function abilityInfo(slot: number)
	local id = activeId()
	local def = id and Castes.get(id)
	local ability = def and Castes.ability(def, slot)
	if not def or not ability then
		return nil
	end
	local resolved = resolvedFor(def.id)
	local range = tonumber(resolved.param(ability.id, "range")) or tonumber(ability.range) or 0
	local radius = tonumber(resolved.param(ability.id, "radius")) or 0
	if radius <= 0 then
		radius = tonumber(ability.radius) or 5
	end
	local width = tonumber(resolved.param(ability.id, "width")) or 0
	if width <= 0 then
		width = 4
	end
	return {
		def = def,
		ability = ability,
		resolved = resolved,
		range = math.max(range, 0),
		radius = radius,
		width = width,
		rank = rankOf(def.id),
	}
end

local function ready(info, slot: number): (boolean, string?)
	if info.rank < (info.ability.rank or 1) then
		return false, "Rango " .. tostring(info.ability.rank)
	end
	local readyAt = tonumber(player:GetAttribute("CasteCd" .. slot)) or 0
	if readyAt - now() > 0.1 then
		return false, nil
	end
	return true, nil
end

local function denied(slot: number, why: string?)
	local button = barButtons[slot]
	if button then
		Comic.punch(button.punch, 0.8)
	end
	Sfx.pop(0.6)
	if why then
		Bubble.flash("Me falta " .. string.lower(why) .. " para esa habilidad", 2)
	end
end

local function fire(slot: number, info, aim: Vector3, food: Model?)
	local module = modules[info.def.id]
	local pre = module and type(module.cast) == "table" and module.cast[info.ability.id]
	if type(pre) == "function" then
		local ok, result = call(info.def.id .. ".cast", pre, aim, food, info.ability, info.def)
		if ok and result == false then
			return
		end
	end
	if remote then
		remote:FireServer("Cast", slot, aim, food)
	end
	local button = barButtons[slot]
	if button then
		Comic.punch(button.punch, 0.75)
	end
end

local function stopAiming()
	aimingSlot = nil
	if aimConnection then
		aimConnection:Disconnect()
		aimConnection = nil
	end
	clearIndicator()
end

local function beginAim(slot: number)
	local info = abilityInfo(slot)
	local root = rootOf(player)
	if not info or not root then
		return
	end
	local ok, why = ready(info, slot)
	if not ok then
		denied(slot, why)
		return
	end
	stopAiming()
	aimingSlot = slot
	buildIndicator(info.def, info.ability, info.range, info.radius, info.width)
	aimConnection = RunService.RenderStepped:Connect(function()
		local r = rootOf(player)
		if not r or aimingSlot ~= slot then
			stopAiming()
			return
		end
		local aim, food = mouseTarget(r.Position, info.range)
		local valid = info.ability.aim ~= "food" or food ~= nil or nearestFood(aim, 8) ~= nil
		updateIndicator(aim, food, r.Position, valid)
	end)
end

local function releaseAim(slot: number)
	if aimingSlot ~= slot then
		return
	end
	stopAiming()
	local info = abilityInfo(slot)
	local root = rootOf(player)
	if not info or not root then
		return
	end
	local ok, why = ready(info, slot)
	if not ok then
		denied(slot, why)
		return
	end
	local aim, food = mouseTarget(root.Position, info.range)
	if info.ability.aim == "self" then
		aim, food = groundAt(root.Position), nil
	end
	fire(slot, info, aim, food)
end

-- Toque o clic en el botón: apunta solo
castTarget = function(slot: number)
	local info = abilityInfo(slot)
	local root = rootOf(player)
	if not info or not root then
		return
	end
	local ok, why = ready(info, slot)
	if not ok then
		denied(slot, why)
		return
	end
	local look = root.CFrame.LookVector * FLAT
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local aim, food = autoTarget(info.ability, root.Position, look, info.range)
	fire(slot, info, aim, food)
end

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
}

---------------------------------------------------------------------------------------------------
-- Panel "Castas"

local PW, PH = 1180, 640
local COL_W, HERO_W, SHEET_W = 230, 460, 470
local GAP = 10
local MINI_H = 110

local gui: ScreenGui
local panel: Frame
local fit: UIScale
local vLeft: Frame
local vLeftFace: Frame
local vHero: Frame
local vHeroFace: Frame
local vSheet: Frame
local vSheetFace: Frame
local colScroll: ScrollingFrame
local colContent: Frame
local hero: Frame
local heroMini: Frame
local sheetScroll: ScrollingFrame
local sheet: Frame
local pathFrame: Frame
local pickHolder: Frame
local pickFace: TextButton
local pickLabel: TextLabel
local compact = false

local selected: string? = nil
local cellViews: { [string]: any } = {}
local heroView: any = {}
local miniView: any = {}
local rows: { any } = {}
local pathView: any = {}
local detailLevel: any = nil
local detailOption = 1
local spinConnection: RBXScriptConnection? = nil
local sideButton: any = nil
local callout: Frame? = nil
local announced = false

local preview: Model? = nil
local previewWorld: WorldModel? = nil
local previewCamera: Camera? = nil
local previewAura: (() -> ())? = nil
local previewFor = ""
local previewAngle = 0
local PREVIEW_AT = CFrame.new(0, 2000, 0) -- lejos: lo que un aura cuelgue en el mundo no se ve

local function list(): { any }
	return Castes.list()
end

local function selectedDef()
	return if selected then Castes.get(selected) else nil
end

-- Celdas de panal en una columna curva
local function cellPos(i: number): (number, number)
	local n = #Castes.Order
	local t = (i - 1) / math.max(n - 1, 1)
	local x = 112 + (if i % 2 == 0 then 30 else -30) * 0.85 - 26 * math.sin(math.pi * t)
	local y = 96 + (i - 1) * 68
	return x, y
end

local paintPanel: () -> ()
local selectCaste: (id: string) -> ()

local function buildCells()
	local index = 0
	for _, id in Castes.Order do
		local def = Castes.get(id)
		if not def then
			continue
		end
		index += 1
		local x, y = cellPos(index)
		local box, fill, inkLayer = hexagon(colContent, 38, Comic.Paper, 5)
		box.Position = UDim2.fromOffset(x, y)
		local scale = Instance.new("UIScale")
		scale.Parent = box

		local emblem = drawEmblem(box, def, 44, def.color, 3)
		for _, d in emblem:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex += 3
			end
		end

		-- Sello de cera de las cerradas
		local wax = Comic.frame(box)
		wax.Size = UDim2.fromScale(1, 1)
		wax.ZIndex = 20
		local drip = Comic.frame(wax, WAX_DARK)
		drip.AnchorPoint = Vector2.new(0.5, 0)
		drip.Position = UDim2.new(0.5, 10, 0.5, 14)
		drip.Size = UDim2.fromOffset(9, 22)
		drip.ZIndex = 20
		Comic.round(drip)
		local seal = circle(wax, 46, SEAL, 3)
		seal.Position = UDim2.fromScale(0.5, 0.5)
		seal.Rotation = -8
		seal.ZIndex = 21
		local sealText = Comic.label(seal, "Capa " .. needDepth(def), Comic.Display, 15, Comic.Paper)
		sealText.Size = UDim2.fromScale(1, 1)
		sealText.ZIndex = 22
		sealText.Rotation = -8
		Comic.ink(sealText, 1.5)

		local rankDisc = circle(box, 22, Comic.Yellow, 2.5)
		rankDisc.Position = UDim2.new(0.5, 26, 0.5, 24)
		rankDisc.ZIndex = 24
		local rankText = Comic.label(rankDisc, "1", Comic.Display, 14, Comic.Ink)
		rankText.Size = UDim2.fromScale(1, 1)
		rankText.ZIndex = 25

		local mine = chip(box, "TÚ", Comic.Red, 13, -10)
		mine.TextColor3 = Comic.Paper
		mine.AnchorPoint = Vector2.new(0.5, 0.5)
		mine.Position = UDim2.new(0.5, -26, 0.5, -26)
		mine.ZIndex = 26

		local mastery, masteryTint = crown(box, 22, GOLD)
		mastery.Position = UDim2.new(0.5, 0, 0.5, -38)
		mastery.ZIndex = 27
		for _, d in mastery:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex += 26
			end
		end
		local _ = masteryTint

		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AnchorPoint = Vector2.new(0.5, 0.5)
		hit.Position = UDim2.fromOffset(x, y)
		hit.Size = UDim2.fromOffset(66, 70)
		hit.ZIndex = 40
		hit.Parent = colContent
		hit.MouseButton1Click:Connect(function()
			selectCaste(def.id)
		end)
		hit.MouseEnter:Connect(function()
			if selected ~= def.id then
				tween(scale, 0.12, { Scale = 1.06 }, Enum.EasingStyle.Back)
			end
		end)
		hit.MouseLeave:Connect(function()
			if selected ~= def.id then
				tween(scale, 0.12, { Scale = 1 })
			end
		end)

		cellViews[def.id] = {
			def = def,
			box = box,
			fill = fill,
			ink = inkLayer,
			scale = scale,
			emblem = emblem,
			wax = wax,
			rankDisc = rankDisc,
			rankText = rankText,
			mine = mine,
			mastery = mastery,
		}
	end
	colContent.Size = UDim2.fromOffset(COL_W, 96 + index * 68)
end

local function paintCells()
	local active = activeId()
	for id, view in cellViews do
		local def = view.def
		local open = unlocked(def)
		local rank = rankOf(id)
		local isSel = selected == id
		view.wax.Visible = not open
		paintLayer(view.fill, if not open then WAX elseif isSel then def.color else Comic.Paper)
		paintLayer(view.ink, if rank >= MAX_RANK and open then GOLD elseif isSel then Comic.Red else Comic.Ink)
		view.emblem.Visible = true
		view.rankDisc.Visible = open and xpOf(id) > 0
		view.rankText.Text = tostring(rank)
		view.mine.Visible = active == id
		view.mastery.Visible = open and rank >= MAX_RANK
		tween(view.scale, 0.16, { Scale = if isSel then 1.14 else 1 }, Enum.EasingStyle.Back)
	end
end

-- Centro: estallido, hormiga girando, nombre y lema
local function buildHero()
	hero = Comic.frame(vHeroFace)
	hero.Size = UDim2.fromOffset(HERO_W, PH)
	hero.ClipsDescendants = true

	local lines = Comic.image(hero, Assets.SpeedLines)
	lines.ScaleType = Enum.ScaleType.Stretch
	lines.AnchorPoint = Vector2.new(0.5, 0.5)
	lines.Position = UDim2.fromScale(0.5, 0.52)
	lines.Size = UDim2.fromOffset(HERO_W * 1.6, PH * 1.3)
	lines.ImageTransparency = 0.55

	local burst = Comic.burst(hero, 560, Comic.Yellow)
	burst.Position = UDim2.new(0.5, 0, 0, 340)
	burst.ZIndex = 2

	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.new(0.5, 0, 0, 340)
	viewport.Size = UDim2.fromOffset(420, 360)
	viewport.Ambient = Color3.fromRGB(190, 186, 200)
	viewport.LightColor = Color3.fromRGB(255, 248, 236)
	viewport.LightDirection = Vector3.new(-0.6, -1, -0.4)
	viewport.ZIndex = 3
	viewport.Parent = hero
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	previewWorld = world
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	previewCamera = camera

	local nameShadow = Comic.label(hero, "", Comic.Display, 92, Comic.Ink)
	at(nameShadow, 26, 30, 420, 100)
	nameShadow.Rotation = -6
	nameShadow.ZIndex = 4
	textLimit(nameShadow, 92, 30)
	local name = Comic.label(hero, "", Comic.Display, 92, Comic.Yellow)
	at(name, 18, 22, 420, 100)
	name.Rotation = -6
	name.ZIndex = 5
	textLimit(name, 92, 30)
	Comic.ink(name, 5)

	local mottoHolder, mottoFace = Comic.box(hero, UDim2.fromOffset(380, 40), Comic.Paper, 4)
	mottoHolder.Position = UDim2.fromOffset(44, 128)
	mottoHolder.Rotation = 2
	mottoHolder.ZIndex = 6
	mottoFace.ZIndex = 6
	local motto = Comic.label(mottoFace, "", Comic.Body, 19, Comic.Ink)
	motto.Size = UDim2.fromScale(1, 1)
	motto.ZIndex = 7
	textLimit(motto, 19, 10)
	pad(motto, 10)

	local rankTag = chip(hero, "", Comic.Yellow, 18, -3)
	rankTag.Position = UDim2.fromOffset(22, PH - 122)
	rankTag.ZIndex = 8

	local stamp = chip(hero, "TU CASTA", Comic.Red, 22, 12)
	stamp.TextColor3 = Comic.Paper
	stamp.AnchorPoint = Vector2.new(1, 0)
	stamp.Position = UDim2.new(1, -24, 0, 186)
	stamp.ZIndex = 8

	heroView = {
		face = vHeroFace,
		lines = lines,
		burst = burst,
		viewport = viewport,
		name = name,
		nameShadow = nameShadow,
		motto = motto,
		rankTag = rankTag,
		stamp = stamp,
	}
end

local function buildMini()
	heroMini = Comic.frame(nil :: any)
	heroMini.Size = UDim2.fromOffset(SHEET_W, MINI_H)
	local emblemSlot = Comic.frame(heroMini)
	at(emblemSlot, 8, 8, 94, 94)
	local name = Comic.label(heroMini, "", Comic.Display, 56, Comic.Yellow)
	at(name, 112, 4, 300, 62)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Rotation = -3
	textLimit(name, 56, 24)
	Comic.ink(name, 4)
	local motto = Comic.label(heroMini, "", Comic.Body, 17, Comic.Ink)
	at(motto, 114, 66, 346, 38)
	motto.TextXAlignment = Enum.TextXAlignment.Left
	motto.TextWrapped = true
	textLimit(motto, 17, 10)
	miniView = { emblemSlot = emblemSlot, name = name, motto = motto, emblemFor = "" }
end

-- Ficha de combate: pasiva y las tres habilidades
local function makeRow(y: number, index: number)
	local holder, face = Comic.box(sheet, UDim2.fromOffset(438, 70), Comic.Paper, 3)
	holder.Position = UDim2.fromOffset(16, y)
	holder.Rotation = if index % 2 == 0 then 0.6 else -0.6
	local keyBox = Comic.frame(face, Comic.Yellow)
	at(keyBox, 10, 12, 46, 46)
	Comic.ink(keyBox, 2.5, true)
	Comic.round(keyBox, 8)
	keyBox.ZIndex = 2
	local key = Comic.label(keyBox, "", Comic.Display, 30, Comic.Ink)
	key.Size = UDim2.fromScale(1, 1)
	key.ZIndex = 3
	local title = Comic.label(face, "", Comic.Display, 22, Comic.Ink)
	at(title, 66, 3, 250, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left
	textLimit(title, 22, 12)
	title.ZIndex = 2
	local meta = Comic.label(face, "", Comic.Display, 17, Comic.Red)
	meta.AnchorPoint = Vector2.new(1, 0)
	meta.Position = UDim2.new(1, -10, 0, 5)
	meta.Size = UDim2.fromOffset(130, 20)
	meta.TextXAlignment = Enum.TextXAlignment.Right
	meta.ZIndex = 2
	local desc = Comic.label(face, "", Comic.Body, 14, Comic.Ink)
	at(desc, 66, 27, 364, 40)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.ZIndex = 2
	textLimit(desc, 14, 8)
	local tag = chip(holder, "", Comic.Yellow, 13, 4)
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(1, 6, 0, 0)
	tag.ZIndex = 5
	local veil = Comic.frame(face, Comic.Paper)
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundTransparency = 0.35
	veil.ZIndex = 6
	local lock = padlock(face, 26)
	lock.Position = UDim2.new(1, -30, 0.5, 6)
	for _, d in lock:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 7
		end
	end
	lock.ZIndex = 7
	local lockText = chip(face, "Rango 3", Comic.Paper, 13, -3)
	lockText.AnchorPoint = Vector2.new(1, 1)
	lockText.Position = UDim2.new(1, -50, 1, -6)
	lockText.ZIndex = 8
	return {
		holder = holder,
		face = face,
		keyBox = keyBox,
		key = key,
		title = title,
		meta = meta,
		desc = desc,
		tag = tag,
		veil = veil,
		lock = lock,
		lockText = lockText,
		emblemFor = "",
	}
end

local function buildSheet()
	sheet = Comic.frame(nil :: any)
	sheet.Size = UDim2.fromOffset(SHEET_W, 405)
	local head = chip(sheet, "FICHA DE COMBATE", Comic.Red, 18, -2)
	head.TextColor3 = Comic.Paper
	head.Position = UDim2.fromOffset(16, 10)
	local style = Comic.label(sheet, "", Comic.Body, 14, Comic.Ink)
	at(style, 18, 40, 384, 46)
	style.TextXAlignment = Enum.TextXAlignment.Left
	style.TextYAlignment = Enum.TextYAlignment.Top
	style.TextWrapped = true
	textLimit(style, 14, 8)
	rows.style = style
	rows[0] = makeRow(90, 0)
	for slot = 1, 3 do
		rows[slot] = makeRow(90 + slot * 78, slot)
	end
end

-- Camino de rangos
local PATH_Y = 92
local function nodePos(rank: number): Vector2
	return Vector2.new(30 + (rank - 1) * 45, PATH_Y + 9 * math.sin((rank - 1) * 0.9))
end

local function segment(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, z: number): Frame
	local d = b - a
	local f = Comic.frame(parent, color)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude + thickness * 0.5, thickness)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.ZIndex = z
	Comic.round(f)
	return f
end

local showDetail: (level: any, option: number) -> ()

local function buildPath()
	pathFrame = Comic.frame(nil :: any)
	pathFrame.Size = UDim2.fromOffset(SHEET_W, 230)
	local head = chip(pathFrame, "CAMINO DE RANGOS", Comic.Yellow, 18, 2)
	head.Position = UDim2.fromOffset(16, 4)
	local xpText = Comic.label(pathFrame, "", Comic.Display, 16, Comic.Ink)
	xpText.AnchorPoint = Vector2.new(1, 0)
	xpText.Position = UDim2.new(1, -18, 0, 8)
	xpText.Size = UDim2.fromOffset(220, 20)
	xpText.TextXAlignment = Enum.TextXAlignment.Right

	local segs, fills = {}, {}
	for r = 1, MAX_RANK - 1 do
		local a, b = nodePos(r), nodePos(r + 1)
		segs[r] = segment(pathFrame, a, b, 9, Comic.Ink, 1)
		local fillSeg = segment(pathFrame, a, b, 4, Comic.Yellow, 2)
		local gradient = Instance.new("UIGradient")
		gradient.Parent = fillSeg
		fills[r] = { frame = fillSeg, gradient = gradient }
	end

	local nodes = {}
	local mutationChips = {}
	local mutationRanks = {}
	for _, r in Castes.MutationRanks do
		mutationRanks[r] = true
	end
	for r = 1, MAX_RANK do
		local p = nodePos(r)
		if r == MAX_RANK then
			local c, tinted = crown(pathFrame, 34, Comic.Paper)
			c.Position = UDim2.fromOffset(p.X, p.Y - 4)
			c.ZIndex = 4
			for _, d in c:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex += 4
				end
			end
			nodes[r] = { crown = c, tinted = tinted }
		else
			local size = if mutationRanks[r] then 18 else 22
			local node = circle(pathFrame, size, Comic.Paper, 2.5)
			node.Position = UDim2.fromOffset(p.X, p.Y)
			node.ZIndex = 4
			local label = Comic.label(node, tostring(r), Comic.Display, if mutationRanks[r] then 12 else 14, Comic.Ink)
			label.Size = UDim2.fromScale(1, 1)
			label.ZIndex = 5
			local pulse = circle(pathFrame, size + 10, Comic.Paper)
			pulse.Position = UDim2.fromOffset(p.X, p.Y)
			pulse.BackgroundTransparency = 1
			pulse.ZIndex = 3
			local pulseStroke = Instance.new("UIStroke")
			pulseStroke.Color = Comic.Red
			pulseStroke.Thickness = 3
			pulseStroke.Parent = pulse
			nodes[r] = { node = node, label = label, pulse = pulse, pulseStroke = pulseStroke }
		end
		if mutationRanks[r] then
			mutationChips[r] = {}
			for option = 1, 2 do
				local dy = if option == 1 then -30 else 30
				local stub = segment(pathFrame, p, p + Vector2.new(0, dy * 0.7), 3, Comic.Ink, 3)
				local hex, fill, inkLayer = hexagon(pathFrame, 14, Comic.Paper, 3)
				hex.Position = UDim2.fromOffset(p.X, p.Y + dy)
				hex.ZIndex = 5
				local letter = Comic.label(hex, if option == 1 then "A" else "B", Comic.Display, 16, Comic.Ink)
				letter.Size = UDim2.fromScale(1, 1)
				letter.ZIndex = 6
				local scale = Instance.new("UIScale")
				scale.Parent = hex
				local hit = Instance.new("TextButton")
				hit.BackgroundTransparency = 1
				hit.Text = ""
				hit.AnchorPoint = Vector2.new(0.5, 0.5)
				hit.Position = UDim2.fromOffset(p.X, p.Y + dy)
				hit.Size = UDim2.fromOffset(34, 34)
				hit.ZIndex = 10
				hit.Parent = pathFrame
				mutationChips[r][option] = { hex = hex, fill = fill, ink = inkLayer, letter = letter, scale = scale, hit = hit, stub = stub }
			end
		end
	end

	-- Ficha de la mutación que señalas
	local holder, face = Comic.box(pathFrame, UDim2.fromOffset(438, 74), Comic.Paper, 3)
	holder.Position = UDim2.fromOffset(16, 148)
	local detailTitle = Comic.label(face, "", Comic.Display, 18, Comic.Ink)
	at(detailTitle, 10, 3, 418, 22)
	detailTitle.TextXAlignment = Enum.TextXAlignment.Left
	textLimit(detailTitle, 18, 10)
	detailTitle.ZIndex = 2
	local detailDesc = Comic.label(face, "", Comic.Body, 14, Comic.Ink)
	at(detailDesc, 10, 26, 418, 44)
	detailDesc.TextXAlignment = Enum.TextXAlignment.Left
	detailDesc.TextYAlignment = Enum.TextYAlignment.Top
	detailDesc.TextWrapped = true
	textLimit(detailDesc, 14, 8)
	detailDesc.ZIndex = 2

	pathView = {
		xpText = xpText,
		segs = segs,
		fills = fills,
		nodes = nodes,
		chips = mutationChips,
		detailFace = face,
		detailTitle = detailTitle,
		detailDesc = detailDesc,
	}
end

local function levelOf(def, rank: number)
	for _, level in def.mutations do
		if level.rank == rank then
			return level
		end
	end
	return nil
end

local function chosenOption(id: string, rank: number): number?
	return tonumber(mutsOf(id)[tostring(rank)])
end

showDetail = function(level: any, option: number)
	local def = selectedDef()
	if not def or not level then
		return
	end
	detailLevel = level
	detailOption = option
	local opt = level.options and level.options[option]
	if not opt then
		return
	end
	local reached = rankOf(def.id) >= level.rank
	local mark = if chosenOption(def.id, level.rank) == option and reached then "  (puesta)" else ""
	pathView.detailTitle.Text = "Rango " .. level.rank .. " · " .. (if option == 1 then "A" else "B") .. " · " .. tostring(opt.name) .. mark
	pathView.detailDesc.Text = tostring(opt.desc or "") .. (if reached then "" else "  (se abre en el rango " .. level.rank .. ")")
	pathView.detailFace.BackgroundColor3 = if reached then Comic.Paper else Color3.fromRGB(226, 216, 196)
end

local function paintPath(def)
	local id = def.id
	local rank = rankOf(id)
	local xp = xpOf(id)
	local k = 0
	if rank < MAX_RANK then
		local from, to = Castes.xpFor(rank), Castes.xpFor(rank + 1)
		k = math.clamp((xp - from) / math.max(to - from, 1), 0, 1)
		pathView.xpText.Text = "Rango " .. rank .. " · " .. Format.short(xp) .. " / " .. Format.short(to) .. " exp"
	else
		pathView.xpText.Text = "¡Maestría! +" .. math.floor(C.MasteryFood * 100 + 0.5) .. " % de comida"
	end
	for r, fill in pathView.fills do
		local amount = if r < rank then 1 elseif r == rank then k else 0
		fill.frame.BackgroundColor3 = def.color
		fill.frame.Visible = amount > 0
		fill.gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(math.clamp(amount, 0.001, 0.998), 0),
			NumberSequenceKeypoint.new(math.clamp(amount, 0.001, 0.998) + 0.001, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	for r, node in pathView.nodes do
		if node.crown then
			for _, f in node.tinted do
				f.BackgroundColor3 = if rank >= MAX_RANK then GOLD else Comic.Paper
			end
		else
			node.node.BackgroundColor3 = if r <= rank then def.color else Comic.Paper
			node.label.TextTransparency = if r <= rank then 0 else 0.45
			node.pulse.Visible = r == rank
		end
	end
	for r, pair in pathView.chips do
		local level = levelOf(def, r)
		local chosen = chosenOption(id, r)
		local reached = rank >= r
		for option, view in pair do
			local has = level ~= nil and level.options ~= nil and level.options[option] ~= nil
			view.hex.Visible = has
			view.hit.Visible = has
			view.stub.Visible = has
			local lit = reached and chosen == option
			paintLayer(view.fill, if lit then def.color elseif reached then Comic.Paper else Color3.fromRGB(214, 204, 186))
			paintLayer(view.ink, if lit then Comic.Red else Comic.Ink)
			view.letter.TextTransparency = if reached then 0 else 0.5
			view.stub.BackgroundColor3 = if lit then def.color else Comic.Ink
			view.scale.Scale = if lit then 1.15 else 1
		end
	end
	-- Detalle: el que señalabas, o la última mutación que ya tienes, o la primera
	local level = detailLevel
	if not level or not levelOf(def, level.rank) or levelOf(def, level.rank) ~= level then
		level = nil
		for _, candidate in def.mutations do
			if candidate.rank <= rank then
				level = candidate
			end
		end
		level = level or def.mutations[1]
		detailOption = if level then (chosenOption(id, level.rank) or 1) else 1
	end
	if level then
		showDetail(level, detailOption)
	else
		pathView.detailTitle.Text = "Sin mutaciones"
		pathView.detailDesc.Text = ""
	end
end

local function paintSheet(def)
	local resolved = resolvedFor(def.id)
	local rank = rankOf(def.id)
	local lines = {}
	for _, line in def.style do
		table.insert(lines, "• " .. tostring(line))
	end
	rows.style.Text = table.concat(lines, "\n")

	local passive = def.passive
	local p = rows[0]
	p.key.Text = ""
	if p.emblemFor ~= def.id then
		p.emblemFor = def.id
		for _, child in p.keyBox:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local mark = drawEmblem(p.keyBox, def, 38, def.color, 4)
		for _, d in mark:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex += 4
			end
		end
	end
	p.keyBox.BackgroundColor3 = Comic.Paper
	p.title.Text = tostring(passive.name or "Pasiva")
	p.meta.Text = "siempre"
	p.desc.Text = Castes.fill(passive.desc, resolved, passive.id)
	p.tag.Text = "PASIVA"
	p.tag.BackgroundColor3 = Comic.Cyan
	p.tag.Visible = true
	p.veil.Visible = false
	p.lock.Visible = false
	p.lockText.Visible = false
	p.face.BackgroundColor3 = Comic.Paper

	for slot = 1, 3 do
		local row = rows[slot]
		local ability = Castes.ability(def, slot)
		row.holder.Visible = ability ~= nil
		if not ability then
			continue
		end
		local need = ability.rank or 1
		local locked = rank < need
		row.key.Text = tostring(slot)
		row.title.Text = tostring(ability.name)
		local cd = tonumber(resolved.param(ability.id, "cooldown")) or tonumber(ability.cooldown) or 0
		row.meta.Text = seconds(cd)
		row.desc.Text = Castes.fill(ability.desc, resolved, ability.id)
		row.tag.Visible = ability.ultimate == true
		row.tag.Text = "DEFINITIVA"
		row.tag.BackgroundColor3 = GOLD
		row.face.BackgroundColor3 = if ability.ultimate then Color3.fromRGB(255, 240, 196) else Comic.Paper
		row.keyBox.BackgroundColor3 = if ability.ultimate then GOLD else Comic.Yellow
		row.veil.Visible = locked
		row.lock.Visible = locked
		row.lockText.Visible = locked
		row.lockText.Text = "Rango " .. need
	end
end

local function rebuildPreviewLook()
	local model = preview
	if not model then
		return
	end
	if previewAura then
		call("aura (quitar)", previewAura)
		previewAura = nil
	end
	local look = Stats.look(State.nodes(), State.royal(), State.depth(), State.num("Rebirths"), player:GetAttribute("Skin") or "rojo", player:GetAttribute("Hat") or "ninguno") :: any
	look.outfit = player:GetAttribute("Outfit")
	look.scale = 1
	local ok, err = pcall(AntLook.apply, model, look)
	if not ok then
		warn("[CRUNCH!] Castas (vista previa):", err)
	end
	model:PivotTo(PREVIEW_AT)
	previewFor = ""
end

local function ensurePreview()
	if preview or not previewWorld then
		return
	end
	local ok, model = pcall(AntModel.build)
	if not ok or not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Highlight") or d:IsA("LocalScript") or d:IsA("Script") then
			d:Destroy()
		end
	end
	model.Name = "CastePreview"
	model:PivotTo(PREVIEW_AT)
	model.Parent = previewWorld
	preview = model
	rebuildPreviewLook()
end

local function paintPreview(def)
	ensurePreview()
	local model = preview
	if not model or previewFor == def.id then
		return
	end
	previewFor = def.id
	if previewAura then
		call("aura (quitar)", previewAura)
		previewAura = nil
	end
	local rank = rankOf(def.id)
	local module = modules[def.id]
	local fn = if module and type(module.aura) == "function" then module.aura else genericAura(def)
	local ok, result = call(def.id .. ".aura (vista previa)", fn, model, rank, rank >= MAX_RANK)
	if ok and type(result) == "function" then
		previewAura = result
	end
end

local function paintHero(def)
	local active = activeId()
	local rank = rankOf(def.id)
	local open = unlocked(def)
	heroView.face.BackgroundColor3 = def.color:Lerp(Comic.Paper, 0.6)
	heroView.lines.ImageColor3 = def.color:Lerp(Comic.Ink, 0.15)
	heroView.burst.ImageColor3 = def.color
	heroView.name.Text = string.upper(def.name)
	heroView.nameShadow.Text = string.upper(def.name)
	heroView.name.TextColor3 = def.accent or def.color
	heroView.motto.Text = def.motto
	heroView.rankTag.Text = if not open
		then "Se abre en la capa " .. needDepth(def)
		elseif rank >= MAX_RANK then "¡Maestría!"
		else "Rango " .. rank .. " de " .. MAX_RANK
	heroView.stamp.Visible = active == def.id
	if not compact then
		paintPreview(def)
	end

	miniView.name.Text = string.upper(def.name)
	miniView.name.TextColor3 = def.accent or def.color
	miniView.motto.Text = def.motto
	if miniView.emblemFor ~= def.id then
		miniView.emblemFor = def.id
		miniView.emblemSlot:ClearAllChildren()
		drawEmblem(miniView.emblemSlot, def, 90, def.color, 2)
	end
end

local function paintButton()
	local def = selectedDef()
	if not def then
		return
	end
	local active = activeId()
	local left = (tonumber(player:GetAttribute("CasteSwitchAt")) or 0) - now()
	local text, color, enabled
	if not unlocked(def) then
		text, color, enabled = "Se abre en la capa " .. needDepth(def), Comic.DirtLight, false
	elseif active == def.id then
		text, color, enabled = "¡Ya eres " .. def.name .. "!", Comic.Green, false
	elseif active and left > 0 then
		text, color, enabled = "Podrás cambiar en " .. math.ceil(left) .. " s", Color3.fromRGB(226, 216, 196), false
	else
		text, color, enabled = "Ser " .. def.name, def.color, true
	end
	pickLabel.Text = text
	pickFace.BackgroundColor3 = color
	pickFace.AutoButtonColor = false
	pickLabel.TextTransparency = if enabled then 0 else 0.15
	pickFace:SetAttribute("Enabled", enabled)
end

paintPanel = function()
	if not gui then
		return
	end
	local def = selectedDef()
	paintCells()
	if not def then
		return
	end
	paintHero(def)
	paintSheet(def)
	paintPath(def)
	paintButton()
end

selectCaste = function(id: string)
	if not Castes.get(id) then
		return
	end
	if selected ~= id then
		selected = id
		detailLevel = nil
		Sfx.pop(1.2)
		if heroView.name then
			local s = heroView.name:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			s.Parent = heroView.name
			Comic.punch(s, 0.6)
		end
	end
	paintPanel()
end

local function layout()
	local camera = Workspace.CurrentCamera
	if not camera or not panel then
		return
	end
	local view = camera.ViewportSize
	local wide = math.min(view.Y / (PH + 40), view.X / (PW + 40))
	compact = wide < 0.72
	if not compact then
		local s = math.min(wide, 1.2)
		fit.Scale = s
		panel.Size = UDim2.fromOffset(PW, PH)
		vLeft.Size = UDim2.fromOffset(COL_W, PH)
		vLeft.Position = UDim2.fromOffset(0, 0)
		vHero.Visible = true
		vHero.Size = UDim2.fromOffset(HERO_W, PH)
		vHero.Position = UDim2.fromOffset(COL_W + GAP, 0)
		vSheet.Size = UDim2.fromOffset(SHEET_W, PH)
		vSheet.Position = UDim2.fromOffset(COL_W + HERO_W + GAP * 2, 0)
		heroMini.Parent = nil
		pickHolder.Parent = vHeroFace
		pickHolder.AnchorPoint = Vector2.new(0.5, 1)
		pickHolder.Position = UDim2.new(0.5, 0, 1, -20)
		sheet.Parent = sheetScroll
		sheet.Position = UDim2.fromOffset(0, 0)
		pathFrame.Parent = sheetScroll
		pathFrame.Position = UDim2.fromOffset(0, 405)
		sheetScroll.CanvasSize = UDim2.fromOffset(0, PH)
		colScroll.CanvasSize = UDim2.fromOffset(0, colContent.Size.Y.Offset)
	else
		local s = math.clamp(view.Y / 560, 0.7, 1.1)
		local width = 780
		if (view.X - 20) / s < width then
			s = math.max(0.45, (view.X - 20) / width)
		end
		fit.Scale = s
		local height = math.max(320, (view.Y - 20) / s)
		panel.Size = UDim2.fromOffset(width, height)
		vLeft.Size = UDim2.fromOffset(COL_W, height)
		vLeft.Position = UDim2.fromOffset(0, 0)
		vHero.Visible = false
		local sheetW = width - COL_W - GAP
		vSheet.Size = UDim2.fromOffset(sheetW, height)
		vSheet.Position = UDim2.fromOffset(COL_W + GAP, 0)
		local x = math.floor((sheetW - SHEET_W) / 2)
		heroMini.Parent = sheetScroll
		heroMini.Position = UDim2.fromOffset(x, 0)
		pickHolder.Parent = sheetScroll
		pickHolder.AnchorPoint = Vector2.new(0.5, 0)
		pickHolder.Position = UDim2.new(0.5, 0, 0, MINI_H + 4)
		sheet.Parent = sheetScroll
		sheet.Position = UDim2.fromOffset(x, MINI_H + 76)
		pathFrame.Parent = sheetScroll
		pathFrame.Position = UDim2.fromOffset(x, MINI_H + 76 + 408)
		sheetScroll.CanvasSize = UDim2.fromOffset(0, MINI_H + 76 + 408 + 232)
		colScroll.CanvasSize = UDim2.fromOffset(0, colContent.Size.Y.Offset)
	end
end

local function makeVignette(color: Color3, shadow: number): (Frame, Frame)
	local holder, face = Comic.box(panel, UDim2.fromOffset(100, 100), color, shadow)
	face.Active = true
	face.ClipsDescendants = true
	return holder, face
end

local function scroller(parent: Instance): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.Size = UDim2.fromScale(1, 1)
	s.ScrollingDirection = Enum.ScrollingDirection.Y
	s.ScrollBarThickness = 7
	s.ScrollBarImageColor3 = Comic.Ink
	s.ElasticBehavior = Enum.ElasticBehavior.Never
	s.ZIndex = 2
	s.Parent = parent
	return s
end

local function buildPanel()
	gui = Instance.new("ScreenGui")
	gui.Name = "Castes"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 22
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Fuera del panel: tinta con trama; un clic ahí cierra
	local backdrop = Instance.new("TextButton")
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Comic.Ink
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Parent = gui
	local dots = Comic.halftone(backdrop, Comic.Red, 45)
	dots.ImageTransparency = 0.7
	backdrop.MouseButton1Click:Connect(function()
		CasteClient.close()
	end)

	panel = Comic.frame(gui)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PW, PH)
	panel.ZIndex = 2
	fit = Instance.new("UIScale")
	fit.Parent = panel

	-- Viñeta izquierda: la colmena
	vLeft, vLeftFace = makeVignette(Color3.fromRGB(92, 58, 34), 8)
	local comb = Comic.halftone(vLeftFace, WAX, 180)
	comb.ImageTransparency = 0.55
	colScroll = scroller(vLeftFace)
	colContent = Comic.frame(colScroll)
	colContent.Size = UDim2.fromOffset(COL_W, PH)
	local title = Comic.label(vLeftFace, "CASTAS", Comic.Display, 40, Comic.Yellow)
	at(title, 14, 6, 200, 44)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Rotation = -4
	title.ZIndex = 30
	Comic.ink(title, 3)
	buildCells()

	-- Viñeta central
	vHero, vHeroFace = makeVignette(Comic.Yellow, 8)
	buildHero()

	-- Viñeta derecha: la ficha
	vSheet, vSheetFace = makeVignette(Comic.Paper, 8)
	local paperDots = Comic.halftone(vSheetFace, Comic.Cyan, 90)
	paperDots.ImageTransparency = 0.75
	sheetScroll = scroller(vSheetFace)
	buildMini()
	buildSheet()
	buildPath()

	-- El botón grande
	local holder, face = Comic.button(vHeroFace, UDim2.fromOffset(340, 62), Comic.Yellow, 5)
	pickHolder = holder
	pickFace = face
	holder.ZIndex = 9
	face.ZIndex = 9
	pickLabel = Comic.label(face, "", Comic.Display, 34, Comic.Ink)
	pickLabel.Size = UDim2.fromScale(1, 1)
	pickLabel.ZIndex = 10
	textLimit(pickLabel, 34, 14)
	pad(pickLabel, 12)
	face.MouseButton1Click:Connect(function()
		local def = selectedDef()
		if not def or face:GetAttribute("Enabled") ~= true or not remote then
			Sfx.pop(0.6)
			return
		end
		remote:FireServer("Pick", def.id)
		Sfx.fanfare()
	end)

	-- Cerrar
	local closeHolder, closeFace = Comic.button(vSheetFace, UDim2.fromOffset(42, 42), Comic.Red, 4)
	closeHolder.AnchorPoint = Vector2.new(1, 0)
	closeHolder.Position = UDim2.new(1, -12, 0, 10)
	closeHolder.ZIndex = 40
	closeFace.ZIndex = 40
	local cross = Comic.label(closeFace, "X", Comic.Display, 28, Comic.Paper)
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 41
	closeFace.MouseButton1Click:Connect(function()
		CasteClient.close()
	end)

	-- Clic en las mutaciones: elegir (si ya llegas) y enseñar su ficha
	for r, pair in pathView.chips do
		for option, view in pair do
			view.hit.MouseEnter:Connect(function()
				local def = selectedDef()
				local level = def and levelOf(def, r)
				if level then
					showDetail(level, option)
				end
			end)
			view.hit.MouseButton1Click:Connect(function()
				local def = selectedDef()
				local level = def and levelOf(def, r)
				if not def or not level then
					return
				end
				showDetail(level, option)
				if rankOf(def.id) >= r and chosenOption(def.id, r) ~= option and remote then
					remote:FireServer("Mutate", r, option, def.id)
					Comic.punch(view.scale, 1.5)
					Sfx.pop(1.35)
				elseif rankOf(def.id) < r then
					Sfx.pop(0.7)
				end
			end)
		end
	end

	layout()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
end

local function hideCallout()
	if callout then
		callout:Destroy()
		callout = nil
	end
end

function CasteClient.isOpen(): boolean
	return panelOpen
end

function CasteClient.open()
	if not gui then
		return
	end
	panelOpen = true
	hideCallout()
	stopAiming()
	if not selected or not Castes.get(selected) then
		local active = activeId()
		selected = active
		if not selected then
			for _, def in list() do
				if unlocked(def) then
					selected = def.id
					break
				end
			end
		end
		selected = selected or (list()[1] and list()[1].id)
	end
	layout()
	rebuildPreviewLook()
	paintPanel()
	gui.Enabled = true
	Sfx.pop(0.9)
	local s = Instance.new("UIScale")
	s.Parent = panel
	Comic.punch(s, 0.85)
	task.delay(0.35, function()
		s:Destroy()
	end)
	if not spinConnection then
		spinConnection = RunService.RenderStepped:Connect(function(dt)
			if heroView.burst then
				heroView.burst.Rotation = (heroView.burst.Rotation + dt * 9) % 360
			end
			local camera = previewCamera
			local model = preview
			if camera and model and not compact then
				previewAngle += dt * 0.55
				local center = model:GetPivot().Position + Vector3.new(0, 0.2, 0)
				local dist = 8.2
				camera.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(previewAngle) * dist, 2.4, math.cos(previewAngle) * dist), center)
			end
			-- El rango actual late en el camino
			local def = selectedDef()
			if def then
				local node = pathView.nodes and pathView.nodes[rankOf(def.id)]
				if node and node.pulseStroke then
					node.pulseStroke.Transparency = 0.5 + 0.5 * math.sin(os.clock() * 6)
				end
			end
		end)
	end
	if sideButton then
		sideButton.setBadge(false)
	end
end

function CasteClient.close()
	panelOpen = false
	if gui then
		gui.Enabled = false
	end
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

function CasteClient.toggle()
	if panelOpen then
		CasteClient.close()
	else
		CasteClient.open()
	end
end

-- Botón lateral y el aviso "¡Elige tu casta!" la primera vez que llegas a la capa 2 sin casta
local function showCallout()
	if callout or not sideButton or not sideButton.holder then
		return
	end
	local label = chip(sideButton.holder, "¡Elige tu casta!", Comic.Yellow, 17, -4)
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.new(1, 12, 0.5, 0)
	label.ZIndex = 8
	Comic.boil(label, 2)
	callout = label
	local s = Instance.new("UIScale")
	s.Parent = label
	Comic.punch(s, 0.3)
end

local function refreshSide()
	if not sideButton then
		return
	end
	local any = false
	for _, def in list() do
		if unlocked(def) then
			any = true
			break
		end
	end
	sideButton.setVisible(any)
	local needsPick = any and activeId() == nil
	sideButton.setBadge(needsPick and not panelOpen)
	if needsPick and not announced and player:GetAttribute("Loaded") == true then
		announced = true
		showCallout()
		Bubble.flash("¡Ya puedo elegir casta! " .. (if KEYBOARD then "Pulsa K" else "Toca Castas"), 6)
	elseif not needsPick then
		hideCallout()
	end
end

---------------------------------------------------------------------------------------------------

local function loadModules()
	local folder = script.Parent:FindFirstChild("Castes")
	if not folder then
		return
	end
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, lib = pcall(require, child)
			if ok and type(lib) == "table" then
				modules[child.Name] = lib
			else
				warn("[CRUNCH!] Efectos de la casta", child.Name, "no se pudieron cargar:", lib)
			end
		end
	end
end

function CasteClient.start(remotes: Folder)
	loadModules()
	buildBar()
	buildPanel()
	onRankUpMine = rankBanner

	sideButton = Hud.addSideButton("Castas", "K", Color3.fromRGB(255, 176, 64), CasteClient.toggle)
	refreshSide()

	-- Todas las hormigas llevan el aura de su casta
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(other)
		local st = auras[other]
		if st and st.cleanup then
			call("aura (quitar)", st.cleanup)
		end
		auras[other] = nil
	end)

	local fx = remotes:WaitForChild("Fx") :: RemoteEvent
	fx.OnClientEvent:Connect(onFx)

	-- Lo que cambia la barra, el panel y el aviso lateral
	for _, name in { "Caste", "CasteData", "CasteRank", "CasteSwitchAt", "Depth", "Loaded" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			refreshSide()
			if panelOpen then
				paintPanel()
			end
		end)
	end
	player:GetAttributeChangedSignal("Caste"):Connect(function()
		stopAiming()
		local id = activeId()
		if id and panelOpen then
			selected = id
			paintPanel()
		end
	end)
	for _, name in { "Skin", "Hat", "Outfit" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if panelOpen then
				rebuildPreviewLook()
				paintPanel()
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape then
			if panelOpen then
				CasteClient.close()
			end
			stopAiming()
			return
		end
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.K then
			CasteClient.toggle()
			return
		end
		local slot = SLOT_KEYS[input.KeyCode]
		if slot and not panelOpen and activeId() then
			beginAim(slot)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local slot = SLOT_KEYS[input.KeyCode]
		if slot then
			releaseAim(slot)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.05)
			local ok, err = pcall(updateBar)
			if not ok then
				warn("[CRUNCH!] Castas (barra):", err)
				task.wait(1)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			if panelOpen then
				pcall(paintButton)
			end
		end
	end)

	remote = remotes:WaitForChild("Caste", 30) :: RemoteEvent?
end

return CasteClient
