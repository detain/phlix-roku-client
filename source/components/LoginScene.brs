' source/components/LoginScene.brs

sub Init()
    m.top.SetFocus(true)

    ' UI nodes
    m.usernameInput = m.top.FindNode("usernameInput")
    m.passwordInput = m.top.FindNode("passwordInput")
    m.loginButton = m.top.FindNode("loginButton")
    m.serverInput = m.top.FindNode("serverInput")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.errorLabel = m.top.FindNode("errorLabel")

    ' Set up button handlers
    if m.loginButton <> invalid then
        m.loginButton.ObserveField("buttonSelected", "OnLoginPressed")
    end if

    ' Load saved server URL
    savedServerUrl = Storage.get("server_url")
    if savedServerUrl <> "" and savedServerUrl <> invalid then
        if m.serverInput <> invalid then
            m.serverInput.text = savedServerUrl
        end if
    else
        if m.serverInput <> invalid then
            m.serverInput.text = "http://localhost:8096"
        end if
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
    serverUrl = ""

    if m.usernameInput <> invalid then
        username = m.usernameInput.text
    end if

    if m.passwordInput <> invalid then
        password = m.passwordInput.text
    end if

    if m.serverInput <> invalid then
        serverUrl = m.serverInput.text
    end if

    ' Validate inputs
    if username = "" or password = "" then
        ShowError("Please enter username and password")
        return
    end if

    if serverUrl = "" then
        ShowError("Please enter server URL")
        return
    end if

    ' Save server URL and username
    Storage.set("server_url", serverUrl)
    Storage.set("username", username)

    ' Update API client with new server URL
    api.baseUrl = serverUrl

    ' Show loading status
    ShowStatus("Logging in...")

    ' Perform login
    result = authManager.login(username, password)

    if result.success then
        ' Clear any errors
        HideError()
        HideStatus()

        ' Report success to app
        Print "Login successful"
        m.top.OnLoginSuccess()
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