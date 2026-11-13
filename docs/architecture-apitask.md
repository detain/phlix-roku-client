# ApiTask Architecture

## Why It Exists

`ApiClient` uses a bounded `wait(35000)` on every HTTP call. Calling `ApiClient` directly from a scene blocks the render thread — the UI freezes for up to 35 seconds. Every network call must be off the render thread.

`ApiTask` is a SceneGraph `Task` node that moves HTTP traffic to its own thread.

---

## The Threading Model

```
Scene (render thread)              ApiTask (task thread)          ApiClient / roUrlTransfer
      |                                    |                               |
      |  set m.top.request = {op, ...}     |                               |
      |  m.top.control = "run"  ---------> |                               |
      |                                    |  m.api.<method>(...) -------> |
      |                                    |                               |
      |                                    |  response = {op, ok, data,   |
      |                                    |                  error}
      |  observe "response" <------------ |                               |
      |  OnApiResponse()                  |                               |
```

**Rule:** The Task thread may ONLY read `m.top.request` and write `m.top.response`. It must NOT touch UI nodes or parent scene references. Only assocarray/string/number crosses the thread boundary.

---

## The Response Envelope

The scene-facing `m.top.response` (written by `ApiTask`) has this shape:

| Field | Type | Description |
|-------|------|-------------|
| `op` | String | The operation that was run (e.g. `"getLibraries"`, `"login"`) |
| `ok` | Boolean | Derived from the HTTP status of the transport envelope — `true` for 2xx, `false` otherwise. **Not** from whether `data` is non-invalid |
| `data` | Object | Server payload, unwrapped exactly once from the transport envelope (`invalid` on parse failure) |
| `error` | String | Human-readable error message when `ok` is `false` |

There is **no** `status` field on the task response. The raw HTTP `status` exists only on the
**transport envelope** `{status, ok, data, error}` returned by `ApiClient.request()`; `ApiTask`
folds it into the response via `ApplyEnvelope()` (`components/ApiTask.brs`). See
[api-envelope.md](api-envelope.md) for the envelope law.

**`ok` derivation (R3.3):**
```brightscript
ok = (status >= 200 and status < 300)
```
The original bug was deriving `ok` from whether `data <> invalid` — a 404 with an error JSON body would incorrectly set `ok = true`.

---

## The One-Outstanding-Run Rule

`control = "run"` on a Task that is **already running** is NOT additive — the second call is silently dropped.

Each scene that dispatches through `ApiTask` must observe this rule. R1.4 added a queueing wrapper: if the Task is busy, the request is queued and dispatched after the current response.

**When to use a second Task node:** If two independent operations can be in-flight simultaneously (e.g. a library load and a playback info request from the same scene), use separate `ApiTask` instances with different `id` attributes.

---

## How to Add a New Op

1. **Choose the op name** — string constant matching the server route (e.g. `"getWatchHistory"`)

2. **Add a branch inside `ExecRequest()` in `components/ApiTask.brs`** — the `req.op` chain runs
   from `getLibraries` (:330) to `logout` (:777); follow the shipped idiom (see `clearWatchHistory`):
   ```brightscript
   else if req.op = "myop" then
       env = api.myMethod(params)
       ApplyEnvelope(result, env)
   end if
   ```

3. **Return the correct envelope** — `ApiClient` methods return the transport envelope `{status, ok, data, error}`; route it through `ApplyEnvelope(result, env)` (see [api-envelope.md](api-envelope.md))

4. **Dispatch from the scene** — set `m.top.request = {op: "myop", params: {...}}`, observe `response`, handle the three outcomes

---

## The 82-Branch Dispatch (Known Scaling Problem)

The `req.op` chain inside `ExecRequest()` (`components/ApiTask.brs:330-777`) is an 82-branch if/else
chain (measured 2026-11-09 at `b6c20b2`; the file's :33-241 region is the cache-helper layer, not the
dispatch). A table dispatch would be better:

```brightscript
' Better: table-based dispatch
dispatch = {
    "getLibrary": sub(params) : return m.api.getLibrary(params) : end sub,
    "login": sub(params) : return m.api.login(params) : end sub,
    "checkAuth": sub(params) : return m.api.checkAuth(params) : end sub,
    ...
}
if dispatch.DoesExist(op) then
    dispatch[op](params)
end if
```

The shipped chain stays as-is: this document records the problem only. Any move to table dispatch would be a dedicated refactor — its own change, with its own review — never a drive-by edit folded into unrelated work.

---

## R5.9 Response Cache

`ApiTask` maintains a bounded LRU cache (60-second TTL) scoped to the Task's `m.api` instance. Cache hits avoid redundant network round-trips when re-entering the same library within a short window.

**Excluded from cache** (always fetch fresh):
- `getItemPlaybackInfo` — highly dynamic with position/user seek
- `createSession`, `reportProgress`, `completeSession` — mutate server state
- `probeHealth` — must reflect current connectivity state
- `checkAuth`, `checkAuthHub`, `login`, `logout` — auth state
- `saveAudiobookProgress` — progress mutation
- `getPlaybackPreferences` — must reflect the freshest server state after a PUT
- `clearWatchHistory` — mutation whose success the user must see confirmed on every press

(Authoritative list: `CacheShouldSkip()` in `components/ApiTask.brs`.)

---

## Links

- `DEVELOPER.md` — broader architecture context
- `source/lib/ApiClient.brs` — the HTTP transport
- `components/ApiTask.brs` — the Task implementation
