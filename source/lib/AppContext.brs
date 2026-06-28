' source/lib/AppContext.brs

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

' Build an ApiClient bound to the configured server URL with any persisted
' auth token / session id restored from Storage.
' @return Object - A ready-to-use ApiClient instance
function GetApiClient() as Object
    api = ApiClient(GetServerUrl())
    token = Storage.get("auth_token")
    if token <> invalid and token <> "" then api.token = token
    refreshToken = Storage.get("refresh_token")
    if refreshToken <> invalid and refreshToken <> "" then api.refreshToken = refreshToken
    sid = Storage.get("session_id")
    if sid <> invalid and sid <> "" then api.sessionId = sid
    return api
end function
