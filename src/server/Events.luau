-- Sucesos del juego a los que otros módulos pueden apuntarse sin tocar la lógica principal
-- (misiones, mascotas, eventos). Quien provoca el suceso llama a Events.fire; quien quiere
-- enterarse, a Events.on.
--
--   "Ate"      (profile, def, amount, byWorkers)  trozos arrancados a una comida
--   "Finished" (profile, def)                     comida terminada del todo
--   "Deposit"  (profile, credited, fullLoad)      entrega en el hormiguero
--   "Bought"   (profile, kind, id)                compra en el árbol ("node", "mini", "workers", "royal")
--   "Dig"      (profile, depth)                   capa nueva
--   "Rebirth"  (profile, jelly)                   enjambre (solo el premio; el reinicio es "RunReset")
--   "RunReset" (profile)                          la partida vuelve a empezar (al enjambrar y desde el
--                                                panel DEV): quien guarda estado de la partida lo limpia aquí
--   "Golden"   (profile)                          bocado dorado
--   "Bite"     (profile, food, chained, position, damage, finished)
--                                                mordisco tuyo acertado (chained: seguido del anterior;
--                                                position: centro de la comida + 1; damage: daño del
--                                                mordisco; finished: lo terminó, y food ya no existe)
--   "FinalBite" (profile, food, position, damage) tu mordisco terminó esa comida (food ya no existe)

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
