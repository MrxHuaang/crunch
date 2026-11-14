-- Comida dorada: decide con qué probabilidad sale dorada cada comida nueva. Manda el mejor
-- "Olfato dorado" entre las jugadoras conectadas. FoodService la tiñe y PlayerService/Colony/Allies
-- la cobran con FoodService.pieceValue (multiplicador de cada jugadora).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stats = require(ReplicatedStorage.Shared.Stats)
local FoodService = require(script.Parent.FoodService)
local Profiles = require(script.Parent.Profiles)

local GoldFood = {}

function GoldFood.start()
	FoodService.goldChance = function(): number
		local best = 0
		for _, profile in Profiles.all() do
			local stats = profile.stats
			if stats and (stats.goldFood or 0) > best then
				best = stats.goldFood
			end
		end
		return Stats.goldFoodChance(best)
	end
end

return GoldFood
