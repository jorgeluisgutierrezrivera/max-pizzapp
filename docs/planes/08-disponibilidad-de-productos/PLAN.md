# Plan 08 — Disponibilidad de productos

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 08 — Disponibilidad de productos (RF-13)
- **Incremento:** tiempo real completo (cierra el incremento 3)
- **Estado:** 🔨 **En curso** — aprobado el 2026-10-04, sin cambios
- **Entrada al tablero:** 2026-09-22, como la 08 del índice; la cancelación (RF-09) se adelantó
  a la 06 (D-33)
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que **cocina o recepción marquen un producto como agotado** y que deje de ofrecerse en la
venta **al instante, en todas las pantallas**, sin tocar los pedidos que ya lo llevan. Y que
se pueda volver a ofrecer cuando se repone.

1. **Desde su propia pantalla, con su cuenta.** Los dos roles marcan un producto agotado o
   disponible: pizzas, bebidas y extras. No hace falta un tercer rol (D-13).
2. **En menos de 2 segundos**, la venta de recepción lo muestra apagado y no deja elegirlo
   (CA-13.1). Si lo marcó cocina, recepción ve además un aviso de qué se agotó.
3. **Los pedidos que ya lo llevan no cambian** (CA-13.2). Una venta todavía sin confirmar que
   lo tiene avisa qué quitar.
4. **El servidor manda.** Un producto agotado no se vende aunque una pantalla vieja lo
   ofrezca: eso ya pasa desde la tarjeta 06 (409 `PRODUCTO_NO_DISPONIBLE`).

**Por qué ahora:** el negocio va a probar el sistema en el local y necesita controlar lo que
no hay (decisión del autor, 4-oct). El apartado 1.2 lo cuantificó: descubrir tarde la falta
de un producto le suma de 10 a 15 minutos de espera al pedido. Con esta tarjeta, **todos los
*Should* quedan implementados**.

**Lo que ya existe**, y no se toca:

- la columna `producto.disponible`, desde la tarjeta 01;
- `GET /productos`, que la devuelve;
- la venta, que rechaza un agotado en el cliente y en el servidor;
- las pantallas de venta, que lo muestran apagado y con la palabra *Agotada*.

Falta **cómo se marca** y **cómo llega en vivo**.

---

## 2. Alcance

**Incluye:**

- **La ruta** `PATCH /api/v1/productos/{id}/disponibilidad`, la del contrato de la Tabla 12,
  para los dos roles (D-66).
- **El aviso en vivo** `producto:disponibilidad`, a las dos pantallas (D-67).
- **El panel *Carta*** en la barra de cocina (la web y el APK) y en la de recepción: los
  productos por categoría, con un interruptor cada uno (D-68).
- **La carta al día en la venta:** se actualiza con el aviso y se vuelve a leer al reconectar
  el canal (D-67). Viene de la tarjeta 07, que la pasó a esta.
- **La venta en curso** con un producto que se agota (D-69).
- **El APK 0.2.0**, con el panel, publicado como un *Release* nuevo.
- El contrato OpenAPI, el README y el BRIEF: la ruta deja de figurar como prevista.
- Dos filas nuevas en la tabla de casos del 2.8 y la medición de la propagación.

**No incluye:**

- **Existencias ni cantidades:** el control de inventario sigue fuera de alcance (Tabla 9).
  Un producto está disponible o no.
- **Agotar o reponer a una hora programada.** Se marca a mano, cuando pasa.
- **El historial de quién marcó qué.** El aviso en vivo dice quién lo marcó, pero no queda
  guardado. Agregarlo pide una tabla nueva; queda para las recomendaciones.
- **Alta, edición y baja de productos.** Es del rol administrador, fuera de alcance (D-13).

---

## 3. Decisiones de diseño

### D-66 · La ruta del contrato, para los dos roles, que solo avisa si algo cambió

- **`PATCH /api/v1/productos/{id}/disponibilidad`**, con el cuerpo `{ "disponible": false }`.
  Es la ruta que ya publican el contrato de la Tabla 12 y el BRIEF como prevista. Responde
  **200 con el producto actualizado**, con la misma forma de `GET /productos`.
- **Los dos roles**, recepción y cocina (`exigirRol`). Una cuenta sin rol recibe 403, como en
  el resto de la API.
- **La validación, antes de tocar la base:**
  - un número de producto que no es un entero positivo: 400 `ID_INVALIDO`;
  - un cuerpo distinto de exactamente `{ "disponible": true | false }`: 400
    `DISPONIBILIDAD_INVALIDA`;
  - un producto que no existe: 404 `PRODUCTO_NO_ENCONTRADO`.

  Todo con el formato de error único.
- **Una sola consulta parametrizada**, que guarda el valor nuevo y devuelve también el
  anterior, sin leer y escribir por separado.
- **Marcar lo que ya estaba igual** responde 200 y **no avisa**: no hay nada que contar. Así
  dos personas que tocan el mismo interruptor a la vez no generan avisos repetidos.
- **Se descartó** `PATCH /productos/{id}` con cualquier campo. Abriría la puerta a editar
  precios y nombres, que son del rol administrador.

### D-67 · El aviso en vivo, a las dos salas, con quién lo marcó

- **`producto:disponibilidad`**, con `{ id, nombre, categoria, disponible, por, fechaHora }`.
  `por` es el rol que lo marcó (`recepcion` o `cocina`), no el nombre de la persona. Va a las
  **dos salas**: a las dos les cambia la carta.
- **Lo que hace cada pantalla:**
  - **La venta de recepción** actualiza ese producto en su carta: queda apagado o vuelve a
    ofrecerse sin recargar. Si lo marcó cocina, muestra un aviso breve: *"Cocina marcó
    Pepperoni como agotada"*.
  - **El panel *Carta***, si está abierto en otra pantalla, mueve el interruptor.
- **El canal avisa; la fuente es la API**, la regla de siempre. Al reconectarse el canal, la
  venta **vuelve a leer la carta**, porque mientras estuvo cortado pudo perderse un aviso. Es
  lo que la tarjeta 07 dejó para esta.

### D-68 · Dónde se marca: un panel *Carta*, el mismo en cocina y en recepción

- **Un botón *Carta*** en la barra de cada rol, al lado del de sonido. En cocina está en la web
  y en el APK.
- **El panel:**
  - una ventana en pantallas anchas y una hoja desde abajo en el celular;
  - los productos **por categoría** (pizzas, bebidas, extras), en el orden de la carta;
  - un **interruptor** cada uno, con *Disponible* o *Agotado* escrito al lado, no solo el
    color;
  - el cambio se guarda al tocar, sin pedir confirmación, porque se deshace con otro toque;
  - mientras se guarda, el interruptor espera. Si falla, vuelve a su lugar y dice por qué.
- **El mismo componente para los dos roles:** una sola pieza que probar.
- **Se descartó marcar desde la tarjeta de la pizza en la venta**, con una pulsación larga.
  Es un gesto escondido que nadie descubre, y cocina no tiene la carta en su pantalla.

### D-69 · La venta en curso con un producto que se agota

- **Si el producto ya está en una venta sin confirmar**, la línea queda marcada *Agotado*, y
  *Confirmar venta* avisa qué quitar en lugar de enviar.
- **Si igual llega al servidor**, porque la pantalla no se enteró, el servidor la rechaza con
  409 `PRODUCTO_NO_DISPONIBLE`, como desde la tarjeta 06, y la pantalla ya muestra ese mensaje.
- **Los pedidos ya enviados no cambian** (CA-13.2): sus líneas guardan producto, cantidad y
  precio, y la ruta nueva no toca ningún pedido.

---

### D-70 · Una categoría entera, con una sola consulta y un solo aviso (revisión del 4-oct)

- **El caso:** se acaba la masa, y ya no se puede hacer ninguna pizza aunque haya toppings.
  Con D-66, cocina tendría que tocar quince interruptores, y recepción recibiría quince avisos
  seguidos. La pregunta la hizo el autor el 4-oct, pensando en el local en funcionamiento.
- **`PATCH /api/v1/productos/disponibilidad`**, con el cuerpo exacto
  `{ "categoria": "pizza", "disponible": false }`, para los dos roles. Agota o repone **todos**
  los productos de esa categoría.
  - **Valida antes de tocar la base:** una categoría que no existe o un cuerpo distinto de esos
    dos campos responden 400 `DISPONIBILIDAD_INVALIDA`.
  - **Una sola consulta parametrizada:**
    `UPDATE … WHERE categoria = $1 AND disponible <> $2 RETURNING id`, que cambia solo lo que
    hacía falta.
  - Responde 200 con la categoría, el valor y los productos que cambiaron.
- **Un solo aviso, `categoria:disponibilidad`**, con
  `{ categoria, disponible, ids, por, fechaHora }`, a las dos salas. Sale solo si cambió algo.
  Recepción ve un aviso: *"Cocina marcó agotadas todas las pizzas"*.
- **No es control de inventario:** el sistema no cuenta cuántas pizzas rinde la masa ni se
  agota solo. Eso sigue fuera de alcance (Tabla 9) y queda para las recomendaciones del
  Capítulo 3.
- **Se descartó** que la app mande quince `PATCH` seguidos: no es atómico, porque una falla a
  mitad deja la carta a medias, y serían quince avisos.

### D-71 · El botón *Agotar todas* del panel, y la venta sin pizzas (revisión del 4-oct)

- **En el panel *Carta*, al lado del título de cada categoría:** *Agotar todas* mientras quede
  alguna disponible, y *Reponer todas* cuando están todas agotadas.
  - **Este sí pide confirmación** (*"¿Agotar todas las pizzas?"*), porque cambia toda una parte
    de la carta. El interruptor de un producto sigue sin pedirla (D-68).
  - Mientras se guarda, los interruptores de esa categoría esperan.
- **En la venta de recepción, si no queda ninguna pizza disponible:** una banda clara, *"No
  quedan pizzas. Solo se venden bebidas, con «Vender bebidas»."*, y *Agregar pizza* apagado.
  La vendedora no tiene que descubrirlo tocando.

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — La API
- [x] La ruta, con su validación, en `backend/src/rutas/productos.js`, y el aviso en
      `tiempo-real.js` (también en `SIN_AVISOS` y en los avisos de `servidor.js`).
- [x] Pruebas (`npm test`):
  - 200 con cada rol, y el producto devuelto;
  - 401 sin token y 403 con una cuenta sin rol;
  - 400 por el número y por cada forma de cuerpo inválido, sin tocar la base;
  - 404;
  - marcar lo mismo no avisa;
  - el aviso llega a las dos salas con su contenido;
  - un pedido que ya lleva el producto no cambia (CA-13.2);
  - una venta nueva con el producto agotado, 409.
- [x] El contrato OpenAPI con la ruta y sus respuestas; `contrato.test.js` en verde.
- [x] Contra la API local con la base y el Keycloak reales: una sonda que marca y repone un
      producto con cada cuenta, y la matriz de errores con los casos nuevos.

### Fase B — La app
- [x] El panel *Carta*, el mismo para los dos roles, con su botón en las dos barras.
- [x] La carta de la venta, al día con el aviso, y leída de nuevo al reconectar el canal.
- [x] El aviso en recepción cuando cocina marca algo.
- [x] La venta en curso con un producto que se agota.
- [x] Pruebas (`flutter test` y `flutter analyze`):
  - el panel marca y repone, espera mientras guarda y vuelve atrás si falla;
  - el aviso en vivo apaga el producto en la venta y muestra el mensaje;
  - la venta en curso no confirma con un agotado;
  - al reconectar, la carta se vuelve a leer;
  - el panel a 1366 × 768 y a 768 × 1024 (RNF-04).
- [x] En local: dos navegadores, cocina marca y recepción lo ve apagado al instante.
- [x] La instalación local en un paso sigue en verde en la integración continua (corridas de `5ac2269`, `108279a` y `39462a7`: *Pruebas* e *Instalacion*, las seis en verde).

### Fase C — En producción
- [x] El autor despliega la API (`git pull` y `up -d --build`). **No hay migración.**
- [x] La app web publicada (`scripts/publicar-web.sh`).
- [x] El APK 0.2.0 compilado y firmado; el autor crea el *Release* `apk-cocina-0.2.0`.
- [x] Las sondas contra producción, con un producto **ficticio** (una bebida), fuera del
      horario de atención (antes de las 18:00), y dejándolo como estaba:
  - marcar y reponer con cada cuenta;
  - 401, 403, 400 y 404;
  - la propagación hasta la otra pantalla, **30 mediciones** (como el RNF-01).

### Fase B2 — Una categoría entera (revisión del 4-oct)
- [x] La ruta `PATCH /productos/disponibilidad` y el aviso `categoria:disponibilidad`, con sus
      pruebas (`npm test`) y el contrato OpenAPI.
- [x] En la app: el botón con confirmación en el panel, el aviso en recepción y la banda de la
      venta sin pizzas, con sus pruebas (`flutter test`).
- [x] La sonda (`probar_disponibilidad.py`) agota y repone **los extras**, que son ficticios, y
      deja cada uno como estaba.
- [x] En local, de punta a punta.

### Fase C2 — En producción otra vez
- [x] El autor actualiza la API; yo publico la web.
- [x] El APK 0.3.0, firmado; el autor crea el *Release* `apk-cocina-0.3.0`.
- [x] Las sondas contra producción.

### Fase D — La prueba del autor y el cierre
- [ ] El autor, con recepción en la computadora y cocina en el APK:
  - cocina marca una pizza agotada y recepción la ve apagada al instante, con el aviso;
  - cocina agota todas las pizzas: un solo aviso y la banda *"No quedan pizzas"* en la venta;
    después las repone;
  - recepción no puede venderla;
  - un pedido que ya la llevaba sigue igual;
  - cocina la repone y vuelve a ofrecerse;
  - recepción también puede marcar y reponer.
- [ ] Capturas con datos ficticios.
- [ ] Las dos filas nuevas en la tabla de casos (`docs/pruebas/README.md`).
- [ ] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **API:**
  - `backend/src/rutas/productos.js`: la ruta y su validación;
  - `backend/src/tiempo-real.js`: el aviso;
  - `backend/src/servidor.js` y `backend/src/app.js`: le pasan los avisos a las rutas de la
    carta.
- **Pruebas de la API:** `backend/test/productos.test.js` y `tiempo-real.test.js`.
- **Contrato:** `docs/api/openapi.yaml`.
- **App:**
  - `frontend/lib/pantallas/panel_de_carta.dart` *(nuevo)*;
  - `frontend/lib/api/canal_en_vivo.dart`: el evento nuevo;
  - `frontend/lib/carta/producto.dart`: actualizar un producto de la carta;
  - `pantalla_cocina.dart`, `pantalla_recepcion.dart`, `segun_rol.dart`, `app.dart` y la
    venta (`venta/formulario_de_venta.dart`).
- **Pruebas de la app:** las nuevas del panel y de la venta, y `anchos_del_rnf04.dart`.
- **Sondas:** `pruebas/api/probar_disponibilidad.py` *(nueva)*, `probar_errores.py` y la
  medición de la propagación (`pruebas/tiempo-real/`).
- **Repositorio:** `README.md`, `docs/BRIEF.md` y `docs/pruebas/README.md`.

**No cambian** la base de datos (no hay migración), el realm ni la instalación local.

---

## 6. Cómo se prueba

| Qué | Cómo | Resultado esperado |
|---|---|---|
| La ruta | `npm test` | 200 con los dos roles; 401, 403, 400 y 404 |
| El aviso | `npm test` (`tiempo-real.test.js`) | Llega a las dos salas con quién lo marcó; marcar lo mismo no avisa |
| CA-13.2 | `npm test` y la prueba del autor | El pedido que ya lo lleva no cambia |
| El servidor manda | `npm test` | Una venta con el agotado responde 409 |
| El panel y la venta | `flutter test` | Marca, repone, espera, vuelve si falla; la venta se apaga con el aviso |
| La carta al reconectar | `flutter test` | Se vuelve a leer |
| RNF-04 | `flutter test` a 1366 × 768 y 768 × 1024 | El panel entra sin desbordes |
| CA-13.1 en producción | La propagación, 30 mediciones | Menos de 2 s en todas |
| De punta a punta | El autor, con la web y el APK | Todo lo de la fase D |

---

## 7. Criterios de aceptación

- Cocina y recepción marcan un producto agotado desde su pantalla, y lo reponen.
- En menos de 2 s, la venta de recepción lo muestra apagado y no deja elegirlo, sin recargar.
  Si lo marcó cocina, recepción ve el aviso.
- Un pedido que ya lo llevaba no cambia. Una venta sin confirmar que lo tiene avisa qué
  quitar, y el servidor rechaza vender un agotado.
- La ruta valida en el servidor (400, 404) y respeta los roles (401, 403), con el formato de
  error único y consultas parametrizadas.
- El APK de cocina, en su versión 0.2.0, también marca y repone.
- La instalación local y las dos suites siguen en verde.

---

## 8. Requisitos que cubre

- **Del sistema:**
  - **RF-13** (*Should*): CA-13.1 y CA-13.2;
  - **RNF-01**: el aviso en menos de 2 s, medido;
  - **RNF-04**: el panel en los dos anchos y en el APK.
- **Institucionales:**
  - **#3**: una operación más sobre el dominio (actualizar la carta);
  - **#8**: validación en el cliente y en el servidor.
- **Del documento:** el 2.6 y el 2.8 (dos casos nuevos). La Tabla 12 y la Tabla 6 dejan de
  marcar RF-13 como previsto.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — La API | ✅ Verificada | 2026-10-04 | **La ruta** `PATCH /productos/:id/disponibilidad` en `rutas/productos.js`: los dos roles; `leerId` (400 `ID_INVALIDO`) y `leerDisponibilidad` (exactamente `{ disponible: boolean }`, si no 400 `DISPONIBILIDAD_INVALIDA`), los dos antes de tocar la base. Una sola consulta (`WITH anterior … FOR UPDATE` y `UPDATE … RETURNING`) devuelve el producto y cómo estaba; 404 `PRODUCTO_NO_ENCONTRADO`; avisa solo si cambió, después de responder. **El aviso** `disponibilidadCambiada` en `tiempo-real.js` emite `producto:disponibilidad` a las dos salas con `{ id, nombre, categoria, disponible, por, fechaHora }`; está en `SIN_AVISOS` y en los avisos de `servidor.js`. El `avisar` de los pedidos pasó a `tiempo-real.js` y lo usan las dos rutas. **`npm test`: 312 de 312** (las 288 de antes y 24 nuevas): sin token 401 y sin rol 403, sin tocar la base; 200 con cada rol, con el producto y el aviso que dice quién lo marcó; una sola consulta, parametrizada (`[7, false]`), que no nombra ningún pedido (CA-13.2); reponer avisa; marcar lo mismo dos veces avisa una sola; 404 sin aviso; seis números inválidos; siete cuerpos inválidos (vacío, texto, nulo, número, un campo de más, solo otro campo, una lista); un cuerpo que no es JSON; y un booleano suelto, que rechaza el lector de JSON con `JSON_INVALIDO`. En `tiempo-real.test.js`: el aviso llega a las dos salas con su contenido y llega por los avisos de la API. **El contrato:** `contrato.test.js` falló hasta sumar la ruta a `openapi.yaml` (con `IdProducto`, `CambioDeDisponibilidad` y el evento en la descripción del canal), y después pasó. **Contra la API local, con la base y el Keycloak reales:** `probar_disponibilidad.py` dio TODO CORRECTO. Recepción vendió una pizza y la Gaseosa 2 L; cocina la marcó agotada; marcarla de nuevo respondió 200 sin cambios; el pedido siguió con sus 2 líneas, Bs 68 y *pendiente* (**CA-13.2**); una venta nueva con la bebida recibió 409 `PRODUCTO_NO_DISPONIBLE` con su id (**CA-13.1**); recepción la repuso; 401, 404, 400 por el número y 400 por un campo de más, con el precio sin cambios. La bebida quedó disponible, como estaba, y el pedido de prueba, cancelado. `probar_errores.py`: **20 de 20**, con los cuatro casos nuevos. `medir_aviso.py` con la cuarta medición (cocina marca la bebida, alternando agotada y disponible, hasta el aviso en recepción), 4 repeticiones en local: mediana de 12 ms y máximo de 13 ms. El reporte versionado de producción se restauró sin cambios: se rehace en la fase C. `correr_sondas.py` suma `sonda-disponibilidad.txt` |
| B — La app | ✅ Verificada | 2026-10-04 | **La carta cambia en el lugar.** `Carta` pasa a avisar sus cambios (`ChangeNotifier`), con `marcarDisponibilidad`, `aplicarDisponibilidadDe`, `estaDisponible` y `porId`; `Producto.conDisponible`. Hacía falta: la venta en curso está atada a la carta, y reemplazarla la reiniciaba. La venta, la pizza a medio armar, la venta directa y lo que se agrega a un pedido escuchan a la carta y dejan de escucharla al cerrarse. Lo que se agotó mientras se armaba se lista (`agotados`); la línea de la pizza se marca *"Agotado: quítala o corrígela"*, la de la bebida ya mostraba *Agotada*, y *Confirmar* dice *"X se agotó: quítalo de la venta."* (D-69). **El canal:** `disponibilidades`, con el evento `producto:disponibilidad`. **El panel *Carta*** (`panel_de_carta.dart`): una ventana desde 600 px y una hoja desde abajo más angosto; por categoría; interruptor con *Disponible* o *Agotado* escrito; *Guardando…* mientras viaja; el mensaje si falla. **Recepción:** el botón en la barra; el aviso apaga el producto sin reiniciar la venta, y si lo marcó cocina, aparece *"Cocina marcó agotado: X"*, en fila detrás del aviso que haya; al volver el canal después de un corte se relee solo la disponibilidad; un 409 `PRODUCTO_NO_DISPONIBLE` marca el producto en la carta. **Cocina:** el botón en la barra (en la web y en el APK); la carta se lee al abrir el panel por primera vez y se mantiene al día con el aviso y al reconectar. **Lo que encontraron las pruebas:** (1) las de recepción compartían una carta global y, con la carta que cambia en el lugar, la prueba del 409 pasaba lo agotado a las siguientes: ahora cada prueba recibe una carta nueva. (2) A 1100 y a 1400 px, el botón nuevo dejaba sin lugar a las pestañas de recepción en la barra: las pestañas suben a la barra desde **1200 px** (antes, 1100), y el botón lleva texto solo desde 1700 px en recepción y desde 600 px en cocina, que no tiene pestañas. (3) En cocina, si la carta no cargaba, el manejador del error de `Future.then` devolvía un tipo inválido y lanzaba una excepción en vez de permitir reintentar: corregido (`then<void>`). **`flutter test`: 322 de 322** (las 289 de antes y 33 nuevas): 15 del modelo (la carta en el lugar, la venta, la pizza a medio armar, la venta directa y lo agregado con un producto que se agota), 10 de recepción (el aviso de cocina sin reiniciar la venta; la reposición; sin aviso si lo marcó recepción; la venta en curso con la bebida y con la pizza agotadas; la relectura al reconectar; el panel desde la barra; el 409; el panel a 1366 × 768 y a 768 × 1024, RNF-04), 7 de cocina (marcar y reponer, *Guardando…*, el error, el aviso de otra pantalla, la lectura y el reintento, y el panel a 360 × 780 como hoja y a 768 × 1024) y 1 del canal. `flutter analyze`, sin avisos. **En local, con la instalación en un paso reconstruida** (la app compilada en Docker, 134 s con caché) contra la API de la fase A: cocina abrió el panel, marcó *Carnívora* (pasó por *Guardando…* y quedó *Agotado*), y la API la devolvió agotada. Recepción la repuso por la API, y **el interruptor del panel de cocina, abierto, volvió solo a *Disponible***. Con recepción en la venta, cocina marcó la *Gaseosa 2 L* por la API: **la venta la mostró *Agotada* y apagada, sin recargar**. Al reponerla, volvió con su precio y apareció *"Cocina volvió a ofrecer: Gaseosa 2 L"*. El README y el BRIEF ya no dicen *previsto* |
| C — En producción | ✅ Verificada | 2026-10-04 | **4-oct, desde las 18:40, dentro del horario: ese día el local no atendía** (revisión del plan). **La API:** el autor trajo el código y reconstruyó solo la API (`up -d --build backend`), sin migración. La API arrancó sana (*"limite: 600 peticiones por minuto por IP"*) y la base, Keycloak y Caddy siguieron arriba sin recrearse. Desde afuera, `PATCH /productos/1/disponibilidad` sin token responde **401** (antes, 404) y la salud, 200. **La web:** `publicar-web.sh`, versión `20261004-185714` (129,9 s de compilación); el `main.dart.js` de producción trae el panel y el evento. **El APK 0.2.0+2:** `compilar-apk.sh`, 52 MB en 339 s, firmado con la misma llave que el 0.1.0 (certificado `3c:32:be:ac…ba:06:b0:1a`), SHA-256 `119cc9ab213c8b44db04764d7a520d0992505ad739eb979bd3b8e1281b97add3`. **Las sondas contra producción** (`correr_sondas.py`, 19:08 a 19:11): las **seis**, TODO CORRECTO (acceso, salud, carta, pedidos, errores y disponibilidad). `sonda-disponibilidad.txt`: con la *Gaseosa 2 L* (id 17), recepción vendió una pizza y la bebida; cocina la marcó agotada; marcarla de nuevo, 200 sin cambios; el pedido siguió con 2 líneas, Bs 68 y *pendiente* (**CA-13.2**); una venta nueva, 409 `PRODUCTO_NO_DISPONIBLE` (**CA-13.1**); recepción la repuso; 401, 404, 400 y 400 con el precio intacto. Quedó disponible y el pedido 414, cancelado. `sonda-errores.txt`: 20 de 20. **La propagación, 30 repeticiones** (`tiempo-real.txt`, 23:11 UTC, por WebSocket): pedido nuevo a cocina, máximo 167 ms; cambio de estado a recepción, 165 ms; lo agregado a cocina, 164 ms; **la disponibilidad a recepción, mediana de 159 ms, p95 de 162 ms y máximo de 164 ms**, todo bajo 2 s. Se cerraron los 30 pedidos de la medición y la bebida quedó como estaba. **El *Release*:** el autor publicó `apk-cocina-0.2.0` desde la web de GitHub, sobre `39462a7` y marcado *Latest*. Verificado en la API pública: el archivo `max-pizzapp-cocina.apk` pesa 54 464 911 bytes, igual que el compilado, y su `digest` es la misma SHA-256. El enlace de Moodle (`…/releases/latest/download/max-pizzapp-cocina.apk`) redirige a la 0.2.0 |
| B2 — Una categoría entera | ✅ Verificada | 2026-10-04 | **La API:** `PATCH /productos/disponibilidad`, para los dos roles, con el cuerpo exacto `{ categoria, disponible }` (si no, 400 `DISPONIBILIDAD_INVALIDA`). Una sola consulta (`UPDATE … WHERE categoria = $1 AND disponible <> $2 RETURNING id`) responde con los que cambiaron, y solo entonces sale **un** aviso, `categoria:disponibilidad`, a las dos salas. **`npm test`: 327 de 327** (15 nuevas: 401, 403, 200 con cada rol con un solo aviso y una sola consulta parametrizada que no nombra pedidos, reponer, nada que cambiar sin aviso, siete cuerpos inválidos, el evento a las dos salas y por los avisos de la API); el contrato OpenAPI con la ruta y `CambioDeCategoria`. **La app:** `Carta.marcarCategoria` y `sinPizzas`; el canal, `disponibilidadesDeCategoria`; en el panel, *Agotar todas* o *Reponer todas* (*todos* en los extras) al lado de cada categoría, con confirmación, y la categoría espera mientras guarda; en recepción, un solo aviso (*"Cocina marcó agotadas todas las pizzas"*); en la venta, la banda *"No quedan pizzas. Solo se venden bebidas, con «Vender bebidas»."* y *Agregar pizza* apagado. **`flutter test`: 336 de 336** (14 nuevas: el modelo, el botón con confirmación y su cancelación, el error, el aviso de otra pantalla, la banda y su retiro, el panel de recepción y la banda a 1366 × 768 y a 768 × 1024); `flutter analyze` sin avisos. **Contra la base y el Keycloak locales:** `probar_disponibilidad.py`, TODO CORRECTO con la sección nueva. Cocina agotó los extras (cambiaron los 4); las pizzas y las bebidas no se tocaron; una venta con un extra agotado recibió 409; agotarlos de nuevo cambió 0; recepción los repuso; una categoría inexistente, 400; sin token, 401. Cada extra quedó como estaba. `probar_errores.py`: **21 de 21**. **En pantalla, con la app reconstruida, a ancho de celular:** cocina agotó las pizzas por la API (cambiaron 15) y la venta de recepción mostró la banda, *Agregar pizza* apagado, las bebidas a la venta y **un solo aviso**. Después se repusieron las 15 |
| C2 — En producción otra vez | ✅ Verificada | 2026-10-04 | **4-oct, de noche; ese día el local no atendía.** **La API:** el autor corrió la actualización del servidor mientras subía el `08-3`, antes del `08-4`: el servidor trajo solo el `08-3`, no reconstruyó la API y `PATCH /productos/disponibilidad` respondía **404**. Repetida después del último push, la API se reconstruyó (sana a los segundos) y la ruta responde **401** sin token; la base, Keycloak y Caddy siguieron arriba sin recrearse. Lección anotada en `MANUAL_GIT.md`: el servidor se actualiza después del último push, nunca en paralelo. *Pruebas* e *Instalacion* en verde para `5c71d2f` y `3d58147`. **La web:** `publicar-web.sh`, versión `20261004-220756` (131,9 s de compilación); `version.json` dice 0.3.0+3 y el `main.dart.js` de producción trae la ruta nueva y la banda *"No quedan pizzas"*. **El APK 0.3.0+3:** 54 464 971 bytes, firmado con la misma llave (certificado `3c:32:be:ac…ba:06:b0:1a`), SHA-256 `c0e032af9cd8c58c593b4bfef4ec3987e3ea1ea0a4cb34ea2d91c4057994fbb9`. **Las sondas contra producción** (`correr_sondas.py`, 02:12 a 02:15 UTC): las **seis**, TODO CORRECTO. `sonda-disponibilidad.txt` suma la categoría entera con los **extras**, que son ficticios: cocina los agotó (200, los ids 19 a 22, los que estaban disponibles); la carta los mostró todos agotados y las pizzas y bebidas, intactas; una venta con un extra, 409 `PRODUCTO_NO_DISPONIBLE`; agotarlos otra vez, 200 sin cambios; recepción repuso los 4; una categoría que no existe, 400 `DISPONIBILIDAD_INVALIDA`; sin token, 401. Cada extra quedó como estaba, la *Gaseosa 2 L* disponible y el pedido de prueba 480, cancelado. `sonda-errores.txt`: **21 de 21**, con la categoría inexistente. La propagación no se volvió a medir: el aviso de la categoría viaja por el mismo canal y las mismas salas que el de la fase C (máximo de 164 ms en 30 mediciones). **El *Release*:** el autor publicó `apk-cocina-0.3.0` desde la web de GitHub, sobre `main`, marcado *Latest*, con la huella en la descripción. Verificado en la API pública: `max-pizzapp-cocina.apk` pesa 54 464 971 bytes y su `digest` es la misma SHA-256; el enlace de Moodle (`…/releases/latest/download/max-pizzapp-cocina.apk`) entrega ese mismo archivo, con la misma huella |
| D — La prueba del autor | ⏳ | | |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-04 | Versión inicial propuesta | El negocio va a probar el sistema en el local y necesita controlar lo que no hay. La tarjeta 13 espera la prueba de la encargada (miércoles 7), y esta se jala mientras tanto (como en D-23) |
| 2026-10-04 | **Aprobado** por el autor, sin cambios | Decisiones D-66 a D-69 registradas en la bitácora |
| 2026-10-04 | Fase B: la `Carta` avisa sus cambios y se actualiza en el lugar; las pestañas de recepción suben a la barra desde 1200 px (antes, 1100); el botón *Carta* lleva texto desde 1700 px en recepción y desde 600 px en cocina | La venta en curso está atada a la carta, y reemplazarla la reiniciaba. Con el botón nuevo, a 1100 y a 1400 px las pestañas de recepción no entraban en la barra (lo encontraron las pruebas de anchos) |
| 2026-10-04 | Fase C: en producción el **4-oct desde las 18:40**, dentro del horario del local, y el APK sube a **0.2.0+2** | El autor confirmó que ese día el local no atendía. Es el mismo criterio que D-61: la regla protege el servicio, no el reloj, y la hora real queda en los reportes |
| 2026-10-04 | **Revisión aprobada por el autor:** agotar o reponer una categoría entera (D-70) y la venta sin pizzas (D-71), en las fases B2 y C2, antes de su prueba. Límite: unas 4 horas; si no alcanza, queda como recomendación | El autor preguntó qué pasa si se acaba la masa: con lo de la fase B eran quince interruptores y quince avisos. Lo aprobó con "lo comencemos ahorita" y fijó tener todo listo el jueves 8, con la defensa el lunes 12 |

---

## 11. Cierre

*(Se completa al cerrar la tarjeta: commits de cada fase y estado final.)*
