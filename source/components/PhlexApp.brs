' source/components/PhlexApp.brs
' @fileoverview PhlexApp - Main application controller for SceneGraph
' @author Phlex Team
' @version 1.0.0
' @requires ApiClient, Storage, AuthManager, SessionManager, LibraryManager, TaskManager
'
' @description
' PhlexApp is the root component of the Phlex Roku application. It serves as the
' main application controller and is responsible for:
' - Initializing the API client and managers
' - Checking for existing authentication sessions
' - Navigating between scenes (Login, Home, Library, etc.)
' - Handling global key events
' - Managing application state
'
' @example
' ```brightscript
' ' PhlexApp is automatically created by SceneGraph
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
' Phlex Main App Component
' Main application entry point for SceneGraph
' ===========================================

sub Init()
    print "Phlex App Init"

    ' Initialize API client with server URL from registry or default
    serverUrl = Storage.get("server_url")
    if serverUrl = "" or serverUrl = invalid then
        serverUrl = "http://localhost:8096"
    end if

    ' Initialize global API client
    api = ApiClient(serverUrl)

    ' Initialize managers
    authManager = AuthManager()
    sessionManager = SessionManager()
    libraryManager = LibraryManager()
    taskManager = TaskManager()

    ' Check for existing session
    if authManager.checkAuth() then
        ' User is already logged in, show home
        ShowHome()
    else
        ' Show login screen
        ShowLogin()
    end if
end sub

sub ShowLogin()
    loginScene = CreateObject("roSGNode", "LoginScene")
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
    sessionManager.endSession()
    authManager.logout()

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