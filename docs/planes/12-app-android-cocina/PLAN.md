# Plan 12 — App Android para cocina

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 12 — App Android para cocina
- **Incremento:** tiempo real completo (E3)
- **Estado:** 🟢 **Aprobado** — 2026-09-30, sin cambios
- **Entrada al tablero:** 2026-09-28 (tutoría T3, D-43)
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que cocina trabaje con **una app instalada en el celular o la tableta**, hecha con el mismo
código de Flutter que la web, que **suene desde que se abre**, sin esperar un toque, y que
**no deje apagarse la pantalla** mientras la cola está abierta.

1. El APK se descarga desde un **enlace público** y se instala en cualquier Android.
2. Cocina entra con **la misma cuenta y la misma página de acceso de Keycloak** que en la
   web, y al cerrar sesión, Keycloak vuelve a pedir la contraseña.
3. Un pedido nuevo **suena aunque nadie haya tocado la pantalla**: lo que la web no puede,
   según la prueba de la tarjeta 07, en la que el pedido 44 llegó mudo.
4. Con el canal caído aparecen la misma banda y el mismo *Recargar* que en la web, y el
   canal vuelve en segundos, sin el defecto de Chrome (E-014).
5. **La web no cambia:** recepción sigue en `https://maxpizzapp.tech`, y cocina también
   puede seguir usándola.

La tutoría T3 sumó el APK al E3 (D-43). El campo del E3 en Moodle lo prevé: *"Frontend (URL
pública o enlace al APK)"*.

---

## 2. Alcance

**Incluye:**

- **La plataforma Android** en el proyecto de Flutter, con su propia entrada, que abre solo
  la pantalla de cocina (D-48).
- **El acceso en Android** con Authorization Code y PKCE, por medio de AppAuth, contra el
  mismo cliente de Keycloak (D-49).
- **El timbre de Android**, que suena desde el arranque, y **la pantalla siempre encendida**
  mientras la cola está abierta (D-50).
- **La firma, la compilación y la descarga** (D-51): una llave propia fuera del repositorio,
  un script que compila el APK y un enlace estable para descargarlo.
- **Una cuenta de recepción en el APK** ve un aviso de que la app es para cocina, y el botón
  para salir. El servidor ya la limita por rol; el aviso es para que se entienda.
- En el README: cómo instalarlo, cómo compilarlo y qué cuenta usar.

**No incluye:**

- **Recepción en Android.** Recepción trabaja en la computadora del mostrador, en la web.
- **La publicación en Google Play.** Pide una cuenta de desarrollador y una revisión que no
  aportan nada al piloto de un local.
- **Avisos con la app cerrada o en segundo plano** (notificaciones del sistema): fuera de
  alcance, como en la web. La pantalla siempre encendida es lo que mantiene la app al frente.
- **Recordar la sesión al cerrar la app.** Los tokens siguen solo en memoria, como en la web
  (D-49).
- **iOS.** Hace falta una Mac, y el local usa Android.
- **La vuelta rápida del canal en Chrome (E-014):** semana del E4. El APK no la necesita,
  porque usa el cliente nativo.

---

## 3. Decisiones de diseño

### D-48 · El APK es el mismo código, con una entrada propia para cocina

- **Una sola base de código.** Las pantallas, el canal, la sesión, la banda y las pruebas
  son los de la web. Lo que cambia por plataforma ya está detrás de interfaces desde las
  tarjetas 04 y 07: cómo se inicia sesión, cómo suena el timbre y cómo se sabe si hay red.
- **Una entrada propia, `lib/main_cocina.dart`.** `main.dart` sigue siendo la web e importa
  las piezas que solo compilan en el navegador. `main_cocina.dart` arma lo mismo con las
  piezas de Android. Se descartó una sola entrada con importaciones condicionales: mezcla
  las dos plataformas en un archivo y la web podría cambiar sin querer.
- **La dirección del servidor llega al compilar**, con `--dart-define=ORIGEN=…`. En la web
  se deduce de la página; en el APK no hay página. Ninguna dirección queda escrita en el
  código, igual que hoy.
- **Solo cocina.** Si entra una cuenta de recepción, ve *"Esta app es para cocina. Recepción
  trabaja en https://maxpizzapp.tech."* con el botón *Cerrar sesión*.

### D-49 · En Android, el acceso usa AppAuth y el mismo cliente de Keycloak

- **AppAuth** (`flutter_appauth`) abre la página de acceso de Keycloak en una pestaña del
  navegador del sistema, no dentro de la app. Es lo que recomienda el estándar para apps
  nativas (RFC 8252): la app **nunca ve la contraseña**. Vuelve por una dirección propia de
  la app, `tech.maxpizzapp.cocina:/callback`.
- **AppAuth solo trae el código.** El canje por los tokens, la renovación a los 48 minutos y
  el cierre por sesión rechazada (D-46) siguen en el mismo `ServicioSesion` de la web. Así
  no hay dos formas de manejar los tokens. El servicio se separa en dos partes: **cómo se
  obtiene el código**, que depende de la plataforma, y **qué se hace con los tokens**, que
  es común.
- **El mismo cliente público, `frontend-web`, con una dirección de retorno más**, exacta.
  Un cliente aparte obligaría a duplicar la audiencia de la API y la configuración, sin
  ganar nada: los dos son públicos y usan PKCE. El realm del repositorio suma la dirección, y
  en producción la agrega el autor desde la consola de Keycloak (el realm solo se importa la
  primera vez).
- **Los tokens, solo en memoria**, como en la web. Si la app se cierra, se vuelve a entrar.
  Si la sesión de Keycloak sigue abierta en el navegador del sistema, entra sin pedir la
  contraseña. Guardar el token de renovación en el teléfono permitiría abrir sin entrar,
  pero dejaría una credencial en el dispositivo de la cocina.
- **Cerrar sesión cierra la de Keycloak**, con la salida de OpenID Connect, igual que la web
  (RF-08).

### D-50 · El timbre suena desde el arranque y la pantalla no se apaga

- **El mismo timbre de dos notas**, generado en código como en la web, sin archivos de
  sonido. En Android se reproduce con `audioplayers`. **Ninguna regla del sistema exige un
  toque previo**, así que `pendienteDeActivar` es siempre falso y la franja de la 07 nunca
  aparece.
- **Suena por el canal de alarma, no por el multimedia.** En una cocina, el volumen
  multimedia suele estar bajo y el teléfono, en silencio. El canal de alarma suena igual. Su
  volumen se regula con el de las alarmas del teléfono, y el README lo dice.
- **La pantalla siempre encendida** (`wakelock_plus`) mientras la cola de cocina está
  abierta. Se libera al cerrar sesión. El README advierte que el teléfono tiene que estar
  cargando.
- **Sin paquete de red.** En la web, el evento `offline` del navegador adelanta la banda. En
  Android, al perder la red, el sistema cierra las conexiones y el latido de 7 s cubre el
  resto: la banda llega en 8 s como máximo, bajo los 10 s del RNF-05. Se mide en la fase D. Si
  tarda más, se suma `connectivity_plus`.

### D-51 · Firmado con una llave propia y descargado desde un Release de GitHub

- **La llave de firma, fuera del repositorio**, en una carpeta al lado de `codigo/`
  (`../llaves-android/`), con su contraseña en un `key.properties` en la misma carpeta. El
  build la busca ahí; si no está, compila sin firmar y lo dice. El `.gitignore` excluye
  además cualquier `*.jks` y cualquier `key.properties`. **Hay que
  respaldarla:** sin ella no se puede publicar una versión nueva que se instale encima de la
  anterior.
- **La descarga, desde un Release del repositorio público**, con el APK adjunto y su
  SHA-256 en la descripción. El enlace
  `…/releases/latest/download/max-pizzapp-cocina.apk` apunta siempre a la última versión, y
  es el que va en Moodle. Se descartó servirlo desde `maxpizzapp.tech`: la publicación de la
  web reemplaza la carpeta entera, y haría falta otra carpeta y otra ruta en Caddy. El
  Release lo crea el autor, como hace con los commits.
- **Un solo APK universal**, que se instala en cualquier teléfono, aunque pese más que uno
  por arquitectura.
- **El APK no lleva secretos:** el cliente de Keycloak es público y la dirección del
  servidor no es secreta.

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — El acceso en Android
- [ ] La plataforma Android en el proyecto (`flutter create --platforms=android`), con
      `applicationId` `tech.maxpizzapp.cocina` y el nombre *Max Pizzapp Cocina*.
- [ ] `ServicioSesion` separado en dos partes: cómo se obtiene el código (web: la
      redirección de hoy; Android: AppAuth) y qué se hace con los tokens (común). **La web se
      comporta igual.**
- [ ] `lib/main_cocina.dart`, con la configuración desde `ORIGEN`.
- [ ] El aviso para una cuenta de recepción.
- [ ] El realm del repositorio con la dirección de retorno del APK; aplicada también en el
      Keycloak de desarrollo.
- [ ] Pruebas: la sesión con un autorizador simulado (entrar, cancelar, error, cerrar
      sesión y renovar) y el aviso de recepción. `flutter test` y `flutter analyze`.
- [ ] **En el emulador**, contra la API y el Keycloak locales (con `adb reverse`, para que
      el emulador los vea en `localhost`): entrar con la cuenta de cocina de desarrollo, ver
      la cola, recibir un pedido en vivo y cerrar sesión.

### Fase B — El timbre y la pantalla encendida
- [ ] `TimbreAndroid`: las dos notas generadas en código, por el canal de alarma.
- [ ] La pantalla encendida mientras la cola está abierta.
- [ ] El ícono de la app con el logo de Max's Pizzas (D-29).
- [ ] Pruebas: el generador de las dos notas (duración, frecuencia de muestreo, que no
      sature) y que en Android no aparece la franja de sonido apagado.
- [ ] En el emulador: el pedido suena sin tocar la pantalla, porque el emulador reproduce el
      audio en la computadora. La pantalla no se apaga pasado el tiempo de espera.

### Fase C — Firma, compilación y descarga
- [ ] La llave de firma, fuera del repositorio.
- [ ] `scripts/compilar-apk.sh`: compila el APK firmado contra producción y calcula su
      SHA-256.
- [ ] README: cómo instalarlo, cómo compilarlo, el volumen de alarma y el cargador.
- [ ] El APK instalado en el emulador **desde el archivo**, no desde el editor: abre y llega
      a la página de acceso de producción.

### Fase D — En producción
- [ ] El autor agrega la dirección de retorno del APK al cliente `frontend-web` de
      producción, desde la consola de Keycloak.
- [ ] El autor crea el Release con el APK y su SHA-256.
- [ ] En el teléfono del autor, contra `https://maxpizzapp.tech`:
  - la descarga desde el enlace;
  - la instalación;
  - la entrada con `cocina.demo`.
- [ ] La web sigue igual: `probar_pedidos.py` y una venta de punta a punta.

### Fase E — La prueba del autor y el cierre
- [ ] El autor, con recepción en la computadora y cocina en el APK:
  - un pedido que **suena sin tocar nada** desde que se abrió la app;
  - la pantalla que no se apaga;
  - la banda en modo avión, y cuánto tarda en volver el canal;
  - cerrar sesión y ver que Keycloak vuelve a pedir la contraseña;
  - una cuenta de recepción, que ve el aviso.
- [ ] Capturas del teléfono, con datos ficticios.
- [ ] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **App:**
  - `frontend/android/` *(nuevo)*: la plataforma, con la dirección de retorno de AppAuth, el
    permiso de pantalla encendida y la firma leída desde fuera del repositorio;
  - `frontend/lib/main_cocina.dart` *(nuevo)*;
  - `frontend/lib/autenticacion/servicio_sesion.dart` y un autorizador por plataforma
    *(nuevos: `autorizador_web.dart` y `autorizador_android.dart`)*;
  - `frontend/lib/configuracion.dart`: la configuración a partir de `ORIGEN`;
  - `frontend/lib/pantallas/timbre_android.dart` *(nuevo)* y el aviso de "app para cocina";
  - `frontend/pubspec.yaml` y `pubspec.lock`: `flutter_appauth`, `audioplayers` y
    `wakelock_plus`, con versión exacta, y el ícono.
- **Pruebas de la app:** `servicio_sesion_test.dart` y las nuevas del timbre y del aviso.
- **Identidad:** `docker/keycloak/realm-maxpizzapp.json`: la dirección de retorno del APK.
- **Scripts:** `scripts/compilar-apk.sh` *(nuevo)*.
- **Repositorio:** `.gitignore` (llaves) y `README.md`.

No cambia la API, la base de datos ni el contrato HTTP. La web se publica igual que hoy.

---

## 6. Cómo se prueba

| Qué | Cómo | Resultado esperado |
|---|---|---|
| La web no cambia | `flutter test`, `flutter analyze` y `flutter build web` | Las 242 pruebas de hoy en verde, más las nuevas |
| La sesión en Android | Pruebas con un autorizador simulado | Entrar, cancelar, error, cerrar sesión y renovar, igual que en la web |
| El acceso real | Emulador contra la API y el Keycloak locales | Entra, ve la cola, recibe un pedido en vivo y sale |
| El timbre | Prueba del generador y emulador | Suena sin tocar la pantalla |
| La pantalla encendida | Emulador, pasado el tiempo de espera | No se apaga con la cola abierta |
| La firma | `apksigner verify` sobre el APK | Firmado con la llave propia |
| Sin secretos | Revisión del repositorio y del APK | Ni la llave ni su contraseña; el APK solo trae el cliente público |
| En producción | El teléfono del autor | Todo lo de la fase E |

---

## 7. Criterios de aceptación

- El APK se descarga desde un enlace público, se instala y abre con el nombre y el logo del
  local.
- Cocina entra con su cuenta de siempre, en la página de Keycloak, y la app nunca ve la
  contraseña. Al cerrar sesión, Keycloak vuelve a pedirla.
- **Un pedido nuevo suena sin que nadie haya tocado la pantalla**, desde que se abre la app.
- La pantalla no se apaga mientras la cola está abierta.
- Con el canal caído aparecen la banda y *Recargar*, en menos de 10 s. Al volver la red, el
  canal vuelve solo.
- Una cuenta de recepción no opera en el APK: ve el aviso y puede salir.
- Ningún secreto en el repositorio ni en el APK.
- **La web sigue igual**, sin regresiones en las pruebas ni en producción.

---

## 8. Requisitos que cubre

- **Del sistema:**
  - **RNF-04**: la misma interfaz, ahora también instalada en Android;
  - **RF-06 y RF-07** (*Must*) en el APK: la cola en vivo y los cambios de estado;
  - **RF-03, CA-03.2** y **RNF-05** en el APK: la banda y *Recargar*;
  - **RF-08**: entrar y salir con Keycloak.
- **Institucionales:** **#4** (interfaz adaptable) y el alcance *web y móvil* del
  diplomado. **#2**: la app no maneja contraseñas y el servidor sigue decidiendo el rol.
- **De la entrega (E3):** el campo *"Frontend (URL pública o enlace al APK)"* lleva los dos.
- **Decisión de la tutoría T3:** D-43.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El acceso en Android | ⬜ | | |
| B — El timbre y la pantalla | ⬜ | | |
| C — Firma y descarga | ⬜ | | |
| D — En producción | ⬜ | | |
| E — La prueba del autor | ⬜ | | |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-30 | Versión inicial propuesta | La tutoría T3 sumó el APK de cocina al E3 (D-43). La prueba de la tarjeta 07 le agregó un requisito: sonar desde el arranque, sin esperar un toque |
| 2026-09-30 | **Aprobado** por el autor, sin cambios | El autor confirmó que el teléfono de la prueba y el de la cocina son Android |

---

## 11. Cierre

—
