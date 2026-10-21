/* Step 12: final check before export
   Read only, changes nothing, safe to run as many times as needed. */
USE olist_ecommerce;

-- 12.1 tables and row counts (11 tables)
SELECT 'category_translation' AS table_name, COUNT(*) AS row_count FROM category_translation
UNION ALL SELECT 'closed_deals',              COUNT(*) FROM closed_deals
UNION ALL SELECT 'marketing_qualified_leads', COUNT(*) FROM marketing_qualified_leads
UNION ALL SELECT 'order_items',               COUNT(*) FROM order_items
UNION ALL SELECT 'orders',                    COUNT(*) FROM orders
UNION ALL SELECT 'products',                  COUNT(*) FROM products
UNION ALL SELECT 'region_state',              COUNT(*) FROM region_state
UNION ALL SELECT 'review_orders',             COUNT(*) FROM review_orders
UNION ALL SELECT 'reviews',                   COUNT(*) FROM reviews
UNION ALL SELECT 'seller_retention_summary',  COUNT(*) FROM seller_retention_summary
UNION ALL SELECT 'sellers',                   COUNT(*) FROM sellers;

-- 12.2 foreign keys (9 in total)
SELECT table_name, constraint_name, referenced_table_name
FROM information_schema.referential_constraints
WHERE constraint_schema = DATABASE()
ORDER BY table_name, constraint_name;

-- 12.3 key numbers
SELECT COUNT(*)                             AS summary_sellers,
       SUM(q1_2018_sales_value_brl)         AS q1_value,
       SUM(sold_in_q2_2018)                 AS sold_in_q2,
       ROUND(100 * AVG(sold_in_q2_2018), 1) AS pct_sold_in_q2,
       (SELECT SUM(price) FROM order_items) AS total_item_value
FROM seller_retention_summary;
