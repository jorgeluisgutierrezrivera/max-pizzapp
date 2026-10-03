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

**La integración continua lo demuestra en cada `push`** (D-59): una máquina de GitHub, que
parte de un clon limpio igual que la del tribunal, corre ese comando y la suite de la app.
El resultado de cada corrida está en la pestaña
[*Actions*](https://github.com/jorgeluisgutierrezrivera/max-pizzapp/actions/workflows/pruebas.yml)
del repositorio, con el reporte de la API como artefacto.

## Los niveles de prueba

| Nivel | Qué prueba | Herramienta | Comando | Necesita | Reporte |
|---|---|---|---|---|---|
| **API** | Cada ruta, el token y el rol, la validación, el precio, los estados, el canal en vivo y el contrato OpenAPI. La base es simulada y anota cada consulta; los tokens los firma un emisor local | `node:test` (Node 24) | `cd backend && npm test` | Node | [`api.txt`](reportes/api.txt), [`api-junit.xml`](reportes/api-junit.xml) |
| **App** | La venta, los pedidos, la cocina, el acceso en la web y en el APK, la sesión, el canal y sus cortes, los avisos, los anchos de pantalla y el contraste | `flutter_test` | `cd frontend && flutter test` | Flutter 3.44.8 | [`app.txt`](reportes/app.txt) |
| **Las dos, con sus reportes** | | | `bash scripts/correr-pruebas.sh` | Node y Flutter | `api.txt`, `app.txt` |
| **Sondas de punta a punta** | Lo mismo que una persona, contra un entorno real: el acceso por PKCE con las cuentas de prueba, la carta y los pedidos en la base de verdad, las carreras que decide su bloqueo y la matriz de errores | Python 3, sin paquetes | `python pruebas/correr_sondas.py` | El entorno levantado, o la URL pública y la contraseña de prueba | [`sonda-*.txt`](reportes/) |
| **Tiempo real** (RNF-01) | Cuánto tarda en llegar cada aviso en vivo, del cambio a la otra pantalla, en 30 repeticiones | `socket.io-client` (Node), desde Python | `python pruebas/tiempo-real/medir_aviso.py` | Igual que las sondas | [`tiempo-real.txt`](reportes/tiempo-real.txt) |
| **Carga** (RNF-01) | El listado de pedidos con 50 activos y 5 usuarios a la vez: el percentil 95 | k6, en Docker | `python pruebas/carga/medir_carga.py` | Docker, y lo mismo que las sondas | [`carga-k6.txt`](reportes/carga-k6.txt) |
| **Disponibilidad** (RNF-05) | Que la API responda 200 en `GET /api/v1/salud`, las 24 horas, desde el 23-sep | UptimeRobot, plan gratuito, desde Norteamérica | automático, cada 5 minutos | — | El panel del monitor (capturas del 2-oct) |
| **Integración continua** | Las dos suites, en un clon limpio, en cada `push`: la API con `npm ci && npm test`; la app con `flutter analyze` y `flutter test` | GitHub Actions ([`pruebas.yml`](../../.github/workflows/pruebas.yml)), Ubuntu 24.04, Node 24.15.0, Flutter 3.44.8 | automático; o *Run workflow* en *Actions* | — | [Las corridas](https://github.com/jorgeluisgutierrezrivera/max-pizzapp/actions/workflows/pruebas.yml), con el artefacto `reporte-api` |

Las sondas, la medición del tiempo real y la carga crean pedidos de prueba con datos
ficticios y los cierran al terminar. Contra producción se corren fuera del horario de
atención del local, de 18:00 a 23:30.

## La usabilidad y los anchos (RNF-03 y RNF-04)

**Un paso es una sección del formulario de venta** (D-60): el cliente, los productos y
confirmar. Desde la tutoría del 24-sep la venta es un solo formulario. En la computadora, la
pantalla numera *1 · Cliente*, *2 · Pizzas* y *3 · Bebidas*, y la observación y *Confirmar*
están en el pedido, a la derecha. En la tableta y el celular no hay lugar para el pedido al
costado: la observación pasa a ser *4 · Observación para cocina* y *Confirmar* queda en la
barra de abajo. Las pizzas y las bebidas son un mismo paso, los productos, y elegir una pizza
en su ventana también es parte de ese paso. **Lo que un pedido exige es el cliente, al menos
una pizza y confirmar: las bebidas y la observación son opcionales.** La prueba *el cliente,
los productos y confirmar, en la misma pantalla: cada toque cae en su sección* hace una venta
completa en esos tres pasos y comprueba que ninguno lleva a otra pantalla.

**Los cuatro estados, en cada vista que consume datos.** Cada celda es el nombre de su prueba:

| Vista | Cargando | Con datos | Vacío | Error |
|---|---|---|---|---|
| **La venta** (la carta), `pantalla_recepcion_test.dart` | *cargando* | *todo a la vista: el cliente, las pizzas, las bebidas y el pedido…* | *carta vacía: lo dice, en vez de una pantalla en blanco* | *error: el mensaje del servidor, y reintentar vuelve a pedir* |
| **Los pedidos de recepción**, `pedidos_de_recepcion_test.dart` | *cargando: lo dice mientras la lectura viaja, y después muestra los pedidos* | *número del día, cliente, para llevar, celular, líneas, lo agregado con su hora, total y estado* | *sin pedidos lo dice, en vez de una pantalla en blanco* | *error: el mensaje del servidor, y Reintentar vuelve a leer* |
| **La cola de cocina**, `pantalla_cocina_test.dart` | *cargando, y luego la cola* | *número, cliente, para llevar, las pizzas con mitades y extras, las bebidas aparte y la observación* | *sin pedidos lo dice, en vez de una pantalla en blanco* | *si la API falla, el mensaje y Reintentar* |

El acceso también lee del servidor (`/sesion`), y tiene su espera y su error con *Reintentar*
(`segun_rol_test.dart`); el estado vacío no le corresponde.

**Los dos anchos del RNF-04**, 1366 × 768 (una computadora portátil) y 768 × 1024 (una tableta
vertical), se prueban en las tres vistas con lo que más ocupa: un nombre largo, una pizza
mitad y mitad con extra, una observación larga, lo agregado y un pedido de cada estado; en
cocina, también la banda de canal caído y la franja del sonido apagado. La comprobación
(`test/anchos_del_rnf04.dart`) mira tres cosas: que Flutter no reporte un desborde, que
ningún texto visible quede fuera del ancho de la pantalla y que nada se desplace de lado.
Quedan afuera, a propósito, la tira de extras del modal de la pizza y cada campo de texto de
una línea, que corre lo escrito cuando no cabe, como en cualquier formulario: ninguno de los
dos desplaza la página. Antes de usarla, la comprobación se calibró: rechazó un texto fuera de
la pantalla, una lista que se desplazaba de lado y un desborde.

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
| CP-05 | CA-03.1 | Cocina cambia el estado de un pedido | Recepción lo ve en menos de 2 s, sin recargar | Peor caso de 262 ms en 30 repeticiones (mediana 231 ms), en producción | ✅ | [`tiempo-real.txt`](reportes/tiempo-real.txt) (*cambio de estado -> recepcion*) |
| CP-06 | CA-03.2 | Se cae el canal en vivo | Aviso y *Recargar* para ver el estado actual | La banda al segundo; sin red, en el acto; *Recargar* relee sin recargar la página | ✅ | app: *un corte en vivo se avisa al segundo…*, *Recargar lee de nuevo…*; tarjeta 07 (`5ba384a`) |
| CP-07 | CA-04.1 | Cocina marca listo un pedido | Recepción recibe el aviso: suena, dice quién y lo cuenta | El aviso, el contador de la pestaña y el título del navegador | ✅ | app: *suena, avisa quién, cuenta en la pestaña y lo dice el título del navegador* |
| CP-08 | CA-04.2 | No hay pedidos listos | Pantalla vacía, sin avisos pendientes | *"No hay pedidos por atender"* | ✅ | app: *sin pedidos lo dice, en vez de una pantalla en blanco* (pedidos de recepción) |
| CP-09 | CA-05.1 | Recepción entrega un pedido listo | Pasa a entregado y sale de la lista | 200, entregado, con el historial de los cuatro pasos | ✅ | [`sonda-pedidos.txt`](reportes/sonda-pedidos.txt) (*recepcion lo entrega*); API: *matriz: recepcion lleva un pedido listo a entregado: 200* |
| CP-10 | CA-05.2 | Recepción intenta entregar uno que no está listo | No se permite | 409 | ✅ | [`sonda-pedidos.txt`](reportes/sonda-pedidos.txt) (*no se entrega lo que no esta listo*); API: *matriz: recepcion lleva un pedido pendiente a entregado: 409* |
| CP-11 | CA-06.1 | Recepción confirma un pedido nuevo | Aparece en cocina en menos de 2 s, al final de la cola | Al final y marcado *Nuevo*; peor caso de 303 ms en 30 repeticiones (mediana 236 ms), en producción | ✅ | app: *un pedido nuevo aparece solo, al final, marcado "Nuevo", y suena el timbre*; [`tiempo-real.txt`](reportes/tiempo-real.txt) (*pedido nuevo -> cocina*) |
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
| CP-23 | RNF-01 | Peor caso de 30 propagaciones < 2 s | El pedido nuevo, 303 ms; el cambio de estado, 262 ms; lo agregado, 705 ms. En producción | ✅ | [`tiempo-real.txt`](reportes/tiempo-real.txt) |
| CP-24 | RNF-01 | Percentil 95 del listado con 50 activos y 5 usuarios < 2 s | 296 ms en 235 lecturas, ninguna fallida. En producción | ✅ | [`carga-k6.txt`](reportes/carga-k6.txt) |
| CP-25 | RNF-02 | Keycloak, token de 60 min, HTTPS, Argon2, rol en el servidor | Todo, con su evidencia | ✅ | Tarjeta 09 (plan, sección 9) |
| CP-26 | RNF-03 | La venta en 3 pasos o menos; 4 estados en cada vista con datos | La venta en 3 pasos, sin cambiar de pantalla; los 4 estados en las 3 vistas, 12 de 12 | ✅ | app: *el cliente, los productos y confirmar, en la misma pantalla: cada toque cae en su sección*; las 12 pruebas de los estados, en la sección de arriba |
| CP-27 | RNF-04 | Sin desplazamiento horizontal a 1366 y 768 px; Chrome y Edge | En las pruebas de la app, nada se desborda ni se desplaza de lado en las 3 vistas, a los 2 tamaños. En producción, en Edge 154.0.4258.53: 16 capturas, 8 por tamaño, con el ciclo de un pedido de la venta a la cancelación, sin desplazamiento de lado. Chrome 154.0.8037.98 es el navegador de las pruebas del autor de las tarjetas anteriores | ✅ | app: *la venta de punta a punta*, *los pedidos* y *la cola*, a 1366 × 768 y a 768 × 1024; capturas del 2-oct en Edge (`rnf04-1366-01` a `08` y `rnf04-768-01` a `08`) |
| CP-28 | RNF-05 | ≥ 99 % de respuestas 200 en 7 días o más; aviso de canal caído < 10 s | **100 %** del 23-sep a la 01:19 al 2-oct a las 21:48, hora de Bolivia: 9 días y 20 horas, unos 2840 sondeos, de los que unos 650 caen en la franja de 18:00 a 23:30. Ningún incidente y 0 minutos caído, en 24 h, en 7 y en 30 días. Respuesta media de 48 ms. El aviso de canal caído, al segundo (CP-06) | ✅ | UptimeRobot, el monitor *Max Pizzapp — salud de la API*, que pide `GET /api/v1/salud` cada 5 minutos (capturas del panel del 2-oct, `uptimerobot-01` y `02`); el aviso: CP-06 |

**Lo que el sondeo no ve.** Uno cada 5 minutos no ve un corte más corto que eso, como los
segundos que tarda en reiniciarse la API en un despliegue. El RNF-05 define la medición así,
y por eso el 100 % se declara con su método y sus fechas, no como «nunca se cortó».
