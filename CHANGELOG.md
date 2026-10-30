# Changelog

## [latest] — rolling sideload prerelease · published on every push to master

**Release model — what is actually released (verified, not narrative).** This
repo has never shipped a versioned release ladder, and this file used to hide
that behind an `[Unreleased]` header over two months of published history. The
truth, read from `git ls-remote --tags origin`, `git log` and
`.github/workflows/package.yml` on the day this block was written, and every
claim below re-checkable the same way:

- **The sideload/QA channel is one rolling `latest`.** The Package workflow
  publishes a GitHub prerelease named `latest` on every push to `master`: the
  job deletes the previous `latest` release *and its tag*
  (`gh release delete latest --yes --cleanup-tag`), then recreates it from the
  freshly built `phlix.zip`. `git ls-remote --tags origin` shows exactly one
  tag (`latest`) — there are no per-version git tags or versioned GitHub
  releases, before or since the vehicle shipped (`3b36606`, 2026-06-28,
  "ci: publish the Roku sideload zip to a rolling \"latest\" release (#13)").
  Everything merged to master ships to sideload users within one CI cycle: the
  dated entries below this header are **released history**, and `docs/publishing.md`
  ("Release Vehicles and Rollback") is the single canonical statement of the
  vehicle, the no-rollback consequence, and the owner-gated versioned-tag plan.
- **No versioned releases exist; claims of any are retracted.** A 2026-10-30
  fix report for this item claimed "tag-verified releases" v1.0.0@e06e35c,
  v1.1.0@b8e03e7, v1.2.0@d5743b0, v1.3.0@2f29b69 and v1.4.0@587f85b. Those
  tags never existed on origin or locally — the r1 review's `git ls-remote
  --tags`/`git tag -l` sweep found exactly one tag (`latest`) then, and this
  lane's independent re-probe on a fresh clone finds the same now. The ladder
  was fabrication, not history, and no future section of this file may claim a
  versioned release the tag layer cannot show (verify-runtime Check 59 R3
  convicts the shape).
- **The store channel is the version triple, not git.** `make package-signed`
  derives the submission `(major, minor, build)` from `package.json`
  "version" — `1.0.1`, unchanged since the field was introduced at `ad9dee1`
  (2026-05-15); no store-submittable bump has ever landed here. Which build is
  live in the Roku Channel Store is Developer Portal state, not repo state
  (docs/publishing.md, "Version Discipline").
- **Chronology anchors, from real commit history** (each resolvable with
  `git show -s <sha>`):
  - 2026-05-14 `dabad21` — first commit in this repo's history.
  - 2026-05-15 `367c48a` / `ad9dee1` — "Restructure: Keep only Roku client
    code"; the 1.0.1 triple lands (manifest + package.json) and holds to today.
  - 2026-06-28 `3b36606` — the rolling `latest` vehicle ships; live ever since.
  - 2026-08-05 `b86bef0` — the `## [R4.10]` section below is stamped; the last
    named release section this file will carry until the owner ships versioned
    releases (owner-gated, not yet).
  - 2026-08-06 → tip — 203 commits (`git rev-list --count master
    --since=2026-08-06`, measured for this entry) reached users only through
    the rolling `latest`; their change log is this section's dated entries.
  - 2026-10-30 `e1d04b8f` — current master tip: the commit the single `latest`
    tag points at while this entry is written.

### Fixed — W-min94 minors cluster (3 cured, 3 stale-verified, 2 honest-blocked) — 2026-10-30

- **M-ROKU-25 (cured, half stale).** The observer-stack half was already dead:
  the retry button's `buttonSelected` wiring moved to a single `Init` owner in
  `6c9e348` (its docblock names the m5 cure). This lane closed the orphan half
  of the ask: `StartAuthCheck`/`StartHubAuthCheck` now DETACH the replaced
  task and timer (`RemoveChild`, stop, un-observe) instead of only un-observing,
  so retry-mashing can no longer accumulate orphaned ApiTask nodes each with an
  in-flight `/auth` request. Disclosure — the 20s boot `Timer` was never
  appended to the render tree, and the repo's own toastTimer law (attach or it
  never ticks) means the boot timeout chrome was device-side fiction; the cure
  appends it, making both the documented behavior and the exploiter's
  "live 20 s timer" premise true.
- **M-ROKU-28 (cured).** `screenStack` gained a depth cap (12): accepted ECP
  deep-links beyond it are refused with a printed conviction instead of
  pushing unbounded DetailScene nodes (the review's memory-pressure walk-down
  on low-tier Rokus); both deep-link call sites handle the refusal. The four
  bootstrap transitions the ask named (`OnConnected`, `OnHubDetected`,
  `OnServerPicked`, `OnLoginSuccess`) now remove their scene by NAMED
  reference (`m.connectScene`/`m.loginScene`/`m.pickerScene`) — the
  `RemoveChild(GetChild(Count-1))` "whatever is last" invariant is gone from
  those paths. (The two `GetChild(0)` logout/teardown sites are outside the
  ask's cited set; disclosed as residual.)
- **M-ROKU-32 (cured).** SearchScene gained the alternative binding the ask
  named: `down` from the keyboard moves focus to the results rail whenever
  results exist. Additive-by-construction — firmware whose `Keyboard`
  consumes `down` internally never delivers it to the scene, so existing key
  navigation is untouched; on the review's failure mode (right-at-edge does
  not bubble) the rail is now reachable. The same device-unverifiable caveat
  the review stated is preserved in the branch docblock.
- **M-ROKU-33 (stale-verified).** Duplicate boot-error observers: cured at
  `6c9e348` (ancestor of HEAD, raws in the fix report) — the observer wires
  exactly once in `Init`; `ShowBootError` only focuses. Content proof: the
  in-file docblock names the m5 cure.
- **M-ROKU-38 (stale-verified).** Deep-link `contentId` path injection:
  `ValidateDeepLinkContentId` now delegates to `IsSafeContentId`, the
  `[A-Za-z0-9_-]` allowlist shipped by `6a40a8f` (ancestor-verified; the
  function's own header recounts the retired printable-minus-`&` checker),
  headless-pinned by `tests/unit/ContentIdGuard.test.brs` in the CI gate.
- **M-ROKU-41 (stale-verified, platform bound disclosed).** The ask's action
  half — verify `Sec-WebSocket-Accept` — shipped fail-closed at `4240ad2`
  (`m.proto.VerifyHandshakeAccept`, ancestor-verified; the W-min91-era battery
  and `SyncPlayWsTls` suite pin it). `RandomByte` remains `Rnd()`-based:
  Roku BrightScript exposes no CSPRNG primitive, and the review itself grants
  the key carries no security absent TLS — the fold-in it asked for is live.
- **M-ROKU-37 (honest-blocked).** Ask: "prefer https for LAN too (self-signed
  warning UX / optional cert upload) or at least a persistent
  cleartext-credentials warning at login". The default-scheme flip breaks the
  fail-closed self-signed-https LAN installs the current policy tolerates and
  the warning-UX half is an owner copy/flow call across seven locale catalogs
  — transport-policy posture, not a blind minors cure. Ruled to the owner reel.
- **M-ROKU-40 (honest-blocked).** Scheme allowlist before assignment across
  stream/transcode/BIF/redirect/poster surfaces. A wrong boundary (the sets
  legitimately mix `http(s)://` server URLs with `pkg:/` placeholders — see
  the placeholder pairs at `AudiobookScene`/`CollectionScene`/`DetailScene`/
  `EpisodeListTask`/`FavoritesScene`) silently kills image and stream chrome
  on device, and this venue cannot verify `Video`/`Poster` render outcomes
  headless. Cure spec: one `IsAllowedMediaUrl` (http/https/pkg:) in Utilities
  applied at each assignment, device-verified. Held for hardware.

### Fixed — W-min93 minors cluster (6 cured, 1 partial-cured, 1 honest-blocked) — 2026-10-30

- **M-ROKU-07 (cured).** The Continue-Watching first-load focus get-yank:
  `OnContinueWatchingResponse` moved focus into `continueGrid` unconditionally
  on first load, teleporting a user who had already navigated to the header.
  The grab now fires only while `m.top.focusedChild = invalid` — the boot
  state where nothing has claimed focus — so the row still becomes the boot
  destination but never yanks an already-moved user.
- **M-ROKU-10 (cured).** `LibraryScene` wire-shape law applied (the sibling
  `CollectionScene` guards, review roku__crossfe m2): `getLibraryItems`
  responses now require `type(resp.data.items) = "roArray"` before
  `m.items.append` (a PHP-preserved-key dict made `roArray.Append(roAssociativeArray)`
  a channel-ending runtime error); `year` accepts both String and numeric
  carriers instead of `str()` type-erroring on a String year; `getLetterIndex`
  stores only a real array and `BuildAzBar` participates only in AA rows with
  an integer `count` (`invalid > 0` on dict-shaped payloads is a runtime
  error).
- **M-ROKU-14 (cured, residual delta).** The packaged-artifact gate already
  existed (`scripts/verify-package.sh`, C08 era) and covers the ask's
  manifest-root + no-`build/` legs; this lane closed the residual the ask
  named: the shipped root manifest must carry `rsg_version=` and every
  `images/…` path it references must exist as an archive member.
- **M-ROKU-16 (partial-cured; remainder honest-blocked).** Cured the pure
  parser half of the ask: `ParseFrames` 126/127-extended lengths are clamped
  (zero high word, clear top bit, minimality, 1 MiB sane maximum) — the old
  plain-Int math overflowed to negative `payLen` on `b6 >= 128`, letting the
  cursor walk backwards into `buffer[-n]` — and a rejection closes the
  socket via `rejectedOversize` in `HandleSocketEvent`. Honest-blocked (ask
  quote: "distinguish would-block … add a pong-miss deadline (3 × interval)
  and mirror HubCommandTask's ladder"): the negative-`Receive` taxonomy and
  ladder re-dial semantics are device-unverifiable in this venue (brs does
  not implement `roStreamSocket`; hardware confirmation of the would-block
  constant vs abort codes is a precondition), same verification-gated class
  the lane logged for hardware asks. Cure spec retained here for a
  hardware-verification lane.
- **M-ROKU-22 (cured).** `OnPlayPressed` gained the `m.playPending` guard;
  the flag clears in the `getItemPlaybackInfo` arm which runs for ok AND
  error envelopes — mashing OK can no longer spawn concurrent PlayerScenes
  and self-inflicted 429 stream-limit bursts.
- **M-ROKU-23 (cured).** All six detail mutations (favorite/unfavorite,
  setRating/clearRating, markWatched/markUnwatched, like, collection add/
  remove) plus the initial `getCollections` fetch now route through
  `SendMutation` behind `m.mutationPending` and release via `EndMutation` in
  their response arms — the ParentalControlsScene `m.pendingOp` serialization
  idiom at the detail surface; presses during a flight are ignored instead of
  bursting requests and racing the revert-on-failure flips.
- **M-ROKU-26 (cured).** `MintRelayToken` returns only a `type(parsed.token) = "roString"`
  value; a hostile hub answering `{"token":123}` can no longer cross a
  non-String into the downstream `"Bearer " + relayToken` and kill the
  command channel before the ladder starts.
- **M-ROKU-36 (honest-blocked).** Ask: "Login uses deprecated `TextEditBox`
  … Roku's current guidance is `VoiceTextEditBox`/dynamic keyboards; … no
  visible retry affordance". The component swap changes the account-entry
  critical path (a regression bricks login on every device at once), carries
  firmware-support surface this venue cannot verify headless, and the
  retry-affordance half is a UX redesign — owner/device-verification call,
  not a blind minors cure. `TextEditBox` renders the system keyboard today
  (review's own words), so shipping posture is unchanged while blocked.

### Fixed — W-min92 minors cluster (3 cured) — 2026-10-30

- **M-ROKU-12 (cured).** The route-manifest fixture was pinned to the
  v0.5.2 era: `tests/fixtures/server-route-manifest.json` re-vendored
  BYTE-FOR-BYTE from contracts tag `v0.5.3`
  (`dist/server-route-manifest.json`, md5
  `915796837d38a77733c169996d97640c`, 412 tuples @ server
  `758f91496c068551b310f1078093335f79c20e04`), replacing the 410-tuple
  `730e55b7` bytes; the gate's `PROVENANCE_SHA`/`TOTAL_TUPLES` constants
  and header prose followed, and the currency token rotated
  (`CS47REVENDORPINQ7T3`). The SyncPlay error census 19->20 resolved as
  a PROMOTION, not a reservation: `syncplay.queue_limit_exceeded` is
  LIVE server-side since `7baa398a` (ancestor-verified;
  `SyncPlayManager.php` sendError site), so `SyncPlayKnownErrorCodes()`,
  the Check 22 emitted-verified set, Check 23's count pins, the seven
  locale catalogs (new `errors_syncplay_queue_limit_exceeded` line;
  catalog set bumped 1.11.0->1.12.0 as a set, rotating CHECK48 R3's
  version pin — disclosed on that row) and the localized-line test
  pins all moved together. Editor hazard now documented in-body: the
  Check 22/23 extractors pair double-quoted strings across the RAW
  census body, so a quoted word inside that function hijacks
  extraction — keep census-body comments quote-free.
- **M-ROKU-13 (cured).** The route gate's scanner matched only
  `.request(`/`.sendRaw(` — the login URL issued inside
  `sendRawWithDeviceId` escaped the census (scanned 91 -> 92, re-pinned
  from measured red), and the header claim that EVERY URL the client
  touches is tuple-exact was overbroad. The gate now matches the third
  call shape, and the two genuinely out-of-registry classes —
  `HubCommandTask`'s hub-registry relay-token site and the two WS dial
  paths (:8097 direct + :8804 relay) — are declared rosters
  (`HUB_SITES`/`WS_SITES`) with per-site reasons and
  literal-survival pins: a roster site whose code text vanishes, or a
  hub site that starts resolving against the SERVER registry, reddens
  the gate. Honest partition, not regex accident.
- **M-ROKU-19 (cured).** `scripts/validate-xml.sh` discovered only a
  FLAT `components/*.xml` glob and "validated" with two substring
  greps: a nested XML file had ZERO coverage while `total_files` stayed
  above the zero-guard, and any malformed document whose
  `<?xml version` / `</component>` markers merely EXISTED passed. The
  script now walks recursively (deterministic order), requires the
  prologue on the first line, runs a real `xml.etree`
  well-formedness parse and asserts the lowercase `<component>` root,
  keeping the zero-file and missing-root fail-louds verbatim.
  Portable legs 13e (nested plant convicted by relative path, restore
  green) and 13f (a file surviving BOTH legacy greps convicted by the
  parser) pin both holes; the real repo validates 48 files green.

### Fixed — W-min91 minors cluster (6 cured) — 2026-10-30

- **M-ROKU-15 (cured — CI unit coverage was fiction).** The 22-suite
  `tests/unit/*.test.brs` roster (291 `sub Test*` cases) executed nowhere:
  `assertTrue`/`assertEqual` were defined nowhere in the repo
  (rooibos-era scaffolding), no runner was wired, and the surrounding
  prose claimed coverage. Cure:
  `tests/scripts/run-headless-unit.mjs` drives the rokucommunity `brs`
  interpreter (devDependency `brs@0.45.0`) over the roster with a
  device-faithful assertion prelude (raw `<>` compare, `GetGlobalAA`
  fail counter, a device-correct `Right` shim for brs' measured
  off-by-one at n==Len), per-test isolation (fresh execute per case),
  closure-resolved source loading and `--selftest`/`--suite`/`--list`
  surfaces. Measured: 210 cases run green, 0 failed; 53 per-test
  exclusions + 4 whole-suite exclusions (28 cases), each carrying a
  measured brs-gap reason (function-object state at `Storage.brs:78` /
  `Utilities.brs:1462`, `roByteArray`, int `not`, invalid-to-typed-formal
  strictness, `Chr(0)` collapse; the `Theme` suite drives a `Theme()`
  API that exists nowhere in the tree — fictional, delete-or-rebuild
  follow-up disclosed; `tests/integration/ApiIntegration.test.brs`
  remains device-integration scope).
  Executing the suites convicted REAL device bugs, all cured here:
  `.Lower()` member calls x14 (no such Roku string member — the global
  is `LCase`), `.Left/.Mid/.Right` member calls x34+ (device globals,
  not members; brs phantom-serves them 0-based, so the class returned
  silently wrong text, e.g. `HostOfUrl`), `.UCase()` members x4, the
  fabricated `.padz(n)` member x6 and `.Repl(" ","0")` member misuse
  x3, `ByteToHex` indexing 0-based into the 1-based `Mid` (EVERY
  percent-escape wrong on device — `UrlEncode(" ")` != `%20`),
  3-argument `.SortBy(` x2 (the signature is 2-arg), `SleepTimer`'s
  duplicate-AA-key `isActive` field-vs-accessor (last-key-wins turned
  the field into a function — `if not m.isActive` crashed; accessor
  deleted), `SkipButton` recording model state before its node guard,
  `OriginOfUrl`'s bracketed-IPv6 off-by-one pair, `HostOfUrl`'s
  bare-IPv6 passthrough, `TokenValueText`'s boxed-boolean parameter
  contract (untyped formal; `roBoolean` arm), and `SleepTimer`
  float-division time math x3 (`/` -> `\`). New Check 65
  (`scripts/verify-runtime.sh`) pins the forbidden-member family
  extinct across `source/` + `components/` + `tests/`, with self-probes
  and the R5 wiring law below.
- **M-ROKU-17 (cured).** test.yml's `Run unit tests` step was gated
  `if: env.ROKU_HOST != ''` while the job env never defined ROKU_HOST —
  permanently dead, unarmable even with secrets (contrast package.yml,
  which wires the secret). Replaced by an unconditional device-free step
  running the headless gate; CHECK65 R5 convicts the dead-step shape
  re-growing.
- **M-ROKU-18 (cured).** Makefile prose-vs-behavior truth: `test-unit`'s
  docblock promised "SKIPS with success" while its no-host arm ended
  `exit 2`; `test-integration` ran its suite then hit an UNCONDITIONAL
  `exit 1`. `test-unit` now runs the headless gate device-free by
  default (rooibos-on-hardware when ROKU_HOST is set); `test-integration`
  is honest device-only with a says-so loudly arm; the `test` umbrella
  ERROR arms agree with their echoes.
- **M-ROKU-20 (cured).** `make package` is deterministic: staged tree,
  fixed mtimes (`touch -t 200001010000.00`), `LC_ALL=C sort` entry
  order, `zip -X` — measured byte-identical across two builds.
  `phlix.zip.sha256` companion is generated and printed; package.yml
  verifies it (`sha256sum -c`), uploads the pair and the rolling
  release body carries the digest.
- **M-ROKU-21 (cured).** `make install` leaked credentials on argv
  (`curl -u dev:pass` is visible in `ps`; the defaults were
  rokudev/rokipassword) — creds now ride `curl --config -` on stdin.
  The `-F "manifest=@manifest"` form field re-introduced the manifest
  dual-source the C08 cure buried (raw checked-in file vs the
  version-injected `build/manifest`) — dropped; the zip's root manifest
  is the single source verify-package.sh already asserts.
- **M-ROKU-44 (cured).** README's env table now documents ROKU_HOST /
  ROKU_TEST_HOST (the names the test gates read) alongside ROKU_IP
  (install/launch/stop) with each surface's readers spelled out — the
  misleading `ROKU_IP=… make test-unit` silently-skip class is closed
  at the doc surface, and after M-ROKU-18 the device-free default
  closes it in behavior too.

### Fixed — W-min90 minors cluster (7 cured, 1 stale-verified) — 2026-10-30

- **M-ROKU-01 (stale-verified, zero diff).** The "five names" finding no
  longer describes the live surface: "watch parties"/"the sync server" copy
  left the catalogs at `4cb7a84`, "watch room" at `ef5b619` (the co-watch
  one-name law later pinned by Check 57), and the error taxonomy at
  `d252b17` — all ancestors of this commit. Live overlays speak Watch
  Together + group consistently. The residual `syncplay.*_room` values ride
  only the DEAD room-scene key set (Check 56 R3 provenance law) whose
  delete-or-re-home disposition is the same open owner decision as
  M-ROKU-09; touching them here would preempt it.
- **M-ROKU-02 (cured, partial-stale disclosed).** `errors.unknown_message`
  says what to do next in all seven locales ("... Please try again." +
  sibling translations) — the review convicted dead-end prose.
  `PhlixApp.ShowContentNotFoundDialog` shipped a hardcoded
  `"Content Not Available"` + a subscription fiction ("check your
  subscription") — now `app.content_unavailable_title` /
  `app.content_unavailable_message` x7, honest server copy. The "hub mode"
  phrase survives on purpose: it is README/docs shipped vocabulary and the
  value is cataloged (the review's own PlayerScene:1587 exhibit was already
  localized at `a5dad23`), so it is NOT-CHANGED with rationale.
- **M-ROKU-04 (cured, partial-stale disclosed).** Nine hardcoded runtime
  strings now ride the catalog: ServerPickerScene load-failure caption +
  "No servers", CollectionsScene "No collections", DetailScene's two
  collection errors, "No stream URL available" x2 (LivePlayerScene +
  PlayerScene), LivePlayerScene "Playback failed" (adopting the existing
  fuller `player.err_playback_failed` copy) and PlayerScene's raw `"Error"`
  dialog title → `Translate("common_error")`. Eight keys added to all
  seven catalogs; CHECK64 R1/R2 pin extinction + the roster. Connect/
  Login/PlayerScene-dialog legs of the finding were already cured at
  `d252b17`/`a5dad23`.
- **M-ROKU-11 (cured).** SettingsScene's account email read
  `GetApiClient().user.email` — a field never restored across scene
  launches, so the dialog stranded on "Logged in as ". The scene now
  dispatches the auth-gated `getMe` op through its own ApiTask (HomeScene
  semantics), type-guards the wire payload, and falls back
  email → username → persisted login name → cataloged "Unknown". No new
  Storage key — CHECK33's six-key wipe law stays whole. CHECK64 R5 pins
  the extinction and the replacement mechanism together.
- **M-ROKU-30 (cured).** `adminButton` sat at x=1240 w=180 — ending 140px
  past the 1280 design plane (the isAdmin gate hid the overflow). The
  header row repacked inside the canvas preserving x-ORDER, y=20 and
  `visible="false"` (CHECK29's walk is name-paired, untouched); CHECK64
  R4 pins x+width <= 1280 for every row member.
- **M-ROKU-42 (cured).** The prerequisites bullet credited the editor to
  "BrightScript by彩虹"; the canonical marketplace extension is
  *BrightScript Language* by RokuDeveloper. README corrected.
- **M-ROKU-47 (cured).** Five "..."-typed values per catalog (settings
  loading/clearing, syncplay status trio) became the U+2026 house glyph
  across all seven locales (35 values); CHECK64 R6 convicts any
  three-dot ellipsis returning to a catalog VALUE.
- **M-ROKU-50 (cured, code-side stale).** README's troubleshooting quote
  still surfaced "Couldn't reach that server" — copy the client stopped
  shipping at `d252b17`; the quote now names the real cataloged sentence
  (`connect.err_unreachable`). The PlayerScene hub-mode string it also
  flagged was already localized at `a5dad23`; README:221's quoted value
  stays verbatim (the adjudicated hub-mode copy) — no rot.
- **Catalog set-bump (disclosed).** `_metadata.version` 1.10.0 → 1.11.0
  as a set x7 for the eight new keys; CHECK48 R3's version pin rotated in
  the same commit per its own bump-as-a-set law. CHECK63 (W-min89) and
  CHECK64 leg rows landed in `docs/static-checks.md`.

### Fixed — W-min89 minors cluster (4 cured, 1 honest-blocked) — 2026-10-30

- **M-ROKU-03 (cured).** `GetErrorMessage`'s default arm echoed the raw
  wire string into spoken dialogs (`if len(safeError) > 0 then return
  safeError`). Transport reason codes now land on the
  `TranslateTransportReason` catalog ladder; any other wire detail is
  printed for diagnostics and replaced in speech by the generic caption.
  `ServerPickerScene`'s load-failure dialog no longer prefers
  `resp.error` — friendly caption in the dialog, detail on the print
  channel (the SafeErrorMessage type-guard law of M-ROKU-12 holds).
  `LoginScene`'s "Server error: {detail}" frame is NOT reverted: it is
  the d252b17-era honest taxonomy shipping a bounded reason inside a
  friendly, cataloged frame (CHECK24-staged `login_err_server`), a
  different shape from an unframed raw echo.
- **M-ROKU-29 (cured).** `ToastManager` spliced `[ERROR]`/`[WARNING]`
  severity tags into the SPOKEN toast text; severity already rides the
  channel (color/duration), so the tags are dropped and `showInfo` is
  lifted from 3000ms to the 4000ms legibility floor. The claimed
  ToastScene label clip (`width=1280`) was stale: the overlay was
  re-based onto the Dialog node by `7942e66` (M-ROKU-17) with no such
  markup.
- **M-ROKU-34 (cured).** Word-bearing player labels rode
  `SmallSystemFont` on a 10-foot TV: `sleepTimerLabel`,
  `syncStatusLabel`, `qualityStatusLabel`, `settingsStatusLabel`,
  `trackListStatusLabel`, `sleepTimerStatusLabel` and the Up-Next
  countdown now ride `MediumSystemFont` (countdown height 20→30).
  `timeLabel` keeps Small by the review's own digits-only carve-out.
  Partial stale: the five status labels already wrap since the
  M-ROKU-20 era; HomeScene's description band is canvas-budget-locked
  (grid ends 684 / canvas 720 — CHECK32) and Labels ellipsize at
  truncation by firmware default; SettingsScene's single-line status
  bar is the CHECK42 R6 adjudicated headline law (detail rides the
  540px `detailLabel`). All three adjudications disclosed, CHECK63 R4
  pins the font floor.
- **M-ROKU-57 (cured).** The README's internal-alias layer is gone:
  `server-A7`→server-advertised (or dropped), `F12a`/`F7a`/`F13`/`F9`/
  `F10`→plain-truth phrasings, `S280`→route gate, `server SP5`/
  `mobile E5 slice` dropped, and the `unscouted` typo fixed. The fake
  Installation "### 6. SyncPlay" step heading is demoted to its proper
  top-level section. CHECK63 R5 convicts any re-growth. The API-table
  blank-line fragmentation leg was stale-verified: the table is
  contiguous at tip (cured by the `9ff4a6d` docs-truth sweep).
- **M-ROKU-09 (honest-blocked).** The dead SyncPlayScene/
  SyncPlayManager pair and its render-thread `wait()` pattern still
  ship — deliberately. Delete-or-re-home is an OPEN owner decision
  recorded in the README "Room-scene retention" note and docs/i18n.md
  (the pair demoted to shipped truth by `fa67902`, M-ROKU-26); Check
  56 pins that dead-truth in both directions. Curing this item means
  exercising the pending ruling, which no fix lane owns; the block
  rationale and raws ride W-min89's report.

### Fixed — W-min88 minors cluster (3 cured, 1 stale-verified) — 2026-10-30

- **M-ROKU-45 (cured).** README's manifest bullet claimed
  `ui_resolutions: (hd, fhd, uhd)` — the manifest declares `hd` and Check
  38 pins the token set to exactly {hd} while the 1280×720 design plane is
  hardcoded (the review era's `hd,full` was itself since rotated: the
  legacy `full` alias stays retired). README now quotes the real value with
  the plane law and the alias note.
- **M-ROKU-46 (cured).** The -our/-or split inverted since the review:
  README carried `behaviour` x2 with zero `behavior` (the
  redirect-follow line had rotated away), and three PlayerScene comments
  carried the fourth, fifth and sixth British spellings. Swept to
  American `behavior` (Roku's own docs' spelling) in README x2 +
  PlayerScene x3; CHANGELOG occurrences are history and stay verbatim.
- **M-ROKU-56 (cured).** README's Required-prerequisites line "Roku
  Developer Account: For sideloading apps" contradicted the shipped
  release law — sideloading is developer mode + `make install`
  (docs/publishing.md: "does not require store certification"); the paid
  account belongs to store submission only. Line rewritten to the honest
  split, pointing at publishing.md's Prerequisites.
- **M-ROKU-43 (stale-verified, zero diff).** The claimed "port fiction" is
  current truth: 8096 IS the documented phlix-server HTTP default at tip
  (server `config/server.php:22` + server README `PHLIX_HTTP_PORT` `8096`
  (`server.port`) + install.sh `--http-port` default 8096). R4.10 deleted
  the client's hardcoded LOCALHOST fallback (AppContext now returns ""
  when unset — a different defect), not the port. README's example URL and
  ApiClient.brs's docblock example ride the documented Phlix port;
  changing them to a non-default would be the regression.

### Fixed — W-min87 minors cluster (6 cured, 2 stale-verified) — 2026-10-30

- **M-ROKU-06 (cured).** The session-expired overlay copy commands "sign in
  again" but OK just closed the player onto a browse whose calls all 401
  with the dead token. `PlayerScene` now discriminates the dialog
  (`m.errorIsAuth`, written by the three overlay subs together): OK on the
  auth failure walks the parent chain to the root scene and calls the same
  `OnLogout()` ceremony SettingsScene's Log Out button uses (six-key wipe,
  stack clear, LoginScene), failing soft to the old close if no `OnLogout`
  host exists. PlayerScene is appended to the LAUNCHING scene's children
  (depth varies), so the walk replaces SettingsScene's fixed two-hop.
- **M-ROKU-08 (cured at the live half).** navigation.md's PushScreen
  example fabricated `ShowLibrary` routing through the stack — the live
  `HomeScene.ShowLibrary` bare-appends. The example now quotes the real
  PhlixApp deep-link callsite, with a pointer to the (already honest)
  "Scenes opened from HomeScene are not on that stack" law. The
  Known-Limitations and four-button-comment sub-claims were cured earlier
  by the C03/C03-r2 docs pass (stale at landing, disclosed).
- **M-ROKU-51 (cured).** The 25 + 3 BrightScript-apostrophe "comment" lines
  smuggled into `PhlixApp.xml`/`DetailScene.xml` are now real XML comments
  (`<!-- -->`, bodies byte-kept) — visible to every XML-aware tool instead
  of riding as invisible text inside `<interface>`.
- **M-ROKU-52 (cured).** architecture-apitask.md's envelope example named a
  `"getLibrary"` op that never existed; now `"getLibraries"` (the shipped
  `ApiTask.brs:330` op).
- **M-ROKU-53 (cured-in-place, files kept).** BLOCKED_R0.1/R0.8 got dated
  2026-10-30 status banners (device queue still blocked; paths stay —
  README's CHECK60-self-pinned structure map and four device-verification.md
  pointers reference them; the "undated"/"not linked" halves of the ask are
  disproved), R0.1's wrong telnet 8080 → flagged as 8085 per
  device-verification.md's law, and R0.8's phantom
  `docs/first-boot-console.log` baseline → capture-a-fresh-log instruction,
  plus its "(11+ CHECKs)" count rotated to the measured 62 legs.
- **M-ROKU-54 (cured).** `LibraryScene.brs`'s sort-picker TODO named
  `roListDialog`, a native-UI dialog that cannot join a SceneGraph tree;
  it now names the shipped picker idioms (LabelList/RowList + ContentNode,
  or a dedicated roSGNode panel) without touching the cycle-on-press
  behavior.
- **M-ROKU-55 (cured).** CLAUDE.md still legislated the R7.5-deleted
  manager layer (`SessionManager`/`LibraryManager`/`TaskManager`, "scenes
  call managers") and listed `m.session`/`m.library` rebuilds at
  OnConnected and OnServerPicked. Rewritten to the live law: scenes
  dispatch through `ApiTask` ops, `AuthManager` wraps auth token state,
  `AppContext` owns connection state; the rebuild lists are `m.api`/`m.auth`.
- **M-ROKU-05 (stale-verified, zero diff).** The Home failure-path ask was
  already shipped by M-ROKU-21: `OnLibrariesResponse`'s else branch sets
  `m.librariesFailed` + `ShowHomeRailFailure()` (catalog copy + focusable
  Retry via the M16 boot-retry idiom); `OnMeResponse`'s degrade is the
  deliberate R4 fail-closed non-admin posture.

### Fixed — CHECK43's bare-"String" whole-line exemption tightens to the wire-bound gate shape (R-ROKU-04 rider) — 2026-10-30

- **The looseness.** R-ROKU-03's own note named this leftover: `"String"`
  sat in GUARDED as a bare literal, so ANY line carrying it for unrelated
  reasons — the non-wire `Type(req.base_url) = "String"` validation gates
  at components/ApiTask.brs:792/:794/:797 are the living shapes — exempted
  arms (a)-(d) on that line; and because the code mask kept the literal
  verbatim, `x.error <> "String"` (a wire member compared to string TEXT)
  never even reached arm (a)'s `<> ""` eyes. Zero exploitable sites today
  (measured at tip: of the 32 code-bearing lines carrying the literal, the
  three bare-token lines match no arm and the rest pair a roString/function
  guard — zero convictions under the strict token, so the tightening ships
  with the whole tree unchanged).
- **The cure.** `"String"` now counts as a guard token ONLY in the
  wire-bound gate shape — the line type-gating a wire member itself,
  `Type(x.error)/Type(x.message) =/<> "String"` (the single-sided analogue
  of the sanctioned roString idiom family). GUARDED gained the
  `WIRE_GATE_HEAD` alternative; the code mask renders an unrelated
  `"String"` as `""` like any other text, closing the invisibility hole in
  the same motion (arm (e)'s raw-line allowance follows the precise token
  automatically). The `"roString"` whole-line exemption — the accepted,
  named PlayerScene residual — is byte-unchanged law.
- **The teeth.** The portable Check43 leg plants both cover shapes
  (`Type(kind) = "String" and resp04cover.error <> ""`;
  `resp04hole.message <> "String"`) — both measured GREEN under the old
  coarse token at 349933e, both name-convicted under the new one — and a
  sanctioned-gate green leg plants ONLY the wire-bound `="String"` shapes
  (bare and compare-sharing) and asserts exit 0, so an over-tighten in
  either direction reddens CI. `make lint`, the route-manifest self-test,
  all 62 verify-runtime legs, and the full portable harness green.

### Fixed — CHECK43's guard exemption becomes guard-SPAN-masked: a second raw operand on a guard-call line no longer rides the token (R-ROKU-03 rider) — 2026-10-30

- **The looseness.** Review r3 named it: arms (a)-(d) skipped any line whose
  CODE carried a guard token, so `WireErrorPresent(x.error) and x.error <> ""`
  — the predicate guarded on the left, the raw compare ungarded on the right —
  slipped CHECK43 entirely. Per-operand exemptions were refused (they would
  convict the sanctioned `type(ev.message) = "roString"` idiom family), so
  the tradeoff had been accepted and carried forward for a cure that keeps
  the family whole.
- **The cure.** Arms (a)-(d) now run on a guard-SPAN-masked view: each
  `SafeErrorMessage`/`WireErrorPresent`/`WireErrorText` call is blanked with
  its balanced argument span (one nesting level), and only the "roString"/
  "String" type-gate literals keep a whole-line exemption. The mixed line
  convicts; a concat of an already-guarded value (`SafeErrorMessage(x.error,
  "") + "!"`) stays clean because the raw read sat inside the span. The
  sanctioned family is byte-unchanged law — PlayerScene:2072's mixed literal
  residual stays accepted and named. Mutation-proven red-then-green against
  the live checker (planted mixed line convicted only post-cure), and the
  hardened leg passes the whole tree with zero new convictions (58 files);
  `make lint` + the route-manifest self-test + all 62 verify-runtime legs
  green. Arm (e)'s raw-line choke-lift allowance untouched (r1-ratified).

### Fixed — §1a/row-39 attribution tightened: the channel-manifest page names 1.0/1.2/1.3; 1.1's authority is the vendored RSG_VERSIONS map (R-ROKU-02 rider) — 2026-10-30

- **The looseness.** M-ROKU-07 review m2: both truth surfaces attributed the
  full {1.0, 1.1, 1.2, 1.3} value space to the live channel-manifest page, but
  the page names 1.0/1.2/1.3 explicitly — 1.1's authority is brighterscript's
  vendored `RSG_VERSIONS` map (`dist/RokuConstants.js`: 1.1 `introducedAt`
  7.5.0, `removedAt` 14.5.0), verified byte-for-byte in the same review. The
  fact was correct; the provenance citation was loose.
- **The cure.** `docs/certification.md` §1a and `docs/static-checks.md` row 39
  now split the attribution exactly that way. Docs prose only: the CHECK39
  legs, their value-space set literal, and the manifest are untouched, so no
  gate's teeth moved.

### Fixed — CHECK39 R5 scans Eval() case-INsensitively, matching BrightScript's own identifier law (R-ROKU-01 rider) — 2026-10-30

- **The hole.** M-ROKU-07 review m1: the R5 leg searched `\bEval\s*\(` with a
  case-SENSITIVE regex while BrightScript identifiers are case-INsensitive — a
  future `eval(`/`EVAL(` call would have bypassed the leg while contradicting
  the declared `rsg_version>=1.2` law (Roku: "Eval() cannot be used with
  rsg_version=1.2"). No current violation existed (the case-insensitive census
  was already 0), so the leg's PASS narration was honest but its teeth were
  narrower than the language it guards.
- **The cure.** `re.IGNORECASE` on the R5 `re.search` (the Check 19 `code_view`
  line-comment masking is untouched), the leg's header comment and
  `docs/static-checks.md` row 39 R5 state the case-insensitivity law where the
  next reader sees it.
- **Proof.** Tip `1f37fd5`: `scripts/verify-runtime.sh` exit 0, 62 checks
  (no numbering moved — this is a within-leg forward fix). Mutation probe: a
  planted `source/` file carrying `eval(`, `EVAL ` and `eval ` call arms exited
  1 with exactly three CHECK39 R5 convictions (pre-cure the leg saw none);
  probe removed, tree clean. `make lint` exit 0 (pre-existing BS1013 baseline
  unchanged); `verify-route-manifest.mjs --self-test` green.

### Fixed — README test inventories + dependency truth cured to shipped-tree reality; Check 62 (M-ROKU-31) — 2026-10-30

- **The hole.** Review roku__writer M7: four README claims had detached from
  the tree. `### BrightScript Configuration` promised "these configurable
  constants (in source files)" followed by nothing — born empty in
  `367c48a`'s restructure (never lost content; nothing was ever written) with
  zero named configurable constants in `source/` (tunables are inline
  call-site literals like `http.SetTimeout(30000)`). The Unit Tests section
  echoed a three-file `make test-unit` listing while `tests/unit/` held
  **22** rooibos suites, and the Test Structure tree repeated the same
  fiction; neither shape matched the target's real behavior either (the
  Makefile prints `Tests require hardware — skipping` then the first 10
  `find` hits in filesystem order, exit 2). §3 "Install Dependencies — No
  external dependencies required" was device-true and dev-false: `make lint`
  runs `npx bsc`, and all three CI workflows (`lint.yml`, `test.yml`,
  `package.yml`) run `npm ci` against `package.json`'s
  brighterscript/@rokucommunity/bslint/rooibos-roku devDependencies. Rider:
  `docs/debugging.md`'s register pointer hardcoded "all 42 checks" — a count
  guaranteed to rot. (The queue's `cured-by: C33 9ff4a6d` stamp names a real
  commit but a different writer-lane cure; every M7 defect was re-verified
  LIVE at `e1d04b8f` and again at `f56793f8` before this lane touched it, and
  the earlier fix-lane claimed shas d16711d1/31b296d/c883230/927238b are all
  phantoms.)
- **The cure.** Docs truth, every section earns content or goes: the empty
  `### BrightScript Configuration` section is deleted (the review's sanctioned
  "(or delete the heading)" arm; no repo reference named it); the Unit Tests
  section now states the measured census — **22 rooibos unit suites** — and
  describes the target's real echo instead of a hand-typed fiction; the Test
  Structure block was regenerated from the shipped `tests/` tree (all 23
  `*.test.brs` by name, no invented per-file prose); §3 now splits the truth
  (device: nothing; toolchain: `npm ci` + the named devDependencies).
  `docs/debugging.md` says "every check leg" — a claim that cannot rot.
  `docs/static-checks.md` gains row 62.
- **The teeth.** `scripts/verify-runtime.sh` **Check 62** — README ↔ tree,
  both directions: R1 the Test Structure block names no phantom suites; R2 no
  shipped suite is unlisted; R3 the `**N rooibos unit suites**` literal equals
  the census; R4 the Install-Dependencies section keeps
  `npm ci`/devDependencies/brighterscript/rooibos-roku and the convicted
  phrase "No external dependencies required" stays extinct; R5 the born-empty
  constants lead-in stays deleted. Portable twin: one README plant re-grows
  the era block plus a phantom `SessionManager.test.brs`, the stale count, the
  dev-false sentence and the empty-section lead-in — CHECK62 R1/R2/R3/R4/R5
  fire naming each plant, CHECK52/56/58/60/61 stay green (gate independence),
  restore exits 0. Red-on-parent MEASURED at `f56793f8`: exactly 8 named
  CHECK62 convictions, all other legs PASS, exit 1. NUMBERING (disclosed,
  CHECK54/55 rebasing precedent): the stalled sibling lane composed this leg
  as 59 against raw tip `e1d04b8f`; Checks 59/60/61 LANDED (M-ROKU-33/32/37)
  before this takeover, so the collision probe at `f56793f8` renumbers the leg
  to 62. No unit suite — pure docs-vs-tree presence legs (CHECK50/52/56/57/58
  precedent). Salvage: the README cure texts and the leg were re-adopted from
  the stalled M-ROKU-31f lane's surviving WIP tree, re-verified hunk-by-hunk
  against `f56793f8` and renumbered; this commit carries that lane's work to
  landed state.

### Fixed — the docs' locale-family inventories enumerate the shipped directory; Check 61 (M-ROKU-37) — 2026-10-30

- **The hole.** No leg anywhere bound the docs' locale-family claims to the
  `locale/` directory. The review lane recorded readers taking the Overview
  headline "plus six shipped sibling catalogs" as a SIX-family claim while
  seven families ship (VERIFY-FIRST: 348 keys × 7 directories — parity
  itself has always been true and the writer review lists it verified-true),
  and the README Project Structure tree — which exhaustively enumerates
  every scene file — showed `locale/` with a SINGLE row,
  under-enumerating seven shipped families as one. CHECK21 derives folders
  from disk and never reads the docs; CHECK48 carries its own hardcoded
  seven-list. Claim-vs-directory drift was invisible to every gate.
- **The cure.** Docs + harness only. `docs/i18n.md` Overview: the total is
  now on the record — "Seven locale families ship: a single base locale
  (`en_US`) plus six shipped sibling catalogs …". The README one-row
  locale block was cured mid-lane by M-ROKU-32's Project-Structure
  regeneration (disclosed: that tree landed at `1e0c565` before this push;
  this lane's README cure is subsumed, and its enumeration is now pinned by
  both CHECK60 and CHECK61). CHECK61: R1 the Overview states the family total
  in words, the base-excluded sibling count, and enumerates every on-disk tag;
  R2 the i18n.md Directory-Structure tree enumerates every directory exactly
  once, no ghosts/dupes (survive-delete); R3 the README Project-Structure tree
  enumerates every directory exactly once; R4 every catalog's
  `_metadata.locale` names its own folder. Fail-loud R0: unreadable/empty
  `locale/`, a missing base, or a count outside the word-map exit red — no
  arm runs vacuously. docs/static-checks.md gains row 61. Numbering note per
  the collision law: the leg was cut as 60 against `c4b39af7`; M-ROKU-32
  claimed 60 at `1e0c565` mid-flight, so after an `ls-remote` re-read this
  lane took the next-free number, 61, before push.
- **Measured.** Red-at-base measured at the push parent
  `5d83dac`, and pre-rebase at `1e0c565` (new leg, untouched parent docs,
  identical both runs):
  exactly 1 named CHECK61 conviction — R1 on the bare-count headline —
  the other 60 legs green including CHECK60, exit 1. R2/R3 were directory-true
  at this base because the M-ROKU-32 regen enumerated the shipped families
  first; all four arms are proven non-vacuous by their plants (the README
  one-row era re-planted fires R3 ×6 — the CHECK56 R1/R3 asymmetry
  precedent). After the cure: `make lint` 0; `bash scripts/verify-runtime.sh`
  exit 0 across all 61 legs (server-migrations sibling staged — a venue
  fact, CHECK14 needs a sibling phlix-server, as in every prior lane);
  portable exit 0 with four new plant-and-restore legs (README one-row era
  → R3 ×6; bare-count headline → R1; stripped tree sibling →
  R2; mislabeled `_metadata.locale` → R4), each red with
  CHECK21/CHECK56/CHECK60 gate independence, restore → exit 0 green.
  Disclosed: the row-59 landing
  debt this entry originally reported was retired concurrently by
  `5d83dac` mid-rebase — the table now runs 59–61 complete; the i18n.md tree and the
  image-asset family claims were re-measured this lane and are already true;
  the review headline's "six families" defect class is fully covered by R1's
  total-in-words law.

### Docs — writer M9's ask list completes: retroactive quality-picker entry + Check 59's table row recovered (M-ROKU-33 follow-through) — 2026-10-30

- **The hole.** The `[latest]` cure landed its header, model block and
  Check 59 but collected only part of review roku__writer M9: the
  Manual-quality-selection feature still had no CHANGELOG entry, so
  README.md:22's "see the CHANGELOG" pointer stayed dead — the writer named
  that pointer as reader-harm — and Check 59 shipped without its
  `docs/static-checks.md` table row, the same landing debt the M-ROKU-28
  docs-truth lane exists to collect.
- **The cure.** Completion, not rotation: the quality picker (shipped
  `46c0d5b`, 2026-07-08, inside the R4.10 era) gets a disclosed retroactive
  entry at that era's tail, and `docs/static-checks.md` gains row 59
  describing the leg as shipped (R1 rolling header, R2 whitespace-collapsed
  model-block needles, R3 version-shaped headers standing on live
  `git tag -l` or package.json backing). The leg, the header and the model
  block are untouched. Writer M9's remaining asks verified already closed at
  tip: the a2216e0 copy-lane entry is recorded, and the release-shape fiction
  died with the twin-landed cure at `abd182a` — this lane raced it live
  (double dispatch on the same item; first push won; the loser's independent
  re-enumeration of the tag layer agreed claim-for-claim, and only the two
  residues above survived as delta).
- **Measured.** `make lint` exit 0; `bash scripts/verify-runtime.sh` exit 0
  over all 59 legs (CI layout: server sibling shallow-cloned for Check 14);
  CHECK59 red-on-base re-measured on `abd182a~1`'s committed CHANGELOG under
  the shipped leg — exactly 4 named convictions (R1 + R2×3), exit 1, all 61
  other PASS legs intact; the lane's own pre-landing leg-versus-base probe
  measured the same class independently (3 convictions — the R2 trio
  collapses to one section-home arm in that leg's shape);
  `bash tests/scripts/verify-runtime-portable.sh` exit 0 including its
  CHECK59 P1/P2 plants.

### Fixed — the CHANGELOG finally describes real releases: rolling-latest header + verified release model; phantom v1.0.0–v1.4.0 claim retracted (M-ROKU-33) — 2026-10-30

- **The hole.** Review roku__writer M33: the file carried exactly two `##`
  headers — `## [Unreleased]` and `## [R4.10] — 2026-08-05` — so no shipped
  release was ever listed: the 203 master pushes since the R4.10 cutoff had
  all been published through the rolling `latest` prerelease while the
  CHANGELOG filed them as unreleased. A prior fix lane for this item returned
  a fully fabricated cure (unreachable sha, unwritten report, five nonexistent
  tags, three 404-ing CI run IDs — findings F1–F5 in the r1 review); this lane
  is the fresh disk-grounded replacement and re-anchored every claim above on
  live origin reads before writing it.
- **The cure.** The section header renamed to the vehicle that exists
  (`## [latest]`), the verified release model stated above, and this entry —
  derived solely from `git ls-remote --tags origin`, `git log`, `package.json`
  and `.github/workflows/package.yml`. Every pre-existing entry kept verbatim
  beneath; `## [R4.10] — 2026-08-05` untouched. Cross-truth is literal: this
  file now states "exactly one tag (`latest`)" in docs/publishing.md's own
  words — Check 40 R4 pins the guide against the workflow, and Check 59 now
  pins this file: R1 keeps the `[latest]` header from decaying back into an
  "unreleased" fiction, R2 keeps the model block carrying the tag-layer truth,
  the publishing.md pointer and the live package.json version (rotate on any
  bump), R3 refuses any versioned release header the tag layer or the version
  field cannot back — the fabrication class this item's phantom r3 rode.
- **Measured.** `make lint` exit 0; `bash scripts/verify-runtime.sh` exit 0
  (all 59 legs, `PHLIX_SERVER_DIR` sibling supplied per venue precedent);
  `bash tests/scripts/verify-runtime-portable.sh` exit 0 — the base-structure
  plant (header reverted to `## [Unreleased]`) fires CHECK59 R1+R2 with
  CHECK40/CHECK54/CHECK57 gate independence, the phantom-ladder plant
  (`## [v9.9.9]`) fires R3 naming the unbacked token, and the restored tree
  returns exit 0 (falsifiability, house planted-red tradition).

### Fixed — publishing.md artifact + signing model cured to shipped truth; CHECK41 gains the R5 smoke-truth rider (M-ROKU-29) — 2026-10-30

- **The hole.** Review roku__writer M5: the store guide still described a
  signing chain the code cannot back. `sagas.xml` was listed as a
  package-validation checklist item — a file no Roku package contract
  contains (the archive is the root `manifest` plus `source/`,
  `components/`, `images/`, `locale/`, exactly the Makefile `zip -r` recipe
  and the layout `scripts/verify-package.sh` enforces). And the self-signed
  `.pkg` was billed five times as sideload-able — publishing.md's Overview
  row ("Sideload testing **only**"), its Step-2 parenthetical ("sideload
  testing only"), its Certificate Details bullet ("✅ Can be sideloaded for
  testing on your own devices"), the Makefile comment, and
  `scripts/package-signed.sh`'s own summary echo ("Sideload it for
  testing") — while Roku's dev-mode installer accepts the unsigned zip and
  nothing else (the Makefile `install` target POSTs `-F archive=@phlix.zip`;
  the script's own signer-failure branch already routed testers there,
  contradicting its summary inside one file). A developer minting the
  auto-generated dev cert to "sideload" got an artifact that installs
  nowhere, and a store-submission reader triaged failures against an
  imaginary file.
- **The cure.** Claims-to-shipped sweep of the whole chain: publishing.md's
  Overview row, Step-2 naming bullet and Certificate Details section now
  state the `phlix-X.X.X-dev-signed.pkg` as what it is — a signing-chain
  smoke test that neither uploads nor installs, with `make install` on the
  unsigned `phlix.zip` named as the only device route; the troubleshooting
  item was replaced by the real archive contract with `verify-package.sh`
  as its enforcer. The Makefile comment, the script summary (keeping the
  Check-41-pinned "NOT accepted by the Roku Channel Store" banner verbatim)
  and README's store-step parenthetical rotate to the same truth.
  CHECK41 — the signing-claim gate whose M-ROKU-10 pass named the artifact
  honestly but left this claim standing — gains an R5 rider: the four
  fiction needles (whitespace-joined, so line-wrapped spellings convict)
  are banned across script/Makefile/doc/README; the smoke framing and the
  `make install` route must SURVIVE deletion in doc and script; the
  package-validation section is pinned token-by-token to the Makefile's
  actual `zip -r` recipe line, and any `sagas` resurrection convicts by
  name. Portable harness RED41 family extended: script echo + publishing.md
  sagas/sideload lines + README wrapped-claim plants each fire CHECK41 R5
  naming their file (CHECK18/CHECK40 gate independence), restore → exit 0.
  `docs/static-checks.md` row 41 rotated with the legs + plant record.
- **Measured.** 7 files +157/−17 before this CHANGELOG entry; verify-runtime
  FULL exit 0; portable harness green incl. the new R5 plant legs; make lint
  exit 0; no new Check number claimed (rider inside the existing family —
  CHECK56-r2 precedent), so the 55–58 numbering race with sibling lanes
  cannot touch this cure.

### Fixed — README Project Structure regenerated from the shipped tree + CHECK 60 self-pins the map (M-ROKU-32) — 2026-10-30

- **The hole.** The block a newcomer navigates the codebase by shipped four
  phantom landmarks and missed a cohort of real ones. `source/lib/` listed
  `SessionManager.brs`, `LibraryManager.brs` and `TaskManager.brs` — all three
  deleted in R7.5 (the removal note lives in `components/PhlixApp.xml`) — and a
  `source/data/Theme.brs` under directories that never existed here. Conversely
  `AppContext.brs` — the hub/connection-state core — was absent from the map,
  and so were the entire music/photos/favorites/search/settings/recommendations/
  ApiTask/DiscoveryTask component cohorts (22 `.brs` files), six of the seven
  locale catalogs, three of the six `scripts/` tools, and `docs/`, `tools/`,
  the npm/bsc config quartet, `LICENSE` and `CHANGELOG.md` at the root. Review
  roku__writer M8; the item survived the C33 9ff4a6d README pass, which cured
  endpoint fictions in other sections and left this block untouched.
- **The cure.** The fenced block regenerated from the live tree at `c4b39af`:
  every `.brs` under `source/` + `components/` listed with a truthful one-line
  role sampled from the file's own docblock (the SyncPlayManager/SyncPlayScene
  DEAD PATH rows preserved byte-ident — Check 56 greps them), full locale/scripts
  lists, and a complete root roster.
- **The pin.** CHECK 60 (scripts/verify-runtime.sh) makes the map self-pinning:
  the set of `*.brs` names inside the block must equal, bidirectionally, the
  basenames on disk under `source/` + `components/` — R1 convicts phantoms,
  R2 convicts misses, a vanished/unbalanced block convicts alone. Basename
  equality is deliberate (a tree, not a manifest; the legit `SkipButton.brs`
  double-residence passes both sides). RED at base measured at `c4b39af`:
  exactly 27 convictions — 4 phantoms (R1) + 23 misses (R2, the 22-file
  component cohort above plus `AppContext.brs`); GREEN at cure: 57 names
  both sides.
  Portable staging completed for the walk (AuthManager + the two player files
  join the stage list); the plant/restore leg re-grows one phantom + drops one
  landmark, convicts both arms by name, holds CHECK 56/58 green (gate
  independence), and returns exit 0 on restore.
- **Recorded, not fixed here.** `tests/unit/Theme.test.brs` calls `Theme()` —
  a symbol defined nowhere in `source/`/`components/` (the review's parenthetical
  "exercises `GetTheme` in Utilities" is itself imprecise; `GetTheme` exists
  nowhere either). An orphan test for a vanished file: a separate defect class,
  filed as a follow-up candidate.
### Fixed — device-verification.md cured to shipped truth: artifact path, dev-mode menu, console port, superseded art audit (M-ROKU-30) — 2026-10-30

- **The hole.** Review roku__writer M6: the repo's only zero-to-console procedure
  shipped lies. Step 1 sent the tester to "Settings → System → About → Developer
  Options" — an Android menu that does not exist on Roku; step 2 promised
  `out/phlix-roku-client.zip (or similar path)` while the Makefile's `PKG_NAME =
  phlix` writes `phlix.zip` in the repo root; step 9 told them to save to
  `docs/first-boot-console.log`, a file that has never existed in the tree. The
  whole-doc claim sweep found the same class deeper: step 4's telnet console port
  8080 (Roku's debug console is 8085), §5.1 presenting the R0.2-cured `&hEC`
  Storage misuse as a live defect, §5.2's "~13 parent scenes are not wired" caveat
  pointing at a "Known Limitation note in CHANGELOG.md" that does not exist and
  describing the bubble-up contract C03 cured 2026-10-28/29, a fabricated `&h06`
  error code on the §5.3 status row, R1.6 naming `Storage.invalidateAll()`/
  `Storage.flush()` where the code runs `ResetCachedStorage(false)`/
  `ResetCachedStorage(true)` + registry flush, the R6.2 audit table declaring
  `icon-focus-sd.png` Missing and all art 1-bit placeholders when six
  spec-dimension 8-bit RGB assets landed at `47cfdb6`→`326eb0d` (splash_fhd IS
  manifest:12; placeholder.png is a LIVE runtime poster fallback, not "discard"),
  and the R6.6 status row claiming documentation-in-this-file for a section that
  never existed here. README §1's dev-mode sequence said "Home (5 times)" — Home×5
  is the Dump-Core prefix; the Developer Settings sequence is Home×3 (official Roku
  docs), matching the other six presses already in the list.
- **The cure.** Docs-only. `docs/device-verification.md`: key-sequence step, real
  `phlix.zip`-at-repo-root artifact (with the `zip -j` root-manifest +
  verify-package.sh self-check noted), port 8085, step 9 re-pointed to the
  verification ticket (vendoring a real log is impossible while the device is
  BLOCKED — `docs/BLOCKED_R0.1.md`), §5.1 tagged (FIXED R0.2) in §5.2's era
  pattern with CHECK 1 named as the pin, §5.2 caveat re-anchored to
  `docs/navigation.md` Back/Close contract + CHECK27, §5.3 given its implemented
  exitChannel/CHECK31 status with the device arm honestly NOT REACHED, R1.6
  mechanism names corrected to the shipped `ResetCachedStorage` paths, R6.2
  replaced by a measured table (sizes + IHDR dimensions taken this lane: 51,879
  B/290×218 … 1,441,342 B/1,920×1,080) with the generated-not-commissioned
  brand-review risk disclosed, and the checklist boxes ticked only where a gate
  run this lane proves them (device box left unchecked). `README.md`: Home (3 times).
- **Measured.** `make lint` exit 0; `make validate-manifest` exit 0;
  `bash scripts/verify-runtime.sh` with `PHLIX_SERVER_DIR=/home/sites/phlix/phlix-server`
  exit 0 (all 58 legs; first sandbox run's single red was this leg's server-dir
  guard, a venue fact not a defect); `tests/scripts/verify-runtime-portable.sh`
  exit 0. No new CHECK: verify-runtime greps no device-verification.md string
  (old or new), and no existing leg's needle set fits a doc-path pin. Locale
  catalog untouched — CHECK21/22 verified by the full runs anyway. Residuals
  reported, out of this lane's scope: the same 8080 console-port error stands in
  README.md:372/:769, docs/debugging.md:97/:100, docs/BLOCKED_R0.1.md:8, and
  docs/BLOCKED_R0.8.md:9 still names the phantom `docs/first-boot-console.log`
  diff baseline.

- **The hole.** Review roku__gameux M21 r2's sole MINOR-1 survivor, live at
  tip: `OnRetryPressed` writes the transient `common_loading` copy into the
  home description strip while the failed rails re-load, but
  `HideHomeRailFailureIfHealthy` restored the default chrome only when the
  strip still showed the `home_rail_failed` copy. After a SUCCESSFUL retry both
  flags clear, the guard's equality fails, and a healthy app kept reading
  "Loading…" until an item focus happened to self-heal the caption. The r1 lane
  struck the dispatched-sha claim as phantom and r2 proved the 4-state cure
  landed at `14465fe` — this lane cures exactly the residual, nothing else.
- **The cure.** `components/HomeScene.brs`: the guard now snapshots the strip
  and restores from EITHER transient copy it owns — failure OR retry-stranded
  loading — behind the unchanged healthy-gate early return (Check 32
  partial-recovery law intact: one rail still failed, the other's copy
  stands). The recognition is safe because `OnRetryPressed` is the SOLE writer
  of `common_loading` onto the description strip: boot loading rides the
  separate `loadingLabel` and `ApplyXmlChrome` defaults the strip to
  `home_select_library`; item captions are a different copy class, so neither
  a live load nor a mid-flight focus can be stripped.
- **New teeth.** `scripts/verify-runtime.sh` **Check 58** — the lane claimed
  Check 57 (next-free at `ff298d9e`, measured) but the sibling co-watch lane
  landed its own Check 57 at `2157264` mid-flight, so this leg renumbered to
  58 on the new tip per the collision law: R1 pins the healthy-gate return,
  the strip snapshot, the two-copy recognition guard and the restore write as
  four exact needles; R2 pins the sole-writer fact with a masked `components/`
  + `source/` `.brs` census requiring the transient copy to appear exactly once
  at `OnRetryPressed` — a second writer convicts ON PURPOSE because it would
  make R1's recognition unsafe to keep. CHECK52 (the M21 failure-topology leg)
  is deliberately guard-agnostic and needed no rotation — the recovery half is
  now owned here. `docs/static-checks.md` gains row 58.
- **Measured.** Red-on-base at `2157264` (this leg, UNFIXED tip `HomeScene.brs`):
  exit 1 with exactly 2 named CHECK58 R1 convictions (the snapshot line, the
  extended guard) and zero other violations across the 58-leg battery — R2 was
  already code-true at base, the defect class was precisely the guard (the
  CHECK56 honest-scope asymmetry precedent). Green after the cure: full battery
  exit 0, 58 checks. Portable twin (`tests/scripts/verify-runtime-portable.sh`,
  the CI harness) exit 0 including the CHECK58 plant legs: P1 reverting the
  guard arm and P2 re-growing a second description-strip `common_loading`
  writer each convicted by name with CHECK52/CHECK56 gate independence (same
  M21 family, disjoint arms; the sibling CHECK57 scratch tree under
  `$TEST_ROOT/red57` stays disjoint from `$TEST_ROOT/red58`), restores returned
  exit 0. `make lint` (bsc) exit 0 — 23 pre-existing BS1013 test-file warnings,
  parent-identical measured both sides at the new base, zero from this change.
  No unit suite — the chrome state machine needs device focus events (rooibos
  is ROKU_HOST-gated); statement/presence legs per the CHECK50/52/53 precedent.
- **Untouched law.** No new locale keys (all three copies pre-exist across the
  7 catalogs) — the 348-key ×7 parity, CHECK25/48 and the version pin all stand
  unrotated; the co-watch one-name values the sibling CHECK57 guards are not
  touched by this cure.

### Fixed — the co-watch feature speaks with one name: Check 57 (M-ROKU-25)

- **The drift (review roku__writer M1).** Five names for one feature, three
  user-visible: the overlay said **Watch Together**, the status lines said
  **groups**, the created group defaulted to `"<device>'s Room"`, the live
  auth error said **watch parties**, and the local errors spoke of a **watch
  room**, **watch session** and a **sync server** with **SyncPlay** spelling
  surviving in two banner/fallback labels. A member hitting "Sign in before
  using watch parties." could not know the feature was the one labeled Watch
  Together, and support copy could not be searched.
- **The cure (law: concept = group, feature = Watch Together).** Thirteen
  `en_US` catalog values swept (the whole `sync server` family -> "the server"
  per the review's own "server (direct)" rubric; `watch session` -> Watch
  Together; `watch parties`/`watch room` -> the block's verbatim replacements;
  `SyncPlay error`/`SyncPlay unavailable` -> `Watch Together error`/`Watch
  Together unavailable`), the created-group default renamed to
  `"<device>'s Group"` at its one producer site, and the README step +
  docs/i18n.md section line de-drifted ("Create Group … to start a new group";
  "Watch-party room UI" is gone from both docs).
- **Check 57.** R1 convicts any convicted name inside the co-watch key scope
  (all `errors.*`, `syncplay.*` outside the pinned carve-out, `player.party_*`
  /`player.sync_*`/`create_group`/`leave`); R2 pins the new default and holds
  `"'s Room"` extinct across `components/` + `source/`; R3 FREEZES the
  room/party key-name census at exactly the six dead-scene `syncplay.*_room`
  carve-out keys + 13 wire/banner identifier mirrors (CON-07: keys are code
  identifiers riding the Check 23 wire mirror — values cured, names never);
  R4 keeps "watch party" out of README + docs/i18n.md. The portable twin
  plants all four arms (the R3 plant grows `syncplay.create_room2` in all
  seven catalogs so Check 21 cannot absorb it) with CHECK20/21/25/51 gate
  independence.
- **Disclosed.** The review's own `local_connect_failed` example carried the
  word "session" while its law killed "session" — the law governs and the
  rubric's "server (direct)" shapes the family. The six `syncplay.*_room`
  keys AND values stay for the dead `SyncPlayScene` (owner-gated
  wire-vs-retire; R3 pins that exact set so the carve-out cannot silently
  grow). Non-en_US catalogs keep their era translations (key parity
  untouched — sibling i18n lane's domain). `docs/i18n.md` joined the portable
  twin's stage list (Check 57 R4 reads it; staging-gap family). Catalog
  `_metadata.version` holds at 1.10.0 — no keys added or removed (dc362df
  precedent: value-only copy cures do not bump).



### Fixed — CHECK56 gains the positive-presence needles its own contract claims; the i18n `errors` row gets its dead marker (M-ROKU-26 r2) — 2026-10-30

- **The hole.** Review M-ROKU-26 r1 (verdict REWORK, MAJOR-1): CHECK56's
  row-56 contract and the leg's R2 comment advertised the `docs/i18n.md`
  syncplay consumer row as survive-delete, but the implementation was a
  conditional shape only — it fired when a row that *contains*
  `components/SyncPlayScene.brs` lacked the annotation, and deleting the row
  outright or rewriting it live-tense without the prefix both measured exit 0
  at `fa67902` (r1 plants V1/V2). The gate described teeth it did not have, and
  the exact surface the review convicted could re-claim live-room framing
  silently. MINOR-1: one line apart, `docs/i18n.md:71`'s `errors` row presented
  `SyncPlayScene.brs` as a live law-driven errors consumer with no dead marker
  (the conditional arm never saw it — it required the `components/` prefix).
- **The cure.** R2's i18n surface is now two arms: POSITIVE survive-delete
  presence (the `| \`syncplay\`` consumer row must exist AND carry
  `**not instantiated**` — deletion convicts the row-vanished arm, a live-tense
  rewrite convicts the lost-annotation requirement), and a consumer-table
  dead-marker law (every table row naming `SyncPlayScene.brs`, bare or
  prefixed, must carry a dead marker). MINOR-1 is cured BOTH-SIDES with the
  choice justified: the `errors` row is annotated honestly in the same commit
  ("the latter **not instantiated** — its error family is shipped copy that can
  never fire live; the live law-driven producer is `SyncPlayTask.brs`") AND
  pinned — the marker law convicts the exact :71 shape if the annotation ever
  decays.
- **MINOR-2 (math corrected forward).** The r1 review measured the `fa67902`
  landing at 11 files +360/−5 — not the entry's claimed "+356 (356 including
  this entry)" (the entry grew four lines after counting) — and 23 pre-existing
  BS1013 warnings, not 22 (the parent-identical half of that claim holds).
  History stands verbatim per house law; these measurements supersede.
- **Measured gates** (fresh clone at tip `f39ce22`): the rotated leg is
  red-on-parent at `f39ce22` with EXACTLY 1 named CHECK56 conviction — the
  r1-named `errors`-row survivor (the positive `syncplay`-row arm is green at
  that parent because the annotation ships there — precisely the vacuous-pass
  asymmetry r1 MAJOR-1 convicted); the portable harness's new i18n
  plant-and-restore trio (V1 delete-row, V2 live-tense rewrite, E strip the
  `errors` marker) each redden CHECK56 naming `docs/i18n.md` with CHECK46/
  CHECK54 gate independence and each restore returns exit 0; full
  `scripts/verify-runtime.sh` exit 0 (all 56 legs, `PHLIX_SERVER_DIR` bound);
  portable harness exit 0; `make lint` exit 0 (23 BS1013, parent-identical).
  Docs+gate only — `docs/i18n.md`, the CHECK56 leg, its ledger row, and the
  portable plant family; no behavior, locale, or wire surface touched.
  [review roku__crossfe M26r2]

### Docs — the i18n docs' numbers meet the shipped tooling: seven checks, seven restored rows, two corrected counts (M-ROKU-28) — 2026-10-30

- **The holes.** Review `roku__writer` M4: `docs/i18n.md:220` said
  "`scripts/verify-runtime.sh` runs all three checks as part of
  `make verify-runtime`" while the same document enumerates SEVEN i18n checks
  directly beneath it (Checks 19-25) — the sentence froze at three in the
  8657ba6b era when three were all that existed. The queue's
  `cured-by: C21 c6c9009; C33 9ff4a6d` annotations never touched the line.
  The mandated whole-file recount of every numeric claim in `docs/i18n.md` +
  `docs/static-checks.md` surfaced three more: the ledger bullet claiming the
  catalog "grew from 140 to 273 keys per locale (v1.3.0 → v1.4.0)" — measured
  274 at `ee70fad` under the loader's flatten rule (a 2026-09-25 review had
  already convicted the 273 figure; the doc bullet never absorbed it, and its
  own next bullet starts at 274); the `docs/static-checks.md` table skipping
  rows 32-38 ENTIRELY — seven live checks (M-ROKU-02/03/04/04-closeout/04-r2/
  05/06 eras) shipped as script legs with no table row, a gap the file itself
  admitted in a "landing debt ... Recorded for closeout collection" comment;
  and the Check 14 section citing "lines 853-855" — the ENUM comment moved to
  `Utilities.brs:1301-1303` long ago.
- **The cures.** :220 now states the seven checks (19-25) and points at
  `docs/static-checks.md` for the full table — with NO total-check count
  embedded, because that number moves with every landing lane: the sentence's
  own failure mode. 273 → 274. Rows 32-38 are restored from each check's
  in-script docblock and R-rule enumeration (32:R1-R5, 33:R1-R6, 34:R1-R5,
  35:R1-R5, 36:R1-R6, 37:R1-R4, 38:R1-R3), the debt comment replaced by a
  collection note, the table complete 1-56 with no duplicate or gap; and the
  Check 14 coordinate re-anchors to what the checker actually greps — the
  `' The full ENUM is:` banner above `PlayableTypes()`, two member lines,
  13 members — a claim re-verified on both sides (the checker's own scoped
  regex over server migrations still elects `034_media_items_type_audiobook.sql`
  with exactly 13).
- **The census (zero survivors).** Every checks/legs/locales/keys claim in both
  files was measured against shipped tooling. Era key-counts via each version's
  bump commit with the loader flatten rule: 140@`d048bfc`, 274@`ee70fad`,
  276@`4761741`, 277@`fd90120`, 278@`a2216e0`, 302@`d252b17`, 310@`dc4d6b3`,
  319@`ab050d5`, 345@`a5dad23`, 348@`14465fe` (= HEAD, and HEAD's
  `_metadata.version` 1.10.0); "all 16 token-bearing values" verified 16 at
  `e010a4e` (the set is 32 today — already disclosed by row 51's own text;
  history verbatim); the wire census 19 = 9 bare SCREAMING + 7 dotted +
  3 pre-flip-only with the reserved set empty, counted live in `Utilities.brs`;
  CHECK51's `PLAYER_KEYS` pin = 29; 13 `SetSyncStatus` call sites at `ab050d5`
  (15 greps minus 2 definition lines); `RatingLabel()` ships exactly 7 labels;
  Check 19's scope list is exactly the three named files; seven locale dirs;
  every portable-harness red-leg and green-set the docs cite (red-20/21/22/
  22b/23/24/25/19/26, the reserved-removal leg, `seq 11 26`, the aggregation
  leg) exists as claimed; era-phrasings ("hardcoded 8 paths", "All 31 checks",
  "checks 11-19 had never executed in CI") re-measured true against their cure
  commits' scripts. No code, catalog, or check leg touched.

### Fixed — the dead SyncPlay room pair is demoted to shipped truth everywhere: Check 56 (M-ROKU-26)

- **Verify-first verdict: NOT stale.** The queue marked the item
  `cured-by: C33 9ff4a6d`; that commit IS an ancestor of `dc362df87`, but its
  README diff touched zero SyncPlayScene/SyncPlayManager lines — it cured other
  endpoint fictions. The i18n.md consumer-table half was cured separately
  `@ab050d5`. Re-proven dead at tip: the room scene has zero instantiation
  sites repo-wide; `SyncPlayManager`'s sole caller is the never-instantiated
  `components/SyncPlayScene.brs:54`; the live watch flow is `PlayerScene.brs:1800`
  driving `SyncPlayTask` directly. The residual liveness claims stood in the
  README tree, CHECK 23's prose, `docs/api-envelope.md`, the `Utilities.brs`
  local-family docblock, and `SyncPlayScene.xml`'s own header ("Launched from
  PlayerScene via SyncPlay button" — a false in-file claim, corrected).
- **Cure = docs-truth demotion, not wiring.** Wiring the room is neither small
  nor spec-matching (the shipped architecture's law is "no separate SyncPlay
  scene") and the wire-vs-retire disposition is an open owner decision
  (`docs/i18n.md` historical record). The pair now carries per-file
  `DEAD PATH — not wired into the shipped UI` banners, README §6 gained the
  "Room-scene retention (dead path)" note, both tree rows their markers, and
  the CHECK 23 / api-envelope / Utilities prose their annotations.
- **Check 56 pins both directions.** R1 instantiation census (wiring the room
  reddens CI on purpose and forces the doc set to be re-cut in the same
  commit); R2 truth-presence across the nine claim surfaces (a cure only needs
  to survive being DELETED — CHECK 54's survival idiom); R3 provenance-kept:
  all seven catalogs keep listing `components/SyncPlayScene.brs` in
  `_metadata.source_files` — deliberately DEVIATING from the review's suggested
  deletion, because the field means "source files that OWN the strings", the
  scene ships and physically owns the syncplay/`*_room` keys (Check 24 stages
  it as a consumer); retiring the files must rotate R3 in the same commit.
- **Measured gates** (fresh clone at `dc362df87`): red-on-parent for the new
  leg — exactly 10 named CHECK56 convictions, ALL R2 truth-presence (R1/R3
  were already code-true: the defect class was precisely documentation). The
  leg shipped locally as Check 55, then renumbered to 56 when the concurrent
  M-ROKU-23 lane (hub relay origin law) landed `d671151` first and took 55;
  red-on-parent re-verified on both subsequent parents (`d671151`, then the
  final push parent `09761fac` after M-ROKU-27's docs entry) — identical 10
  convictions each time. Full
  `scripts/verify-runtime.sh` exit 0 with `PHLIX_SERVER_DIR` bound; portable
  harness exit 0 including the new Check-56 CI-layout asserts and its
  plant-and-restore leg (planted `CreateObject("roSGNode", "SyncPlayScene")` +
  stripped README marker -> R1+R2 convictions with CHECK46/CHECK54 gate
  independence; restore -> exit 0); `make lint` exit 0 (22 pre-existing BS1013
  test-file warnings, parent-identical). No locale, behavior, or wire surface
  touched — 11 files, +356/−5 (356 including this entry), all prose/gate. [review roku__writer M2]
### Docs — i18n.md Future Work no longer advertises the closed `{token}` concat defect (M-ROKU-27) — 2026-10-29

- **The hole.** Review `roku__writer` M3. `docs/i18n.md:499` (Future Work)
  still listed the `{token}` raw-concat defect as live — "Two pre-existing
  call sites concatenate ... rendering literal `{email}` / `{url}` / `{count}`
  text; flagged for a follow-up lane" — directly contradicting line 480 of
  the same document, which records the 2026-09 token-defect lane closing the
  class. The code settled it: all three named sites substitute via
  `TranslateWithParams` (`SettingsScene.brs:120`/`:146`,
  `DetailScene.brs:299`, shipped in e010a4e, guarded by Check 24). Reader
  harm: a follow-up lane "fixes" a dead bug or files a false report.
- **The cure.** The bullet is struck and dated closed in the file's own
  closed-item convention (mirroring the adjacent XML-chrome bullet), with the
  landing commit and the Check 24 law named. Historical Notes :480 already
  carries the full shipped truth; no code, catalog, or check touched.

### Fixed — the hub relay stops downgrading a minted token to cleartext behind https origins (M-ROKU-23) — 2026-10-29

- **The defect (review roku__secnet M2).** `StartHubCommandConsumer` stripped
  the persisted hub URL's scheme and dialled the FIXED plaintext relay
  listener `ws://<hub>:8804` regardless of the origin — `components/PhlixApp
  .brs` carried the stale parse comment "(http://host[:port])" as its only
  nod at the shape — and `components/HubCommandTask.brs` then minted a relay
  token over the hub's (possibly TLS) REST lane and carried it,
  `Authorization: Bearer` on a raw `roStreamSocket` handshake, across
  cleartext. Behind an `https://` hub that means a passive path sniffer can
  capture a live push-into-the-session credential and inject "Alexa, play X"
  commands behind the very TLS identity the hub advertises — the scheme
  mismatch itself is the exploitable class (same doctrine M-ROKU-14/4240ad2
  used for the :8097 account-JWT leg: refuse, never silently downgrade).
- **The cure.** New pure predicate `HubRelayCleartextRefusedForOrigin`
  (`source/lib/Utilities.brs`, global string functions ONLY — see the
  device-safety note below) refuses the cleartext dial for `https://` origins;
  it is enforced at the scene choke BEFORE `auth_token` is read and again at
  the task (`RunConsumer`) before any mint or connect — defense in depth.
  `http://`/legacy scheme-less hubs keep byte-identical behavior (their REST
  lane is already cleartext; no NEW exposure class is created or removed
  there). CHECK55 pins the predicate shape, the refuse-before-credential and
  refuse-before-mint orders, the survival of the plaintext arm, the docs law,
  and (R3) that NO `roSecureSocket` instantiation ships from this lane. R3
  also pins `components/HubCommandTask.xml`'s Utilities.brs script-include:
  a component scope does NOT auto-include pkg:/source, and the first honest
  full `make lint` caught exactly that — the task-side choke had been written
  against a symbol outside its scope (BS1140); the twin closure is
  `SyncPlayTask.xml` (Storage + Utilities + SyncPlayProtocol + own), now
  mirrored here with its stale "needs only SyncPlayProtocol" comment
  rewritten to truth.
- **The wss arm: DEFERRED with disclosure, not impossible.** The managed
  hub's TLS front-end already routes `GET /syncplay/` to the relay worker
  (phlix-hub `docs/websockets.md`), so `wss://<hub-domain>/syncplay/{id}`
  exists server-side today. The client leg needs on-device verification of
  `roSecureSocket`'s method surface, which this venue could not reach (the
  docs restructure 404s); shipping blind platform calls is exactly the
  convicted class (below), so the refusal law lands now and the wss migration
  rides the same disclosed-deferred posture edbbd8a ratified for :8097. Cost
  stated honestly: "Alexa, play X" stays CLOSED on https hubs until the wss
  arm lands.
- **Device-safety law learned mid-lane (rider findings, REPORTED).** The
  predicate family avoids member `.Mid`/`.Lower` because this lane PROVED both
  are landmines: `ifStringOps` indices are 0-based while the globals are
  1-based, and `.Lower()` is not a Roku string member at all (roString
  implements ifString + ifStringOps + ifToStr only). At this tip 14 `.Lower()`
  member calls ship in `source/` (main.brs x2, Utilities.brs x12) — each is a
  device runtime error, which renders the M-ROKU-15 custody family
  (`HostOfUrl`/`OriginOfUrl`/`NormalizeServerUrl` et al.) device-dead, on top
  of two off-by-one member-`.Mid` scheme/port strips in `HostOfUrl`/
  `OriginOfUrl`; `tests/unit/RedirectCustody.test.brs` encodes expectations
  that cannot pass as written and never runs in CI (hardware skip). CHECK55
  R1 pins the globals-only law on THIS family's new code; the estate-wide
  sweep is queued for its own item (see `.reviews/fixlog/M-ROKU-23__fix.md`
  Observations).
- **No new user-facing strings** — catalogs untouched (the refusal is silent,
  the posture state is the already-existing `closed`); locale 7-family
  key-set parity re-verified read-only in the fixlog.
- **Gates.** `make lint` (bsc) zero new; `scripts/verify-runtime.sh` FULL
  green with the new Check 55 leg (this lane numbered it 54 mid-work; the
  M-ROKU-22 residual `0f0d42b` took Check 54 from origin under the lane and the
  rebase re-numbered this leg to 55 — CHECK50-line precedent, disclosed); portable harness gains a CHECK55
  plant-and-restore leg (scene choke, task choke, predicate rename, README
  prose — each named red, CHECK53 gate independence, restore -> 0); device
  suite `tests/unit/HubRelayOriginLaw.test.brs` (truth table, also executed
  under the brs interpreter in-lane for real-behavior proof — output in the
  fixlog).
### Fixed — the SyncPlay dial posture gets its composition census and survival pins: Check 54 (M-ROKU-22 residual)

- **What landed where (disclosed double-lane).** Review roku__secnet M1
  ("plaintext-by-assertion") was filed once and shipped by two lanes. The
  prose cure — scoped headings, the `roSecureSocket` deferred-arm truth, the
  CHECK46 R2 misclaim conviction arms — is `edbbd8a`. That commit message
  claimed "dead worklog pointers re-anchored" and missed one:
  `source/lib/SyncPlayProtocol.brs` still cited the vanished `worklog §1f`;
  this lane deletes it.
- **What prose cannot pin (Check 54).** The M1 exfil scenario needs the
  bearer JWT to reach a host the user never authenticated against. That
  remains impossible only while the dial COMPOSES honestly: the SyncPlayTask
  node has exactly one instantiation site, that site orders builder ->
  invalid guard -> refusal probe -> node, `BuildSyncPlayWsParts` refuses
  `https://` origins in-code and FORCES port 8097 from the stored
  `GetServerUrl` authority, and hub mode is choked at the panel entry (no
  relay path exists, so a hub token has nowhere to ride). CHECK46/48/53 each
  guard their own choke but none censuses the composition: a second,
  ungated dial site would pass all three. R2 adds truth-PRESENCE arms — the
  scoped `ws://`-only heading, the README/TASK `roSecureSocket` deferred-arm
  sentences, the SPEC §5 citation — because a conviction arm only catches a
  lie coming back, not a truth being silently deleted. R3 convicts the dead
  `worklog §` / "See the worklog" pointer family in the M22 file set
  (LiveTV/LivePlayer's bare pointers are a different feature's prose debt,
  disclosed as out of scope). The plant-and-restore leg re-plants the hub
  choke, truncates the heading and re-adds the `§1f` pointer: exactly the
  CHECK54 R1/R2/R3 legs fire and CHECK46/48/53 stay green (gate
  independence).

### Fixed — the SyncPlay transport stops asserting a false platform limit: wss is DEFERRED, not impossible (M-ROKU-22) — 2026-10-29

- **The defect (review roku__secnet M1, the "plaintext-by-assertion" item).**
  The mechanical halves of this finding were cured earlier in the campaign:
  M-ROKU-14 (4240ad2 + 93b1ab8) refuses the plaintext `:8097` dial on `https://`
  origins BEFORE the account JWT is read and fail-closed-verifies the
  RFC6455 `Sec-WebSocket-Accept` proof (CHECK46), M-ROKU-15 (7541a10) consent-
  gates off-LAN `http://` custody (CHECK48), M-ROKU-24 (dda19ea) wipes old-host
  tokens at the persist choke (CHECK53). The finding's named assertion half
  survived them: shipped prose still claimed the platform could not do TLS at
  all — README "…`wss://` is impossible", README "since Roku can't do TLS", and
  the SyncPlayTask header's "Roku platform: … (never wss://)". That is false on
  this repo's own evidence: every https REST origin here does TLS
  (`SetCertificatesFile("common:/certs/ca-bundle.crt")` ×4 in `ApiClient.brs`),
  and `roSecureSocket` is the platform's TLS client socket (named in the
  Check-46 scope note as the deferred migration). A false impossibility frames
  the refusal law as the only conceivable posture and shuts down the mitigation
  — the exact harm the review charged. The header also carried DEAD pointers
  ("See worklog §2", "(worklog §1)") — no worklog exists in-repo.
- **The cure (docs-truth, no behavior change).** README, the SyncPlayTask
  header, and the Check-46 row now state the shipped truth: this BUILD rides
  the plaintext `roStreamSocket` and ships no wss path; the platform CAN do TLS;
  the wss migration is a deferred option; custody rests on the refusal law, the
  M15 consent gate, the fail-closed accept proof — never on a transport that
  "cannot do TLS". The Check-46 row's wrong cross-pointer (wss migration filed
  under "secnet M2" — that is the hub-relay `:8804` leg, queue M-ROKU-23) is
  corrected to this item's own deferred arm. Scoped-true sentences stay
  verbatim (README "roStreamSocket has no TLS", Utilities.brs "impossible on
  THIS transport"); CHANGELOG history stays verbatim per house law. The
  roSecureSocket wss migration itself is NOT shipped here: a hand-rolled
  TLS-socket WebSocket client is a device-unverifiable feature the M14 lane
  explicitly deferred, and no vendored RokuOS socket docs exist in-repo to
  build against — the honest posture is refusal (shipped) with the option named
  truthfully, not a fabricated migration nor a false impossibility.
- **Law (CHECK46 R2-prose rotation — no new check number).** The extinct-
  claims arm now also convicts the two misclaim shapes (`wss://` stated
  impossible, Roku stated unable to do TLS) across README, SyncPlayTask and
  SyncPlayProtocol; the wording of the cure cannot re-trigger it (scoped-true
  forms probe-verified green). Portable plant-and-restore leg re-grows both
  forms in a scratch README — both arms fire naming README.md, CHECK44/CHECK45
  stay green (gate independence), restore returns exit 0.
- **Per-path truth at landing:** https origins — refused (never dialled);
  `http://` origins — cleartext `ws://` dial with the account JWT, ratified as
  no-new-exposure-class (their REST lane already rides the same bearer in
  cleartext; off-LAN `http://` cannot even persist without the M15 consent
  dialog); hub relay `:8804` — scoped 1-hour mint token, its own TLS posture
  rides queue M-ROKU-23; wss via roSecureSocket — deferred, now named as
  deferred.

### Fixed — a server-URL change no longer carries the old host's tokens (M-ROKU-24) — 2026-10-29

- **The defect (review roku__secnet M3).** `PersistAndGo` — the single
  `server_url` write-site CHECK48 R2 censuses to exactly one — overwrote the
  persisted address while the PREVIOUS host's `auth_token`, `refresh_token`
  and `session_id` were still in Storage. `PhlixApp.OnConnected` then rebuilt
  the client (`GetApiClient()` restores those keys unconditionally),
  `restoreSession()` fired `GET {new}/auth/me` with the OLD Bearer, and the
  401 refresh arm POSTed the old refresh token to `{new}/auth/refresh` — a
  latent credential leak to an unverified host. Reachable at the tip through
  the boot transport-failure retry (`HandleBootAuthFailure` ->
  `ShowConnect(reason)` prefills the saved address, M-ROKU-04): edit it to
  another host and connect. Settings -> Switch (`OnSwitchServer`) did wipe
  six keys first, but the invariant lived in one caller, not at the choke —
  exactly the implicit-invariant shape the review convicted.
- **The cure.** The custody law now sits at the write-site: when a
  `server_url` was already persisted AND the incoming url differs,
  `ResetCachedStorage(true)` (the R1.6 six-key wipe — auth/session + hub
  binding keys; `server_url` and `device_id` survive by that primitive's own
  law) runs BEFORE the new url is written and before the `connected` signal.
  The rebuilt client restores nothing, `restoreSession()` takes its honest
  `no_session` arm and the user logs in on the new server; no credential ever
  rides a request to a host it was not issued by. Same-URL reconnect (the
  prefill/retry affordance) KEEPS its session — equality means the persisted
  tokens belong to this host; first connect has no prior url and wipes
  nothing. The cleartext-consent arm reaches the same choke and inherits the
  law. `OnConnected` gained the docblock truth; its purity (rebuild +
  `StartAuthCheck()`, zero storage writes) is now pinned.
- **Law (CHECK53, static statement-presence legs — the CHECK50/51/52
  precedent, the flow needs registry + network nodes):** R1 pins the capture
  (`previousUrl = GetServerUrl()`), the exact conditional guard, the
  `ResetCachedStorage(true)` call and the wipe -> write -> signal order; R2
  convicts any hand-rolled delete list inside the choke (the six-key census
  is `Storage.brs`'s single source) and keeps the write count at one; R3
  keeps `OnConnected` a pure rebuild with the auth check wired. Portable
  plant-and-restore leg re-grows the pre-cure persist and fires four named
  CHECK53 convictions with CHECK48/CHECK52 gate independence. Red-on-parent
  MEASURED at `14465fe`: exactly 4 CHECK53 pins fire, all 52 other legs PASS.
- **Scope honesty.** No new user-facing strings — the wipe is silent and its
  observable effect is the login screen, already cataloged in all seven
  locales; the `_metadata.version` 1.10.0 set and CHECK48's pin are
  untouched. `Back`/teardown posture (CHECK27/C47) and the key-repeat
  throttles are untouched; `make lint` and the full battery are green at the
  landing sha.

### Fixed — a failed read never renders as emptiness again (M-ROKU-21) — 2026-10-29

- **The defect (review roku__gameux M6).** Failure and emptiness were rendered
  identically on both home surfaces. `DashboardScene`'s `ExtractData` collapsed
  `!ok` (401/403), a missing or malformed envelope and an honest empty `[]` into
  the SAME `[]` — its own docblock advertised the collapse — and
  `RenderDashboard` printed "(none)" rows, so an admin with a cleared token read
  "you have nothing" from a server that had actually refused. `HomeScene`'s
  `OnLibrariesResponse` had no failure branch at all (empty grid, description
  still "Select a library", no retry), and `OnContinueWatchingResponse` just
  `return`ed on `!ok` — indistinguishable from "you have not watched anything".
  A wiped token or an unreachable server produced a confidently-empty app with
  no recovery path.
- **The cure.** `ExtractData` now yields `invalid` on every failure arm and
  `[]` only on honest emptiness; `OnApiResponse` classifies each section into
  `m.nowPlayingFailed/m.storageFailed/m.activityFailed`. A failed section
  renders `Translate("dashboard_failed_row")` instead of "(none)", the status
  strip switches to `Translate("dashboard_failed_status")`, and a
  `focusable="true"` Retry button (the device-proven M-ROKU-16 boot-retry
  idiom) is revealed and takes focus; `buttonSelected` re-runs the whole
  serialized chain through the same `StartLoadChain` boot uses. On `HomeScene`,
  both rail handlers own explicit failure branches (`m.librariesFailed`,
  `m.continueFailed`) that light the description bar with
  `Translate("home_rail_failed")` and reveal the same focused Retry control;
  pressing it re-fires exactly the failed loads and nothing else, and success
  restores "Select a library" only when the bar still shows the failure copy.
  Honest emptiness stays honest: the dashboard still prints "(none)" when the
  server genuinely has nothing, and the continue rail keeps its
  hidden-when-empty shared-slot design (Check 32 law untouched).
- **Copy law.** All three sentences ride the locale catalog ×7 (new `home` +
  two-key `dashboard` keys, `_metadata.version` 1.9.0 → 1.10.0 as a set under
  CHECK48 R3's bump law, 348 keys per locale after this lane's set-bump joined the live-copy lane's twenty-six); the Retry label reuses the
  existing `common.retry` key through both `ApplyXmlChrome` subs. The three
  English sentences appear as raw literals in no `.brs` anywhere.
- **Teeth.** Check 52 in `scripts/verify-runtime.sh` pins the five
  `return invalid` arms (and bans any surviving `return []` in the body), the
  per-section classification, the three localized failure writes, both scenes'
  failure branches and retry re-fire arms, the XML focusability, and
  per-locale speakability — red-on-unfixed-source measured at 47 pins; the
  portable twin reverts ONE branch (`!ok` arm back to `return []`) in a scratch
  copy and requires CHECK52 to name both the lost arm and the collapse
  detector while CHECK48/CHECK51 stay green.
- **Numbers.** 16 files, 547+/39− in this commit (rebased onto the mid-lane `2dd8b76` + `a5dad23` landings);
  `make lint`/`bslint`/`validate-xml.sh` (48 files) clean, full
  `verify-runtime.sh` battery and `verify-runtime-portable.sh` exit 0.

### Fixed — the FULL live player/party surface rides the locale catalog (M-ROKU-20 r2) — 2026-10-29

- **The defect (review roku__gameux M5 + r1 issues=5).** r1 closed with a
  PHANTOM commit (sha `1510912` never existed) and a pin claimed as "Check 50"
  — a number already held by M-ROKU-19 (r1 finding 5). By the time this fresh
  r2 clone swept the surface, a crossing sibling landing (`ab050d5`) had
  localized the three P5-S5 `errorMessageLabel` overlay texts (its own
  narrower Check 51; trio keys + CHECK48's 1.9.0 rotation are its landing,
  untouched here). Still raw English on every non-English device: the 13
  `SetSyncStatus` panel labels (incl. the `"{group} - {n} in group - {role}"`
  composition), the whole `ShowPartyNotice`/`NotifyPartyEvent` banner family
  (the `{member} joined` concat, elections, drops, host transport attribution),
  the playback/transcode dialogs, the hub-mode notice and the `SyncPlayTask`
  unknown-code fallback feeding the error banner.
- **The cure (r2).** 26 more `player_*` keys (29 with the trio's three) in all
  SEVEN locales — 319 → 345 flattened keys per locale (v1.9.0 held; sentences
  kept verbatim — a translation refactor, not a copy rewrite). Dialog
  titles/buttons ride the existing `common_error`/`common_retry`/
  `common_cancel` vocabulary; roles reuse `syncplay_role_host`/
  `syncplay_role_guest`; the three token keys (`player_sync_status_group`,
  `player_sync_members_in_group`, `player_party_member_joined`) compose only
  through `TranslateWithParams` (Check 24 law; 32 token-bearing values total).
  `SyncPlayScene`'s dead-room disposition is documented in `docs/i18n.md`
  (keys parity-guarded; wire-vs-retire an owner call).
- **The teeth.** Check 51 superseded IN PLACE into the full M-ROKU-20 law
  (same number, strictly stronger legs; trio needles compatible): R1 the three
  overlay render sites; R2 every swept sentence convicted quote-anchored in
  the comment-masked code view of all `*.brs` under `components/` + `source/`,
  file:line named — PLUS the call-shape law: `SetSyncStatus("/ShowPartyNotice("/
  NotifyPartyEvent("` may never open a raw literal; R3 all 29 keys SPEAKABLE
  x7; R0 fail-loud. CHECK50's R3/R4 needles rotated to the localized call
  shapes (disclosed in-commit; attribution semantics unchanged), and its
  portable plant needle with them.
- **Verified:** `make lint` diagnostic census identical to parent (22 lines,
  exit 0); `scripts/verify-runtime.sh` 51/51 legs exit 0;
  `tests/scripts/verify-runtime-portable.sh` exit 0 (CHECK51 plant leg —
  shared with `ab050d5` — asserts R1+R2 named red with CHECK20/CHECK50 gate
  independence, restore green; ja_JP resolution leg green on all 345 keys);
  ad-hoc second probe reverting the connected-banner + task fallback to raw
  literals -> exit 1 with three named CHECK51 pins (CHECK50 R4 jointly red);
  seven-catalog flattened-key + token-multiset parity identical.

### Fixed — the toast dispatch rides the proven observed-field channel; CHECK49 R7 re-pinned around the mechanism (M-ROKU-17 r2, superseding the 689b475 dispatch door) — 2026-10-29

- **The defect (review roku__gameux M17r1 CRITICAL-1).** The r1 round re-based
  the toast onto the built-in Dialog and repaired per-scope wiring — both
  reviewed RIGHT — but preserved the R3.4 DELIVERY fiction:
  `target.PostMessage("showToast", content)` into `sub onMessage(msg as
  Object)`. That wire is no articulable RokuOS node contract. Adjudicated from
  the vendored authority this channel lints against
  (brighterscript/dist/roku-types/data.json): `PostMessage` is modeled exactly
  once — on `roRenderThreadQueue`, whose documented receive path is
  `AddMessageHandler`, used nowhere here — `roSGNode` is modeled without it,
  and no `onMessage` special is modeled at ANY arity. Repo precedent concurs:
  none of the seven shipped Task components rides an onMessage door; every
  working child->coordinator delivery (the requestClose arms,
  ShowErrorDialog's wasClosed observers) rides OBSERVED FIELDS. The twin
  landing 689b475 re-signatured the receiver to
  `onMessage(messageType as String, data as Object)` claiming a platform
  contract, and pinned that claim into CHECK49 R7 — the same unmodeled door
  with an inverted gate actively defending fiction against future cures; this
  round supersedes the dispatch half of 689b475 outright (its CHECK49 R7
  contract-arm pins rotate with it). 689b475's pre-attach queue drain (r1 ask
  3 — silent pre-setScene drops were the second dead door) is genuinely
  mechanism-independent and is ADOPTED verbatim into this cure; its queue
  pins fold into the new R7.
- **The cure (reviewer-recommended observed-field channel).** Delivery rides
  the root scene's DECLARED, OBSERVED interface fields: `PhlixApp.xml` gains
  `toastMessage` (string) + `toastDuration` (integer) payload and `toastSeq`
  (integer, `alwaysNotify`) trigger; `ToastManager.show()` queues
  pre-attach (cap 10, loud drop-oldest) and drains via `deliver()`, which
  keeps the documented `GetParent()` root walk, then writes
  payload-before-trigger behind a `DoesExist("toastSeq")` foreign-root guard;
  `PhlixApp` Init wires `ObserveField("toastSeq", "OnToastNotice")`; the arm
  reads the typed payload (duration bounded 0 < d <= 30000, adopting the
  689b475 boundary cap) into the SAME FIFO/display/dismiss coordinator the r1
  round built — untouched. The `onMessage` sub retires WITH its docblock.
  Copy stays app-side static, String/Integer-typed at every hop
  (ROKU-12/CHECK43), the XML ships zero literals (CHECK25), no custom key
  handling exists (C21/CHECK47 posture), and the coordinator's cap-5 + 30s
  bounded-retry policies are preserved verbatim.
- **The gate.** CHECK49 R7 now pins the mechanism itself: comment-masked
  repo-wide scans convict `.PostMessage(` and `sub onMessage(` extinct; the
  sender's guard/payload/trigger writes and payload-before-trigger order, the
  root's observer wiring + receiver arm + payload reads, all three interface
  declarations (trigger `alwaysNotify`), and the adopted pre-attach queue
  needles stand. Measured with the merged tree: reverting the dispatch files
  to the 689b475 door fires 12 named R7 pins; reverting to the r1
  7942e66 fiction fires 18 — R1..R6 and every other leg green in both
  probes, so the leg convicts the dispatch path specifically. Portable harness
  RED49B re-cut as one combined plant (dead wire + silent-drop + observer
  strip + arm rename; display machinery untouched) firing CHECK49 R7
  ten ways naming both files, with R1/R6 territory held and
  CHECK47/CHECK48/CHECK50/CHECK51 gate independence; restore -> exit 0.
  `docs/static-checks.md` row 49's false-as-worded "root `onMessage`
  coordinator" clause rotates with the cure.
- **Disclosed venue facts.** Full `scripts/verify-runtime.sh` exit 0 at 51
  legs (M20 added Check 51 since the r1 round); `make lint` exit 0 with the
  orphan-warning set identical to the 689b475 parent in the same venue (bsc
  reports 22 BS1013 `.test.brs` orphans here — a superset of the two files
  the r1 review named and of the single one the r1 report claimed; the
  delta attributable to this lane is ZERO, set-diff proven), `make bslint`
  green. rooibos .test.brs: NOT run (no ROKU_HOST — disclosed; the dispatch
  hop is render-thread field semantics — the same platform behavior the
  shipped requestClose arms exercise live, pinned statically per the
  CHECK47/48/49 family precedent). Locale law untouched by this lane.


### Fixed — live playback error copy rides the locale catalog (M-ROKU-20) — 2026-10-29

- **The defect (review roku__gameux M5).** The three highest-stakes messages a
  player can see — "Your session has expired…" (progress saving dead),
  "Playback blocked by access schedule…" (403) and "Stream limit reached…" (429) —
  shipped as raw English inside `PlayerScene.brs`'s error-overlay subs (L1012/
  L1701/L1714 at the parent), while the localized watch-party catalog family sat
  half-dead behind `SyncPlayScene`, a component never instantiated anywhere.
  A German or Japanese household got English exactly when something was wrong.
  The three texts were already the oldest named entry in the XML-chrome lane's
  documented-residuals list in docs/i18n.md.
- **The cure.** The three `Show*Error` subs now write
  `Translate("player_err_session_expired"/"player_err_access_schedule"/
  "player_err_stream_limit")` through the shipped `LoadLocaleStrings`/`Translate`
  loader — no `{placeholder}` tokens, so plain `Translate` is the lawful path
  (Check 24 untouched). All seven catalogs gained the three `player` keys
  (translated, alphabetical placement), bumping as a set v1.8.0 → v1.9.0 under
  CHECK48 R3's law (its version pin rotated with the set); 316 → 319 flattened
  keys per locale, Check 21 mirror parity held. Static law CHECK51 (the 51st
  leg): R1 pins the three overlay-sub Translate writes, R2 scans every `.brs`
  under components/ + source/ (comment-masked) for the three cured sentences as
  raw literals, R3 pins per-locale speakability of the three keys — the CHECK48
  idiom. Red-on-parent measured at `9ba7c9d` before the cure: 27 pins broken
  (R1×3 + R2×3 naming L1012/L1701/L1714 + R3×21), every other leg green; green
  after. Portable twin rides the plant-and-restore idiom: re-growing the raw
  session-arm literal fires CHECK51 R1+R2 with CHECK20/CHECK50 gate
  independence; restore exits 0.
- **Disclosed residuals (minors-queue, honest annotation shipped).** The rest of
  the M5 family stays raw: the 13 `SetSyncStatus` literals + the M-ROKU-19
  banner copy (that lane's CHANGELOG forward-points them at this sweep's
  choke-points — a ~10-15-key `syncplay_*` expansion kept out of this lane's
  brief-mandated minimal shape), the `ShowErrorDialog`
  "Error"/"Retry"/"Cancel"/"Playback failed…"/"Transcode timed out." sites
  (25-violation census if PlayerScene joined CHECK19 TARGETS — measured, too
  broad here), and the `SyncPlayScene` dead component itself (wire vs retire —
  owner decision; docs/i18n.md now says so at the section row). No new wire
  codes; no XML chrome touched.


### Fixed — the M-ROKU-17 pipeline's dispatch door opens: two-arg onMessage contract, pre-attach queue drain (M-ROKU-17r2) — 2026-10-29

- **The defect the landing left.** The sibling M-ROKU-17 cure (`7942e66`,
  disk-audited by this lane) rebuilt the display half correctly — Dialog-
  derived overlay, root coordinator, real `dialog` field, loud capped
  queue — but kept `sub onMessage(msg as Object)`. PostMessage dispatches
  through the platform contract `onMessage(messageType as String, data as
  Object)`: `msg` bound the STRING "showToast", the `roAssociativeArray`
  probe never passed, `messageType` stayed empty and every notice died at
  the door — the r1 headline ("the toast pipeline cannot display") still
  lived at origin tip while CHECK49 stayed green (its rules pinned the
  coordinator, never the signature). The manager kept the second dead
  joint too: `if m._scene = invalid then return` — a silent permanent drop
  for any notice raised before its scope's `setScene` (r1 ask 3).
- **The cure.** The arm now declares the contract: gate on
  `messageType = "showToast"`, `type()`-guard the payload node, extract the
  text through the shipped `WireErrorText` leaf and the duration through an
  integer probe with sane bounds (ROKU-12/CHECK43 law applied at the
  newly-visible boundary — today's posters are static app copy, the guard
  holds the door for the next caller). `ToastManager` gained the pre-attach
  queue `_pending` (cap 10, drop-OLDEST with a loud dev print — never
  silent) and `setScene` drains it FIFO into the unchanged `deliver`
  (the GetParent root walk moves into `deliver` verbatim, so their R6
  needles survive). Zero permanent drops on the normal path.
- **The teeth.** CHECK49 R7 (scripts/verify-runtime.sh) pins the signature
  literal, the guarded arm (gate, roSGNode probe, WireErrorText, integer
  probe, EnqueueToast) and the queue/drain pair — with the silent-drop
  guard forbidden outright. It is RED on `7942e66` (the dead door) and both
  plants fire in the portable harness's new RED49b family (single-arg
  re-plant names PhlixApp.brs; silent-drop re-plant names
  ToastManager.brs; CHECK49 R1/R6 territory and Checks 47/48 hold green —
  gate independence; restore returns exit 0). Docs row and this entry
  carry the truth; the architecture the sibling shipped is untouched.
### Fixed — watch-party events are now attributed on screen while watching (M-ROKU-19) — 2026-10-29

- **The defect (review roku__gameux M4).** Every SyncPlay event surfaced only on
  `syncStatusLabel`, which lives INSIDE `syncPanel` — and closing the panel
  stops the socket, so while actually watching (panel closed) the host's
  pause/seek/resume silently changed the picture and joins/host-elections/
  errors/drops were invisible. `ApplyRemotePlayback` carried no status call at
  all.
- **The cure.** A scene-level `partyNotice` strip in `PlayerScene.xml`
  (hidden by default, literal-free per CHECK25) driven by new
  `ShowPartyNotice`/`HidePartyNotice` subs using the shipped R2.1 one-shot
  Timer idiom; `NotifyPartyEvent` writes panel label AND banner. All three
  host-transport arms attribute ("Host resumed"/"Host paused"/"Host changed
  position", 2.5 s); open/info/host_elect/error banner 4 s, unexpected drops
  banner "Watch party disconnected" 6 s — suppressed when the close was
  user-initiated (`m.syncUserStopped` set before every intentional task stop,
  reset on fresh connect). The banner is panel-independent by law (CHECK50
  pins syncPanel out of its bodies).
- **Disclosed residuals.** The new literals ride the same un-Translate()'d
  family as the existing 13 `SetSyncStatus` strings — M-ROKU-20's i18n sweep
  localizes through the `ShowPartyNotice`/`NotifyPartyEvent` choke points.
  `SyncPlayTask`'s `closed` remains terminal (no auto-reconnect) and leaving
  the panel still drops the party — both deeper design items reported in the
  fixlog. Static law CHECK50 (scripts/verify-runtime.sh) + portable
  plant-and-restore red legs pin the cure; CHECK50 numbering reserves 49 for
  the M-ROKU-17 toast cure (landed at `7942e66` mid-this-lane; rebased atop).

### Fixed — the toast pipeline displays via the shipped dialog mechanism (M-ROKU-17) — 2026-10-29

- **The defect (review roku__gameux M2).** The R3.4 ambient-feedback layer was a
  three-layer phantom — and the r1 round adjudicated its one "fix" a phantom too
  (`934a322` is not an object anywhere; the defect re-verified live at `7541a10`):
  the root `onMessage` showToast arm ended in `m.top.ComponentController.Dialog = toast` —
  SGDEX vocabulary, no such node ever existed in the component set (sole occurrence
  repo-wide), the assignment landed on invalid; the overlay `ToastScene` extended
  `Scene`, which is not a legal `Scene.dialog` payload (Roku's Scene reference expects
  "a node extended from a Dialog node"); and its script faked its mechanics — a Timer
  created but never attached (timers only tick in the render tree), a Label
  `visible="false"` never flipped, `m.top.close` writes (the built-in Dialog's dismiss
  control, not a Scene field) and a fabricated OnKeyEvent. Delivery was dead too:
  BrightScript `m` is per component-script-scope, so every including scope owns its own
  ToastManager instance, and the only non-root consumer (`PlayerScene.SetProgressWarning`)
  never called `setScene` — its singleton died at the invalid guard.
- **The cure (riding the shipped idiom).** `ToastScene.xml` re-based onto
  `extends="Dialog"` — zero children, zero literals (the notice text rides the inherited
  title field); the phantom `ToastScene.brs` deleted. The root `PhlixApp` coordinator
  gains an honest queue: FIFO cap 5, overflow drops the OLDEST with a loud dev print
  (never silent); display through `target.dialog = toast` on the CURRENT surface
  (topmost Scene-derived last-appended child — the OnConnected idiom, gated by
  `DoesExist("dialog")`); a scene-owned modal is never trampled (busy surface: bounded
  2s x 15-tick probe window, an expired queue drops WITH a print — zero permanent-drop
  on the normal path); auto-dismiss and Back exit ride the documented `close`/`wasClosed`
  pair on a shared Timer attached to the root scene (a Timer only ticks in the render
  tree); `OnToastClosed` drains the queue and an `IsSameNode` identity guard discards
  stale events from a reclaimed toast. `ToastManager.show()` now walks the documented
  `GetParent()` chain to the root coordinator (there is NO `GetTop()` on roSGNode — that
  is roSGScreen), and `PlayerScene` wires its scope's singleton (`toast.setScene(m.top)`).
  The one notice string made visible today is static player-progress copy, String-typed
  at both hops — the newly-visible path admits no unguarded wire text (ROKU-12/CHECK43
  law intact), and locale law is untouched (zero new literals, zero catalog edits).
- **The gate.** New CHECK49 leg in `scripts/verify-runtime.sh`: R1 keeps
  ComponentController extinct repo-wide (comment-masked, so era prose may name the dead
  defect); R2 pins `extends="Dialog"` byte-exactly and the phantom chrome (`toastLabel`,
  "Toast text here") extinct; R3 requires `components/ToastScene.brs` to stay DELETED;
  R4 pins the display write, the `wasClosed` drain observer and the `close` dismiss
  write; R5 pins the coordinator shape (queue init, the EnqueueToast/TryShowToast/
  ArmToastRetry trio, the cap-5 and 15-tick bounds, the root-attached `AppendChild
  (m.toastTimer)`); R6 pins the PlayerScene wiring and the manager root walk. CHECK25's
  stale Toast EXEMPT rotated out with the label that justified it (a stale exemption is
  itself red). Red-on-parent MEASURED at `7541a10`: 17 named CHECK49 pins fire with
  CHECK25 firing jointly (by design) and every other leg green; the full run exits 0 at
  49 legs here. Portable harness: a four-file plant-and-restore leg fires CHECK49 R1/R2/
  R3/R4/R6 naming each plant, CHECK47/CHECK48 gate independence, restore -> exit 0.

### Fixed — credential custody on the Connect/pair flow: consent-gated cleartext and self-decided redirects (M-ROKU-15) — 2026-10-29

- **The defect (review roku__exploiter M4).** Three custody holes survived the
  C21/C33-era laws and ROKU-14's WS-TLS floor (re-verified real at `1894809`):
  `NormalizeServerUrl` passed a typed `http://` through to ANY host and inferred
  `http://` from a narrow `192.`/`10.` string-prefix, `Connect()` persisted the
  probe-scrubbed URL unconditionally (so a cleartext origin for the password POST
  and every later Bearer was stored with no word said), and both credentialed
  sends left `roUrlTransfer` auto-follow ON — a hostile or compromised origin's
  `3xx Location` walked the credential to a host the user never chose.
- **The cure (fix-essence honored).** Pure new leaves in `Utilities.brs`:
  `HostOfUrl` (bracket-IPv6 aware), `IsPrivateHostAddress` (RFC1918 + `127/8` +
  `169.254/16` + `localhost`/`::1` — `10th-street.example.com` stays public),
  `ServerUrlUsesCleartextToRemoteHost`, `OriginOfUrl`, `IsCredentialSafeRedirectHop`,
  `ResolveRedirectTarget`, `RedirectHopLimit` (3); `NormalizeServerUrl` now
  delegates its inference to the same predicate the consent gate rides (single
  source — disclosed broadening: bare `127.x`/`localhost`/`::1`/`169.254.x` now
  infer `http://` like `192.168.x` always did). `Connect()` is THE consent choke:
  an off-LAN `http://` origin renders the loud two-button dialog (cataloged
  strings, default-deny — declining writes nothing) before the single
  `server_url` write-site `PersistAndGo`; the "Connect anyway" override funnels
  through the same gate. `sendRaw`/`sendRawWithDeviceId` pin
  `EnableRedirects(false)` and re-send each hop only for a same-origin target or
  a same-host `http -> https` upgrade; refusals carry no body and classify to a
  new 7th bucket, `connect.redirect_refused` (catalogs x7, `_metadata.version`
  1.7.0 -> 1.8.0), so `restoreSession` never wipes credentials on them.
  `resolveLocation` pins the same refusal (its docblock's best-effort hedge is
  now a guarantee); `probeHealth` deliberately keeps following — zero credentials.
- **The gate.** New CHECK48 in `scripts/verify-runtime.sh` (redirect law +
  consent choke + inference single-source + catalogs + suite; red-on-parent at
  `1894809`: 69 pins broken, other 47 checks PASS) with a plant-and-restore leg
  in the portable harness and a row in docs/static-checks.md;
  `tests/unit/RedirectCustody.test.brs` (+7) covers the pure leaves.

### Fixed — bootstrap screens never consume Back; the boot-retry button is focusable and wired once (M-ROKU-16) — 2026-10-29

- **The defect (review roku__gameux M1 + m5).** ConnectScene, LoginScene and
  ServerPickerScene each ate the Back press deliberately (`handled = true` —
  "Don't allow backing out"), so a signed-out user — whose first surface is
  one of these three — had no escape but Home or power. Certification requires
  Back to be never-disabled, and docs/navigation.md's own root-back law
  (M-ROKU-01/CHECK31) already promised "One Back from Home — or from any other
  bootstrap screen — exits cleanly": the traps made the repo's own sentence
  false. Compounding on the boot chrome: `ShowBootError` revealed the Retry
  button but never `SetFocus`'d it (`buttonSelected` requires focus + OK, so
  after a 20 s boot timeout the visible control was unpressable), and it
  re-`ObserveField`'d `buttonSelected` on every display, accumulating duplicate
  handlers with each retry.
- **The cure.** The three scenes' `OnKeyEvent` bodies carry no `"back"` branch
  at all — they return false, and the press bubbles to `PhlixApp.OnKeyEvent`,
  whose stack-bottom arm raises `exitChannel` for the clean `main()` end
  (exactly the HomeScene precedent, which never had a back branch). The
  buttonSelected observer moves to `Init` (wired exactly once; the static
  button outlives every error cycle), and `ShowBootError` now ends with
  `m.bootRetryButton.SetFocus(true)` — the C20-era focus law applied at the
  boot surface.
- **Teeth.** New CHECK47 leg in `scripts/verify-runtime.sh`: R1 convicts any
  `OnKeyEvent` body of the four bootstrap scenes that branches on `"back"`
  (comments masked; HomeScene included so the precedent cannot regrow a trap);
  R2 pins `ShowBootError`'s focus arm + zero `ObserveField(` and Init's single
  wiring; R3 pins the docs scope (navigation.md names the law by CHECK47,
  certification.md 3.3 carries M-ROKU-16). Red-on-parent MEASURED: the new
  script against the era tree `39380e3` — exit 1, exactly 8 named problems
  (R1 ×3 scene traps, R2 ×3 chrome pins — missing focus, the per-error re-observe and
  Init's absent single-wiring are the same era read three ways — R3 ×2 docs not yet
  carrying the law), all 46 sibling legs green. Portable plant-and-restore leg:
  re-swallowing Back in a scratch ConnectScene and returning the chrome to the
  trap era fire R1/R2 by name with CHECK46/CHECK44 green (gate independence);
  restore returns exit 0.

### Fixed — SecWebSocketAcceptValue truncates at the CRLF blank line (M-ROKU-14 r1 MAJOR-1) — 2026-10-29

- **The defect (r1 review of `4240ad2`).** The accept parser's header-block
  truncation searched for `\n\n`; the HTTP/WS handshake terminator is
  `\r\n\r\n`, so the truncation never fired on real-shape input and a body
  line after the terminator was extracted as if it were a header. The shipped
  device vector in `TestSecWebSocketAcceptValueParsing` (spoofed body → `""`)
  asserted the claimed law and therefore failed on-device (rooibos is
  ROKU_HOST-gated; the CHECK46 teeth pinned only the invalid/empty guard, so
  CI never saw it). Production was unaffected — the task hands the parser a
  byte slice ending AT the terminator — so this cure makes the defense-in-
  depth layer exist while claiming to, and the docblock "a body can never
  impersonate a header" claim true as written: no prose rewording needed.
- **The cure.** The line loop stops at the first blank line (`cut = ""` once
  Trim removes the CR — one test covering the CRLF terminator, CR-only
  padding, and bare-LF terminations alike) and the dead `Instr(nl + nl)`
  truncation is removed. The shipped spoofed vector passes as-authored; a new
  paired vector pins the complement: real accept header + terminator +
  spoofed body line → the header's value only. Verified by faithful
  simulation: all nine header-parse vectors (the suite's five, the review's
  proof input, a bare-LF shape, and prod-shape slices) match expectations.
- **Teeth.** CHECK46 R2 gains the blank-line tooth (the parser body must
  carry the stop). Red-on-parent MEASURED: new script against the era tree
  `4240ad2` — exit 1, exactly 1 named problem, naming
  `source/lib/SyncPlayProtocol.brs` and the MAJOR-1 class, all 45 sibling
  legs green. The portable plant-and-restore leg gains the THIRD defect arm:
  stripping the stop re-grows the class, fires the tooth naming the parser
  file, restore returns exit 0. CHECK46 R4 now names all five Test subs
  (adds the previously-unpinned `TestIsHex40Shape`), making docs row 46's
  "its five Test subs" true.
- **Minors.** The close report's "28 named problems red-on-parent" claim is
  rotated to the measured 29 (the era's missing test file double-counts: the
  read() fail-loud line + R4's "vanished" line — teeth stand; this CHANGELOG
  already pinned 29, the report now matches).

### Fixed — CHECK43 exemption list deleted, gate teeth grown to the two proven-blind sink classes (M-ROKU-12 r2 cure) — 2026-10-29

- **The residual (review M-ROKU-12 r2).** The r1 lane landed the ApiClient/
  PhlixApp source cure (`WireErrorText`, 587f85b) but not its tail: the
  CHECK43 in-flight WARN exemption {components/PhlixApp.brs, source/lib/
  ApiClient.brs} still path-blinded the two wire-choke files to the class,
  and the gate itself still could not SEE the two sink forms its own
  docblock names — r2 re-planted both in non-exempt `DetailScene.brs` and
  the full script ran rc=0 PASS (this lane reproduced the blindness at
  base `4240ad2`). The class was silently re-accumulable everywhere.
- **Gate teeth.** CHECK43 R1 grows from three arms to five: RAW_CONCAT (a
  wire `.error`/`.message` concatenated into or out of a string literal,
  both operand orders — the blind plant `"Server error: " + resp.error`)
  and TYPED_SINK (a wire member as a direct call argument to any callee
  whose first parameter is not proven `as Object` — the set is derived
  from the tree's own function/sub signatures, so SafeErrorMessage/
  WireErrorPresent/WireErrorText/GetErrorMessage/DiagnosticText self-
  exempt while the second blind plant `IsTransportReason(resp.error)`
  convicts naming the callee). `WireErrorText\(` joins GUARDED (the r2
  Ask-1 coupled precondition: the cured lines now survive by the token,
  not by RAW_READ's inability to cross `(`). GUARDED is evaluated on the
  code-masked line for the sink-family arms (a comment naming a guard no
  longer exempts a real raw op — r1 minor; the choke-lift arm keeps the
  raw-line allowance), and the type-gate literals survive the string mask
  so the `type(ev.message) = "roString"` family stays exempt. The RSG
  `.top` lookbehind is fixed into a working position (the old
  `(?<!m\.top\.)` window could never match: the pattern consumes the dot).
- **Exemption deletion.** The INFLIGHT dict, the WARN print and the stale
  header prose are gone; both wire-choke files rejoin the normal scan and
  pass clean (59 files, 46 legs, rc=0). `docs/static-checks.md` row 43 is
  re-anchored (its INFLIGHT sentence contradicted row 44; the cure-site
  census now reads eleven, naming the `SettingsScene:214` landing cure —
  the historical `16f338ca8` red-on-parent figures 35/31/ten stay verbatim
  for their true baseline). The portable RED43 leg plants ALL FIVE arms in
  a scratch `DetailScene.brs` — each must convict naming file and read
  (teeth proof this lane: the two-form r2 plant reddens rc=1 on the cured
  script where it passed rc=0 at the parent, log-paired in the fix report).
- **Prose math (r2 ask 3).** The 587f85b entry's red-on-`ff2791024` count
  is corrected to 14 named diagnostics in both homes (docs row 44 + the
  entry below); r2 measured 15 only on staged `a84cdb7` — the fixer's own
  report already carried the 14.
- **Lineage note.** The r1 review's `ten → eleven` census minor lands
  here; the historical CHANGELOG entries keep their then-true figures
  verbatim per house rule (forward-correction in this entry).

### Fixed — SyncPlay refuses TLS origins and proves the handshake (M-ROKU-14) — 2026-10-29

- **The defect (review roku__exploiter M3).** `BuildSyncPlayWsParts`
  (components/PlayerScene.brs) read the MAIN ACCOUNT JWT and handed it to
  `SyncPlayTask` regardless of the connected server origin's scheme; the task
  then offered it verbatim in the cleartext `Sec-WebSocket-Protocol: bearer,
  <jwt>` handshake over `roStreamSocket` (plaintext TCP, no TLS — `wss://` is
  impossible here). On an `https://` origin the credential had been
  established over TLS, so a passive LAN sniff captured a TLS-protected
  account token — the exact class the hub relay path had already retired by
  minting scoped relay tokens. Additionally `HandshakeAccepted` validated
  only the "101" status line and explicitly deferred the `Sec-WebSocket-
  Accept` hash, so a blind injector could forge an upgrade with no handshake
  proof at all.
- **The cure (refuse + prove).** (1) Origin law:
  `SyncPlayWsRefusedForOrigin(serverUrl as String) as Boolean`
  (source/lib/Utilities.brs — pure, case-insensitive `https://` prefix) is
  consulted INSIDE `BuildSyncPlayWsParts` BEFORE the credential is read; a
  TLS origin returns invalid and `ConnectSyncTask` renders the honest line
  (`syncplay_status_tls_refused`, all seven catalogs). `http://` origins keep
  dialling: their REST lane is already cleartext, so the dial adds no new
  exposure class. (2) Handshake proof: `SyncPlayProtocol` gains the RFC6455
  §1.3 machinery — `WS_ACCEPT_GUID`, `SecWebSocketAcceptValue` (header-block
  scan; a body can never impersonate a header), `ExpectedSecWebSocketAccept`
  (roEVPDigest `Setup("sha1")`/`Process`, its documented 40-hex output
  shape-gated before the hex→base64 conversion) and
  `VerifyHandshakeAccept`, FAIL-CLOSED: absent header, non-computable
  expectation or mismatch refuse the dial. `WaitForConnect` runs it AFTER the
  101 status gate (echo tolerance untouched), tags `m.wsAcceptFailed`, and
  `RunSocket` reports the new client-minted census code
  `local.ws_accept_invalid` (never a wire code — Check 23 family; catalog
  version 1.6.0 → 1.7.0 across the seven locales).
- **Teeth.** `scripts/verify-runtime.sh` Check 46 statically pins the
  predicate, the ordered choke (refusal before the token read), the trio's
  fail-closed shapes, the call ordering in `WaitForConnect`, the gated
  `EmitError`, census membership, and the seven-catalog speakability — and
  asserts the era's "do NOT verify / deferred" claims stay extinct in code
  and prose. `tests/unit/SyncPlayWsTls.test.brs` pins the predicate truth
  table, header-parse vectors (incl. the body-spoof guard), the wrong-case
  base64 mismatch, and the RFC6455 §1.3 example
  (`dGhlIHNhbXBsZSBub25jZQ==` → `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`) on-device;
  firmware without SHA-1 must take the fail-closed branch, which the same
  test asserts. Red-on-parent: CHECK46 R1–R4 each fire against `6a40a8f`
  (measured 29 problems at the era tree — R1×4 predicate/choke, R2×8 proof
  machinery + dead-era prose, R3×15 census + seven-catalog speakability,
  R4×2 vanished suite + its unreadable-pin guard; mutation probes soften-each
  → red).
- **Behavior change disclosed:** users who log in over an `https://` origin
  but expect SyncPlay on a reachable plaintext `:8097` now see a refusal
  status instead of a silently-downgraded connection. That silent downgrade
  WAS the vulnerability; scoped SyncPlay WS tokens server-side (the relay's
  design vocabulary) remain the follow-up that would re-open this lane.

### Fixed — untrusted mediaId shape-gated before play (M-ROKU-13) — 2026-10-29

- **The defect (review roku__exploiter M2).** The hub relay's
  `pending_command` frames ride a PLAINTEXT socket (`HubCommandTask` —
  `roStreamSocket`, no TLS), and ECP/launch deep-link args are
  attacker-settable; the play machinery consumed their `mediaId` with only an
  `invalid`/`""` check on the relay path and a printable-minus-`&` checker on
  the launch path. Both shapes survived into `ApiClient`'s
  `"/media/" + itemId` raw concatenation, so `x?profile=1`, `x#frag` or
  `x/../../admin/users` turned the victim's signed-in TV into an arbitrary
  Bearer-authenticated GET engine (LAN injector or hostile relay; the warm
  path additionally force-closed the active player, PhlixApp's
  `HandleWarmDeepLink`). `ValidateDeepLinkContentId` let `/ ? = # . :`
  through, and the relay path skipped even that.
- **The cure (one canonical guard, two gates + one delegate).**
  `IsSafeContentId(contentId as Dynamic)` (source/lib/Utilities.brs):
  `type()` must be String/roString — hostile JSON shapes (number, AA, list)
  are contract violations and return false, never stringified; the value is
  judged in its trimmed form; the length cap `ContentIdMaxLen()` (255,
  gate-pinned literal) runs BEFORE the per-byte loop; the loop allows exactly
  `[A-Za-z0-9_-]` (server item ids are CHAR(36) UUIDs — nothing legitimate
  needs a rejected byte, so the policy is a pure allowlist, no escaping).
  Applied at every entry: `OnPendingHubCommand` ignores relay frames whose
  `mediaId` fails the shape (matching that handler's documented ignore
  posture), `ValidateDeepLinkContentId` delegates to it (the era's printable
  loop is deleted; `ExtractDeepLinkParams` now forwards the trimmed value),
  and the single play choke `ProcessDeepLink` gates the id BEFORE any
  `getItem` request is built — a rejected id fails VISIBLE (the R3.1
  content-not-found dialog, since a shape-rejected id can never exist in the
  catalog) and never leaves the TV. The six play call sites (cold launch,
  warm x2, login-stashed restore, boot arms, relay) all funnel through the
  choke; `HandleWarmDeepLink`'s player teardown now runs only on
  entry-validated ids.
- **The gates.** CHECK45 (scripts/verify-runtime.sh): R1 pins the guard
  family live (signature, the [A-Za-z0-9_-] range literals + `-`/`_` codes —
  a printable-only re-fatten reddens — and the 255 cap literal); R2 pins the
  relay handler's guard before its `ProcessDeepLink()` call and extinct the
  era `invalid or = ""` form (comment-masked, ordering-pinned); R3 pins the
  choke gate before the request assignment and the visible reject; R4 pins
  the launch delegation. tests/unit/ContentIdGuard.test.brs pins the guard
  contract on-device (ROKU_HOST) with the review's exact hostile shapes —
  path traversal, `?`/`#`/`&`/`=`/`%`/space/`:`, control and high bytes,
  non-String wire values, trim-for-judgment, and the cap boundaries. The
  portable harness carries a two-arm plant-and-restore leg (re-planting the
  era relay form fires R2; re-fattening the launch validator fires R4;
  CHECK43/CHECK44 stay green through both; restore returns exit 0).
- **Deliberately out of scope (reported, not silently expanded).** The
  malicious-SERVER echo class — a hostile server's own `item.id` re-entering
  path interpolations across `ApiClient` (`/media/{id}`, playback-info,
  transcode, and the letter/`parentId` query families) — is the review's
  wider fix-direction tail; it rides a separate queue scope, and the server
  still enforces auth on every route it can reach.

### Fixed — M-ROKU-11 completion: version disclosure on the WebSocket/relay
dials + type-guarded wire error lifts (takeover lane) — 2026-10-29

- **The gap after CHECK42.** The landed M-ROKU-11 cure stamped the three
  `ApiClient` REST send sites; the SyncPlay `:8097` WebSocket handshake and
  the hub-relay path (token mint `POST` + handshake map) still dialed
  version-blind — the M11r2 docs pass recorded that honestly; this entry
  closes it.
- **Dial stamps via a task-scope leaf.** Task-thread components do not see
  `AppContext` (RSG component scopes), so `ProtocolChannelVersion()` — a
  zero-dependency roAppInfo leaf with invalid/empty degradation — landed in
  `SyncPlayProtocol.brs` (already included by both task XMLs; the first
  attempt calling `GetChannelVersion()` from a task compiled clean and died
  at runtime — CHECK44 R3 is the defect guard). `SyncPlayTask.WaitForConnect`
  and `HubCommandTask` (mint + map) now stamp `X-Phlix-Client-Version`;
  `probeHealth` stays header-free on purpose (arbitrary candidate origins).
- **Wire-lift guard.** `WireErrorText(value as Object, fallback as String)`
  (two required args — BrightScript has no default parameters, the same law
  M12's `SafeErrorMessage` landed with) now guards every wire-controlled
  error lift that reaches a String sink: the `restoreSession` transport
  chain, both `http_`-bucket error arms, and PhlixApp's boot-failure reason.
  A hostile `{"error":{...}}` body degrades to the typed fallback instead of
  raising. (SettingsScene's history arm shipped in M12's landing.)
- **Gate.** `scripts/verify-runtime.sh` CHECK44 (R1–R5, red-on-`ff2791024`
  with 14 named diagnostics — count corrected per review M-ROKU-12 r2's
  staged re-measurement; 15 was the `a84cdb7` figure; portable-harness
  mint-strip plant + CHECK42 gate-independence assert).
- Takeover disclosure: the prior lanes on this item raced fleet restarts
  (phantom-closeout protocol); this lane verified surviving disk work against
  origin, adopted origin's CHECK42/M12/M11r2 lines wholesale, and landed only
  the re-verified completion delta. Server riders: header ingestion into
  `ClientHeartbeatStore` stays a server-contract item; browser-CORS
  `Allow-Headers` (server `CorsManager.php:53`) does not list the header and
  is irrelevant to Roku sockets — web clients would need it added first.

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

### Added — In-player quality selection (G4, PR #32) — recorded retroactively 2026-10-30 (M-ROKU-33, review roku__writer M9)

Shipped `46c0d5b` (2026-07-08), inside this era. This entry is a disclosed
retroactive record: the CHANGELOG never carried it, and README.md's
"Manual quality selection" bullet has pointed readers ("see the CHANGELOG")
at this missing entry ever since — that pointer resolves with this commit.
Press **Up** in the player to open a quality picker listing **Auto**
(server-driven ABR over the multi-variant master) plus every rung the active
transcode advertises in its `variants[]` ladder, highest first; picking a
rung swaps playback to that rung's own signed playlist and resumes at the
same position, picking Auto hands playback back to native ABR. The choice
persists in the `Storage` key `preferred_quality` and re-applies on the next
transcode. With no ladder (direct-play or a legacy job) the picker shows Auto
only and no-ops gracefully. Depends on server-side A7 (the variants ladder).
Known limitation, unchanged and device-unverified: the transient
content-swap-while-playing behaviour still needs an on-device smoke test
(device queue blocked — `docs/BLOCKED_R0.1.md`); code path
`components/PlayerScene.brs`.
