# Plan 06 — Pedidos y cola de cocina

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 06 — Pedidos y cola de cocina
- **Incremento:** pedidos sobre la URL pública
- **Estado:** 🔵 **En curso — aprobado** el 2026-09-24, con "para llevar o comer aquí" (D-34)
- **Entrada al tablero:** 2026-09-24
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Cerrar el recorrido que el E2 pide ver funcionando **en la dirección pública**:

1. Recepción termina la venta, y **el pedido queda guardado** con el precio que calcula el
   servidor.
2. **Cocina lo ve en menos de 2 segundos**, sin recargar, en orden de llegada.
3. Cocina lo **empieza** y lo marca **listo**.
4. Recepción lo **entrega**, o lo **cancela** antes de que esté listo, con un motivo.

Con eso, el pedido tiene su **CRUD completo**: se crea, se lee, se actualiza su estado y se
da de baja. Cada cambio queda registrado con quién lo hizo y cuándo.

---

## 2. Alcance

**Incluye:**

- **Dos pasos nuevos en la venta**, antes del resumen:
  - **"¿Para llevar o para comer aquí?"** (D-34);
  - **"¿A nombre de quién?"** (D-31), con el nombre obligatorio y el celular opcional.
- **`POST /api/v1/pedidos`:** valida todo de nuevo, calcula el precio con la regla de D-27 y
  guarda el pedido **en una sola transacción**.
- **`GET /api/v1/pedidos`** (los activos, con filtro por estado) y **`GET
  /api/v1/pedidos/:id`** (con sus líneas y su historial).
- **`PATCH /api/v1/pedidos/:id/estado`:** los cambios de estado, cada uno solo para el rol
  que le corresponde.
- **`POST /api/v1/pedidos/:id/cancelacion`:** la baja, con motivo (D-33, adelantada de la
  tarjeta 08).
- **Un canal en vivo mínimo con Socket.IO (D-21):** los eventos `pedido:nuevo` y
  `pedido:estado`, con el mismo token que la API.
- **La pantalla de cocina:** la cola en vivo, con *Empezar* y *Listo*.
- **Los pedidos en recepción:** los activos en vivo, con *Entregar*, *Cancelar* y *Llamar*.
- **Una migración, la `06`:** el dato de si el pedido es para llevar, el formato del celular,
  un celular por cliente y el motivo de la cancelación.

**No incluye:**

- **Lo que hace robusto al canal en vivo (tarjeta 07):**
  - reconectar solo y avisar cuando el canal se cae (RNF-05);
  - renovar el token de una conexión abierta;
  - el evento `producto:disponibilidad`.
- **Marcar un producto agotado:** tarjeta 08.
- **Editar las líneas de un pedido ya enviado:** si el cliente cambia de idea, el pedido se
  cancela y se hace de nuevo. Así la cocina nunca prepara algo que cambió sin avisar.
- **El tiempo de espera en la cola (RF-10) y el comprobante (RF-12):** son *Could*.
- **Buscar o autocompletar clientes ya registrados:** trabajo futuro.

---

## 3. Decisiones de diseño

1. **Manda el servidor, y avisa si no coincide.**
   - La app envía qué se pidió y el **total que mostró**.
   - El servidor lee los productos de la base **dentro de la transacción**, calcula cada línea
     con la regla de D-27 y lo compara con ese total.
   - Si no coinciden, responde **409 `PRECIO_CAMBIADO`** con el total correcto, y la app
     recarga la carta. Solo pasa si la carta cambió en medio de la venta.
   - Un producto agotado o inexistente da **409 `PRODUCTO_NO_DISPONIBLE`** o **400**.

   La vendedora nunca cobra un precio distinto del que queda guardado.

2. **Todo o nada.** El cliente, el pedido, sus líneas, los extras colgados de cada pizza y el
   primer registro del historial se guardan en **una transacción**. Si algo falla, no queda
   nada a medias. Todas las consultas van **parametrizadas**.

3. **El estado inicial lo decide el servidor.** Un pedido con pizzas nace **pendiente**. Uno
   solo de bebidas nace **listo**, y cocina nunca lo ve (D-32).

4. **Cada cambio de estado tiene dueño:**

   | Desde | Hacia | Quién |
   |---|---|---|
   | pendiente | en preparación | cocina |
   | en preparación | listo | cocina |
   | listo | entregado | recepción |
   | pendiente o en preparación | cancelado, con motivo | recepción |

   - **Rol equivocado:** 403.
   - **Cambio que no está en la tabla:** 409 `TRANSICION_NO_PERMITIDA`.
   - **Dos personas tocan el mismo pedido a la vez:** gana la primera y la segunda recibe 409.
     El servidor lee el estado con `SELECT … FOR UPDATE`, que toma la fila hasta el `COMMIT`:
     la segunda espera, lee el estado que dejó la primera y recibe el 409.
   - Cada cambio suma una fila al historial con el usuario, su nombre y la hora.

   La app oculta los botones que no corresponden, pero **quien decide es el servidor**.

5. **La baja es lógica (D-33).** Un pedido cancelado no se borra: conserva sus líneas y su
   historial, con el motivo de la cancelación. No existe `DELETE` sobre pedidos.

6. **Para llevar o para comer aquí (D-34), y el cliente (D-31).**
   - **Para llevar:** se pregunta siempre, en su propia pantalla, y se guarda en
     `pedido.para_llevar`. El servidor lo exige: sin ese dato, 400.
   - **Nombre:** obligatorio, hasta 120 caracteres.
   - **Celular:** opcional, 8 dígitos que empiezan con 6 o 7. Si ya está registrado, se usa
     ese cliente. Si el pedido es para llevar, el campo sugiere dejarlo "para avisarle cuando
     esté listo".
   - **Quién ve el celular:** solo **recepción**. La respuesta a cocina no lo incluye.

7. **El canal en vivo, lo mínimo que exige el E2.**
   - **Socket.IO sobre el mismo servidor** de la API. Usa la ruta `/socket.io/`, que Caddy ya
     reenvía desde la tarjeta 02.
   - **Al conectar, se valida el token con el mismo verificador de la API.** Sin token válido
     no hay conexión. Cada pantalla entra a la sala de su rol.
   - **Los eventos salen después del `COMMIT`**, nunca antes: nadie se entera de un pedido que
     no llegó a guardarse.
     - `pedido:nuevo` va a cocina, si el pedido es para ella, y a recepción.
     - `pedido:estado` va a los dos roles.
   - **Si el canal falla, la pantalla recarga la lista**, siempre desde la API: el canal avisa,
     la API es la fuente. Lo demás es la tarjeta 07.

8. **Las pantallas siguen la línea que aprobó el autor.**
   - **Cocina:** una tarjeta grande por pedido, en orden de llegada. Cada una muestra el número,
     el nombre del cliente, **si es para llevar**, cuánto hace que llegó, las pizzas con sus
     mitades y extras, las bebidas aparte y la observación destacada, con **un solo botón**:
     *Empezar* o *Listo*.
   - **Recepción:** suma una sección *Pedidos* junto a *Nueva venta*. Cada pedido activo
     muestra su estado. Los listos ofrecen *Entregar* y, si hay celular, *Llamar*. Los que no
     están listos, *Cancelar*.
   - **Terminar venta:** muestra "Pedido #12 de Ana enviado a cocina" y deja lista una venta
     nueva. Si el envío falla, **la venta no se pierde**.

9. **Solo datos ficticios en las pruebas:** "Ana Prueba · 70000001", nunca un número real
   (observación 2.6 de la tutoría T2).

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — La base
- [x] `06_pedido_cliente_y_cancelacion.sql`:
  - `pedido.para_llevar`, obligatorio, y **todo pedido con cliente** (`cliente_id` obligatorio);
  - el formato del celular y **un celular por cliente**, con un índice único parcial;
  - `historial_estado.motivo`, **obligatorio si el estado es cancelado** y prohibido en los
    demás;
  - repetible.
- [x] Probada en una instalación nueva y sobre la base local, con casos válidos e imposibles.

### Fase B — Crear el pedido
- [x] `POST /api/v1/pedidos`: validación completa, precio del servidor, total comparado,
      transacción, estado inicial según lo pedido, 201 con el pedido.
- [x] Pruebas automáticas:
  - la tabla de la sección 6 del plan 05;
  - las entradas inválidas, cada una con su 400;
  - agotado, precio cambiado y los permisos;
  - que un fallo a mitad de la transacción no deje nada.
- [x] Sonda contra la base real (`pruebas/api/probar_pedidos.py`).

### Fase C — Leer, avanzar y cancelar
- [x] `GET /api/v1/pedidos` (activos, con filtro por uno o varios estados) y `GET
      /api/v1/pedidos/:id`, sin el celular para cocina.
- [x] `PATCH /api/v1/pedidos/:id/estado` y `POST /api/v1/pedidos/:id/cancelacion`.
- [x] Pruebas automáticas:
  - la matriz completa de estados por roles, con sus 403 y 409;
  - la carrera entre dos cambios simultáneos;
  - el historial.

### Fase D — El aviso en vivo
- [x] Socket.IO con el token en el saludo; salas por rol; eventos después del `COMMIT`.
- [x] Pruebas:
  - sin token, o con uno vencido, no hay conexión;
  - cocina recibe `pedido:nuevo`, y un pedido de solo bebidas no le llega;
  - un script propio mide **del `POST` al evento**, contra el entorno local.

### Fase E — La venta envía el pedido
- [x] Los pasos "¿Para llevar o para comer aquí?" y "¿A nombre de quién?", con los dos datos
      también en el resumen.
- [x] *Terminar venta* conectado: la confirmación, y los errores sin perder la venta.
- [x] Pruebas de *widgets*.
- [x] *(Pedido del autor al revisarla)* Los colores en **rojo ladrillo** en lugar del negro
      (D-29, segunda revisión), la **distribución para la computadora** y una **pantalla de
      acceso** con la foto de una pizza del local.

### Fase F — La cola de cocina
- [ ] La pantalla de cocina en vivo, con *Empezar* y *Listo*, en orden de llegada.
- [ ] Un aviso que **suena** cuando llega un pedido nuevo.
- [ ] Pruebas de *widgets*, y revisión del autor en el navegador.

### Fase G — Los pedidos en recepción
- [ ] Los activos en vivo, con *Entregar*, *Cancelar* con motivo y *Llamar*.
- [ ] Cuando un pedido queda listo: un aviso que **suena** en la computadora, el aviso a la
      vista y el título de la pestaña ("(1) Pedido listo"), pedido por el autor. El sonido se
      habilita con un toque por jornada: el navegador no deja sonar una página que nadie tocó.
- [ ] Pruebas de *widgets*, y revisión del autor en el navegador.

### Fase H — En producción
- [ ] La migración `06` en la base de producción, con respaldo previo.
- [ ] La API reconstruida y la app publicada.
- [ ] Las sondas y la medición del aviso, contra la dirección pública.

### Fase I — La prueba del autor
- [ ] Recepción en el celular y cocina en la computadora, con cuentas distintas:
  - una venta completa hasta entregarla;
  - otra venta cancelada;
  - una de solo bebidas;
  - cocina ve cada pedido nuevo en menos de 2 s.

---

## 5. Archivos que se tocan / crean

- **Base:** `docker/postgres/init/06_pedido_cliente_y_cancelacion.sql` *(nuevo)*.
- **API:**
  - `backend/src/rutas/pedidos.js` *(nuevo)*;
  - `backend/src/precio.js` *(nuevo: la regla de D-27 en el servidor)*;
  - `backend/src/tiempo-real.js` *(nuevo: Socket.IO)*;
  - `backend/src/app.js`, `backend/src/index.js` y `backend/package.json` *(socket.io)*.
- **Pruebas de la API:** `backend/test/pedidos.test.js`, `backend/test/tiempo-real.test.js`,
  `pruebas/api/probar_pedidos.py` y un script que mide el aviso.
- **App:**
  - `frontend/lib/`: el paso del cliente, el envío, la cocina, los pedidos de recepción y el
    canal en vivo;
  - `frontend/test/`;
  - `frontend/pubspec.yaml` *(el cliente de Socket.IO)*;
  - `frontend/web_dev_config.yaml` *(el proxy de desarrollo también reenvía `/socket.io/`)*.
- **Documentación:** `README.md` *(la migración y las sondas)* y `docs/BRIEF.md`, que suma el
  cliente con celular.

---

## 6. Cómo se prueba

**El precio.** La tabla de la sección 6 del plan 05, ahora en el servidor, con los mismos
totales que la app.

**Lo que el servidor rechaza:**

| Envío | Respuesta |
|---|---|
| Sin líneas | 400 |
| Cantidad 0, negativa, decimal o mayor de 999, el tope de la app y de la base | 400 |
| Mitades del mismo sabor, o la otra mitad no es una pizza | 400 |
| Un extra sin pizza, o algo que no es un extra puesto como extra | 400 |
| Sin decir si es para llevar | 400 |
| Nombre vacío o de más de 120 caracteres | 400 |
| Celular que no son 8 dígitos o no empieza con 6 o 7 | 400 |
| Observación de más de 240 caracteres | 400 |
| Un producto agotado | 409 `PRODUCTO_NO_DISPONIBLE` |
| El total no coincide con el del servidor | 409 `PRECIO_CAMBIADO`, con el total correcto |
| Cocina intenta crear un pedido | 403 |

**Los estados:** la matriz entera, cada estado de origen por cada destino y cada rol, con su
200, 403 o 409.

**En vivo:**
- sin token, no hay conexión;
- cocina recibe el pedido nuevo;
- un pedido de solo bebidas no le llega a cocina;
- el tiempo **del `POST` al evento**, medido en local y en producción. Tiene que quedar bajo
  2 segundos.

**En el navegador, con dos cuentas a la vez:**
- recepción vende; cocina ve el pedido, lo empieza y lo marca listo;
- recepción lo entrega;
- otra venta, cancelada con motivo;
- una de solo bebidas, que cocina no ve.

---

## 7. Criterios de aceptación

- La venta se guarda con el precio del servidor, que coincide con el que vio la vendedora.
- Cocina ve el pedido nuevo **en menos de 2 segundos**, sin recargar, en orden de llegada.
- Cada cambio de estado lo hace solo su rol, y el servidor lo exige aunque la app se
  saltee. Una transición inválida da 409, y un rol equivocado, 403.
- Cancelar exige un motivo y solo se puede antes de "listo". El pedido cancelado no se borra.
- Cada cambio queda en el historial con usuario y hora.
- Un pedido de solo bebidas nace listo y cocina no lo ve.
- Todo pedido dice si es para llevar, y cocina lo ve.
- El nombre es obligatorio; el celular, opcional y con formato válido, y solo lo ve
  recepción.
- Un fallo a mitad de camino no deja un pedido a medias.
- Todo funciona en la dirección pública, con dos dispositivos.

---

## 8. Requisitos que cubre

- **Del sistema:**
  - **RF-02** (registrar pedido), completo;
  - **RF-05** (marcar entregado);
  - **RF-06** (ver los pedidos entrantes en vivo);
  - **RF-07** (actualizar estado, cocina);
  - **RF-09** (cancelar);
  - **RF-11** (observación);
  - **RF-03** y **RF-04** (el estado en vivo y el aviso de listo en recepción), en su
    versión mínima. La robustez del canal es la tarjeta 07.
- **Institucionales:**
  - **#2** (control de acceso por rol en cada operación);
  - **#3** (persistencia con CRUD: el de pedidos, completo);
  - **#8** (validación en cliente y servidor).
- **De la entrega:** el **CRUD completo** del E2 y el recorrido *"login → recepción registra
  pedido → cocina lo ve en menos de 2 s"* en la URL pública.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — La base | ✅ Verificada | 2026-09-24 | **Instalación nueva** en un PostgreSQL 17 descartable, con la carpeta de scripts montada como en producción: corren `00`, `01`, `02`, `04`, `05` y `06` en orden y sin errores; quedan **5 tablas** y los 22 productos. **Repetible:** una segunda ejecución de la `06` termina con código 0. **Cómo quedó:** `pedido.para_llevar` y `pedido.cliente_id` obligatorios y sin valor por defecto; `historial_estado.motivo` opcional; las restricciones `cliente_celular_valido`, `historial_estado_motivo_solo_al_cancelar` y `historial_estado_motivo_no_vacio`, y el índice único parcial `cliente_celular_unico`. **Casos, uno por uno:** se aceptan los **6 válidos** (pedido para comer aquí, cliente sin celular, dos clientes sin celular, celular que empieza con 6, cambio de estado sin motivo, cancelación con motivo) y se **rechazan los 12 imposibles**, cada uno por su causa: pedido que no dice si es para llevar, pedido sin cliente, celular de 7 y de 9 dígitos, que empieza con 5, con espacios y con prefijo de país, dos clientes con el mismo celular, cancelación sin motivo, motivo en un cambio que no es cancelación, motivo en blanco y motivo de más de 120 caracteres. **El celular identifica al cliente:** insertar el mismo número con `ON CONFLICT` devuelve el mismo cliente, con el nombre actualizado, y sigue habiendo uno solo. **Sobre una base que ya tiene pedidos:** un pedido anterior queda como "para comer aquí"; y si hubiera un pedido sin cliente, la migración se detiene **sin cambiar nada** (ni siquiera agrega la columna), porque corre en una transacción. **Base local:** migración aplicada, los 19 casos en verde otra vez y la API sana. **Lo que salió:** el README solo listaba hasta la `05` en el paso de actualizar; ahora incluye la `06` y se detiene en la primera que falle |
| B — Crear el pedido | ✅ Verificada | 2026-09-24 | **La regla, aparte de la ruta:** `src/precio.js` valida la forma de la venta y calcula el precio en **centavos enteros**, sin base ni HTTP. **`npm test`: 109 de 109** (42 anteriores y **67 nuevas**). **La regla (50 casos):** la tabla completa de la sección 6 del plan 05 con los precios reales (Salame con Peperoni **Bs 47,50**, Carnívora con Criolla española **Bs 62,50**, 3 Choclo con extra **Bs 150**, solo 2 gaseosas **Bs 36**); A/B igual a B/A; la media mitad de centavo redondea hacia arriba, como la app; los extras llevan la cantidad de su pizza; con pizzas nace *pendiente* y solo bebidas nace *listo* (D-32); y **36 rechazos**, cada uno con su mensaje: 8 que dependen de la carta (otra mitad que no es pizza, extra vendido solo, bebida con extras o con mitad, algo que no es extra puesto como extra, producto inexistente, pizza o mitad agotadas) y 28 de forma (sin líneas, más de 100, sin decir si es para llevar, sin nombre, nombre de 121, celular de 7 dígitos, que empieza con 5, con espacios, con prefijo de país o como número, observación de 241, cantidades 0, negativa, decimal, 1000 o como texto, mitades del mismo sabor, extra repetido, sin el total mostrado, total negativo o con tres decimales…). **La ruta (17 casos), con una base simulada que entiende la transacción:** sin token 401 y cocina 403 **sin pedir ni una conexión**; una venta mal armada, 400 sin tocar la base; la venta válida, **201** con el pedido, la cabecera `Location` y el extra dentro de su pizza; **una sola transacción en orden** (`BEGIN`, productos con `FOR SHARE`, escrituras, `COMMIT`) y la conexión devuelta; **todo como parámetro**: ni el nombre, ni el celular, ni la observación aparecen en el texto SQL; el cliente con celular se busca por su número; total distinto, **409 `PRECIO_CAMBIADO`** con el total correcto y sin ninguna escritura; producto agotado, **409 `PRODUCTO_NO_DISPONIBLE`** con cuál es; **la base falla a mitad de la transacción: `ROLLBACK`, 500 sin detalles y nada más se escribe**; si también falla el `ROLLBACK`, la conexión se descarta; la base caída al conectar, **503**. **Contra la base real** (`probar_pedidos.py`, tokens reales): **23 de 23**. La tabla completa quedó guardada con sus totales exactos, solo bebidas nació *listo*, la venta mixta de Bs 189 devuelve sus tres líneas con el extra adentro, sin celular y para comer aquí también, y los 7 rechazos salen con su código. **En la base:** un solo cliente con el celular 70000001 aunque se usó en 9 ventas; los 9 pedidos con su registro inicial en el historial; ningún pedido cuyo total difiera de la suma de sus líneas; los 3 extras colgados de su pizza con su misma cantidad. **Agotado de verdad:** con la Napolitana marcada no disponible en la base, la venta responde 409 con su nombre; después se volvió a dejar disponible. **Lo que salió:** los mensajes de la API van sin tildes, por convención del código, y la app los va a mostrar; por eso el error de agotado lleva además el producto, para que la app arme su propio mensaje |
| C — Leer, avanzar y cancelar | ✅ Verificada | 2026-09-24 | **Las rutas:** `GET /pedidos` (sin filtro, los activos; con `?estado=` uno o varios, separados por coma), `GET /pedidos/:id` con su historial, `PATCH /pedidos/:id/estado` y `POST /pedidos/:id/cancelacion`. **Quién hace cada cambio** vive en una tabla (`src/pedidos/estados.js`), y el rol se comprueba **antes** de pedir una conexión. **El bloqueo:** el estado se lee con `SELECT … FOR UPDATE` y el cambio y su fila del historial se guardan en la misma transacción. **`npm test`: 178 de 178** (109 anteriores y **69 nuevas**). **La matriz completa, generada y no escrita a mano:** los 5 estados de origen por los 3 destinos del `PATCH` por los 2 roles, 30 casos: el rol que no es dueño recibe 403 sin tocar la base; el dueño, 200 con su fila en el historial, o **409 `TRANSICION_NO_PERMITIDA`** con el estado actual, `ROLLBACK` y el pedido intacto. **La cancelación desde los 5 estados:** recepción, 200 con el motivo recortado en el historial desde *pendiente* y *en preparación*, y 409 desde los otros tres; cocina, siempre 403 sin tocar la base. **Lo que se rechaza sin tocar la base:** 5 filtros inválidos de la cola (un estado que no existe, uno vacío, el parámetro repetido, otro parámetro y un intento de inyección), 6 números de pedido inválidos (`abc`, `0`, `-1`, `1.5`, `1e3` y uno que no cabe en la columna), 4 motivos inválidos y 5 cuerpos del `PATCH` (entre ellos *cancelado*, que tiene su propia ruta con motivo, y `constructor`, un nombre que un objeto de JavaScript hereda). Cocina recibe la cola **sin el celular** de nadie. **Contra la base real** (`probar_pedidos.py`, tokens reales): **45 de 45**. El ciclo completo, pendiente → en preparación → listo → entregado, con el historial diciendo qué rol hizo cada paso; lo que cada rol no puede hacer (403) y los saltos imposibles (409), entre ellos **entregar lo que no está listo (D-08)**; la cancelación con motivo, y el pedido cancelado se sigue leyendo; **la carrera real: dos "listo" lanzados a la vez sobre el mismo pedido, uno pasa y el otro recibe 409, y el historial registra un solo "listo"**; la cola de cocina en orden de llegada, sin celulares y sin los pedidos listos. **La prueba se limpia sola:** al final cancela o entrega los pedidos que creó, y ninguno queda activo. Así se puede correr contra producción sin dejar pedidos de prueba en la cola de cocina |
| D — El aviso en vivo | ✅ Verificada | 2026-09-24 | **El canal:** Socket.IO 4.8.3 en el mismo proceso y el mismo puerto que la API, por `/socket.io/`, que Caddy ya reenvía. El token viaja en el saludo, no en la dirección, y se valida con **el mismo verificador que la API**, que se separó del *middleware* para que un token valga en los dos o en ninguno. Cada conexión entra a la sala de su rol. **Los avisos:** `pedido:nuevo` a recepción completo y a cocina **sin el celular**, y a cocina solo si tiene algo que preparar; `pedido:estado` a los dos roles, con el pedido, el estado anterior, el nuevo y la hora. Salen **después del `COMMIT`**, y si el canal fallara, la operación ya quedó guardada y respondida. **`npm test`: 199 de 199** (178 anteriores y **21 nuevas**). **Con el cliente real de Socket.IO (13):** el canal rechaza, cada una con su código, la conexión sin token, con un token inventado, firmado por una clave ajena, de otra aplicación, vencido y sin los roles del sistema; recepción y cocina entran; cocina recibe el pedido sin el celular y recepción completo; un pedido de solo bebidas le llega a recepción y no a cocina; un cambio de estado les llega a los dos. **El orden (8):** el aviso del pedido nuevo sale una vez y después del `COMMIT`; una venta mal armada, un precio que cambió o un fallo a mitad de la transacción no avisan nada; un cambio de estado y una cancelación avisan después del `COMMIT` con desde y hacia; un cambio rechazado (409 o 403) no avisa; y si el canal falla, el pedido igual queda guardado y respondido. **Contra la API real, con tokens reales** (`pruebas/tiempo-real/medir_aviso.py`, 20 pedidos por *websocket*): **del envío de la venta al aviso en cocina, mediana 22 ms y peor caso 78 ms; del cambio de estado al aviso en recepción, mediana 17 ms y peor caso 30 ms**. La medición cancela los pedidos que crea. **Lo que salió (E-011):** la primera prueba contra la API en Docker encontró que **el proceso se caía** al recibir `/socket.io/`. Express y Socket.IO respondían la misma petición, porque Express se había agregado al servidor después de conectar el canal, y Socket.IO solo toma `/socket.io/` para los manejadores que ya existen. Docker lo reiniciaba y el chequeo de salud seguía en verde, así que el fallo pasaba inadvertido. Las pruebas no lo vieron porque montaban el canal sin Express. Se corrigió armando el servidor en un solo lugar (`src/servidor.js`), que usan el arranque y las pruebas, y dos pruebas nuevas lo cubren; después, cero reinicios |
| E — La venta envía el pedido | ✅ Verificada · **aprobada por el autor** | 2026-09-24 | **Dos pasos nuevos**, después de la observación: "¿Para llevar o para comer aquí?" y "¿A nombre de quién?", con el nombre obligatorio y el celular opcional (solo números, hasta 8, y si es para llevar sugiere pedirlo). La lógica valida lo mismo que el servidor y la base. Si se vuelve del resumen a cambiar algo, ya no se pregunta de nuevo quién es. **El envío:** la venta arma el cuerpo de `POST /api/v1/pedidos` con el total mostrado en bolivianos; el cliente de la API suma `POST` y `PATCH` con la misma renovación del token ante un 401, y el error trae los datos extra del servidor (el total correcto, el producto agotado). *Terminar venta* dice "Enviando a cocina…" y no deja tocar dos veces; al guardar muestra el **número que asignó el servidor**, el cliente y el total, y *Nueva venta* empieza otra; un pedido de solo bebidas dice "listo para entregar". **Si no se guardó, la venta no se pierde**, y el mensaje dice qué hacer: agotado (con el nombre), sin conexión (y se reintenta) o precio cambiado (con el total correcto). **`flutter test`: 130 de 130** (106 anteriores y **24 nuevas**): 9 de la lógica (el orden de los pasos, nombre obligatorio, celular boliviano, 120 caracteres, volver, cambiar el cliente y la observación desde el resumen, y el cuerpo exacto del pedido con mitades, extras, bebidas y el total al centavo); 3 del cliente de la API; 10 de la pantalla (el envío completo con su confirmación, "Enviando" sin doble envío, solo bebidas, agotado, sin conexión con reintento, precio cambiado, la validación del cliente, el resumen con el cliente y *Cambiar*, y la distribución en pantalla ancha); y 2 de contraste. **Revisión con el autor:** pidió (a) **quitar el negro**, que desentonaba desde el acceso hasta la venta: entre tres paletas eligió **rojo ladrillo** `#C0392B` con amarillo suave en los precios; el negro y los colores puros quedan solo en el logo, y las pruebas WCAG se rehicieron (blanco sobre el rojo 5,4 a 1, rojo sobre el crema 5,0 a 1, precios más de 7 a 1); (b) **mejorar la vista en la computadora**, que se veía desordenada: la pregunta arriba en una franja angosta, un vacío debajo y la venta pegada al borde. Ahora va todo en un contenedor centrado de hasta 1280 px, la pregunta centrada en la altura, la venta en una tarjeta al lado y las opciones grandes en fila, como fichas; el celular no cambia; (c) **una pantalla de acceso más atractiva**: la foto de La Malcriada con el nombre del local y sus tres sucursales, y al lado el acceso con qué hace el sistema; en el celular, la foto como portada. Todo lo que dice del local sale de sus datos registrados. **Para revisar el diseño sin iniciar sesión** se armó una entrada aparte, fuera del repositorio, con la carta real; así se miraron la computadora, el celular y el acceso antes de mostrárselos al autor |
| F — La cola de cocina | ⏳ Pendiente | — | — |
| G — Los pedidos en recepción | ⏳ Pendiente | — | — |
| H — En producción | ⏳ Pendiente | — | — |
| I — La prueba del autor | ⏳ Pendiente | — | — |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-24 | Versión inicial propuesta | La última tarjeta antes del E2. Incorpora las decisiones del autor sobre el cliente (D-31), los pedidos de solo bebidas (D-32) y la cancelación (D-33), y el canal en vivo mínimo que el E2 exige (D-21) |
| 2026-09-24 | **Aprobado**, sumando "para llevar o comer aquí" (D-34) | El autor aprobó el plan con la recomendación: cocina ve si va en caja o en plato. No toca el E1: es un dato más del pedido, dentro de RF-02 |
| 2026-09-24 | **Revisión de la fase E con el autor** | Los colores pasan a rojo ladrillo (D-29, segunda revisión); la venta se distribuye mejor en la computadora; la pantalla de acceso lleva una foto del local. Se suma un **aviso que suena**: en recepción cuando un pedido queda listo, y en cocina cuando llega uno nuevo |

---

## 11. Cierre

- **Commits que cierran la tarjeta:** —
- **Fecha de cierre:** —
