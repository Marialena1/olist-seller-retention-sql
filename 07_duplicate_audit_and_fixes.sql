/* Step 7: duplicate and redundancy audit, plus the fixes it led to
   Run after scripts 01-06.

   Steps 1-6 only checked duplicate keys. This looks for the other kinds
   of duplication:
     7.1 identical rows
     7.2 same content under a different id
     7.3 the same value written two ways ('SP' vs 'sp')
     7.4 duplicated columns / information stored twice
   It found two real problems, fixed in 7.5 and 7.6. */
USE olist;
SET SQL_SAFE_UPDATES = 0;


/* 7.1 exact duplicate rows (every column identical)
   GROUP BY all the columns puts identical rows together and HAVING
   COUNT(*) > 1 keeps only the groups with copies. Should be 0 everywhere. */
SELECT 'orders' AS table_name, COUNT(*) AS duplicated_rows FROM (SELECT 1 FROM clean_orders GROUP BY order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date HAVING COUNT(*) > 1) x
UNION ALL SELECT 'order_items',   COUNT(*) FROM (SELECT 1 FROM clean_order_items GROUP BY order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value HAVING COUNT(*) > 1) x
UNION ALL SELECT 'sellers',       COUNT(*) FROM (SELECT 1 FROM clean_sellers GROUP BY seller_id, seller_zip_code_prefix, seller_city, seller_state HAVING COUNT(*) > 1) x
UNION ALL SELECT 'order_reviews', COUNT(*) FROM (SELECT 1 FROM clean_order_reviews GROUP BY review_id, order_id, review_score, review_creation_date, review_answer_timestamp HAVING COUNT(*) > 1) x
UNION ALL SELECT 'products',      COUNT(*) FROM (SELECT 1 FROM clean_products GROUP BY product_id, product_category_name, product_name_length, product_description_length, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm HAVING COUNT(*) > 1) x
UNION ALL SELECT 'category_translation', COUNT(*) FROM (SELECT 1 FROM clean_category_translation GROUP BY product_category_name, product_category_name_english HAVING COUNT(*) > 1) x
UNION ALL SELECT 'marketing_qualified_leads', COUNT(*) FROM (SELECT 1 FROM clean_marketing_qualified_leads GROUP BY mql_id, first_contact_date, landing_page_id, origin HAVING COUNT(*) > 1) x
UNION ALL SELECT 'closed_deals',  COUNT(*) FROM (SELECT 1 FROM clean_closed_deals GROUP BY mql_id, seller_id, sdr_id, sr_id, won_date, business_segment, lead_type, lead_behaviour_profile, has_company, has_gtin, average_stock, business_type, declared_product_catalog_size, declared_monthly_revenue HAVING COUNT(*) > 1) x;


/* 7.2 hidden duplicates, same content but different id
   A row can be a copy even with a different id, so we group by everything
   except the id. Only the reviews turned out to be real duplicates
   (24, fixed in 7.5). The rest:
   - products: 431 groups of identical attributes, but 429 belong to one
     seller, the same item listed several times (colours/sizes) and each
     has its own sales. Separate listings, kept.
   - order_items: buying 2 units creates 2 lines, that's quantity and not
     duplication. Kept.
   - leads: lots of different businesses sign up the same day through the
     same page. Kept. */
SELECT 'reviews: same order+score+dates' AS check_name, COUNT(*) AS groups_found
FROM (SELECT 1 FROM clean_order_reviews GROUP BY order_id, review_score, review_creation_date, review_answer_timestamp HAVING COUNT(*) > 1) x
UNION ALL SELECT 'products: identical attributes',
       COUNT(*) FROM (SELECT 1 FROM clean_products WHERE product_category_name IS NOT NULL GROUP BY product_category_name, product_name_length, product_description_length, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm HAVING COUNT(*) > 1) x
UNION ALL SELECT 'order_items: same order+product+seller',
       COUNT(*) FROM (SELECT 1 FROM clean_order_items GROUP BY order_id, product_id, seller_id HAVING COUNT(*) > 1) x
UNION ALL SELECT 'leads: same day+page+channel',
       COUNT(*) FROM (SELECT 1 FROM clean_marketing_qualified_leads GROUP BY first_contact_date, landing_page_id, origin HAVING COUNT(*) > 1) x
UNION ALL SELECT 'orders: same customer+time+status',
       COUNT(*) FROM (SELECT 1 FROM clean_orders GROUP BY customer_id, order_purchase_timestamp, order_status HAVING COUNT(*) > 1) x;

-- two of the duplicate reviews: same order, same score, same dates to the
-- minute, only the review_id is different
SELECT r.*
FROM clean_order_reviews r
JOIN (SELECT order_id FROM clean_order_reviews
      GROUP BY order_id, review_score, review_creation_date, review_answer_timestamp
      HAVING COUNT(*) > 1 LIMIT 2) d ON d.order_id = r.order_id
ORDER BY r.order_id;


/* 7.3 same value written two ways
   e.g. 'delivered' vs 'Delivered ' would count as two values.
   COLLATE utf8mb4_bin counts the values exactly and LOWER(TRIM()) counts
   them after standardising, so if the two counts differ there are
   variants. Should be 0 for every column. */
SELECT 'order_status' AS col, COUNT(DISTINCT order_status COLLATE utf8mb4_bin) - COUNT(DISTINCT LOWER(TRIM(order_status))) AS variants FROM clean_orders
UNION ALL SELECT 'seller_state',          COUNT(DISTINCT seller_state COLLATE utf8mb4_bin) - COUNT(DISTINCT UPPER(TRIM(seller_state))) FROM clean_sellers
UNION ALL SELECT 'product_category_name', COUNT(DISTINCT product_category_name COLLATE utf8mb4_bin) - COUNT(DISTINCT LOWER(TRIM(product_category_name))) FROM clean_products
UNION ALL SELECT 'origin',                COUNT(DISTINCT origin COLLATE utf8mb4_bin) - COUNT(DISTINCT LOWER(TRIM(origin))) FROM clean_marketing_qualified_leads
UNION ALL SELECT 'business_segment',      COUNT(DISTINCT business_segment COLLATE utf8mb4_bin) - COUNT(DISTINCT LOWER(TRIM(business_segment))) FROM clean_closed_deals
UNION ALL SELECT 'lead_type',             COUNT(DISTINCT lead_type COLLATE utf8mb4_bin) - COUNT(DISTINCT LOWER(TRIM(lead_type))) FROM clean_closed_deals
UNION ALL SELECT 'english category name', COUNT(*) - COUNT(DISTINCT product_category_name_english) FROM clean_category_translation;

/* hidden spaces at the start or end of a value ('pet ' vs 'pet')
   The check above can miss these because MySQL ignores trailing spaces
   when comparing text. LENGTH counts every character so if trimming
   changes the length there was a hidden space. Should be 0 everywhere. */
SELECT 'seller_city' AS col, SUM(LENGTH(seller_city) <> LENGTH(TRIM(seller_city))) AS values_with_spaces FROM clean_sellers
UNION ALL SELECT 'seller_state',          SUM(LENGTH(seller_state) <> LENGTH(TRIM(seller_state))) FROM clean_sellers
UNION ALL SELECT 'order_status',          SUM(LENGTH(order_status) <> LENGTH(TRIM(order_status))) FROM clean_orders
UNION ALL SELECT 'product_category_name', SUM(LENGTH(product_category_name) <> LENGTH(TRIM(product_category_name))) FROM clean_products
UNION ALL SELECT 'category_name_english', SUM(LENGTH(product_category_name_english) <> LENGTH(TRIM(product_category_name_english))) FROM clean_category_translation
UNION ALL SELECT 'origin',                SUM(LENGTH(origin) <> LENGTH(TRIM(origin))) FROM clean_marketing_qualified_leads
UNION ALL SELECT 'business_segment',      SUM(LENGTH(business_segment) <> LENGTH(TRIM(business_segment))) FROM clean_closed_deals
UNION ALL SELECT 'lead_type',             SUM(LENGTH(lead_type) <> LENGTH(TRIM(lead_type))) FROM clean_closed_deals;


/* 7.4 duplicated columns
   (a) is any column name used in more than one table?
   5 names show up (mql_id, order_id, product_category_name, product_id,
   seller_id) and all of them are keys linking two tables. That's intended,
   a foreign key has to repeat the key it points to. No descriptive column
   (city, price, date) is stored twice. */
SELECT column_name, GROUP_CONCAT(table_name ORDER BY table_name) AS in_tables
FROM information_schema.columns
WHERE table_schema = DATABASE() AND table_name LIKE 'clean%'
GROUP BY column_name
HAVING COUNT(*) > 1;

/* (b) information stored twice inside a table
   A seller's zip code already tells you the state, because Brazilian zip
   codes are handed out in fixed ranges per state (e.g. 80000-87999 is
   Parana). So seller_state repeats what is in seller_zip_code_prefix (a
   transitive dependency: seller_id -> zip -> state). When the same fact
   is stored twice the copies can contradict each other, so we check.

   First a small reference table with the official ranges (Correios). */
DROP TABLE IF EXISTS zip_state_ranges;
CREATE TABLE zip_state_ranges (
    state    CHAR(2) NOT NULL,
    zip_from CHAR(5) NOT NULL,
    zip_to   CHAR(5) NOT NULL
);
INSERT INTO zip_state_ranges (state, zip_from, zip_to) VALUES
 ('SP','01000','19999'), ('RJ','20000','28999'), ('ES','29000','29999'), ('MG','30000','39999'),
 ('BA','40000','48999'), ('SE','49000','49999'), ('PE','50000','56999'), ('AL','57000','57999'),
 ('PB','58000','58999'), ('RN','59000','59999'), ('CE','60000','63999'), ('PI','64000','64999'),
 ('MA','65000','65999'), ('PA','66000','68899'), ('AP','68900','68999'), ('AM','69000','69299'),
 ('RR','69300','69399'), ('AM','69400','69899'), ('AC','69900','69999'), ('DF','70000','72799'),
 ('GO','72800','72999'), ('DF','73000','73699'), ('GO','73700','76799'), ('RO','76800','76999'),
 ('TO','77000','77999'), ('MT','78000','78899'), ('RO','78900','78999'), ('MS','79000','79999'),
 ('PR','80000','87999'), ('SC','88000','89999'), ('RS','90000','99999');

-- every seller's zip should fall in exactly one range
SELECT SUM(n = 0) AS sellers_without_range, SUM(n > 1) AS sellers_in_two_ranges
FROM (SELECT s.seller_id, COUNT(r.state) AS n
      FROM clean_sellers s
      LEFT JOIN zip_state_ranges r ON s.seller_zip_code_prefix BETWEEN r.zip_from AND r.zip_to
      GROUP BY s.seller_id) x;

-- check: sellers whose state contradicts their zip code.
-- 35 sellers, 33 of them say 'SP' (e.g. a seller in Curitiba with a
-- Curitiba zip, PR, recorded as SP). SP looks like a default value that
-- was never changed, and the city usually agrees with the zip.
SELECT s.seller_id, s.seller_zip_code_prefix, s.seller_city,
       s.seller_state AS recorded_state, r.state AS state_from_zip
FROM clean_sellers s
JOIN zip_state_ranges r ON s.seller_zip_code_prefix BETWEEN r.zip_from AND r.zip_to
WHERE s.seller_state <> r.state
ORDER BY s.seller_zip_code_prefix;


/* 7.5 fix: duplicate reviews
   24 orders have two review rows with the same score, creation date and
   answer time to the minute, only the review_id differs. In 22 of them
   even the comment is identical, so it's the same review recorded twice.
   Left in, those orders would count twice in a seller's average score.
   Rule: keep one row per group (the lowest review_id, so the result is
   the same every time) and delete the others. */
DELETE r
FROM clean_order_reviews r
JOIN (SELECT order_id, review_score, review_creation_date, review_answer_timestamp,
             MIN(review_id) AS keep_id
      FROM clean_order_reviews
      GROUP BY order_id, review_score, review_creation_date, review_answer_timestamp
      HAVING COUNT(*) > 1) d
  ON  r.order_id                = d.order_id
  AND r.review_score            = d.review_score
  AND r.review_creation_date    = d.review_creation_date
  AND r.review_answer_timestamp = d.review_answer_timestamp
WHERE r.review_id <> d.keep_id;

-- verify: 24 rows fewer and no duplicate groups left
SELECT COUNT(*) AS review_rows,
       (SELECT COUNT(*) FROM (SELECT 1 FROM clean_order_reviews
                              GROUP BY order_id, review_score, review_creation_date, review_answer_timestamp
                              HAVING COUNT(*) > 1) x) AS duplicate_groups_left
FROM clean_order_reviews;


/* 7.6 fix: states that contradict the zip code
   Which one is right, the state or the zip? The zip wins, because it's a
   structured code from an official range and the city name agrees with
   it. One exception: if the city name points to the recorded state
   instead (other sellers with that city have zips in the recorded state)
   the evidence is split, so we leave it.

   Step 1: build the list of corrections in its own table so every change
   is documented (like city_corrections in step 2). */
DROP TABLE IF EXISTS state_corrections;
CREATE TABLE state_corrections AS
SELECT s.seller_id, s.seller_zip_code_prefix, s.seller_city,
       s.seller_state AS old_state, r.state AS new_state
FROM clean_sellers s
JOIN zip_state_ranges r ON s.seller_zip_code_prefix BETWEEN r.zip_from AND r.zip_to
WHERE s.seller_state <> r.state
  AND NOT EXISTS (                       -- exception: city agrees with the recorded state
        SELECT 1
        FROM clean_sellers s2
        JOIN zip_state_ranges r2 ON s2.seller_zip_code_prefix BETWEEN r2.zip_from AND r2.zip_to
        WHERE s2.seller_city = s.seller_city
          AND s2.seller_id  <> s.seller_id
          AND r2.state       = s.seller_state);

-- 34 corrections. The exception is zip 37540, city "sao paulo", recorded
-- SP: the zip says MG but the city says SP so it stays as SP.
SELECT old_state, new_state, COUNT(*) AS sellers
FROM state_corrections
GROUP BY old_state, new_state
ORDER BY sellers DESC;

-- step 2: apply them
UPDATE clean_sellers s
JOIN state_corrections c ON c.seller_id = s.seller_id
SET s.seller_state = c.new_state;

-- step 3: one city still ends with its state code, "aguas claras df".
-- Fix A2 in step 2.4 only removed a code matching the recorded state and
-- this seller was recorded as SP. Now the state is DF so the same rule
-- catches it.
UPDATE clean_sellers
SET seller_city = TRIM(REGEXP_REPLACE(seller_city, CONCAT('[ -]+', LOWER(seller_state), '$'), ''))
WHERE seller_city REGEXP CONCAT('[ -]+', LOWER(seller_state), '$');

-- step 4: three sellers typed their state name as their city. The city
-- comes from other sellers with the same zip prefix.
-- (INSERT IGNORE skips rows already in the table so running the script
-- twice doesn't stop with a duplicate entry error)
INSERT IGNORE INTO city_corrections VALUES
 ('minas gerais',   'campo do meio', 'state name typed as city; other seller with ZIP 37165 is in campo do meio'),
 ('parana',         'maringa',       'state name typed as city; other sellers with ZIP 87083 are in maringa'),
 ('santa catarina', 'palhoca',       'state name typed as city; other sellers with ZIP 88135 are in palhoca');
UPDATE clean_sellers s
JOIN city_corrections c ON s.seller_city COLLATE utf8mb4_bin = c.wrong_city
SET s.seller_city = c.correct_city;


/* verify
   Only 1 contradiction should be left (the exception, zip 37540). SP goes
   from 1,849 to 1,817 sellers and we end up with 22 states instead of 23
   (the only "PA" seller was really in PR). */
SELECT COUNT(*) AS contradictions_left
FROM clean_sellers s
JOIN zip_state_ranges r ON s.seller_zip_code_prefix BETWEEN r.zip_from AND r.zip_to
WHERE s.seller_state <> r.state;

SELECT seller_state, COUNT(*) AS sellers
FROM clean_sellers
GROUP BY seller_state
ORDER BY sellers DESC;

/* how many of our 1,351 study sellers were affected?
   11. Small, but each one was in the wrong state (mostly counted as SP)
   which would have distorted the regional comparison. */
SELECT COUNT(DISTINCT c.seller_id) AS eligible_sellers_corrected
FROM state_corrections c
WHERE c.seller_id IN (SELECT i.seller_id
                      FROM clean_order_items i
                      JOIN clean_orders o ON o.order_id = i.order_id
                      WHERE o.order_status = 'delivered'
                        AND o.order_purchase_timestamp >= '2018-01-01'
                        AND o.order_purchase_timestamp <  '2018-04-01');


/* 7.7 other impossible values (flag only)
   Checking for duplicates also means asking whether one event has two
   contradicting dates. Three more problems, all in columns the analysis
   doesn't use, so the rows are kept and noted:

   a) shipping_limit_date in 2020 for orders placed in 2017, 4 item lines
      (3 orders), a seller deadline 3 years after the purchase
   b) a review dated before its order was placed, 64 links. 40 of them are
      reviews shared by several orders (5.5), the review belongs to an
      earlier order and was also attached to a later one
   c) declared_monthly_revenue of R$50,000,000 for a seller with 10
      products, not believable. If revenue is ever used, use the median
      and not the average. */
SELECT
  (SELECT COUNT(*) FROM clean_order_items WHERE shipping_limit_date >= '2019-01-01') AS shipping_limit_after_2018,
  (SELECT COUNT(*) FROM clean_order_reviews r JOIN clean_orders o ON o.order_id = r.order_id
    WHERE r.review_creation_date < DATE(o.order_purchase_timestamp))               AS review_before_purchase,
  (SELECT COUNT(*) FROM clean_closed_deals WHERE declared_monthly_revenue >= 10000000) AS revenue_10m_or_more;


/* 7.8 two small consistency fixes
   a) average_stock: 4 deals say 'unknown' while 776 are NULL, both mean
      not known. Same rule as 6.3/6.8, in columns we don't group by
      unknown becomes NULL.
   b) business_segment 'jewerly' is a misspelling of 'jewelry' (it could
      show up as a label in Tableau). */
UPDATE clean_closed_deals SET average_stock    = NULL      WHERE average_stock = 'unknown';
UPDATE clean_closed_deals SET business_segment = 'jewelry' WHERE business_segment = 'jewerly';
