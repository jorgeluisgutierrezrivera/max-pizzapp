# Plan 04 — App Flutter y acceso por rol

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 04 — App Flutter y acceso por rol
- **Incremento:** cimientos (acceso de punta a punta)
- **Estado:** 🟢 Aprobado — aprobado el 2026-09-23, con la decisión 8 ya revisada (desarrollo en local)
- **Entrada al tablero:** 2026-09-23
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que una persona abra **`https://maxpizzapp.tech`**, inicie sesión con su cuenta y llegue a
**la pantalla de su rol**: recepción o cocina. El rol lo confirma el servidor. Y que pueda
cerrar sesión y entrar con otra cuenta en el mismo dispositivo.

Es la primera pieza del sistema que **se ve**, y la última de los cimientos: con ella, el
flujo de acceso queda probado de punta a punta en producción, desde el navegador hasta la
base de datos. Sobre esto se construyen la carta (05) y los pedidos (06).

**Por qué va antes que el CRUD.** El CRUD sigue el patrón que ya tiene la API. Flutter web
es lo único de la vertical que nunca pasó por producción: el flujo PKCE en el navegador, las
redirecciones de Keycloak, el build servido por Caddy. Lo que falle ahí aparece al
desplegar. Es también el orden que fijó la plenaria P3: login en producción el miércoles,
CRUD el jueves.

**Deliberadamente chica.** Las pantallas por rol de esta tarjeta solo saludan y permiten
salir. Las pantallas reales llegan con las tarjetas 05 y 06.

---

## 2. Alcance

**Incluye:**

- Proyecto **Flutter web** en `frontend/`, con versiones fijadas y `pubspec.lock` versionado.
- **Inicio de sesión** con *Authorization Code* + **PKCE (S256)** contra Keycloak.
- **Pantalla por rol** según `GET /api/v1/sesion`: recepción o cocina, con el nombre de la
  persona y el botón de salir.
- **Cierre de sesión en Keycloak** y cambio de usuario en el mismo dispositivo (RF-08).
- **Renovación del token** antes de que venza, para que una tableta aguante el turno.
- Estados de **cargando** y **error**, con el mensaje que manda la API.
- **Entorno de desarrollo** local: el servidor de desarrollo de Flutter con proxy hacia el
  backend local, contra el Keycloak local.
- **Publicación** del build en la dirección pública, en lugar de la página de cortesía.

**No incluye (llega en tarjetas posteriores):**

- La carta y la toma de pedidos: tarjeta 05. Los pedidos y la cola de cocina: tarjeta 06.
- El canal en tiempo real: tarjeta 07.
- La política de contenido (CSP): tarjeta 09, cuando se sepa qué necesita el build.
- Compilar y publicar automáticamente desde GitHub (CI/CD): queda como posible mejora.

---

## 3. Decisiones de diseño

1. **Una sola app para los dos roles.** Después de entrar, la app pregunta al servidor quién
   es la persona (`GET /api/v1/sesion`) y muestra la pantalla que corresponde. No decide
   por lo que ella misma lee del token: **el rol lo confirma el servidor**. La app puede
   ocultar lo que un rol no debe ver; impedirlo es tarea del servidor, y eso ya se probó en la
   tarjeta 03.

2. **PKCE implementado con tres paquetes pequeños, sin librería de OIDC.** Se usan `http`,
   `crypto` y `web`, todos del equipo de Dart. El flujo tiene cuatro pasos —generar el
   verificador, redirigir, recibir el código, canjearlo— y es el mismo que ya recorre la
   prueba `probar_acceso_pkce.py`. Escribirlo a mano son unas cien líneas que se pueden
   **explicar línea por línea en la defensa**. Una librería de OIDC completa agrega mucho
   más código del que se usa y oculta justo lo que el tribunal pregunta. El cálculo del
   desafío se comprueba contra **el vector de prueba oficial del RFC 7636**.

3. **El token vive solo en memoria.** Nunca en `localStorage`: todo lo que está ahí lo puede
   leer cualquier script que llegue a ejecutarse en la página. Solo el verificador y el
   `state` pasan por `sessionStorage`, y únicamente durante la ida y vuelta a Keycloak: se
   borran apenas se canjea el código. **Al recargar la página no se pide la contraseña otra
   vez:** la app vuelve a Keycloak con `prompt=none`, y como la sesión de Keycloak sigue
   abierta, regresa con un código nuevo sin mostrar nada.

4. **El `state` protege contra el inicio de sesión forzado (CSRF).** Es un valor aleatorio
   que sale con la redirección y tiene que volver idéntico. Si no coincide, el código se
   descarta.

5. **El token se renueva antes de vencer.** Dura 60 minutos, y la sesión de Keycloak aguanta
   60 minutos sin actividad y 10 horas en total. La app renueva el token un rato antes de que
   venza, y con eso una tableta de cocina queda con la sesión abierta todo el turno de 18:00 a
   23:30. Si la renovación falla o la API responde 401, la app vuelve a la pantalla de acceso
   con un mensaje claro. No se cambia nada del realm.

6. **Cerrar sesión cierra la sesión de Keycloak, no solo la de la app.** Si la app solo
   borrara su token, al tocar "Iniciar sesión" Keycloak reconocería su propia sesión y
   entraría **con la misma cuenta sin pedir nada**. Eso rompe el RF-08: cambiar de usuario en
   el mismo dispositivo. Se redirige al *endpoint* de cierre de Keycloak con
   `id_token_hint` y vuelta a la app.

7. **Ninguna dirección escrita a mano.** La API se llama con la ruta relativa `/api/v1`,
   porque está en el mismo origen. La dirección de Keycloak se deduce del origen de la
   página (`https://auth.` + el dominio actual). En desarrollo, donde el origen es
   `localhost`, llega por `--dart-define=KEYCLOAK_URL=http://localhost:8082`. Es la trampa que la plenaria P3 marcó
   como la más frecuente del frontend.

8. **Desarrollo contra el entorno local, con el proxy del servidor de desarrollo de
   Flutter.** La app corre en `http://localhost:8090`, y sus llamadas a `/api/` se reenvían
   al backend local (`http://localhost:3001`) mediante `web_dev_config.yaml`, disponible
   desde Flutter 3.38. Para el navegador todo es el mismo origen, así que **no hace falta
   abrir CORS en la API**: se desarrolla igual que se despliega. El Keycloak de desarrollo es
   el local (`http://localhost:8082`). Así, **ningún dato de prueba toca producción**, y la
   tarjeta 06 podrá crear pedidos en desarrollo sin ensuciar la base pública.

   Para el canje del token hay que agregar **`http://localhost:8090`** a los orígenes web del
   cliente `frontend-web`. **Comprobado el 23-sep, en los dos Keycloak:** el canje desde
   `localhost:8090` responde **403**. La regla `http://localhost:*` del realm sirve para las
   redirecciones, pero no se traduce en un origen permitido. En producción, el mismo control
   acepta `https://maxpizzapp.tech` y rechaza un origen ajeno, que es lo correcto.

   El cambio va en el archivo del realm y se aplica con `kcadm` en los dos Keycloak, porque
   `--import-realm` no sobrescribe un realm que ya existe. En producción no hace falta para
   funcionar, pero se aplica igual: **el realm del servidor tiene que ser el mismo que el del
   repositorio**, o un despliegue desde cero daría otro resultado. El riesgo es bajo: permitir
   un origen no da acceso a nadie, y el token sigue exigiendo las credenciales.

   > **Revisión del 23-sep.** La primera versión de este plan desarrollaba contra la API y el
   > realm de **producción**, porque Docker Desktop no arrancaba en la máquina del autor
   > (tarjeta 03, §3). Docker volvió a funcionar antes de aprobar el plan, y el entorno local
   > completo pasó sus pruebas: backend sano, acceso PKCE correcto y 12/12 en la prueba de la
   > API con tokens reales. Se desarrolla en local.

9. **El build se compila en la máquina del autor, nunca en el servidor.** `flutter build web`
   usa más memoria y procesador que todo el sistema en marcha, y el servidor tiene 1 vCPU.
   El resultado se publica **fuera del repositorio**, en `/opt/maxpizzapp-web`, con un script
   versionado que compila, copia a una carpeta nueva y la intercambia con la anterior en un
   solo paso: nadie ve una versión a medias. Caddy sirve esa carpeta; si no existe, sigue
   sirviendo la página de cortesía del repositorio.

10. **Sin caché para los archivos de arranque.** `index.html`, `flutter_bootstrap.js` y
    `version.json` se sirven con `Cache-Control: no-cache`. Sin esto, después de publicar una
    versión nueva el navegador puede seguir mostrando la anterior, y eso se nota en una demo.

11. **Dos correcciones al `.gitignore` que de otro modo romperían la app en silencio:**
    - La línea `web/` ignora **cualquier** carpeta llamada `web`, incluida `frontend/web/`,
      que tiene el `index.html` de la app y **sí** se versiona. Se reemplaza por una regla que
      solo ignora el build.
    - `frontend/pubspec.lock` estaba ignorado. En una aplicación ese archivo **tiene que
      versionarse**: es lo que hace que el build de mañana use exactamente las mismas
      versiones que el de hoy. Cumple el mismo papel que `package-lock.json` en el backend.

---

## 4. Fases y checklist

### Fase A — El proyecto
- [x] `flutter create` solo para web, con el nombre `maxpizzapp`.
- [x] `pubspec.yaml` con la restricción de Dart y los paquetes en **versiones exactas**.
      Anotarlos en el README.
- [x] Corregir el `.gitignore`: `frontend/web/` se versiona, `pubspec.lock` también.
- [x] Estructura por responsabilidad: configuración, autenticación, cliente de la API,
      pantallas. *(Las carpetas de autenticación y del cliente de la API se crean en las
      fases B y C, con su contenido; no se dejan carpetas vacías.)*
- [x] `flutter analyze` sin avisos.

### Fase B — El acceso
- [ ] Verificador, desafío S256 y `state`, con generador aleatorio seguro.
- [ ] Redirección a Keycloak y recepción del código al volver; limpieza de la URL.
- [ ] Canje del código por el token y comprobación del `state`.
- [ ] Recarga de la página sin pedir la contraseña (`prompt=none`).
- [ ] Renovación del token antes de que venza; vuelta al acceso si falla.
- [ ] Cierre de sesión en Keycloak, con vuelta a la app.

### Fase C — La sesión y el rol
- [ ] Cliente de la API que agrega el token y entiende el formato único de error.
- [ ] `GET /api/v1/sesion` y la pantalla del rol correspondiente.
- [ ] Estados de cargando y de error, con el mensaje que manda la API.
- [ ] Interfaz adaptable al celular, la tableta y el escritorio (RNF-04).

### Fase D — El entorno de desarrollo
- [ ] `web_dev_config.yaml`: puerto 8090 y proxy de `/api/` al backend local
      (`http://localhost:3001`).
- [ ] `http://localhost:8090` en los orígenes web del cliente: en el archivo del realm y
      aplicado con `kcadm` en el Keycloak local y en el de producción.
- [ ] Repetir la prueba del 23-sep: el canje desde `localhost:8090` pasa de 403 a aceptado,
      y el de un origen ajeno sigue en 403.

### Fase E — La publicación
- [ ] `scripts/publicar-web.sh`: compila en modo *release*, copia a una carpeta nueva del
      servidor y la intercambia con la anterior.
- [ ] Caddy sirve `/opt/maxpizzapp-web`, con la página de cortesía como respaldo.
- [ ] Encabezados sin caché para los archivos de arranque.
- [ ] Procedimiento en el README.

### Fase F — Pruebas
- [ ] `flutter test`: el vector de prueba del RFC 7636, la deducción de la dirección de
      Keycloak, y la lectura de `/sesion` y del formato de error.
- [ ] Prueba en el navegador con las dos cuentas (ver sección 6).

---

## 5. Archivos que se tocan / crean

- `frontend/` *(nuevo)*: `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`,
  `web_dev_config.yaml`, `web/` y `lib/` (configuración, autenticación, cliente de la API,
  pantallas)
- `frontend/test/` *(nuevo)*
- `scripts/publicar-web.sh` *(nuevo)*
- `.gitignore` *(se corrigen las reglas de `web/` y `pubspec.lock`)*
- `docker/keycloak/realm-maxpizzapp.json` *(`http://localhost:8090` en los orígenes web)*
- `docker/docker-compose.prod.yml` *(carpeta del sitio configurable)*
- `docker/caddy/Caddyfile` *(sin caché para los archivos de arranque)*
- `README.md` *(versiones de Flutter y sus paquetes, cómo desarrollar y cómo publicar)*

---

## 6. Cómo se prueba

**Automáticas**, con `flutter test` y `flutter analyze`.

**En el navegador, en `https://maxpizzapp.tech`.** **La contraseña la escribe el autor:** el
agente no escribe contraseñas. Después, el agente puede inspeccionar la página para
comprobar lo que no se ve a simple vista.

1. Sin sesión, la app muestra la pantalla de acceso.
2. Con `recepcion.demo`: pantalla de recepción con el nombre de la cuenta.
3. **Recargar la página:** sigue en recepción **sin volver a pedir la contraseña**.
4. **Salir y entrar con `cocina.demo`:** Keycloak **pide las credenciales de nuevo** y la app
   muestra la pantalla de cocina. Es la prueba del RF-08.
5. Después de entrar, **ni el token ni el verificador quedan** en `localStorage` ni en
   `sessionStorage`.
6. Tocar la API sin sesión (por ejemplo, con la sesión cerrada en otra pestaña): la app
   vuelve al acceso con un mensaje, no queda en blanco.
7. **Desde el celular con datos móviles**, fuera de la red de la casa: el mismo recorrido,
   con la pantalla bien adaptada.
8. Publicar dos veces seguidas: la segunda versión aparece **sin borrar la caché** del
   navegador.

---

## 7. Criterios de aceptación

- Las dos cuentas entran en la dirección pública y cada una llega a **su** pantalla.
- Cerrar sesión obliga a escribir las credenciales de nuevo (RF-08).
- Recargar la página no pide la contraseña mientras la sesión de Keycloak siga abierta.
- **Ningún token** en `localStorage` ni en `sessionStorage` después de entrar.
- **Ninguna dirección escrita a mano** en el código de la app.
- `flutter analyze` sin avisos y `flutter test` en verde, con el vector del RFC 7636.
- La app se ve y se usa bien en el celular, la tableta y el escritorio.
- El build se publica con un comando, sin versiones a medias.

---

## 8. Requisitos que cubre

- **Institucionales:** **#1** (la dirección pública sirve la aplicación real), **#2**
  (autenticación con control de acceso por rol, de punta a punta), **#4** (interfaz
  adaptable) y **#7** (ningún secreto en el cliente: un cliente público no tiene secreto, y
  por eso usa PKCE).
- **Del sistema:** **RF-01** (iniciar sesión) completo, **RF-08** (cerrar sesión y cambiar
  de usuario), **RNF-02** (token de 60 minutos, solo en memoria, sobre HTTPS) y **RNF-04**
  (adaptable).
- **De la entrega:** la pieza de **frontend navegable** del **E2** y el paso *"login en
  producción"* del orden de trabajo de la plenaria P3.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El proyecto | ✅ Verificada | 2026-09-23 | `flutter create --platforms web --empty`, sin los archivos de IntelliJ ni el README genérico que agrega. Flutter **3.44.8**, Dart **3.12.2**; `http` **1.6.0**, `crypto` **3.0.7**, `web` **1.1.1** y `flutter_lints` **6.0.0**, fijados sin `^`, con `pubspec.lock` versionado. `.gitignore` corregido: ya no ignora `frontend/web/` ni `pubspec.lock`. `index.html` y manifiesto en español, `noindex`, color de marca y **orientación libre** (las tabletas de cocina se usan en horizontal). `configuracion.dart` deduce Keycloak del dominio (`https://auth.` + dominio) o lo toma de `--dart-define` en local, y falla con un mensaje claro si no puede. `flutter analyze`: **sin avisos**. `flutter test`: **9/9**. `flutter build web --release`: compila en 74 s. Servido en local: la pantalla de acceso se ve en tema claro y oscuro, en escritorio y a 375 px, **sin errores en la consola** |
| B — El acceso | ⏳ Pendiente | — | — |
| C — La sesión y el rol | ⏳ Pendiente | — | — |
| D — El entorno de desarrollo | ⏳ Pendiente | — | — |
| E — La publicación | ⏳ Pendiente | — | — |
| F — Pruebas | ⏳ Pendiente | — | — |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-23 | Versión inicial propuesta | Primera pieza visible del sistema y la que más riesgo tiene al desplegar. Va antes que el CRUD, como fija la plenaria P3 |
| 2026-09-23 | **Aprobado** | Revisado por el autor, con la decisión 8 ya en su versión local |
| 2026-09-23 | Decisión 8: se desarrolla contra el entorno **local**, no contra producción | Docker Desktop volvió a funcionar. El entorno local completo pasó sus pruebas (acceso PKCE correcto y 12/12 en la API con tokens reales), así que ningún dato de desarrollo toca producción. El cambio del realm sigue haciendo falta: el Keycloak local también rechaza `localhost:8090` |

---

## 11. Cierre

- **Commits que cierran la tarjeta:** —
- **Fecha de cierre:** —
