-- ============================================================================
-- Max Pizzapp — Migración 04: solo pizzas enteras, extras y descripción (D-27, D-28)
--
-- POR QUÉ EXISTE
--   La migración 02 modeló la regla de venta tal como se entendía entonces (D-25):
--   pizzas enteras o medias, con gama y precio de media. La dueña de Max's Pizzas
--   la precisó el mismo día (D-27):
--     - solo se venden pizzas ENTERAS: no hay medias;
--     - una entera puede ser de un sabor o de dos mitades de sabores distintos, y
--       entonces cuesta (precio A + precio B) / 2, al centavo;
--     - la carta no se agrupa por gama.
--   Y el autor pidió EXTRAS por pizza (D-28).
--
--   Esta migración ajusta el modelo sin editar la 02, que ya está en el historial:
--     QUITA   la porción de cada línea, y la gama y el precio de media de cada
--             producto. El precio de media tendría que valer siempre la mitad
--             exacta del precio; guardarlo aparte solo permitiría que no coincida.
--     MANTIENE la segunda mitad (producto_mitad_id) y la regla de que sea distinta.
--     AGREGA  la categoría «extra», la descripción de cada producto y la línea de
--             la que cuelga un extra (detalle_pedido.linea_de_id).
--   El modelo sigue teniendo las cinco entidades que promete el perfil.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 02 (y de 03 mientras exista). En
--   una base que ya existe se aplica UNA VEZ a mano, después de la 02:
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/04_solo_enteras_y_extras.sql
--   Está escrita para que ejecutarla dos veces no cambie nada ni falle.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. La categoría «extra»
--
-- Va FUERA de la transacción: PostgreSQL no deja usar un valor nuevo de un tipo
-- enumerado en la misma transacción que lo crea. Nada de este archivo lo usa, pero
-- la carta, que corre después, sí.
-- ----------------------------------------------------------------------------

ALTER TYPE categoria_producto ADD VALUE IF NOT EXISTS 'extra';


BEGIN;

-- ----------------------------------------------------------------------------
-- 2. producto: sin gama ni precio de media; con descripción
-- ----------------------------------------------------------------------------

ALTER TABLE producto
    DROP CONSTRAINT IF EXISTS producto_pizza_con_gama_y_media,
    DROP CONSTRAINT IF EXISTS producto_precio_media_valido,
    DROP COLUMN IF EXISTS gama,
    DROP COLUMN IF EXISTS precio_media,
    ADD COLUMN IF NOT EXISTS descripcion varchar(200);

DROP TYPE IF EXISTS gama_pizza;

ALTER TABLE producto DROP CONSTRAINT IF EXISTS producto_descripcion_no_vacia;
ALTER TABLE producto
    -- Sin descripción es válido (una bebida no la necesita); vacía, no.
    ADD CONSTRAINT producto_descripcion_no_vacia
        CHECK (descripcion IS NULL OR btrim(descripcion) <> '');


-- ----------------------------------------------------------------------------
-- 3. detalle_pedido: sin porción; con la línea de la que cuelga un extra
-- ----------------------------------------------------------------------------

ALTER TABLE detalle_pedido
    DROP CONSTRAINT IF EXISTS detalle_pedido_mitad_solo_en_entera,
    DROP COLUMN IF EXISTS porcion,
    ADD COLUMN IF NOT EXISTS linea_de_id integer;

DROP TYPE IF EXISTS porcion_pizza;

-- Las restricciones se quitan y se vuelven a poner: así la migración se puede
-- ejecutar dos veces sin error. La clave foránea va primero porque depende de la
-- restricción única.
ALTER TABLE detalle_pedido
    DROP CONSTRAINT IF EXISTS detalle_pedido_linea_de_fk,
    DROP CONSTRAINT IF EXISTS detalle_pedido_extra_no_de_si_mismo,
    DROP CONSTRAINT IF EXISTS detalle_pedido_extra_sin_mitad,
    DROP CONSTRAINT IF EXISTS detalle_pedido_id_pedido_unico;

ALTER TABLE detalle_pedido
    -- Existe solo para que la clave foránea de abajo pueda apuntar al par
    -- (línea, pedido). El id ya es único por sí solo.
    ADD CONSTRAINT detalle_pedido_id_pedido_unico UNIQUE (id, pedido_id),
    -- Un extra cuelga de una línea DEL MISMO PEDIDO: la clave compuesta impide
    -- colgarlo de una pizza de otro pedido. Si se borra la pizza, se borran sus
    -- extras. Con linea_de_id nulo, la clave no se comprueba: es una línea común.
    ADD CONSTRAINT detalle_pedido_linea_de_fk
        FOREIGN KEY (linea_de_id, pedido_id)
        REFERENCES detalle_pedido (id, pedido_id) ON DELETE CASCADE,
    ADD CONSTRAINT detalle_pedido_extra_no_de_si_mismo
        CHECK (linea_de_id IS NULL OR linea_de_id <> id),
    -- Un extra es un solo producto: no tiene segunda mitad.
    ADD CONSTRAINT detalle_pedido_extra_sin_mitad
        CHECK (linea_de_id IS NULL OR producto_mitad_id IS NULL);

-- Lo que la base NO puede comprobar porque cruza tablas o filas, y valida el
-- servidor (tarjeta 06): que un extra sea de la categoría «extra» y cuelgue de una
-- pizza, que lleve la misma cantidad que su pizza, que las dos mitades sean pizzas,
-- y que la venta tenga al menos un producto.

-- Para leer los extras de una pizza sin recorrer todas las líneas.
CREATE INDEX IF NOT EXISTS detalle_pedido_linea_de_idx
    ON detalle_pedido (linea_de_id) WHERE linea_de_id IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 4. Documentación dentro de la base
-- ----------------------------------------------------------------------------

-- El comentario de 01 decía el nombre viejo del local (D-29).
COMMENT ON TABLE producto IS 'Carta de Max''s Pizzas: lo que se puede pedir.';

COMMENT ON TYPE categoria_producto IS
    'Categorías de la carta. «extra» es un agregado que se vende colgado de una pizza.';

COMMENT ON COLUMN producto.precio IS
    'Precio vigente. En una pizza de dos mitades, cada mitad aporta la mitad exacta de este precio. El precio con el que se cobró queda en la línea del pedido.';
COMMENT ON COLUMN producto.descripcion IS
    'Qué lleva el producto, para mostrarlo al venderlo. Opcional.';

COMMENT ON COLUMN detalle_pedido.producto_id IS
    'El producto; en una pizza de dos mitades, la primera mitad.';
COMMENT ON COLUMN detalle_pedido.producto_mitad_id IS
    'Solo en una pizza de dos sabores: la segunda mitad, distinta de la primera.';
COMMENT ON COLUMN detalle_pedido.linea_de_id IS
    'Solo en un extra: la línea de la pizza de la que cuelga, en el mismo pedido.';
COMMENT ON COLUMN detalle_pedido.precio_unitario IS
    'Precio de una unidad de esta línea en el momento del pedido, calculado por el servidor (D-27): una pizza de un sabor, su precio; de dos mitades, (precio A + precio B) / 2; un extra o una bebida, su precio.';

COMMIT;
