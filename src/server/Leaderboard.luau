-- Tabla de puntuaciones. La puntuación es toda la comida que has reunido en tu vida.
-- Dos sitios: la lista de jugadores de Roblox (leaderstats, con números abreviados: 1.2M, 3.4B…)
-- y un cartel en el jardín con las diez más glotonas de todos los servidores.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Profiles = require(script.Parent.Profiles)

local Leaderboard = {}

local REFRESH = 90
local names: { [number]: string } = {}
local store = nil
local worldDown = false -- la última consulta mundial falló (por ejemplo, Studio sin acceso a la API)

-- Un OrderedDataStore solo guarda enteros, y la comida llega a números enormes:
-- se guarda el logaritmo con seis decimales, que conserva el orden.
local function encode(total: number): number
	return math.floor(math.log10(total + 1) * 1e6)
end

local function decode(value: number): number
	return 10 ^ (value / 1e6) - 1
end

local function attach(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Comida", "Capa" } do
		local value = Instance.new("StringValue")
		value.Name = name
		value.Value = if name == "Capa" then "1" else "0"
		value.Parent = stats
	end
	stats.Parent = player
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = player and player.DisplayName
	if not name then
		local ok, result = pcall(Players.GetNameFromUserIdAsync, Players, userId)
		name = if ok then result else "Hormiga " .. userId
	end
	names[userId] = name
	return name
end

local function paint(panelName: string, rows: { { name: string, total: number } }, empty: string?)
	local board = Workspace:FindFirstChild("Board")
	local panel = board and board:FindFirstChild(panelName)
	local gui = panel and panel:FindFirstChild("BoardGui")
	if not gui then
		return
	end
	for i = 1, 10 do
		local label = gui:FindFirstChild("Row" .. i)
		local row = rows[i]
		if label and label:IsA("TextLabel") then
			if row then
				label.Text = string.format("  %d.  %s   %s", i, row.name, Format.short(row.total))
			else
				-- Sin datos todavía: una línea que lo explica en vez de un cartel vacío
				label.Text = if i == 1 and #rows == 0 and empty then "  " .. empty else ""
			end
		end
	end
end

local function localRows()
	local rows = {}
	for player, profile in Profiles.all() do
		table.insert(rows, { name = player.DisplayName, total = profile.data.totalFood })
	end
	table.sort(rows, function(a, b)
		return a.total > b.total
	end)
	return rows
end

local function globalRows()
	if not store then
		return nil
	end
	for player, profile in Profiles.all() do
		if profile.canSave then
			pcall(function()
				store:SetAsync(tostring(player.UserId), encode(profile.data.totalFood))
			end)
		end
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	worldDown = not ok
	if not ok then
		return nil
	end
	local rows = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(rows, { name = nameOf(userId), total = decode(entry.value) })
		end
	end
	return rows
end

function Leaderboard.start()
	Players.PlayerAdded:Connect(attach)
	for _, player in Players:GetPlayers() do
		attach(player)
	end

	local ok, result = pcall(function()
		-- En Studio, ranking de prueba aparte (ver Data)
		return DataStoreService:GetOrderedDataStore(Config.Save.TopStore .. (if RunService:IsStudio() then "_studio" else ""))
	end)
	store = if ok then result else nil

	-- Lista de jugadores: se refresca a menudo, es barato
	task.spawn(function()
		while true do
			task.wait(1)
			for player, profile in Profiles.all() do
				local stats = player:FindFirstChild("leaderstats")
				if stats then
					(stats.Comida :: StringValue).Value = Format.short(profile.data.totalFood);
					(stats.Capa :: StringValue).Value = tostring(profile.data.depth)
				end
			end
		end
	end)

	-- Cartel del servidor: se repinta a menudo, sale de memoria
	task.spawn(function()
		while true do
			paint("ServerPanel", localRows())
			task.wait(3)
		end
	end)

	-- Cartel mundial: las diez con más comida reunida entre todos los servidores. Sale de un
	-- OrderedDataStore, así que solo funciona con acceso a la API (siempre en el juego publicado).
	task.spawn(function()
		local global = {}
		local first = true
		while true do
			local rows = globalRows()
			if rows then
				global = rows
			end
			paint("WorldPanel", global, if store and not worldDown then "Aún no hay nadie" else "Solo en el juego publicado")
			-- La primera vuelta llega antes de que cargue nadie: se repite pronto para incluir a quien entra
			task.wait(if first then 20 else REFRESH)
			first = false
		end
	end)
end

return Leaderboard
