update world_state
set last_scheduler_at = coalesce(last_scheduler_at, current_timestamp)
where id = 'WORLD';
