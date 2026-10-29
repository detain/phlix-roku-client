# Roku Debugging Guide

Two audiences share this page. **A retail user** (channel installed from the
Channel Store, no developer mode) can read a real diagnostic surface inside the
app — see [Support playbook](#support-playbook). **A developer** with a
dev-mode device has the telnet console and the ECP router — see
[Developer surfaces](#developer-surfaces). Earlier revisions of this page
described only the developer path and described parts of it wrongly; the
corrections are called out inline so the old claims cannot be re-imported.

---

## Support playbook

### What a retail user can actually do (no dev mode, no computer)

**Settings → Version (the About entry).** Selecting it prints the build
identity and the diagnostic tail in the panel on the right. Everything there is
read from firmware or from this run's memory — nothing is a hardcoded string:

| Line | Source | Notes |
|------|--------|-------|
| `Version: x.y.z` | `roAppInfo.GetVersion()` | the stamped manifest `major.minor.build`, i.e. the installed channel version |
| `Device Model` / `Device ID` | `roDeviceInfo.GetModel()`, the stored `GetChannelClientId()` | model number and the per-channel persistent client id |
| `Channel ID: …` | `roAppInfo.GetID()` | store channel id, or `dev` for a sideload |
| `Roku OS: a.b.c (build)` | `roDeviceInfo.GetOSVersion()` | all four firmware fields, uninterpreted |
| `Video Mode` / `Total Memory` | `GetVideoMode()`, `GetDeviceInfo().totalMemoryMB` | display resolution and device RAM |
| `Previous run:` + `Exit code: … at …` | `roAppManager.GetLastExitInfo()` | **Roku OS 13.0+ only.** Why the last run ended; `No abnormal exit recorded` when the firmware has nothing to report |
| `Recent errors:` + up to 5 lines | this run's render-thread ring | `{index}. {kind} (+{elapsed}s): {detail}` |

The ring is **memory, not a log file**: it holds the last 12 failures recorded
on the render thread (max 5 shown), and it is empty right after a launch. It
records the boot auth ladder (`PhlixApp.HandleBootAuthFailure`) and the Settings
server calls that used to be reported as a fixed sentence with the real reason
discarded (`SettingsScene.OnApiResponse` failure arms). Because BrightScript
function state is per-thread, RSG task threads do **not** feed it — the
cross-run story comes from the OS-side exit record instead, which is exactly
what survives a crash and is readable from the next run.

Useful exit codes are the memory-related ones the OS reports —
`EXIT_CHANNEL_MEM_LIMIT_FG`, `EXIT_CHANNEL_MEM_LIMIT_BG`, `EXIT_OUT_OF_MEMORY`,
`EXIT_AM_LOWRESOURCE`, `EXIT_SYSTEM_KILL`, and `EXIT_UNKNOWN` as the default
([developer.roku.com/dev/docs/dev-environment#lastexitorterminationreason-parameter](https://developer.roku.com/dev/docs/dev-environment#lastexitorterminationreason-parameter),
live 2026-10-29).

So the retail flow is: **reproduce the problem, open Settings → Version, read or
photograph the panel, and report the `Version`, `Channel ID`, `Exit code` and
`Recent errors` lines.** Restarting the player refreshes the OS-side record; it
clears the in-memory ring (expected, not a defect).

What a retail user *cannot* do: capture console prints, read a log file, or
send anything to us. There is **no remote telemetry in this client** — no
crash-report endpoint, no analytics call, nothing uploaded beyond the API
requests the feature itself makes. The version header below is the only
*build-identity* diagnostic the wire carries, and it only reaches the Phlix
server the user chose to connect to.

### The server-side half of the story

Every HTTP request this channel issues through its `ApiClient` transport
carries `X-Phlix-Client-Version: <roAppInfo.GetVersion()>` alongside the
existing `X-Phlix-Device-ID/-Name/-Type` and `X-Phlix-Session-ID` headers —
all three `ApiClient` send sites (`sendRaw`, `sendRawWithDeviceId`,
`resolveLocation`). Honest scope: the hub relay-token mint
(`HubCommandTask.MintRelayToken`, a `roUrlTransfer` of its own) and the two
SyncPlay WS upgrade handshakes (`SyncPlayProtocol.BuildHandshakeRequest` over
a raw socket) also carry `X-Phlix-Client-Version` — the mint stamps it on its
`POST` and the dials put it in their handshake maps (`SyncPlayTask` builds
its `extraHeaders` upgrade map unconditionally), valued by the
AppContext-free leaf `ProtocolChannelVersion()` (roAppInfo, `unknown`
degradation) in `SyncPlayProtocol.brs`, because task-thread scopes cannot see
`AppContext`. `probeHealth` stays header-free deliberately: it probes
arbitrary candidate origins before the user has chosen one. CHECK 44 pins the
dial sites, the leaf's roAppInfo source and AppContext-free shape, and the
`WireErrorText` type guard on every wire error lift (a hostile non-String
`error` body degrades to the caller's typed fallback instead of raising at a
String sink).
Adding a header is wire-safe: the server reads headers selectively
(`$request->getHeader(...)`), so an unrecognized `X-Phlix-*` header is simply
not consumed — there is no whitelist that strips it, and no new error code or
route is involved. A self-hosted operator who logs request headers can
therefore see which channel build a device runs. CHECK 42 pins that all three
sites keep the header and that its value never comes from a literal.

Honest scope: the server has a client-telemetry store
(`src/Stats/ClientHeartbeatStoreInterface.php`, with `MAX_VERSION_LENGTH`,
`MAX_CLIENT_TYPE_LENGTH`, `MAX_BUILD_TOKEN_LENGTH` — landing today through the
QuickConnect PIN-login flow). The Roku channel authenticates via `/auth/login`,
not QuickConnect, so **this lane does not write heartbeat rows**; the header is
available to header-logging operators, and wiring the channel into the
heartbeat store is a separate server-contract item, not something invented here.

---

## Developer surfaces

### The console (telnet, port 8080) — requires developer mode

```bash
telnet <roku-ip> 8080
```

The console streams output **from the moment the socket connects**: text
printed before you attached is gone and is never replayed. To see the earliest
frames, connect first and *then* launch the channel (`make launch`, or
`POST /launch/dev` below).

- The old claim that "the channel must be running (or launching) when you
  connect" is wrong — the port answers whether or not a channel is up, and
  connecting while a channel is already running is precisely the case where
  you miss startup output.
- Console output requires a **developer-mode** device with the channel
  sideloaded (`make install`). A store-installed Phlix channel has no console
  reachable by the user.
- `print` from a task thread and from the render thread interleave on this
  stream, so timing-looking output may not reflect scene-thread ordering.
- The last-exit record's `console_log` field is **not** available to Phlix: per
  [developer.roku.com/dev/docs/ifappmanager](https://developer.roku.com/dev/docs/ifappmanager)
  (live 2026-10-29) the last 20 console lines are only recorded for channels
  whose manifest sets `run_as_process=1`. This manifest does not set it, so
  `GetLastExitInfo()` gives the exit code/timestamp/state without console text.

### Temporary debug output

`print` is the mechanism; nothing else exists on-device. `make lint` does
**not** enforce anything about it — the bslint config in this repo sets
`"no-print": "off"` (see `bslint.json`), so prints are permitted by the gate.
The rule to remove them is a code-review convention of this project, not a
build failure. (The previous revision of this page asserted that `make lint`
rejects `console.log` — no such rule exists; `console.log` is not BrightScript
at all.)

```brightscript
print "DEBUG: value = "; someValue
```

### ECP router (port 8060) — requires developer mode

Useful for driving the channel without a remote:

| Endpoint | Purpose |
|----------|---------|
| `GET /query/device-info` | Device information |
| `POST /launch/dev` | Launch developer channel |
| `POST /input` | Send input events |
| `POST /keypress/<key>` | Send keypresses (e.g. `/keypress/home`, `/keypress/play`) |

```bash
# Launch the channel
curl -X POST "http://$ROKU_IP:8060/launch/dev?contentId=&t="

# Send a keypress
curl -X POST http://$ROKU_IP:8060/keypress/play
```

`make install`, `make launch` and `make stop` wrap the same router calls with
the `ROKU_IP` / `ROKU_DEV` / `ROKU_PASSWORD` variables.

---

## Error Dictionary

### &hEC — Dot operator on non-object

**Message:** `Dot operator attempted with invalid left-hand side`

**Meaning:** Calling a method or property on a value that is not an object. This was the `Storage` factory bug (R0.2).

**Cause:** `Storage` is a factory function. `Storage.get("x")` throws `&hEC`; use `GetStorage().get("x")`.

**Guarded by:** CHECK 1 in `scripts/verify-runtime.sh`

---

### &hF4 — Member function not found

**Message:** `Member function not found in BrightScript Component or interface`

**Meaning:** Calling a method that the target node type does not declare.

**Cause:** `m.top.Close()` on Scene nodes — `Close()` belongs to `roSGScreen`, not `Scene`. Use the `requestClose` field instead (R0.4).

**Guarded by:** CHECK 2 in `scripts/verify-runtime.sh`

**Also reachable by scope, not just by type:** a function defined in one
component's script list is not visible from another. `IIF` in this project is a
**local** helper inside `components/SettingsScene.brs`, not the firmware global
— `bsc` resolves it in that scope only and reports `BS1140 Cannot find function
'IIF'` everywhere else. Code in `source/lib/` therefore uses explicit
`if`/`else` branches (see `ChannelInfo` in `source/lib/AppContext.brs`).

---

### Silent no-op — field assignment does nothing

**Message:** *(none — silently ignored)*

**Meaning:** Assigning to a field that does not exist on a SceneGraph node silently does nothing. No error is thrown.

**Cause:** This was `Video.subtitleTrack` — the field is `currentSubtitleTrack` (R6.6).

**How to detect:** Read the field back and compare:
```brightscript
m.videoPlayer.subtitleTrack = "1"
if m.videoPlayer.subtitleTrack <> "1" then
    print "field does not exist or is read-only"
end if
```

**Guarded by:** CHECK 8 in `scripts/verify-runtime.sh` (invalid Video fields)

---

### Observer callback never fires

**Message:** *(silent — the callback simply doesn't fire)*

**Meaning:** The observer is registered but the callback function name doesn't resolve in the component's scope.

**Cause:** `ObserveField("x", "OnFoo")` — if `OnFoo` isn't defined in the component, the observer fires nothing.

**How to detect:** The field changes but nothing happens.

**Guarded by:** CHECK 6 in `scripts/verify-runtime.sh` (ObserveField callback missing)

---

### Frozen UI — render-thread network call

**Message:** *(UI becomes unresponsive for up to 35 seconds)*

**Meaning:** A blocking network call on the render thread. `ApiClient` uses `wait(35000)` internally.

**Cause:** Calling `ApiClient` methods directly from a scene instead of dispatching to an `ApiTask`. Fixed in R1 — all network I/O now goes through `ApiTask`.

**How to detect:** The UI freezes; pressing any key does nothing.

**Guarded by:** CHECK 10 in `scripts/verify-runtime.sh` (render-thread network)
— and it is why the diagnostics ring is fed only at render-thread sites.

---

## Static check coverage

The full register (all 42 checks, defect class, audit source, leg-by-leg
description, and the red-proof each one carries) lives in
[docs/static-checks.md](static-checks.md). Representative entries:

| Error Class | Static Check | File |
|-------------|-------------|------|
| Storage misuse (`&hEC`) | CHECK 1 | `scripts/verify-runtime.sh` |
| `m.top.Close()` (`&hF4`) | CHECK 2 | `scripts/verify-runtime.sh` |
| Invalid PosterGrid fields | CHECK 4 | `scripts/verify-runtime.sh` |
| Invalid `halign=` attribute | CHECK 5 | `scripts/verify-runtime.sh` |
| Missing ObserveField callback | CHECK 6 | `scripts/verify-runtime.sh` |
| Missing FindNode target | CHECK 7 | `scripts/verify-runtime.sh` |
| Invalid Video fields | CHECK 8 | `scripts/verify-runtime.sh` |
| Invalid Roku key names | CHECK 9 | `scripts/verify-runtime.sh` |
| Render-thread network | CHECK 10 | `scripts/verify-runtime.sh` |
| Unguarded Task control=run | CHECK 11 | `scripts/verify-runtime.sh` |
| Version header / diagnostics surface drift | CHECK 42 | `scripts/verify-runtime.sh` |
