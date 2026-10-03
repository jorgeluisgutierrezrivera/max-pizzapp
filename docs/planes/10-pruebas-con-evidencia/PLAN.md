# Plan 10 — Pruebas con evidencia

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 10 — Pruebas con evidencia
- **Incremento:** seguridad, pruebas y documento (E3)
- **Estado:** ✅ **Hecho** — las 28 filas de la tabla de casos con su evidencia, y la
  integración continua en verde. Aprobado el 2026-10-02, sin cambios; con una revisión, la
  hora de la fase C (sección 10)
- **Entrada al tablero:** 2026-09-22 (orden del 22-sep); contenido fijado el 2026-10-02
- **Cierre:** 2026-10-02
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que cada requisito que el sistema dice cumplir tenga **su prueba y su reporte guardado**, y
que cualquiera pueda volver a correrlas. El E3 lo pide así: *"Una prueba sin evidencia no
existe"*, con *"la tabla de casos del apartado 2.8, con camino feliz y error de cada Must,
casos de 401 y 403, y al menos una suite automatizada con su reporte en el repositorio"*. Y
la sexta línea de la entrega es *"el comando para ejecutarlas y la ruta del reporte"*, que
tiene que funcionar **en un clon limpio**.

Lo que ya existe y esta tarjeta **no** rehace:
- la suite de la API (`npm test`, 288 pruebas, sin base ni Keycloak);
- la de la app (`flutter test`, 280);
- las sondas contra producción con las cuentas reales (`pruebas/`);
- la evidencia de seguridad de la tarjeta 09 (la matriz de errores y la validación doble).

Lo que falta, revisado el 2-oct:
1. **Ningún reporte queda guardado.** Las pruebas se corren y su salida se pierde.
2. **RNF-01 no está medido como lo define el 2.3:** la propagación se midió con 10 y 20
   repeticiones, no con **30**, y la carga del listado con **50 pedidos activos y 5 usuarios
   concurrentes, con k6**, no se midió nunca. El docente lo pidió por escrito en la T3.
3. **RNF-03 y RNF-04 no tienen su prueba explícita.** Las pruebas de la app recorren 1366,
   1024, 360 y 320 px, pero **no 768**, el ancho de tableta del RNF-04. Los estados de carga,
   vacío y error existen, pero nadie los mapeó vista por vista. *"3 pasos o menos"* no está
   definido.
4. **RNF-05** tiene el monitor andando desde el 23-sep, pero **falta su resultado**: la
   captura del informe de UptimeRobot.
5. **No hay una tabla de casos** que junte cada criterio de aceptación con su prueba y su
   evidencia.

---

## 2. Alcance

**Incluye:**
- **Los reportes, versionados** en `docs/pruebas/reportes/`: los de la suite de la API y de
  la app, y la salida de cada sonda y medición contra producción.
- **El plan de pruebas** en `docs/pruebas/README.md`: qué se prueba, con qué, cómo se corre
  y **la tabla de casos**, de la que sale el 2.8.
- **La integración continua** con GitHub Actions: un clon limpio corre las dos suites en
  cada `push`.
- **RNF-01 en producción:** 30 propagaciones y k6, fuera del horario de atención.
- **RNF-03 y RNF-04:** el mapa de los cuatro estados por vista, la definición de *paso* y las
  pruebas a 1366 y 768 px, con sus capturas.
- **RNF-05:** el resultado del monitor, con sus fechas.
- **Una sonda de errores** en el repositorio: la matriz de 401, 403 y 400 de la tarjeta 09,
  más un acceso con la contraseña equivocada (CA-01.2).

**No incluye:**
- **Pruebas de punta a punta con un navegador automatizado** (Playwright, Selenium). Flutter
  dibuja en un *canvas*, lo que vuelve frágil ese tipo de prueba. El flujo completo lo cubren
  la sonda de pedidos contra producción, las pruebas de la app y la prueba del autor.
- **Medir la cobertura de código.** Un porcentaje sin la tabla de casos no dice qué
  requisito está probado; la tabla sí.
- **Pruebas de carga más allá del RNF-01**, como estrés o resistencia: el piloto es un
  local, con 5 usuarios como mucho.
- **Un escaneo automático de vulnerabilidades**: si sobra tiempo, en el E4.

---

## 3. Decisiones de diseño

### D-57 · Los reportes, con nombre fijo en el repositorio, y la tabla de casos como fuente del 2.8

- **`docs/pruebas/reportes/`**, con un archivo por prueba y **nombre fijo** (`api.txt`,
  `app.txt`, `carga-k6.txt`…). Cada reporte lleva adentro la fecha, la versión y el entorno
  en que se corrió. El historial de Git guarda las versiones anteriores, así que la ruta de
  la sexta línea no cambia de una entrega a otra.
- **El reporte de la API sale en dos formatos:** texto para leer y **JUnit (XML)**, que es lo
  que entienden las herramientas de integración continua. Lo arma el propio `node --test`,
  sin paquetes nuevos.
- **La tabla de casos vive en `docs/pruebas/README.md`**, y el 2.8 del documento se deriva de
  ella, como el contrato de la API del 2.4.4 se deriva de `openapi.yaml`. Cada fila dice qué
  criterio prueba, qué se esperaba, qué se obtuvo y **dónde está la evidencia**: un reporte,
  una prueba automática por su nombre, una figura o un commit.
- **La sexta línea de Moodle:** `cd backend && npm ci && npm test`, y el reporte en
  `docs/pruebas/reportes/api.txt`. Es la suite que corre sin nada más que Node: ni base, ni
  Keycloak, ni Flutter.

### D-58 · La carga con k6 en Docker, contra producción y por debajo del límite de peticiones

- **k6 corre en su imagen oficial de Docker** (`grafana/k6:2.3.0`, fijada): no se instala
  nada en la máquina, y el script queda en el repositorio (`pruebas/carga/`).
- **Lo que mide es exactamente el RNF-01:** `GET /api/v1/pedidos` con **50 pedidos activos**
  y **5 usuarios concurrentes**, reportando el **percentil 95**, con el umbral de 2 s escrito
  en el script (si no se cumple, k6 termina con error).
- **Los tokens los consigue la sonda de siempre**, por PKCE con las cuentas de prueba, y
  pasan a k6 por el entorno. Nunca se imprimen.
- **Los 50 pedidos se crean al empezar y se cancelan al terminar**, con el motivo *"Prueba de
  carga k6"*: no queda ninguno activo.
- **Cada usuario lee una vez por segundo durante 60 s.** Todo sale de una sola IP, y el límite
  de la tarjeta 09 es de 600 por minuto: 50 altas, unas 300 lecturas y 50 cancelaciones
  quedan por debajo. Una lectura por segundo y por pantalla ya es mucho más que el uso real.
- **Se corre fuera del horario de atención** (de 18:00 a 23:30): los 50 pedidos aparecerían
  en la cocina.

### D-59 · La integración continua corre las dos suites en un clon limpio

- **GitHub Actions** (`.github/workflows/pruebas.yml`), en cada `push` y en cada *pull
  request*: un trabajo para la API (Node 24.15, `npm ci`, `npm test`, con el reporte JUnit
  como artefacto) y otro para la app (Flutter 3.44.8, `flutter analyze` y `flutter test`).
- **Es la prueba de la sexta línea:** la máquina de GitHub parte de un clon limpio, sin
  `.env`, sin base y sin Keycloak, igual que la del tribunal.
- **Una insignia en el README** muestra el último resultado.
- Las pruebas contra producción **no** corren en la integración continua: necesitan las
  contraseñas de las cuentas de prueba, que no se guardan en GitHub.

### D-60 · Un *paso* es una sección del formulario de venta

- **RNF-03 pide *"registrar un pedido en 3 pasos o menos"***. Desde la tutoría del 24-sep la
  venta es **un solo formulario** con tres secciones: **el cliente** (nombre, celular y para
  llevar o comer aquí), **los productos** (pizzas y bebidas) y **confirmar**. Un paso es cada
  una de esas secciones. Elegir una pizza en su ventana es parte de la sección de productos,
  no un paso aparte.
- **La evidencia es una prueba de la app** que hace una venta completa recorriendo solo esas
  tres secciones, más la captura de la venta del 2-oct.
- **Los cuatro estados** (cargando, con datos, vacío y error) se comprueban en **cada vista
  que consume datos**: la venta (la carta), los pedidos de recepción y la cola de cocina. Se
  mapea cada estado a su prueba, y se escribe la que falte.

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — La suite con su reporte, y el plan de pruebas
- [x] `npm run test:reporte` en la API: el texto en la consola y en `api.txt`, y el JUnit en
      `api-junit.xml`. `npm test` sigue igual.
- [x] La app: `flutter test --file-reporter expanded:…` deja `app.txt`.
- [x] `pruebas/api/probar_errores.py` *(nuevo)*: la matriz de 401, 403 y 400, y un acceso con
      la contraseña equivocada.
- [x] Las sondas contra producción, con su salida en `reportes/`: el acceso, la carta, los
      pedidos y los errores.
- [x] `docs/pruebas/README.md`: los niveles de prueba, las herramientas, cómo se corre cada
      una y dónde queda su reporte. La tabla de casos, con su estructura.
- [x] El README del repositorio: el comando de la sexta línea y la ruta del reporte.

### Fase B — La integración continua
- [x] `.github/workflows/pruebas.yml`, con las versiones fijadas.
- [x] La insignia en el README.
- [x] El autor sube; el agente comprueba en la API pública de GitHub que la corrida terminó
      en verde. Si una prueba falla solo en la integración continua, se corrige o se explica
      en este plan.

### Fase C — RNF-01 en producción
- [x] `pruebas/carga/listado-pedidos.k6.js` y `pruebas/carga/medir_carga.py` *(nuevos)*.
- [x] Probado primero contra el entorno local.
- [x] En producción, fuera del horario de atención: **k6** (percentil 95 del listado, con 50
      activos y 5 usuarios) y **las 30 propagaciones** (`medir_aviso.py` con `VECES=30`), con
      sus reportes. Al terminar, ningún pedido de prueba activo. *(Se corrió dentro del
      horario, con el local sin atender ese día: ver la sección 10.)*

### Fase D — RNF-03 y RNF-04
- [x] El mapa de los cuatro estados en las tres vistas con datos, cada uno con su prueba; las
      que falten, escritas.
- [x] Una prueba de la app: la venta completa en tres pasos.
- [x] Pruebas de la app a **1366 × 768** y a **768 × 1024** en la venta, los pedidos y la cola
      de cocina, sin desbordes.
- [x] Capturas a esos dos anchos.
- [x] El autor abre la app en **Edge**, además de Chrome.

### Fase E — La tabla de casos y el cierre
- [x] La tabla completa en `docs/pruebas/README.md`: camino feliz y error de cada *Must*
      (RF-01 a RF-07, 14 filas), los casos de 401, 403, 400, 413 y 429, y una fila por RNF,
      cada una con lo obtenido y su evidencia.
- [x] **RNF-05:** el autor saca la captura del informe de UptimeRobot, con las fechas y el
      porcentaje. *(La leyó el agente en el Chrome del autor, con su sesión abierta y a su
      pedido.)*
- [x] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **Pruebas y reportes:**
  - `docs/pruebas/README.md` *(nuevo)*: el plan de pruebas y la tabla de casos;
  - `docs/pruebas/reportes/` *(nuevo)*: los reportes;
  - `pruebas/api/probar_errores.py` *(nuevo)*;
  - `pruebas/carga/listado-pedidos.k6.js` y `pruebas/carga/medir_carga.py` *(nuevos)*;
  - `pruebas/tiempo-real/medir_aviso.py`: 30 repeticiones por omisión, como el RNF-01.
- **API:** `backend/package.json` (el *script* `test:reporte`).
- **App:** las pruebas nuevas de los anchos, de los estados y de los tres pasos, en
  `frontend/test/`.
- **Integración continua:** `.github/workflows/pruebas.yml` *(nuevo)*.
- **Documentación:** `README.md`.

No cambia el código de la API, de la app ni la base: solo pruebas, *scripts* y documentos.

---

## 6. Cómo se prueba

| Qué | Cómo | Resultado esperado |
|---|---|---|
| La suite y su reporte | `npm run test:reporte` y `flutter test` con reporte | 288 y 280 en verde, y los reportes escritos |
| La sexta línea | La integración continua, que parte de un clon limpio | Las dos suites en verde en GitHub |
| La propagación (RNF-01) | `medir_aviso.py` con 30 repeticiones, contra producción | El peor caso, bajo 2 s |
| La carga (RNF-01) | k6 con 50 activos y 5 usuarios, contra producción | El percentil 95 del listado, bajo 2 s; ningún error |
| Los estados (RNF-03) | Pruebas de la app, vista por vista | Cargando, con datos, vacío y error en las tres |
| Los anchos (RNF-04) | Pruebas de la app y capturas | Nada se desborda a 1366 ni a 768 px |
| La disponibilidad (RNF-05) | El informe de UptimeRobot | ≥ 99 % en 7 días o más, con fechas |

---

## 7. Criterios de aceptación

- **Un solo comando, en un clon limpio, corre la suite de la API y deja su reporte**, y la
  integración continua lo demuestra en cada `push`.
- Los reportes de la API, de la app, de las sondas, de la propagación y de k6 están
  **versionados** en `docs/pruebas/reportes/`, con la fecha y el entorno adentro.
- **RNF-01:** el peor caso de 30 propagaciones y el percentil 95 del listado con 50 activos
  y 5 usuarios, los dos bajo 2 s, medidos en producción.
- **RNF-03:** la venta en tres pasos, y los cuatro estados en cada vista con datos, cada uno
  con su prueba.
- **RNF-04:** sin desbordes a 1366 y a 768 px, en Chrome y en Edge.
- **RNF-05:** el resultado del monitor, con sus fechas.
- **La tabla de casos:** camino feliz y error de cada *Must*, y los casos de 401 y 403, **cada
  fila con su evidencia**.
- **Sin regresiones**, y sin ningún secreto en los reportes.

---

## 8. Requisitos que cubre

- **Del sistema:** la verificación formal de **RNF-01, RNF-03, RNF-04 y RNF-05**, y de los
  criterios de aceptación de **RF-01 a RF-07**.
- **Institucionales:** **#4** (interfaz adaptable, medida) y la exigencia del módulo de
  pruebas con evidencia.
- **De la entrega (E3):** la tabla del 2.8, *"al menos una suite automatizada con su reporte
  en el repositorio"*, la sexta línea y *"las pruebas automatizadas corren en un clon
  limpio"*.
- **De la tutoría T3:** RNF-01 con 30 repeticiones y k6 con 5 usuarios y 50 pedidos, y el
  resultado del sondeo de RNF-05.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — La suite con su reporte | ✅ Verificada | 2026-10-02 | **La API:** `npm run test:reporte` (`backend/scripts/reporte-de-pruebas.js`) corre la misma suite que `npm test` con dos reportes del propio `node --test`: `api.txt`, que empieza con la fecha, la versión, Node, el sistema, el comando y el resultado, y `api-junit.xml`, con los **288 casos**. **288 de 288.** Sin códigos de color, y con las rutas relativas a la raíz del repositorio: las trazas que imprimen a propósito las pruebas que provocan errores, y el atributo `file` de cada caso del JUnit, traían la ruta absoluta de la máquina (`E:\Max Pizzapp v2\…`). `npm test` no cambió. **Las dos suites:** `bash scripts/correr-pruebas.sh` deja además `app.txt`, con la misma cabecera: **280 de 280**, Flutter 3.44.8. El reporte de Flutter también traía las rutas absolutas: se dejan relativas (`test/…`), con una expresión que sirve igual en Windows y en Linux. **La sonda de errores** (`pruebas/api/probar_errores.py`, nueva): los 15 casos de 401, 403, 400, 413 y 415 de la tarjeta 09, más **un acceso con la contraseña equivocada (CA-01.2)**, el último y uno solo, para no activar el bloqueo por intentos rápidos. **16 de 16**, en local y en producción. La sonda de acceso reconoce ahora el mensaje de Keycloak en español (*"Usuario o contraseña incorrectos"*): antes, la contraseña equivocada salía como *"no hubo redirección"* en lugar de *"credenciales rechazadas"*. **Las sondas, con su reporte:** `pruebas/correr_sondas.py` corre las cinco (acceso, salud, carta, pedidos y errores) y deja `sonda-*.txt`, con la fecha, la API y Keycloak al principio. En local, todas correctas. **En producción** (2-oct, 11:25, fuera del horario de atención): acceso en 4,1 s, salud en 7,3 s, carta en 7,4 s, pedidos en 107,6 s y errores en 13,3 s, **TODAS CORRECTAS**; la de pedidos cerró los pedidos que creó. Ningún reporte contiene la contraseña (buscada con su valor real) ni un token. **El plan de pruebas** (`docs/pruebas/README.md`): la sexta línea, los niveles de prueba con su herramienta, su comando y su reporte, y **la tabla de casos**. De los 14 casos de los *Must*, 12 ya tienen su evidencia; CP-05 y CP-11 (menos de 2 s) esperan las 30 propagaciones de la fase C. Los 8 de seguridad, completos. De los 6 de los RNF, el de RNF-02; los demás, en las fases C, D y E. Cada nombre de prueba citado se verificó contra el código. **El README** del repositorio: la sexta línea, la ruta del reporte y los dos comandos nuevos |
| B — La integración continua | ✅ Verificada | 2026-10-02 | **El flujo** (`.github/workflows/pruebas.yml`): en cada `push` a `main`, en cada *pull request* y a mano (*Run workflow*), dos trabajos en Ubuntu 24.04. **La API**, con Node 24.15.0: `npm ci`, `npm test` —el comando de la sexta línea— y `npm run test:reporte`, cuyo texto y JUnit quedan como artefacto `reporte-api`. **La app**, con Flutter 3.44.8: `flutter pub get --enforce-lockfile`, `flutter analyze` y `flutter test`. Las versiones, fijadas; un tiempo máximo de 10 y 20 minutos por trabajo, para que una prueba colgada no corra horas. **La insignia**, al principio del README, y el párrafo de la integración continua en su sección de pruebas. **Comprobado antes de subir:** `actionlint` 1.7.12, sin observaciones; las acciones (`checkout`, `setup-node` y `upload-artifact` en su versión 7, `subosito/flutter-action` en la 2), la imagen `ubuntu-24.04`, Node 24.15.0 y Flutter 3.44.8 existen, y las entradas que usa el flujo son las de cada acción. **Un clon limpio, simulado en Docker:** el código de `main` (`5b7908b`) bajado de GitHub, en Linux y con la hora en UTC, como la máquina de GitHub. La API: **288 de 288**, y el reporte sin rutas absolutas. La app, con el Flutter 3.44.8 para Linux (su SHA-256, verificado): las dependencias exactas, el análisis **sin avisos** y **280 de 280**, en 1 min 17 s. En Linux se revisaba lo que en Windows no se ve: los nombres de archivo distinguen mayúsculas, y las pruebas que muestran horas corren en UTC. **En GitHub**, comprobado en su API pública: la corrida 1 (`849545d`, el `10-2`), **en verde** en 137 s, con la API en 28 s y la app en 134 s, cada paso en verde y el artefacto `reporte-api` guardado; la corrida 2 (`3767109`, el `10-3`), **en verde** en 76 s, con la app en 71 s porque el Flutter ya estaba en caché. Los registros de cada paso piden iniciar sesión en GitHub, pero un paso en verde alcanza: `node --test` y `flutter test` terminan con error ante una sola falla. La insignia del README dice *passing* |
| C — RNF-01 en producción | ✅ Verificada | 2026-10-02 | **La carga** (`pruebas/carga/`, nuevos): `listado-pedidos.k6.js` crea 50 pedidos pendientes al empezar; 5 usuarios a la vez, 3 de recepción y 2 de cocina, leen `GET /api/v1/pedidos` una vez por segundo durante 60 s, y cada lectura comprueba que el listado trae los 50 o más; al terminar, cancela los 50 con el motivo *"Prueba de carga k6"*. Los umbrales están en el script: percentil 95 bajo 2 s, ninguna lectura fallida y todas las comprobaciones cumplidas. `medir_carga.py` consigue los tokens por PKCE y corre k6 2.3.0 en Docker: el script entra por la entrada estándar y los tokens por el entorno, sin aparecer en la línea de comandos. **La propagación:** `medir_aviso.py` hace 30 repeticiones por omisión y deja su reporte. **En local:** k6, percentil 95 de 24 ms en 297 lecturas, ninguna falla y los 50 cancelados; la propagación, peor caso de 176 ms. **En producción**, corridas por el autor el 2-oct a las 20:04, hora de Bolivia (los reportes dicen 00:03 y 00:05 del 3-oct, en UTC). **Las 30 propagaciones** ([`tiempo-real.txt`](../../pruebas/reportes/tiempo-real.txt)): del pedido nuevo a cocina, **peor caso de 303 ms** (mediana 236); del cambio de estado a recepción, **262 ms** (mediana 231); de lo agregado a cocina, **705 ms** (mediana 239). Los 30 pedidos, cerrados. **k6** ([`carga-k6.txt`](../../pruebas/reportes/carga-k6.txt)): 235 lecturas del listado con 50 activos y 5 usuarios, **percentil 95 de 296 ms** (mediana 286, máximo 369), ninguna falla y 470 de 470 comprobaciones; 336 peticiones en total, bajo el límite de 600 por minuto. Los 50 pedidos (#327 a #376), cancelados. **Los dos, holgados:** el peor caso más alto queda a un tercio del umbral. El piso de unos 230 ms aparece en todas las mediciones, también en las más simples: es el viaje por la red entre la máquina del autor y el servidor, porque en local las mismas pruebas dan decenas de milisegundos. Ningún token en los reportes |
| D — RNF-03 y RNF-04 | ✅ Verificada | 2026-10-02 | **Los cuatro estados:** el mapa vista por vista está en `docs/pruebas/README.md`. De las 12 celdas, 10 ya tenían su prueba; faltaban *cargando* y *error* en los pedidos de recepción, aunque los dos estados ya estaban en el código. Se escribieron: *cargando: lo dice mientras la lectura viaja, y después muestra los pedidos* y *error: el mensaje del servidor, y Reintentar vuelve a leer*. **12 de 12.** **Los tres pasos (D-60):** *el cliente, los productos y confirmar, en la misma pantalla: cada toque cae en su sección*. Hace una venta completa a 1366 × 768: comprueba que el nombre, el celular y *para llevar* están en *1 · Cliente*, que *Agregar pizza* está en *2 · Pizzas* y la gaseosa en *3 · Bebidas*, y que *Confirmar* está en el pedido. La venta llega a la API, y la pantalla es la misma al empezar y al terminar. **Los dos anchos:** `test/anchos_del_rnf04.dart` (nuevo) define los dos tamaños y la comprobación de que nada se desborda, ningún texto visible queda fuera del ancho y nada se desplaza de lado. Al correrla por primera vez marcó el campo del nombre, que corre lo escrito cuando un nombre largo no cabe, como cualquier campo de texto: se dejó afuera, junto con la tira de extras del modal de la pizza, porque ninguno de los dos desplaza la página. Antes de usarla se calibró con un archivo temporal, ya borrado: rechazó un texto fuera de la pantalla, una lista que se desplazaba de lado y un desborde, y dejó pasar una pantalla sana. **Seis pruebas, en verde:** la venta de punta a punta (un nombre largo, una pizza mitad y mitad con extra, una bebida, una observación larga, la ventana de la pizza, la de las bebidas y el aviso de la venta), los pedidos (uno de cada estado, un nombre largo, lo agregado y la ventana de cancelar) y la cola (cuatro pedidos, un nombre y una observación largos, lo agregado, la franja del sonido y la banda de canal caído), cada una a 1366 × 768 y a 768 × 1024. **La suite:** **289 de 289** (280 + 9), `flutter analyze` sin avisos, y el reporte `app.txt` regenerado. Solo se agregaron pruebas: ninguna línea de las existentes cambió. **En GitHub:** la corrida 4 (`4701c5f`, el `10-4`), en verde en 69 s, con las 289 en Linux. **Los navegadores del autor**, los dos al día el 2-oct: **Microsoft Edge 154.0.4258.53** y **Google Chrome 154.0.8037.98**, de 64 bits. **En producción, en Edge** (el autor, el 2-oct de 21:07 a 21:37): 16 capturas con el modo dispositivo de las herramientas de desarrollo, 8 a 1366 × 768 y 8 a 768 × 1024, guardadas al doble de densidad. Cada juego recorre el ciclo de un pedido de prueba: la venta llena y enviada, la cocina vacía y con el pedido, el pedido en recepción, la ventana de cancelar y lo que ven las dos pantallas después de cancelarlo (los pedidos 116 y 117, cancelados). En ninguna hay desplazamiento de lado ni algo que se salga de la pantalla. **Lo que mostraron:** por debajo de 900 px el pedido no entra al costado, así que la venta suma *4 · Observación para cocina* y lleva *Confirmar* a la barra de abajo. El plan de pruebas lo describe así, y deja dicho que un pedido exige solo el cliente, al menos una pizza y confirmar. Dos detalles cosméticos, para el E4: a 1366 px, *"Jugo natural 1 L"* deja la *"L"* sola en otra línea, y a 768 px el aviso de la venta tapa por un momento el resumen de la barra de abajo |
| E — La tabla de casos | ✅ Verificada | 2026-10-02 | **La tabla de casos** (`docs/pruebas/README.md`), completa: **28 filas, todas con lo obtenido y su evidencia, ninguna pendiente**. Son el camino feliz y el error de cada *Must*, de RF-01 a RF-07 (CP-01 a CP-14); la seguridad, con 401, 403, 400, 413, 415 y 429 (CP-15 a CP-22); y una fila por cada medida de los RNF (CP-23 a CP-28). **RNF-05:** el monitor de UptimeRobot *Max Pizzapp — salud de la API* pide `GET /api/v1/salud` cada 5 minutos desde Norteamérica, las 24 horas, más exigente que la franja de atención. El agente lo leyó en el Chrome del autor, con su sesión abierta y a su pedido, el 2-oct a las 21:48. *Up* hace 9 días, 20 horas y 29 minutos, o sea **desde el 23-sep a la 01:19**, la hora del alta anotada en el plan 03. **100 % en 24 h, en 7 y en 30 días; 0 incidentes y 0 minutos caído**; respuesta media de 48 ms en la última hora. Son unos 2840 sondeos, de los que unos 650 caen en la franja de 18:00 a 23:30: los 650, en 200. El aviso de canal caído, la otra mitad del RNF-05, ya estaba probado (CP-06). Dos capturas del panel, `uptimerobot-01` y `02`; el panel es oscuro, así que sirven como evidencia, pero para el documento conviene la tabla con los números. **Lo que el sondeo no ve:** uno cada 5 minutos no ve un corte más corto que eso, como los segundos de un reinicio en un despliegue. Se declara así en el plan de pruebas, con el método y las fechas. **Nivel nuevo** en la tabla de niveles: la disponibilidad, con su herramienta y su frecuencia |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-02 | Versión inicial propuesta | Lo que el E3 pide para las pruebas, lo que pidió el docente en la T3 y lo que la revisión del 2-oct encontró sin medir (sección 1) |
| 2026-10-02 | **Aprobado** por el autor, sin cambios | |
| 2026-10-02 | **La fase C se corre a las 20:04, dentro del horario de atención** que D-58 evitaba (D-61) | El autor confirmó que ese día el local no usaba el sistema. La regla existe para no meter 50 pedidos de prueba en la cocina durante el servicio, y ese día no había servicio. La hora real queda en los reportes |

---

## 11. Cierre

- **Commits de la tarjeta**, uno por fase probada:
  - `ed53fa7` el plan (10-P);
  - `5b7908b` los reportes en el repositorio, la sonda de errores y el plan de pruebas (A);
  - `849545d` la integración continua (B);
  - `3767109` el RNF-01 en producción: las 30 propagaciones y k6 (C);
  - `30677d1` la tabla de casos con el RNF-01 y la integración continua verificada: completa
    al `3767109`, que se subió antes de que estuvieran escritos los dos README;
  - `4701c5f` las pruebas del RNF-03 y del RNF-04 (D).

  El cierre (10-E) lleva el RNF-04 en Edge, el RNF-05, este apartado y el índice de planes.
- **Criterios de aceptación (sección 7):** los ocho cumplidos.
  - **Un solo comando en un clon limpio:** `cd backend && npm ci && npm test`, 288 de 288. La
    integración continua lo demuestra en cada `push`: las cuatro corridas de la tarjeta, en
    verde, con la app (289 de 289) en el mismo flujo.
  - **Los reportes, versionados** en `docs/pruebas/reportes/`, cada uno con la fecha y el
    entorno: la API (texto y JUnit), la app, las cinco sondas, la propagación y k6.
  - **RNF-01**, en producción: el peor caso de 30 propagaciones, 705 ms; el percentil 95 del
    listado con 50 activos y 5 usuarios, 296 ms.
  - **RNF-03:** la venta en tres pasos, y los cuatro estados en las tres vistas, 12 de 12.
  - **RNF-04:** sin desbordes a 1366 y a 768 px, en las pruebas y en 16 capturas en Edge. Chrome
    es el navegador de todas las pruebas del autor de las tarjetas anteriores.
  - **RNF-05:** 100 % del 23-sep a la 01:19 al 2-oct a las 21:48.
  - **La tabla de casos:** 28 filas, cada una con su evidencia.
  - **Sin regresiones y sin secretos:** las dos suites en verde, y ni la contraseña de prueba
    ni un token en ningún reporte. La contraseña se buscó con su valor real, el autor en los
    reportes de la fase C y el agente en los de la fase A.
- **Requisitos:** la verificación de RNF-01, RNF-03, RNF-04 y RNF-05, y de los criterios de
  aceptación de RF-01 a RF-07; el institucional #4; lo que pide el E3 de la tabla del 2.8, la
  suite con su reporte y la sexta línea; y lo pedido en la tutoría T3. **La tabla de casos es
  la fuente del apartado 2.8.**
- **Lo que salió, además de lo previsto** (secciones 9 y 10):
  - las mediciones en producción se corrieron dentro del horario, con el local sin atender
    ese día, y quedó escrito el motivo;
  - la comprobación del RNF-04 marcó al principio el campo del nombre, que corre lo escrito
    cuando no cabe: se dejó afuera, con su porqué, y la comprobación se calibró antes de
    usarla;
  - las capturas a 768 px mostraron que, por debajo de 900 px, la venta suma *4 · Observación
    para cocina* y lleva *Confirmar* abajo; el plan de pruebas lo describe así;
  - el `10-3` se subió sin los dos README, y los completó el `30677d1`.
- **Queda abierto, con destino:**
  - **la numeración de las secciones de la venta:** la pantalla numera hasta cuatro, y
    *Confirmar* aparte, mientras el RNF-03 cuenta tres pasos. Numerar solo lo obligatorio, o
    no numerar, haría que la pantalla diga lo mismo que el requisito: semana del E4, con su
    plan;
  - **dos detalles de la venta:** *"Jugo natural 1 L"* deja la *"L"* sola a 1366 px, y a 768 px
    el aviso de la venta tapa un momento la barra de abajo: E4;
  - **el RNF-05 sigue midiendo:** otra lectura del monitor antes de la defensa;
  - **un escaneo automático de vulnerabilidades:** si sobra tiempo, en el E4 (sección 2).
- **Fecha de cierre:** 2026-10-02.
