# Pruebas

Cada requisito que el sistema dice cumplir tiene aquí **su prueba y su reporte**. Los
reportes viven en [`reportes/`](reportes/), con nombre fijo: cada uno lleva adentro la fecha,
la versión y el entorno en que se corrió, y el historial de Git guarda los anteriores (D-57).
La tabla de casos del final es la fuente del apartado 2.8 del documento.

## La sexta línea de la entrega

```bash
cd backend && npm ci && npm test
```

Corre en un clon limpio, sin base de datos, sin Keycloak y sin `.env`: solo necesita Node 24.
Su reporte es [`reportes/api.txt`](reportes/api.txt) (y [`reportes/api-junit.xml`](reportes/api-junit.xml),
en JUnit). Para volver a escribirlo: `cd backend && npm run test:reporte`.

## Los niveles de prueba

| Nivel | Qué prueba | Herramienta | Comando | Necesita | Reporte |
|---|---|---|---|---|---|
| **API** | Cada ruta, el token y el rol, la validación, el precio, los estados, el canal en vivo y el contrato OpenAPI. La base es simulada y anota cada consulta; los tokens los firma un emisor local | `node:test` (Node 24) | `cd backend && npm test` | Node | [`api.txt`](reportes/api.txt), [`api-junit.xml`](reportes/api-junit.xml) |
| **App** | La venta, los pedidos, la cocina, el acceso en la web y en el APK, la sesión, el canal y sus cortes, los avisos, los anchos de pantalla y el contraste | `flutter_test` | `cd frontend && flutter test` | Flutter 3.44.8 | [`app.txt`](reportes/app.txt) |
| **Las dos, con sus reportes** | | | `bash scripts/correr-pruebas.sh` | Node y Flutter | `api.txt`, `app.txt` |
| **Sondas de punta a punta** | Lo mismo que una persona, contra un entorno real: el acceso por PKCE con las cuentas de prueba, la carta y los pedidos en la base de verdad, las carreras que decide su bloqueo y la matriz de errores | Python 3, sin paquetes | `python pruebas/correr_sondas.py` | El entorno levantado, o la URL pública y la contraseña de prueba | [`sonda-*.txt`](reportes/) |
| **Tiempo real** (RNF-01) | Cuánto tarda en llegar cada aviso en vivo, del cambio a la otra pantalla, en 30 repeticiones | `socket.io-client` (Node), desde Python | `python pruebas/tiempo-real/medir_aviso.py` | Igual que las sondas | ⏳ fase C |
| **Carga** (RNF-01) | El listado de pedidos con 50 activos y 5 usuarios a la vez: el percentil 95 | k6, en Docker | `python pruebas/carga/medir_carga.py` | Docker, y lo mismo que las sondas | ⏳ fase C |
| **Integración continua** | Las dos suites, en un clon limpio, en cada `push` | GitHub Actions | automático | — | ⏳ fase B |

Las sondas, la medición del tiempo real y la carga crean pedidos de prueba con datos
ficticios y los cierran al terminar. Contra producción se corren fuera del horario de
atención del local, de 18:00 a 23:30.

## La tabla de casos

Camino feliz y error de cada requisito *Must* (RF-01 a RF-07), los casos de seguridad y los
requisitos no funcionales. **Obtenido** es lo que dio la última corrida; **Evidencia**, dónde
verlo: un reporte de esta carpeta, una prueba automática por su nombre o un commit.

### Los requisitos *Must*

| ID | Criterio | Escenario | Esperado | Obtenido | Estado | Evidencia |
|---|---|---|---|---|---|---|
| CP-01 | CA-01.1 | Una cuenta con credenciales válidas entra por Keycloak | Recibe su token con su rol, de 60 min, y va a su pantalla | Las dos cuentas, con su rol, la API en la audiencia y 60 min | ✅ | [`sonda-acceso.txt`](reportes/sonda-acceso.txt); app: *con codigo y state correctos: canjea el codigo y entra*, *recepcion va a la pantalla de recepcion, con su nombre*, *cocina va a la pantalla de cocina* |
| CP-02 | CA-01.2 | Una contraseña equivocada | Keycloak no entrega código ni token | *Credenciales rechazadas* | ✅ | [`sonda-errores.txt`](reportes/sonda-errores.txt) |
| CP-03 | CA-02.1 | Recepción vende productos disponibles y confirma | El pedido se crea pendiente, con su número del día y el precio que calcula el servidor | 201, pendiente, Bs 189, número del día | ✅ | [`sonda-pedidos.txt`](reportes/sonda-pedidos.txt) (*venta mixta de Bs 189*); app: *una venta completa: el cuerpo exacto que se envía…* |
| CP-04 | CA-02.2 | Una venta sin productos | No se crea; *"Agregue al menos un producto"* | 400 `VENTA_INVALIDA`; la app no deja confirmar | ✅ | [`sonda-errores.txt`](reportes/sonda-errores.txt); app: *confirmar sin lo necesario dice qué falta y no envía nada* |
| CP-05 | CA-03.1 | Cocina cambia el estado de un pedido | Recepción lo ve en menos de 2 s, sin recargar | ⏳ 30 repeticiones en la fase C | ⏳ | `tiempo-real.txt` (fase C) |
| CP-06 | CA-03.2 | Se cae el canal en vivo | Aviso y *Recargar* para ver el estado actual | La banda al segundo; sin red, en el acto; *Recargar* relee sin recargar la página | ✅ | app: *un corte en vivo se avisa al segundo…*, *Recargar lee de nuevo…*; tarjeta 07 (`5ba384a`) |
| CP-07 | CA-04.1 | Cocina marca listo un pedido | Recepción recibe el aviso: suena, dice quién y lo cuenta | El aviso, el contador de la pestaña y el título del navegador | ✅ | app: *suena, avisa quién, cuenta en la pestaña y lo dice el título del navegador* |
| CP-08 | CA-04.2 | No hay pedidos listos | Pantalla vacía, sin avisos pendientes | *"No hay pedidos por atender"* | ✅ | app: *sin pedidos lo dice, en vez de una pantalla en blanco* (pedidos de recepción) |
| CP-09 | CA-05.1 | Recepción entrega un pedido listo | Pasa a entregado y sale de la lista | 200, entregado, con el historial de los cuatro pasos | ✅ | [`sonda-pedidos.txt`](reportes/sonda-pedidos.txt) (*recepcion lo entrega*); API: *matriz: recepcion lleva un pedido listo a entregado: 200* |
| CP-10 | CA-05.2 | Recepción intenta entregar uno que no está listo | No se permite | 409 | ✅ | [`sonda-pedidos.txt`](reportes/sonda-pedidos.txt) (*no se entrega lo que no esta listo*); API: *matriz: recepcion lleva un pedido pendiente a entregado: 409* |
| CP-11 | CA-06.1 | Recepción confirma un pedido nuevo | Aparece en cocina en menos de 2 s, al final de la cola | Al final y marcado *Nuevo*; el tiempo, ⏳ fase C | ⏳ | app: *un pedido nuevo aparece solo, al final, marcado "Nuevo", y suena el timbre*; `tiempo-real.txt` (fase C) |
| CP-12 | CA-06.2 | No hay pedidos pendientes | Cocina ve la pantalla vacía | *"No hay pedidos en cocina"* | ✅ | app: *sin pedidos lo dice, en vez de una pantalla en blanco* (cocina) |
| CP-13 | CA-07.1 | Cocina empieza un pedido y después lo marca listo | Pendiente → en preparación → listo | 200 y 200, con quién hizo cada paso | ✅ | [`sonda-pedidos.txt`](reportes/sonda-pedidos.txt) (*cocina lo empieza*, *cocina lo marca listo*); app: *Empezar lo pasa a en preparación; Listo lo saca de la cola* |
| CP-14 | CA-07.2 | Cocina intenta cambiar un pedido entregado | No se permite: es un estado final | 409 | ✅ | API: *matriz: cocina lleva un pedido entregado a en_preparacion: 409* |

### Seguridad

| ID | Escenario | Esperado | Obtenido | Estado | Evidencia |
|---|---|---|---|---|---|
| CP-15 | Una ruta protegida sin token | 401 | 401 `TOKEN_AUSENTE` | ✅ | [`sonda-errores.txt`](reportes/sonda-errores.txt) |
| CP-16 | Un token con la firma alterada | 401 | 401 `TOKEN_INVALIDO` | ✅ | [`sonda-errores.txt`](reportes/sonda-errores.txt) |
| CP-17 | Cocina intenta vender, cancelar o agregar | 403 | 403 `ROL_SIN_PERMISO`, los tres | ✅ | [`sonda-errores.txt`](reportes/sonda-errores.txt) |
| CP-18 | Recepción intenta empezar un pedido | 403 | 403 `ROL_SIN_PERMISO` | ✅ | [`sonda-pedidos.txt`](reportes/sonda-pedidos.txt) (*recepcion no empieza un pedido*) |
| CP-19 | Una cuenta nueva, sin rol | 403 en todas las rutas | 403 `ROL_SIN_PERMISO` | ✅ | Tarjeta 09, fase B (`f8072da`); API: *la cola sin token: 401; con un token sin rol: 403*; app: *una cuenta sin rol del sistema no entra a ninguna pantalla* |
| CP-20 | Datos inválidos: celular, nulo, cantidad, filtro, número de pedido, motivo, cuerpo que no es JSON | 400 en el formato único | 400, con su código cada uno | ✅ | [`sonda-errores.txt`](reportes/sonda-errores.txt) |
| CP-21 | Un cuerpo de 150 KB o con otro juego de caracteres | 413 / 415 | 413 y 415 | ✅ | [`sonda-errores.txt`](reportes/sonda-errores.txt) |
| CP-22 | Más de 600 peticiones por minuto desde una IP | 429 a partir de la 601 | 600 respondieron, 100 recibieron 429 | ✅ | Tarjeta 09, fase A (`fb19f9c`); API: *pasado el limite, 429 en el formato unico…* |

### Requisitos no funcionales

| ID | Requisito | Métrica | Obtenido | Estado | Evidencia |
|---|---|---|---|---|---|
| CP-23 | RNF-01 | Peor caso de 30 propagaciones < 2 s | ⏳ | ⏳ | fase C |
| CP-24 | RNF-01 | Percentil 95 del listado con 50 activos y 5 usuarios < 2 s | ⏳ | ⏳ | fase C |
| CP-25 | RNF-02 | Keycloak, token de 60 min, HTTPS, Argon2, rol en el servidor | Todo, con su evidencia | ✅ | Tarjeta 09 (plan, sección 9) |
| CP-26 | RNF-03 | La venta en 3 pasos o menos; 4 estados en cada vista con datos | ⏳ | ⏳ | fase D |
| CP-27 | RNF-04 | Sin desplazamiento horizontal a 1366 y 768 px; Chrome y Edge | ⏳ | ⏳ | fase D |
| CP-28 | RNF-05 | ≥ 99 % de respuestas 200 en 7 días o más; aviso de canal caído < 10 s | El aviso, sí (CP-06); el monitor, ⏳ | ⏳ | fase E |
