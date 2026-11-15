-- Hormigueros de zona: uno compartido a la entrada de cada zona 2..14 (posición en Config.depotPos).
-- Quien tiene la zona abierta entrega ahí como en casa (PlayerService) y sus obreras de esa zona viajan
-- solo hasta ahí (Colony). El cliente calcula las mismas posiciones con Config: no se replica nada más.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local HillModel = require(script.Parent.HillModel)

local Depots = {}

local FLAT = Vector3.new(1, 0, 1)
local DIRT = Color3.fromRGB(170, 112, 66)
local INK = Color3.fromRGB(20, 16, 16)

-- Abierto si la jugadora tiene esa zona (stats.depth ya cuenta la llave maestra mientras dura)
function Depots.isOpen(profile, zone: number): boolean
	local stats = profile.stats
	return stats ~= nil and zone >= 2 and zone <= (stats.depth or 1)
end

-- El hormiguero de zona abierto en cuyo radio de entrega (+ margin) está `position` (nil si ninguno)
function Depots.near(profile, position: Vector3, margin: number?): number?
	local zone = Config.zoneAt(position.Z)
	local at = Config.depotPos(zone)
	if not at or not Depots.isOpen(profile, zone) then
		return nil
	end
	if ((position - at) * FLAT).Magnitude > Config.Depot.Radius + (margin or 0) then
		return nil
	end
	return zone
end

function Depots.distance(zone: number, position: Vector3): number
	local at = Config.depotPos(zone)
	return if at then ((position - at) * FLAT).Magnitude else math.huge
end

-- Boca del montículo: de ahí sale el chorro de comida al entregar
function Depots.top(zone: number): Vector3
	return (Config.depotPos(zone) or Vector3.zero) + Vector3.new(0, 9 * Config.Depot.Scale, 0)
end

-- Quita el decorado de la zona que caiga encima del hormiguero (no toca suelo ni camino)
local function clearDecor(zone, at: Vector3)
	-- World nombra cada zona por su tema (Workspace.Zones.<theme>.Decor)
	local zones = Workspace:FindFirstChild("Zones")
	local model = zones and zones:FindFirstChild(zone.theme)
	local decor = model and model:FindFirstChild("Decor")
	if not decor then
		return
	end
	-- Por posición, no con consultas espaciales: el decorado tiene CanQuery = false. Solo piezas que caen
	-- encima y no son de las largas que cruzan el camino (bancales, manteles)
	local reach = Config.Depot.Radius + 4
	for _, piece in decor:GetChildren() do
		local cf, size
		if piece:IsA("Model") then
			cf, size = piece:GetBoundingBox()
		elseif piece:IsA("BasePart") then
			cf, size = piece.CFrame, piece.Size
		end
		if cf and math.max(size.X, size.Z) < 40 and ((cf.Position - at) * FLAT).Magnitude < reach + math.max(size.X, size.Z) / 2 then
			piece:Destroy()
		end
	end
end

local function sign(model: Model, at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = at + Vector3.new(0, 14 * Config.Depot.Scale + 4, 0)
	anchor.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 40)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(255, 250, 235)
	label.TextColor3 = INK
	label.FontFace = Font.new("rbxasset://fonts/families/Bangers.json")
	label.TextScaled = true
	label.Text = "Entrega aquí"
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = INK
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
end

local function build(zone, folder: Model)
	local at = Config.depotPos(zone.id) :: Vector3
	clearDecor(zone, at)

	local model = Instance.new("Model")
	model.Name = "Depot" .. zone.id
	model:SetAttribute("Zone", zone.id)
	local s = Config.Depot.Scale

	-- Colisión simple, como el hormiguero de casa; el montículo visible lo hace HillModel
	local collider = Instance.new("Part")
	collider.Name = "Collider"
	collider.Shape = Enum.PartType.Cylinder
	collider.Anchored = true
	collider.Transparency = 1
	collider.Size = Vector3.new(6 * s, 13 * s, 13 * s) -- mismo cilindro que el de casa (13 de diámetro)
	collider.CFrame = CFrame.new(at + Vector3.new(0, 3 * s, 0)) * CFrame.Angles(0, 0, math.rad(90))
	collider.Parent = model

	-- Mira hacia el centro del camino
	local inward = Vector3.new(-math.sign(at.X), 0, 0)
	local side = inward:Cross(Vector3.yAxis)
	local ok, err = pcall(HillModel.build, model, {
		center = at,
		inward = inward,
		side = side,
		scale = s,
		depth = zone.id,
		rebirths = 0,
		tint = DIRT:Lerp(zone.floor, 0.35), -- tierra con un toque del color de la zona
	})
	if not ok then
		warn("[CRUNCH!] Hormiguero de zona", zone.id, err)
	end
	sign(model, at)
	model.WorldPivot = CFrame.new(at)
	model.Parent = folder
end

function Depots.build()
	local folder = Instance.new("Model")
	folder.Name = "Depots"
	local outline = Instance.new("Highlight")
	outline.Name = "InkOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = INK
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = folder
	for _, zone in Config.Zones do
		if Config.depotPos(zone.id) then
			build(zone, folder)
		end
	end
	folder.Parent = Workspace
end

return Depots
