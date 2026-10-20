/* =====================================================================
   BU7141 – Olist seller retention project
   STEP 0: SET-UP AND LOADING THE RAW CSV FILES
   ---------------------------------------------------------------------
   Idea: load every CSV *exactly as it is* into a "raw_" table where every
   column is plain text. Nothing gets converted or dropped on the way in,
   so we can check the data ourselves and every change after this point is
   one of OUR documented steps (not something an import tool did silently).
   The raw_ tables are never edited. All cleaning happens on "clean_" copies.

   BEFORE YOU RUN:
   1. Change the schema name in the USE line to your team's schema.
   2. Put the 8 CSV files in one folder. Press Cmd+F (Ctrl+F on Windows),
      click the replace option, and replace  '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data'  with that
      folder, e.g.  /Users/marialena/Documents/olist
   3. Workbench needs permission to read local files (one-time):
      Database > Manage Connections > your connection > Advanced tab >
      in the "Others" box add a new line:  OPT_LOCAL_INFILE=1
      Then close and reopen the connection.
   ===================================================================== */

USE olist;                    -- <-- change to your schema name
SET SQL_SAFE_UPDATES = 0;     -- Workbench blocks UPDATEs without a key in WHERE; we need them
SET GLOBAL local_infile = 1;  -- lets the server accept LOAD DATA LOCAL


/* ---------- 0.1 orders ---------- */
DROP TABLE IF EXISTS raw_orders;
CREATE TABLE raw_orders (
    order_id                      VARCHAR(50),
    customer_id                   VARCHAR(50),
    order_status                  VARCHAR(50),
    order_purchase_timestamp      VARCHAR(50),
    order_approved_at             VARCHAR(50),
    order_delivered_carrier_date  VARCHAR(50),
    order_delivered_customer_date VARCHAR(50),
    order_estimated_delivery_date VARCHAR(50)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/olist_orders_dataset.csv'
INTO TABLE raw_orders CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* ---------- 0.2 order_items ---------- */
DROP TABLE IF EXISTS raw_order_items;
CREATE TABLE raw_order_items (
    order_id            VARCHAR(50),
    order_item_id       VARCHAR(50),
    product_id          VARCHAR(50),
    seller_id           VARCHAR(50),
    shipping_limit_date VARCHAR(50),
    price               VARCHAR(50),
    freight_value       VARCHAR(50)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/olist_order_items_dataset.csv'
INTO TABLE raw_order_items CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* ---------- 0.3 sellers ---------- */
DROP TABLE IF EXISTS raw_sellers;
CREATE TABLE raw_sellers (
    seller_id              VARCHAR(50),
    seller_zip_code_prefix VARCHAR(50),
    seller_city            VARCHAR(100),
    seller_state           VARCHAR(50)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/olist_sellers_dataset.csv'
INTO TABLE raw_sellers CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* ---------- 0.4 order_reviews ----------
   The comment columns are free text with commas and line breaks inside
   quotes, so they are TEXT here. ESCAPED BY '' matters: without it MySQL
   reads a backslash as an escape character and damages values. */
DROP TABLE IF EXISTS raw_order_reviews;
CREATE TABLE raw_order_reviews (
    review_id               VARCHAR(50),
    order_id                VARCHAR(50),
    review_score            VARCHAR(50),
    review_comment_title    TEXT,
    review_comment_message  TEXT,
    review_creation_date    VARCHAR(50),
    review_answer_timestamp VARCHAR(50)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/olist_order_reviews_dataset.csv'
INTO TABLE raw_order_reviews CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* ---------- 0.5 products ---------- */
DROP TABLE IF EXISTS raw_products;
CREATE TABLE raw_products (
    product_id                 VARCHAR(50),
    product_category_name      VARCHAR(100),
    product_name_lenght        VARCHAR(50),
    product_description_lenght VARCHAR(50),
    product_photos_qty         VARCHAR(50),
    product_weight_g           VARCHAR(50),
    product_length_cm          VARCHAR(50),
    product_height_cm          VARCHAR(50),
    product_width_cm           VARCHAR(50)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/olist_products_dataset.csv'
INTO TABLE raw_products CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* ---------- 0.6 product_category_name_translation ----------
   (This file starts with an invisible "BOM" character in the header.
   IGNORE 1 LINES skips the header, so it does not reach the table.) */
DROP TABLE IF EXISTS raw_category_translation;
CREATE TABLE raw_category_translation (
    product_category_name         VARCHAR(100),
    product_category_name_english VARCHAR(100)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/product_category_name_translation.csv'
INTO TABLE raw_category_translation CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* ---------- 0.7 marketing_qualified_leads ---------- */
DROP TABLE IF EXISTS raw_marketing_qualified_leads;
CREATE TABLE raw_marketing_qualified_leads (
    mql_id             VARCHAR(50),
    first_contact_date VARCHAR(50),
    landing_page_id    VARCHAR(50),
    origin             VARCHAR(50)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/olist_marketing_qualified_leads_dataset.csv'
INTO TABLE raw_marketing_qualified_leads CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

/* ---------- 0.8 closed_deals ---------- */
DROP TABLE IF EXISTS raw_closed_deals;
CREATE TABLE raw_closed_deals (
    mql_id                        VARCHAR(50),
    seller_id                     VARCHAR(50),
    sdr_id                        VARCHAR(50),
    sr_id                         VARCHAR(50),
    won_date                      VARCHAR(50),
    business_segment              VARCHAR(100),
    lead_type                     VARCHAR(50),
    lead_behaviour_profile        VARCHAR(50),
    has_company                   VARCHAR(50),
    has_gtin                      VARCHAR(50),
    average_stock                 VARCHAR(50),
    business_type                 VARCHAR(50),
    declared_product_catalog_size VARCHAR(50),
    declared_monthly_revenue      VARCHAR(50)
);
LOAD DATA LOCAL INFILE '/Users/marialenageorgiou/Desktop/master/data management & visualisation/group assignment/data/olist_closed_deals_dataset.csv'
INTO TABLE raw_closed_deals CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES;


/* =====================================================================
   0.9 CHECK: did every row arrive?  (Compare with the CSV row counts.)
   Expected:
     raw_orders                      99,441
     raw_order_items                112,650
     raw_sellers                      3,095
     raw_order_reviews               99,224
     raw_products                    32,951
     raw_category_translation            71
     raw_marketing_qualified_leads    8,000
     raw_closed_deals                   842
   ===================================================================== */
SELECT 'raw_orders' AS table_name, COUNT(*) AS row_count FROM raw_orders
UNION ALL SELECT 'raw_order_items',               COUNT(*) FROM raw_order_items
UNION ALL SELECT 'raw_sellers',                   COUNT(*) FROM raw_sellers
UNION ALL SELECT 'raw_order_reviews',             COUNT(*) FROM raw_order_reviews
UNION ALL SELECT 'raw_products',                  COUNT(*) FROM raw_products
UNION ALL SELECT 'raw_category_translation',      COUNT(*) FROM raw_category_translation
UNION ALL SELECT 'raw_marketing_qualified_leads', COUNT(*) FROM raw_marketing_qualified_leads
UNION ALL SELECT 'raw_closed_deals',              COUNT(*) FROM raw_closed_deals;

/* 0.10 CHECK: hidden Windows line-break characters.
   A CSV saved on Windows (or re-saved by Excel) ends every line with two
   invisible characters, \r\n, instead of just \n. We load with '\n', so
   in those files the last column of each row keeps a stray \r (CHAR(13)).
   That stray character would make e.g. '25' fail to become a number.
   Expected (the last row of a file has no line break, so it is one short):
     orders 0 | order_items 0 | sellers 0 | reviews 99,223 | products 32,950
     translation 70 | mql 7,999 | deals 841
   -> 5 of the 8 files have Windows line endings. We remove the \r in each
      table's cleaning step (we do NOT edit the raw tables). */
SELECT 'orders' AS t, COUNT(*) AS rows_with_cr FROM raw_orders WHERE order_estimated_delivery_date LIKE CONCAT('%', CHAR(13))
UNION ALL SELECT 'order_items', COUNT(*) FROM raw_order_items   WHERE freight_value LIKE CONCAT('%', CHAR(13))
UNION ALL SELECT 'sellers',     COUNT(*) FROM raw_sellers       WHERE seller_state LIKE CONCAT('%', CHAR(13))
UNION ALL SELECT 'reviews',     COUNT(*) FROM raw_order_reviews WHERE review_answer_timestamp LIKE CONCAT('%', CHAR(13))
UNION ALL SELECT 'products',    COUNT(*) FROM raw_products      WHERE product_width_cm LIKE CONCAT('%', CHAR(13))
UNION ALL SELECT 'translation', COUNT(*) FROM raw_category_translation WHERE product_category_name_english LIKE CONCAT('%', CHAR(13))
UNION ALL SELECT 'mql',         COUNT(*) FROM raw_marketing_qualified_leads WHERE origin LIKE CONCAT('%', CHAR(13))
UNION ALL SELECT 'deals',       COUNT(*) FROM raw_closed_deals  WHERE declared_monthly_revenue LIKE CONCAT('%', CHAR(13));
