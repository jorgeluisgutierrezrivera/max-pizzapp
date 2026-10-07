# Plan 14 — Las bebidas reales

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 14 — Las bebidas reales
- **Incremento:** semana del E4 (cierre)
- **Estado:** ✅ **Hecho** — cerrada el 2026-10-07, en producción y probada por el autor.
  Aprobada ese mismo día con la corrección del autor (segunda versión del día: ver
  *Revisiones*)
- **Entrada al tablero:** 2026-10-07, a pedido del autor. Entra mientras la 13 espera la prueba
  de la encargada y la 08 la prueba del autor (D-23)
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que la carta tenga **las bebidas que de verdad vende el local, con sus precios**, nombradas como
se venden en el mostrador.

Las tres bebidas de hoy son **ficticias** (`05_carta.sql`): *Agua mineral 600 ml*, *Gaseosa 2 L*
y *Jugo natural 1 L*. El autor dio la lista real el 7-oct:

| Bebida | Precio |
|---|---|
| Agua 500 ml (la pequeña) | Bs 6 |
| Jugo 1 L | Bs 15 |
| Soda personal (la *mini*, de menos de 200 ml) | Bs 3 |
| Soda 1 L | Bs 10 |
| Soda 1,5 L | Bs 15 |
| Soda 2 L | Bs 20 |

**Cómo se venden, según el autor:**

- Las bebidas las tiene y las sirve **la recepcionista**; las pizzas salen de cocina.
- La vendedora **registra la bebida y la entrega al instante**. Recién al entregarla le pregunta
  al cliente si quiere Coca-Cola, Fanta o Sprite, y en el jugo, el sabor.
- **Lo que tiene que quedar registrado es que se vendió una soda y de qué tamaño**, dentro del
  pedido, con su precio. La marca y el sabor no.

**Lo que ya existe**, y no se toca:

- la categoría `bebida`;
- las bebidas dentro del pedido (sección *3 · Bebidas* de la venta) y en la venta directa
  (*Vender bebidas*, que nace entregada: D-38);
- agregar una bebida a un pedido hasta entregarlo (D-37);
- que cocina prepara solo las pizzas: las bebidas de un pedido las ve en una línea gris debajo
  de ellas, como referencia, y la venta directa ni le llega (D-38);
- el precio que calcula el servidor y que cada línea guarda (D-27);
- agotar y reponer una bebida desde el panel *Carta*, con los dos roles (D-66 a D-71).

---

## 2. Alcance

**Incluye:**

- **La carta real de bebidas**, en `05_carta.sql`.
- **Las tres ficticias toman su nombre y su precio reales**, sin crear productos aparte (D-73).
- **Las bebidas en el orden en que se piden**: por tipo y, dentro de cada tipo, de la más chica
  a la más grande (D-74).
- Las sondas y sus reportes, con las bebidas reales; el README y la tabla de casos del 2.8, si
  nombran las ficticias.

**No incluye:**

- **La marca ni el sabor.** No se registran: se preguntan al entregar (D-72).
- **Cambios en la base, en la API o en el contrato.** Es un cambio de datos: no hay columnas ni
  rutas nuevas.
- **Un APK nuevo.** El de cocina no vende bebidas, y su panel *Carta* lee la carta de la API.
- **Precios por hora, combos, promociones o existencias.** Siguen fuera de alcance.
- **Alta y edición de productos desde la app.** Siguen siendo del administrador, fuera de
  alcance (D-13). La carta se cambia con su archivo versionado, como hasta ahora.

---

## 3. Decisiones de diseño

### D-72 · Bebidas genéricas: agua, jugo y soda, y la soda por tamaño

- **Seis productos:** *Agua 500 ml*, *Jugo 1 L*, *Soda personal (mini)*, *Soda 1 L*, *Soda 1,5 L*
  y *Soda 2 L*.
- **La marca de la soda y el sabor del jugo no se registran.** La vendedora los pregunta al
  entregar, que es en el momento de la venta.
- **Por qué:**
  - lo que el local necesita saber es qué se vendió y a cuánto. El precio depende del tamaño,
    no de la marca;
  - la bebida se entrega en el acto. Registrar la marca obligaría a preguntarla antes de
    cobrar, y el mostrador se haría más lento;
  - con seis bebidas, la sección *3 · Bebidas* sigue entrando en el formulario: dos filas de
    tres a 1366 × 768 (D-36, RNF-04). Con una bebida por marca y sabor serían más de quince, y
    habría que rediseñar la venta.
- **Se descartó** un producto por marca y tamaño (*Coca-Cola 2 L*, *Fanta 2 L*…), que fue la
  primera versión de este plan.

### D-73 · Las tres ficticias toman su nombre real, sin crear productos aparte

| Hoy (ficticia) | Pasa a ser | Precio |
|---|---|---|
| Agua mineral 600 ml | Agua 500 ml | Bs 6 (igual) |
| Jugo natural 1 L | Jugo 1 L | Bs 15 (igual) |
| Gaseosa 2 L | Soda 2 L | de Bs 18 a Bs 20 |

Las otras tres sodas (*personal*, *1 L* y *1,5 L*) son productos nuevos.

- **Por qué:** eran **el mismo producto con un nombre provisional**: el agua pequeña, el jugo y
  la soda de dos litros.
  - Crearlos aparte dejaría dos productos para la misma bebida.
  - La base tampoco deja borrar los viejos, porque hay pedidos que los nombran
    (`ON DELETE RESTRICT`).
- **Los pedidos que ya los llevan siguen diciendo lo que se cobró.** Cada línea guarda su
  precio (D-27): una *Soda 2 L* vendida a Bs 18 sigue costando Bs 18 en ese pedido, y la carta
  dice Bs 20 desde ahora. Es lo que el esquema prevé para un cambio de precio.
- **`05_carta.sql` se puede seguir ejecutando las veces que haga falta.** Primero renombra,
  y solo lo que todavía tiene el nombre viejo. Después carga la carta como siempre, sin
  duplicar nada. En una instalación nueva no hay nada que renombrar. Producción y una
  instalación nueva terminan con la misma carta.
- **Se descartó** retirar las ficticias con una columna nueva (`retirado_en`), también de la
  primera versión. Tenía sentido cuando la Gaseosa 2 L iba a convertirse en una marca; con
  nombres genéricos, la soda de dos litros sigue siendo la misma.

### D-74 · Las bebidas, en el orden en que se piden

- **Hoy la carta las ordena por nombre**, y la *Soda personal* quedaría última, detrás de la
  de 2 litros.
- **Pasan a ordenarse por tipo** (la primera palabra: Agua, Jugo, Soda) **y, dentro de cada
  tipo, por precio**, que en las sodas es lo mismo que el tamaño:

  ```
  Agua 500 ml · Jugo 1 L · Soda personal (mini) · Soda 1 L · Soda 1,5 L · Soda 2 L
  ```

- **Solo las bebidas:** las pizzas y los extras siguen por nombre, que es como se buscan (D-30).
- **Mismo orden en todas las pantallas que muestran bebidas:** la venta, *Vender bebidas*,
  *Agregar* y el panel *Carta*.

### D-75 · El formulario llena la pantalla solo si las bebidas entran en dos filas (fase A)

- **Lo que encontraron las pruebas.** Con seis bebidas, la sección *3 · Bebidas* ocupa dos filas
  de tres a 1366 px. Con eso fallaron dos pruebas de la venta:
  - **a 1024 × 640**, las bebidas van de a dos y ocupan tres filas, y las pizzas se quedaron
    sin alto;
  - **a 1366 × 768 con la banda *No quedan pizzas*** (D-71), el formulario se pasó 26 px de la
    pantalla.
- **La regla:** en la computadora, el formulario ocupa la pantalla entera solo si **las
  bebidas entran en dos filas**. Si no entran, se desplaza, con el pedido al lado, como ya pasaba
  en una ventana baja. Hoy eso pasa por debajo de unos 1210 px de ancho. Si la carta crece,
  el formulario se desplaza en lugar de desbordarse.
- **La banda *No quedan pizzas*** va en el lugar de las pizzas, que se encoge si falta alto, y
  no fija arriba. *Agregar pizza* sigue a la vista y apagado, como dice D-71.
- **Se mantiene** la forma de elegir bebidas: un toque en **+** y **−** para corregir, en la
  misma pantalla.
- **Se descartó** elegirlas en una ventana aparte: entraría siempre, pero serían dos toques más
  por bebida, justo en lo que se entrega al instante.

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — La carta y el orden, en local
- [x] `05_carta.sql`: el encabezado, los tres cambios de nombre y las seis bebidas con sus
      precios.
- [x] Contra la base de desarrollo, que **ya tiene pedidos con las ficticias**:
  - se ejecuta dos veces, y la segunda no cambia nada;
  - los pedidos viejos conservan su precio (la *Soda 2 L* a Bs 18);
  - la carta tiene seis bebidas y ninguna ficticia.
- [x] Una base nueva con los scripts de inicialización, la parte de base de una instalación
      desde cero: las mismas seis bebidas. La instalación completa la prueba el flujo
      *Instalacion* de la integración continua al subir el código.
- [x] La app: el orden de las bebidas (D-74) y el formulario que llena la pantalla solo si
      entran (D-75).
- [x] Pruebas (`flutter test` y `flutter analyze`):
  - el orden;
  - la carta de prueba de la venta, con las seis bebidas reales y sus precios;
  - el formulario sin desplazarse a 1366 × 630, 1280 × 640, 1536 × 730 y 1920 × 950, y
    desplazándose a 1024 × 640;
  - RNF-04 a 1366 × 768 y 768 × 1024, también con la banda *No quedan pizzas*.
- [x] La suite de la API (`npm test`) sigue en verde. No cambia código del servidor.
- [x] Las sondas, con las bebidas reales:
  - `probar_pedidos.py`: la *Soda 2 L* a Bs 20;
  - `probar_disponibilidad.py` y `medir-aviso.js`, con la *Soda 2 L* por omisión.

  Contra la API local, en verde.

### Fase B — Producción
- [x] Fuera del horario del local (18:00 a 23:30): respaldo de la base, `05_carta.sql`
      ejecutado y la app publicada. La API no se reconstruye.
- [x] Las sondas contra producción y sus reportes regenerados: las seis, `sonda-*.txt`.

### Fase C — Prueba del autor
- [x] En producción: un pedido con pizza y tres bebidas reales, de la venta a la entrega, en
      recepción y en cocina. La venta directa, la soda agregada a un pedido *Listo* y la *Soda
      2 L* agotada quedaron probadas por las sondas (fase B).
- [x] Las capturas de la venta con las bebidas reales, para el Anexo A (`pc-01` y `pc-03`).

### Cierre
- [x] `documento/evidencia-por-tarjeta/14-bebidas-reales.md`, la fila de EMPEZAR-AQUI, TAREAS,
      la bitácora (D-72 a D-75) y `DATOS-DEL-NEGOCIO.md` con las bebidas reales.
- [x] La tarjeta en el tablero de GitHub Projects.
- [ ] El paquete para el agente documental:
  - el Anexo A: las bebidas genéricas, y que la marca se pregunta al entregar;
  - la Figura 6 y las demás capturas que muestran las ficticias;
  - lo que cambia en el 2.8.

---

## 5. Criterios de aceptación

1. La venta ofrece **seis bebidas reales con sus precios**, y ninguna ficticia.
2. **Una soda se registra por su tamaño**, sin marca, dentro del pedido o en la venta directa.
3. **Los pedidos que ya llevaban una ficticia no cambian lo que se cobró.**
4. **Las bebidas aparecen en el orden en que se piden:** agua, jugo y las sodas de menor a
   mayor.
5. El formulario de venta sigue entrando **sin desplazarse a 1366 × 768**.
6. `05_carta.sql` se puede ejecutar **dos veces sin cambiar nada** la segunda vez.

**Cómo se cumplieron, el 7-oct:**

| # | Criterio | Cumplido | Evidencia |
|---|---|---|---|
| 1 | Seis bebidas reales, ninguna ficticia | ✅ | La carta de producción (fase B) y `pc-01` |
| 2 | La soda, por tamaño y sin marca | ✅ | `pc-01`, `pc-03` y `apk-07` |
| 3 | Los pedidos viejos no cambian lo cobrado | ✅ | 67 líneas a Bs 18 en desarrollo (fase A). En producción, la Soda 2 L es el mismo producto 17 |
| 4 | El orden en que se piden | ✅ | `pc-01`, con la prueba del orden en `venta_test.dart` |
| 5 | Sin desplazarse a 1366 × 768 | ✅ | Las pruebas de RNF-04, también con la banda sin pizzas |
| 6 | `05_carta.sql`, dos veces sin cambios | ✅ | La huella de la tabla, igual antes y después (fase A) |

**Los commits:** `843f16e` (14-P), `1dbde6f` (14-1), `71ff641` (14-2) y el cierre (14-E). La
integración continua, *Pruebas* e *Instalacion*, quedó en verde en los tres primeros.

---

## 6. Riesgos

| Riesgo | Qué se hace |
|---|---|
| Cambiar el nombre a un producto ya vendido parece reescribir la historia | Lo que se cobró está en la línea, no en el producto (D-27). Se prueba con un pedido viejo antes y después (fase A) |
| Las sondas de producción esperan la *Gaseosa 2 L* a Bs 18 | Se actualizan en la fase A, antes de tocar producción |
| La carta se cambia en producción durante el servicio | Fase B fuera de 18:00 a 23:30, con respaldo antes |

---

## 7. Revisiones

- **2026-10-07, la misma mañana, con el autor:** la primera versión registraba **marca y
  sabor**. Eran unas 17 bebidas, y para eso tenía:
  - tres columnas nuevas (`grupo`, `variante`, `medida`);
  - un cuadro de marca por tamaño para elegirlas;
  - las ficticias retiradas con `retirado_en`;
  - las bebidas destacadas en la tarjeta del pedido.

  El autor la corrigió así:

  > No anotes por sabores, ni nada, que sean genéricos como jugo, soda y agua. La vendedora
  > registra la soda y la entrega al instante; al entregarla le pregunta si quiere coca,
  > fanta o sprite, pero que quede el registro de que se vendió una soda. Solo anotar qué tipo
  > de soda: personal, de litro, de litro y medio o de dos litros.

  Con eso:
  - el cambio pasa a ser **solo de datos**, más el orden de las bebidas;
  - salen las columnas, el cuadro y `retirado_en`;
  - las ficticias **toman su nombre real**;
  - la tarjeta del pedido no cambia, porque la bebida ya se entregó al venderla.

  El autor confirmó además el precio de la soda personal: Bs 3, porque es la *mini* de menos
  de 200 ml.

## 8. Evidencia

| Fase | Resultado | Estado |
|---|---|---|
| A — local | Ver el detalle debajo | ✅ 7-oct |
| B — producción | Ver el detalle debajo | ✅ 7-oct |
| C — prueba del autor | El pedido 36 en recepción (Chrome) y en cocina (APK), con las bebidas reales | ✅ 7-oct |

**Fase A, 7-oct, en local.**

- **Base de desarrollo**, con pedidos que ya llevaban las ficticias. Antes había 67 líneas de
  *Gaseosa 2 L* a Bs 18, 3 de *Agua mineral 600 ml* y 2 de *Jugo natural 1 L*. Después de
  `05_carta.sql`:
  - las tres son *Soda 2 L*, *Agua 500 ml* y *Jugo 1 L*, con el mismo número de producto;
  - la *Soda 2 L* vale Bs 20 en la carta;
  - **las 67 líneas siguen cobradas a Bs 18**;
  - se agregaron *Soda personal (mini)* (Bs 3), *Soda 1 L* (Bs 10) y *Soda 1,5 L* (Bs 15).
- **La segunda ejecución no cambió nada:** la huella de la tabla `producto`, un md5 de todas
  sus filas, fue la misma antes y después (`a98bcb2a…`, 25 productos).
- **Base nueva**, `postgres:17-alpine` con `docker/postgres/init`: se inicializó sin errores,
  con las seis bebidas y ninguna ficticia.
- **La app:** `flutter test` 338 de 338 (antes 336, más el orden de las bebidas y el formulario
  a 1024 × 640), y `flutter analyze` sin avisos.
- **La API:** `npm test` 327 de 327, sin cambios en el servidor.
- **Las sondas contra la API local:** `probar_pedidos.py` *TODO CORRECTO*, con la venta mixta
  de Bs 193 y la venta directa de 2 sodas de Bs 40. `probar_disponibilidad.py` también *TODO
  CORRECTO*, con la *Soda 2 L*.

  Los reportes versionados no se tocaron: salen de producción, en la fase B.

**Fase B, 7-oct, en producción** (antes de las 18:00, con el local sin atender).

- **10:56, el respaldo:** `/opt/respaldos/maxpizzapp-2026-10-07-1456.dump`, de 63 KB. El nombre
  lleva la hora del servidor, en UTC.
- **La carta.** El servidor ya estaba en `1dbde6f`. La carga respondió `UPDATE 3` (las tres
  ficticias renombradas) e `INSERT 0 25` (la carta completa), y la consulta mostró las seis
  bebidas, de *Soda personal (mini)* a Bs 3 hasta *Soda 2 L* a Bs 20.
- **La *Soda 2 L* de producción es el producto 17**, el mismo número que tenía la *Gaseosa 2 L*
  en el reporte del 4-oct: es el mismo producto con su nombre real (D-73).
- **11:08, la app**, publicada con `publicar-web.sh` (versión `20261007-110701`). Comprobado
  desde afuera:
  - el `main.dart.js` que sirve `maxpizzapp.tech` tiene la misma hora que la compilación local;
  - `/api/v1/salud` responde `ok`;
  - la app carga sin errores en la consola.
- **11:11 a 11:13, las sondas** (`correr_sondas.py`, corridas por el autor): las seis *TODO
  CORRECTO*, con la contraseña leída del `.env` del servidor y ningún secreto en los reportes.
  - **Pedidos:** la venta mixta de Bs 193; la venta directa de 2 sodas, de Bs 40; una soda
    agregada a un pedido pendiente (Bs 70) y a uno listo (Bs 145,50).
  - **Disponibilidad:** la *Soda 2 L* agotada, una venta nueva rechazada con 409
    `PRODUCTO_NO_DISPONIBLE`, y repuesta como estaba.

**Fase C, 7-oct, en producción: la parte de cocina** (el autor, con el APK 0.3.0 en su teléfono;
capturas `documento/evidencias/2026-10-07-apk-01` a `09`).

- **De 09:59 a 10:00, el APK instalado de nuevo:** el aviso de Play Protect, el arranque, el
  acceso y Keycloak con `cocina.demo`.
- **11:35, el panel *Carta* del APK** muestra las seis bebidas reales y ninguna ficticia, sin
  recompilar nada: la carta viene de la API. Las ordena por nombre, con la soda personal al
  final, porque el orden por tamaño (D-74) está en la web y no en el APK 0.3.0, como se previó.
- **11:37 y 11:38, el pedido 36** de «Juancito Pinto», para llevar: una Carnívora con extra
  queso, agua de 500 ml, soda de 1,5 L y jugo de 1 L. Llega en vivo, pasa a *En preparación* y
  la cola queda vacía después de *Listo*. Cocina ve las bebidas en una línea gris, debajo de la
  pizza, como referencia.
- **Recepción, en la PC con Google Chrome** (capturas `2026-10-07-pc-01` a `06`):
  - la venta muestra las seis bebidas reales **en el orden en que se piden** (D-74), en dos
    filas, y el formulario entra entero a 1920 px, sin desplazarse (D-75);
  - el pedido 36 suma Bs 68 de la pizza más Bs 6, 15 y 15 de las bebidas: **Bs 104**;
  - lo sigue en *Pedidos* hasta *Listo*, con *Agregar bebida*, y lo entrega.
- **La venta directa, la soda agregada a un pedido listo y la *Soda 2 L* agotada** las probaron
  las sondas en producción (fase B). En la prueba, recepción además agotó todas las bebidas a la
  vez (`pc-09`, `pc-10`), que es la tarjeta 08.
