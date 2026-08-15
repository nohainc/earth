ALTER TABLE machines ADD COLUMN input_per_output NUMERIC NOT NULL DEFAULT 0.25;
UPDATE machines SET input_per_output = CASE output_resource WHEN 'material' THEN 0.15 WHEN 'energy' THEN 0.08 WHEN 'compute' THEN 0.2 ELSE 0.25 END;
CREATE INDEX IF NOT EXISTS machines_input_resource_idx ON machines(input_resource, condition, utilization);
