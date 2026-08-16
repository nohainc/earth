# Local testing with the production PostgreSQL database

The local reference server can hydrate its initial state from the production
PostgreSQL database while keeping test mutations in memory. This is the
recommended mode for local UI and API testing.

## Start safely

Set the connection string at runtime; do not commit it to `.env`, source files,
or documentation:

```bash
DATABASE_URL="$DATABASE_URL" DATABASE_READ_ONLY=true npm run start:prod-local
```

The launcher accepts the usual libpq `sslrootcert=system` parameter and
normalizes it for Node's PostgreSQL driver; no credential or certificate path is
stored by the launcher.

The server listens on `http://127.0.0.1:8787`. The initial `/api/world` state is
read from PostgreSQL. POST commands update only the local process and disappear
when it stops.

The launcher refuses to start without `DATABASE_URL`, and refuses non-local
database writes unless `CONFIRM_PRODUCTION_DB_WRITES=I_UNDERSTAND_PRODUCTION_WRITES`
is explicitly supplied. Production writes are not recommended because this
reference simulator does not provide the Worker’s full transaction and
authorization boundary.

## Acceptance checks

1. Start with an explicit PostgreSQL URI and `DATABASE_READ_ONLY=true`.
2. `GET /api/storage` reports `mode: postgres-reference`.
3. `GET /api/world` reflects the canonical database snapshot.
4. Execute a local POST command and confirm the response changes locally.
5. Query PostgreSQL independently and confirm the local POST did not change
   the database.
6. Stop and restart the server; the local mutation is gone and the canonical
   database snapshot is loaded again.
7. Start without `DATABASE_URL`; the launcher exits with a clear error.
8. Start with non-local `DATABASE_URL` and `DATABASE_READ_ONLY=false` without
   the confirmation flag; the launcher refuses to start.

## Instructions for AI-assisted development

Use this workflow whenever you need to test a new Worker-compatible API or
Flutter change against current production data.

### 1. Inspect before starting

From `earth/`:

```bash
git status --short
git log -3 --oneline
```

Preserve unrelated user changes. Never add the database URI to source files,
`.env` files committed to Git, test fixtures, screenshots, logs, prompts, or
the final report.

### 2. Start the guarded local server

The AI must receive the connection URI through the runtime environment. Use a
local shell variable, secret manager, or task environment; never substitute the
real credential into a committed command or document.

```bash
export EARTH_TEST_DATABASE_URL='[provided securely at runtime]'
DATABASE_URL="$EARTH_TEST_DATABASE_URL" \
DATABASE_READ_ONLY=true \
PORT=8787 \
npm run start:prod-local
```

Expected startup output includes:

```text
read-only database / in-memory mutations
EARTH reference simulator listening on http://127.0.0.1:8787
```

If `DATABASE_URL` is absent, TLS cannot be established, or canonical data
cannot be loaded, stop and report the startup error. Do not start with stale
or partial state and do not switch to a different database silently.

### 3. Verify the server before testing a change

In a second terminal, run:

```bash
curl -fsS http://127.0.0.1:8787/api/storage
curl -fsS http://127.0.0.1:8787/api/health
curl -fsS http://127.0.0.1:8787/api/world
```

Required results:

- `/api/storage` reports `configured: true`, `mode: postgres-reference`, and
  `authority: non-production`.
- `/api/health` reports `ok: true` and `database: true`.
- `/api/world` contains a current canonical snapshot.

Record only safe metadata such as the database hostname, game day, migration
version, and test result. Never record the URI, password, account secret, or
private user data.

### 4. Test API changes

Use the local base URL for requests:

```bash
LOCAL_EARTH_URL='http://127.0.0.1:8787'
curl -fsS "$LOCAL_EARTH_URL/api/world/activity"
```

For every changed command, test all of the following as applicable:

1. Valid request returns the documented success DTO.
2. Malformed JSON returns a safe validation error.
3. Invalid values return the stable error code and correlation ID.
4. Repeating the same correlation/idempotency key does not apply the command
   twice.
5. Unauthorized or out-of-scope actors are rejected.
6. Failed commands do not create partial local state.
7. Events are emitted only after the command succeeds.

The local reference server is useful for compatibility and UI testing. It is
not a substitute for Worker/PostgreSQL transaction tests. Domain mutations that
must be authoritative still require the PostgreSQL adapter tests and the
Cloudflare smoke suite.

### 5. Test Flutter changes against the local server

Start the Flutter client with the local API URL:

```bash
cd flutter_client
flutter run -d chrome \
  --dart-define=EARTH_API_URL=http://127.0.0.1:8787
```

For a release build:

```bash
flutter analyze
flutter test
flutter build web --release --base-href / \
  --dart-define=EARTH_API_URL=http://127.0.0.1:8787
```

Verify the changed screen in the browser, including loading, success, empty,
error, retry, and logout states. Confirm that the client does not display
optimistic financial or governance results before the server response.

### 6. Test live events

Open the local event stream:

```bash
curl -N http://127.0.0.1:8787/api/events
```

Then perform a supported local command in another terminal. Confirm:

- The initial `connected` event is received.
- A successful command produces one event with data framing.
- Duplicate event delivery is ignored by the client.
- A failed command produces no success event.
- Reconnecting does not create duplicate UI state.

The reference server's events are local compatibility behavior. Worker Durable
Object broadcast and PostgreSQL outbox delivery must additionally be verified
with their focused tests and the deployed smoke suite.

### 7. Confirm read-only protection

Before stopping the server, record the relevant state from `/api/world`. After
performing local POST commands, run the database verification checks against the
same approved target:

```bash
DATABASE_URL="$EARTH_TEST_DATABASE_URL" npm run db:verify:manifest
DATABASE_URL="$EARTH_TEST_DATABASE_URL" npm run db:verify:invariants
```

The checks must still pass, and the AI must report that local mutations were
not persisted. Never set `DATABASE_READ_ONLY=false` for routine testing.

### 8. Stop and clean up

Stop the local server with `Ctrl-C`, then unset the runtime credential:

```bash
unset EARTH_TEST_DATABASE_URL
```

Check the worktree:

```bash
git status --short
```

Do not commit generated build output, credentials, logs, or unrelated lockfile
changes. Report the exact files changed, commands run, passing/failing tests,
and any environment blockers.

### AI acceptance checklist

A change is ready for handoff only when:

- the guarded server started from an explicit database target;
- health and canonical snapshot checks passed;
- focused tests and `npm test` passed;
- Flutter analyzer/tests/build passed when Flutter code changed;
- changed API success, validation, authorization, replay, and failure paths
  were tested;
- local POST mutations were proven not to persist to PostgreSQL;
- live-event behavior was tested where applicable;
- no credentials or private data were written to the repository or report;
- known blockers and deferred production verification are clearly listed.
