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

8. **Save the console output** to `docs/first-boot-console.log`.

## Known Defects to Look For

### §5.1 — `Storage` Factory Runtime Error

**Error code:** `&hEC` ("Dot operator attempted with invalid left-hand side")

**What it means:** The `Storage.brs` factory at line 15 returns an object, but approximately 40 call sites treat the function value itself as that object. This causes a runtime error on the first frame of `PhlixApp.Init`.

**When to expect it:** On the first frame immediately after channel launch.

**How to confirm it's cleared:** The channel renders the home screen without this error appearing in the telnet console.

---

### §5.2 — `m.top.Close()` Member Function Not Found

**Error code:** `&hF4` ("Member function not found in BrightScript Component or interface")

**What it means:** Code calls `m.top.Close()` on a node that does not have a `Close()` method. This is a SceneGraph API misuse — `Close()` is not a valid method on `roList` or similar nodes.

**When to expect it:** On the first Back press from the home screen or when exiting a library view.

**How to confirm it's cleared:** The channel navigates back without this error appearing in the telnet console.

---

## Status

| Defect | Status | Notes |
|--------|--------|-------|
| §5.1 `Storage` factory (`&hEC`) | NOT REACHED | No device available for testing |
| §5.2 `m.top.Close()` (`&hF4`) | NOT REACHED | No device available for testing |

*This document was created because `ROKU_HOST` is unset — no physical hardware was available for sideload verification.*
