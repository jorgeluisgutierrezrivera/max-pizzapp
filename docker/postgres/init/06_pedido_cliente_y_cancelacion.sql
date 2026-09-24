-- ============================================================================
-- Max Pizzapp — Migración 06: para llevar, el cliente y la cancelación
--                             (D-31, D-33, D-34)
--
-- POR QUÉ EXISTE
--   La tarjeta 06 guarda los pedidos, y al diseñarla el autor precisó tres cosas:
--     - todo pedido va a nombre de un cliente, y el celular, si lo da, sirve
--       para avisarle que su pedido está listo (D-31);
--     - todo pedido dice si es para llevar o para comer en el local (D-34);
--     - la baja de un pedido es su cancelación, con un motivo, y no se borra
--       nada (D-33).
--
--   Esta migración:
--     AGREGA  pedido.para_llevar y historial_estado.motivo.
--     EXIGE   que todo pedido tenga cliente, y que el celular tenga el formato
--             de un celular boliviano: 8 dígitos que empiezan con 6 o 7.
--     IMPIDE  que dos clientes tengan el mismo celular: el celular identifica
--             al cliente, y un pedido nuevo con ese número se asocia a él.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 05. En una base que ya existe se
--   aplica UNA VEZ a mano, antes de reconstruir la API:
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/06_pedido_cliente_y_cancelacion.sql
--   Está escrita para que ejecutarla dos veces no cambie nada ni falle.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. pedido: para llevar o para comer aquí, y siempre con cliente
-- ----------------------------------------------------------------------------

-- El valor por defecto existe solo para completar las filas que ya hubiera; se
-- quita enseguida, así que a partir de aquí cada pedido tiene que decirlo.
ALTER TABLE pedido
    ADD COLUMN IF NOT EXISTS para_llevar boolean NOT NULL DEFAULT false;
ALTER TABLE pedido
    ALTER COLUMN para_llevar DROP DEFAULT;

-- El nombre del cliente es obligatorio (D-31): ningún pedido queda sin cliente.
ALTER TABLE pedido
    ALTER COLUMN cliente_id SET NOT NULL;


-- ----------------------------------------------------------------------------
-- 2. cliente: el celular, con formato y único
-- ----------------------------------------------------------------------------

ALTER TABLE cliente DROP CONSTRAINT IF EXISTS cliente_celular_valido;
ALTER TABLE cliente
    -- Sin celular es válido: el cliente que come en el local puede no darlo.
    ADD CONSTRAINT cliente_celular_valido
        CHECK (celular IS NULL OR celular ~ '^[67][0-9]{7}$');

-- Parcial: los clientes sin celular no chocan entre sí. La API busca por este
-- índice para asociar un pedido nuevo al cliente que ya dio ese número.
CREATE UNIQUE INDEX IF NOT EXISTS cliente_celular_unico
    ON cliente (celular) WHERE celular IS NOT NULL;


-- ----------------------------------------------------------------------------
-- 3. historial_estado: el motivo de una cancelación
-- ----------------------------------------------------------------------------

ALTER TABLE historial_estado
    ADD COLUMN IF NOT EXISTS motivo varchar(120);

ALTER TABLE historial_estado
    DROP CONSTRAINT IF EXISTS historial_estado_motivo_solo_al_cancelar,
    DROP CONSTRAINT IF EXISTS historial_estado_motivo_no_vacio;
ALTER TABLE historial_estado
    -- Toda cancelación dice por qué, y ningún otro cambio lleva motivo.
    ADD CONSTRAINT historial_estado_motivo_solo_al_cancelar
        CHECK ((estado = 'cancelado') = (motivo IS NOT NULL)),
    ADD CONSTRAINT historial_estado_motivo_no_vacio
        CHECK (motivo IS NULL OR btrim(motivo) <> '');

-- Lo que la base NO puede comprobar porque depende de quién llama o del estado
-- anterior, y valida el servidor: qué rol hace cada cambio, qué cambios de
-- estado son válidos, que solo recepción vea el celular, y que un pedido sin
-- pizzas nazca «listo» (D-32).


-- ----------------------------------------------------------------------------
-- 4. Documentación dentro de la base
-- ----------------------------------------------------------------------------

COMMENT ON COLUMN pedido.para_llevar IS
    'Verdadero si el pedido es para llevar; falso si se come en el local (D-34). Cocina lo ve para saber si va en caja o en plato.';
COMMENT ON COLUMN pedido.cliente_id IS
    'El cliente a cuyo nombre está el pedido. Obligatorio (D-31).';
COMMENT ON COLUMN cliente.celular IS
    'Opcional. Para avisarle al cliente que su pedido está listo. Identifica al cliente: no se repite. Solo lo ve recepción (D-31).';
COMMENT ON COLUMN historial_estado.motivo IS
    'Solo en una cancelación, y obligatorio en ella: por qué se canceló el pedido (D-33).';

COMMIT;
