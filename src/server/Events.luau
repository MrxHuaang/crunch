-- Sucesos del juego a los que otros módulos pueden apuntarse sin tocar la lógica principal
-- (misiones, mascotas, eventos). Quien provoca el suceso llama a Events.fire; quien quiere
-- enterarse, a Events.on.
--
--   "Ate"      (profile, def, amount, byWorkers)  trozos arrancados a una comida
--   "Finished" (profile, def)                     comida terminada del todo
--   "Deposit"  (profile, credited, fullLoad)      entrega en el hormiguero
--   "Bought"   (profile, kind, id)                compra en el árbol ("node", "mini", "workers", "royal")
--   "Dig"      (profile, depth)                   capa nueva
--   "Rebirth"  (profile, jelly)                   enjambre
--   "Golden"   (profile)                          bocado dorado
--   "Bite"     (profile, food, chained)           mordisco tuyo acertado (chained: seguido del anterior)

local Events = {}

local listeners: { [string]: { (...any) -> () } } = {}

function Events.on(name: string, fn: (...any) -> ())
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, fn)
end

function Events.fire(name: string, ...: any)
	local list = listeners[name]
	if not list then
		return
	end
	for _, fn in list do
		-- Un oyente con un fallo no debe romper la mordida ni la entrega
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[CRUNCH!] Suceso", name, err)
		end
	end
end

return Events
