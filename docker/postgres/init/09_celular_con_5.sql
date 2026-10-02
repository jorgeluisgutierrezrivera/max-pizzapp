-- ============================================================================
-- Max Pizzapp — Migración 09: los celulares que empiezan con 5 (D-56)
--
-- POR QUÉ EXISTE
--   El autor avisó el 1-oct que en Bolivia ya se asignan celulares que empiezan
--   con 5. El Plan Técnico Fundamental de Numeración (Ministerio de Obras
--   Públicas, RM 339/2021) reserva los dígitos 5, 6 y 7 para el servicio móvil.
--   La 06 solo admitía 6 y 7: un cliente con un celular nuevo no podía dar su
--   número, y la base lo habría rechazado aunque la app y la API lo aceptaran.
--
--   Esta migración:
--     CAMBIA  cliente_celular_valido: 8 dígitos que empiezan con 5, 6 o 7. Lo
--             demás de la regla no cambia: el celular sigue siendo opcional.
--   Ningún celular guardado deja de cumplirla: la regla nueva incluye a la vieja.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 08. En una base que ya existe se
--   aplica UNA VEZ a mano, ANTES de reconstruir la API (si la API acepta un 5
--   antes que la base, esa venta respondería 500):
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/09_celular_con_5.sql
--   Está escrita para que ejecutarla dos veces no cambie nada ni falle.
-- ============================================================================

BEGIN;

ALTER TABLE cliente DROP CONSTRAINT IF EXISTS cliente_celular_valido;
ALTER TABLE cliente
    -- Sin celular es válido: el cliente que come en el local puede no darlo.
    ADD CONSTRAINT cliente_celular_valido
        CHECK (celular IS NULL OR celular ~ '^[5-7][0-9]{7}$');

COMMENT ON CONSTRAINT cliente_celular_valido ON cliente IS
    'Celular boliviano: 8 dígitos que empiezan con 5, 6 o 7 (D-31, D-56).';

COMMIT;
