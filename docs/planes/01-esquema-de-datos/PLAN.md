# Plan 01 — Esquema de datos y PostgreSQL en contenedor

> Plan de trabajo de la tarjeta. Se aprueba **antes** de escribir código; al cerrarla, este
> mismo archivo guarda la evidencia de las pruebas y los commits que la cerraron.

- **Tarjeta:** 01 — Esquema de datos y PostgreSQL en contenedor
- **Incremento:** cimientos (persistencia)
- **Estado:** 🔵 Verificado — pruebas en verde el 2026-09-22; cierra al subir los
  commits 6P, 6 y 7
- **Entrada al tablero:** 2026-09-17
- **Cierre:** —
- **Autor:** Jorge Luis Gutierrez Rivera — UAJMS

---

## 1. Objetivo

Dejar la **persistencia funcionando y verificada**: el esquema relacional completo del
dominio (carta, clientes, pedidos, líneas de pedido y trazabilidad de estados) creándose
solo al levantar el contenedor de PostgreSQL con `docker compose`.

Es la cimentación de todo lo demás: sin este modelo no hay pedidos que tomar, ni cola de
cocina que mostrar, ni estados que propagar en tiempo real. La base de datos es la
**única fuente de verdad** del sistema, y este esquema es su definición.

---

## 2. Alcance

**Incluye:**

- Esquema completo en `docker/postgres/init/01_schema.sql`: tipos enumerados, las cinco
  tablas del dominio con claves foráneas, restricciones `CHECK`, índices y comentarios de
  documentación en la propia base de datos.
- Servicio `postgres` en `docker/docker-compose.yml`, montando el directorio de
  inicialización y persistiendo en el volumen `postgres_datos` ya declarado.
- Verificación sobre base limpia de que todo se crea sin errores y de que el modelo
  soporta el flujo real de un pedido.

**No incluye (llega en tarjetas posteriores):**

- Datos de la carta (los productos reales) y el endpoint que la expone.
- Cualquier código de backend: acceso a datos, validaciones y rutas.
- Keycloak y la autorización por rol.

---

## 3. Decisiones de diseño

1. **Ciclo de vida del pedido como tipo enumerado** `estado_pedido`:
   `pendiente · en_preparacion · listo · entregado · cancelado`. Los nombres técnicos van
   sin acentos ni espacios; la interfaz muestra la etiqueta legible. La base de datos
   garantiza que el valor sea uno de esos; **la máquina de estados (qué transición es
   válida) y el permiso por rol se validan en el servidor**, que es la única capa
   confiable.

2. **Sin tabla de usuarios.** La identidad y las credenciales las gestiona Keycloak. Por
   eso `pedido.creado_por` y `historial_estado.usuario_id` guardan el identificador de
   Keycloak (el `sub`, un UUID) como texto, acompañado de una copia del nombre
   (`creado_por_nombre`, `usuario_nombre`) para poder leer quién hizo qué sin consultar
   Keycloak en cada lectura. Es una decisión de arquitectura: una clave foránea a una
   tabla que no existe sería imposible.

3. **`producto.disponible` como booleano**, no como tipo enumerado. Un producto está o no
   disponible; un enumerado de dos valores solo agrega una conversión de tipos frágil en
   cada escritura. En la versión anterior del sistema, un enumerado equivalente provocó
   fallos de escritura por una conversión implícita de texto que PostgreSQL no hace.

4. **Precio histórico en cada línea.** `detalle_pedido` guarda `precio_unitario` además de
   `subtotal`: el precio de la carta puede cambiar mañana, pero el pedido debe conservar el
   precio con el que se cobró.

5. **Integridad referencial explícita.** Las líneas y el historial se borran **en cascada**
   con su pedido, porque son partes dependientes; en cambio no se puede borrar un producto
   o un cliente que ya tiene pedidos, lo que la API traducirá a un 409.

6. **El esquema entra completo en un solo archivo de inicialización.** PostgreSQL ejecuta
   los scripts de inicialización en orden alfabético y una sola vez, al crear el volumen.
   Como `detalle_pedido` referencia a `producto`, partir el esquema en dos archivos
   obligaría a que el segundo dependa del primero sin ninguna ganancia. Los **datos** de la
   carta sí llegan después, en su propio archivo `02_carta.sql`, junto con el endpoint que
   los expone.

7. **Un solo local.** No hay tabla de sucursales: el alcance es el local piloto. La
   operación multi-sede está fuera de alcance y agregarla después no rompe el modelo.

8. **El puerto de PostgreSQL no se publica al host por defecto.** Los contenedores se
   alcanzan entre sí por la red interna; publicarlo solo hace falta para inspeccionar la
   base con una herramienta externa, y queda documentado cómo hacerlo.

---

## 4. Fases y checklist

### Fase A — Esquema de datos
- [ ] Tipos enumerados `estado_pedido` y `categoria_producto`.
- [ ] Tabla `producto`: nombre, categoría, precio con restricción de positivo, disponible,
      fecha de alta.
- [ ] Tabla `cliente`: nombre obligatorio, celular opcional (en mostrador a veces solo se
      tiene el nombre).
- [ ] Tabla `pedido`: cliente, estado con valor inicial `pendiente`, observación, total con
      restricción de no negativo, autor (identificador de Keycloak y nombre), fecha.
- [ ] Tabla `detalle_pedido`: pedido, producto, cantidad entre 1 y 999, precio unitario y
      subtotal.
- [ ] Tabla `historial_estado`: pedido, estado alcanzado, autor y fecha.
- [ ] Índices: cola de cocina por estado y fecha, líneas por pedido, historial por pedido y
      fecha, búsqueda de cliente, carta disponible por categoría.
- [ ] Comentarios de documentación en tablas y columnas, para que el diagrama
      entidad-relación se pueda regenerar desde la base real en lugar de dibujarlo a mano.

### Fase B — PostgreSQL en el compose
- [ ] Servicio `postgres` heredando los ajustes comunes, con la imagen fijada
      `postgres:17-alpine`, credenciales desde el archivo de entorno, volumen de datos y el
      directorio de inicialización montado en solo lectura.
- [ ] Comprobación de salud del servicio, para que lo que dependa de la base espere a que
      esté realmente lista.

### Fase C — Pruebas sobre base limpia
- [ ] Levantar desde cero, con el volumen recreado, y confirmar que la inicialización
      termina sin errores.
- [ ] Verificar que existen los tipos, las cinco tablas, las claves foráneas, las
      restricciones y los índices.
- [ ] Ejercitar el modelo end-to-end con datos de prueba: crear cliente y producto, abrir
      un pedido con dos líneas, avanzar el estado registrando historial, y comprobar que
      borrar el pedido arrastra líneas e historial pero que **no** se puede borrar un
      producto que ya tiene pedidos.
- [ ] Comprobar el camino de escritura contra las columnas de tipo enumerado, que es donde
      falló la versión anterior del sistema.

---

## 5. Archivos que se tocan / crean

- `docker/postgres/init/01_schema.sql` *(nuevo)*
- `docker/docker-compose.yml` *(se agrega el servicio `postgres`)*
- `.env.example` *(puertos de desarrollo 5433 y 3001, para no chocar con el sistema
  anterior que corre en la misma máquina)*

---

## 6. Cómo se prueba

Desde la raíz del repositorio, con el archivo de entorno ya creado a partir de la
plantilla:

```
docker compose --env-file .env -f docker/docker-compose.yml down -v
docker compose --env-file .env -f docker/docker-compose.yml up -d
docker compose --env-file .env -f docker/docker-compose.yml logs postgres
```

Los scripts de inicialización solo corren al **crear** el volumen: por eso, para volver a
aplicar el esquema en desarrollo, hay que recrear la base con `down -v`. Las consultas de
verificación y el ejercicio del flujo se ejecutan dentro del contenedor.

---

## 7. Criterios de aceptación

- Sobre base limpia, la inicialización crea los tipos, las cinco tablas, sus claves
  foráneas, restricciones e índices **sin un solo error** en el registro del contenedor.
- El modelo soporta el flujo completo de un pedido, incluida la trazabilidad de estados.
- El borrado en cascada y el borrado restringido se comportan como se declaró.
- Los datos sobreviven a detener y volver a levantar los contenedores.
- No hay credenciales escritas en el esquema ni en el compose: todas vienen del archivo de
  entorno, que no se versiona.

---

## 8. Requisitos que cubre

- **Institucionales:** persistencia en base de datos con operaciones CRUD, habilitando el
  CRUD que construyen las tarjetas siguientes; secretos fuera del repositorio.
- **Funcionales:** deja el modelo que habilita el registro de pedidos, la cola de cocina,
  el avance de estados, la cancelación y el historial del día.

---

## 9. Registro de avance

| Fase | Estado | Fecha | Evidencia de la prueba |
|---|---|---|---|
| A — Esquema de datos | ✅ Verificada | 2026-09-22 | Inventario leído del catálogo de la base ya creada: **2** tipos enumerados (`categoria_producto`, `estado_pedido`), **5** tablas (producto 6 columnas, cliente 3, pedido 8, detalle_pedido 6, historial_estado 6), **9** restricciones CHECK, **4** claves foráneas y **11** índices (5 propios + 6 de clave primaria/unicidad) |
| B — PostgreSQL en el compose | ✅ Verificada | 2026-09-22 | `docker compose up -d` crea la red `maxpizzapp_interna`, el volumen `maxpizzapp_postgres_datos` y el contenedor `maxpizzapp-bd` (`postgres:17-alpine`), que pasa a *healthy*. El registro de inicialización no tiene un solo ERROR |
| C — Flujo completo de un pedido | ✅ Verificada | 2026-09-22 | Con datos ficticios (`Ana Prueba / 70000001`): alta de 2 productos, 1 cliente y 1 pedido con observación y 2 líneas; recorrido *pendiente → en_preparacion → listo → entregado* con sus **4** filas de historial; la suma de las líneas (160.00) cuadra con el total de la cabecera |
| D — Lo que la base debe impedir | ✅ Verificada | 2026-09-22 | Rechaza un estado inventado (`en_camino`, tipo enumerado), una línea con cantidad 0 (`detalle_pedido_cantidad_valida`), borrar un producto que figura en un pedido y borrar un cliente con pedidos (ambos `ON DELETE RESTRICT`) |
| E — Borrado en cascada | ✅ Verificada | 2026-09-22 | Al borrar el pedido, sus 2 líneas y sus 4 filas de historial se van con él (2/4 → 0/0). La verificación corre dentro de una transacción con `ROLLBACK`: la base queda con 0 filas en las cinco tablas |
| F — Persistencia | ✅ Verificada | 2026-09-22 | Fila insertada, `docker compose down` + `up -d`, y la fila sigue ahí: el volumen sobrevive a la recreación del contenedor. Después se borró |
| G — Secretos fuera del repositorio | ✅ Verificada | 2026-09-22 | Ni el esquema ni el compose contienen credenciales: llegan del `.env`, que `git check-ignore` confirma ignorado |

---

## 10. Revisiones del plan

| Fecha | Cambio | Motivo |
|---|---|---|
| 2026-09-17 | Versión inicial propuesta | — |
| 2026-09-20 | **Aprobado sin cambios** | Revisado por el autor; las ocho decisiones de diseño se aceptan tal como están propuestas |
| 2026-09-20 | Al escribir el esquema se resolvieron cinco diferencias entre este plan y el diccionario de datos del apartado 2.4 | Ver la sección 12; el esquema es la fuente de verdad y el diccionario debe alinearse con él |
| 2026-09-22 | El contenedor pasa a llamarse **`maxpizzapp-bd`** (era `maxpizzapp-postgres`) y los puertos de desarrollo a 5433 y 3001 | En la máquina de desarrollo sigue corriendo el sistema anterior, que ya ocupa los nombres `maxpizzapp-postgres`, `maxpizzapp-keycloak` y `maxpizzapp-api` y los puertos 5432, 8081 y 3000. Los nombres de contenedor son únicos en todo el demonio de Docker: repetirlos impide arrancar. Ver **D-22** |

---

## 11. Cierre

- **Commits que cierran la tarjeta:** **6P** (este plan), **6** (`01_schema.sql`) y **7**
  (servicio `postgres` en el compose y puertos de desarrollo en `.env.example`). Los pasos
  están escritos en el manual de Git del proyecto; los ejecuta el autor.
- **Pruebas:** en verde el **2026-09-22** (sección 9). El guión de verificación completo
  —inventario del esquema, flujo del pedido, restricciones, cascada y limpieza— está
  descrito en la sección 6 y se ejecuta con `psql` dentro del contenedor.
- **Fecha de cierre:** 2026-09-22, a la espera de los commits.

---

## 12. Diferencias resueltas contra el diccionario de datos del 2.4

Al escribir el esquema aparecieron cinco puntos donde **este plan y el diccionario de datos
del apartado 2.4** (Tablas 11 a 11.e del perfil ya entregado) no decían exactamente lo
mismo. Se resolvieron así, y **el diccionario debe alinearse con esta columna** antes del
documento final. Ninguna contradice lo entregado: son precisiones o añadidos.

| # | Punto | Plan | Diccionario 2.4 | Resuelto en el esquema | Por qué |
|---|---|---|---|---|---|
| 1 | `producto.precio` | "restricción de positivo" | `CHECK (precio >= 0)` | **`>= 0`** | Manda el documento entregado. Un precio cero no rompe nada y evita una discrepancia que habría que explicar |
| 2 | `detalle_pedido.cantidad` | "entre 1 y 999" | `CHECK (cantidad > 0)` | **`> 0 AND <= 999`** | El tope evita que un error de tecleo registre 9999 pizzas. Cumple lo que dice el diccionario y añade un límite superior |
| 3 | `producto.creado_en` | "fecha de alta" | no figura | **Se crea** | Estaba en el plan aprobado y permite auditar cuándo entró cada producto a la carta |
| 4 | Nombres obligatorios | — | "Obligatorio: Sí" | `NOT NULL` **+ `CHECK (btrim(...) <> '')`** | `NOT NULL` no impide la cadena vacía. Sin esto se puede registrar un pedido a nombre de "" |
| 5 | `pedido.total` | — | obligatorio, sin valor por defecto | `NOT NULL` **`DEFAULT 0`** | La cabecera se inserta antes que sus líneas; sin valor por defecto habría que conocer el total antes de tenerlo |

**Qué hay que tocar en `documento/2.4-diseno-borrador.md`** cuando se actualice para el
documento final: añadir la fila `creado_en` a la Tabla 11.c, corregir la restricción de
`cantidad` en la Tabla 11.b, anotar el valor por defecto de `total` en la Tabla 11, y
mencionar los `CHECK` de no vacío donde corresponda. **La Figura 4 no cambia**: no se añaden
ni se quitan entidades ni relaciones.
