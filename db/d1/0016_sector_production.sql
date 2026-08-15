ALTER TABLE businesses ADD COLUMN sector TEXT NOT NULL DEFAULT 'maintenance';
ALTER TABLE machines ADD COLUMN output_resource TEXT NOT NULL DEFAULT 'components';
ALTER TABLE machines ADD COLUMN input_resource TEXT NOT NULL DEFAULT 'energy';
UPDATE businesses SET sector = 'maintenance' WHERE sector IS NULL OR sector = '';
UPDATE machines SET output_resource = CASE machine_type WHEN 'extractor' THEN 'material' WHEN 'energy-array' THEN 'energy' WHEN 'compute-node' THEN 'compute' ELSE 'components' END;
CREATE INDEX IF NOT EXISTS machines_output_resource_idx ON machines(output_resource, condition, utilization);
