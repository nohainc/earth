-- Remove trailing ' Chat' suffix from corporation, community, and city comm_channels
UPDATE comm_channels
SET name = regexp_replace(name, ' Chat$', '')
WHERE scope IN ('corporation', 'community', 'city')
  AND name LIKE '% Chat';
