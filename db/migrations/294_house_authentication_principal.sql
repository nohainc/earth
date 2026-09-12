-- Death, Inheritance & House Continuity V2 Plan 2.
-- Authentication belongs to the persistent House, not its current Human.

CREATE TABLE IF NOT EXISTS auth_accounts (
  id TEXT PRIMARY KEY,
  house_id TEXT NOT NULL REFERENCES houses(id),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  password_iterations INTEGER NOT NULL DEFAULT 100000,
  email_verified_at TIMESTAMPTZ,
  mfa_secret TEXT,
  mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO auth_accounts (
  id, house_id, email, password_hash, password_salt, password_iterations,
  email_verified_at, mfa_secret, mfa_enabled, created_at
)
SELECT 'AUTH-' || h.house_id, h.house_id, c.email, c.password_hash, c.password_salt,
       c.password_iterations, c.email_verified_at, c.mfa_secret, c.mfa_enabled, c.created_at
FROM auth_credentials c
JOIN humans h ON h.id = c.human_id
ON CONFLICT (id) DO UPDATE SET house_id = EXCLUDED.house_id;

ALTER TABLE auth_sessions
  ADD COLUMN IF NOT EXISTS account_id TEXT;

UPDATE auth_sessions s
SET account_id = a.id
FROM auth_accounts a
JOIN humans h ON h.house_id = a.house_id
WHERE s.account_id IS NULL AND s.human_id = h.id;

-- A legacy session may outlive a deleted/incomplete credential record. Such a
-- session cannot authenticate through the new House principal, so remove it
-- before enforcing the non-null account relationship. Valid sessions above
-- retain their token, expiry, revocation state, and session ID.
DELETE FROM auth_sessions s
WHERE s.account_id IS NULL;

ALTER TABLE auth_sessions
  ALTER COLUMN account_id SET NOT NULL;
ALTER TABLE auth_sessions
  ADD CONSTRAINT auth_sessions_account_fk FOREIGN KEY (account_id) REFERENCES auth_accounts(id);
CREATE INDEX IF NOT EXISTS auth_sessions_account_idx ON auth_sessions(account_id, revoked_at, expires_at);

ALTER TABLE auth_action_tokens
  ADD COLUMN IF NOT EXISTS account_id TEXT;

UPDATE auth_action_tokens t
SET account_id = a.id
FROM auth_accounts a
JOIN humans h ON h.house_id = a.house_id
WHERE t.account_id IS NULL AND t.human_id = h.id;

DELETE FROM auth_action_tokens t
WHERE t.account_id IS NULL;

ALTER TABLE auth_action_tokens
  ALTER COLUMN account_id SET NOT NULL;
ALTER TABLE auth_action_tokens
  ADD CONSTRAINT auth_action_tokens_account_fk FOREIGN KEY (account_id) REFERENCES auth_accounts(id);
CREATE INDEX IF NOT EXISTS auth_action_tokens_account_idx ON auth_action_tokens(account_id, action, consumed_at);

COMMENT ON TABLE auth_accounts IS
  'Stable authentication principal for a House; the current Human may change without logout.';
COMMENT ON COLUMN auth_sessions.account_id IS
  'Persistent House authentication principal. human_id is retained only as a migration compatibility field.';

-- Closing a Human must not revoke the House's authentication sessions. The
-- session resolves the current incumbent through houses.current_human_id, so
-- succession changes the character visible to the player without logging the
-- persistent House principal out.
CREATE OR REPLACE FUNCTION earth_close_human(p_human_id TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE humans
  SET account_status = 'closed', deleted_at = COALESCE(deleted_at, NOW())
  WHERE id = p_human_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Human % not found', p_human_id;
  END IF;
  UPDATE owner_registry
  SET status = 'closed', updated_at = NOW()
  WHERE source_id = p_human_id;
END;
$$;
