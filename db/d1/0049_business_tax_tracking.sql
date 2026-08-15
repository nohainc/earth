ALTER TABLE business_financials ADD COLUMN taxed_revenue NUMERIC NOT NULL DEFAULT 0 CHECK (taxed_revenue >= 0);
