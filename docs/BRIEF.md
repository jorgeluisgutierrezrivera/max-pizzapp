# Max Pizzapp — Brief de desarrollo

> Documento de contexto para construir el sistema. Es la especificación que guía al
> agente de código y al estudiante. Es **autocontenido**: solo referencia material que
> vive dentro de este repositorio (`codigo/`).
>
> **Negocio:** pizzería **Max's Pizzas** (Tarija). **Producto de software:** **Max Pizzapp**.
> En el documento y la defensa se distingue el negocio (Max's Pizzas) del software (Max Pizzapp).
>
> **Estudiante:** Jorge Luis Gutierrez Rivera — UAJMS, Diplomado en Desarrollo Web y
> Aplicaciones Móviles · **Módulo 4 — Integración y Despliegue de Soluciones**.

---

## 1. Qué es

**Max Pizzapp** es un sistema **web** de gestión de pedidos con **sincronización en
tiempo real** entre **recepción** y **cocina** de la pizzería **Max's Pizzas**. Digitaliza
el tramo del proceso que hoy se coordina de forma manual (se anota en papel y se pasa de palabra):

```
Recepción crea el pedido → Cocina lo ve en vivo → Cocina lo prepara y marca "listo" → Recepción entrega
```

**Alcance = un local piloto:** central de la zona **Villa Fátima (Tarija)**. Las otras
dos sedes (Villa Avaroa, Tabladita) quedan como **trabajo futuro**.

**La "profundidad" del proyecto = el tiempo real.** Es lo que se demuestra en la defensa
y lo que justifica el valor del sistema frente al proceso manual.

---

## 2. Problema que resuelve

En Max's Pizzas los pedidos se registran y coordinan de forma **manual**, sin un medio que
refleje el **estado de cada pedido en tiempo real**. Esto genera errores en la toma,
**pérdida del orden de atención** y demoras en la preparación.

---

## 3. Roles y permisos

Regla del módulo: **máximo 2 roles diferenciados**. Decisión:

| Rol | MoSCoW | Funciones | Dispositivo |
|---|---|---|---|
| **Recepción** | **Must** | Crea pedidos desde la carta, ve el estado en vivo, cancela mientras está pendiente, marca entregado, marca un producto agotado | Tablet / PC |
| **Cocina** | **Must** | Ve los pedidos entrantes en vivo (orden de llegada), avanza estado, marca "listo", marca un producto agotado | Tablet / monitor |

El sistema tiene **exactamente dos roles**: Recepción y Cocina. El rol de administrador
—gestión de la carta e historial del día— queda **declarado fuera de alcance** y pasa a
trabajo futuro: sería un tercer rol diferenciado, por encima del máximo que admite el
módulo. Lo único que de verdad hacía falta de ese rol, que un producto agotado deje de
ofrecerse, lo resuelven los dos roles existentes (RF-13).

**Autorización siempre en el servidor**, no solo en la interfaz. La identidad y las
credenciales las gestiona **Keycloak** (nunca hay tabla propia de usuarios).

---

## 4. Ciclo de vida del pedido

```
pendiente → en preparación → listo → entregado
                          \→ cancelado (solo mientras está pendiente, D-41)
```

- Cada transición la ejecuta **solo el rol habilitado** (cocina avanza a
  preparación/listo; recepción marca entregado; recepción cancela).
- Cada transición se registra con **usuario + fecha/hora** (trazabilidad).
- **No se entrega un pedido que no esté "listo"** (regla de negocio; se valida en el servidor).
- Al cambiar el estado, las demás pantallas se actualizan **en vivo por WebSockets**
  (ver §6), sin recargar.

---

## 5. Reglas de negocio clave

- **El pedido se identifica por el cliente** (nombre), no por mesa. No hay meseros ni
  numeración de mesas.
- **La entrega la hace la recepción** en mostrador (no hay rol de despacho separado).
- **Orden de la cola de cocina:** cronológico por llegada.
- **Fuera de alcance (Won't have, trabajo futuro):**
  - Módulo de **despacho** como rol independiente.
  - **Control de caja y ventas** (cobros, arqueo, reportes de venta).
  - **Promociones y combos con condiciones** (descuentos por día u horario, 2×1,
    porcentajes). Un combo de precio fijo puede cargarse después como un producto más.
  - **Operación multi-sede** (sucursales Villa Avaroa y Tabladita).
  - Logística propia de delivery; integración con WhatsApp/redes; pago por QR dinámico.

---

## 6. Stack tecnológico

| Capa | Tecnología | Rol |
|---|---|---|
| Frontend web | **Flutter (Dart)** | Interfaz; consume la API por HTTP REST y escucha eventos en tiempo real |
| Tiempo real | **Socket.IO (WebSockets)** | Propaga cambios de estado a recepción/cocina en vivo (< 2 s) |
| Identidad y roles | **Keycloak** | Autenticación OIDC/OAuth 2.0; roles recepción y cocina |
| Backend / API | **Node.js + Express** | API REST, valida tokens de Keycloak (`jwks-rsa`), lógica de negocio, CRUD, servidor Socket.IO |
| Base de datos | **PostgreSQL** (`pg`) | Persistencia relacional; **única fuente de verdad** |
| Contenedores | **Docker / Docker Compose** | Mismas imágenes y versiones en dev y en prod, para reducir las diferencias entre entornos |
| Reverse proxy (prod) | **Caddy** | HTTPS (Let's Encrypt), sirve el Flutter web y expone la API en el mismo origen |
| Control de versiones | **Git** | Historial progresivo (lo maneja el estudiante a mano) |

**Decisión de arquitectura del tiempo real:** se eligió **WebSockets (Socket.IO) sobre
el backend Express** en lugar de Firebase. Motivo: mantiene **Postgres como única fuente
de verdad** y **Keycloak como única auth**; el frontend nunca toca la BD directamente.

> **Versiones:** usar LTS/estables y **dejarlas registradas** (para la tabla de stack de
> la monografía). Node siempre **LTS** (par). Tomar las versiones exactas del entorno real
> el primer día y fijarlas en `package.json`, `pubspec.yaml` e imágenes de Docker.

**Flujo:** Flutter → HTTPS → Express (valida token Keycloak, aplica reglas por rol) →
PostgreSQL. Los cambios de estado se emiten por Socket.IO a las pantallas conectadas.
El **esquema de la BD es la fuente de verdad**: vive en `docker/postgres/init/*.sql`.

---

## 7. Modelo de datos (entidades del alcance)

| Entidad | Campos principales |
|---|---|
| **Producto** | id (PK), nombre, categoria, precio, disponible, solo_entera (las pizzas que ya combinan sabores y no se venden por mitades) |
| **Cliente** | id (PK), nombre, celular *(extensible a nit/razon_social en el futuro)* |
| **Pedido** | id (PK), numero_del_dia, cliente_id (FK; vacío solo en la venta directa de bebidas), para_llevar, creado_por (sub KC), estado, observacion, total, creado_en, dia |
| **DetallePedido** | id (PK), pedido_id (FK), producto_id (FK), producto_mitad_id, linea_de_id, cantidad, precio_unitario, subtotal, agregado_en/por (si llegó después de enviar el pedido) |
| **HistorialEstado** | id (PK), pedido_id (FK), estado, usuario (sub KC), fecha_hora |

Relaciones: Producto 1—N DetallePedido · Cliente 1—N Pedido · Pedido 1—N
DetallePedido/HistorialEstado. La identidad de usuario **no es una tabla** (Keycloak).

> Sin tablas de Caja/Venta/Inventario/Sucursal: son Won't have (fuera de alcance). El diagrama ER se
> regenera desde PostgreSQL cuando el esquema real esté construido.

---

## 8. Seguridad y validación (aplicar en cada incremento)

Cubierto por el stack:
- **Autenticación / sesiones:** Keycloak (OIDC).
- **Autorización por rol:** Keycloak + verificación **en el servidor** en cada petición.
- **Cifrado de comunicaciones:** HTTPS en producción (Caddy + Let's Encrypt).
- **Gestión de secretos:** variables de entorno (`.env`), **fuera del repo** (`.gitignore`);
  `.env.example` con los nombres, sin valores reales.

A implementar:
1. **Validación en cliente Y servidor** (la del servidor es la única confiable).
2. **Consultas parametrizadas** siempre (nunca concatenar SQL con texto del usuario).
3. **Escapado/saneo** de lo que se muestra en pantalla (XSS).
4. **Rate limiting** de login (Keycloak).
5. **Autorización por petición:** cada endpoint (salvo login) valida token, rol y estado.
6. **Cabeceras de seguridad** (Helmet en Express).

> **RNF con métrica a cumplir:** propagación de cambios en tiempo real **< 2 s**; token
> JWT con vigencia **~60 min**; interfaz **responsive**; degradación controlada si cae el
> canal de tiempo real.

---

## 9. Requisitos funcionales (resumen)

Resumen operativo (los Must son exactamente el flujo que se demuestra en la defensa):

| ID | MoSCoW | Requisito |
|---|---|---|
| RF-01 | Must | Iniciar sesión |
| RF-02 | Must | Registrar pedido (recepción) |
| RF-03 | Must | Ver estado en tiempo real (recepción) |
| RF-04 | Must | Aviso de pedido listo |
| RF-05 | Must | Marcar entregado |
| RF-06 | Must | Ver pedidos entrantes en vivo (cocina) |
| RF-07 | Must | Actualizar estado del pedido (cocina) |
| RF-08 | Should | Cerrar sesión y cambiar de usuario en el mismo dispositivo |
| RF-09 | Should | Cancelar pedido |
| RF-10 | Could | Ver el tiempo de espera de cada pedido en la cola de cocina |
| RF-11 | Should | Agregar observación al pedido |
| RF-12 | Could | Ver comprobante del pedido |
| RF-13 | Should | Marcar un producto como agotado (recepción o cocina) |
| RF-14 | Should | Agregar productos a un pedido ya enviado (recepción) |

Must have = 7/14 (50 %, ≤ 60 %); el reparto completo es 7 Must · 5 Should · 2 Could. Los
Must son exactamente el flujo que se demuestra en la defensa.

> **RF-11 pasó de *Could* a *Should* el 22-sep**, tras la tutoría T2: la observación del
> pedido ya estaba en el modelo (`pedido.observacion`), en el caso de uso de registro y en
> el cuerpo de `POST /api/v1/pedidos`, así que *Could* contradecía al resto del diseño.
>
> **RF-14 se sumó el 24-sep** (D-37), al revisar la venta con el autor: en el mostrador, el
> cliente pide la pizza y después la soda. Se puede agregar mientras el pedido no se entregó;
> pizzas, solo mientras cocina no lo terminó.

**Fuera de alcance (rol administrador).** Gestionar la carta y consultar el historial del
día exigirían un tercer rol diferenciado, por encima del máximo admitido; se declaran como
capacidades fuera de alcance y quedan como trabajo futuro. La necesidad concreta que
justificaba la gestión de la carta —que un producto agotado deje de ofrecerse— se resuelve
con **RF-13**, que ejecutan los dos roles existentes desde su propia pantalla.

---

## 10. API REST (endpoints iniciales)

**La autenticación no es un endpoint de esta API.** Se resuelve por redirección a Keycloak
con OpenID Connect, flujo *Authorization Code* + PKCE: el usuario escribe sus credenciales en
Keycloak, la app canja el código por el token y la API solo valida la firma. **El backend
nunca recibe contraseñas.**

El contrato se publica **versionado**: la versión va en la ruta para que un cambio
incompatible pueda convivir con la versión anterior mientras el cliente migra.

```
GET    /api/v1/productos                      La carta, con agotados (recepción y cocina)
POST   /api/v1/pedidos                        Crea pedido en estado "pendiente", o la venta directa
                                              de bebidas, que nace "entregada"
GET    /api/v1/pedidos                        Pedidos activos (filtro por estado)
GET    /api/v1/pedidos/:id                    Pedido con sus líneas
POST   /api/v1/pedidos/:id/lineas             Agrega productos a un pedido que no se entregó
PATCH  /api/v1/pedidos/:id/estado             Avanza estado según rol autorizado
POST   /api/v1/pedidos/:id/cancelacion        Cancela con motivo (solo si está pendiente)
PATCH  /api/v1/productos/:id/disponibilidad   Marca un producto agotado o disponible
GET    /api/v1/salud                          Estado del servicio
```
Además, canal en tiempo real por **Socket.IO** sobre el mismo origen: eventos
`pedido:nuevo`, `pedido:estado`, `pedido:actualizado` y `producto:disponibilidad`. Todas las rutas (salvo salud)
exigen token válido de Keycloak: el servidor valida la firma del token y **los permisos que
exige cada ruta**, que no son los mismos en todas. Cuando la operación **cambia el estado de
un pedido**, comprueba además que la transición solicitada sea válida.

---

## 11. Requisitos mínimos institucionales (obligatorios para la defensa)

1. Desplegado con **URL pública** funcional.
2. **Autenticación** + control de acceso por rol.
3. **Persistencia** en BD con operaciones CRUD.
4. Interfaz **responsive** (adaptable a distintos tamaños).
5. Repositorio con **historial de commits progresivo** (no un único volcado final).
6. **README** con descripción e instrucciones de ejecución local.
7. Credenciales y variables sensibles en **variables de entorno**, nunca en el repo.
8. **Validación de entradas en cliente y servidor**.

---

## 12. Despliegue

Un **VPS con Docker** corriendo el `docker-compose` (Postgres + Keycloak + backend) +
**Caddy** (HTTPS) sirviendo el Flutter web en el mismo origen (evita CORS; API bajo `/api`,
Keycloak en subdominio `auth.`). **Gotcha clave:** el *issuer* de Keycloak debe ser la **URL
pública** o la API rechaza todos los tokens.

> El plan inicial era una VM gratuita de Oracle Cloud Always Free. Se cambió el **22-sep**
> porque el alta depende de una verificación lenta y de cupo ARM, y el primer despliegue
> público vence el 26-sep. El motivo queda registrado fuera del repositorio, en la bitácora
> de decisiones del proyecto.

---

## 13. Metodología y flujo de trabajo

- **Metodología académica: Kanban** (flujo continuo, WIP = 1). No Scrum, no "sprints".
- **Flujo de trabajo con el agente:** plan → aprobación → código → pruebas → aprobación
  → subida. Una tarjeta a la vez.
- **Git lo maneja el estudiante a mano.** Ningún nombre de rama/commit dice "sprint"; se
  nombra por funcionalidad. Commits progresivos y frecuentes, en fechas distintas.

---

## 14. Incrementos (mapeados a las entregas del módulo)

| Inc | Foco | Entrega |
|---|---|---|
| **Inc 0** | Repo init + perfil de proyecto (Cap 1, 2.2–2.5, matriz, ≥5 commits) | **E1 — 19-sep** |
| **Inc 1** | Cimientos: Docker + Keycloak + login por rol | **E2 — 26-sep** |
| **Inc 2** | CRUD de pedidos + frontend navegable + **primer despliegue público** | **E2 — 26-sep** |
| **Inc 3** | **Tiempo real (Socket.IO)** + producto agotado (RF-13) + cancelación | **E3 — 3-oct** |
| **Inc 4** | Seguridad + pruebas con evidencia + documento completo | **E3 — 3-oct / E4 — 10-oct** |

> El módulo exige el **primer despliegue público en la Semana 2**, para E2, aunque el
> sistema esté incompleto. E3 es el checkpoint técnico: seguridad, pruebas con evidencia y
> borrador de los capítulos 1 y 2.

**Definición de "hecho" por tarjeta:** funcionalidad demostrable + pruebas e2e en verde
+ validación cliente/servidor + sin secretos en el repo + commit del estudiante.
