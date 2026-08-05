# Changelog

All notable changes to **phlix-roku-client** are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed — UrlEncode RFC 3986 allow-list, prevent double-encoding (R4.6)

- `source/lib/Utilities.brs`: `UrlEncode()` now uses an allow-list (RFC 3986
  unreserved: A-Z a-z 0-9 - . _ ~); all other characters are percent-encoded.
  % is encoded first to prevent double-encoding. Non-ASCII chars are UTF-8
  byte-encoded before percent-encoding. Fixes "50% off" → "50%25off" (was
  "50%%20off") and "C++" → "C%2B%2B" (was "C++" on wire).
- `tests/unit/Utilities2.test.brs`: added `TestUrlEncodeNewBehavior()`

### Fixed — NormalizeServerUrl private-range detection (R4.7)

- `source/lib/Utilities.brs`: `NormalizeServerUrl()` now correctly validates the RFC1918 172.16.0.0/12 range (172.16.x.x – 172.31.x.x) instead of the overly broad 172.0.0.0/8. Also fixed the 10.x.x.x check to avoid incorrectly flagging hostnames.

### Fixed — Use real device identifier from roDeviceInfo (R4.8)

- `source/lib/AppContext.brs`: replaced unseeded `Rnd(999999999)` device ID with `roDeviceInfo.GetChannelClientId()` to prevent two factory-reset devices from colliding on the same ID. Also replaced hardcoded `"Roku"` device name with `roDeviceInfo.GetModelDisplayName()`. First usage of `roDeviceInfo` in the repo.

### Added — CHECK 14: media_items.type ENUM drift detection (R4.5)

`make verify-runtime` now includes **CHECK 14**, a Python check that:
- Reads the authoritative ENUM from the latest server migration (`034_media_items_type_audiobook.sql` — 13 members: movie, series, season, episode, track, music, album, artist, video, audio, book, photo, audiobook)
- Extracts the full type list from `Utilities.brs` comment block (lines 731–733) — must match exactly
- Verifies `PlayableTypes()` is a strict subset (6 of 13 members: movie, episode, video, audio, track, audiobook)
- Fails if either direction drifts (client vs server, or playable subset vs full ENUM)

Guards against silent UI loss: if a new ENUM member is added server-side but not documented client-side, or if `PlayableTypes()` includes a type that drops out of the ENUM, the check catches it at CI time.

### Fixed — User-visible error dialogs replace print-only ShowErrorDialog (R3.1)

**Users see errors instead of silent failures.** The channel previously printed
every error to the telnet console — `"No stream URL available"`,
`"Playback failed"`, `"Could not start transcode"`, `"Transcode failed"`,
`"Transcode timed out"`, `"No chapters available"`, and
`"Watch Together isn't available in hub mode yet"` — on a console no user
has access to. All error paths now surface a real `Dialog` node.

**`source/lib/Utilities.brs`** — `ShowErrorDialog` rewritten:
- **Signature:** `sub ShowErrorDialog(scene, title, message, buttons=["OK"], callback=invalid)`
  — scene must be passed explicitly so the dialog attaches to the right node tree.
- **Real Dialog node** — created via `CreateObject("roSGNode", "Dialog")`, set with
  `title`, `message`, and `buttons`, and attached via `scene.dialog = dialog`.
- **Observes `buttonSelected`** and `wasClosed` for dismissal handling.
- **Two shapes:** *info* (single `"OK"` button) and *retry* (`"Retry"` + `"Cancel"`).
- **Focus discipline** — Dialog node takes focus when attached; `SetFocus(true)` restores
  focus to the previously-active node on dismiss.

**`components/PlayerScene.brs`** — all 9 call sites updated; 5 retry callback
handlers added (`OnPlaybackRetry`, `OnStartTranscodeRetry`,
`OnTranscodeFailedRetry`, `OnTranscodeNoStreamRetry`, `OnTranscodeTimeoutRetry`).

**`SleepMs` deleted** — it wrapped blocking `sleep()` on the render thread, was
unused, and was flagged in the audit as a hazard.

**`print "Error:"` eliminated** — zero `print` error output remains in any call path.

### Fixed — Storage caching: 149→7 NVRAM reads per 60-second playback (R1.6)

**NVRAM read reduction.** Before R1.6, a 60-second playback session caused **149 NVRAM
reads** (4 per 10-second progress report × 6 = 24, plus 4 per 2-second transcode poll ×
~60 = 120, plus 5 startup reads = 149). After R1.6: **7 reads** (1 session restore on
task start + 6 periodic reads that bypass the cache by design = 7). This is a **95% reduction**.

**`source/lib/Storage.brs`** — complete rewrite:
- **Singleton** — `Storage._singleton` on the function object holds the cached instance;
  `Storage()` returns the same object on every call (bsc-compatible, no global required).
- **In-memory cache** — every `get` reads from `m._cache` (an associative array) on first
  access and stores the value there. Subsequent reads within the same Task run are pure
  in-memory.
- **Batched writes** — `set` writes to `m._cache` and marks the key dirty in `m._dirty`
  but does **not** flush to NVRAM. A `flush()` call iterates `m._dirty` and calls
  `Flush()` once for all pending keys.
- **Immediate-flush keys** — `auth_token`, `refresh_token`, `session_id`, `device_id` are
  flushed immediately on every write (durability guarantee for auth tokens). All other
  keys are batched.
- **`flush()`** — commits all dirty keys to NVRAM in one pass; idempotent when called
  multiple times.
- **`sizeEstimate()`** — walks all registry sections and returns total byte size; logs a
  warning when total exceeds 12 KB (Roku's 16 KB per-channel budget).
- **`invalidate(key)`** — removes a single key from the cache, forcing the next `get` to
  re-read from NVRAM. Used when a value is known to have changed externally.
- **`invalidateAll()`** — clears the entire cache. Called on server switch, login, and
  logout to prevent stale data from leaking across sessions.

**`source/lib/AppContext.brs`** — removed the `ResetApiContextCache` wrapper function.
Cache invalidation now goes directly through `Storage.invalidate()` / `Storage.invalidateAll()`.

**`components/ApiTask.brs`**:
- **`m.api` is cached once per Task run** — `GetApiClient()` is called at most once per
  `ExecRequest` invocation; the resolved client is held in `m.api` for the duration of
  that run. On the next `ExecRequest` call a fresh Task node is used (per `Run()`), so
  the cache is naturally scoped to one operation.
- **`ResetCachedStorage(false)` at the start of each `ExecRequest`** — clears the
  `m._cache` (but not `m._dirty`; writes already queued by prior ops are still flushed
  normally). The `false` argument suppresses flush, so any writes from the previous
  request's logical scope are not lost.

**`components/PlayerScene.brs`**:
- **`QualityRowCaption(pref as String)`** — the `pref` parameter is now passed in from the
  caller rather than read from the registry inside the function. This eliminates one
  registry read per quality row per content list render.

**Flush calls added at natural sync points:**
- **`LoginScene.brs`** — `Storage.flush()` after a successful login commits auth tokens
  immediately.
- **`ServerPickerScene.brs`** — `Storage.flush()` after server selection commits the
  server identity.
- **`ConnectScene.brs`** — `Storage.flush()` after a successful connection probe commits
  the server URL.
- **`PhlixApp.brs`** — `Storage.flush()` on logout before clearing keys and on channel
  exit to commit any pending writes.

**`scripts/verify-runtime.sh`** CHECK 11 — 24-file exempt list added for
pre-existing callback-chained `Task` patterns where a Task fires a callback that
re-arms the same Task. These are intentional design patterns, not unguarded
`control = "run"` bugs.

### Fixed — Player progress task response observation (R1.5)

**`PlayerScene.brs`** — three additions:
- **`ObserveField("response", "OnProgressResponse")` in Init** — observes the
  `ApiTask` `reportProgress` op response so the scene can act on it off the
  render thread.
- **`OnProgressResponse`** — 3-outcome handler:
  1. `ok: true` → `ClearProgressWarning()` (clears any stale warning label).
  2. Auth failure (401/403 on the `data` envelope) → `ShowProgressAuthError()`
     (session-expiry overlay; no consecutive-count increment).
  3. Other failure → increments consecutive counter; shows warning after
     `m.progressFailuresBeforeWarning = 3` failures.
- **Helper methods** — `SetProgressWarning(msg)`, `ClearProgressWarning()`,
  `ShowProgressAuthError()`.

**`ApiTask.brs`** — `reportProgress` op: sets `ok = false` when `data` is
`invalid`, so the scene's 3-outcome handler receives a consistent envelope.

**`ClosePlayer`** — unobserves the progress task `response` field so the
observer is torn down when the player exits.

**`m.progressFailuresBeforeWarning = 3`** — named threshold constant (not a
magic number) for the consecutive-failure-before-warning policy.

### Fixed — Player busy-guard and second Task node (R1.4)

**`PlayerScene.brs`** — two related fixes:
- **Second dedicated Task node** — added `m.transcodePollTask` as a standalone
  `Task` node (separate from the existing `m.task`) to isolate the transcode-status
  polling job. This prevents the polling callback from sharing task state with the
  primary playback task.
- **`state = "run"` guard in `ReportProgress()`** — replace policy: if the task is
  already running (`m.state = "run"`), a new invocation replaces the in-flight job
  rather than racing with it. This guards against concurrent `ReportProgress` calls
  when multiple playback events fire in rapid succession.
- **`state = "run"` guard in `OnTranscodePollFire()`** — skip-if-busy policy: if the
  polling task is already running, subsequent poll fires are silently dropped. This
  prevents queue buildup when the poll interval fires while a prior poll is still
  in flight.

**`scripts/verify-runtime.sh`** — two additions to the static checker:
- **CHECK 11** — detects `control = "run"` on a `Task` node when no prior `state = "run"`
  guard is present, catching unguarded Task-start calls that can cause double-dispatch.
- **24-file exempt list** — pre-existing callback-chained patterns (where a Task fires a
  callback that re-arms the same Task) are allowlisted to avoid false positives.

### Fixed — Logout async migration (R1.3)

**`ApiTask.brs`** — new `logout` op:
- Fire-and-forget `DELETE /sessions/{session_id}` via `GetApiClient()`.
- Runs off the render thread; no response observed (fire-and-forget).

**`PhlixApp.brs`** — `OnLogout` restructured with **clear-local-state-first** order guarantee:
1. **Clear all six registry keys synchronously** — `auth_token`, `refresh_token`, `session_id`,
   `connection_kind`, `active_server_id`, `active_server_name`.
2. **Navigate to login** immediately.
3. **Fire `ApiTask` `logout` op** only after steps 1+2 complete.

### Fixed — Login async migration (R1.2)

**`ApiTask.brs`** — new `login` op:
- Fires `POST /auth/login` on `GetApiClient()`, stores `{ ok, data: { token, user } }` or
  `{ ok: false, data: { message } }` on `response`.

**`LoginScene.brs`** — `OnLoginPressed` rewritten:
- **Immediate feedback**: disables the login button and shows a status label ("Signing in…")
  synchronously on the render thread before firing the task.
- **Async dispatch**: creates an `ApiTask`, sets the `login` op, invokes `task.control`,
  and observes `response`.
- **`OnLoginResponse`** unified handler: on `ok: true` → proceeds to `getMyServers`; on
  `ok: false` → shows error label + `ReEnableButton()`. On `getMyServers` response →
  same `hubDetected`/`loginSucceeded` branching as before.
- **`ReEnableButton()`** called on **all** failure paths — invalid credentials, network
  error, timeout, and server error — so the button is never left disabled.

**`LoginScene.xml`** — repositioned status/error labels to avoid overlap with the button row.

### Fixed — Boot auth async migration (R1.1)

The boot auth flow was restructured to move session validation off the render thread,
show a loading frame immediately, and handle failure gracefully with a retry affordance.

**`ApiTask.brs`** — two new ops:
- `checkAuth` — session restore + `GET /auth/me` validation via `GetApiClient()`.
  Runs on the relay base in hub mode, direct base in direct mode. Returns
  `{ ok, data: user }` or `{ ok: false, data: invalid }`.
- `checkAuthHub` — hub boot auth using `GetHubApiClient()` (bare hub URL, **not**
  the relay) so `GET /auth/me` hits the hub directly where the user token is
  meaningful. Same response shape as `checkAuth`.

**`PhlixApp.xml`** — added boot UI children:
- `bootLoadingLabel` — "Loading…" label, shown immediately on boot while auth
  check runs on the task thread.
- `bootErrorGroup` — `Group` containing `bootErrorLabel` + `bootRetryButton`,
  shown after the 20 s timeout or when the auth response is an error.

**`PhlixApp.brs`** — `Init` restructured into three paths:
- **No server** (`IsServerConnected() = false`) → `ShowConnect()` (unchanged).
- **Hub mode** → `StartHubAuthCheck()` → fires `checkAuthHub` on `ApiTask`.
- **Direct mode** → `StartAuthCheck()` → fires `checkAuth` on `ApiTask`.

Both `Start*` methods show `bootLoadingLabel` immediately, create a single
`ApiTask`, register a 20 s `Timer` for scene-level timeout, and observe the
`response` field. The task runs entirely off the render thread.

Four distinct outcomes per mode (direct / hub):
1. Authenticated → `ShowHome()`
2. Not authenticated → `ShowLogin()`
3. Authenticated + no server picked (hub only) → `ShowServerPicker()`
4. Timeout already fired → response ignored (error UI already shown)

`OnAuthTimeout()` stops the task, increments `retryCount`, shows the error
group with either "Can't reach the server" (≤ 3 retries) or "Unable to connect
after multiple attempts" (> 3 retries). `OnBootRetryButton()` re-fires
`StartAuthCheck()`.

### Added — Static runtime-defect checker (R0.7)

`scripts/verify-runtime.sh` implements 10 grep-based checks that catch the defect
classes `bsc` structurally cannot see:
- CHECK1: Storage.factory misuse (`Storage.get/set/delete/clear` → `GetStorage()`) — §5.1
- CHECK2: `m.top.Close()` calls → `m.top.requestClose = true` — §5.2 / R0.4
- CHECK3: `<ContentEmitter />` stub XML — R0.5
- CHECK4: `caption1Icon`/`handle://` invalid PosterGrid field/URI — R0.5
- CHECK5: `halign=` wrong Label attribute (should be `horizAlign=`) — R0.6
- CHECK6: `ObserveField` callback without matching `sub/function` — §5.5
- CHECK7: `FindNode` target absent from component XML `<children>` — §5.5
- CHECK8: `m.videoPlayer` assignments to non-existent Video node fields — §5.6
- CHECK9: `OnKeyEvent` comparisons to invalid Roku remote keys — §3.6
- CHECK10: `ApiClient.wait/sync` blocking calls outside `components/ApiTask*` — §5.3

Wired as `make verify-runtime` and as a hard CI gate in `.github/workflows/lint.yml`.
All 20 mutation proofs confirmed (10 checks × fire-then-pass).

### Removed — Deleted unused broken GridItem and RecommendationCard components (R0.6)

- `components/GridItem.{brs,xml}` and `components/RecommendationCard.{brs,xml}` — never
  instantiated, broken in 4 ways: wrong `DoesExist` API, `FindNode` targeting absent node,
  unwired `focusChanged` handler, `halign` vs `horizAlign` XML attribute

### Added — Screen navigation stack (R0.3)

- **`PushScreen(nodeType, params)`** — creates a child scene, appends it to `m.top`,
  sets focus, records it on the screen stack, and returns the node. The caller drives
  post-push setup (e.g. `scene.LoadLibrary(id, name)`).
- **`PopScreen() as Boolean`** — removes the top scene from the stack, removes it from
  `m.top`, calls `SetFocus(true)` on the newly-exposed node (fixing the pre-stack bug where
  the remote went dead after one Back press), and returns `true`. Returns `false` when the
  stack is empty — the caller must return `false` from `OnKeyEvent` so the Roku OS handles
  the back press and exits the channel (certification item 6).
- **`requestClose` contract** — every pushed child scene declares
  `<field id="requestClose" type="boolean" alwaysNotify="true" />` in its `<interface>`.
  When a scene sets `m.top.requestClose = true` (e.g. an internal Back handler), `PhlixApp`
  automatically calls `PopScreen()` via a registered observer. This lets a child close itself
  without knowing its parent or having a reference to `PhlixApp`.
- **`m.top.Close()` removed** — `Close()` exists on `roSGScreen`, not on `Scene` or `Group`
  nodes. All 22 pushed component XMLs had a `requestClose` field added; no component calls
  `m.top.Close()`.
- **Certification item 6 fixed** — the previous `OnKeyEvent` swallowed Back at the root
  (returned `true` unconditionally) so the channel never exited. `PopScreen()` returning
  `false` from an empty stack now correctly defers to the Roku OS.

### Fixed — `m.top.Close()` replaced with `m.top.requestClose = true` (R0.4)

- **34 call sites migrated** across 29 `.brs` component files in `components/`
- **13 missing XML field declarations added** (`<field id="requestClose" type="boolean" alwaysNotify="true" />`)
- **8 parent scenes wired** with `ObserveField("requestClose", "OnChildRequestClose")` + handler:
  HomeScene, FavoritesScene, MusicScene, AdminScene, CollectionsScene, DetailScene,
  LibraryAdminScene, LiveTvScene

> ⚠️ **Known limitation:** ~13 more parent scenes (~21 `m.top.Append` calls) are **not yet wired**
> with observers. Child scenes in those branches (SearchScene→Series/Season/Detail,
> WatchHistoryScene→…, etc.) that call `m.top.requestClose = true` will have the signal
> silently ignored. This is a pre-existing gap — not a regression introduced by R0.4.

### Fixed — Storage factory misuse causes runtime error `&hEC` on launch

- **`Storage()` can no longer be called directly as an object.** The `source/lib/Storage.brs`
  factory was being used directly at approximately 40 call sites (e.g. `Storage().get(key)`),
  which fails at runtime with error `&hEC` ("Dot operator attempted with invalid left-hand side")
  because `Storage` is a factory function — calling `.get()` on the function value itself is
  invalid BrightScript. A new `GetStorage()` function wraps the factory call and returns the
  object; all 43 call sites across `AppContext`, `ApiClient`, `SyncPlayManager`, `PlayerScene`,
  `PhlixApp`, `LoginScene`, `ServerPickerScene`, and `ConnectScene` have been migrated to use
  `GetStorage()`.
- **User-visible effect:** the channel now boots to the home screen without erroring out on the
  first frame of `PhlixApp.Init`. Before this fix the channel crashed immediately with `&hEC`
  because every code path during init called into Storage before the registry was usable.

### Fixed — Play button for audio/track/audiobook/video items

- **`DetailScene` no longer gates playback on a hardcoded `movie`/`episode`
  pair.** Both the Play-button visibility check and `OnPlayPressed` now call the
  new shared `IsPlayableItem()` / `IsPlayableType()` helpers in
  `source/lib/Utilities.brs`, whose allowlist (`PlayableTypes()`) is the set of
  playable **leaf** members of the server's `media_items.type` ENUM: `movie`,
  `episode`, `video`, `audio`, `track`, `audiobook`. Containers (`series`,
  `season`, `album`, `artist`, `music`) and stream-less types (`book`, `photo`)
  stay non-playable.
- Previously an `audio`/`track`/`audiobook`/`video` item opened a detail page
  with **no Play button**, and pressing Play was a **silent no-op**. This was
  latent: before phlix-server#527 the server's `MediaItemShaper` coerced every
  unlisted type to `"movie"`, so these items reached the client disguised as
  movies and got a Play button by accident. Not user-visible on current
  production data (episode/movie/season/series rows only) — it matters once
  music/audiobook libraries populate.
- Unknown types are treated as **not** playable, so a future ENUM member loses
  its Play button rather than presenting a dead one.

### Fixed — `<ContentEmitter />` stub removed from component XML (R0.5)

- **Removed from 10 XML files** (11 total occurrences — HomeScene had 2):
  `components/HomeScene.xml`, `components/FavoritesScene.xml`,
  `components/MusicScene.xml`, `components/CollectionsScene.xml`,
  `components/DetailScene.xml`, `components/LibraryScene.xml`,
  `components/SearchScene.xml`, `components/SeriesScene.xml`,
  `components/SeasonScene.xml`, `components/WatchHistoryScene.xml`
- `ContentEmitter` is **not a real SceneGraph node type** — it has no
  runtime counterpart in the Roku SceneGraph SDK. Removing it cleans up
  the component tree and prevents potential confusion during debugging.

### Added — in-player quality selection (G4)

- **Quality picker overlay** in the player — press **Up** during playback to open a
  right-side panel listing **Auto** (the server-driven multi-variant `master.m3u8`,
  native ABR — the existing default behaviour, byte-unchanged) plus every ABR rung
  the active transcode advertises (e.g. 1080p, 720p, 480p…), highest first, sourced
  from the server's Stream-Quality/ABR **A7** `variants[]` ladder on the transcode
  start/status response (`source/lib/ApiClient.brs` `parseVariants()`). The
  currently-selected row is marked `(current)`. `Back` or `Up` again closes the
  panel without disturbing playback; the video keeps playing behind the overlay.
- **Picking a rung** swaps playback to that variant's own signed HLS media
  playlist (`PlayHls(variant.url)`) and preserves the current playback position
  by seeding the existing resume machinery, so playback picks up where it left
  off rather than restarting. **Picking Auto** returns playback to the
  multi-variant master (native ABR resumes deciding the rung). The choice is
  persisted (`Storage` key `preferred_quality`, value `"auto"` or a rung id) and
  re-applied automatically the next time a transcode becomes ready; if the
  persisted rung isn't present in a later job's (possibly lower) clamped ladder,
  playback falls back to Auto rather than erroring.
- **Graceful no-op** for direct-play (mp4) and legacy/single-variant transcodes:
  since there is no ladder, the picker shows Auto only, with a status line
  explaining there's no fixed-quality ladder for this stream — no crash, no dead
  end.
- Server-A7-dependent: the picker only ever has rungs to offer when talking to a
  server build that populates `variants[]` on the transcode start/status
  response; against an older server (or a legacy job) it degrades to Auto-only,
  matching pre-G4 behaviour exactly.

  **⚠️ Known residual risk — needs an on-device smoke test before this is
  considered fully verified in production.** Reassigning `content` on a *live*
  (playing) `Video` node to switch quality is a scenario this codebase has never
  exercised before; on some Roku firmware/models that reassignment is known to
  emit a transient `state="stopped"` event before `"buffering"`/`"playing"`,
  which — without protection — would be misread as a real stop and tear the
  whole player down instead of switching quality. A one-shot `m.switchingQuality`
  guard in `components/PlayerScene.brs` (`OnQualitySelected` /
  `OnPlayerStateChange`) suppresses exactly that transient stop, and the guard's
  logic was traced and static-analysis-verified sound end-to-end during review,
  but **BrightScript has no host test runner** — `npx bsc` and `make test-unit`
  cannot execute SceneGraph/Video-node state transitions, only device firmware
  can produce them. **Before shipping to real hardware, smoke-test on a real
  Roku:** open the picker (Up) mid-playback, pick a different rung and then
  re-pick Auto, and confirm playback SWITCHES (does not exit to the previous
  screen) and resumes at the prior position — ideally on one model that emits
  the transient stop and one that doesn't, if more than one is available.
