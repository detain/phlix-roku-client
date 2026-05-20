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
source/components/*.{brs,xml}  → SceneGraph scenes (PhlixApp, Login, Home, Library, Detail, Player, GridItem)
source/lib/*.brs           → pure BrightScript modules, all using the factory-object pattern
source/pages/*.brs         → page controllers used by scenes
source/data/Theme.brs      → constants
```

Each scene is an XML file declaring nodes + interface fields, paired with a `.brs` file implementing `Init`, `OnKeyEvent`, and field observers. Scene navigation happens by `CreateObject("roSGNode", "<SceneName>")` and `m.top.Append(scene)` — see `PhlixApp.brs`.

### Factory pattern for lib modules

Every file in `source/lib/` exposes a single `PascalCase` factory function that returns an object literal containing both state and methods (closing over `m`). Example: `ApiClient(baseUrl)` returns `{ baseUrl, token, sessionId, deviceProfile, setToken: function(...), request: function(...), … }`. There are no classes. To add functionality, extend the returned object literal, not a prototype.

`ApiClient` is the single chokepoint for all HTTP to the Phlix server — every endpoint goes through its internal `request(method, path, body)`. It also reaches into `Storage` (the registry-backed key/value module) to persist `auth_token` and `session_id`.

Managers (`AuthManager`, `SessionManager`, `LibraryManager`, `TaskManager`) are thin wrappers around `ApiClient` that own a slice of state and the user-facing verbs. Scenes call managers, managers call `ApiClient`, `ApiClient` calls the server. Do not let scenes call `ApiClient` directly — that bypasses the manager state.

### Device profile is load-bearing

`ApiClient.deviceProfile` (in `source/lib/ApiClient.brs`) declares which containers/codecs the Roku will direct-play vs. transcode. The server reads this on `/Items/{id}/PlaybackInfo` and chooses the stream URL accordingly. Changing it changes server-side behavior, not just client decoding.

## BrightScript conventions used in this repo

These are conventions enforced informally (sometimes by `make lint`'s greps); follow them so existing code stays consistent.

- **PascalCase** for functions/subs and filenames; **camelCase** for variables and SceneGraph node IDs; `UPPER_SNAKE` for constants.
- Type every parameter and return: `function GetUserById(id as String) as Object`.
- `invalid` is the null. Always guard before use: `if user <> invalid then …`. Functions that fetch data return `invalid` or `{}` on failure rather than throwing.
- `print` is the only logging primitive — `make lint` rejects `console.log`. Leave production code free of speculative debug prints.
- Don't introduce hardcoded server URLs or credentials — server URL comes from the login flow / Settings page and is persisted via `Storage`.

## When editing scenes

- Component XML and its `.brs` are coupled by file name and the `<script uri="…">` tag — rename both together.
- Observers registered with `ObserveField` must be paired with `UnObserveField` when the scene tears down, or they leak.
- Focus management is explicit: `SetFocus(true)` only on the currently-visible interactive node. Multiple `SetFocus` calls in one frame fight each other.

## Reference docs already in the repo

- `README.md` — install/sideload procedure, full API endpoint table, remote-button mapping.
- `DEVELOPER.md` — extensive coding conventions, scene-graph patterns, debugging via telnet on port 8080, mocking patterns for tests. Consult before writing new patterns from scratch.
