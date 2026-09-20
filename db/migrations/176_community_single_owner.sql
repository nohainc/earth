-- V5 Communities have exactly one active OWNER. Moderators are delegated managers.

WITH ranked_owners AS (
  SELECT community_id, house_id,
         ROW_NUMBER() OVER (
           PARTITION BY community_id
           ORDER BY joined_at ASC, house_id ASC
         ) AS owner_rank
  FROM community_memberships
  WHERE status = 'ACTIVE' AND role = 'OWNER'
)
UPDATE community_memberships cm
SET role = 'MODERATOR', updated_at = CURRENT_TIMESTAMP
FROM ranked_owners ro
WHERE ro.community_id = cm.community_id
  AND ro.house_id = cm.house_id
  AND ro.owner_rank > 1;

CREATE UNIQUE INDEX community_one_active_owner_uq
  ON community_memberships (community_id)
  WHERE status = 'ACTIVE' AND role = 'OWNER';
