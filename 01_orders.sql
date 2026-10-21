/* Step 1: orders (raw_orders -> clean_orders)
   Same pattern in every step: check the problem, fix it, verify. */
USE olist;
SET SQL_SAFE_UPDATES = 0;

-- 1.1 work on a copy so raw_orders stays as loaded
DROP TABLE IF EXISTS clean_orders;
CREATE TABLE clean_orders AS SELECT * FROM raw_orders;
DESCRIBE clean_orders;

/* 1.2 duplicates
   order_id should be unique, one row per order */
SELECT COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids
FROM clean_orders;


/* 1.3 IDs are well formed
   every Olist id is 32 characters of 0-9 and a-f */
SELECT SUM(order_id    NOT REGEXP '^[0-9a-f]{32}$') AS bad_order_ids,
       SUM(customer_id NOT REGEXP '^[0-9a-f]{32}$') AS bad_customer_ids
FROM clean_orders;


/* 1.4 order status
   8 values, all lower case: delivered, shipped, canceled, unavailable,
   invoiced, processing, created, approved */
SELECT order_status, COUNT(*) AS orders
FROM clean_orders
GROUP BY order_status
ORDER BY orders DESC;

-- precaution: trim and lower case the status (it was already consistent)
UPDATE clean_orders
SET order_status = LOWER(TRIM(order_status))
WHERE order_status <> LOWER(TRIM(order_status)) COLLATE utf8mb4_bin;


/* 1.5 missing dates stored as empty text
   An empty string is not a date, it has to be NULL before the column can
   become a DATETIME. The blanks mean that step never happened, e.g. a
   cancelled order was never delivered. */
SELECT SUM(order_purchase_timestamp      = '') AS blank_purchase,
       SUM(order_approved_at             = '') AS blank_approved,
       SUM(order_delivered_carrier_date  = '') AS blank_carrier,
       SUM(order_delivered_customer_date = '') AS blank_delivered,
       SUM(order_estimated_delivery_date = '') AS blank_estimated
FROM clean_orders;

-- empty text to NULL
UPDATE clean_orders SET order_approved_at             = NULL WHERE order_approved_at             = '';
UPDATE clean_orders SET order_delivered_carrier_date  = NULL WHERE order_delivered_carrier_date  = '';
UPDATE clean_orders SET order_delivered_customer_date = NULL WHERE order_delivered_customer_date = '';


/* 1.6 dates from text to DATETIME
   As text, dates sort like words so we could not filter by quarter.
   First check every value is YYYY-MM-DD HH:MM:SS. */
SELECT SUM(order_purchase_timestamp      NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_purchase,
       SUM(order_approved_at             NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_approved,
       SUM(order_delivered_carrier_date  NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_carrier,
       SUM(order_delivered_customer_date NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_delivered,
       SUM(order_estimated_delivery_date NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_estimated
FROM clean_orders;

-- set the data types (ids are always 32 characters so CHAR(32))
ALTER TABLE clean_orders
    MODIFY order_id                      CHAR(32)    NOT NULL,
    MODIFY customer_id                   CHAR(32)    NOT NULL,
    MODIFY order_status                  VARCHAR(20) NOT NULL,
    MODIFY order_purchase_timestamp      DATETIME    NOT NULL,
    MODIFY order_approved_at             DATETIME    NULL,
    MODIFY order_delivered_carrier_date  DATETIME    NULL,
    MODIFY order_delivered_customer_date DATETIME    NULL,
    MODIFY order_estimated_delivery_date DATETIME    NOT NULL;

DESCRIBE clean_orders;


/* 1.7 does the data cover our two quarters?
   Orders run from 2016-09 to 2018-10. Jan to Jun 2018 has roughly the same
   number of orders each month, so Q1 (baseline) and Q2 (follow-up) are
   both fully covered. Sep and Oct 2018 are an incomplete tail, outside
   our window. */
SELECT MIN(order_purchase_timestamp) AS first_order,
       MAX(order_purchase_timestamp) AS last_order
FROM clean_orders;

SELECT DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
       COUNT(*) AS orders
FROM clean_orders
WHERE order_purchase_timestamp >= '2018-01-01'
GROUP BY purchase_month
ORDER BY purchase_month;


/* 1.8 logical date checks (flag only, nothing is changed)
   Some orders were handed to the carrier before they were purchased
   (166) or delivered before the carrier got them (23). We can't know the
   real dates and we only use the purchase date and the status, so the
   rows stay and this goes in as a limitation. Deleting them would also
   delete real sales. */
SELECT SUM(order_approved_at             < order_purchase_timestamp)     AS approved_before_purchase,
       SUM(order_delivered_carrier_date  < order_purchase_timestamp)     AS carrier_before_purchase,
       SUM(order_delivered_customer_date < order_purchase_timestamp)     AS delivered_before_purchase,
       SUM(order_delivered_customer_date < order_delivered_carrier_date) AS delivered_before_carrier
FROM clean_orders;

SELECT order_id, order_purchase_timestamp, order_delivered_carrier_date
FROM clean_orders
WHERE order_delivered_carrier_date < order_purchase_timestamp
LIMIT 10;


/* 1.9 status vs delivery date (flag only)
   A few orders are 'delivered' with no delivery date (8) or have a
   delivery date but another status (6). We use the status as the rule for
   a completed sale since it is the platform's own outcome. 14 orders out
   of 99,441 won't change any result. */
SELECT SUM(order_status = 'delivered'  AND order_delivered_customer_date IS NULL)     AS delivered_without_date,
       SUM(order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL) AS date_but_not_delivered
FROM clean_orders;


/* 1.10 verify, no rows should be removed */
SELECT COUNT(*)                                AS row_count,
       SUM(order_approved_at IS NULL)             AS null_approved,
       SUM(order_delivered_carrier_date IS NULL)  AS null_carrier,
       SUM(order_delivered_customer_date IS NULL) AS null_delivered
FROM clean_orders;
