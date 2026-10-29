# Changelog

## [Unreleased]

### Docs — M-ROKU-11 r2: version-header coverage claims scoped to shipped truth — 2026-10-29

- The r1 review (review roku__devops) held the cure solid but found the
  docs overclaiming its coverage — the exact defect class this item exists
  to close. Two sentences scoped in `docs/debugging.md`: the header law now
  reads every HTTP request the channel issues **through its `ApiClient`
  transport** carries the stamp, with a rider disclosing that the hub
  relay-token mint (`HubCommandTask.MintRelayToken`) and the two SyncPlay
  WS upgrade handshakes (`SyncPlayProtocol.BuildHandshakeRequest`) are not
  yet stamped; the telemetry sentence is narrowed to the only
  *build-identity* diagnostic the wire carries (the device-id/name/session
  headers are listed two lines below). The M11 "Callers traced"
  parenthetical above is corrected in place per the reviewer's explicit
  ask. No code and no CHECK 42 change — the script's census prose was
  already scoped to the three ApiClient sites; re-verified against tip
  `a84cdb7` (mint POST: Authorization + Content-Type only; WS handshakes:
  Authorization only). Docs-only: 2 files, zero code lines.

### Fixed — wire error text type-guarded before render-path string ops (M-ROKU-12) — 2026-10-29

- **The defect (review roku__exploiter M1).** A response body is
  attacker-influenced data: the contract says `{error: string}`, but a hostile
  server (or, on http://, any LAN injector) can answer `{"error":123}` /
  `{"error":{"code":1}}`. Every consumer fed that value into a String
  operation unguarded — `<> ""` / `= ""` compares, `lcase`/`instr`,
  concatenation, an `as String` sink — so the first hostile non-String raised
  a BrightScript runtime type mismatch: scenes died mid-login / mid-action on
  the render thread (LoginScene's ladder, ServerPickerScene, PlayerScene's
  access-schedule arm, the four admin `MessageOf` reducers), and
  `DeriveResponseError` — the task-thread choke every scene-facing envelope
  error rides — bricked the task.
- **The cure (one guard family).** `SafeErrorMessage(value as Object,
  fallbackMessage as String)` (source/lib/Utilities.brs): `type(value)` must
  be roString/String — a non-String is a contract violation and degrades to
  the caller's typed fallback, never partially rendered; the value is capped
  at `WireErrorMessageMax()` (300, gate-pinned literal) BEFORE the O(n)
  `StripWireControlChars()` loop (CR/LF/TAB/NUL/DEL never reach a Label —
  Roku renders plain text, there is no ANSI class, but control bytes are
  single-line-chrome garbage), then trimmed; empty collapses to the fallback.
  `GetErrorMessage` is retyped `as Object` and rides the guard first; its
  legacy `http_*` map is preserved verbatim. The task choke
  `DeriveResponseError` routes all three wire candidates through the guard,
  and a new `WireErrorPresent()` (a malformed non-String error still counts
  as failure, never as success) replaces the raw admin `{error}` compare.
  All ten wire-text consumer sites are cured; behavior changes only for
  hostile non-String inputs, which previously crashed or silently
  misclassified.
- **The gate.** CHECK43 (scripts/verify-runtime.sh) fails loud on raw
  `.error`/`.message` reads, literal compares, or string ops in any shipped
  .brs (red-on-parent: 35 problems across the ten cure sites + the four
  choke pins at `16f338ca8`), pins the cure artifacts themselves (guard
  signature, cap literal 300, DeriveResponseError wiring), exempts
  guard-bearing lines and `m.top.*` RSG-typed fields, and WARN-lists exactly
  the two in-flight files (components/PhlixApp.brs:388 + the
  source/lib/ApiClient.brs envelope lifts) whose raw wire pair the live
  M-ROKU-11 lane owns curing at the ApiClient source choke — the WARN set
  must never grow. tests/unit/WireGuard.test.brs pins the guard contract
  on-device (rooibos); the portable harness carries a three-arm
  plant-and-restore red leg with CHECK26/CHECK41 gate independence.
### Fixed — retail-user visibility: channel version on every request, honest readable About, shipped-truth log story (M-ROKU-11) — 2026-10-29

- **The defect (review roku__devops M4).** "No way to support a retail
  user": (a) the app sent `X-Phlix-Device-ID`/`-Name`/`-Type` and a
  session id on every request but **no channel version anywhere** —
  support looking at server logs could not tell which build a device
  ran; (b) Settings → About rendered a **hardcoded `version = "1.0.1"`**
  (the lie) into `statusLabel` — a 40px `wrap="false"` Label, so even the
  old five-line `Chr(10)` block it once assembled was clipped to one
  line: the "About" surface was theater in two directions; (c) a crash
  left no readable trace — the only log story was dev-mode telnet, and
  `docs/debugging.md` itself contained two fictions (a claim that the
  channel had to be *already running* before connecting — telnet
  streams from the connect moment; and `console.log()` vocabulary that
  does not exist in BrightScript while `bslint.json` keeps `no-print`
  off); (d) no crash surface at all for a user without dev mode.
- **Callers traced (both sides).** All three ApiClient send sites
  (`sendRaw`/`sendRawWithDeviceId`/`resolveLocation` — every HTTP the
  channel makes through `ApiClient` routes through one of them; the hub
  relay-token mint and the two SyncPlay WS upgrade handshakes are not yet
  stamped — scoped by the r2 entry below); the About row's only
  consumer is `SettingsScene.ShowAbout()`; the server was audited
  READ-ONLY for header handling: it reads headers *selectively* via
  `$request->getHeader()` (`X-Phlix-Device-Type`
  `src/Controllers/MediaItemController.php:501`, `X-Device-Id`
  `src/Controllers/AuthController.php:239` era coords) — **no whitelist
  strips unknown `X-Phlix-*` headers**, so a new header is pure
  wire-safe additivity with zero new wire codes (contract law held).
- **The cure (Roku's own surfaces only — no invented API, no fabricated
  telemetry endpoint).** (a) `source/lib/AppContext.brs` gains
  `ChannelInfo()`/`GetChannelVersion()` over `roAppInfo.GetVersion()` +
  `GetID()` (both fields vendored in
  `node_modules/brighterscript/dist/roku-types/data.json`), cached on
  the function object like `DeviceInfoData()`; every ApiClient send site
  now stamps `X-Phlix-Client-Version` and the factory tail binds
  `obj.clientVersion = GetChannelVersion()`. (b) About reads real state:
  channel version, channel ID, Roku OS version
  (`roDeviceInfo.GetOSVersion()` — string fields, joined via
  `DiagnosticText`), plus **previous-run exit info** from
  `roAppManager.GetLastExitInfo()` — documented since Roku OS 13.0
  (https://developer.roku.com/dev/docs/ifappmanager, read 2026-10-29),
  firmware-gated via `Val(GetOSVersion().major) >= 13` because
  `roappmanager` does not implement `ifAssociativeArray` (no
  `DoesExist()` probe), and **last-12 error ring** in memory
  (`RecordDiagnosticsError`, seq'd, trimmed) pushed from the
  render-thread chokepoints that used to discard their failure reason
  (boot-auth handler, preferences/history arms). All of it renders into
  `detailLabel` — the panel's only wrapping surface (width 400,
  height 540, `wrap="true"`) — while `statusLabel` keeps the single-line
  version headline. Thread-locality is honest in the docblock: RSG tasks
  run on their own thread, so the ring is UI-thread-only by law and
  crash-run visibility comes OS-side via the exit-info read.
  (c) `docs/debugging.md` rewritten to shipped truth: a retail support
  playbook (every About line + its source API + what retail users
  CANNOT do), a server-side half stating the header contract, developer
  surfaces corrected (telnet streams from connect moment; `print` not
  `console.log`; **`console_log` in GetLastExitInfo requires
  `run_as_process=1` — this Manifest does not set it**, so that field is
  pinned absent in prose, not silently promised). (d) Eight
  `settings.about_*` catalog keys, translated in all 7 locales
  (302 → 310, v1.6.0).
- **verify-runtime Check 42 (the anti-drift pin).** R1 all three send
  sites carry the header from `m.clientVersion` + the factory stamp; R2
  bans any version literal re-entering `source/`+`components/` (the
  `1.0.1` census); R3 pins the `GetChannelVersion()` → `roAppInfo` read
  shape and its scene consumption; R4 the ring (capacity 12, trim loop,
  render-thread push sites); R5 the OS-13 gate + the Manifest's
  `run_as_process` absence + the doc's console_log truth; R6 the block
  writes the wrapping `detailLabel` and `statusLabel` stays unwrapped;
  R7 the eight catalog keys exist and are consumed; R8 bans network I/O
  in the diagnostics surface (a fabricated telemetry endpoint is the
  failure mode this lane refuses to introduce).
- **Gates.** `make lint` (bsc) 0 errors; `make bslint` pass;
  `scripts/validate-xml.sh` pass; `scripts/verify-runtime.sh` 42/42 PASS;
  `tests/scripts/verify-runtime-portable.sh` green incl. its new
  Check 42 plant-and-restore leg (stripped header + planted `1.0.1` +
  statusLabel retarget → CHECK42 R1/R2/R6 fire with CHECK41/CHECK20
  gate independence; restore → exit 0). Red-on-parent measured at
  `16f338ca8`: CHECK42 R1–R7 all fire on the pre-fix tree.
- **Rider notes.** The server's AD-27 heartbeat store
  (`src/Stats/ClientHeartbeatStoreInterface.php`, `MAX_VERSION_LENGTH=32`)
  lands client versions via the QuickConnect/PIN-login flow only —
  Phlix-roku authenticates through `/auth/login`, so wiring heartbeats
  is OUT OF SCOPE here and deliberately not claimed; the header ships
  the telemetry into logs regardless. Server-side reads (if any) are a
  separate estate decision.

### Fixed — package-signed honesty: claimed preconditions enforced, mislabeled "signed" artifact impossible (M-ROKU-10) — 2026-10-29

- **The defect (review roku__devops M3, all four bullets).**
  `scripts/package-signed.sh` + `docs/publishing.md` + the
  `.github/workflows/package.yml` signing lane shipped four linked
  dishonesties: (a) the header and docs claimed a `ROKU_DEV_PASSWORD`
  environment variable was required and the script "will fail" without it —
  **no component ever read it** (the review's evidence: the script "never
  reads ROKU_DEV_PASSWORD", `scripts/package-signed.sh:9` at the pin); auth
  is the external rokudev CLI's stored `rokudev auth` session, the password
  is typed at its prompt; (b) the faux-signature fallback: when `rokupkg`
  existed but signing failed, the script `cp`'d the unsigned zip onto the
  `.pkg` name and still printed "✓ Signed package ready" + "Upload … to the
  Roku developer portal" — a renamed unsigned zip under a signed name is
  exactly the artifact that wastes a store review cycle; (c) the inert
  version stamp: `PKG_VERSION="${PKG_VERSION:-1.0.1}"` — the Makefile
  derived the real version but make does NOT export ordinary variables into
  recipes, so direct invocations were permanently mis-stamped `1.0.1`;
  (d) the CI stub: the `package-signed` job ran `make package-signed` in a
  job that installed no signer (no setup-node/npm ci) and collected no
  artifact — silently skipped while its gate secret is unset, and the day
  anyone armed the secret it would have exited 1 and blocked
  `release-latest`, which listed it under `needs:`.
- **Callers traced (both sides).** Nothing invokes the script except the
  `make package-signed` target (`Makefile`) — the deleted workflow job was
  its only CI caller; no artifact collector ever consumed its output
  (`release-latest` publishes the sideload `phlix.zip` only). Manual dev +
  manual store are the real flows, so the minimal honest shape was chosen
  per-flow rather than provisioning owner-gated signing credentials in CI.
- **The cure (fail-loud-or-delete-claim doctrine; precedent ROKU-09
  `905ab2e4` / windows WIN-05).** (a) The phantom-secret claim is deleted
  from the script header, the Makefile comment, and every publishing.md
  site (Prerequisites item 3, the Step-2 flow list, the CI snippet — the
  docs now state the truth: no password env var exists to export).
  (b) The rename fallback is killed: a signing failure exits non-zero and
  mints NOTHING (probe-verified: signer-fail leaves zero `.pkg` files);
  additionally the script now INSPECTS the certificate (`openssl x509`
  subject-vs-issuer compare) and names the artifact to its nature — a
  self-signed cert yields `phlix-X.X.X-dev-signed.pkg` with a "NOT accepted
  by the Roku Channel Store" banner and no upload instructions, a CA-issued
  cert yields `phlix-X.X.X.pkg` with the portal steps; an unreadable cert
  fails loud instead of minting an artifact of unknown provenance.
  (c) The version: the hardcoded default is gone — PKG_VERSION comes from
  the environment (the Makefile now passes `PKG_VERSION="$(PKG_VERSION)"`
  explicitly), else from `scripts/derive-version.sh --pkg-version`, else the
  script halts BEFORE producing anything; `package-signed` also joined
  `.PHONY` while in the target's neighborhood. (d) The workflow stub is
  DELETED and `release-latest` needs `package` alone; the comment left in
  its place states the re-admission law (a CI signing job must land WITH
  `npm ci` + rokudev provisioning + certificate handling in one change).
- **verify-runtime Check 41 (the anti-drift pin).** Static claim↔behavior
  consistency in both directions: R1 the phantom token may not reappear in
  script/workflow/docs; R2 the `cp zip→pkg` pattern is banned and the
  nature-gate, the `-dev-signed` name and its doc echo, and the dev-only
  banner must exist; R3 bans a literal-default `PKG_VERSION` assignment and
  requires the derive fallback, the empty-version guard, and the Makefile's
  explicit pass-through; R4 reddens any workflow job that runs
  `make package-signed` without an in-job signer provision, and any
  `needs:` entry that names a nonexistent job. The wrapper is never
  EXECUTED by the gate (it shells out to make/external CLIs — unlike
  CHECK40's pure script), so its behavior was probe-verified at fix time:
  dev-signed success (honest name + banner, rc 0), signer-failure mints
  nothing (rc 1, zero artifacts), no-signer halt (rc 1), no-version halt
  (rc 1), CA-cert store branch (real name + portal steps).
- **Measured proofs.** Red-on-parent: CHECK41 against the `905ab2e4` files
  → 12 problems naming every finding class (R1 x2, R2 x5, R3 x4, R4 x1).
  Mutation: the portable harness leg re-plants the phantom claim, the
  rename-fake-pkg line, the hardcoded default and a signer-less stub job →
  CHECK41 R1/R2/R3/R4 each fire by name with CHECK18/CHECK40 gate
  independence; restore → exit 0. Gates at HEAD: `make lint` rc 0;
  `scripts/verify-runtime.sh` full 41-leg run exit 0;
  `bash tests/scripts/verify-runtime-portable.sh` exit 0 (incl. the new
  leg); `bash -n` clean on both touched scripts.
- **Docs.** `docs/publishing.md`: artifact table gains the honest
  `*-dev-signed.pkg` row; the Step-2 flow list, Prerequisites and the
  CI/CD section are rewritten to what the code actually does (no promise
  it can't keep). `docs/static-checks.md`: Check 41 row + harness
  paragraph. Publication vehicle untouched (rolling `latest` sideload +
  manual store submission; CHECK40's pins held).
- **Owner reel (NOT shipped here):** arming CI-side signing is an owner
  credential decision — provisioning (`npm ci` + rokudev + Roku-issued
  cert in CI) rides the WIN-05 upload-proof rider; until then Check 41 R4
  keeps an un-buildable stub from re-accumulating.

### Fixed — release version-discipline dead code cured to shipped reality + publishing docs truth (M-ROKU-09) — 2026-10-29

- **The defect (review roku__devops M2).** `scripts/derive-version.sh` carried
  CI-build-number machinery — `get_git_count()` / `get_ci_build_version()`
  honoring `CI_BUILD_NUMBER`/`GITHUB_RUN_NUMBER` — that no `main()` case
  dispatched and no caller in the repo referenced (grep: self-references only):
  the "release-time version discipline designed but dead code" of the finding.
  Same file, two adjacent fictions: the header advertised a no-arg mode that
  "output[s] all fields as manifest format" — nothing emits manifest format,
  and running the documented call crashed (`main "$@"` → `"$1": unbound
  variable` under `set -u`, exit 1); and `--pkg-version|*)` silently answered
  ANY unknown flag with the pkg version, so a caller reaching for the (dead)
  `--build-ci` would have baked a wrong `build_version` without an error.
  Around the script, the delivery story was undocumented: the only publication
  vehicle is the rolling `latest` GitHub prerelease that the `Package` workflow
  deletes (`gh release delete latest --yes --cleanup-tag`; gh help:
  "--cleanup-tag Delete the specified tag in addition to its release") and
  recreates on every master push — the previous sideload build is destroyed,
  `git ls-remote --tags origin` shows exactly one tag (`latest`), no doc said
  a store submission requires bumping the never-bumped `1.0.1` triple
  (`git log -S'"version"' -- package.json`: initial commit only), and
  `grep -riE "rollback|revert" docs/ README.md` was zero hits. README's store
  section additionally claimed "Upload your packaged app (phlix.zip)" while
  docs/publishing.md correctly requires the signed `.pkg`. The queue's
  `cured-by: C33 9ff4a6d` is ADJACENT-not-cured: that writer-lane commit fixed
  endpoint/URL/locale fictions in README/verify-runtime and never touched
  derive-version.sh or the publishing/version docs (diff proof at `9ff4a6d`).
- **The cure (scope A; delete-the-fiction, precedent windows WIN-05 e5e29b1).**
  The dead CI-build functions are DELETED, the header documents exactly the
  five shipped behaviors (no-arg = `--pkg-version` alias), the dispatch is
  guarded `case "${1:-}"` with an explicit `""` arm, and unknown flags exit 2
  naming the supported set — fail-loud where the silent trap was. Docs ship
  the real flow: `docs/publishing.md` gains "Version Discipline" (the triple is
  derived from `package.json` by the script; `make package` rewrites the build
  manifest; Check 18 pins drift; Roku requires a strictly increasing triple per
  submission → bump package.json before building the `.pkg`) and "Release
  Vehicles and Rollback" (rolling `latest` is the shipped vehicle, previous
  build destroyed, no GitHub-side rollback, store-side version management
  lives at the Roku portal, and versioned releases + a rollback procedure are
  an explicitly UNSHIPPED owner decision). README's Manifest Configuration and
  store-publishing sections were corrected to the same truth (`.pkg`, bump
  first, version triple not hand-edited in the manifest).
- **Teeth (CHECK40 + harness leg 15).** New verify-runtime leg pins the class
  shut: (R1) every function of `derive-version.sh` is reachable from top level
  (bare-word call graph — the dead pair re-added redds it), (R2) header usage
  flags ↔ dispatch arms are a bijection, the `""` arm/`${1:-}` guard exist and
  the "manifest format" phrase is banned, (R3) behavior probes run the script:
  no-arg must print package.json's version, `--build-ci` must fail — and (R4)
  the workflow↔docs tripwire: the three `latest`-vehicle pins in
  `package.yml`, the rolling/rollback/bump vocabulary in `publishing.md`, the
  `.pkg` truth in README's store section (changing the vehicle without
  rotating the docs reddens CI; the docs were already missing at parent, so
  R4 measured red there too). Red-on-parent measured: all four rule classes
  fire against the `9c70037`-era files (12 problems, rc=1) and green at HEAD.
  `tests/scripts/verify-runtime-portable.sh` stages the four new inputs,
  asserts the positive header, and carries a plant-and-restore red leg
  (unreachable function + ghost `--ghost` flag → R1/R2 fire naming both,
  CHECK18/CHECK39 gate-independent; restore → exit 0). No gate weakened;
  the script's callers (`Makefile` ×4 flags) are untouched and `make
  verify-runtime` (40 legs), `make lint`, `make validate-manifest`,
  `make validate-xml` (48 files) and the full portable harness exit 0.
- **Out of scope, by doctrine (scope B, owner-gated):** switching the
  publication vehicle to versioned releases and shipping a rollback story is a
  release-strategy decision — the workflow was NOT flipped; the concrete
  recommendation rides the fixlog's OWNER-REEL rider. `package-signed.sh`'s
  hardcoded `PKG_VERSION` fallback and label integrity is the sibling finding
  M3 (`package-signed.sh` contradicts its docs), untouched here.

### Fixed — verify-runtime.sh aggregation: checks 1-10 were print-only, the gate could never fail on them (M-ROKU-08) — 2026-10-29

- **The defect (review roku__devops M8).** `VIOLATIONS` — the single value
  `exit $((VIOLATIONS))` reads — was RE-ZEROED at four leg headers: checks
  8/9/10/11 opened with `VIOLATIONS=0` and rode it as a per-leg PASS-display
  local. Check 11's reset (old :153) wiped everything checks 1-10 had flagged,
  so those ten legs' diagnostics were theater: they printed but could never
  gate CI (`lint.yml` verify-runtime step + the `package` job's `needs:`).
  Measured from red at b8dd771: baseline exit 0; planted CHECK1 hit — violation
  PRINTED, gate exit 0; planted CHECK39 hit (after the last reset, control) —
  exit 1. The queue's `cured-by: C21 c6c9009; C33 9ff4a6d` annotation is false:
  `VIOLATIONS=0` occurs at the identical five sites (:13 init + :110/:124/:142/
  :153) in `c6c9009~1`, `c6c9009`, `9ff4a6d` AND `b8dd771` — neither cure
  touched the accumulator (diff proof in `.reviews/fixlog/M-ROKU-08__fix.md`
  §r2-cure).
- **The cure (aggregation law: one sink, zero it once).** The four header
  re-zeros are gone; `VIOLATIONS` is initialized once and only accumulated.
  Checks 8/9/10 PASS-display migrated to the same `FOUND` local checks 1-7 use;
  check 11's display was already `PYRET`-driven. Exposure sweep: the clean tree
  prints PASS on all ten early legs, so no latent violation was surfaced — the
  full 39-leg harness still exits 0; `make lint` (bsc) and `validate-xml.sh`
  (48 files) unchanged-green.
- **Teeth (portable harness leg 14).**
  `tests/scripts/verify-runtime-portable.sh` gains a plant-and-restore
  aggregation leg: a synthetic `Storage.get` violation rides CHECK1 — the
  EARLIEST leg, maximum wipe distance — and the run must exit non-zero with the
  print visible while CHECK20/21/39 stay green (gate independence); removing the
  plant returns exit 0 (falsifiability). Re-adding ANY single re-zero in the
  cured range reddens this leg: mutation-proven at fix time (one `VIOLATIONS=0`
  restored at the check-8 header → plant printed, exit 0). Red-on-parent: the
  same leg against the b8dd771 script fails exactly where the bug lived.
  `docs/static-checks.md` carries the aggregation law + the leg.
- **Same-shape strike, forward-fix discipline:** no behavior changed in any of
  the 39 checks themselves — only the plumbing from print to exit.

### Fixed — manifest rsg_version 7.0 fiction cured to the legal cert value 1.3 + CHECK39 (M-ROKU-07) — 2026-10-29

- **The defect (review roku__crossfe M3).** The manifest declared
  `rsg_version=7.0` since the R6.1 manifest "fix". That is not a legal value:
  per the live channel-manifest docs (developer.roku.com, retrieved
  2026-10-29) `rsg_version` "Sets the SceneGraph observer callback model" and
  its documented value space is 1.0/1.1/1.2/1.3 — "7.0" conflated the key with
  RSG's component-library package version. Devices silently IGNORE unknown
  values and run the firmware default (1.2 as of Roku OS 9.3), so the line was
  a false-comfort knob no vendored tool could flag: brighterscript's
  RokuConstants treats unknown-but-semver values as valid by design (the exit
  was `node_modules/.../brighterscript/dist/RokuConstants.js:11-39`). And the
  knob the channel thought it had turned is a certification requirement that
  expired while the fiction sat: "You must set this parameter to
  rsg_version=1.3 by October 1, 2026, to continue passing certification
  testing" (same page; vendored tooling corroborates — Roku's static-analysis
  cert tool requires 1.3 at minFirmware 15.1.0+). The maybe-cured C33 (9ff4a6d)
  was the README docs-truth lane — it never touched the manifest: red-on-parent
  re-proven at 0c9c7ac below.
- **The cure.** `manifest` declares `rsg_version=1.3` with a contiguous `'`
  rationale comment block at the key (value space, the default-to-1.2 rule,
  the certification deadline and the feature-usage census). Adjudication was
  honest-first: the channel relies on NO >=1.1-exclusive behavior — 489
  `ObserveField` sites and `roSGNodeEvent` task loops are core SceneGraph at
  every rsg version; zero `Register(OneShot)`-class calls — so the removal
  option was live, but 1.3 is MANDATED by the passed cert deadline, and it
  costs nothing: its hard rule is that Eval() "cannot be used with
  rsg_version=1.2" and the shipped `.brs` set calls Eval exactly zero times.
  Docs truth pass: `docs/certification.md` row 1.5 demoted from the false PASS
  to PARTIAL with a new §1a value-space/deadline citation (the "mm_icon_focus_sd
  fixed" credit reclassified per live docs — it and `mm_icon_side_hd` are now
  LEGACY attributes — and the one remaining REQUIRED-key gap, the absent
  `mm_icon_focus_fhd`, recorded for its own art lane, matching the
  `docs/static-checks.md` row 39).
- **CHECK39 (verify-runtime.sh, new leg).** R1 the key exists (absent = silent
  firmware default = cert fail); R2 value ∈ the documented set
  {1.0,1.1,1.2,1.3} — the 7.0 fiction class, named in the red; R3 shipped
  value is exactly 1.3 (re-bless only from a measured red if Roku moves the
  goalpost); R4 the comment block above the key carries "cert" and "observer"
  (case-insensitive, CHECK38 R3 idiom); R5 `\bEval\(` extinct in
  source/+components/ `.brs` (string-aware comment masking) so the >=1.2
  declaration and the code can never contradict each other. Red-on-parent
  proof: at 0c9c7ac the leg fires exactly 2 problems (R2 naming `'7.0'`, R4)
  and the other 38 checks stay green (PARENT_EXIT=1, no other
  "CHECKn: N problem(s)" lines). After the cure the full script exits 0
  (39/39 legs) and `make lint` (bsc/bslint) stays exit 0 — bsc accepts 1.3.
- **Portable harness.** CI-layout positive run asserts the Check 39 header +
  green line; a dedicated scratch-copy red leg plants `rsg_version=7.0` with
  the rationale comment stripped — CHECK39 fires naming the illegal value and
  R4, while the sibling manifest readers CHECK18 (version drift) and CHECK38
  (design plane) stay green (gate independence); restoring the cured manifest
  returns exit 0 (falsifiability). Full `verify-runtime-portable.sh` run: PASS.

### Fixed — ui_resolutions declares hd-only, matching the hardcoded 1280x720 design plane (M-ROKU-06, CHECK38) — 2026-10-29

- **The defect (review roku__crossfe M6).** The manifest declared
  `ui_resolutions=hd,full` against a codebase that hardcodes the 720p design
  space: 112 XML width/height/loadWidth/loadHeight attribute pins to 1280/720
  across 37 files (cce1b34 census), `PlayerScene.brs` sizing the Video node
  1280x720 at :1185 and :3000, progress computed from a bare 854 at :639.
  With 'full' declared, RokuOS runs 1080p devices NATIVELY at 1920x1080 —
  coordinates are never auto-scaled — so on every FHD device the UI rendered
  unscaled in the top-left two-thirds of the screen. Repo-wide scaling census:
  zero `resolutionRatio`, `viewBounds`, `GetVisibleRect` or root `Group scale`
  usages; `videoMode` is read only for the About screen
  (`SettingsScene.brs:356`). The lone FHD-space layouts — `RecommendationsScene.xml`
  's 1920-wide bar and two `translation="[960, 540]"` center pins (the 1920x1080
  center point) — were anomalies even inside the declared pair: every other
  scene centers on the 720p plane (cf. `DetailScene.xml` loadingLabel
  `[640, 340]`).
- **The cure.** `manifest` declares `ui_resolutions=hd` alone: the OS renders
  the 1280x720 canvas and upscales it to 1080p — the standard fixed-layout
  posture — with a contiguous comment block at the key stating the law and the
  re-declaration condition. 'sd' is intentionally absent (https-only modern
  app; a 1280-wide plane never fits a 640x480 screen).
  `components/RecommendationsScene.xml` is brought onto the design plane
  (1920→1280 bar, `[960, 540]`→`[640, 360]` ×2), the review's own "the
  declaration and the layouts must agree" closing law.
- **CHECK38 (verify-runtime.sh, new leg).** While the 720p plane exists in the
  markup (premise P, XML comments blanked line-preservingly so prose may quote
  dead literals): R1 the ui_resolutions token set is exactly {hd}; R2 no
  width="1920"/height="1080" attribute and no `translation="[960` survives in
  the markup; R3 the contiguous comment block directly above the key carries
  "design" and "720" — the rationale stays visible at the decision site.
  Red-on-parent proof: at cce1b34 the leg fires exactly 5 problems (R1×1,
  R2×3, R3×1) with the other 37 checks green; after the cure the full script
  exits 0 (38/38). Header asserted green in the CI-layout positive run of
  `tests/scripts/verify-runtime-portable.sh` (manifest + components already
  staged there).
- **Gates.** make lint (bsc) exit 0 — 18 pre-existing BS1013 warnings, zero in
  lane-touched files; make validate-xml exit 0 (48 files); verify-runtime full
  pass exit 0; portable harness full suite exit 0; make package exit 0 with
  verify-package green (root manifest present, 135 members, packaged
  `ui_resolutions=hd` disk-proven).

### Fixed — Discovery rebuilt on the documented socket surface; errored scans degrade like empty ones (M-ROKU-04 r2, CHECK37) — 2026-10-29

- **The defect (review M-ROKU-04__r1, issue 1, blocking).** The r1 LAN scan
  drove `roSocket` through a `"udp:"` constructor string plus
  `EnableBroadcast` / `JoinMulticastGroup` / one-arg `Receive` — none of which
  exist in this repo's own vendored Roku documentation mirror
  (node_modules/brighterscript/dist/roku-types/data.json, whose only UDP
  component is `roDataGramSocket`) — and hid the component name from bsc
  behind a const-fold-defeating function so the compiler could flag nothing.
  A BrightScript runtime error on that thread killed the task BEFORE it wrote
  `response`; ConnectScene observed only `response`, so the Connect screen
  latched on "Searching…" and the Find button dead-buttoned permanently —
  the exact day-1 defect class M-ROKU-04 set out to cure, re-introduced on
  the feature's success path (first inbound datagram).
- **The cure.** `components/DiscoveryTask.brs` now follows the worked example
  quoted verbatim in the vendored docs: `CreateObject("roDataGramSocket")`
  (no arguments, compiler-visible), `roSocketAddress` + `ifSocket.SetAddress`
  bind, `SetMessagePort`/`NotifyReadable`, `ifSocketCastOption.SetBroadcast`
  and `JoinGroup`, `SetSendToAddress`+`SendStr`, `GetSocketID`/`GetID` event
  ownership, and an `IsReadable`+`ReceiveStr` drain. The name indirection is
  gone. Enforcement truth, measured: bsc/bslint do not resolve member calls on
  `CreateObject`-typed locals, so CHECK37 — not the compiler — is the guard:
  it pins every documented verb present and every r1 counter-doc form dead,
  reddening the runtime gate instead of the user's living room.
- **The floor.** ConnectScene now observes BOTH `response` and `state` on the
  find task; `state="finish"` arriving without a response retires the task
  and renders the same honest `connect_find_none` floor an empty scan gets —
  manual entry is never lost and Find stays re-pressable. Teardown un-observes
  both fields (C03 pairing law).
- **CHECK37 (scripts/verify-runtime.sh).** R1 pins the documented verb set
  present and the counter-doc surface dead in DiscoveryTask.brs; R2 pins the
  dual-field observation + paired un-observation; R3 pins the finish arm's
  degradation content; R4 pins ParseSsdpResponse's home in Utilities.brs so
  the pure parser stays unit-reachable (it moved there from component scope).
- **Tests.** New `tests/unit/Discovery.test.brs`: 18 cases over the three
  pure boundary functions (ClassifyUrlFailure every bucket + honest default,
  ExtractServerOrigin reduction/userinfo/foreign-scheme rejection,
  ParseSsdpResponse accept/reject matrix). Venue-gated per house law —
  rooibos needs a device (ROKU_HOST); not executed in this lane.
- **Minor honesty carries (review issues 2/5).** restoreSession's
  `server_error` credential-wipe is now explicitly justified in its docblock
  (kept: the server answered and rejected the session shape; behavior
  unchanged); probeHealth's docblock records that any 1xx/3xx verdict lands
  on the `unreachable` label and why that is benign until redirect-off mode
  exists.

### Fixed — Day-1 honesty triangle had no consumer-side pin; CHECK36 closes the loop (M-ROKU-04 closeout) — 2026-10-29

- **The gap.** d252b17 cured the day-1 onboarding dead-ends (honest boot-failure
  ladder, reason-forwarding boot legs, real Settings→Server switch, LAN Find
  flow) and Check 34 pinned the taxonomy PRODUCERS — classifier buckets, the
  literal Translate ladder, catalog messages. Nothing pinned the CONSUMERS:
  PhlixApp.brs could silently regress to the pre-fix "guess the cause" dialog
  (which told never-logged-in users "Unable to reach server. Please check your
  network."), ShowConnect could drop the boot reason on the handoff, or the
  server switch could revert to the dead "not implemented" copy, and the gate
  would stay green.
- **CHECK36 (scripts/verify-runtime.sh).** Six rules close the triangle: R1
  both boot-auth handlers delegate failures to HandleBootAuthFailure(result)
  and the three pre-fix misdiagnosis literals stay dead text in PhlixApp.brs
  code; R2 the ladder keeps its no_session / transport / session_invalid arms
  (Translate-sourced copy); R3 the reason survives the handoff
  (ShowConnect→bootReason→ConnectScene TranslateTransportReason); R4 ApiTask
  forwards restoreReason in BOTH boot legs (count-pinned to 2); R5 the server
  switch is real (SettingsScene hands off to OnSwitchServer, which keeps
  ResetCachedStorage(true) + ShowConnect); R6 the killed
  settings.status_server_switch_not_implemented key stays out of every shipped
  catalog.
- **Teeth.** Mutation-proven in a scratch worktree at d252b17: each of R1-R5
  mutations (handler re-hardcode, no_session arm swap, dropped forwarding, dead
  button return, bootReason handoff removal) reddens exactly CHECK36 and
  nothing else; resurrecting the dead key in en_US fires CHECK36 R6 plus the
  legitimate Check 21 mirror-parity corroboration; restored control run exit 0.
- **Gates.** verify-runtime.sh exit 0 (all 36 legs); the portable twin
  (tests/scripts/verify-runtime-portable.sh) exit 0 with the Check 35 and
  Check 36 headers riding the staged fake layout - landing Check 36 surfaced a
  Check 35 staging gap (source/lib/AppContext.brs was missing from the fake
  layout, so the twin's wrapper-home leg reported "wrapper file gone");
  forward-fixed by adding AppContext.brs to the portable stage list.
  validate-xml and `make lint` untouched-green (this commit is gate-only —
  zero shipped .brs/.xml/.json changes).

### Fixed — Direct-play gate called CanDecodeVideo with fabricated positional strings; options-AA signature cure (M-ROKU-05, CHECK35) — 2026-10-29

- **The symptom (review roku__crossfe M5).** The R6.8 direct-play gate
  wrapped `devInfoObj.CanDecodeVideo(codec, container, profile)` - THREE
  positional strings. The SDK interface (docs.roku.com/dev/docs/ifdeviceinfo,
  mirrored in the vendored brighterscript SDK-types corpus) defines
  `CanDecodeVideo(video_format As Object) As Object`: one associative array
  (keys Codec required; Profile, Level, Container optional; lower-case quoted
  keys per the pre-14.1 case-sensitivity note) and an AA return whose
  "result" key carries the boolean. The positional call was arity-mismatched
  on every firmware, so the gate threw or coerced Invalid - theater or a
  crash vector on the PlayerScene startup path.
- **The cure.** `DeviceCanDecodeVideo` in source/lib/AppContext.brs now
  builds the options AA (quoted lower-case keys; empty-string container/
  profile omitted rather than sent empty; level never claimed), issues the
  single-object call, and parses the returned AA via Lookup("result").
  Public wrapper signature preserved, so components/PlayerScene.brs needed
  no edit.
- **Fail-open policy.** When the gate itself is broken - method missing on
  pre-7.10 firmware (HasMethod guard), non-AA return, or non-Boolean
  result - the wrapper returns true (attempt direct play) with a logged
  note. Rationale: a capability gate, not a requirement; the server
  transcodes anything, and PlayerScene's OnPlayerStateChange error fallback
  (transcodeAttempted-guarded, PlayerScene.brs) already recovers a wrongly-
  open gate, while a wrongly-closed one taxes every video with transcode
  latency and server load.
- **CHECK35 (scripts/verify-runtime.sh).** Five rules pin the contract:
  R1 no positional CanDecodeVideo( call survives in any .brs (word-boundary
  scoped so the wrapper's own name never trips it), R2 quoted lower-case
  options keys + single-argument device-call form in the wrapper body,
  R3 Lookup("result") parse, R4 HasMethod firmware guard with exactly three
  fail-open "return true" arms, R5 the fabricated positional comment never
  returns. Red-on-parent proof: against d252b17's AppContext.brs the leg
  reports 10 problems and exits 1; in-tree mutation (wrapper reverted to
  the HEAD blob) reddens the leg, restore greens the full 35-leg suite.
- **Gates.** `make lint` (bsc) exit 0 (zero new diagnostics; only
  pre-existing BS1013 test-file-reference warnings); scripts/verify-runtime.sh
  full pass exit 0 with all legs green; scripts/validate-xml.sh unaffected
  (no XML changed).

### Fixed — Day-1 onboarding: discover-first connect, honest transport taxonomy, real server switch, truthful boot (M-ROKU-04, CHECK34) — 2026-10-29

- **The symptom (review roku__casualgamer M5).** Getting started meant
  hunt-and-pecking `http://192.168.1.100:8096` on the on-screen keyboard with
  no pairing, no code and no alternative; every failure collapsed to one
  guessed label ("Couldn't reach that server", and at boot the far worse
  "Connection Error — Unable to reach server. Please check your network."
  which the boot flow showed to users who were merely NOT LOGGED IN — the
  server was fine, the session simply did not exist yet, and the real
  "Session Expired" dialog was unreachable dead text); Settings → Server URL
  → "Switch" answered `not_implemented` (a shipped dead button); and the
  whole connect/login error surface bypassed the i18n catalog in hardcoded
  English.
- **Pairing cross-read first (server capability, read-only).** phlix-server
  DOES ship a device-pairing flow — S518 QuickConnect
  (`src/Server/Http/Controllers/Auth/QuickConnectController.php`, routes at
  `src/Server/Core/Application.php:556-572`: initiate → {code,secret,
  expiresIn}; public status poll; AuthMiddleware approve carrying the
  256-bit SECRET; one-shot token redemption). It is deliberately NOT
  wired from this channel: `approve` requires the secret, which per design
  ships only inside a QR the TV must render, and Roku BrightScript has no QR
  encoder (no bitwise primitives; ~1000-line Reed-Solomon, device-
  untestable here — forbidden-risk class). phlix-ui has no approval page
  yet (only the manifest tuples + error cites) and phlix-hub serves no
  quick-connect routes. A TV showing a code nobody could enter anywhere
  would be one MORE fake affordance — the exact defect class this item
  cures. The estate owes a phone-side approver (ui lane follow-up, filed in
  the fixlog); meanwhile the day-1 typed-input burden is removed the other
  way round:
- **Discover-first connect.** New `components/DiscoveryTask.{brs,xml}` —
  one UDP multicast M-SEARCH to `239.255.255.250:1900` with
  `ST: urn:schemas-upnp-org:device:MediaServer:1` (wire shape mirrored from
  the server's own `src/Discovery/Ssdp/SsdpSocket.php:316-321`), a bounded
  4.2 s scan, and responses accepted only when they name Phlix (USN
  `uuid:PHLIXSERVER` or SERVER header `Phlix/` — the responder's exact
  markers, `src/Dlna/SsdpAdvertiser.php`, which is ON by default per
  `config/dlna.php`). `LOCATION` is reduced to a `scheme://host[:port]`
  origin via the new Utilities `ExtractServerOrigin` (http(s) only, userinfo
  rejected). ConnectScene gains a "Find Phlix server on network" button:
  one hit pre-fills the address box, several open a pick-list, none (or any
  socket failure) fall back to the manual entry floor with an honest
  message. The typed URL stays exactly what the review called for it to be:
  the documented fallback path, not the front door.
- **The honest taxonomy.** `Utilities.ClassifyUrlFailure` is now the single
  classifier over `roUrlEvent.GetFailureReason()` — `dns` / `refused` /
  `tls` / `timeout` / `bad_url` / `unreachable`, six buckets, no guesses.
  `ApiClient.request()`, `login()` and `probeHealth()` carry the true
  bucket (the old `started?timeout:connect` heuristic mislabeled every DNS
  failure as a timeout; probeHealth now reports `{state, code}` instead of
  collapsing reachable-but-blocked `/health` into "unreachable").
  `restoreSession()` reports WHY it failed through `m.restoreReason`:
  `no_session` / `session_invalid` / `server_error` / one of the transport
  buckets — and a transport blip NO LONGER wipes stored credentials (only
  a real 401/403 does), so a router reboot does not sign the household
  out.
- **Truthful boot routing.** Both boot arms (`OnAuthResponse`,
  `OnHubAuthResponse`) now share `HandleBootAuthFailure`: not-logged-in
  lands silently on the login screen (no dialog at all — it is not an
  error); a dead session gets the "Session Expired" dialog, which is now
  genuinely reachable; an unreachable server gets a per-cause message and
  lands on the Connect screen pre-filled with the saved address — the retry
  surface (find-your-server included), not a stuck dialog, honouring the
  C03 teardown contract throughout (`Teardown()` un-observes every new
  observer).
- **The "Switch" button switches.** Settings → Server URL → Switch confirms
  into `PhlixApp.OnSwitchServer()`: credentials + session captured BEFORE
  the surgical wipe (M-ROKU-03 order law), admin flag reset, hub consumer
  stopped, best-effort server-side session DELETE rides the request, then
  the Connect screen opens with the discovery floor — the
  `settings_status_server_switch_not_implemented` key is deleted from all
  seven catalogs.
- **Catalog law.** Every connect/login/boot error surface moved THROUGH the
  catalog: 25 new keys ×7 locales (catalog v1.5.0 — `connect.err_dns`,
  `login.status_signing_in`, `app.server_problem_message`, …), the
  token-bearing `login.err_server` consumed via `TranslateWithParams`, XML
  chrome localized via the `ApplyXmlChrome` pattern CHECK25 requires, and
  CHECK34 (new leg in `scripts/verify-runtime.sh`) pins the triangle: the
  classifier's bucket set ↔ the single literal `TranslateTransportReason`
  ladder ↔ the en_US messages (dead-copy + drift both red; red-on-parent
  proven: 9 named diagnostics at e7c6087).
- **Forward-fix on the same path (disclosed).** `tests/scripts/
  verify-runtime-portable.sh` was ALREADY red on the parent: checks 30-33
  landed reading `README.md`, `source/main.brs`, `source/lib/Storage.brs`
  and `tests/fixtures/server-route-manifest.json`, which the CI-layout
  fixture never staged (FileNotFoundError → exit 1; no CI job runs it, so
  master carried the red). The stage list now includes them; the full
  battery — positive run + every planted-red leg — exits 0.
- **Gates.** `make lint` (bsc, zero errors), `make bslint`, full
  `scripts/verify-runtime.sh` (34 legs incl the new CHECK34),
  `make validate-xml`, `make validate-routes` (+ falsifiability self-test),
  `tests/scripts/verify-runtime-portable.sh`: all exit 0. Discovery is
  statically verified + device-untested (no Roku here); every socket failure
  degrades to the pre-existing manual path, never a dead end.

### Fixed — Hub-mode logout teardown rides the relay base; OnLogout docblock wire-truth (CHECK33 R2) — 2026-10-29

- **The residual.** Review `M-ROKU-03 r1` issue 1 (minor): the entry below
  cured direct-mode teardown but its prose — and the OnLogout docblock it
  copied — claimed the session "lives on the host the login POSTed to" and
  that the hub-mode relay base is "a different session space with no such
  route". Both sentences are false wire provenance. The hub's
  `AuthController` login returns only `access_token`/`refresh_token`
  (phlix-hub `src/Http/Controllers/AuthController.php:99-100,:146-147` —
  no `session_id`) and the hub serves no user-facing `/sessions` HTTP
  route at all; the persisted `session_id` is ALWAYS a server-side row,
  created by PlayerScene's `createSession` through the relay base
  (`GetApiClient()` → `GetMediaBaseUrl()`), which the hub re-anchors at
  the picked server's `/api/v1/sessions` (phlix-hub
  `src/Application.php:595-615` registers the DELETE proxy; phlix-server
  `src/Server/Core/Application.php:902` `endSession`). The relay is
  precisely the working route; the bare hub url is the one with no such
  route — so post-fix, hub-mode logout sent
  `DELETE {hub}/api/v1/sessions/{id}` → 404, leaving teardown a silent
  no-op in hub mode (invisible: `result.ok` stays true, local logout is
  complete, server rows idle-expire; direct mode was genuinely cured).
- **The fix (reviewer option b).** `OnLogout` now resolves the teardown
  base through the guarded `GetMediaBaseUrl()` instead of `GetServerUrl()`,
  captured BEFORE the wipe: in hub mode the relay base depends on
  `connection_kind` + `active_server_id`, which `ResetCachedStorage(true)`
  deletes — resolving after the wipe would degrade to the bare hub url.
  Direct mode is byte-unchanged in behavior (`GetMediaBaseUrl()` is
  documented byte-identical to `GetServerUrl()` there); the DELETE now
  rides the same base + Bearer pair that created the session in both
  modes. The docblock states the wire truth with its cross-repo cites;
  the historical entry above is kept verbatim, corrected forward here.
- **The gate.** CHECK33 R2's false "host the login POSTed to"
  parenthetical is replaced by a static ordering leg: `OnLogout` must
  call `GetMediaBaseUrl()` BEFORE `ResetCachedStorage(true)` (and stay
  `IsServerConnected()`-guarded) — red on the pre-fix tree (no such call
  exists there), PASS on the cure. BrightScript has no unit runner in
  this repo; the verify-runtime static leg IS the test.

### Fixed — Logout lands on a real login surface; fake network error and silent-no-op teardown cured (CHECK33) — 2026-10-29

- **The hole.** Review `roku__casualgamer` M4 (major): logging out dead-ended
  the app on a bogus "Cannot connect to server. Check your network" error.
  The README law (`Connecting to your server`, step 4) promises logout
  "keeps `server_url`, so you return to the login screen on the same
  hub/server" — and the README was the honest side. `ResetCachedStorage(true)`
  (R1.6) called `registry.DeleteAll()`, over-widening the historical six-key
  auth/session wipe to the WHOLE registry section — `server_url` included.
  With the base erased, the next login POSTed `/api/v1/auth/login` at an
  empty URL; `roUrlTransfer.AsyncPostFromString` refuses outright,
  `ApiClient.request()` labels the failure `error: "connect"`, and
  `LoginScene` rendered a network-diagnostic for what was actually a
  self-inflicted missing-server state — an unrecoverable one from that
  screen. Two collateral bugs on the same path: the logout `ApiTask` was
  appended AFTER `ShowLogin()`, so it — not the scene — was the last child
  the `OnLoginSuccess`/`OnHubDetected`/`OnConnected` transitions pop (the
  transition then removed the task and left LoginScene on screen); and the
  server-side `DELETE /api/v1/sessions/{id}` teardown re-read
  `session_id` from the registry AFTER the wipe deleted it, so the DELETE
  was a silent no-op on every logout since it shipped.
- **The fix.** Make the code tell the truth: `ResetCachedStorage(fullReset)`
  now deletes exactly the six auth/session keys (`auth_token`,
  `refresh_token`, `session_id`, `connection_kind`, `active_server_id`,
  `active_server_name`) via buffered `registry.Delete` + one `Flush` — one
  NVRAM write, the R1.6 perf intent kept — and `server_url`, `username` and
  `device_id` survive, matching the README. `OnLogout` captures
  token/session/base BEFORE the wipe and carries them on the logoutTask
  request (`{op:"logout", base_url, auth_token, session_id}` — direct
  `server_url`, the host the login POSTed to, not the hub-mode relay base);
  the task is appended BEFORE `ShowLogin()`, restoring the
  last-child-equals-scene transition law; and `ShowLogin` gained the
  AppContext-law guard — with no server configured (legacy wiped installs)
  it routes to `ConnectScene` instead of dangling a login on an empty base.
  The `ApiTask` logout branch consumes the request (fresh
  `ApiClient(req.base_url)` with direct `.token` assignment, which — unlike
  `setToken` — does not re-persist credentials into the just-cleared
  registry) and keeps `result.ok = true` regardless of reachability.
  SettingsScene's "clear ALL 6 registry keys" comment now names the six.
- **The gate.** CHECK33 (scripts/verify-runtime.sh): (R1) `ResetCachedStorage`
  contains no `DeleteAll` and its wipe set EQUALS the six auth/session keys —
  wiping `server_url` is forbidden by constant; (R2) `OnLogout` captures the
  credentials before the wipe and the request carries all three fields;
  (R3) the task is appended before `ShowLogin()`; (R4) `ShowLogin` guards
  `IsServerConnected()` and routes to `ShowConnect()`; (R5) the ApiTask
  branch reads the request, never the wiped registry, rides the Bearer, and
  stays ok; (R6) the README promise sentence stays in place — if the law ever
  changes, the manual must be re-derived in the same commit. Red-on-parent
  proof: 11 problems on pre-fix files, PASS on the cure.

### Fixed — Settings restore-gate, Up Next ghost rail, and header-doc truth (CHECK32) — 2026-10-29

- **The hole.** Review `roku__casualgamer` M3+M6 (major), re-audited at
  70782bb. M3's headline claim (Settings unreachable for admins) was already
  cured by c6c9009/CHECK29 — the header walk is `search↔forYou↔favorites↔
  collections↔settings↔admin` in both directions — but two residuals stayed
  live: the README (`:498`) still described a four-button header
  `Search ↔ Favorites ↔ Collections ↔ Admin` (no For You, no Settings), and
  `FocusHeaderZone()` restored focus to `adminButton` without a `.visible`
  gate — a post-demotion getMe round hiding the button while `m.headerCol`
  still said "admin" stranded the grid->header return on a hidden node. M6
  was fully live: `upNextLabel` sat byte-identically on `libraryLabel`
  ([40,448]) and `upNextGrid` ([0,488]+300) stacked inside `libraryGrid`'s
  footprint ([0,484]+200), while the hand-rolled vertical chain consumed
  every up/down with `handled = true` and had no upnext arm — a ghost rail
  rendered under Libraries and unreachable by remote.
- **The fix.** Shared-slot rail law: the 720p home screen hosts exactly one
  rail row above Libraries (header to y=100, Libraries at y=448, description
  bar at y=680), so Up Next moved into Continue Watching's slot
  ([40,104]/[0,144]) and BOTH response handlers enforce the exclusion —
  `OnUpNextResponse` bails via `ContinueRailVisible()` while the slot is
  taken; `OnContinueWatchingResponse` retracts the upNext rail before
  claiming it — so whichever parallel load answers first, at most one rail
  is visible and nothing ever stacks on Libraries. The chain gained upnext
  arms: Down from the header and Up from the library grid enter the rail
  when it is the visible one, and Up Next leaves Down to Libraries, Up to
  the header zone. `FocusHeaderZone`'s admin restore is gated on
  `adminButton.visible` (a hidden button falls through to Search and
  resyncs `m.headerCol`). README's Home Header Navigation now walks six
  buttons with a For You and Settings bullet, matching the XML.
- **Static legs.** `scripts/verify-runtime.sh` CHECK32 R1-R5: the
  demotion-safe restore gate, the rail geometry (shared-slot equality AND
  vertical non-intersection with the Libraries row — the ghost stack is
  forbidden by constant), both loaders' exclusion guards, upnext-chain
  reachability both directions, and README header prose DERIVED from the
  XML button titles (count word + x-order chain line must equal what the
  scene declares). CHECK29 R5's admin restore pattern was relaxed to accept
  the `.visible` gate; CHECK32 R1 mandates it, so the pair is no weaker
  than either leg alone.

### Fixed — Back at Home exits the channel; black dead-screen cured (CHECK31) — 2026-10-29

- **The hole.** Review `roku__casualgamer` M2 (major): pressing Back on Home did
  not exit the channel — it revealed a black dead screen and required a second
  Back. `HomeScene.OnKeyEvent` has no back arm (by design — nav law CHECK27 R3
  keeps close signals out of the bootstrap scenes), so the key bubbled to
  `PhlixApp.OnKeyEvent`, which returned `PopScreen()`'s raw `false` at an empty
  stack and trusted docs/navigation.md's claim that "the Roku OS handles the
  back press and exit the channel". Fiction: with nested child scenes RSG's
  native close only ends the FOCUSED scene — HomeScene vanished, the root's
  black boot chrome (`bootLoadingLabel`/`bootErrorGroup`) sat on screen until a
  second Back closed the root too. Connect/Login/ServerPicker shared the bug.
  `PopScreen`'s own docblock law ("false ... signals the caller should exit the
  channel") had no acting caller.
- **The fix.** Honor the contract: `PhlixApp.xml` declares
  `exitChannel` (boolean, alwaysNotify); the `OnKeyEvent` back guard raises it
  and CONSUMES the key at stack-bottom; `main.brs` observes `exitChannel` on the
  screen message port and ends `main()` when the event arrives — the
  SceneGraph-correct channel exit, since the official component library bsc
  bundles lists no creatable `roApp` (only roAppInfo/roAppManager/
  roAppMemoryMonitor), so `CreateObject("roApp").Exit()` is a silent-invalid
  dead end. The loop additionally now exits on `roSGScreenEvent`/
  `isScreenClosed` (zombie-loop hygiene past root closure). One Back from Home
  exits cleanly, no black frame; docs/navigation.md's exit paragraph,
  docs/certification.md 3.3 and the README Back row were cured of the
  native-close fiction in the same commit.
- **The gate.** CHECK31 (scripts/verify-runtime.sh): (R1) root interface
  declares `exitChannel` boolean alwaysNotify; (R2) the OnKeyEvent back arm
  pairs `handled = PopScreen()` with the `not handled` guard that writes
  `m.top.exitChannel = true` and re-consumes; (R3) `main.brs` observes the
  field on a port and its wait loop exits on the event; (R4) the loop exits on
  `isScreenClosed`; (R5) no `.brs` calls `CreateObject("roApp")`. Red on the
  9ff4a6d parent era (5 problems), green at tip; mutation probe (strip the
  guard arm) reddens exactly R2.

### Docs — README endpoint fictions, dead URLs, locale-packaging truth (CHECK30) — 2026-10-29

- **The hole.** Review `roku__writer` C1-C3 (criticals). The README "API
  Endpoints" table still led with ten Emby-era rows (`Auth/Login`, the three
  `Sessions` verbs, `Library/VirtualFolders`, `Items`, `Sessions/Play`,
  `Playstate`, `Playstate/Progress`, `Users/Me`) — routes the server never
  registered (absent from the vendored 410-tuple
  `tests/fixtures/server-route-manifest.json`) and the client never calls
  (grep over `source/` + `components/` empty); CALIBER_LEARNINGS had already
  warned the pre-F0b prose was stale and the block survived the sweep. The
  manual-deploy recipe zipped `manifest source components images` and omitted
  `locale/` — following it ships a channel that renders raw catalog keys on
  the TV (docs/i18n.md states the consequence); only `make package` shipped
  locales. And zero-to-TV step 2 told readers to `git clone
  github.com/your-org/phlix-roku` (404), Support linked a 404 wiki, while
  package.json's repository.url named a third, also-dead home
  (`phlix-media/phlix-roku-client`, 404) — all three curls verified.
- **The fix.** The ten fictional rows are deleted and the lead-in now points
  at the gated manifest itself (every remaining row verified IN-manifest, or
  hub-registered in phlix-hub for the two hub-mode routes); the manual recipe
  zips all five trees with an honest parenthetical (the `make package` path
  was already true — `scripts/verify-package.sh` leg 5 fails a zip whose
  `locale/` tree carries zero files); clone URL, `cd`, Support links and
  `package.json` repository.url all point at the live
  `github.com/detain/phlix-roku-client` (the retired wiki replaced by the
  in-repo `docs/`).
- **Gate teeth.** `scripts/verify-runtime.sh` gains CHECK 30: the fabricated
  routes may never reappear backticked; every API-table `/api/v1/...` row
  must resolve against the vendored manifest ∪ the pinned hub-mode pair;
  README and package.json must know exactly one repo home; the manual zip
  recipe must name all five trees. Mutation-proven: the check ran red on the
  era README (23 problems, listed per file:line) before the docs were cured.
  `docs/static-checks.md` gains rows 27-30 (the table had silently stopped at
  26 when the C03/C20/C21 lanes added their checks) and its stale "All 26
  checks" count is corrected.

### Fixed — HomeScene header focus chain reaches Settings (CHECK29) — 2026-10-29

- **The hole.** Review `roku__gameux` C2 (critical): the hand-rolled Left/Right
  header walk in `OnKeyEvent` skipped `settingsButton` (x=1110) entirely —
  Right stepped collections→admin (isAdmin) and Left stepped admin→collections.
  Every header transition returns `handled = true`, which disables Roku's
  spatial-search fallback, so for admins `SettingsScene` (logout, caption mode,
  server switching, playback prefs) was HARD unreachable on a remote-only
  platform; non-admins fell through to the spatial accident and desynced
  `m.headerCol`. The observer and screen were finished (`OnSettingsPressed` →
  creates `SettingsScene`) — only the nav path to them was missing.
- **The fix.** Settings is inserted into the chain at its visual x-position:
  Search ↔ For You ↔ Favorites ↔ Collections ↔ Settings ↔ Admin. The step into
  Admin moves from Collections to Settings and stays `m.isAdmin`-gated (hidden-
  button law preserved); `FocusHeaderZone()` gains the matching restore branch
  so a grid→header return can land on Settings without desyncing the chain.
- **Gate teeth.** `scripts/verify-runtime.sh` gains CHECK 29: header candidates
  are parsed from the `HomeScene.xml` y=20 Button row and sorted by x, the
  Right walk must equal the consecutive x-order pairs, the Left walk its exact
  inverse, every edge must focus its destination column's node, the admin step
  must be `isAdmin`-gated, `FocusHeaderZone` must restore every column, and
  `settingsButton` must carry a live `buttonSelected`→`OnSettingsPressed`→
  `SettingsScene` wire. Mutation-proven: era code → 3 reds (R2/R3/R5); gate
  stripped → R4 alone reds; FocusHeaderZone branch removed → R5 alone reds.

### Fixed — validate-xml vacuous-pass hole closed (zero-file guard) — 2026-10-02

- **The hole.** The estate CI-gate audit (2026-10-02) found `make validate-xml`
  was an inline Makefile glob loop whose exit code was driven solely by
  per-file structure errors. When the glob discovered ZERO files — a renamed
  `components/` dir, a drifted path pattern, an empty checkout — the loop body
  never ran, nothing was validated, and the target still exited 0: a
  permanently-green gate that checked nothing.
- **The fix.** The check moved to `scripts/validate-xml.sh`, which parses its
  scan root at the boundary (missing dir = immediate refusal), counts every
  file it discovers, and fails loudly — non-zero exit + a message naming the
  empty discovery as a path-pattern regression — when the count is zero. The
  per-file law is unchanged (`<?xml version` + `</component>`). The default
  root derives from the script's own location (the `verify-runtime.sh`
  layout-independent idiom), so CI and dev sandboxes behave identically.
- **Falsifiability.** `tests/scripts/verify-runtime-portable.sh` gains legs
  (13a–d): real `components/` validates green with its file count echoed; an
  empty scratch root must exit non-zero with the loud "discovered ZERO XML
  files" message; a missing root must be refused; a planted malformed XML is
  named in the failure and removal returns exit 0 (plant/restore proves the
  extraction preserved the original per-file behavior).

### Changed — SyncPlay :8097 auth carrier flipped to the two-entry bearer subprotocol — 2026-09-30

- **The flip.** The hand-rolled WebSocket client (there is no `roWebSocket` on
  Roku — `SyncPlayTask`/`HubCommandTask` write the RFC 6455 upgrade themselves
  over `roStreamSocket`) now carries the bearer JWT on the handshake header
  `Sec-WebSocket-Protocol: bearer, <jwt>` — the TWO-ENTRY offer (marker entry
  first, raw JWT second, never dotted, never url-encoded) that
  `SyncPlayAuthMiddleware::bearerSubprotocolToken()` parses. `BuildSyncPlayWsParts`
  returns the bare `/syncplay` path + the token as a separate `bearerToken`
  config field; `SyncPlayTask.WaitForConnect` feeds it to the pre-existing
  `BuildHandshakeRequest` `extraHeaders` seam (the S298 header, generalized).
  No `?token=` remains on any code path.
- **The unblocker.** phlix-server `424c14d0` shipped the dual-carrier
  transitional law on `:8097` (docs/dev/WEBSOCKET_AUTH_CARRIERS.md): bearer
  header accepted, legacy query accepted TRANSITIONALLY for older builds,
  disagreement between carriers refused pre-101. The estate debt marker
  `WEBSOCKET_URL_QUERY_REFUSED` is retired for this client (transitional notes
  kept at every former TODO site).
- **101 echo tolerance.** The server answers an accepted *offered* handshake
  with exactly one `Sec-WebSocket-Protocol: bearer` response line (marker
  only). `HandshakeAccepted` is a status-line-only check and the header scan
  keys off the byte `\r\n\r\n`, so the echo is parsed and tolerated by design —
  pinned by `TestSyncPlayProtocolHandshakeAcceptedToleratesBearerEcho`
  (offered-echo and legacy-no-echo 101s both pass); offer serialization pinned
  by `TestSyncPlayProtocolBearerSubprotocolOffer` +
  `TestSyncPlayProtocolBuildHandshakeRequestWithBearerOffer` (and the plain
  handshake test now asserts NO token ever rides the query).
- **Docs.** README / CLAUDE.md / `SyncPlayTask.xml` interface comment
  restated to the header-carrier law. No display strings touched — locale
  catalogs unchanged. Hub mode unchanged (still refused client-side; the
  `:8804` `HubCommandTask` keeps its sanctioned `Authorization:` carrier).

### Fixed — dotted Translate keys render raw keys; CHECK 20 blind spot closed — 2026-09-29

- **The defect.** `components/AudiobookPlayerScene.brs` called
  `Translate("player.playback_error")` / `Translate("audiobookplayer.error_no_stream")`
  — dotted forms can never resolve: the loader flattens the catalog to
  `"<section>_<bareKey>"` underscore keys and `Translate()`'s nested-probe
  fallback only walks a fixed section list. The dialog would have rendered the
  raw keys. Fixed to `player_playback_error` / `audiobookplayer_error_no_stream`
  (both exist in all 7 catalogs); no other dotted call site exists in the tree.
- **The shield.** CHECK 20's key regex was the dotless class `[A-Za-z0-9_]`,
  so dotted literals were invisible to the scanner — that is how the defect
  shipped. The class now includes `.` (CHECK 20 and, for mirror-parity, CHECK
  24's `TP_KEY_RE`), and dotted misses report an explicit
  "dotted Translate key can never resolve" diagnostic naming the underscore
  form. `tests/scripts/verify-runtime-portable.sh` gained a CHECK 20 red leg:
  a planted dotted `Translate` fires red naming file + key + suggestion with
  Checks 21–26 green, and removing the plant returns the run to exit 0.
- **Catalog version** bumped 1.4.2 → 1.4.3 across all 7 locales (call-site
  fix + shield; catalog payloads byte-stable).

### Fixed — API envelope follow-through: every 2c119f9 consumer wired, + CHECK26 — 2026-09-29

- **The systemic break, completed.** `2c119f9` wrapped `ApiClient.request()`
  in the transport envelope `{status, ok, data, error}` and updated ZERO
  consumers — every reader of a former server field silently read `invalid`
  off the envelope. Dead and quiet: Home rails (`libraries`), item/detail
  loads (`item`), episode & library grids via `EpisodeListTask` (`items`),
  the whole Live TV list layer (`programs`/`recordings`/`channels`), hub
  detection + server picker (`servers` — plus a 404-vs-direct server that
  now maps to an honest empty list instead of a fake network error), SyncPlay
  group lists/create/join (`groups`/`group`), session creation
  (`session_id`), favorites/search/recommendations/admin/music/photos/
  collections/livetv op branches, and — separately pinned — **login**:
  the task derived `ok` from a `success` key the server AND hub never return
  (verified against `AuthManager::createAuthResponse` and the hub
  `AuthController`), so every credential entry died at "Login failed".
- **One unwrap, one choke.** New global `UnwrapApiEnvelope(env)`
  (`source/lib/ApiClient.brs`, ENVELOPE LAW docblock shipped in-channel) +
  `ApplyEnvelope(result, env)` in `components/ApiTask.brs`: every op branch
  now publishes the SERVER PAYLOAD at `response.data` with `response.ok` as
  the HTTP verdict — the shape the ~30 scene handlers were already written
  against. Scene fixes where the contract demanded more: `ListTask`,
  `EpisodeListTask`, `SyncPlayManager` (direct-call readers), `LoginScene`
  (ok-based verdict + honest four-case error taxonomy), `AuthManager.login`
  (envelope-aware), `AudiobookPlayerScene` (phantom `getAudiobookPlaybackInfo`
  op deleted — the route never existed server-side and the dispatch hung the
  player on its loading label; playback now starts from the signer-minted
  `stream_url` carried by the audiobook payload, or fails loudly with a new
  `audiobookplayer.error_no_stream` catalog string — locale v1.4.2 ×7).
- **CHECK 26 (make verify-runtime, 25 → 26).** Fails loud on the exact
  fingerprint of the old bug class: server payload keys read off
  envelope-level variables (`resp.libraries`, `data.items`, …), raw
  `api.X()` leaks into ApiTask `result.data`, and missing law artifacts.
  Regression leg in `tests/scripts/verify-runtime-portable.sh` plants a
  `resp.libraries` read in scratch `DetailScene.brs`, proves CHECK 26 goes red
  naming file and read while Checks 20/24/25 stay green.
  `tests/unit/ApiEnvelope.test.brs` pins the helper semantics (six pure
  cases incl. the login-shape pin). Law documented at `docs/api-envelope.md`.

### Changed — syncplay twin-flip evidence promotion: reserved trio → emitted-verified — 2026-09-25

- **The flip landed upstream.** phlix-server PR #798 @ `9b2394ee` switched the
  group create/join/leave failure wraps to the dotted registry forms —
  `syncplay.create_failed`/`join_failed`/`leave_failed` are LIVE on the wire
  (`SyncPlayManager.php:1588/1627/1659`, re-verified read-only at origin).
  Per the #90 promotion law, the trio moved from declared-reserved to
  emitted-verified in Check 22's evidence split and the `Utilities.brs`
  docblock. Census (19) and all seven catalogs are **byte-stable** — only the
  split moved.
- **Reserved ledger is now empty; the gate stays armed.**
  `SyncPlayReservedErrorCodes()` is kept with a documented empty state:
  declaration-before-census-entry ("declaration, not discovery") is a
  structural law, and collapsing it would silently disarm the next flip.
  Check 22's reserved legs now pin the empty set; the portable harness gained
  red proofs for a rogue declaration in the empty function AND for removing
  the function outright.
- **SCREAMING trio stays resolved.** `CREATE_FAILED`/`JOIN_FAILED`/`LEAVE_FAILED`
  remain in the 19-census and catalogs — they are emitted only by pre-flip
  servers, and a family retires only when its servers do (the dual map's whole
  point). Evidence annotations in the checker now name both server SHAs.

### Added — i18n XML-chrome lane: markup strings inside the translate net + CHECK25 — 2026-09-25

- **The last documented i18n gap closed.** User-facing literals shipped as
  SceneGraph markup (`title=`/`text=` attributes in `components/**/*.xml`) were
  invisible to Checks 19-24, which read only `.brs` source. All 182 markup
  literals are now covered: 6 reasoned exemptions (brand "Phlix" ×2, the "PiP"
  acronym, RatingBadge glyph/numeric placeholders, the never-rendered Toast
  placeholder) and 176 catalog-backed strings whose localized value is set at
  scene init by a new per-component `ApplyXmlChrome()` pass (findNode +
  `Translate()`/`TranslateWithParams()` guard per node), following the
  DetailScene action-button precedent. ~20 previously id-less header labels
  gained ids so the override can address them.
- **Catalog v1.3.0 → v1.4.0, 140 → 273 keys per locale** (×7). New
  `common_*` chrome vocabulary (buttons/sections), scene sections
  (`player_*`, `connect_*`, `login_*`, `search_*`, `parentalcontrols_*`,
  `library*`, `libraryadminactions_*`, `useradminactions_*`, `syncplay_*`
  labels, `detail_row_*`, empty/select states); reuse where the value already
  existed (`common_ok/retry`, `detail_favorite_add` etc., `settings_item_
  caption_mode`, `utilities_rating_*`). `'Loading...'`/`'Loading…'` unified on
  `common_loading`. Registers follow house law: informal tú/vous/du/tu/você,
  ja desu-masu labels. `_metadata.source_files` now enumerates every `.brs`
  calling Translate.
- **Token templates replace concatenated chrome:** ProfileActions rating
  buttons carry bare `G…UNRATED` defaults composed via
  `profileactions_rating_prefix {rating}`; Library `Sort:`/`Filter:` labels
  became `library_sort_label {sort}` / `library_filter_label {filter}` with a
  literal-Translate `TranslateSortLabel` resolver (replaces the English value
  map); ParentalControls/Profiles profile-interpolated titles became
  `*_title_with_*` templates; PlayerScene up-next countdown/title became
  `player_playing_in {seconds}` / `player_up_next_title {title}`; boot-error
  and playback-panel strings became `app_boot_*` / `player_*` keys.
- **Check 25 (guard law, append-only):** parses every `components/**/*.xml`
  (entity-decoded), requires each non-empty markup literal to be exempt
  (stale exemptions red), catalog-byte-matched, id-addressable, and proven to
  have a real override path (`findNode("<id>")` + `Translate("<value's key>")`
  in the paired `.brs`); `<text>` content nodes rejected outright; fail-loud
  `file:line`. The portable harness now ships the full `components/` tree,
  asserts Check 11-25 headers, and gains the red-25 leg: a planted raw label
  fires CHECK25 while Checks 20-24 stay green.
- **Gates:** `make lint` · `make bslint` · `bash scripts/verify-runtime.sh`
  (25/25, exit 0) · `bash tests/scripts/verify-runtime-portable.sh` (all
  legs, exit 0) · `make package` green. No `Translate()` call-site key was
  changed on existing screens; device-run posture unchanged (no ROKU_HOST in
  this venue — rooibos suites skip by precedent).

### Changed — W111 (cs47b): route-manifest CONTENT re-vendor (404→410 tuples) — 2026-09-17

- **cs#47 currency re-vendor (lane cs47b) — CONTENT regen, roku is NOT pure this
  wave.** `tests/fixtures/server-route-manifest.json` re-vendored byte-identical
  from the `@phlix/contracts` canonical master export (untagged regen #34), and
  the code pins in `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA` →
  the era sha; `TOTAL_TUPLES` → 410, RISEN with the six new quick-connect /
  telemetry routes; Application guard count 367→373, WebPortal 48 and shared 11
  hold) advance in the same commit; the header gains the regen-lineage note. The
  route-content bytes move alongside provenance — every tuple the gate still
  matches is unchanged, so no roku request site needed re-pinning: the client-route
  scan re-measures at the same 91 request sites / 81 distinct tuples with the
  falsifiability self-test green.

### Changed — W93 (cs46a): route-manifest PROVENANCE re-vendor (404 tuples — route bytes unmoved) — 2026-09-15

- **cs#46 currency re-vendor (lane cs46a) — PROVENANCE-only re-pin.** Roku is PURE
  currency: `tests/fixtures/server-route-manifest.json` re-vendored byte-identical
  from the `@phlix/contracts` canonical master export (untagged regen #33), and the
  code pin in `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA` → the era
  sha; `TOTAL_TUPLES` → 404, held) advances in the same commit. The diff against the
  previous vendored bytes is provenance-only: no route-registration change upstream,
  so the `[method, path]` tuples are byte-for-byte identical and the count holds at
  404; only the embedded provenance moves, which rotates the vendored blob while the
  described route surface is unchanged. The client-route scan is unchanged —
  re-measured at **91 request sites / 81 distinct tuples**, with the falsifiability
  self-test green.

### Changed — W85 (cs45): route-manifest PROVENANCE re-pin (404 tuples — route bytes unmoved) — 2026-09-13

- **cs#45 currency cascade (lane cs45) — PROVENANCE-only re-pin.** Roku is PURE
  currency: `tests/fixtures/server-route-manifest.json` re-vendored byte-identical
  from the `@phlix/contracts` canonical master export (untagged regen #32), and
  the two code pins in `tests/scripts/verify-route-manifest.mjs`
  (`PROVENANCE_SHA` → the era sha, `TOTAL_TUPLES` → 404, held) advance in the same
  commit. The server span since the previous pin is bundle-only: no
  route-registration file and nothing under the server's `include/` or `src/`
  moved, so the `[method, path]` tuples are byte-for-byte identical and the count
  holds at 404; only the embedded provenance moves, which rotates the vendored
  blob while the described route surface is unchanged. Roku's legacy
  `/music/albums/{name}` + `/music/artists/{name}` builders stay put (S240 is
  additive; they remain tuple-exact in the 404 superset) and the client-route scan
  is unchanged — re-measured at **91 request sites / 81 distinct tuples**, with
  the falsifiability self-test green. No survival-token home in this repo — the
  wave token lives in its two verified code homes.

### Changed — W83 (cs44): route-manifest PROVENANCE re-pin (404 tuples — route bytes unmoved) — 2026-09-13

- **cs#44 currency cascade (lane cs44) — PROVENANCE-only re-pin.** Roku is PURE
  currency: `tests/fixtures/server-route-manifest.json` re-vendored byte-identical
  from the `@phlix/contracts` canonical master export, and the two code pins in
  `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA` → the era sha,
  `TOTAL_TUPLES` → 404, held) advance in the same commit. The server span since the
  previous pin is bundle-only: no route-registration file and nothing under the
  server's `include/` or `src/` moved, so the `[method, path]` tuples are
  byte-for-byte identical and the count holds at 404; only the embedded provenance
  moves, which rotates the vendored blob while the described route surface is
  unchanged. Roku's legacy `/music/albums/{name}` + `/music/artists/{name}` builders
  stay put (S240 is additive; they remain tuple-exact in the 404 superset) and the
  client-route scan is unchanged — re-measured at **91 request sites / 81 distinct
  tuples**. No survival-token home in this repo — the wave token lives in its two
  verified code homes.

### Changed — W81 (cs43): route-manifest CONTENT regen (402→404) — pure currency, no client migration — 2026-09-12

- **cs#43 currency cascade (lane cs43) — a CONTENT regen.** phlix-server S240
  merged two ADDITIVE query-param rails (`GET /api/v1/music/artist?name=` and
  `GET /api/v1/music/album?name=`), so the vendored route manifest grows
  **402 → 404 `[method, path]` tuples**. `tests/fixtures/server-route-manifest.json`
   re-vendored byte-identical from `@phlix/contracts` master (untagged regen #30
   against the then-current phlix-server tip); the blob is content-identical
   across the estate.
- **Roku is PURE currency this wave — no client migration.** The two code pins in
  `tests/scripts/verify-route-manifest.mjs` (`PROVENANCE_SHA` → the era sha,
  `TOTAL_TUPLES` → 404) advance in the same commit. Roku's legacy
  `/music/albums/{name}` + `/music/artists/{name}` builders in
  `source/lib/ApiClient.brs` stay put: S240 is additive and the server still
  serves the path-param rails, so they remain tuple-exact in the 404 superset. The
  client-route scan is unchanged — re-measured at **91 request sites / 81 distinct
  tuples across 2 modules, tuple-exact**; `--self-test` still demonstrates the gate
  is falsifiable (planted-unserved RED + sibling-absence RED + served GREEN). Roku
  carries no md5 pin. Untagged wave.

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
