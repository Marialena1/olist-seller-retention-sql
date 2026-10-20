/* =====================================================================
   STEP 1: ORDERS   (raw_orders -> clean_orders)
   Pattern for every step: CHECK (look at the problem) -> FIX -> VERIFY.
   Write down the number each CHECK returns and the "rows affected"
   number Workbench shows in the Output panel for each FIX.
   ===================================================================== */
USE olist;
SET SQL_SAFE_UPDATES = 0;

-- 1.1 Work on a copy, so raw_orders stays exactly as loaded.
DROP TABLE IF EXISTS clean_orders;
CREATE TABLE clean_orders AS SELECT * FROM raw_orders;
DESCRIBE clean_orders;

/* ---------- 1.2 Duplicates ----------
   order_id should be unique (one row per order).  Expected: 0 */
SELECT COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_order_ids
FROM clean_orders;


/* ---------- 1.3 IDs are well-formed ----------
   Every Olist ID is 32 characters of 0-9 / a-f.  Expected: 0 and 0 */
SELECT SUM(order_id    NOT REGEXP '^[0-9a-f]{32}$') AS bad_order_ids,
       SUM(customer_id NOT REGEXP '^[0-9a-f]{32}$') AS bad_customer_ids
FROM clean_orders;


/* ---------- 1.4 Order status: allowed values ----------
   Expected 8 values, all lower case, no spaces:
   delivered 96,478 | shipped 1,107 | canceled 625 | unavailable 609 |
   invoiced 314 | processing 301 | created 5 | approved 2              */
SELECT order_status, COUNT(*) AS orders
FROM clean_orders
GROUP BY order_status
ORDER BY orders DESC;

-- FIX (precaution): standardise to trimmed lower case.
-- Expected: 0 rows affected, i.e. the column was already consistent.
UPDATE clean_orders
SET order_status = LOWER(TRIM(order_status))
WHERE order_status <> LOWER(TRIM(order_status)) COLLATE utf8mb4_bin;


/* ---------- 1.5 Missing dates stored as empty text ----------
   An empty string is not a date. MySQL needs NULL ("no value") before the
   column can become a DATETIME. Empty here means the step had not
   happened (yet), e.g. a cancelled order was never delivered.
   Expected: approved 160 | carrier 1,783 | delivered 2,965 | others 0 */
SELECT SUM(order_purchase_timestamp      = '') AS blank_purchase,
       SUM(order_approved_at             = '') AS blank_approved,
       SUM(order_delivered_carrier_date  = '') AS blank_carrier,
       SUM(order_delivered_customer_date = '') AS blank_delivered,
       SUM(order_estimated_delivery_date = '') AS blank_estimated
FROM clean_orders;

-- FIX: empty text -> NULL. (Expected rows affected: 160, 1783, 2965)
UPDATE clean_orders SET order_approved_at             = NULL WHERE order_approved_at             = '';
UPDATE clean_orders SET order_delivered_carrier_date  = NULL WHERE order_delivered_carrier_date  = '';
UPDATE clean_orders SET order_delivered_customer_date = NULL WHERE order_delivered_customer_date = '';


/* ---------- 1.6 Dates: text -> real DATETIME ----------
   Stored as text, dates sort and compare as words, so we could not filter
   "Jan-Mar 2018". First check every value has the format
   YYYY-MM-DD HH:MM:SS.  Expected: 0 in every column */
SELECT SUM(order_purchase_timestamp      NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_purchase,
       SUM(order_approved_at             NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_approved,
       SUM(order_delivered_carrier_date  NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_carrier,
       SUM(order_delivered_customer_date NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_delivered,
       SUM(order_estimated_delivery_date NOT REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$') AS bad_estimated
FROM clean_orders;

-- FIX: set proper data types (IDs are always 32 characters -> CHAR(32)).
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


/* ---------- 1.7 Does the data cover our two quarters? ----------
   Expected: first order 2016-09-04, last order 2018-10-17.
   Monthly counts for 2018: Jan 7,269 | Feb 6,728 | Mar 7,211 |
   Apr 6,939 | May 6,873 | Jun 6,167 | Jul 6,292 | Aug 6,512 |
   Sep 16 | Oct 4.
   -> Jan-Jun 2018 is complete and of similar size every month, so both
      our baseline (Q1) and follow-up (Q2) quarters are fully covered.
      Sep-Oct 2018 is an incomplete tail, which is outside our window. */
SELECT MIN(order_purchase_timestamp) AS first_order,
       MAX(order_purchase_timestamp) AS last_order
FROM clean_orders;

SELECT DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS purchase_month,
       COUNT(*) AS orders
FROM clean_orders
WHERE order_purchase_timestamp >= '2018-01-01'
GROUP BY purchase_month
ORDER BY purchase_month;


/* ---------- 1.8 Logical date checks (FLAG ONLY, we do not change these) ----------
   Expected:
     approved before purchase                 0
     handed to carrier before purchase      166
     delivered to customer before purchase    0
     delivered to customer before carrier    23
   We cannot know the true dates, and our analysis only uses the purchase
   date and the status, so we keep these rows and note them as a
   limitation. Deleting them would also delete real sales. */
SELECT SUM(order_approved_at             < order_purchase_timestamp)     AS approved_before_purchase,
       SUM(order_delivered_carrier_date  < order_purchase_timestamp)     AS carrier_before_purchase,
       SUM(order_delivered_customer_date < order_purchase_timestamp)     AS delivered_before_purchase,
       SUM(order_delivered_customer_date < order_delivered_carrier_date) AS delivered_before_carrier
FROM clean_orders;

SELECT order_id, order_purchase_timestamp, order_delivered_carrier_date
FROM clean_orders
WHERE order_delivered_carrier_date < order_purchase_timestamp
LIMIT 10;


/* ---------- 1.9 Status vs delivery date (FLAG ONLY) ----------
   Expected: 8 orders say 'delivered' but have no delivery date;
             6 orders have a delivery date but another status.
   Decision: the STATUS is our rule for a completed sale (status =
   'delivered'), because it is the platform's official outcome of the
   order. 14 orders out of 99,441 is too few to change any result. */
SELECT SUM(order_status = 'delivered'  AND order_delivered_customer_date IS NULL)     AS delivered_without_date,
       SUM(order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL) AS date_but_not_delivered
FROM clean_orders;


/* ---------- 1.10 VERIFY ----------
   Expected: 99,441 rows (no rows removed) and the NULL counts from 1.5. */
SELECT COUNT(*)                                AS row_count,
       SUM(order_approved_at IS NULL)             AS null_approved,
       SUM(order_delivered_carrier_date IS NULL)  AS null_carrier,
       SUM(order_delivered_customer_date IS NULL) AS null_delivered
FROM clean_orders;
