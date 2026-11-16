-- Decide qué comida tienes a tiro y la resalta. Morder y marcar rastro usan este mismo objetivo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Comic = require(script.Parent.Comic)
local State = require(script.Parent.State)

local Targeting = {}

local current: Model? = nil

function Targeting.current(): Model?
	return if current and current.Parent then current else nil
end

-- Recorrer las ~1.000 comidas en cada fotograma costaba ~1 ms en PC (varios en celular). Cada
-- SCAN_EVERY s se apartan las que quedan a menos de NEAR_MARGIN de más del alcance (sobra para lo que
-- se recorre andando o volando en ese rato) y, entre esas, se busca la más cercana PICK_HZ veces por segundo.
local SCAN_EVERY = 0.4
local NEAR_MARGIN = 60
local PICK_EVERY = 1 / 15

local FLAT = Vector3.new(1, 0, 1)

local function gapTo(food: Model, from: Vector3): number
	return ((food:GetPivot().Position - from) * FLAT).Magnitude - (food:GetAttribute("Radius") or 1)
end

local function nearest(root: BasePart, foods: { Instance }, range: number): Model?
	local best: Model? = nil
	local bestGap = range
	for _, food in foods do
		if food.Parent and food:IsA("Model") then
			local gap = gapTo(food, root.Position)
			if gap <= bestGap then
				best = food
				bestGap = gap
			end
		end
	end
	return best
end

function Targeting.start()
	local player = Players.LocalPlayer
	local foods = Workspace:WaitForChild("Food")

	local outline = Instance.new("Highlight")
	outline.Name = "TargetOutline"
	outline.FillColor = Comic.Yellow
	outline.FillTransparency = 0.7
	outline.OutlineColor = Comic.Red
	outline.DepthMode = Enum.HighlightDepthMode.Occluded

	local nearby: { Instance } = {}
	local scanAt, pickAt = 0, 0
	local scanFrom = Vector3.zero
	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local clock = os.clock()
		-- Si la comida a tiro se acabó, no se espera a la siguiente vuelta
		local lost = current ~= nil and current.Parent == nil
		if not root then
			current = nil
		elseif lost or clock >= pickAt then
			pickAt = clock + PICK_EVERY
			local range = State.stats().biteRange
			-- También tras un salto (túnel, honda, alas): la lista vieja era de otro sitio
			if clock >= scanAt or ((root.Position - scanFrom) * FLAT).Magnitude > NEAR_MARGIN / 2 then
				scanAt = clock + SCAN_EVERY
				scanFrom = root.Position
				table.clear(nearby)
				for _, food in foods:GetChildren() do
					if food:IsA("Model") and gapTo(food, root.Position) <= range + NEAR_MARGIN then
						table.insert(nearby, food)
					end
				end
			end
			current = nearest(root, nearby, range)
		end
		if outline.Parent ~= current then
			outline.Parent = current
		end
	end)
end

return Targeting
