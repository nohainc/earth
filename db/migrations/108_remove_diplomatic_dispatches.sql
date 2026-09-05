-- Migration 108: remove the unused private diplomatic-mail system.
-- Player communication is provided by channels; contracts, governance, and
-- lifecycle events remain in their own records and system notifications.

DROP TABLE IF EXISTS diplomatic_dispatches;
