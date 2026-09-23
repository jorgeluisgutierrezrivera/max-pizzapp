# Plan 03 — API base: estado del servicio y validación de token

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 03 — API base: estado del servicio y validación de token
- **Incremento:** cimientos (servidor de aplicación)
- **Estado:** ✅ Hecho — desplegada en `https://maxpizzapp.tech/api/v1` y verificada el
  2026-09-23, con el monitor del RNF-05 en marcha; a la espera de los commits 12b y 12c
- **Entrada al tablero:** 2026-09-22
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Levantar el **servidor de aplicación**: un proceso Express que responde bajo `/api/v1`, que
sabe decir si su base de datos está viva y que **sabe quién llama y con qué rol** antes de
ejecutar nada.

No entrega todavía ninguna funcionalidad del negocio. Entrega las dos piezas sobre las que
se apoyan todas las demás: la ruta que el monitor de disponibilidad va a consultar cada
cinco minutos, y la comprobación del token que convierte a Keycloak en algo más que una
pantalla de acceso bonita. **La interfaz puede ocultar lo que un rol no debe hacer; solo el
servidor puede impedirlo**, y esta tarjeta es donde eso se construye.

---

## 2. Alcance

**Incluye:**

- Proyecto Node en `backend/`, con las versiones **fijadas** y anotadas en el README.
- **`GET /api/v1/salud`**: única ruta sin token, con la respuesta que fija la Tabla 12 del
  documento —200 si el servicio y su base responden, **503** si la base no responde—.
- **Middleware de validación de token**: firma contra las claves publicadas por Keycloak,
  emisor, expiración y **audiencia**. Deja disponible el identificador del usuario, su
  nombre y sus roles para el resto de la aplicación.
- **Comprobación de rol por ruta**, que responde **403** cuando el token es válido pero el
  rol no alcanza.
- Acceso a PostgreSQL con **consultas parametrizadas**, sin una sola concatenación.
- **Manejo central de errores** con los códigos del contrato y sin filtrar trazas al cliente.
- Servicio `backend` en el compose de desarrollo **y en el de producción**, con su
  `Dockerfile`.
- **`GET /api/v1/sesion`**: la única ruta protegida de esta tarjeta; devuelve quién llama y
  con qué roles.
- Pruebas de las seis situaciones de acceso, con tokens **reales** del realm.
- En cuanto `/api/v1/salud` responda en la dirección pública: **alta del monitor de
  disponibilidad** del RNF-05.

**No incluye (llega en tarjetas posteriores):**

- Las rutas de negocio —carta, pedidos, estados—: tarjetas 05 y 06.
- El canal en tiempo real: tarjeta 07.
- La aplicación Flutter: tarjeta 04.
- La infraestructura del despliegue (servidor, dominio, proxy, identidad): tarjeta 02, ya
  cerrada. Esta tarjeta solo agrega su servicio al compose de producción.

---

## 3. Decisiones de diseño

1. **El token se valida en local contra las claves publicadas, no preguntándole a Keycloak
   en cada petición.** El servidor descarga el juego de claves públicas del realm (JWKS),
   lo mantiene en memoria y verifica la firma él mismo. Preguntar a Keycloak por cada
   petición añadiría un salto de red a cada llamada —contra el RNF-01, que fija dos
   segundos— y dejaría la aplicación entera a merced de un parpadeo del proveedor de
   identidad.

2. **Se comprueban cuatro cosas, no una:** que la **firma** sea de este realm, que el
   **emisor** sea el esperado, que el token **no haya expirado** y que la **audiencia**
   incluya a esta API. La audiencia es la que se suele olvidar, y es la que impide que un
   token emitido para otra aplicación del mismo Keycloak —con firma perfectamente válida—
   sirva para entrar aquí.

3. **El emisor llega por variable de entorno.** En desarrollo es el Keycloak local; en
   producción, la URL pública. Es el *gotcha* registrado en D-09: si el emisor esperado y el
   del token no coinciden al carácter, el servidor rechaza absolutamente todos los tokens y
   el síntoma —"el login funciona pero nada más"— no apunta a la causa.

4. **El rol se comprueba en el servidor, en cada petición.** No al entrar a la pantalla, no
   en el cliente. Cada ruta declara qué rol exige, y el mismo mecanismo sirve para las
   tarjetas siguientes.

5. **La ruta de salud consulta la base de verdad.** Un endpoint que devuelve "OK" sin tocar
   nada miente en cuanto la base se cae, y es justo cuando hace falta que no mienta: de él
   depende la métrica de disponibilidad del RNF-05. A cambio, **no revela nada de la
   topología** —ni versiones, ni nombres de máquina, ni cadenas de conexión—: es público.

6. **Todas las consultas van parametrizadas.** Ningún dato que venga de fuera se concatena
   dentro de una sentencia SQL. Es el requisito mínimo 8 y es la respuesta a la pregunta de
   inyección que el tribunal hace siempre.

7. **Los errores tienen una sola forma y no cuentan de más.** El cliente recibe un código y
   un mensaje legible; la traza y el detalle técnico quedan en el registro del servidor.
   Filtrar una traza a la respuesta es regalar el mapa de la aplicación.

8. **El proceso se apaga ordenadamente.** Ante la señal de parada cierra el servidor y el
   pool de conexiones antes de morir. Sin eso, cada redespliegue deja conexiones colgando en
   PostgreSQL, y eso se nota cuando se redespliega diez veces en una semana, que es lo que
   va a pasar.

---

## 4. Fases y checklist

### Fase A — El esqueleto
- [x] `package.json` con dependencias y **versiones exactas**, nunca `latest`; anotarlas en
      la tabla de versiones del README.
- [x] Estructura por responsabilidad: configuración, acceso a datos, middleware, rutas.
- [x] Toda la configuración desde el entorno, con **fallo al arrancar** si falta una
      variable obligatoria. Es preferible no arrancar a arrancar mal.
- [x] Apagado ordenado del servidor y del pool.

### Fase B — Estado del servicio
- [x] Pool de conexiones a PostgreSQL.
- [x] `GET /api/v1/salud`: consulta trivial a la base; **200** con el estado, **503** si no
      responde. Sin datos internos en la respuesta.

### Fase C — Identidad
- [x] Middleware que valida firma, emisor, expiración y audiencia contra el JWKS del realm.
- [x] Del token se extraen identificador (`sub`), nombre y roles.
- [x] Comprobador de rol reutilizable por ruta.
- [x] **401** token ausente, expirado o inválido · **403** rol sin permiso.

### Fase D — Errores y entradas
- [x] Manejador central con los códigos de la Tabla 12: 400, 401, 403, 404, 409, 503.
- [x] Forma única de respuesta de error, sin trazas.
- [x] Rutas inexistentes: 404 con la misma forma, no la página de Express.

### Fase E — El contenedor
- [x] `Dockerfile` sobre la imagen de Node fijada, ejecutando como **usuario sin
      privilegios**.
- [x] Servicio `backend` en el compose, esperando a que la base esté sana.
- [x] Comprobación de salud del contenedor apuntando a la ruta de salud.

### Fase F — Pruebas
- [x] Script versionado en `pruebas/api/` que obtiene tokens **reales** del realm y
      comprueba las seis situaciones de la sección 7.

---

## 5. Archivos que se tocan / crean

- `backend/package.json`, `backend/package-lock.json` *(nuevos)*
- `backend/Dockerfile`, `backend/.dockerignore` *(nuevos)*
- `backend/src/` *(nuevo)*: arranque, configuración, pool de datos, middleware de token y
  de rol, ruta de salud, manejador de errores
- `docker/docker-compose.yml` *(se agrega el servicio `backend`)*
- `.env.example` *(emisor, audiencia y URL interna del proveedor de identidad)*
- `README.md` *(versiones fijadas y cómo levantar la API)*
- `pruebas/api/probar_salud_y_token.py` *(nuevo)*

---

## 6. Cómo se prueba

Con el entorno levantado y el realm ya importado (tarjeta 02, fase D):

1. `GET /api/v1/salud` → **200**.
2. Detener el contenedor de la base y repetir → **503**. Volver a levantarla → **200** otra
   vez. *Esta es la prueba que la mayoría se salta, y es la que demuestra que la ruta no
   miente.*
3. Llamar a una ruta protegida **sin token** → 401.
4. Con un token **manipulado** (una letra cambiada en la firma) → 401.
5. Con un token **expirado** → 401.
6. Con un token **de otra audiencia** → 401.
7. Con token válido de **recepción** sobre una ruta que exige **cocina** → 403.
8. Con token válido del rol correcto → pasa, y el servidor sabe quién es.

Los tokens salen del realm real, con `pruebas/identidad/probar_acceso_pkce.py` como punto de
partida.

---

## 7. Criterios de aceptación

- La ruta de salud devuelve **200 con la base arriba y 503 con la base caída**, comprobado
  apagándola de verdad.
- Las seis situaciones de acceso responden **exactamente** el código que fija la Tabla 12.
- El servidor **nunca** acepta un token cuya firma, emisor, vigencia o audiencia no cuadre.
- **Ninguna** consulta se construye concatenando texto.
- **Ningún** secreto ni URL de producción escrita en el código: todo del entorno.
- El servicio levanta desde cero con `docker compose up` y su contenedor llega a *sano*.
- Ninguna respuesta de error filtra trazas ni detalles internos.

---

## 8. Requisitos que cubre

- **Institucionales:** **#2** (autenticación y control de acceso por rol) en su mitad de
  servidor, que es la que cuenta; **#8** (validación en el servidor) en su base; **#3**
  (persistencia) en el acceso a datos; **#7** (secretos fuera del repositorio).
- **Del sistema:** **RNF-02** —validación de token y autorización por rol comprobada en el
  servidor en el 100 % de las rutas salvo la de salud—; **RNF-05**, que necesita esta ruta
  de salud para poder medirse; y **RF-01**, del que esta tarjeta construye la mitad de
  servidor.
- **De la entrega:** es lo que se despliega detrás del proxy en cuanto haya servidor, y sin
  ello el **E2** no tiene nada que mostrar más allá de una página estática.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El esqueleto | ✅ Verificada | 2026-09-23 | Express **5.2.1**, `pg` **8.23.0**, `jsonwebtoken` **9.0.3**, `jwks-rsa` **4.1.0**, fijadas sin `^` y con `package-lock.json`. Estructura: `config`, `errores`, `autenticacion`, `app` (construible sin base ni Keycloak reales, para las pruebas) e `index` (arranque y apagado). Sin `POSTGRES_*` o `KEYCLOAK_ISSUER`, el proceso **no arranca** |
| B — Estado del servicio | ✅ Verificada | 2026-09-23 | `GET /api/v1/salud` → **200** `{"estado":"ok","baseDeDatos":"ok"}` desde Internet. **Base detenida de verdad** (`docker stop maxpizzapp-bd`): **503** `{"estado":"degradado","baseDeDatos":"sin respuesta"}`, con el motivo técnico solo en el registro. Base arrancada de nuevo: **200** sin reiniciar el backend, porque el pool reconecta solo |
| C — Identidad | ✅ Verificada | 2026-09-23 | Validación local contra el JWKS del realm leído por la red interna (clave RS256), con **firma, emisor, vigencia y audiencia**, solo `RS256`. En producción, con tokens reales: las dos cuentas → 200 y el servidor reconoce su rol y su usuario; firma manipulada → 401 `TOKEN_INVALIDO` |
| D — Errores y entradas | ✅ Verificada | 2026-09-23 | Forma única `{"error":{"codigo","mensaje"}}` en 400, 401, 403, 404, 500 y 503. 404 propio en vez de la página de Express; JSON mal formado → 400, no 500; sin `X-Powered-By`. El 409 lo usarán las rutas del negocio, con el mismo manejador |
| E — El contenedor | ✅ Verificada | 2026-09-23 | `node:24-alpine`, `npm ci --omit=dev`, proceso como usuario **`node`**, no root. Comprobación de salud contra `/api/v1/salud`: **healthy a los 15 s** en el servidor. En producción, el 3000 **no se publica**: está cerrado desde fuera y solo se llega por Caddy |
| F — Pruebas | ✅ Verificada | 2026-09-23 | `npm test`: **16/16** con un emisor local que fabrica tokens expirados, de otra audiencia, de otro emisor, con clave ajena y con `alg: none`, más los 403 por rol. **Prueba de mutación:** al quitar la comprobación de emisor y de audiencia fallan exactamente esas dos pruebas. `pruebas/api/probar_salud_y_token.py` contra `https://maxpizzapp.tech` con tokens reales: **12/12** |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-22 | Versión inicial propuesta | Se adelanta mientras la tarjeta 02 está bloqueada esperando el servidor. La API es lo primero que se despliega encima del proxy, y se puede construir y probar entera en local contra el realm que ya funciona |
| 2026-09-23 | **Aprobado**, con dos ajustes | Revisado por el autor tras cerrar la tarjeta 02 |
| 2026-09-23 | Ajuste 1: se agrega **`GET /api/v1/sesion`** (Recepción, Cocina) → `200 { sub, nombre, roles }` · 401 | Las pruebas de 401 y 403 necesitan una ruta protegida real. La app la usa en la tarjeta 04 para saber qué pantalla mostrar según el rol **confirmado por el servidor**, no por lo que la app lee del token. Es una ruta nueva del contrato: entra a la Tabla 12 del 2.4 en el mismo acto |
| 2026-09-23 | Ajuste 2: el servicio `backend` entra también a **`docker-compose.prod.yml`**, y la tarjeta cierra **desplegada** | La plenaria P3 pidió el esqueleto en línea el miércoles 23: frontend, `/api/v1/salud` y base conectada, en su URL pública. La tarjeta 02 ya dejó el proxy esperando a `backend:3000` |
| 2026-09-23 | El 403 se prueba con el middleware montado sobre una ruta que exige el rol contrario, en las pruebas de integración | Todavía no existe ninguna ruta del negocio exclusiva de un rol (llegan con la tarjeta 06). No se inventa una ruta pública solo para probar |

---

## 11. Cierre

- **Commits que cierran la tarjeta:** **10A** (aprobación del plan con sus dos ajustes),
  **10** (la API y sus 16 pruebas), **11** (el backend en los dos compose), **12** (la prueba
  con tokens reales) y **12b** (esta evidencia). Los pasos están en el manual de Git del
  proyecto; los ejecuta el autor.
- **Criterios de aceptación (sección 7):** los siete cumplidos. 200/503 comprobado apagando la
  base de verdad; las situaciones de acceso responden el código de la Tabla 12; ningún token
  pasa con la firma, el emisor, la vigencia o la audiencia equivocados; ninguna concatenación
  en SQL (la única consulta es `SELECT 1`, y el patrón queda fijado para las siguientes);
  ningún secreto ni URL de producción en el código; el contenedor llega a *healthy*; ningún
  error filtra trazas.
- **Monitor de disponibilidad del RNF-05:** UptimeRobot, plan gratuito (uso no comercial),
  monitor HTTP(s) *"Max Pizzapp — salud de la API"* sobre
  `https://maxpizzapp.tech/api/v1/salud`, **cada 5 minutos**, con aviso por correo. Lo dio de
  alta el autor. **Inicio del periodo medido: 2026-09-23, ~01:15 hora de Bolivia (05:15
  UTC).** Los 7 días que exige el RNF-05 se cumplen el **2026-09-30** a la misma hora, antes
  del E3. Primera lectura: *Up*, 100 % en 24 h, 0 incidentes. El monitor mide las 24 horas,
  más exigente que la franja de atención de 18:00 a 23:30. El 2.8 declara **las fechas
  realmente medidas**, sin redondear. El historial se conserva 90 días en el plan gratuito.
- **Fecha de cierre:** 2026-09-23.
