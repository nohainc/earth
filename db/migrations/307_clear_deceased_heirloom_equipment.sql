-- Death & Continuity V2 Plan 19.
-- Heirlooms remain House property, but equipment is a mortal Human state.

UPDATE house_heirlooms heirloom
SET equipped_by_human_id = NULL
FROM humans human
WHERE heirloom.equipped_by_human_id = human.id
  AND human.life_status IN ('deceased', 'estate');

CREATE INDEX IF NOT EXISTS house_heirlooms_equipped_human_idx
  ON house_heirlooms(equipped_by_human_id)
  WHERE equipped_by_human_id IS NOT NULL;
