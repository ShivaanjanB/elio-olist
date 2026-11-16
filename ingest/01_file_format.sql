-- The instruction card Snowflake uses to read the Olist CSVs.

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

-- CREATE OR REPLACE (not IF NOT EXISTS): a file format holds settings only, no data,
-- so replacing it is harmless and a re-run always applies exactly what is written here.
CREATE OR REPLACE FILE FORMAT ELIO_OLIST.RAW.OLIST_CSV
  TYPE                           = CSV
  FIELD_DELIMITER                = ','
  SKIP_HEADER                    = 1
  FIELD_OPTIONALLY_ENCLOSED_BY   = '"'
  ENCODING                       = 'UTF8'
  SKIP_BYTE_ORDER_MARK           = TRUE
  EMPTY_FIELD_AS_NULL            = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE    -- wrong field count = error in a plain COPY / dry run (ignored by the SELECT-form load: see 04_dry_run.py)
  TRIM_SPACE                     = FALSE   -- RAW does no cleaning
  REPLACE_INVALID_CHARACTERS     = FALSE   -- invalid UTF-8 fails loudly instead of being swapped silently
  COMMENT = 'How to read the Olist CSVs: quoted fields, one header line, UTF-8';
