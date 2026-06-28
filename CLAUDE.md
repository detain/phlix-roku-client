# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native Roku (BrightScript + SceneGraph XML) client for the Phlix Media Server. There is no compiler and no host-side runtime — the code only executes when packaged and sideloaded onto a Roku device. Treat the toolchain as a thin wrapper around `zip` + the Roku ECP HTTP API on port 8060.

## Commands

All workflows go through `Makefile`. `package.json` exists only to alias these for `npm`-aware tooling; there is no Node code.

| Command | What it actually does |
|---|---|
| `make package` | `zip -r phlix.zip manifest source images`. That zip is the entire build artifact. |
| `make install ROKU_IP=… ROKU_DEV=… ROKU_PASSWORD=…` | Packages, then POSTs the zip to `http://$ROKU_IP:8060/install/app`. |
| `make launch` / `make stop` | ECP keypress/launch calls — also need `ROKU_IP` etc. |
| `make lint` | **Not a real linter.** A bash script of `grep` checks (no `console.log`, no `TODO/FIXME`, function names start with capital letter, expected files exist). It only `echo`es warnings; it never exits non‑zero. |
| `make test` / `make test-unit` / `make test-integration` | **Does not run any tests.** Only `find`s and lists `*.test.brs` filenames. BrightScript tests can only execute on a device. |
| `make validate-manifest` / `make validate-xml` | Greps `manifest` for required keys and checks XML files contain `<?xml` + `</component>`. The only `make` targets that `exit 1` on failure. |

Running a single test: there is no host runner. To execute a test you must sideload the package and invoke the test from the device (via the developer portal or telnet console on port 8080).

### CI caveat

`.github/workflows/{lint,test}.yml` invoke every step with `|| true`. Combined with `make lint`/`make test` never failing on their own, CI is effectively informational — a green check does **not** mean the code is correct. Don't trust CI as a quality gate; verify changes by sideloading.

## Architecture

### Layering

```
source/main.brs            → boots an roSGScreen, instantiates the PhlixApp scene, runs the message loop
components/*.{brs,xml}      → SceneGraph scenes + Task nodes (PhlixApp, Connect, Login, ServerPicker, Home, Library, Detail, Player, GridItem, ApiTask, SyncPlayTask, …)
source/lib/*.brs           → pure BrightScript modules, all using the factory-object pattern (incl. SyncPlayProtocol)
source/pages/*.brs         → page controllers used by scenes
source/data/Theme.brs      → constants
```

> The old `source/hub/` (`HubAuth.brs`, `HubConfig.brs`), `source/views/HubSettings.brs`, and
> `source/player/HlsPlayer.brs` were **deleted in F12b** — they were dead code targeting a wrong,
> never-wired hub contract (a `/api/v1/relay/{id}` path that does not exist). Hub support now lives
> in `AppContext.brs` + `ServerPickerScene` (see "Boot / connection gate" below). Don't resurrect
> those files or their guessed envelope shapes.

Each scene is an XML file declaring nodes + interface fields, paired with a `.brs` file implementing `Init`, `OnKeyEvent`, and field observers. Scene navigation happens by `CreateObject("roSGNode", "<SceneName>")` and `m.top.Append(scene)` — see `PhlixApp.brs`.

### Factory pattern for lib modules

Every file in `source/lib/` exposes a single `PascalCase` factory function that returns an object literal containing both state and methods (closing over `m`). Example: `ApiClient(baseUrl)` returns `{ baseUrl, token, sessionId, setToken: function(...), … }`. There are no classes. To add functionality, extend the returned object literal, not a prototype.

`ApiClient` is the single chokepoint for all HTTP to the Phlix server — every endpoint goes through its internal request transport, which builds `url = m.baseUrl + "/api/v1" + path` (so `baseUrl` is the bare origin, **without** the `/api/v1` prefix). It also reaches into `Storage` (the registry-backed key/value module) to persist `auth_token`, `refresh_token`, and `session_id`. The one exception is `probeHealth()`, which hits `{baseUrl}/health` directly (NOT `/api/v1/health`) — it is used by the first-run Connect flow to verify a candidate URL is reachable before persisting it.

In **hub mode** the media `ApiClient`'s `baseUrl` is the relay base `{hub}/api/v1/servers/{id}/proxy` (from `GetMediaBaseUrl()`), so the same transport produces `{hub}/api/v1/servers/{id}/proxy/api/v1{path}` — the hub captures the trailing `api/v1{path}`, re-anchors it as `/api/v1{path}`, and tunnels it to the server. The existing Bearer-send is correct as-is (the hub token *is* the relay auth); no transport change was needed for relay routing. `getMyServers()` (`GET /me/servers`) was added for hub detection / the server picker.

Managers (`AuthManager`, `SessionManager`, `LibraryManager`, `TaskManager`) are thin wrappers around `ApiClient` that own a slice of state and the user-facing verbs. Scenes call managers, managers call `ApiClient`, `ApiClient` calls the server. Do not let scenes call `ApiClient` directly — that bypasses the manager state.

### Boot / connection gate

`main.brs` boots the `PhlixApp` scene. `PhlixApp.Init` builds the managers, then gates on whether a server has been chosen: `if not IsServerConnected()` → `ShowConnect()`, else it branches on **connection kind**. `IsServerConnected()` (in `source/lib/AppContext.brs`) just checks that the persisted `server_url` is set and non-empty.

On first run that path is `ShowConnect()` → the user picks a server on `ConnectScene` → on success `OnConnected()` removes the Connect scene, rebuilds `m.api`/`m.auth`/`m.session`/`m.library` against the now-connected `server_url`, then falls through to `ShowLogin()` (or `ShowHome()` if a session was restored). The persisted key is `server_url`, consumed by `GetMediaBaseUrl()` / `GetServerUrl()`.

#### Hub vs direct (F12b)

The connect URL may be a **direct Phlix server** or a **Phlix Hub** — both expose `/health` and `POST /api/v1/auth/login`, so connect + login are identical. `AppContext.brs` persists `connection_kind` (`"hub"`/`"direct"`; absent/unrecognized → `"direct"`) and, in hub mode, `active_server_id` + `active_server_name`.

- **Detection** happens **after login**: `LoginScene` calls `GET /api/v1/me/servers`; a `{servers:[…]}` array → hub (sets `connection_kind="hub"`, fires `hubDetected`); 404 / no array → direct (`connection_kind="direct"`, fires `loginSucceeded`).
- **Server picker.** On `hubDetected`, `PhlixApp` shows `ServerPickerScene` (one-shot `getMyServers` via `ApiTask`). Picking persists `active_server_id`/`active_server_name`, fires `serverPicked`, and `PhlixApp.OnServerPicked` **rebuilds `m.api`/`m.auth`/`m.session`/`m.library`** so they bind to the relay base.
- **Relay-base `GetApiClient`.** `GetApiClient()` binds to `GetMediaBaseUrl()` (was `GetServerUrl()`). `GetMediaBaseUrl()` returns `{hubUrl}/api/v1/servers/{activeServerId}/proxy` **only** when `connection_kind="hub"` AND `active_server_id` is non-empty; otherwise it falls back to the bare `GetServerUrl()`. So in hub mode every scene/`ApiTask` transparently routes through the hub relay (the **hub** Bearer is the relay auth — the hub strips client auth, verifies ownership, injects `X-Phlix-Relay-User`), and **direct mode is byte-unchanged**. The fallback is what lets login and the `/me/servers` probe hit the bare hub URL before a server is picked.
- **Hub-scoped calls use `GetHubApiClient()`** (bare hub URL + restored token), NOT `GetApiClient()`. Boot session-validation in hub mode runs `GetHubApiClient()` + `AuthManager.checkAuth()` (so `/auth/me` hits the hub, not the relay where it is unreliable): valid + server picked → `ShowHome()`; valid + no server → `ShowServerPicker()`; else `ShowLogin()`.
- **Logout** clears `connection_kind`/`active_server_id`/`active_server_name` but **keeps** `server_url`.

> **Known hub-mode limitation:** the hub registers only `GET`/`POST` on its relay proxy, so `PUT`/`DELETE` (favorites-remove, rating set/clear, server-side session-end) don't reach the server in hub mode; and hub-token refresh-over-relay is not wired (re-auth on expiry). Both are documented follow-ups in `README.md` ("Hub / multi-server mode"). Direct mode is unaffected.

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
- Observers registered with `ObserveField` must be paired with `UnObserveField` when the scene tears down, or they leak.
- Focus management is explicit: `SetFocus(true)` only on the currently-visible interactive node. Multiple `SetFocus` calls in one frame fight each other.

## Reference docs already in the repo

- `README.md` — install/sideload procedure, full API endpoint table, remote-button mapping.
- `DEVELOPER.md` — extensive coding conventions, scene-graph patterns, debugging via telnet on port 8080, mocking patterns for tests. Consult before writing new patterns from scratch.
