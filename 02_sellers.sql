/* =====================================================================
   STEP 2: SELLERS   (raw_sellers -> clean_sellers)
   Sellers are the object of our study (one row per seller).
   ===================================================================== */
USE olist;
SET SQL_SAFE_UPDATES = 0;

DROP TABLE IF EXISTS clean_sellers;
CREATE TABLE clean_sellers AS SELECT * FROM raw_sellers;


/* ---------- 2.1 Duplicates and ID format ----------
   Expected: 3,095 sellers, 0 duplicates, 0 badly formed IDs */
SELECT COUNT(*)                                        AS sellers,
       COUNT(*) - COUNT(DISTINCT seller_id)            AS duplicate_seller_ids,
       SUM(seller_id NOT REGEXP '^[0-9a-f]{32}$')      AS bad_seller_ids
FROM clean_sellers;


/* ---------- 2.2 ZIP code prefix: keep as TEXT ----------
   Brazilian ZIP prefixes have 5 digits and many start with 0 (e.g. 03407
   in Sao Paulo). Stored as a number, 03407 would become 3407, so we keep
   it as CHAR(5). This is also why we did not let an import tool guess the
   column types.
   Expected: 0 values that are not exactly 5 digits; 1,027 start with 0 */
SELECT SUM(seller_zip_code_prefix NOT REGEXP '^[0-9]{5}$') AS not_5_digits,
       SUM(seller_zip_code_prefix LIKE '0%')               AS starting_with_zero
FROM clean_sellers;


/* ---------- 2.3 State: valid Brazilian state codes ----------
   Our regional analysis relies on this column, so it must be clean.
   Expected: 0 invalid codes; 23 distinct states (Brazil has 27 incl. DF;
   AL, AP, RR and TO simply have no sellers). */
SELECT COUNT(DISTINCT seller_state) AS distinct_states,
       SUM(seller_state NOT IN ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
                                'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')) AS invalid_states
FROM clean_sellers;

SELECT seller_state, COUNT(*) AS sellers
FROM clean_sellers
GROUP BY seller_state
ORDER BY sellers DESC;


/* ---------- 2.4 City: free-text problems ----------
   Sellers typed their own city, so the column is messy. City is NOT used
   in our analysis (we use state/region), so we fix the clear errors to
   keep the table consistent, but we do not try to be perfect.

   CHECK A: values that contain something other than lower-case letters,
   spaces, hyphens or apostrophes, or that contain accented letters.
   (LENGTH counts bytes, CHAR_LENGTH counts letters: they differ only
   when there is an accented letter such as a in "sao".)
   Expected: 24 rows */
SELECT seller_id, seller_zip_code_prefix, seller_state, seller_city
FROM clean_sellers
WHERE seller_city NOT REGEXP '^[a-z '' -]+$'
   OR LENGTH(seller_city) <> CHAR_LENGTH(seller_city)
ORDER BY seller_city;

-- FIX A1: the state was typed after the city ("maua/sao paulo",
-- "cariacica / es", "rio de janeiro, rio de janeiro, brasil",
-- "rio de janeiro \rio de janeiro", "lages - sc"): keep only the part
-- before the separator.  Expected rows affected: 15, 2, 1, 4
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, '/', 1))   WHERE seller_city LIKE '%/%';
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, ',', 1))   WHERE seller_city LIKE '%,%';
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, CHAR(92), 1)) WHERE LOCATE(CHAR(92), seller_city) > 0;  -- CHAR(92) is the backslash
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, ' - ', 1)) WHERE seller_city LIKE '% - %';

-- FIX A2: the seller's own state code typed at the end ("brasilia df",
-- "andira-pr", "angra dos reis rj", "sao paulo sp").
-- Only removed when it matches that seller's state, so real city names
-- are not touched.  Expected rows affected: 4
UPDATE clean_sellers
SET seller_city = TRIM(REGEXP_REPLACE(seller_city, CONCAT('[ -]+', LOWER(seller_state), '$'), ''))
WHERE seller_city REGEXP CONCAT('[ -]+', LOWER(seller_state), '$');

-- FIX A3: double spaces ("sao  paulo").  Expected rows affected: 3
UPDATE clean_sellers SET seller_city = REPLACE(seller_city, '  ', ' ') WHERE seller_city LIKE '%  %';

-- FIX A4: special characters. Every other city is written without
-- accents, but two values contain one:
--   "são paulo"  -> the tilde is stored as a separate "combining" mark
--                   (character U+0303), so we simply remove that mark
--   "santa barbara d´oeste" -> an accent sign (U+00B4) is used instead
--                   of an apostrophe, so we replace it with '
-- CHAR(... USING utf8mb4) builds these characters from their byte codes,
-- so the script does not depend on how Workbench displays accents.
-- Expected rows affected: 1 and 2
UPDATE clean_sellers SET seller_city = REPLACE(seller_city, CHAR(0xCC83 USING utf8mb4), '')
WHERE LOCATE(CHAR(0xCC83 USING utf8mb4), seller_city COLLATE utf8mb4_bin) > 0;
UPDATE clean_sellers SET seller_city = REPLACE(seller_city, CHAR(0xC2B4 USING utf8mb4), '''')
WHERE LOCATE(CHAR(0xC2B4 USING utf8mb4), seller_city COLLATE utf8mb4_bin) > 0;


/* CHECK B: misspellings and values that are not a city.
   We list each correction in a small lookup table, so every change is
   visible and documented, and apply it with one UPDATE.
   How we found them: compared city names within the same state and
   looked for near-identical spellings (e.g. "garulhos" vs "guarulhos",
   50 sellers). Two non-city values (a ZIP code and an e-mail address)
   were replaced by the city of other sellers with the same ZIP prefix. */
DROP TABLE IF EXISTS city_corrections;
CREATE TABLE city_corrections (
    wrong_city   VARCHAR(100) COLLATE utf8mb4_bin PRIMARY KEY,
    correct_city VARCHAR(100),
    reason       VARCHAR(120)
);
INSERT INTO city_corrections VALUES
 ('sao paulop',            'sao paulo',             'typo'),
 ('sao pauo',              'sao paulo',             'typo'),
 ('sao paluo',             'sao paulo',             'typo'),
 ('sp',                    'sao paulo',             'state code typed instead of city; ZIP 03363 is Sao Paulo city'),
 ('sbc',                   'sao bernardo do campo', 'abbreviation of Sao Bernardo do Campo'),
 ('ao bernardo do campo',  'sao bernardo do campo', 'typo'),
 ('sao bernardo do capo',  'sao bernardo do campo', 'typo'),
 ('santa barbara d oeste', 'santa barbara d''oeste','missing apostrophe'),
 ('sando andre',           'santo andre',           'typo'),
 ('garulhos',              'guarulhos',             'typo'),
 ('mogi das cruses',       'mogi das cruzes',       'typo'),
 ('portoferreira',         'porto ferreira',        'missing space'),
 ('ribeirao pretp',        'ribeirao preto',        'typo'),
 ('riberao preto',         'ribeirao preto',        'typo'),
 ('robeirao preto',        'ribeirao preto',        'typo'),
 ('s jose do rio preto',   'sao jose do rio preto', 'abbreviation'),
 ('sao jose do rio pret',  'sao jose do rio preto', 'typo'),
 ('scao jose do rio pardo','sao jose do rio pardo', 'typo'),
 ('tabao da serra',        'taboao da serra',       'typo'),
 ('belo horizont',         'belo horizonte',        'typo'),
 ('cascavael',             'cascavel',              'typo'),
 ('sao jose dos pinhas',   'sao jose dos pinhais',  'typo'),
 ('balenario camboriu',    'balneario camboriu',    'typo'),
 ('floranopolis',          'florianopolis',         'typo'),
 ('sao miguel d''oeste',   'sao miguel do oeste',   'official name is Sao Miguel do Oeste'),
 ('arraial d''ajuda (porto seguro)', 'porto seguro', 'district name; municipality is Porto Seguro'),
 ('04482255',              'rio de janeiro',        'ZIP code typed as city; other sellers with ZIP 22790 are in rio de janeiro'),
 ('vendas@creditparts.com.br', 'maringa',           'e-mail typed as city; other sellers with ZIP 87025 are in maringa');

-- check 
SELECT * FROM city_corrections;

-- FIX B: apply the lookup table (28 corrections).  Expected rows affected: 33
-- (COLLATE utf8mb4_bin = exact match, so "são" is not treated as "sao")
UPDATE clean_sellers s
JOIN city_corrections c ON s.seller_city COLLATE utf8mb4_bin = c.wrong_city
SET s.seller_city = c.correct_city;

-- check 
SELECT seller_city, COUNT(*) FROM clean_sellers
WHERE seller_city IN ('guarulhos', 'garulhos')
GROUP BY seller_city;

/* ---------- 2.5 Set data types ---------- */
ALTER TABLE clean_sellers
    MODIFY seller_id              CHAR(32)     NOT NULL,
    MODIFY seller_zip_code_prefix CHAR(5)      NOT NULL,
    MODIFY seller_city            VARCHAR(100) NOT NULL,
    MODIFY seller_state           CHAR(2)      NOT NULL;


/* ---------- 2.6 VERIFY ----------
   Expected: 3,095 rows; 0 cities left with odd characters or accents;
   number of distinct cities goes from 611 (raw) to 556 (clean). */
SELECT COUNT(*) AS row_count,
       SUM(seller_city NOT REGEXP '^[a-z '' -]+$' OR LENGTH(seller_city) <> CHAR_LENGTH(seller_city)) AS odd_cities_left,
       (SELECT COUNT(DISTINCT seller_city COLLATE utf8mb4_bin) FROM raw_sellers) AS distinct_cities_raw,
       COUNT(DISTINCT seller_city COLLATE utf8mb4_bin)                           AS distinct_cities_clean
FROM clean_sellers;
