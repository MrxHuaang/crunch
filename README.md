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
| Túnel exprés (junto a tu agujero o a una salida) | mantener `B` (mando: `B`) | tocar el aviso |
| Lluvia propia | `L` | botón Lluvia |
| Mordisco cargado | dejar de morder junto a la comida y volver a morder | igual |

Comida dorada: de vez en cuando una comida sale de oro (brilla y suelta chispas) y vale x5; *Olfato dorado* hace que salgan más y que la tuya valga más. *Túnel exprés* (capa 2) abre un agujero junto a tu hormiguero con salida a la entrada de cada zona abierta. *Mordida en cadena*: al terminar una comida, un rayo salta a las de al lado del racimo y les arranca tres mordiscos tuyos, y luego un 70 % del anterior en cada salto.

La comida sale en racimos (`Config.FoodLayout`, `FoodService`): en cada zona del camino, 52 comidas en ocho racimos de 4 a 16 comidas casi tocándose (migas, mixtos con una grande rodeada de pequeñas, medianas y un banquete con la jefa de la zona, una grande con cuatro veces su vida), con pasillos libres entre ellos. Cada comida vuelve a su sitio del racimo. Las zonas miden 190 de ancho por 230 de largo (`Config.Map`).

Mejoras que cambian cómo juegas (`Config.Extras`, módulos `Extras`): *Mordisco cargado* (quieta junto a la comida tus mandíbulas brillan; el siguiente mordisco, o la carga llena, arranca un pedazo enorme), *Doble mandíbula* (cada mordisco muerde también la comida de al lado), *Buche* (te guardas parte de cada entrega para el viaje siguiente), *Puesto avanzado* (un hormiguero pequeño con tu nombre a la entrada de tu zona más honda: entregas allí y las obreras de esa zona salen de él), *Comida gigante* (una comida de tu zona crece varias veces), *Lluvia propia* (llueven migas de tu zona a tu alrededor) y *Senda de feromonas* (tus rastros brillan en el suelo y por ellos corres más).

Jardín vivo (`Config.Garden`, módulos `Garden`): la comida del jardín crece con la gente y las obreras conectadas, las obreras sin rastro no comen junto a hormigueros ajenos ni lo que alguien muerde, y junto al hormiguero de quien empieza nunca falta comida. Cada 2-3 minutos pasa algo pequeño (una mariposa suelta un regalo para la primera que llegue, hora feliz con la comida del jardín doble, un pan gigante para todas), y hay setas saltarinas y dientes de león para soplar.
Primeros pasos (`Config.Opening`, módulos `Opening`): quien empieza de cero sigue seis metas cortas en la tira de narración (morder, entregar, primera mejora, correr, primera obrera, capa 2), cada una con fiesta y un premio pequeño; sus primeras 30 migas valen el doble.

## Estructura

| Carpeta | Qué hay |
|---|---|
| `src/shared` | `Config` (todo el balance, zonas, comidas, árbol, tienda y textos), `Stats` (fórmulas), `FoodModels`, `AntModel` y `AntLook` (cómo cambia la hormiga con las mejoras y la ropa), `Assets` (ids de imágenes, sonidos y música) |
| `src/server` | `World` (jardín, camino, puertas, hormiguero que crece y su cartel), `HillModel` (el montículo visible; si falta, `World` pone uno sencillo), `Decor`, `Decor2` y `Decor3` (decorado de cada zona, por tema), `Nest` (huevo dorado y hongos junto al montículo), `FoodService`, `PlayerService` (morder, depositar), `Colony` (obreras), `Shop` (compras, excavar, vestidor, enjambrar), `Events` (bus de sucesos: comer, terminar, entregar, comprar, excavar, enjambrar, bocado dorado), `Monetize`, `Leaderboard`, `Data`, `Profiles` |
| `src/server`, opcionales | Se arrancan solo si existen: `Quests` (misiones y premio diario, escucha `Events`), `WorldEvents` (lluvia de migas y banquete), `PetService` (mascotas), `Hazards` (peligros de cada zona), `Allies` (la rama Aliadas: abeja mensajera, imán, escolta, pisotón, tirachinas, lupa, mega crunch), `GoldFood` (probabilidad de comida dorada), `Chain` (mordida en cadena, escucha `FinalBite`), `Tunnel` (agujeros y viajes del túnel exprés), `Extras` (mordisco cargado, doble mandíbula, buche, puesto avanzado, comida gigante, lluvia propia) |
| `src/client` | `Tree` (árbol-hormiguero por capas), `Hud`, `Swarm` (dibujo de obreras), `Abilities`, `Places` (puertas y ambiente por zona), `Wardrobe`, `Store`, `Fx`, `Bubble`, `Sfx` (sonidos y música), `Comic` (estilo), `State`, `Targeting`, `AntAnim` |
| `src/client`, opcionales | Se arrancan solo si existen: `Life` (bichos, banderas al viento, nubes), `Ambience` (partículas de cada zona), `Quests`, `WorldEvents`, `Pets`, `Hazards` (su parte de cliente), `Allies` (dibuja abeja, escarabajo, escolta y lupa de todas), `Extras` (brillo del mordisco cargado, migas de la lluvia, sendas de feromonas y su velocidad) |
| `src/client`, siempre | `Chain` (el rayo de la mordida en cadena), `Tunnel` (avisos del túnel, poste de zonas y viaje) |
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

- `Config.FoodCurve`: vida de cada comida (mordiscos que debe costar con la mordida de su capa: 6, 18 y 56 a media capa) y valor de cada zona (`ZoneValues`).
- `Config.Player` (`BitePower`, `BiteSplit`, `CarryGrowth`, `MinLoadBites`) y `Config.Milestones`: la mordida, la carga y sus hitos.
- `Config.StageGrowth` y `Config.DigBase`: cuánto más cuesta cada capa.
- `Config.CostScale`: abarata o encarece todo el árbol de golpe.

Antes de tocarlos, mira el efecto:

```bash
python tools/sim.py
```

Simula el bucle de verdad, viaje a viaje (ir hasta los racimos de una zona andando y corriendo, morder con su enfriamiento, mordiscos por comida, cadena y área dentro del racimo, llenarse y volver, con túnel, alas, abeja y puesto avanzado), la colonia con sus topes (una comida no cae en menos de 3 s; lo que sobra pasa a su racimo; ninguna zona da más de lo que rebrota) y el resto de ingresos, para tres perfiles: activo (85 % del tiempo jugando a mano), casual (45 %) y ausente (10 %). Por capa imprime minutos, compras, espera más larga entre compras, reparto del ingreso (mano, colonia, ayudantes, extras de la mano, resto, misiones, castas y social) y mordiscos por comida y por viaje, y termina con una lista APROBADO/FALLA de los objetivos de ritmo (`--detalle` la enseña entera). `python tools/sim.py --audit` añade la tabla de cada mejora: cuánto sube el ingreso al comprarla por primera vez y su retorno. Con los números actuales (activo): primera compra a los pocos segundos, primera obrera a los 3 minutos, capa 2 a los 9 minutos, luego unos 30 minutos por capa y unas 6 horas hasta la capa 14; casual, entre 1,6 y 2 veces más. También imprime las cifras de la hormiga al empezar cada capa y a media capa (mordida, mordiscos normales y pulsaciones por comida de su zona, pulsaciones por viaje y velocidad), las mismas que da `Stats.derive` en partida. La velocidad al andar tiene techo (`Config.Player.MaxWalk`, 45) y lo que las mejoras den de más se vuelve comida; igual con lo que arrancan a las vecinas área, cadena, doble mandíbula, escolta y mega crunch (`NeighborCap`). `SIN=bee,lens python tools/sim.py` simula sin las mejoras que digas y casi todos los números se pueden probar sin tocar el archivo (`BITE_POWER=1.3 python tools/sim.py`). Es una simulación, no una prueba con jugadores; `sim.py` copia las constantes de `Config`, así que si cambias unas cambia las otras.

Además de las 46 cámaras grandes (38 en cuatro ramas y 8 en la de Aliadas, sin galerías), el árbol tiene 504 galerías: cámaras pequeñas de un solo nivel, 9 por rama en cada capa, que se generan solas desde `Config.MiniTune` (costos, cantidades por tipo, y qué tipos salen en cada rama). Cuestan de 12 a 300 a escala de la capa, para que siempre haya algo barato que comprar, y el botón «Comprar lo barato» compra de golpe las que quepan en la mitad de tu comida. Sus efectos son pequeños a propósito (las de mordida, carga y obreras dan un 8-15 % de lo que se tiene a media capa); si subes los porcentajes permanentes, las capas finales se aceleran mucho.

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
