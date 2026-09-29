# Plan 07 — El canal en vivo y la sesión, a prueba de cortes

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 07 — El canal en vivo y la sesión
- **Incremento:** tiempo real completo (E3)
- **Estado:** 🔵 **Aprobado** el 2026-09-29, sin cambios (propuesto el 2026-09-28)
- **Entrada al tablero:** 2026-09-28
- **Cierre:** —
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
- [ ] `pingInterval` 4 s y `pingTimeout` 3 s en el canal (D-44).
- [ ] `usuarioDelToken` devuelve también cuándo vence el token.
- [ ] Cada conexión se corta al vencer su token, y el temporizador se limpia si la conexión se
      cierra antes (D-47).
- [ ] Pruebas con el cliente real de Socket.IO:
  - el saludo trae los dos valores;
  - una conexión con un token que vence en 2 s se corta a los 2 s;
  - una conexión que se cierra antes no deja un temporizador vivo.
- [ ] `pruebas/tiempo-real/medir-caida.js`, contra la API local: 10 repeticiones bajo 10 s.

### Fase B — La app: la sesión y la reconexión
- [ ] El canal distingue por qué se cortó:
  - si el corte fue del servidor, reconecta en el acto con el token vigente;
  - si rechazó el token, pide renovarlo una vez y reconecta;
  - si lo vuelve a rechazar, o si la cuenta no tiene rol, avisa que la sesión terminó.
- [ ] El cliente de la API: un 401 que persiste después de renovar cierra la sesión.
- [ ] La sesión, cerrada por cualquiera de los dos, vuelve al acceso con "Tu sesión expiró.
      Inicia sesión de nuevo."
- [ ] Pruebas de la lógica del canal con un socket simulado, del cliente de la API y de la
      sesión.
- [ ] En local, con la vigencia del token bajada a **2 minutos solo en el Keycloak de
      desarrollo**: el canal se corta a los 2 minutos y la app se reconecta sola, sin banda.

### Fase C — La app: el aviso de canal caído
- [ ] La banda con *Recargar* (D-45), en las dos pestañas de recepción y en cocina.
- [ ] Los eventos `offline` y `online` del navegador. Van en un archivo aparte, que solo se
      carga en la web, como el sonido.
- [ ] Los 5 s de gracia al abrir y los 3 s para el corte por vencimiento.
- [ ] Pruebas de *widgets*:
  - la banda aparece al perder el canal y se va al volver;
  - no aparece en los primeros 5 s, y sí si no conecta en ese tiempo;
  - *Recargar* relee e intenta reconectar;
  - está a la vista en *Venta*, en *Pedidos* y en cocina;
  - a 320 px no se desborda.
- [ ] En el navegador, en local: la API detenida, la red cortada y el canal colgado.

### Fase D — En producción
- [ ] El autor trae el código al servidor y reconstruye la API. No hay migraciones.
      **Fuera del horario de atención (18:00 a 23:30).**
- [ ] Se publica la app.
- [ ] Contra la dirección pública:
  - el saludo trae 4 s y 3 s;
  - `probar_pedidos.py` y `medir_aviso.py`, sin regresiones;
  - la API con 0 reinicios.
- [ ] El modo avión en el celular, cronometrado, con su captura.

### Fase E — La prueba del autor y el cierre
- [ ] El autor, en producción, con dos dispositivos:
  - la banda y *Recargar*;
  - una venta mientras cocina está sin canal, que cocina ve al volver;
  - la vuelta al acceso.

  Se cuentan las reconexiones durante la prueba (riesgo de D-44).
- [ ] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **API:** `backend/src/tiempo-real.js` (el latido y el corte al vencer) y
  `backend/src/autenticacion.js` (cuándo vence el token).
- **Pruebas de la API:** `backend/test/tiempo-real.test.js` y
  `pruebas/tiempo-real/medir-caida.js` *(nuevo)*.
- **App:**
  - `frontend/lib/api/canal_en_vivo.dart`: la reconexión y el rechazo;
  - `frontend/lib/api/cliente_api.dart`: el 401 que persiste;
  - `frontend/lib/autenticacion/servicio_sesion.dart` y `frontend/lib/main.dart`: el cierre
    de la sesión rechazada;
  - `frontend/lib/pantallas/aviso_sin_conexion.dart` *(nuevo)*: la banda;
  - `frontend/lib/pantallas/red.dart` y `red_web.dart` *(nuevos)*: `offline` y `online`;
  - `frontend/lib/pantallas/pantalla_recepcion.dart`, `pantalla_cocina.dart` y
    `frontend/lib/pedidos/pedidos_en_vivo.dart`.
- **Pruebas de la app:** `frontend/test/canal_en_vivo_test.dart` *(nuevo)*,
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
| A — El servidor | ⬜ Pendiente | | |
| B — La sesión y la reconexión | ⬜ Pendiente | | |
| C — El aviso de canal caído | ⬜ Pendiente | | |
| D — En producción | ⬜ Pendiente | | |
| E — La prueba del autor | ⬜ Pendiente | | |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-28 | Versión inicial propuesta | El enunciado del E3 exige todos los *Must* en producción y un 401 que devuelva al acceso. CA-03.2 (RF-03, *Must*) estaba sin cumplir: solo existía el indicador "Conectando…". Al revisar el cliente de Socket.IO para escribir el plan aparecieron el latido de 45 s y el defecto latente de D-46 |
| 2026-09-29 | Las decisiones pasan a numerarse **D-44 a D-47** | La D-43 quedó para el APK de cocina, que la tutoría T3 sumó al E3 antes de que este plan se aprobara |
| 2026-09-29 | **Aprobado** por el autor, sin cambios | Las respuestas de la tutoría T3 (APK para cocina, sin Postman) y las recomendaciones escritas del E2 no tocan esta tarjeta |

---

## 11. Cierre

—
