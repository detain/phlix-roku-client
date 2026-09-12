# Changelog

## [Unreleased]

### Changed — W79 (cs42): route-manifest currency re-pin to current server master — 2026-09-12

- **cs#42 currency re-pin cascade (lane cs42).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #29 against the current phlix-server
  master tip). **Pure provenance re-pin, not a content change:** the server span
  since the prior pin is four commits of SyncPlay bridge/worker/room and
  WebSocket plumbing work, a catalog-pin bump and an AGENTS.md theming
  paragraph — an empty diff on the two route-bearing guard-constant files — so
  the manifest still carries exactly 402 `[method, path]` tuples and the stripped
  route content is unchanged (the estate fence digest measures equal
  old-vs-new) — only `provenance.serverSha` / `generatedAt` advance. The single
  code pin `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA`) moves in
  the same commit; the client-route scan it runs stays exactly as before — 91
  request sites / 81 distinct tuples across 2 modules, tuple-exact. No Roku
  request surface changed.

### Changed — W75 (cs41): route-manifest currency re-pin to current server master — 2026-09-12

- **cs#41 currency re-pin cascade (lane cs41).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #28 against the current phlix-server
  master tip). **Pure provenance re-pin, not a content change:** the server span
  since the prior pin is one merge confined to the parallel-suite
  junit-merge tooling, two new guard tests and changelog/release-journal
  prose — nothing under the route-surface directories — so
  the manifest still carries exactly 402 `[method, path]` tuples and the stripped
  route content is unchanged (the estate fence digest measures equal
  old-vs-new) — only `provenance.serverSha` / `generatedAt` advance. The single
  code pin `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA`) moves in
  the same commit; the client-route scan it runs stays exactly as before — 91
  request sites / 81 distinct tuples across 2 modules, tuple-exact. No Roku
  request surface changed.

### Changed — W72 (cs40): route-manifest currency re-pin to current server master — 2026-09-12

- **cs#40 currency re-pin cascade (lane cs40).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #27 against the current phlix-server
  master tip). **Pure provenance re-pin, not a content change:** the server span
  since the prior pin is three merges confined to parallel-harness
  suite-runner plumbing, an ignore-rule tidy and changelog/release-journal
  prose — nothing under the route-surface directories — so
  the manifest still carries exactly 402 `[method, path]` tuples and the stripped
  route content is unchanged (the estate fence digest measures equal
  old-vs-new) — only `provenance.serverSha` / `generatedAt` advance. The single
  code pin `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA`) moves in
  the same commit; the client-route scan it runs stays exactly as before — 91
  request sites / 81 distinct tuples across 2 modules, tuple-exact. No Roku
  request surface changed.

### Changed — W70 (cs39): route-manifest currency re-pin to current server master — 2026-09-11

- **cs#39 currency re-pin cascade (lane cs39).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #26 against the current phlix-server
  master tip). **Pure provenance re-pin, not a content change:** the server span
  since the prior pin is one packaging-and-installation merge confined to the
  install script, release-process and changelog journals, and one third-party
  clone pin-guard test — nothing under the route-surface directories — so
  the manifest still carries exactly 402 `[method, path]` tuples and the stripped
  route content is unchanged (the estate fence digest measures equal
  old-vs-new) — only `provenance.serverSha` / `generatedAt` advance. The single
  code pin `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA`) moves in
  the same commit; the client-route scan it runs stays exactly as before — 91
  request sites / 81 distinct tuples across 2 modules, tuple-exact. No Roku
  request surface changed.

### Changed — W67 (cs38): route-manifest currency re-pin to current server master — 2026-09-11

- **cs#38 currency re-pin cascade (lane cs38).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #25 against the current phlix-server
  master tip). **Pure provenance re-pin, not a content change:** the server span
  since the prior pin is two commits confined to CI workflow definitions, docker
  example files, helm chart value files, support test files and changelog
  prose — nothing under the route-surface directories — so
  the manifest still carries exactly 402 `[method, path]` tuples and the stripped
  route content is unchanged (the estate fence digest measures equal
  old-vs-new) — only `provenance.serverSha` / `generatedAt` advance. The single
  code pin `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA`) moves in
  the same commit; the client-route scan it runs stays exactly as before — 91
  request sites / 81 distinct tuples across 2 modules, tuple-exact. No Roku
  request surface changed.

### Changed — W63 (cs37): route-manifest currency re-pin to current server master — 2026-09-11

- **cs#37 currency re-pin cascade (lane cs37).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #24 against the current phlix-server
  master tip). **Pure provenance re-pin, not a content change:** the server span
  since the prior pin touched only CI workflow definitions, one CI prerequisite
  script and three test files — nothing under the route-surface directories — so
  the manifest still carries exactly 402 `[method, path]` tuples and the stripped
  route content is unchanged (the estate fence digest measures equal
  old-vs-new) — only `provenance.serverSha` / `generatedAt` advance. The single
  code pin `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA`) moves in
  the same commit; the client-route scan it runs stays exactly as before — 91
  request sites / 81 distinct tuples across 2 modules, tuple-exact. No Roku
  request surface changed.

### Changed — W61 (cs36): route-manifest currency re-pin to current server master — 2026-09-11

- **cs#36 currency re-pin cascade (lane cs36).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen against the current phlix-server
  master tip). **Pure provenance re-pin, not a content change:** the server span
  since the prior pin touched only a test file and the CHANGELOG, so the manifest
  still carries exactly 402 `[method, path]` tuples and the stripped route content
  is unchanged — only `provenance.serverSha` / `generatedAt` advance. The single
  code pin `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA`) moves in
  the same commit; the client-route scan it runs stays exactly as before — 91
  request sites / 81 distinct tuples across 2 modules, tuple-exact. No Roku
  request surface changed.

### Changed — W59 (cs35): route-manifest full regen (401 → 402 tuples) — 2026-09-11

- **cs#35 currency re-pin cascade (lane cs35).** Vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen against the current phlix-server
  master tip). Genuine full regen, not provenance-only: the server gained one
  WebPortal route, so the manifest moves 401 → 402 `[method, path]` tuples
  (Application source count holds, WebPortal source count rises by one, shared
  overlap unchanged). Gate pins `PROVENANCE_SHA` and `TOTAL_TUPLES` in
  `tests/scripts/verify-route-manifest.mjs` advance in the same commit; the gate
  self-derives its own site/tuple counts (91 sites / 81 tuples — unchanged)
  because no Roku request site calls the new route, so the vendored manifest is
  simply a superset. Untagged wave: the dependency tag pin stays put.

### Prior era snapshot — W58 (cs34): PURE provenance re-pin (401 tuples)

### Changed — W58 (cs34): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-10

- PURE provenance re-pin, zero route bytes: vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #21 against the current
  phlix-server master tip; purity re-proven before regenerating — the server
  route-relevant span is empty and both generator-input guard blobs hash
  identically at both ends). 401 `[method, path]` tuples unchanged; the
  provenance-stripped route-content md5 and the sorted-tuple fence digest
  measure equal old-vs-new, only provenance bytes move. Gate pin
  `PROVENANCE_SHA` in `tests/scripts/verify-route-manifest.mjs` advances in the
  same commit; the gate self-derives its site/tuple counts (91 sites / 81
  tuples — unchanged). Untagged wave: the dependency tag pin stays put.

### Changed — W57 (cs33): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-10

- PURE provenance re-pin, zero route bytes: vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #20 against the current
  phlix-server master tip; purity re-proven before regenerating — the server
  route-relevant span is empty and both generator-input guard blobs hash
  identically at both ends). 401 `[method, path]` tuples unchanged; the
  provenance-stripped route-content md5 and the sorted-tuple fence digest
  measure equal old-vs-new, only provenance bytes move. Gate pin
  `PROVENANCE_SHA` in `tests/scripts/verify-route-manifest.mjs` advances in the
  same commit; the gate self-derives its site/tuple counts (91 sites / 81
  tuples — unchanged). Untagged wave: the dependency tag pin stays put.

### Changed — W55 (cs32): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-10

- PURE provenance re-pin, zero route bytes: vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (untagged regen #19 against the current
  phlix-server master tip; purity re-proven before regenerating — the server
  route-relevant span is empty and both generator-input guard blobs hash
  identically at both ends). 401 `[method, path]` tuples unchanged; the
  provenance-stripped route-content md5 measures equal old-vs-new, only
  provenance bytes move. Gate pin `PROVENANCE_SHA` in
  `tests/scripts/verify-route-manifest.mjs` advances in the same commit; the
  gate self-derives its site/tuple counts (91 sites / 81 tuples — unchanged).
  Untagged wave: the dependency tag pin stays put.

### Changed — W53 (cs31): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-10

- PURE provenance re-pin, zero route bytes: vendored
  `tests/fixtures/server-route-manifest.json` re-vendored byte-identical from
  `@phlix/contracts` master (fresh regen against the current
  phlix-server master tip; purity re-proven before regenerating — the server
  route-relevant span is empty and both generator-input guard blobs hash
  identically at both ends). 401 `[method, path]` tuples unchanged; the
  provenance-stripped route-content md5 measures equal old-vs-new, only
  provenance bytes move. Gate pin `PROVENANCE_SHA` in
  `tests/scripts/verify-route-manifest.mjs` advances in the same commit; the
  gate self-derives its site/tuple counts (unchanged). Untagged wave: the
  dependency tag pin stays put.

### Changed — W50 (cs30 era-2): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-09

- Server moved mid-wave (`32183f5b` → `5986b61d`, S210 #749 — docker boot-gate bounds only,
  route-zero re-proven: Router/Application/guard blobs and Routes/+FastPath/ trees byte-identical).
  Vendored `server-route-manifest.json` re-vendored byte-identical from `@phlix/contracts` master
  `57a8528a` (era-2 regen; full-file md5 `cb53d53f` → `045c0984`, blob identity `dd0cbaca` verified
  against the contracts dist artifact; stripped route-content md5 `508a…` holds — 401 tuples).
  Gate pins advance in the same commit; counts unchanged.

### Changed — W49 (cs30): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-09

- **cs#30 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `767146a8` (untagged regen #17 against server master `32183f5b`; previous
  provenance `8697c099`/`e15d9543` — the cs#29 leg). The span `e15d9543` → `32183f5b` is two merges
  (S266 #747, S171 #748), re-proven route-zero at the contracts leg: route-authority blobs/trees
  identical, `WebPortalRouter.php` comment-only, the deleted `public/index.php` front controller
  carried zero route-wiring hits — the tuple set is byte-identical (stripped route-set md5 `508a6415`
  old = new, 401 both sides), only provenance moves. `TOTAL_TUPLES` stays 401 and the 91-site /
  81-tuple `CHECK_COUNTS` pins stay; `PROVENANCE_SHA` moves to `32183f5b` (full literal; the summary
  line now prints that sha8 — currency, not drift). No md5 assertion here (unchanged posture;
  vendored bytes verified against the contracts dist blob `9068173e` at the source of the copy —
  `git hash-object` identical). Gate + planted-divergence self-test GREEN in-lane; `make lint`
  0 errors, 24 warning lines.

### Changed — W48 (cs29): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-09

- **cs#29 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `8697c099` (untagged regen #16 against server master `e15d9543`; previous
  provenance `a1ca39d8`/`a5cde27e` — the cs#28 leg). The span `a5cde27e` → `e15d9543` is two merges
  (S211 #745, S114 #746), re-proven route-zero at the contracts leg: route-authority blobs/trees
  identical, zero route-wiring hunks in the moved `Application.php` — the tuple set is byte-identical
  (stripped route-set md5 `508a6415` old = new, 401 both sides), only provenance moves. `TOTAL_TUPLES`
  stays 401 and the 91-site / 81-tuple `CHECK_COUNTS` pins stay; `PROVENANCE_SHA` moves to `e15d9543`
  (full literal; the summary line now prints that sha8 — currency, not drift). No md5 assertion here
  (unchanged posture; vendored bytes verified against the contracts dist blob `73b945aa` at the source
  of the copy). Gate + planted-divergence self-test GREEN in-lane; `make lint` 0 errors, 24 warning
  lines.

### Changed — W47 (cs28): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-09

- **cs#28 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `a1ca39d8` (regen against server master `a5cde27e`; previous provenance
  `28000fa4`/`afe54c7c` — the cs#27 leg). The span since `afe54c7c` is S187 whole-tree unused-import
  reflow — route-zero: the tuple set is byte-identical (stripped route-set md5 `508a6415` old = new,
  401 both sides), only provenance moves. `tests/scripts/verify-route-manifest.mjs` moves
  `PROVENANCE_SHA` to `a5cde27e`; `TOTAL_TUPLES` stays 401 and the 91-site / 81-tuple `CHECK_COUNTS`
  pins stay. No md5 assertion here (unchanged posture; vendored bytes verified against the contracts
  dist blob at the source of the copy). Gate + planted-divergence self-test GREEN on skynet2;
  `make lint` 0 errors.

### Changed — W46 (cs27): route-manifest provenance re-pin — PURE, 401 tuples unchanged — 2026-09-09

- **cs#27 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `28000fa4` (regen against server master `afe54c7c`; previous provenance
  `97c87f27`/`1e14b539` — the cs#26 leg). Seven server merges since `1e14b539`, all route-zero:
  the tuple set is byte-identical (stripped route-set md5 `508a6415` old = new, 401 both sides) —
  only provenance moves. `tests/scripts/verify-route-manifest.mjs` moves `PROVENANCE_SHA` to
  `afe54c7c`; `TOTAL_TUPLES` stays 401 (per `.claude/rules/route-manifest-gate.md` the pins move
  together only when the set moves); the 91-site / 81-tuple `CHECK_COUNTS` pins stay. No md5
  assertion here (unchanged posture). Gate + planted-divergence self-test GREEN; `make lint`
  0 errors.

### Changed — W43 (cs26): route-manifest re-pin — REAL route add, non-pure, 401 tuples — 2026-09-08

- **cs#26 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `97c87f27` (regen against server master `1e14b539` — S273
  `POST /api/v1/admin/updates/check`, a real route add; previous provenance `e837e31c`/`2746677e`).
  Unlike cs#23–25 this leg is NON-PURE: the server tuple set moves 400 → 401 — the admin route
  this client never calls, so client-side coverage is untouched.
  `tests/scripts/verify-route-manifest.mjs` moves `PROVENANCE_SHA` to `1e14b539` and
  `TOTAL_TUPLES` to 401 (per the rule in `.claude/rules/route-manifest-gate.md` the two pins
  move together); the 91-site / 81-tuple `CHECK_COUNTS` pins stay. No md5 assertion here
  (unchanged posture; the vendored bytes themselves verified md5 `e3647899` against the
  contracts dist at the source of the copy).
  Verified on skynet2: `[S280 route gate] roku: 91 request sites / 81 distinct tuples` —
  tuple-exact @ the new provenance; `--self-test` falsifiability green; the full device-free CI
  gate set green (`make lint`, `bslint`, `validate-xml`, `validate-manifest`, `check`,
  `verify-runtime` with the server sibling supplied). No version or install-pin moves in this repo.

### Changed — W38 (cs25): route-manifest provenance re-pin (no route change) — 2026-09-08

- **cs#25 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `e837e31c` (regen against server master `2746677e` — S112/S166
  landing, zero route hunks; previous provenance `59fd9b02`/`df6aa8e5`).
  All 400 tuples byte-identical — only provenance moves.
  `tests/scripts/verify-route-manifest.mjs` moves the `PROVENANCE_SHA` pin to `2746677e`;
  `TOTAL_TUPLES = 400` and every coverage pin stay. No md5 assertion here (unchanged posture).
  Verified on skynet2: 91 request sites / 81 distinct tuples — tuple-exact @ the new provenance;
  `--self-test` falsifiability green; `make lint` green. No version or install-pin moves in this repo.

### Changed — W38 (cs24): route-manifest provenance re-pin (no route change) — 2026-09-07

- **cs#24 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `59fd9b02` (regen against server master `df6aa8e5` — the S227
  ThemeRegistry dead-island delete, zero route hunks; previous provenance `bcd27dfd`/`bab33ff2`).
  All 400 tuples byte-identical — only provenance moves.
  `tests/scripts/verify-route-manifest.mjs` moves the `PROVENANCE_SHA` pin to `df6aa8e5`;
  `TOTAL_TUPLES = 400` and every coverage pin stay. No md5 assertion here (unchanged posture).
  Verified: 91 request sites / 81 distinct tuples — tuple-exact @ the new provenance; `--self-test`
  falsifiability green; `make lint` green. No version or install-pin moves in this repo.

### Changed — W37 (cs23): route-manifest provenance re-pin (no route change) — 2026-09-06

- **cs#23 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `bcd27dfd` (regen against server master `bab33ff2` — the S443
  `Uuid::v4` entropy close-out, zero route hunks; previous provenance `876d0ea7`/`e4853f0f`).
  All 400 tuples byte-identical — only provenance moves.
  `tests/scripts/verify-route-manifest.mjs` moves the `PROVENANCE_SHA` pin to `bab33ff2`;
  `TOTAL_TUPLES = 400` and every coverage pin stay. No md5 assertion here (unchanged posture).
  Verified: 91 request sites / 81 distinct tuples — tuple-exact @ the new provenance; `--self-test`
  falsifiability green; `make lint` green. No version or install-pin moves in this repo.

### Changed — W36 (cs22): route-manifest provenance re-pin (no route change) — 2026-09-06

- **cs#22 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `876d0ea7` (regen against server master `e4853f0f` — the S439
  zero-residue close-out, one commit past S438 `f17cafe6`; zero route hunks; previous provenance
  `341fc6e2`/`e729d48a`). All 400 tuples byte-identical — only provenance moves.
  `tests/scripts/verify-route-manifest.mjs` moves the `PROVENANCE_SHA` pin to `e4853f0f`;
  `TOTAL_TUPLES = 400` and every coverage pin stay. No md5 assertion here (unchanged posture).
  Verified: 91 request sites / 81 distinct tuples — tuple-exact @ the new provenance; `--self-test`
  falsifiability green; `make lint` green. No version or install-pin moves in this repo.

### Changed — W35 (cs21): route-manifest provenance re-pin (no route change) — 2026-09-06

- **cs#21 currency leg.** `tests/fixtures/server-route-manifest.json` re-vendored verbatim from
  `@phlix/contracts` master `341fc6e2` (regen against server master `e729d48a` — a caliber-refresh
  sync commit, zero route hunks; previous provenance `f2e284b3`/`f35a5742`). All 400 tuples
  byte-identical — only provenance moves. `tests/scripts/verify-route-manifest.mjs` moves the
  `PROVENANCE_SHA` pin to `e729d48a`; `TOTAL_TUPLES = 400` and every coverage pin stay.
  No md5 assertion here (unchanged posture). Verified: 91 request sites / 81 distinct tuples —
  tuple-exact @ the new provenance; `--self-test` falsifiability green; `make lint` green.
  No version or install-pin moves in this repo.

### Changed — W34 (cs20retag): route-manifest provenance re-pin (no route change) — 2026-09-05

- **cs#20 currency leg of the combined re-tag wave.** `tests/fixtures/server-route-manifest.json`
  re-vendored verbatim from `@phlix/contracts` master `f2e284b3` (regen against server master
  `f35a5742` — the web-ui `@phlix/ui` v0.99.1 re-pin commit, zero PHP, zero route hunks; previous
  provenance `2250def2`/`3a253991`). All 400 tuples byte-identical — only provenance moves.
  `tests/scripts/verify-route-manifest.mjs` moves the `PROVENANCE_SHA` pin to `f35a5742`;
  `TOTAL_TUPLES = 400` and every coverage pin stay. No md5 assertion here (unchanged posture).
  Verified: 91 request sites / 81 distinct tuples — tuple-exact @ the new provenance; `--self-test`
  falsifiability green; `make lint` green. No version or install-pin moves in this repo.

### Changed — W33 (cs19): route-manifest provenance re-pin (no route change) — 2026-09-05

- **cs#19 currency cascade.** `tests/fixtures/server-route-manifest.json`
  re-vendored verbatim from `@phlix/contracts` master `2250def2` (regen
  against server master `3a253991`; previous provenance `e74cdc88` — S431
  executable census, one commit, no route hunks). All 400 tuples byte-identical
  — only provenance moves. `tests/scripts/verify-route-manifest.mjs` moves the
  `PROVENANCE_SHA` pin to `3a253991`; `TOTAL_TUPLES = 400` and every coverage
  pin stay. No md5 assertion here (unchanged posture). Untagged wave: no
  version or install-pin moves.

### Changed — W31 (cs18): route-manifest provenance re-pin (no route change) — 2026-09-05

- **cs#18 currency cascade.** `tests/fixtures/server-route-manifest.json`
  re-vendored verbatim from `@phlix/contracts` master `51ed6cd3` (regen
  against server master `e74cdc88`; previous provenance `4b620f59`). All 400
  tuples byte-identical — only provenance moves.
  `tests/scripts/verify-route-manifest.mjs` follows its `PROVENANCE_SHA` pin
  to `e74cdc88` (this gate pins provenance sha, not md5). The issued set
  stays 91 request sites / 81 distinct tuples — the delta is tuple-neutral;
  no coverage or partition pin moved.

### Changed — W29 (cs17): route-manifest provenance re-pin (no route change) — 2026-09-04

- **cs#17 currency cascade.** `tests/fixtures/server-route-manifest.json`
  re-vendored verbatim from `@phlix/contracts` master `55311c68` (regen
  against server master `4b620f59`; previous provenance `888a42b2`). All 400
  tuples byte-identical — only provenance moves.
  `tests/scripts/verify-route-manifest.mjs` follows its `PROVENANCE_SHA` pin
  to `4b620f59` (this gate pins provenance sha, not md5). No coverage or
  partition pin moved.

### Added — S280 client route gate (roku half)

- **`tests/fixtures/server-route-manifest.json`** — vendored byte-for-byte from
  `@phlix/contracts` `dist/server-route-manifest.json` (400 `[method, pathTemplate]`
  tuples derived from phlix-server `8f72faec`; provenance pinned inside the gate).
- **`tests/scripts/verify-route-manifest.mjs`** (`make validate-routes`, also wired
  into `make validate` and `test.yml`) — statically scans every `.request("VERB",
  …)` / `.sendRaw("VERB", …)` site in `source/` + `components/` (including
  `path`/`cachePath` variable-assignment chains) and requires each issued URL to
  be tuple-exact against the manifest: exact segment count, `{param}` spans one
  segment, never a substring (no sibling-wildcard absorption). Coverage is
  pinned: **91 request sites / 81 distinct tuples across 2 modules**.
  Partition exceptions are enumerated with reasons AND negative-pinned
  (`GET /me/servers` is hub-only — it reds the moment the server registers it);
  `GET /health` (probeHealth, outside the `/api/v1` concat) is positively pinned.
  `--self-test` proves the matcher is falsifiable on demand; the planted-unserved
  URL was demonstrated RED on a real source file and reverted to green.

### Fixed — three calls to routes phlix-server never registered (S280)

- **`markWatched`** POSTed `/users/me/history/{id}` — only the DELETE half of
  that path exists. Now `POST /api/v1/media/{id}/watched` (the registered
  mark-watched rail; detail-screen "Mark watched" finally stops 404ing).
- **ApiTask next-up** requested `/me/next-up`; the served rail is
  `/api/v1/users/me/next-up` (its own code comment always said so). Fixed in
  the request and both cache-key literals.
- **`getItemCast` + the cast/crew display chain REMOVED**: `GET /media/{id}/cast`
  is on neither registry (the server's HTTP layer emits no cast key anywhere —
  `/cast` is Chromecast devices only), so the detail-screen fetch 404'd on every
  open and the invalid-guarded handler rendered nothing since the feature was
  written. Removed: `ApiClient.getItemCast`, the `ApiTask` op branch, the
  `DetailScene` handler + request site + `DisplayCast`/`DisplayCrew`. Same
  verdict s280ui/S285 reached for can-never-succeed placeholders. If the server
  ever registers credits (W19 routes-or-removal), re-add against the manifest.
- **Dead notification-preferences surface REMOVED** (`getNotificationPreferences`
  / `updateNotificationPreferences` → `GET|PUT /users/me/notifications`, never
  served anywhere, zero callers in source, tests, or docs).

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
