INSERT INTO constitutional_rules (
  id, part_number, article_number, rule_number, title, description,
  default_value, permitted_values, authority, active
)
VALUES
  (
    'RULE-4-1', 4, 1, '4.1', 'Primary Heir Allocation',
    'The designated primary heir receives liquid estate credits and all transferable productive assets.',
    '70%', NULL, 'Earth', true
  ),
  (
    'RULE-4-2', 4, 1, '4.2', 'Municipal Trust Allocation',
    'The deceased citizen’s resident city receives a statutory allocation for public services.',
    '20%', NULL, 'Earth', true
  ),
  (
    'RULE-4-3', 4, 1, '4.3', 'House Reserve Allocation',
    'A statutory allocation is reserved for the citizen’s House and its generational continuity.',
    '10%', NULL, 'Earth', true
  ),
  (
    'RULE-4-4', 4, 1, '4.4', 'Estate Buffer',
    'An unclaimed estate remains protected before public liquidation.',
    '30 game days', NULL, 'Earth', true
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
