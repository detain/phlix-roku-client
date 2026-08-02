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

## Status

| Defect | Status | Notes |
|--------|--------|-------|
| §5.1 `Storage` factory (`&hEC`) | NOT REACHED | No device available for testing |
| §5.2 `m.top.Close()` (`&hF4`) | FIXED R0.4 | Code migrated; device smoke test still recommended for un-wired branches |
| §5.3 Back at root (`&h06` / cert item 6) | NOT REACHED | No device available for testing |
| R1.1 Boot auth async | NOT REACHED | No device available for testing |
| R1.2 Login async | NOT REACHED | No device available for testing |

*This document was created because `ROKU_HOST` is unset — no physical hardware was available for sideload verification.*
