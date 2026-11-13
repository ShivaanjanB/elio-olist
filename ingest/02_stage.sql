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
  DIRECTORY   = (ENABLE = TRUE)                              -- a directory table, so Snowsight can list the files
  COMMENT     = 'Landing area for the Olist CSVs. Filled by ingest/02_upload_files.py';

-- IF NOT EXISTS leaves an existing stage as it is, so make sure the directory table is on
-- even for a stage created before this setting was added. Harmless if already on.
ALTER STAGE ELIO_OLIST.RAW.OLIST_STAGE SET DIRECTORY = (ENABLE = TRUE);

-- A directory table on an internal stage is NOT updated automatically: refresh it after uploads
-- (ingest/02_upload_files.py does this too).
ALTER STAGE ELIO_OLIST.RAW.OLIST_STAGE REFRESH;

-- What is on the dock right now?
LIST @ELIO_OLIST.RAW.OLIST_STAGE;
