' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/AppContext.brs

' copyright 2026 Joe Huss
'
'

' ===========================================
' App Context for Roku
' Global accessor functions for shared app state.
' BrightScript has no global variables (only global functions), so the API
' client and server URL are exposed through these source-scope functions which
' are visible to every component. Each scene/manager builds a lightweight
' ApiClient via GetApiClient() that restores the persisted token/session from
' Storage, so per-scene state stays transient while auth survives navigation.
'
' R1.6 caching: GetStorage() now returns a cached singleton; its internal
' _cache map holds the last-read value of each registry key, so repeated
' GetStorage().get() calls within a Task or scene lifetime hit memory not NVRAM.
' Call ResetCachedStorage(fullReset) on server switch, login, and logout so the
' next API call re-reads the fresh values.
' ===========================================

' Get the configured server URL. Returns "" when no server has been configured;
' callers MUST check IsServerConnected() first and route to Connect if unconfigured.
' @return String - The server base URL, or "" when not configured
function GetServerUrl() as String
    url = GetStorage().get("server_url")
    if url = invalid or url = "" then return ""
    return url
end function

' True when a server URL has been chosen (persisted under "server_url" and
' non-empty). Boot gates on this: first run (no server_url) -> ConnectScene;
' otherwise the normal auth flow. GetServerUrl returns "" when unconfigured;
' callers MUST check IsServerConnected() first and route to Connect if unconfigured.
' @return Boolean - true when a non-empty server_url is persisted
function IsServerConnected() as Boolean
    url = GetStorage().get("server_url")
    return (url <> invalid and url <> "")
end function

' The connection kind for the persisted server: "hub" or "direct". An absent /
' empty / unrecognized value is treated as "direct" (the pre-F12b default), so
' existing direct installs are byte-unchanged. F12b's LoginScene probes
' /me/servers post-login to detect a hub and persists this.
' @return String - "hub" or "direct"
function GetConnectionKind() as String
    kind = GetStorage().get("connection_kind")
    if kind = "hub" then return "hub"
    return "direct"
end function

' The server the user picked on the ServerPickerScene (hub mode only). Empty
' when no server has been chosen yet (or in direct mode). The id is persisted as
' a stringified value by the picker (the relay path needs a String segment).
' @return String - the active server id, or ""
function GetActiveServerId() as String
    id = GetStorage().get("active_server_id")
    if id = invalid then return ""
    return id
end function

' The base url that the MEDIA ApiClient binds to.
' - direct mode: the bare server url (byte-identical to GetServerUrl()).
' - hub mode WITH a picked server: the relay proxy base
'   {hubUrl}/api/v1/servers/{activeServerId}/proxy. Since ApiClient.sendRaw
'   builds m.baseUrl + "/api/v1" + path, the final url becomes
'   {hubUrl}/api/v1/servers/{id}/proxy/api/v1{path}, which the hub proxy
'   re-anchors at the server's /api/v1{path}. The HUB Bearer (already sent by
'   sendRaw) is the relay auth - NO extra headers, NO sendRaw change.
' - hub mode WITHOUT a picked server: the bare hub url (so login + /me/servers
'   work before a server is chosen).
' @return String - the media base url
function GetMediaBaseUrl() as String
    base = GetServerUrl()
    if GetConnectionKind() = "hub" then
        activeId = GetActiveServerId()
        if activeId <> "" then
            return base + "/api/v1/servers/" + activeId + "/proxy"
        end if
    end if
    return base
end function

' Build an ApiClient bound to the MEDIA base url (GetMediaBaseUrl) with any
' persisted auth token / session id restored from Storage. In hub mode with a
' picked server this transparently routes every existing scene + ApiTask call
' through the relay; in direct mode it is byte-unchanged.
'
' R1.6: The Storage singleton caches registry reads in memory. A fresh ApiClient
' is still built each call (the object carries auth state for this operation),
' but the Storage reads inside here hit the cache, not NVRAM.
' @return Object - A ready-to-use ApiClient instance
function GetApiClient() as Object
    api = ApiClient(GetMediaBaseUrl())
    token = GetStorage().get("auth_token")
    if token <> invalid and token <> "" then api.token = token
    refreshToken = GetStorage().get("refresh_token")
    if refreshToken <> invalid and refreshToken <> "" then api.refreshToken = refreshToken
    sid = GetStorage().get("session_id")
    if sid <> invalid and sid <> "" then api.sessionId = sid
    return api
end function

' Build an ApiClient bound to the BARE server url (the hub), NOT the relay base.
' Used for hub-scoped calls that must hit the hub directly: boot session
' validation (/auth/me over relay is unreliable - the server has no such local
' user) and /me/servers once an active server is picked (otherwise GetApiClient
' would point at the relay). Restores the same persisted token/session.
' @return Object - A ready-to-use ApiClient instance bound to the bare hub url
function GetHubApiClient() as Object
    api = ApiClient(GetServerUrl())
    token = GetStorage().get("auth_token")
    if token <> invalid and token <> "" then api.token = token
    refreshToken = GetStorage().get("refresh_token")
    if refreshToken <> invalid and refreshToken <> "" then api.refreshToken = refreshToken
    sid = GetStorage().get("session_id")
    if sid <> invalid and sid <> "" then api.sessionId = sid
    return api
end function

' ===========================================
' Device Capability Detection (R6.8)
' Records device model, video mode, and memory tier at boot.
' Uses roDeviceInfo methods per:
' - GetModel()       -> https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
' - GetVideoMode()   -> https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
' - GetDeviceInfo()  -> https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
' - CanDecodeVideo() -> https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
' ===========================================

' Factory function for device info - returns cached singleton.
' Follows the Storage pattern: state stored as property on the function object.
' Named DeviceInfoData to avoid shadowing local deviceInfo variables in other files.
' @return Object - device info object with model, videoMode, memoryTier, totalMemoryMB
function DeviceInfoData() as Object
    if DeviceInfoData._cache <> invalid then return DeviceInfoData._cache

    devInfoObj = CreateObject("roDeviceInfo")

    ' GetModel() returns the device model number (e.g., "4800X", "3920X")
    ' Docs: https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
    model = devInfoObj.GetModel()

    ' GetVideoMode() returns the display resolution (e.g., "1080p", "720p", "480p")
    ' Docs: https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
    videoMode = devInfoObj.GetVideoMode()

    ' GetDeviceInfo() returns an associative array with device details:
    ' { serialNumber, modelNumber, modelName, tvFeatures, audioCapabilities,
    '   outputCapabilities, totalMemoryMB, deviceType, hasGames, country,
    '   countryInfo, locale, timeZone, timeZoneInfo, isRokuTV, isDTV }
    ' Docs: https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md
    devInfo = devInfoObj.GetDeviceInfo()
    totalMemoryMB = 0
    if devInfo <> invalid and devInfo.DoesExist("totalMemoryMB") then
        totalMemoryMB = devInfo.totalMemoryMB
    end if

    ' Memory tier classification based on total RAM:
    ' - Low tier: < 512 MB  (Roku Express, some legacy devices)
    ' - Medium tier: 512-1024 MB (Roku Streaming Stick, most mid-range)
    ' - High tier: > 1024 MB (Roku Ultra, high-end devices)
    ' R6.8: Memory tier feeds page size and poster decode size decisions.
    memoryTier = "low"
    if totalMemoryMB >= 1024 then
        memoryTier = "high"
    else if totalMemoryMB >= 512 then
        memoryTier = "medium"
    end if

    DeviceInfoData._cache = {
        model: model
        videoMode: videoMode
        memoryTier: memoryTier
        totalMemoryMB: totalMemoryMB
    }

    print "Device info: model=" DeviceInfoData._cache.model " videoMode=" DeviceInfoData._cache.videoMode " memoryTier=" DeviceInfoData._cache.memoryTier " (" totalMemoryMB "MB)"
    return DeviceInfoData._cache
end function

' Initialize device info by querying roDeviceInfo once at boot.
' R6.8: Called from PhlixApp.Init to capture device capabilities early.
' @return Object - cached device info associative array
function InitDeviceInfo() as Object
    return DeviceInfoData()
end function

' Get the cached device model name (e.g., "4800X", "3920X").
' R6.8: Model appears in diagnostics output.
' @return String - device model number
function GetDeviceModel() as String
    return DeviceInfoData().model
end function

' Get the cached video mode (e.g., "1080p", "720p", "480p").
' R6.8: Video mode appears in diagnostics output.
' @return String - display resolution mode
function GetDeviceVideoMode() as String
    return DeviceInfoData().videoMode
end function

' Get the cached memory tier classification.
' R6.8: Memory tier feeds page size and poster decode size decisions.
' @return String - "low", "medium", or "high"
function GetDeviceMemoryTier() as String
    return DeviceInfoData().memoryTier
end function

' Check if the device can decode a specific video format.
' R6.8: Gates direct play - if DeviceCanDecodeVideo returns false, go straight to transcode.
' Per https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md:
' "Use CanDecodeVideo to determine if the device can decode a specific video codec."
' @param codec String - video codec (e.g., "h264", "h265", "vp9")
' @param container String - container format (e.g., "mp4", "mkv", "hls")
' @param profile String - codec profile (e.g., "high", "main", "baseline") - may be empty
' @return Boolean - true if device can decode this format
function DeviceCanDecodeVideo(codec as String, container as String, profile as String) as Boolean
    devInfoObj = CreateObject("roDeviceInfo")
    ' CanDecodeVideo(codec as String, container as String, profile as String) as Boolean
    ' codec: the video codec (h264, h265, vp9, etc.)
    ' container: the container format (mp4, mkv, hls, etc.)
    ' profile: the codec profile (high, main, baseline, etc.) - empty string for any
    return devInfoObj.CanDecodeVideo(codec, container, profile)
end function

' Get a page size recommendation based on memory tier.
' R6.8: Memory tier feeds page size decisions - lower tier devices get smaller pages.
' @return Integer - recommended page size (items per page)
function GetPageSize() as Integer
    tier = GetDeviceMemoryTier()
    if tier = "high" then
        return 50
    else if tier = "medium" then
        return 30
    else
        return 20
    end if
end function

' Get a poster decode size recommendation based on memory tier.
' R6.8: Memory tier feeds poster decode size - lower tier devices decode smaller posters.
' @return Integer - recommended poster dimension (width/height in pixels)
function GetPosterDecodeSize() as Integer
    tier = GetDeviceMemoryTier()
    if tier = "high" then
        return 400
    else if tier = "medium" then
        return 300
    else
        return 200
    end if
end function

' Get device diagnostics string for logging.
' R7.8: Device model and video mode appear in diagnostics output.
' @return String - formatted diagnostics string
function GetDeviceDiagnostics() as String
    info = DeviceInfoData()
    return "device=" + info.model + " videoMode=" + info.videoMode + " memoryTier=" + info.memoryTier + " (" + info.totalMemoryMB.toStr() + "MB)"
end function

' ===========================================
' R7.12: i18n Initialization
' Loads locale strings from the bundled strings.json on app startup.
' Called from PhlixApp.Init after device capabilities are initialized.
' ===========================================
function InitLocale() as Void
    LoadLocaleStrings()
end function

' ===========================================
' Admin State (R7.9)
' Tracks whether the current logged-in user is an admin.
' Set by HomeScene.OnMeResponse after /auth/me returns.
' Used by AdminScene to gate Live TV and other admin-only menu items.
' Function-property pattern provides module-level persistence.
' ===========================================
function SetIsAdmin(value as Boolean) as Void
    SetIsAdmin.isAdmin = value
end function

function GetIsAdmin() as Boolean
    v = SetIsAdmin.isAdmin
    if v = invalid then return false
    return v
end function


