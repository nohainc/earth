-- Migration 022: Add genesis_at and simulated_day_offset to world_state

alter table world_state
  add column if not exists genesis_at timestamptz not null default '2026-01-01T00:00:00Z',
  add column if not exists simulated_day_offset integer not null default 0;
