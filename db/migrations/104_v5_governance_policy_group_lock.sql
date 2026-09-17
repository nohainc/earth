-- EARTH ACTIVE MIGRATION: enforce one active amendment per authority/policy group.

CREATE UNIQUE INDEX v5_governance_one_active_policy_group_idx
  ON v5_governance_proposals (
    subject_type,
    COALESCE(subject_id, ''),
    policy_group
  )
  WHERE status IN ('VOTING', 'PASSED', 'SCHEDULED');
