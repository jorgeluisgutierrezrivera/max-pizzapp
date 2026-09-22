-- ============================================================================
-- Max Pizzapp — Esquema de datos (PostgreSQL 17)
--
-- La base de datos es la ÚNICA FUENTE DE VERDAD del sistema, y este archivo es
-- su definición: está versionado junto al código, no se toca a mano en la base.
--
-- CUÁNDO SE EJECUTA
--   Una sola vez, al CREAR el volumen de datos. Volver a levantar los
--   contenedores no lo vuelve a correr. Para reaplicarlo en desarrollo hay que
--   recrear la base:
--     docker compose --env-file .env -f docker/docker-compose.yml down -v
--     docker compose --env-file .env -f docker/docker-compose.yml up -d
--
-- QUÉ GARANTIZA LA BASE Y QUÉ NO
--   La base garantiza que un valor exista, que sea de un tipo válido y que las
--   relaciones sean coherentes. La base NO decide si una transición de estado
--   es legal ni quién puede ejecutarla: eso se valida en el servidor, que es la
--   única capa confiable. Un tipo enumerado impide un valor inventado; no
--   impide una jugada ilegal.
--
-- IDENTIDAD DE USUARIO
--   No hay tabla de usuarios: las credenciales y los roles los gestiona
--   Keycloak. Donde hace falta saber quién hizo algo se guarda su identificador
--   de Keycloak (el «sub», un UUID) y una copia de su nombre en ese momento,
--   para que el historial siga siendo legible aunque esa persona ya no exista
--   en el proveedor de identidad.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Tipos enumerados
-- ----------------------------------------------------------------------------

-- Ciclo de vida del pedido:
--   pendiente → en_preparacion → listo → entregado
--                             ↘ cancelado  (solo antes de «listo»)
-- Los nombres técnicos van sin acentos ni espacios; la interfaz muestra la
-- etiqueta legible.
CREATE TYPE estado_pedido AS ENUM (
    'pendiente',
    'en_preparacion',
    'listo',
    'entregado',
    'cancelado'
);

-- Agrupación con la que se presenta la carta en la pantalla de recepción.
CREATE TYPE categoria_producto AS ENUM (
    'pizza',
    'entrada',
    'bebida',
    'postre'
);

COMMENT ON TYPE estado_pedido IS
    'Estados posibles de un pedido. Las transiciones válidas entre ellos las decide el servidor, no la base.';
COMMENT ON TYPE categoria_producto IS
    'Categorías de la carta para agrupar los productos en pantalla.';


-- ----------------------------------------------------------------------------
-- 2. Tablas del dominio
-- ----------------------------------------------------------------------------

-- --- producto ----------------------------------------------------------------
-- La carta. «disponible» es un booleano y no un enumerado de dos valores: un
-- producto está o no está disponible, y un enumerado solo agregaría una
-- conversión de tipos frágil en cada escritura.
CREATE TABLE producto (
    id         serial             PRIMARY KEY,
    nombre     varchar(120)       NOT NULL,
    categoria  categoria_producto NOT NULL,
    precio     numeric(10,2)      NOT NULL,
    disponible boolean            NOT NULL DEFAULT true,
    creado_en  timestamptz        NOT NULL DEFAULT now(),

    CONSTRAINT producto_nombre_unico     UNIQUE (nombre),
    CONSTRAINT producto_nombre_no_vacio  CHECK (btrim(nombre) <> ''),
    CONSTRAINT producto_precio_valido    CHECK (precio >= 0)
);

-- --- cliente -----------------------------------------------------------------
-- El pedido se identifica por el cliente, no por mesa. En mostrador a veces
-- solo se tiene el nombre, por eso el celular es opcional.
CREATE TABLE cliente (
    id      serial       PRIMARY KEY,
    nombre  varchar(120) NOT NULL,
    celular varchar(20),

    CONSTRAINT cliente_nombre_no_vacio CHECK (btrim(nombre) <> '')
);

-- --- pedido ------------------------------------------------------------------
-- Un pedido nace «pendiente» y su orden en la cola de cocina es cronológico por
-- «creado_en». El total se conserva con el precio del momento: si mañana cambia
-- la carta, este pedido sigue diciendo lo que costó.
CREATE TABLE pedido (
    id                serial        PRIMARY KEY,
    cliente_id        integer,
    creado_por        text          NOT NULL,
    creado_por_nombre varchar(120)  NOT NULL,
    estado            estado_pedido NOT NULL DEFAULT 'pendiente',
    observacion       varchar(240),
    total             numeric(10,2) NOT NULL DEFAULT 0,
    creado_en         timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT pedido_cliente_fk
        FOREIGN KEY (cliente_id) REFERENCES cliente (id) ON DELETE RESTRICT,
    CONSTRAINT pedido_creado_por_no_vacio CHECK (btrim(creado_por) <> ''),
    CONSTRAINT pedido_total_valido        CHECK (total >= 0)
);

-- --- detalle_pedido ----------------------------------------------------------
-- Las líneas del pedido. Se borran EN CASCADA con su pedido, porque son partes
-- dependientes de él. En cambio no se puede borrar un producto que ya aparece
-- en una línea (RESTRICT): la API traduce ese rechazo a un 409.
CREATE TABLE detalle_pedido (
    id              serial        PRIMARY KEY,
    pedido_id       integer       NOT NULL,
    producto_id     integer       NOT NULL,
    cantidad        integer       NOT NULL,
    precio_unitario numeric(10,2) NOT NULL,
    subtotal        numeric(10,2) NOT NULL,

    CONSTRAINT detalle_pedido_pedido_fk
        FOREIGN KEY (pedido_id) REFERENCES pedido (id) ON DELETE CASCADE,
    CONSTRAINT detalle_pedido_producto_fk
        FOREIGN KEY (producto_id) REFERENCES producto (id) ON DELETE RESTRICT,
    CONSTRAINT detalle_pedido_cantidad_valida  CHECK (cantidad > 0 AND cantidad <= 999),
    CONSTRAINT detalle_pedido_precio_valido    CHECK (precio_unitario >= 0),
    CONSTRAINT detalle_pedido_subtotal_valido  CHECK (subtotal >= 0)
);

-- --- historial_estado --------------------------------------------------------
-- La trazabilidad: cada cambio de estado deja quién lo hizo y cuándo. Se borra
-- en cascada con su pedido, igual que las líneas.
CREATE TABLE historial_estado (
    id             serial        PRIMARY KEY,
    pedido_id      integer       NOT NULL,
    estado         estado_pedido NOT NULL,
    usuario_id     text          NOT NULL,
    usuario_nombre varchar(120)  NOT NULL,
    fecha_hora     timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT historial_estado_pedido_fk
        FOREIGN KEY (pedido_id) REFERENCES pedido (id) ON DELETE CASCADE,
    CONSTRAINT historial_estado_usuario_no_vacio CHECK (btrim(usuario_id) <> '')
);


-- ----------------------------------------------------------------------------
-- 3. Índices
--    Uno por cada consulta que el sistema hace de forma repetida.
-- ----------------------------------------------------------------------------

-- La cola de cocina: pedidos de un estado, en orden de llegada. Es la consulta
-- más frecuente del sistema y la que sostiene el tiempo real.
CREATE INDEX pedido_cola_cocina_idx ON pedido (estado, creado_en);

-- Las líneas de un pedido, al abrirlo o al calcular su total.
CREATE INDEX detalle_pedido_pedido_idx ON detalle_pedido (pedido_id);

-- El recorrido de estados de un pedido, en orden cronológico.
CREATE INDEX historial_estado_pedido_idx ON historial_estado (pedido_id, fecha_hora);

-- Búsqueda de cliente por nombre, sin que importen mayúsculas ni minúsculas.
-- El índice es sobre lower(nombre), así que la consulta debe usar lower(...)
-- para aprovecharlo.
CREATE INDEX cliente_nombre_idx ON cliente (lower(nombre));

-- La carta que se muestra: solo productos disponibles, agrupados por categoría.
-- Índice parcial: no indexa los agotados, que no se consultan.
CREATE INDEX producto_carta_idx ON producto (categoria) WHERE disponible;


-- ----------------------------------------------------------------------------
-- 4. Documentación dentro de la propia base
--    Permite regenerar el diagrama entidad-relación y el diccionario de datos
--    desde la base real, en vez de dibujarlos a mano y que se desincronicen.
-- ----------------------------------------------------------------------------

COMMENT ON TABLE producto         IS 'Carta de Max Pizzas: lo que se puede pedir.';
COMMENT ON TABLE cliente          IS 'Persona que hace el pedido; se anuncia por su nombre.';
COMMENT ON TABLE pedido           IS 'Cabecera del pedido: quién lo pidió, en qué estado está y cuánto suma.';
COMMENT ON TABLE detalle_pedido   IS 'Líneas del pedido: qué productos y en qué cantidad.';
COMMENT ON TABLE historial_estado IS 'Trazabilidad: cada cambio de estado con su autor y su momento.';

COMMENT ON COLUMN producto.nombre     IS 'Nombre del producto en la carta. Único.';
COMMENT ON COLUMN producto.categoria  IS 'Agrupación con la que se muestra la carta.';
COMMENT ON COLUMN producto.precio     IS 'Precio vigente. El precio con el que se cobró un pedido se guarda en la línea, no aquí.';
COMMENT ON COLUMN producto.disponible IS 'Falso cuando el producto está agotado y deja de ofrecerse (RF-13).';
COMMENT ON COLUMN producto.creado_en  IS 'Fecha de alta del producto en la carta.';

COMMENT ON COLUMN cliente.nombre  IS 'Nombre con el que se anuncia el pedido.';
COMMENT ON COLUMN cliente.celular IS 'Contacto opcional para avisar que el pedido está listo.';

COMMENT ON COLUMN pedido.cliente_id        IS 'Cliente que realiza el pedido. Opcional: en mostrador puede no registrarse.';
COMMENT ON COLUMN pedido.creado_por        IS 'Identificador (sub) del usuario de recepción que registró el pedido. Viene de Keycloak.';
COMMENT ON COLUMN pedido.creado_por_nombre IS 'Copia del nombre del usuario en el momento del registro.';
COMMENT ON COLUMN pedido.estado            IS 'Estado actual. Nace en pendiente; las transiciones las valida el servidor.';
COMMENT ON COLUMN pedido.observacion       IS 'Indicación para cocina, por ejemplo "sin cebolla".';
COMMENT ON COLUMN pedido.total             IS 'Suma de los subtotales de sus líneas, con el precio del momento.';
COMMENT ON COLUMN pedido.creado_en         IS 'Momento del registro. Ordena la cola de cocina.';

COMMENT ON COLUMN detalle_pedido.cantidad        IS 'Unidades solicitadas, entre 1 y 999.';
COMMENT ON COLUMN detalle_pedido.precio_unitario IS 'Precio del producto en el momento del pedido, no el de hoy.';
COMMENT ON COLUMN detalle_pedido.subtotal        IS 'Cantidad multiplicada por el precio unitario.';

COMMENT ON COLUMN historial_estado.estado         IS 'Estado al que pasó el pedido.';
COMMENT ON COLUMN historial_estado.usuario_id     IS 'Identificador (sub) de quien ejecutó el cambio.';
COMMENT ON COLUMN historial_estado.usuario_nombre IS 'Copia del nombre de quien ejecutó el cambio.';
COMMENT ON COLUMN historial_estado.fecha_hora     IS 'Momento del cambio de estado.';
