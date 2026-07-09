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

    ' Set up button handlers
    if m.loginButton <> invalid then
        m.loginButton.ObserveField("buttonSelected", "OnLoginPressed")
    end if

    ' Load saved credentials
    savedUsername = Storage.get("username")
    if savedUsername <> "" and savedUsername <> invalid then
        if m.usernameInput <> invalid then
            m.usernameInput.text = savedUsername
        end if
    end if
end sub

sub OnLoginPressed()
    username = ""
    password = ""

    if m.usernameInput <> invalid then
        username = m.usernameInput.text
    end if

    if m.passwordInput <> invalid then
        password = m.passwordInput.text
    end if

    ' Validate inputs
    if username = "" or password = "" then
        ShowError("Please enter username and password")
        return
    end if

    ' Save username (server_url is owned by the Connect screen now). m.api is
    ' already bound to the connected server_url via GetApiClient in Init.
    Storage.set("username", username)

    ' Show loading status
    ShowStatus("Logging in...")

    ' Perform login
    result = m.auth.login(username, password)

    if result.success then
        ' Clear any errors
        HideError()
        HideStatus()

        ' F12b hub detection: a hub exposes GET /me/servers ({servers:[...]});
        ' a direct server does not (404 -> no .servers array). m.api was built
        ' from GetApiClient in Init; at login active_server_id is empty so the
        ' media base falls back to the bare connect url -> this probes the
        ' actual endpoint we logged into. Persist the kind, then fire the
        ' matching transition field (PhlixApp observes both).
        serversResp = m.api.getMyServers()
        if serversResp <> invalid and serversResp.DoesExist("servers") and type(serversResp.servers) = "roArray" then
            ' It's a hub -> let PhlixApp show the server picker.
            Storage.set("connection_kind", "hub")
            Print "Hub detected"
            m.top.hubDetected = true
        else
            ' Direct server -> go straight to Home.
            Storage.set("connection_kind", "direct")
            Print "Login successful"
            m.top.loginSucceeded = true
        end if
    else
        ShowError("Login failed. Please check your credentials.")
        HideStatus()
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