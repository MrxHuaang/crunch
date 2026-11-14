-- Piezas base del estilo: tinta, colores de imprenta, cajas con sombra dura, estallidos,
-- trama de puntos y "hervor de línea" (el temblor del dibujo hecho a mano).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Assets)

local Comic = {}

Comic.Ink = Color3.fromRGB(20, 16, 16)
Comic.Paper = Color3.fromRGB(255, 250, 235)
Comic.Yellow = Color3.fromRGB(255, 210, 63)
Comic.Red = Color3.fromRGB(230, 57, 70)
Comic.Cyan = Color3.fromRGB(62, 193, 243)
Comic.Green = Color3.fromRGB(110, 200, 90)
Comic.Crumb = Color3.fromRGB(222, 166, 92)
Comic.Dirt = Color3.fromRGB(150, 98, 60)
Comic.DirtDark = Color3.fromRGB(112, 72, 46)
Comic.DirtLight = Color3.fromRGB(214, 168, 116)

Comic.Display = Font.new("rbxasset://fonts/families/Bangers.json")
Comic.Body = Font.new("rbxasset://fonts/families/ComicNeueAngular.json", Enum.FontWeight.Bold)

-- Trazo de tinta. En un texto bordea las letras; con border = true, la caja.
function Comic.ink(parent: GuiObject, thickness: number, border: boolean?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Comic.Ink
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	if border then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	stroke.Parent = parent
	return stroke
end

function Comic.round(parent: GuiObject, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0)
	corner.Parent = parent
	return corner
end

-- Mantiene un widget diseñado en píxeles legible en cualquier pantalla.
function Comic.autoScale(widget: GuiObject, reference: number?): UIScale
	local scale = Instance.new("UIScale")
	scale.Parent = widget
	local function update()
		local camera = Workspace.CurrentCamera
		if camera then
			scale.Scale = math.clamp(camera.ViewportSize.Y / (reference or 900), 0.55, 1.5)
		end
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

function Comic.frame(parent: Instance, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	if color then
		frame.BackgroundColor3 = color
	else
		frame.BackgroundTransparency = 1
	end
	frame.Parent = parent
	return frame
end

-- Caja de viñeta: cara de color con borde de tinta y sombra dura desplazada, como tinta mal registrada.
function Comic.box(parent: Instance, size: UDim2, color: Color3, shadowOffset: number): (Frame, Frame)
	local holder = Comic.frame(parent)
	holder.Size = size

	local shadow = Comic.frame(holder, Comic.Ink)
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(shadowOffset, shadowOffset)

	local face = Comic.frame(holder, color)
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	Comic.ink(face, 4)

	return holder, face
end

function Comic.label(parent: Instance, text: string, font: Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	return label
end

function Comic.image(parent: Instance, asset: string, color: Color3?): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = asset
	image.ScaleType = Enum.ScaleType.Fit
	if color then
		image.ImageColor3 = color
	end
	image.Parent = parent
	return image
end

-- Trama de puntos que se desvanece hacia un lado, como sombreado de imprenta.
function Comic.halftone(parent: GuiObject, color: Color3, rotation: number): ImageLabel
	local dots = Comic.image(parent, Assets.Halftone, color)
	dots.ScaleType = Enum.ScaleType.Tile
	dots.TileSize = UDim2.fromOffset(26, 26)
	dots.Size = UDim2.fromScale(1, 1)
	local fade = Instance.new("UIGradient")
	fade.Rotation = rotation
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	fade.Parent = dots
	return dots
end

-- Estallido de onomatopeya. La imagen es blanca con tinta: se tiñe con el color.
function Comic.burst(parent: Instance, diameter: number, color: Color3): ImageLabel
	local burst = Comic.image(parent, Assets.Burst, color)
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromOffset(diameter, diameter)
	return burst
end

-- Botón de cómic: al pulsar, la cara se hunde sobre su sombra.
function Comic.button(parent: Instance, size: UDim2, color: Color3, shadowOffset: number): (Frame, TextButton)
	local holder = Comic.frame(parent)
	holder.Size = size

	local shadow = Comic.frame(holder, Comic.Ink)
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(shadowOffset, shadowOffset)

	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.AutoButtonColor = false
	face.BackgroundColor3 = color
	face.BorderSizePixel = 0
	face.Size = UDim2.fromScale(1, 1)
	face.Text = ""
	face.Parent = holder
	Comic.ink(face, 4, true)

	local quick = TweenInfo.new(0.06)
	face.MouseButton1Down:Connect(function()
		TweenService:Create(face, quick, { Position = UDim2.fromOffset(shadowOffset - 1, shadowOffset - 1) }):Play()
	end)
	local function release()
		TweenService:Create(face, quick, { Position = UDim2.fromOffset(0, 0) }):Play()
	end
	face.MouseButton1Up:Connect(release)
	face.MouseLeave:Connect(release)

	return holder, face
end

function Comic.punch(scale: UIScale, from: number)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Hervor de línea: cada pocos fotogramas el objeto cambia un pelín de ángulo, como si lo redibujaran.
local boiling: { { object: GuiObject, base: number, amount: number } } = {}
local rng = Random.new()

function Comic.boil(object: GuiObject, amount: number)
	table.insert(boiling, { object = object, base = object.Rotation, amount = amount })
end

task.spawn(function()
	while true do
		task.wait(0.14)
		for i = #boiling, 1, -1 do
			local entry = boiling[i]
			if entry.object.Parent then
				entry.object.Rotation = entry.base + rng:NextNumber(-entry.amount, entry.amount)
			else
				table.remove(boiling, i)
			end
		end
	end
end)

return Comic
