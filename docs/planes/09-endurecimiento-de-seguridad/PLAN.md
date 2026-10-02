# Plan 09 — Endurecimiento de seguridad

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 09 — Endurecimiento de seguridad
- **Incremento:** seguridad, pruebas y documento (E3)
- **Estado:** ✅ **Hecho** — en producción desde el 2026-10-02 y probado por el autor con la
  web y el APK. Aprobado el 2026-10-01, sin cambios
- **Entrada al tablero:** 2026-09-22 (orden del 22-sep); contenido fijado el 2026-10-01
- **Cierre:** 2026-10-02
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Cerrar lo que la seguridad del sistema todavía deja abierto, y dejar **la evidencia** de lo
que ya estaba bien, porque el E3 la pide con estas palabras: *"Un rol que solo se esconde en
el frontend no está implementado. Una prueba sin evidencia no existe."*

Lo que ya existe, y esta tarjeta **no** rehace: Keycloak con *Authorization Code* y PKCE, el
token de 60 minutos, el bloqueo tras 5 intentos fallidos, la validación del token (firma,
emisor, vigencia y audiencia) y del rol en cada ruta, el 401 que vuelve al acceso (tarjeta
07), la validación en la app y en la API con un solo formato de error, las consultas
parametrizadas, los secretos en `.env` y HTTPS con HSTS en Caddy.

Lo que falta, revisado en el código el 1-oct:

1. **La API no manda cabeceras de seguridad propias.** Solo apaga `x-powered-by`. El BRIEF
   (sección 8) prevé Helmet desde el E1.
2. **La API no limita las peticiones.** Un script puede mandarle miles por segundo. (El
   `rateLimit: true` de `autenticacion.js` es de `jwks-rsa`: limita cuántas veces la API pide
   las claves a Keycloak, no cuántas peticiones recibe.)
3. **Un texto con caracteres de control llega a la base.** PostgreSQL no admite el carácter
   nulo en un texto: un nombre con `\u0000` haría fallar la consulta y la API respondería
   **500** en lugar de **400**. Se confirma con una prueba antes de corregirlo.
4. **Keycloak acepta cualquier puerto de `localhost` como dirección de retorno**
   (`http://localhost:*` y `http://127.0.0.1:*`), también en producción. La tutoría T3 pidió
   restringirlas a las exactas que se usan.
5. **Keycloak no tiene política de contraseñas**, y el algoritmo de *hash* es el que trae por
   defecto (Argon2 desde la versión 25), sin que nada lo fije ni lo muestre.
6. **Una cuenta nueva nace con dos roles de Keycloak** (`offline_access` y
   `uma_authorization`, los de fábrica). Ninguno abre la API, pero el E3 pide *"las cuentas
   nuevas nacen con el menor privilegio"*: el mínimo es ninguno.
7. **La consola de administración de Keycloak** está en Internet
   (`https://auth.maxpizzapp.tech/admin`) con la **cuenta temporal de arranque**, que la
   propia consola marca para reemplazar, y el realm `master` **sin protección de fuerza
   bruta** (viene apagada de fábrica).
8. **La app no tiene política de contenido (CSP).** El Caddyfile lo dejó dicho: *"se define
   en la tarjeta de endurecimiento, cuando se sepa qué necesita de verdad el Flutter
   compilado"*. Ya se sabe: medido en producción el 1-oct, la app carga CanvasKit desde
   `www.gstatic.com` y dos fuentes desde `fonts.gstatic.com`.

---

## 2. Alcance

**Incluye:**

- **En la API:** cabeceras de seguridad con Helmet; un límite de peticiones por IP con
  respuesta 429 en el formato único de error; el rechazo de los caracteres de control en los
  textos libres; y un tamaño máximo de mensaje chico en el canal en vivo, que no recibe nada
  de los clientes.
- **En Keycloak**, con un script versionado que se aplica igual en desarrollo y en
  producción: direcciones de retorno exactas, política de contraseñas con Argon2 explícito,
  el rol por defecto vacío, el registro de los eventos de acceso y la protección de fuerza
  bruta del realm `master`. El autor reemplaza la cuenta temporal de administración.
- **En la app web:** CanvasKit servido desde el propio dominio y una CSP medida, primero en
  modo informe y después impuesta, más `Permissions-Policy`.
- **La evidencia para el 2.7:** cabeceras vistas desde afuera, la matriz 400/401/403/429, el
  bloqueo tras 5 intentos, el algoritmo de *hash*, la cuenta nueva sin rol, las direcciones
  rechazadas, los puertos del servidor, `npm audit`, la búsqueda de secretos y una tabla de
  la validación doble (cada dato de entrada, su regla en la app y en la API).

**No incluye:**

- **Rotar el token de renovación** (que cada renovación invalide el anterior). Dos pestañas
  de la misma persona comparten la sesión de Keycloak: la que renueva primero dejaría fuera a
  la otra. El riesgo que cubre (un token de renovación robado) ya está acotado: los tokens
  viven solo en memoria y la sesión dura 10 horas como máximo.
- **Acortar el token de 60 minutos**: es lo que declara el RNF-02.
- **Limitar las conexiones del canal en vivo por IP.** Cada conexión exige un token válido,
  que la API verifica en memoria sin consultar a Keycloak, y el canal no acepta mensajes.
- **Restringir la consola de Keycloak por IP.** El autor la administra desde una conexión
  con IP dinámica. La protegen la contraseña del administrador permanente y el bloqueo por
  fuerza bruta.
- **Segundo factor (MFA)**: fuera de alcance para el piloto de un local.
- **Un escaneo de vulnerabilidades automatizado** (por ejemplo, OWASP ZAP): si sobra tiempo,
  en el E4.
- **El tema visual de Keycloak**: tarjeta 11.

---

## 3. Decisiones de diseño

### D-52 · La API pone sus cabeceras y limita las peticiones por IP, con un límite generoso

- **Helmet 8**, con una CSP propia de una API que solo devuelve JSON (`default-src 'none';
  frame-ancestors 'none'`). **HSTS no lo pone la API**: lo pone Caddy, que es quien termina
  TLS. Así hay una sola fuente para cada cabecera.
- **`express-rate-limit` 8**, en memoria (hay un solo proceso de la API), por IP, sobre todo
  `/api/v1`. La IP es la del cliente, no la de Caddy: la API ya confía solo en el proxy de la
  red interna (`trust proxy` en `app.js`), y una prueba lo comprueba.
- **600 peticiones por minuto por IP**, configurable con `LIMITE_PETICIONES_POR_MINUTO`.
  Generoso a propósito: **todos los dispositivos del local salen a Internet por la misma
  IP**, y las pruebas contra producción (las sondas y k6, en la tarjeta 10) también. Diez por
  segundo sostenidas están muy por encima del uso real más intenso (una venta cada pocos
  segundos) y muy por debajo de lo que manda un script de ataque.
- **Pasado el límite, 429** con el formato único: `{ "error": { "codigo":
  "DEMASIADAS_PETICIONES", "mensaje": "…" } }`, y las cabeceras estándar `RateLimit` y
  `Retry-After`. La app ya muestra el `mensaje` de cualquier error de la API.
- El límite se aplica **antes** de validar el token: una avalancha sin token también se
  corta.

### D-53 · La seguridad de Keycloak se aplica con un script versionado, igual en todos lados

- `--import-realm` **no sobrescribe** un realm que ya existe: lo que cambie en
  `realm-maxpizzapp.json` no llega solo a producción. Hasta hoy, cada ajuste en producción se
  hizo a mano en la consola. **`scripts/endurecer-keycloak.sh`** lo hace con `kcadm`, sin
  clics y repetible: se prueba en desarrollo y se corre igual en producción. El realm del
  repositorio queda con lo mismo, para una instalación desde cero.
- **Las direcciones de retorno, exactas y las mismas en los dos entornos**:
  - `https://maxpizzapp.tech/`, la web (la app vuelve siempre a la raíz);
  - `tech.maxpizzapp.cocina:/callback`, el APK;
  - `http://localhost:8090/`, la web en desarrollo;
  - `http://localhost:9999/callback`, **las sondas** (`probar_acceso_pkce.py`,
    `probar_pedidos.py`, `medir_aviso.py`). Entran con PKCE contra producción y son la
    evidencia del 401/403 y del RNF-01 que pidió el docente. Es una dirección de *loopback*
    con puerto fijo, el patrón que el RFC 8252 prevé para clientes nativos.

  Se descartó mantener dos listas (desarrollo y producción): se desincronizan sin avisar, y
  cada dirección de la lista común es exacta.
- **Los orígenes web**, explícitos: `https://maxpizzapp.tech` y `http://localhost:8090`. El
  `+` de hoy los deducía de las direcciones de retorno.
- **`sslRequired` se queda en `external`.** Con `all`, Keycloak rechazaría a la API, que lee
  sus claves por la red interna de Docker, sin TLS.

### D-54 · Las cuentas nuevas nacen sin ningún rol, y la contraseña se guarda con Argon2 a la vista

- **El rol por defecto del realm, vacío.** Se le quitan `offline_access` (permite pedir
  tokens de renovación que no vencen con la sesión, y la app no los usa) y
  `uma_authorization` (para un tipo de autorización que el sistema no usa). Una cuenta nueva
  no tiene ningún rol: la API le responde 403 en todas las rutas, y la app no la deja pasar
  de la pantalla de error, con el mensaje de la API. El registro abierto ya estaba apagado: las cuentas las crea el negocio.
- **Política de contraseñas:** `length(12) and notUsername and hashAlgorithm(argon2)`. El
  *hash* con Argon2 ya era el de fábrica; ahora lo fija la configuración y queda a la vista.
  La evidencia es el algoritmo registrado en la credencial de cada cuenta, leído de la base
  de Keycloak **sin** leer el *hash*.
- **Los eventos de acceso**, guardados 7 días (inicio de sesión, fallos, salida). Sirven para
  ver un intento de fuerza bruta, y son la evidencia del bloqueo.
- **El realm `master`**, el de la consola, con la misma protección de fuerza bruta que el del
  sistema. **La cuenta temporal de arranque se reemplaza** por una permanente con una
  contraseña que elige y guarda el autor. El agente nunca la ve.

### D-55 · CanvasKit se sirve desde el propio dominio, y la CSP se mide antes de imponerla

- **`flutter build web --no-web-resources-cdn`**: CanvasKit, el motor que dibuja la app, sale
  del propio dominio y no de `www.gstatic.com`. Así **ningún script viene de un tercero** y
  la CSP puede decir `script-src 'self'`. El costo: la primera carga baja unos 3 MB
  comprimidos desde el servidor en lugar de la red de Google; después el navegador lo
  revalida con un 304.
- **Las fuentes siguen viniendo de `fonts.gstatic.com`.** Flutter las descarga solo cuando el
  texto las necesita (Roboto y un símbolo). Servirlas desde el propio dominio obliga a
  empaquetarlas en la app y a cambiar el tema: no entra en esta tarjeta.
- **La CSP propuesta**, a confirmar con la medición:

  ```
  default-src 'self';
  script-src 'self' 'wasm-unsafe-eval';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: blob:;
  font-src 'self' https://fonts.gstatic.com;
  connect-src 'self' wss://maxpizzapp.tech https://auth.maxpizzapp.tech https://fonts.gstatic.com;
  object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'
  ```

  `'wasm-unsafe-eval'` lo exige CanvasKit, que es WebAssembly. `'unsafe-inline'` en los
  estilos lo exigen el fondo crema del `index.html` y los estilos que Flutter inserta al
  arrancar. Se acepta porque **los scripts no lo llevan**: un estilo inyectado no ejecuta
  código. `auth.maxpizzapp.tech` es el canje del código por los tokens.
- **Primero en modo informe** (`Content-Security-Policy-Report-Only`): el navegador avisa en
  la consola lo que la política bloquearía, sin bloquear nada. Se recorren todas las
  pantallas. Recién sin avisos se impone. Una CSP puesta a ciegas rompe la app, y eso se
  descubre el día de la entrega.
- La CSP va en el bloque de Caddy que sirve la app, **no** en el del sitio entero: las
  respuestas de la API llevan la suya, la de Helmet.

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — La API
- [x] Helmet 8 y `express-rate-limit` 8, con versión exacta.
- [x] Las cabeceras de Helmet en toda respuesta de la API, sin HSTS, con la CSP de JSON.
- [x] El límite por IP sobre `/api/v1`, configurable, con 429 en el formato único.
- [x] Los caracteres de control rechazados con 400 en el nombre, la observación y el motivo
      de cancelación. Primero, la prueba que muestra el 500 de hoy.
- [x] El canal en vivo con un mensaje máximo de 16 KB (hoy, 1 MB).
- [x] `LIMITE_PETICIONES_POR_MINUTO` en `.env.example`; el 429 en `docs/api/openapi.yaml`.
- [x] Pruebas: las cabeceras, el 429 con su formato y sus cabeceras, que el límite cuenta por
      la IP del cliente detrás de Caddy (dos IP distintas no se suman), los caracteres de
      control y que el canal sigue conectando con un token real. `npm test` en verde.
- [x] **En producción** (el autor trae el código y reconstruye solo la API): las cabeceras
      vistas con `curl`, el 429 desde afuera y `probar_pedidos.py` en TODO CORRECTO, que
      además prueba que el límite no molesta al uso real.

### Fase B — Keycloak
- [x] `scripts/endurecer-keycloak.sh`: idempotente; usa la cuenta de administración del
      `.env` y, si no está, la pide; nunca imprime una contraseña.
- [x] `realm-maxpizzapp.json` con lo mismo, y su README al día.
- [x] **En desarrollo:** el script aplicado. Las cuatro direcciones exactas, que pasan (HTTP
      200), y cualquier otra rechazada (400); la contraseña corta, rechazada al asignarla; una
      cuenta nueva sin rol, que recibe 403 en `/sesion` y en `/pedidos`; 5 intentos fallidos
      y la cuenta bloqueada, visto en la detección de ataques y en los eventos; y Argon2 en
      la credencial de las dos cuentas de demostración. `probar_acceso_pkce.py` sigue
      entrando.
- [x] **En producción:** el autor trae el código y corre el script. Las mismas
      comprobaciones desde afuera, sin bloquear las cuentas de demostración. Después, el
      autor crea su administrador permanente en la consola y borra el temporal, y vuelve a
      correr el script con esa cuenta: su resumen ya no muestra ninguna cuenta temporal. (El
      agente no entra a la consola: no maneja esa contraseña.)

### Fase C — La CSP de la app
- [x] `scripts/publicar-web.sh` con `--no-web-resources-cdn`.
- [x] El Caddyfile con la CSP en **modo informe** y `Permissions-Policy` en el bloque de la
      app.
- [x] Publicada la app y recargado Caddy: en el navegador, sin un solo aviso de la CSP en la
      consola al recorrer el acceso, Keycloak, la vuelta, la venta, los pedidos, la cocina, el
      canal en vivo y el cierre de sesión. CanvasKit llega desde `maxpizzapp.tech`.
- [x] **La CSP impuesta**, en un commit aparte, y el mismo recorrido sin errores.

### Fase D — La evidencia
- [x] Desde afuera: las cabeceras de la app, de la API y de Keycloak; la matriz de 400, 401,
      403 y 429 contra producción.
- [x] En el servidor, solo lectura: los puertos abiertos (`ss -tlnp`: solo 22, 80 y 443) y si
      SSH acepta contraseñas.
- [x] `npm audit` de la API; las consultas, todas parametrizadas (búsqueda en el código); la
      búsqueda de secretos en el árbol de trabajo, y la del historial, que la corre el autor
      como el 25-sep.
- [x] La tabla de la validación doble, campo por campo, para el 2.7.
- [x] El BRIEF (sección 8) y el README con lo implementado.

### Fase E — La prueba del autor y el cierre
- [x] El autor entra en la web y en el APK, hace una venta, la sigue en la cocina y cierra
      sesión: todo igual que antes.
- [x] El autor entra a la consola de Keycloak con su administrador permanente.
- [x] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **API:**
  - `backend/package.json` y `package-lock.json`: `helmet` y `express-rate-limit`;
  - `backend/src/app.js`: las cabeceras y el límite;
  - `backend/src/config.js`: `LIMITE_PETICIONES_POR_MINUTO`;
  - `backend/src/precio.js` y `backend/src/rutas/pedidos.js`: los caracteres de control;
  - `backend/src/tiempo-real.js`: el tamaño máximo de mensaje del canal;
  - `backend/test/seguridad.test.js` *(nuevo)*.
- **Identidad:** `docker/keycloak/realm-maxpizzapp.json` y `docker/keycloak/README.md`.
- **Proxy:** `docker/caddy/Caddyfile`.
- **Scripts:** `scripts/endurecer-keycloak.sh` *(nuevo)* y `scripts/publicar-web.sh`.
- **Documentación:** `docs/api/openapi.yaml` (el 429), `docs/BRIEF.md` (sección 8),
  `README.md` y `.env.example`.

No cambia la base de datos ni el código de la app Flutter. El APK no se recompila: su
dirección de retorno no cambia.

---

## 6. Cómo se prueba

| Qué | Cómo | Resultado esperado |
|---|---|---|
| Lo de antes sigue igual | `npm test`, con las 273 pruebas de hoy | En verde, más las nuevas |
| Las cabeceras | Pruebas de la API y `curl -I` contra producción | Las de Helmet, sin `X-Powered-By`; HSTS una sola vez |
| El límite | Prueba con un límite bajo, y una ráfaga contra producción | 429 con el formato único y `Retry-After`; otra IP sigue pasando |
| Caracteres de control | Prueba con `\u0000` en el nombre, la observación y el motivo | 400, nunca 500 |
| Direcciones de retorno | La consulta de autorización con cada dirección | 200 las cuatro exactas; 400 cualquier otra, como `http://localhost:1234/` |
| Cuenta nueva | Una cuenta creada en desarrollo, sin rol | 403 en `/sesion` y `/pedidos`; la app no pasa de la pantalla de error |
| Fuerza bruta | 5 intentos fallidos en desarrollo | La cuenta bloqueada: detección de ataques y eventos |
| Argon2 | La credencial en la base de Keycloak, sin el *hash* | `"algorithm":"argon2"` |
| La CSP | El navegador, en modo informe y después impuesta | Ningún aviso al recorrer todas las pantallas |
| Producción | `probar_pedidos.py` y la prueba del autor | TODO CORRECTO; la web y el APK, igual que antes |

---

## 7. Criterios de aceptación

- Toda respuesta de la API lleva las cabeceras de seguridad, y ninguna anuncia la tecnología
  del servidor.
- Una IP que pasa de 600 peticiones por minuto recibe 429 en el formato único, sin afectar a
  otra IP. El uso real y las sondas contra producción nunca lo alcanzan.
- Ningún dato de entrada hace responder 500 a la API: un texto con caracteres de control
  recibe 400.
- Keycloak acepta solo las cuatro direcciones de retorno exactas, guarda las contraseñas con
  Argon2 por configuración, exige 12 caracteres, crea las cuentas nuevas sin ningún rol,
  registra los accesos y bloquea tras 5 intentos, también en la consola de administración.
  La cuenta temporal de administración ya no existe.
- La app web corre con una CSP impuesta, sin scripts de terceros y sin avisos en la consola.
- **La web y el APK siguen igual**, sin regresiones en las pruebas ni en producción.
- Ningún secreto en el repositorio, en el historial ni en la salida de los scripts.

---

## 8. Requisitos que cubre

- **Del sistema:** **RNF-02** (contraseñas con *hash* gestionadas por el proveedor, HTTPS y
  autorización en el servidor), ahora con la evidencia de cada parte.
- **Institucionales:** **#2** autenticación y control por rol; **#7** secretos fuera del
  repositorio; **#8** validación de entradas en cliente y servidor.
- **De la entrega (E3):** *"contraseñas en hash (bcrypt o argon2)"*, *"las cuentas nuevas
  nacen con el menor privilegio"* y *"validación doble"*, con la evidencia para el **2.7
  Seguridad**, que es nuevo en el E3.
- **De la tutoría T3:** las direcciones de `localhost` del realm, restringidas a las exactas.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — La API | ✅ Verificada | 2026-10-01 | **Las dependencias:** `helmet` 8.3.0 y `express-rate-limit` 8.7.0, con versión exacta; `npm audit`: 0 vulnerabilidades. **Las cabeceras** (Helmet, sin HSTS, que lo pone Caddy): `Content-Security-Policy: default-src 'none';frame-ancestors 'none'`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: no-referrer`, `Cross-Origin-Opener-Policy` y `Cross-Origin-Resource-Policy` en `same-origin`, y ningún `X-Powered-By`, tanto en las respuestas correctas como en los errores. En producción, Caddy reemplaza `X-Frame-Options` (por `DENY`) y `Referrer-Policy` con las suyas, iguales o más estrictas. **El límite:** 600 peticiones por minuto por IP, configurable con `LIMITE_PETICIONES_POR_MINUTO` (un valor inválido no deja arrancar la API), aplicado antes de leer el cuerpo y de validar el token. Pasado el límite, 429 `DEMASIADAS_PETICIONES` en el formato único, con `Retry-After` y las cabeceras `RateLimit`. La API anuncia el límite al arrancar. **Los caracteres de control:** el hallazgo se confirmó **antes** de corregirlo, contra la API local con la base real: una venta con `\u0000` en el nombre respondía **500** `ERROR_INTERNO`, y el registro decía `invalid byte sequence for encoding "UTF8": 0x00` (código 22021). Ahora el nombre, la observación y el motivo rechazan los caracteres de control (C0, DEL y C1) con 400, antes de tocar la base. La observación admite saltos de línea, porque su campo en la app tiene dos renglones. La misma venta, con la API local reconstruida: **400** `VENTA_INVALIDA`, *"El nombre tiene caracteres no validos."* **El canal:** mensaje máximo de 16 KB (era 1 MB). **`npm test`: 284 de 284** (273 anteriores y **11 nuevas** en `seguridad.test.js`): las cabeceras en un 200, un 401 y un 404; el 429 con su formato, `Retry-After` y las cabeceras de seguridad; dos IP detrás de Caddy que no se suman; el límite que corta antes del token; el límite por defecto y los valores inválidos; siete caracteres de control en el nombre, y los acentos, la eñe y los emojis que siguen entrando; la observación con saltos de línea sí y con otros controles no; el 400 por la API sin tocar la base, en la venta y en el motivo; y el canal, que acepta el saludo con un token real y corta un mensaje de más de 16 KB. El contrato OpenAPI suma el 429 y la regla de los textos. **Con la API local reconstruida, contra la base y el Keycloak reales:** `probar_pedidos.py` termina en **TODO CORRECTO**, sin ningún 429. Usó **186 de las 600** peticiones del minuto, menos de un tercio del límite. **En producción** (1-oct, 20:14; el autor trajo el código, hizo el respaldo de la base, aplicó la migración 09 del celular, que llegó en el mismo despliegue, y reconstruyó solo la API): la API arrancó sana con *"limite: 600 peticiones por minuto por IP"*, y Keycloak, la base y Caddy siguieron arriba sin recrearse. **Las cabeceras, vistas con `curl` desde afuera:** las de Helmet y las de Caddy; HSTS una sola vez, la de Caddy; `X-Frame-Options: DENY` y `Referrer-Policy: strict-origin-when-cross-origin`, también de Caddy; ningún `Server` ni `X-Powered-By`. **`probar_pedidos.py`, con las dos cuentas por PKCE:** **TODO CORRECTO**, sin ningún 429, y cerró los 31 pedidos que creó. **La venta con `\u0000` en el nombre:** **400** `VENTA_INVALIDA`. **El 429 desde afuera:** 700 peticiones sin token, en paralelo y por IPv6, en 4 s: **600 respondieron 401 y 100 respondieron 429**. El 429 trae el formato único, `Retry-After: 57` y las cabeceras de seguridad. Desde la misma máquina, por IPv4, se seguía entrando (200). **Lo que salió:** (1) la primera ráfaga, de 650, no llegó al límite, porque la máquina repartía las conexiones entre IPv4 e IPv6 (el dominio tiene las dos direcciones) y cada familia cuenta aparte. Es lo correcto: son dos direcciones distintas, y en IPv6 la clave es la red /56 entera, así que cambiar de dirección dentro de ella no esquiva el límite. (2) La segunda, de 650 forzada por IPv6, tampoco, porque un proceso de `curl` por petición tardó más de un minuto y la ventana, que es fija, se reinició a mitad. Con conexiones reutilizadas, las 700 entraron en 4 s |
| B — Keycloak | ✅ Verificada | 2026-10-02 | **El script** `scripts/endurecer-keycloak.sh`, con `kcadm` dentro del contenedor: las contraseñas viajan por variables de entorno (`docker exec -e NOMBRE`, sin el valor), nunca en los argumentos ni en la salida, y la configuración de `kcadm` se borra al terminar. Usa la cuenta del `.env` o, con `KC_USUARIO`, pide la contraseña sin mostrarla. Al final muestra cómo quedó todo. **Instalación desde cero**, en un Keycloak 26.7.4 descartable que importa el realm del repositorio: (1) **la importación fallaba**: la descripción del cliente `frontend-web`, que se alargó en la tarjeta 12 al sumar el APK, tenía 266 caracteres y Keycloak admite 255 (*"Value too long for column DESCRIPTION"*). Producción no lo notó porque el realm solo se importa la primera vez; un clon nuevo, como el del tribunal, no arrancaba. Se acortó. (2) **Keycloak llena el rol por defecto al crear el realm** con cuatro roles de fábrica, aunque el archivo lo declare vacío: solo el script lo vacía, y pasa a ser un paso de la instalación, después del primer arranque. (3) Las cuentas importadas del archivo tienen solo su rol (`recepcion.demo`: `recepcion`). El script se corrió **cuatro veces seguidas** sobre ese Keycloak, con el mismo resultado. Las dos primeras se cortaban al mostrar el resumen, porque el filtro `--fields` de `kcadm` no muestra los atributos (un mapa anidado): ahora se leen del cliente entero. Antes, el script se cortaba si al `.env` le faltaba una variable opcional, como `DOMINIO` en desarrollo: también corregido. **En el Keycloak de desarrollo**, con la cuenta del `.env`: **las direcciones de retorno**, con la consulta de autorización: **200** las cuatro exactas (`https://maxpizzapp.tech/`, `tech.maxpizzapp.cocina:/callback`, `http://localhost:8090/`, `http://localhost:9999/callback`) y **400** seis parecidas (`http://localhost:1234/`, `http://127.0.0.1:8090/`, `https://maxpizzapp.tech/otra`, `http://localhost:8090/otra`, `tech.maxpizzapp.otra:/callback` y `https://maxpizzapp.tech.ejemplo.test/`). La salida, solo a la web, al APK y a la web en desarrollo; PKCE S256 se conservó. **El rol por defecto tenía cuatro roles, no dos:** además de `offline_access` y `uma_authorization`, `view-profile` y `manage-account`, los de la consola de cuenta. Quedó **vacío**. **Una cuenta nueva** (`nueva.cuenta`, creada como la crearía el negocio): su único rol es el por defecto, vacío; la contraseña de 9 caracteres, **rechazada** (*"longitud mínima 12"*); igual al usuario, **rechazada** (*"no puede ser igual al nombre de usuario"*); 18 al azar, aceptada. Entra por PKCE, y su token no trae ningún rol del sistema: la API le responde **403 `ROL_SIN_PERMISO`** en `GET /sesion`, `GET /pedidos`, `GET /productos` y `POST /pedidos`. **Argon2**, leído de la base de Keycloak sin el *hash*: las tres cuentas con `argon2`, tipo `id`, versión 1.3, 7 MB de memoria, paralelismo 1 y *hash* de 32 bytes. **La fuerza bruta:** con 5 claves equivocadas separadas 1,5 s, la detección de ataques marca `numFailures: 5`, `disabled: true` y un bloqueo de **60 s**; con la clave **correcta**, después, tampoco entra. Los eventos guardan `LOGIN_ERROR` con `invalid_user_credentials` y, ya bloqueada, `user_temporarily_disabled`. En una primera vuelta, con los intentos seguidos, la cuenta se bloqueó **al segundo fallo**: dos fallos en menos de 1 s activan el bloqueo por intentos rápidos (`quickLoginCheckMilliSeconds`), también de 60 s. La cuenta de prueba se borró, y las dos de demostración siguen entrando **En producción** (1-oct, a la noche; `09-2` = `f8072da`): el autor trajo el código y corrió el script con la cuenta del `.env`. Su resumen, igual al de desarrollo: las cuatro direcciones de retorno exactas, la salida a la web, al APK y a la web en desarrollo, PKCE S256, la política `length(12) and notUsername and hashAlgorithm(argon2)` y `bruteForceProtected: true` en los dos realms, los eventos por 7 días y el rol por defecto **vacío**. Keycloak no se reinició y las sesiones abiertas siguieron. **Desde afuera:** la consulta de autorización da **200** a las cuatro direcciones exactas y **400** a `http://localhost:1234/`, `http://127.0.0.1:8090/`, `https://maxpizzapp.tech/otra` y `tech.maxpizzapp.otra:/callback`. **Argon2**, leído de la base de Keycloak de producción sin el *hash*: `recepcion.demo`, `cocina.demo` y la cuenta de administración, las tres con `argon2`. `probar_pedidos.py` contra producción, con las dos cuentas por PKCE por la dirección de las sondas: **TODO CORRECTO**, con sus 401 y 403, y cerró los 31 pedidos que creó. **La cuenta de administración permanente** (2-oct): el autor leyó la temporal del `.env` del servidor, entró a la consola, creó su cuenta en el realm `master`, le puso contraseña (la política de 12 caracteres ya rige en `master`) y el rol `admin`, entró con ella y recién entonces borró `maxpizzapp-admin`, la temporal. El script, corrido en el servidor con `KC_USUARIO` y la contraseña pedida sin mostrarse, ya no lista ninguna cuenta con `is_temporary_admin`. En la base de Keycloak: **una sola** cuenta en `master`, permanente, con la contraseña en **Argon2** y los roles `admin` y `default-roles-master`. La contraseña de esa cuenta no está en ningún archivo. |
| C — La CSP de la app | ✅ Verificada | 2026-10-02 | **Lo que carga la app**, medido en producción el 1-oct: CanvasKit desde `www.gstatic.com` y dos fuentes (Roboto y Noto Sans Symbols) desde `fonts.gstatic.com`. **Con `--no-web-resources-cdn`**, el `flutter_bootstrap.js` compilado trae `useLocalCanvasKit: true`, y CanvasKit (`canvaskit.wasm` y `canvaskit.js`) sale del propio origen. Las fuentes siguen en `fonts.gstatic.com`. **La réplica local:** la app compilada en release, igual que para producción, servida por un Caddy 2 con el mismo bloque de la app y la misma CSP, cambiando solo las direcciones (el canal en `ws://localhost:8091`, Keycloak en `http://localhost:8082`), contra la API, la base y el Keycloak de desarrollo. Va en el puerto 8091 porque el 8090 lo ocupa otro programa de la máquina del autor; esa dirección se sumó un momento al Keycloak de desarrollo y se quitó al terminar, volviendo a correr `endurecer-keycloak.sh`. **Primero se calibró la herramienta:** una imagen de `example.com` cargada a propósito aparece en la consola como infracción en modo informe, así que la consola sí muestra lo que la CSP bloquearía. **En modo informe**, recorriendo la carga de la app, el acceso de recepción por Keycloak, el canje del código por los tokens, la carta, las 18 fotos de pizzas y las de bebidas, las fuentes y la pestaña de pedidos con **"En vivo"** (el canal por WebSocket): **ningún aviso**, salvo el provocado. **Impuesta** (`Content-Security-Policy`), lo mismo con la app recargada: carga, entra, la carta, los pedidos y "En vivo"; **cerrar sesión** pasa por Keycloak y vuelve al acceso; y **cocina** entra y ve su cola con "En vivo". **Ningún bloqueo** en la consola. **El Caddyfile de producción**, con la CSP en modo informe y `Permissions-Policy`, pasa `caddy validate`, y `caddy adapt` muestra la CSP con el dominio resuelto (`wss://maxpizzapp.tech`, `https://auth.maxpizzapp.tech`). **Para aplicarlo en el servidor hay que reiniciar Caddy, no recargarlo:** el Caddyfile está montado como archivo suelto, y `git pull` lo reemplaza por uno nuevo que un `caddy reload` no vería **En producción, en modo informe** (2-oct; `09-3` = `b54936f`): el autor trajo el código y reinició Caddy. Desde afuera, la app responde con `Content-Security-Policy-Report-Only` y `Permissions-Policy`, y la API conserva su propia CSP, la de Helmet. El agente publicó la app compilada con `--no-web-resources-cdn` (`20261002-090354`). En el navegador, contra `https://maxpizzapp.tech`: la comprobación silenciosa de la sesión con Keycloak vuelve con `login_required`, como corresponde sin sesión; **CanvasKit llega desde `maxpizzapp.tech`** (`/canvaskit/chromium/canvaskit.wasm` y `.js`), las fuentes desde `fonts.gstatic.com`, la portada y el logo desde el propio origen; y **ningún aviso de la CSP** en la consola. El tramo con la sesión iniciada no lo recorre el agente en producción, porque no escribe contraseñas reales: quedó medido en la réplica, y lo recorre el autor en la fase E con la CSP ya impuesta **Impuesta en producción** (`09-4` = `9680cf7`; el autor reinició Caddy): la app responde con `Content-Security-Policy`. En el navegador, contra `https://maxpizzapp.tech`: la app carga (CanvasKit desde el propio dominio), muestra el acceso con su portada y su logo, *Iniciar sesión* lleva a la página de Keycloak, y la consola no muestra **ningún error ni bloqueo** |
| D — La evidencia | ✅ Verificada | 2026-10-02 | **Las cabeceras, desde afuera**, de los tres orígenes. La app: la CSP impuesta, `Permissions-Policy`, HSTS, `nosniff`, `X-Frame-Options: DENY` y `Referrer-Policy: strict-origin-when-cross-origin`. La API: la CSP de Helmet (`default-src 'none'`), `Cross-Origin-Opener-Policy` y `Cross-Origin-Resource-Policy`, más las de Caddy. Keycloak: HSTS, `nosniff` y su propio `X-Frame-Options: SAMEORIGIN`. Ninguno anuncia `Server` ni `X-Powered-By`, y `http://` redirige a `https://` con un 308. **El servidor, solo lectura:** hacia afuera escuchan solo el 22 (SSH), el 80 y el 443; la base, Keycloak y la API no tienen ningún puerto publicado. **Hallazgo:** SSH acepta **contraseñas**, también para entrar como **root**, y el cortafuegos (`ufw`) está inactivo. El registro del servidor tiene **131 accesos aceptados, todos con llave**, y **946 intentos fallidos de contraseña**: robots que prueban entrar. Se propone al autor apagar la contraseña (sección 10). **Las dependencias:** `npm audit`, 0 vulnerabilidades, con las de desarrollo y sin ellas. **Las consultas:** 32 llamadas a `query`; 13 plantillas con SQL y **ninguna interpolación** (`${…}`), ningún SQL armado con `+`, y los valores siempre como `$1` a `$9`. **Los secretos, en el árbol de trabajo:** 424 archivos revisados, binarios incluidos, contra los valores reales de las cuatro variables secretas del `.env` de desarrollo (`POSTGRES_PASSWORD`, `KEYCLOAK_CLIENT_SECRET`, `KEYCLOAK_ADMIN_PASSWORD` y `KEYCLOAK_DEMO_PASSWORD`): **no aparece ninguno**. El `.gitignore` excluye `.env` y `.env.*`, salvo `.env.example`, y las llaves (`*.jks`, `key.properties`, `*.pem`, `*.p12`…). Una primera búsqueda tomó como secretas todas las variables con `KEY` en el nombre y marcó el nombre del realm y el del cliente, que son públicos: se repitió solo con las cuatro secretas. **La matriz de errores contra producción**, con las dos cuentas por PKCE: **13 de 13** como se esperaba (sección 9.2). **La validación doble**, campo por campo, en la sección 9.1. **Hallazgo y arreglo:** al repasar la validación apareció que un cuerpo de **más de 100 KB** y uno con **otro juego de caracteres** respondían **500** (`PayloadTooLargeError` y `UnsupportedMediaTypeError` en el registro), y se podían provocar **sin token**, porque el cuerpo se lee antes de validar la sesión. Ahora responden **413** `CUERPO_DEMASIADO_GRANDE` y **415** `FORMATO_NO_SOPORTADO`, en el formato único, y cualquier otro error del cliente que marque la librería responde con su propio 4xx. Confirmado contra la API local antes y después. `npm test`: **288 de 288** (2 nuevas). El contrato OpenAPI describe los tres rechazos del cuerpo. **Los documentos:** el BRIEF (sección 8) pasa Helmet y el límite de peticiones a *implementado*, con lo demás de esta tarjeta, y el README suma una sección *Seguridad* con lo que protege cada pieza y dos comprobaciones con `curl` **El arreglo, en producción** (`09-5` = `497f2dd`; el autor reconstruyó solo la API, sin que se recrearan Keycloak ni la base): sin token, un cuerpo de 150 KB responde **413** `CUERPO_DEMASIADO_GRANDE`, y uno con `charset=latin9` o con una compresión desconocida, **415** `FORMATO_NO_SOPORTADO`. El registro de la API ya no anota esos casos como errores internos **Los secretos, en el historial de Git**, buscados por el autor en su copia del repositorio (2-oct), igual que el 25-sep: (1) los nombres de archivo de todos los commits: solo aparece `.env.example`; ninguna llave del APK (`*.jks`, `key.properties`), ningún `.env`, `.pem` ni `.p12`. (2) Tokens, llaves privadas, cadenas de conexión con clave y variables de contraseña con valor, en todos los cambios de todos los commits: solo siete líneas, todas inocuas, las tres del README que *generan* contraseñas con `openssl rand` y los cuatro valores de relleno de `.env.example` (`cambia_esta_contrasena…`, `cambia_este_secreto`). (3) Las dos contraseñas de demostración, la local y la de producción, buscadas con `git log -S`: **ningún commit** las contiene. **El historial está limpio** **SSH solo con llave, aplicado por el autor** (2-oct), después de ver los 946 intentos fallidos: un archivo `/etc/ssh/sshd_config.d/01-solo-llave.conf` con `PasswordAuthentication no`, `KbdInteractiveAuthentication no` y `PermitRootLogin prohibit-password`, que gana sobre el `50-cloud-init.conf` porque SSH usa el primer valor que encuentra. `sshd -t` lo validó antes de recargar. **Resultado:** `passwordauthentication no` y `permitrootlogin without-password`; desde una segunda ventana, sin cerrar la primera, la llave sigue entrando (`ok`), y un intento con contraseña responde `Permission denied (publickey).` sin pedirla. El cortafuegos (`ufw`) se deja apagado: hacia afuera solo escuchan el 22, el 80 y el 443, y Docker publica sus puertos por fuera de `ufw`, así que activarlo daría una protección que en realidad no tiene |
| E — La prueba del autor | ✅ Verificada | 2026-10-02 | **En producción, con todo lo de esta tarjeta ya aplicado** (la CSP impuesta, el límite de peticiones, Keycloak endurecido y SSH solo con llave), recepción en la computadora y cocina en el APK, de 10:49 a 10:58 (capturas `pc-01` a `pc-08` y `cel-01` a `cel-04`, con datos ficticios). (1) **El acceso**: la app web y el APK cargan y entran por Keycloak. (2) **La venta** de *Ana Prueba · 50000001*, para llevar: una Carnívora, una mitad Cuatro quesos y mitad Hawaiana con extra queso y una gaseosa, **Bs 138,50**. Es el primer celular que empieza con 5 en producción (D-56), y se guarda sin ningún rechazo. (3) **En el APK**, el pedido 1 llega solo, *"Nuevo · recién llegado"*, con "En vivo"; *Empezar* lo pasa a *En preparación* y *Listo* lo cierra en cocina. (4) **En recepción**, el aviso *"Pedido 1 de Ana Prueba está listo"* con *Ver pedidos*, la pestaña con *"1 listo"* y el título de la ventana *"(1) Pedido listo"*; *Entregar* deja la cola en cero. (5) **La limpieza**: los pedidos de prueba viejos (el 45 del 30-sep, entre otros) se cerraron y la cola de cocina quedó vacía antes de la venta. El autor confirma que todo funcionó igual que antes: **la CSP impuesta no rompió nada** en el tramo con la sesión iniciada, que el agente no podía recorrer en producción |


### 9.1 La validación doble, campo por campo (fase D)

La app valida para avisar a tiempo; la API vuelve a validar todo, porque es la única
validación confiable; y la base tiene la última palabra con sus restricciones. Todas las
respuestas de error tienen la misma forma: `{ "error": { "codigo", "mensaje" } }`.

| Dato | En la app | En la API | En la base | Si no cumple |
|---|---|---|---|---|
| Nombre del cliente | Obligatorio; hasta 120 caracteres (el campo no deja escribir más) | Obligatorio, texto, se recorta; hasta 120; sin caracteres de control | `cliente_nombre_no_vacio` | 400 `VENTA_INVALIDA` |
| Celular | Opcional; 8 dígitos que empiezan con 5, 6 o 7, avisado en el campo | Lo mismo, como texto | `cliente_celular_valido` (`^[5-7][0-9]{7}$`) y único | 400 `VENTA_INVALIDA` |
| Para llevar o comer aquí | Obligatorio: se elige una de dos | Booleano obligatorio | No nulo | 400 `VENTA_INVALIDA` |
| Observación | Opcional; hasta 240 caracteres, en dos renglones | Texto, hasta 240; sin caracteres de control, salvo saltos de línea | — | 400 `VENTA_INVALIDA` |
| Líneas de la venta | Al menos una pizza; las bebidas solas van por *Vender bebidas* | De 1 a 100 líneas; al menos una pizza; la venta directa, solo bebidas | — | 400 `VENTA_INVALIDA` |
| Producto, mitad y extras | Se eligen de la carta, no se escriben | Que existan en la carta; la mitad, otra pizza; una pizza *solo entera* no va por mitades; hasta 10 extras, sin repetir, solo en pizzas | Claves foráneas; la mitad distinta del producto | 400 `VENTA_INVALIDA`; 409 `PRODUCTO_NO_DISPONIBLE` si se agotó |
| Cantidad | De 1 a 999, con los botones | Entero de 1 a 999 | `detalle_pedido_cantidad_valida` (1 a 999) | 400 `VENTA_INVALIDA` |
| Total | Lo calcula la app con la misma regla que el servidor | El servidor lo recalcula; si no coincide, no guarda nada | `pedido_total_valido` (≥ 0) | 409 `PRECIO_CAMBIADO`, con el total correcto |
| Avance de estado | Solo aparece el botón que le toca al rol | El rol de la ruta, la transición válida desde el estado actual y la versión que tenía a la vista | El tipo `estado_pedido` | 400 `ESTADO_INVALIDO`; 403; 409 |
| Motivo de cancelación | Uno de tres con un toque, u otro escrito de hasta 120; sin motivo, el botón se apaga | Obligatorio, hasta 120, sin caracteres de control | No vacío, y solo en un pedido cancelado | 400 `MOTIVO_INVALIDO` |
| Número de pedido (en la ruta) | — | Entero positivo que cabe en la columna | Clave primaria | 400 `ID_INVALIDO`; 404 |
| Filtro de estado | — | Solo los cinco estados | — | 400 `FILTRO_INVALIDO` |
| El cuerpo de la petición | Lo arma la app | JSON en UTF-8, de hasta 100 KB | — | 400 `JSON_INVALIDO`; 413; 415 |
| Token y rol | La app no muestra lo que el rol no puede hacer | Firma, emisor, vigencia, audiencia y rol en cada ruta, salvo `/salud` | — | 401; 403 `ROL_SIN_PERMISO` |

### 9.2 La matriz de errores, contra producción (fase D)

2-oct, con las dos cuentas de prueba por PKCE. Ningún caso crea nada en la base: todos se
cortan antes, en la validación, en el token o en el rol.

| Esperado | Caso | Petición | Obtenido |
|---|---|---|---|
| 401 | Sin token | `GET /pedidos` | 401 `TOKEN_AUSENTE` |
| 401 | Token con la firma alterada | `GET /pedidos` | 401 `TOKEN_INVALIDO` |
| 403 | Cocina intenta vender | `POST /pedidos` | 403 `ROL_SIN_PERMISO` |
| 403 | Cocina intenta cancelar | `POST /pedidos/1/cancelacion` | 403 `ROL_SIN_PERMISO` |
| 403 | Cocina intenta agregar a un pedido | `POST /pedidos/1/lineas` | 403 `ROL_SIN_PERMISO` |
| 400 | Celular que no es boliviano | `POST /pedidos` | 400 `VENTA_INVALIDA` |
| 400 | Nombre con un carácter nulo | `POST /pedidos` | 400 `VENTA_INVALIDA` |
| 400 | Venta sin productos | `POST /pedidos` | 400 `VENTA_INVALIDA` |
| 400 | Cantidad fuera de rango (1000) | `POST /pedidos` | 400 `VENTA_INVALIDA` |
| 400 | Cuerpo que no es JSON | `POST /pedidos` | 400 `JSON_INVALIDO` |
| 400 | Filtro de estado que no existe | `GET /pedidos?estado=quemado` | 400 `FILTRO_INVALIDO` |
| 400 | Número de pedido que no es válido | `GET /pedidos/abc` | 400 `ID_INVALIDO` |
| 400 | Cancelar sin motivo | `POST /pedidos/1/cancelacion` | 400 `MOTIVO_INVALIDO` |
| 413 | Cuerpo de 150 KB, sin token | `POST /pedidos` | 413 `CUERPO_DEMASIADO_GRANDE` (antes del arreglo: 500) |
| 415 | Cuerpo con `charset=latin9`, sin token | `POST /pedidos` | 415 `FORMATO_NO_SOPORTADO` (antes: 500) |
| 415 | Cuerpo con una compresión desconocida | `POST /pedidos` | 415 `FORMATO_NO_SOPORTADO` |
| 429 | 700 peticiones en 4 s desde una IP (fase A) | `GET /pedidos` | 600 respondieron 401 y 100, 429 `DEMASIADAS_PETICIONES` |

Los 403 de recepción sobre los estados de cocina (empezar, marcar listo) necesitan un
pedido real y los prueba `probar_pedidos.py`, que también terminó en TODO CORRECTO contra
producción.

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-01 | Versión inicial propuesta | Lo que el E3 pide para la seguridad y lo que la revisión del código del 1-oct encontró abierto (sección 1) |
| 2026-10-01 | **Aprobado** por el autor, sin cambios | |
| 2026-10-01 | Fase B: se quitan **los cuatro** roles del rol por defecto, no dos; el script es también un paso de la **instalación nueva**; el realm del repositorio, con la descripción del cliente acortada; el agente **no** entra a la consola para comprobar la cuenta temporal | El rol por defecto también traía los dos de la consola de cuenta. Al crear un realm, Keycloak llena el rol por defecto aunque el archivo diga otra cosa. La descripción larga, de la tarjeta 12, hacía fallar la importación desde cero. La contraseña del administrador permanente es solo del autor |
| 2026-10-02 | Fase C: el recorrido con la sesión iniciada, en modo informe y en modo impuesto, se mide en una **réplica local** con el mismo build y la misma CSP; en producción, el modo informe se verifica en la carga, y el recorrido con sesión lo hace el autor en la fase E | En producción, el agente no puede entrar: no escribe contraseñas reales. La réplica recorre los dos roles con las cuentas de desarrollo y mide lo mismo; solo cambian las direcciones |
| 2026-10-02 | Fase D: se corrige el **500** de un cuerpo demasiado grande o con otro juego de caracteres (ahora 413 y 415), con dos pruebas | Lo encontró el repaso de la validación; se podía provocar sin token |
| 2026-10-02 | Fase D: se **propone** al autor apagar la contraseña de SSH en el servidor, y **el autor lo aplica** el mismo día | 946 intentos fallidos de contraseña en el registro, y todos los accesos reales fueron con llave. Es un cambio del sistema del servidor, que administra el autor |

---

## 11. Cierre

- **Commits de la tarjeta**, uno por fase probada:
  - `f935239` el plan (09-P);
  - `fb19f9c` la API: cabeceras, límite de peticiones y caracteres de control (A);
  - `f8072da` Keycloak con un script versionado (B);
  - `b54936f` la CSP en modo informe y CanvasKit propio (C);
  - `9680cf7` la CSP impuesta (C);
  - `497f2dd` el 413 y el 415, y la evidencia de seguridad (D).

  Fuera de la tarjeta, en el mismo despliegue que el `09-1`: `21ebbf5`, el celular que
  empieza con 5 (D-56). El cierre (09-E) lleva este apartado y el índice de planes. Lo que se
  hizo en el servidor sin commit: la configuración de Keycloak (el script), la cuenta de
  administración permanente y SSH solo con llave.
- **Criterios de aceptación (sección 7):** los siete cumplidos.
  - **Toda respuesta de la API lleva las cabeceras de seguridad**, en los aciertos y en los
    errores, y ninguna anuncia la tecnología del servidor.
  - **El límite:** a la petición 601 de una IP, 429 en el formato único, y otra IP sigue
    entrando. Las sondas usan menos de un tercio del límite.
  - **Ningún dato de entrada responde 500:** los caracteres de control reciben 400, y el
    cuerpo demasiado grande o con otro juego de caracteres, 413 y 415. Los dos 500 que
    aparecieron se confirmaron antes de corregirlos.
  - **Keycloak:** cuatro direcciones de retorno exactas, Argon2 por configuración, 12
    caracteres, las cuentas nuevas sin ningún rol, los accesos registrados, el bloqueo tras 5
    intentos también en la consola, y ninguna cuenta temporal de administración.
  - **La app web corre con la CSP impuesta**, sin scripts de terceros y sin avisos en la
    consola.
  - **La web y el APK siguen igual:** `npm test` 288 de 288, `flutter test` 280 de 280,
    `probar_pedidos.py` TODO CORRECTO contra producción y la prueba del autor.
  - **Ningún secreto** en el árbol de trabajo, en el historial ni en la salida de los
    scripts.
- **Requisitos:** RNF-02, con la evidencia de cada parte; los institucionales #2, #7 y #8; lo
  que pide el E3 sobre el *hash*, el menor privilegio y la validación doble; y el pedido de la
  tutoría T3 sobre las direcciones de `localhost`. Las secciones 9.1 y 9.2 son la base del
  apartado 2.7.
- **Lo que salió, además de lo previsto** (secciones 9 y 10): la importación del realm desde
  cero fallaba por una descripción de 266 caracteres que venía de la tarjeta 12; Keycloak
  llena el rol por defecto al crear el realm, así que el script es un paso de la
  instalación; el rol por defecto tenía cuatro roles, no dos; y SSH aceptaba contraseñas,
  con 946 intentos fallidos en el registro.
- **Queda abierto, con destino:**
  - **las 13 actualizaciones del sistema** que anuncia el servidor al entrar por SSH:
    aplicarlas antes de la defensa, en un momento sin pedidos, con un respaldo antes;
  - **los íconos de la barra de estado del APK** sobre fondo claro (de la tarjeta 12): semana
    del E4;
  - **las fuentes desde `fonts.gstatic.com`**: empaquetarlas en la app quitaría el último
    origen externo de la CSP; si sobra tiempo, en el E4.
- **Fecha de cierre:** 2026-10-02, con la tarjeta en producción y probada por el autor.
