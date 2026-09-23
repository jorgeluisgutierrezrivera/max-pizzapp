-- ============================================================================
-- Max Pizzapp — Migración 02: porciones de pizza y datos de la carta (D-25)
--
-- POR QUÉ EXISTE
--   Max Pizzas vende un único tamaño de pizza, ENTERO o MEDIO, y una pizza entera
--   puede llevar DOS MITADES de sabores distintos. El esquema original (01) no
--   podía guardarlo: cada línea de pedido era un producto con su cantidad. Esta
--   migración agrega lo necesario sin crear entidades nuevas: el modelo sigue
--   teniendo las cinco que promete el perfil del proyecto.
--
-- LAS REGLAS DE VENTA (confirmadas con el autor, D-25)
--   - Cada pizza tiene SU precio de entera y SU precio de media. Las gamas
--     tradicional y premium agrupan la carta; no fijan el precio.
--   - Una media es de un solo sabor.
--   - Una entera es de un sabor, o de dos mitades de sabores distintos y de
--     cualquier gama.
--   - Precio: entera de un sabor = su precio de entera; entera de dos mitades =
--     suma de los precios de media; media = su precio de media.
--   El precio lo CALCULA EL SERVIDOR y lo guarda en la línea: la base solo
--   impide las combinaciones imposibles.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 01_schema.sql (los scripts de
--   esta carpeta corren en orden alfabético al crear el volumen). En una base
--   que ya existe se aplica UNA VEZ a mano:
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/02_porciones_y_carta.sql
--   Está escrita para que ejecutarla dos veces no cambie nada ni falle.
--
-- POR QUÉ UNA MIGRACIÓN Y NO UNA EDICIÓN DE 01
--   01_schema.sql ya está en el historial y ya creó la base de producción. Si se
--   editara, una instalación nueva y la de producción quedarían distintas sin
--   que nada lo avise. Así, el historial muestra qué cambió, cuándo y por qué.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Tipos enumerados
-- ----------------------------------------------------------------------------

-- CREATE TYPE no admite IF NOT EXISTS: se tolera que ya exista.
DO $$ BEGIN
    CREATE TYPE gama_pizza AS ENUM ('tradicional', 'premium');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TYPE porcion_pizza AS ENUM ('entera', 'media');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON TYPE gama_pizza IS
    'Gama de una pizza en la carta. Agrupa la carta; el precio es de cada pizza.';
COMMENT ON TYPE porcion_pizza IS
    'Cómo se vende una pizza: entera o media. Hay un único tamaño.';


-- ----------------------------------------------------------------------------
-- 2. producto: gama, precio de media e imagen
-- ----------------------------------------------------------------------------

ALTER TABLE producto
    ADD COLUMN IF NOT EXISTS gama         gama_pizza,
    ADD COLUMN IF NOT EXISTS precio_media numeric(10,2),
    ADD COLUMN IF NOT EXISTS imagen       varchar(80);

-- Las restricciones se quitan y se vuelven a poner: así la migración se puede
-- ejecutar dos veces sin error.
ALTER TABLE producto
    DROP CONSTRAINT IF EXISTS producto_pizza_con_gama_y_media,
    DROP CONSTRAINT IF EXISTS producto_precio_media_valido,
    DROP CONSTRAINT IF EXISTS producto_imagen_nombre_simple;

ALTER TABLE producto
    -- Toda pizza tiene gama y precio de media; nada que no sea pizza los tiene.
    ADD CONSTRAINT producto_pizza_con_gama_y_media
        CHECK ((categoria = 'pizza') = (gama IS NOT NULL AND precio_media IS NOT NULL)),
    ADD CONSTRAINT producto_precio_media_valido
        CHECK (precio_media IS NULL OR precio_media >= 0),
    -- Solo el NOMBRE de un archivo, nunca una ruta ni una dirección: así no se
    -- puede apuntar a otro lugar, y cambiar de dominio no toca la base.
    ADD CONSTRAINT producto_imagen_nombre_simple
        CHECK (imagen IS NULL OR imagen ~ '^[a-z0-9-]+\.(png|jpg|webp)$');

COMMENT ON COLUMN producto.precio       IS 'Precio de venta. En una pizza, el precio de la pizza entera.';
COMMENT ON COLUMN producto.gama         IS 'Solo en pizzas: tradicional o premium. Agrupa la carta.';
COMMENT ON COLUMN producto.precio_media IS 'Solo en pizzas: precio de media pizza, y de cada mitad de una entera de dos sabores.';
COMMENT ON COLUMN producto.imagen       IS 'Nombre del archivo de la ilustración, servido junto a la app. Nunca una dirección.';


-- ----------------------------------------------------------------------------
-- 3. detalle_pedido: porción y segunda mitad
-- ----------------------------------------------------------------------------

ALTER TABLE detalle_pedido
    ADD COLUMN IF NOT EXISTS porcion           porcion_pizza,
    ADD COLUMN IF NOT EXISTS producto_mitad_id integer;

ALTER TABLE detalle_pedido
    DROP CONSTRAINT IF EXISTS detalle_pedido_mitad_fk,
    DROP CONSTRAINT IF EXISTS detalle_pedido_mitad_solo_en_entera,
    DROP CONSTRAINT IF EXISTS detalle_pedido_mitades_distintas;

ALTER TABLE detalle_pedido
    -- Igual que producto_id: un producto que ya figura en un pedido no se borra.
    ADD CONSTRAINT detalle_pedido_mitad_fk
        FOREIGN KEY (producto_mitad_id) REFERENCES producto (id) ON DELETE RESTRICT,
    -- Una media es de un solo sabor.
    ADD CONSTRAINT detalle_pedido_mitad_solo_en_entera
        CHECK (producto_mitad_id IS NULL OR porcion = 'entera'),
    -- Dos mitades del mismo sabor no son una pizza mitad y mitad: son una entera.
    ADD CONSTRAINT detalle_pedido_mitades_distintas
        CHECK (producto_mitad_id IS NULL OR producto_mitad_id <> producto_id);

-- Lo que la base NO puede comprobar porque cruza tablas, y valida el servidor:
-- que la porción esté presente justo cuando el producto es una pizza, y que la
-- segunda mitad también sea una pizza.

-- Sin este índice, borrar o intentar borrar un producto obligaría a recorrer
-- todas las líneas buscando si figura como segunda mitad.
CREATE INDEX IF NOT EXISTS detalle_pedido_mitad_idx
    ON detalle_pedido (producto_mitad_id) WHERE producto_mitad_id IS NOT NULL;

COMMENT ON COLUMN detalle_pedido.producto_id       IS 'El producto; en una pizza de dos mitades, la primera mitad.';
COMMENT ON COLUMN detalle_pedido.porcion           IS 'Solo en pizzas: entera o media.';
COMMENT ON COLUMN detalle_pedido.producto_mitad_id IS 'Solo en una pizza entera de dos sabores: la segunda mitad, distinta de la primera.';
COMMENT ON COLUMN detalle_pedido.precio_unitario   IS 'Precio de una unidad de esta línea en el momento del pedido, calculado por el servidor con la regla de D-25.';

COMMIT;
