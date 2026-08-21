-- EARTH PostgreSQL Migration 044: Make food production a first-class event
ALTER TABLE production_events DROP CONSTRAINT IF EXISTS production_events_resource_check;
ALTER TABLE production_events
  ADD CONSTRAINT production_events_resource_check
  CHECK (resource IN ('food', 'material', 'components', 'energy', 'compute'));
