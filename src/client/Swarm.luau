-- Dibuja las obreras de cada colonia. El servidor solo publica cuántas hay y a qué comida van
-- (TrailPos/TrailRadius/TrailColor en el hormiguero); aquí se convierten en filas de hormigas.
-- Cada hormiga tiene una posición objetivo que sale de una fórmula y una posición recordada que
-- la persigue con la velocidad limitada: así, si el destino cambia, corren a reincorporarse en
-- vez de aparecer de golpe. Las rutas también se suavizan: si el destino cambia (con colonias
-- grandes cambia varias veces por segundo), su final se desliza en vez de saltar, y cada hormiga
-- se queda en su ruta mientras exista. Todas las piezas se mueven de una vez con BulkMoveTo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AntModel = require(ReplicatedStorage.Shared.AntModel)
local Config = require(ReplicatedStorage.Shared.Config)
local Comic = require(script.Parent.Comic)

local Swarm = {}

local PARKED = CFrame.new(0, -60, 0)
local TAU = math.pi * 2

local CHASE = 4 -- al reincorporarse corren como mucho 4 veces su paso normal
local EASE = 1.2 -- velocidad extra por cada stud de distancia a su sitio (frenan al llegar)
local RUN_ENTER = 2.5 -- a más de esto de su sitio, corren mirando hacia él
local RUN_EXIT = 1 -- y dejan de correr al acercarse a menos de esto
local REAIM = 1.5 -- solo cambian de rumbo si el sitio se movió más que esto
local GRACE = 1.5 -- segundos sin destino antes de ponerse a deambular
local GLIDE = 45 -- studs/s a los que se desliza el final de una ruta cuando cambia el destino
local GLIDE_TIME = 2.8 -- y como mucho tarda esto, aunque el salto sea enorme
local VIEW = 400 -- más lejos que esto (hormiguero y rutas) no se calcula nada
local SNAP = 40 -- fuera de cámara, más lejos que esto de su sitio se recolocan sin correr
local HIDDEN = 220 -- nunca se recoloca de golpe nada a menos de esto de la cámara

local SOLDIER_SIZE = 1.7
local SOLDIER_PACE = 0.88 -- las soldado van un pelín más despacio
local SOLDIER_TINT = 0.35
local SOLDIER_LOCAL = 5
local SOLDIER_OTHER = 2

-- Piezas relativas al centro de la hormiga (frente = -Z), escaladas por k
local function shape(k: number, stepRate: number)
	local legs = { {}, {} } -- dos poses de patas que se alternan al andar
	for pose = 1, 2 do
		for i, yaw in { -38, 0, 38 } do
			local swing = if (i + pose) % 2 == 0 then 14 else -14
			legs[pose][i] = CFrame.new(0, -0.2 * k, 0) * CFrame.Angles(0, math.rad(yaw + swing), 0)
		end
	end
	return {
		k = k,
		lift = 0.1 + 0.4 * k, -- altura del centro sobre el suelo: el abdomen roza el suelo
		stepRate = stepRate,
		body = {
			CFrame.new(0, 0.05 * k, 0.72 * k), -- abdomen
			CFrame.new(0, 0, 0), -- tórax
			CFrame.new(0, 0.1 * k, -0.62 * k), -- cabeza
		},
		legs = legs,
		chunk = CFrame.new(0, 0.3 * k, -1.25 * k),
		-- Mandíbulas (solo soldado): bisagra delante de la cabeza
		jawL = CFrame.new(-0.42, -0.02, -1.5),
		jawR = CFrame.new(0.42, -0.02, -1.5),
	}
end

local WORKER = shape(1, 1.6)
local SOLDIER = shape(SOLDIER_SIZE, 1)
local JAW_TIP = CFrame.new(0, 0, -0.5)

local container: Model
local rng = Random.new(5)
local colonies: { [Model]: any } = {}
local order: { any } = {} -- mismas colonias, en orden fijo para que piezas y CFrames cuadren
local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local partsDirty = true

local markers: { BillboardGui } = {}
local markerBursts: { ImageLabel } = {}
local markerLabels: { TextLabel } = {}
local markerNear: { boolean? } = {}
local MARKER_NEAR = 25 -- a menos de esto de tu hormiga la bandera se apaga: ya ves la comida
local MARKER_FADE = 0.65 -- transparencia cerca (se ve al ~35 %)
local anchors: { BasePart } = {}
local anchorAt: { Vector3? } = {}
local markerWant = { false, false, false }
local markerAt: { Vector3 } = { Vector3.zero, Vector3.zero, Vector3.zero }

local function piece(size: Vector3, color: Color3, kind: string): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.Color = color
	part.CFrame = PARKED
	if kind == "blob" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	elseif kind == "rod" then
		part.Shape = Enum.PartType.Cylinder
	end
	part.Parent = container
	return part
end

local function newAnt(soldier: boolean)
	local k = if soldier then SOLDIER_SIZE else 1
	local body = if soldier then AntModel.Body:Lerp(AntModel.Ink, SOLDIER_TINT) else AntModel.Body
	local bodyDark = if soldier then AntModel.BodyDark:Lerp(AntModel.Ink, SOLDIER_TINT) else AntModel.BodyDark
	local list = {
		piece(Vector3.new(1, 0.9, 1.3) * k, bodyDark, "blob"),
		piece(Vector3.new(0.62, 0.58, 0.62) * k, body, "blob"),
		piece(Vector3.new(0.95, 0.85, 0.85) * k, body, "blob"),
		piece(Vector3.new(2, 0.11, 0.11) * k, AntModel.Ink, "rod"),
		piece(Vector3.new(2, 0.11, 0.11) * k, AntModel.Ink, "rod"),
		piece(Vector3.new(2, 0.11, 0.11) * k, AntModel.Ink, "rod"),
		piece(Vector3.new(0.6, 0.6, 0.6) * k, Comic.Crumb, "blob"),
	}
	if soldier then
		table.insert(list, piece(Vector3.new(0.28, 0.24, 1), AntModel.Ink, "block"))
		table.insert(list, piece(Vector3.new(0.28, 0.24, 1), AntModel.Ink, "block"))
	end
	return {
		soldier = soldier,
		shape = if soldier then SOLDIER else WORKER,
		phase = rng:NextNumber(),
		jitter = rng:NextNumber(-0.45, 0.45),
		seed = rng:NextNumber(),
		w1 = rng:NextNumber(0.12, 0.3), -- ritmo propio al deambular
		w2 = rng:NextNumber(0.1, 0.25),
		stride = rng:NextNumber(0, 4),
		pos = nil :: Vector3?,
		heading = -Vector3.zAxis,
		slot = 0, -- ruta (1..3) que tiene asignada; 0 = ninguna
		running = false,
		aim = Vector3.zero, -- punto hacia el que corre; solo se renueva si el sitio se aleja de él
		parts = list,
	}
end

local function resize(list: { any }, count: number, soldier: boolean)
	if #list == count then
		return
	end
	while #list < count do
		table.insert(list, newAnt(soldier))
	end
	while #list > count do
		local ant = table.remove(list)
		for _, part in ant.parts do
			part:Destroy()
		end
	end
	partsDirty = true
end

local function newColony(hill: Model)
	-- Una ruta por hueco publicado (TrailPos1..3). No se compactan: cada hormiga recuerda su hueco.
	local routes = {}
	for i = 1, 3 do
		routes[i] = {
			alive = false, -- publicada ahora o hace menos de GRACE
			seen = -math.huge,
			target = Vector3.zero, -- último TrailPos publicado
			shown = Vector3.zero, -- final que se dibuja: se desliza hacia target
			glide = GLIDE,
			radius = 1,
			from = Vector3.zero,
			to = Vector3.zero,
			delta = Vector3.zero,
			dir = Vector3.xAxis,
			side = Vector3.zAxis,
			span = 1,
			color = Comic.Crumb,
			-- Avance acumulado de la fila (en vueltas). Acumular en vez de travel/span hace que
			-- estirar o encoger la ruta no baraje a las hormigas por toda ella.
			u = 0,
			uSoldier = 0,
		}
	end
	local soldiers, ants = {}, {}
	return {
		hill = hill,
		soldiers = soldiers,
		ants = ants,
		lists = { soldiers, ants },
		isLocal = false,
		routes = routes,
		routeCount = 0, -- rutas vivas
		mask = 0, -- qué huecos estaban vivos en el último reparto
		assigned = -1, -- cuántas hormigas había en el último reparto
		shareKey = "", -- TrailShare1..3 del último reparto (escuadrones)
		weights = nil :: { number }?,
		counts = { 0, 0, 0 },
		quota = { 0, 0, 0 },
		culled = false,
		hillPos = Vector3.zero,
		door = Vector3.zero,
		ring = 12,
		ground = Config.GroundY,
		speed = Config.Worker.Speed,
	}
end

local function rebuildParts()
	table.clear(parts)
	table.clear(cframes)
	for _, colony in order do
		for _, ant in colony.soldiers do
			for _, part in ant.parts do
				table.insert(parts, part)
			end
		end
		for _, ant in colony.ants do
			for _, part in ant.parts do
				table.insert(parts, part)
			end
		end
	end
	partsDirty = false
end

local function makeMarker(index: number): BillboardGui
	local anchor = Instance.new("Part")
	anchor.Name = "TrailAnchor" .. index
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = PARKED
	anchor.Parent = Workspace:FindFirstChild("SwarmMarkers")
	anchors[index] = anchor

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TrailMarker"
	billboard.Size = UDim2.fromOffset(42, 42)
	billboard.AlwaysOnTop = true -- de lejos, para encontrarla; de cerca se apaga (ver abajo)
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Adornee = anchor
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local burst = Comic.burst(billboard, 40, Comic.Cyan)
	local label = Comic.label(burst, tostring(index), Comic.Display, 19, Comic.Ink)
	label.Size = UDim2.fromScale(1, 1)
	Comic.boil(burst, 5)
	markerBursts[index] = burst
	markerLabels[index] = label
	return billboard
end

-- Distancia en planta de p al segmento a-b
local function segmentDistance(p: Vector3, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 0 then
		t = math.clamp(((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2, 0, 1)
	end
	local dx = p.X - (a.X + abx * t)
	local dz = p.Z - (a.Z + abz * t)
	return math.sqrt(dx * dx + dz * dz)
end

-- Lee los destinos publicados y actualiza las rutas de la colonia (reutiliza sus tablas).
-- El final de cada ruta no salta al nuevo destino: se desliza hacia él. Un hueco que deja de
-- publicarse sigue vivo GRACE segundos con su último final, por si llega otro destino enseguida.
-- Devuelve la máscara de huecos vivos y cuántos hay.
local function updateRoutes(colony, hill: Model, scale: number, showMarkers: boolean, clock: number, dt: number): (number, number)
	local hillPos = colony.hillPos
	local ground = colony.ground
	local mask, alive = 0, 0
	for i = 1, 3 do
		local route = colony.routes[i]
		local foodPos = hill:GetAttribute("TrailPos" .. i)
		if typeof(foodPos) == "Vector3" then
			local radius = hill:GetAttribute("TrailRadius" .. i)
			route.radius = if type(radius) == "number" then radius else 1
			local color = hill:GetAttribute("TrailColor" .. i)
			route.color = if typeof(color) == "Color3" then color else Comic.Crumb
			if not route.alive then
				-- Ruta nueva: aparece ya en su sitio (las hormigas caminan hacia ella)
				route.shown = foodPos
				route.target = foodPos
				route.u = 0
				route.uSoldier = 0
			elseif foodPos ~= route.target then
				-- Nuevo destino en el mismo hueco: se desliza; los saltos grandes, más deprisa
				route.target = foodPos
				route.glide = math.max(GLIDE, (foodPos - route.shown).Magnitude / GLIDE_TIME)
			end
			route.alive = true
			route.seen = clock
			-- Marked: cuántos de los primeros huecos son rastros a mano (con escuadrones, los demás no)
			local marked = hill:GetAttribute("Marked")
			if showMarkers and (type(marked) ~= "number" or i <= marked) then
				markerWant[i] = true
				markerAt[i] = foodPos + Vector3.new(0, 5 + route.radius, 0)
			end
		elseif route.alive and clock - route.seen > GRACE then
			route.alive = false
		end

		if not route.alive then
			continue
		end
		mask += 2 ^ (i - 1)
		alive += 1

		local gap = route.target - route.shown
		local distance = gap.Magnitude
		local stepLen = route.glide * dt
		route.shown = if distance <= stepLen then route.target else route.shown + gap * (stepLen / distance)

		local endPos = route.shown
		-- Fuera del jardín, las obreras van y vuelven del hormiguero de esa zona (Config.depotPos)
		local base, gap0 = hillPos, 9 * scale
		local depot = Config.depotPos(Config.zoneAt(endPos.Z))
		if depot then
			base, gap0 = depot, 6 * Config.Depot.Scale
		end
		local flat = (endPos - base) * Vector3.new(1, 0, 1)
		local length = flat.Magnitude
		local dir = if length > 0.1 then flat / length else Vector3.xAxis
		local from = base + dir * gap0
		local to = endPos - dir * (route.radius + 0.4)
		route.from = Vector3.new(from.X, ground, from.Z)
		route.to = Vector3.new(to.X, ground, to.Z)
		route.delta = route.to - route.from
		route.dir = dir
		route.side = dir:Cross(Vector3.yAxis)
		route.span = math.max(route.delta.Magnitude, 1)
		route.u = (route.u + colony.speed * dt / (2 * route.span)) % 1
		route.uSoldier = (route.uSoldier + colony.speed * SOLDIER_PACE * dt / (2 * route.span)) % 1
	end
	return mask, alive
end

-- Reparte las hormigas entre las rutas vivas sin mover a las que ya están en una que sigue viva:
-- solo cambian de ruta las de un hueco que desapareció o las que sobran para llenar uno nuevo.
local function rebalance(colony, alive: number)
	local routes = colony.routes
	local counts = colony.counts
	local quota = colony.quota
	local total = #colony.soldiers + #colony.ants
	for s = 1, 3 do
		counts[s] = 0
		quota[s] = 0
	end
	if alive == 0 then
		return
	end

	for _, list in colony.lists do
		for _, ant in list do
			local slot = ant.slot
			if slot > 0 and routes[slot].alive then
				counts[slot] += 1
			else
				ant.slot = 0
			end
		end
	end

	local weights = colony.weights -- escuadrones (TrailShare1..3): filas según su parte
	if weights then
		local sum = 0
		for s = 1, 3 do
			if routes[s].alive then
				sum += weights[s]
			end
		end
		local given = 0
		for s = 1, 3 do
			if routes[s].alive and sum > 0 then
				quota[s] = math.max(math.floor(total * weights[s] / sum), if total >= alive then 1 else 0)
				given += quota[s]
			end
		end
		for s = 1, 3 do
			if routes[s].alive and given < total then
				quota[s] += total - given
				given = total
			end
		end
	else
		local base = total // alive
		local extra = total % alive
		for s = 1, 3 do
			if routes[s].alive then
				quota[s] = base + (if extra > 0 then 1 else 0)
				extra -= 1
			end
		end
	end

	-- Las que sobran en una ruta (empezando por las últimas) quedan libres
	for l = #colony.lists, 1, -1 do
		local list = colony.lists[l]
		for i = #list, 1, -1 do
			local ant = list[i]
			local slot = ant.slot
			if slot > 0 and counts[slot] > quota[slot] then
				counts[slot] -= 1
				ant.slot = 0
			end
		end
	end

	-- Y las libres van a las rutas que tienen hueco
	for _, list in colony.lists do
		for _, ant in list do
			if ant.slot == 0 then
				for s = 1, 3 do
					if counts[s] < quota[s] then
						counts[s] += 1
						ant.slot = s
						break
					end
				end
			end
		end
	end
end

local function drawAnt(colony, ant, n: number, dt: number, clock: number, camPos: Vector3): number
	local form = ant.shape
	local soldier = ant.soldier
	local groundY = colony.ground + form.lift

	-- 1. Dónde debería estar según la fórmula
	local target: Vector3
	local routeHeading: Vector3? = nil
	local carrying = false
	local slot = ant.slot
	if colony.routeCount > 0 and slot > 0 and colony.routes[slot].alive then
		local route = colony.routes[slot]
		local u = ((if soldier then route.uSoldier else route.u) + ant.phase) % 1
		local going = u < 0.5
		local f = if going then u * 2 else 2 - u * 2
		-- Ida y vuelta por carriles distintos, como una fila de verdad
		local lane = ((if going then 0.8 else -0.8) + ant.jitter) * (if soldier then 1.6 else 1)
		local p = route.from + route.delta * f + route.side * lane
		target = Vector3.new(p.X, groundY, p.Z)
		routeHeading = if going then route.dir else -route.dir
		carrying = not going
		local chunk = ant.parts[7]
		if chunk.Color ~= route.color then
			chunk.Color = route.color
		end
	else
		-- Sin comida a la vista deambulan alrededor del montículo, cada una a su ritmo
		local hillPos = colony.hillPos
		local angle = ant.seed * TAU + 0.5 * math.sin(clock * ant.w1 + ant.seed * 31)
		local radius = colony.ring
			+ ant.jitter * 5
			+ 1.8 * math.sin(clock * ant.w2 + ant.seed * 17)
			+ (if soldier then 1.5 else 0)
		target = Vector3.new(hillPos.X + math.cos(angle) * radius, groundY, hillPos.Z + math.sin(angle) * radius)
	end

	-- 2. La posición recordada persigue al objetivo con la velocidad limitada
	-- Nunca aparece de golpe a la vista: recién nacida sale por la puerta; tras estar fuera de
	-- vista se coloca en su sitio solo si ese sitio también está lejos de la cámara.
	local pos = ant.pos
	if not pos then
		local spawnAtTarget = colony.culled and (target - camPos).Magnitude > HIDDEN
		pos = if spawnAtTarget then target else Vector3.new(colony.door.X, groundY, colony.door.Z)
	end
	local gap = target - pos
	local dist = gap.Magnitude
	local moved = 0
	if dist > SNAP and (pos - camPos).Magnitude > HIDDEN and (target - camPos).Magnitude > HIDDEN then
		pos = target
		ant.running = false
	elseif dist > 1e-4 then
		-- Persecución que frena al llegar: deprisa si está lejos, a su paso si está cerca
		local speed = colony.speed
		local limit = math.min(speed * CHASE, speed + dist * EASE * speed / 2) * dt
		if dist > limit then
			pos += gap * (limit / dist)
			moved = limit
		else
			pos = target
			moved = dist
		end
	end
	ant.pos = pos
	ant.stride += moved

	-- 3. Rumbo con histéresis: corriendo apunta a un punto que solo se renueva si su sitio se
	-- aleja más de REAIM (así no gira cada fotograma si el sitio tiembla); andando, el de la ruta.
	if ant.running then
		if dist < RUN_EXIT then
			ant.running = false
		end
	elseif dist > RUN_ENTER then
		ant.running = true
		ant.aim = target
	end

	local desired: Vector3? = nil
	if ant.running then
		if (target - ant.aim).Magnitude > REAIM then
			ant.aim = target
		end
		local toAim = Vector3.new(ant.aim.X - pos.X, 0, ant.aim.Z - pos.Z)
		if toAim.Magnitude > 0.3 then
			desired = toAim.Unit
		end
	elseif routeHeading then
		desired = routeHeading
	elseif moved > 1e-4 then
		-- Deambulando: hacia donde se mueve
		local step = Vector3.new(gap.X, 0, gap.Z)
		if step.Magnitude > 1e-4 then
			desired = step.Unit
		end
	end
	if desired then
		local turned = ant.heading:Lerp(desired, math.min(1, dt * 10))
		-- Media vuelta (al llegar a la comida o al hormiguero): gira de una vez
		ant.heading = if desired:Dot(ant.heading) < -0.3 or turned.Magnitude < 0.2 then desired else turned.Unit
	end

	-- 4. Piezas
	local step = ant.stride * form.stepRate + ant.seed * 10
	local up = pos + Vector3.new(0, math.abs(math.sin(step * 2)) * 0.1 * form.k, 0)
	local base = CFrame.lookAt(up, up + ant.heading)
	local legs = form.legs[math.floor(step) % 2 + 1]
	local body = form.body

	cframes[n + 1] = base * body[1]
	cframes[n + 2] = base * body[2]
	cframes[n + 3] = base * body[3]
	cframes[n + 4] = base * legs[1]
	cframes[n + 5] = base * legs[2]
	cframes[n + 6] = base * legs[3]
	cframes[n + 7] = if carrying then base * form.chunk else PARKED
	n += 7
	if soldier then
		-- Mandíbulas que se abren y cierran despacio
		local clack = math.rad(16 + 10 * math.sin(clock * 5 + ant.seed * 20))
		cframes[n + 1] = base * form.jawL * CFrame.Angles(0, -clack, 0) * JAW_TIP
		cframes[n + 2] = base * form.jawR * CFrame.Angles(0, clack, 0) * JAW_TIP
		n += 2
	end
	return n
end

local function park(list: { any }, n: number): number
	for _, ant in list do
		for _ = 1, #ant.parts do
			n += 1
			cframes[n] = PARKED
		end
		ant.pos = nil
	end
	return n
end

function Swarm.start()
	container = Instance.new("Model")
	container.Name = "Swarm"
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = Comic.Ink
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = container
	container.Parent = Workspace

	-- Anclas invisibles de las banderas de rastro (fuera del modelo para que no las contornee)
	local markerFolder = Instance.new("Folder")
	markerFolder.Name = "SwarmMarkers"
	markerFolder.Parent = Workspace
	for i = 1, 3 do
		markers[i] = makeMarker(i)
	end

	local player = Players.LocalPlayer
	local maxLocal = Config.Swarm.MaxLocal
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		maxLocal = math.floor(maxLocal / 2) -- los móviles mueven menos piezas
	end

	RunService.Heartbeat:Connect(function(rawDt)
		local hills = Workspace:FindFirstChild("Anthills")
		if not hills then
			return
		end
		local dt = math.min(rawDt, 0.25)
		local now = Workspace:GetServerTimeNow()
		local clock = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero

		-- Ajusta cuántas hormigas se dibujan por colonia
		for _, hill in hills:GetChildren() do
			if not hill:IsA("Model") then
				continue
			end
			local owner = hill:GetAttribute("OwnerId") or 0
			local workers = if owner == 0 then 0 else (hill:GetAttribute("Workers") or 0)
			local colony = colonies[hill]
			if not colony then
				colony = newColony(hill)
				colonies[hill] = colony
				table.insert(order, colony)
			end
			local isLocal = owner == player.UserId
			colony.isLocal = isLocal
			local total = math.min(workers, if isLocal then maxLocal else Config.Swarm.MaxOther)
			local soldiers = math.min(hill:GetAttribute("Soldiers") or 0, if isLocal then SOLDIER_LOCAL else SOLDIER_OTHER, total)
			soldiers = math.max(math.floor(soldiers), 0)
			resize(colony.soldiers, soldiers, true)
			resize(colony.ants, math.max(math.floor(total) - soldiers, 0), false)
		end
		-- Colonias cuyo hormiguero ya no está (o salió del streaming)
		for i = #order, 1, -1 do
			local colony = order[i]
			if colony.hill.Parent ~= hills then
				resize(colony.soldiers, 0, true)
				resize(colony.ants, 0, false)
				colonies[colony.hill] = nil
				table.remove(order, i)
				partsDirty = true
			end
		end
		if partsDirty then
			rebuildParts()
		end

		local n = 0
		for _, colony in order do
			local hill = colony.hill
			local scale = hill:GetAttribute("Scale") or 1
			local hillPos = hill:GetPivot().Position
			colony.hillPos = hillPos
			colony.ground = Config.GroundY
			colony.ring = 8.5 * scale + 4

			local frenzy = now < (hill:GetAttribute("FrenzyUntil") or 0)
			colony.speed = (hill:GetAttribute("WorkerSpeed") or Config.Worker.Speed) * (if frenzy then 2 else 1)

			-- Las banderas solo señalan rastros que marcaste tú, no el destino automático.
			-- Sin destino, las rutas viejas siguen vivas GRACE segundos; después, a deambular.
			local showMarkers = colony.isLocal and hill:GetAttribute("Auto") == false
			local mask, alive = updateRoutes(colony, hill, scale, showMarkers, clock, dt)
			colony.routeCount = alive

			local total = #colony.ants + #colony.soldiers
			if total == 0 then
				continue
			end
			-- Escuadrones (módulo Orders): parte de las obreras de cada hueco; sin ella, filas iguales
			local share1, share2, share3 = hill:GetAttribute("TrailShare1"), hill:GetAttribute("TrailShare2"), hill:GetAttribute("TrailShare3")
			local weighted = type(share1) == "number" or type(share2) == "number" or type(share3) == "number"
			local shareKey = if weighted then string.format("%s|%s|%s", tostring(share1), tostring(share2), tostring(share3)) else ""
			if shareKey ~= colony.shareKey then
				colony.shareKey = shareKey
				colony.weights = if weighted
					then {
						if type(share1) == "number" then share1 else 0,
						if type(share2) == "number" then share2 else 0,
						if type(share3) == "number" then share3 else 0,
					}
					else nil
				colony.assigned = -1 -- fuerza el reparto
			end
			-- Reparto estable: solo se rehace si cambian las rutas vivas, el número de hormigas o su parte
			if mask ~= colony.mask or total ~= colony.assigned then
				colony.mask = mask
				colony.assigned = total
				rebalance(colony, alive)
			end

			-- Lejos de la cámara (hormiguero y rutas): se aparcan sin hacer cuentas
			local near = (hillPos - camPos).Magnitude < VIEW
			if not near then
				for r = 1, 3 do
					local route = colony.routes[r]
					if route.alive and segmentDistance(camPos, route.from, route.to) < VIEW then
						near = true
						break
					end
				end
			end
			if not near then
				n = park(colony.soldiers, n)
				n = park(colony.ants, n)
				colony.culled = true
				continue
			end

			local inward = Vector3.new(-hillPos.X, 0, -hillPos.Z)
			inward = if inward.Magnitude > 0.1 then inward.Unit else Vector3.xAxis
			colony.door = hillPos + inward * (8.5 * scale)

			for _, ant in colony.soldiers do
				n = drawAnt(colony, ant, n, dt, clock, camPos)
			end
			for _, ant in colony.ants do
				n = drawAnt(colony, ant, n, dt, clock, camPos)
			end
			colony.culled = false
		end

		-- Banderas de rastro. Cerca de tu hormiga se apagan y dejan de dibujarse encima de todo,
		-- así tu propio personaje las tapa en vez de quedar tapado por ellas.
		local character = player.Character
		local me = character and character:FindFirstChild("HumanoidRootPart")
		local myPos = if me and me:IsA("BasePart") then me.Position else nil
		for i = 1, 3 do
			if markerWant[i] then
				local near = myPos ~= nil and (markerAt[i] - myPos).Magnitude < MARKER_NEAR
				if near ~= markerNear[i] then
					markerNear[i] = near
					local fade = if near then MARKER_FADE else 0
					markers[i].AlwaysOnTop = not near
					markerBursts[i].ImageTransparency = fade
					markerLabels[i].TextTransparency = fade
				end
			end
		end
		for i = 1, 3 do
			local marker = markers[i]
			local want = markerWant[i]
			if want and anchorAt[i] ~= markerAt[i] then
				anchorAt[i] = markerAt[i]
				anchors[i].CFrame = CFrame.new(markerAt[i])
			end
			if marker.Enabled ~= want then
				marker.Enabled = want
			end
			markerWant[i] = false
		end

		if n > 0 and n == #parts then
			Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

-- Ruta viva i (1..3) de la colonia de ese hormiguero, o nil. Solo lectura: la usa el módulo Orders
-- para plantar el banderín de cada escuadrón a la cabeza de su fila.
function Swarm.route(hill: Model, i: number)
	local colony = colonies[hill]
	local route = colony and colony.routes[i]
	return if route and route.alive then route else nil
end

return Swarm
