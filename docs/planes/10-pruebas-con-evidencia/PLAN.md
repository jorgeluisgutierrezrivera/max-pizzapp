# Plan 10 — Pruebas con evidencia

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 10 — Pruebas con evidencia
- **Incremento:** seguridad, pruebas y documento (E3)
- **Estado:** 🔵 **En curso** — aprobado el 2026-10-02, sin cambios
- **Entrada al tablero:** 2026-09-22 (orden del 22-sep); contenido fijado el 2026-10-02
- **Cierre:** —
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
- [ ] `.github/workflows/pruebas.yml`, con las versiones fijadas.
- [ ] La insignia en el README.
- [ ] El autor sube; el agente comprueba en la API pública de GitHub que la corrida terminó
      en verde. Si una prueba falla solo en la integración continua, se corrige o se explica
      en este plan.

### Fase C — RNF-01 en producción
- [ ] `pruebas/carga/listado-pedidos.k6.js` y `pruebas/carga/medir_carga.py` *(nuevos)*.
- [ ] Probado primero contra el entorno local.
- [ ] En producción, fuera del horario de atención: **k6** (percentil 95 del listado, con 50
      activos y 5 usuarios) y **las 30 propagaciones** (`medir_aviso.py` con `VECES=30`), con
      sus reportes. Al terminar, ningún pedido de prueba activo.

### Fase D — RNF-03 y RNF-04
- [ ] El mapa de los cuatro estados en las tres vistas con datos, cada uno con su prueba; las
      que falten, escritas.
- [ ] Una prueba de la app: la venta completa en tres pasos.
- [ ] Pruebas de la app a **1366 × 768** y a **768 × 1024** en la venta, los pedidos y la cola
      de cocina, sin desbordes.
- [ ] Capturas a esos dos anchos.
- [ ] El autor abre la app en **Edge**, además de Chrome.

### Fase E — La tabla de casos y el cierre
- [ ] La tabla completa en `docs/pruebas/README.md`: camino feliz y error de cada *Must*
      (RF-01 a RF-07, 14 filas), los casos de 401, 403, 400, 413 y 429, y una fila por RNF,
      cada una con lo obtenido y su evidencia.
- [ ] **RNF-05:** el autor saca la captura del informe de UptimeRobot, con las fechas y el
      porcentaje.
- [ ] Evidencia en la sección 9 y cierre.

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
| B — La integración continua | ⬜ | | |
| C — RNF-01 en producción | ⬜ | | |
| D — RNF-03 y RNF-04 | ⬜ | | |
| E — La tabla de casos | ⬜ | | |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-02 | Versión inicial propuesta | Lo que el E3 pide para las pruebas, lo que pidió el docente en la T3 y lo que la revisión del 2-oct encontró sin medir (sección 1) |
| 2026-10-02 | **Aprobado** por el autor, sin cambios | |

---

## 11. Cierre

—
