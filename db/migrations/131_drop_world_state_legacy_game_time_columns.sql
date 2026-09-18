-- Migration: 131_drop_world_state_legacy_game_time_columns.sql
-- EARTH V5 Authoritative Clock & Schema Simplification
--
-- Drops legacy mutable game_day and game_minute columns from world_state in favor
-- of continuous authoritative world clock derived from genesis_at.

ALTER TABLE world_state DROP COLUMN IF EXISTS game_day;
ALTER TABLE world_state DROP COLUMN IF EXISTS game_minute;

-- Drop obsolete mutable clock advance function if present
DROP FUNCTION IF EXISTS earth_advance_world_clock(INTEGER);
