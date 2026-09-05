# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native Roku (BrightScript + SceneGraph XML) client for the Phlix Media Server. There is no compiler and no host-side runtime — the code only executes when packaged and sideloaded onto a Roku device. Treat the toolchain as a thin wrapper around `zip` + the Roku ECP HTTP API on port 8060.

## Commands

All workflows go through `Makefile`. `package.json` exists only to alias these for `npm`-aware tooling; there is no Node code.

| Command | What it actually does |
|---|---|
| `make package` | Runs `_update-manifest` first (`scripts/derive-version.sh` rewrites `major_version`/`minor_version`/`build_version` into `build/manifest`), then `zip -r phlix.zip build/manifest source components images`. That zip is the entire build artifact. ⚠️ **Omitting `components` ships a UI-less channel** — the entire SceneGraph UI lives in `components/`, so a zip without it produces a black screen on the device. |
| `make package-signed` | Runs `scripts/package-signed.sh` to build a signed store-submission package — see `docs/publishing.md`. |
| `make install ROKU_IP=… ROKU_DEV=… ROKU_PASSWORD=…` | Packages, then POSTs the zip to `http://$ROKU_IP:8060/install/app`. |
| `make launch` / `make stop` | ECP keypress/launch calls — also need `ROKU_IP` etc. |
| `make lint` | Runs `npx bsc --project bsconfig.json` (brighterscript type-check). This IS a hard gate — it exits non‑zero on any diagnostic (type error, missing field, malformed XML/component pairing). The old grep-script description is stale. |
| `make bslint` | Runs `npx bslint --project bsconfig.json` (brighterscript style linter). A separate hard gate from `make lint` — exits non-zero on any error or warning. |
| `make test` / `make test-unit` / `make test-integration` | Drive `rooibos` (`npx rooibos-roku`), which **requires a device** — they only execute when `ROKU_HOST` (or `ROKU_TEST_HOST`) is set. Without one `make test` falls back to `make lint` and exits 1, and `make test-unit` lists the `tests/unit/*.test.brs` files and exits 2. |
| `make validate-routes` | S280 route gate — `node tests/scripts/verify-route-manifest.mjs` scans every URL the client can issue and compares it **tuple-exact** against the vendored `tests/fixtures/server-route-manifest.json`, then re-runs with `--self-test` to prove it can still go red. |
| `make validate-manifest` / `make validate-xml` | Greps `manifest` for required keys and checks XML files contain `<?xml` + `</component>`. Both `exit 1` on failure. |

Running a single test: there is no host runner — `rooibos --group unit` / `--group integration` still need `ROKU_HOST`. Otherwise sideload the package and invoke the test from the device (via the developer portal or telnet console on port 8080).

### CI caveat

`lint.yml` runs `bsc`, `bslint`, `validate-xml`, and `verify-runtime` as hard gates — no `|| true`. `test.yml` runs `make lint`, `make validate-routes`, `make validate-manifest`, and `make check`, and runs the unit-test step only when `ROKU_HOST` is set. Don't trust CI alone — verify by sideloading.

## Automated Quality Gates

> ⚠️  `bsc` green does not mean the code runs. It validates syntax, XML/component pairing, and type signatures — NOT:
> 1. Whether node field names actually exist on the declared node type
> 2. Whether the code path is reachable on the render thread vs Task thread
> 3. Whether runtime errors like &hEC (dot operator on non-object) or &hF4 (member function not found) will occur
> 4. Whether an observer callback name actually resolves in the component's scope

These commands are run in CI and must pass before merging:

- `npx bsc --project bsconfig.json` — brighterscript type-check (zero diagnostics required)
- `make verify-runtime` — 19 runtime-defect checks (scripts/verify-runtime.sh); hard CI gate in lint.yml and package.yml
- `make validate-routes` — S280 route gate: every issued URL is tuple-exact against `tests/fixtures/server-route-manifest.json`; hard CI gate in test.yml
- `make validate-manifest` — manifest has required fields
- `make validate-xml` — all XML files are valid SceneGraph documents
- `make lint` — runs bsc, the actual hard gate
- `make bslint` — runs bslint, a separate hard style gate (zero errors/warnings required)

## Architecture

### Layering

```
source/main.brs            → boots an roSGScreen, instantiates the PhlixApp scene, runs the message loop
components/*.{brs,xml}      → SceneGraph scenes + Task nodes (PhlixApp, Connect, Login, ServerPicker, Home, Library, Detail, Player, Recommendations, ApiTask, SyncPlayTask, HubCommandTask, ToastScene, …)
source/lib/*.brs           → pure BrightScript modules, all using the factory-object pattern (incl. SyncPlayProtocol, SyncPlayManager, ToastManager)
source/data/Theme.brs      → constants
locale/en_US/strings.json  → base-locale user-facing strings (see docs/i18n.md)
```

> The old `source/hub/` (`HubAuth.brs`, `HubConfig.brs`), `source/views/HubSettings.brs`, and
> `source/player/HlsPlayer.brs` were **deleted in F12b** — they were dead code targeting a wrong,
> never-wired hub contract (a `/api/v1/relay/{id}` path that does not exist). Hub support now lives
> in `AppContext.brs` + `ServerPickerScene` (see "Boot / connection gate" below). Don't resurrect
> those files or their guessed envelope shapes.

Each scene is an XML file declaring nodes + interface fields, paired with a `.brs` file implementing `Init`, `OnKeyEvent`, and field observers. Two navigation patterns coexist:

- **Bootstrap scenes** (Connect, Login, ServerPicker, Home) are managed by `Show*` methods
  and `On*` handlers. They are direct children of `m.top` added via `CreateObject` + `m.top.Append`
  and removed via explicit `RemoveChild` in transition handlers.
- **Pushed screens** (Library, Detail, Player, Search, etc.) use the screen stack:
  `PushScreen(nodeType, params)` creates/registers/pushes, `PopScreen()` removes/top pops,
  and the **`requestClose` contract** (see `PhlixApp.brs` and `docs/navigation.md`).

### Factory pattern for lib modules

Every file in `source/lib/` exposes a single `PascalCase` factory function that returns an object literal containing both state and methods (closing over `m`). Example: `ApiClient(baseUrl)` returns `{ baseUrl, token, sessionId, setToken: function(...), … }`. There are no classes. To add functionality, extend the returned object literal, not a prototype.

`ApiClient` is the single chokepoint for all HTTP to the Phlix server — every endpoint goes through its internal request transport, which builds `url = m.baseUrl + "/api/v1" + path` (so `baseUrl` is the bare origin, **without** the `/api/v1` prefix). It also reaches into `Storage` (the registry-backed key/value module) to persist `auth_token`, `refresh_token`, and `session_id`. The one exception is `probeHealth()`, which hits `{baseUrl}/health` directly (NOT `/api/v1/health`) — it is used by the first-run Connect flow to verify a candidate URL is reachable before persisting it.

In **hub mode** the media `ApiClient`'s `baseUrl` is the relay base `{hub}/api/v1/servers/{id}/proxy` (from `GetMediaBaseUrl()`), so the same transport produces `{hub}/api/v1/servers/{id}/proxy/api/v1{path}` — the hub captures the trailing `api/v1{path}`, re-anchors it as `/api/v1{path}`, and tunnels it to the server. The existing Bearer-send is correct as-is (the hub token *is* the relay auth); no transport change was needed for relay routing. `getMyServers()` (`GET /me/servers`) was added for hub detection / the server picker.

Managers (`AuthManager`, `SessionManager`, `LibraryManager`, `TaskManager`, `SyncPlayManager`) are thin wrappers around `ApiClient` that own a slice of state and the user-facing verbs. Scenes call managers, managers call `ApiClient`, `ApiClient` calls the server. Do not let scenes call `ApiClient` directly — that bypasses the manager state.

### Boot / connection gate

`main.brs` boots the `PhlixApp` scene. `PhlixApp.Init` builds the managers, then gates on whether a server has been chosen: `if not IsServerConnected()` → `ShowConnect()`, else it branches on **connection kind**. `IsServerConnected()` (in `source/lib/AppContext.brs`) just checks that the persisted `server_url` is set and non-empty.

On first run that path is `ShowConnect()` → the user picks a server on `ConnectScene` → on success `OnConnected()` removes the Connect scene, rebuilds `m.api`/`m.auth`/`m.session`/`m.library` against the now-connected `server_url`, then fires `StartAuthCheck()` (same async pattern as the boot flow below).

#### Async boot auth (R1.1)

When a server is already connected, `PhlixApp.Init` immediately shows a loading
label (`bootLoadingLabel`) and fires session validation on an `ApiTask` (off the
render thread) with a **20-second scene-level timeout**:

- **Direct mode** → `StartAuthCheck()` → `ApiTask` `checkAuth` op → `GetApiClient().restoreSession()` + `GET /auth/me`.
- **Hub mode** → `StartHubAuthCheck()` → `ApiTask` `checkAuthHub` op → `GetHubApiClient().restoreSession()` + `GET /auth/me` (bare hub URL, **not** the relay, because the relay's `/auth/me` is the server's perspective on the hub user and is unreliable).

Four distinct outcomes per mode:
1. Authenticated → `ShowHome()`
2. Not authenticated / server error → `ShowLogin()`
3. Hub mode only: authenticated + no `active_server_id` → `ShowServerPicker()`
4. Timeout already fired → response ignored; the error UI is already shown.

On timeout, `OnAuthTimeout()` shows the `bootErrorGroup` (error label + retry button)
and increments a retry counter. After ≤ 3 retries the message is "Can't reach the
server"; after > 3 it is "Unable to connect after multiple attempts". The retry
button re-fires `StartAuthCheck()`.

The boot UI nodes (`bootLoadingLabel`, `bootErrorGroup`, `bootErrorLabel`,
`bootRetryButton`) are declared as children in `PhlixApp.xml` and referenced by
`FindNode` in `Init`. The `bootRetryButton` observer is registered lazily on first
display of the error group so that timeout-triggered and manually-triggered error
states both wire the same handler.

#### Async login flow (R1.2)

`LoginScene.OnLoginPressed` mirrors the async boot-auth pattern:
1. **Render-thread feedback first** — button disabled, status label set before any I/O.
2. **Task dispatch** — `ApiTask` with `login` op, observed on `response` field.
3. **`OnLoginResponse`** — `ok: true` chains `getMyServers`; `ok: false` shows error + `ReEnableButton()`.
4. **`ReEnableButton()`** is the mandatory teardown on every failure branch — no exceptions.

#### Hub vs direct (F12b)

The connect URL may be a **direct Phlix server** or a **Phlix Hub** — both expose `/health` and `POST /api/v1/auth/login`, so connect + login are identical. `AppContext.brs` persists `connection_kind` (`"hub"`/`"direct"`; absent/unrecognized → `"direct"`) and, in hub mode, `active_server_id` + `active_server_name`.

- **Detection** happens **after login**: `LoginScene` calls `GET /api/v1/me/servers`; a `{servers:[…]}` array → hub (sets `connection_kind="hub"`, fires `hubDetected`); 404 / no array → direct (`connection_kind="direct"`, fires `loginSucceeded`).
- **Server picker.** On `hubDetected`, `PhlixApp` shows `ServerPickerScene` (one-shot `getMyServers` via `ApiTask`). Picking persists `active_server_id`/`active_server_name`, fires `serverPicked`, and `PhlixApp.OnServerPicked` **rebuilds `m.api`/`m.auth`/`m.session`/`m.library`** so they bind to the relay base.
- **Relay-base `GetApiClient`.** `GetApiClient()` binds to `GetMediaBaseUrl()` (was `GetServerUrl()`). `GetMediaBaseUrl()` returns `{hubUrl}/api/v1/servers/{activeServerId}/proxy` **only** when `connection_kind="hub"` AND `active_server_id` is non-empty; otherwise it falls back to the bare `GetServerUrl()`. So in hub mode every scene/`ApiTask` transparently routes through the hub relay (the **hub** Bearer is the relay auth — the hub strips client auth, verifies ownership, injects `X-Phlix-Relay-User`), and **direct mode is byte-unchanged**. The fallback is what lets login and the `/me/servers` probe hit the bare hub URL before a server is picked.
- **Hub-scoped calls use `GetHubApiClient()`** (bare hub URL + restored token), NOT `GetApiClient()`. Boot session-validation in hub mode runs `GetHubApiClient()` + `AuthManager.checkAuth()` (so `/auth/me` hits the hub, not the relay where it is unreliable): valid + server picked → `ShowHome()`; valid + no server → `ShowServerPicker()`; else `ShowLogin()`.
- **Logout** clears `connection_kind`/`active_server_id`/`active_server_name` but **keeps** `server_url`.
- **Logout order guarantee (R1.3):** `OnLogout` clears all six registry keys
  (`auth_token`, `refresh_token`, `session_id`, `connection_kind`, `active_server_id`,
  `active_server_name`) synchronously on the render thread **first**, then navigates to
  `ShowLogin()`, then fires the `ApiTask` `logout` op off-thread. This order ensures local
  state is committed before the async server call fires, so a rapid re-login on the same
  device cannot observe stale session data.

### SyncPlay / Watch Together (F13)

SyncPlay is a hand-rolled RFC6455 WebSocket client built **to a not-yet-deployed phlix-server target
contract** (the post-`SP*` SyncPlay worker; the server's `:8097` WS worker is still a `(Future)`
stub), and it is **device-unverifiable** (bsc + review only). Two new files plus an additive overlay:

- `source/lib/SyncPlayProtocol.brs` — a **pure** factory (no I/O, no UI): RFC6455 framing
  (`BuildClientFrame`/`BuildTextFrame`/`ParseFrames` with masked client frames + buffered decode;
  BrightScript has no infix `xor`, so masking uses a composed `XorByte` helper), the WebSocket
  handshake helpers (we send a valid random `Sec-WebSocket-Key` and accept the `101` **without
  verifying the accept hash** — noted in-code), the **FLAT** `syncplay_*` codec (`Encode`/`Decode`;
  payload fields at the top level, `protocol_version:1`, ms `timestamp`), and the NTP TimeSync
  (weighted-mean offset, variance-<50 stability, drift EMA clamped `[0.99,1.01]`). Module-level
  `NowMs() as LongInteger` uses a `1000&` literal to avoid 32-bit overflow on `seconds*1000`.
- `components/SyncPlayTask.{xml,brs}` — a long-lived `Task` (`functionName="RunSocket"`) that owns
  the `roStreamSocket`. Socket I/O **must** be off the render thread: one shared `roMessagePort`
  receives both `roSocketEvent` and the scene→task `command` `roSGNodeEvent`; a `wait(4000,port)`
  returning `invalid` is the tick that sends a `time_ping`. Only assocarray/string/number cross the
  Task↔scene boundary — the Task reads `config`/`command` and writes `event`/`connectionState`, never
  touching UI nodes. Because component scope does not auto-include `pkg:/source`, its XML carries the
  full `<script>` closure (Storage, Utilities, AppContext, SyncPlayProtocol, own `.brs`).
- `components/PlayerScene.{xml,brs}` — the **only** place playback control lives, so SyncPlay is an
  additive "Watch Together" overlay there (LabelList of groups + Create/Leave + status). It is opened
  by the `*`/Options key and **lazily** creates the `SyncPlayTask` + group-list `ApiTask` on first
  open, so the default playback path is byte-unchanged when the overlay is never opened. Inbound host
  play/pause/seek are applied to the local `Video` node drift-corrected (ms→s) and echo-suppressed by
  `your_id`; when this device is the host, local play/pause/seek (at the user-input layer only — not
  from `OnPlayerStateChange`, to avoid feedback loops) are broadcast.
- `ApiClient.getSyncPlayGroups()` → `GET /api/v1/syncplay/groups` (whole `{groups}` envelope, not
  unwrapped) feeds the overlay list so no group id is typed on the TV; create/join/leave go over WS.

  > **Note:** The documentation was vindicated — commit `608141d` regressed the code to use `/syncplay/rooms`
  > instead of `/api/v1/syncplay/groups`, and R4.1's static checks now guard it. The docs were right;
  > the code was wrong.

**Two hard facts to keep in docs/code:**

- **`ws://` only.** `roStreamSocket` is plaintext TCP with **no TLS** → `wss://` is impossible. The
  scene derives `ws://<host>:8097/syncplay?token=<auth_token>` from `GetServerUrl()` (port forced to
  `8097`). It only works against a Roku-reachable **plaintext** `:8097` (LAN / documented exposure).
- **Hub mode is disabled.** The hub relay is HTTP-only (strips `Upgrade`), so SyncPlay refuses to
  open in hub mode with a message. Direct mode (`GetConnectionKind()<>"hub"`) only.

> The pre-F0b Roku client targeted an Emby-style API (an `ApiClient.deviceProfile` blob plus routes like `/Items/{id}/PlaybackInfo`). F0b removed the device profile and migrated the client to the canonical Phlix `/api/v1` API; there is no device-profile negotiation any more. Treat any lingering Emby-route references in older docs/comments as stale.

## BrightScript conventions used in this repo

These are conventions enforced informally (sometimes by `make lint`'s greps); follow them so existing code stays consistent.

- **PascalCase** for functions/subs and filenames; **camelCase** for variables and SceneGraph node IDs; `UPPER_SNAKE` for constants.
- Type every parameter and return: `function GetUserById(id as String) as Object`.
- `invalid` is the null. Always guard before use: `if user <> invalid then …`. Functions that fetch data return `invalid` or `{}` on failure rather than throwing.
- `print` is the only logging primitive — `make lint` rejects `console.log`. Leave production code free of speculative debug prints.
- Don't introduce hardcoded server URLs or credentials — the server URL is entered on the first-run **Connect screen** (`ConnectScene`, which normalizes the input and probes `GET {url}/health`) and is persisted via `Storage` under the `server_url` key. The boot flow gates on it (`PhlixApp.Init` → `IsServerConnected()` → `ShowConnect()` when unset). The login screen only collects username/password.

## When editing scenes

- Component XML and its `.brs` are coupled by file name and the `<script uri="…">` tag — rename both together.
- **Pushed screens** (any scene opened via `PushScreen`, i.e. on top of Home) **must**
  declare `<field id="requestClose" type="boolean" alwaysNotify="true" />` in their `<interface>`.
  This is how a scene closes itself without knowing its parent. Do not call `m.top.Close()`
  — that method does not exist on `Scene`/`Group` nodes and throws `&hF4`.
- Observers registered with `ObserveField` must be paired with `UnObserveField` when the scene tears down, or they leak.
- **3-outcome task response observer** — when a scene fires a `Task` and
  observes its `response` field, always handle all three logical outcomes:
  1. `ok: true` → success path.
  2. Auth/401 failure → dedicated auth-error path (e.g. session expiry overlay).
  3. Other failure → increment failure counter, warn after N consecutive
     failures (`m.progressFailuresBeforeWarning = 3`).
  Always pair `ObserveField` with `UnObserveField` in the scene's teardown
  path (e.g. `ClosePlayer`) so observers do not outlive the scene.
- Focus management is explicit: `SetFocus(true)` only on the currently-visible interactive node. Multiple `SetFocus` calls in one frame fight each other. `PopScreen` calls `SetFocus(true)` on the newly-exposed node automatically.
- **Busy-guard on Task nodes** — when starting a `Task` node with `control = "run"`, always
  guard first. Two policies are in use:
  - **Replace** (`ReportProgress`): if `m.state = "run"`, overwrite the in-flight job — use
    `if m.state <> "run" then m.state = "run" : m.top.control = "run" : end if`.
  - **Skip-if-busy** (`OnTranscodePollFire`): if `m.state = "run"`, silently return — use
    `if m.state = "run" then return else m.state = "run" : m.top.control = "run" : end if`.
  Unguarded `control = "run"` is caught by CHECK 11 in `make verify-runtime`.

## Reference docs already in the repo

- `README.md` — install/sideload procedure, full API endpoint table, remote-button mapping.
- `DEVELOPER.md` — extensive coding conventions, scene-graph patterns, mocking patterns for tests. Consult before writing new patterns from scratch.
- `docs/debugging.md` — telnet debugging guide with the full error dictionary (`&hEC`, `&hF4`, silent no-ops, etc.) and ECP endpoints.
- `docs/architecture-apitask.md` — ApiTask op-dispatch threading model, response envelope, and scaling notes.
- `docs/static-checks.md` — the 19 `make verify-runtime` checks, their CI wiring, and the `tests/scripts/verify-runtime-portable.sh` regression test.
- `docs/i18n.md` — the `locale/en_US/strings.json` scaffold and how CHECK 19 enforces it.
- `docs/publishing.md` — `make package-signed` and the store-submission steps.

<!-- caliber:managed:pre-commit -->
## Before Committing

**IMPORTANT:** Before every git commit, you MUST ensure Caliber syncs agent configs with the latest code changes.

First, check if the pre-commit hook is already installed:
```bash
grep -q "caliber" .git/hooks/pre-commit 2>/dev/null && echo "hook-active" || echo "no-hook"
```

- If **hook-active**: the hook handles sync automatically — just commit normally. Tell the user: "Caliber will sync your agent configs automatically via the pre-commit hook."
- If **no-hook**: run Caliber manually before committing:
  1. Tell the user: "Caliber: Syncing agent configs with your latest changes..."
  2. Run: `caliber refresh && git add CALIBER_LEARNINGS.md CLAUDE.md .claude/ 2>/dev/null`
  3. After it completes, briefly tell the user what Caliber updated. Then proceed with the commit.

**Valid `caliber refresh` options:** `--quiet` (suppress output) and `--dry-run` (preview without writing). Do not pass any other flags — options like `--auto-approve`, `--debug`, or `--force` do not exist and will cause errors.

**`caliber config`** takes no flags — it runs an interactive provider setup. Do not pass `--provider`, `--api-key`, or `--endpoint`.

If `caliber` is not found, tell the user: "This project uses Caliber for agent config sync. Run /setup-caliber to get set up."
<!-- /caliber:managed:pre-commit -->

<!-- caliber:managed:learnings -->
## Session Learnings

Read `CALIBER_LEARNINGS.md` for patterns and anti-patterns learned from previous sessions.
These are auto-extracted from real tool usage — treat them as project-specific rules.
<!-- /caliber:managed:learnings -->

<!-- caliber:managed:model-config -->
## Model Configuration

Recommended default: `claude-sonnet-4-6` with high effort (stronger reasoning; higher cost and latency than smaller models).
Smaller/faster models trade quality for speed and cost — pick what fits the task.
Pin your choice (`/model` in Claude Code, or `CALIBER_MODEL` when using Caliber with an API provider) so upstream default changes do not silently change behavior.

<!-- /caliber:managed:model-config -->

<!-- caliber:managed:sync -->
## Context Sync

This project uses [Caliber](https://github.com/caliber-ai-org/ai-setup) to keep AI agent configs in sync across Claude Code, Cursor, Copilot, and Codex.
Configs update automatically before each commit via `caliber refresh`.
If the pre-commit hook is not set up, run `/setup-caliber` to configure everything automatically.
<!-- /caliber:managed:sync -->
