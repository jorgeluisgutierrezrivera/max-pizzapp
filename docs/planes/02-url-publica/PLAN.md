# Plan 02 — URL pública con HTTPS, proxy e identidad

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 02 — URL pública con HTTPS, proxy e identidad
- **Incremento:** cimientos (infraestructura e identidad)
- **Estado:** 🔵 Verificado — pruebas en verde el 2026-09-23; cierra al subir los
  commits 30, 30b, 30c y 31
- **Entrada al tablero:** 2026-09-22
- **Cierre:** 2026-09-23
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que **exista una dirección pública con HTTPS** sirviendo el sistema, y que **el proveedor de
identidad funcione detrás de ella**. Al terminar esta tarjeta, cualquiera —el docente, el
tribunal— puede abrir la URL desde su casa y ver algo servido por este proyecto, y la
pantalla de acceso de Keycloak responde en su subdominio con certificado válido.

**Por qué esta tarjeta va antes que las pantallas.** El primer despliegue público lo exige
la entrega E2 del sábado 26, y la tutoría T2 lo señaló como el riesgo principal del
proyecto. Lo que falla en un despliegue —puertos, HTTPS, certificados, el *issuer* de
Keycloak, las URI de redirección— no falla nunca en local y falla siempre la primera vez
afuera. Construir cuatro pantallas y descubrir el viernes que Keycloak rechaza todos los
tokens es perder la entrega; tener la dirección pública el martes y empujarle
funcionalidad encima cada día no tiene ese riesgo.

---

## 2. Alcance

**Incluye:**

- Servidor (VPS) con Docker y el repositorio desplegado, con su archivo de entorno de
  producción creado **en el servidor**, nunca versionado.
- Dos nombres de dominio resolviendo a ese servidor: el de la aplicación y el de identidad.
- **Caddy** como proxy inverso, con certificado TLS obtenido y renovado automáticamente,
  sirviendo por ahora una página estática de cortesía en la raíz.
- **Keycloak en modo producción** detrás del proxy, con el *realm* del proyecto, su cliente
  y los **dos roles** —recepción y cocina— y un usuario de prueba por rol.
- El *realm* **versionado como archivo** en el repositorio, construido y probado primero en
  local, para que en el servidor sea una importación y no una configuración a mano.
- `docker-compose.prod.yml` y `Caddyfile` versionados: el despliegue se reproduce con un
  comando, no con una sesión de terminal irrepetible.

**No incluye (llega en tarjetas posteriores):**

- La API (`GET /api/v1/salud` y el resto) y el middleware que valida el token: **tarjeta 03**.
- La aplicación Flutter y el acceso por rol de punta a punta: **tarjeta 04**.
- El alta del monitor de disponibilidad de RNF-05: necesita el endpoint de salud, así que
  entra con la tarjeta 03. **No se puede olvidar**: la métrica pide un periodo de al menos
  siete días y el reloj arranca el día que exista el endpoint.

---

## 3. Decisiones de diseño

1. **Un solo origen para la aplicación y la API; identidad en un subdominio aparte.**
   `https://<dominio>/` sirve la aplicación y `https://<dominio>/api/*` la API —mismo
   origen, así **no hay CORS** ni en las llamadas ni en el canal en tiempo real—, mientras
   que Keycloak vive en `https://auth.<dominio>/`. Es la arquitectura que ya describe el
   apartado 2.4 del documento.

2. **El *issuer* de Keycloak es la URL pública, no la interna.** Es el error clásico del
   despliegue y ya estaba registrado como riesgo en D-09: si el *realm* emite tokens con
   `http://keycloak:8080` como emisor, la API los rechaza todos y el login "funciona" pero
   nada más. Keycloak arranca con su *hostname* fijado en el dominio público y confiando en
   las cabeceras del proxy.

3. **El *realm* se construye en local y se exporta a un archivo versionado.** Es la decisión
   que más riesgo quita: la parte difícil de Keycloak —clientes, roles, URI de redirección,
   orígenes permitidos— se resuelve en la máquina de desarrollo, donde equivocarse es
   gratis, y en el servidor solo se importa. Además queda como evidencia reproducible: el
   tribunal puede ver la configuración de identidad en el repositorio.

4. **El archivo del *realm* declara las URI de desarrollo y las de producción.** Desarrollo
   (`http://localhost:...`) y producción (`https://<dominio>/...`) conviven en la misma
   lista de URI de redirección y orígenes web. Alternativa descartada: mantener dos
   archivos, que se desincronizan en cuanto uno cambia.

5. **El cliente de la aplicación es público, con PKCE; el de la API es confidencial.** La
   aplicación web no puede guardar un secreto —vive en el navegador—, así que usa el flujo
   *Authorization Code* con PKCE, como fija D-17. La API no inicia sesiones: solo valida
   firmas.

6. **Ningún puerto se publica al host en producción.** Postgres y Keycloak solo son
   alcanzables por la red interna de Docker; lo único expuesto a Internet son el 80 y el
   443 de Caddy. En desarrollo sí se publican, con los puertos separados de D-22.

7. **La contraseña del administrador de Keycloak y las de la base se generan en el
   servidor.** El `.env` de producción no es una copia del de desarrollo: valores nuevos,
   creados ahí y no versionados.

8. **Una página estática de cortesía mientras no haya aplicación.** Sirve para tres cosas:
   comprobar que el certificado es válido, dar algo que enseñar el día de la entrega si
   algo se retrasa, y que el monitor de disponibilidad tenga a qué apuntar. Se reemplaza
   por la aplicación en la tarjeta 04.

---

## 4. Fases y checklist

### Fase A — El servidor
- [x] VPS disponible con acceso administrativo: Hostinger KVM 1, contratado (D-24).
- [x] Comprobar que los puertos **80 y 443 están libres**: si ya corre otro servidor web,
      Caddy no puede tomarlos.
- [x] Docker y el complemento de Compose instalados.
- [x] Cortafuegos del proveedor abierto solo en 22, 80 y 443. Se usa el del panel y **no**
      `ufw`: los puertos que publica Docker se saltan las reglas de `ufw`.
- [x] Repositorio clonado y `.env` de producción creado **en el servidor**.

### Fase B — Los nombres de dominio
- [x] `<dominio>` y `auth.<dominio>` resolviendo a la dirección del servidor.
- [x] Verificado desde fuera antes de pedir certificados: un dominio que no resuelve hace
      fallar la validación y consume intentos.

### Fase C — Proxy y HTTPS
- [x] `docker/caddy/Caddyfile`: la raíz sirve los archivos estáticos, `/api/*` va a la API
      (aún no existe: queda declarado), `auth.<dominio>` va a Keycloak.
- [x] Cabeceras del proxy hacia Keycloak para que sepa que está detrás de HTTPS.
- [x] Certificado emitido y candado válido en el navegador.

### Fase D — Identidad *(local: hecha el 22-sep)*
- [x] En local: *realm* del proyecto, cliente de la aplicación (público, PKCE), cliente de
      la API, **roles recepción y cocina**, y un usuario de prueba por rol con datos
      ficticios.
- [x] *Realm* versionado en `docker/keycloak/realm-maxpizzapp.json`. Se escribió a mano en
      lugar de exportarlo de la consola: un *export* en bruto arrastra cientos de líneas de
      configuración por defecto que nadie puede revisar ni defender.
- [x] En el servidor: Keycloak en modo producción con el *hostname* público, importando ese
      archivo al arrancar.
- [x] Comprobar el emisor y las claves públicas en el documento de descubrimiento del
      *realm*, que es lo que la API usará para validar tokens.
- [x] Prueba de acceso de punta a punta con PKCE, versionada en
      `pruebas/identidad/probar_acceso_pkce.py`.
- [x] Reemplazar `REEMPLAZAR-POR-EL-DOMINIO` en el *realm* por el dominio real, **antes** de
      importarlo en el servidor.

### Fase E — Reproducibilidad
- [x] `docker/docker-compose.prod.yml` versionado, con Caddy, Keycloak y Postgres.
- [x] Procedimiento de despliegue escrito en el README del repositorio.

---

## 5. Archivos que se tocan / crean

- `docker/caddy/Caddyfile` *(nuevo)*
- `docker/caddy/sitio/index.html` *(nuevo — la página de cortesía)*
- `docker/keycloak/realm-maxpizzapp.json` *(nuevo — la configuración de identidad)*
- `docker/keycloak/README.md` *(nuevo — qué define el realm y cómo se establecen las
  contraseñas, que no están en el repositorio)*
- `docker/postgres/init/00_bases.sql` *(nuevo — la base de datos propia de Keycloak)*
- `pruebas/identidad/probar_acceso_pkce.py` *(nuevo — la prueba del flujo de acceso)*
- `docker/docker-compose.prod.yml` *(nuevo)*
- `docker/docker-compose.yml` *(se agrega el servicio de Keycloak para desarrollo)*
- `.env.example` *(variables de dominio y de identidad, sin valores)*
- `README.md` *(procedimiento de despliegue)*

---

## 6. Cómo se prueba

Desde **fuera del servidor** —una prueba que se hace en el propio servidor no demuestra que
el sistema es público—, con el navegador y con la terminal:

1. `https://<dominio>/` abre la página con **candado válido**.
2. `http://<dominio>/` **redirige** a HTTPS.
3. `https://auth.<dominio>/realms/maxpizzapp/.well-known/openid-configuration` devuelve el
   documento de descubrimiento, y su campo `issuer` es **la URL pública**, no una interna.
4. La pantalla de acceso de Keycloak carga y los dos usuarios de prueba entran, cada uno
   con su rol en el token.
5. `docker compose ps` en el servidor muestra los contenedores sanos.
6. Apagar y levantar el servidor completo: todo vuelve solo, sin intervención manual.

---

## 7. Criterios de aceptación

- La dirección pública **responde desde otra red** (no solo desde el servidor) con
  certificado válido.
- El *realm* importado tiene **exactamente dos roles** —recepción y cocina— y un usuario de
  prueba por rol, con datos ficticios.
- El emisor de los tokens es la URL pública.
- **Ningún secreto** en el repositorio: el `.env` de producción vive solo en el servidor y
  el archivo del *realm* no contiene contraseñas reales.
- El despliegue es **reproducible**: con el repositorio y un archivo de entorno, un
  `docker compose -f docker-compose.prod.yml up -d` levanta todo.
- Queda una **captura fechada** de la URL pública funcionando, para el apartado 2.9.

---

## 8. Requisitos que cubre

- **Institucionales:** **#1 URL pública funcional** —el requisito que no se puede sustituir
  por nada— y **#7 secretos en variables de entorno**. Deja encaminado el **#2**
  (autenticación con control de acceso por rol), que cierra en las tarjetas 03 y 04.
- **Del sistema:** habilita **RF-01** (iniciar sesión) y es la precondición de todo lo
  demás. **RNF-02** en su parte de cifrado: todo el tráfico público viaja por HTTPS.
- **De la entrega:** es la mitad de infraestructura del **E2** del sábado 26.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El servidor | ✅ Verificada | 2026-09-23 | Hostinger KVM 1 (1 vCPU, 3,8 GB, 48 GB), **Ubuntu 24.04.5 LTS** tras el `apt upgrade` inicial y un reinicio (llegó como 24.04.4), kernel 6.8.0-142. Acceso root **solo por llave** ed25519, comprobado sin contraseña (`BatchMode`). Antes de instalar nada, solo `sshd` escuchaba: **80 y 443 libres**. **Docker 29.8.1** y **Compose v5.5.1**. Cortafuegos del panel `maxpizzapp-web`: acepta TCP 22/80/443 y UDP 443, descarta el resto; SSH sigue entrando con el cortafuegos activo. Repositorio en `/opt/maxpizzapp`; `.env` de producción creado **en el servidor**, con permisos `600` y contraseñas generadas ahí con `openssl rand` (48 caracteres para la base y el administrador de Keycloak), que nunca se imprimieron |
| B — Los nombres de dominio | ✅ Verificada | 2026-09-23 | `maxpizzapp.tech`, con los nameservers de Hostinger. Consultado a `8.8.8.8` desde fuera del servidor: `@` → `2.25.241.190` (A) y `2a02:4780:75:6d87::1` (AAAA, la IPv6 propia del VPS, comprobada con `ip -6 addr`); `auth` → `2.25.241.190`. Sin registro CAA que bloquee a Let's Encrypt |
| C — Proxy y HTTPS | ✅ Verificada | 2026-09-23 | `caddy validate`: configuración válida. Certificados de **Let's Encrypt** obtenidos para `maxpizzapp.tech` y `auth.maxpizzapp.tech` (emisor YE2, válidos hasta el 22-dic-2026). **Desde fuera del servidor**: `https://maxpizzapp.tech` → 200 con certificado válido; `http://` → **308** a HTTPS; cabeceras HSTS, `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy` y HTTP/3 anunciado, sin cabecera `Server`; `/api/v1/salud` → 502, lo esperado sin la tarjeta 03. En el host solo escuchan **22, 80 y 443**; los puertos 5432, 8080, 9000 y 2019 están **cerrados desde fuera** |
| D — Identidad (local) | ✅ Verificada | 2026-09-22 | Keycloak **26.7.4** levanta contra su propia base en PostgreSQL e **importa el realm** al arrancar. El documento de descubrimiento publica el emisor y **2 claves** (firma RS256 y cifrado); el realm queda con los **2 roles**, los **2 clientes** —`frontend-web` público con PKCE, `backend-api` sin flujos— y las **2 cuentas** de demostración |
| D — Prueba de acceso | ✅ Verificada | 2026-09-22 | `pruebas/identidad/probar_acceso_pkce.py` recorre el flujo real —pantalla de acceso, credenciales, canje del código con el verificador PKCE— para las dos cuentas. Cada token llega **con su rol y solo el suyo**, con `backend-api` en la audiencia y **60 minutos** de vigencia, que es lo que declara el RNF-02 |
| D — Identidad (servidor) | ✅ Verificada | 2026-09-23 | Keycloak en modo producción (`start`) importa el realm al arrancar. El documento de descubrimiento publica el emisor **`https://auth.maxpizzapp.tech/realms/maxpizzapp`**: la URL pública, no una interna (riesgo D-09 descartado). Contraseñas de las cuentas demo asignadas con `kcadm` leyendo el `.env`, sin que pasaran por la terminal. `probar_acceso_pkce.py` con `KEYCLOAK_URL=https://auth.maxpizzapp.tech`, ejecutado en el servidor: **las dos cuentas entran** y cada token trae solo su rol, `backend-api` en la audiencia, 60 minutos de vigencia y el emisor público. La prueba ahora **falla si el emisor no coincide** |
| E — Reproducibilidad | ✅ Verificada | 2026-09-23 | Levantado con `docker compose --env-file .env -f docker/docker-compose.prod.yml up -d`: los tres contenedores sanos en 50 s. **Reinicio completo del servidor**: todo volvió solo en **65 s**, sin intervención. Procedimiento completo en el README: requisitos, DNS, `.env` generado en el servidor, validación, arranque, verificación desde fuera y actualización |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-22 | Versión inicial propuesta | Reordenación de D-21: el despliegue público se adelanta y pasa a ser la tarjeta siguiente al esquema de datos, en lugar de ir al final del incremento |
| 2026-09-22 | **Aprobado sin cambios** | Revisado por el autor. Se empieza por la **fase D en local** —construir y exportar el *realm*—, que es la única que no depende de que el VPS esté disponible |
| 2026-09-22 | Se añade `docker/postgres/init/00_bases.sql` a los archivos de la tarjeta | Keycloak necesita su propia base de datos. Se le da una base aparte dentro del mismo PostgreSQL, en vez de un segundo motor: es una pieza menos que mantener y una menos que consume memoria en el servidor, que es el recurso escaso (lo advirtió la tutoría T2) |
| 2026-09-22 | El realm desactiva la acción requerida *Verify Profile* | Sin ella, la primera vez que entra una cuenta Keycloak le exige completar el perfil con un correo. Son cuentas **operativas del local**, no personales: no hay correo que verificar, y en una tableta de cocina ese formulario es fricción sin contrapartida |
| 2026-09-22 | El realm se escribe a mano en vez de exportarlo de la consola | Un *export* en bruto trae cientos de líneas de configuración por defecto. El archivo escrito a mano se lee, se revisa y se puede defender línea por línea |
| 2026-09-23 | El servidor es un Hostinger KVM 1 con el dominio `maxpizzapp.tech` | Se descartó el VPS prestado. Se eligió un proveedor que activa el servidor en minutos, sin una verificación de identidad que pueda tardar días: es el riesgo que ya había hecho caer a Oracle. Detalle en D-24 |
| 2026-09-23 | `docker-compose.prod.yml` es autónomo, no una sobreescritura | Al combinar dos archivos, Compose suma las listas de `ports`: el 8082 de Keycloak en desarrollo quedaría publicado en producción |

---

## 11. Cierre

- **Commits que cierran la tarjeta:** **30** (Caddy, página de cortesía, compose de
  producción y `.env.example`), **30b** (dominio en el realm), **30c** (prueba de acceso
  contra producción y evidencia) y **31** (procedimiento de despliegue en el README). Los
  pasos están en el manual de Git del proyecto; los ejecuta el autor.
- **Pruebas:** en verde el **2026-09-23** (sección 9), todas hechas desde fuera del
  servidor salvo las que por definición van dentro: los puertos que escuchan y el acceso
  con la contraseña demo, que no sale de la máquina.
- **Criterios de aceptación (sección 7):** los seis cumplidos. Dirección pública desde otra
  red con certificado válido; realm con exactamente dos roles y una cuenta ficticia por
  rol; emisor = URL pública; ningún secreto en el repositorio; despliegue reproducible con
  un `docker compose up -d`; y la captura fechada, pendiente de tomar (ver abajo).
- **Queda abierto:** la **captura fechada** de la URL pública para el apartado 2.9, que
  toma el autor; y el **monitor de disponibilidad** del RNF-05, que espera a
  `GET /api/v1/salud` (tarjeta 03).
- **Fecha de cierre:** 2026-09-23, a la espera de los commits.
