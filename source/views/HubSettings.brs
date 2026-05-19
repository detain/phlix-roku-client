' source/views/HubSettings.brs

' ===========================================
' Hub Settings Scene
' Hub URL configuration, authentication, and server selection
' ===========================================

function HubSettingsScene() as Object
    obj = {
        top: invalid

        ' UI nodes
        hubUrlInput: invalid
        usernameInput: invalid
        passwordInput: invalid
        signInButton: invalid
        signOutButton: invalid
        serversList: invalid
        connectionModeDirect: invalid
        connectionModeRelay: invalid
        statusLabel: invalid
        errorLabel: invalid

        ' State
        hubAuth: invalid
        hubConfig: invalid
        servers: []

        ' Initialize the scene
        init: function(top as Object)
            m.top = top
            m.top.SetFocus(true)

            ' Create hub auth and config managers
            m.hubAuth = HubAuth()
            m.hubConfig = HubConfig()

            ' Find UI nodes
            m.hubUrlInput = m.top.FindNode("hubUrlInput")
            m.usernameInput = m.top.FindNode("usernameInput")
            m.passwordInput = m.top.FindNode("passwordInput")
            m.signInButton = m.top.FindNode("signInButton")
            m.signOutButton = m.top.FindNode("signOutButton")
            m.serversList = m.top.FindNode("serversList")
            m.connectionModeDirect = m.top.FindNode("connectionModeDirect")
            m.connectionModeRelay = m.top.FindNode("connectionModeRelay")
            m.statusLabel = m.top.FindNode("statusLabel")
            m.errorLabel = m.top.FindNode("errorLabel")

            ' Set up button handlers
            if m.signInButton <> invalid then
                m.signInButton.ObserveField("buttonSelected", "OnSignInPressed")
            end if
            if m.signOutButton <> invalid then
                m.signOutButton.ObserveField("buttonSelected", "OnSignOutPressed")
            end if
            if m.connectionModeDirect <> invalid then
                m.connectionModeDirect.ObserveField("buttonSelected", "OnDirectModeSelected")
            end if
            if m.connectionModeRelay <> invalid then
                m.connectionModeRelay.ObserveField("buttonSelected", "OnRelayModeSelected")
            end if

            ' Load saved values
            m.loadSavedState()

            ' Update UI based on current state
            m.updateUiState()
        end function

        ' Load saved hub configuration
        loadSavedState: function()
            ' Load hub URL
            savedHubUrl = Storage.get("hub_url")
            if savedHubUrl <> "" and savedHubUrl <> invalid then
                if m.hubUrlInput <> invalid then
                    m.hubUrlInput.text = savedHubUrl
                end if
                m.hubConfig.hubUrl = savedHubUrl
            end if

            ' Load connection mode
            savedMode = Storage.get("connection_mode")
            if savedMode = "relay" then
                m.hubConfig.setConnectionMode("relay")
            else
                m.hubConfig.setConnectionMode("direct")
            end if

            ' Update connection mode radio buttons
            m.updateConnectionModeUi()
        end function

        ' Update UI based on sign-in state
        updateUiState: function()
            isSignedIn = m.hubAuth.isSignedIn()

            ' Show/hide sign in form
            if m.usernameInput <> invalid then
                m.usernameInput.visible = not isSignedIn
            end if
            if m.passwordInput <> invalid then
                m.passwordInput.visible = not isSignedIn
            end if
            if m.signInButton <> invalid then
                m.signInButton.visible = not isSignedIn
            end if

            ' Show/hide sign out button
            if m.signOutButton <> invalid then
                m.signOutButton.visible = isSignedIn
            end if

            ' Show/hide servers list and connection mode when signed in
            if m.serversList <> invalid then
                m.serversList.visible = isSignedIn
            end if
            if m.connectionModeDirect <> invalid then
                m.connectionModeDirect.visible = isSignedIn
            end if
            if m.connectionModeRelay <> invalid then
                m.connectionModeRelay.visible = isSignedIn
            end if

            ' If signed in, load servers
            if isSignedIn then
                m.refreshServers()
            end if
        end function

        ' Update connection mode radio button UI
        updateConnectionModeUi: function()
            if m.connectionModeDirect <> invalid and m.connectionModeRelay <> invalid then
                if m.hubConfig.connectionMode = "relay" then
                    m.connectionModeDirect.checked = false
                    m.connectionModeRelay.checked = true
                else
                    m.connectionModeDirect.checked = true
                    m.connectionModeRelay.checked = false
                end if
            end if
        end function

        ' Refresh server list from hub
        refreshServers: function()
            m.showStatus("Loading servers...")

            m.servers = m.hubAuth.listServers()

            if m.servers.Count() = 0 then
                m.showError("No servers found or session expired")
                m.hideStatus()
                return
            end if

            m.hideError()
            m.hideStatus()
            m.populateServersList()
        end function

        ' Populate servers list UI
        populateServersList: function()
            if m.serversList = invalid then return

            ' Create content node for list
            content = CreateObject("roSGNode", "ContentNode")

            for each server in m.servers
                item = content.CreateChild("ContentNode")
                item.title = server.name
                item.url = server.serverId
                item.description = server.hostname

                ' Mark active server
                if m.hubConfig.activeServer <> invalid and m.hubConfig.activeServer.serverId = server.serverId then
                    item.Icon = "checked"
                else
                    item.Icon = "unchecked"
                end if
            end for

            m.serversList.content = content
            m.serversList.ObserveField("itemSelected", "OnServerSelected")
        end function

        ' Handle sign in button press
        onSignInPressed: function()
            hubUrl = ""
            username = ""
            password = ""

            if m.hubUrlInput <> invalid then
                hubUrl = m.hubUrlInput.text
            end if
            if m.usernameInput <> invalid then
                username = m.usernameInput.text
            end if
            if m.passwordInput <> invalid then
                password = m.passwordInput.text
            end if

            ' Validate inputs
            if hubUrl = "" then
                m.showError("Please enter hub URL")
                return
            end if

            if username = "" or password = "" then
                m.showError("Please enter username and password")
                return
            end if

            ' Save hub URL
            m.hubConfig.setHubUrl(hubUrl)

            ' Show loading
            m.showStatus("Signing in...")

            ' Perform sign in
            success = m.hubAuth.signIn(hubUrl, username, password)

            if success then
                m.hideError()
                m.hideStatus()
                m.passwordInput.text = ""  ' Clear password
                m.updateUiState()
            else
                m.showError("Sign in failed. Check your credentials.")
                m.hideStatus()
            end if
        end function

        ' Handle sign out button press
        onSignOutPressed: function()
            m.hubAuth.signOut()
            m.hubConfig.clear()
            m.servers = []

            ' Clear form fields
            if m.usernameInput <> invalid then
                m.usernameInput.text = ""
            end if
            if m.passwordInput <> invalid then
                m.passwordInput.text = ""
            end if

            m.updateUiState()
            m.showStatus("Signed out")
            m.hideStatus()
        end function

        ' Handle server selection
        onServerSelected: function()
            if m.serversList = invalid then return

            index = m.serversList.itemSelected
            if index < 0 or index >= m.servers.Count() then return

            selectedServer = m.servers[index]
            m.hubConfig.setActiveServer(selectedServer)

            ' Update list to show selection
            m.populateServersList()

            m.showStatus("Server selected: " + selectedServer.name)
            m.hideStatus()
        end function

        ' Handle direct mode selection
        onDirectModeSelected: function()
            m.hubConfig.setConnectionMode("direct")
            m.updateConnectionModeUi()
        end function

        ' Handle relay mode selection
        onRelayModeSelected: function()
            m.hubConfig.setConnectionMode("relay")
            m.updateConnectionModeUi()
        end function

        ' Show status message
        showStatus: function(message as String)
            if m.statusLabel <> invalid then
                m.statusLabel.text = message
                m.statusLabel.visible = true
            end if
        end function

        ' Hide status message
        hideStatus: function()
            if m.statusLabel <> invalid then
                m.statusLabel.visible = false
            end if
        end function

        ' Show error message
        showError: function(message as String)
            if m.errorLabel <> invalid then
                m.errorLabel.text = message
                m.errorLabel.visible = true
            end if
        end function

        ' Hide error message
        hideError: function()
            if m.errorLabel <> invalid then
                m.errorLabel.visible = false
            end if
        end function

        ' Handle key events
        onKeyEvent: function(key as String, press as Boolean) as Boolean
            handled = false

            if press then
                if key = "back" then
                    handled = true
                end if
            end if

            return handled
        end function
    }

    return obj
end function

' Factory function alias
function HubSettingsSceneFactory() as Object
    return HubSettingsScene()
end function