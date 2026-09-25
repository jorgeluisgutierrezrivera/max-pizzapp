-- ============================================================================
-- Max Pizzapp — Migración 08: las pizzas que se venden solo enteras (D-39)
--
-- POR QUÉ EXISTE
--   Al revisar la tarjeta 06, el autor precisó una regla del local: Dos
--   estaciones, Tres estaciones y Criolla española ya vienen armadas por
--   sectores, con varios sabores en una misma pizza. No se venden como mitad de
--   otra pizza, ni se combinan entre sí: se venden enteras. La carta (05) ya las
--   describía así; faltaba que la base, la API y la venta lo hicieran cumplir.
--
--   Esta migración:
--     AGREGA  producto.solo_entera: verdadero en las pizzas que no se venden por
--             mitades. Por omisión, falso: una pizza nueva de la carta sí admite
--             mitades, que es lo común.
--     MARCA   las tres especialidades.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 07. En una base que ya existe se
--   aplica UNA VEZ a mano, después de la 07 y antes de reconstruir la API:
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/08_pizzas_solo_enteras.sql
--   Está escrita para que ejecutarla dos veces no cambie nada ni falle.
-- ============================================================================

BEGIN;

ALTER TABLE producto
    ADD COLUMN IF NOT EXISTS solo_entera boolean NOT NULL DEFAULT false;

ALTER TABLE producto DROP CONSTRAINT IF EXISTS producto_solo_entera_es_pizza;
ALTER TABLE producto
    -- Solo una pizza puede ser "solo entera": una bebida o un extra no tienen
    -- mitades de las que hablar.
    ADD CONSTRAINT producto_solo_entera_es_pizza CHECK (NOT solo_entera OR categoria = 'pizza');

-- Las especialidades armadas por sectores, por su nombre, como las carga la 05.
UPDATE producto
   SET solo_entera = true
 WHERE nombre IN ('Dos estaciones', 'Tres estaciones', 'Criolla española')
   AND categoria = 'pizza';

-- Lo que la base NO puede comprobar porque depende de otra fila, y valida el
-- servidor al calcular la venta: que ninguna de las dos mitades de una línea sea
-- una pizza "solo entera".

COMMENT ON COLUMN producto.solo_entera IS
    'Verdadero en las pizzas que se venden solo enteras, porque ya combinan varios sabores (Dos estaciones, Tres estaciones, Criolla española). No pueden ser mitad de otra pizza (D-39).';

COMMIT;
