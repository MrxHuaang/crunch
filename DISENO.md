# CRUNCH! — Documento de diseño

Título en Roblox: **CRUNCH! 🐜 [Ant Incremental]**

Incremental de hormigas para Roblox. Empiezas como una hormiga sola que carga una miga por viaje. Terminas dirigiendo un enjambre que desmonta un picnic entero en segundos.

## Versión 2: lo que cambió respecto al MVP

Las secciones de abajo describen el MVP original. Esto es lo que manda ahora; los números exactos viven en `src/shared/Config.luau`.

**Mapa.** Un jardín redondo (radio 150) con los seis hormigueros en arco al fondo, separados unos 66 studs para que no se pisen al crecer, y, hacia delante, un camino recto partido en trece zonas con puerta, del exterior a la casa y de vuelta afuera: Picnic, Huerto, Jungla, Playa, Barbacoa, Cocina, Despensa, Nevera, Cuarto de juguetes, Escritorio, Feria, Dulcelandia y Espacio. Cada zona tiene tres comidas propias (la tercera suele ser dura) y su decorado. La Tarta está al final del Espacio.

**Capas.** El hormiguero se excava en catorce capas. Excavar la capa N abre la zona N, destapa una franja del árbol y sube el tope de las mejoras que crecen por capa (mordida, carga, velocidad, guardería…). Es el "nivel" que piden las puertas, y también la escala del montículo que ven los demás.

**Árbol.** Sigue siendo el corte del hormiguero, ahora una viñeta larga que se recorre hacia abajo: cuatro pozos (Mandíbulas, Patas, Colonia, Feromonas) cruzan las catorce capas, con las mejoras grandes en el pozo y galerías de mejoras pequeñas a los lados. La cámara real, al fondo.

**Mecánicas nuevas.** Racha (morder sin parar pega más), bocado dorado, saliva ácida contra comida dura, carga completa y reparto doble al entregar, huevos dorados y hongos junto al hormiguero, trofeos por terminar cada tipo de comida, alas de ida y vuelta, soldados visibles.

**Lo que ven los demás.** El montículo crece y cambia de color con las capas, gana banderas con cada enjambre y corona a los diez. Su cartel de madera dice la capa, los trofeos (uno por cada tipo de comida terminado alguna vez, +3 % de comida cada uno) y los enjambres. La hormiga cambia con lo que compra: mandíbulas, pinchos, abdomen, zapatos, alas, armadura, tamaño. El vestidor (colores, sombreros, estelas) se paga con comida y no se pierde al enjambrar.

**Junto al montículo.** Con la mejora de huevos dorados, cada cierto tiempo aparece un huevo brillante en el suelo, al lado contrario del cartel: pisarlo da varios minutos de colonia de golpe. Con el jardín de hongos crecen tres hongos al otro costado; maduros brillan, y comerse uno da comida doble un rato. Solo la dueña puede cogerlos.

**Enjambrar.** Ya no exige la tarta: se puede en cuanto la comida de la partida da una gota de jalea (hacia la zona 5 o 6). Comerse la tarta entera duplica la jalea de esa partida. Enjambrar en la capa 7 hace la segunda vuelta un ~43 % más rápida (antes, 86-99 %: casi no había segunda vuelta).

**Árbol Real.** Ocho mejoras pagadas con jalea (`Config.Royal`). Sus efectos se suman por nivel (+12 % de comida, de mordida o de colonia, `Config.Rebirth`) y sus precios se multiplican (`cost * growth ^ nivel`), así la jalea de más rinde cada vez menos y el árbol no se llena en dos vueltas. El Néctar real (+2 % de comida por nivel) no tiene tope: siempre hay algo en qué gastar la jalea, también la comprada.

**Tasa base de la colonia.** `data.baseRate` es lo que da la colonia sin frenesí, ratos x2, poción ni hongo, con los mismos topes. Con ella se calculan el progreso sin conexión, sacos, huevos, misiones, regalos y reglas: un potenciador activo ya no infla los premios. Olor a fiesta (la colonia al doble al entregar) salta como mucho cada 20 s; con viajes de 2-4 s era x2 siempre.

**Puntuación.** La comida reunida en toda tu vida: en la lista de jugadores de Roblox y en un cartel del jardín con las diez mejores, con números abreviados (K, M, B, T, Qd, Qn…).

**Arranque.** Las primeras comidas del jardín (miga, pipa, arándano) están hechas para leerse como comida a escala de hormiga, y la mitad de la comida del jardín sale cerca de los hormigueros y vuelve enseguida: los primeros viajes son cortos. La primera compra llega en segundos y la primera obrera hacia los dos minutos y medio.

**Hormigueros de zona.** Cada zona del camino (2 a 14) tiene a su entrada, a la derecha, un hormiguero compartido (`Config.Depot`, módulo `Depots`). Quien tiene la zona abierta (o la llave maestra) entrega ahí como en casa, y sus obreras de esa zona viajan solo hasta él: se acabó volver al jardín en cada viaje. La abeja y el tirachinas entregan en el hormiguero abierto más cercano (casa o zona). El Puesto avanzado se retiró del árbol; Túnel, Alas, Abeja, Obreras rápidas, Autopista y Feromona dulce se rediseñarán.

**Ritmo.** Según `tools/sim.py` (perfil activo): capa 2 hacia el minuto 9, después unos 22-33 minutos por capa y la capa 14 hacia las 5,5 horas. Para mantenerlo con los hormigueros de zona se rebajó el valor de la comida desde la zona 3 (`FoodCurve.ZoneValues`) y lo que rinden Feromona dulce, Obreras rápidas y Autopista. Es una simulación, falta probarlo con jugadores.

**Tienda.** Pases permanentes (comida doble, mordida automática, colonia veloz, alas doradas, VIP, jalea doble, patas turbo, despensa sin fondo) y productos de un uso (poción x2, saco, carretilla, pala dorada, frenesí, huevo dorado, tarros de jalea). Donde Roblox no deja vender azar (PolicyService), el próximo huevo de mascota se decide antes de pagar, se enseña y se guarda; el servidor solo cobra el que el cliente enseñaba.

**Celular.** `Hud.compact()` (pantalla táctil y pequeña) cambia la distribución: menú en rejilla arriba a la izquierda, habilidades sobre el botón de saltar, botones de al menos 44 px y textos a escala de la pantalla.

**Sonido y movimiento.** El botón del sonido abre un menú con Música, Efectos y Movimiento suave. Movimiento suave quita temblores, zoom y líneas que giran; arranca con la opción de movimiento reducido del sistema.

**Medición e insignias.** `Analytics` solo escucha: embudo de primeros pasos, capas, enjambres, economía de jalea y comida, y compras con Robux como evento propio. Las insignias (`Config.Badges`: capa 2, capa 7, primer enjambre, la Tarta, capa 14) llevan `badgeId = 0` hasta crearlas en Roblox; con 0 no se entregan.

**Retención.** El premio diario espera a que terminen los primeros pasos y deja un día de gracia por semana sin perder la racha. En Colonia hay un botón Invitar.

## Decisiones tomadas

| Tema | Decisión |
|---|---|
| Rol del jugador | Siempre controlas tu hormiga en tercera persona |
| Estilo visual | Cómic a color, cartoon: contorno negro, colores planos, onomatopeyas |
| Multijugador | Jardín compartido, cada jugador con su hormiguero. Sin combate ni robo |
| Alcance inicial | MVP de 1 zona (el jardín con un picnic) y un primer rebirth |

## 1. Bucle principal

1. Sales del hormiguero y buscas comida.
2. Muerdes la comida. Cada objeto tiene vida y se desmonta en trozos visibles.
3. Cargas trozos hasta tu capacidad.
4. Vuelves y depositas. Ganas **Comida** (moneda base).
5. Gastas Comida en mejoras y obreras.
6. Repites, cada vez más rápido y con objetos más grandes.

Regla de diseño: cada 2-5 minutos el jugador desbloquea algo que cambia cómo juega, no solo un número más alto.

## 2. Fases del MVP (cómo se va abriendo el juego)

| Fase | Tiempo aprox. | Qué pasa | Qué se desbloquea |
|---|---|---|---|
| 0. Sola | 0-3 min | 1 miga por viaje, caminas lento | Mejoras de mandíbula, carga y velocidad |
| 1. Primera obrera | 3-8 min | Una obrera repite tu ruta sola | Comprar más obreras |
| 2. Feromonas | 8-15 min | Marcas una comida y las obreras van en fila | Cubo de azúcar, galleta |
| 3. Soldados | 15-30 min | Las soldados rompen objetos duros | Manzana, sándwich, lata de refresco |
| 4. Reina | 30-50 min | La reina pone huevos sola: las obreras se compran solas | Cámaras nuevas del hormiguero |
| 5. Enjambre | 50-90 min | Cientos de hormigas visibles, la comida desaparece en segundos | La Tarta (objetivo final de zona) |
| 6. Rebirth | ~90 min | Te comes la Tarta y puedes **Enjambrar** | Jalea Real y mejoras permanentes |

La segunda partida debe durar cerca de la mitad que la primera. La tercera, menos.

## 3. Recursos

- **Comida**: moneda base. Se gana depositando. Se reinicia al Enjambrar.
- **Jalea Real**: moneda de prestigio. Se gana al Enjambrar. Nunca se pierde.
- **Población**: cantidad de obreras y soldados. Limitada por las cámaras del hormiguero.

Después del MVP: Mutágeno (drop raro de enemigos, para mutaciones) y pulgones (mascotas que dan bonos).

## 4. Árbol de mejoras: el hormiguero en corte

El árbol de habilidades es el propio hormiguero visto en corte lateral, como una viñeta de cómic. Cada cámara es un nodo y cada túnel es una conexión. Comprar un nodo excava esa cámara y se ve en tu hormiguero real del mapa.

Cuatro ramas que salen de la entrada:

**Mandíbulas** (tu hormiga, fuerza)
- Mordida fuerte: más daño por mordisco (niveles 1-25)
- Mordida doble: probabilidad de golpe crítico con onomatopeya "¡CRUNCH!"
- Mandíbula sierra: puedes morder objetos duros sin soldados
- Mordida en área: dañas todo lo cercano

**Patas** (tu hormiga, movilidad)
- Paso rápido: velocidad de movimiento
- Lomo fuerte: capacidad de carga
- Sprint: carrera corta con enfriamiento
- Alas: planeas de vuelta al hormiguero (desbloqueo tardío, muy satisfactorio)

**Colonia** (automatización)
- Guardería: desbloquea obreras
- Obreras rápidas / obreras fuertes
- Cuartel: desbloquea soldados
- Cámara real: la reina compra obreras sola
- Almacén: comida que se gana estando desconectado (límite de horas)

**Feromonas** (control del enjambre)
- Rastro: marcar una comida como objetivo
- Rastro doble / triple: varios objetivos a la vez
- Frenesí: habilidad activa, todo el enjambre x3 durante 15 s
- Rastro inteligente: las obreras eligen solas la comida más rentable

Nodos con costo en Comida se reinician al Enjambrar. Hay un segundo árbol pequeño, el **Árbol Real**, que se paga con Jalea Real y es permanente: multiplicador global, empezar con obreras, conservar ciertas cámaras, desbloquear zonas.

## 5. Rebirth: Enjambrar

- Requisito: terminar la Tarta.
- Animación: vuelo nupcial, la colonia sale volando en una viñeta a página completa.
- Jalea Real ganada = `floor(sqrt(comidaTotalDeLaPartida / 1e6))`. La raíz cuadrada da saltos grandes al inicio y rendimientos decrecientes después.
- Se reinicia: Comida, obreras, nodos de Comida.
- Se conserva: Jalea Real, Árbol Real, cosméticos, estadísticas.
- El juego avisa cuándo conviene Enjambrar ("ganarías 12 de Jalea"), para que el jugador no lo haga demasiado pronto ni demasiado tarde.

## 6. Números

- Costo de mejora: `base * 1.15^nivel` (obreras), `base * 1.5^nivel` (nodos de pocos niveles).
- Producción: lineal por unidad, multiplicada por nodos y Jalea.
- Comida de cada objeto: cada nivel de objeto vale unas 8-10 veces el anterior y tiene unas 6 veces más vida.
- Formato: 1.2K, 3.4M, 5.6B, luego notación `1.2e15`. Los `number` de Luau llegan a 1e308, suficiente para el MVP.
- Todos los valores viven en tablas de configuración (`shared/Config`) para balancear sin tocar lógica.

## 7. Qué lo hace satisfactorio

- La comida se **desmonta de verdad**: 6-8 estados de daño por objeto, con trozos que saltan.
- **Filas de hormigas** cargando trozos más grandes que ellas.
- Onomatopeyas de cómic: "¡ÑAM!", "¡CRUNCH!", "¡POP!" en cada mordida fuerte.
- Números que saltan del hormiguero al depositar.
- Tu hormiga **crece** un poco con cada rama completada.
- Sonido con tono que sube en rachas de depósitos.
- Cámara que se aleja poco a poco a medida que crece el enjambre.

## 8. Estilo cómic en Roblox

- **Contorno negro**: técnica de casco invertido hecha en Blender (malla duplicada, normales invertidas, negra, un poco más grande). El `Highlight` de Roblox tiene un límite bajo de instancias simultáneas y no sirve para un enjambre.
- **Colores planos**: material liso, sin PBR. Paleta corta y saturada.
- **Tramas de puntos** (halftone) en sombras del suelo y fondos de UI.
- **Escala**: todo se ve desde abajo. Hierba como árboles, zapatos como edificios.
- **UI**: paneles tipo viñeta con borde negro grueso, bocadillos, fuentes Bangers o Luckiest Guy (incluidas en Roblox).
- **Luz**: cálida de tarde, sombras suaves, saturación subida con ColorCorrection.

## 9. Arquitectura técnica

- **Servidor manda**: toda la economía se calcula en el servidor. El cliente solo pide acciones ("morder", "depositar", "comprar"). El servidor valida distancia, enfriamiento y saldo.
- **Guardado**: DataStore con bloqueo de sesión propio (`src/server/Data.luau`, sin ProfileStore): cada guardado lleva el servidor dueño y la hora; otro servidor no carga hasta que se suelta o caduca (90 s). Guarda al salir, cada minuto y al cerrar.
- **Revisión**: `selene src` en GitHub Actions en cada push y pull request (`.github/workflows/ci.yml`).
- **Enjambre**: las obreras son un número en el servidor (producción por segundo hacia cada objetivo). El cliente dibuja un máximo de unas 300 hormigas, sin Humanoid, movidas en lote con `workspace:BulkMoveTo`. Si hay más, cada hormiga visible representa a varias.
- **Comida**: el servidor guarda la vida. El cliente cambia el estado visual.
- **Hormiga del jugador**: personaje propio (StarterCharacter) con 6 patas. En el MVP, animación de patas por código; luego animación hecha en Blender.
- **Progreso sin conexión**: se calcula al entrar, con tope de horas según el nodo Almacén.

Estructura del proyecto (Rojo):

```
src/
  server/    Economía, guardado, validación, comida
  client/    Controles, enjambre visual, UI, efectos
  shared/    Config (mejoras, árbol, comida), fórmulas, formato de números
assets/      Modelos de Blender y texturas
```

## 10. Herramientas

**Obligatorias**
- Roblox Studio (gratis, con cuenta de Roblox)
- Git
- Rokit (gestor de herramientas) y con él Rojo, que sincroniza los archivos de código con Studio, y selene, el linter
- Plugin de Rojo dentro de Studio
- Servidor MCP de Roblox Studio (viene integrado en Studio): deja que Claude vea y edite el lugar abierto

**Arte**
- Blender (ya instalado): modelos, contorno de casco invertido, exportar FBX
- Krita (gratis): texturas de trama, iconos y piezas de UI
- Sonidos: Creator Store de Roblox y jsfxr (web, gratis) para efectos

**Opcionales**
- VS Code con la extensión Luau LSP, para leer y tocar código a mano
- Audacity para recortar audio
- Generador 3D con IA (el de Studio, Meshy o Tripo) para mallas base que luego se limpian en Blender

## 11. Hitos

| Hito | Contenido | Hecho cuando |
|---|---|---|
| 0. Montaje | Instalar herramientas, proyecto Rojo, Claude conectado a Studio | Un script de prueba se sincroniza y corre |
| 1. Bucle base | Hormiga, migas, morder, cargar, depositar, contador | Se puede farmear con cubos grises |
| 2. Mejoras y guardado | Mejoras básicas, DataStore con bloqueo de sesión | El progreso sobrevive a salir y entrar |
| 3. Enjambre | Obreras, feromonas, render en lote | 300 hormigas en fila sin caídas de FPS |
| 4. Árbol-hormiguero | UI en corte, 4 ramas, cámaras que se excavan | Todas las fases 0-5 son alcanzables |
| 5. Rebirth | Tarta, Enjambrar, Árbol Real | Segunda partida más rápida que la primera |
| 6. Arte y jugo | Modelos cómic, onomatopeyas, sonido, cámara | Se ve y se oye como cómic |
| 7. Prueba | 3-5 amigos juegan, ajuste de balance | Nadie se atasca más de 5 min sin desbloqueo |
| 8. Publicar | Icono, miniaturas, descripción, gamepasses simples | Juego público |

## 12. Después del MVP

- Zonas nuevas: cocina, basurero, ciudad
- Enemigos: arañas y escarabajos que atacan filas
- Pulgones como mascotas coleccionables
- Eventos: lluvia (riesgo), picnic que cae del cielo (premio)
- Mutaciones con Mutágeno
- Clasificaciones y regalos diarios
- Segunda capa de prestigio
