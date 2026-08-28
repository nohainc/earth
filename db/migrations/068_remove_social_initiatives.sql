-- Remove the retired social-initiatives feature and all of its operational data.
-- Research projects, civic megaprojects, contracts, and non-social notifications remain intact.

DELETE FROM notifications
WHERE notification_type = 'social'
   OR id LIKE 'SOCIAL-%'
   OR entity_id LIKE 'social-%';

DELETE FROM world_events
WHERE event_type LIKE 'social.%'
   OR (event_type = 'institution.project_completed' AND details LIKE '%initiativeId%');

DELETE FROM ledger_entries
WHERE reason_type IN ('social_escrow_lock', 'social_escrow_release', 'social_escrow_forfeit')
   OR reason_id LIKE 'social-%'
   OR debit_account LIKE 'social-social-%'
   OR credit_account LIKE 'social-social-%';

DELETE FROM account_balances
WHERE account_id LIKE 'social-social-%'
   OR owner_id LIKE 'social-social-%';

DROP TABLE IF EXISTS social_initiative_members;
DROP TABLE IF EXISTS social_initiatives;
DROP TABLE IF EXISTS social_relationships;
