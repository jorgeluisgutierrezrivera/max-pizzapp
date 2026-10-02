# Plan 09 — Endurecimiento de seguridad

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 09 — Endurecimiento de seguridad
- **Incremento:** seguridad, pruebas y documento (E3)
- **Estado:** 🔵 **En curso** — aprobado el 2026-10-01, sin cambios
- **Entrada al tablero:** 2026-09-22 (orden del 22-sep); contenido fijado el 2026-10-01
- **Cierre:** —
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
- [ ] **En producción:** el autor trae el código y corre el script. Las mismas
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
- [ ] **La CSP impuesta**, en un commit aparte, y el mismo recorrido sin errores.

### Fase D — La evidencia
- [ ] Desde afuera: las cabeceras de la app, de la API y de Keycloak; la matriz de 400, 401,
      403 y 429 contra producción.
- [ ] En el servidor, solo lectura: los puertos abiertos (`ss -tlnp`: solo 22, 80 y 443) y si
      SSH acepta contraseñas.
- [ ] `npm audit` de la API; las consultas, todas parametrizadas (búsqueda en el código); la
      búsqueda de secretos en el árbol de trabajo, y la del historial, que la corre el autor
      como el 25-sep.
- [ ] La tabla de la validación doble, campo por campo, para el 2.7.
- [ ] El BRIEF (sección 8) y el README con lo implementado.

### Fase E — La prueba del autor y el cierre
- [ ] El autor entra en la web y en el APK, hace una venta, la sigue en la cocina y cierra
      sesión: todo igual que antes.
- [ ] El autor entra a la consola de Keycloak con su administrador permanente.
- [ ] Evidencia en la sección 9 y cierre.

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
| B — Keycloak | 🟡 En producción; falta reemplazar la cuenta temporal de administración | 2026-10-01 | **El script** `scripts/endurecer-keycloak.sh`, con `kcadm` dentro del contenedor: las contraseñas viajan por variables de entorno (`docker exec -e NOMBRE`, sin el valor), nunca en los argumentos ni en la salida, y la configuración de `kcadm` se borra al terminar. Usa la cuenta del `.env` o, con `KC_USUARIO`, pide la contraseña sin mostrarla. Al final muestra cómo quedó todo. **Instalación desde cero**, en un Keycloak 26.7.4 descartable que importa el realm del repositorio: (1) **la importación fallaba**: la descripción del cliente `frontend-web`, que se alargó en la tarjeta 12 al sumar el APK, tenía 266 caracteres y Keycloak admite 255 (*"Value too long for column DESCRIPTION"*). Producción no lo notó porque el realm solo se importa la primera vez; un clon nuevo, como el del tribunal, no arrancaba. Se acortó. (2) **Keycloak llena el rol por defecto al crear el realm** con cuatro roles de fábrica, aunque el archivo lo declare vacío: solo el script lo vacía, y pasa a ser un paso de la instalación, después del primer arranque. (3) Las cuentas importadas del archivo tienen solo su rol (`recepcion.demo`: `recepcion`). El script se corrió **cuatro veces seguidas** sobre ese Keycloak, con el mismo resultado. Las dos primeras se cortaban al mostrar el resumen, porque el filtro `--fields` de `kcadm` no muestra los atributos (un mapa anidado): ahora se leen del cliente entero. Antes, el script se cortaba si al `.env` le faltaba una variable opcional, como `DOMINIO` en desarrollo: también corregido. **En el Keycloak de desarrollo**, con la cuenta del `.env`: **las direcciones de retorno**, con la consulta de autorización: **200** las cuatro exactas (`https://maxpizzapp.tech/`, `tech.maxpizzapp.cocina:/callback`, `http://localhost:8090/`, `http://localhost:9999/callback`) y **400** seis parecidas (`http://localhost:1234/`, `http://127.0.0.1:8090/`, `https://maxpizzapp.tech/otra`, `http://localhost:8090/otra`, `tech.maxpizzapp.otra:/callback` y `https://maxpizzapp.tech.ejemplo.test/`). La salida, solo a la web, al APK y a la web en desarrollo; PKCE S256 se conservó. **El rol por defecto tenía cuatro roles, no dos:** además de `offline_access` y `uma_authorization`, `view-profile` y `manage-account`, los de la consola de cuenta. Quedó **vacío**. **Una cuenta nueva** (`nueva.cuenta`, creada como la crearía el negocio): su único rol es el por defecto, vacío; la contraseña de 9 caracteres, **rechazada** (*"longitud mínima 12"*); igual al usuario, **rechazada** (*"no puede ser igual al nombre de usuario"*); 18 al azar, aceptada. Entra por PKCE, y su token no trae ningún rol del sistema: la API le responde **403 `ROL_SIN_PERMISO`** en `GET /sesion`, `GET /pedidos`, `GET /productos` y `POST /pedidos`. **Argon2**, leído de la base de Keycloak sin el *hash*: las tres cuentas con `argon2`, tipo `id`, versión 1.3, 7 MB de memoria, paralelismo 1 y *hash* de 32 bytes. **La fuerza bruta:** con 5 claves equivocadas separadas 1,5 s, la detección de ataques marca `numFailures: 5`, `disabled: true` y un bloqueo de **60 s**; con la clave **correcta**, después, tampoco entra. Los eventos guardan `LOGIN_ERROR` con `invalid_user_credentials` y, ya bloqueada, `user_temporarily_disabled`. En una primera vuelta, con los intentos seguidos, la cuenta se bloqueó **al segundo fallo**: dos fallos en menos de 1 s activan el bloqueo por intentos rápidos (`quickLoginCheckMilliSeconds`), también de 60 s. La cuenta de prueba se borró, y las dos de demostración siguen entrando **En producción** (1-oct, a la noche; `09-2` = `f8072da`): el autor trajo el código y corrió el script con la cuenta del `.env`. Su resumen, igual al de desarrollo: las cuatro direcciones de retorno exactas, la salida a la web, al APK y a la web en desarrollo, PKCE S256, la política `length(12) and notUsername and hashAlgorithm(argon2)` y `bruteForceProtected: true` en los dos realms, los eventos por 7 días y el rol por defecto **vacío**. Keycloak no se reinició y las sesiones abiertas siguieron. **Desde afuera:** la consulta de autorización da **200** a las cuatro direcciones exactas y **400** a `http://localhost:1234/`, `http://127.0.0.1:8090/`, `https://maxpizzapp.tech/otra` y `tech.maxpizzapp.otra:/callback`. **Argon2**, leído de la base de Keycloak de producción sin el *hash*: `recepcion.demo`, `cocina.demo` y la cuenta de administración, las tres con `argon2`. `probar_pedidos.py` contra producción, con las dos cuentas por PKCE por la dirección de las sondas: **TODO CORRECTO**, con sus 401 y 403, y cerró los 31 pedidos que creó. **Falta:** la cuenta de administración sigue siendo la temporal de arranque (`maxpizzapp-admin`, `is_temporary_admin`); la reemplaza el autor en la próxima sesión |
| C — La CSP de la app | 🟡 En informe en producción; impuesta en el `09-4`, falta verificarla | 2026-10-02 | **Lo que carga la app**, medido en producción el 1-oct: CanvasKit desde `www.gstatic.com` y dos fuentes (Roboto y Noto Sans Symbols) desde `fonts.gstatic.com`. **Con `--no-web-resources-cdn`**, el `flutter_bootstrap.js` compilado trae `useLocalCanvasKit: true`, y CanvasKit (`canvaskit.wasm` y `canvaskit.js`) sale del propio origen. Las fuentes siguen en `fonts.gstatic.com`. **La réplica local:** la app compilada en release, igual que para producción, servida por un Caddy 2 con el mismo bloque de la app y la misma CSP, cambiando solo las direcciones (el canal en `ws://localhost:8091`, Keycloak en `http://localhost:8082`), contra la API, la base y el Keycloak de desarrollo. Va en el puerto 8091 porque el 8090 lo ocupa otro programa de la máquina del autor; esa dirección se sumó un momento al Keycloak de desarrollo y se quitó al terminar, volviendo a correr `endurecer-keycloak.sh`. **Primero se calibró la herramienta:** una imagen de `example.com` cargada a propósito aparece en la consola como infracción en modo informe, así que la consola sí muestra lo que la CSP bloquearía. **En modo informe**, recorriendo la carga de la app, el acceso de recepción por Keycloak, el canje del código por los tokens, la carta, las 18 fotos de pizzas y las de bebidas, las fuentes y la pestaña de pedidos con **"En vivo"** (el canal por WebSocket): **ningún aviso**, salvo el provocado. **Impuesta** (`Content-Security-Policy`), lo mismo con la app recargada: carga, entra, la carta, los pedidos y "En vivo"; **cerrar sesión** pasa por Keycloak y vuelve al acceso; y **cocina** entra y ve su cola con "En vivo". **Ningún bloqueo** en la consola. **El Caddyfile de producción**, con la CSP en modo informe y `Permissions-Policy`, pasa `caddy validate`, y `caddy adapt` muestra la CSP con el dominio resuelto (`wss://maxpizzapp.tech`, `https://auth.maxpizzapp.tech`). **Para aplicarlo en el servidor hay que reiniciar Caddy, no recargarlo:** el Caddyfile está montado como archivo suelto, y `git pull` lo reemplaza por uno nuevo que un `caddy reload` no vería **En producción, en modo informe** (2-oct; `09-3` = `b54936f`): el autor trajo el código y reinició Caddy. Desde afuera, la app responde con `Content-Security-Policy-Report-Only` y `Permissions-Policy`, y la API conserva su propia CSP, la de Helmet. El agente publicó la app compilada con `--no-web-resources-cdn` (`20261002-090354`). En el navegador, contra `https://maxpizzapp.tech`: la comprobación silenciosa de la sesión con Keycloak vuelve con `login_required`, como corresponde sin sesión; **CanvasKit llega desde `maxpizzapp.tech`** (`/canvaskit/chromium/canvaskit.wasm` y `.js`), las fuentes desde `fonts.gstatic.com`, la portada y el logo desde el propio origen; y **ningún aviso de la CSP** en la consola. El tramo con la sesión iniciada no lo recorre el agente en producción, porque no escribe contraseñas reales: quedó medido en la réplica, y lo recorre el autor en la fase E con la CSP ya impuesta |
| D — La evidencia | ⬜ | | |
| E — La prueba del autor | ⬜ | | |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-01 | Versión inicial propuesta | Lo que el E3 pide para la seguridad y lo que la revisión del código del 1-oct encontró abierto (sección 1) |
| 2026-10-01 | **Aprobado** por el autor, sin cambios | |
| 2026-10-01 | Fase B: se quitan **los cuatro** roles del rol por defecto, no dos; el script es también un paso de la **instalación nueva**; el realm del repositorio, con la descripción del cliente acortada; el agente **no** entra a la consola para comprobar la cuenta temporal | El rol por defecto también traía los dos de la consola de cuenta. Al crear un realm, Keycloak llena el rol por defecto aunque el archivo diga otra cosa. La descripción larga, de la tarjeta 12, hacía fallar la importación desde cero. La contraseña del administrador permanente es solo del autor |
| 2026-10-02 | Fase C: el recorrido con la sesión iniciada, en modo informe y en modo impuesto, se mide en una **réplica local** con el mismo build y la misma CSP; en producción, el modo informe se verifica en la carga, y el recorrido con sesión lo hace el autor en la fase E | En producción, el agente no puede entrar: no escribe contraseñas reales. La réplica recorre los dos roles con las cuentas de desarrollo y mide lo mismo; solo cambian las direcciones |

---

## 11. Cierre

—
