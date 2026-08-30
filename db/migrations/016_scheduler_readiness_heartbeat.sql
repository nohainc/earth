alter table world_state
  add column if not exists last_scheduler_at timestamptz;
