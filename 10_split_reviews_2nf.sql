/* Step 10 (2NF): split order_reviews into reviews and review_orders
   Database: olist_ecommerce

   The problem: order_reviews has a two column key (review_id, order_id),
   but review_score, review_creation_date and review_answer_timestamp
   depend on review_id alone. When one review is linked to several orders
   those values are repeated on every row. That's a partial dependency and
   2NF doesn't allow it.

   The fix: store each review once and the review-order links separately.
     reviews       (review_id PK, review_score, review_creation_date,
                    review_answer_timestamp)         one row per review
     review_orders (review_id, order_id), PK is both   one row per link
   Orders and reviews are many to many (an order can have 2 reviews and a
   review can cover 2 orders), review_orders is the link table.

   Run after 09. If the region/summary script was already run that's fine
   too, the summary's review scores are checked at the end. */
USE olist_ecommerce;
SET SQL_SAFE_UPDATES = 0;


/* 10.1 check the dependency before splitting
   If a review_id ever had two different scores or dates the split would
   lose information, so we check that it never happens. 779 review_ids are
   linked to more than one order, with 0 different scores and 0 different
   dates. */
SELECT COUNT(*)                     AS reviews_on_several_orders,
       SUM(n_scores > 1)            AS with_different_scores,
       SUM(n_dates  > 1)            AS with_different_dates
FROM (SELECT review_id,
             COUNT(DISTINCT review_score) AS n_scores,
             COUNT(DISTINCT review_creation_date, review_answer_timestamp) AS n_dates
      FROM order_reviews
      GROUP BY review_id
      HAVING COUNT(*) > 1) x;


/* 10.2 create the two new tables
   Same character set and collation as the other tables so the foreign
   keys work. The CHECK keeps scores between 1 and 5 like before. */
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


/* 10.3 fill them
   reviews: SELECT DISTINCT keeps one row per review (10.1 showed the
   repeated rows are identical), 98,396 rows.
   review_orders: every (review, order) pair, 99,200 rows. */
INSERT INTO reviews (review_id, review_score, review_creation_date, review_answer_timestamp)
SELECT DISTINCT review_id, review_score, review_creation_date, review_answer_timestamp
FROM order_reviews;

INSERT INTO review_orders (review_id, order_id)
SELECT review_id, order_id
FROM order_reviews;


/* 10.4 verify that nothing was lost
   Joining the two new tables back together must give exactly the old
   table, same number of rows and no row that differs (98,396 reviews,
   99,200 links, 99,200 rebuilt rows, 0 that differ). */
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


/* 10.5 remove the old table
   Only after 10.4 shows 0 differences. Keeping it would store every
   review twice, which is the redundancy we are removing. Its foreign key
   to orders goes with it. The data also still exists in
   clean_order_reviews in the olist cleaning schema. */
DROP TABLE order_reviews;


/* 10.6 only if seller_retention_summary was already built
   Recalculate each seller's average review score from the new tables and
   compare with what is stored, nothing should differ (1,351 sellers).
   Skip this query if the summary doesn't exist yet. */
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
