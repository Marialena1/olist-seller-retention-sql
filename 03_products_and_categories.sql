/* =====================================================================
   STEP 3: CATEGORY TRANSLATION + PRODUCTS
   raw_category_translation -> clean_category_translation
   raw_products             -> clean_products
   We use products only for each seller's main product category.
   ===================================================================== */
USE olist;
SET SQL_SAFE_UPDATES = 0;

/* ---------------- PART A: category translation ---------------- */
DROP TABLE IF EXISTS clean_category_translation;
CREATE TABLE clean_category_translation AS SELECT * FROM raw_category_translation;

-- 3.1 Hidden Windows line-break (\r) at the end of the English name
-- (see step 0.10). Expected rows affected: 70
UPDATE clean_category_translation
SET product_category_name_english = REPLACE(product_category_name_english, CHAR(13), '')
WHERE product_category_name_english LIKE CONCAT('%', CHAR(13));

-- 3.2 Duplicates.  Expected: 71 rows, 0 duplicates
SELECT COUNT(*) AS categories,
       COUNT(*) - COUNT(DISTINCT product_category_name) AS duplicates
FROM clean_category_translation;

-- 3.3 Spelling mistakes in the English names. These names will appear
-- as labels in Tableau, so we correct them.
-- CHECK  Expected: 4 rows
SELECT * FROM clean_category_translation
WHERE product_category_name_english IN
      ('costruction_tools_garden','costruction_tools_tools','fashio_female_clothing','home_confort');

-- FIX  Expected rows affected: 1 each
UPDATE clean_category_translation SET product_category_name_english = 'construction_tools_garden' WHERE product_category_name_english = 'costruction_tools_garden';
UPDATE clean_category_translation SET product_category_name_english = 'construction_tools_tools'  WHERE product_category_name_english = 'costruction_tools_tools';
UPDATE clean_category_translation SET product_category_name_english = 'fashion_female_clothing'   WHERE product_category_name_english = 'fashio_female_clothing';
UPDATE clean_category_translation SET product_category_name_english = 'home_comfort'              WHERE product_category_name_english = 'home_confort';


/* ---------------- PART B: products ---------------- */
DROP TABLE IF EXISTS clean_products;
CREATE TABLE clean_products AS SELECT * FROM raw_products;

-- 3.4 Hidden \r at the end of the last column.  Expected rows affected: 32,950
UPDATE clean_products
SET product_width_cm = REPLACE(product_width_cm, CHAR(13), '')
WHERE product_width_cm LIKE CONCAT('%', CHAR(13));

-- 3.5 Duplicates and ID format.  Expected: 32,951 products, 0, 0
SELECT COUNT(*)                                   AS products,
       COUNT(*) - COUNT(DISTINCT product_id)      AS duplicate_product_ids,
       SUM(product_id NOT REGEXP '^[0-9a-f]{32}$') AS bad_product_ids
FROM clean_products;

-- 3.6 Column names are misspelt in the source ("lenght"). Fix them so
-- the team and Tableau use correct names.
ALTER TABLE clean_products
    RENAME COLUMN product_name_lenght        TO product_name_length,
    RENAME COLUMN product_description_lenght TO product_description_length;


/* 3.7 Missing values stored as empty text.
   Expected: category 610 | name length 610 | description length 610 |
             photos 610 | weight 2 | length 2 | height 2 | width 2
   The same 610 products are missing all their catalogue information,
   and 2 products are missing all their measurements. */
SELECT SUM(product_category_name      = '') AS blank_category,
       SUM(product_name_length        = '') AS blank_name_length,
       SUM(product_description_length = '') AS blank_description_length,
       SUM(product_photos_qty         = '') AS blank_photos,
       SUM(product_weight_g           = '') AS blank_weight,
       SUM(product_length_cm          = '') AS blank_length,
       SUM(product_height_cm          = '') AS blank_height,
       SUM(product_width_cm           = '') AS blank_width
FROM clean_products;

-- FIX: empty text -> NULL (expected rows affected: 610 x4, then 2 x4)
UPDATE clean_products SET product_category_name      = NULL WHERE product_category_name      = '';
UPDATE clean_products SET product_name_length        = NULL WHERE product_name_length        = '';
UPDATE clean_products SET product_description_length = NULL WHERE product_description_length = '';
UPDATE clean_products SET product_photos_qty         = NULL WHERE product_photos_qty         = '';
UPDATE clean_products SET product_weight_g           = NULL WHERE product_weight_g           = '';
UPDATE clean_products SET product_length_cm          = NULL WHERE product_length_cm          = '';
UPDATE clean_products SET product_height_cm          = NULL WHERE product_height_cm          = '';
UPDATE clean_products SET product_width_cm           = NULL WHERE product_width_cm           = '';

/* Decision on the 610 products with no category: we KEEP them and leave
   the category NULL. Deleting them would also delete their sales from
   order_items. When we group sellers by main category, NULL becomes
   the label 'unknown' (with COALESCE, as in the Session 3 slides). */


-- 3.8 Numbers check: all remaining values are whole numbers.  Expected: 0
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


-- 3.9 Impossible values: a physical product cannot weigh 0 g.
-- CHECK ranges. Expected: weight 0 to 40,425 g, with 4 products at 0 g;
-- length 7-105, height 2-105, width 6-118 cm, photos 1-20 (all plausible)
SELECT MIN(product_weight_g) AS min_weight, MAX(product_weight_g) AS max_weight,
       SUM(product_weight_g = 0) AS zero_weight,
       MIN(product_length_cm) AS min_len, MAX(product_length_cm) AS max_len,
       MIN(product_height_cm) AS min_h,   MAX(product_height_cm) AS max_h,
       MIN(product_width_cm)  AS min_w,   MAX(product_width_cm)  AS max_w,
       MIN(product_photos_qty) AS min_photos, MAX(product_photos_qty) AS max_photos
FROM clean_products;

-- FIX: 0 g -> NULL (unknown). Expected rows affected: 4
UPDATE clean_products SET product_weight_g = NULL WHERE product_weight_g = 0;


/* 3.10 Categories without an English translation.
   Expected: 2 categories, 13 products:
     portateis_cozinha_e_preparadores_de_alimentos  10
     pc_gamer                                         3            */
SELECT p.product_category_name, COUNT(*) AS products
FROM clean_products p
LEFT JOIN clean_category_translation t
       ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name;

-- FIX: add the 2 missing translations, so every product category has an
-- English name and can be linked (foreign key) to the translation table.
-- Expected rows affected: 2
INSERT INTO clean_category_translation (product_category_name, product_category_name_english)
VALUES ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers'),
       ('pc_gamer', 'pc_gamer');

ALTER TABLE clean_category_translation
    MODIFY product_category_name         VARCHAR(100) NOT NULL,
    MODIFY product_category_name_english VARCHAR(100) NOT NULL;


/* 3.11 VERIFY
   Expected: 32,951 products; 0 categories without translation;
             73 categories in the translation table; 0 products at 0 g */
SELECT (SELECT COUNT(*) FROM clean_products) AS products,
       (SELECT COUNT(*) FROM clean_products p
          LEFT JOIN clean_category_translation t ON t.product_category_name = p.product_category_name
         WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL) AS untranslated_products,
       (SELECT COUNT(*) FROM clean_category_translation) AS translation_rows,
       (SELECT COUNT(*) FROM clean_products WHERE product_weight_g = 0) AS zero_weight_left;
