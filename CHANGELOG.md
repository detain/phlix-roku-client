# Changelog

## [Unreleased]

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
