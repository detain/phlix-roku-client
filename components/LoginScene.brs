' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/LoginScene.brs

' copyright 2026 Joe Huss
'


sub Init()
    m.top.SetFocus(true)

    ' Login + the /me/servers probe ALWAYS target the bare connect endpoint
    ' (the hub or direct server the user connected to), NEVER the relay base:
    ' a hub access token is minted by the HUB, so re-login while a hub server is
    ' still selected (kind="hub" + active_server_id set, e.g. after the hourly
    ' hub token expires) must hit the hub directly. GetApiClient would return the
    ' relay base in that state and the proxy's own AuthMiddleware would 401 the
    ' expired token before it ever tunnels. GetHubApiClient binds to the bare
    ' server_url, which is the correct login target in BOTH hub and direct mode.
    m.api = GetHubApiClient()
    m.auth = AuthManager(m.api)

    ' UI nodes
    m.usernameInput = m.top.FindNode("usernameInput")
    m.passwordInput = m.top.FindNode("passwordInput")
    m.loginButton = m.top.FindNode("loginButton")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.errorLabel = m.top.FindNode("errorLabel")

    ' ApiTask for async login + getMyServers (prevents render-thread freeze)
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnLoginResponse")
    m.top.Append(m.apiTask)

    ' Set up button handlers
    if m.loginButton <> invalid then
        m.loginButton.ObserveField("buttonSelected", "OnLoginPressed")
    end if

    ' Load saved credentials
    savedUsername = GetStorage().get("username")
    if savedUsername <> "" and savedUsername <> invalid then
        if m.usernameInput <> invalid then
            m.usernameInput.text = savedUsername
        end if
    end if
end sub

' OnLoginPressed - fires login on ApiTask and returns immediately.
' The render thread stays responsive while the network call runs off-thread.
' Immediate feedback: button disabled + "Signing in..." status shown.
sub OnLoginPressed()
    username = ""
    password = ""

    if m.usernameInput <> invalid then
        username = m.usernameInput.text
    end if

    if m.passwordInput <> invalid then
        password = m.passwordInput.text
    end if

    ' Validate inputs (fail fast before any async work)
    if username = "" or password = "" then
        ShowError("Please enter username and password")
        return
    end if

    ' Save username (server_url is owned by the Connect screen now)
    GetStorage().set("username", username)

    ' Immediate UI feedback: disable button + show status
    if m.loginButton <> invalid then
        m.loginButton.disabled = true
    end if
    ShowStatus("Signing in...")

    ' Fire login on ApiTask (off render thread) and return immediately.
    ' The task will call GetHubApiClient() + AuthManager.login() internally.
    m.apiTask.request = { op: "login", username: username, password: password }
    m.apiTask.control = "run"
end sub

' OnLoginResponse - single handler for both login and getMyServers responses.
' Distinguished by result.op. Serializes login -> getMyServers so they never
' run concurrently on the same task node.
'
' Four distinct failure outcomes:
'   1. Wrong credentials (401)          -> "Invalid username or password."
'   2. Server unreachable (no data)    -> "Cannot connect to server. Check your network."
'   3. Server error (5xx, other 4xx)   -> "Server error: <detail>"
'   4. Login ok but getMyServers fails -> "Unable to load servers. Try again."
sub OnLoginResponse(event as Object)
    result = event.GetData()

    ' Stop any stale task state
    if m.apiTask <> invalid then
        m.apiTask.control = "stop"
    end if

    if result.op = "login" then
        ' ---- LOGIN RESPONSE ----
        ' Case 1 & 2 & 3: login failed
        if result = invalid or result.ok <> true or result.data = invalid or result.data.success <> true then
            ReEnableButton()
            HideStatus()

            ' Distinguish the failure cases by examining result.data.error
            if result = invalid or result.data = invalid then
                ' Case 2: server unreachable / network error
                ShowError("Cannot connect to server. Check your network.")
            else if result.data.error <> invalid and result.data.error <> "" then
                errMsg = result.data.error
                ' Case 1: wrong credentials (common error strings from server)
                if instr(1, lcase(errMsg), "invalid") > 0 or instr(1, lcase(errMsg), "credential") > 0 or instr(1, lcase(errMsg), "unauthorized") > 0 or instr(1, lcase(errMsg), "401") > 0 then
                    ShowError("Invalid username or password.")
                else
                    ' Case 3: server error with detail
                    ShowError("Server error: " + errMsg)
                end if
            else
                ' Generic fallback
                ShowError("Login failed. Please check your credentials.")
            end if
            return
        end if

        ' Login succeeded. Clear errors and proceed to getMyServers (serialized).
        HideError()
        ShowStatus("Loading servers...")

        m.apiTask.request = { op: "getMyServers" }
        m.apiTask.control = "run"

    else if result.op = "getMyServers" then
        ' ---- GETMYSEVERS RESPONSE ----
        HideStatus()

        ' Case 4: getMyServers failed
        if result = invalid or result.ok <> true or result.data = invalid then
            ReEnableButton()
            ShowError("Unable to load servers. Try again.")
            return
        end if

        ' Hub detection: a hub exposes GET /me/servers ({servers:[...]});
        ' a direct server does not (404 -> no .servers array).
        serversResp = result.data
        if serversResp <> invalid and serversResp.DoesExist("servers") and type(serversResp.servers) = "roArray" and serversResp.servers.count() > 0 then
            ' It's a hub -> let PhlixApp show the server picker.
            GetStorage().set("connection_kind", "hub")
            m.top.hubDetected = true
        else
            ' Direct server -> go straight to Home.
            GetStorage().set("connection_kind", "direct")
            m.top.loginSucceeded = true
        end if
    end if
end sub

' ReEnableButton - re-enables the login button on every failure path.
sub ReEnableButton()
    if m.loginButton <> invalid then
        m.loginButton.disabled = false
    end if
end sub

sub ShowError(message as String)
    if m.errorLabel <> invalid then
        m.errorLabel.text = message
        m.errorLabel.visible = true
    end if
end sub

sub HideError()
    if m.errorLabel <> invalid then
        m.errorLabel.visible = false
    end if
end sub

sub ShowStatus(message as String)
    if m.statusLabel <> invalid then
        m.statusLabel.text = message
        m.statusLabel.visible = true
    end if
end sub

sub HideStatus()
    if m.statusLabel <> invalid then
        m.statusLabel.visible = false
    end if
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            ' Don't allow back from login screen
            handled = true
        end if
    end if

    return handled
end sub