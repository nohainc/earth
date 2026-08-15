ALTER TABLE world_state ADD COLUMN living_cost_index NUMERIC NOT NULL DEFAULT 1.0;
ALTER TABLE world_state ADD COLUMN essential_services_index NUMERIC NOT NULL DEFAULT 0.68;
