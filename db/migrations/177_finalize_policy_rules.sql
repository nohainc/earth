-- Plan 27: finalize canonical policy values and expose wear to consumers.

INSERT INTO economic_policy_rules (code, output_multiplier, cost_multiplier, decay_multiplier, description) VALUES
  ('overclock', 1.60, 1.90, 3.00, 'Extreme output with extreme operating cost and wear')
ON CONFLICT (code) DO UPDATE SET
  output_multiplier = EXCLUDED.output_multiplier,
  cost_multiplier = EXCLUDED.cost_multiplier,
  decay_multiplier = EXCLUDED.decay_multiplier,
  description = EXCLUDED.description;

UPDATE economic_policy_rules
SET decay_multiplier = 0.10,
    description = 'Production halted with minimum operating cost and low residual wear'
WHERE code = 'halted';
