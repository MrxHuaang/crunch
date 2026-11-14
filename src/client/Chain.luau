-- Mordida en cadena: el rayo de cómic que salta de comida en comida (suceso Fx "Chain").
-- Cada salto sale con un retardo corto: núcleo blanco con halo amarillo y trazo de tinta, quebrado
-- y con ramas, que parpadea una vez. En cada comida tocada: chispas, destello con luz y aplastón.
-- Todo el mundo ve el rayo; la dueña además oye un zumbido que sube de tono con cada salto, ve los
-- números que salen de cada comida, las migajas que le vuelan a la boca y nota un temblor que crece
-- con la cadena. Al acabar, "¡ZAS! xN" con el número de saltos.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Comic = require(script.Parent.Comic)
local Fx = require(script.Parent.Fx)
local Sfx = require(script.Parent.Sfx)

local Chain = {}

local STEP = 0.075 -- segundos entre un salto y el siguiente
local SEEN = 140 -- más lejos de la cámara no se dibuja
local NEAR = 70 -- más lejos que esto, el rayo de otra jugadora va sin luces ni ramas
local YELLOW = Color3.fromRGB(255, 232, 60)
local HOT = Color3.fromRGB(255, 170, 40)

-- La comida que hay en ese punto (el servidor manda el centro de cada comida tocada)
local function foodNear(spot: Vector3): Model?
	local foods = Workspace:FindFirstChild("Food")
	if not foods then
		return nil
	end
	local best, bestGap = nil, 3
	for _, food in foods:GetChildren() do
		if food:IsA("Model") then
			local gap = ((food:GetPivot().Position - spot) * Vector3.new(1, 0, 1)).Magnitude
			if gap < bestGap then
				best, bestGap = food, gap
			end
		end
	end
	return best
end

function Chain.play(owner: Player?, points: any, amounts: any)
	if type(points) ~= "table" or #points < 2 then
		return
	end
	local mine = owner == Players.LocalPlayer
	local camera = Workspace.CurrentCamera
	local far = false
	if typeof(points[1]) == "Vector3" and camera then
		local distance = (camera.CFrame.Position - points[1]).Magnitude
		if not mine and distance > SEEN then
			return
		end
		far = not mine and distance > NEAR
	end
	local hops = #points - 1
	if mine then
		Fx.shake(math.min(0.12 + 0.07 * hops, 0.5))
		Fx.kick(1.5 + 0.4 * math.min(hops, 6))
	end
	for i = 1, hops do
		task.delay((i - 1) * STEP, function()
			local from, to = points[i], points[i + 1]
			if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
				return
			end
			-- Cada salto un poco más caliente: de amarillo a naranja
			local heat = math.clamp((i - 1) / 5, 0, 1)
			local color = YELLOW:Lerp(HOT, heat)
			local lift = Vector3.new(0, 0.8, 0)
			Fx.bolt(from + lift, to + lift, {
				width = if far then 0.7 else 1.1,
				color = color,
				life = 0.24,
				forks = if far then 0 elseif mine then 2 else 1,
				ink = not far,
			})
			Fx.sparks(to + lift, if far then 4 else 10, color)
			if not far then
				Fx.flash(to + lift, color, 3, true)
			end
			if mine then
				local food = foodNear(to)
				if food then
					Fx.squash(food, 0.2, from)
				else
					Fx.finish(to, true) -- el rayo se la terminó: remate pequeño
				end
				local amount = type(amounts) == "table" and tonumber(amounts[i]) or 0
				if amount > 0 then
					Fx.number(to + lift, amount, true, false)
				end
				Fx.absorb(to + lift, YELLOW, 2, 0.34, 0.03)
				Sfx.zap(i)
				if i == 1 then
					Fx.word(from + Vector3.new(0, 2.5, 0), "¡BZZT!", Comic.Yellow, 40, { life = 0.45 })
				end
				if i == hops then
					Fx.word(to + Vector3.new(0, 3, 0), "¡ZAS! x" .. hops, Comic.Yellow, 46 + 4 * math.min(hops, 6), {
						life = 0.7,
						side = 0,
						force = true,
					})
				end
			end
		end)
	end
end

return Chain
