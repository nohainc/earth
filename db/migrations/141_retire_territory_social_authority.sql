-- EARTH ACTIVE MIGRATION: narrow Territory to physical/geographic context
--
-- Territory remains a canonical location and capacity primitive. The former
-- governance, lease, and commons objects are retained as immutable history so
-- old installations remain readable, but no longer participate in V5 runtime
-- settlement or player-facing API contracts.

COMMENT ON TABLE territory_governance IS
  'LEGACY HISTORY ONLY: Territory is not a V5 government or political authority.';
COMMENT ON TABLE territory_rights IS
  'LEGACY HISTORY ONLY: V5 capacity is derived from House and Corporation assets.';
COMMENT ON TABLE territory_lease_payments IS
  'LEGACY HISTORY ONLY: Territory does not collect rent or operate a treasury in V5.';
COMMENT ON TABLE territory_right_events IS
  'LEGACY HISTORY ONLY: retained for historical audit of retired Territory rights.';
COMMENT ON TABLE commons_dividend_policies IS
  'LEGACY HISTORY ONLY: Territory commons dividends are not a V5 economic authority.';
COMMENT ON TABLE commons_dividend_declarations IS
  'LEGACY HISTORY ONLY: retained for historical audit of retired Territory dividends.';
COMMENT ON TABLE commons_dividend_payments IS
  'LEGACY HISTORY ONLY: retained for historical audit of retired Territory dividends.';
