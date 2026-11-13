-- =============================================================================
-- ingest/02_stage.sql
-- The landing area ("loading dock") for the Olist CSVs. Run as ELIO_TRANSFORMER.
-- Safe to re-run.
--
-- A stage holds FILES, so this uses IF NOT EXISTS: CREATE OR REPLACE would delete
-- every staged file. (The file format in 01_file_format.sql holds only settings,
-- which is why that one can safely use CREATE OR REPLACE.)
--
-- The files are uploaded afterwards by ingest/02_upload_files.py, because PUT cannot run
-- from a Snowsight worksheet.
-- =============================================================================

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

CREATE STAGE IF NOT EXISTS ELIO_OLIST.RAW.OLIST_STAGE
  FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')   -- default reader for files on this stage
  COMMENT     = 'Landing area for the Olist CSVs. Filled by ingest/02_upload_files.py';

-- What is on the dock right now?
LIST @ELIO_OLIST.RAW.OLIST_STAGE;
