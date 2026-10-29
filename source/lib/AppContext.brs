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

' Check whether the device reports it can decode a specific video format.
' R6.8: Gates direct play - if this returns false, PlayerScene goes straight
' to transcode.
'
' SDK contract (https://developer.roku.com/dev/docs/ifdeviceinfo, live 2026-10-29):
'   CanDecodeVideo(video_format As Object) As Object
' The parameter is ONE associative array of format options - keys "codec",
' "container", "profile", "level" - not positional strings, and the return
' is an associative array whose "result" key carries the Boolean. The method
' was added in Roku OS 7.10. Array keys are case-sensitive before Roku OS
' 14.1, so every key here is quoted in lower case. (The comment this file
' used to carry claimed a positional (codec, container, profile) Boolean
' signature; that API never existed, and calling it that way threw or
' yielded Invalid on every firmware - the M-ROKU-05 defect. CHECK35 keeps
' the fabricated form pinned dead.)
'
' Fail-OPEN policy when the gate itself is broken (method missing on
' pre-7.10 firmware, non-AA return, or no Boolean "result"): report "can
' decode" and let the play attempt proceed. Rationale: this is a capability
' gate, not a requirement - the server transcodes anything. A wrongly-closed
' gate taxes every video on that device with transcode latency and server
' load; a wrongly-open gate costs one player error, and PlayerScene's
' OnPlayerStateChange error fallback (transcodeAttempted-guarded) already
' starts a transcode from there.
' @param codec String - video codec (e.g., "h264", "h265", "vp9")
' @param container String - container format (e.g., "mp4", "mkv", "hls") - empty omits the key
' @param profile String - codec profile (e.g., "high", "main", "baseline") - empty omits the key
' @return Boolean - true if direct play is worth attempting
function DeviceCanDecodeVideo(codec as String, container as String, profile as String) as Boolean
    devInfoObj = CreateObject("roDeviceInfo")
    if not devInfoObj.HasMethod("CanDecodeVideo") then
        print "AppContext: CanDecodeVideo missing (pre-7.10 firmware); failing open to direct play"
        return true
    end if

    ' Options AA built at the boundary; keys the caller does not know (empty
    ' string) are omitted rather than sent empty, and "level" is never
    ' supplied - this resolver has no level knowledge.
    videoFormat = {"codec": codec}
    if container <> "" then videoFormat["container"] = container
    if profile <> "" then videoFormat["profile"] = profile

    decodeResult = devInfoObj.CanDecodeVideo(videoFormat)
    if type(decodeResult) <> "roAssociativeArray" then
        print "AppContext: CanDecodeVideo returned " type(decodeResult) ", not an AA; failing open to direct play"
        return true
    end if

    canDecode = decodeResult.Lookup("result")
    if type(canDecode) <> "Boolean" then
        print "AppContext: CanDecodeVideo returned no Boolean result; failing open to direct play"
        return true
    end if
    return canDecode
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
' M-ROKU-11: CHANNEL IDENTITY + LOCAL DIAGNOSTICS
' A retail user previously had no way to tell anyone WHAT was running or
' WHAT went wrong: no version left the device on the wire, the About screen
' showed a hardcoded string, and the only log story was a dev-mode telnet.
' This family closes all three with Roku's own mechanisms:
'   - identity comes from ifappinfo (roAppInfo) - firmware, not a literal;
'   - crash info comes from ifappmanager.GetLastExitInfo() - the OS-side
'     last-exit record, readable from the NEXT run (OS 13.0+);
'   - the error ring is honest UI-thread-local memory (no remote telemetry
'     endpoint is invented or called - there is nothing to call).
' Surface law (CHECK37): every call below is vendored in
' node_modules/brighterscript/dist/roku-types/data.json - ifappinfo
' GetVersion/GetID, ifdeviceinfo GetOSVersion, ifappmanager
' GetLastExitInfo/GetUptime (roTimespan TotalMilliseconds). Firmware
' availability is gated on GetOSVersion().major >= 13 via Val(), NOT on
' DoesExist() (roAppManager does not implement ifAssociativeArray, so
' component .DoesExist() is not a clean probe there).
' ===========================================

' Factory function for channel identity - returns cached singleton (Storage/
' DeviceInfoData function-object-cache pattern). Only the two fields this
' client actually consumes are carried (About screen + the wire header);
' roAppInfo.GetTitle()/GetValue() stay unread rather than cached dead.
' Docs: https://developer.roku.com/docs/references/brightscript/interfaces/ifappinfo.md
' GetVersion() returns the conglomerate manifest version "major.minor.build";
' make package stamps those fields from package.json via derive-version.sh,
' so the value tracks the release chain (CHECK41 R3) with no client literal.
' @return Object - {version, channelId} (Strings, never invalid)
function ChannelInfo() as Object
    if ChannelInfo._cache <> invalid then return ChannelInfo._cache

    appInfo = CreateObject("roAppInfo")
    version = appInfo.GetVersion()
    channelId = appInfo.GetID()

    ' Explicit branches, not IIF(): the firmware has a global IIF but this
    ' project's linter does not resolve it outside the one component that
    ' declares a local String-only copy (components/SettingsScene.brs), so
    ' source/lib code must not reach for it.
    if version = invalid then version = "unknown"
    if channelId = invalid then channelId = "unknown"

    ChannelInfo._cache = {
        version: version
        channelId: channelId
    }
    return ChannelInfo._cache
end function

' The channel version reported to the server on every request
' (X-Phlix-Client-Version, ApiClient) and on the About screen - ONE source.
' @return String - e.g. "1.0.1"
function GetChannelVersion() as String
    return ChannelInfo().version
end function

' Cached Roku OS version (ifdeviceinfo.GetOSVersion). Docs (live 2026-10-29,
' https://developer.roku.com/dev/docs/ifdeviceinfo#getosversion-as-object):
' returns an roAssociativeArray whose major / minor / revision / build values
' are STRINGS — never compare them numerically without Val().
' @return Object - {major, minor, revision, build} (Strings; empty when absent)
function DeviceOSVersion() as Object
    if DeviceOSVersion._cache <> invalid then return DeviceOSVersion._cache
    aa = CreateObject("roDeviceInfo").GetOSVersion()
    if aa = invalid then aa = {}
    DeviceOSVersion._cache = aa
    return DeviceOSVersion._cache
end function

' Human-readable OS stamp, all four firmware fields, uninterpreted.
' @return String - e.g. "13.4.6 (4127)"
function GetOSVersionString() as String
    v = DeviceOSVersion()
    return DiagnosticText(v.major) + "." + DiagnosticText(v.minor) + "." + DiagnosticText(v.revision) + " (" + DiagnosticText(v.build) + ")"
end function

' The major OS number for firmware gating (GetOSVersion().major is a String).
' @return Integer - 0 when the firmware gave nothing usable
function GetOSMajorVersion() as Integer
    major = DeviceOSVersion().major
    if major = invalid then return 0
    return Val(major)
end function

' String-safe rendering of any firmware scalar for the {token} substitution
' path (ApplyNamedTokens works on Strings; GetLastExitInfo mixes String and
' Integer values across firmware versions, so nothing is assumed). An empty
' string reads as "unknown" too: on a diagnostics surface a blank tells the
' reader nothing about whether the field existed.
' @param value Object|invalid - firmware value
' @return String - printable text, "unknown" when nothing usable
function DiagnosticText(value as Object) as String
    if value = invalid then return "unknown"
    t = type(value)
    if t = "String" or t = "roString" then
        if value = "" then return "unknown"
        return value
    end if
    if t = "Integer" or t = "roInteger" or t = "LongInteger" or t = "roLongInt" then
        return Str(value).trim()
    end if
    return "unknown"
end function

' The OS-side record of why the PREVIOUS run ended.
' Docs: https://developer.roku.com/dev/docs/ifappmanager (live 2026-10-29) -
' GetLastExitInfo() exists since Roku OS 13.0 and returns invalid when no
' exits were recorded. Keys: timestamp (ISO 8601), exit_code (memory-related
' values include EXIT_CHANNEL_MEM_LIMIT_FG/BG, EXIT_OUT_OF_MEMORY,
' EXIT_AM_LOWRESOURCE, EXIT_SYSTEM_KILL; EXIT_UNKNOWN otherwise), mem_limit
' (only on MEM_LIMIT codes), app_state, media_player_state, and console_log -
' the LAST 20 console lines - which only exists when the manifest sets
' run_as_process=1. This manifest does NOT set it, so console_log is absent
' on Phlix and the docs say so instead of pretending otherwise.
' @return Object|invalid - the raw exit record, invalid when unavailable
function GetLastExitInfo() as Object
    if GetOSMajorVersion() < 13 then return invalid
    info = CreateObject("roAppManager").GetLastExitInfo()
    if info = invalid then return invalid
    if info.DoesExist("timestamp") then
        print "Last exit info: code=" info.exit_code " timestamp=" info.timestamp
    end if
    return info
end function

' ---------------------------------------------------------------------
' Last-N error ring (M-ROKU-11 "crash surface", honest scope)
'
' THREAD-LOCALITY LAW: BrightScript function-object properties (the
' RecordDiagnosticsError.* cache below) are per-thread state. RSG tasks
' (ApiTask & friends) run on their OWN threads, so a push from inside
' ApiClient would never be visible to the render thread that reads the
' About screen. The ring is therefore pushed ONLY at render-thread
' chokepoints (PhlixApp.HandleBootAuthFailure, SettingsScene.OnApiResponse
' failure arms); apiError is reserved for a future render-thread wrapper
' that already holds a classified reason.
' Cross-run visibility does NOT depend on this ring: the OS-side
' GetLastExitInfo() above records the run that already died.
' ---------------------------------------------------------------------

' Ring capacity - CHECK42 pins this literal.
function DiagnosticsRingSize() as Integer
    return 12
end function

' How many ring entries the About screen renders (oldest of those shown is
' dropped first). CHECK42 pins this literal so the doc and the code rotate
' together.
function DiagnosticsShownCount() as Integer
    return 5
end function

' Milliseconds since THIS run started. ifappmanager.GetUptime() does NOT
' return device uptime: the vendored typing (roku-types data.json) says it
' returns an roTimespan marked when the channel was launched, so
' TotalMilliseconds() is time since app start — exactly the ordering hint
' the ring wants. Docs:
' https://developer.roku.com/docs/references/brightscript/interfaces/ifappmanager.md
' https://developer.roku.com/docs/references/brightscript/interfaces/iftimespan.md
' @return LongInteger - elapsed milliseconds (0 when firmware gave nothing)
function GetRunElapsedMs() as LongInteger
    span = CreateObject("roAppManager").GetUptime()
    if span = invalid then return 0
    return span.TotalMilliseconds()
end function

' Append one failure verdict to the UI-thread ring, trimming to the last N.
' @param kind String - "bootAuth" | "settingsPrefs" | "settingsHistory" | "apiError"
' @param detail String - short technical context (path + reason)
sub RecordDiagnosticsError(kind as String, detail as String)
    ring = RecordDiagnosticsError._ring
    if ring = invalid then
        ring = []
        RecordDiagnosticsError._ring = ring
    end if
    seq = RecordDiagnosticsError._seq
    if seq = invalid then seq = 0
    seq = seq + 1
    RecordDiagnosticsError._seq = seq

    ring.Push({
        seq: seq
        kind: kind
        detail: detail
        elapsedSec: Int(GetRunElapsedMs() / 1000)
    })
    while ring.Count() > DiagnosticsRingSize()
        ring.Delete(0)
    end while
end sub

' Read-only copy of the ring, oldest first.
' @return Object - Array of {seq, kind, detail, elapsedSec}
function GetDiagnosticsRing() as Object
    ring = RecordDiagnosticsError._ring
    if ring = invalid then return []
    copy = []
    for each entry in ring
        copy.Push(entry)
    end for
    return copy
end function

' Empty the ring (support flow: clear, reproduce, read).
sub ClearDiagnosticsRing()
    RecordDiagnosticsError._ring = invalid
    RecordDiagnosticsError._seq = invalid
end sub

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


