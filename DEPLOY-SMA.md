# Activepieces tester environment

Tested source: upstream `0.88.3`, commit `54babcf9b3c6079125042134e2f70c7ce0f97a6a`.

## Deploy

```bash
./tester-env deploy
```

This builds the root `Dockerfile` from this checkout, starts Activepieces with
Postgres and Redis, and creates the deterministic platform owner:

```text
URL: http://localhost:18100/
Browser MCP URL: http://host.docker.internal:18100/
Email: owner@tester-env.local
Password: TesterEnv1234!
```

`PORT=18100` is the default. Override it with `--port <port>` or `PORT=<port>`.
`IMAGE_TAG` is honored for content-addressed scenario images; `RUN_ID` scopes
containers and volumes through `--run-id`.
`PIECES_TIMEOUT_SECONDS` (default 600) bounds the piece-catalog readiness wait.

## Piece catalog readiness

The app syncs ~13k piece rows from the cloud in the background after first
boot (about 6 min solo, ~10 min with two parallel clean deploys in 0.88.3,
latest-first). Two properties make a plain wait unreliable: the API freezes
its in-process piece registry on the first metadata read, so metadata/options
calls stay blind until the streaming sync ends and invalidates it; and the
seed-pinned `@activepieces/piece-schedule@0.1.21` is an old row that only
lands at the tail of the stream.

Deploy therefore pre-inserts a minimal snapshot (schedule 0.1.21, http
0.12.1, byte-identical to what the sync stores) into Postgres before the
first metadata read, then waits until both metadata GETs resolve. The
background sync skips existing rows and keeps streaming the rest; the
DELETE+INSERT runs in one transaction, so re-deploying over existing volumes
is safe. If the budget (`PIECES_TIMEOUT_SECONDS`, default 600) expires,
deploy fails loudly instead of reporting a healthy app with a partial
catalog; rerunning deploy resumes the sync incrementally on the same volumes.

Regenerate the embedded snapshot when the pinned versions change:

```bash
mkdir -p ../../.work/tmp/activepieces-snapshot
curl -fsS "https://cloud.activepieces.com/api/v1/pieces/@activepieces/piece-schedule?version=<ver>" -o ../../.work/tmp/activepieces-snapshot/schedule.json
curl -fsS "https://cloud.activepieces.com/api/v1/pieces/@activepieces/piece-http?version=<ver>" -o ../../.work/tmp/activepieces-snapshot/http.json
# emit DELETE+INSERT for piece_metadata replicating pieceMetadataService.create()
# (quoted identifiers, dollar-quoted JSON, fixed 21-char ids) into piece_snapshot_sql()
```

## Worker self-callback

The embedded worker resolves piece bundles and dynamic property options
(`POST /api/v1/pieces/options`, `EXECUTE_PROPERTY` jobs) through the public
API URL derived from `AP_FRONTEND_URL` (`http://localhost:<host-port>`). That
host port does not exist inside the app container, so without a fix every
dynamic piece dropdown fails with `fetch failed` server-side and renders
`Unexpected error, please retry` in the builder (HTTP `Body Type` cannot reach
JSON). The entrypoint therefore forwards loopback `<host-port>` to the app
port (`AP_PORT`, 80) with a small node TCP proxy; `HOST_PORT` is injected by
`docker-compose.tester-env.yml`. No browser-facing URL changes.

## Reset and inspect

```bash
./tester-env reset
./tester-env deploy
./tester-env status
./tester-env logs
```

`reset` removes only this environment's Compose containers, network, and named
volumes; it retains the built image.

## Seed and verify

```bash
./tester-env seed
./tester-env verify
```

The deterministic product baseline is a small operations workspace:

- Folders: `Seed Folder` (empty), `Customer Support` (2 flows), and `Finance Operations` (1 flow).
- Disabled draft flows: `New Ticket Triage`, `Weekly Escalation Digest`, and `Supplier Invoice Review`.

Seed uses local authenticated API calls, is safe to repeat, and creates no
external connections. Verify checks the owner and these API-visible entities.

Browser checker handoff: sign in, open the flows list, verify the three named
flows have the `Disabled` status, then open `Customer Support` and verify its
two flows; `Finance Operations` contains `Supplier Invoice Review`.
