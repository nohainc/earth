-- Migration 057: Community application questions, applicant response messages, and rejection reasons.

ALTER TABLE communities
  ADD COLUMN IF NOT EXISTS application_question TEXT NOT NULL DEFAULT '';

ALTER TABLE community_membership_requests
  ADD COLUMN IF NOT EXISTS application_message TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT NOT NULL DEFAULT '';
