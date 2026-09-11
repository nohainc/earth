-- Technology & Research V2 Plan 11: remove obsolete industrial access layers.
-- Corporation access is now represented by corporation_technology_access.

DROP TABLE IF EXISTS human_technology_subscriptions;
DROP TABLE IF EXISTS human_technology_adoptions;
DROP TABLE IF EXISTS corporation_technology_shares;

