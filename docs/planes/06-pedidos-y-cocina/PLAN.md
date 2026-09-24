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
     El `UPDATE` solo cambia la fila si todavía está en el estado esperado.
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
- [ ] `06_pedido_cliente_y_cancelacion.sql`:
  - `pedido.para_llevar`, obligatorio, y **todo pedido con cliente** (`cliente_id` obligatorio);
  - el formato del celular y **un celular por cliente**, con un índice único parcial;
  - `historial_estado.motivo`, **obligatorio si el estado es cancelado** y prohibido en los
    demás;
  - repetible.
- [ ] Probada en una instalación nueva y sobre la base local, con casos válidos e imposibles.

### Fase B — Crear el pedido
- [ ] `POST /api/v1/pedidos`: validación completa, precio del servidor, total comparado,
      transacción, estado inicial según lo pedido, 201 con el pedido.
- [ ] Pruebas automáticas:
  - la tabla de la sección 6 del plan 05;
  - las entradas inválidas, cada una con su 400;
  - agotado, precio cambiado y los permisos;
  - que un fallo a mitad de la transacción no deje nada.
- [ ] Sonda contra la base real (`pruebas/api/probar_pedidos.py`).

### Fase C — Leer, avanzar y cancelar
- [ ] `GET /api/v1/pedidos` (activos, con filtro por uno o varios estados) y `GET
      /api/v1/pedidos/:id`, sin el celular para cocina.
- [ ] `PATCH /api/v1/pedidos/:id/estado` y `POST /api/v1/pedidos/:id/cancelacion`.
- [ ] Pruebas automáticas:
  - la matriz completa de estados por roles, con sus 403 y 409;
  - la carrera entre dos cambios simultáneos;
  - el historial.

### Fase D — El aviso en vivo
- [ ] Socket.IO con el token en el saludo; salas por rol; eventos después del `COMMIT`.
- [ ] Pruebas:
  - sin token, o con uno vencido, no hay conexión;
  - cocina recibe `pedido:nuevo`, y un pedido de solo bebidas no le llega;
  - un script propio mide **del `POST` al evento**, contra el entorno local.

### Fase E — La venta envía el pedido
- [ ] Los pasos "¿Para llevar o para comer aquí?" y "¿A nombre de quién?", con los dos datos
      también en el resumen.
- [ ] *Terminar venta* conectado: la confirmación, y los errores sin perder la venta.
- [ ] Pruebas de *widgets*.

### Fase F — La cola de cocina
- [ ] La pantalla de cocina en vivo, con *Empezar* y *Listo*, en orden de llegada.
- [ ] Pruebas de *widgets*, y revisión del autor en el navegador.

### Fase G — Los pedidos en recepción
- [ ] Los activos en vivo, con *Entregar*, *Cancelar* con motivo y *Llamar*.
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
| A — La base | ⏳ Pendiente | — | — |
| B — Crear el pedido | ⏳ Pendiente | — | — |
| C — Leer, avanzar y cancelar | ⏳ Pendiente | — | — |
| D — El aviso en vivo | ⏳ Pendiente | — | — |
| E — La venta envía el pedido | ⏳ Pendiente | — | — |
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

---

## 11. Cierre

- **Commits que cierran la tarjeta:** —
- **Fecha de cierre:** —
