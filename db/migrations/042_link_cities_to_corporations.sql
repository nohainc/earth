-- Migration 042: make the canonical city/corporation affiliation explicit.
-- Existing city membership remains intact; this only links the seeded city
-- to the seeded corporation so residency can carry corporation membership.

UPDATE cities
SET corporation_id = 'CORP-001'
WHERE id = 'CITY-0084'
  AND corporation_id IS NULL
  AND EXISTS (SELECT 1 FROM corporations WHERE id = 'CORP-001');
