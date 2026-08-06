# Changelog

## [Unreleased]

### Added — Settings screen with six sections

- `components/SettingsScene.xml|brs`: Full Settings screen with Account, Server, Playback, Captions, Watch History, and About sections — accessible from the home screen gear icon.

### Added — Audiobook library and chapter-marked player

- `source/lib/AudiobookManager.brs`, `components/AudiobookScene.xml|brs`, `components/AudiobookPlayerScene.xml|brs`: Dedicated audiobook library with chapter navigation and a player that resumes from the last position.

### Added — Real markWatched / markUnwatched

- `source/lib/WatchedManager.brs`: User library now correctly persists watched state server-side. Previously a no-op stub.

### Added — Detail pages enriched with cast, similar items, and ratings

- `components/DetailScene.xml|brs`: Detail screen now shows cast members, similar recommendations, and audience ratings from the server.

### Added — Server-side sort, facet filters, and A-Z jump list on library browse

- `components/LibraryScene.xml|brs`, `source/lib/LibraryManager.brs`: Library browse supports server-side sorting (title, year, rating) and facet filtering (unwatched, in-progress, collection). A-Z letter jump list enables quick navigation of large libraries.

### Added — Next-episode card with countdown and Up Next rail

- `components/PlayerScene.xml|brs`: When a series has a next episode queued, a card appears with a countdown and a cancel button. The home screen Up Next rail surfaces resumable episodes.

### Added — Signed package build script and publishing guide

- `scripts/package-signed.sh`: Produces a signed `.ipk` for Channel Store submission.
- `docs/publishing.md`: Step-by-step guide for building, signing, and submitting the channel.

### Fixed — Replace invalid `halign=` with `horizAlign=` on Label nodes

- `components/ConnectScene.xml`, `components/LoginScene.xml`, `components/RatingBadge.xml`: Replaced four occurrences of `halign=` (not a Label field) with `horizAlign=` (correct field).

### Added — BrightScript test framework (rooibos)

- `bsconfig.json`: Rooibos test framework now installed and wired. `make test-unit` fails if tests are present but the device is not connected, catching missing-device test runs early.

### Fixed — validate-xml now exits non-zero on validation errors

- `Makefile`: The `validate-xml` target now properly returns exit code 1 when XML validation fails, making it a reliable CI gate.

## [R4.10] — 2026-08-05

### Fixed — Remove hardcoded localhost fallback origin (R4.10)

- `source/lib/AppContext.brs`: `GetServerUrl()` no longer falls back to `http://localhost:8096`. Returns "" when no server is configured — callers must check `IsServerConnected()` first and route to Connect.
- `scripts/verify-runtime.sh`: Added CHECK 15 to detect hardcoded localhost URLs in source files.
