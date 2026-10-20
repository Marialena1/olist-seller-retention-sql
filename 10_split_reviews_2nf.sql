/* =====================================================================
   STEP 10: SPLIT order_reviews INTO reviews + review_orders (2NF)
   Database: olist_ecommerce

   The problem (Second Normal Form):
   order_reviews has a two-column key (review_id, order_id), but
   review_score, review_creation_date and review_answer_timestamp depend
   on review_id ALONE. When one review is linked to several orders, those
   values are repeated on every row. That is a partial dependency, which
   2NF does not allow.

   The fix: store each review once, and the review-order links separately.
     reviews       (review_id PK, review_score, review_creation_date,
                    review_answer_timestamp)          one row per review
     review_orders (review_id, order_id)  PK = both   one row per link
   Orders and reviews are many-to-many (an order can have 2 reviews, a
   review can cover 2 orders); review_orders is the link table between them.

   Run AFTER 09. (If you already ran the region/summary script, that is
   fine too: the summary's review scores are checked at the end.)
   ===================================================================== */
USE olist_ecommerce;
SET SQL_SAFE_UPDATES = 0;


/* ---------- 10.1 CHECK the dependency before splitting ----------
   If a review_id ever had two different scores or dates, splitting would
   lose information, so we prove it never happens.
   Expected: 779 review_ids linked to more than one order,
             0 with different scores, 0 with different dates. */
SELECT COUNT(*)                     AS reviews_on_several_orders,
       SUM(n_scores > 1)            AS with_different_scores,
       SUM(n_dates  > 1)            AS with_different_dates
FROM (SELECT review_id,
             COUNT(DISTINCT review_score) AS n_scores,
             COUNT(DISTINCT review_creation_date, review_answer_timestamp) AS n_dates
      FROM order_reviews
      GROUP BY review_id
      HAVING COUNT(*) > 1) x;


/* ---------- 10.2 Create the two new tables ----------
   Same character set and collation as the other tables, so the foreign
   keys work. The CHECK keeps scores between 1 and 5, as before. */
DROP TABLE IF EXISTS review_orders;
DROP TABLE IF EXISTS reviews;

CREATE TABLE reviews (
    review_id               CHAR(32) NOT NULL,
    review_score            TINYINT  NOT NULL,
    review_creation_date    DATETIME NOT NULL,
    review_answer_timestamp DATETIME NOT NULL,
    PRIMARY KEY (review_id),
    CONSTRAINT chk_reviews_score CHECK (review_score BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE review_orders (
    review_id CHAR(32) NOT NULL,
    order_id  CHAR(32) NOT NULL,
    PRIMARY KEY (review_id, order_id),
    CONSTRAINT fk_review_orders_review FOREIGN KEY (review_id) REFERENCES reviews (review_id),
    CONSTRAINT fk_review_orders_order  FOREIGN KEY (order_id)  REFERENCES orders (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


/* ---------- 10.3 Fill them ----------
   reviews: SELECT DISTINCT keeps one row per review (10.1 proved the
   repeated rows are identical).          Expected rows affected: 98,396
   review_orders: every (review, order) pair.  Expected: 99,200 */
INSERT INTO reviews (review_id, review_score, review_creation_date, review_answer_timestamp)
SELECT DISTINCT review_id, review_score, review_creation_date, review_answer_timestamp
FROM order_reviews;

INSERT INTO review_orders (review_id, order_id)
SELECT review_id, order_id
FROM order_reviews;


/* ---------- 10.4 VERIFY: nothing lost ----------
   Joining the two new tables back together must give exactly the old
   table: same number of rows and no row that differs.
   Expected: 98,396 | 99,200 | 99,200 | 0 */
SELECT (SELECT COUNT(*) FROM reviews)       AS reviews,
       (SELECT COUNT(*) FROM review_orders) AS review_orders,
       (SELECT COUNT(*) FROM review_orders ro JOIN reviews r ON r.review_id = ro.review_id) AS rebuilt_rows,
       (SELECT COUNT(*)
          FROM order_reviews o
          LEFT JOIN review_orders ro ON ro.review_id = o.review_id AND ro.order_id = o.order_id
          LEFT JOIN reviews r        ON r.review_id  = o.review_id
         WHERE ro.review_id IS NULL
            OR r.review_score            <> o.review_score
            OR r.review_creation_date    <> o.review_creation_date
            OR r.review_answer_timestamp <> o.review_answer_timestamp) AS rows_that_differ;


/* ---------- 10.5 Remove the old table ----------
   Only after 10.4 shows 0 differences. Keeping it would store every
   review twice, which is exactly the redundancy we are removing.
   (Its foreign key to orders is removed with it. The data also still
   exists in clean_order_reviews in the olist cleaning schema.) */
DROP TABLE order_reviews;


/* ---------- 10.6 Only if you ALREADY built seller_retention_summary ----------
   Recalculate each seller's average review score from the new tables and
   compare with what is stored. Expected: 1,351 sellers compared, 0 differ.
   (If the summary does not exist yet, skip this query.) */
WITH q1_orders AS (
    SELECT DISTINCT i.seller_id, i.order_id
    FROM order_items i
    JOIN orders o ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2018-01-01'
      AND o.order_purchase_timestamp <  '2018-04-01'
),
order_score AS (
    SELECT ro.order_id, AVG(r.review_score) AS score
    FROM review_orders ro
    JOIN reviews r ON r.review_id = ro.review_id
    JOIN orders  o ON o.order_id  = ro.order_id
    WHERE r.review_creation_date >= DATE(o.order_purchase_timestamp)
    GROUP BY ro.order_id
),
recalc AS (
    SELECT q.seller_id, ROUND(AVG(os.score), 2) AS avg_score
    FROM q1_orders q
    JOIN order_score os ON os.order_id = q.order_id
    GROUP BY q.seller_id
)
SELECT COUNT(*) AS sellers_compared,
       SUM(NOT (s.avg_review_score_q1 <=> rc.avg_score)) AS sellers_that_differ
FROM seller_retention_summary s
LEFT JOIN recalc rc ON rc.seller_id = s.seller_id;
