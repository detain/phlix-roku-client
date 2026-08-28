# Changelog

## [Unreleased]

### Fixed — parental-controls creates 400'd on the wire shape (S234)

- `OnAddTag` now posts `{tag, tag_type}` and `OnAddSchedule` posts `{name, start_time, end_time, days_of_week, is_active}` — the previous camelCase bodies (`tagType`, `startTime`, …) 400'd against the server on every create. The path is reachable (ParentalControlsScene → ApiTask `createProfileTag`/`createProfileSchedule` → ApiClient).
- The list read paths now consume the server's snake_case emission: `ScheduleCaption` reads `days_of_week`/`start_time`/`end_time`/`is_active` and `TagCaption` reads `tag_type` (the camelCase reads rendered empty captions).
- `ApiClient.brs` payload comments updated to document the snake_case shapes. Refs: S234

### Added — Hub relay pending_command consumer (S298)

"Alexa, play X" (the hub's S93 `pending_command` push) can now land on an open Roku app. A new `HubCommandTask` runs whenever the app is open in hub mode with a picked server (NOT gated on a SyncPlay room join): it mints a per-user, server-scoped relay token from the hub (`POST /api/v1/me/servers/{serverId}/relay-token`), connects a raw RFC6455 socket to `ws://<hub>:8804/syncplay/{server_id}` with the token on the `Authorization: Bearer` header (S237 — never the query string), and forwards only `pending_command`/`play_media` frames to the scene, which routes them through the existing R6.3 deep-link machinery into playback. The socket lifecycle is open-whenever with a bounded reconnect ladder (5 attempts, 1s/2s/4s/8s/16s) that re-mints the relay token on every attempt (they expire hourly) and counts post-connect drops as ladder attempts. The dead `buildWsParts()` (the only estate-wide `:8804` reference, inside a function with zero callers, carrying the token in the query string) is removed; `SyncPlayProtocol.BuildHandshakeRequest` gains an optional `extraHeaders` parameter so a raw handshake can carry the Authorization header without disturbing the existing `:8097` caller. Refs: S298

### Fixed — CI runtime-defect gate (verify-runtime.sh) re-enabled

- Removed all hardcoded `/home/sites/phlix/...` paths from `scripts/verify-runtime.sh`. It now derives `REPO` from its own location and `SERVER_DIR` from `PHLIX_SERVER_DIR` or the sibling `phlix-server` checkout. Checks 11-19 had never run in CI since 2026-08-08 — the script crashed at Check 11 with FileNotFoundError — so `package` / `package-signed` / `release-latest` were being skipped (a skipped job counts as success).
- Removed the `|| true` neuter in `lint.yml`. `verify-runtime` is now a hard gate in both `lint.yml` and `package.yml` (the `package` job depends on the `lint-verify-runtime` job).
- Check 14 now reads the server `media_items.type` ENUM from a fresh clone of `detain/phlix-server` in CI (sibling `../phlix-server`, matching the dev sandbox layout).
- All 19 checks now fail the build: checks 1-7 and 12-13 set `VIOLATIONS=1`, per-check python failures accumulate (`PYRET`/`PYOUT`) instead of aborting the run, and the script exits `$((VIOLATIONS))`.
- Added `tests/scripts/verify-runtime-portable.sh`, a standalone regression test that proves the script runs from an arbitrary CI layout with a sibling phlix-server and that a broken ENUM comment makes it exit non-zero.

### Added — Settings screen with six sections

Settings are now organized into six clear sections (Account, Server, Playback, Captions, Watch History, and About), accessible directly from the home screen gear icon. Refs: R9.8

### Added — Audiobook library and chapter-marked player

Audiobook listeners can browse their library and pick up exactly where they left off with chapter navigation and automatic position resuming. Refs: R9.8

### Added — Real markWatched / markUnwatched

Watched status now persists correctly to the server, so your progress is saved across sessions. Previously this was a non-functional placeholder. Refs: R9.4

### Added — Detail pages enriched with cast, similar items, and ratings

Detail screens now display cast members, similar title recommendations, and audience ratings provided by the server. Refs: R9.4

### Added — Server-side sort, facet filters, and A-Z jump list on library browse

Library browsing supports server-side sorting by title, year, or rating, and filtering by unwatched, in-progress, or collection. A-Z letter jump list enables quick navigation of large libraries. Refs: R9.8

### Added — Next-episode card with countdown and Up Next rail

When a series has a next episode queued, a countdown card appears with an option to cancel. The home screen Up Next rail surfaces resumable episodes. Refs: R9.8

### Added — Signed package build script and publishing guide

A new signed package build script (`scripts/package-signed.sh`) and step-by-step publishing guide (`docs/publishing.md`) simplify Channel Store submission. Refs: R9.8

### Fixed — Label alignment now renders correctly on Connect, Login, and Rating screens

Four instances of an invalid field name (`halign=`) were replaced with the correct field (`horizAlign=`) on Label nodes in the Connect, Login, and Rating Badge screens. Refs: R9.2

### Added — BrightScript test framework (rooibos)

Rooibos test framework is now installed and wired. The `make test-unit` command now properly fails when tests exist but no device is connected, catching missing-device test runs early in development. Refs: R9.3

### Fixed — validate-xml is now a reliable CI gate

The `validate-xml` Makefile target now correctly returns exit code 1 on validation failure, making it a dependable CI gate. Refs: R9.3

## [R4.10] — 2026-08-05

### Fixed — Remove hardcoded localhost fallback origin (R4.10)

- `source/lib/AppContext.brs`: `GetServerUrl()` no longer falls back to `http://localhost:8096`. Returns "" when no server is configured — callers must check `IsServerConnected()` first and route to Connect.
- `scripts/verify-runtime.sh`: Added CHECK 15 to detect hardcoded localhost URLs in source files.
