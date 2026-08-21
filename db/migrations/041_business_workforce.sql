-- Staff are business assets with wages, skills, and morale. They make the
-- management loop about people as well as machines.
CREATE TABLE IF NOT EXISTS business_employees (
  id text primary key,
  business_id text not null references businesses(id) on delete cascade,
  name text not null,
  role text not null,
  skill numeric(5,2) not null default 0.60 check (skill >= 0 and skill <= 1),
  morale numeric(5,2) not null default 0.75 check (morale >= 0 and morale <= 1),
  wage numeric(20,2) not null default 40 check (wage >= 0),
  status text not null default 'active' check (status in ('active','leave','dismissed')),
  hired_game_day bigint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
CREATE INDEX IF NOT EXISTS business_employees_business_idx
  ON business_employees(business_id, status);

INSERT INTO business_employees (id, business_id, name, role, skill, morale, wage, hired_game_day)
SELECT 'EMP-' || substr(md5(b.id || seed.role), 1, 12), b.id, seed.name, seed.role,
       seed.skill, seed.morale, seed.wage, COALESCE(w.game_day, 1)
FROM businesses b
CROSS JOIN (VALUES
  ('Mara Voss', 'Operations Lead', 0.82, 0.80, 85.00),
  ('Ilan Roe', 'Systems Technician', 0.71, 0.76, 62.00),
  ('Nia Sol', 'Client Coordinator', 0.66, 0.84, 54.00)
) AS seed(name, role, skill, morale, wage)
LEFT JOIN world_state w ON w.id = 'WORLD'
WHERE NOT EXISTS (
  SELECT 1 FROM business_employees e WHERE e.business_id = b.id
);
