-- =============================================================================
-- ingest/01_file_format.sql
-- The instruction card Snowflake uses to read the Olist CSVs.
-- Run as ELIO_TRANSFORMER (the pipeline role). Safe to re-run.
--
-- Evidence behind each setting (from profiling the raw files, see ingest/README.md):
--   * review comments contain commas AND line breaks inside double quotes
--       -> FIELD_OPTIONALLY_ENCLOSED_BY = '"'   (the default is NONE, so it must be set)
--   * quoting is inconsistent (IDs quoted, numbers not, even within one row) -> "optionally"
--   * every file has one header line                          -> SKIP_HEADER = 1
--   * every file is valid UTF-8; the category file starts with a byte-order mark
--       -> ENCODING = 'UTF8', SKIP_BYTE_ORDER_MARK = TRUE
--   * reviews and the category file use Windows line endings (CRLF)
--       -> RECORD_DELIMITER is left at its default (a new line); \r\n is understood
--   * blank fields are common (e.g. orders not yet delivered)  -> EMPTY_FIELD_AS_NULL = TRUE
-- =============================================================================

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
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE    -- a row with the wrong number of fields fails loudly
  TRIM_SPACE                     = FALSE   -- RAW does no cleaning
  REPLACE_INVALID_CHARACTERS     = FALSE   -- invalid UTF-8 fails loudly instead of being swapped silently
  COMMENT = 'How to read the Olist CSVs: quoted fields, one header line, UTF-8';
