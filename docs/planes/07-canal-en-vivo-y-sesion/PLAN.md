# Plan 07 — El canal en vivo y la sesión, a prueba de cortes

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 07 — El canal en vivo y la sesión
- **Incremento:** tiempo real completo (E3)
- **Estado:** ✅ **Hecho** — en producción desde el 2026-09-30 y probada por el autor con dos
  dispositivos. Aprobado el 2026-09-29, sin cambios (propuesto el 2026-09-28)
- **Entrada al tablero:** 2026-09-28
- **Cierre:** 2026-09-30
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que ninguna pantalla **muestre como actual algo que ya no lo es**, ni **siga operando con una
sesión que el servidor ya no acepta**:

1. Si el canal en vivo se cae, recepción y cocina **lo ven en menos de 10 segundos**, con un
   aviso claro y un botón **Recargar** que vuelve a leer el estado actual (CA-03.2, RNF-05).
2. Cuando el canal vuelve, el aviso se va solo y la pantalla se pone al día.
3. Si el servidor rechaza la sesión —en la API o en el canal— y renovar el token no lo
   resuelve, la persona **vuelve a la pantalla de acceso** con un mensaje, en vez de quedarse
   en una pantalla con errores o en "Conectando…" para siempre.
4. Una conexión en vivo **no sobrevive a su token**: cuando vence, el servidor la corta y la
   app se reconecta sola con el token vigente, sin que la persona lo note.

CA-03.2 es un criterio de **RF-03, que es *Must***: sin esta tarjeta, el E3 no tiene todos
los *Must* en producción.

---

## 2. Alcance

**Incluye:**

- **El latido del canal**, acortado para detectar un corte silencioso en menos de 10 s (D-44).
- **El aviso de canal caído** con *Recargar*, en recepción (en las dos pestañas) y en cocina
  (D-45), y el aviso inmediato del navegador cuando el dispositivo pierde la red.
- **La reconexión que hoy no ocurre:** después de un corte decidido por el servidor o de una
  conexión rechazada, la app vuelve a intentarlo con el token vigente.
- **La sesión rechazada lleva al acceso** (D-46): el 401 que persiste después de renovar, en
  la API, y el rechazo del canal por token, después de renovar una vez.
- **El corte de la conexión al vencer su token** (D-47).
- **La medición del RNF-05** (el aviso en menos de 10 s), en local y en producción.

**No incluye:**

- **Marcar un producto agotado y el evento `producto:disponibilidad`:** tarjeta 08 (RF-13).
- **Cabeceras de seguridad, límite de peticiones y los clientes de Keycloak** (entre ellos,
  la vía para obtener un token desde Postman): tarjeta 09.
- **La tabla de pruebas del 2.8, los reportes versionados y la integración continua:**
  tarjeta 10. Esta tarjeta deja su evidencia en la sección 9, que la 10 consolida.
- **Guardar acciones sin red para enviarlas después.** Sin red, una venta no se envía y la
  app lo dice, como hoy. Una cola de acciones pendientes podría mandar a cocina un pedido
  minutos tarde, cuando el mostrador ya lo resolvió de otra forma.
- **Avisos con la app cerrada** (notificaciones del sistema): fuera de alcance.
- **El tiempo de espera en la cola (RF-10):** es *Could*.

---

## 3. Decisiones de diseño

### D-44 · El latido del canal se acorta para detectar un corte en menos de 10 s

Un corte se detecta por tres caminos, y solo uno es lento:

| Qué pasa | Cómo se entera la app | Cuánto tarda hoy |
|---|---|---|
| La API se cae o se reinicia | Caddy cierra la conexión y Socket.IO avisa | En el acto |
| El dispositivo pierde la red (Wi-Fi apagado, modo avión) | El navegador dispara el evento `offline` | En el acto, **si la app lo escucha**: hoy no lo hace |
| La red se "cuelga" sin que nadie cierre nada | Solo el latido: el servidor manda un ping cada `pingInterval` y el cliente da la conexión por muerta si no recibe ninguno en `pingInterval + pingTimeout` | **Hasta 45 s** (25 s + 20 s, los valores de fábrica) |

Lo del tercer caso está verificado en el código del cliente de Flutter (`socket_io_client`
3.1.6): el temporizador se arma con la suma de los dos valores que manda el servidor en el
saludo.

**Decisión:** `pingInterval` = **4 s** y `pingTimeout` = **3 s**, así que el corte se detecta
en **7 s como máximo**, con margen para mostrar el aviso antes de los 10 s. La app, además,
escucha `offline` y `online` del navegador.

- **Costo:** un paquete de pocos bytes cada 4 s por pantalla conectada. Con las cuatro o
  cinco pantallas del local, es despreciable.
- **Riesgo:** en una red móvil muy lenta, 3 s sin respuesta podría dar un corte falso. Se
  vería como un aviso breve seguido de una relectura: molesto pero no dañino. Se observa en
  la prueba del autor (fase E), contando las reconexiones.
- **Descartado:** consultar `/salud` cada pocos segundos. Sería un segundo mecanismo para lo
  mismo, y más tráfico que el latido.

### D-45 · Canal caído: una banda visible y *Recargar*

- **Qué se ve:** una banda de advertencia arriba de la pantalla, no el punto pequeño de hoy:
  *"Sin conexión en vivo. Lo que ves puede no estar al día."* con el botón **Recargar**. En
  recepción está sobre las dos pestañas, también en *Venta*, porque sin canal no llega el
  aviso de "pedido listo". En cocina, sobre la cola.
- **Cuándo aparece:** en el momento en que se detecta la caída. Al abrir la pantalla se
  esperan **5 s** a la primera conexión, para no alarmar en cada arranque. Si el corte lo
  decidió el servidor al vencer un token (D-47), la app se reconecta en el acto y la banda
  aparece solo si no lo logra en 3 s.
- **Qué hace *Recargar*:** vuelve a leer de la API lo que la pantalla muestra (los pedidos y,
  en recepción, también la carta) e intenta reconectar el canal. **No recarga la página**:
  eso obligaría a pasar de nuevo por Keycloak.
- **Cuando el canal vuelve:** la banda se va sola y la lista se relee, como ya hace hoy.
- **Mientras tanto se puede seguir trabajando:** entregar, empezar, marcar listo y vender van
  por la API, no por el canal. Si lo que falta es la red entera, esas acciones muestran el
  mensaje de "sin conexión" que ya existe (CU-03, flujo A2).
- El indicador "En vivo / Conectando…" de la barra se queda: la banda es el aviso y el
  indicador, el estado.

### D-46 · Toda sesión que el servidor rechaza termina en la pantalla de acceso

El E3 lo pide textualmente: *"un 401 que devuelve al usuario al login"*.

| Caso | Hoy | Con esta tarjeta |
|---|---|---|
| La API responde 401 y la renovación del token falla | Vuelve al acceso con "Tu sesión expiró" | Igual |
| La API responde 401, se renueva, y el reintento **vuelve** a dar 401 | Queda la pantalla con un error | **Vuelve al acceso** |
| El canal rechaza la conexión por el token | Queda en "Conectando…" **para siempre**: el cliente no reintenta después de un rechazo (verificado en `socket_io_client` 3.1.6) | Renueva el token **una vez** y reconecta; si lo vuelven a rechazar, **vuelve al acceso** |
| El canal rechaza la conexión porque la cuenta no tiene rol del sistema | Igual que arriba | **Vuelve al acceso** |

El tercer caso es un **defecto latente**: una computadora que se suspende más de una hora
despierta con el token vencido, el canal lo rechaza, y la pantalla queda sin avisos en vivo
aunque la app renueve el token después.

### D-47 · Una conexión en vivo no sobrevive a su token

- **Hoy** el token se comprueba **solo al conectarse**. Una conexión abierta sigue recibiendo
  pedidos —con el nombre y el celular del cliente— después de que su token venció, o de que
  la cuenta se deshabilitó en Keycloak.
- **Decisión:** al aceptar la conexión, el servidor programa su corte para el instante en que
  vence el token (`exp`). La app renueva el token a los 48 minutos (el 80 % de los 60), así
  que al cortarse ya tiene uno nuevo, y se reconecta en el acto.
- Hace falta porque el cliente de Flutter **no se reconecta solo** después de un corte
  decidido por el servidor (el mismo `destroy()` del caso anterior). La reconexión se
  programa en la app.

### Cómo se mide el RNF-05 (el aviso en menos de 10 s)

- **El corte silencioso, en local:** un script propio, `pruebas/tiempo-real/medir-caida.js`,
  pone un "tapón" TCP entre el cliente de Socket.IO y la API: deja pasar el tráfico, y en un
  instante dado deja de reenviarlo **sin cerrar nada**, que es lo que hace una red colgada.
  Mide desde ese instante hasta que el cliente declara la conexión perdida. **10
  repeticiones; se reporta el peor caso.** Tiene que quedar bajo 10 s; se espera 7 s o menos.
- **La configuración, en producción:** el saludo de Socket.IO trae `pingInterval` y
  `pingTimeout`. El mismo script, en otro modo, se conecta a la dirección pública y los lee:
  prueba que producción corre con los valores medidos en local.
- **En producción, en el celular:** con la app abierta, se activa el modo avión y se
  cronometra hasta que aparece la banda; después se desactiva y se comprueba que se va sola y
  que la lista se relee. Queda una captura de pantalla fechada.

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — El servidor: latido corto y corte al vencer el token
- [x] `pingInterval` 4 s y `pingTimeout` 3 s en el canal (D-44).
- [x] `usuarioDelToken` devuelve también cuándo vence el token.
- [x] Cada conexión se corta al vencer su token, y el temporizador se limpia si la conexión se
      cierra antes (D-47).
- [x] Pruebas con el cliente real de Socket.IO:
  - el saludo trae los dos valores;
  - una conexión con un token que vence en 2 s se corta a los 2 s;
  - una conexión que se cierra antes no deja un temporizador vivo.
- [x] `pruebas/tiempo-real/medir-caida.js`, contra la API local: 10 repeticiones bajo 10 s.

### Fase B — La app: la sesión y la reconexión
- [x] El canal distingue por qué se cortó:
  - si el corte fue del servidor, reconecta en el acto con el token vigente;
  - si rechazó el token, pide renovarlo una vez y reconecta;
  - si lo vuelve a rechazar, o si la cuenta no tiene rol, avisa que la sesión terminó.
- [x] El cliente de la API: un 401 que persiste después de renovar cierra la sesión.
- [x] La sesión, cerrada por cualquiera de los dos, vuelve al acceso con "Tu sesión expiró.
      Inicia sesión de nuevo."
- [x] Pruebas de la lógica del canal con un socket simulado, del cliente de la API y de la
      sesión.
- [x] En local, con la vigencia del token bajada a **2 minutos solo en el Keycloak de
      desarrollo**: el canal se corta a los 2 minutos y la app se reconecta sola. *(Con el
      cliente real fuera del navegador; la banda llega en la fase C.)*

### Fase C — La app: el aviso de canal caído
- [x] La banda con *Recargar* (D-45), en las dos pestañas de recepción y en cocina.
- [x] Los eventos `offline` y `online` del navegador. Van en un archivo aparte, que solo se
      carga en la web, como el sonido.
- [x] Los 5 s de gracia al abrir y **1 s** para cualquier corte *(ver revisiones)*.
- [x] Pruebas de *widgets*:
  - la banda aparece al perder el canal y se va al volver;
  - no aparece en los primeros 5 s, y sí si no conecta en ese tiempo;
  - *Recargar* relee *(ver revisiones)*;
  - está a la vista en *Venta*, en *Pedidos* y en cocina;
  - a 320 px no se desborda.
- [x] En el navegador, en local: la red cortada y el canal colgado, revisados por el autor.

### Fase D — En producción
- [x] El autor trae el código al servidor y reconstruye la API. No hay migraciones.
      **Fuera del horario de atención (18:00 a 23:30).**
- [x] Se publica la app.
- [x] Contra la dirección pública:
  - el saludo trae 4 s y 3 s;
  - `probar_pedidos.py` y `medir_aviso.py`, sin regresiones;
  - la API con 0 reinicios.
- [x] El modo avión en el celular, con su captura.

### Fase E — La prueba del autor y el cierre
- [x] El autor, en producción, con dos dispositivos:
  - la banda y *Recargar*;
  - una venta mientras cocina está sin canal, que cocina ve al volver;
  - la vuelta al acceso *(verificada con el cliente real en la fase B: provocarla a mano
    en producción exigiría invalidar la sesión desde la consola de Keycloak)*.

  Se cuentan las reconexiones durante la prueba (riesgo de D-44).
- [x] **Hallazgo de la prueba:** después de iniciar sesión, cocina quedaba con el sonido
      apagado hasta el primer toque, y un pedido llegó sin sonar. Se suma la franja de
      sonido apagado.
- [x] La franja, en producción, revisada por el autor: esta vez el navegador ya dejaba
      sonar al entrar, así que no hizo falta *(ver la sección 9)*.
- [x] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **API:** `backend/src/tiempo-real.js` (el latido y el corte al vencer) y
  `backend/src/autenticacion.js` (cuándo vence el token).
- **Pruebas de la API:** `backend/test/tiempo-real.test.js`, y
  `pruebas/tiempo-real/medir-caida.js` con `medir_caida.py`, que obtiene el token real como
  `medir_aviso.py` *(nuevos)*.
- **App:**
  - `frontend/lib/api/canal_en_vivo.dart`: la reconexión y el rechazo;
  - `frontend/lib/api/cliente_api.dart`: el 401 que persiste;
  - `frontend/lib/autenticacion/servicio_sesion.dart` y `frontend/lib/main.dart`: el cierre
    de la sesión rechazada;
  - `frontend/lib/pantallas/aviso_sin_conexion.dart` *(nuevo)*: la banda;
  - `frontend/lib/pantallas/red.dart` y `red_web.dart` *(nuevos)*: `offline` y `online`;
  - `frontend/lib/pantallas/aviso_sin_sonido.dart` *(nuevo, hallazgo de la fase E)*,
    `timbre.dart` y `timbre_web.dart`: la franja de sonido apagado;
  - `frontend/lib/pantallas/pantalla_recepcion.dart`, `pantalla_cocina.dart` y
    `segun_rol.dart`. *(`pedidos_en_vivo.dart`, previsto en el plan, no hizo falta tocarlo:
    la relectura al reconectar ya estaba.)*
- **Pruebas de la app:** `frontend/test/canal_en_vivo_test.dart` y
  `aviso_sin_conexion_test.dart` *(nuevos)*, `identidad_test.dart`,
  `cliente_api_test.dart`, `servicio_sesion_test.dart`, `pantalla_cocina_test.dart`,
  `pantalla_recepcion_test.dart` y `pedidos_de_recepcion_test.dart`.
- **Documentación:** `README.md` (qué pasa si se cae el canal y la medición nueva).

No cambia la base de datos, el contrato HTTP de la API ni el realm de producción.

---

## 6. Cómo se prueba

| Qué | Cómo | Resultado esperado |
|---|---|---|
| El latido | Prueba automática: el saludo del canal | `pingInterval` 4000 y `pingTimeout` 3000 |
| El corte silencioso | `medir-caida.js` con el tapón, 10 veces, en local | Peor caso bajo 10 s (se espera ≤ 7 s) |
| El corte al vencer el token | Prueba automática con un token de 2 s | La conexión se corta a los 2 s; ninguna dura más que su token |
| La reconexión transparente | Local, con tokens de 2 minutos | A los 2 minutos se corta y reconecta sola, sin banda |
| El canal rechazado | Prueba con socket simulado | Renueva una vez; si lo rechazan otra vez, la sesión termina |
| El 401 que persiste | Prueba del cliente de la API | La sesión termina y se vuelve al acceso con el mensaje |
| La banda | Pruebas de *widgets* y navegador | Aparece al caer, se va al volver, *Recargar* relee; a la vista en las tres vistas |
| El modo avión | Celular, en producción | La banda en menos de 10 s (se espera al instante), con captura |
| Regresiones | `npm test`, `flutter test`, `flutter analyze`, `probar_pedidos.py`, `medir_aviso.py` | Todo en verde; el aviso de pedido nuevo, bajo 2 s |

---

## 7. Criterios de aceptación

- Con el canal colgado en silencio, la banda aparece **en menos de 10 s** (peor caso medido).
  Con la API caída o el dispositivo sin red, **en el acto**.
- *Recargar* muestra el estado actual sin recargar la página. Al volver el canal, la banda se
  va sola y la lista se relee.
- Con el canal caído, las acciones siguen funcionando por la API mientras haya red.
- **Ninguna pantalla sigue operando con una sesión rechazada:** un 401 que la renovación no
  resuelve, o un canal que rechaza el token dos veces, llevan al acceso con el mensaje.
- **Ninguna pantalla queda en "Conectando…" para siempre** mientras la sesión sea válida.
- **Ninguna conexión en vivo dura más que su token**, y la persona no nota la reconexión.
- Sin regresiones en las pruebas ni en producción.

---

## 8. Requisitos que cubre

- **Del sistema:**
  - **RF-03, CA-03.2** (*Must*): el aviso y la recarga cuando cae el canal;
  - **RNF-05**, su segunda mitad: el aviso en menos de 10 s y la recarga manual;
  - **RF-08, CA-08.2** (*Should*): el token vencido lleva al acceso;
  - **CU-03, flujo A2**: con el canal caído, el cambio se guarda igual y se avisa;
  - **RNF-02**: el token se exige también durante la conexión en vivo.
- **Institucionales:** **#2** (autenticación y control de acceso).
- **De la entrega (E3):** *"sesión o token que vence, y un 401 que devuelve al usuario al
  login"*, y todos los *Must* en producción.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El servidor | ✅ Verificada | 2026-09-29 | **Antes, en producción** (`medir_caida.py` en modo `saludo` contra `https://maxpizzapp.tech`): *"latido cada 25000 ms, espera 20000 ms: una red colgada se nota en 45000 ms como maximo"*. **El cambio:** el canal anuncia `pingInterval` 4000 y `pingTimeout` 3000; `usuarioDelToken` devuelve cuándo vence el token (`venceEn`), que la ruta `/sesion` no expone; y cada conexión programa su corte para esa hora, con `socket.disconnect(true)`, y lo cancela si se cierra antes. **`npm test`: 273 de 273** (269 anteriores y **4 nuevas**): el saludo trae 4000 y 3000; con un token de 2 s la conexión se corta a los 1,85 s por `io server disconnect`, es decir, la corta el servidor; con un token de 60 minutos sigue abierta pasados 2,5 s; y con un reloj simulado, el corte queda programado entre 59 y 60 minutos y se cancela al cerrarse la conexión. **Contra la API local en Docker, con el token real de cocina** (`medir_caida.py`, 10 cortes con el tapón TCP, cada uno en un momento al azar del ciclo del latido): **mínimo 3,04 s, mediana 6,13 s, máximo 6,89 s**. Los 10 se detectaron por el latido (`ping timeout`) y todos bajo 10 s, dentro de los 3 a 7 s que da la teoría. El modo `saludo` en local dice 7000 ms. **Sin regresiones, contra la API local:** `probar_pedidos.py` **76 de 76**; el aviso en vivo, mediana 19 ms a cocina, 15 ms a recepción y 17 ms de lo agregado; 0 reinicios. **Lo que salió:** (1) **esta fase no puede llegar sola a producción.** El servidor ahora corta cada conexión al vencer su token, y la app publicada no se reconecta después de un corte del servidor (es lo que arregla la fase B): a los 60 minutos, las pantallas quedarían en "Conectando…". El servidor se actualiza en la fase D, con la app de las fases B y C ya publicada. (2) Docker Desktop no arrancaba: otra vez E-010, ahora en `docker-secrets-engine`. Se resolvió renombrando las dos carpetas, como dice el registro |
| B — La sesión y la reconexión | ✅ Verificada | 2026-09-30 | **El canal** (`lib/api/canal_en_vivo.dart`) deja el socket detrás de una interfaz mínima (`SocketDelCanal`), para poder simular cortes y rechazos, y decide por el motivo: un corte del servidor (`io server disconnect`) reconecta en el acto con el token vigente; un rechazo por el token (`TOKEN_AUSENTE`, `TOKEN_EXPIRADO`, `TOKEN_INVALIDO`) lo renueva **una vez** y reconecta; un segundo rechazo, o uno por otro motivo (`ROL_SIN_PERMISO`), termina la sesión; y una caída de la red o del servidor queda en manos de la reconexión del propio cliente. **El cliente de la API:** si el reintento con el token renovado vuelve a dar 401, termina la sesión; un 403 no, porque el token es válido y lo que no alcanza es el rol. **La sesión** suma `terminarSesionRechazada()`: vuelve al acceso con *"Tu sesión expiró. Inicia sesión de nuevo."* y olvida los tokens, también el de renovación. **`flutter test`: 214 de 214** (195 anteriores y **19 nuevas**): 15 del canal con el socket simulado (el corte del servidor reconecta sin renovar; tres motivos de caída de la red no tocan nada; los tres rechazos del token renuevan una vez y reconectan con el token nuevo; el segundo rechazo termina la sesión; después de volver a entrar, un rechazo futuro tiene otra vez su renovación; sin rol termina sin renovar; si la renovación falla no reconecta; un error sin código no hace nada; si la pantalla cerró el canal mientras renovaba, no se reabre; y los avisos siguen llegando), 3 del cliente de la API (el 401 que persiste termina la sesión con un solo reintento; el reintento que pasa no; un 403 no) y 1 de la sesión. `flutter analyze` sin observaciones. **Con el cliente real, contra la API y el Keycloak locales** (verificación fuera del repositorio, con la vigencia del token bajada a 120 s solo en el Keycloak de desarrollo y devuelta después a 3600): un token inválido es rechazado por el servidor, el canal lo renueva una vez y entra; un rechazo que se repite termina la sesión; y **el servidor cortó la conexión a la hora exacta en que vencía el token (5 ms antes) y el canal volvió a entrar 15 ms después**, con el token que ya tenía renovado, sin renovar ni terminar la sesión, y el pedido nuevo que se vendió enseguida le llegó por el canal. **Lo que salió:** el payload del rechazo que llega al cliente de Flutter es `{message, data: {codigo}}`, el mismo que arma el servidor, así que el código se lee sin adivinar el texto. Docker Desktop estaba cerrado tras reiniciar la máquina, sin error; solo hizo falta abrirlo |
| C — El aviso de canal caído | ✅ Verificada · **revisada por el autor** | 2026-09-30 | **La lógica** (`VigiaDelCanal`, en `lib/pantallas/aviso_sin_conexion.dart`, sin pantalla): al abrir espera 5 s la primera conexión; ante un corte, 1 s, para que la reconexión tras el vencimiento del token (15 ms, fase B) no haga parpadear nada; y si el dispositivo pierde la red, avisa en el acto, con los eventos `online` y `offline` del navegador (`red_web.dart`, cargado solo desde `main.dart`, como el sonido). **La banda** (`AvisoSinConexion`), amarilla y anunciada a los lectores de pantalla, dice *"Sin conexión en vivo. Lo que ves puede no estar al día."* con **Recargar**, que muestra "Recargando…" y no se puede tocar dos veces. En cocina va sobre la cola y relee la cola. En recepción va **sobre las dos pestañas**, también *Nueva venta*, y relee los pedidos **sin tocar la venta en curso**. **`flutter test`: 236 de 236** (214 anteriores y **22 nuevas**): 7 de la lógica (los 5 s al abrir, conectar antes, arrancar conectado, el corte al segundo y la vuelta, el corte por vencimiento que no parpadea, la red del dispositivo y la red que vuelve con el canal todavía caído); 7 de la banda (el texto, *Recargar* con su espera y sin doble toque, una lectura que falla, y 320, 360, 768 y 1366 px sin desbordes); 5 en cocina (la banda a los 5 s, que se va y relee al conectar; el corte al segundo y *Recargar* que trae un pedido nuevo; seguir trabajando con *Empezar*; la red del dispositivo; 320 px); y 3 en recepción (la banda en las dos pestañas; *Recargar* relee los pedidos y conserva el nombre escrito en la venta; se va sola al volver). Las pruebas de la venta arrancan con un canal conectado, que es el caso normal. `flutter analyze` sin observaciones. **Lo que se vio en el navegador** (build de producción en local, con un servidor de revisión que congela el canal sin cerrarlo): el autor vio aparecer la banda **a los 4 s** y, en otra vuelta, **a los 3 s en cocina y 5 s en recepción**, bajo los 8 s del peor caso. **Lo que salió:** (1) el tema de la app estira los `FilledButton` a todo el ancho, y dentro de la fila de la banda eso era un ancho infinito: el botón lleva su propio tamaño mínimo. (2) **La vuelta del canal en Chrome tarda de 10 a 30 s** tras una red colgada, por el defecto del cliente de Flutter en la web contado en las revisiones del plan. Medido con el mismo tapón: cliente de JavaScript en Chrome, de 1,4 a 7,7 s; cliente de Flutter fuera del navegador, de 0,3 a 6,4 s; cliente de Flutter en Chrome, de 10 a 15 s con los valores de fábrica y de 28 a 31 s con un intento de 5 s, que por eso se descartó. No afecta al aviso ni a *Recargar*. El arreglo de fondo queda para la semana del E4 (E-014) |
| D — En producción | ✅ Verificada | 2026-09-30 | **El modo avión, del autor, en su celular con cocina abierta en `https://maxpizzapp.tech`** (dos capturas de las 11:27, sin datos personales): antes, "En vivo"; con el modo avión, **la banda en el mismo minuto**, con *Recargar* y el indicador en "Conectando…", sin desbordes en el ancho del celular. El aviso lo dispara el evento `offline` del navegador, sin esperar al latido. **Lo que midió el agente:** **Antes** (11:16, 30-sep): la API corría desde el 25-sep con 0 reinicios y anunciaba el latido viejo, *"cada 25000 ms, espera 20000 ms: una red colgada se nota en 45000 ms como maximo"*. **El orden, para que nadie quede con la app vieja frente al servidor nuevo** (la app vieja no se reconectaba tras el corte al vencer el token): primero se publicó la app, versión `20260930-111556`, que funciona igual con el servidor viejo; después, **el autor** trajo el código y reconstruyó solo la API, sin migraciones. **Después, contra `https://maxpizzapp.tech`:** el saludo anuncia **4000 y 3000 ms**, así que una red colgada se nota en 7 s como máximo. Solo se recreó `maxpizzapp-backend`: Keycloak y la base siguieron en pie desde hacía 7 días, es decir, sin el problema de E-013. La API tiene **0 reinicios** y ninguna línea de error en su registro, y `/salud` responde 200 con la base. Con las cuentas reales: el acceso con PKCE, **correcto**; `probar_pedidos.py`, **76 de 76**; y el aviso en vivo, 10 mediciones de cada uno: **pedido nuevo a cocina, mediana 176 ms y peor caso 240 ms; cambio de estado a recepción, 198 ms y 375 ms; lo agregado a cocina, 172 ms y 749 ms**. Al terminar, ningún pedido activo (63 entregados y 90 cancelados, todos de pruebas) y la API todavía con 0 reinicios |
| E — La prueba del autor | ✅ Verificada | 2026-09-30 | **En producción, con recepción en la computadora y cocina en el celular del autor** (datos ficticios: *Gabriel Cantante · 60000001*; capturas `e1` a `e5` del celular, de 11:32 a 11:34). (1) Cocina en vivo, sin pedidos. (2) **Modo avión: la banda en el acto.** (3) Con cocina sin red, recepción vende el **pedido 44** (Champiñones y una gaseosa, para llevar, "Bien cocida"); cocina no lo ve, que es lo correcto. (4) Sin el modo avión, la banda sigue unos segundos mientras el canal vuelve. (5) **El pedido 44 aparece solo**, "recién llegado", con su observación resaltada, **a los 5 a 7 s de volver la red y sin tocar *Recargar***. **Ningún corte falso:** la banda solo apareció cuando se cortó la red (riesgo de D-44, sin observarse). **Hallazgo:** en las capturas, el ícono de sonido aparece tachado: el pedido 44 **llegó sin sonar**. El navegador no deja sonar una página hasta que la persona la toca, e iniciar sesión recarga la página; el sonido se activaba recién con el primer toque (fase I de la tarjeta 06), y si nadie tocaba la cocina, el primer pedido llegaba mudo. **Corrección:** una **franja** *"El sonido está apagado. Tocá en cualquier parte de la pantalla para activarlo."*, en recepción y en cocina, mientras el navegador no deje sonar. Al primer toque en cualquier parte, el sonido se activa, **suena una vez para confirmarlo** y la franja se va. Nunca suena al cargar la página, y si el toque cae sobre el botón del parlante no suena dos veces. `flutter test`: **242 de 242** (236 anteriores y **6 nuevas**: la franja aparece, se va al activarse, no está si el sonido ya anda, 320 px en cocina, las dos pestañas de recepción, y su contraste). **El arreglo de fondo para cocina es el APK** (tarjeta 12): una app instalada no tiene esa regla del navegador y suena desde que se abre **La franja, en producción** (30-sep, con la app `20260930-120338`): el autor cerró la sesión de cocina en el celular y volvió a entrar, y esta vez la pantalla **quedó con sonido desde el arranque**, sin franja. Es el comportamiento correcto: la franja solo aparece mientras el navegador bloquea el sonido, y el navegador no siempre lo bloquea (decide con su propia política, por ejemplo según cuánto se usó el sitio con sonido). El caso en que sí bloquea, el del pedido 44, lo cubren las 6 pruebas de la franja |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-28 | Versión inicial propuesta | El enunciado del E3 exige todos los *Must* en producción y un 401 que devuelva al acceso. CA-03.2 (RF-03, *Must*) estaba sin cumplir: solo existía el indicador "Conectando…". Al revisar el cliente de Socket.IO para escribir el plan aparecieron el latido de 45 s y el defecto latente de D-46 |
| 2026-09-29 | Las decisiones pasan a numerarse **D-44 a D-47** | La D-43 quedó para el APK de cocina, que la tutoría T3 sumó al E3 antes de que este plan se aprobara |
| 2026-09-29 | **Aprobado** por el autor, sin cambios | Las respuestas de la tutoría T3 (APK para cocina, sin Postman) y las recomendaciones escritas del E2 no tocan esta tarjeta |
| 2026-09-30 | **Fase C, dos simplificaciones de D-45.** (1) Una sola espera de **1 s** para cualquier corte, en lugar de avisar en el acto y esperar 3 s solo tras el corte por vencimiento. (2) *Recargar* vuelve a leer los pedidos (en cocina, la cola), pero **no** fuerza la reconexión ni relee la carta | (1) La fase B midió que, tras el corte por vencimiento, el canal vuelve en 15 ms: con 1 s alcanza para que la banda no parpadee, sin tener que distinguir el motivo del corte en la pantalla. El corte silencioso se sigue avisando antes de los 10 s: a los 8 s como mucho (7 del latido y 1 de espera). (2) El cliente de Socket.IO reintenta solo cada pocos segundos, y pedirle que conecte mientras espera su próximo intento no hace nada. Releer la carta reiniciaría la venta que se está armando |
| 2026-09-30 | **Fase C, a partir de la revisión del autor:** cada intento de reconexión espera respuesta **5 s** (de fábrica, 20) y la espera entre intentos llega a **3 s** como máximo (de fábrica, 5) | Al soltar la red congelada, el autor vio que el canal tardaba 15 y 10 s en volver. La causa: el intento en curso quedaba esperando su respuesta hasta 20 s. Medido con el cliente real y el tapón, con caídas de 2 a 10 s: antes volvía entre 1,6 y 15,5 s después de soltar (6 cortes); con el ajuste, entre 0,3 y 6,4 s (8 cortes). El aviso de la caída no cambia: peor caso 6,4 s antes y 6,2 s después |
| 2026-09-30 | **Se deshace la mitad del ajuste anterior:** el tiempo de cada intento vuelve al de fábrica (20 s); la espera máxima entre intentos se queda en 3 s. Decidido con el autor. El arreglo de fondo pasa a la semana del E4 | Con la app en Chrome, el autor midió que la vuelta **empeoraba** con el ajuste: 28 y 31 s, contra 15 y 10 s con los valores de fábrica. La causa es un defecto del cliente de Socket.IO para Flutter en la web: al vencer un intento no cierra el WebSocket que el navegador está abriendo, y Chrome admite uno solo abriéndose por servidor, así que los intentos siguientes quedan en fila detrás del colgado. Acortar el tiempo por intento multiplicaba los colgados. Lo confirmó una sonda en Chrome con el cliente de JavaScript, que sí cierra el WebSocket: volvió entre 1,4 y 7,7 s con la misma configuración. El aviso y *Recargar*, que son lo que exigen CA-03.2 y RNF-05, no dependen de esto. El APK de cocina usa el cliente nativo, que no tiene el defecto (0,3 a 6,4 s). El arreglo de fondo, un adaptador propio para la web que cierre el intento vencido, queda para la semana del E4 |
| 2026-09-30 | **Fase E: se suma la franja de sonido apagado** | En la prueba del autor, el pedido 44 llegó a cocina sin sonar: tras iniciar sesión, el navegador no deja sonar hasta el primer toque. Ninguna página puede saltarse esa regla, pero sí decirla: la franja evita que la cocina quede muda sin que nadie lo note. Para cocina, el arreglo de fondo es el APK (tarjeta 12), que queda con el requisito de sonar desde el arranque |

---

## 11. Cierre

- **Commits de la tarjeta**, uno por fase probada:
  - `b03a02d` el plan (07-P);
  - `699e6fa` el servidor: latido corto y corte al vencer el token (A);
  - `aa96bd4` la app: la sesión y la reconexión (B);
  - `5ba384a` la app: la banda de canal caído (C);
  - `2a55599` la franja de sonido apagado (hallazgo de la fase E).

  La fase D no lleva commit: es la publicación de la app y la reconstrucción de la API en el
  servidor. El cierre (07-E) lleva este apartado y el índice de planes.
- **Criterios de aceptación (sección 7):** los siete cumplidos.
  - **La banda con el canal colgado, bajo 10 s:** la caída se detectó a los 6,89 s en el peor
    de 10 cortes, y la banda aparece 1 s después. En el navegador, el autor la vio a los 3 a
    5 s. Con el dispositivo sin red, en el acto.
  - ***Recargar*, sin recargar la página**, y la banda que se va sola al volver el canal.
  - **Las acciones siguen por la API con el canal caído**, cubierto por las pruebas de cocina.
  - **Ninguna sesión rechazada sigue operando**, y **ninguna pantalla queda en "Conectando…"
    para siempre**: fase B, con el socket simulado y con el cliente real.
  - **Ninguna conexión dura más que su token:** el corte llegó 5 ms antes del vencimiento y la
    reconexión, 15 ms después, sin que se note.
  - **Sin regresiones:** `npm test` 273 de 273, `flutter test` 242 de 242 y, contra
    producción, `probar_pedidos.py` 76 de 76 y el aviso en vivo con medianas de 172 a 198 ms.
- **Requisitos:** RF-03 (CA-03.2), la segunda mitad de RNF-05, RF-08 (CA-08.2), CU-03 (flujo
  A2) y RNF-02 durante la conexión en vivo. Con esta tarjeta, **todos los *Must* quedan en
  producción**, como pide el E3.
- **Queda abierto, con destino:**
  - **E-014:** en Chrome, el canal tarda de 10 a 30 s en volver tras una red colgada. No
    afecta al aviso ni a *Recargar*. El arreglo de fondo, un adaptador propio de WebSocket
    para la web, va a la semana del E4, con su plan;
  - **el sonido en cocina desde el arranque** queda como requisito de la tarjeta 12 (APK). En
    la web, la franja avisa cuando el navegador lo bloquea;
  - **la vuelta al acceso** no se provocó a mano en producción, porque exigiría invalidar la
    sesión desde la consola de Keycloak. Quedó verificada en la fase B, con el cliente real.
- **Fecha de cierre:** 2026-09-30, con la tarjeta en producción y aprobada por el autor.
