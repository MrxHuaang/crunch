# Hormigueros de zona

Fecha: 2026-11-14

## Para qué

Volver caminando desde las zonas lejanas a entregar es tedioso: la capa 14 queda a unos 3.400 studs del jardín. Julián quiere poder entregar en cada zona. Las mejoras que hoy lo resuelven a medias (Túnel exprés, Alas, Abeja mensajera, Puesto avanzado, catapulta de la Porteadora) se rediseñarán después; este trabajo no las toca salvo lo imprescindible.

Éxito: en cualquier zona abierta, la jugadora llena la carga y entrega a pocos pasos; el juego dura lo mismo que hoy.

## Decisiones de Julián

- **Un hormiguero compartido por zona** (no uno por jugador): cualquiera que tenga la zona abierta entrega ahí y la comida va a su propia colonia.
- **Las obreras también entregan en el hormiguero de su zona.**
- **Se mantiene el ritmo actual**: tras el cambio se reajusta el balance con `tools/sim.py` para que la partida dure lo mismo.
- **Mejoras de obreras (opción A)**: "Obreras rápidas", "Autopista" y "Senda de feromonas" quedan casi sin efecto con este cambio y se aceptan así hasta el rediseño de movilidad, donde se reimaginan. El reajuste de balance puede recortar lo que rinden las obreras en general (también las del jardín).
- **Puesto avanzado fuera del árbol** hasta el rediseño: no se ve ni se compra, y su hormiguero pequeño deja de aparecer (se pisaría con el hormiguero de zona). A quien ya lo tenga no le pasa nada más: su nivel queda guardado sin efecto.

## Objetivos

- Zonas 2 a 14: un hormiguero de zona en su entrada.
- Entregar ahí es igual que en casa: misma cuenta (`PlayerService.credit`), mismo efecto, reparto doble, suceso "Deposit" (buche, misiones, reglas lo oyen).
- Las obreras que trabajan en una zona viajan solo hasta el hormiguero de esa zona.
- Tras el cambio, `python tools/sim.py` sigue aprobando los objetivos de ritmo y los tiempos por capa quedan cerca de los de hoy (ver Balance).

## No objetivos

- Rediseñar Túnel, Alas, Abeja, Puesto avanzado, catapulta, "Obreras rápidas", "Autopista" o "Senda de feromonas" (después, aparte).
- Cambiar el hormiguero de casa: sigue siendo de cada jugadora, crece, lleva su cartel, el huevo y los hongos.
- Jardín (zona 1): sin hormiguero de zona; se entrega en casa como hoy.

## Antiobjetivos

- Que el juego se acorte mucho (contenido consumido en poco tiempo, jalea demasiado pronto).
- Que el hormiguero de zona tape el camino, la puerta o los racimos.
- Que el antitrampas castigue las entregas legítimas en zona, o que se pueda abusar de él para entregar sin viajar.
- Romper a quien ya juega: partidas guardadas sin cambios de formato.

## Restricciones

- Rojo, Luau, estilo del proyecto; el servidor manda.
- `tools/sim.py` copia a mano las constantes de `Config`: si cambia una, cambia la otra.
- Panel DEV: la pestaña Viaje ya lleva a la entrada de cada zona; debe seguir funcionando (y la regla del proyecto: lo nuevo aparece en el panel si se puede probar).
- Antitrampas (`PlayerService.canReach`/`moved`): la entrega en zona pasa por el mismo control que la de casa.

## Enfoques considerados

| Enfoque | Qué tiene | Qué cuesta |
|---|---|---|
| **Módulo nuevo `Depots` en el servidor** (elegido) | Parte básica del juego; una sola fuente de verdad para entrega a pie, obreras, Extras y cliente | Tocar varios módulos que hoy suponen "entregar = casa" |
| Ampliar el Puesto avanzado (Extras) | Ya existe la entrega y el atajo de obreras | Extras es opcional y el puesto solo existe si se compra; mezclaría algo básico con una mejora que se rediseñará |

Sobre a quién pertenece: uno compartido por zona (elegido) frente a uno por jugador y zona (hasta 84 en el mapa, más desorden).

## Diseño

### Modelo y lugar

- `World` construye un hormiguero de zona por cada zona 2..14, a la entrada (cerca de `zone.z0`, por dentro de la puerta), a un lado del camino para no tapar el paso ni la puerta. Aspecto: montículo de hormiguero con la paleta del tema de la zona (`Themes`/`Decor*`), más pequeño que el de casa, con un cartel "Entrega aquí".
- Se publica para el cliente (p. ej. carpeta `Workspace.Depots` con un modelo por zona y atributo `Zone`).

### Servidor: `Depots`

- Lista de puntos de entrega: posición y radio de cada hormiguero de zona.
- `Depots.near(profile, position) -> zone?`: el hormiguero de zona dentro del radio de entrega, si la jugadora tiene esa zona abierta (`depth >= zona`, o llave maestra activa para esa zona).
- `Depots.forFood(profile, def, foodPos) -> (position, distance)?`: el hormiguero de la zona de esa comida, para las obreras.

### Entrega a pie

- `PlayerService.depositLoop`: entrega si está en el radio de casa **o** `Depots.near` devuelve zona, con el mismo `canReach`/`moved`. Mismo `fxRemote "Deposit"` con la posición del hormiguero donde entregó.

### Obreras

- `Colony`: el alcance del viaje de una obrera a comida de la zona N≥2 se mide desde el hormiguero de la zona N (sin tramo hasta casa). Sustituye el uso actual de `Colony.shortcut` para este caso; el atajo del Puesto avanzado sigue existiendo, pero queda sin efecto en zonas con hormiguero (se rediseñará).
- El dibujo de obreras en el cliente (`Swarm`) debe ir y venir entre la comida y el hormiguero de zona, no hasta casa, para que se vea lo que pasa.

### Extras y demás oyentes

- `Extras`: el buche y cualquier "¿estoy en un punto de entrega?" (`atDepot`) cuentan el hormiguero de zona.
- Revisar quién más supone "entregar = hormiguero de casa" (misiones, reglas de `Perks`, `Opening`, `Juice`): que funcionen igual al entregar en zona.

### Cliente

- `Juice`: la flecha de carga llena apunta al punto de entrega más cercano que tengas abierto.
- Textos que digan "llévalo a tu hormiguero" pasan a "a un hormiguero" donde aplique.

### Balance (mantener el ritmo)

- `tools/sim.py`: modelar que el viaje de vuelta (a mano y de obreras) en zonas ≥2 termina en el hormiguero de zona.
- Reajustar números de `Config` (los que el README señala para mover la curva: `FoodCurve.ZoneValues`, `StageGrowth`, `DigBase`, `CostScale`, u otros que el constructor vea más limpios) hasta que, en perfil activo, cada capa tarde lo mismo que hoy ±15 % y el total hasta la capa 14 quede en ~6 h ±10 %, y los objetivos APROBADO/FALLA no empeoren (hoy 307/308).
- Copiar los números nuevos a `sim.py` y a `Config` a la vez.

### Puesto avanzado

- Nodo `outpost` oculto del árbol y no comprable (sin borrarlo de los datos guardados); `Extras` deja de construir el puesto y su atajo de obreras; `sim.py` deja de comprarlo. Si `Config.Tree` no tiene forma de ocultar un nodo, el constructor elige la más limpia (y la deja anotada para el rediseño).

### Casa sigue importando (decisión de Claude)

- La despensa (`Social`), el huevo y los hongos siguen en el hormiguero de casa. Las entregas en zona llenan la despensa igual que las de casa. Volver a casa queda como algo que se hace de vez en cuando, no en cada viaje.

### Medir el balance sin optimismo (decisión de Claude)

- `sim.py` supone que la jugadora activa usa Túnel y Alas, así que a partir de la capa 6 casi no anda y el cambio apenas se nota allí. El reajuste se comprueba también con `SIN=tunnel,wings` (y con el perfil casual) para que el juego real no se acorte aunque el perfil activo diga que todo va bien.

### Panel DEV

- Sin pestaña nueva: "Viaje" ya lleva a la entrada de cada zona, junto al hormiguero de zona.

## Para el constructor

- Posición exacta del hormiguero en cada entrada, tamaño, radio de entrega y aspecto por tema.
- Qué números de `Config` mover para recuperar el ritmo.
- Cómo se ve en el cliente que una obrera entrega en zona.
- Actualizar README (Funcionamiento, Balance) y DISENO.md (mapa, ritmo).
