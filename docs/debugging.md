# Roku Debugging Guide

## Reading the Console

Connect via telnet before launching the channel to capture the very first frame:

```bash
telnet <roku-ip> 8080
```

The channel must be running (or launching) when you connect — if you connect after launch you'll miss early errors.

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

---

## ECP Endpoints

Useful for testing without the UI:

| Endpoint | Purpose |
|----------|---------|
| `GET /query/device-info` | Device information |
| `POST /launch/dev` | Launch developer channel |
| `POST /input` | Send input events |
| `POST /keypress/<key>` | Send keypresses (e.g. `/keypress/home`, `/keypress/play`) |

```bash
# Launch the channel
curl -X POST http://$ROKU_IP:8060/launch/dev?contentId=&t=

# Send a keypress
curl -X POST http://$ROKU_IP:8060/keypress/play
```

---

## Adding Temporary Debug Output

Use `print` statements — they output to the telnet console. `make lint` rejects `console.log`.

```brightscript
print "DEBUG: value = "; someValue
```

Remove all debug prints before committing.

---

## Static Check Coverage

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
