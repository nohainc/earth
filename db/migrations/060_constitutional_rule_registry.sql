CREATE TABLE IF NOT EXISTS constitutional_rules (
  id text PRIMARY KEY,
  part_number integer NOT NULL,
  article_number integer NOT NULL DEFAULT 1,
  rule_number text NOT NULL UNIQUE,
  title text NOT NULL,
  description text NOT NULL,
  default_value text NOT NULL,
  permitted_values text,
  active boolean NOT NULL DEFAULT true,
  updated_game_day bigint,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS constitutional_rules_active_order_idx
  ON constitutional_rules (active, part_number, article_number, rule_number);

INSERT INTO constitutional_rules (id, part_number, article_number, rule_number, title, description, default_value, permitted_values)
VALUES
  ('CONST-1-1', 1, 1, '1.1', 'Rule Precedence', 'A city override replaces a corporation override; a corporation override replaces the Earth baseline.', 'Earth baseline', 'Earth, Corporation, or City source'),
  ('CONST-1-2', 1, 1, '1.2', 'Override Authority', 'A rule may be changed only by the institutional levels explicitly permitted for that rule.', 'Rule-specific authority', 'Only the levels named by that rule'),
  ('CONST-2-1', 2, 1, '2.1', 'Income Tax Rate', 'The Earth levy is the fallback. A permitted city or corporation charter rate replaces it.', 'Earth income levy', '0–50%'),
  ('CONST-2-2', 2, 1, '2.2', 'Sales Tax Rate', 'Applies through the City → Corporation → Earth resolution order.', 'Earth sales levy', '0–25%'),
  ('CONST-2-3', 2, 1, '2.3', 'Corporate Tax Rate', 'The active local charter rate is used when present; otherwise the Earth business levy applies.', 'Earth business levy', '0–50%'),
  ('CONST-2-4', 2, 1, '2.4', 'Property Tax Rate', 'Defined for institutional charters; its economic settlement is reserved for the property-tax system.', 'Earth property baseline', '0–30%'),
  ('CONST-3-1', 3, 1, '3.1', 'Proposal Eligibility', 'An active, politically eligible resident or corporation member may propose and vote in that institution.', 'Active, politically eligible member or resident', NULL),
  ('CONST-3-2', 3, 1, '3.2', 'Quorum & Approval', 'Active governance-rule versions supply the quorum and approval values for a proposal.', '25% quorum · 50% approval', 'Active governance-rule version'),
  ('CONST-3-3', 3, 1, '3.3', 'Cooling-Off & Appeal', 'Passed proposals wait before execution and may be constitutionally challenged.', '1 game-day implementation delay', NULL),
  ('CONST-4-1', 4, 1, '4.1', 'Corporation Admission Policy', 'A corporation selects open entry or approval-based membership for its own institution.', 'Open admission', 'Open or approval')
ON CONFLICT (id) DO NOTHING;
