' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ApiTask.brs

' copyright 2026 Joe Huss
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
' ===========================================

sub Init()
    m.top.functionName = "ExecRequest"
end sub

' Derives the ok flag from an ApiClient response.
' - Wrapped helpers return the full {status,ok,data,error} envelope from request().
'   In this case data.ok is the HTTP-level ok (true for 200-299).
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
    end if

    api = m.api
    req = m.top.request
    result = { op: "", ok: false, data: invalid, error: "" }

    if req <> invalid and req.op <> invalid then
        result.op = req.op

        if req.op = "getLibraries" then
            result.data = api.getLibraries()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getLibraryItems" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getLibraryItems(req.libraryId, opts)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getItem" then
            result.data = api.getItem(req.itemId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getItemPlaybackInfo" then
            result.data = api.getItemPlaybackInfo(req.itemId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "startTranscode" then
            result.data = api.startTranscode(req.itemId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getTranscodeStatus" then
            result.data = api.getTranscodeStatus(req.jobId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "createSession" then
            result.data = api.createSession()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "reportProgress" then
            result.data = api.reportProgress(req.mediaItemId, req.positionTicks, req.durationTicks, req.isPaused)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getContinueWatching" then
            result.data = api.getContinueWatching()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getWatchHistory" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getWatchHistory(opts)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getRecommendations" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getRecommendations(opts)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "search" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.search(req.query, opts)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "favorite" then
            result.data = api.addFavorite(req.itemId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "unfavorite" then
            result.data = api.removeFavorite(req.itemId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "setRating" then
            result.data = api.setRating(req.itemId, req.rating)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "clearRating" then
            result.data = api.clearRating(req.itemId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getFavorites" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getFavorites(opts)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getArtists" then
            result.data = api.getArtists()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getAlbums" then
            result.data = api.getAlbums()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getAlbum" then
            result.data = api.getAlbum(req.albumName)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getTracks" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getTracks(opts)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getPhotoAlbums" then
            result.data = api.getPhotoAlbums(req.libraryId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getPhotoAlbum" then
            result.data = api.getPhotoAlbum(req.albumId, req.libraryId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getCollections" then
            result.data = api.getCollections()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getCollection" then
            result.data = api.getCollection(req.collectionId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getMe" then
            result.data = api.getMe()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
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
            hubApi = GetHubApiClient()
            result.data = hubApi.login(req.username, req.password)
            result.ok = (result.data <> invalid and result.data.success = true)
        else if req.op = "getMyServers" then
            ' Hub detection / server list. At pick-time active_server_id is empty,
            ' so GetApiClient binds to the bare hub url -> this hits the hub.
            result.data = api.getMyServers()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getAdminNowPlaying" then
            result.data = api.getAdminNowPlaying()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getAdminStorage" then
            result.data = api.getAdminStorage()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getAdminActivity" then
            limit = 20
            if req.DoesExist("limit") and req.limit <> invalid then limit = req.limit
            result.data = api.getAdminActivity(limit)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "scanLibrary" then
            result.data = api.scanLibrary(req.libraryId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "rescanLibrary" then
            result.data = api.rescanLibrary(req.libraryId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "matchLibraryMetadata" then
            result.data = api.matchLibraryMetadata(req.libraryId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getLibraryScanStatus" then
            result.data = api.getLibraryScanStatus(req.libraryId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getAdminUsers" then
            status = ""
            if req.DoesExist("status") and req.status <> invalid then status = req.status
            result.data = api.getAdminUsers(status)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getAdminUser" then
            result.data = api.getAdminUser(req.userId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "approveUser" then
            result.data = api.approveUser(req.userId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "disableUser" then
            result.data = api.disableUser(req.userId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "setUserAdmin" then
            result.data = api.setUserAdmin(req.userId, req.isAdmin)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "resetUserPassword" then
            result.data = api.resetUserPassword(req.userId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getUserProfiles" then
            result.data = api.getUserProfiles(req.userId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getProfile" then
            result.data = api.getProfile(req.profileId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "setProfileRating" then
            result.data = api.setProfileRating(req.profileId, req.rating)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "clearProfilePin" then
            result.data = api.clearProfilePin(req.profileId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getChannels" then
            result.data = api.getChannels()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getChannelStreamUrl" then
            streamUrl = api.getChannelStreamUrl(req.channelId)
            result.data = { stream_url: streamUrl }
            result.ok = (streamUrl <> invalid and streamUrl <> "")
        else if req.op = "getGuide" then
            result.data = api.getGuide()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getRecordings" then
            result.data = api.getRecordings()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getSeriesRules" then
            result.data = api.getSeriesRules()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getSyncPlayGroups" then
            result.data = api.getSyncPlayGroups()
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "createSyncPlayGroup" then
            result.data = api.createSyncPlayGroup(req.name, req.isPublic)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "joinSyncPlayGroup" then
            result.data = api.joinSyncPlayGroup(req.roomId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "leaveSyncPlayGroup" then
            result.data = api.leaveSyncPlayGroup(req.roomId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "probeHealth" then
            ' Probe the CANDIDATE url, not the shared GetApiClient (which is bound
            ' to the old/absent server_url at first run). Build a fresh client.
            api2 = ApiClient(req.url)
            result.data = api2.probeHealth()
            result.ok = (result.data <> invalid and HealthOk(result.data))
        else if req.op = "getProfileSchedules" then
            result.data = api.getProfileSchedules(req.profileId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "createProfileSchedule" then
            result.data = api.createProfileSchedule(req.profileId, req.schedule)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "deleteProfileSchedule" then
            result.data = api.deleteProfileSchedule(req.profileId, req.scheduleId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getProfileTags" then
            result.data = api.getProfileTags(req.profileId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "createProfileTag" then
            result.data = api.createProfileTag(req.profileId, req.tag)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "deleteProfileTag" then
            result.data = api.deleteProfileTag(req.profileId, req.tagId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "getProfileStreamLimits" then
            result.data = api.getProfileStreamLimits(req.profileId)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
        else if req.op = "updateProfileStreamLimits" then
            result.data = api.updateProfileStreamLimits(req.profileId, req.limits)
            result.ok = DeriveResponseOk(result.data)
            result.error = DeriveResponseError(result.data)
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