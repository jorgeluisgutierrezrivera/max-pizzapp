-- ============================================================================
-- Max Pizzapp — bases de datos del entorno
--
-- Este archivo corre ANTES que 01_schema.sql (los scripts de inicialización se
-- ejecutan en orden alfabético) y solo una vez, al CREAR el volumen de datos.
--
-- POR QUÉ EXISTE
--   El proveedor de identidad (Keycloak) necesita su propia base de datos para
--   guardar el realm, los clientes, los roles y los usuarios. Se le da una base
--   aparte dentro del MISMO servidor PostgreSQL, en lugar de un segundo motor:
--   es una pieza menos que mantener y una menos que consume memoria en el
--   servidor de producción, que es el recurso escaso.
--
--   Base aparte, no esquema aparte: Keycloak gestiona sus propias tablas y sus
--   migraciones entre versiones. Mezclarlas con las del dominio haría ilegible
--   el modelo de datos del proyecto y ataría las dos cosas en cada copia de
--   seguridad.
--
-- QUIÉN LA USA
--   El mismo usuario de la aplicación, que es el dueño del servidor en este
--   despliegue de un solo local. Darle a Keycloak su propio rol con permisos
--   limitados a su base es una mejora razonable de endurecimiento; se deja
--   anotada para la tarjeta de seguridad, no se improvisa aquí.
-- ============================================================================

CREATE DATABASE keycloak;

COMMENT ON DATABASE keycloak IS
    'Datos del proveedor de identidad (Keycloak): realm, clientes, roles y usuarios. '
    'No la toca la aplicacion: la gestiona Keycloak con sus propias migraciones.';
