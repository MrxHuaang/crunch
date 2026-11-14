-- Encuadre de las vistas previas 3D (ViewportFrame de Castas y del Vestidor): la cámara gira
-- alrededor del modelo y lo ve siempre entero, centrado y con margen, sea cual sea su tamaño
-- (alas, trajes voluminosos, auras). Se mide la caja real de las piezas visibles, no el pivote
-- (el pivote de la hormiga es la raíz, en el tórax: el abdomen queda muy a un lado).

local ViewFit = {}

local MARGIN = 1.18 -- aire alrededor del modelo
local REMEASURE = 0.4 -- segundos entre medidas (las auras se mueven y crecen)
local LIFT = 0.22 -- la cámara mira un poco desde arriba

-- Caja de mundo de las piezas visibles. Devuelve (centro, radio horizontal, media altura).
-- `below`: espacio extra por debajo (la peana del Vestidor).
function ViewFit.measure(model: Model, below: number?): (Vector3, number, number)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local any = false
	for _, part in model:GetDescendants() do
		-- La raíz invisible y las cajas de choque no cuentan
		if part:IsA("BasePart") and part.Transparency < 0.98 then
			any = true
			local cf, half = part.CFrame, part.Size / 2
			local r, u, b = cf.RightVector * half.X, cf.UpVector * half.Y, cf.LookVector * half.Z
			local ex = math.abs(r.X) + math.abs(u.X) + math.abs(b.X)
			local ey = math.abs(r.Y) + math.abs(u.Y) + math.abs(b.Y)
			local ez = math.abs(r.Z) + math.abs(u.Z) + math.abs(b.Z)
			local p = cf.Position
			minX, maxX = math.min(minX, p.X - ex), math.max(maxX, p.X + ex)
			minY, maxY = math.min(minY, p.Y - ey), math.max(maxY, p.Y + ey)
			minZ, maxZ = math.min(minZ, p.Z - ez), math.max(maxZ, p.Z + ez)
		end
	end
	if not any then
		local cf, size = model:GetBoundingBox()
		local p = cf.Position
		minX, maxX = p.X - size.X / 2, p.X + size.X / 2
		minY, maxY = p.Y - size.Y / 2, p.Y + size.Y / 2
		minZ, maxZ = p.Z - size.Z / 2, p.Z + size.Z / 2
	end
	minY -= below or 0
	local center = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)
	-- Al girar, lo que importa en horizontal es la diagonal de la planta
	local hx, hz = (maxX - minX) / 2, (maxZ - minZ) / 2
	return center, math.sqrt(hx * hx + hz * hz), (maxY - minY) / 2
end

-- Distancia para que quepa una "lata" de ese radio y esa media altura en el ViewportFrame,
-- con el campo de visión de la cámara (vertical) y la proporción real del marco
function ViewFit.distance(viewport: ViewportFrame, camera: Camera, radius: number, halfY: number): number
	local size = viewport.AbsoluteSize
	local aspect = if size.X > 1 and size.Y > 1 then size.X / size.Y else 1
	local halfV = math.rad(camera.FieldOfView) / 2
	local halfH = math.atan(math.tan(halfV) * aspect)
	local byWidth = radius * MARGIN / math.sin(halfH)
	local byHeight = halfY * MARGIN / math.tan(halfV) + radius
	return math.max(byWidth, byHeight, 2)
end

-- Coloca la cámara en órbita (ángulo `angle`). `state` es una tabla del que llama que guarda la
-- última medida; ViewFit.reset(state) la olvida (modelo nuevo o vestido distinto).
function ViewFit.orbit(camera: Camera, viewport: ViewportFrame, model: Model, angle: number, state: any, below: number?): Vector3
	local now = os.clock()
	if state.center == nil or now - (state.at or 0) > REMEASURE then
		state.at = now
		local center, radius, halfY = ViewFit.measure(model, below)
		state.target = ViewFit.distance(viewport, camera, radius, halfY)
		state.goal = center
		if state.center == nil then
			state.center, state.dist = center, state.target
		end
	end
	-- Suave: si crece un aura, la cámara se aleja sin saltos
	state.center = state.center:Lerp(state.goal, 0.15)
	state.dist += (state.target - state.dist) * 0.15
	local d = state.dist
	local eye = state.center + Vector3.new(math.sin(angle) * d, d * LIFT, math.cos(angle) * d)
	camera.CFrame = CFrame.lookAt(eye, state.center)
	return state.center
end

function ViewFit.reset(state: any)
	state.center = nil
	state.at = 0
end

return ViewFit
