# Plan 11 — Identidad visual del acceso

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 11 — Identidad visual del acceso
- **Incremento:** semana del E4 (cierre). Es un extra: ningún requisito la exige
- **Estado:** 📝 **Propuesto** — 2026-10-07, noche
- **Entrada al tablero:** 2026-09-22, como la 11 del índice, para *después del E2*. Se jala el
  7-oct mientras la 13 espera la prueba de instalación del jueves 8 (D-23)
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Que la página de inicio de sesión **se vea como Max Pizzapp y no como Keycloak**.

Es lo primero que ve cada persona que usa el sistema: la recepcionista en la computadora, cocina
en el teléfono y el tribunal en la defensa. Hoy es la página genérica de Keycloak 26.7: fondo
gris, sin el logo del local y con los colores de Keycloak. El autor la describió el 7-oct como
*"muy genérica y no tiene tampoco los colores de la pizzería ni el logo ni nada"*. Después de
iniciar sesión, la app sí tiene la identidad del local (tarjeta 05: el tema claro en rojo
ladrillo, el logo y las fotos reales).

**El tiempo es corto.** El E4 cierra el sábado 10 y el documento es lo que más demora, así que
la tarjeta tiene un límite: **si el viernes 9 al mediodía no está en producción, se descarta** y
queda como trabajo futuro, sin costo. Nada de ella toca lo que ya funciona.

---

## 2. Alcance

**Incluye:**

- **Un tema propio de Keycloak, `maxpizzapp`, solo para la página de acceso.** Hereda del tema
  oficial (`keycloak.v2`) y cambia **solo la apariencia** (D-77):
  - el **logo del local** arriba del formulario, el mismo de la app
    (`frontend/assets/marca/logo-mp.png`);
  - los **colores de la app** (`frontend/lib/tema.dart`): el fondo crema, la tarjeta blanca, el
    botón *Iniciar sesión* en rojo ladrillo, los enlaces y el foco en los mismos tonos, y el
    negro y el amarillo de la marca en la cabecera;
  - el **título** *Max Pizzapp*, que ya viene del nombre del realm, con la tipografía y los
    pesos de la app.
- **El tema activado** en el realm, en los tres lugares donde vive Keycloak:
  - el **desarrollo** y la **instalación local en un paso**, que importan el realm al crearlo y
    aplican el script de configuración en cada arranque (D-64);
  - **producción**, con el mismo script, que el autor corre en el servidor.
- **El APK de cocina sin cambios ni versión nueva.** Inicia sesión con el navegador del
  teléfono, en esta misma página, así que la ve con el tema nuevo.
- **La evidencia:** capturas del acceso en la PC y en el teléfono, y la Figura A.1 del Anexo A.

**No incluye:**

- **Cambiar el flujo de acceso.** Siguen el código de autorización con PKCE, las cuentas, los
  roles, la política de contraseñas y el bloqueo por intentos fallidos (tarjeta 09).
- **Reescribir las páginas de Keycloak** (las plantillas FreeMarker). Se descartó: una versión
  nueva de Keycloak puede cambiarlas y romper la página (D-77).
- **Las otras pantallas de Keycloak:** la consola de administración, la de la cuenta y los
  correos. Nadie del local las usa.
- **Fuentes, imágenes o estilos de otro sitio.** Todo sale del propio Keycloak (D-78).

---

## 3. Decisiones de diseño

### D-77 · Un tema propio que hereda del oficial y solo cambia los estilos

- **Cómo funciona.** Keycloak busca los temas en `/opt/keycloak/themes`. El tema `maxpizzapp`
  declara `parent=keycloak.v2`: toma del oficial las páginas, los textos en español y los
  estilos de PatternFly 5, y les suma **una hoja de estilos propia** y el logo. Si a un archivo
  le falta algo, Keycloak lo busca en el tema padre.
- **Dónde vive:** `docker/keycloak/tema/maxpizzapp/login/`, versionado. Se monta en el
  contenedor de Keycloak **de solo lectura**, en el `docker-compose.yml` y en el de producción.
  No hace falta una imagen propia de Keycloak: el tema no es una opción de compilación.
- **Cómo se activa:** el realm dice `loginTheme: maxpizzapp`. Va en dos lugares:
  - en `realm-maxpizzapp.json`, para que una base nueva lo traiga desde el primer arranque (la
    instalación local y la integración continua);
  - en `endurecer.sh`, que aplica la configuración sobre un realm que ya existe, como el de
    producción. Es el mismo script de siempre (D-64), que no guarda ningún secreto.
- **Por qué solo estilos.** Las plantillas FreeMarker de Keycloak cambian entre versiones; una
  hoja de estilos sobre las clases y variables de PatternFly es mucho más estable. Si algo
  falla, la página sigue funcionando con el aspecto del tema oficial.
- **Volver atrás** es un solo comando en el servidor: `loginTheme` vuelve a `keycloak.v2`.
- **Se descartó:**
  - **reescribir las plantillas:** más control, pero más horas y riesgo en cada actualización;
  - **una herramienta que genera el tema con React (Keycloakify):** suma un paso de compilación
    y dependencias para una sola página.

### D-78 · Nada de otro sitio: la fuente del sistema y el logo dentro del tema

- **La tipografía es la del sistema** (`system-ui`, *Segoe UI* en Windows y *Roboto* en
  Android), no una fuente descargada. En el teléfono de cocina coincide con la de la app, que es
  Roboto, y no suma ninguna petición.
- **El logo va dentro del tema**, como imagen del propio Keycloak.
- **Por qué:** la página de acceso es la de la contraseña. No carga nada de otro dominio, como el
  resto del sistema desde la CSP de la tarjeta 09 (D-55). La política de Keycloak
  (`frame-src 'self'; frame-ancestors 'self'; object-src 'none'`) no cambia.

---

## 4. Fases y checklist

Cada fase se prueba y se sube por separado.

### Fase A — El tema, en local
- [ ] `docker/keycloak/tema/maxpizzapp/login/`: `theme.properties`, la hoja de estilos y el logo.
- [ ] El montaje en el contenedor de Keycloak, en `docker-compose.yml` y en
      `docker-compose.prod.yml`.
- [ ] `loginTheme` en `realm-maxpizzapp.json` y en `endurecer.sh`.
- [ ] Las pruebas, en local:
  - la página de acceso a **1366 × 768** y a **360 × 780** (el teléfono), sin desplazamiento
    horizontal (RNF-04);
  - **el error de contraseña** también con el tema;
  - **el contraste** del texto y del botón: al menos 4,5 a 1 (WCAG AA), como el resto de la
    app;
  - **ninguna petición a otro dominio**, mirado en las herramientas del navegador;
  - la sonda de acceso (`probar_acceso_pkce.py`), en verde: el flujo no cambió;
  - **una instalación desde cero** (`instalar.cmd`) trae el tema sin pasos extra.
- [ ] **Capturas para el autor, antes de subir nada.** Si no le gusta, se ajusta o se descarta.

### Fase B — La subida
- [ ] **Recién después de la prueba de instalación del jueves 8.** La prueba descarga el ZIP de
      GitHub: lo que se suba antes entraría en ella.
- [ ] El commit de la fase A, con *Pruebas* e *Instalacion* en verde.

### Fase C — En producción, el jueves 8 antes de las 18:00
- [ ] El autor trae el código, recrea solo Keycloak (alrededor de 1 minuto sin poder iniciar
      sesión; las pantallas abiertas siguen funcionando) y corre el script de configuración.
- [ ] Desde afuera, la página de acceso pública muestra el tema.
- [ ] La sonda de acceso contra producción, en verde.
- [ ] En el teléfono, el APK 0.4.0 abre el acceso con el tema nuevo, sin reinstalarse.

### Fase D — La evidencia y el cierre
- [ ] Capturas del acceso en la PC y en el APK, con la cuenta de prueba y la contraseña en
      puntos.
- [ ] La Figura A.1 del Anexo A, con el acceso nuevo.
- [ ] Evidencia en la sección 9 y cierre.

---

## 5. Archivos que se tocan / crean

- **Nuevos:** `docker/keycloak/tema/maxpizzapp/login/theme.properties`,
  `…/resources/css/maxpizzapp.css` y `…/resources/img/logo-mp.png`.
- **Modificados:** `docker/docker-compose.yml` y `docker/docker-compose.prod.yml` (el montaje),
  `docker/keycloak/realm-maxpizzapp.json` y `docker/keycloak/endurecer.sh` (`loginTheme`),
  `docker/keycloak/README.md` y el README del repositorio (dónde está el tema y cómo se activa).

**No cambian:** la base de datos, la API, la app, el APK, el contrato ni las pruebas
automáticas.

---

## 6. Cómo se prueba

| Qué | Cómo | Resultado esperado |
|---|---|---|
| El aspecto | La página de acceso en local, a 1366 × 768 y 360 × 780 | El logo, los colores y el título de la app, sin desplazamiento horizontal |
| El error | Una contraseña equivocada | El mensaje de Keycloak, con el mismo tema |
| El contraste | Las herramientas del navegador | 4,5 a 1 o más en el texto y el botón |
| Nada externo | La pestaña de red del navegador | Todas las peticiones, al propio Keycloak |
| El acceso no cambió | `probar_acceso_pkce.py`, en local y en producción | Las dos cuentas entran, con su rol |
| La instalación | `instalar.cmd` desde cero y la integración continua | El tema llega sin pasos extra; *Instalacion* en verde |
| El APK | El teléfono de cocina, sin reinstalar | El acceso con el tema nuevo |

---

## 7. Criterios de aceptación

- La página de acceso muestra **el logo, los colores y el título de Max Pizzapp**, en la PC y en
  el teléfono, sin desplazamiento horizontal a 1366 × 768 y 360 × 780.
- El texto y el botón tienen **contraste de 4,5 a 1 o más**.
- **El acceso funciona igual:** la sonda de acceso en verde, en local y en producción, y el error
  de contraseña con el mismo tema.
- **Nada se carga de otro dominio.**
- **Una instalación nueva trae el tema sola**, y la integración continua sigue en verde.
- **Se puede volver atrás** con un comando.

---

## 8. Requisitos que cubre

- **Del sistema:** RF-01 (el acceso, sin cambios de comportamiento); RNF-03 y RNF-04 (la misma
  identidad y los mismos anchos que el resto de la app).
- **Institucionales:** #4, la interfaz responsive, también en la página de acceso.
- **Del documento:** la Figura A.1 del Anexo A, y una línea en el 2.4.3 o el 2.6.5 sobre la
  identidad visual. La tabla de tarjetas suma la 11.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — El tema, en local | ⏳ | | |
| B — La subida | ⏳ | | |
| C — En producción | ⏳ | | |
| D — La evidencia y el cierre | ⏳ | | |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-10-07 | Versión inicial propuesta | El autor pidió personalizar el acceso, que es genérico, como un extra mientras el agente documental trabaja en la v11. Límite: el viernes 9 al mediodía |

---

## 11. Cierre

*(Se completa al cerrar la tarjeta: commits de cada fase y estado final.)*
