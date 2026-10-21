/* Step 9: copy the clean data into the team database (olist_ecommerce)

   Not done through csv files because when Workbench exports a csv an
   empty value (NULL) becomes an empty field, and loading that into a
   date or number column fails ("Incorrect datetime/integer value: ''").
   Copying table to table inside MySQL keeps the NULLs and needs no files.

   Before running:
   1. run the first two lines below (create and select the database)
   2. open Krish's OlistDb2.sql and run it completely, it creates the 8
      empty tables inside olist_ecommerce
   3. come back here and run the rest step by step */
CREATE DATABASE IF NOT EXISTS olist_ecommerce;
USE olist_ecommerce;


/* 9.1 fix one column type in Krish's structure
   average_stock holds ranges like '1-5', '5-20', '200+'. That's text and
   DECIMAL(12,2) rejects it ("Incorrect decimal value: '20-50'"). */
ALTER TABLE closed_deals MODIFY average_stock VARCHAR(20) NULL;


/* 9.2 copy the data
   olist.clean_orders means the table clean_orders in the schema olist,
   where the cleaning was done. */
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


/* 9.3 verify
   row counts and total sales should match the clean tables, and the NULL
   delivered dates should still be NULL */
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
