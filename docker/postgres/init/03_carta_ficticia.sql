-- ============================================================================
-- Max Pizzapp — Carta FICTICIA para desarrollo y demostración
--
-- ESTO NO ES LA CARTA DE MAX PIZZAS
--   Los nombres son genéricos y los precios, en bolivianos, son plausibles pero
--   inventados. Sirven para desarrollar, probar y demostrar el sistema mientras
--   no se cargue la carta real. Las ilustraciones se dibujaron para el proyecto
--   y viven con la app, en frontend/web/carta/: aquí se guarda solo el nombre
--   del archivo.
--
-- CÓMO SE REEMPLAZA
--   La carta real se carga con otro archivo con esta misma forma. Este no toca
--   el esquema: solo inserta filas en producto.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 02_porciones_y_carta.sql. En una
--   base que ya existe, a mano:
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/03_carta_ficticia.sql
--   Se puede ejecutar las veces que haga falta: un producto que ya existe (por
--   su nombre) se actualiza con los datos de este archivo, sin duplicarse. Lo
--   único que NO se toca es «disponible»: si cocina marcó un producto agotado,
--   volver a cargar la carta no lo revive.
--
-- LAS REGLAS QUE SIGUE (D-25)
--   Cada pizza tiene su precio de entera (precio) y su precio de media
--   (precio_media), y una gama que solo agrupa la carta. Las bebidas no tienen
--   gama ni precio de media. La migración 02 rechaza cualquier fila que no lo
--   cumpla.
-- ============================================================================

BEGIN;

INSERT INTO producto (nombre, categoria, gama, precio, precio_media, imagen) VALUES
    -- Tradicionales
    ('Muzzarella',     'pizza',  'tradicional', 55.00, 30.00, 'muzzarella.png'),
    ('Napolitana',     'pizza',  'tradicional', 60.00, 32.00, 'napolitana.png'),
    ('Pepperoni',      'pizza',  'tradicional', 65.00, 35.00, 'pepperoni.png'),
    ('Jamón y queso',  'pizza',  'tradicional', 60.00, 32.00, 'jamon-y-queso.png'),
    ('Fugazza',        'pizza',  'tradicional', 55.00, 30.00, 'fugazza.png'),
    -- Premium
    ('Carnívora',      'pizza',  'premium',     85.00, 45.00, 'carnivora.png'),
    ('Hawaiana',       'pizza',  'premium',     80.00, 42.00, 'hawaiana.png'),
    ('Cuatro quesos',  'pizza',  'premium',     82.00, 43.00, 'cuatro-quesos.png'),
    ('Pollo barbacoa', 'pizza',  'premium',     85.00, 45.00, 'pollo-barbacoa.png'),
    -- Bebidas
    ('Gaseosa 2 L',         'bebida', NULL, 18.00, NULL, 'gaseosa.png'),
    ('Jugo natural 1 L',    'bebida', NULL, 15.00, NULL, 'jugo-natural.png'),
    ('Agua mineral 600 ml', 'bebida', NULL,  6.00, NULL, 'agua-mineral.png')
ON CONFLICT (nombre) DO UPDATE SET
    categoria    = EXCLUDED.categoria,
    gama         = EXCLUDED.gama,
    precio       = EXCLUDED.precio,
    precio_media = EXCLUDED.precio_media,
    imagen       = EXCLUDED.imagen;

COMMIT;
