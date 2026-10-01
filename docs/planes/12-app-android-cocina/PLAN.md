# Plan 12 — App Android para cocina

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 12 — App Android para cocina
- **Incremento:** tiempo real completo (E3)
- **Estado:** ✅ **Hecho** — publicado el 2026-10-01 (Release `apk-cocina-0.1.0`) y probado
  por el autor en su teléfono contra producción. Aprobado el 2026-09-30, sin cambios
- **Entrada al tablero:** 2026-09-28 (tutoría T3, D-43)
- **Cierre:** 2026-10-01
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
- [x] La plataforma Android en el proyecto (`flutter create --platforms=android`), con
      `applicationId` `tech.maxpizzapp.cocina` y el nombre *Max Pizzapp Cocina*.
- [x] `ServicioSesion` separado en dos partes: cómo se obtiene el código (web: la
      redirección de hoy; Android: AppAuth) y qué se hace con los tokens (común). **La web se
      comporta igual.**
- [x] `lib/main_cocina.dart`, con la configuración desde `ORIGEN`.
- [x] El aviso para una cuenta de recepción.
- [x] El realm del repositorio con la dirección de retorno del APK; aplicada también en el
      Keycloak de desarrollo.
- [x] Pruebas: la sesión con un autorizador simulado (entrar, cancelar, error, cerrar
      sesión y renovar) y el aviso de recepción. `flutter test` y `flutter analyze`.
- [x] **En el emulador**, contra la API y el Keycloak locales (con `adb reverse`, para que
      el emulador los vea en `localhost`): entrar con la cuenta de cocina de desarrollo, ver
      la cola, recibir un pedido en vivo y cerrar sesión.

### Fase B — El timbre y la pantalla encendida
- [x] `TimbreAndroid`: las dos notas generadas en código, por el canal de alarma.
- [x] La pantalla encendida mientras la cola está abierta.
- [x] El ícono de la app con el logo de Max's Pizzas (D-29).
- [x] Pruebas: el generador de las dos notas (duración, frecuencia de muestreo, que no
      sature) y que en Android no aparece la franja de sonido apagado.
- [x] En el emulador: el pedido suena sin tocar la pantalla, porque el emulador reproduce el
      audio en la computadora. La pantalla no se apaga pasado el tiempo de espera.

### Fase C — Firma, compilación y descarga
- [x] La llave de firma, fuera del repositorio.
- [x] `scripts/compilar-apk.sh`: compila el APK firmado contra producción y calcula su
      SHA-256.
- [x] README: cómo instalarlo, cómo compilarlo, el volumen de alarma y el cargador.
- [x] El APK instalado en el emulador **desde el archivo**, no desde el editor: abre y llega
      a la página de acceso de producción.

### Fase D — En producción
- [x] El autor agrega la dirección de retorno del APK al cliente `frontend-web` de
      producción, desde la consola de Keycloak.
- [x] El autor crea el Release con el APK y su SHA-256.
- [x] En el teléfono del autor, contra `https://maxpizzapp.tech`:
  - la descarga desde el enlace;
  - la instalación;
  - la entrada con `cocina.demo`.
- [x] La web sigue igual: `probar_pedidos.py` y una venta de punta a punta.

### Fase E — La prueba del autor y el cierre
- [x] El autor, con recepción en la computadora y cocina en el APK:
  - un pedido que **suena sin tocar nada** desde que se abrió la app;
  - la pantalla que no se apaga;
  - la banda en modo avión, y cuánto tarda en volver el canal;
  - cerrar sesión y ver que Keycloak vuelve a pedir la contraseña;
  - una cuenta de recepción, que ve el aviso.
- [x] Capturas del teléfono, con datos ficticios.
- [x] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **App:**
  - `frontend/android/` *(nuevo)*: la plataforma, con la dirección de retorno de AppAuth, el
    permiso de pantalla encendida y la firma leída desde fuera del repositorio;
  - `frontend/lib/main_cocina.dart` *(nuevo)* y `frontend/lib/app.dart` *(nuevo)*: lo que
    comparten las dos entradas, sacado de `main.dart` sin cambiarlo;
  - `frontend/lib/autenticacion/servicio_sesion.dart` y un autorizador por plataforma
    *(nuevos: `autorizador_web.dart` y `autorizador_android.dart`)*;
  - `frontend/lib/configuracion.dart`: la configuración a partir de `ORIGEN`;
  - `frontend/lib/pantallas/timbre_android.dart` *(nuevo)* y el aviso de "app para cocina",
    en `segun_rol.dart` con `pantalla_error.dart`;
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
| A — El acceso en Android | ✅ Verificada | 2026-09-30 | **La plataforma:** `flutter create --platforms=android` sumó `android/`, con `applicationId` `tech.maxpizzapp.cocina`, el nombre *Max Pizzapp Cocina*, el permiso de Internet, el esquema de retorno de AppAuth y, solo en la compilación de desarrollo, `http` para el entorno local. Del manifiesto se quitó `taskAffinity=""`, que según `flutter_appauth` impide volver a la app después del acceso. `flutter create` también dejó archivos de plantilla que el proyecto no usa (`.idea/`, dos `.iml`, un README y una prueba de ejemplo): se borraron, y en `.metadata` se volvió a declarar la web junto a Android. **El acceso:** `ServicioSesion` delega en un `Autorizador` cómo se obtiene el código. `AutorizadorWeb` es la redirección de siempre, movida sin cambios. `AutorizadorAndroid` usa `flutter_appauth` 12.1.0 y solo trae el código y el verificador. El canje, la renovación y el cierre por sesión rechazada siguen en `ServicioSesion`. **Las 15 pruebas de la sesión web pasan sin tocarlas.** Lo que comparten las dos entradas pasó de `main.dart` a `app.dart`. **`flutter test`: 265 de 265** (242 anteriores y **23 nuevas**): 10 del autorizador de Android con AppAuth simulado (el pedido al cliente público con la dirección de la app y por https, el código con su verificador, volverse atrás sin error, la falla de AppAuth, una respuesta sin código, el cierre de sesión y su falla, y `http` solo en desarrollo); 6 de la sesión con ese autorizador (al abrir no pide nada, el canje con la dirección de la app, volverse atrás, el canje rechazado, cerrar sesión y el aviso si Keycloak no llega a cerrar); 4 de la configuración con `ORIGEN`; y 3 del aviso de recepción. `flutter analyze` sin observaciones y `flutter build web` igual que antes. **El realm** suma `tech.maxpizzapp.cocina:/callback` al cliente `frontend-web`, como dirección de retorno y de salida, y lo mismo se aplicó en el Keycloak de desarrollo. **En el emulador** (Pixel 7, compilación de desarrollo contra la API y el Keycloak locales, con `adb reverse`): la app abre en la pantalla de acceso; *Iniciar sesión* abre Keycloak en el navegador del sistema, no en la app; con la cuenta de cocina de desarrollo, **entra a la cola con "En vivo"**; una venta hecha como recepción contra la API local (*Gabriel Cantante · 60000001*) **aparece sola, "Nuevo · recién llegado", en menos de 2 s**; *Cerrar sesión* vuelve al acceso y **Keycloak vuelve a pedir la contraseña**; y la cuenta de recepción ve *"Esta app es para cocina. Recepción trabaja en la web: localhost"* con *Cerrar sesión*. Cerrar la pestaña de Keycloak devuelve al acceso sin mensaje de error, como se probó. La venta de prueba se canceló. **Lo que salió:** (1) una prueba nueva encontró que, al cerrar sesión, `ServicioSesion` descartaba el aviso de que Keycloak no llegó a cerrar: corregido. (2) En el emulador, Chrome mostró su bienvenida la primera vez (el autor la aceptó) y el teclado abrió un tutorial de lápiz que se comía lo escrito; son cosas del emulador, no de la app. (3) `android/.gitignore` no excluía `.kotlin/`, que genera la compilación: se sumó |
| B — El timbre y la pantalla | ✅ Verificada | 2026-10-01 | **El timbre:** `TimbreAndroid` reproduce las mismas dos notas de la web, armadas en memoria como un WAV de 16 bits a 44 100 Hz (`SonidoDelTimbre`: 880 Hz y, a los 0,18 s, 1318,5 Hz; 0,58 s en total, 50 KB), con `audioplayers` 6.8.1 por el canal de **alarma** (`USAGE_ALARM`), que baja un momento lo que esté sonando en el teléfono sin cortarlo. Está siempre habilitado: la franja de sonido apagado no aparece, y la barra muestra el ícono de que suena, sin botón. **La pantalla:** `PantallaEncendidaAndroid`, con `wakelock_plus` 1.8.1. La cola de cocina la pide al abrirse y la suelta al cerrarse, que es lo que pasa al cerrar sesión. En la web, `PantallaSegunElSistema` no hace nada. **No hizo falta ningún permiso**, aunque el plan lo suponía: `wakelock_plus` usa la marca `FLAG_KEEP_SCREEN_ON` de la ventana, no un *wake lock* del sistema. **El ícono:** el logo sobre el carbón `#141414`, armado con `flutter_launcher_icons` 0.14.4 (`dart run flutter_launcher_icons`, configurado en `pubspec.yaml`): cuadrado para Android 7 y adaptable desde Android 8, con el logo al 56 % para que ninguna forma de lanzador lo corte (revisado en círculo, *squircle* y cuadrado). Solo toca `android/`: los íconos de la web quedaron intactos. **`flutter test`: 280 de 280** (265 anteriores y **15 nuevas**): 7 del generador (la cabecera WAV, los 0,58 s de la web, el peso, el pico entre 0,6 y 0,8 sin recortes, que empiece y termine en silencio, las dos frecuencias medidas con Goertzel y la caída de cada nota); 5 del timbre (siempre habilitado, cada aviso suena, el sonido que suena es el que se preparó, una falla del teléfono no tumba la cola, y sin franja ni botón); 2 de la cola (la pantalla encendida al abrir y suelta al cerrar; un pedido nuevo y lo agregado suenan sin ningún toque); y 1 de `PantallaSegunRol` (la pantalla encendida es solo de la cola de cocina). `flutter analyze` sin observaciones y `flutter build web` compila: comparado con la web subida, `main.dart.js` pesa 2,1 KB más (0,07 %), el registro de los dos plugins, que la web nunca llama; el aviso de fuentes de `CupertinoIcons` al compilar ya estaba antes. **Ninguna versión de los paquetes que ya usaba la web cambió**: el `pubspec.lock` suma 48 paquetes, todos traídos por los tres nuevos y la mayoría para otras plataformas. **En el emulador** (Pixel 7, compilación de desarrollo contra la API y el Keycloak locales): el ícono nuevo en el lanzador y en el arranque. Con el apagado de pantalla en 15 s, **en el acceso se apagó**, como control, y **en la cola, a los 40 s sin tocar nada, seguía encendida**, con `KEEP_SCREEN_ON` en la ventana. **Al cerrar sesión, la ventana perdió `KEEP_SCREEN_ON` y la pantalla se apagó** antes de los 25 s. Cuatro ventas como recepción contra la API local (*Gabriel Cantante · 60000001*), sin tocar el teléfono: cada pedido **apareció solo, "Nuevo · recién llegado", y sonó**. El sistema de audio registra el reproductor de la app con `USAGE_ALARM`, por el flujo de alarma, sin silenciar, sonando 0,6 s. Las ventas se cancelaron. **Lo que salió:** (1) **E-015**: el APK no compilaba, porque la compilación incremental de Kotlin no admite el proyecto en `E:` y los paquetes en `C:`. Se apagó en `android/gradle.properties`, con su porqué, y quedó en la base de errores. (2) El **primer** sonido llegaba **2,4 s** después del aviso, porque el teléfono recién entonces preparaba el reproductor; los siguientes, a 0,4 s. Ahora el sonido se prepara al abrir la app y se reutiliza: **0,2 s** el primero y **0,04 s** el segundo. (3) Mientras Chrome mostraba su bienvenida, Android cerró la app para liberar memoria. Al volver de Keycloak, la app arrancó de cero, la respuesta de AppAuth no tuvo a quién llegar y quedó en el acceso, sin error. El segundo *Iniciar sesión* entró sin pedir la clave, porque la sesión de Keycloak seguía abierta. Puede pasar en un teléfono con poca memoria: se revisa en la fase E. (4) El generador de íconos reescribió `AndroidManifest.xml` con otro fin de línea, sin cambiar su contenido: se devolvió byte a byte al del repositorio |
| C — Firma y descarga | ✅ Verificada | 2026-10-01 | **La llave:** RSA de 4096 bits, PKCS12, válida por 10 000 días, en `../llaves-android/` (al lado de `codigo/`, fuera del repositorio), con su contraseña en `key.properties`. La contraseña se generó al azar y fue directo al archivo y a `keytool` por una variable de entorno: no se imprimió en ningún momento. Huella SHA-256 del certificado: `3c:32:be:ac:…:ba:06:b0:1a`. El `.gitignore` suma `key.properties` (ya excluía `*.jks` y `*.keystore`). **La firma en Gradle:** `build.gradle.kts` lee la llave desde esa carpeta. Si no la encuentra, firma con la llave de depuración y lo avisa; el plan decía "compila sin firmar", pero Flutter no entrega un APK de release sin firma, y así un clon del repositorio, como el del tribunal, igual puede compilarlo para probar. **El script** `scripts/compilar-apk.sh`: se niega a compilar sin la llave; compila el APK universal contra `https://maxpizzapp.tech`; verifica con `apksigner` que esté firmado y que **no** sea con la llave de depuración; y lo deja en `frontend/build/max-pizzapp-cocina.apk` con su versión, su tamaño y su SHA-256. **Probado por los dos caminos:** con la llave, firmado con `CN=Max Pizzapp Cocina` y la huella de la llave propia; **sin la llave** (carpeta apartada un momento), el script se negó con su mensaje, y un `flutter build apk` a mano salió firmado con `CN=Android Debug`. El aviso de Gradle no se ve, porque Flutter oculta su salida: el guardián es el script. **El APK:** 0.1.0, código de versión 1, universal (arm64, armeabi-v7a y x86_64), 52 MB, firma v2. **Sin secretos:** se descomprimió y se buscó en sus 348 archivos la contraseña de la llave y los cuatro valores secretos del `.env` (sin imprimirlos): **ninguno aparece**, como tampoco `llaves-android`, `key.properties` ni `.jks`. La dirección de producción sí está, como se espera, y `localhost:8082` aparece solo en el mensaje de ayuda para quien compila mal en desarrollo, no como dirección de conexión. **En el emulador, instalado desde el archivo** (`adb install` del APK, después de desinstalar la versión de desarrollo, que tenía otra llave): abre en el acceso. *Iniciar sesión* llega por HTTPS al Keycloak de **producción**, que responde *"Parámetro no válido: redirect_uri"*. Es lo esperado: la dirección de retorno del APK todavía no está en el cliente de producción. Se agrega en la fase D, y la misma consulta hecha con `curl` lo confirma (HTTP 400 para la dirección del APK, 200 para la de la web). Al cerrar esa pestaña, la app vuelve al acceso sin caerse. Una versión nueva, con la misma llave, **se instaló encima** de la anterior. **Lo que salió:** (1) la pantalla de arranque de Android 12 mostraba el logo amarillo **sobre fondo blanco**, sin su círculo, y así no se lee. Ahora el arranque es crema, el mismo fondo con el que arranca la web, con el logo sobre su círculo carbón como en `LogoMaxPizzas` (`values-v31/styles.xml`). En Android 7 a 11, el fondo crema con el ícono al centro. El fondo detrás de Flutter también es crema, así que no hay destello blanco. Se borraron los estilos de modo noche que dejó la plantilla, porque el tema es claro y fijo (D-29) y arrancaría en negro, y el `launch_background.xml` duplicado de `drawable-v21`, que con `minSdk` 24 siempre tapaba al otro. (2) `apksigner` 37 escribe `V2 Signer: certificate DN`, no `Signer #1`: el primer filtro del script no encontraba nada y lo cortaba sin mensaje. Ahora acepta los dos formatos y, si no ve un certificado, lo dice. (3) Al borrar el `-v21`, la fusión incremental de recursos de Gradle quedó desfasada y no encontraba `launch_background`: se borraron los intermedios del módulo de la app y compiló |
| D — En producción | ✅ Verificada | 2026-10-01 | **Keycloak de producción:** el autor abrió la sesión de administración y, a su pedido, el agente agregó con Claude in Chrome `tech.maxpizzapp.cocina:/callback` al cliente `frontend-web`, como dirección de retorno y de salida, sin tocar nada más. Antes, producción tenía lo mismo que el realm del repositorio salvo esa línea. Verificado desde afuera con la consulta de autorización: la dirección del APK pasó de **HTTP 400 a 200**, la de la web sigue en 200 y una dirección parecida (`tech.maxpizzapp.otra:/callback`) sigue en 400, porque la coincidencia es exacta. **El Release** `apk-cocina-0.1.0`, *APK de cocina 0.1.0*, marcado como el último. La etiqueta apunta a `137e531`, el commit de la fase C, con el que se compiló el APK. El agente completó el formulario, el autor adjuntó el APK (52 MB: la herramienta del navegador sube hasta 10 MB) y el agente publicó a pedido del autor. **El enlace público** `…/releases/latest/download/max-pizzapp-cocina.apk` responde HTTP 200 y entrega 53 875 003 bytes con el **mismo SHA-256** que el compilado (`e17077c3…adbe5`); GitHub muestra la misma huella. **La web sigue igual:** `probar_pedidos.py` contra producción, con las dos cuentas por PKCE, termina en **TODO CORRECTO** y no deja ningún pedido de prueba activo (cerró los 30 que creó). Se corrió fuera del horario de atención. **Aparte, para la tarjeta 09:** la consola avisa que la cuenta de administración es la **temporal de arranque**; lo correcto es crear una permanente y borrar la temporal. **En el teléfono del autor** (Honor 50 con Android 13, el 1-oct a las 19:01): el APK se descargó del enlace público y se instaló. Play Protect avisó que no conoce la app, porque no viene de Google Play, y se eligió instalarla de todas formas; el README lo dice desde ahora. El ícono *Max Pizzapp Cocina* quedó en la pantalla de inicio. Con `cocina.demo`, en la página de Keycloak de producción abierta en una pestaña del navegador del teléfono, **entró a la cola con "En vivo"** |
| E — La prueba del autor | ✅ Verificada | 2026-10-01 | **En producción, con recepción en la web y cocina en el APK, en el teléfono del autor** (Honor 50, Android 13; datos ficticios; capturas `apk-01` a `apk-10`, de 19:01 a 19:07). (1) **El arranque**, en crema con el logo, sin destello blanco. (2) **El acceso:** *Iniciar sesión* abre el Keycloak de producción en una pestaña del navegador, no en la app, y con `cocina.demo` entra a la cola, "En vivo". (3) **Recepción vende el pedido 34** (*Juan Perez*: un Choclo y una gaseosa, para comer aquí). En el APK **aparece solo, "Nuevo · recién llegado", y suena al instante**, sin que nadie haya tocado el teléfono desde que se abrió la app. Es lo que la web no podía en la prueba de la 07, en la que el pedido 44 llegó mudo. (4) **La pantalla quedó encendida** con la cola abierta. El autor no la dejó mucho tiempo sin tocar: el tiempo se midió en el emulador en la fase B (40 s sin tocar, con el apagado en 15 s). (5) **Modo avión: la banda *Sin conexión en vivo*, con *Recargar*, a los 3 s**, bajo los 8 s que preveía D-50 y los 10 s del RNF-05. No hizo falta `connectivity_plus`. (6) **Sin el modo avión, el canal volvió solo a "En vivo" en 5 a 7 s**, sin tocar *Recargar*: lo mismo que la web en la 07. (7) **Cerrar sesión** vuelve a la pantalla de acceso, y al entrar otra vez **Keycloak pidió usuario y contraseña**. (8) **Con `recepcion.demo`**, la app muestra *"Esta app es para cocina. Recepción trabaja en la web: maxpizzapp.tech"* con *Cerrar sesión*. El riesgo visto en la fase B, que Android cierre la app mientras el navegador muestra Keycloak, **no se presentó** en el teléfono. **Lo que salió:** (1) en la cola seguían el 44 y el 45, pedidos de prueba del 30-sep que quedaron pendientes (*"hace 31 h"*). El número del pedido se reinicia cada día: si hoy se llegara al 44, habría dos tarjetas con el mismo número en la cocina. En la operación normal los pedidos se cierran el mismo día; estos se cancelan desde recepción antes de la revisión del E3. (2) En la pantalla de acceso y en el aviso de recepción, los íconos de la barra de estado del teléfono (la hora, la batería) salen blancos sobre el fondo claro y casi no se leen. Es cosmético y pide un APK nuevo: queda para la semana del E4 |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-30 | Versión inicial propuesta | La tutoría T3 sumó el APK de cocina al E3 (D-43). La prueba de la tarjeta 07 le agregó un requisito: sonar desde el arranque, sin esperar un toque |
| 2026-09-30 | **Aprobado** por el autor, sin cambios | El autor confirmó que el teléfono de la prueba y el de la cocina son Android |
| 2026-10-01 | Fase B: el timbre se **prepara al abrir la app**; la pantalla encendida **no lleva permiso**; `android/gradle.properties` apaga la compilación incremental de Kotlin | Lo midió el emulador: sin preparar, el primer sonido llegaba a los 2,4 s. `wakelock_plus` usa una marca de la ventana, que no pide permiso. Sin el ajuste de Kotlin, el APK no compila en esta máquina (E-015) |
| 2026-10-01 | Fase C: sin la llave, el APK de release se firma con la **llave de depuración** (no "sin firmar") y el script se niega a publicarlo; el arranque del APK, en **crema con el logo sobre su círculo carbón** | Flutter no entrega un APK de release sin firma, y así un clon del repositorio igual compila para probar. La pantalla de arranque de Android 12 dejaba el logo amarillo sobre blanco, ilegible |

---

## 11. Cierre

- **Commits de la tarjeta**, uno por fase probada:
  - `fcb085e` el plan (12-P);
  - `b7740f7` el acceso en Android (A);
  - `5b5a531` el timbre, la pantalla encendida y el ícono (B);
  - `137e531` la firma, el script de compilación y la instalación en el README (C).

  La fase D no lleva commit: es la dirección de retorno en el Keycloak de producción y el
  Release `apk-cocina-0.1.0`, con la etiqueta sobre `137e531`. El cierre (12-E) lleva este
  apartado, el índice de planes y dos líneas del README.
- **Criterios de aceptación (sección 7):** los ocho cumplidos.
  - **Se descarga, se instala y abre con el nombre y el logo del local:** en el teléfono del
    autor, desde el enlace público.
  - **Cocina entra con su cuenta, en la página de Keycloak, y la app no ve la contraseña.** Al
    cerrar sesión, Keycloak la volvió a pedir.
  - **Un pedido nuevo suena sin que nadie haya tocado la pantalla:** el 34, al instante.
  - **La pantalla no se apaga con la cola abierta:** medido en el emulador (fase B) y visto en
    el teléfono.
  - **La banda con el canal caído, bajo 10 s:** a los 3 s. Al volver la red, el canal volvió
    solo en 5 a 7 s.
  - **Una cuenta de recepción no opera en el APK:** ve el aviso y sale. El servidor igual la
    limita por rol, como prueba `probar_pedidos.py`.
  - **Ningún secreto en el repositorio ni en el APK:** fase C, con los 348 archivos del APK
    revisados.
  - **La web sigue igual:** `flutter test` 280 de 280, `flutter build web` y, contra
    producción, `probar_pedidos.py` con TODO CORRECTO.
- **Requisitos:** RNF-04 (la misma interfaz, ahora también instalada en Android); RF-06 y
  RF-07 en el APK; RF-03 (CA-03.2) y RNF-05 en el APK; RF-08. Decisión de la tutoría T3:
  D-43. El campo *"Frontend (URL pública o enlace al APK)"* del E3 lleva los dos.
- **Queda abierto, con destino:**
  - **el respaldo de la llave de firma**, a cargo del autor: sin ella no se puede publicar una
    versión que se instale encima de la actual;
  - **los pedidos de prueba 44 y 45**, que el autor cancela desde recepción antes de la
    revisión del E3;
  - **la cuenta de administración temporal de Keycloak**: tarjeta 09;
  - **los íconos de la barra de estado** sobre fondo claro: un APK nuevo en la semana del E4;
  - **E-014**, la vuelta lenta del canal en Chrome, es solo de la web: semana del E4.
- **Fecha de cierre:** 2026-10-01, con el APK publicado y probado por el autor en su teléfono.
