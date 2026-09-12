\set ON_ERROR_STOP on
BEGIN;
\ir 01_schema.sql
\ir 02_functions.sql
\ir 03_reference_data.sql
\ir 04_initial_world.sql
COMMIT;
