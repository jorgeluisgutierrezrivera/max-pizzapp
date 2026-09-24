# Plan 05 — La carta y la venta en recepción

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 05 — La carta y la venta en recepción
- **Incremento:** pedidos sobre la URL pública
- **Estado:** 🟡 **Revisión 2 propuesta** — pendiente de aprobación. La versión 1 se aprobó el
  2026-09-23; sus fases A, B y C se hicieron y subieron, y la pantalla de su fase D **no se
  aprobó** (ver la sección 10)
- **Entrada al tablero:** 2026-09-23
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

> **Qué cambió en la revisión 2 y por qué.** Al ver la pantalla de la versión 1, el autor la
> rechazó. Mostraba todas las combinaciones de mitades con sus sumas, y eso le daba a la
> vendedora más información de la que necesita y más ocasiones de equivocarse. Además, la
> dueña precisó cómo vende el local, y dos supuestos de la versión 1 resultaron falsos:
> **no se venden medias pizzas** y **la carta no se agrupa por gama**. La revisión 2 trae
> tres cosas: la venta como un **recorrido guiado** de una pregunta por paso, la **carta
> real** del local y su **identidad visual**. Lo ya subido (`05-1` a `05-3`) no se borra: la
> migración nueva lo ajusta, y el historial muestra cómo el modelo siguió a la regla del
> negocio a medida que se precisó.

---

## 1. Objetivo

Que la vendedora registre una venta **sin pensar en el sistema**, respondiendo una pregunta
a la vez, en el orden en que se lo pide el cliente en el mostrador:

1. ¿Cuántas pizzas? *(o solo bebidas)*
2. Si son varias: ¿todas iguales?
3. ¿Un sabor o mitad y mitad?
4. El sabor, o las dos mitades.
5. ¿Algún extra?
6. Si son distintas: ¿cuántas de esta? *(hasta completar la cantidad)*
7. Las bebidas.
8. Una observación para cocina ("sin cebolla").
9. El resumen, con el total.

Todo con **la carta real** de Max's Pizzas y con **su identidad visual**: su logo, su paleta
negra, amarilla y roja, y un tema oscuro pensado para un local que trabaja de noche.

El pedido armado **todavía no se envía a cocina**: el botón *Terminar venta* lo conecta la
tarjeta 06, que agrega el `POST`, el precio calculado por el servidor y la cola de cocina.

---

## 2. Alcance

**Incluye:**

- **El modelo ajustado a la regla real (D-27)**, en una migración nueva, la `04`. Solo
  pizzas enteras: se quitan la porción, la gama y el precio de media que agregó la `02`. Se
  agregan los **extras** (D-28) y la **descripción** de cada producto.
- **La carta real:** las 15 pizzas del catálogo del local, con sus ingredientes y precios,
  que están por confirmar con la dueña. Las **bebidas** y los **extras** siguen siendo
  ficticios hasta tener los reales.
- **Una ilustración dibujada por pizza**, hasta que lleguen las fotos reales. Las fotos las
  reemplazan cambiando solo los archivos.
- **`GET /api/v1/productos` ajustado:** sin gama ni precio de media, con descripción, con la
  categoría `extra` y la carta en orden alfabético.
- **La identidad visual (D-29):** logo, paleta, tema oscuro fijo, ícono de la pestaña y
  pantalla de acceso.
- **El recorrido guiado de la venta (D-30)**, con los cuatro estados de una pantalla con datos
  (cargando, vacía, error con Reintentar y con datos), adaptable a tableta, celular y
  escritorio.

**No incluye:**

- Enviar el pedido, el precio que se cobra y la cola de cocina: tarjeta 06.
- Marcar un producto agotado: tarjeta 08. Esta tarjeta sí **muestra** los agotados, que no
  se pueden elegir.
- Las fotos reales: entran cuando el autor las consiga, sin tocar el código.
- Promociones y combos: fuera de alcance (D-26).

---

## 3. Decisiones de diseño

1. **Solo pizzas enteras, y la mitad vale exactamente la mitad (D-27, reemplaza a D-25).**
   Confirmado por la dueña: un único tamaño y solo enteras; la compra puede ser **solo de
   bebidas**. Una entera puede ser de **un sabor** o de **dos mitades de sabores distintos**.
   **Precio:**
   - una pizza de un sabor cuesta su precio;
   - una de dos mitades cuesta **(precio A + precio B) / 2**, al centavo (Salame 45 con
     Peperoni 50 = **Bs 47,50**);
   - cada extra suma su precio, **uno solo** para cualquier pizza;
   - una bebida cuesta su precio.

   El precio de media deja de ser un dato: es siempre la mitad exacta, y guardarlo aparte
   solo abriría la puerta a que no coincida.

2. **El modelo sigue con cinco entidades.** La migración `04`:
   - **Quita** de `producto` la gama y el precio de media, con sus tipos y restricciones.
     Quita de `detalle_pedido` la porción: ya no hay nada que elegir.
   - **Mantiene** la segunda mitad (`producto_mitad_id`) y la regla de que las dos mitades
     sean distintas.
   - **Agrega** la categoría `extra`, la **descripción** de cada producto (sus ingredientes,
     que la vendedora ve al elegir) y, en `detalle_pedido`, `linea_de_id`. Un extra es una
     línea colgada de la línea de su pizza; se borra con ella.
   - **Corrige** el comentario de la tabla `producto`, que decía el nombre viejo del local.

   La `02` no se edita: ya está en el historial y aplicada en la base local. En producción
   corren la `02` y la `04` seguidas, y el resultado es el mismo que en una instalación
   nueva.

3. **La carta es un archivo de datos, no una migración.** `05_carta.sql` reemplaza a
   `03_carta_ficticia.sql`, que se elimina. Tiene que correr **después** de la `04`, porque
   usa la categoría `extra` y la descripción. Sigue siendo repetible
   (`ON CONFLICT (nombre)`) y no revive agotados. Su cabecera dice qué es real y qué es
   ficticio: las pizzas son del catálogo, con precios por confirmar; las bebidas y los
   extras son inventados.

4. **Las ilustraciones, dibujadas por el script hasta que haya fotos.** `dibujar-carta.py`
   dibuja las 15 pizzas con sus ingredientes (salame, choclo, champiñones, carne, chorizo,
   albahaca…), y las dos y tres estaciones por sectores. Se quitan los dibujos de pizzas que
   no están en la carta real. La base sigue guardando solo el nombre del archivo, y la
   restricción ya admite `.jpg` y `.webp` para las fotos.

5. **Una sola lista de sabores, en orden alfabético, sin grupos.** Lo pidió el autor. Con 15
   pizzas, el orden alfabético es el más rápido cuando el cliente dice un nombre. Cada sabor
   muestra su dibujo, su nombre, sus ingredientes en letra chica y **un solo precio**: el
   que corresponde a ese paso. En "un sabor", el precio de la pizza; al elegir una mitad, el
   de esa mitad.

6. **El recorrido: una pregunta por pantalla, siempre hacia adelante (D-30).**
   - **La cantidad es libre**, con − / + y el teclado, de 1 a 50. El techo solo ataja un
     error de tipeo (200 en vez de 20).
   - **"¿Todas iguales?"** Si la respuesta es sí, la pizza se define una vez y vale para
     todas: 20 pizzas iguales llevan el mismo tiempo que una. Si es no, cada pizza definida
     pregunta **"¿cuántas de esta?"**, con el atajo "las N que faltan", y una barra muestra
     **"faltan X de N"**. Con una sola pizza no se pregunta.
   - En cada paso, arriba, **dónde está** ("Pizza · Mitad y mitad · Segunda mitad") y
     **Volver**. En la segunda mitad ya no aparece el sabor de la primera.
   - **Solo bebidas** es un botón del primer paso, que salta directo a las bebidas.
   - **El resumen** permite quitar un grupo, cambiar su cantidad y **agregar más pizzas**. La
     venta necesita al menos un producto.
   - **El total siempre a la vista:** a la derecha en pantallas anchas, abajo en las
     angostas.
   - **Sin sugerencias de mezclas ni listas de combinaciones.**

7. **La identidad visual del local (D-29), con su permiso.**
   - **Tema oscuro fijo:** fondo carbón `#141414`, **amarillo `#FAF126`** para las acciones
     principales, con texto negro, **rojo `#F90304`** solo para *Terminar venta* y los
     avisos, y texto blanco.
   - **El logo** va en la barra, en la pantalla de acceso y como ícono de la pestaña y de la
     app instalada.
   - **La distinción no se rompe:** el software se llama **Max Pizzapp**; el local, **Max's
     Pizzas**.

8. **La regla de precio vive una vez en cada lado, con la misma tabla de casos.** En la app,
   una función pura calcula la vista previa en **centavos enteros**; en el servidor, la
   tarjeta 06 calcula el precio que se guarda. Las dos se prueban con la tabla de la
   sección 6. Si alguna vez difieren, manda el servidor.

---

## 4. Fases y checklist

### Fases A, B y C — versión 1 ✅ *(hechas y subidas: `05-1`, `05-2`, `05-3`)*
El modelo de porciones, la carta ficticia y la ruta de la carta. Su evidencia está en la
sección 9. Lo que de ellas cambia, lo ajustan las fases A2, B2 y C2.

### Fase A2 — El modelo ajustado a la regla real
- [ ] `04_solo_enteras_y_extras.sql`: quita porción, gama y precio de media; agrega `extra`,
      `descripcion` y `linea_de_id`; repetible sin errores.
- [ ] Probado en una instalación nueva (`00` a `05`) y sobre la base local, que ya tiene la
      `02`.
- [ ] La base rechaza lo imposible: dos mitades iguales, un extra colgado de sí mismo, una
      descripción vacía o larga.

### Fase B2 — La carta real y sus dibujos
- [ ] `05_carta.sql`: 15 pizzas reales, 3 bebidas y 4 extras ficticios; repetible; no revive
      agotados. Se elimina `03_carta_ficticia.sql`.
- [ ] 15 dibujos de pizza con sus ingredientes; se quitan los que ya no van.

### Fase C2 — La API ajustada
- [ ] `GET /api/v1/productos`: descripción, categoría `extra`, orden alfabético, sin gama ni
      precio de media.
- [ ] Pruebas automáticas y la sonda real actualizadas; la Tabla 12 del 2.4, también.

### Fase D1 — La identidad visual
- [ ] Tema oscuro fijo con la paleta, el logo en la barra y en el acceso, e íconos de la app
      hechos a partir del logo.

### Fase D2 — El recorrido guiado
- [ ] Los nueve pasos de la sección 1, con Volver, "dónde está" y el total a la vista.
- [ ] Cantidad libre, "¿todas iguales?", "¿cuántas de esta?", solo bebidas y resumen
      editable.
- [ ] Los cuatro estados y adaptable a tableta, celular y escritorio.

### Fase E — En producción
- [ ] Migraciones `02` y `04` y la carta `05` aplicadas en la base de producción, en ese
      orden.
- [ ] La API reconstruida y la app publicada: **comprobar que la versión nueva llega sola al
      navegador**, lo que quedó pendiente en la tarjeta 04.

### Fase F — Pruebas
- [ ] La regla de precio con la tabla de la sección 6.
- [ ] Pruebas de *widgets* de cada paso del recorrido.
- [ ] Recorrido del autor en el navegador y desde el celular.

---

## 5. Archivos que se tocan / crean

- `docker/postgres/init/04_solo_enteras_y_extras.sql` y `05_carta.sql` *(nuevos)*;
  `03_carta_ficticia.sql` *(se elimina)*
- `scripts/dibujar-carta.py` y `frontend/web/carta/` *(los 15 dibujos; se quitan los que ya
  no van)*
- `backend/src/rutas/productos.js`, `backend/test/productos.test.js`,
  `pruebas/api/probar_carta.py`
- `frontend/lib/` *(tema, logo, carta, regla de precio, recorrido)*, `frontend/web/`
  *(íconos y manifiesto)*, `frontend/test/`
- `README.md` *(el orden de las migraciones y la carta)*

---

## 6. Cómo se prueba

**La regla de precio**, con la carta real. Es la misma tabla que usa el servidor en la
tarjeta 06:

| Venta | Total |
|---|---|
| 1 Peperoni | 50 |
| 1 mitad Salame, mitad Peperoni | (45 + 50) / 2 = **47,50** |
| 1 mitad Carnívora, mitad Criolla / Española | (60 + 65) / 2 = **62,50** |
| 2 mitad Salame, mitad Peperoni | 2 × 47,50 = **95** |
| 1 Hawaiana con extra queso (8) | 50 + 8 = **58** |
| 3 Choclo iguales, cada una con extra choclo (5) | 3 × (45 + 5) = **150** |
| Solo 2 gaseosas (18) | **36** |
| Mitades del mismo sabor | **rechazada**: es una pizza de un sabor |
| La otra mitad no es una pizza | **rechazada** |
| Un extra sin pizza | **rechazada** |
| Venta sin ningún producto | **rechazada** |

**La base:** instalación nueva y repetible, casos válidos e imposibles, como en la fase A.

**La API:** las pruebas automáticas de la tarjeta 03 ampliadas, y la sonda contra la base
real.

**En el navegador:** con `recepcion.demo`, estas ventas completas, comprobando el total:
- 20 pizzas "sabores distintos" en tres grupos;
- 3 pizzas iguales con un extra;
- una mitad y mitad;
- solo bebidas.

Y en el celular, que todo se acomode.

---

## 7. Criterios de aceptación

- La vendedora completa una venta respondiendo **una pregunta por pantalla**, sin listas de
  combinaciones.
- 20 pizzas iguales se registran con los **mismos pasos** que una.
- Se puede vender **solo bebidas**; no se puede terminar una venta vacía.
- El total calcula **exactamente** la tabla de la sección 6, con la mitad exacta.
- La carta real, en orden alfabético, con sus dibujos e ingredientes; los agotados no se
  pueden elegir.
- La app lleva el logo y la paleta del local, en tema oscuro.
- Una versión nueva de la app llega al navegador **sin borrar la caché**.
- Ninguna imagen ni dirección completa guardada en la base.

---

## 8. Requisitos que cubre

- **Del sistema:** **RF-02** (registrar pedido), en su parte de pantalla; el envío es la
  tarjeta 06. **RNF-04** (adaptable).
- **Institucionales:** **#3** (persistencia: la carta sale de la base) y **#8** (validación
  en cliente y servidor).
- **De la entrega:** la pantalla principal del **E2**, *"con datos reales de la API,
  estados de carga, vacío y error"*.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El modelo *(versión 1)* | ✅ Verificada · ajustada por A2 | 2026-09-23 | **Instalación nueva** en un PostgreSQL 17 descartable: corren `00`, `01` y `02` en orden y sin errores; quedan las 5 columnas nuevas, las **6 restricciones** y **5 tablas**, las mismas cinco entidades. **Repetible:** una segunda ejecución de `02` termina con código 0. **Casos, uno por uno:** se aceptan las 4 líneas válidas (entera de un sabor, media, entera de dos mitades, bebida sin porción) y se **rechazan las 9 imposibles**, cada una por su restricción: media con dos sabores, dos mitades iguales, pizza sin gama, pizza sin precio de media, bebida con gama, imagen con una ruta, imagen con una dirección, precio de media negativo, y borrar un producto que figura **solo como segunda mitad** (`detalle_pedido_mitad_fk`, probado aparte). **Base local existente:** migración aplicada a mano con `psql`, 6 restricciones presentes, backend sano. Producción: en la fase E |
| B — La carta ficticia y sus ilustraciones *(versión 1)* | ✅ Verificada · reemplazada por B2 | 2026-09-23 | **Carta:** 12 productos (5 tradicionales, 4 premium, 3 bebidas). **Instalación nueva** en un PostgreSQL 17 descartable: corren `00` a `03` en orden y sin errores. **Repetible:** aplicada dos veces sobre la base local, siguen siendo 12, sin duplicados (`ON CONFLICT (nombre)`). **No revive agotados:** con la hawaiana marcada no disponible, recargar la carta la deja no disponible. **Ilustraciones:** 12 PNG de 600 × 600 con fondo transparente, entre 6 y 37 KB, dibujadas por `scripts/dibujar-carta.py` con formas simples y sin imágenes de terceros; dos ejecuciones dan archivos idénticos byte a byte. La etiqueta de la gaseosa se rediseñó para que no recordara a ninguna marca real |
| C — La API *(versión 1)* | ✅ Verificada · ajustada por C2 | 2026-09-23 | **`npm test`: 40 de 40** (16 del acceso y **24 nuevas** de la carta). Con una base simulada que anota cada consulta se comprueba *qué llega a la base*: sin token (401) o sin rol (403) la base ni se consulta; los filtros viajan como **parámetros** y el texto SQL es **el mismo** con o sin filtros; los **9 filtros inválidos**, entre ellos un intento de inyección, responden **400 `FILTRO_INVALIDO` sin tocar la base**; base caída, pool agotado y base reiniciándose dan **503**, y un error de SQL da 500 sin su texto. **Contra el esquema real** (`pruebas/api/probar_carta.py`, tokens reales de los dos roles): la carta completa, en orden, filtros correctos y 400 a `?categoria=pasta`. **Casos reales:** con la hawaiana agotada, `?disponible=false` la devuelve; con el contenedor de la base **detenido**, la API responde **503 `BASE_NO_DISPONIBLE`** a los ~5 s y se recupera sola al volver la base |
| D — La pantalla de recepción *(versión 1)* | ❌ **No aprobada por el autor** · no se subió | 2026-09-23 | Se construyó y probó (77 pruebas en verde, recorrida en el navegador), y **el autor la rechazó al verla**: al elegir una pizza mostraba todas las combinaciones de mitades con sus sumas, y eso es demasiada información para la vendedora, que se equivocaría más de lo que acertaría. Además, la dueña precisó que no se venden medias pizzas. De esa versión se reutilizan la **regla de precio en centavos**, el patrón de los cuatro estados y dos aprendizajes de sus pruebas: un aviso emergente tapaba la barra de abajo en el celular, y a 320 px el título no cabía junto a los botones |
| A2 — El modelo ajustado | ⏳ Pendiente | — | — |
| B2 — La carta real y sus dibujos | ⏳ Pendiente | — | — |
| C2 — La API ajustada | ⏳ Pendiente | — | — |
| D1 — La identidad visual | ⏳ Pendiente | — | — |
| D2 — El recorrido guiado | ⏳ Pendiente | — | — |
| E — En producción | ⏳ Pendiente | — | — |
| F — Pruebas | ⏳ Pendiente | — | — |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-23 | Versión inicial propuesta | Primera tarjeta del CRUD del E2. Incorpora las reglas de venta que precisó el autor (D-25) |
| 2026-09-23 | **Aprobado** sin cambios | Revisado por el autor. Las promociones y los combos quedan fuera de alcance (D-26): no entran en esta tarjeta ni en el modelo |
| 2026-09-23 | **Pantalla de la fase D no aprobada** | Demasiada información a la vista: todas las combinaciones de mitades con sus sumas. El autor pide una venta guiada, de una pregunta por paso |
| 2026-09-23 | **Revisión 2 propuesta** | La dueña confirmó que **solo se venden pizzas enteras** (D-27, reemplaza a D-25), que la mitad vale la mitad exacta y que se puede vender **solo bebidas**. Se suman los **extras** (D-28), la **identidad visual** del local, con su nombre oficial **Max's Pizzas** (D-29), el **recorrido guiado** (D-30) y la **carta real** del catálogo, sin grupos |

---

## 11. Cierre

- **Commits que cierran la tarjeta:** —
- **Fecha de cierre:** —
