# Panel de desarrollador (solo Studio)

Fecha: 2026-11-14

## Para qué

Julián (no programa) quiere probar CRUNCH! sin jugar horas. Hoy hay que escribir comandos a mano en la barra de comandos de Studio (`CrunchDebug:Fire("max", 4)`, `PetDebug`, comandos de castas) y los eventos no se pueden lanzar: salen solos con temporizador. Lo que más va a hacer:

1. **Saltar a etapas avanzadas** (capa N con el árbol listo) para ver zonas y mejoras del final.
2. **Lanzar eventos** al momento para verlos y comprobar que reparten bien.
3. **Darse comida** (y jalea) para comprar mejoras a mano.

Éxito: con un par de clics, sin escribir nada, está en la situación que quiere probar.

## Objetivos

- Un panel dentro del juego, visible al darle Play en Studio.
- Secciones: **Partida**, **Eventos**, **Viaje**.
- Lo que hace el panel se ve igual que en el juego real (los atributos y la interfaz se refrescan como siempre).

## No objetivos

- Que funcione en el juego publicado. Decidido: solo Studio.
- Editar balance (`Config`) desde el panel.
- Herramientas para mascotas y castas más allá de lo que ya hacen `PetDebug` y los comandos de castas (se pueden exponer como botones simples, ver "Para el constructor").

## Antiobjetivos (sería un fracaso aunque funcione)

- **Que el panel o su RemoteEvent exista en un servidor publicado.** Un jugador podría darse comida.
- **Ensuciar datos reales.** Si en Studio se activa el acceso a la API, Studio y el juego publicado comparten DataStore: darse mil millones de comida en Studio quedaría guardado en la cuenta real y en el ranking mundial. Se resuelve con almacenes de prueba en Studio (ver Datos).
- Romper la barra de comandos actual (`CrunchDebug`, `PetDebug`): el README la documenta y el compañero la usa.

## Restricciones

- Rojo: código en `src/`, todo `.luau`, estilo del proyecto (tabulaciones, comentarios en español, módulos opcionales que arrancan solo si existen).
- El servidor manda: el cliente solo pide acciones por un RemoteEvent.
- El antitrampas de `PlayerService` (ancla de viaje): un teletransporte del panel tiene que llamar a `PlayerService.moved` o la siguiente acción esperaría.
- Interfaz con las piezas de `client/Comic.luau` (estilo cómic, sin degradados).

## Enfoques considerados

| Enfoque | Qué tiene | Qué cuesta |
|---|---|---|
| **A. Panel dentro del juego** (elegido) | Clics, sin memorizar nada; se prueba como lo ve un jugador | El más trabajoso: interfaz + servidor + un disparador por evento |
| B. Comandos de chat (`/comida 1000`) | Rápido de hacer | Hay que recordar comandos; Julián no programa |
| C. Plugin de Studio | Panel en la barra de Studio | Instalación aparte, más difícil de mantener, sin ventaja sobre A |

Julián eligió **A**.

## Diseño

### Seguridad: solo Studio

- Servidor: `src/server/DevTools.luau`, arrancado desde `init.server.luau` **solo si `RunService:IsStudio()`**. Crea el RemoteEvent `Dev` dentro de la carpeta de remotos. Fuera de Studio no se crea nada.
- Cada manejador vuelve a comprobar `RunService:IsStudio()` (defensa doble) y valida tipos y rangos.
- Cliente: `src/client/DevPanel.luau`, arrancado solo si existe `Remotes.Dev` (así en el juego publicado ni se dibuja).

### Datos: en Studio, almacén de prueba separado (decidido por Julián)

En Studio el juego usa siempre otros almacenes: `Config.Save.Store .. "_studio"` para las partidas y `Config.Save.TopStore .. "_studio"` para el ranking. Lo hecho en Studio (con el panel o con `CrunchDebug`) se guarda y se puede probar saliendo y volviendo a entrar, pero nunca toca las partidas reales ni el ranking mundial. Consecuencia aceptada: en Studio no se ve la partida real, sino una de prueba que empieza de cero. El cambio va en `Data` (`getStore`) y en `Leaderboard`, con una línea cada uno según `RunService:IsStudio()`. El panel muestra un aviso fijo "Datos de prueba (Studio)".

Alternativa descartada: que la sesión deje de guardar al usar el panel (no deja probar la persistencia y `CrunchDebug` seguiría ensuciando datos reales).

### Partida

- **Preparar capa N** (1–14), decisión de Claude: parte de una partida limpia (como "Reiniciar partida") y deja a la jugadora como si hubiera llegado ahí: capa N, árbol al tope de la capa N (como `max`) y galerías de las capas ≤ N (como `minis`). Así bajar de 14 a 3 no deja restos. No toca jalea, árbol real, enjambres, mascotas, castas ni compras.
- **Comida**: botones +1K, +1M, +1B, +1T (pasa por `Profiles.addFood`, como hoy).
- **Jalea**: +10, +100. **Enjambres**: fijar 0–10 (banderas y corona).
- **Reiniciar partida**, decisión de Claude: como enjambrar sin premio. A cero: comida de la partida, capa, árbol (`nodes`), galerías (`minis`), obreras y lo que lleva encima. Se conservan jalea, árbol real, enjambres, trofeos, vestidor, mascotas, castas y compras (así no se desincronizan los módulos que guardan estado propio).
- **Pases y productos**: lista de `Config.Passes` y `Config.Products` con botón "Dar" (usa `Monetize.debugGrant`).

### Eventos

Un botón por evento. Cada módulo de eventos expone una función pequeña de disparo (hoy solo arrancan con temporizador). Decisión de Claude: el evento sale por su camino normal, con su aviso previo, para verlo como un jugador; si ya hay uno en curso en ese módulo, no se fuerza y el panel dice "ya hay un evento activo". El disparo adelanta el siguiente evento del planificador, no reescribe su lógica.

- `WorldEvents`: lluvia de migas, banquete.
- `Garden`: mariposa con regalo, hora feliz, pan gigante.
- `Nest`: huevo dorado y hongos maduros ya (para quien pulsa).
- Otros si son baratos de exponer: comida dorada (`GoldFood`), pisotón de peligro (`Hazards`).

### Viaje

- **Ir a zona N**: a la entrada de la zona (`Config.zoneStart`), y **A casa** (spawn del hormiguero). El servidor mueve al personaje y llama a `PlayerService.moved`.

### Interfaz

- Botón pequeño "DEV" en una esquina y tecla **F2** para abrir/cerrar.
- Panel con tres pestañas (Partida, Eventos, Viaje) hecho con `Comic.box`, `Comic.button`, `Comic.label`.
- Al pulsar algo, un aviso corto en el propio panel ("+1M de comida", "Lluvia lanzada").

```
┌─ DEV · datos de prueba ─────┐
│ [Partida] [Eventos] [Viaje] │
│ Capa [8 ▾]  [Preparar]      │
│ Comida [+1K][+1M][+1B][+1T] │
│ Jalea  [+10][+100]          │
│ Enjambres [− 3 +]           │
│ [Reiniciar partida]         │
└─────────────────────────────┘
```

### Se actualiza solo con el juego (pedido por Julián)

El panel no lleva listas escritas a mano: todo sale de donde ya vive, para que una zona, un evento o un artículo nuevo aparezca sin tocar el panel.

- **Zonas y capas**: de `Config.Zones` y `Stats.MaxDepth`.
- **Pases y productos**: de `Config.Passes` y `Config.Products`.
- **Eventos**: registro en el servidor. Cada módulo que tiene un evento lo apunta al arrancar, por ejemplo `DevTools.register("rain", "Lluvia de migas", función)`. Fuera de Studio `register` no hace nada. El cliente pide la lista al abrir y dibuja un botón por entrada. Un evento nuevo solo necesita su línea de `register` en su propio módulo.
- **Comandos de castas y mascotas**: si entran como botones, por el mismo registro.
- Al añadir un evento o una zona, quien lo haga (persona o Claude) añade su registro; el README lo explica en "Herramientas de Studio".

### Relación con lo que ya existe

- La lógica de `CrunchDebug` se mueve a una función compartida en `DevTools` (o `PlayerService` la expone) para que el panel y la barra de comandos hagan exactamente lo mismo. `CrunchDebug` sigue existiendo con los mismos comandos.
- `CrunchDebug` hoy aplica a todos los jugadores; el panel aplica solo a quien pulsa (en una prueba local con varios clientes, cada uno controla lo suyo).

## Para el constructor (decisiones abiertas de implementación)

- Qué eventos menores incluir aparte de los listados, según lo fácil que sea exponerlos sin tocar su lógica.
- Si las castas y mascotas entran como botones (elegir casta, rango 10, sin enfriamientos; dar mascota), reutilizando los comandos existentes.
- Distribución exacta del panel, tamaños y posición, siguiendo el estilo de `Hud`.
- Actualizar el README (sección "Herramientas de Studio").
