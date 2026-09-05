---
description: Every URL this client issues must be tuple-exact against the vendored phlix-server route manifest (S280 gate)
globs:
  - source/lib/ApiClient.brs
  - components/*.brs
  - tests/scripts/verify-route-manifest.mjs
  - tests/fixtures/server-route-manifest.json
alwaysApply: false
---

# S280 route manifest gate

`make validate-routes` runs `node tests/scripts/verify-route-manifest.mjs`, which statically
scans every URL the client can put on the wire and compares it **tuple-exact** (`[method,
pathTemplate]`) against `tests/fixtures/server-route-manifest.json` — a byte-for-byte vendored
copy of the `@phlix/contracts` server route manifest. It is a hard gate in
`.github/workflows/test.yml`.

## Rules

- **Matching is segment-wise, never substring.** `{param}` spans exactly one path segment, so
  `/api/v1/media/{id}` can never absorb `/api/v1/media/{id}/markers`. Adding a request site the
  server does not register fails the gate by name.
- **Adding an endpoint** means the server registers it first; then re-vendor the manifest. Never
  hand-edit `tests/fixtures/server-route-manifest.json` — it is generated.
- **Re-vendoring moves the pins.** `PROVENANCE_SHA` and `TOTAL_TUPLES` at the top of
  `tests/scripts/verify-route-manifest.mjs` must be updated in the same commit as the fixture,
  or the gate reds.
- **Hub-origin routes are partitioned, not exempt.** `GET /api/v1/me/servers` lives in the
  `PARTITIONED` list in the scanner with a written reason, and the gate asserts the path is
  *absent* from the server manifest. Adding a partition entry moves its pinned count.
- **Falsifiability is part of the gate.** `make validate-routes` also runs
  `node tests/scripts/verify-route-manifest.mjs --self-test`, which plants an unserved URL and
  asserts the check goes red. Do not weaken it into a check that can only pass.
