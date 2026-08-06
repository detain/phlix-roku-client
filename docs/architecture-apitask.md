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
      |                                    |                  error, status}
      |  observe "response" <------------ |                               |
      |  OnApiResponse()                  |                               |
```

**Rule:** The Task thread may ONLY read `m.top.request` and write `m.top.response`. It must NOT touch UI nodes or parent scene references. Only assocarray/string/number crosses the thread boundary.

---

## The Response Envelope

After R3.3, every API response uses this shape:

| Field | Type | Description |
|-------|------|-------------|
| `op` | String | The operation that was run (e.g. `"getLibrary"`, `"login"`) |
| `ok` | Boolean | Derived from HTTP status — `true` for 2xx, `false` otherwise. **Not** from whether `data` is non-invalid |
| `data` | Object | Parsed JSON response body, or `invalid` on parse failure |
| `error` | String | Human-readable error message when `ok` is `false` |
| `status` | Integer | Raw HTTP status code |

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

2. **Add to `ApiTask.brs:33-241`** — add an `if op = "myop" then` branch:
   ```brightscript
   else if op = "myop"
       m.top.response = m.api.myMethod(params)
   end if
   ```

3. **Return the correct envelope** — `ApiClient` methods return `{op, ok, data, error, status}` automatically

4. **Dispatch from the scene** — set `m.top.request = {op: "myop", params: {...}}`, observe `response`, handle the three outcomes

---

## The 70-Branch Dispatch (Known Scaling Problem)

`ApiTask.brs:33-241` is a 70-branch if/else chain. A table dispatch would be better:

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

Do not refactor in this step — just note the problem.

---

## R5.9 Response Cache

`ApiTask` maintains a bounded LRU cache (60-second TTL) scoped to the Task's `m.api` instance. Cache hits avoid redundant network round-trips when re-entering the same library within a short window.

**Excluded from cache** (always fetch fresh):
- `getItemPlaybackInfo` — highly dynamic with position/user seek
- `createSession`, `reportProgress`, `completeSession` — mutate server state
- `probeHealth` — must reflect current connectivity state
- `checkAuth`, `checkAuthHub`, `login`, `logout` — auth state

---

## Links

- `DEVELOPER.md` — broader architecture context
- `source/lib/ApiClient.brs` — the HTTP transport
- `components/ApiTask.brs` — the Task implementation
