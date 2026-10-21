/* Step 5: order reviews (raw_order_reviews -> clean_order_reviews)
   Used as an extra factor, the review scores a seller got in the
   baseline quarter. */
USE olist;
SET SQL_SAFE_UPDATES = 0;

/* 5.1 keep only the columns we need
   review_comment_title and review_comment_message are left out. We only
   use the 1-5 score, the comments are free text in Portuguese, mostly
   empty (about 88% of titles and 59% of messages) and have line breaks
   inside. Keeping only what the analysis needs is data minimisation. They
   are still in raw_order_reviews. */
SELECT COUNT(*)                         AS reviews,
       SUM(review_comment_title   = '') AS blank_titles,
       SUM(review_comment_message = '') AS blank_messages
FROM raw_order_reviews;

DROP TABLE IF EXISTS clean_order_reviews;
CREATE TABLE clean_order_reviews AS
SELECT review_id, order_id, review_score, review_creation_date, review_answer_timestamp
FROM raw_order_reviews;

-- 5.2 hidden \r at the end of the last column
UPDATE clean_order_reviews
SET review_answer_timestamp = REPLACE(review_answer_timestamp, CHAR(13), '')
WHERE review_answer_timestamp LIKE CONCAT('%', CHAR(13));


/* 5.3 score must be a whole number from 1 to 5 */
SELECT review_score, COUNT(*) AS reviews
FROM clean_order_reviews
GROUP BY review_score
ORDER BY review_score DESC;


/* 5.4 dates are in a different format from the orders table
   Orders use 2018-01-18 21:46:00 but this file uses 1/18/18 21:46
   (month/day/2 digit year, no seconds), probably from the csv being
   opened and saved in Excel. As text, sorting by date would be wrong
   ("10/1/17" sorts before "2/1/17").
   check that every value matches M/D/YY H:MM */
SELECT review_creation_date, review_answer_timestamp FROM clean_order_reviews LIMIT 5;
SELECT SUM(review_creation_date    NOT REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2} [0-9]{1,2}:[0-9]{2}$') AS bad_creation,
       SUM(review_answer_timestamp NOT REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2} [0-9]{1,2}:[0-9]{2}$') AS bad_answer
FROM clean_order_reviews;

-- fix with STR_TO_DATE: %c month, %e day, %y 2 digit year (18 = 2018),
-- %k hour, %i minutes
UPDATE clean_order_reviews SET review_creation_date    = STR_TO_DATE(review_creation_date,    '%c/%e/%y %k:%i');
UPDATE clean_order_reviews SET review_answer_timestamp = STR_TO_DATE(review_answer_timestamp, '%c/%e/%y %k:%i');

ALTER TABLE clean_order_reviews
    MODIFY review_id               CHAR(32) NOT NULL,
    MODIFY order_id                CHAR(32) NOT NULL,
    MODIFY review_score            TINYINT  NOT NULL,
    MODIFY review_creation_date    DATETIME NOT NULL,
    MODIFY review_answer_timestamp DATETIME NOT NULL;

/* verify the conversion: dates should be within the life of the dataset
   and an answer can't come before the review was created */
SELECT MIN(review_creation_date) AS first_review,
       MAX(review_creation_date) AS last_review,
       SUM(review_answer_timestamp < review_creation_date) AS answer_before_creation
FROM clean_order_reviews;


/* 5.5 duplicates, review_id is not unique on its own
   Some review_ids repeat (814 rows) and some order_ids repeat (551), but
   no (review_id, order_id) pair repeats. So one review can be linked to
   several orders (a customer who placed several orders and reviewed them
   together) and some orders got more than one review. Neither is an
   error so nothing is deleted. The key of this table is the pair
   (review_id, order_id). */
SELECT COUNT(*) - COUNT(DISTINCT review_id)           AS repeated_review_ids,
       COUNT(*) - COUNT(DISTINCT order_id)            AS repeated_order_ids,
       COUNT(*) - COUNT(DISTINCT review_id, order_id) AS repeated_pairs
FROM clean_order_reviews;

-- example: one review_id shared by two different orders
SELECT * FROM clean_order_reviews
WHERE review_id = (SELECT review_id FROM clean_order_reviews
                   GROUP BY review_id HAVING COUNT(*) > 1 LIMIT 1);


/* 5.6 every review belongs to an existing order */
SELECT COUNT(*) AS reviews_without_order
FROM clean_order_reviews r
LEFT JOIN clean_orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;


/* 5.7 verify */
SELECT COUNT(*) AS row_count FROM clean_order_reviews;
