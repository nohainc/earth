DELETE FROM constitutional_rules;

INSERT INTO constitutional_rules (id, part_number, article_number, rule_number, title, description, default_value, permitted_values)
VALUES
  ('RULE-1-1', 1, 1, '1.1', 'Basic Income Levy', 'Earth applies the default levy to eligible citizens; a permitted institution charter may replace the rate.', 'Active Earth tax-rule rate', '0–50%'),
  ('RULE-1-2', 1, 1, '1.2', 'Business Tax Rate', 'Earth applies the default rate to taxable business revenue; a permitted institution charter may replace the rate.', 'Active Earth tax-rule rate', '0–50%'),
  ('RULE-1-3', 1, 1, '1.3', 'Market Sales Tax Rate', 'Earth supplies the market rate; a permitted institutional charter may replace the rate for an affiliated user.', 'Active Earth market tax-rule rate', '0–25%'),
  ('RULE-2-1', 2, 1, '2.1', 'Quorum', 'A proposal must reach the active governance-rule participation threshold to be valid.', '25%', 'Active governance-rule value'),
  ('RULE-2-2', 2, 1, '2.2', 'Approval Threshold', 'A valid proposal must reach the active governance-rule approval threshold to pass.', '50%', 'Active governance-rule value'),
  ('RULE-2-3', 2, 1, '2.3', 'Implementation Delay', 'A passed proposal waits before it may be executed.', '1 game day', NULL),
  ('RULE-3-1', 3, 1, '3.1', 'Corporation Admission Policy', 'A corporation decides whether eligible applicants join immediately or require approval.', 'Open', 'Open or approval');
