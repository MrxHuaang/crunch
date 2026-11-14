-- Pases de juego (permanentes) y productos (se pueden comprar varias veces).
-- Los ids se configuran en shared/Config. Con id = 0 el artículo está apagado.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Data = require(script.Parent.Data)
local Events = require(script.Parent.Events)
local Profiles = require(script.Parent.Profiles)

local Monetize = {}

local passById = {}
for _, pass in Config.Passes do
	if pass.passId > 0 then
		passById[pass.passId] = pass
	end
end
local productById = {}
for _, product in Config.Products do
	if product.productId > 0 then
		productById[product.productId] = product
	end
end

local function grantPass(profile, pass)
	profile.passes[pass.id] = true
	profile.player:SetAttribute("P_" .. pass.id, true)
end

-- Comprueba qué pases tiene el jugador al entrar.
function Monetize.load(profile)
	for _, pass in passById do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(profile.player.UserId, pass.passId)
		end)
		if ok and owns then
			grantPass(profile, pass)
		end
	end
end

local function colonyTime(profile, seconds: number, floor: number): number
	local stats = profile.stats
	-- Aunque la colonia aún sea pequeña, el saco debe valer algo a tu nivel
	local zoneFood = Config.Foods[(stats.depth - 1) * 3 + 1]
	local gain = math.max(math.floor(profile.data.rate * seconds), floor * stats.biteDamage * zoneFood.value)
	return Profiles.addFood(profile, gain)
end

local GRANTS = {
	frenzy = function(profile)
		local now = Workspace:GetServerTimeNow()
		profile.frenzyUntil = math.max(profile.frenzyUntil, now) + 60
		Profiles.say(profile, "¡Frenesí! La colonia se ha vuelto loca", 4)
	end,
	potion = function(profile)
		local now = Workspace:GetServerTimeNow()
		profile.buffUntil = math.max(profile.buffUntil, now) + 1800
		Profiles.say(profile, "¡Poción x2! Media hora de comida doble", 5)
	end,
	sack = function(profile)
		colonyTime(profile, 900, 300)
		Profiles.say(profile, "¡Un saco entero de comida!", 4)
	end,
	bigSack = function(profile)
		colonyTime(profile, 7200, 2400)
		Profiles.say(profile, "¡Una carretilla hasta arriba de comida!", 4)
	end,
	shovel = function(profile)
		local data = profile.data
		if data.depth < Stats.MaxDepth then
			data.depth += 1
			Profiles.say(profile, "¡Capa nueva! Se abre " .. Config.Zones[data.depth].name, 6)
			-- Las estadísticas, al día antes de avisar: los oyentes leen la capa nueva
			Profiles.refresh(profile)
			Events.fire("Dig", profile, data.depth)
		else
			-- Ya no queda nada que excavar: se devuelve en jalea
			data.jelly += 15
			Profiles.say(profile, "No queda tierra que excavar. Toma 15 de jalea", 6)
		end
	end,
	egg = function(profile)
		profile.eggAt = 0
		profile.eggGift = true
		Profiles.say(profile, "¡Un huevo dorado te espera junto a tu hormiguero!", 5)
	end,
	jar = function(profile)
		profile.data.jelly += 5
		Profiles.say(profile, "¡Jalea real! Ábrela en la cámara real", 4)
	end,
	bigJar = function(profile)
		profile.data.jelly += 30
		Profiles.say(profile, "¡Un barril de jalea real!", 4)
	end,
}

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = player and Profiles.get(player)
	local product = productById[receipt.ProductId]
	if not profile or not product then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Cada compra se entrega una sola vez aunque Roblox repita el aviso
	local data = profile.data
	data.receipts = data.receipts or {}
	if table.find(data.receipts, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	GRANTS[product.id](profile)
	table.insert(data.receipts, receipt.PurchaseId)
	while #data.receipts > 40 do
		table.remove(data.receipts, 1)
	end
	Profiles.refresh(profile)

	-- Solo se confirma la compra si quedó guardada
	if profile.canSave and not Data.save(player.UserId, data) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Solo para probar en Studio: entrega un pase o producto sin pasar por Roblox.
function Monetize.debugGrant(profile, id: string)
	for _, pass in Config.Passes do
		if pass.id == id then
			grantPass(profile, pass)
		end
	end
	if GRANTS[id] then
		GRANTS[id](profile)
	end
	Profiles.refresh(profile)
end

function Monetize.start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local profile = Profiles.get(player)
		local pass = passById[passId]
		if purchased and profile and pass then
			grantPass(profile, pass)
			Profiles.refresh(profile)
		end
	end)
end

return Monetize
