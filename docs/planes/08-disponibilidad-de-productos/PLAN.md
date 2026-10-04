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
- [ ] La instalación local en un paso sigue en verde en la integración continua.

### Fase C — En producción
- [ ] El autor despliega la API (`git pull` y `up -d --build`). **No hay migración.**
- [ ] La app web publicada (`scripts/publicar-web.sh`).
- [ ] El APK 0.2.0 compilado y firmado; el autor crea el *Release* `apk-cocina-0.2.0`.
- [ ] Las sondas contra producción, con un producto **ficticio** (una bebida), fuera del
      horario de atención (antes de las 18:00), y dejándolo como estaba:
  - marcar y reponer con cada cuenta;
  - 401, 403, 400 y 404;
  - la propagación hasta la otra pantalla, **30 mediciones** (como el RNF-01).

### Fase D — La prueba del autor y el cierre
- [ ] El autor, con recepción en la computadora y cocina en el APK:
  - cocina marca una pizza agotada y recepción la ve apagada al instante, con el aviso;
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
| C — En producción | ⏳ | | |
| D — La prueba del autor | ⏳ | | |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-04 | Versión inicial propuesta | El negocio va a probar el sistema en el local y necesita controlar lo que no hay. La tarjeta 13 espera la prueba de la encargada (miércoles 7), y esta se jala mientras tanto (como en D-23) |
| 2026-10-04 | **Aprobado** por el autor, sin cambios | Decisiones D-66 a D-69 registradas en la bitácora |
| 2026-10-04 | Fase B: la `Carta` avisa sus cambios y se actualiza en el lugar; las pestañas de recepción suben a la barra desde 1200 px (antes, 1100); el botón *Carta* lleva texto desde 1700 px en recepción y desde 600 px en cocina | La venta en curso está atada a la carta, y reemplazarla la reiniciaba. Con el botón nuevo, a 1100 y a 1400 px las pestañas de recepción no entraban en la barra (lo encontraron las pruebas de anchos) |

---

## 11. Cierre

*(Se completa al cerrar la tarjeta: commits de cada fase y estado final.)*
