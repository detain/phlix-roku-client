' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ApiTask.brs

' copyright 2026 Joe Huss
'
'
'
' ===========================================
' ApiTask - generic SceneGraph Task node
' Runs ONE API operation on its own task thread so the blocking wait() in
' ApiClient.sendRaw no longer runs on the render thread. Scenes set the
' `request` assocarray, set control="run", and observe `response`.
'
' THREAD RULE: this function runs on the task thread; it may ONLY read its own
' m.top.request and write m.top.response. It must NOT touch UI/parent nodes.
' Only assocarray/string/number data crosses the thread boundary (ApiClient
' returns parsed-JSON assocarrays - safe).
'
' ENVELOPE LAW (docs/api-envelope.md): this task is THE single choke where a
' transport envelope {status,ok,data,error} from ApiClient.request()/login()
' is unwrapped - exactly once, via ApplyEnvelope below - before crossing to
' the render thread. Every branch answers with
'     { op, ok, data = SERVER PAYLOAD (or the documented key inside it),
'       error, requestId? }
' so scenes consume `resp.ok` + `resp.data.<serverKey>` and never touch
' transport framing. A branch that leaks the raw envelope re-introduces the
' silent-empty-render bug class 2c119f9 created; CHECK 26 reddens it.
' ===========================================

' R5.9: Response cache constants (Bounded LRU cache scoped to Task's m.api).
' TTL of 60 seconds reduces re-fetching when re-entering a library within a
' short window. Server does NOT send ETag/Last-Modified on API endpoints, so
' conditional requests (If-None-Match) are not possible — cache is TTL-only.

sub Init()
    m.top.functionName = "ExecRequest"
end sub

' ---------------------------------------------
' R5.9: Endpoints excluded from caching
' ---------------------------------------------
' Playback info: highly dynamic, changes with position, user seek, etc.
' Session endpoints: createSession, reportProgress, completeSession — these
'   mutate server-side state and should never be cached.
' Health probe: used for connectivity checks, must always reflect current state.
' Auth check: session validation must reflect current server state.
' ---------------------------------------------
function CacheShouldSkip(op as String) as Boolean
    if op = "getItemPlaybackInfo" return true
    if op = "createSession" return true
    if op = "reportProgress" return true
    if op = "completeSession" return true
    if op = "probeHealth" return true
    if op = "checkAuth" return true
    if op = "checkAuthHub" return true
    if op = "login" return true
    if op = "logout" return true
    if op = "saveAudiobookProgress" return true
    ' Settings mutations must never be cached: the preferences read must reflect
    ' the freshest server state after a PUT, and clearWatchHistory is a mutation
    ' whose success the user must see confirmed on every press.
    if op = "getPlaybackPreferences" return true
    if op = "clearWatchHistory" return true
    return false
end function

' ---------------------------------------------
' R5.9: LRU cache helpers (operate on m.api.m_responseCache)
' Each entry: { data: <response>, expiresAt: <LongInt seconds since epoch> }
' ---------------------------------------------

' Returns cached response data if valid (not expired), otherwise invalid.
' On valid hit, moves key to end of m_responseCacheOrder (most recently used).
function CacheTryGet(client as Object, method as String, path as String) as Object
    if client.m_responseCache = invalid then return invalid

    key = method + ":" + path
    if not client.m_responseCache.DoesExist(key) then return invalid

    entry = client.m_responseCache[key]
    ' Use roDateTime.SinceEpochTime() for Unix epoch seconds.
    dateTime = CreateObject("roDateTime")
    now = dateTime.SinceEpochTime()
    if now >= entry.expiresAt then
        ' Expired — evict and return invalid.
        client.m_responseCache.delete(key)
        return invalid
    end if

    ' Valid hit: update LRU order.
    client.m_responseCacheOrder.push(key)
    return entry.data
end function

' Stores response in cache with TTL. Evicts LRU entry if at capacity.
' Only call this AFTER a successful API response.
sub CacheStore(client as Object, method as String, path as String, data as Object)
    if client.m_responseCache = invalid then
        client.m_responseCache = {}
        client.m_responseCacheOrder = []
    end if

    key = method + ":" + path
    dateTime = CreateObject("roDateTime")
    now = dateTime.SinceEpochTime()

    ' Evict LRU entry if at capacity (skip if key already exists — refresh).
    ' Bounded LRU cache: capacity of 50 entries, 60s TTL.
    if client.m_responseCache.count() >= 50 and not client.m_responseCache.DoesExist(key) then
        if client.m_responseCacheOrder.count() > 0 then
            oldest = client.m_responseCacheOrder.shift()
            client.m_responseCache.delete(oldest)
        end if
    end if

    client.m_responseCache[key] = {
        data: data
        expiresAt: now + 60
    }
    client.m_responseCacheOrder.push(key)
end sub

' ---------------------------------------------
' R5.9: Cache invalidation by mutation type
' ---------------------------------------------

    ' Invalidate list endpoints that may change after favorite/rating mutations.
    ' itemId is optional — if provided, also invalidate that specific item.
    sub CacheInvalidateItem(client as Object, itemId as String)
        if client.m_responseCache = invalid then return

        toDelete = []

        ' Invalidate library items lists (they include user_data with favorite/rating).
        for each key in client.m_responseCache
            if Instr(1, key, "GET:/media") > 0 or Instr(1, key, "GET:/libraries") > 0 then
                toDelete.push(key)
            end if
        end for

        ' R5.4: Invalidate favorites list when items are added/removed.
        ' Without this, the stale cache returns the old list causing index-shift bugs
        ' where items appear "lost" after unfavorite (client has old ContentNode with
        ' more children than m.results).
        for each key in client.m_responseCache
            if Instr(1, key, "GET:/users/me/favorites") > 0 then
                toDelete.push(key)
            end if
        end for

    ' Invalidate specific item if provided.
    if itemId <> invalid and itemId <> "" then
        toDelete.push("GET:/media/" + itemId)
        ' Invalidate playback info too (changes with user state).
        toDelete.push("GET:/media/" + itemId + "/playback-info")
    end if

    for each key in toDelete
        client.m_responseCache.delete(key)
    end for
end sub

' Invalidate scan-affected endpoints: library items and continue-watching.
sub CacheInvalidateScan(client as Object)
    if client.m_responseCache = invalid then return

    toDelete = []

    ' Invalidate media lists and library lists.
    for each key in client.m_responseCache
        if Instr(1, key, "GET:/media") > 0 or Instr(1, key, "GET:/libraries") > 0 then
            toDelete.push(key)
        end if
    end for

    ' Invalidate continue-watching (scan may mark items as fully watched).
    for each key in client.m_responseCache
        if Instr(1, key, "GET:/me/continue-watching") > 0 then
            toDelete.push(key)
        end if
    end for

    for each key in toDelete
        client.m_responseCache.delete(key)
    end for
end sub

' Derives the ok flag from an ApiClient response.
' ENVELOPE LAW (see header): the canonical inputs are transport envelopes.
' - Wrapped helpers return the full {status,ok,data,error} envelope from
'   request()/login(). In this case data.ok is the HTTP-level ok (true for
'   200-299).
' - Unwrapped helpers return just the extracted data (array or object). We infer
'   ok from whether data is present and, for objects, whether data.success is false.
' - Arrays are always "ok" (a valid empty [] means success).
function DeriveResponseOk(data as Object) as Boolean
    if data = invalid then return false

    ' Wrapped helper: data is the full envelope from request() with .ok field
    if type(data) = "roAssociativeArray" and data.DoesExist("ok") then
        if data.ok = false then return false
        ' HTTP ok - now check for API-level {success: false} OR {error: ...} in data.data
        if type(data.data) = "roAssociativeArray" then
            if data.data.DoesExist("success") then
                return (data.data.success <> false)
            end if
            ' Admin actions return {error: "..."} on failure (no success key)
            if data.data.DoesExist("error") and data.data.error <> invalid and data.data.error <> "" then
                return false
            end if
        end if
        return true
    end if

    ' Unwrapped helper: data is the extracted payload (array or object)
    if type(data) = "roArray" then return true   ' arrays are valid data

    if type(data) = "roAssociativeArray" then
        ' Object payload - check for API-level success flag
        if data.DoesExist("success") then
            return (data.success <> false)
        end if
        return true
    end if

    return false
end function

' Extracts the error string from an ApiClient response.
' For wrapped helpers, error is at data.error.
' For unwrapped helpers, error is not available (returns "").
function DeriveResponseError(data as Object) as String
    if data = invalid then return ""
    if type(data) = "roAssociativeArray" and data.DoesExist("ok") then
        ' Wrapped helper - error is in the envelope
        if data.error <> invalid and data.error <> "" then
            return data.error
        end if
        ' Check for API-level {success:false,message:"..."} in data.data
        if type(data.data) = "roAssociativeArray" then
            if data.data.DoesExist("message") and data.data.message <> invalid then
                return data.data.message
            end if
            if data.data.DoesExist("error") and data.data.error <> invalid then
                return data.data.error
            end if
        end if
    end if
    return ""
end function

' ENVELOPE LAW choke (docs/api-envelope.md): record one transport envelope
' onto the scene-facing task response, unwrapping the server payload
' EXACTLY ONCE. Every op branch that receives the full
' {status,ok,data,error} envelope from ApiClient MUST go through here
' instead of assigning result.data/ok/error by hand.
' Unwrapped-helper pass-through (getMe-style: the method already returned
' the payload or invalid) keeps working: UnwrapApiEnvelope hands non-
' envelopes through untouched and DeriveResponseOk infers ok from
' presence, as before.
sub ApplyEnvelope(result as Object, env as Object)
    result.data = UnwrapApiEnvelope(env)
    result.ok = DeriveResponseOk(env)
    result.error = DeriveResponseError(env)
end sub

sub ExecRequest()
    ' R1.6: Invalidate the Storage read cache so we re-read the freshest values
    ' from the registry. This is the ONLY ResetCachedStorage call per Task run —
    ' all subsequent GetStorage().get() calls within this execution (GetApiClient's
    ' three token reads, any other storage reads) hit the in-memory cache, not NVRAM.
    ResetCachedStorage(false)

    ' R1.6: Build the ApiClient ONCE and reuse it for all operations on this Task.
    ' Previously each if-branch called GetApiClient() fresh → 3 NVRAM reads per call.
    ' Caching it here means 3 reads total for the entire Task lifetime instead of
    ' 3 × number_of_operations.
    if m.api = invalid then
        m.api = GetApiClient()
        ' R5.9: Initialize response cache on the shared ApiClient. The cache is
        ' scoped to this Task node's lifetime (m.api lives across operations).
        m.api.m_responseCache = {}
        m.api.m_responseCacheOrder = []
    end if

    api = m.api
    req = m.top.request
    result = { op: "", ok: false, data: invalid, error: "" }

    if req <> invalid and req.op <> invalid then
        result.op = req.op
        ' Echo an optional caller-supplied request id so scenes that run
        ' one-shot task nodes in parallel (HomeScene/LibraryScene pattern) can
        ' discard stale responses that finish after a newer request replaced
        ' them. Pure data pass-through - no behavior change when absent.
        if req.DoesExist("requestId") and req.requestId <> invalid then
            result.requestId = req.requestId
        end if

        if req.op = "getLibraries" then
            ' R5.9: Cache at request level (full envelope, unwrap on both hit
            ' and miss). ENVELOPE LAW + scene contract: HomeScene/LibraryAdmin
            ' Scene consume result.data AS the libraries ARRAY, so after the
            ' single transport unwrap this branch drills one further level
            ' into the server payload {libraries:[...]} (documented op shape
            ' in docs/api-envelope.md).
            cachedResp = CacheTryGet(api, "GET", "/libraries")
            if cachedResp = invalid then
                cachedResp = api.request("GET", "/libraries", invalid)
                if DeriveResponseOk(cachedResp) then
                    CacheStore(api, "GET", "/libraries", cachedResp)
                end if
            end if
            ApplyEnvelope(result, cachedResp)
            if result.ok then
                if result.data <> invalid and result.data.libraries <> invalid then
                    result.data = result.data.libraries
                else
                    result.data = []
                end if
            end if
        else if req.op = "getLibraryItems" then
            ' R5.9: Cache at request level using same query-string logic as ApiClient.
            opts = req.options
            if opts = invalid then opts = {}
            limit = 50
            offset = 0
            if opts.DoesExist("limit") then limit = opts.limit
            if opts.DoesExist("offset") then offset = opts.offset
            if opts.DoesExist("startIndex") then offset = opts.startIndex
            params = []
            if opts.DoesExist("parentId") then
                params.push("parentId=" + UrlEncode(opts.parentId))
            else
                params.push("libraryId=" + UrlEncode(req.libraryId))
                params.push("topLevel=1")
            end if
            params.push("limit=" + str(limit).trim())
            params.push("offset=" + str(offset).trim())
            if opts.DoesExist("sort") then params.push("sort=" + UrlEncode(opts.sort))
            if opts.DoesExist("order") then params.push("order=" + UrlEncode(opts.order))
            ' genres[]: the server reads this filter with is_array($query['genres'])
            ' (phlix-server src/Server/WebPortal/WebPortalRouter.php
            ' extractMediaQueryParams - a SCALAR `genres=` is silently dropped).
            ' Emit the PHP bracket-array form `genres%5B%5D=<value>` once per
            ' element - byte-identical to what phlix-ui's URLSearchParams sends -
            ' so $_GET/parse_str hydrate a real array on both HTTP stacks.
            if opts.DoesExist("genres") and opts.genres <> invalid
                genreList = opts.genres
                if type(genreList) = "roArray" then
                    for each g in genreList
                        if g <> invalid and g <> "" then
                            params.push("genres%5B%5D=" + UrlEncode(g))
                        end if
                    end for
                else
                    params.push("genres%5B%5D=" + UrlEncode(genreList))
                end if
            end if
            ' NOTE: there is deliberately NO `letter=` param here. GET /media
            ' accepts no letter filter (WebPortalRouter::extractMediaQueryParams);
            ' the old scalar `letter=` was ignored server-side, so A-Z jumps
            ' silently re-showed page 1. Letter navigation routes through the
            ' cumulative offsets of GET /media/letter-index (see getLetterIndex
            ' op + LibraryScene.OnLetterSelected).
            if opts.DoesExist("search") then params.push("search=" + UrlEncode(opts.search))
            cachePath = "/media?" + JoinStrings(params, "&")
            cachedResp = CacheTryGet(api, "GET", cachePath)
            if cachedResp <> invalid then
                ' ENVELOPE LAW: cachedResp is the {status,ok,data,error}
                ' transport envelope; ApplyEnvelope unwraps it once so scenes
                ' read the server payload at result.data level (resp.data.items).
                ApplyEnvelope(result, cachedResp)
            else
                resp = api.request("GET", cachePath, invalid)
                ApplyEnvelope(result, resp)
                if result.ok then
                    CacheStore(api, "GET", cachePath, resp)
                end if
            end if
        else if req.op = "getItem" then
            ' R5.9: Cache at request level. Scene contract (Home/Detail/Player/
            ' PhlixApp deep link): result.data IS the item OBJECT, so after the
            ' single transport unwrap this branch drills one further level into
            ' the server payload {item:{...}} (documented in docs/api-envelope.md).
            cachePath = "/media/" + req.itemId
            cachedResp = CacheTryGet(api, "GET", cachePath)
            if cachedResp = invalid then
                cachedResp = api.request("GET", cachePath, invalid)
                if DeriveResponseOk(cachedResp) then
                    CacheStore(api, "GET", cachePath, cachedResp)
                end if
            end if
            ApplyEnvelope(result, cachedResp)
            if result.ok then
                if result.data <> invalid and result.data.item <> invalid then
                    result.data = result.data.item
                else
                    result.data = invalid
                end if
            end if
        else if req.op = "getItemPlaybackInfo" then
            ApplyEnvelope(result, api.getItemPlaybackInfo(req.itemId))
        else if req.op = "getItemSimilar" then
            ApplyEnvelope(result, api.getItemSimilar(req.itemId))
        else if req.op = "getItemRatings" then
            ApplyEnvelope(result, api.getItemRatings(req.itemId))
        else if req.op = "getItemTrailers" then
            ApplyEnvelope(result, api.getItemTrailers(req.itemId))
        else if req.op = "getItemExtras" then
            ApplyEnvelope(result, api.getItemExtras(req.itemId))
        else if req.op = "startTranscode" then
            ApplyEnvelope(result, api.startTranscode(req.itemId))
        else if req.op = "getTranscodeStatus" then
            ApplyEnvelope(result, api.getTranscodeStatus(req.jobId))
        else if req.op = "createSession" then
            ApplyEnvelope(result, api.createSession())
        else if req.op = "reportProgress" then
            ApplyEnvelope(result, api.reportProgress(req.mediaItemId, req.positionTicks, req.durationTicks, req.isPaused))
        else if req.op = "completeSession" then
            ApplyEnvelope(result, api.completeSession())
        else if req.op = "getContinueWatching" then
            ' R5.9: Cache at request level.
            cachedResp = CacheTryGet(api, "GET", "/me/continue-watching")
            if cachedResp <> invalid then
                ApplyEnvelope(result, cachedResp)
            else
                resp = api.request("GET", "/me/continue-watching", invalid)
                ApplyEnvelope(result, resp)
                if result.ok then
                    CacheStore(api, "GET", "/me/continue-watching", resp)
                end if
            end if
        else if req.op = "getNextUp" then
            ' R7.2: Fetch the next episode/item for autoplay card and Up Next rail.
            ' Endpoint: GET /api/v1/users/me/next-up
            ' Response: direct item object (or null if nothing up next)
            cachedResp = CacheTryGet(api, "GET", "/users/me/next-up")
            if cachedResp <> invalid then
                ApplyEnvelope(result, cachedResp)
            else
                resp = api.request("GET", "/users/me/next-up", invalid)
                ApplyEnvelope(result, resp)
                if result.ok then
                    CacheStore(api, "GET", "/users/me/next-up", resp)
                end if
            end if
        else if req.op = "getRecommendations" then
            ' R5.9: Cache at request level.
            opts = req.options
            if opts = invalid then opts = {}
            limit = 20
            if opts.DoesExist("limit") then limit = opts.limit
            cachePath = "/me/recommendations?limit=" + str(limit).trim()
            cachedResp = CacheTryGet(api, "GET", cachePath)
            if cachedResp <> invalid then
                ApplyEnvelope(result, cachedResp)
            else
                resp = api.request("GET", cachePath, invalid)
                ApplyEnvelope(result, resp)
                if result.ok then
                    CacheStore(api, "GET", cachePath, resp)
                end if
            end if
        else if req.op = "search" then
            opts = req.options
            if opts = invalid then opts = {}
            ApplyEnvelope(result, api.search(req.query, opts))
        else if req.op = "favorite" then
            ApplyEnvelope(result, api.addFavorite(req.itemId))
            ' R5.9: Invalidate cache after favorite mutation (affects media items + lists).
            if result.ok then
                CacheInvalidateItem(api, req.itemId)
            end if
        else if req.op = "unfavorite" then
            ApplyEnvelope(result, api.removeFavorite(req.itemId))
            ' R5.9: Invalidate cache after unfavorite mutation.
            if result.ok then
                CacheInvalidateItem(api, req.itemId)
            end if
        else if req.op = "setRating" then
            ApplyEnvelope(result, api.setRating(req.itemId, req.rating))
            ' R5.9: Invalidate cache after rating mutation.
            if result.ok then
                CacheInvalidateItem(api, req.itemId)
            end if
        else if req.op = "clearRating" then
            ApplyEnvelope(result, api.clearRating(req.itemId))
            ' R5.9: Invalidate cache after clear-rating mutation.
            if result.ok then
                CacheInvalidateItem(api, req.itemId)
            end if
        else if req.op = "markWatched" then
            ApplyEnvelope(result, api.markWatched(req.itemId))
            ' R7.5: Invalidate cache after watched mutation.
            if result.ok then
                CacheInvalidateItem(api, req.itemId)
            end if
        else if req.op = "markUnwatched" then
            ApplyEnvelope(result, api.markUnwatched(req.itemId))
            ' R7.5: Invalidate cache after unwatched mutation.
            if result.ok then
                CacheInvalidateItem(api, req.itemId)
            end if
        else if req.op = "like" then
            ApplyEnvelope(result, api.like(req.itemId))
            ' R7.5: Invalidate cache after like mutation.
            if result.ok then
                CacheInvalidateItem(api, req.itemId)
            end if
        else if req.op = "getFavorites" then
            ' R5.9: Cache at request level.
            opts = req.options
            if opts = invalid then opts = {}
            limit = 50
            offset = 0
            if opts.DoesExist("limit") then limit = opts.limit
            if opts.DoesExist("offset") then offset = opts.offset
            cachePath = "/users/me/favorites?limit=" + str(limit).trim() + "&offset=" + str(offset).trim()
            cachedResp = CacheTryGet(api, "GET", cachePath)
            if cachedResp <> invalid then
                ApplyEnvelope(result, cachedResp)
            else
                resp = api.request("GET", cachePath, invalid)
                ApplyEnvelope(result, resp)
                if result.ok then
                    CacheStore(api, "GET", cachePath, resp)
                end if
            end if
        else if req.op = "getArtists" then
            ApplyEnvelope(result, api.getArtists())
        else if req.op = "getAudiobooks" then
            opts = req.options
            if opts = invalid then opts = {}
            ApplyEnvelope(result, api.getAudiobooks(opts))
        else if req.op = "getAudiobook" then
            ApplyEnvelope(result, api.getAudiobook(req.audiobookId))
        else if req.op = "getAudiobookChapters" then
            ApplyEnvelope(result, api.getAudiobookChapters(req.audiobookId))
        else if req.op = "getAudiobookProgress" then
            ApplyEnvelope(result, api.getAudiobookProgress(req.audiobookId))
        else if req.op = "saveAudiobookProgress" then
            ApplyEnvelope(result, api.saveAudiobookProgress(req.audiobookId, req.positionMs, req.currentChapterIndex))
        else if req.op = "getAlbums" then
            ApplyEnvelope(result, api.getAlbums())
        else if req.op = "getAlbum" then
            ApplyEnvelope(result, api.getAlbum(req.albumName))
        else if req.op = "getTracks" then
            opts = req.options
            if opts = invalid then opts = {}
            ApplyEnvelope(result, api.getTracks(opts))
        else if req.op = "getPhotoAlbums" then
            ApplyEnvelope(result, api.getPhotoAlbums(req.libraryId))
        else if req.op = "getPhotoAlbum" then
            ApplyEnvelope(result, api.getPhotoAlbum(req.albumId, req.libraryId))
        else if req.op = "getCollections" then
            ApplyEnvelope(result, api.getCollections())
        else if req.op = "getCollection" then
            ApplyEnvelope(result, api.getCollection(req.collectionId))
        else if req.op = "addToCollection" then
            ApplyEnvelope(result, api.addToCollection(req.collectionId, req.itemId))
        else if req.op = "removeFromCollection" then
            ApplyEnvelope(result, api.removeFromCollection(req.collectionId, req.itemId))
        else if req.op = "getMe" then
            ApplyEnvelope(result, api.getMe())
        else if req.op = "checkAuth" then
            ' Session restore + /auth/me validation on the task thread (not render).
            ' Runs on GetApiClient (relay base in hub mode, direct base in direct mode).
            result.ok = api.restoreSession()
            result.data = api.user
        else if req.op = "checkAuthHub" then
            ' Hub boot auth: uses GetHubApiClient (bare hub url) so /auth/me hits
            ' the hub directly, not through the relay (where hub-user /auth/me is
            ' unreliable). Follows same restoreSession pattern as checkAuth.
            hubApi = GetHubApiClient()
            result.ok = hubApi.restoreSession()
            result.data = hubApi.user
        else if req.op = "login" then
            ' Login on the task thread so the render thread never blocks.
            ' Uses GetHubApiClient (bare hub url) so login hits the hub directly,
            ' matching the original LoginScene login target.
            ' ApiClient.login returns the TRANSPORT ENVELOPE now: neither the
            ' server nor the hub /auth/login body carries a "success" key
            ' (verified: AuthManager::createAuthResponse / hub AuthController),
            ' so the HTTP status via env.ok is the verdict. Tokens + api.user
            ' are persisted inside login() itself on success. The scene gets
            ' {access_token, refresh_token, token_type, expires_in, user} at
            ' result.data on success and {error} (with the message also lifted
            ' to result.error) on failure.
            hubApi = GetHubApiClient()
            ApplyEnvelope(result, hubApi.login(req.username, req.password))
        else if req.op = "getMyServers" then
            ' Hub detection / server list. At pick-time active_server_id is empty,
            ' so GetApiClient binds to the bare hub url -> this hits the hub.
            ' A DIRECT server has no /me/servers route: its 404 IS the expected
            ' "direct" signal, not a failure, so it answers ok=true with an empty
            ' payload (the scenes' .servers checks then route to direct). Only a
            ' transport error or a non-404 failure fails the response - Login
            ' must never dead-end on a perfectly healthy plain server.
            env = api.getMyServers()
            if env <> invalid and not env.ok and env.status = 404 then
                result.ok = true
                result.data = {}
            else
                ApplyEnvelope(result, env)
            end if
        else if req.op = "getAdminNowPlaying" then
            ApplyEnvelope(result, api.getAdminNowPlaying())
        else if req.op = "getAdminStorage" then
            ApplyEnvelope(result, api.getAdminStorage())
        else if req.op = "getAdminActivity" then
            limit = 20
            if req.DoesExist("limit") and req.limit <> invalid then limit = req.limit
            ApplyEnvelope(result, api.getAdminActivity(limit))
        else if req.op = "scanLibrary" then
            ApplyEnvelope(result, api.scanLibrary(req.libraryId))
            ' R5.9: Invalidate cache after scan (library content may change).
            if result.ok then
                CacheInvalidateScan(api)
            end if
        else if req.op = "rescanLibrary" then
            ApplyEnvelope(result, api.rescanLibrary(req.libraryId))
            ' R5.9: Invalidate cache after rescan.
            if result.ok then
                CacheInvalidateScan(api)
            end if
        else if req.op = "matchLibraryMetadata" then
            ApplyEnvelope(result, api.matchLibraryMetadata(req.libraryId))
            ' R5.9: Invalidate cache after metadata match (item metadata may change).
            if result.ok then
                CacheInvalidateScan(api)
            end if
        else if req.op = "getLibraryScanStatus" then
            ApplyEnvelope(result, api.getLibraryScanStatus(req.libraryId))
        else if req.op = "getAdminUsers" then
            status = ""
            if req.DoesExist("status") and req.status <> invalid then status = req.status
            ApplyEnvelope(result, api.getAdminUsers(status))
        else if req.op = "getAdminUser" then
            ApplyEnvelope(result, api.getAdminUser(req.userId))
        else if req.op = "approveUser" then
            ApplyEnvelope(result, api.approveUser(req.userId))
        else if req.op = "disableUser" then
            ApplyEnvelope(result, api.disableUser(req.userId))
        else if req.op = "setUserAdmin" then
            ApplyEnvelope(result, api.setUserAdmin(req.userId, req.isAdmin))
        else if req.op = "resetUserPassword" then
            ApplyEnvelope(result, api.resetUserPassword(req.userId))
        else if req.op = "getUserProfiles" then
            ApplyEnvelope(result, api.getUserProfiles(req.userId))
        else if req.op = "getProfile" then
            ApplyEnvelope(result, api.getProfile(req.profileId))
        else if req.op = "setProfileRating" then
            ApplyEnvelope(result, api.setProfileRating(req.profileId, req.rating))
        else if req.op = "clearProfilePin" then
            ApplyEnvelope(result, api.clearProfilePin(req.profileId))
        else if req.op = "getChannels" then
            ApplyEnvelope(result, api.getChannels())
        else if req.op = "getChannelStreamUrl" then
            streamUrl = api.getChannelStreamUrl(req.channelId)
            result.data = { stream_url: streamUrl }
            result.ok = (streamUrl <> invalid and streamUrl <> "")
        else if req.op = "getGuide" then
            ApplyEnvelope(result, api.getGuide())
        else if req.op = "getRecordings" then
            ApplyEnvelope(result, api.getRecordings())
        else if req.op = "getSeriesRules" then
            ApplyEnvelope(result, api.getSeriesRules())
        else if req.op = "getSyncPlayGroups" then
            ApplyEnvelope(result, api.getSyncPlayGroups())
        else if req.op = "createSyncPlayGroup" then
            ApplyEnvelope(result, api.createSyncPlayGroup(req.name, req.isPublic))
        else if req.op = "joinSyncPlayGroup" then
            ApplyEnvelope(result, api.joinSyncPlayGroup(req.roomId))
        else if req.op = "leaveSyncPlayGroup" then
            ApplyEnvelope(result, api.leaveSyncPlayGroup(req.roomId))
        else if req.op = "probeHealth" then
            ' Probe the CANDIDATE url, not the shared GetApiClient (which is bound
            ' to the old/absent server_url at first run). Build a fresh client.
            api2 = ApiClient(req.url)
            result.data = api2.probeHealth()
            result.ok = (result.data <> invalid and HealthOk(result.data))
        else if req.op = "getProfileSchedules" then
            ApplyEnvelope(result, api.getProfileSchedules(req.profileId))
        else if req.op = "createProfileSchedule" then
            ApplyEnvelope(result, api.createProfileSchedule(req.profileId, req.schedule))
        else if req.op = "deleteProfileSchedule" then
            ApplyEnvelope(result, api.deleteProfileSchedule(req.profileId, req.scheduleId))
        else if req.op = "getProfileTags" then
            ApplyEnvelope(result, api.getProfileTags(req.profileId))
        else if req.op = "createProfileTag" then
            ApplyEnvelope(result, api.createProfileTag(req.profileId, req.tag))
        else if req.op = "deleteProfileTag" then
            ApplyEnvelope(result, api.deleteProfileTag(req.profileId, req.tagId))
        else if req.op = "getProfileStreamLimits" then
            ApplyEnvelope(result, api.getProfileStreamLimits(req.profileId))
        else if req.op = "updateProfileStreamLimits" then
            ApplyEnvelope(result, api.updateProfileStreamLimits(req.profileId, req.limits))
        else if req.op = "getMediaFacets" then
            libraryId = ""
            if req.DoesExist("libraryId") and req.libraryId <> invalid then
                libraryId = req.libraryId
            end if
            env = api.getMediaFacets(libraryId)
            ' Unwrap the transport envelope (see getLibraryItems above): the
            ' server returns {genres:[...]} at .data; scenes read resp.data.genres.
            ApplyEnvelope(result, env)
        else if req.op = "getLetterIndex" then
            ' GET /media/letter-index - phlix-server WebPortalRouter route
            ' 'GET /api/v1/media/letter-index' (registerRoutes) -> getLetterIndex():
            ' accepts the SAME filters as /media (genres%5B%5D etc.) + libraryId,
            ' has NO `letter` parameter, and returns
            ' {letters:[{letter,offset,count}], total} with CUMULATIVE offsets
            ' ('#' first, then A-Z) valid for a name-asc sorted /media query.
            ' The caller jumps the grid by requesting /media at the bucket offset.
            libraryId = ""
            if req.DoesExist("libraryId") and req.libraryId <> invalid then
                libraryId = req.libraryId
            end if
            genres = invalid
            if req.DoesExist("genres") and req.genres <> invalid then
                genres = req.genres
            end if
            env = api.getLetterIndex(libraryId, genres)
            ApplyEnvelope(result, env)
        else if req.op = "getPlaybackPreferences" then
            ' GET /me/playback/preferences - server payload {preferences:{...}}
            ' at .data (unwrapped here so the scene reads resp.data.preferences).
            env = api.getPlaybackPreferences()
            ApplyEnvelope(result, env)
        else if req.op = "clearWatchHistory" then
            ' DELETE /users/me/history - server payload {message} at .data.
            ' Mutation: dispatched here (task thread) so the 35s-blocking
            ' transport never runs on the render thread.
            env = api.clearWatchHistory()
            ApplyEnvelope(result, env)
        else if req.op = "logout" then
            ' Fire-and-forget server-side session teardown.
            ' Local credentials have already been cleared by OnLogout before this
            ' task is dispatched. Uses a fresh ApiClient so the baseUrl is live even
            ' if the calling scene has already cleared m.api.baseUrl.
            logoutApi = ApiClient(GetServerUrl())
            sessionId = GetStorage().get("session_id")
            if sessionId <> "" then
                logoutApi.request("DELETE", "/sessions/" + sessionId, invalid)
            end if
            result.ok = true
        end if
    end if

    m.top.response = result
end sub