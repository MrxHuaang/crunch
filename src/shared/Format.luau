--!strict
-- Formato corto de números grandes: 1.2K, 3.4M, 5.6B... luego notación científica.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td" }

function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = math.floor(math.log10(n) / 3)
	if tier >= #SUFFIXES then
		local exp = math.floor(math.log10(n))
		return string.format("%s%.2fe%d", sign, n / 10 ^ exp, exp)
	end
	local scaled = n / 10 ^ (tier * 3)
	local text = if scaled < 10
		then string.format("%.2f", scaled)
		elseif scaled < 100 then string.format("%.1f", scaled)
		else string.format("%d", math.floor(scaled))
	if text:find(".", 1, true) then
		text = (text:gsub("%.?0+$", ""))
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

return Format
