INSERT INTO tax_rules (id, scope, category, rate, active, version)
VALUES ('TAX-OUC-BUSINESS', 'BUSINESS', 'revenue-tax', 0.02, 1, 1)
ON CONFLICT(id) DO UPDATE SET scope = excluded.scope, category = excluded.category, rate = excluded.rate, active = excluded.active, version = excluded.version;
