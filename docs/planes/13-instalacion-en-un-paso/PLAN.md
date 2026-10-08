# Plan 13 — Instalación local en un solo paso

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 13 — Instalación local en un solo paso
- **Incremento:** documento y entrega final (E4)
- **Estado:** ✅ **Hecho** — aprobado el 2026-10-04; la prueba de instalación se hizo el
  2026-10-08 y la tarjeta se cerró ese mismo día
- **Entrada al tablero:** 2026-10-04 (enunciado del E4)
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que una persona que no es el autor, en una computadora con Windows y **sin ninguna
herramienta de desarrollo**, instale el sistema completo siguiendo el manual de instalación
y que funcione: las dos cuentas de prueba entran, una venta llega a cocina en vivo, cocina
la marca lista y recepción la entrega.

1. **Solo hace falta Docker Desktop.** Ni Git, ni Node, ni Flutter, ni Python, ni una
   consola de Linux.
2. El código se baja **como ZIP desde GitHub**, o con `git clone` quien lo tenga.
3. **Un solo paso**, doble clic en `instalar.cmd`:
   - crea el `.env` con contraseñas al azar;
   - construye y levanta los servicios;
   - deja Keycloak configurado, con las contraseñas de las cuentas de prueba;
   - comprueba que todo responde.

   Al terminar, muestra la dirección y abre el navegador.
4. **Repetirlo no rompe nada:** no pisa el `.env` ni borra los datos.
5. **El trabajo diario del autor y producción no cambian.**

**Por qué:** la lista previa del enunciado del E4 exige *"Otra persona siguió el manual de
instalación — y el sistema levantó"*. La persona es **el encargado de recepción**, en la
computadora del local (revisión del 8-oct). Hoy, levantarlo en local pide cinco herramientas
(Docker, Flutter, Git Bash, Python y Node) y cuatro pasos a mano, uno de ellos con `kcadm`
dentro de un contenedor. Así él no lo puede hacer.

---

## 2. Alcance

**Incluye:**

- **La app compilada dentro de Docker**, a partir del código del repositorio, y servida en
  `http://localhost:8090` con el mismo único origen que en producción (D-62).
- **Keycloak configurado en el mismo arranque**, con el mismo script de seguridad que se usa
  en producción, y las contraseñas de las cuentas de prueba (D-64).
- **El instalador** (D-63):
  - `instalar.cmd` en la raíz, que llama a `scripts/instalar.ps1`, para Windows;
  - `scripts/instalar.sh`, para Linux y macOS, que es el que usa la integración continua.
- **La instalación probada sola en la integración continua**, desde un clon limpio (D-65).
- El README: `Requisitos previos` y `Puesta en marcha en local` reescritos con dos caminos:
  la instalación de prueba, en un paso, y el entorno de desarrollo, como hoy.
- **El manual de instalación y despliegue** (Anexo B del documento), escrito para alguien
  que no programa. Va paso a paso, con capturas y con los mensajes de error frecuentes.
- **La prueba del encargado de recepción**, con su evidencia: cuánto tardó, dónde dudó y qué
  se corrigió.

**No incluye:**

- **El APK en local:** apunta a producción, y compilarlo pide el SDK de Android y la llave
  de firma. El README ya explica cómo compilarlo; el Anexo B lo resume para un desarrollador.
- **Cambios en el despliegue de producción.** El Anexo B describe el que existe (README,
  *Despliegue en el servidor*).
- **Imágenes ya construidas en un registro** (GHCR o Docker Hub): ver D-62.
- **HTTPS en local:** es `localhost`, igual que en desarrollo.
- **El respaldo programado de la base y el registro por petición.** Los pide la plenaria P4,
  no el enunciado del E4; quedan para después de la entrega.

---

## 3. Decisiones de diseño

### D-62 · La app se compila dentro de Docker, desde el código del repositorio

- **Un `frontend/Dockerfile` en dos etapas:**
  1. **Compilar:** Debian *slim* con el SDK de **Flutter 3.44.8**, la misma versión del README
     y de la integración continua: el código de su etiqueta, sin historia, **verificado por el
     commit exacto** que Flutter publica para esa versión. Después la herramienta baja solo el
     SDK de Dart y lo de la web (ver la revisión del 4-oct). Corre `flutter pub get --enforce-lockfile` y
     `flutter build web --release --no-web-resources-cdn`, con la dirección de Keycloak
     **local** (`http://localhost:${KEYCLOAK_PORT}`) como argumento de compilación.
  2. **Servir:** la misma imagen de Caddy que producción, con un `docker/caddy/Caddyfile.local`
     que sirve la app y reenvía `/api/*` y `/socket.io/*` a la API. Para el navegador, la app
     y la API comparten origen, como en `https://maxpizzapp.tech`.
- **Puerto 8090, fijo.** Es la dirección de retorno exacta que el realm ya declara para la web
  local (D-53), así que el realm no cambia.
- **Sin CSP ni HSTS en local:** es `http` en una sola máquina. La política medida es la de
  producción (D-55) y no se toca.
- **Un perfil de Compose, `completo`.** El servicio `web` y el de configuración de Keycloak
  solo arrancan con `--profile completo`. Así el `flutter run` del autor, que también usa el
  8090, no choca con ellos, y la descripción del entorno de desarrollo sigue en **un solo
  archivo**. No se suma un tercer archivo de Compose; el de producción ya obliga a mantener dos.
- **Se descartó publicar imágenes ya construidas.** El manual tiene que probar que el sistema
  **se levanta desde el repositorio**. Un registro agrega un paso de publicación y la
  visibilidad del paquete, y la imagen se desfasaría del código. **El precio:** la primera
  instalación baja el SDK de Flutter y tarda más. Se mide en la fase A.
- **Se descartó el paquete completo de Flutter** (1,55 GB, con los artefactos de todas las
  plataformas): a la velocidad medida en la máquina del autor, cerca de 1 MB/s, son 26
  minutos solo de descarga.
- **Se descartó la imagen de Flutter de Cirrus Labs:** trae el SDK de Android, varios GB que
  la web no usa.

### D-63 · Un solo paso: el instalador crea el `.env` y comprueba que todo responde

- **`instalar.cmd`**, en la raíz, se abre con doble clic. Llama a
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\instalar.ps1`. El *Bypass* vale
  solo para ese proceso: **no cambia ninguna configuración de seguridad de la PC**, y deja
  correr el script aunque Windows lo marque como bajado de Internet.
- **Compatible con Windows PowerShell 5.1**, el que trae Windows 10, y con los textos sin
  tildes, como el resto de los scripts del repositorio. `.gitattributes` deja `*.cmd` y
  `*.ps1` con saltos de línea de Windows.
- **Qué hace, en orden:**
  1. **Comprueba Docker.** Si Docker Desktop no está abierto o no responde, lo dice en
     castellano y con qué hacer.
  2. **Comprueba los puertos** 8090, 8082 y 3001. Si uno está ocupado, dice cuál y no sigue.
  3. **El `.env`.** Si no existe, lo crea a partir de `.env.example` y reemplaza cada valor
     `cambia_…` por 24 caracteres al azar, generados con el generador criptográfico del
     sistema. **Nunca pisa un `.env` que ya existe.**
  4. **Una instalación anterior sin su `.env`.** Si ya hay datos de una instalación anterior
     pero el `.env` es nuevo (por ejemplo, porque se volvió a descomprimir el ZIP), las
     contraseñas no coinciden con las de la base. Lo detecta antes de levantar, lo explica y
     ofrece `instalar.cmd desde-cero`, que borra solo los datos de esta instalación.
  5. **Levanta todo:**
     `docker compose --env-file .env -f docker/docker-compose.yml --profile completo up -d --build`.
  6. **Espera** a que cada servicio esté sano y a que la configuración de Keycloak termine
     bien. La primera vez puede tardar hasta 15 minutos, y lo avisa.
  7. **Comprueba** que `http://localhost:8090/api/v1/salud` responde 200 y que la app carga.
  8. **Termina:**
     - muestra la dirección, las dos cuentas y la contraseña de prueba;
     - abre el navegador en `http://localhost:8090`.

     La contraseña de prueba es local y generada en esa PC, y sin ella no se puede entrar. Las
     contraseñas de la base y de la consola de Keycloak **no se muestran**. Las capturas del
     manual se recortan sin esa línea.
- **`scripts/instalar.sh`** hace lo mismo en Linux y macOS.

### D-64 · Keycloak se configura en el arranque, con el mismo script que producción

- **El script de seguridad se separa en dos.** La parte que corre dentro del contenedor de
  Keycloak, hoy escrita dentro de `scripts/endurecer-keycloak.sh`, pasa a un archivo propio:
  `docker/keycloak/endurecer.sh`, con la dirección del servidor como parámetro.
  `scripts/endurecer-keycloak.sh` sigue funcionando igual en desarrollo y en producción: le
  pasa ese archivo a `docker exec`.
- **Un servicio de una sola vez, `keycloak-config`**, con la misma imagen de Keycloak y
  dentro del perfil `completo`:
  - espera a que Keycloak esté sano;
  - corre `endurecer.sh` contra `http://keycloak:8080`;
  - asigna a `recepcion.demo` y `cocina.demo` la contraseña de `KEYCLOAK_DEMO_PASSWORD`;
  - termina.

  **Una sola fuente para la seguridad de Keycloak:** el entorno local y producción no
  pueden desfasarse.
- **Se puede repetir:** el script ya da siempre el mismo resultado. La contraseña generada,
  de 24 caracteres, cumple la política de Keycloak (12 o más, distinta del usuario).

### D-65 · La instalación también se prueba sola en la integración continua

- Un flujo nuevo, `.github/workflows/instalacion.yml`, en Ubuntu 24.04 y desde un clon
  limpio:
  - corre `bash scripts/instalar.sh`;
  - pide un token por PKCE con cada cuenta de prueba (`probar_acceso_pkce.py`, contra el
    entorno recién levantado);
  - con cada token, pide una ruta de su rol y una del otro **a través del 8090**: 200 y 403.
- **Por qué:** la persona prueba el manual una vez, y la integración continua avisa si un
  commit posterior rompe la instalación. Ese commit puede ser la tarjeta 08, que suma una
  migración.

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase 0 — La PC del local (la revisa el autor, en paralelo)

Requisitos de Docker Desktop para Windows 10, consultados en su documentación el
**2026-10-04**:

- [x] Windows 10 de 64 bits, versión **22H2 (compilación 19045)**: `winver`.
- [x] **8 GB de RAM**: *Configuración → Sistema → Acerca de*.
- [x] **Virtualización habilitada**: *Administrador de tareas → Rendimiento → CPU →
      Virtualización: Habilitado*. Si dice *Deshabilitado*, se activa en la BIOS.
- [x] Unos **20 GB libres** en el disco y conexión a Internet.
- [x] Una cuenta de administrador a mano. Docker Desktop se instala sin ella, pero activar WSL 2
      la pide una vez, y después hay que reiniciar.

Docker solo da soporte en las versiones de Windows que Microsoft todavía mantiene.
Windows 10 22H2 lo está hasta el 13-oct-2026, con las actualizaciones extendidas. **Si la PC
no cumple, se decide con el autor otra computadora para la prueba antes del miércoles.**

**Revisión del 8-oct:** la prueba se hizo en la **computadora nueva del local**, que ya
cumplía todo: Windows 11 Home 25H2 (compilación 26200.8457), 8 GB de RAM, la virtualización
habilitada, 30 GB libres y 280 Mbps. La PC con Windows 10 ya no se usó.

### Fase A — La app en Docker
- [x] `frontend/Dockerfile` en dos etapas y `frontend/.dockerignore` (sin `build/`,
      `.dart_tool/` ni lo compilado de Android).
- [x] `docker/caddy/Caddyfile.local`.
- [x] El servicio `web` en `docker/docker-compose.yml`, en el perfil `completo`.
- [x] En esta máquina: las dos cuentas entran por `http://localhost:8090`, una venta llega a
      cocina en vivo, lista y entregada.
- [x] Medidos: el tamaño de cada imagen, el tiempo de la primera compilación y la memoria
      máxima que usa la compilación de Flutter.

### Fase B — Keycloak en el arranque
- [x] `docker/keycloak/endurecer.sh`, separado del script de hoy; `scripts/endurecer-keycloak.sh`
      lo usa.
- [x] En el Keycloak de desarrollo, el script reformado da **la misma salida** que el de hoy.
- [x] El servicio `keycloak-config` en el perfil `completo`.
- [x] Sobre una base de Keycloak recién creada: el realm queda endurecido y las dos cuentas
      entran con la contraseña del `.env`. Corrido dos veces, el mismo resultado.

### Fase C — El instalador
- [x] `instalar.cmd`, `scripts/instalar.ps1` y `scripts/instalar.sh`; `.gitattributes`.
- [x] El README: requisitos previos y puesta en marcha, con los dos caminos.
- [x] **En Linux, desde cero:** dentro de un Docker limpio (`docker:dind`), con una copia del
      repositorio, como hará la integración continua.
- [x] **En Windows, en la máquina del autor**, con `powershell.exe` 5.1:
  - el `.env` generado, los mensajes de Docker cerrado y de puerto ocupado, y el aviso de
    instalación anterior;
  - ~~la instalación completa desde cero~~: pasa a la fase E, la del encargado de recepción. En esta
    máquina obligaba a recrear la base de desarrollo, y cada parte ya se probó por separado
    (revisión del 4-oct).
- [x] Repetir la instalación no pisa el `.env` ni borra datos.

### Fase D — La integración continua y el manual
- [x] `.github/workflows/instalacion.yml`, en verde en GitHub después del push.
- [x] El Anexo B redactado para alguien que no programa: pasos numerados, capturas con datos
      ficticios, cómo detener y volver a abrir el sistema, y los mensajes de error frecuentes.
      Las capturas son las fotos de la prueba de la fase E.
- [x] El autor revisa el Anexo B antes de dárselo al encargado de recepción (lo llevó impreso
      a la prueba).

### Fase E — La prueba del encargado de recepción y el cierre
- [x] **El encargado de recepción**, en la computadora del local, sigue el Anexo B **sin
      ayuda** (mirar está permitido; dictar los pasos, no):
  - instala Docker Desktop;
  - baja el ZIP;
  - corre `instalar.cmd`;
  - entra con las dos cuentas, hace una venta con datos ficticios, cocina la marca lista y
    recepción la entrega.

  Lo hizo, con **tres intervenciones** del autor: ver la fila E de la sección 9.
- [x] Se anotan las horas de inicio y fin ~~de cada paso~~, y cada lugar donde dudó o se trabó.
      Fotos de la pantalla sin la contraseña. Se anotaron solo el inicio y el fin de toda la
      prueba, no los de cada paso.
- [x] Lo que falló se corrige en el manual o en los scripts, en el mismo día.
- [x] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **App:** `frontend/Dockerfile` y `frontend/.dockerignore` *(nuevos)*.
- **Contenedores:**
  - `docker/docker-compose.yml`: los servicios `web` y `keycloak-config`, en el perfil
    `completo`;
  - `docker/caddy/Caddyfile.local` *(nuevo)*.
- **Identidad:**
  - `docker/keycloak/endurecer.sh` *(nuevo, separado del script de hoy)*;
  - `scripts/endurecer-keycloak.sh`;
  - `docker/keycloak/README.md`.
- **Instalador:** `instalar.cmd`, `scripts/instalar.ps1` y `scripts/instalar.sh` *(nuevos)*;
  `.gitattributes`.
- **Integración continua:** `.github/workflows/instalacion.yml` *(nuevo)*.
- **Repositorio:** `README.md` y los comentarios de `.env.example` (el instalador completa
  los valores `cambia_…`).
- **Fuera del repositorio:** el Anexo B, en el documento, y la evidencia de la prueba.

**No cambian** la API, la base de datos, el realm, la app ni el despliegue de producción.

---

## 6. Cómo se prueba

| Qué | Cómo | Resultado esperado |
|---|---|---|
| La app en Docker | `--profile completo up -d --build` en esta máquina | Las dos cuentas entran por el 8090 y el flujo completo funciona |
| Keycloak en el arranque | Base de Keycloak nueva, arranque y segundo arranque | El realm endurecido y las cuentas con la contraseña del `.env`, las dos veces |
| El script de producción sigue igual | `bash scripts/endurecer-keycloak.sh` en desarrollo | La misma salida que antes de separarlo |
| Instalación desde cero en Linux | `instalar.sh` en un Docker limpio | Salud 200, la app carga, tokens de las dos cuentas, 200 y 403 |
| Instalación en Windows | `instalar.cmd` con PowerShell 5.1 | Los mensajes de cada caso, y la instalación completa |
| Repetir | Correr el instalador otra vez | El mismo `.env`, los mismos datos |
| Integración continua | El flujo nuevo después del push | En verde, desde un clon limpio |
| Sin secretos | Revisión del repositorio y de las imágenes | Ningún `.env` ni contraseña; el `.env` se genera en cada PC |
| **Otra persona** | El encargado de recepción, con el Anexo B, en la computadora del local | **El sistema levanta y el flujo completo funciona** |

---

## 7. Criterios de aceptación

- En una PC que solo tiene Docker Desktop, el sistema se instala en un paso a partir del ZIP
  de GitHub. Al terminar, la salud responde 200 y la app abre en `http://localhost:8090`.
- Las dos cuentas de prueba entran. Una venta llega a cocina en vivo, cocina la marca lista y
  recepción la entrega. Con el token de un rol, la ruta del otro responde 403.
- Repetir la instalación no pisa el `.env` ni borra datos. Una instalación anterior sin su
  `.env` se detecta y se explica, sin fallar a mitad.
- El entorno de desarrollo del autor (`flutter run`) y producción siguen igual.
- Ningún secreto en el repositorio ni en las imágenes.
- La instalación pasa en la integración continua desde un clon limpio.
- La instalación local publica sus tres puertos (8090, 8082 y 3001) solo en `127.0.0.1`
  (revisión del 8-oct).
- **El encargado de recepción siguió el manual en la computadora del local y el sistema
  levantó.** El criterio decía *"con Windows 10"*; la computadora nueva del local tiene
  Windows 11 (revisión del 8-oct).

---

## 8. Requisitos que cubre

- **De la entrega (E4):**
  - *"Otra persona siguió el manual de instalación — y el sistema levantó"*;
  - el **Anexo B**, manual de instalación y despliegue;
  - *"Repositorio final: … README completo"*.
- **Institucionales:**
  - **#6**: el README con instrucciones de ejecución local, ahora en un paso;
  - **#7**: credenciales fuera del repositorio, con el `.env` generado en cada máquina.
- **Del documento:** el **2.9**, *configuración de entornos* (desarrollo, instalación local y
  producción).

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| 0 — La PC del local | ✅ Verificada | 2026-10-08 | El 4-oct, la PC de entonces: **Windows 10 22H2** y **8 GB de RAM**, con la **virtualización deshabilitada**. El 8-oct la prueba se hizo en la **computadora nueva del local**, que ya cumplía todo, con foto de cada dato: ASUS ZenBook, **Windows 11 Home 25H2** (compilación 26200.8457), Ryzen 5 4500U, **8 GB** (7,42 utilizables), **virtualización habilitada** en el Administrador de tareas, 30 GB libres y **280 Mbps** en fast.com |
| A — La app en Docker | ✅ Verificada | 2026-10-04 | **La imagen:** `frontend/Dockerfile` en dos etapas. El SDK de Flutter 3.44.8 se clona sin historia desde su etiqueta y se verifica contra el commit publicado (`058e0af…`); la compilación falla si no coincide. La etapa final es `caddy:2-alpine` con la app en `/srv`. **Primera compilación, sin nada en caché, en la máquina del autor:** 747 s (12,5 min), repartidos así: paquetes de Debian 145 s, clonar Flutter 100 s, SDK de Dart (222 MB) y artefactos de la web 393 s, paquetes de la app 28 s, compilación de la app 68 s. Antes se había probado el paquete completo de Flutter: pesa **1,55 GB**, y la conexión medida da cerca de 1 MB/s (20 MB en 21 s), así que se descartó (revisión del 4-oct). **Tamaños:** la imagen de la app pesa 149 MB. La compilación de Flutter llega a **1,24 GB de memoria como máximo**, medida con `docker stats` cada segundo. Ya en marcha, el sistema completo usa unos 860 MB: Keycloak 697 MB, la API 87 MB, la base 53 MB y la app 19 MB. **El puerto:** la app se publica en `127.0.0.1:8090`. En la máquina del autor, el notificador de Wondershare ocupa `0.0.0.0:8090` (E-009), y aun así la app arranca y responde: el enlace específico a `127.0.0.1` tiene prioridad. **En marcha, sobre el entorno de desarrollo** (`--profile completo up -d`): la app sana; `/api/v1/salud` responde 200 `{"estado":"ok","baseDeDatos":"ok"}` a través del 8090; la app trae las cabeceras `X-Content-Type-Options`, `X-Frame-Options: DENY`, `Referrer-Policy` y `Cache-Control: no-cache`. **Las sondas a través del 8090:** `probar_acceso_pkce.py` termina en TODO CORRECTO con las dos cuentas; `probar_errores.py` con `API_URL=http://localhost:8090/api/v1` da 16 de 16 (401 sin token y con la firma alterada, 403 de cocina al vender, cancelar y agregar, los 400, 413 y 415, y el acceso con la contraseña equivocada). `medir_aviso.py`, también a través del 8090, por WebSocket y con 5 mediciones: pedido nuevo a cocina, mediana de 22 ms; cambio de estado a recepción, 20 ms; lo agregado a cocina, 19 ms. Los 5 pedidos de la medición quedaron cerrados, y el reporte versionado de producción se restauró sin cambios. **En el navegador:** `http://localhost:8090` sirve la app compilada en la imagen. *Iniciar sesión* lleva a Keycloak con `redirect_uri=http://localhost:8090/`; con `recepcion.demo` vuelve a la app, entra como Recepción y carga la carta. Un primer intento falló porque el pegado no llega al navegador integrado, y Keycloak lo contó como contraseña equivocada. *Cerrar sesión* pasa por Keycloak y devuelve la app a `localhost:8090`. Con `cocina.demo` entra como Cocina, ve la cola con los dos pedidos de prueba de la base de desarrollo y el indicador **En vivo** en verde. La venta, la marca de listo y la entrega desde la interfaz quedan para la prueba de la encargada; por el canal ya las recorrió `medir_aviso.py` |
| B — Keycloak en el arranque | ✅ Verificada | 2026-10-04 | **El script separado:** `docker/keycloak/endurecer.sh` (la parte de adentro), y `scripts/endurecer-keycloak.sh` se la pasa a `docker exec` por la entrada estándar. **Contra el Keycloak de desarrollo da la misma salida, byte por byte, que el script de antes** (`diff` sin diferencias). **El servicio `keycloak-config`:** las variables se leen dentro del contenedor (`$$`), así que `docker compose config` no muestra ninguna contraseña. Sobre el realm de desarrollo aplicó los pasos 1 a 4, asignó las dos contraseñas de prueba (paso 5) y salió con código 0. La app arrancó recién después, por `service_completed_successfully`. **Corrido otra vez, el mismo resultado y código 0.** **Sobre una base de Keycloak recién creada**, en la prueba desde cero de la fase C: los pasos 1 a 5 y código 0. El rol por defecto, que Keycloak llena con cuatro roles de fábrica al crear el realm, queda vacío (`[ ]`), y las dos cuentas entran con la contraseña del `.env` nuevo |
| C — El instalador | ✅ Verificada | 2026-10-04 | **En Windows, con `powershell.exe` 5.1.26100 (el mismo motor de Windows 10), en la máquina del autor:** (1) **datos anteriores sin su `.env`**, en una copia de la carpeta sin `.env`: lo detecta antes de levantar nada, explica que las contraseñas ya no coinciden, propone `instalar.cmd desde-cero`, sale con código 1 y **no crea el `.env`**; (2) **Docker que no responde** (`DOCKER_HOST` apuntado a un caño inexistente): *"Docker Desktop no esta abierto, o todavia esta arrancando…"*, código 1; (3) **una opción desconocida**: la nombra y lista las válidas, código 1; (4) **la instalación completa sobre la instalación existente**, con el `.env` y los datos de desarrollo: los seis pasos, la salud 200 y la app, el aviso final con la dirección y las cuentas, y el navegador abierto en `http://localhost:8090`. Código 0, **73 s**. El 8090 ocupado en `0.0.0.0` por el notificador de Wondershare ya no corta la instalación (revisión del 4-oct); (5) **`instalar.cmd`** con la ruta `E:\Max Pizzapp v2\codigo` (con espacios): pasa la opción al script, muestra *"Presione una tecla para continuar"* y devuelve el código de salida. (6) **generar el `.env`**, con el mismo código del instalador y PowerShell 5.1, a partir de un `.env.example` con saltos de Windows (el peor caso): sin marca de codificación ni retornos de carro, las 75 líneas intactas, ningún `cambia_`, `POSTGRES_USER=maxpizzapp` y tres contraseñas de 24 letras y números, distintas en cada corrida. **Mensajes:** de usted, como el manual. **En Linux, desde cero, dentro de un Docker limpio** (`docker:dind`), sin el `.env`, los volúmenes ni las imágenes construidas de esta máquina (solo se le precargaron las imágenes base): `CI=true bash scripts/instalar.sh` creó el `.env`, bajó y compiló todo y terminó con código 0 en **905 s (15 min)**. Dentro de ese mismo Docker: `probar_acceso_pkce.py` dio TODO CORRECTO y `probar_errores.py` a través del 8090 dio 16 de 16. **Repetirlo** dejó el `.env` byte por byte igual (*"Ya hay un .env: se usa el que esta"*) y volvió a terminar en código 0. Salió un ruido: el primer `curl` de la espera imprimía *"Connection reset by peer"* antes de que la app estuviera lista. Ahora es silencioso. **La instalación completa en Windows desde cero** es la de la encargada (fase E): en la máquina del autor obligaba a recrear la base de desarrollo, y cada parte ya se probó por separado |
| D — Integración continua y manual | ✅ Verificada | 2026-10-08 | **El flujo** `.github/workflows/instalacion.yml`, sin avisos de `actionlint` 1.7.12 (con `shellcheck`). Subido en `b18695e`. **Primera corrida en GitHub, en verde** (run `37232481276`, Ubuntu 24.04, en una máquina limpia): instalación en un paso con `instalar.sh` **156 s**, el acceso PKCE con las dos cuentas, la matriz de 401, 403 y 400 a través del 8090, la segunda instalación con el `.env` sin cambios (22 s) y la bajada. En total, **186 s**. El paso *"Si algo fallo"* no corrió. Las cuatro corridas de *Pruebas* de los commits `ea8071d`, `86ed727`, `6c6b869` y `b18695e`, en verde. **El manual:** el Anexo B, redactado de usted, con la Parte 1 para quien instala en su computadora (B.1 a B.7) y la Parte 2 para el servidor y el APK (B.8 a B.12), con los tiempos medidos. **El 8-oct:** el autor lo llevó impreso a la prueba; las capturas son las fotos de esa prueba, y el manual se corrigió con lo que enseñó (fila E) |
| E — La prueba del encargado de recepción | ✅ Verificada | 2026-10-08 | **Quién y dónde:** el encargado de recepción, que usa la computadora para lo básico (encenderla, navegar) y no programa, en la computadora del local (fila 0), con el Anexo B impreso. Navegador: Google Chrome 154.0.8037.98. **Tiempo:** de 13:00 a 14:30, **1 h 30 min** en total, con Docker Desktop y el problema de WSL incluidos. Las horas de cada paso no se anotaron. La compilación del paso [4/6] marcaba 385 s cuando le faltaban 2 de sus 29 pasos (foto), y el SDK de Dart (222 MB) bajó a 1,9 MB/s. **Lo que hizo solo:** comprobar la computadora (B.1), bajar y extraer el ZIP (B.3), `instalar.cmd` del [1/6] al [6/6] (B.4), la venta y detener y volver a abrir el sistema (B.6). **El resultado: el sistema levantó y el flujo completo funcionó.** El pedido 1 (datos ficticios, Para llevar, una Carnívora, una Clásica y una Soda personal: Bs 108) llegó a cocina como *recién llegado*; cocina lo empezó y lo marcó listo; recepción recibió el aviso *"Pedido 1 … está listo"* y lo entregó, y las dos colas quedaron vacías. `/api/v1/salud` respondió `{"estado":"ok","baseDeDatos":"ok"}`, y en Docker Desktop el proyecto `maxpizzapp` quedó en marcha. **Tres intervenciones del autor:** (1) **WSL.** Docker Desktop **4.94.0** ya no muestra *Use WSL 2 instead of Hyper-V*: propone *Per-user installation (Recommended)*, sin permisos de administrador, y así no activa la Plataforma de máquina virtual de Windows. Al abrirlo dijo *"Virtual Machine Platform not enabled"*. El autor corrió en una terminal de administrador `Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform` y `wsl --install` (que además bajó Ubuntu, que no hace falta), y reinició. (2) **La ventana de cocina:** le indicó abrirla en una ventana privada, aunque la ventana del instalador ya lo decía. (3) **La contraseña de prueba:** lo ayudó a entrar con ella. **Un aviso que el manual no tenía:** el Firewall de Windows preguntó si las redes podían acceder a *Docker Desktop Backend*, y se eligió *Permitir*. Keycloak (8082, con su consola de administración) y la API (3001) se publicaban en todas las direcciones. **Su opinión, anotada por el autor:** el manual está completo, pero tendría que ser más interactivo o con fotos, y más específico. **Lo corregido el mismo día:** (a) **el Anexo B:** preparar Windows antes de Docker Desktop (`wsl --install --no-distribution` y reiniciar); las pantallas de Docker 4.94 (*Per-user*, *Close*); qué elegir en el aviso del Firewall (*Cancelar*); la ventana privada en Chrome y en Edge, y por qué una normal no sirve; dónde está la contraseña, cómo copiarla y cómo volver a verla; una foto de la prueba en cada paso; y cuatro filas nuevas en los problemas frecuentes. (b) **El código (commit `13-4`):** Keycloak y la API se publican solo en `127.0.0.1`, como la app; `instalar.ps1` deja pasar, en los tres puertos, a otro programa que escuche en `0.0.0.0` (E-009); el README, con el paso de WSL. **Probado en la máquina del autor:** `instalar.ps1` con PowerShell 5.1 sobre la instalación existente, código 0 en 264 s. Antes, 8082 y 3001 escuchaban en `::`, es decir, en todas las direcciones; ahora, solo en `127.0.0.1`. Desde la IP de la red (`192.168.1.7`) los dos rechazan la conexión. `probar_acceso_pkce.py` dio TODO CORRECTO con las dos cuentas, y la página de acceso, abierta por `localhost:8082` en un navegador, cargó sus 9 recursos con 200. **Sin probar:** el manual corregido en una computadora nueva, y Windows 10, que sigue en los requisitos porque Docker lo admite: la computadora del local y la del autor tienen Windows 11. **Evidencia:** 46 fotos, fuera del repositorio, sin la contraseña |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-04 | Versión inicial propuesta | El enunciado del E4 exige que otra persona siga el manual de instalación y el sistema levante. La sigue la encargada de recepción, en la PC del local, con Windows 10. El autor aprobó la tarjeta antes de escribir el plan |
| 2026-10-04 | **Aprobado** por el autor, sin cambios | Decisiones D-62 a D-65 registradas en la bitácora |
| 2026-10-04 | Fase A: el SDK de Flutter se baja como el código de su etiqueta, sin historia, verificado por el commit exacto (`058e0af…`), en vez del paquete de 1,55 GB verificado por SHA-256. La app se publica solo en `127.0.0.1:8090` | Medido en la máquina del autor: el paquete pesa 1,55 GB y la conexión da cerca de 1 MB/s. El commit es una verificación tan fuerte como la suma, y así se bajan solo el SDK de Dart y lo de la web. La instalación local es para esa PC, no para otros equipos de la red |
| 2026-10-04 | Fases A y B en **un solo commit** (`13-1`); el instalador queda en `13-2`, la integración continua en `13-3` y el cierre en `13-E` | El servicio `web` depende de `keycloak-config` dentro del mismo `docker-compose.yml`: separarlos dejaba un commit con un compose que no arranca |
| 2026-10-04 | Fase C: en Windows, un programa que escucha el 8090 en `0.0.0.0` no corta la instalación; los mensajes del instalador, **de usted** | El notificador de Wondershare de la PC del autor ocupa `0.0.0.0:8090`, y la app igual arranca y responde, porque la dirección exacta `127.0.0.1` tiene prioridad. Lo que sí estorba es otro programa en `127.0.0.1` o en IPv6, y eso se sigue revisando. El manual trata de usted, y la encargada tiene que leer lo mismo en los dos |
| 2026-10-04 | Fase C: la instalación completa de Windows desde cero pasa a la fase E (en ese momento, la encargada de recepción, en Windows 10) | En la máquina del autor, el proyecto y los nombres de los contenedores son los mismos que en desarrollo, y probarla obligaba a borrar la base de desarrollo. Cada parte se probó por separado con PowerShell 5.1 (generar el `.env`, los mensajes, la instalación completa sobre la existente y `instalar.cmd`), y la instalación desde cero se probó en Linux, en un Docker limpio |
| 2026-10-08 | Fase E: la prueba la hace **el encargado de recepción**, en la **computadora nueva del local, con Windows 11 Home 25H2**. Se ajustan el objetivo, la fase 0, la tabla de pruebas y el criterio | Antes de la prueba, el negocio cambió de dependiente y de computadora. Windows 10 sigue en los requisitos, porque Docker Desktop lo admite, pero queda sin una prueba real: la máquina del autor también tiene Windows 11 |
| 2026-10-08 | Fase E: Keycloak (8082) y la API (3001) se publican solo en `127.0.0.1`, como la app, y el instalador deja pasar en los tres puertos a otro programa en `0.0.0.0`. Va en su propio commit, `13-4`, antes del cierre (D-79) | En la prueba, el Firewall de Windows preguntó si dejaba pasar a *Docker Desktop Backend*, y con *Permitir* la consola de Keycloak y la API quedaban al alcance de otros equipos del local. La instalación local es para esa computadora. Producción no cambia: tiene su propio archivo y no publica esos puertos. Aprobado por el autor el 8-oct |
| 2026-10-08 | Fase E: el Anexo B prepara Windows **antes** de Docker Desktop, con `wsl --install --no-distribution` y un reinicio (D-80) | Docker Desktop 4.94 propone instalarse por usuario, sin administrador, y así no activa la Plataforma de máquina virtual que WSL 2 necesita. La fase 0 ya lo preveía (*activar WSL 2 pide la cuenta de administrador una vez*), pero el manual lo dejaba en manos del instalador de Docker |

---

## 11. Cierre

- **Commits de la tarjeta:**
  - `ea8071d` el plan (13-P, 4-oct);
  - `86ed727` la app en Docker y Keycloak en el arranque (fases A y B, un solo commit: ver la
    revisión del 4-oct);
  - `6c6b869` el instalador, con el README (fase C);
  - `b18695e` la integración continua (fase D);
  - `e635749` lo que la prueba de instalación mandó corregir: los puertos solo en
    `127.0.0.1`, el control de puertos del instalador, el paso de WSL en el README y la
    evidencia de las fases 0, D y E (13-4, 8-oct);
  - el cierre (13-E) lleva este apartado y el índice de planes.
- **Criterios de aceptación (sección 7):** los ocho cumplidos.
  - **En un paso, desde el ZIP, en una PC que solo tiene Docker Desktop:** la prueba del
    encargado de recepción (fila E), con la salud en 200 y la app en `http://localhost:8090`.
  - **Las dos cuentas, la venta en vivo, lista y entregada, y el 403 del otro rol:** el flujo,
    en la prueba de la fila E; el 403 cruzado, en la integración continua y en las sondas de la
    fase A, a través del 8090.
  - **Repetir no pisa el `.env`; una instalación sin su `.env` se explica:** fase C, en
    Windows y en Linux, y la segunda instalación de la integración continua.
  - **El desarrollo y producción siguen igual:** `flutter run` no cambió; con los puertos en
    `127.0.0.1`, la sonda de acceso del entorno de desarrollo sigue en verde, y el teléfono en
    desarrollo usa `adb reverse`, que llega a `localhost`. Producción usa su propio archivo y
    no se tocó.
  - **Sin secretos:** el `.env` se genera en cada PC; las fotos de la prueba no muestran la
    contraseña.
  - **La integración continua, desde un clon limpio:** *Instalacion* en verde desde
    `b18695e`, y también para `e635749`, con los puertos nuevos (run `37858086453`): la
    instalación en 175 s, el acceso PKCE con las dos cuentas, los 401, 403 y 400 a través del
    8090 y la segunda instalación con el `.env` sin cambios; 3 min 30 s en total. *Pruebas*,
    también en verde.
  - **Los tres puertos solo en `127.0.0.1`:** medido en la máquina del autor (fila E).
  - **Otra persona siguió el manual y el sistema levantó:** el encargado de recepción, el
    8-oct, en la computadora del local, con tres intervenciones del autor que se corrigieron el
    mismo día en el manual y en el código.
- **Requisitos:** los de la sección 8. Del E4, *"otra persona siguió el manual de instalación
  — y el sistema levantó"* y el Anexo B; los institucionales #6 (el README con la ejecución
  local, en un paso) y #7 (credenciales fuera del repositorio). Decisiones: D-62 a D-65, D-79 y
  D-80; el error de la prueba, E-017.
- **Queda sin probar:** el manual corregido en una computadora nueva, y Windows 10 (fila E).
- **No cambiaron** la API, la base de datos, el realm, la app ni el despliegue de producción.
