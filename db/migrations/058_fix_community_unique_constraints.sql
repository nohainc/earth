-- Migration 058: Drop restrictive unique constraint on community_membership_requests so users can re-apply/re-join freely.
ALTER TABLE community_membership_requests
  DROP CONSTRAINT IF EXISTS community_membership_requests_community_id_human_id_status_key;
