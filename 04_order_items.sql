/* =====================================================================
   STEP 4: ORDER ITEMS   (raw_order_items -> clean_order_items)
   This table links orders to sellers and products, and holds the price.
   It is the source of every sales number in our analysis.
   Run steps 1-3 first: the link checks below use those clean tables.
   ===================================================================== */
USE olist;
SET SQL_SAFE_UPDATES = 0;

DROP TABLE IF EXISTS clean_order_items;
CREATE TABLE clean_order_items AS SELECT * FROM raw_order_items;


/* 4.1 Duplicates. One row = one item line of an order, identified by
   (order_id, order_item_id) together.  Expected: 112,650 rows, 0 duplicates */
SELECT COUNT(*) AS item_rows,
       COUNT(*) - COUNT(DISTINCT order_id, order_item_id) AS duplicate_lines
FROM clean_order_items;


/* 4.2 Blanks and formats.  Expected: 0 in every column */
SELECT SUM(order_id   NOT REGEXP '^[0-9a-f]{32}$') AS bad_order_ids,
       SUM(product_id NOT REGEXP '^[0-9a-f]{32}$') AS bad_product_ids,
       SUM(seller_id  NOT REGEXP '^[0-9a-f]{32}$') AS bad_seller_ids,
       SUM(order_item_id NOT REGEXP '^[0-9]+$')    AS bad_item_numbers,
       SUM(shipping_limit_date NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_dates,
       SUM(price         NOT REGEXP '^[0-9]+(\\.[0-9]{1,2})?$') AS bad_prices,
       SUM(freight_value NOT REGEXP '^[0-9]+(\\.[0-9]{1,2})?$') AS bad_freight
FROM clean_order_items;

-- Set data types. Money is DECIMAL, not FLOAT, so totals add up exactly.
ALTER TABLE clean_order_items
    MODIFY order_id            CHAR(32)      NOT NULL,
    MODIFY order_item_id       INT           NOT NULL,
    MODIFY product_id          CHAR(32)      NOT NULL,
    MODIFY seller_id           CHAR(32)      NOT NULL,
    MODIFY shipping_limit_date DATETIME      NOT NULL,
    MODIFY price               DECIMAL(10,2) NOT NULL,
    MODIFY freight_value       DECIMAL(10,2) NOT NULL;


/* 4.3 Value ranges.
   Expected: price R$0.85 to R$6,735.00, none at 0 or below;
             freight R$0.00 to R$409.68, 383 lines with R$0.00 freight;
             order_item_id 1 to 21.
   Decision: R$0 freight is kept, because free shipping is a normal
   commercial offer, not an error. Prices are all positive, so nothing
   to fix. We use price only (not freight) as the seller's sales value,
   because freight is a delivery cost, not merchandise sold. */
SELECT MIN(price) AS min_price, MAX(price) AS max_price, SUM(price <= 0) AS price_zero_or_less,
       MIN(freight_value) AS min_freight, MAX(freight_value) AS max_freight,
       SUM(freight_value = 0) AS free_freight_lines,
       MIN(order_item_id) AS min_item_no, MAX(order_item_id) AS max_item_no
FROM clean_order_items;

/* Note for the report: order_item_id is the line number inside an order
   (1st item, 2nd item, ...), not a quantity. So "number of orders" must be
   counted with COUNT(DISTINCT order_id), otherwise an order with 3 items
   would be counted 3 times. */


/* 4.4 Referential integrity: does every item point to an existing
   order, seller and product?  Expected: 0, 0, 0  */
SELECT
  (SELECT COUNT(*) FROM clean_order_items i LEFT JOIN clean_orders   o ON o.order_id   = i.order_id   WHERE o.order_id   IS NULL) AS items_without_order,
  (SELECT COUNT(*) FROM clean_order_items i LEFT JOIN clean_sellers  s ON s.seller_id  = i.seller_id  WHERE s.seller_id  IS NULL) AS items_without_seller,
  (SELECT COUNT(*) FROM clean_order_items i LEFT JOIN clean_products p ON p.product_id = i.product_id WHERE p.product_id IS NULL) AS items_without_product;

/* And the other way round: orders with no items.
   Expected: 775 orders, by status: unavailable 603 | canceled 164 |
   created 5 | invoiced 2 | shipped 1. None are 'delivered', so they can
   never count as a sale. We keep them (they are real orders). */
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM clean_orders o
LEFT JOIN clean_order_items i ON i.order_id = o.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

/* Every seller in the sellers table has at least one item.  Expected: 0 */
SELECT COUNT(*) AS sellers_without_items
FROM clean_sellers s
LEFT JOIN (SELECT DISTINCT seller_id FROM clean_order_items) i ON i.seller_id = s.seller_id
WHERE i.seller_id IS NULL;


/* 4.5 VERIFY: totals are unchanged by cleaning (reconciliation).
   Expected: 112,650 rows; total price R$13,591,643.70 in both tables.  */
SELECT (SELECT COUNT(*) FROM clean_order_items)                       AS clean_rows,
       (SELECT SUM(CAST(price AS DECIMAL(12,2))) FROM raw_order_items) AS raw_total_price,
       (SELECT SUM(price) FROM clean_order_items)                      AS clean_total_price;

/* 4.6 Sanity check on our study window (same rule the summary table
   uses): delivered orders purchased 1 Jan - 31 Mar 2018.
   Expected: 1,351 sellers, R$2,704,438.38 of merchandise value. */
SELECT COUNT(DISTINCT i.seller_id) AS eligible_sellers,
       SUM(i.price)                AS baseline_value_brl
FROM clean_order_items i
JOIN clean_orders o ON o.order_id = i.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2018-01-01'
  AND o.order_purchase_timestamp <  '2018-04-01';
