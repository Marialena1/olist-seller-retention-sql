# Understanding Seller Retention on Olist: SQL Scripts

SQL scripts (MySQL) used for the Data Management and Visualization group assignment, Trinity College Dublin (Group 6, October 2026).

The scripts load the raw Olist CSV files, clean them, audit duplicates, copy the cleaned tables into the team database, and prepare the final tables for export. Run them in numeric order.

| Script | Purpose |
|--------|---------|
| `00_setup_and_load_raw.sql` | Create the schema and load the raw CSV files (update the file paths first) |
| `01_orders.sql` | Clean orders |
| `02_sellers.sql` | Clean sellers |
| `03_products_and_categories.sql` | Clean products and category translations |
| `04_order_items.sql` | Clean order items |
| `05_order_reviews.sql` | Clean order reviews |
| `06_marketing_and_deals.sql` | Clean marketing qualified leads and closed deals |
| `07_duplicate_audit_and_fixes.sql` | Duplicate audit and fixes |
| `08_final_checks.sql` | Final checks on the cleaned data |
| `09_copy_into_team_database.sql` | Copy cleaned tables into the team database |
| `10_region_summary_and_foreign_keys.sql` | Region summary and foreign keys |
| `10_split_reviews_2nf.sql` | Split reviews to satisfy 2NF |
| `12_final_check_before_export.sql` | Final check before export |

Data source: the public Olist Brazilian e-commerce dataset.
