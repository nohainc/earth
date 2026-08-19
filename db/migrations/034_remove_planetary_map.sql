-- Migration 034: Remove the unused planetary map and territory concession subsystem.
-- Keep migration 027 in history; this forward migration is safe for existing databases.
-- This migration intentionally uses DROP DDL rather than CREATE/ALTER DDL.
DROP TABLE IF EXISTS plot_yield_logs CASCADE;
DROP TABLE IF EXISTS territory_plot_leases CASCADE;
DROP TABLE IF EXISTS territory_plots CASCADE;
DROP TABLE IF EXISTS planetary_regions CASCADE;
