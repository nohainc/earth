-- Keep the applicant's original message immutable while storing a separate
-- moderator decision/rejection note.

ALTER TABLE community_membership_requests
  ADD COLUMN IF NOT EXISTS decision_note TEXT NULL;
