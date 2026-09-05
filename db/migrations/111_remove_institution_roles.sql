-- Remove the obsolete Authority / Active Terms & Delegation subsystem.
-- Institution ownership is now explicit and does not expire or delegate.

ALTER TABLE institutions
  ADD COLUMN IF NOT EXISTS administrator_human_id TEXT REFERENCES humans(id);

-- Preserve the current administrator before removing role assignments. The
-- founder roles created by the application are the authoritative owner record.
DO $$
BEGIN
  IF to_regclass('public.role_assignments') IS NOT NULL
     AND to_regclass('public.institution_roles') IS NOT NULL THEN
    EXECUTE $sql$
      UPDATE institutions i
      SET administrator_human_id = source.human_id
      FROM (
        SELECT DISTINCT ON (ra.institution_id)
          ra.institution_id,
          ra.human_id
        FROM role_assignments ra
        JOIN institution_roles ir ON ir.id = ra.role_id
        WHERE ra.status = 'active'
        ORDER BY ra.institution_id, ra.started_game_day, ra.created_at
      ) source
      WHERE i.id = source.institution_id
        AND i.administrator_human_id IS NULL
    $sql$;
  END IF;
END $$;

-- Institutions without a currently active term still retain their founder in
-- the governance rule metadata; use that identity as the safe fallback.
UPDATE institutions i
SET administrator_human_id = r.created_by
FROM (
  SELECT DISTINCT ON (institution_id) institution_id, created_by
  FROM governance_rules
  ORDER BY institution_id, version ASC
) r
WHERE i.id = r.institution_id
  AND i.administrator_human_id IS NULL;

DROP TABLE IF EXISTS authority_events;
DROP TABLE IF EXISTS authority_delegations;
DROP TABLE IF EXISTS role_assignments;
DROP TABLE IF EXISTS institution_roles;

CREATE INDEX IF NOT EXISTS institutions_administrator_idx
  ON institutions(administrator_human_id);
