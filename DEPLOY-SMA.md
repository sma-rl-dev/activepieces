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
