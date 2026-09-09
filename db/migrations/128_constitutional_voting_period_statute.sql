-- 128_constitutional_voting_period_statute.sql
-- Adds Article 2.4 "Voting Period" to the constitutional rule registry.

INSERT INTO constitutional_rules (id, part_number, article_number, rule_number, title, description, default_value, permitted_values)
VALUES
  ('RULE-2-4', 2, 1, '2.4', 'Voting Period', 'A proposal remains open for voting for the duration specified by the active governance rule before outcome resolution.', '3 game days', '1–14 game days')
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  default_value = EXCLUDED.default_value,
  permitted_values = EXCLUDED.permitted_values,
  active = true;
