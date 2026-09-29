' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/LoginScene.brs

' copyright 2026 Joe Huss
'


sub Init()
    ApplyXmlChrome()
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
    ' The task will call GetHubApiClient() + ApiClient.login() internally
    ' (transport envelope in, unwrapped payload out at result.data).
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
    ' Fail fast on a malformed task frame before any member access.
    if result = invalid then
        ReEnableButton()
        HideStatus()
        ShowError("Cannot connect to server. Check your network.")
        return
    end if

    ' Stop any stale task state
    if m.apiTask <> invalid then
        m.apiTask.control = "stop"
    end if

    if result.op = "login" then
        ' ---- LOGIN RESPONSE ----
        ' ENVELOPE LAW: ApiTask answered with {op, ok, data = SERVER PAYLOAD,
        ' error}. The server/hub /auth/login body carries NO "success" key -
        ' the HTTP status behind ok is the verdict. The pre-fix
        ' `data.success = true` compare was therefore false on EVERY
        ' response and no login could ever succeed.
        ' Cases 1 & 2 & 3: login failed
        if result.ok <> true then
            ReEnableButton()
            HideStatus()

            ' Distinguish the failure cases: transport errors carry no
            ' payload; 4xx/5xx carry the server's {error} detail at
            ' result.data (with the same message lifted to result.error).
            transportError = result.error = "connect" or result.error = "timeout"
            detail = ""
            if result.data <> invalid and type(result.data) = "roAssociativeArray" then
                if result.data.DoesExist("error") and result.data.error <> invalid then
                    detail = result.data.error
                end if
            end if
            if detail = "" and result.error <> invalid then detail = result.error

            if transportError then
                ' Case 2: server unreachable / network error
                ShowError("Cannot connect to server. Check your network.")
            else if instr(1, lcase(detail), "invalid") > 0 or instr(1, lcase(detail), "credential") > 0 or instr(1, lcase(detail), "unauthorized") > 0 or instr(1, lcase(detail), "401") > 0 then
                ' Case 1: wrong credentials (common error strings from server)
                ShowError("Invalid username or password.")
            else if detail <> "" then
                ' Case 3: server error with detail
                ShowError("Server error: " + detail)
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

        ' Hub detection (docs/api-envelope.md): the ApiTask getMyServers
        ' branch answers with the UNWRAPPED payload - {servers:[...]} on a
        ' hub, {} for a DIRECT server (its 404 is the expected "no such
        ' route" signal, translated to ok=true + empty payload at the choke),
        ' and ok=false only on genuine failures (handled as Case 4 above).
        serversResp = result.data
        if serversResp <> invalid and serversResp.DoesExist("servers") and type(serversResp.servers) = "roArray" and serversResp.servers.count() > 0 then
            ' It's a hub -> let PhlixApp show the server picker.
            GetStorage().set("connection_kind", "hub")
            GetStorage().flush()  ' R1.6: persist before scene transition to ServerPicker
            m.top.hubDetected = true
        else
            ' Direct server -> go straight to Home.
            GetStorage().set("connection_kind", "direct")
            GetStorage().flush()  ' R1.6: persist before scene transition to Home
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

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            ' Don't allow back from login screen
            handled = true
        end if
    end if

    return handled
end function

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("usernameLabel")
    if n <> invalid then n.text = Translate("login_username")
    n = m.top.findNode("passwordLabel")
    if n <> invalid then n.text = Translate("login_password")
    n = m.top.findNode("loginButton")
    if n <> invalid then n.title = Translate("login_button")
end sub
