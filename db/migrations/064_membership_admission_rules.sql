INSERT INTO constitutional_rules (
  id, part_number, article_number, rule_number, title, description,
  default_value, permitted_values, authority, active
)
VALUES
  (
    'RULE-3-2', 3, 1, '3.2', 'City Admission Policy',
    'A city follows the admission policy of its parent corporation. A city cannot override that policy.',
    'Parent corporation policy', NULL, 'Corporation', true
  ),
  (
    'RULE-3-3', 3, 1, '3.3', 'Community Admission Policy',
    'A community chooses whether eligible citizens join immediately or require approval.',
    'Open', 'Open or approval', 'Community', true
  )
ON CONFLICT (id) DO UPDATE SET
  part_number = EXCLUDED.part_number,
  article_number = EXCLUDED.article_number,
  rule_number = EXCLUDED.rule_number,
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  default_value = EXCLUDED.default_value,
  permitted_values = EXCLUDED.permitted_values,
  authority = EXCLUDED.authority,
  active = true,
  updated_at = now();
