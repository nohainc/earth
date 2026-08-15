ALTER TABLE auth_credentials ADD COLUMN mfa_secret TEXT;
ALTER TABLE auth_credentials ADD COLUMN mfa_enabled INTEGER NOT NULL DEFAULT 0;
