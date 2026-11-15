# Hormigueros de zona — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un hormiguero compartido a la entrada de cada zona 2..14 donde la jugadora y sus obreras entregan, sin que la partida dure menos que hoy.

**Architecture:** La posición de cada hormiguero de zona sale de una fórmula en `Config` (servidor, cliente y `sim.py` la comparten sin replicar nada). Un módulo de servidor `Depots` los construye y responde "¿hay uno abierto aquí?" y "¿a qué distancia queda esta comida?". `PlayerService`, `Colony` y `Extras` lo consultan; el cliente dibuja obreras, flecha y chorro hacia él. Al final, `sim.py` modela la entrega en zona y se reajusta `Config` para recuperar el ritmo.

**Tech Stack:** Luau (Rojo), Roblox Studio (pruebas con `execute_luau` del MCP de Studio y el panel DEV), Python 3 (`tools/sim.py`), `selene`.

**Spec:** `docs/superpowers/specs/2026-11-14-hormigueros-de-zona-design.md`

## Global Constraints

- Zonas 2..14 tienen hormiguero de zona; el jardín (zona 1) no.
- Abierto para una jugadora si `zona <= stats.depth`, o si la llave maestra (`zoneKey`, Monetize) tiene esa zona abierta en este momento.
- Entregar en zona = entregar en casa: `PlayerService.credit` (suceso "Deposit", reparto doble, buche, despensa) y el mismo antitrampas (`canReach` + `moved`).
- Puesto avanzado: nodo `outpost` fuera de `Config.Tree`; `Stats` da `hasOutpost = false` aunque el guardado tenga nivel; no se construye.
- Ritmo tras el reajuste (perfil activo, `python tools/sim.py`): minutos acumulados por capa dentro de ±15 % de la tabla de hoy (1: 9,4 · 2: 39,2 · 3: 70,9 · 4: 101,4 · 5: 131,5 · 7: 192,2 · 10: 281,4 · 13: 370,6), total hasta la capa 14 ≈ 6 h ±10 %, APROBADO ≥ 307. Con `SIN=tunnel,wings` las capas no deben quedar por debajo del −15 % de la tabla.
- `sim.py` y `Config` cambian juntos (mismos números).
- Formato de guardado sin cambios.

## Review Focus

1. **Hormiguero de zona que tapa algo**: la puerta, la salida del túnel (x = −65, z0 − 8), un racimo (empiezan en z0 − 25) o decorado encima → el sitio debe quedar despejado y pisable (Task 2).
2. **Zona cerrada**: pisar el hormiguero de una zona que no tienes abierta no entrega; con la llave maestra activa sí (Task 3).
3. **Teletransporte al hormiguero de zona**: la entrega espera igual que en casa (Task 3).
4. **Obreras en el jardín**: siguen yendo a casa y rinden como antes del cambio salvo el reajuste global (Task 4).
5. **Quien tenía el Puesto avanzado**: entra, no ve el puesto, no se rompe nada y no hay atributos `OutpostPos` colgando (Task 1).

---

### Task 1: Geometría en Config y retirada del Puesto avanzado

**Files:**
- Modify: `src/shared/Config.luau` (junto a `Config.Map`/`zoneStart`, y `Config.Tree` línea del nodo `outpost`)
- Modify: `src/shared/Stats.luau:309` (`hasOutpost`) y su texto (`:638`)

**Interfaces:**
- Produces:
  - `Config.Depot = { Radius = 12, Scale = 0.55, X = Config.Map.Half - 20, ZIn = 12 }` (radio de entrega plano, escala del modelo respecto al de casa, lado y fondo desde `z0`).
  - `Config.depotPos(zone: number): Vector3?` → `Vector3.new(Depot.X, Config.GroundY, zone.z0 - Depot.ZIn)` para zonas 2..#Zones; `nil` para 1 o fuera de rango.
  - `Config.zoneAt(z: number): number` → la zona cuyo tramo `[z1 − 10, z0 + 10]` contiene `z`; 1 si está en el jardín.

- [ ] **Step 1: Prueba (Studio, Edit, `execute_luau`)**: `require(ReplicatedStorage.Shared.Config)`; para cada zona 2..14, `Config.zoneAt(Config.depotPos(i).Z) == i`; `Config.depotPos(1) == nil`; `Config.zoneAt(0) == 1`; ninguna entrada de `Config.Tree` con `id == "outpost"`; `|depotPos(i).X| + Depot.Radius <= Config.Map.Half`. Ejecutar: falla (no existen).
- [ ] **Step 2:** Implementar `Config.Depot`, `depotPos`, `zoneAt`; borrar la línea del nodo `outpost` en `Config.Tree`; en `Stats`, `hasOutpost = false` con comentario "retirado hasta el rediseño de movilidad" y quitar su texto de la ficha.
- [ ] **Step 3:** Comprobar que nada más en `src` referencia el nodo `outpost` como requisito (`parent`, `needs`, `MiniTune`): `grep -rn '"outpost"' src`; ajustar lo que haya.
- [ ] **Step 4:** Repetir la prueba: PASS. Play con un perfil que tenga `nodes.outpost = 1` (`CrunchDebug:Fire("node","outpost",1)`): sin errores en consola, sin modelo `Outpost`, el hormiguero de casa sin atributo `OutpostPos` (Review Focus 5). `selene src/shared`: 0 errores.

### Task 2: Módulo `Depots` y su modelo

**Files:**
- Create: `src/server/Depots.luau`
- Modify: `src/server/HillModel.luau` (`HillModel.build` acepta `info.tint: Color3?`)
- Modify: `src/server/init.server.luau` (`Depots.build()` justo después de `World.build()`)

**Interfaces:**
- Consumes: `Config.Depot`, `Config.depotPos`, `Config.zoneAt` (Task 1).
- Produces:
  - `Depots.build()`: crea `Workspace.Depots` (Model) con un Model por zona 2..14 llamado `Depot<id>`, atributo `Zone = id`, pivot en `Config.depotPos(id)`, montículo de `HillModel.build` con `scale = Config.Depot.Scale` y `tint = zone.floor` mezclado con la tierra (Lerp ~0.35), collider pisable y BillboardGui "Entrega aquí". Quita el decorado (`Workspace.Props`/zona) que quede dentro de `Config.Depot.Radius + 4` del centro.
  - `Depots.isOpen(profile, zone: number): boolean` (depth o llave maestra activa para esa zona).
  - `Depots.near(profile, position: Vector3): number?` → zona del hormiguero abierto a ≤ `Config.Depot.Radius` en plano.
  - `Depots.distance(zone: number, position: Vector3): number` → distancia plana del hormiguero de esa zona a `position`.
  - `Depots.top(zone: number): Vector3` → punto alto del montículo para el chorro (`depotPos + Vector3.new(0, 9 * Config.Depot.Scale, 0)`).

- [ ] **Step 1: Prueba (Studio, Play, Server)**: `Workspace.Depots` tiene 13 hijos `Depot2..Depot14` con `Zone` correcto y pivot a < 1 stud de `Config.depotPos`; en cada uno, `workspace:GetPartBoundsInRadius(depotPos, Config.Depot.Radius)` no devuelve partes de puertas (`Gates`), de racimos (`Food`) ni de la salida del túnel (Review Focus 1). Ejecutar: falla.
- [ ] **Step 2:** Implementar `HillModel` con `tint` opcional (sin `tint`, idéntico a hoy) y `Depots.build` con lo de arriba.
- [ ] **Step 3:** Prueba PASS. `screen_capture` de la entrada de las zonas 2, 9 y 14 (Edit no tiene el mundo: hacerlo en Play con `CrunchDebug`/panel DEV "Viaje") y revisar que se ve como hormiguero de la zona y no tapa el camino. `selene`: 0 errores.

### Task 3: Entrega a pie en zona

**Files:**
- Modify: `src/server/PlayerService.luau` (`depositLoop`)
- Modify: `src/server/Extras.luau` (`atDepot`)

**Interfaces:**
- Consumes: `Depots.near`, `Depots.top` (Task 2).
- Produces: el `fxRemote "Deposit"` lleva como posición `Depots.top(zona)` cuando se entrega en zona (en casa, como hoy).

- [ ] **Step 1: Prueba (Studio, Play, Client, panel DEV)**:
  - `prepare 5`, `zone 5`, morder hasta tener carga, colocarse a < 8 studs de `Config.depotPos(5)` → `Carry` pasa a 0 y `Food` sube en ≤ 1 s.
  - `prepare 3`, colocarse en el hormiguero de la zona 5 con carga → `Carry` no cambia en 3 s (Review Focus 2); `grant zoneKey` y repetir dentro del tiempo de la llave → entrega.
  - Con carga en el jardín, teletransportarse al hormiguero de la zona 5 (capa 5) → no entrega en 1,5 s; sí tras el tiempo legal (Review Focus 3).
  - Entregar en zona con la mejora `buche` (`CrunchDebug node buche 1`) → al salir del radio la carga vuelve (atributo `Carry` > 0).
  Ejecutar: falla.
- [ ] **Step 2:** En `depositLoop`, si no está en casa, `Depots.near(profile, root.Position)`; si da zona y `canReach`, el mismo bloque de entrega que en casa con `Depots.top(zona)` en el aviso. Extraer el bloque común a una función local para no duplicarlo. En `Extras.atDepot`, contar `Depots.near` (con el margen que recibe).
- [ ] **Step 3:** Prueba PASS; consola limpia; `selene`.

### Task 4: Obreras al hormiguero de su zona

**Files:**
- Modify: `src/server/Colony.luau:304-309`

**Interfaces:**
- Consumes: `Depots.distance` (Task 2).

- [ ] **Step 1: Prueba (Studio, Play, Server/Client)**: con `prepare 6`, `workers 60` y un rastro marcado en una comida de la zona 6 (remoto `Trail` del cliente), medir la comida ganada por la colonia en 20 s sin morder (`Food` antes/después). Guardar la cifra. Repetir el mismo montaje en el jardín. Ejecutar antes del cambio para tener las dos referencias.
- [ ] **Step 2:** En el cálculo del viaje: si `def.zone >= 2`, `reach = Depots.distance(def.zone, foodPos)`; si no, como hoy. `Colony.shortcut` deja de aplicarse cuando hay hormiguero de zona.
- [ ] **Step 3:** Repetir: zona 6 ≥ 5 veces la referencia; jardín igual (±10 %) (Review Focus 4). `selene`.

### Task 5: Cliente — obreras, flecha, chorro y textos

**Files:**
- Modify: `src/client/Swarm.luau:325-330` (base de la ruta)
- Modify: `src/client/Juice.luau:280-319` (`updateArrow`)
- Modify: `src/client/Fx.luau:1697-1763` (`Fx.deposit`)
- Modify: `src/client/init.client.luau:175` (texto de ayuda)

**Interfaces:**
- Consumes: `Config.depotPos`, `Config.zoneAt`, `Config.Depot` (Task 1); aviso "Deposit" con la posición de Task 3.

- [ ] **Step 1: Prueba (Studio, Play, Client)**: con `prepare 6`, obreras y rastro en la zona 6, `Swarm.route(hill, 1).from` queda a < 15 studs de `Config.depotPos(6)`; con carga llena en la zona 6, la flecha de `Juice` apunta al hormiguero de la zona 6 (comprobar su orientación/objetivo); `screen_capture` de una entrega en zona con el chorro saliendo del hormiguero de zona. Ejecutar: falla.
- [ ] **Step 2:** `Swarm`: si `Config.zoneAt(endPos.Z) >= 2`, `base = Config.depotPos(zona)` y `gap0` pequeño (como hoy con el puesto); quitar la rama `OutpostPos`. `Juice`: objetivo = el más cercano entre casa y los hormigueros de zonas `<= State.depth()`; se oculta dentro de su radio. `Fx.deposit`: si la posición recibida está a más de 30 studs de casa, el agujero es esa posición menos `9 * Config.Depot.Scale` en Y. Texto `init.client.luau:175`: en zonas ≥ 2 "Lleva las migas al hormiguero de la zona"; en el jardín, igual que hoy.
- [ ] **Step 3:** Prueba PASS; consola limpia; `selene src/client`.

### Task 6: Simulador y reajuste del ritmo

**Files:**
- Modify: `tools/sim.py` (`trip` :479-594, `colony` :646-704, constantes :137-147, nodo `outpost` :184 y :194, puesto :570 y :669)
- Modify: `src/shared/Config.luau` (los números de balance que se muevan)

**Interfaces:**
- Consumes: geometría de `Config.Depot` (copiada a `sim.py` como `DEPOT_X`, `DEPOT_IN`).

- [ ] **Step 1:** Guardar la salida actual: `python tools/sim.py > base.txt` y `SIN=tunnel,wings python tools/sim.py > base_sin.txt` (en el workspace del plan, no en el repo).
- [ ] **Step 2:** En `sim.py`: `depot_trip(zone)` = distancia media plana desde `(DEPOT_X, z0 − DEPOT_IN)` a los centros de la rejilla 3×3 de racimos de esa zona (x en `[−Half+14, Half−14]`, z de `z0 − 25` a `z1 + 16`; en la 14, `z1 + 95`), copiando la fórmula de `FoodService:204-227`. A mano en zonas ≥ 2: ida y vuelta = `depot_trip`, sin túnel/alas/puesto en ese tramo. Colonia en zonas ≥ 2: `reach = depot_trip(z)`. Quitar el nodo y la lógica del puesto.
- [ ] **Step 3:** Ejecutar `python tools/sim.py`: anotar cuánto se acelera (esperado: mucho). Este es el "rojo" del reajuste.
- [ ] **Step 4:** Reajustar con los mandos del README (`FoodCurve.ZoneValues`, `StageGrowth`, `DigBase`, `CostScale`, y si la colonia pasa del 40 %, los de obreras: `WorkerSpeed`/`workerCarry`/`COLONY_SPREAD`) hasta cumplir el ritmo de Global Constraints con perfil activo, casual y `SIN=tunnel,wings`. Cada número que cambie, en `Config` y `sim.py` a la vez.
- [ ] **Step 5:** Salida final: tabla por capa antes/después y conteo APROBADO/FALLA de los tres perfiles; nada por debajo de los mínimos. Comprobar en Studio que `Config` carga (Play sin errores).

### Task 7: Documentación, revisión y cierre

**Files:**
- Modify: `README.md` (Funcionamiento, Estructura con `Depots`, Balance con la tabla nueva), `DISENO.md` (mapa y ritmo)

- [ ] **Step 1:** Actualizar README y DISENO con los hormigueros de zona, el Puesto avanzado retirado y los tiempos nuevos.
- [ ] **Step 2:** Revisión final del cambio entero (revisión adversarial independiente) y preguntar a Julián antes del commit y push.
