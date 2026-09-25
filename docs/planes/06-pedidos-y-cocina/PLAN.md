# Plan 06 — Pedidos y cola de cocina

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 06 — Pedidos y cola de cocina
- **Incremento:** pedidos sobre la URL pública
- **Estado:** 🔵 **En curso — aprobado** el 2026-09-24, con "para llevar o comer aquí" (D-34);
  **revisado el mismo día** con la observación de la tutoría: la venta en una sola pantalla,
  agregar a un pedido ya enviado y la venta directa de bebidas (D-36, D-37 y D-38)
- **Entrada al tablero:** 2026-09-24
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Cerrar el recorrido que el E2 pide ver funcionando **en la dirección pública**:

1. Recepción arma la venta **en una sola pantalla** y la confirma, y **el pedido queda
   guardado** con el precio que calcula el servidor.
2. **Cocina lo ve en menos de 2 segundos**, sin recargar, en orden de llegada.
3. Cocina lo **empieza** y lo marca **listo**.
4. Recepción lo **entrega**, o lo **cancela** mientras está pendiente, con un motivo (D-41).

Con eso, el pedido tiene su **CRUD completo**: se crea, se lee, se actualiza su estado y se
da de baja. Cada cambio queda registrado con quién lo hizo y cuándo.

---

## 2. Alcance

**Incluye:**

- **La venta en una sola pantalla (D-36)**, en el orden en que se dicta en el mostrador: el
  cliente (nombre obligatorio y celular opcional, D-31), si es para llevar o para comer aquí
  (D-34), las pizzas, las bebidas, la observación y *Confirmar venta*. Cada pizza se arma en
  un modal.
- **La venta directa de bebidas (D-38):** la soda suelta, sin nombre ni preguntas. Nace
  entregada y no pasa por cocina.
- **Agregar productos a un pedido ya enviado (D-37)**, mientras no se haya entregado, con
  reglas según su estado.
- **El número del día (D-35):** "Pedido 12", el que se canta en el mostrador.
- **`POST /api/v1/pedidos`:** valida todo de nuevo, calcula el precio con la regla de D-27 y
  guarda el pedido **en una sola transacción**.
- **`GET /api/v1/pedidos`** (los activos, con filtro por estado) y **`GET
  /api/v1/pedidos/:id`** (con sus líneas y su historial).
- **`PATCH /api/v1/pedidos/:id/estado`:** los cambios de estado, cada uno solo para el rol
  que le corresponde.
- **`POST /api/v1/pedidos/:id/cancelacion`:** la baja, con motivo (D-33, adelantada de la
  tarjeta 08).
- **Un canal en vivo mínimo con Socket.IO (D-21):** los eventos `pedido:nuevo`,
  `pedido:estado` y `pedido:actualizado`, con el mismo token que la API.
- **La pantalla de cocina:** la cola en vivo, con *Empezar* y *Listo*.
- **Los pedidos en recepción:** los activos en vivo, con *Entregar*, *Cancelar*, *Llamar* y
  *Agregar*.
- **Dos migraciones:**
  - la `06`: el dato de si el pedido es para llevar, el formato del celular, un celular por
    cliente y el motivo de la cancelación;
  - la `07`: el número del día, la venta directa y las líneas que se agregan después;
  - la `08`: las pizzas que se venden solo enteras (D-39), sumada al revisar la fase I.

**No incluye:**

- **Lo que hace robusto al canal en vivo (tarjeta 07):**
  - reconectar solo y avisar cuando el canal se cae (RNF-05);
  - renovar el token de una conexión abierta;
  - el evento `producto:disponibilidad`.
- **Marcar un producto agotado:** tarjeta 08.
- **Quitar o cambiar algo de un pedido ya enviado:** solo se puede **agregar** (D-37). Si el
  cliente cambia de idea mientras el pedido está pendiente, se cancela y se hace de nuevo;
  cuando cocina ya lo empezó, no se cancela (D-41). Así la cocina nunca prepara algo que
  cambió sin avisar.
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

3. **El estado inicial lo decide el servidor.** Un pedido lleva al menos una pizza y nace
   **pendiente**. Las bebidas solas son una **venta directa**: nace **entregada** y cocina
   nunca la ve (D-38). Reemplaza a D-32, donde un pedido de solo bebidas nacía listo. Un
   pedido con nombre y sin pizzas se rechaza con 400.

4. **Cada cambio de estado tiene dueño:**

   | Desde | Hacia | Quién |
   |---|---|---|
   | pendiente | en preparación | cocina |
   | en preparación | listo | cocina |
   | listo | entregado | recepción |
   | pendiente | cancelado, con motivo | recepción |

   *(Revisado el 25-sep, D-41: hasta entonces también se cancelaba en preparación.)*

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
   - **Para llevar:** se pregunta siempre, sin una opción marcada de entrada, y se guarda en
     `pedido.para_llevar`. El servidor lo exige: sin ese dato, 400.
   - **Nombre:** obligatorio, hasta 120 caracteres.
   - **Celular:** opcional, 8 dígitos que empiezan con 6 o 7. Si ya está registrado, se usa
     ese cliente. Si el pedido es para llevar, el campo sugiere dejarlo "para avisarle cuando
     esté listo".
   - **Quién ve el celular:** solo **recepción**. La respuesta a cocina no lo incluye.
   - **La venta directa no lleva cliente**, ni dice si es para llevar (D-38): la soda se
     entrega en el momento y no hay a quién llamar.

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
   - **La venta, en una sola pantalla y en F (D-36).** Arriba, el cliente y "comer aquí o
     para llevar". Debajo, las pizzas, las bebidas y la observación. A la derecha, el pedido
     con el total y *Confirmar venta*; en el celular, una barra fija abajo. *Agregar pizza*
     abre un modal con un solo scroll: entera o mitad y mitad, los sabores con su foto, los
     extras, la cantidad y el botón con el precio. Se mantiene lo que el autor aprobó: un solo
     precio a la vista, cada pizza confirmada con su precio y ninguna lista de combinaciones.
   - **Confirmar venta:** muestra "Pedido 12 de Ana enviado a cocina" y deja el formulario
     limpio para el siguiente cliente. Si el envío falla, **la venta no se pierde**.
   - **Vender bebidas:** un modal aparte, con las bebidas, el total y *Cobrar*.
   - **Recepción:** suma una sección *Pedidos* junto a *Nueva venta*. Cada pedido activo
     muestra su estado. Los listos van primero y ofrecen *Entregar* y, si hay celular,
     *Llamar*. Los pendientes, *Cancelar* (D-41). Los que no se entregaron, *Agregar*.

9. **Solo datos ficticios en las pruebas:** "Ana Prueba · 70000001", nunca un número real
   (observación 2.6 de la tutoría T2).

10. **El número del día (D-35).**
    - `pedido.numero_del_dia` empieza en 1 cada día y **no tiene huecos**. El día lo calcula la
      base desde la hora del pedido, en la hora de Bolivia (`America/La_Paz`).
    - Se asigna **dentro de la transacción que guarda el pedido**, después de un bloqueo de
      transacción (`pg_advisory_xact_lock`) que pone en fila las ventas simultáneas: cada una
      toma el máximo del día más uno. Si la venta falla, el número no se gasta.
    - Una restricción única por día y número lo respalda en la base.
    - La venta directa no lleva número: nadie la canta, y así cocina no ve saltos.

11. **Agregar a un pedido ya enviado (D-37).**

    | Estado del pedido | Bebidas | Pizzas |
    |---|---|---|
    | pendiente | sí | sí |
    | en preparación | sí | sí, y cocina recibe el aviso con sonido |
    | listo | sí | no: van en un pedido nuevo |
    | entregado o cancelado | no | no |

    - `POST /api/v1/pedidos/:id/lineas`, solo recepción. El mismo precio del servidor, el mismo
      total comparado y **el mismo bloqueo** (`FOR UPDATE`) que los cambios de estado: si
      cocina marca *Listo* justo cuando recepción agrega una pizza, gana el primero y el
      segundo recibe 409.
    - Cada línea agregada guarda **cuándo y quién** la agregó, para que cocina la vea marcada.
    - **Nadie avanza un pedido sin haber visto lo último.** Las líneas solo se agregan, nunca
      se quitan, así que su cantidad sirve de **versión** del pedido. *Empezar*, *Listo* y
      *Entregar* mandan la versión que se vio; si después se agregó algo, **409
      `PEDIDO_CAMBIADO`** y la pantalla se pone al día.
    - El aviso `pedido:actualizado` va a recepción y, si el pedido está en su cola, a cocina.

12. **La venta directa de bebidas (D-38).**
    - `POST /api/v1/pedidos` con `ventaDirecta: true` y **solo bebidas**. No lleva cliente, ni
      "para llevar", ni observación, ni número del día.
    - Nace **entregada**, con su fila en el historial: queda quién la vendió y cuándo.
    - No se avisa por el canal: no entra en ninguna lista activa.
    - **La base rechaza cualquier mezcla:** un pedido tiene cliente, "para llevar" y número; una
      venta directa no tiene ninguno de los tres, no lleva observación y está entregada.

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
- [x] La pantalla de cocina en vivo, con *Empezar* y *Listo*, en orden de llegada.
- [x] Un aviso que **suena** cuando llega un pedido nuevo.
- [x] Pruebas de *widgets*, y revisión del autor en el navegador.

### Fase G — El número del día, agregar y la venta directa, en la API
- [x] `07_numero_agregados_y_venta_directa.sql`:
  - `pedido.dia`, calculado por la base, y `pedido.numero_del_dia`, único por día (D-35);
  - la venta directa: sin cliente, sin "para llevar", sin número, sin observación y siempre
    entregada; la base rechaza cualquier mezcla (D-38);
  - cuándo y quién agregó cada línea que llega después de enviar el pedido (D-37);
  - repetible, y probada en una instalación nueva y sobre la base local.
- [x] `POST /api/v1/pedidos`: el número del día en la misma transacción; un pedido sin pizzas
      se rechaza; la venta directa nace entregada.
- [x] `POST /api/v1/pedidos/:id/lineas`: agregar, con las reglas de la decisión 11, y el aviso
      `pedido:actualizado`.
- [x] La versión del pedido: un cambio de estado con una versión vieja da 409
      `PEDIDO_CAMBIADO`.
- [x] Pruebas automáticas y la sonda contra la base real, con **dos carreras nuevas**: muchas
      ventas a la vez no repiten ni saltan números, y *Listo* contra *Agregar*.

### Fase H — La venta en una sola pantalla
- [x] El formulario en F, con el pedido y el total a la derecha; en el celular, una barra fija
      abajo.
- [x] El modal de cada pizza, con un scroll: entera o mitad y mitad, sabores, extras y
      cantidad. Tocar una pizza ya agregada la abre para corregirla.
- [x] *Vender bebidas*: el modal de la venta directa.
- [x] *Confirmar venta*: "Pedido 12 enviado a cocina" y el formulario limpio; si falla, la venta
      no se pierde.
- [x] Pruebas de la lógica y de *widgets*, y revisión del autor en el navegador.

### Fase I — Los pedidos en recepción
- [x] La sección *Pedidos*: los activos en vivo, los listos primero, con *Entregar*, *Cancelar*
      con motivo, *Llamar* y *Agregar*.
- [x] Cuando un pedido queda listo: un aviso que **suena** en la computadora, el aviso a la
      vista y el título de la pestaña ("(1) Pedido listo"), pedido por el autor. El sonido se
      habilita con un toque por jornada: el navegador no deja sonar una página que nadie tocó.
- [x] Cocina: el número del día, y lo agregado, marcado y con sonido.
- [x] Pruebas de *widgets*, y revisión del autor en el navegador.
- [x] *(Pedido del autor al revisarla)* El sonido **viene activado**: se enciende solo con el
      primer toque en la pantalla, sin buscar el botón. Y **Dos estaciones, Tres estaciones y
      Criolla española se venden solo enteras** (D-39): la migración `08`, el servidor que lo
      exige y la venta que no las ofrece como mitad.

### Fase J — En producción
- [x] Las migraciones `06`, `07` y `08` en la base de producción, con respaldo previo.
- [x] La API reconstruida y la app publicada.
- [x] Las sondas y la medición del aviso, contra la dirección pública.

### Fase K — La prueba del autor
- [x] Recepción en el celular y cocina en la computadora, con cuentas distintas:
  - una venta completa hasta entregarla;
  - una pizza agregada mientras cocina prepara el pedido;
  - otra venta cancelada;
  - una venta directa de bebidas;
  - cocina ve cada pedido nuevo en menos de 2 s.
- [x] *(Pedido del autor al probarla)* Un pedido que cocina ya empezó **no se cancela**
      (D-41): el servidor lo rechaza, la app solo ofrece *Cancelar* en el pendiente, y las
      pruebas contra la API real cierran lo que queda en preparación terminándolo y
      entregándolo. Se vuelve a publicar en producción.

---

## 5. Archivos que se tocan / crean

- **Base:** `docker/postgres/init/06_pedido_cliente_y_cancelacion.sql`,
  `docker/postgres/init/07_numero_agregados_y_venta_directa.sql` y
  `docker/postgres/init/08_pizzas_solo_enteras.sql` *(nuevos)*.
- **API:**
  - `backend/src/rutas/pedidos.js` *(nuevo)*;
  - `backend/src/pedidos/`: crear, leer, cambiar de estado y **agregar** *(nuevos)*;
  - `backend/src/precio.js` *(nuevo: la regla de D-27 en el servidor)*;
  - `backend/src/tiempo-real.js` *(nuevo: Socket.IO)*;
  - `backend/src/app.js`, `backend/src/index.js` y `backend/package.json` *(socket.io)*.
- **Pruebas de la API:** `backend/test/pedidos.test.js`, `backend/test/tiempo-real.test.js`,
  `pruebas/api/probar_pedidos.py` y un script que mide el aviso.
- **App:**
  - `frontend/lib/`: la venta en una pantalla con sus modales, el envío, la cocina, los pedidos
    de recepción y el canal en vivo;
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
| Un pedido con nombre y sin pizzas | 400 |
| Una venta directa con cliente, "para llevar", observación o algo que no es una bebida | 400 |
| Una mitad de Dos estaciones, Tres estaciones o Criolla española (D-39) | 400 |
| Agregar a un pedido entregado o cancelado, o una pizza a uno listo | 409 `AGREGADO_NO_PERMITIDO` |
| Cancelar un pedido que cocina ya empezó (D-41) | 409 `TRANSICION_NO_PERMITIDA` |
| Cambiar el estado con una versión vieja del pedido | 409 `PEDIDO_CAMBIADO` |

**Las carreras, contra la base real:**
- dos cambios de estado a la vez sobre el mismo pedido: pasa uno;
- muchas ventas a la vez: los números del día salen seguidos, sin repetir ni saltar;
- *Listo* y *Agregar una pizza* a la vez: gana el primero y el otro recibe 409.

**Los estados:** la matriz entera, cada estado de origen por cada destino y cada rol, con su
200, 403 o 409.

**En vivo:**
- sin token, no hay conexión;
- cocina recibe el pedido nuevo;
- un pedido de solo bebidas no le llega a cocina;
- lo agregado a un pedido le llega a recepción, y a cocina si el pedido está en su cola;
- el tiempo **del `POST` al evento**, medido en local y en producción. Tiene que quedar bajo
  2 segundos.

**En el navegador, con dos cuentas a la vez:**
- recepción vende; cocina ve el pedido, lo empieza y lo marca listo;
- recepción lo entrega;
- una pizza agregada mientras cocina prepara el pedido, que cocina ve marcada;
- otra venta, cancelada con motivo;
- una venta directa de bebidas, que nadie más ve.

---

## 7. Criterios de aceptación

- La venta se guarda con el precio del servidor, que coincide con el que vio la vendedora.
- Cocina ve el pedido nuevo **en menos de 2 segundos**, sin recargar, en orden de llegada.
- Cada cambio de estado lo hace solo su rol, y el servidor lo exige aunque la app se
  saltee. Una transición inválida da 409, y un rol equivocado, 403.
- Cancelar exige un motivo y solo se puede mientras el pedido está pendiente (D-41). El
  pedido cancelado no se borra.
- Cada cambio queda en el historial con usuario y hora.
- La venta se arma y se confirma en una sola pantalla, y cada pizza en un modal.
- La venta directa de bebidas no pide nombre, nace entregada y nadie más la ve. Un pedido con
  nombre lleva al menos una pizza.
- Cada pedido lleva su número del día, sin huecos ni repetidos, aunque dos ventas lleguen a la
  vez.
- A un pedido que no se entregó se le puede agregar, con las reglas de su estado, y nadie lo
  avanza sin haber visto lo último que se le agregó.
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
  - **RF-14** (agregar productos a un pedido ya enviado, *Should*), **nuevo** (D-37): se suma
    a la lista de requisitos del documento;
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
| F — La cola de cocina | ✅ Verificada · **aprobada por el autor** ("cocina está trabajando correctamente") | 2026-09-24 | **La pantalla:** cada pedido es una tarjeta grande, en orden de llegada (de izquierda a derecha y de arriba abajo), en tantas columnas como quepan; dice el número, el cliente, si es para llevar, cuánto hace que llegó (se actualiza sola), las pizzas con sus mitades y extras, las bebidas aparte y la observación resaltada; un solo botón, *Empezar* y después *Listo*, y el pedido en preparación lleva borde rojo. Arriba, cuántos hay y si el canal está "En vivo". **En vivo:** el cliente de Socket.IO para Flutter (`socket_io_client` 3.1.6, fijado) entrega el token vigente **en cada conexión, también al reconectarse**. Un pedido nuevo aparece solo, al final, con la marca "Nuevo" un minuto y un **sonido de dos tonos** hecho con la Web Audio API, sin archivos; el sonido se habilita con un toque en "Activar sonido", porque el navegador no deja sonar una página que nadie tocó. Si otro dispositivo cambia un pedido, la tarjeta se actualiza; si recepción lo cancela, sale de la cola y cocina ve el aviso; **al reconectarse, la cola se vuelve a leer de la API**, porque el canal avisa y la API es la fuente. **`flutter test`: 149 de 149** (130 anteriores y **19 nuevas**): 17 de la cocina, con un canal y un timbre de prueba (los cuatro estados, lo que muestra cada tarjeta, el orden, columnas en la computadora y una en el celular a 320 px, *Empezar* y *Listo*, un solo cambio aunque se toque dos veces, el 409 que relee la cola, el pedido nuevo con su sonido y sin duplicados, el que nace listo no entra, el cambio desde otro dispositivo, la cancelación avisada, la relectura al reconectar y el botón de sonido), una de la barra a 600, 800 y 999 px, y una de los parámetros de consulta del cliente de la API. **Contra la API real**, con el cliente de Flutter fuera del navegador y tokens reales: el canal de la app recibe el pedido nuevo y su cambio de estado, el modelo los entiende, y **a cocina no le llega el celular**. **Lo que salió:** (1) a 800 px, una tableta, la barra no alcanzaba para el título, el sonido, el nombre y *Cerrar sesión*: el nombre se muestra desde 900 px y el sonido lleva texto desde 1000 px; (2) para revisarla en el navegador, el servidor de revisión reenvía también el WebSocket de `/socket.io/`, como Caddy, y el servidor de desarrollo de Flutter lo tiene declarado; (3) el autor preguntó cómo se numeran los pedidos y cómo sigue cocina el orden: la cola va por hora de llegada, y se decidió un **número del día** para el mostrador (D-35, fase G) |
| G — El número del día, agregar y la venta directa, en la API | ✅ Verificada | 2026-09-24 | **La migración `07`, en una instalación nueva** (PostgreSQL 17 descartable con la carpeta de scripts montada): corren `00` a `07` en orden y sin errores. **Repetible:** una segunda ejecución termina con código 0 y no renumera nada. **Casos, uno por uno: 24 de 24.** Se aceptan los **9 válidos**: un pedido con su número, dos del mismo día seguidos, la venta directa, dos ventas directas el mismo día (sin número no chocan), el mismo número en días distintos, una línea agregada con cuándo y quién, una línea original sin nada de eso, y **el día es el de Bolivia**: las 01:00 UTC del 25 cuentan como el 24 y las 04:00 UTC, como el 25. Se **rechazan los 15 imposibles**, cada uno por su restricción: un pedido con cliente y sin número, o sin "para llevar"; dos pedidos con el mismo número el mismo día; números 0 y negativo; una venta directa pendiente, lista, con observación, para llevar o con número; una venta directa que después se cancela; escribir el día a mano; y una línea agregada sin quién, con quién en blanco o con quién pero sin cuándo. **Sobre una base con pedidos:** cinco pedidos de dos días, con los ids cruzados respecto de la hora, quedan numerados 1, 2, 3 y 1, 2 **en orden de llegada**, y el de las 21:30 de Bolivia (01:30 UTC del día siguiente) queda en su día. **Base local:** aplicada; sus 54 pedidos anteriores quedaron numerados del 1 al 54, y los 24 casos, otra vez en verde. **La API.** El número del día se asigna después de un bloqueo de transacción (`pg_advisory_xact_lock`), y la hora del pedido se toma **después** del bloqueo, para que el orden de los números sea el de llegada. La venta directa (`ventaDirecta: true`) no toma el bloqueo ni crea cliente. `POST /pedidos/:id/lineas` toma la fila con `FOR UPDATE`, lee la carta con `FOR SHARE`, decide según el estado, compara el total y guarda las líneas con cuándo y quién, y suma al total. El cambio de estado acepta la `version` que se vio y la compara con la cantidad de líneas, **contada en una consulta aparte después de tomar la fila**: en READ COMMITTED, una misma consulta no vería lo que agregó quien tenía la fila hasta recién. **`npm test`: 259 de 259** (199 anteriores y **60 nuevas**): 16 de la regla (la venta directa nace entregada, un pedido sin pizzas se rechaza, una venta directa con pizza o con cliente, para llevar u observación se rechaza, lo agregado y su precio); 4 del alta (el orden bloqueo → número → pedido dentro de la transacción y en la hora de Bolivia, la venta directa sin cliente ni bloqueo, y sus dos rechazos), y se rehízo la de solo bebidas, que ahora da 400; **26 de agregar**, con la matriz generada de 5 estados por bebida y pizza, el orden de la transacción, cuándo y quién en cada línea, el extra colgado de la pizza agregada, el total, los 400, 404 y 409, el fallo a mitad de camino y el aviso después del `COMMIT`; 12 de la versión (vieja, igual, ausente, antes que la transición y 6 inválidas); y 2 del canal (lo agregado le llega a cocina sin el celular si el pedido está en su cola, y si está listo, solo a recepción), más la de solo bebidas rehecha: la venta directa no se avisa a nadie. **Contra la base real** (`probar_pedidos.py`, tokens reales): **71 de 71**. Los números salen seguidos en el orden de venta; la venta directa nace entregada, sin cliente ni número, con quien la vendió en el historial, y no aparece entre los activos; solo bebidas a nombre de un cliente, 400; agregar una soda a un pendiente (total 68, versión 2, marcada como agregada), una pizza mitad y mitad con extra a uno en preparación (123,50, versión 4), *Listo* con la versión vieja da 409 y con la actual pasa, una pizza a uno listo da 409 y una soda sí, nada a uno entregado. **Las dos carreras nuevas:** 12 ventas lanzadas a la vez se guardan todas, **con números seguidos, sin repetir ni saltar, y en el orden de llegada**; y en 8 rondas de *Listo* contra *Agregar una pizza* **siempre pasa uno solo**: ganaron las dos operaciones alguna vez (en una corrida, agregar 2 veces y listo 6), y el perdedor recibió siempre el 409 que le corresponde: `PEDIDO_CAMBIADO` si llegó tarde *Listo*, `AGREGADO_NO_PERMITIDO` si llegó tarde la pizza. **En la base,** después de todo: ningún pedido cuyo total difiera de la suma de sus líneas, 182 pedidos del día numerados del 1 al 182 sin huecos, y las ventas directas, todas entregadas. **El aviso en vivo**, medido otra vez: mediana 20 ms a cocina y 14 ms a recepción |
| H — La venta en una sola pantalla | ✅ Verificada · **aprobada por el autor** ("ahora sí está bien… aprobado") | 2026-09-24 | **La lógica, sin pantalla** (`lib/carta/venta.dart`, reescrita): `FormularioVenta` guarda el cliente, "para llevar" (sin opción marcada de entrada), las pizzas en líneas, las bebidas y la observación; junta la misma pizza en una línea aunque sus mitades vengan en otro orden, corrige una línea en su lugar, dice **qué falta para confirmar con las mismas reglas que el servidor** (nombre, celular boliviano, para llevar, al menos una pizza) y arma el cuerpo de `POST /api/v1/pedidos`. `ArmadoDePizza` es la pizza del modal: entera o mitad y mitad (el primer sabor tocado es la mitad 1 y el segundo la 2; tocar uno elegido lo quita; un tercero reemplaza a la segunda), extras, cantidad de 1 a 50 y un solo precio. `VentaDeBebidas` arma la venta directa (`ventaDirecta: true`, sin cliente). Se fueron el recorrido paso a paso de D-30 y sus pantallas (`pasos.dart`, `venta_guiada.dart`, `resumen_venta.dart`). **La pantalla:** en la computadora, el formulario **ocupa todo el alto sin desplazarse**: arriba "1 · Cliente" (nombre, celular y comer aquí o para llevar, con *Vender bebidas* en la misma línea, porque es la primera decisión del mostrador), en el medio las pizzas, que se estiran y tienen su propia lista si son muchas, con *Agregar otra pizza* siempre a la vista, y abajo las bebidas con − y +. A la derecha, el pedido: el nombre con el celular al lado, debajo "– Para llevar", cada línea con su precio, la observación para cocina, el total y *Confirmar venta*. En el celular, lo mismo una sección debajo de otra, con el total y *Confirmar* fijos abajo. **El modal de cada pizza:** en la computadora, los sabores con su foto a la izquierda y, fijos a la derecha, el tipo, los extras, la cantidad y el botón con el único precio; en el celular, los extras en una fila deslizable en el pie. En ninguno hay que bajar hasta después de las pizzas para elegir un extra. Tocar una línea abre el modal para corregirla o quitarla. **Al confirmar,** un aviso flotante dice "Pedido 12 de Ana Prueba enviado a cocina · Para llevar · Bs 106" y se cierra solo a los 6 segundos, o con la X; el formulario queda limpio y vuelve arriba. Si el envío falla, la venta no se pierde y el mensaje dice qué hacer. **`flutter test`: 163 de 163**; se rehicieron las pruebas de la venta: **48 de la lógica** (la tabla de la sección 6, el formulario, lo que falta para confirmar, el cuerpo exacto que se envía, el modal y la venta directa) y **38 de la pantalla** (los estados de carga, una venta completa con el cuerpo exacto, lo que falta marcado sin enviar nada, el celular inválido, cancelar con confirmación, el modal —entera por defecto, el botón que dice qué falta, mitad y mitad marcadas 1 y 2, una agotada que no responde, cerrar sin agregar, corregir y quitar, − y +, la misma pizza en una sola línea—, el envío —"Enviando" sin doble envío, agotado, sin conexión con reintento, precio cambiado—, la venta directa —cobra, no toca la venta en curso, si falla conserva las bebidas, cerrarla no vende—, el aviso que se cierra solo, y la distribución: **en 1024 × 600, 1366 × 630, 1536 × 730 y 1920 × 950 el formulario llega hasta abajo sin desplazarse**, con muchas pizzas se desplaza solo su lista, en el celular vuelve arriba al enviar, los extras del modal están a la vista sin desplazar nada, y en 320 px nada se desborda). **En el navegador**, con la carta real: una venta completa hasta el aviso, una venta directa y el aviso que se cierra solo. **Revisión con el autor, en dos vueltas.** (1) "Me gusta cómo se ve", y pidió quitar el desplazamiento innecesario, poner el celular al lado del nombre y "para llevar" en un renglón debajo, y que el aviso se cierre solo: quedaba arriba un minuto y el formulario se quedaba desplazado abajo. (2) Después pidió no comprimirlo tanto sino repartirlo en toda la pantalla, y no tener que bajar hasta después de las pizzas para elegir los extras. **Lo que salió:** en 320 px, el precio de una línea de pizza empujaba la fila fuera del borde: ahora se achica antes de desbordarse; y con tres bebidas por fila, los nombres se partían mal: la fila de bebidas del formulario usa un contador más compacto |
| I — Los pedidos en recepción | ✅ Verificada · **aprobada por el autor** ("perfecto, funciona", y con los dos ajustes, "está bien, aprobado") | 2026-09-25 | **Recepción, en dos pestañas:** *Venta* y *Pedidos*. En la computadora van dentro de la barra (desde 1100 px) y la venta conserva todo lo que se estaba armando al ir y volver. **La sección *Pedidos*:** los activos en vivo, **los listos primero**, cada uno con su número del día, el cliente, el celular, "para llevar", cuánto hace que se vendió, las líneas (lo agregado, con su hora) y el total; *Entregar* solo en el listo; *Cancelar* con un motivo elegido de una lista o escrito; *Llamar* muestra el número con *Copiar* y *Llamar*, que en el celular abre el marcador; y *Agregar* abre un modal con las pizzas (el mismo de la venta) y las bebidas, y envía solo lo nuevo con el total esperado. Si cocina ya lo tiene listo, la app explica que se puede sumar una bebida pero no una pizza. **Cuando un pedido queda listo:** suena, aparece un aviso de 10 segundos con *Ver pedidos*, la pestaña dice "(1) Pedido listo" y la barra, "1 listo". **Cocina:** cada tarjeta dice el número del día; lo agregado llega en vivo con la marca "Se agregó algo", su hora en la línea y el sonido; y *Listo* manda la versión que vio, así que si recepción agregó algo en ese momento, cocina recibe el 409 `PEDIDO_CAMBIADO`, relee el pedido y lo ve antes de cerrarlo. **Ajustes que pidió el autor al revisarla:** (1) **el sonido viene activado**: el navegador no deja sonar una página que nadie usó, así que el timbre intenta al cargar y, si no puede, se activa solo con el primer toque o tecla en cualquier parte de la pantalla, y la barra pasa sola al ícono del parlante; el botón "Activar sonido" queda para probarlo. (2) **Dos estaciones, Tres estaciones y Criolla española se venden solo enteras (D-39):** la migración `08` agrega `producto.solo_entera` con una restricción que solo lo permite en pizzas y marca las tres; el servidor rechaza con 400 una línea en la que cualquiera de las dos mitades sea solo entera, al vender y al agregar; la carta devuelve `soloEntera`; y en "mitad y mitad" la venta las muestra atenuadas con "Solo entera" y no deja elegirlas, y si estaba elegida una como entera, al pasar a mitades se suelta. **La migración `08`:** aplicada dos veces a la base local sin error, rechaza marcar una bebida y funciona en una instalación nueva de `00` a `08`. **`npm test`: 267 de 267** (259 anteriores; 4 de D-39, las tres mitades rechazadas y la pizza entera a su precio, y la carta marca las tres; y 4 del puente de avisos, abajo). **Contra la base real** (`probar_pedidos.py`, tokens reales): **75 de 75**, con la carta que marca las tres y los tres rechazos. **`flutter test`: 193 de 193** (163 anteriores y 30 nuevas), `flutter analyze` sin observaciones: **20 de los pedidos de recepción** (el orden con los listos primero, los que llegan y se van en vivo, el aviso y el título de la pestaña, entregar, cancelar con motivo, llamar, agregar con su 409 explicado, y la barra en nueve anchos, de 320 a 1920 px, sin desbordarse); de la cocina, el número, la versión y su 409, lo agregado con su marca y su sonido, y el sonido que se enciende solo; y de D-39, la lógica y el modal. **En el navegador**, con la carta real y las dos cuentas de prueba, el autor probó la fase ("perfecto, funciona") y después revisó los dos ajustes. **Lo que salió:** (1) a 360 px las pestañas se salían del borde: ahora ocupan el ancho y se achican; (2) con las pestañas debajo de la barra, en una computadora baja la lista de pizzas quedaba de 100 px: las pestañas pasaron a la barra desde 1100 px y el formulario llena la pantalla solo desde 520 px de alto; (3) la tabla de precios del plan 05 tenía "mitad Carnívora, mitad Criolla española", que D-39 vuelve imposible: se cambió en las pruebas de la API por Carnívora con Cuatro quesos (Bs 57,50) y en las de la app por Salame con Hawaiana (Bs 47,50); (4) al preparar la subida apareció que el formateador de Dart se había pasado con otro ancho de línea a todo el frontend, también a archivos que la fase no tocó: cada uno volvió a quedar igual al subido, y los que sí cambiaron conservan el ancho que tenían, para que el commit lleve solo los cambios de la fase; después, `flutter analyze` sin observaciones y `flutter test` 193 de 193 otra vez; (5) **con la fase aprobada, el autor encontró que al agregar una pizza desde *Pedidos*, cocina no se enteraba** (E-012): el aviso de lo agregado existía en el canal, pero no en el puente que `servidor.js` le arma a la API, y ninguna prueba pasaba por ese puente. Se corrigió, y 4 pruebas nuevas avisan por el mismo camino que la API: el puente tiene los mismos avisos que el canal, y cada uno llega a un cliente real de Socket.IO (sin la corrección, fallan 2). La medición contra la API real suma lo agregado: **del envío a cocina, mediana 23 ms y peor caso 27 ms** en 10 pedidos en preparación, con la venta en 26 ms y el cambio de estado en 22 ms |
| J — En producción | ✅ Verificada | 2026-09-25 | **Antes:** producción seguía en la tarjeta 05, con la venta guiada: `POST /api/v1/pedidos` y `/socket.io/` respondían 404, y la base tenía 22 productos y **0 pedidos**, así que la `06`, que exige cliente en cada pedido, no tenía nada que la detuviera. **El autor, en el servidor:** trajo el código, hizo el **respaldo** de la base fuera de la carpeta del repositorio (`/opt/respaldos/maxpizzapp-2026-09-25-1441.dump`, 29 KB, con `pg_dump -Fc`), aplicó las migraciones **`06`, `07` y `08` en orden y sin errores**, y reconstruyó la API. **La app** se compiló en la máquina de desarrollo y se publicó como la versión `20260925-110300`; las dos anteriores quedan para volver atrás. **Contra la dirección pública, con las cuentas de prueba y tokens reales:** el inicio de sesión con PKCE de los dos roles, correcto; la API con tokens reales (`probar_salud_y_token.py`), correcta; **`probar_pedidos.py`: 75 de 75**, con la carta que marca las tres pizzas solo enteras, sus tres rechazos, el número del día, la venta directa, agregar, el ciclo completo, la cancelación y **las tres carreras**: 12 ventas a la vez, todas guardadas y numeradas en el orden de llegada; dos cambios a la vez sobre el mismo pedido, uno solo pasa; y *Listo* contra *Agregar una pizza* en 8 rondas, siempre uno solo (agregar ganó 5 y listo 3). **El aviso en vivo, 20 mediciones de cada uno** desde la máquina de desarrollo hasta el servidor y de vuelta: **pedido nuevo a cocina, mediana 142 ms y peor caso 147 ms; cambio de estado a recepción, 140 ms y 155 ms; lo agregado a cocina, 141 ms y 431 ms**, todo por *websocket* y muy por debajo de los 2 s de RF-06. **Después:** la API sana y con **0 reinicios** (E-011), y **ningún pedido de prueba activo**: los 53 que crearon la sonda y la medición quedaron cancelados o entregados. **Lo que salió:** el autor vio todavía la pantalla de acceso vieja, con el botón negro, porque la app se publica después de reconstruir la API; al publicarla apareció la nueva. Y como las pruebas usaron los números del día 1 al 52 (una de las 53 fue una venta directa, que no lleva número), los pedidos de hoy en producción empiezan en el 53; mañana vuelve a empezar en 1 |
| K — La prueba del autor | ✅ Verificada · **aprobada por el autor** ("funciona todo bien… está todo perfecto") | 2026-09-25 | **En producción, `https://maxpizzapp.tech`, con las dos cuentas de prueba.** Lo que quedó registrado en la base, leído sin modificar nada: **pedido 53**, para llevar, con una pizza **agregada** mientras cocina lo preparaba, empezado, listo y entregado entre las 11:10 y las 11:12; **pedido 54**, cancelado con motivo ("Error al tomar el pedido") **cuando ya estaba en preparación**; **pedido 55**, otra venta con algo agregado, hasta entregarla; **pedido 56**, cancelado estando **pendiente**, con motivo ("El cliente se fue"); y una **venta directa de bebidas** de Bs 18, sin nombre ni número, que nació entregada a las 11:50. **Lo que pidió el autor al probarla (D-41):** el pedido 54 mostró que se podía cancelar uno que cocina ya empezó, y eso es pérdida para el local, porque lo que entró al horno ya se gastó. Desde entonces **solo se cancela el pendiente**: el servidor responde 409 `TRANSICION_NO_PERMITIDA` y la app ofrece *Cancelar* solo en el pendiente; al que está en preparación se le puede seguir agregando. Las pruebas contra la API real ya no podían cerrar sus pedidos cancelándolos: ahora terminan y entregan los que cocina empezó. Local: `npm test` 267 de 267, `flutter test` **194 de 194** (una nueva: si cocina lo empieza justo antes de cancelar, la app lo explica y relee), `probar_pedidos.py` **76 de 76** (uno nuevo: cancelar uno en preparación da 409). **El autor publicó la app él mismo** con `scripts/publicar-web.sh` (versión `20260925-113407`), para saber explicarlo en la defensa, y reconstruyó la API en el servidor. **La primera vez la regla quedó solo en la pantalla:** la app nueva ya ocultaba el botón, pero el servidor no había traído el código, así que una pestaña vieja todavía podía cancelar; se detectó al revisar el contenedor, antes de dar la fase por buena, y se completó con el `git pull` y el `up -d --build`. **Después, contra la dirección pública:** `probar_pedidos.py` **76 de 76**, con el 409 de D-41; el aviso en vivo, 10 mediciones de cada uno: **pedido nuevo a cocina, mediana 147 ms y peor caso 161 ms; cambio de estado a recepción, 147 ms y 150 ms; lo agregado a cocina, 150 ms y 435 ms**; la API con **0 reinicios** y **ningún pedido activo** al terminar |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-24 | Versión inicial propuesta | La última tarjeta antes del E2. Incorpora las decisiones del autor sobre el cliente (D-31), los pedidos de solo bebidas (D-32) y la cancelación (D-33), y el canal en vivo mínimo que el E2 exige (D-21) |
| 2026-09-24 | **Aprobado**, sumando "para llevar o comer aquí" (D-34) | El autor aprobó el plan con la recomendación: cocina ve si va en caja o en plato. No toca el E1: es un dato más del pedido, dentro de RF-02 |
| 2026-09-24 | **Número del día (D-35)**, a pedido del autor, en la fase G | El número de la base crece siempre, puede tener huecos y no vuelve a empezar: en un mes, los pedidos serían #1.543. Para cantarlos en el mostrador, un número que empieza en 1 cada día, sin huecos. El de la base se queda como identificador interno |
| 2026-09-24 | **Revisión de la fase E con el autor** | Los colores pasan a rojo ladrillo (D-29, segunda revisión); la venta se distribuye mejor en la computadora; la pantalla de acceso lleva una foto del local. Se suma un **aviso que suena**: en recepción cuando un pedido queda listo, y en cocina cuando llega uno nuevo |
| 2026-09-24 | **Revisión de la fase H con el autor, en dos vueltas** | Sin desplazamiento innecesario: el formulario ocupa la pantalla y solo la lista de pizzas se desplaza si son muchas. *Vender bebidas* sube a la línea del cliente y la observación pasa al pedido, justo antes de confirmar. El pedido muestra el celular al lado del nombre y "para llevar" debajo. El aviso de la venta flota y se cierra solo. En el modal, los extras quedan siempre a la vista |
| 2026-09-24 | **Observación de la tutoría: la venta en una sola pantalla (D-36)**, y dos casos del mostrador que sumó el autor: **agregar a un pedido ya enviado (D-37)** y **la venta directa de bebidas (D-38)**. Las fases pasan a ser G (la API), H (la venta), I (los pedidos en recepción), J (producción) y K (la prueba del autor). Aprobado por el autor | La tutoría observó que la venta eran demasiadas pantallas seguidas y que en la computadora se hacía larga. Pidió un formulario en F, en el orden cliente → para llevar o comer aquí → pizzas → observación → confirmar, con cada pizza en un modal. El autor sumó el cliente que pide la soda después de la pizza, sin hacer otro ticket, y el que solo pasa a comprar una soda, sin que se le pida el nombre |
| 2026-09-25 | **Revisión de la fase I con el autor:** el sonido viene activado, y **tres pizzas se venden solo enteras (D-39)**, con una migración nueva, la `08` | El autor probó la fase ("funciona") y pidió dos ajustes. El sonido: tener que tocar "Activar sonido" se olvida; ahora se activa solo con el primer toque en la pantalla, que es lo máximo que el navegador permite. Las pizzas: Dos estaciones, Tres estaciones y Criolla española ya combinan sabores y no se venden por mitades. La tabla de precios del plan 05 tenía "mitad Carnívora, mitad Criolla española", que deja de ser posible: las pruebas de la API la cambian por Carnívora con Cuatro quesos, y las de la app por Salame con Hawaiana |
| 2026-09-25 | **Un pedido en preparación ya no se cancela (D-41)**, a pedido del autor durante la fase K | La preparación es corta y lo que entró al horno ya se gastó: cancelarlo es pérdida para el local. Se cancela solo el pendiente; al que está en preparación se le puede seguir agregando (D-37). Cambia la tabla de transiciones, la sección *Pedidos* de recepción, las pruebas contra la API real, que ya no pueden cerrar sus pedidos cancelándolos, y el RF-09 del documento |

---

## 11. Cierre

- **Commits de la tarjeta**, uno por fase probada:
  - `3471a88` el plan (06-P);
  - `0f7c17b` la base (A);
  - `41a9949` crear el pedido (B);
  - `544fe38` leer, avanzar y cancelar (C);
  - `2574507` el aviso en vivo (D);
  - `c9b15cc` la venta envía el pedido (E);
  - `56d2121` la cola de cocina (F);
  - `736666d` el número del día, agregar y la venta directa (G);
  - `3b41513` la venta en una sola pantalla (H);
  - `57dce99` los pedidos en recepción (I);
  - `85ea26f` un pedido en preparación no se cancela (K, D-41).

  Aparte, `7c2d0cf` completó el README, el `.gitignore` y el `.env.example` con el modelo del
  tutor. El cierre (06-E) lleva este apartado y el índice de planes.
- **Fecha de cierre:** 2026-09-25, con la tarjeta en producción y aprobada por el autor.
