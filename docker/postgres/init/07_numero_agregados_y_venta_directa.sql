-- ============================================================================
-- Max Pizzapp — Migración 07: el número del día, lo agregado después y la
--                             venta directa de bebidas (D-35, D-37, D-38)
--
-- POR QUÉ EXISTE
--   Tres cosas del mostrador que el autor precisó al revisar la tarjeta 06:
--     - los pedidos se cantan con un número corto que empieza en 1 cada día y no
--       tiene huecos: "Pedido 12" (D-35);
--     - a un pedido ya enviado se le pueden agregar productos, y cocina tiene
--       que ver qué llegó después (D-37);
--     - la soda que se vende al paso no lleva nombre ni pasa por cocina: es una
--       venta directa, entregada en el momento (D-38).
--
--   Esta migración:
--     AGREGA  pedido.dia, que la base calcula desde la hora del pedido en la
--             hora de Bolivia, y pedido.numero_del_dia, único por día.
--     AGREGA  detalle_pedido.agregado_en, agregado_por y agregado_por_nombre:
--             cuándo y quién agregó una línea después de enviar el pedido.
--     PERMITE un pedido sin cliente y sin "para llevar", pero SOLO si es una
--             venta directa: sin número, sin observación y entregada.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 06. En una base que ya existe se
--   aplica UNA VEZ a mano, después de la 06 y antes de reconstruir la API:
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/07_numero_agregados_y_venta_directa.sql
--   Está escrita para que ejecutarla dos veces no cambie nada ni falle.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. El número del día (D-35)
-- ----------------------------------------------------------------------------

-- El día lo calcula la base, no la API: así un pedido nunca queda en un día
-- distinto del de su hora. Es la fecha en Bolivia (UTC-4, sin horario de
-- verano), no la del servidor, que corre en UTC: un pedido de las 21:00 de
-- Tarija es de ese día, aunque en UTC ya sea el siguiente.
ALTER TABLE pedido
    ADD COLUMN IF NOT EXISTS dia date
        GENERATED ALWAYS AS ((creado_en AT TIME ZONE 'America/La_Paz')::date) STORED;

ALTER TABLE pedido
    ADD COLUMN IF NOT EXISTS numero_del_dia integer;

-- Los pedidos que ya existían reciben su número en orden de llegada, día por
-- día. Solo los que no lo tienen: una segunda ejecución no los renumera.
UPDATE pedido p
   SET numero_del_dia = n.numero
  FROM (SELECT id,
               row_number() OVER (PARTITION BY dia ORDER BY creado_en, id) AS numero
          FROM pedido) n
 WHERE p.id = n.id
   AND p.numero_del_dia IS NULL
   AND p.cliente_id IS NOT NULL;

ALTER TABLE pedido
    DROP CONSTRAINT IF EXISTS pedido_numero_del_dia_valido,
    DROP CONSTRAINT IF EXISTS pedido_numero_del_dia_unico;
ALTER TABLE pedido
    ADD CONSTRAINT pedido_numero_del_dia_valido CHECK (numero_del_dia > 0),
    -- Dos ventas simultáneas no pueden sacar el mismo número. La API ya las pone
    -- en fila con un bloqueo; esta restricción es la garantía de la base.
    ADD CONSTRAINT pedido_numero_del_dia_unico UNIQUE (dia, numero_del_dia);


-- ----------------------------------------------------------------------------
-- 2. La venta directa de bebidas (D-38)
-- ----------------------------------------------------------------------------

-- El cliente y "para llevar" dejan de ser obligatorios en la columna, porque la
-- venta directa no los tiene. La regla completa la pone la restricción de abajo.
ALTER TABLE pedido ALTER COLUMN cliente_id DROP NOT NULL;
ALTER TABLE pedido ALTER COLUMN para_llevar DROP NOT NULL;

ALTER TABLE pedido DROP CONSTRAINT IF EXISTS pedido_o_venta_directa;
ALTER TABLE pedido
    -- O es un pedido, con cliente, "para llevar" y número del día; o es una venta
    -- directa, sin ninguno de los tres, sin observación y ya entregada. Nada a
    -- medio camino: un pedido con cliente y sin número, o una venta sin cliente
    -- esperando en la cola de cocina, son imposibles.
    ADD CONSTRAINT pedido_o_venta_directa CHECK (
        (cliente_id IS NOT NULL AND para_llevar IS NOT NULL AND numero_del_dia IS NOT NULL)
        OR
        (cliente_id IS NULL AND para_llevar IS NULL AND numero_del_dia IS NULL
         AND observacion IS NULL AND estado = 'entregado')
    );


-- ----------------------------------------------------------------------------
-- 3. Lo que se agrega a un pedido ya enviado (D-37)
-- ----------------------------------------------------------------------------

-- Vacías en las líneas con las que nació el pedido; completas en las que se
-- agregaron después. Cocina las ve marcadas, y queda quién las agregó.
ALTER TABLE detalle_pedido
    ADD COLUMN IF NOT EXISTS agregado_en         timestamptz,
    ADD COLUMN IF NOT EXISTS agregado_por        text,
    ADD COLUMN IF NOT EXISTS agregado_por_nombre varchar(120);

ALTER TABLE detalle_pedido DROP CONSTRAINT IF EXISTS detalle_pedido_agregado_completo;
ALTER TABLE detalle_pedido
    -- Las tres juntas o ninguna: una línea agregada dice cuándo y quién.
    ADD CONSTRAINT detalle_pedido_agregado_completo CHECK (
        (agregado_en IS NULL AND agregado_por IS NULL AND agregado_por_nombre IS NULL)
        OR
        (agregado_en IS NOT NULL AND btrim(agregado_por) <> '' AND agregado_por_nombre IS NOT NULL)
    );

-- Lo que la base NO puede comprobar porque depende de otras filas o de quién
-- llama, y valida el servidor: que una venta directa sea solo de bebidas, que
-- un pedido lleve al menos una pizza, y qué se puede agregar según el estado
-- del pedido.


-- ----------------------------------------------------------------------------
-- 4. Documentación dentro de la base
-- ----------------------------------------------------------------------------

COMMENT ON COLUMN pedido.dia IS
    'Fecha del pedido en la hora de Bolivia (America/La_Paz). La calcula la base desde creado_en (D-35).';
COMMENT ON COLUMN pedido.numero_del_dia IS
    'El número que se canta en el mostrador: empieza en 1 cada día y no tiene huecos. Vacío en la venta directa (D-35, D-38).';
COMMENT ON COLUMN pedido.cliente_id IS
    'El cliente a cuyo nombre está el pedido. Obligatorio en todo pedido; vacío solo en la venta directa de bebidas (D-31, D-38).';
COMMENT ON COLUMN pedido.para_llevar IS
    'Verdadero si el pedido es para llevar; falso si se come en el local (D-34). Vacío solo en la venta directa (D-38).';
COMMENT ON COLUMN detalle_pedido.agregado_en IS
    'Cuándo se agregó la línea a un pedido ya enviado. Vacío en las líneas con las que nació el pedido (D-37).';
COMMENT ON COLUMN detalle_pedido.agregado_por IS
    'Identificador (sub) de quien agregó la línea. Viene de Keycloak (D-37).';
COMMENT ON COLUMN detalle_pedido.agregado_por_nombre IS
    'Copia del nombre de quien agregó la línea (D-37).';

COMMIT;
