-- ============================================================================
-- Max Pizzapp — La carta de Max's Pizzas
--
-- QUÉ ES REAL Y QUÉ NO
--   PIZZAS:   las 15 del catálogo del local (WhatsApp Business, 23-sep-2026), con
--             sus ingredientes. Los PRECIOS son los del catálogo, CONFIRMADOS por
--             la dueña el 25-sep-2026. Todas llevan masa casera y salsa de la
--             casa; la descripción dice solo lo que cambia.
--   BEBIDAS y EXTRAS: FICTICIOS. El catálogo no los muestra; se reemplazan cuando
--             lleguen los reales.
--   IMÁGENES: las pizzas usan las fotos del local, preparadas con
--             scripts/preparar-fotos.py (.webp); las bebidas, dibujos del proyecto
--             (scripts/dibujar-carta.py). La base guarda solo el nombre del archivo.
--
-- LAS REGLAS QUE SIGUE (D-27, D-28)
--   Solo pizzas enteras, de un sabor o de dos mitades. Una pizza de dos mitades
--   cuesta (precio A + precio B) / 2: el precio de cada mitad no se guarda, se
--   calcula. Un extra tiene un solo precio para cualquier pizza.
--   Las especialidades armadas por sectores (Dos estaciones, Tres estaciones y
--   Criolla española, que fusiona dos especiales con ingredientes criollos) son
--   pizzas con nombre y PRECIO PROPIO: no se cobran por mitades. La regla de las
--   mitades es para cuando el cliente combina dos sabores de la carta.
--
-- CUÁNDO SE EJECUTA
--   En una instalación nueva, sola, después de 04_solo_enteras_y_extras.sql: usa la
--   categoría «extra» y la descripción que agrega la 04. En una base que ya existe:
--     docker exec -i maxpizzapp-bd sh -c \
--       'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
--       < docker/postgres/init/05_carta.sql
--   Se puede ejecutar las veces que haga falta: un producto que ya existe (por su
--   nombre) se actualiza con los datos de este archivo, sin duplicarse. Lo único que
--   NO se toca es «disponible»: un producto marcado agotado en la base sigue
--   agotado aunque se vuelva a cargar la carta.
-- ============================================================================

BEGIN;

INSERT INTO producto (nombre, categoria, precio, descripcion, imagen) VALUES
    -- Pizzas: las del catálogo del local, con los precios confirmados por la dueña
    ('Carnívora',          'pizza', 60.00, 'Doble queso, peperoni y carne',                                             'carnivora.webp'),
    ('Champiñones',        'pizza', 50.00, 'Doble queso, jamón y champiñones',                                          'champinones.webp'),
    ('Choclo',             'pizza', 45.00, 'Doble queso, jamón y choclo',                                               'choclo.webp'),
    ('Clásica',            'pizza', 45.00, 'Doble queso, jamón y aceituna',                                             'clasica.webp'),
    ('Criolla española',   'pizza', 65.00, 'Queso criollo, mozzarella, chorizo ahumado, carne especial y choclo',       'criolla-espanola.webp'),
    ('Cuatro quesos',      'pizza', 55.00, 'Queso criollo, mozzarella, queso azul y cheddar',                           'cuatro-quesos.webp'),
    ('Dos estaciones',     'pizza', 50.00, 'Queso criollo, mozzarella, jamón, choclo y peperoni',                       'dos-estaciones.webp'),
    ('Española',           'pizza', 60.00, 'Queso criollo, mozzarella, chorizo ahumado y choclo',                       'espanola.webp'),
    ('Hawaiana',           'pizza', 50.00, 'Doble queso, jamón y piña caramelizada',                                    'hawaiana.webp'),
    ('La Malcriada',       'pizza', 60.00, 'Doble queso, peperoni, carne especial de la casa, choclo, parmesano y albahaca fresca', 'la-malcriada.webp'),
    ('Napolitana',         'pizza', 40.00, 'Doble queso, jamón y tomate en rodajas',                                    'napolitana.webp'),
    ('Peperoni',           'pizza', 50.00, 'Doble queso, jamón y peperoni',                                             'peperoni.webp'),
    ('Salame',             'pizza', 45.00, 'Doble queso y salame',                                                      'salame.webp'),
    ('Tres estaciones',    'pizza', 50.00, 'Doble queso, peperoni, salame y choclo',                                    'tres-estaciones.webp'),
    ('Vegetariana',        'pizza', 45.00, 'Doble queso, choclo y aceituna',                                            'vegetariana.webp'),
    -- Bebidas: ficticias
    ('Agua mineral 600 ml', 'bebida',  6.00, NULL, 'agua-mineral.png'),
    ('Gaseosa 2 L',         'bebida', 18.00, NULL, 'gaseosa.png'),
    ('Jugo natural 1 L',    'bebida', 15.00, NULL, 'jugo-natural.png'),
    -- Extras: ficticios, un solo precio para cualquier pizza
    ('Extra choclo',   'extra',  5.00, NULL, NULL),
    ('Extra jamón',    'extra',  8.00, NULL, NULL),
    ('Extra peperoni', 'extra', 10.00, NULL, NULL),
    ('Extra queso',    'extra',  8.00, NULL, NULL)
ON CONFLICT (nombre) DO UPDATE SET
    categoria   = EXCLUDED.categoria,
    precio      = EXCLUDED.precio,
    descripcion = EXCLUDED.descripcion,
    imagen      = EXCLUDED.imagen;

COMMIT;
