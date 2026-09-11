-- Death & Continuity V2 Plan 27.
-- A House can have only one lineage record for a generation.

DELETE FROM house_lineage_records newer
USING house_lineage_records older
WHERE newer.house_id = older.house_id
  AND newer.generation = older.generation
  AND newer.ctid > older.ctid;

CREATE UNIQUE INDEX IF NOT EXISTS house_lineage_records_house_generation_idx
  ON house_lineage_records(house_id, generation);
