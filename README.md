# CRUNCH!

Incremental de hormigas para Roblox, con estética de cómic. Empiezas sola con una miga por viaje, excavas tu hormiguero capa a capa y cada capa te abre un sitio nuevo: del jardín al picnic, el huerto, la jungla, la playa, la barbacoa, la cocina, la despensa, la nevera, el cuarto de juguetes, el escritorio, la feria, Dulcelandia y el espacio (catorce zonas, una por capa). El diseño completo está en [DISENO.md](DISENO.md).

## Cómo trabajar

1. Abre el lugar en Roblox Studio.
2. En una terminal, dentro de esta carpeta:

   ```bash
   rojo serve
   ```

3. En Studio: pestaña **Plugins** → **Rojo** → **Connect**.
4. Pulsa **Play**.

Todo el juego se construye por código al arrancar el servidor (mapa, luz, hormigueros, comida y la hormiga). El lugar de Studio puede estar vacío. `Workspace.StreamingEnabled` debe estar apagado: el mapa es pequeño y los clientes dibujan las obreras a partir de los hormigueros, que tienen que estar siempre cargados.

## Controles

| Acción | Teclado | Táctil |
|---|---|---|
| Morder | mantener clic o `E` | mantener pulsado |
| Hormiguero (árbol de mejoras) | `Q` | botón Hormiguero |
| Vestidor | `V` | botón Vestidor |
| Coger el huevo dorado o un hongo maduro (junto a tu hormiguero) | pisarlo | pisarlo |
| Rastro, sprint, alas, frenesí, pisotón, tirachinas | `F`, `Shift`, `R`, `G`, `X`, `C` | botones a la derecha |

## Estructura

| Carpeta | Qué hay |
|---|---|
| `src/shared` | `Config` (todo el balance, zonas, comidas, árbol, tienda y textos), `Stats` (fórmulas), `FoodModels`, `AntModel` y `AntLook` (cómo cambia la hormiga con las mejoras y la ropa), `Assets` (ids de imágenes, sonidos y música) |
| `src/server` | `World` (jardín, camino, puertas, hormiguero que crece y su cartel), `HillModel` (el montículo visible; si falta, `World` pone uno sencillo), `Decor`, `Decor2` y `Decor3` (decorado de cada zona, por tema), `Nest` (huevo dorado y hongos junto al montículo), `FoodService`, `PlayerService` (morder, depositar), `Colony` (obreras), `Shop` (compras, excavar, vestidor, enjambrar), `Events` (bus de sucesos: comer, terminar, entregar, comprar, excavar, enjambrar, bocado dorado), `Monetize`, `Leaderboard`, `Data`, `Profiles` |
| `src/server`, opcionales | Se arrancan solo si existen: `Quests` (misiones y premio diario, escucha `Events`), `WorldEvents` (lluvia de migas y banquete), `PetService` (mascotas), `Hazards` (peligros de cada zona), `Allies` (la rama Aliadas: abeja mensajera, imán, escolta, pisotón, tirachinas, lupa, mega crunch) |
| `src/client` | `Tree` (árbol-hormiguero por capas), `Hud`, `Swarm` (dibujo de obreras), `Abilities`, `Places` (puertas y ambiente por zona), `Wardrobe`, `Store`, `Fx`, `Bubble`, `Sfx` (sonidos y música), `Comic` (estilo), `State`, `Targeting`, `AntAnim` |
| `src/client`, opcionales | Se arrancan solo si existen: `Life` (bichos, banderas al viento, nubes), `Ambience` (partículas de cada zona), `Quests`, `WorldEvents`, `Pets`, `Hazards` (su parte de cliente), `Allies` (dibuja abeja, escarabajo, escolta y lupa de todas) |
| `art` | `gen_art.py` genera las texturas e iconos en `art/out` |
| `tools` | `sim.py` simula cuánto tarda cada capa con los números actuales |

## Zonas

Una por capa del hormiguero, en este orden por el camino (`Config.Zones` y `FOOD_LIST`; la comida en cursiva es dura):

| Capa | Zona (tema) | Comidas |
|---|---|---|
| 1 | Jardín | Miga, Pipa, Arándano |
| 2 | Picnic | Galleta, Sándwich, *Manzana* |
| 3 | Huerto | Fresa, Tomate, *Zanahoria* |
| 4 | Jungla | Uvas, Plátano, *Coco* |
| 5 | Playa (`Mar`) | Patatas fritas, Helado, *Sandía* |
| 6 | Barbacoa | Mazorca asada, Brocheta, *Costillas* |
| 7 | Cocina | Cubo de azúcar, Huevo frito, Queso |
| 8 | Despensa | Cereales, Pan de molde, *Tarro de miel* |
| 9 | Nevera | Yogur, Sushi, *Lata de refresco* |
| 10 | Cuarto de juguetes (`Juguetes`) | Ganchitos, Zumo, *Huevo sorpresa* |
| 11 | Escritorio | Cruasán, Barrita de cereales, *Nuez* |
| 12 | Feria | Palomitas, Perrito caliente, Hamburguesa |
| 13 | Dulcelandia (`Dulce`) | Donut, Magdalena, *Chocolate* |
| 14 | Espacio | Gominola, Pizza, Tarta (jefa) |

Para añadir una zona: su entrada en `Config.Zones` y `Config.Layers`, tres comidas en `FOOD_LIST` con su constructor en `FoodModels`, su decorado en un módulo `Decor*` (con `Themes`), su ambiente en `Ambience` y `Places`, y las listas de `tools/sim.py`. Los peligros (`Hazards`) buscan su zona por tema, no por número.

## Balance

Todo está en `src/shared/Config.luau`. La curva entera se mueve con pocos números:

- `Config.FoodCurve`: vida y valor de cada comida según su puesto en la lista.
- `Config.StageGrowth` y `Config.DigBase`: cuánto más cuesta cada capa.
- `Config.CostScale`: abarata o encarece todo el árbol de golpe.

Antes de tocarlos, mira el efecto:

```bash
python tools/sim.py
```

Imprime los minutos que tarda en llegar a cada capa un jugador que compra siempre lo más barato. Con los números actuales: primera compra a los pocos segundos, primera obrera hacia los 2,5 minutos, capa 2 a los 10 minutos, luego entre 30 y 48 minutos por capa salvo la 6, la 7 y la 8, que van más rápidas, y unas 7 horas la primera partida entera de 14 capas. La abeja mensajera es lo que más mueve el ritmo (sin ella, casi 9 horas); `SIN=bee,lens python tools/sim.py` simula sin las mejoras que digas. El simulador copia también la geometría del mapa (distancia de los hormigueros a cada zona y la comida del jardín, que sale a medias junto a los hormigueros) y el tope de la colonia: una comida no cae en menos de 3 segundos por muchas obreras que haya, y sin rastros la colonia trabaja en tres comidas del jardín a la vez. Es una simulación, no una prueba con jugadores; `sim.py` copia las constantes de `Config`, así que si cambias unas cambia las otras.

Además de las 46 cámaras grandes (38 en cuatro ramas y 8 en la de Aliadas, sin galerías), el árbol tiene 504 galerías: cámaras pequeñas de un solo nivel, 9 por rama en cada capa, que se generan solas desde `Config.MiniTune` (costos, cantidades por tipo, y qué tipos salen en cada rama). Cuestan de 15 a 600 a escala de la capa, para que siempre haya algo barato que comprar, y el botón «Comprar lo barato» compra de golpe las que quepan en la mitad de tu comida. Sus efectos son pequeños a propósito: lo que más mueve el ritmo es el Paladar de cada capa (`MiniTune.Zone`), que solo sube la comida de esa zona; si subes los porcentajes permanentes, las capas finales se aceleran mucho.

## Pendiente de configurar en Roblox

- **Guardado en Studio**: Configuración del juego → Seguridad → activar *Enable Studio Access to API Services*. Sin eso, en Studio se juega sin guardar y el cartel de puntuaciones solo muestra a los jugadores del servidor (en el juego publicado guarda siempre y el cartel es mundial).
- **Jugadores por servidor**: 6 como máximo. Hay 6 hormigueros.
- **Microtransacciones**: crea los pases y productos en el panel de creador (Monetización) y pega sus ids en `Config.Passes` y `Config.Products`. Cada uno trae un precio sugerido en `robux`. Con id `0` el artículo no aparece en el juego publicado; en Studio se listan todos para revisar la tienda.
- **Música**: `Assets.Music` es una lista de temas del catálogo libre de Roblox elegidos por búsqueda. Escúchalos y cambia los que no te gusten.

## Herramientas de desarrollo (solo en Studio)

Con el juego en Play, desde la barra de comandos en vista de servidor:

```lua
local d = game.ServerScriptService.CrunchDebug
d:Fire("food", 5000)        -- dar comida
d:Fire("depth", 4)          -- fijar la capa excavada
d:Fire("max", 4)            -- todo el árbol al tope de la capa 4
d:Fire("minis")             -- todas las galerías de las capas ya excavadas
d:Fire("node", "bite", 6)   -- fijar el nivel de un nodo
d:Fire("workers", 20)       -- fijar obreras
d:Fire("jelly", 10)         -- fijar jalea
d:Fire("rebirths", 3)       -- fijar enjambres (banderas y corona)
d:Fire("tarta")             -- marcar la tarta como comida
d:Fire("grant", "vip")      -- entregar un pase o producto por su id de Config
```

## Arte

```bash
python art/gen_art.py
```

Genera trama, cielo, viñeta, líneas de velocidad, estallido e iconos. Si cambias una imagen hay que volver a subirla a Roblox y actualizar su id en `src/shared/Assets.luau`. Varias mejoras nuevas del árbol reutilizan el icono de su familia (campo `icon` en `Config.Tree`).
