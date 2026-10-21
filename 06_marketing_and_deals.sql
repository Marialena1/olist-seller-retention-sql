/* Step 6: marketing funnel (side analysis only)
   raw_marketing_qualified_leads -> clean_marketing_qualified_leads
   raw_closed_deals              -> clean_closed_deals */
USE olist;
SET SQL_SAFE_UPDATES = 0;

/* part A: marketing qualified leads */
DROP TABLE IF EXISTS clean_marketing_qualified_leads;
CREATE TABLE clean_marketing_qualified_leads AS SELECT * FROM raw_marketing_qualified_leads;

-- 6.1 hidden \r at the end of the last column
UPDATE clean_marketing_qualified_leads
SET origin = REPLACE(origin, CHAR(13), '')
WHERE origin LIKE CONCAT('%', CHAR(13));

-- 6.2 duplicates and id format
SELECT COUNT(*) AS leads,
       COUNT(*) - COUNT(DISTINCT mql_id)                 AS duplicate_mql_ids,
       SUM(mql_id          NOT REGEXP '^[0-9a-f]{32}$')  AS bad_mql_ids,
       SUM(landing_page_id NOT REGEXP '^[0-9a-f]{32}$')  AS bad_landing_page_ids
FROM clean_marketing_qualified_leads;

/* 6.3 origin (acquisition channel)
   There are 10 named channels, 60 blanks and 1,099 already 'unknown'.
   Blank and 'unknown' both mean we don't know the channel, so the blanks
   are merged into 'unknown'. Origin is the grouping used in the side
   analysis, one clear category is better than two kinds of missing. */
SELECT origin, COUNT(*) AS leads
FROM clean_marketing_qualified_leads
GROUP BY origin
ORDER BY leads DESC;

UPDATE clean_marketing_qualified_leads SET origin = 'unknown' WHERE origin = '';

/* 6.4 first_contact_date is M/D/YY text (e.g. 2/1/18) like the reviews
   check the format */
SELECT SUM(first_contact_date NOT REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2}$') AS bad_dates
FROM clean_marketing_qualified_leads;

-- fix
UPDATE clean_marketing_qualified_leads
SET first_contact_date = STR_TO_DATE(first_contact_date, '%c/%e/%y');

ALTER TABLE clean_marketing_qualified_leads
    MODIFY mql_id             CHAR(32)    NOT NULL,
    MODIFY first_contact_date DATE        NOT NULL,
    MODIFY landing_page_id    CHAR(32)    NOT NULL,
    MODIFY origin             VARCHAR(30) NOT NULL;

-- verify
SELECT MIN(first_contact_date) AS first_contact, MAX(first_contact_date) AS last_contact
FROM clean_marketing_qualified_leads;


/* part B: closed deals */
DROP TABLE IF EXISTS clean_closed_deals;
CREATE TABLE clean_closed_deals AS SELECT * FROM raw_closed_deals;

-- 6.5 hidden \r at the end of the last column
UPDATE clean_closed_deals
SET declared_monthly_revenue = REPLACE(declared_monthly_revenue, CHAR(13), '')
WHERE declared_monthly_revenue LIKE CONCAT('%', CHAR(13));

-- 6.6 duplicates
SELECT COUNT(*) AS deals,
       COUNT(*) - COUNT(DISTINCT mql_id)    AS duplicate_mql_ids,
       COUNT(*) - COUNT(DISTINCT seller_id) AS duplicate_seller_ids
FROM clean_closed_deals;

/* 6.7 Excel damage in average_stock
   The real answer options are ranges: '1-5', '5-20', '20-50', '50-200',
   '200+'. When the file was opened in Excel '1-5' was read as a date
   (5 January) and saved as '5-Jan', and '5-20' became '20-May'. */
SELECT average_stock, COUNT(*) AS deals
FROM clean_closed_deals
GROUP BY average_stock
ORDER BY deals DESC;

-- fix
UPDATE clean_closed_deals SET average_stock = '1-5'  WHERE average_stock = '5-Jan';
UPDATE clean_closed_deals SET average_stock = '5-20' WHERE average_stock = '20-May';


/* 6.8 blanks to NULL in the text columns
   NULL and not 'unknown' here because these columns aren't used as
   groupings. */
UPDATE clean_closed_deals SET business_segment       = NULL WHERE business_segment       = '';
UPDATE clean_closed_deals SET lead_type              = NULL WHERE lead_type              = '';
UPDATE clean_closed_deals SET lead_behaviour_profile = NULL WHERE lead_behaviour_profile = '';
UPDATE clean_closed_deals SET average_stock          = NULL WHERE average_stock          = '';
UPDATE clean_closed_deals SET business_type          = NULL WHERE business_type          = '';


/* 6.9 first normal form, one value per cell
   lead_behaviour_profile sometimes has two values in one cell (e.g.
   'cat, wolf'), which breaks 1NF. It's only 16 of 842 deals and the column
   isn't used in the analysis, so they are replaced with 'mixed' instead
   of splitting into a separate table. */
SELECT lead_behaviour_profile, COUNT(*) AS deals
FROM clean_closed_deals
WHERE lead_behaviour_profile LIKE '%,%'
GROUP BY lead_behaviour_profile;

-- fix
UPDATE clean_closed_deals SET lead_behaviour_profile = 'mixed' WHERE lead_behaviour_profile LIKE '%,%';


/* 6.10 TRUE/FALSE text to 1/0 (TINYINT, which is how MySQL stores BOOLEAN),
   blank to NULL */
SELECT 'has_company' AS col, has_company AS val, COUNT(*) AS n FROM clean_closed_deals GROUP BY has_company
UNION ALL
SELECT 'has_gtin', has_gtin, COUNT(*) FROM clean_closed_deals GROUP BY has_gtin;

UPDATE clean_closed_deals
SET has_company = CASE has_company WHEN 'TRUE' THEN '1' WHEN 'FALSE' THEN '0' ELSE NULL END,
    has_gtin    = CASE has_gtin    WHEN 'TRUE' THEN '1' WHEN 'FALSE' THEN '0' ELSE NULL END;


/* 6.11 numeric columns
   declared_product_catalog_size is blank in 773 rows, those become NULL.
   declared_monthly_revenue is 0 in 797 of 842 rows (95%). These
   businesses signed with Olist so a real revenue of 0 isn't believable,
   and leaving the zeros in would pull any average towards 0. So 0 is
   treated as not declared (NULL). */
SELECT SUM(declared_product_catalog_size = '') AS blank_catalog_size,
       SUM(declared_monthly_revenue = '0')     AS zero_revenue,
       SUM(declared_monthly_revenue NOT REGEXP '^[0-9]+(\\.[0-9]+)?$') AS non_numeric_revenue
FROM clean_closed_deals;

UPDATE clean_closed_deals SET declared_product_catalog_size = NULL WHERE declared_product_catalog_size = '';
UPDATE clean_closed_deals SET declared_monthly_revenue      = NULL WHERE declared_monthly_revenue = '0';


/* 6.12 won_date is M/D/YY H:MM text */
SELECT SUM(won_date NOT REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{2} [0-9]{1,2}:[0-9]{2}$') AS bad_dates
FROM clean_closed_deals;

-- fix
UPDATE clean_closed_deals SET won_date = STR_TO_DATE(won_date, '%c/%e/%y %k:%i');

ALTER TABLE clean_closed_deals
    MODIFY mql_id                        CHAR(32)      NOT NULL,
    MODIFY seller_id                     CHAR(32)      NOT NULL,
    MODIFY sdr_id                        CHAR(32)      NOT NULL,
    MODIFY sr_id                         CHAR(32)      NOT NULL,
    MODIFY won_date                      DATETIME      NOT NULL,
    MODIFY business_segment              VARCHAR(50)   NULL,
    MODIFY lead_type                     VARCHAR(30)   NULL,
    MODIFY lead_behaviour_profile        VARCHAR(20)   NULL,
    MODIFY has_company                   TINYINT       NULL,
    MODIFY has_gtin                      TINYINT       NULL,
    MODIFY average_stock                 VARCHAR(20)   NULL,
    MODIFY business_type                 VARCHAR(30)   NULL,
    MODIFY declared_product_catalog_size INT           NULL,
    MODIFY declared_monthly_revenue      DECIMAL(12,2) NULL;


/* 6.13 links and logic
   All 842 deals have a lead, but only 380 of the 842 deal sellers are in
   the sellers table. The other 462 signed up but have no sales in our
   order data, so that isn't an error, but it means closed_deals.seller_id
   can't have a strict foreign key to sellers (tell whoever builds the
   database). One deal was won before the first contact, flag only.
   54 of our 1,351 eligible sellers (Q1 2018) have a closed deal. */
SELECT
  (SELECT COUNT(*) FROM clean_closed_deals d JOIN clean_marketing_qualified_leads m ON m.mql_id = d.mql_id) AS deals_with_lead,
  (SELECT COUNT(*) FROM clean_closed_deals d JOIN clean_sellers s ON s.seller_id = d.seller_id)            AS deals_with_seller,
  (SELECT COUNT(*) FROM clean_closed_deals d JOIN clean_marketing_qualified_leads m ON m.mql_id = d.mql_id
    WHERE DATE(d.won_date) < m.first_contact_date)                                                          AS won_before_contact,
  (SELECT COUNT(DISTINCT d.seller_id)
     FROM clean_closed_deals d
     JOIN clean_order_items i ON i.seller_id = d.seller_id
     JOIN clean_orders o      ON o.order_id  = i.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2018-01-01'
      AND o.order_purchase_timestamp <  '2018-04-01')                                                       AS eligible_sellers_with_deal;

-- 6.14 verify
SELECT (SELECT COUNT(*) FROM clean_marketing_qualified_leads) AS leads,
       (SELECT COUNT(*) FROM clean_closed_deals)              AS deals;
