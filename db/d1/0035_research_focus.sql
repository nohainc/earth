ALTER TABLE research_projects ADD COLUMN focus TEXT NOT NULL DEFAULT 'efficiency' CHECK (focus IN ('efficiency','durability','safety','cost'));
