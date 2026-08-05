# Device Verification Procedure

This document records the first-boot verification procedure for the Phlix Roku channel.

## Numbered First-Boot Procedure

1. **Enable Developer Mode** on the target Roku device:
   - Navigate to Settings → System → About → Developer Options (or press the key sequence to enter developer mode)
   - Enable Developer Mode and note the device IP address

2. **Package the channel** on the development machine:
   ```bash
   cd /home/sites/phlix/phlix-roku-client
   make package
   ```
   This produces a zip file at `out/phlix-roku-client.zip` (or similar path).

3. **Sideload the channel**:
   - From a browser on the same network as the Roku, navigate to:
     ```
     http://<roku-ip>/plugin_install
     ```
   - Upload the zip file from step 2.

4. **Open telnet before launching** to capture the first frame:
   ```bash
   telnet <roku-ip> 8080
   ```
   Leave this terminal open. All BrightScript console output will appear here.

5. **Launch the Phlix channel** from the Roku home screen.

6. **Capture first-frame output**: Record everything printed to the telnet console from channel launch through initial render.

7. **Test §5.2 (`m.top.Close()`)**: Press Back from the home screen. Navigate into a library view, then press Back again to exit. Capture all console output.

8. **Test certification item 6 (Back exits at root)**: From the home screen (root), press Back.
   The channel must exit — the Roku home screen must appear. If the channel stays open or
   shows an error, cert item 6 is not satisfied. Capture all console output.

9. **Save the console output** to `docs/first-boot-console.log`.

## Known Defects to Look For

### §5.1 — `Storage` Factory Runtime Error

**Error code:** `&hEC` ("Dot operator attempted with invalid left-hand side")

**What it means:** The `Storage.brs` factory at line 15 returns an object, but approximately 40 call sites treat the function value itself as that object. This causes a runtime error on the first frame of `PhlixApp.Init`.

**When to expect it:** On the first frame immediately after channel launch.

**How to confirm it's cleared:** The channel renders the home screen without this error appearing in the telnet console.

---

### §5.2 — `m.top.Close()` Member Function Not Found (FIXED R0.4)

**Error code:** `&hF4` ("Member function not found in BrightScript Component or interface")

**What it means:** Code calls `m.top.Close()` on a node that does not have a `Close()` method. This is a SceneGraph API misuse — `Close()` is not a valid method on `Scene` or `Group` nodes.

**When to expect it (pre-R0.4):** On the first Back press from the home screen or when exiting a library view.

**Status:** Fixed in R0.4. All 34 call sites were migrated to `m.top.requestClose = true`. The `requestClose` field was added to all relevant component XMLs and the 8 primary parent scenes (HomeScene, FavoritesScene, MusicScene, AdminScene, CollectionsScene, DetailScene, LibraryAdminScene, LiveTvScene) are wired with `ObserveField("requestClose", "OnChildRequestClose")`.

**How to confirm it's cleared:** Navigate into any pushed screen (Library, Detail, etc.) and press Back. The channel navigates back cleanly with no `&hF4` error in the telnet console. A residual ~13 parent scenes are not wired (see the Known Limitation note in CHANGELOG.md) — if you encounter a branch that silently ignores Back, that is an un-wired scene, not the `&hF4` error.

---

### §5.3 — Back at root does not exit channel (certification item 6)

**What it means:** The back-handler in `PhlixApp.OnKeyEvent` always returned `true` (handled) even when the screen stack was empty, preventing the Roku OS from handling the back press and exiting the channel. Users were stuck on the home screen.

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
     be used. `Storage.invalidateAll()` was called on the server switch.
4. **Logout**:
   - Log out. Confirm the channel returns to the login screen immediately (local
     state cleared first, then server-side `DELETE /sessions` fires off-thread).
   - Power-cycle. Re-launch. Confirm the channel does **not** restore the old session
     — `Storage.flush()` was called before clearing keys on logout.

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

### Current Asset State (as of R6.2 audit)

| File | Size | Dimensions | Bit Depth | Status |
|------|------|------------|-----------|--------|
| `images/icon-focus-hd.png` | 6,917 B | 540×405 | 16-bit RGB | **Wrong dimensions** — should be 290×218; placeholder quality |
| `images/icon-focus-sd.png` | — | — | — | **Missing** — referenced in manifest but not present |
| `images/icon-side-hd.png` | 166 B | 175×29 | 1-bit colormap | **Placeholder** — trivially small |
| `images/splash-sd.png` | 237 B | 960×540 | 1-bit colormap | **Placeholder** — 1-bit cannot be real art |
| `images/splash-hd.png` | 286 B | 1,280×720 | 1-bit colormap | **Placeholder** — 1-bit cannot be real art |
| `images/splash-fhd.png` | 426 B | 1,920×1,080 | 1-bit colormap | **Placeholder** — 1-bit cannot be real art |
| `images/placeholder.png` | 186 B | 280×380 | 1-bit colormap | **Not referenced** in manifest; discard |

### Static Verification

`make verify-runtime` Check 16 validates that every PNG in `images/` is large enough to plausibly contain real art at its pixel dimensions (bytes ≥ width × height × 0.5). This catches all current placeholders immediately.

### What Must Be Commissioned

The following must be designed and supplied as 24-bit PNG files before the channel can pass art review:

1. **HD Channel Icon (290×218)** — the primary store listing image; must contain the Phlix wordmark or symbol on a solid or gradient background
2. **SD Channel Icon (246×140)** — scaled variant of the HD icon
3. **Side Icon (176×110)** — smaller variant for channel guide sidebar
4. **Splash Screen HD (1,280×720)** — branded splash with Phlix logo; background color `#1a1a2e` is already declared in the manifest
5. **Splash Screen FHD (1,920×1,080)** — same design at 1080p
6. **Splash Screen SD (720×480)** — same design at 480p

**Important:** Do not generate placeholder art that "looks better" — it will still fail Roku's automated art validation. Real bitmap assets must be commissioned from a designer.

### Post-Commissioning Checklist

- [ ] All 6 PNG files exist in `images/` with correct dimensions
- [ ] All files pass `make verify-runtime` Check 16 (size validation)
- [ ] `make validate-manifest` confirms all declared assets are present
- [ ] `npx bsc --project bsconfig.json` is clean
- [ ] Channel is sideloaded and visually verified on a real Roku device

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

## Status

| Defect | Status | Notes |
|--------|--------|-------|
| §5.1 `Storage` factory (`&hEC`) | NOT REACHED | No device available for testing |
| §5.2 `m.top.Close()` (`&hF4`) | FIXED R0.4 | Code migrated; device smoke test still recommended for un-wired branches |
| §5.3 Back at root (`&h06` / cert item 6) | NOT REACHED | No device available for testing |
| R1.1 Boot auth async | NOT REACHED | No device available for testing |
| R1.2 Login async | NOT REACHED | No device available for testing |
| R1.6 Storage caching | NOT REACHED | No device available for testing |
| R6.2 Channel art | ART COMMISSION NEEDED | No Phlix brand assets exist; all images are placeholders (1-bit, tiny, or wrong dimensions); see §R6.2 Channel Art Review above |
| R6.3 Cold-launch deep linking | IMPLEMENTED | main.brs reads args.contentId/args.mediaType, validates contentId, routes based on mediaType; unauthenticated and not-found cases handled; ECP test commands documented in device-verification.md |
| R6.4 Warm deep linking via roInput | IMPLEMENTED | main.brs creates roInput and handles roInputEvent in main message loop; shared validation/routing with R6.3 (ExtractDeepLinkParams); supports_input_launch=1 added to manifest; mid-playback deep links stop playback cleanly per R4.4 before navigating; ECP `input` commands documented in device-verification.md |

*This document was created because `ROKU_HOST` is unset — no physical hardware was available for sideload verification.*
