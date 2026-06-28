' source/lib/ApiClient.brs
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
                Storage.set("auth_token", token)
            else
                Storage.delete("auth_token")
            end if
        end function

        ' Set refresh token
        setRefreshToken: function(refreshToken as String) as Void
            m.refreshToken = refreshToken
            if refreshToken <> "" then
                Storage.set("refresh_token", refreshToken)
            else
                Storage.delete("refresh_token")
            end if
        end function

        ' Set session ID
        setSession: function(sessionId as String) as Void
            m.sessionId = sessionId
            if sessionId <> "" then
                Storage.set("session_id", sessionId)
            else
                Storage.delete("session_id")
            end if
        end function

        ' Restore session from storage and validate via GET /auth/me
        restoreSession: function() as Boolean
            token = Storage.get("auth_token")
            refreshToken = Storage.get("refresh_token")
            sessionId = Storage.get("session_id")

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

            result = { code: 0, json: invalid }
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
        ' failed refresh the tokens are cleared. Returns the parsed JSON body
        ' (or invalid).
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

            return raw.json
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

        ' ---------------------------------------------------------------------
        ' Continue watching (F3 consumes the UI)
        ' ---------------------------------------------------------------------

        ' GET /me/continue-watching -> {items:[...]} ; returns whole object.
        getContinueWatching: function() as Object
            return m.request("GET", "/me/continue-watching", invalid)
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
    }

    ' Generate device ID if not exists
    obj.deviceId = Storage.get("device_id")
    if obj.deviceId = "" or obj.deviceId = invalid then
        obj.deviceId = "roku-" + str(Rnd(999999999)).trim() + "-" + str(Rnd(999999999)).trim()
        Storage.set("device_id", obj.deviceId)
    end if

    return obj
end function
