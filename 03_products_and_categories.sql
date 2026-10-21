/* Step 3: category translation and products
   raw_category_translation -> clean_category_translation
   raw_products             -> clean_products
   Products are only used for each seller's main product category. */
USE olist;
SET SQL_SAFE_UPDATES = 0;

/* part A: category translation */
DROP TABLE IF EXISTS clean_category_translation;
CREATE TABLE clean_category_translation AS SELECT * FROM raw_category_translation;

-- 3.1 hidden \r at the end of the english name (see 0.10)
UPDATE clean_category_translation
SET product_category_name_english = REPLACE(product_category_name_english, CHAR(13), '')
WHERE product_category_name_english LIKE CONCAT('%', CHAR(13));

-- 3.2 duplicates
SELECT COUNT(*) AS categories,
       COUNT(*) - COUNT(DISTINCT product_category_name) AS duplicates
FROM clean_category_translation;

-- 3.3 spelling mistakes in the english names. They show up as labels in
-- Tableau so we correct them.
-- check
SELECT * FROM clean_category_translation
WHERE product_category_name_english IN
      ('costruction_tools_garden','costruction_tools_tools','fashio_female_clothing','home_confort');

-- fix
UPDATE clean_category_translation SET product_category_name_english = 'construction_tools_garden' WHERE product_category_name_english = 'costruction_tools_garden';
UPDATE clean_category_translation SET product_category_name_english = 'construction_tools_tools'  WHERE product_category_name_english = 'costruction_tools_tools';
UPDATE clean_category_translation SET product_category_name_english = 'fashion_female_clothing'   WHERE product_category_name_english = 'fashio_female_clothing';
UPDATE clean_category_translation SET product_category_name_english = 'home_comfort'              WHERE product_category_name_english = 'home_confort';


/* part B: products */
DROP TABLE IF EXISTS clean_products;
CREATE TABLE clean_products AS SELECT * FROM raw_products;

-- 3.4 hidden \r at the end of the last column
UPDATE clean_products
SET product_width_cm = REPLACE(product_width_cm, CHAR(13), '')
WHERE product_width_cm LIKE CONCAT('%', CHAR(13));

-- 3.5 duplicates and id format
SELECT COUNT(*)                                   AS products,
       COUNT(*) - COUNT(DISTINCT product_id)      AS duplicate_product_ids,
       SUM(product_id NOT REGEXP '^[0-9a-f]{32}$') AS bad_product_ids
FROM clean_products;

-- 3.6 two column names are misspelt in the source ("lenght"), renamed so
-- the team and Tableau get correct names
ALTER TABLE clean_products
    RENAME COLUMN product_name_lenght        TO product_name_length,
    RENAME COLUMN product_description_lenght TO product_description_length;


/* 3.7 missing values stored as empty text
   The same 610 products are missing all their catalogue info (category,
   name length, description length, photos) and 2 products are missing
   their measurements. */
SELECT SUM(product_category_name      = '') AS blank_category,
       SUM(product_name_length        = '') AS blank_name_length,
       SUM(product_description_length = '') AS blank_description_length,
       SUM(product_photos_qty         = '') AS blank_photos,
       SUM(product_weight_g           = '') AS blank_weight,
       SUM(product_length_cm          = '') AS blank_length,
       SUM(product_height_cm          = '') AS blank_height,
       SUM(product_width_cm           = '') AS blank_width
FROM clean_products;

-- empty text to NULL
UPDATE clean_products SET product_category_name      = NULL WHERE product_category_name      = '';
UPDATE clean_products SET product_name_length        = NULL WHERE product_name_length        = '';
UPDATE clean_products SET product_description_length = NULL WHERE product_description_length = '';
UPDATE clean_products SET product_photos_qty         = NULL WHERE product_photos_qty         = '';
UPDATE clean_products SET product_weight_g           = NULL WHERE product_weight_g           = '';
UPDATE clean_products SET product_length_cm          = NULL WHERE product_length_cm          = '';
UPDATE clean_products SET product_height_cm          = NULL WHERE product_height_cm          = '';
UPDATE clean_products SET product_width_cm           = NULL WHERE product_width_cm           = '';

/* The 610 products with no category are kept and the category stays NULL.
   Deleting them would also delete their sales from order_items. When we
   group sellers by main category, NULL becomes 'unknown' (COALESCE). */


-- 3.8 the remaining values should all be whole numbers
SELECT SUM(product_name_length        NOT REGEXP '^[0-9]+$') AS bad_name_length,
       SUM(product_description_length NOT REGEXP '^[0-9]+$') AS bad_description_length,
       SUM(product_photos_qty         NOT REGEXP '^[0-9]+$') AS bad_photos,
       SUM(product_weight_g           NOT REGEXP '^[0-9]+$') AS bad_weight,
       SUM(product_length_cm          NOT REGEXP '^[0-9]+$') AS bad_length,
       SUM(product_height_cm          NOT REGEXP '^[0-9]+$') AS bad_height,
       SUM(product_width_cm           NOT REGEXP '^[0-9]+$') AS bad_width
FROM clean_products;

ALTER TABLE clean_products
    MODIFY product_id                 CHAR(32)     NOT NULL,
    MODIFY product_category_name      VARCHAR(100) NULL,
    MODIFY product_name_length        INT NULL,
    MODIFY product_description_length INT NULL,
    MODIFY product_photos_qty         INT NULL,
    MODIFY product_weight_g           INT NULL,
    MODIFY product_length_cm          INT NULL,
    MODIFY product_height_cm          INT NULL,
    MODIFY product_width_cm           INT NULL;


-- 3.9 impossible values, a physical product can't weigh 0 g
-- check the ranges (4 products have weight 0, the rest look plausible)
SELECT MIN(product_weight_g) AS min_weight, MAX(product_weight_g) AS max_weight,
       SUM(product_weight_g = 0) AS zero_weight,
       MIN(product_length_cm) AS min_len, MAX(product_length_cm) AS max_len,
       MIN(product_height_cm) AS min_h,   MAX(product_height_cm) AS max_h,
       MIN(product_width_cm)  AS min_w,   MAX(product_width_cm)  AS max_w,
       MIN(product_photos_qty) AS min_photos, MAX(product_photos_qty) AS max_photos
FROM clean_products;

-- fix: 0 g becomes NULL (unknown)
UPDATE clean_products SET product_weight_g = NULL WHERE product_weight_g = 0;


/* 3.10 categories without an english translation
   2 categories (13 products): portateis_cozinha_e_preparadores_de_alimentos
   (10) and pc_gamer (3) */
SELECT p.product_category_name, COUNT(*) AS products
FROM clean_products p
LEFT JOIN clean_category_translation t
       ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name;

-- fix: add the 2 missing translations so every product category has an
-- english name and can be linked to the translation table with a foreign key
INSERT INTO clean_category_translation (product_category_name, product_category_name_english)
VALUES ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers'),
       ('pc_gamer', 'pc_gamer');

ALTER TABLE clean_category_translation
    MODIFY product_category_name         VARCHAR(100) NOT NULL,
    MODIFY product_category_name_english VARCHAR(100) NOT NULL;


/* 3.11 verify */
SELECT (SELECT COUNT(*) FROM clean_products) AS products,
       (SELECT COUNT(*) FROM clean_products p
          LEFT JOIN clean_category_translation t ON t.product_category_name = p.product_category_name
         WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL) AS untranslated_products,
       (SELECT COUNT(*) FROM clean_category_translation) AS translation_rows,
       (SELECT COUNT(*) FROM clean_products WHERE product_weight_g = 0) AS zero_weight_left;
