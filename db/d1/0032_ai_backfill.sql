INSERT OR IGNORE INTO ai_assistants (id, owner_id, tier, policy, enabled)
SELECT 'AI-' || humans.id, humans.id, 'basic', 'recommend', 1
FROM humans
WHERE humans.life_status = 'active';
