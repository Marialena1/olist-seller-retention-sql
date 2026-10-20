/* =====================================================================
   STEP 12: FINAL CHECK BEFORE EXPORT  (read-only: changes nothing,
   safe to run as many times as you like)
   ===================================================================== */
USE olist_ecommerce;

-- 12.1 Tables and row counts.  Expected: 11 tables
-- category_translation 73 | closed_deals 842 | marketing_qualified_leads 8000 |
-- order_items 112650 | orders 99441 | products 32951 | region_state 27 |
-- review_orders 99200 | reviews 98396 | seller_retention_summary 1351 | sellers 3095
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

-- 12.2 Foreign keys.  Expected: 9 rows
-- closed_deals->marketing_qualified_leads, order_items->orders/products/sellers,
-- products->category_translation, review_orders->orders/reviews,
-- seller_retention_summary->sellers, sellers->region_state
SELECT table_name, constraint_name, referenced_table_name
FROM information_schema.referential_constraints
WHERE constraint_schema = DATABASE()
ORDER BY table_name, constraint_name;

-- 12.3 Key numbers.  Expected: 1351 | 2704438.38 | 1032 | 76.4 | 13591643.70
SELECT COUNT(*)                             AS summary_sellers,
       SUM(q1_2018_sales_value_brl)         AS q1_value,
       SUM(sold_in_q2_2018)                 AS sold_in_q2,
       ROUND(100 * AVG(sold_in_q2_2018), 1) AS pct_sold_in_q2,
       (SELECT SUM(price) FROM order_items) AS total_item_value
FROM seller_retention_summary;
