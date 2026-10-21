/* Step 8: final checks before handing the clean tables to the team
   Run after scripts 01-07. Nothing is changed here, these queries are
   the evidence for the report that cleaning didn't lose or invent data. */
USE olist;

/* 8.1 row counts, raw vs clean
   The only rows deleted were the 24 duplicate reviews (7.5). Choosing
   which orders count (delivered, Jan-Jun 2018) happens later in the
   summary table and not in cleaning, so the database stays complete and
   the filter is in one place.
   Counts should match for every table except order_reviews (99,224 to
   99,200) and category_translation (71 to 73, two categories added in 3.10). */
SELECT 'orders' AS table_name, (SELECT COUNT(*) FROM raw_orders) AS raw_rows, (SELECT COUNT(*) FROM clean_orders) AS clean_rows
UNION ALL SELECT 'order_items', (SELECT COUNT(*) FROM raw_order_items), (SELECT COUNT(*) FROM clean_order_items)
UNION ALL SELECT 'sellers',     (SELECT COUNT(*) FROM raw_sellers),     (SELECT COUNT(*) FROM clean_sellers)
UNION ALL SELECT 'order_reviews', (SELECT COUNT(*) FROM raw_order_reviews), (SELECT COUNT(*) FROM clean_order_reviews)
UNION ALL SELECT 'products',    (SELECT COUNT(*) FROM raw_products),    (SELECT COUNT(*) FROM clean_products)
UNION ALL SELECT 'category_translation', (SELECT COUNT(*) FROM raw_category_translation), (SELECT COUNT(*) FROM clean_category_translation)
UNION ALL SELECT 'marketing_qualified_leads', (SELECT COUNT(*) FROM raw_marketing_qualified_leads), (SELECT COUNT(*) FROM clean_marketing_qualified_leads)
UNION ALL SELECT 'closed_deals', (SELECT COUNT(*) FROM raw_closed_deals), (SELECT COUNT(*) FROM clean_closed_deals);


/* 8.2 final column types of every clean table (for the logical model /
   data dictionary in the report) */
SELECT table_name, column_name, column_type, is_nullable
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name LIKE 'clean%'
ORDER BY table_name, ordinal_position;


/* 8.3 the keys the database needs hold in the clean data, all should be 0 */
SELECT
  (SELECT COUNT(*) - COUNT(DISTINCT order_id)                 FROM clean_orders)        AS dup_pk_orders,
  (SELECT COUNT(*) - COUNT(DISTINCT order_id, order_item_id)  FROM clean_order_items)   AS dup_pk_order_items,
  (SELECT COUNT(*) - COUNT(DISTINCT seller_id)                FROM clean_sellers)       AS dup_pk_sellers,
  (SELECT COUNT(*) - COUNT(DISTINCT product_id)               FROM clean_products)      AS dup_pk_products,
  (SELECT COUNT(*) - COUNT(DISTINCT review_id, order_id)      FROM clean_order_reviews) AS dup_pk_reviews,
  (SELECT COUNT(*) - COUNT(DISTINCT product_category_name)    FROM clean_category_translation) AS dup_pk_translation,
  (SELECT COUNT(*) - COUNT(DISTINCT mql_id)                   FROM clean_marketing_qualified_leads) AS dup_pk_mql,
  (SELECT COUNT(*) - COUNT(DISTINCT mql_id)                   FROM clean_closed_deals)  AS dup_pk_deals;


/* 8.4 total sales value is unchanged, the difference should be 0.00 */
SELECT (SELECT SUM(CAST(price AS DECIMAL(12,2))) FROM raw_order_items) AS raw_total,
       (SELECT SUM(price) FROM clean_order_items)                      AS clean_total,
       (SELECT SUM(CAST(price AS DECIMAL(12,2))) FROM raw_order_items)
     - (SELECT SUM(price) FROM clean_order_items)                      AS difference;


/* 8.5 remaining NULLs, all explained in the cleaning log:
   orders (approved, carrier, delivered dates), products (category 610,
   weight 6 = 2 missing + 4 that were 0 g) and closed_deals (monthly
   revenue 797, where 0 meant not declared) */
SELECT 'orders.order_approved_at' AS col, COUNT(*) AS nulls FROM clean_orders WHERE order_approved_at IS NULL
UNION ALL SELECT 'orders.order_delivered_carrier_date',  COUNT(*) FROM clean_orders WHERE order_delivered_carrier_date IS NULL
UNION ALL SELECT 'orders.order_delivered_customer_date', COUNT(*) FROM clean_orders WHERE order_delivered_customer_date IS NULL
UNION ALL SELECT 'products.product_category_name',       COUNT(*) FROM clean_products WHERE product_category_name IS NULL
UNION ALL SELECT 'products.product_weight_g',            COUNT(*) FROM clean_products WHERE product_weight_g IS NULL
UNION ALL SELECT 'closed_deals.declared_monthly_revenue', COUNT(*) FROM clean_closed_deals WHERE declared_monthly_revenue IS NULL;
