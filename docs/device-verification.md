# Device Verification Procedure

This document records the first-boot verification procedure for the Phlix Roku channel.

## Numbered First-Boot Procedure

1. **Enable Developer Mode** on the target Roku device. There is no Settings-menu path
   for this — Roku has no "Developer Options" screen (that's Android lore). On the
   device remote press the key sequence: **Home ×3, Up ×2, Right, Left, Right, Left,
   Right** (README §1 "Enable Developer Mode" documents the same flow). The Developer
   Settings screen appears: note the device IP address shown, enable the Development
   Application Installer, accept the Developer Tools License Agreement, and set a
   device password — the device reboots with the installer page at `http://<roku-ip>/`
   live.

2. **Package the channel** on the development machine:
   ```bash
   cd /home/sites/phlix/phlix-roku-client
   make package
   ```
   This produces `phlix.zip` in the **repo root** — the Makefile's `PKG_NAME` is
   `phlix` and the `package` target writes the archive in front of itself (no `out/`
   directory exists). The recipe zips `source/ components/ images/ locale/` and then
   `zip -j` adds the version-derived manifest as a bare root member, and the target
   ends by opening its own output through `scripts/verify-package.sh`, so a
   structurally invalid zip fails the build loudly.

3. **Sideload the channel**:
   - From a browser on the same network as the Roku, navigate to:
     ```
     http://<roku-ip>/plugin_install
     ```
   - Upload the zip file from step 2.

4. **Open telnet before launching** to capture the first frame. The Roku BrightScript
   debug console listens on **port 8085** (8080 is not the console port):
   ```bash
   telnet <roku-ip> 8085
   ```
   Leave this terminal open. All BrightScript console output will appear here.

5. **Launch the Phlix channel** from the Roku home screen.

6. **Capture first-frame output**: Record everything printed to the telnet console from channel launch through initial render.

7. **Test §5.2 (`m.top.Close()`)**: Press Back from the home screen. Navigate into a library view, then press Back again to exit. Capture all console output.

8. **Test certification item 6 (Back exits at root)**: From the home screen (root), press Back.
   The channel must exit — the Roku home screen must appear. If the channel stays open or
   shows an error, cert item 6 is not satisfied. Capture all console output.

9. **Save the console output** — attach the full capture to the verification ticket.
   (Do not write it into the tree: an earlier revision of this doc said "save to
   `docs/first-boot-console.log`", a file that has never existed in this repo. The
   ticket attachment is the baseline that `docs/BLOCKED_R0.8.md` re-verification runs
   diff against.)

## Known Defects to Look For

### §5.1 — `Storage` Factory Runtime Error (FIXED R0.2)

**Error code:** `&hEC` ("Dot operator attempted with invalid left-hand side")

**What it meant (pre-R0.2):** The `Storage` factory returns an object, but roughly 40
call sites at the time treated the function value itself as that object — writing
`Storage.get("x")` instead of `GetStorage().get("x")`. That throws a runtime error on
the first frame of `PhlixApp.Init`.

**When to expect it (pre-R0.2):** On the first frame immediately after channel launch.

**Status:** Fixed in R0.2. Every storage call site now goes through `GetStorage()`
(`source/lib/Storage.brs`), and the misuse is statically gated: `make verify-runtime`
CHECK 1 fails on any direct `Storage.factory`-style use. `docs/BLOCKED_R0.1.md` records
the grep verification.

**How to confirm it's cleared:** The channel renders the home screen without this error appearing in the telnet console.

---

### §5.2 — `m.top.Close()` Member Function Not Found (FIXED R0.4)

**Error code:** `&hF4` ("Member function not found in BrightScript Component or interface")

**What it means:** Code calls `m.top.Close()` on a node that does not have a `Close()` method. This is a SceneGraph API misuse — `Close()` is not a valid method on `Scene` or `Group` nodes.

**When to expect it (pre-R0.4):** On the first Back press from the home screen or when exiting a library view.

**Status:** Fixed in R0.4. All 34 call sites were migrated to `m.top.requestClose = true`. The `requestClose` field was added to all relevant component XMLs and the 8 primary parent scenes (HomeScene, FavoritesScene, MusicScene, AdminScene, CollectionsScene, DetailScene, LibraryAdminScene, LiveTvScene) are wired with `ObserveField("requestClose", "OnChildRequestClose")`.

**How to confirm it's cleared:** Navigate into any pushed screen (Library, Detail, etc.) and press Back. The channel navigates back cleanly with no `&hF4` error in the telnet console. Earlier revisions of this doc warned that "~13 parent scenes are not wired" — that caveat described the dead bubble-up contract (every parent handler re-raised `requestClose` and the chain died at HomeScene), which was cured 2026-10-28/29 (C03 + C03-r2): all parent handlers now remove the requesting child locally, and `scripts/verify-runtime.sh` CHECK27 pins both halves of the contract. The authoritative description is the "Back/Close contract" note under Known Limitations in `docs/navigation.md` — if Back is ever silently ignored on some branch again, that is a regression of that contract, not the `&hF4` error.

---

### §5.3 — Back at root does not exit channel (certification item 6)

**What it means:** The back-handler in `PhlixApp.OnKeyEvent` always returned `true` (handled) even when the screen stack was empty, preventing the Roku OS from handling the back press and exiting the channel. Users were stuck on the home screen.

**Status (code cure implemented, device test NOT REACHED):** `PhlixApp.OnKeyEvent` now pairs `handled = PopScreen()` with a `not handled` guard that raises `m.top.exitChannel` and consumes the key; `source/main.brs` observes `exitChannel` on the screen message port, its wait loop returns, and the channel exits (there is no `roApp.Exit()` in SceneGraph — exit-by-main-return is the platform primitive). `make verify-runtime` CHECK31 pins the arm. On-device confirmation still stands blocked (no hardware — `docs/BLOCKED_R0.1.md`).

**When to expect it:** Press Back from the home screen (or any root screen). The channel must exit and return to the Roku home screen.

**How to confirm it's cleared:** After navigating into a library or detail view and pressing Back until the stack is empty, one more Back press must exit the channel. The Roku home screen appears. No error in the telnet console.

---

## R1.1 Boot Auth Smoke Test

After R1.1 the boot sequence shows a "Loading…" label while session validation
runs on `ApiTask` (off the render thread). A 20-second timeout replaces the
previous render-thread block.

1. Launch the channel. Confirm the "Loading…" label appears **before** any
   network activity reaches the telnet console.
2. Wait for home screen. Authenticated session should resolve within a few
   seconds; confirm no render-thread blocking.
3. **Timeout test** (requires a unreachable server or firewall):
   - After 20 s the error group must appear with "Can't reach the server".
   - Press the **Retry** button. A new auth check should fire.
   - After 3 retries the message should escalate to "Unable to connect after
     multiple attempts".
4. **Hub mode**: Repeat steps 1–2 on a hub connection. The first boot should
   land on `ServerPickerScene` if no `active_server_id` is persisted.

## R1.2 Login Async Smoke Test

After R1.2 the login screen shows immediate feedback (button disabled, "Signing in…"
label) before the network request fires, and re-enables the button on every failure.

1. Open the login screen (`LoginScene`). Confirm the button is enabled and no
   status label is visible.
2. Press **Login** with valid credentials. Confirm:
   - Button is disabled **immediately** (before any network activity).
   - "Signing in…" (or equivalent) status label appears.
   - Home screen appears on success.
3. Press **Login** with **invalid credentials**. Confirm:
   - Button is disabled immediately.
   - Error message appears.
   - Button is **re-enabled** (can press Login again).
4. **Network-error path** (requires an unreachable server or firewall):
   - After the request fails, button must be re-enabled and an error label shown.
5. **Hub mode**: Repeat steps 1–2 on a hub connection. `getMyServers` chains
   correctly and `ServerPickerScene` appears if no `active_server_id` is persisted.

## R1.6 Storage Caching Smoke Test

After R1.6 the channel uses an in-memory cache for registry reads with batched
writes and explicit flush calls at sync points. Auth tokens (`auth_token`,
`refresh_token`, `session_id`, `device_id`) are still flushed immediately.

1. **Registry read reduction** (requires telnet console):
   - Start playback of any content and observe the telnet console for NVRAM read
     activity over 60 seconds. Before R1.6: ~149 reads. After R1.6: ~7 reads.
   - The progress-report tick (every 10 s) and transcode-poll tick (every 2 s) should
     produce no observable registry read activity.
2. **Auth-token durability**:
   - Log in successfully. Immediately power-cycle the device (or force-kill the
     channel via the Roku home menu). Re-launch.
   - Confirm the session was persisted — the channel should boot to the home screen
     without a login prompt. Auth tokens were flushed immediately on login.
3. **Server switch**:
   - Connect to Server A, log in, then switch to Server B via `ServerPickerScene`.
   - Confirm the new server's session is active and the old server's session cannot
     be used. `PhlixApp.OnServerPicked` calls `ResetCachedStorage(false)`, which clears
     the cached reads so the next `GetApiClient()` resolves the new `active_server_id`
     (the storage object's `invalidateAll()` member is not the server-switch path).
4. **Logout**:
   - Log out. Confirm the channel returns to the login screen immediately (local
     state cleared first, then server-side `DELETE /sessions` fires off-thread).
   - Power-cycle. Re-launch. Confirm the channel does **not** restore the old session
     — `PhlixApp.OnLogout` calls `ResetCachedStorage(true)`, which deletes exactly the
     six auth/session keys (`auth_token`, `refresh_token`, `session_id`,
     `connection_kind`, `active_server_id`, `active_server_name`) and then flushes the
     buffered deletes to the registry as one NVRAM write. `server_url` deliberately
     survives so you return to the login screen on the same hub/server (README law).

## R6.2 Channel Art Review

**Reference:** `client_missing.md` §3.1 — placeholder art assets (166–6,917 bytes) will fail Roku channel certification review.

### Required Channel Art Assets (per Roku specification)

| Asset | Manifest Key | Required Dimensions | Notes |
|-------|-------------|-------------------|-------|
| HD Channel Icon (focus) | `mm_icon_focus_hd` | **290 × 218 px** | Primary store listing icon |
| SD Channel Icon (focus) | `mm_icon_focus_sd` | **246 × 140 px** | SD store listing icon |
| Side Icon | `mm_icon_side_hd` | **176 × 110 px** | Channel guide sidebar |
| Splash Screen HD | `splash_screen_hd` | **1,280 × 720 px** | 720p TVs |
| Splash Screen FHD | — (not in manifest) | **1,920 × 1,080 px** | 1080p TVs |
| Splash Screen SD | `splash_screen_sd` | **720 × 480 px** | Legacy SD TVs |

Source: Roku Channel Store channel art requirements (290×218 HD icon, 246×140 SD icon, 176×110 side icon; splash screens at 1280×720 HD, 1920×1080 FHD, 720×480 SD).

### Asset State (measured at this commit — the original R6.2 audit table is superseded)

The audit-era placeholders (166–6,917 bytes, mostly 1-bit) were replaced by generated
channel art (`tools/gen_channel_art.py`, commits `47cfdb6` → `b625d15` → `326eb0d`;
see `docs/image_generation_info.md`). Every manifest-referenced asset now exists at the
exact Roku-spec dimensions as 8-bit RGB PNGs:

| File | Size | Dimensions | Manifest key | Status |
|------|------|------------|--------------|--------|
| `images/icon-focus-hd.png` | 51,879 B | 290×218 | `mm_icon_focus_hd` | Correct spec |
| `images/icon-focus-sd.png` | 32,586 B | 246×140 | `mm_icon_focus_sd` | Correct spec (earlier audits called it Missing — it exists) |
| `images/icon-side-hd.png` | 20,433 B | 176×110 | `mm_icon_side_hd` | Correct spec |
| `images/splash-hd.png` | 682,827 B | 1,280×720 | `splash_screen_hd` | Correct spec |
| `images/splash-fhd.png` | 1,441,342 B | 1,920×1,080 | `splash_screen_fhd` (manifest:12) | Correct spec |
| `images/splash-sd.png` | 276,935 B | 720×480 | `splash_screen_sd` | Correct spec |
| `images/placeholder.png` | 65,185 B | 280×380 | — (not a manifest key) | Live runtime poster fallback (`pkg:/images/placeholder.png` — CollectionScene/DetailScene `HDPosterUrl`); keep |

**Still open:** the shipped art is machine-generated, not designer-commissioned brand
work. It satisfies every structural contract (dimensions, bit depth, size floors,
manifest wiring) and passes `make verify-runtime` Check 16, but no static check can
judge Roku store art review on brand quality, and on-device visual confirmation
remains BLOCKED (no hardware — `docs/BLOCKED_R0.1.md`). Treat store art review as a
certification risk until a device pass and the store submission say otherwise.

### Static Verification

`make verify-runtime` Check 16 validates that every PNG in `images/` is large enough to plausibly contain real art at its pixel dimensions (bytes ≥ width × height × 0.5). This is what caught the original placeholders; the landed generated art satisfies it.

### Remaining Art Work (the six required assets now exist — see measured table above)

The structural checklist below is satisfied by `tools/gen_channel_art.py` output; what
remains is the part no script can do: replace or bless the generated designs with
Phlix brand art and have it survive Roku store review. The six spec slots:

1. **HD Channel Icon (290×218)** — the primary store listing image; must contain the Phlix wordmark or symbol on a solid or gradient background
2. **SD Channel Icon (246×140)** — scaled variant of the HD icon
3. **Side Icon (176×110)** — smaller variant for channel guide sidebar
4. **Splash Screen HD (1,280×720)** — branded splash with Phlix logo; background color `#1a1a2e` is already declared in the manifest
5. **Splash Screen FHD (1,920×1,080)** — same design at 1080p
6. **Splash Screen SD (720×480)** — same design at 480p

**Important:** Check 16 is a size floor, not a design judge — an asset can pass it and
still fail Roku's art review on brand quality. Re-generating ("it looks better") is not
a substitute for real design work before store submission.

### Post-Commissioning Checklist

- [x] All 6 PNG files exist in `images/` with correct dimensions (measured, this commit)
- [x] All files pass `make verify-runtime` Check 16 (size validation)
- [x] `make validate-manifest` confirms all declared assets are present
- [x] `npx bsc --project bsconfig.json` is clean
- [ ] Channel is sideloaded and visually verified on a real Roku device (BLOCKED — no hardware)

## R6.3 Cold-Launch Deep Linking

**Reference:** `client_missing.md` §2.3 and §3.2 — certification blocker. Deep linking
required for content catalog apps. Implementation in `source/main.brs` + `components/PhlixApp.brs`.

### Test Commands (ECP via cURL)

Roku's External Control Protocol (ECP) sends deep-link params on the launch URL.
The channel ID for a sideloaded dev channel is `dev`.

```bash
# Set your device IP
export ROKU_DEV_TARGET=192.168.1.XXX

# Test movie deep link (direct playback)
curl -d '' "http://$ROKU_DEV_TARGET:8060/launch/dev?contentId=movie123&mediaType=movie"

# Test episode deep link (direct playback)
curl -d '' "http://$ROKU_DEV_TARGET:8060/launch/dev?contentId=ep456&mediaType=episode"

# Test series deep link (smart bookmark - next unwatched or resume)
curl -d '' "http://$ROKU_DEV_TARGET:8060/launch/dev?contentId=series789&mediaType=series"

# Test season deep link (episode picker)
curl -d '' "http://$ROKU_DEV_TARGET:8060/launch/dev?contentId=season101&mediaType=season"

# Test short-form video deep link
curl -d '' "http://$ROKU_DEV_TARGET:8060/launch/dev?contentId=clip202&mediaType=shortformvideo"

# Test while app is already running (warm launch via input command)
curl -d '' "http://$ROKU_DEV_TARGET:8060/input?contentId=movie123&mediaType=movie"
```

### Expected Behaviors (per Roku deep-linking spec)

| mediaType | Expected behavior |
|-----------|------------------|
| movie | Direct playback, resume from bookmark if available |
| episode | Direct playback, resume from bookmark if available |
| series | Smart bookmark: next unwatched episode OR resume position |
| season | Episode picker showing the season's episodes |
| shortFormVideo | Direct playback |
| tvSpecial | Direct playback |

### Validation Checklist

- [ ] App launches to the correct content (not home screen) when deep-linked
- [ ] Unauthenticated deep link redirects to login, then resumes the deep link
- [ ] Invalid/unknown contentId shows a real dialog (R3.1), not a blank screen
- [ ] Invalid mediaType falls through to home screen gracefully
- [ ] ECP `launch` command from cold state works
- [ ] ECP `input` command from warm state (app already running) works
- [ ] **R6.4** Mid-playback deep link stops current playback cleanly (progress + completion reported per R4.4) before navigating
- [ ] **R6.4** `supports_input_launch=1` is present in manifest
- [ ] **R6.4** `roInput` is created and `roInputEvent` is handled in the main message loop

Source: [Roku Deep Linking Documentation](https://developer.roku.com/docs/developer-program/deep-linking)

## R6.5 Global Caption Mode

**Reference:** `client_missing.md` §3.3 — certification blocker. Zero references to
`globalCaptionMode`, `subtitleConfig`, `captionStyle`, or `availableSubtitleTracks`.

**Goal:** The channel respects the device's caption preference.

### Implementation

1. **Read device caption mode at player start** (`PlayerScene.Show()`):
   ```brightscript
   deviceInfo = CreateObject("roDeviceInfo")
   deviceCaptionMode = deviceInfo.GetCaptionsMode()
   m.videoPlayer.globalCaptionMode = deviceCaptionMode
   ```
   Per [Video node globalCaptionMode field](https://developer.roku.com/dev/docs/video):
   > "Sets the value of the global Roku closed-caption mode... The app should set the
   > `subtitleTrack` field regardless of the selected Caption Mode."

2. **Observe changes during playback**:
   ```brightscript
   m.videoPlayer.ObserveField("globalCaptionMode", "OnCaptionModeChanged")
   ```
   The user can change caption mode from the Roku system menu (**/Options/* key) during playback,
   and the channel follows via the observer.

3. **Channel-level toggle** (`PlayerScene.OpenCaptionModeList()`):
   Added "Caption Mode" as row index 2 in the settings panel (alongside Audio and Subtitles).
   Selecting a mode sets `m.videoPlayer.globalCaptionMode` for the session.

### Four Standard Modes (per Roku certification)

| Mode | Expected Behaviour |
|------|-------------------|
| **On** | Captions always visible when subtitle track is selected |
| **Off** | Captions never shown regardless of subtitle track |
| **Instant replay** | Captions shown only during instant replay (replay button rewinds 10-25s) |
| **When mute** | Captions shown only when volume is muted (Roku TVs only) |

### Validation Checklist

- [ ] `globalCaptionMode` is read from `roDeviceInfo.GetCaptionsMode()` at player start and applied to Video node
- [ ] Changes from Roku system menu (Options/* key) during playback are observed via `OnCaptionModeChanged`
- [ ] All four standard modes ("On", "Off", "Instant replay", "When mute") are offered in the channel toggle
- [ ] Channel-level toggle sets `m.videoPlayer.globalCaptionMode` for the session
- [ ] `roDeviceInfo.SetCaptionsMode()` is called to sync channel choice to system

Source: [Roku Closed Caption Documentation](https://developer.roku.com/en-us/docs/developer-program/core-concepts/closed-caption)

## Status

| Defect | Status | Notes |
|--------|--------|-------|
| §5.1 `Storage` factory (`&hEC`) | STATIC CLEARED | `make verify-runtime` CHECK 1 confirms no direct Storage.factory calls; device test BLOCKED (R0.1 — no hardware) |
| §5.2 `m.top.Close()` (`&hF4`) | STATIC CLEARED | `make verify-runtime` CHECK 2 confirms no m.top.Close() calls; 34 call sites migrated to m.top.requestClose; device smoke test BLOCKED (R0.1 — no hardware) |
| R0.1 Device verification | BLOCKED | Physical hardware required; static checks (CHECK 1, 2, 6) confirm code fixes in place; docs already existed from prior session |
| §5.3 Back at root (cert item 6) | CURE PINED, DEVICE NOT REACHED | exitChannel arm implemented; `make verify-runtime` CHECK31 pins it; no device available for testing (this row previously cited an error code `&h06` the defect never produced — removed as fabricated) |
| R1.1 Boot auth async | NOT REACHED | No device available for testing |
| R1.2 Login async | NOT REACHED | No device available for testing |
| R1.6 Storage caching | NOT REACHED | No device available for testing |
| R6.2 Channel art | STRUCTURAL PASS, BRAND REVIEW OPEN | All six manifest assets exist at exact spec dimensions as 8-bit RGB generated art (see §R6.2 measured table); store-quality review + device visual verification still pending — the old "all images are placeholders (1-bit, tiny, or wrong dimensions)" claim was superseded by `47cfdb6`→`326eb0d` |
| R6.3 Cold-launch deep linking | IMPLEMENTED | main.brs reads args.contentId/args.mediaType, validates contentId, routes based on mediaType; unauthenticated and not-found cases handled; ECP test commands documented in device-verification.md |
| R6.4 Warm deep linking via roInput | IMPLEMENTED | main.brs creates roInput and handles roInputEvent in main message loop; shared validation/routing with R6.3 (ExtractDeepLinkParams); supports_input_launch=1 added to manifest; mid-playback deep links stop playback cleanly per R4.4 before navigating; ECP `input` commands documented in device-verification.md |
| R6.5 Global caption mode | IMPLEMENTED | PlayerScene.Show() reads roDeviceInfo.GetCaptionsMode() and applies to m.videoPlayer.globalCaptionMode; OnCaptionModeChanged observer handles Roku menu changes during playback; OpenCaptionModeList() offers all four standard modes (On, Off, Instant replay, When mute); channel toggle syncs back via roDeviceInfo.SetCaptionsMode(); documented in device-verification.md |
| R6.6 Subtitle track selection | IMPLEMENTED | currentSubtitleTrack field applied per track selection; node's subtitleTracks array used as authoritative source; server-side id matched to node's TrackName; implemented in `components/PlayerScene.brs` (`OnSubtitleTrackSelected`) — there is no R6.6 section in this doc, only in `docs/certification.md` (row 4.3) |

*This document was created because `ROKU_HOST` is unset — no physical hardware was available for sideload verification.*
