INSERT INTO constitutional_rules (
  id, part_number, article_number, rule_number, title, description,
  default_value, permitted_values, authority, active
)
VALUES
  (
    'RULE-1-4', 1, 1, '1.4', 'Business-Tax Allocation',
    'Business-tax revenue is allocated between the resident city, parent corporation, and Earth treasury.',
    'City 60% · Corporation 25% · Earth 15%', NULL, 'Earth', true
  ),
  (
    'RULE-2-4', 2, 1, '2.4', 'Political Eligibility',
    'Only an active citizen who has reached their recorded political-maturity day may hold civic office.',
    'Active citizen after political maturity', NULL, 'Earth', true
  ),
  (
    'RULE-3-4', 3, 1, '3.4', 'City–Corporation Affiliation',
    'A city belongs to a parent corporation, and residency must remain compatible with that corporation membership.',
    'Parent corporation affiliation required', NULL, 'Earth', true
  ),
  (
    'RULE-4-5', 4, 1, '4.5', 'Estate Liquidation',
    'An unclaimed estate is liquidated after the statutory estate buffer expires.',
    'After 30 game days', NULL, 'Earth', true
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
