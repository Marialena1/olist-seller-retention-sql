/* Step 10: region table, seller retention summary, foreign keys
   Database: olist_ecommerce (run after 09)

   10.1 region_state: state code to Brazilian region
   10.2 seller_retention_summary: one row per seller who sold in Q1 2018
   10.3 foreign keys from the ERD
   10.4 checks

   Run it once. If something stops halfway, re-run Krish's OlistDb2.sql,
   then 09, then this script (that resets all tables including the
   foreign keys). */
USE olist_ecommerce;
SET SQL_SAFE_UPDATES = 0;

-- start clean if the script is run a second time (order matters, the
-- summary points to sellers and sellers will point to region_state)
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS seller_retention_summary;
DROP TABLE IF EXISTS region_state;
SET FOREIGN_KEY_CHECKS = 1;


/* 10.1 region_state
   Brazil's 27 states (26 plus the Federal District) in the 5 IBGE
   regions. A state determines its region, so the region is stored here
   once and not repeated on every seller row (3NF).
   COLLATE utf8mb4_unicode_ci is there because a foreign key needs the
   same character set and collation on both columns, and Krish's tables
   use utf8mb4_unicode_ci. */
CREATE TABLE region_state (
    state_code  CHAR(2)     NOT NULL,
    state_name  VARCHAR(30) NOT NULL,
    region_name VARCHAR(20) NOT NULL,
    PRIMARY KEY (state_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO region_state (state_code, state_name, region_name) VALUES
 ('AC','Acre','North'), ('AP','Amapa','North'), ('AM','Amazonas','North'), ('PA','Para','North'),
 ('RO','Rondonia','North'), ('RR','Roraima','North'), ('TO','Tocantins','North'),
 ('AL','Alagoas','Northeast'), ('BA','Bahia','Northeast'), ('CE','Ceara','Northeast'),
 ('MA','Maranhao','Northeast'), ('PB','Paraiba','Northeast'), ('PE','Pernambuco','Northeast'),
 ('PI','Piaui','Northeast'), ('RN','Rio Grande do Norte','Northeast'), ('SE','Sergipe','Northeast'),
 ('DF','Distrito Federal','Central-West'), ('GO','Goias','Central-West'),
 ('MT','Mato Grosso','Central-West'), ('MS','Mato Grosso do Sul','Central-West'),
 ('ES','Espirito Santo','Southeast'), ('MG','Minas Gerais','Southeast'),
 ('RJ','Rio de Janeiro','Southeast'), ('SP','Sao Paulo','Southeast'),
 ('PR','Parana','South'), ('RS','Rio Grande do Sul','South'), ('SC','Santa Catarina','South');

-- should be 27 states and 0 sellers with a state missing here
SELECT (SELECT COUNT(*) FROM region_state) AS states,
       (SELECT COUNT(*) FROM sellers s LEFT JOIN region_state r ON r.state_code = s.seller_state
         WHERE r.state_code IS NULL) AS sellers_without_region;


/* 10.2 seller_retention_summary
   One row per eligible seller, meaning at least one delivered order
   purchased in Q1 2018 (1 Jan to 31 Mar). Rules, same as in the cleaning log:
   - a sale only counts if order_status = 'delivered'
   - dates are >= start of the quarter and < start of the next quarter
   - orders are counted with COUNT(DISTINCT order_id), order_item_id is a
     line number and not a quantity
   - sales value is price only, freight excluded
   - sold_in_q2_2018 is 1 if the seller has at least one delivered order
     in Q2 2018 (1 Apr to 30 Jun), otherwise 0. No Q2 sale doesn't prove
     the seller left Olist.
   - main_category is the category with the most items sold in Q1 (tie:
     higher sales value, then alphabetical), 'unknown' if the product has
     no category
   - avg_review_score_q1 is the average over the seller's Q1 orders with
     one score per order (the average if an order has 2 reviews). Reviews
     dated before the order was placed are left out (see 7.7).
   Each measure is its own subquery, joined on seller_id at the end.
   Joining items and reviews directly would repeat rows and inflate the
   totals. */
CREATE TABLE seller_retention_summary (
    seller_id                CHAR(32)      NOT NULL,
    q1_2018_order_count      INT           NOT NULL,
    q1_2018_sales_value_brl  DECIMAL(12,2) NOT NULL,
    q2_2018_order_count      INT           NOT NULL,
    q2_2018_sales_value_brl  DECIMAL(12,2) NOT NULL,
    sold_in_q2_2018          TINYINT       NOT NULL,
    main_category            VARCHAR(100)  NOT NULL,
    avg_review_score_q1      DECIMAL(3,2)  NULL,
    PRIMARY KEY (seller_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO seller_retention_summary
WITH
-- delivered Q1 items per seller (one row per item)
q1_items AS (
    SELECT i.seller_id, i.order_id, i.product_id, i.price
    FROM order_items i
    JOIN orders o ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2018-01-01'
      AND o.order_purchase_timestamp <  '2018-04-01'
),
q1 AS (
    SELECT seller_id,
           COUNT(DISTINCT order_id) AS order_count,
           SUM(price)               AS sales_value
    FROM q1_items
    GROUP BY seller_id
),
q2 AS (
    SELECT i.seller_id,
           COUNT(DISTINCT i.order_id) AS order_count,
           SUM(i.price)               AS sales_value
    FROM order_items i
    JOIN orders o ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2018-04-01'
      AND o.order_purchase_timestamp <  '2018-07-01'
    GROUP BY i.seller_id
),
-- main category: rank the seller's categories by items sold in Q1
category_rank AS (
    SELECT q.seller_id,
           COALESCE(t.product_category_name_english, 'unknown') AS category,
           ROW_NUMBER() OVER (PARTITION BY q.seller_id
                              ORDER BY COUNT(*) DESC, SUM(q.price) DESC,
                                       COALESCE(t.product_category_name_english, 'unknown')) AS rn
    FROM q1_items q
    JOIN products p ON p.product_id = q.product_id
    LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name
    GROUP BY q.seller_id, COALESCE(t.product_category_name_english, 'unknown')
),
-- one review score per order (average if the order has 2+ reviews)
order_score AS (
    SELECT r.order_id, AVG(r.review_score) AS score
    FROM order_reviews r
    JOIN orders o ON o.order_id = r.order_id
    WHERE r.review_creation_date >= DATE(o.order_purchase_timestamp)
    GROUP BY r.order_id
),
q1_reviews AS (
    SELECT so.seller_id, AVG(os.score) AS avg_score
    FROM (SELECT DISTINCT seller_id, order_id FROM q1_items) so
    JOIN order_score os ON os.order_id = so.order_id
    GROUP BY so.seller_id
)
SELECT q1.seller_id,
       q1.order_count,
       q1.sales_value,
       COALESCE(q2.order_count, 0),
       COALESCE(q2.sales_value, 0),
       CASE WHEN q2.seller_id IS NULL THEN 0 ELSE 1 END,
       cr.category,
       ROUND(rv.avg_score, 2)
FROM q1
LEFT JOIN q2            ON q2.seller_id = q1.seller_id
JOIN category_rank cr   ON cr.seller_id = q1.seller_id AND cr.rn = 1
LEFT JOIN q1_reviews rv ON rv.seller_id = q1.seller_id;


/* 10.3 foreign keys
   A foreign key makes MySQL refuse any row that points to something that
   doesn't exist (e.g. an order item for a seller who isn't in sellers).
   The data was checked in cleaning so all of these are accepted.
   Not added: closed_deals.seller_id to sellers. Only 380 of the 842 deal
   sellers are in sellers (the others never sold), so that link is shown
   in the ERD as optional but not enforced. */
ALTER TABLE order_items
    ADD CONSTRAINT fk_items_order   FOREIGN KEY (order_id)   REFERENCES orders (order_id),
    ADD CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products (product_id),
    ADD CONSTRAINT fk_items_seller  FOREIGN KEY (seller_id)  REFERENCES sellers (seller_id);

ALTER TABLE order_reviews
    ADD CONSTRAINT fk_reviews_order FOREIGN KEY (order_id) REFERENCES orders (order_id);

ALTER TABLE products
    ADD CONSTRAINT fk_products_category FOREIGN KEY (product_category_name)
        REFERENCES category_translation (product_category_name);

ALTER TABLE closed_deals
    ADD CONSTRAINT fk_deals_lead FOREIGN KEY (mql_id) REFERENCES marketing_qualified_leads (mql_id);

ALTER TABLE sellers
    ADD CONSTRAINT fk_sellers_state FOREIGN KEY (seller_state) REFERENCES region_state (state_code);

ALTER TABLE seller_retention_summary
    ADD CONSTRAINT fk_summary_seller FOREIGN KEY (seller_id) REFERENCES sellers (seller_id);


/* 10.4 checks */

-- (a) the foreign keys now in the database
SELECT table_name, constraint_name, referenced_table_name
FROM information_schema.referential_constraints
WHERE constraint_schema = DATABASE()
ORDER BY table_name;

-- (b) summary totals
SELECT COUNT(*)                                  AS sellers,
       SUM(q1_2018_sales_value_brl)              AS q1_value,
       SUM(sold_in_q2_2018)                      AS sold_in_q2,
       ROUND(100 * AVG(sold_in_q2_2018), 1)      AS pct_sold_in_q2,
       SUM(avg_review_score_q1 IS NULL)          AS no_review_score
FROM seller_retention_summary;

-- (c) reconciliation: the summary's Q1 value should equal the value taken
-- straight from order_items (difference 0.00)
SELECT (SELECT SUM(q1_2018_sales_value_brl) FROM seller_retention_summary)
     - (SELECT SUM(i.price) FROM order_items i JOIN orders o ON o.order_id = i.order_id
         WHERE o.order_status = 'delivered'
           AND o.order_purchase_timestamp >= '2018-01-01'
           AND o.order_purchase_timestamp <  '2018-04-01') AS difference;

-- (d) first look by region (the state comes from sellers and region_state,
-- it isn't stored in the summary). North has only 1 seller and Northeast
-- 28, so in the analysis they are combined into one "North and Northeast"
-- group (29 sellers), as agreed earlier.
SELECT r.region_name,
       COUNT(*)                            AS sellers,
       SUM(s2.sold_in_q2_2018)             AS sold_in_q2,
       ROUND(100 * AVG(s2.sold_in_q2_2018), 1) AS pct_sold_in_q2
FROM seller_retention_summary s2
JOIN sellers s       ON s.seller_id = s2.seller_id
JOIN region_state r  ON r.state_code = s.seller_state
GROUP BY r.region_name
ORDER BY sellers DESC;
