-- Simulation ticks are internal activity, not public news.
DELETE FROM world_events
WHERE event_type IN ('world_clock', 'scheduled_tick')
   OR LOWER(COALESCE(title, '')) LIKE '%public world announcement%';
