'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/ApiClient.brs

' copyright 2026 Joe Huss
'

' @fileoverview ApiClient - Main HTTP client for Phlix Media Server API communication
' @author Phlix Team
' @version 2.0.0
' @requires Storage module for persistent storage
'
' @description
' This module provides the ApiClient factory function which creates an object
' for communicating with the Phlix Media Server canonical /api/v1 REST API.
' It handles:
' - Authentication (access_token + refresh_token, refresh-on-401-once)
' - Session management
' - Library browsing and item retrieval
' - Playback info + transcode fallback
' - Progress synchronization
'
' @example
' ```brightscript
' api = ApiClient("http://192.168.1.100:8096")
' user = api.login("username", "password")
' libraries = api.getLibraries()
' ```
'
' @module ApiClient
' @requires Storage

' ===========================================
' Phlix API Client for Roku
' Canonical /api/v1 contract (snake_case envelopes, Bearer + refresh tokens)
' ===========================================

function ApiClient(baseUrl as String) as Object
    obj = {
        baseUrl: baseUrl
        token: ""
        refreshToken: ""
        sessionId: ""
        deviceId: ""
        deviceName: "Roku"
        deviceType: "roku"
        user: invalid

        ' Set authentication (access) token
        setToken: function(token as String) as Void
            m.token = token
            if token <> "" then
                GetStorage().set("auth_token", token)
            else
                GetStorage().delete("auth_token")
            end if
        end function

        ' Set refresh token
        setRefreshToken: function(refreshToken as String) as Void
            m.refreshToken = refreshToken
            if refreshToken <> "" then
                GetStorage().set("refresh_token", refreshToken)
            else
                GetStorage().delete("refresh_token")
            end if
        end function

        ' Set session ID
        setSession: function(sessionId as String) as Void
            m.sessionId = sessionId
            if sessionId <> "" then
                GetStorage().set("session_id", sessionId)
            else
                GetStorage().delete("session_id")
            end if
        end function

        ' Restore session from storage and validate via GET /auth/me
        restoreSession: function() as Boolean
            token = GetStorage().get("auth_token")
            refreshToken = GetStorage().get("refresh_token")
            sessionId = GetStorage().get("session_id")

            if token <> invalid and token <> "" then
                m.token = token
                if refreshToken <> invalid and refreshToken <> "" then m.refreshToken = refreshToken
                if sessionId <> invalid and sessionId <> "" then m.sessionId = sessionId

                ' Validate token with server (canonical /auth/me returns {user})
                result = m.request("GET", "/auth/me", invalid)
                if result <> invalid and result.user <> invalid then
                    m.user = result.user
                    return true
                end if
            end if

            m.setToken("")
            m.setRefreshToken("")
            m.setSession("")
            return false
        end function

        ' ---------------------------------------------------------------------
        ' Low-level transport. Issues one HTTP request and returns the parsed
        ' JSON body plus the response code so callers (and the refresh wrapper)
        ' can react to 401s.
        '
        ' Uses roUrlTransfer async (AsyncGetToString / AsyncPostFromString) with
        ' a message port so we can read roUrlEvent.GetResponseCode() — the
        ' synchronous GetToString/PostFromString API does NOT expose the HTTP
        ' status code, which is required for refresh-on-401. We wait on the port
        ' (bounded by SetTimeout) which is safe here because all API calls in
        ' this client are invoked off the render thread by the managers/tasks.
        ' @return Object - { code: Integer, json: Object|invalid }
        ' ---------------------------------------------------------------------
        sendRaw: function(method as String, path as String, body as Object) as Object
            url = m.baseUrl + "/api/v1" + path

            port = CreateObject("roMessagePort")
            http = CreateObject("roUrlTransfer")
            http.SetPort(port)
            http.SetUrl(url)
            http.RetainBodyOnError(true)
            http.SetTimeout(30000)
            http.EnableEncodings(true)

            ' Standard headers
            http.AddHeader("Content-Type", "application/json")
            http.AddHeader("X-Phlix-Device-ID", m.deviceId)
            http.AddHeader("X-Phlix-Device-Name", m.deviceName)
            http.AddHeader("X-Phlix-Device-Type", m.deviceType)

            if m.token <> "" then
                http.AddHeader("Authorization", "Bearer " + m.token)
            end if

            if m.sessionId <> "" then
                http.AddHeader("X-Phlix-Session-ID", m.sessionId)
            end if

            ' Honor TLS on https origins.
            if Left(url, 6) = "https:" then
                http.SetCertificatesFile("common:/certs/ca-bundle.crt")
                http.InitClientCertificates()
            end if

            ' Issue the correct HTTP verb. GET (or any verb with no body) reads;
            ' verbs carrying a body POST/PUT/PATCH/DELETE the JSON payload.
            started = false
            if method = "GET" then
                started = http.AsyncGetToString()
            else
                http.SetRequest(method)
                if body <> invalid then
                    started = http.AsyncPostFromString(FormatJSON(body))
                else
                    started = http.AsyncGetToString()
                end if
            end if

            result = { code: 0, json: invalid, started: started }
            if not started then
                return result
            end if

            ' Block on the response, bounded to 35s (just above the 30s transfer
            ' timeout) so a lost/never-fired event can't hang the caller forever.
            event = wait(35000, port)
            if type(event) = "roUrlEvent" then
                result.code = event.GetResponseCode()
                responseString = event.GetString()
                if responseString <> invalid and responseString <> "" then
                    result.json = ParseJSON(responseString)
                end if
            else
                ' Timed out / no event - cancel the transfer.
                http.AsyncCancel()
            end if

            return result
        end function

        ' Attempt to refresh the access token using the stored refresh token.
        ' Returns true on success (new access_token stored).
        refreshAccessToken: function() as Boolean
            if m.refreshToken = "" then return false

            raw = m.sendRaw("POST", "/auth/refresh", { refresh_token: m.refreshToken })
            if raw.json <> invalid and raw.json.access_token <> invalid then
                m.setToken(raw.json.access_token)
                if raw.json.refresh_token <> invalid then
                    m.setRefreshToken(raw.json.refresh_token)
                end if
                return true
            end if

            return false
        end function

        ' High-level request. Sends the request and, on a 401 with a refresh
        ' token available, refreshes the access token and retries once. On a
        ' failed refresh the tokens are cleared. Returns a structured result:
        ' { status: Integer, ok: Boolean, data: Object, error: String }
        ' ok is true when status is 200-299. Transport failures produce
        ' ok=false, status=0, and a non-empty error string.
        request: function(method as String, path as String, body as Object) as Object
            raw = m.sendRaw(method, path, body)

            ' Refresh-on-401-once: do not retry the refresh endpoint itself.
            if raw.code = 401 and m.refreshToken <> "" and path <> "/auth/refresh" then
                if m.refreshAccessToken() then
                    raw = m.sendRaw(method, path, body)
                else
                    ' Refresh failed - clear stale credentials.
                    m.setToken("")
                    m.setRefreshToken("")
                end if
            end if

            status = raw.code
            ok = (status >= 200 and status <= 299)
            data = raw.json
            error = ""

            ' Transport failure: code=0 with no body means the request never
            ' got a HTTP response. Distinguish timeout vs connect failure.
            if status = 0 then
                ok = false
                if raw.started then
                    error = "timeout"   ' connection started but timed out
                else
                    error = "connect"    ' never started (DNS, refused, etc.)
                end if
            end if

            if status >= 400 then
                if data <> invalid and data.DoesExist("error") then
                    error = data.error
                else
                    error = "http_" + str(status).trim()
                end if
            end if

            return {
                status: status,
                ok: ok,
                data: data,
                error: error
            }
        end function

        ' ---------------------------------------------------------------------
        ' Authentication
        ' ---------------------------------------------------------------------

        ' POST /auth/login -> {access_token, refresh_token, user, ...}
        login: function(username as String, password as String) as Object
            body = {
                username: username
                password: password
            }
            ' Server accepts email login too; mirror phlix-ui by sending email
            ' when the identifier looks like an address.
            if Instr(1, username, "@") > 0 then body.email = username

            ' Bind the token to this device (optional server-side).
            raw = m.sendRawWithDeviceId("POST", "/auth/login", body)
            result = raw.json

            if result <> invalid and result.access_token <> invalid then
                m.setToken(result.access_token)
                if result.refresh_token <> invalid then
                    m.setRefreshToken(result.refresh_token)
                end if
                m.user = result.user
            end if

            return result
        end function

        ' Variant of sendRaw that also sends X-Device-Id (used on login so the
        ' server can bind the issued token to this device).
        sendRawWithDeviceId: function(method as String, path as String, body as Object) as Object
            url = m.baseUrl + "/api/v1" + path

            port = CreateObject("roMessagePort")
            http = CreateObject("roUrlTransfer")
            http.SetPort(port)
            http.SetUrl(url)
            http.RetainBodyOnError(true)
            http.SetTimeout(30000)
            http.EnableEncodings(true)

            http.AddHeader("Content-Type", "application/json")
            http.AddHeader("X-Phlix-Device-ID", m.deviceId)
            http.AddHeader("X-Phlix-Device-Name", m.deviceName)
            http.AddHeader("X-Phlix-Device-Type", m.deviceType)
            http.AddHeader("X-Device-Id", m.deviceId)

            if Left(url, 6) = "https:" then
                http.SetCertificatesFile("common:/certs/ca-bundle.crt")
                http.InitClientCertificates()
            end if

            result = { code: 0, json: invalid }
            started = false
            if body <> invalid then
                http.SetRequest(method)
                started = http.AsyncPostFromString(FormatJSON(body))
            else
                started = http.AsyncGetToString()
            end if

            if not started then return result

            event = wait(35000, port)
            if type(event) = "roUrlEvent" then
                result.code = event.GetResponseCode()
                responseString = event.GetString()
                if responseString <> invalid and responseString <> "" then
                    result.json = ParseJSON(responseString)
                end if
            else
                http.AsyncCancel()
            end if

            return result
        end function

        ' DELETE /sessions/{id} then clear all local credentials.
        logout: function() as Void
            if m.sessionId <> "" then
                m.request("DELETE", "/sessions/" + m.sessionId, invalid)
            end if
            m.setToken("")
            m.setRefreshToken("")
            m.setSession("")
            m.user = invalid
        end function

        ' ---------------------------------------------------------------------
        ' Session management
        ' ---------------------------------------------------------------------

        ' DELETE /sessions/{id} -> {message} ; ends the session WITHOUT clearing
        ' auth credentials (distinct from logout). Clears the local session id.
        endSession: function() as Object
            if m.sessionId = "" then return invalid
            result = m.request("DELETE", "/sessions/" + m.sessionId, invalid)
            m.setSession("")
            return result
        end function

        ' POST /sessions {device_id, device_name, device_type} -> {session_id}
        ' Token-gated (not user-gated): after restoreSession across scene
        ' navigation GetApiClient repopulates m.token but NOT m.user, so the
        ' player must be able to create a session to report progress.
        createSession: function() as Object
            if m.token = "" then
                print "Not logged in"
                return invalid
            end if

            result = m.request("POST", "/sessions", {
                device_id: m.deviceId
                device_name: m.deviceName
                device_type: m.deviceType
            })

            if result <> invalid and result.session_id <> invalid then
                m.setSession(result.session_id)
            end if

            return result
        end function

        ' ---------------------------------------------------------------------
        ' Library browsing
        ' ---------------------------------------------------------------------

        ' GET /libraries -> {libraries:[...]} ; returns the libraries array.
        getLibraries: function() as Object
            result = m.request("GET", "/libraries", invalid)
            if result <> invalid and result.libraries <> invalid then
                return result.libraries
            end if
            return []
        end function

        ' GET /media with query params. Returns the whole {items,total,limit,
        ' offset} envelope (managers read .items).
        getLibraryItems: function(libraryId as String, options = {} as Object) as Object
            limit = 50
            offset = 0
            sort = "name"
            order = "asc"
            if options.DoesExist("limit") then limit = options.limit
            ' Accept either offset or the legacy startIndex key.
            if options.DoesExist("offset") then offset = options.offset
            if options.DoesExist("startIndex") then offset = options.startIndex
            if options.DoesExist("sort") then sort = options.sort
            if options.DoesExist("order") then order = options.order

            params = []

            ' Library browse semantics (WebPortalRouter): default to
            ' libraryId=<id>&topLevel=1 (only movies + series at the grid level).
            ' An explicit options.parentId switches to direct-children mode
            ' (series->season->episode, F2) and OMITS topLevel.
            if options.DoesExist("parentId") then
                params.push("parentId=" + UrlEncode(options.parentId))
            else
                params.push("libraryId=" + UrlEncode(libraryId))
                ' topLevel coerced to the string "1" (NOT str(true)->"true").
                params.push("topLevel=1")
            end if

            params.push("limit=" + str(limit).trim())
            params.push("offset=" + str(offset).trim())
            params.push("sort=" + UrlEncode(sort))
            params.push("order=" + UrlEncode(order))

            ' Optional filters mirrored from the canonical contract.
            if options.DoesExist("search") then params.push("search=" + UrlEncode(options.search))

            query = "?" + JoinStrings(params, "&")
            return m.request("GET", "/media" + query, invalid)
        end function

        ' GET /media?search=<q> with query params. Global search across ALL
        ' libraries: deliberately omits libraryId/parentId/topLevel (the server
        ' ignores topLevel when search is set, so results can include
        ' season/episode rows too). Returns the whole {items,total,limit,offset}
        ' envelope (the scene reads .items).
        search: function(query as String, options = {} as Object) as Object
            limit = 50
            offset = 0
            sort = "name"
            order = "asc"
            if options.DoesExist("limit") then limit = options.limit
            if options.DoesExist("offset") then offset = options.offset
            if options.DoesExist("startIndex") then offset = options.startIndex
            if options.DoesExist("sort") then sort = options.sort
            if options.DoesExist("order") then order = options.order

            q = query
            if q = invalid then q = ""

            params = []
            params.push("search=" + UrlEncode(q))
            params.push("limit=" + str(limit).trim())
            params.push("offset=" + str(offset).trim())
            params.push("sort=" + UrlEncode(sort))
            params.push("order=" + UrlEncode(order))

            query2 = "?" + JoinStrings(params, "&")
            return m.request("GET", "/media" + query2, invalid)
        end function

        ' GET /media/{id} -> {item:{...}} ; returns the unwrapped item.
        getItem: function(itemId as String) as Object
            result = m.request("GET", "/media/" + itemId, invalid)
            if result <> invalid and result.item <> invalid then
                return result.item
            end if
            return invalid
        end function

        ' GET /media/{id}/playback-info -> whole object (markers/chapters/skip).
        getItemPlaybackInfo: function(itemId as String) as Object
            return m.request("GET", "/media/" + itemId + "/playback-info", invalid)
        end function

        ' GET /media/facets?libraryId=<id> -> {genres: string[]} of distinct
        ' genres for the given library (or all libraries if no libraryId).
        getMediaFacets: function(libraryId = "" as String) as Object
            path = "/media/facets"
            if libraryId <> "" then
                path = path + "?libraryId=" + UrlEncode(libraryId)
            end if
            return m.request("GET", path, invalid)
        end function

        ' GET /media/letter-index?libraryId=<id>&letter=<A-Z> -> {letters: [...]} of
        ' {letter, offset, count} buckets for A-Z + #, scoped to libraryId. The
        ' offset values are cumulative and can be used directly as pagination
        ' offsets to jump to a specific letter's page in the grid.
        getLetterIndex: function(libraryId as String, letter as String) as Object
            path = "/media/letter-index?letter=" + UrlEncode(letter)
            if libraryId <> "" then
                path = path + "&libraryId=" + UrlEncode(libraryId)
            end if
            return m.request("GET", path, invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Transcode (codec fallback)
        ' ---------------------------------------------------------------------

        ' POST /media/{id}/transcode (NO body; server picks profile from
        ' X-Phlix-Device-Type) -> {job_id, master_url, hls_url, dash_url, ...}
        startTranscode: function(itemId as String) as Object
            return m.request("POST", "/media/" + itemId + "/transcode", invalid)
        end function

        ' GET /transcode/{jobId}/status -> {job_id, status, playlist_ready, ...}
        getTranscodeStatus: function(jobId as String) as Object
            return m.request("GET", "/transcode/" + jobId + "/status", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Quality ladder (G4). The transcode start (POST /media/{id}/transcode)
        ' and status (GET /transcode/{jobId}/status) responses carry a signed
        ' `variants` array (server A7 / plan D6): each entry is
        ' { id, label, width, height, bitrate, codecs, url, is_original, is_copy }
        ' ordered highest-first, where `url` is that variant's own signed HLS
        ' media playlist ("/hls/{job}/media_v{id}.m3u8"). Auto (native ABR) is the
        ' `master_url`, not a variant. A legacy single-variant job sends
        ' `variants: null` (or omits the key) -> [].
        '
        ' parseVariants returns a compact array of { id, label, url } assocarrays
        ' (the only fields the PlayerScene picker needs), preserving the server's
        ' highest-first order. It is PURE (no state, no I/O) and NEVER crashes on a
        ' missing/malformed field - a rung without a usable id+url is dropped.
        ' @param resp Object - a transcode start/status response (whole json)
        ' @return Object - array of { id:String, label:String, url:String }
        parseVariants: function(resp as Object) as Object
            out = []
            if resp = invalid then return out
            ' Defensive: a non-assocarray resp (e.g. an roArray/roString) passes
            ' the invalid check but has no .DoesExist member -> guard it before any
            ' field access so a malformed input returns [] instead of crashing.
            if type(resp) <> "roAssociativeArray" then return out
            if not resp.DoesExist("variants") then return out
            variants = resp.variants
            if variants = invalid or type(variants) <> "roArray" then return out

            for each v in variants
                if v <> invalid and type(v) = "roAssociativeArray" then
                    ' JSON-parsed fields box as "roString"; hand-built assocarrays
                    ' (unit tests) may carry the intrinsic "String" - accept BOTH.
                    id = ""
                    if v.DoesExist("id") and (type(v.id) = "roString" or type(v.id) = "String") then id = v.id
                    url = ""
                    if v.DoesExist("url") and (type(v.url) = "roString" or type(v.url) = "String") then url = v.url
                    if id <> "" and url <> "" then
                        label = id
                        if v.DoesExist("label") and (type(v.label) = "roString" or type(v.label) = "String") and v.label <> "" then label = v.label
                        out.Push({ id: id, label: label, url: url })
                    end if
                end if
            end for

            return out
        end function

        ' ---------------------------------------------------------------------
        ' Playback progress
        ' ---------------------------------------------------------------------

        ' POST /sessions/{id}/progress with media_item_id + ticks.
        ' Ticks are 100ns units (10_000_000 = 1 second).
        reportProgress: function(mediaItemId as String, positionTicks as LongInteger, durationTicks as LongInteger, isPaused as Boolean) as Object
            if m.sessionId = "" then return invalid
            return m.request("POST", "/sessions/" + m.sessionId + "/progress", {
                media_item_id: mediaItemId
                position_ticks: positionTicks
                duration_ticks: durationTicks
                is_paused: isPaused
            })
        end function

        ' POST /sessions/{id}/complete — marks the episode as fully watched so it
        ' is removed from Continue Watching.
        completeSession: function() as Object
            if m.sessionId = "" then return invalid
            return m.request("POST", "/sessions/" + m.sessionId + "/complete", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Continue watching (F3 consumes the UI)
        ' ---------------------------------------------------------------------

        ' GET /me/continue-watching -> {items:[...]} ; returns whole object.
        getContinueWatching: function() as Object
            return m.request("GET", "/me/continue-watching", invalid)
        end function

        ' GET /me/recommendations -> {recommendations:[...]} ; returns whole object.
        getRecommendations: function(options = {} as Object) as Object
            limit = 20
            if options.DoesExist("limit") then limit = options.limit

            params = []
            params.push("limit=" + str(limit).trim())

            query = "?" + JoinStrings(params, "&")
            return m.request("GET", "/me/recommendations" + query, invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Favorites + ratings (per-user, account-level). itemId is a UUID and
        ' goes straight into the path (no UrlEncode, consistent with getItem).
        ' ---------------------------------------------------------------------

        ' POST /media/{id}/favorite (NO body) -> {message} ; whole json.
        addFavorite: function(itemId as String) as Object
            return m.request("POST", "/media/" + itemId + "/favorite", invalid)
        end function

        ' DELETE /media/{id}/favorite (NO body) -> {message} ; whole json.
        removeFavorite: function(itemId as String) as Object
            return m.request("DELETE", "/media/" + itemId + "/favorite", invalid)
        end function

        ' PUT /media/{id}/rating {rating:<int 1-10>} -> {message} ; whole json.
        setRating: function(itemId as String, rating as Integer) as Object
            return m.request("PUT", "/media/" + itemId + "/rating", { rating: rating })
        end function

        ' DELETE /media/{id}/rating (clear) -> {message} ; whole json.
        clearRating: function(itemId as String) as Object
            return m.request("DELETE", "/media/" + itemId + "/rating", invalid)
        end function

        ' GET /users/me/favorites?limit&offset -> {items,limit,offset} ; whole
        ' json (F5b consumes the list; F5a just exposes the method).
        getFavorites: function(options = {} as Object) as Object
            limit = 50
            offset = 0
            if options.DoesExist("limit") then limit = options.limit
            if options.DoesExist("offset") then offset = options.offset

            params = []
            params.push("limit=" + str(limit).trim())
            params.push("offset=" + str(offset).trim())

            query = "?" + JoinStrings(params, "&")
            return m.request("GET", "/users/me/favorites" + query, invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Music (F6). All /music/* routes are Bearer-gated and aggregate across
        ' ALL music libraries server-side (no library_id param). These return
        ' the WHOLE envelope (mirror getFavorites); the scene reads the named key.
        ' ---------------------------------------------------------------------

        ' GET /music/artists -> {artists:[...]} ; whole json.
        getArtists: function() as Object
            return m.request("GET", "/music/artists", invalid)
        end function

        ' GET /music/albums -> {albums:[...]} ; whole json.
        getAlbums: function() as Object
            return m.request("GET", "/music/albums", invalid)
        end function

        ' GET /music/albums/{name} -> {album:{...}} ; the album NAME is the path
        ' segment (URL-encoded). The returned album.tracks are RAW media rows.
        getAlbum: function(albumName as String) as Object
            return m.request("GET", "/music/albums/" + UrlEncode(albumName), invalid)
        end function

        ' GET /music/tracks?limit&offset -> {tracks,total,limit,offset} ; whole
        ' json. Tracks here are FLAT (unlike album.tracks).
        getTracks: function(options = {} as Object) as Object
            limit = 100
            offset = 0
            if options.DoesExist("limit") then limit = options.limit
            if options.DoesExist("offset") then offset = options.offset

            params = []
            params.push("limit=" + str(limit).trim())
            params.push("offset=" + str(offset).trim())

            query = "?" + JoinStrings(params, "&")
            return m.request("GET", "/music/tracks" + query, invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Photos (F7). All /photo/* JSON routes are Bearer-gated and REQUIRE a
        ' library_id. These return the WHOLE envelope (mirror getAlbums); the
        ' scene reads the named key. The thumbnail_url / full_url fields on the
        ' returned photos are ABSOLUTE + SIGNED (token embedded) -> they drop
        ' straight into a Poster.uri / PosterGrid HDPosterUrl (NO Bearer).
        ' ---------------------------------------------------------------------

        ' GET /photo/albums?library_id -> {albums:[...]} ; library_id REQUIRED.
        getPhotoAlbums: function(libraryId as String) as Object
            return m.request("GET", "/photo/albums?library_id=" + UrlEncode(libraryId), invalid)
        end function

        ' GET /photo/albums/{id}?library_id -> {album:{...}} ; id = md5(date);
        ' library_id REQUIRED. The returned album.photos carry signed urls.
        getPhotoAlbum: function(albumId as String, libraryId as String) as Object
            return m.request("GET", "/photo/albums/" + UrlEncode(albumId) + "?library_id=" + UrlEncode(libraryId), invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Collections (F8, read-only browse). The /collections* read routes are
        ' currently UNAUTHENTICATED server-side (no AuthMiddleware — a server gap
        ' flagged upstream); the client still sends its standard headers. These
        ' return the WHOLE envelope (mirror getFavorites/getAlbums); the scene
        ' reads the named key. A collection id is a UUID -> path directly (no
        ' UrlEncode, consistent with getItem).
        ' ---------------------------------------------------------------------

        ' GET /collections -> {collections:[...]} ; whole json.
        getCollections: function() as Object
            return m.request("GET", "/collections", invalid)
        end function

        ' GET /collections/{id} -> {collection:{...}, items:[...], total} ; whole
        ' json. The items are RAW DB rows (poster_url/overview/year under
        ' metadata.*), NOT MediaItemShaper-shaped -> the scene normalizes each
        ' row with Utilities.NormalizeCollectionItem.
        getCollection: function(collectionId as String) as Object
            return m.request("GET", "/collections/" + collectionId, invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Current user (F11). GET /auth/me -> {user} ; returns the unwrapped user
        ' (or invalid). HomeScene uses user.is_admin to gate the admin entry.
        ' ---------------------------------------------------------------------
        getMe: function() as Object
            result = m.request("GET", "/auth/me", invalid)
            if result <> invalid and result.user <> invalid then
                return result.user
            end if
            return invalid
        end function

        ' ---------------------------------------------------------------------
        ' Hub mode (F12b). GET /me/servers -> {servers:[ {serverId, serverName,
        ' status, relayActive, libraryCount, hostnameCandidates, ...} ]} (CAMEL
        ' case). Exists ONLY on a hub; a DIRECT server has no such route (404),
        ' so the caller treats a missing/non-array .servers as "direct". Returns
        ' the WHOLE envelope (the caller reads .servers); invalid on failure.
        ' ---------------------------------------------------------------------
        getMyServers: function() as Object
            return m.request("GET", "/me/servers", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Admin dashboard (F11a, read-only). All /admin/* require is_admin+active
        ' (AdminMiddleware -> 401/403). Envelope is {success,data,count}; these
        ' return the WHOLE json (the scene reads .data, an array).
        ' ---------------------------------------------------------------------
        getAdminNowPlaying: function() as Object
            return m.request("GET", "/admin/dashboard/now-playing", invalid)
        end function

        getAdminStorage: function() as Object
            return m.request("GET", "/admin/dashboard/storage", invalid)
        end function

        getAdminActivity: function(limit as Integer) as Object
            return m.request("GET", "/admin/dashboard/activity?limit=" + str(limit).trim(), invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Libraries admin (F11b). Bare /libraries/{id}/* routes, internally
        ' requireAdmin-gated. scan/rescan/match enqueue async jobs (202
        ' {job_id,status,message}); scan-status returns {scan_status:<job|null>}.
        ' libraryId is a UUID -> path directly. POST has NO body (proven no-body
        ' POST pattern, same as startTranscode). All return the WHOLE json.
        ' ---------------------------------------------------------------------
        scanLibrary: function(libraryId as String) as Object
            return m.request("POST", "/libraries/" + libraryId + "/scan", invalid)
        end function

        rescanLibrary: function(libraryId as String) as Object
            return m.request("POST", "/libraries/" + libraryId + "/rescan", invalid)
        end function

        matchLibraryMetadata: function(libraryId as String) as Object
            return m.request("POST", "/libraries/" + libraryId + "/match-metadata", invalid)
        end function

        getLibraryScanStatus: function(libraryId as String) as Object
            return m.request("GET", "/libraries/" + libraryId + "/scan-status", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Users admin (F11c). All /admin/users* require is_admin+active
        ' (AdminMiddleware). List returns {users:[...]}; get returns {user}; the
        ' action POSTs return {message} on success or {error} on a 400/404 guard
        ' (callers must read the specific key - result.ok is TRUE either way).
        ' reset-password additionally returns {new_password}. set-admin carries a
        ' JSON body {is_admin:bool}; the others are no-body POSTs. All return the
        ' WHOLE json (admin getters do not unwrap).
        ' ---------------------------------------------------------------------
        getAdminUsers: function(status as String) as Object
            path = "/admin/users"
            if status <> invalid and status <> "" then path = path + "?status=" + UrlEncode(status)
            return m.request("GET", path, invalid)
        end function

        getAdminUser: function(userId as String) as Object
            return m.request("GET", "/admin/users/" + userId, invalid)
        end function

        approveUser: function(userId as String) as Object
            return m.request("POST", "/admin/users/" + userId + "/approve", invalid)
        end function

        disableUser: function(userId as String) as Object
            return m.request("POST", "/admin/users/" + userId + "/disable", invalid)
        end function

        setUserAdmin: function(userId as String, isAdmin as Boolean) as Object
            return m.request("POST", "/admin/users/" + userId + "/set-admin", { is_admin: isAdmin })
        end function

        resetUserPassword: function(userId as String) as Object
            return m.request("POST", "/admin/users/" + userId + "/reset-password", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Profiles admin (F10). /admin/users/{userId}/profiles +
        ' /admin/profiles/{id}[/pin] all under AdminMiddleware. getUserProfiles
        ' returns the WHOLE {profiles:[...]}; getProfile returns the WHOLE
        ' {profile}; the mutations return {message} (or {error} on a guard -
        ' result.ok is TRUE either way, the caller reads the key).  userId is a
        ' String (from UserAdminScene); profileId is stringified by the caller.
        ' setProfileRating sends body {rating:int}; clearProfilePin is a no-body
        ' DELETE. All return the WHOLE json (admin getters do not unwrap).
        ' ---------------------------------------------------------------------
        getUserProfiles: function(userId as String) as Object
            return m.request("GET", "/admin/users/" + userId + "/profiles", invalid)
        end function

        getProfile: function(profileId as String) as Object
            return m.request("GET", "/admin/profiles/" + profileId, invalid)
        end function

        setProfileRating: function(profileId as String, rating as Integer) as Object
            return m.request("PUT", "/admin/profiles/" + profileId, { rating: rating })
        end function

        clearProfilePin: function(profileId as String) as Object
            return m.request("DELETE", "/admin/profiles/" + profileId + "/pin", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Live TV (F9a). /admin/livetv/* require is_admin+active (AdminMiddleware).
        ' getChannels returns the WHOLE envelope {success,channels:[...]} (admin
        ' getters do not unwrap). getChannelStreamUrl resolves the Bearer-gated 302
        ' from /channels/{id}/stream to the final (unauthenticated) tuner/HLS url so
        ' the Video node - which cannot carry our Bearer - can play it directly.
        ' ---------------------------------------------------------------------
        getChannels: function() as Object
            return m.request("GET", "/admin/livetv/channels", invalid)
        end function

        ' Resolve the channel stream redirect WITH Bearer and return the Location
        ' (the final stream url), or "" on failure. DEVICE-UNVERIFIABLE: roUrlTransfer
        ' redirect-follow behavior is firmware-dependent; if it auto-follows we get a
        ' 200 with no Location and return "" (caller shows an error). See worklog.
        getChannelStreamUrl: function(channelId as String) as String
            return m.resolveLocation("/admin/livetv/channels/" + channelId + "/stream")
        end function

        ' Issue a GET and return the 3xx Location header WITHOUT following the redirect
        ' (best-effort). Mirrors sendRaw's roUrlTransfer + roMessagePort + bounded wait,
        ' but reads headers instead of the body. Sends the same device + Bearer headers.
        resolveLocation: function(path as String) as String
            url = m.baseUrl + "/api/v1" + path

            port = CreateObject("roMessagePort")
            http = CreateObject("roUrlTransfer")
            http.SetPort(port)
            http.SetUrl(url)
            http.RetainBodyOnError(true)
            http.SetTimeout(30000)
            http.EnableEncodings(true)

            http.AddHeader("X-Phlix-Device-ID", m.deviceId)
            http.AddHeader("X-Phlix-Device-Name", m.deviceName)
            http.AddHeader("X-Phlix-Device-Type", m.deviceType)
            if m.token <> "" then http.AddHeader("Authorization", "Bearer " + m.token)
            if m.sessionId <> "" then http.AddHeader("X-Phlix-Session-ID", m.sessionId)

            if Left(url, 6) = "https:" then
                http.SetCertificatesFile("common:/certs/ca-bundle.crt")
                http.InitClientCertificates()
            end if

            if not http.AsyncGetToString() then return ""

            location = ""
            event = wait(35000, port)
            if type(event) = "roUrlEvent" then
                code = event.GetResponseCode()
                if code >= 300 and code < 400 then
                    headers = event.GetResponseHeaders()
                    if headers <> invalid then
                        if headers.DoesExist("Location") then
                            location = headers.Location
                        else if headers.DoesExist("location") then
                            location = headers.location
                        end if
                    end if
                end if
            else
                http.AsyncCancel()
            end if

            if location = invalid then location = ""
            return location
        end function

        ' ---------------------------------------------------------------------
        ' Health probe (F12a connect flow). Hits {baseUrl}/health DIRECTLY (the
        ' public, unauthenticated health endpoint - NOT /api/v1/health, so it does
        ' NOT go through sendRaw's "/api/v1" concat). Used on first-run connect to
        ' confirm a typed URL is reachable. The caller constructs a fresh
        ' ApiClient(candidateUrl) so this probes the CANDIDATE origin (the shared
        ' client is bound to the old/absent server_url at first run). Uses a short
        ' SYNC GetToString with an ~8s timeout so an unreachable host fails fast;
        ' it runs on the ApiTask thread so a sync wait is safe here. Returns the
        ' parsed JSON body, or invalid on empty/parse-fail/transport error.
        ' ---------------------------------------------------------------------
        probeHealth: function() as Object
            url = m.baseUrl + "/health"

            http = CreateObject("roUrlTransfer")
            http.SetUrl(url)
            http.RetainBodyOnError(true)
            http.SetTimeout(8000)
            http.EnableEncodings(true)

            if Left(url, 6) = "https:" then
                http.SetCertificatesFile("common:/certs/ca-bundle.crt")
                http.InitClientCertificates()
            end if

            responseString = http.GetToString()
            if responseString = invalid or responseString = "" then return invalid

            return ParseJSON(responseString)
        end function

        ' Live TV read-only lists (F9b). All return the WHOLE envelope; scenes read
        ' resp.data.programs / .recordings / .rules.
        getGuide: function() as Object
            return m.request("GET", "/admin/livetv/guide", invalid)
        end function

        getRecordings: function() as Object
            return m.request("GET", "/admin/livetv/recordings", invalid)
        end function

        getSeriesRules: function() as Object
            return m.request("GET", "/admin/livetv/series-rules", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' SyncPlay (F13 / P8-S4). REST endpoints for group management.
        '
        ' Source citations (phlix-server):
        '   SyncPlayController.php  - HTTP entry points (lines noted below)
        '   SyncPlaySnapshotService.php - listGroups response shape (lines 127-160)
        '   SyncPlayManager.php     - createGroup/joinGroup/leaveGroup return values
        '   GroupState.php          - getState() / serialize() field names
        '   SyncPlay.d.ts (phlix-contracts) - intended contract shapes
        '
        ' Route 1: GET /api/v1/syncplay/groups
        '   -> {groups:[{id, name, member_count, has_password, current_media, is_playing}]}
        '   Source: SyncPlayController.php:65 (listGroups)
        '           SyncPlaySnapshotService.php:127-160 (listGroups returns snake_case)
        '           Contract: SyncPlayGroupListItem (SyncPlay.d.ts:45-52)
        '
        ' Route 2: POST /api/v1/syncplay/groups {name, is_public}
        '   Body: {name:string, is_public?:bool} -- is_public is IGNORED by server
        '   <- {success:true, group:{group_id,group_name,member_count,members:{...},
        '               host_id,current_media_id,current_media_duration,
        '               playback_position,playback_state,queue,created_at,last_activity_at}}
        '   Source: SyncPlayController.php:81-108 (createGroup reads body['name'],body['password'] only)
        '           SyncPlayManager.php:325-373 (createGroup returns $group->getState())
        '           GroupState.php:677-703 (getState() field names)
        '   NOTE: server does NOT return roomId/sessionId/serverUrl at top level.
        '         is_public sent by client is NOT read by server controller.
        '
        ' Route 3: POST /api/v1/syncplay/groups/{id}/join
        '   Body: {password?:string, memberId?:string, memberName?:string}
        '   <- {success:true, group:{group_id,group_name,member_count,members:{...},...}}
        '   Source: SyncPlayController.php:148-175 (joinGroup)
        '           SyncPlayManager.php:396-453 (joinGroup)
        '   NOTE: server does NOT return sessionId or currentState at top level.
        '         Playback state fields are inside group (playback_position,playback_state).
        '
        ' Route 4: POST /api/v1/syncplay/groups/{id}/leave
        '   Body: {memberId?:string}
        '   <- {success:true, message?:string}
        '   Source: SyncPlayController.php:187-211 (leaveGroup)
        '           SyncPlayManager.php:471-509 (leaveGroup)
        '
        ' Route 5: GET /api/v1/syncplay/groups/{id}
        '   <- {group:{group_id,group_name,member_count,members:{...},...}}
        '   Source: SyncPlayController.php:121-136 (getGroup)
        '           SyncPlaySnapshotService.php:171-200 (getGroupState)
        '
        ' WebSocket: ws://{host}:8097/syncplay/{roomId}?token={jwt}
        '   (serverUrl is derived client-side from ApiClient baseUrl, not returned by server)
        '
        ' Contract disagreements to report for phlix-contracts:
        '   1. is_public is NOT tracked by server — not returned in listGroups, not stored
        '   2. createGroup/joinGroup do NOT return sessionId or serverUrl
        '   3. joinGroup response has no top-level currentState; playback state is inside group
        '   4. Contract SyncPlayGroupListItem has no is_public field (correct — server doesn't store it)
        '   5. members is a dict/object (associative array keyed by memberId), not SyncPlayMember[]
        ' ---------------------------------------------------------------------

        ' GET /syncplay/groups -> {groups:[...]}
        getSyncPlayGroups: function() as Object
            return m.request("GET", "/syncplay/groups", invalid)
        end function

        ' POST /syncplay/groups {name,is_public} -> {success,group:{group_id,...}}
        ' NOTE: is_public is sent but NOT read by the server (controller only reads name/password).
        createSyncPlayGroup: function(name as String, isPublic as Boolean) as Object
            return m.request("POST", "/syncplay/groups", { name: name, is_public: isPublic })
        end function

        ' POST /syncplay/groups/{id}/join -> {sessionId,members,currentState}
        joinSyncPlayGroup: function(roomId as String) as Object
            return m.request("POST", "/syncplay/groups/" + roomId + "/join", invalid)
        end function

        ' POST /syncplay/groups/{id}/leave -> {message}
        leaveSyncPlayGroup: function(roomId as String) as Object
            return m.request("POST", "/syncplay/groups/" + roomId + "/leave", invalid)
        end function

        ' ---------------------------------------------------------------------
        ' Parental Controls (P5-S5). Access schedules, tags, and stream limits.
        ' profileId is stringified by the caller before passing here (an Integer
        ' in the path would CRASH). All return the WHOLE json.
        ' ---------------------------------------------------------------------

        ' GET /profiles/{id}/schedules -> {schedules:[...]}
        getProfileSchedules: function(profileId as String) as Object
            return m.request("GET", "/profiles/" + profileId + "/schedules", invalid)
        end function

        ' POST /profiles/{id}/schedules {name,startTime,endTime,daysOfWeek,isActive}
        ' -> {schedule} (the created schedule) or {error}
        createProfileSchedule: function(profileId as String, schedule as Object) as Object
            return m.request("POST", "/profiles/" + profileId + "/schedules", schedule)
        end function

        ' DELETE /profiles/{id}/schedules/{scheduleId} -> {message}
        deleteProfileSchedule: function(profileId as String, scheduleId as String) as Object
            return m.request("DELETE", "/profiles/" + profileId + "/schedules/" + scheduleId, invalid)
        end function

        ' GET /profiles/{id}/tags -> {tags:[...]}
        getProfileTags: function(profileId as String) as Object
            return m.request("GET", "/profiles/" + profileId + "/tags", invalid)
        end function

        ' POST /profiles/{id}/tags {tag,tagType} -> {tag} (the created tag)
        createProfileTag: function(profileId as String, tag as Object) as Object
            return m.request("POST", "/profiles/" + profileId + "/tags", tag)
        end function

        ' DELETE /profiles/{id}/tags/{tagId} -> {message}
        deleteProfileTag: function(profileId as String, tagId as String) as Object
            return m.request("DELETE", "/profiles/" + profileId + "/tags/" + tagId, invalid)
        end function

        ' GET /profiles/{id}/stream-limits -> {stream_limit:{...}} (whole envelope)
        getProfileStreamLimits: function(profileId as String) as Object
            return m.request("GET", "/profiles/" + profileId + "/stream-limits", invalid)
        end function

        ' PUT /profiles/{id}/stream-limits {maxConcurrentStreams} -> {message}
        updateProfileStreamLimits: function(profileId as String, limits as Object) as Object
            return m.request("PUT", "/profiles/" + profileId + "/stream-limits", limits)
        end function

        ' ---------------------------------------------------------------------
        ' Playback preferences (R7.1). GET /me/playback/preferences -> {prefs}.
        ' ---------------------------------------------------------------------
        getPlaybackPreferences: function() as Object
            return m.request("GET", "/me/playback/preferences", invalid)
        end function

        ' PUT /me/playback/preferences {preferences} -> {message}
        updatePlaybackPreferences: function(preferences as Object) as Object
            return m.request("PUT", "/me/playback/preferences", preferences)
        end function

        ' ---------------------------------------------------------------------
        ' Watch history (R7.1). DELETE /api/v1/users/me/history -> {message}.
        ' ---------------------------------------------------------------------
        clearWatchHistory: function() as Object
            return m.request("DELETE", "/users/me/history", invalid)
        end function
    }

    ' roDeviceInfo provides device identification per the ifDeviceInfo interface
    ' See: https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
    deviceInfo = CreateObject("roDeviceInfo")

    ' Use GetChannelClientId() for stable per-device, per-channel identifier
    ' This replaces the old Rnd-based ID that collided on factory-reset devices
    ' Clear any stale Rnd-based device_id (migration for never-shipped channel)
    obj.deviceId = deviceInfo.GetChannelClientId()
    GetStorage().set("device_id", obj.deviceId)

    ' Use real device name from firmware (e.g., "Roku 2 XD", "Roku Ultra")
    obj.deviceName = deviceInfo.GetModelDisplayName()

    return obj
end function