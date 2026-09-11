-- Death & Continuity V2 Plan 29.
-- Make the House history graph explicit in both directions.

ALTER TABLE house_lineage_records
  ADD COLUMN IF NOT EXISTS successor_human_id TEXT REFERENCES humans(id);

UPDATE house_lineage_records lineage
SET successor_human_id = event.successor_human_id
FROM succession_events event
WHERE event.house_id = lineage.house_id
  AND event.predecessor_human_id = lineage.human_id
  AND lineage.successor_human_id IS NULL;

UPDATE house_lineage_records predecessor
SET successor_human_id = successor.human_id
FROM house_lineage_records successor
WHERE successor.house_id = predecessor.house_id
  AND successor.generation = predecessor.generation + 1
  AND predecessor.successor_human_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_house_lineage_successor
  ON house_lineage_records(successor_human_id);
