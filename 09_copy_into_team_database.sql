/* =====================================================================
   STEP 9: COPY THE CLEAN DATA INTO THE TEAM DATABASE (olist_ecommerce)
   ---------------------------------------------------------------------
   Why not CSV files? When Workbench exports a CSV, an empty value
   (NULL) becomes an empty field. Loading an empty field into a date or
   number column fails with "Incorrect datetime/integer value: ''".
   Copying table to table inside MySQL keeps NULLs as NULLs and needs no
   files at all.

   BEFORE RUNNING THIS SCRIPT:
   1. Run the first two lines below (create + select the database).
   2. Open Krish's OlistDb2.sql (File > Open SQL Script) and run it
      completely (lightning bolt). It creates the 8 empty tables inside
      olist_ecommerce because that database is now selected.
   3. Come back to this script and run the rest, step by step.
   ===================================================================== */
CREATE DATABASE IF NOT EXISTS olist_ecommerce;
USE olist_ecommerce;


/* 9.1 Fix one column type in Krish's structure.
   average_stock holds ranges like '1-5', '5-20', '200+'. Those are text,
   not numbers, so DECIMAL(12,2) rejects them ("Incorrect decimal value:
   '20-50'"). It must be text. */
ALTER TABLE closed_deals MODIFY average_stock VARCHAR(20) NULL;


/* 9.2 Copy the data. INSERT INTO ... SELECT reads rows from one table and
   adds them to another. olist.clean_orders means "the table clean_orders
   in the schema olist" (where we did the cleaning).
   Expected rows affected: 73 | 8,000 | 842 | 3,095 | 32,951 | 99,441 |
   112,650 | 99,200 */
INSERT INTO category_translation (product_category_name, product_category_name_english)
SELECT product_category_name, product_category_name_english FROM olist.clean_category_translation;

INSERT INTO marketing_qualified_leads (mql_id, first_contact_date, landing_page_id, origin)
SELECT mql_id, first_contact_date, landing_page_id, origin FROM olist.clean_marketing_qualified_leads;

INSERT INTO closed_deals (mql_id, seller_id, sdr_id, sr_id, won_date, business_segment, lead_type,
                          lead_behaviour_profile, has_company, has_gtin, average_stock, business_type,
                          declared_product_catalog_size, declared_monthly_revenue)
SELECT mql_id, seller_id, sdr_id, sr_id, won_date, business_segment, lead_type,
       lead_behaviour_profile, has_company, has_gtin, average_stock, business_type,
       declared_product_catalog_size, declared_monthly_revenue
FROM olist.clean_closed_deals;

INSERT INTO sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state)
SELECT seller_id, seller_zip_code_prefix, seller_city, seller_state FROM olist.clean_sellers;

INSERT INTO products (product_id, product_category_name, product_name_length, product_description_length,
                      product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm)
SELECT product_id, product_category_name, product_name_length, product_description_length,
       product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm
FROM olist.clean_products;

INSERT INTO orders (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
                    order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date)
SELECT order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
       order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date
FROM olist.clean_orders;

INSERT INTO order_items (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value)
SELECT order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value
FROM olist.clean_order_items;

INSERT INTO order_reviews (review_id, order_id, review_score, review_creation_date, review_answer_timestamp)
SELECT review_id, order_id, review_score, review_creation_date, review_answer_timestamp
FROM olist.clean_order_reviews;


/* 9.3 VERIFY: same row counts and same total sales as the clean tables.
   Expected: 73, 8000, 842, 3095, 32951, 99441, 112650, 99200,
   total price 13591643.70, NULL delivered dates 2965 (NULLs kept). */
SELECT (SELECT COUNT(*) FROM category_translation)      AS category_translation,
       (SELECT COUNT(*) FROM marketing_qualified_leads) AS marketing_qualified_leads,
       (SELECT COUNT(*) FROM closed_deals)              AS closed_deals,
       (SELECT COUNT(*) FROM sellers)                   AS sellers,
       (SELECT COUNT(*) FROM products)                  AS products,
       (SELECT COUNT(*) FROM orders)                    AS orders,
       (SELECT COUNT(*) FROM order_items)               AS order_items,
       (SELECT COUNT(*) FROM order_reviews)             AS order_reviews,
       (SELECT SUM(price) FROM order_items)             AS total_price,
       (SELECT COUNT(*) FROM orders WHERE order_delivered_customer_date IS NULL) AS null_delivered_dates;
