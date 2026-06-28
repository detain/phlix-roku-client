' source/components/PhlixApp.brs
' @fileoverview PhlixApp - Main application controller for SceneGraph
' @author Phlix Team
' @version 1.0.0
' @requires ApiClient, Storage, AuthManager, SessionManager, LibraryManager, TaskManager
'
' @description
' PhlixApp is the root component of the Phlix Roku application. It serves as the
' main application controller and is responsible for:
' - Initializing the API client and managers
' - Checking for existing authentication sessions
' - Navigating between scenes (Login, Home, Library, etc.)
' - Handling global key events
' - Managing application state
'
' @example
' ```brightscript
' ' PhlixApp is automatically created by SceneGraph
' ' Handle login success transition
' m.top.OnLoginSuccess()
'
' ' Handle logout
' m.top.OnLogout()
' ```
'
' @component
' @extends Scene
' @interface
'   @field {String} data - Observable data for the app
' @events
'   @event OnLoginSuccess - Fired when user successfully logs in
'   @event OnLogout - Fired when user logs out

' ===========================================
' Phlix Main App Component
' Main application entry point for SceneGraph
' ===========================================

sub Init()
    print "Phlix App Init"

    ' Initialize the shared API client (restores token/session from Storage)
    m.api = GetApiClient()

    ' Initialize managers, sharing the single API client
    m.auth = AuthManager(m.api)
    m.session = SessionManager(m.api)
    m.library = LibraryManager(m.api)
    m.tasks = TaskManager()

    ' First-run gate: with no server chosen yet, show the Connect screen. Only
    ' once a server_url is persisted do we run the normal auth flow.
    if not IsServerConnected() then
        ShowConnect()
    else if m.auth.checkAuth() then
        ' User is already logged in, show home
        ShowHome()
    else
        ' Show login screen
        ShowLogin()
    end if
end sub

sub ShowConnect()
    connectScene = CreateObject("roSGNode", "ConnectScene")
    connectScene.ObserveField("connected", "OnConnected")
    m.top.Append(connectScene)
    connectScene.SetFocus(true)
end sub

sub OnConnected()
    ' Remove the connect child (the last-appended child).
    m.top.RemoveChild(m.top.GetChild(m.top.GetChildCount() - 1))

    ' Rebuild the shared API client + managers so they bind to the newly
    ' persisted server_url (the originals were built against the absent default).
    m.api = GetApiClient()
    m.auth = AuthManager(m.api)
    m.session = SessionManager(m.api)
    m.library = LibraryManager(m.api)

    ' First run: checkAuth is false -> ShowLogin.
    if m.auth.checkAuth() then
        ShowHome()
    else
        ShowLogin()
    end if
end sub

sub ShowLogin()
    loginScene = CreateObject("roSGNode", "LoginScene")
    loginScene.ObserveField("loginSucceeded", "OnLoginSuccess")
    m.top.Append(loginScene)
    loginScene.SetFocus(true)
end sub

sub ShowHome()
    homeScene = CreateObject("roSGNode", "HomeScene")
    m.top.Append(homeScene)
    homeScene.SetFocus(true)
end sub

sub OnLoginSuccess()
    ' Transition from login to home
    m.top.RemoveChild(m.top.GetChild(m.top.GetChildCount() - 1))
    ShowHome()
end sub

sub OnLogout()
    ' Clean up sessions
    m.session.endSession()
    m.auth.logout()

    ' Remove all children and show login
    while m.top.GetChildCount() > 0
        m.top.RemoveChild(m.top.GetChild(0))
    end while

    ShowLogin()
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            ' Handle back button
            if m.top.GetChildCount() > 1 then
                m.top.RemoveChild(m.top.GetChild(m.top.GetChildCount() - 1))
                handled = true
            end if
        end if
    end if

    return handled
end sub