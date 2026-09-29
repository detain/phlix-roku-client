# The API Envelope Law

Status: binding for every reader of `ApiClient` responses.
Machine-enforced by **CHECK 26** (`make verify-runtime`) and
`tests/unit/ApiEnvelope.test.brs`; the law block also ships in-channel as a
docblock in `source/lib/ApiClient.brs` (this directory is not part of the
zip).

## Why this exists

Commit `2c119f9` (2026-08-04) changed `ApiClient.request()` from returning the
raw parsed JSON body to returning a **transport envelope**:

```brightscript
{
    status: Integer   ' HTTP response code; 0 = transport failure
    ok: Boolean       ' true only for 200-299
    data: Object      ' THE SERVER PAYLOAD (raw JSON body), invalid when absent
    error: String     ' "" | "connect" | "timeout" | server {error} | "http_NNN"
}
```

It updated **zero** consumers. Every feature that read a server field straight
off what used to be the body silently started reading `invalid` off the
envelope: Home rails (`libraries`), episode lists (`items`), hub detection
(`servers`), the Live TV guide/recordings/channels lists, SyncPlay group
lists, login error surfaces, session creation, audiobook lists — all dead, all
quietly. That bug class — *silent empty render* — is what this law forbids.

## The law

1. **One unwrap, at one choke.** The envelope is peeled exactly once per hop,
   by `UnwrapApiEnvelope(env)` (`source/lib/ApiClient.brs`):

   ```brightscript
   function UnwrapApiEnvelope(env as Object) as Object
   ```

   - `invalid` → `invalid`
   - non-assocarray → returned unchanged (safe for pre-unwrapped helpers)
   - assocarray carrying **both** `status` **and** `ok` → returns `env.data`
     (the server payload; may itself be `invalid` on failure)
   - anything else → returned unchanged (a payload from a helper that already
     drilled the envelope, e.g. `getMe`)

2. **Honor `ok` before touching the payload.** Unwrapping is not enough — a
   failed request carries `data = invalid`. Guard on `env.ok` (or
   `resp.ok` at scene level) and **surface the failure honestly** (status UI,
   error dialog, `m.top.ok = false`). Never fall through to an empty render
   without a reason the user or a log can see.

3. **Scenes never see the transport envelope.** `components/ApiTask.brs` is
   the single choke for the scene layer: every branch routes the ApiClient
   result through `ApplyEnvelope(result, env)` before publishing
   `m.top.response`. A scene's contract is therefore fixed:

   ```brightscript
   sub OnApiResponse(event as Object)
       resp = event.GetData()              ' {op, ok, data, error, requestId?}
       if resp = invalid or not resp.ok then
           ' ... show the error, keep the UI honest ...
           return
       end if
       ' resp.data IS the server payload - read its keys directly:
       items = resp.data.items
   end sub
   ```

4. **Named conventions (CHECK 26 keys off these).** A variable holding a
   transport envelope is named `env` (or `cachedResp` in the ApiTask cache
   paths); a variable holding an unwrapped server payload is named `payload`.
   Server payload keys are **never** read off `env.` / `resp.` / `result.` /
   `raw.` / bare `data.` — the checker fails those fingerprints red.

## Choke map

| Layer | Handled by | Result shape |
|---|---|---|
| Transport | `ApiClient.request()` | envelope `{status, ok, data, error}` |
| Convenience getters | `ApiClient.getLibraries/getItem/getAudiobook/getMe/...` | already-unwrapped payload (`invalid`/`[]` on failure), via `UnwrapApiEnvelope` behind `env.ok` |
| Login | `ApiClient.login()` | envelope like `request()` — note: **no `success` key exists** on the server or hub login body; the verdict is `ok` (server login returns `{access_token, refresh_token, token_type, expires_in, user}`) |
| Task boundary | `ApiTask` `ApplyEnvelope()` | task `response.data` = server payload, `response.ok` = HTTP verdict |
| Direct-call tasks | `ListTask`, `EpisodeListTask`, `SyncPlayManager` | unwrap with `UnwrapApiEnvelope` + `env.ok` guard locally (they skip the ApiTask hop) |
| Scenes | read `resp.ok` + `resp.data.<serverKey>` only | — |

### Documented exceptions

- **`getLibraries` op** publishes `response.data` as the **libraries array**
  (drills one level at the choke because both consumers — `HomeScene`,
  `LibraryAdminScene` — bind `resp.data` directly to an array).
- **`getItem` op** likewise publishes the **item object** itself.
- **`checkAuth` / `checkAuthHub`** publish `api.user` (already payload-level;
  `restoreSession()` unwraps internally).
- **`probeHealth`** returns the raw `/health` JSON by design — it does not go
  through `request()` at all (public unauthenticated endpoint, own transport).
- **`getChannelStreamUrl`** synthesizes `{stream_url: String}` (header
  resolution, not a JSON body).
- **`getMyServers`**: `GET /me/servers` exists only on a hub; a **direct**
  server answers 404, which is the expected "no hub" signal, so the task maps
  404 to `ok = true, data = {}` (no servers) instead of an error. Any other
  failure stays red so `LoginScene`/`ServerPickerScene` surface it.
- **Admin dashboard payloads** are double-`data` **by contract**:
  `resp.data.data` at scene level is correct — the outer `data` is the task
  response's payload slot, the inner `data` is the server's own
  `{success, data, count}` admin envelope (`DashboardScene.ExtractData`).
- **`/media/facets`, letter-index, playback preferences, watch-history
  clear** were already unwrapped at the task pre-law; they now go through
  `ApplyEnvelope` for uniformity (scene-visible shape unchanged).

## Good / bad

```brightscript
' GOOD - unwrap once, honor ok, fail loud
env = api.getGuide()
if env = invalid or not env.ok then
    m.top.ok = false                    ' honest failure; UI shows a reason
    return
end if
payload = UnwrapApiEnvelope(env)
if payload = invalid or payload.programs = invalid then
    m.top.ok = false
    return
end if

' BAD - the exact 2c119f9 regression (reads the envelope as if it were the body)
data = api.getGuide()
if data = invalid or data.programs = invalid then     ' programs never exists here
    m.top.items = []                                   ' silent empty render
    m.top.ok = false
    return
end if
```

## Enforcement

- **CHECK 26** (`scripts/verify-runtime.sh`, run by `make verify-runtime`):
  greps shipped `source/` + `components/` code (comments and string literals
  excluded) for the R1 fingerprint regex above, requires every
  `result.data =` assignment in `ApiTask.brs` to come from an unwrap or a
  documented exception, and requires the law artifacts (`ApplyEnvelope` in
  `ApiTask.brs`, `ENVELOPE LAW` + `UnwrapApiEnvelope` in `ApiClient.brs`) to
  exist. Its regression leg in `tests/scripts/verify-runtime-portable.sh`
  plants a `resp.libraries` read in a scratch `DetailScene.brs` and proves the
  check goes red while every other gate stays green.
- **`tests/unit/ApiEnvelope.test.brs`** pins the helper semantics (device-run
  via rooibos).
