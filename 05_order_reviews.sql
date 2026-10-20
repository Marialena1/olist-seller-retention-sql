/* =====================================================================
   STEP 5: ORDER REVIEWS   (raw_order_reviews -> clean_order_reviews)
   Used as an extra factor: the review scores a seller received in the
   baseline quarter.
   ===================================================================== */
USE olist;
SET SQL_SAFE_UPDATES = 0;

/* 5.1 Keep only the columns we need.
   We leave out review_comment_title and review_comment_message:
   - our question does not use them (we use the 1-5 score);
   - they are free text in Portuguese and mostly empty (88% of titles and
     59% of messages are blank), with line breaks inside the text;
   - keeping only what the analysis needs is good data-management practice
     (data minimisation). They stay available in raw_order_reviews.
   Expected: 87,656 blank titles, 58,247 blank messages out of 99,224 */
SELECT COUNT(*)                         AS reviews,
       SUM(review_comment_title   = '') AS blank_titles,
       SUM(review_comment_message = '') AS blank_messages
FROM raw_order_reviews;

DROP TABLE IF EXISTS clean_order_reviews;
CREATE TABLE clean_order_reviews AS
SELECT review_id, order_id, review_score, review_creation_date, review_answer_timestamp
FROM raw_order_reviews;

-- 5.2 Hidden \r at the end of the last column.  Expected rows affected: 99,223
UPDATE clean_order_reviews
SET review_answer_timestamp = REPLACE(review_answer_timestamp, CHAR(13), '')
WHERE review_answer_timestamp LIKE CONCAT('%', CHAR(13));


/* 5.3 Score must be a whole number from 1 to 5.
   Expected: 5 -> 57,328 | 4 -> 19,142 | 3 -> 8,179 | 2 -> 3,151 | 1 -> 11,424 */
SELECT review_score, COUNT(*) AS reviews
FROM clean_order_reviews
GROUP BY review_score
ORDER BY review_score DESC;


/* 5.4 Dates are in a DIFFERENT format from the orders table.
   Orders use 2018-01-18 21:46:00; this file uses 1/18/18 21:46
   (month/day/2-digit year, no seconds). This is the typical result of a
   CSV being opened and re-saved in Excel. If we left it as text, sorting
   and filtering by date would be wrong ("10/1/17" sorts before "2/1/17").
   CHECK: every value matches M/D/YY H:MM.  Expected: 0 and 0 */
SELECT review_creation_date, review_answer_timestamp FROM clean_order_reviews LIMIT 5;
SELECT SUM(review_creation_date    NOT REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2} [0-9]{1,2}:[0-9]{2}$') AS bad_creation,
       SUM(review_answer_timestamp NOT REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2} [0-9]{1,2}:[0-9]{2}$') AS bad_answer
FROM clean_order_reviews;

-- FIX: convert with STR_TO_DATE.  %c = month, %e = day, %y = 2-digit
-- year (18 -> 2018), %k = hour, %i = minutes.  Expected rows affected: 99,224 each
UPDATE clean_order_reviews SET review_creation_date    = STR_TO_DATE(review_creation_date,    '%c/%e/%y %k:%i');
UPDATE clean_order_reviews SET review_answer_timestamp = STR_TO_DATE(review_answer_timestamp, '%c/%e/%y %k:%i');

ALTER TABLE clean_order_reviews
    MODIFY review_id               CHAR(32) NOT NULL,
    MODIFY order_id                CHAR(32) NOT NULL,
    MODIFY review_score            TINYINT  NOT NULL,
    MODIFY review_creation_date    DATETIME NOT NULL,
    MODIFY review_answer_timestamp DATETIME NOT NULL;

/* VERIFY the conversion: the dates must fall inside the life of the
   dataset and an answer cannot come before the review was created.
   Expected: 2016-10-02 to 2018-08-31; 0 answers before creation */
SELECT MIN(review_creation_date) AS first_review,
       MAX(review_creation_date) AS last_review,
       SUM(review_answer_timestamp < review_creation_date) AS answer_before_creation
FROM clean_order_reviews;


/* 5.5 Duplicates: review_id is NOT unique on its own.
   Expected: 814 rows repeat a review_id, 551 rows repeat an order_id,
   but 0 rows repeat the PAIR (review_id, order_id).
   Meaning: one review can be linked to several orders (a customer who
   placed several orders reviewed them together), and some orders received
   more than one review. Neither is an error, so we delete nothing.
   -> The key of this table is the pair (review_id, order_id).  */
SELECT COUNT(*) - COUNT(DISTINCT review_id)           AS repeated_review_ids,
       COUNT(*) - COUNT(DISTINCT order_id)            AS repeated_order_ids,
       COUNT(*) - COUNT(DISTINCT review_id, order_id) AS repeated_pairs
FROM clean_order_reviews;

-- Example: one review_id shared by two different orders
SELECT * FROM clean_order_reviews
WHERE review_id = (SELECT review_id FROM clean_order_reviews
                   GROUP BY review_id HAVING COUNT(*) > 1 LIMIT 1);


/* 5.6 Every review belongs to an existing order.  Expected: 0 */
SELECT COUNT(*) AS reviews_without_order
FROM clean_order_reviews r
LEFT JOIN clean_orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;


/* 5.7 VERIFY.  Expected: 99,224 rows, 5 columns */
SELECT COUNT(*) AS row_count FROM clean_order_reviews;
