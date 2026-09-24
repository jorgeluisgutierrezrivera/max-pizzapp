# Plan 05 — La carta y la pantalla de recepción

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 05 — La carta y la pantalla de recepción
- **Incremento:** pedidos sobre la URL pública
- **Estado:** 🟢 Aprobado — aprobado el 2026-09-23, sin cambios sobre lo propuesto
- **Entrada al tablero:** 2026-09-23
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que la recepción vea **la carta del local** en su pantalla —pizzas tradicionales, pizzas
premium y bebidas, con su ilustración y sus precios— y **arme un pedido** como se vende en
Max Pizzas: pizzas enteras o medias, y enteras de **dos mitades** de sabores distintos, con
el total calculado según la regla del local.

El pedido armado **todavía no se envía a cocina**: eso es la tarjeta 06, que agrega el
`POST` y la cola. Esta tarjeta deja la carta servida por la API y la pantalla que la usa.

---

## 2. Alcance

**Incluye:**

- **La regla de porciones en el modelo** (D-25), como una migración numerada: gama, precio de
  media e imagen en `producto`; porción y segunda mitad en `detalle_pedido`.
- **Una carta ficticia** como datos iniciales, con precios plausibles, hasta que llegue la
  carta real.
- **Ilustraciones propias** de cada producto, dibujadas para el proyecto, hasta que lleguen
  las fotos del local.
- **`GET /api/v1/productos`**, con filtros por categoría y disponibilidad.
- **La pantalla de recepción:** la carta agrupada, con los cuatro estados (cargando, vacío,
  error y con datos).
- **El armado del pedido en pantalla:** elegir entera o media, sumar una segunda mitad,
  cantidades, quitar líneas y ver el total.

**No incluye (llega en tarjetas posteriores):**

- Enviar el pedido y la cola de cocina: tarjeta 06. Ahí el **servidor** calcula y guarda el
  precio; el de esta pantalla es una vista previa.
- Marcar un producto como agotado: tarjeta 08. Esta tarjeta sí **muestra** los agotados.
- La carta y las fotos reales: se reemplazan cuando lleguen, sin tocar el código.

---

## 3. Decisiones de diseño

1. **Las reglas de venta, en la base y en el servidor (D-25).** Un solo tamaño, entera o
   media; cada pizza con su precio de entera y de media; la media es de un sabor; la entera
   puede tener dos mitades de sabores distintos, de cualquier gama. **Precio:** entera de un
   sabor = su precio de entera; entera de dos mitades = suma de los precios de media; media =
   su precio de media. Premium y tradicional agrupan la carta; no fijan el precio.

2. **Cinco entidades, como promete el objetivo 2 del perfil.** La regla se resuelve con
   columnas, no con tablas nuevas. Una pizza nunca tiene más de dos sabores, así que la
   segunda mitad es **una columna opcional** en `detalle_pedido`. La base impide lo
   imposible: una media con dos sabores, dos mitades iguales, una pizza sin gama o sin precio
   de media, una bebida con gama. Lo que cruza tablas —que la mitad sea una pizza— lo valida
   el servidor en la tarjeta 06.

3. **Una migración numerada, no una edición del esquema original.** `02_porciones_y_carta.sql`
   corre después de `01_schema.sql` en una instalación nueva. En producción, donde la base ya
   existe, se aplica **una vez** con `psql`. Está escrita para que ejecutarla dos veces no
   rompa nada. El historial muestra que el modelo cambió por una regla de negocio, y cuándo.

4. **La carta ficticia es un archivo aparte**, `03_carta_ficticia.sql`, marcado como tal en
   su cabecera. Se reemplaza entero por la carta real sin tocar el esquema. Los nombres son
   genéricos (pepperoni, carnívora…) y los precios, plausibles pero inventados.

5. **Las ilustraciones van con la app, no en la base.** La base guarda solo el **nombre** del
   archivo (`pepperoni.png`), nunca la imagen ni una dirección completa. Los archivos viven
   en `frontend/web/carta/`: el servidor de desarrollo los sirve, y el build los copia a
   producción, donde Caddy los entrega con la misma revalidación que el resto de la app. Una
   restricción de la base admite solo nombres simples (`^[a-z0-9-]+\.(png|jpg|webp)$`): no se
   puede colar una ruta a otro lugar. Si una imagen falta o no carga, la tarjeta muestra un
   ícono.

   **Carga en el sistema:** unas 12 imágenes de 600 × 600 px, de unos 30 KB cada una, que el
   navegador descarga una vez y después revalida. Ninguna pasa por la API ni por la base.

6. **`GET /api/v1/productos` para recepción y cocina.** La Tabla 12 del 2.4 lo daba solo a
   recepción, pero cocina también va a necesitar la carta para marcar un producto agotado
   (RF-13, tarjeta 08). **Es un ajuste del contrato** y entra a la Tabla 12 en el mismo acto.
   Los filtros se validan en el servidor (400 si no son válidos) y la consulta es
   parametrizada.

7. **La regla de precio vive una sola vez en cada lado, con la misma tabla de casos.** En la
   app, una función pura calcula el total de la vista previa; en el servidor, la tarjeta 06
   calcula el precio que se guarda. Las dos se prueban **con la misma tabla de ejemplos** de
   la sección 6, así que no pueden divergir sin que una prueba lo note. Si alguna vez
   difieren, manda el servidor.

8. **La pantalla, pensada para el mostrador.** Una grilla de tarjetas grandes, fácil de tocar
   en una tableta, que se reacomoda en el celular. La carta agrupada en el orden en que se
   pide: tradicionales, premium, bebidas. El pedido en armado queda a la derecha en pantallas
   anchas y abajo en las angostas. Los agotados se ven atenuados y no se pueden agregar.

---

## 4. Fases y checklist

### Fase A — El modelo
- [x] `02_porciones_y_carta.sql`: tipos `gama_pizza` y `porcion_pizza`, columnas y
      restricciones de D-25, repetible sin errores.
- [x] Probado sobre una base vacía (después de `01_schema.sql`) y sobre la base local actual.
- [x] Probar que la base **rechaza** lo imposible: media con dos sabores, mitades iguales,
      pizza sin gama, bebida con gama, nombre de imagen con una ruta.

### Fase B — La carta ficticia y sus ilustraciones
- [x] `03_carta_ficticia.sql`: 5 tradicionales, 4 premium y 3 bebidas, repetible sin errores.
- [x] Una ilustración por producto en `frontend/web/carta/`, dibujada para el proyecto.

### Fase C — La API
- [x] `GET /api/v1/productos` con filtros `categoria` y `disponible`, validados.
- [x] Pruebas: el listado, los filtros, un filtro inválido (400), sin token (401).
- [x] La Tabla 12 del 2.4 actualizada: roles de la ruta y cuerpo de `POST /pedidos`.

### Fase D — La pantalla de recepción
- [ ] La carta agrupada, con ilustración, precios de entera y media, y agotados atenuados.
- [ ] Los cuatro estados: cargando, vacío, error (con Reintentar) y con datos.
- [ ] El armado: entera, media, segunda mitad, cantidades, quitar y el total.
- [ ] Adaptable a la tableta, al celular y al escritorio.

### Fase E — En producción
- [ ] Migración y carta aplicadas en la base de producción.
- [ ] App publicada: **comprobar que la versión nueva llega sola al navegador**, lo que quedó
      pendiente en la tarjeta 04.

### Fase F — Pruebas
- [ ] La regla de precio con la tabla de la sección 6, en la app.
- [ ] Pruebas de *widgets* del armado del pedido.
- [ ] Recorrido en el navegador y desde el celular.

---

## 5. Archivos que se tocan / crean

- `docker/postgres/init/02_porciones_y_carta.sql` *(nuevo)*
- `docker/postgres/init/03_carta_ficticia.sql` *(nuevo)*
- `frontend/web/carta/` *(nuevo: las ilustraciones)*
- `scripts/dibujar-carta.py` *(nuevo: dibuja las ilustraciones; agregado en la fase B)*
- `backend/src/rutas/productos.js` *(nuevo)*, `backend/src/app.js`, `backend/src/errores.js` *(el 503)* y `backend/test/` *(`productos.test.js` nuevo; el emisor de tokens de prueba pasa a `test/soporte/emisor.js`, compartido)*
- `pruebas/api/probar_carta.py` *(nuevo: la carta con token real y base real)*
- `frontend/lib/` *(modelo de producto, regla de precio, pantalla de recepción)* y
  `frontend/test/`
- `README.md` *(cómo aplicar una migración en una base existente)*

---

## 6. Cómo se prueba

**La regla de precio**, con esta tabla de ejemplos, que usan la app aquí y el servidor en la
tarjeta 06 (precios de ejemplo: pepperoni 65 entera / 35 media; carnívora 85 / 45; hawaiana
premium 80 / 42):

| Línea | Total |
|---|---|
| 1 pepperoni entera | 65 |
| 1 carnívora media | 45 |
| 1 entera mitad pepperoni, mitad carnívora | 35 + 45 = 80 |
| 1 entera mitad carnívora, mitad hawaiana | 45 + 42 = 87 |
| 2 enteras mitad pepperoni, mitad carnívora | 2 × 80 = 160 |
| Mitades del mismo sabor | **rechazada**: es una entera de un sabor |
| Media con dos sabores | **rechazada** |

**La base:** que acepte los casos válidos y rechace los imposibles (fase A).

**La API:** automáticas, como en la tarjeta 03.

**En el navegador:** con `recepcion.demo`, la carta completa con sus ilustraciones; armar un
pedido con una media, una entera y una entera de dos mitades, y comprobar el total; en el
celular, la carta y el pedido se acomodan.

---

## 7. Criterios de aceptación

- La base **rechaza** una media con dos sabores, dos mitades iguales y una pizza sin precio de
  media.
- `GET /api/v1/productos` devuelve la carta con gama, precios e imagen; filtra; responde 400
  a un filtro inválido y 401 sin token.
- La pantalla de recepción muestra la carta agrupada con sus ilustraciones y los cuatro
  estados.
- El armado calcula **exactamente** la tabla de la sección 6.
- Una versión nueva de la app llega al navegador **sin borrar la caché**.
- Ninguna imagen ni dirección completa guardada en la base.

---

## 8. Requisitos que cubre

- **Del sistema:** **RF-02** (registrar pedido), en su parte de pantalla: la carta y el armado.
  El envío es la tarjeta 06. **RNF-04** (adaptable).
- **Institucionales:** **#3** (persistencia: la carta sale de la base) y **#8** (validación
  en cliente y servidor: filtros validados, combinaciones imposibles rechazadas).
- **De la entrega:** la primera pantalla real del **E2**: *"pantallas principales con datos
  reales de la API, estados de carga, vacío y error"*.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El modelo | ✅ Verificada | 2026-09-23 | **Instalación nueva** en un PostgreSQL 17 descartable: corren `00`, `01` y `02` en orden y sin errores; quedan las 5 columnas nuevas, las **6 restricciones** y **5 tablas**, las mismas cinco entidades. **Repetible:** una segunda ejecución de `02` termina con código 0. **Casos, uno por uno:** se aceptan las 4 líneas válidas (entera de un sabor, media, entera de dos mitades, bebida sin porción) y se **rechazan las 9 imposibles**, cada una por su restricción: media con dos sabores, dos mitades iguales, pizza sin gama, pizza sin precio de media, bebida con gama, imagen con una ruta, imagen con una dirección, precio de media negativo, y borrar un producto que figura **solo como segunda mitad** (`detalle_pedido_mitad_fk`, probado aparte). **Base local existente:** migración aplicada a mano con `psql`, 6 restricciones presentes, backend sano. Producción: en la fase E |
| B — La carta ficticia y sus ilustraciones | ✅ Verificada | 2026-09-23 | **Carta:** 12 productos (5 tradicionales, 4 premium, 3 bebidas) con los precios de la tabla de la sección 6 para pepperoni, carnívora y hawaiana. **Instalación nueva** en un PostgreSQL 17 descartable: corren `00` a `03` en orden y sin errores, y quedan 5 + 4 + 3 productos. **Repetible:** aplicada dos veces sobre la base local, termina con código 0 y siguen siendo 12, sin duplicados (`ON CONFLICT (nombre)`). **No revive agotados:** con la hawaiana marcada no disponible, recargar la carta la deja no disponible. Todas las filas pasan las restricciones de la fase A. **Ilustraciones:** 12 PNG de 600 × 600 con fondo transparente, entre 6 y 37 KB (unos 330 KB en total), dibujadas por `scripts/dibujar-carta.py` con formas simples y sin imágenes de terceros. Dos ejecuciones dan archivos idénticos byte a byte. La etiqueta de la gaseosa se rediseñó para que no recordara a ninguna marca real |
| C — La API | ✅ Verificada | 2026-09-23 | **`npm test`: 40 de 40** (16 del acceso, que siguen igual tras mover el emisor de prueba a `test/soporte/`, y **24 nuevas** de la carta). Con una base simulada que anota cada consulta se comprueba *qué llega a la base*: sin token (401) o sin rol (403) la base ni se consulta; los filtros viajan como **parámetros** y el texto SQL es **el mismo** con o sin filtros; los **9 filtros inválidos** (categoría inexistente, con mayúsculas, un intento de inyección, repetida, vacía, `disponible=si`, `disponible=1`, un filtro desconocido y uno con corchetes) responden **400 `FILTRO_INVALIDO` sin tocar la base**; base caída, pool agotado y base reiniciándose dan **503**, y un error de SQL da 500 sin su texto. **Contra el esquema real** (`pruebas/api/probar_carta.py`, tokens reales de `recepcion.demo` y `cocina.demo`): los dos roles leen la carta, 12 productos en el orden de la carta, precios numéricos, imágenes con nombre simple, filtros correctos y 400 a `?categoria=pasta`. **Casos reales:** con la hawaiana agotada, `?disponible=false` la devuelve y la carta completa la incluye atenuable; con el contenedor de la base **detenido**, la API responde **503 `BASE_NO_DISPONIBLE`** a los ~5 s (el límite del pool) y se recupera sola al volver la base. **Contrato:** la ruta pasa a recepción **y cocina**, suma el 400 y el 503; Tabla 12 del borrador 2.4 y `BRIEF.md` actualizados |
| D — La pantalla de recepción | ⏳ Pendiente | — | — |
| E — En producción | ⏳ Pendiente | — | — |
| F — Pruebas | ⏳ Pendiente | — | — |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-23 | Versión inicial propuesta | Primera tarjeta del CRUD del E2. Incorpora las reglas de venta que precisó el autor (D-25) |
| 2026-09-23 | **Aprobado** sin cambios | Revisado por el autor. Las promociones y los combos quedan fuera de alcance (D-26): no entran en esta tarjeta ni en el modelo |

---

## 11. Cierre

- **Commits que cierran la tarjeta:** —
- **Fecha de cierre:** —
