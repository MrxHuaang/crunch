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

local function nearest(root: BasePart, foods: Instance, range: number): Model?
	local best: Model? = nil
	local bestGap = range
	for _, food in foods:GetChildren() do
		if food:IsA("Model") then
			local flat = (food:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)
			local gap = flat.Magnitude - (food:GetAttribute("Radius") or 1)
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

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		current = if root then nearest(root :: BasePart, foods, State.stats().biteRange) else nil
		outline.Parent = current
	end)
end

return Targeting
