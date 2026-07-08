' source/lib/AppContext.brs

' copyright 2026 Joe Huss
'


' ===========================================
' App Context for Roku
' Global accessor functions for shared app state.
' BrightScript has no global variables (only global functions), so the API
' client and server URL are exposed through these source-scope functions which
' are visible to every component. Each scene/manager builds a lightweight
' ApiClient via GetApiClient() that restores the persisted token/session from
' Storage, so per-scene state stays transient while auth survives navigation.
' ===========================================

' Get the configured server URL, falling back to the local default.
' @return String - The server base URL
function GetServerUrl() as String
    url = Storage.get("server_url")
    if url = invalid or url = "" then url = "http://localhost:8096"
    return url
end function

' True when a server URL has been chosen (persisted under "server_url" and
' non-empty). Boot gates on this: first run (no server_url) -> ConnectScene;
' otherwise the normal auth flow. GetServerUrl keeps its localhost fallback as a
' defensive default for any code path that reaches it before connect completes.
' @return Boolean - true when a non-empty server_url is persisted
function IsServerConnected() as Boolean
    url = Storage.get("server_url")
    return (url <> invalid and url <> "")
end function

' The connection kind for the persisted server: "hub" or "direct". An absent /
' empty / unrecognized value is treated as "direct" (the pre-F12b default), so
' existing direct installs are byte-unchanged. F12b's LoginScene probes
' /me/servers post-login to detect a hub and persists this.
' @return String - "hub" or "direct"
function GetConnectionKind() as String
    kind = Storage.get("connection_kind")
    if kind = "hub" then return "hub"
    return "direct"
end function

' The server the user picked on the ServerPickerScene (hub mode only). Empty
' when no server has been chosen yet (or in direct mode). The id is persisted as
' a stringified value by the picker (the relay path needs a String segment).
' @return String - the active server id, or ""
function GetActiveServerId() as String
    id = Storage.get("active_server_id")
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
' @return Object - A ready-to-use ApiClient instance
function GetApiClient() as Object
    api = ApiClient(GetMediaBaseUrl())
    token = Storage.get("auth_token")
    if token <> invalid and token <> "" then api.token = token
    refreshToken = Storage.get("refresh_token")
    if refreshToken <> invalid and refreshToken <> "" then api.refreshToken = refreshToken
    sid = Storage.get("session_id")
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
    token = Storage.get("auth_token")
    if token <> invalid and token <> "" then api.token = token
    refreshToken = Storage.get("refresh_token")
    if refreshToken <> invalid and refreshToken <> "" then api.refreshToken = refreshToken
    sid = Storage.get("session_id")
    if sid <> invalid and sid <> "" then api.sessionId = sid
    return api
end function