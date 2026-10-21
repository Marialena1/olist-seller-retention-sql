/* Step 2: sellers (raw_sellers -> clean_sellers)
   Sellers are what we study, one row per seller. */
USE olist;
SET SQL_SAFE_UPDATES = 0;

DROP TABLE IF EXISTS clean_sellers;
CREATE TABLE clean_sellers AS SELECT * FROM raw_sellers;


/* 2.1 duplicates and id format */
SELECT COUNT(*)                                        AS sellers,
       COUNT(*) - COUNT(DISTINCT seller_id)            AS duplicate_seller_ids,
       SUM(seller_id NOT REGEXP '^[0-9a-f]{32}$')      AS bad_seller_ids
FROM clean_sellers;


/* 2.2 zip code prefix, keep as text
   Brazilian zip prefixes have 5 digits and many start with 0 (e.g. 03407).
   As a number that would become 3407, so it stays CHAR(5). This is also
   why we didn't let an import tool guess the column types. */
SELECT SUM(seller_zip_code_prefix NOT REGEXP '^[0-9]{5}$') AS not_5_digits,
       SUM(seller_zip_code_prefix LIKE '0%')               AS starting_with_zero
FROM clean_sellers;


/* 2.3 state codes
   Our regional analysis relies on this column so it has to be valid.
   Brazil has 27 states incl. DF, the data has 23 (AL, AP, RR and TO
   have no sellers). */
SELECT COUNT(DISTINCT seller_state) AS distinct_states,
       SUM(seller_state NOT IN ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
                                'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')) AS invalid_states
FROM clean_sellers;

SELECT seller_state, COUNT(*) AS sellers
FROM clean_sellers
GROUP BY seller_state
ORDER BY sellers DESC;


/* 2.4 city, free text problems
   Sellers typed their own city so the column is messy. We don't use city
   in the analysis (we use state/region), so we only fix the clear errors
   to keep the table consistent.

   Check A: cities with anything other than lower case letters, spaces,
   hyphens or apostrophes, or with accented letters. LENGTH counts bytes
   and CHAR_LENGTH counts letters, so they only differ when there is an
   accent. */
SELECT seller_id, seller_zip_code_prefix, seller_state, seller_city
FROM clean_sellers
WHERE seller_city NOT REGEXP '^[a-z '' -]+$'
   OR LENGTH(seller_city) <> CHAR_LENGTH(seller_city)
ORDER BY seller_city;

-- fix A1: the state was typed after the city ("maua/sao paulo",
-- "cariacica / es", "rio de janeiro, rio de janeiro, brasil",
-- "rio de janeiro \rio de janeiro", "lages - sc"), keep the part before
-- the separator
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, '/', 1))   WHERE seller_city LIKE '%/%';
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, ',', 1))   WHERE seller_city LIKE '%,%';
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, CHAR(92), 1)) WHERE LOCATE(CHAR(92), seller_city) > 0;  -- CHAR(92) is the backslash
UPDATE clean_sellers SET seller_city = TRIM(SUBSTRING_INDEX(seller_city, ' - ', 1)) WHERE seller_city LIKE '% - %';

-- fix A2: the seller's own state code typed at the end ("brasilia df",
-- "andira-pr", "angra dos reis rj", "sao paulo sp"). Only removed when it
-- matches that seller's state so real city names aren't touched.
UPDATE clean_sellers
SET seller_city = TRIM(REGEXP_REPLACE(seller_city, CONCAT('[ -]+', LOWER(seller_state), '$'), ''))
WHERE seller_city REGEXP CONCAT('[ -]+', LOWER(seller_state), '$');

-- fix A3: double spaces ("sao  paulo")
UPDATE clean_sellers SET seller_city = REPLACE(seller_city, '  ', ' ') WHERE seller_city LIKE '%  %';

-- fix A4: special characters. Every other city has no accents but two do:
--   "são paulo": the tilde is stored as a separate combining mark (U+0303),
--                so we just remove it
--   "santa barbara d´oeste": an accent sign (U+00B4) is used instead of an
--                apostrophe, so we replace it with '
-- CHAR(... USING utf8mb4) builds the characters from their byte codes so
-- the script doesn't depend on how Workbench shows accents.
UPDATE clean_sellers SET seller_city = REPLACE(seller_city, CHAR(0xCC83 USING utf8mb4), '')
WHERE LOCATE(CHAR(0xCC83 USING utf8mb4), seller_city COLLATE utf8mb4_bin) > 0;
UPDATE clean_sellers SET seller_city = REPLACE(seller_city, CHAR(0xC2B4 USING utf8mb4), '''')
WHERE LOCATE(CHAR(0xC2B4 USING utf8mb4), seller_city COLLATE utf8mb4_bin) > 0;


/* Check B: misspellings and values that aren't a city.
   Each correction goes in a small lookup table so every change is visible,
   then one UPDATE applies them. Found by comparing city names within the
   same state and looking for near identical spellings (e.g. "garulhos" vs
   "guarulhos"). A zip code and an e-mail address typed as city were
   replaced with the city of other sellers with the same zip prefix. */
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

-- fix B: apply the lookup table
-- (COLLATE utf8mb4_bin makes it an exact match, so "são" isn't treated as "sao")
UPDATE clean_sellers s
JOIN city_corrections c ON s.seller_city COLLATE utf8mb4_bin = c.wrong_city
SET s.seller_city = c.correct_city;

-- check
SELECT seller_city, COUNT(*) FROM clean_sellers
WHERE seller_city IN ('guarulhos', 'garulhos')
GROUP BY seller_city;

/* 2.5 data types */
ALTER TABLE clean_sellers
    MODIFY seller_id              CHAR(32)     NOT NULL,
    MODIFY seller_zip_code_prefix CHAR(5)      NOT NULL,
    MODIFY seller_city            VARCHAR(100) NOT NULL,
    MODIFY seller_state           CHAR(2)      NOT NULL;


/* 2.6 verify
   no odd characters left, and fewer distinct cities than in the raw table */
SELECT COUNT(*) AS row_count,
       SUM(seller_city NOT REGEXP '^[a-z '' -]+$' OR LENGTH(seller_city) <> CHAR_LENGTH(seller_city)) AS odd_cities_left,
       (SELECT COUNT(DISTINCT seller_city COLLATE utf8mb4_bin) FROM raw_sellers) AS distinct_cities_raw,
       COUNT(DISTINCT seller_city COLLATE utf8mb4_bin)                           AS distinct_cities_clean
FROM clean_sellers;
