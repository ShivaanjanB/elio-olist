-- Look inside the staged files THROUGH the file format, before loading anything.

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

-- 1. How many records does Snowflake read in each staged file?
SELECT METADATA$FILENAME AS staged_file, COUNT(*) AS records
FROM @ELIO_OLIST.RAW.OLIST_STAGE (FILE_FORMAT => 'ELIO_OLIST.RAW.OLIST_CSV')
GROUP BY 1
ORDER BY 1;

-- 2. Stray carriage returns (\r) at the end of the LAST field of the Windows-style files?
--    0 means the default record delimiter handled CRLF correctly.
SELECT 'order_reviews (last field)' AS checked,
       COUNT_IF($7 LIKE '%' || CHR(13) || '%') AS rows_with_stray_cr
FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_order_reviews_dataset.csv.gz (FILE_FORMAT => 'ELIO_OLIST.RAW.OLIST_CSV')
UNION ALL
SELECT 'category translation (last field)',
       COUNT_IF($2 LIKE '%' || CHR(13) || '%')
FROM @ELIO_OLIST.RAW.OLIST_STAGE/product_category_name_translation.csv.gz (FILE_FORMAT => 'ELIO_OLIST.RAW.OLIST_CSV');

-- 3. Portuguese accents intact? The 6th character of "Parabéns..." must be code point 233 (é).
--    195 would mean the bytes were misread (the garbled "Ã©").
SELECT UNICODE(SUBSTR($5, 6, 1)) AS sixth_char_code_point
FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_order_reviews_dataset.csv.gz (FILE_FORMAT => 'ELIO_OLIST.RAW.OLIST_CSV')
WHERE $5 LIKE 'Parab%ns lojas lannister%'
LIMIT 1;

-- 4. The byte-order mark must not have leaked into the first field of the category file.
--    First character code point 65279 would be the BOM; 98 is a plain "b" of "beleza_saude".
SELECT UNICODE(SUBSTR($1, 1, 1)) AS first_char_code_point
FROM @ELIO_OLIST.RAW.OLIST_STAGE/product_category_name_translation.csv.gz (FILE_FORMAT => 'ELIO_OLIST.RAW.OLIST_CSV')
LIMIT 1;
