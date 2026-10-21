# Understanding Seller Retention on Olist: SQL scripts

MySQL scripts for our Data Management and Visualization group assignment (Group 6, TCD). Run them in numeric order.

- `00` creates the raw tables and loads the csv files (change the file paths first)
- `01` to `06` clean each table (orders, sellers, products, order items, reviews, marketing leads and closed deals)
- `07` duplicate audit and fixes
- `08` final checks on the clean tables
- `09` copies the clean tables into the team database
- `10_region_summary_and_foreign_keys` region table, seller retention summary and foreign keys
- `10_split_reviews_2nf` splits the reviews table for 2NF
- `12` final check before export

Data: the public Olist Brazilian e-commerce dataset.
