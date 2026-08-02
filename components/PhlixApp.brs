'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/components/PhlixApp.brs

' copyright 2026 Joe Huss
'

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

    ' Screen stack for tracking pushed scenes. Each entry is the roSGNode that
    ' was pushed. Bootstrap scenes (Connect, Login, ServerPicker, Home) are NOT
    ' tracked here; they are managed by Show* methods + On* handlers.
    m.screenStack = []

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
    else if GetConnectionKind() = "hub" then
        ' Hub mode: validate the HUB session against the BARE hub url - /auth/me
        ' over the relay returns the hub-user perspective on the server (the
        ' server has no such local user) and is unreliable, so we must hit the
        ' hub directly here, NOT GetApiClient (which is the relay base once a
        ' server is picked).
        m.hubApi = GetHubApiClient()
        m.hubAuth = AuthManager(m.hubApi)
        if m.hubAuth.checkAuth() then
            if GetActiveServerId() <> "" then
                ShowHome()
            else
                ShowServerPicker()
            end if
        else
            ShowLogin()
        end if
    else if m.auth.checkAuth() then
        ' Direct mode: user is already logged in, show home
        ShowHome()
    else
        ' Show login screen
        ShowLogin()
    end if
end sub

' PushScreen - Creates, shows, and tracks a child scene on the screen stack.
'
' Creates a node of the given type, appends it as a child of m.top, sets focus
' on it, records it on the stack, and returns it. The caller may then call
' additional setup methods on the returned node (LoadLibrary, Show, etc.).
'
' @param nodeType {String} - The SceneGraph node type name (e.g. "LibraryScene")
' @param params {Object} - Optional params passed to setup methods (unused here;
'                          caller drives setup after PushScreen returns the node)
' @returns {Object} - The newly created roSGNode
function PushScreen(nodeType as String, params as Object) as Object
    scene = CreateObject("roSGNode", nodeType)
    ' Observe requestClose so the child can ask to be popped without touching
    ' its parent. When the child sets m.top.requestClose = true, this handler
    ' fires and PopScreen is called.
    scene.ObserveField("requestClose", "OnChildRequestClose")
    m.top.Append(scene)
    scene.SetFocus(true)
    m.screenStack.Push(scene)
    return scene
end function

' PopScreen - Removes the top scene from the stack and restores focus.
'
' Removes the most-recently-pushed scene (if any), removes it from m.top,
' calls SetFocus(true) on the newly-exposed node so the remote stays alive,
' and returns true. If the stack is empty returns false so the caller knows
' to exit the channel.
'
' @returns {Boolean} - True if a scene was popped; false if the stack is
'                      empty, signaling the caller should exit the channel
function PopScreen() as Boolean
    if m.screenStack.Count() = 0 then
        return false
    end if

    popped = m.screenStack.Pop()
    ' Unobserve to prevent leaks after removal; then remove from the scene tree.
    popped.UnObserveField("requestClose")
    m.top.RemoveChild(popped)

    ' Restore focus to the newly-exposed node so the remote stays alive.
    ' Per Roku SceneGraph focus rules, SetFocus on a Scene node makes it the
    ' focused scene. The child is responsible for ensuring one of its
    ' interactive children has focus when its Init runs.
    ' Ref: https://developer.roku.com/docs/developer-program/core-concepts/
    '          focus-management.md
    if m.screenStack.Count() > 0 then
        topNode = m.screenStack.Peek()
        topNode.SetFocus(true)
    end if

    return true
end function

' OnChildRequestClose - Called when a pushed child scene raises requestClose.
'
' The child has set m.top.requestClose = true to request removal without
' knowing its parent. This handler is registered by PushScreen for every node
' that is added to the stack.
'
' @param event {Object} - The roSGNodeEvent (unused; the field value is always
'                         true by the time this fires)
sub OnChildRequestClose(event as Object)
    PopScreen()
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
    ' Observe BOTH outcomes: a direct login -> Home, OR a hub login (the
    ' /me/servers probe found a hub) -> the server picker.
    loginScene.ObserveField("loginSucceeded", "OnLoginSuccess")
    loginScene.ObserveField("hubDetected", "OnHubDetected")
    m.top.Append(loginScene)
    loginScene.SetFocus(true)
end sub

sub OnHubDetected()
    ' Remove the login child, then show the server picker.
    m.top.RemoveChild(m.top.GetChild(m.top.GetChildCount() - 1))
    ShowServerPicker()
end sub

sub ShowServerPicker()
    pickerScene = CreateObject("roSGNode", "ServerPickerScene")
    pickerScene.ObserveField("serverPicked", "OnServerPicked")
    m.top.Append(pickerScene)
    pickerScene.SetFocus(true)
end sub

sub OnServerPicked()
    ' Remove the picker child.
    m.top.RemoveChild(m.top.GetChild(m.top.GetChildCount() - 1))

    ' Rebuild the shared API client + managers so they bind to the relay base
    ' (GetApiClient now returns the relay url because active_server_id is set).
    ' A manager left bound to the pre-pick (bare hub) base would silently route
    ' media calls to the wrong place - same lesson as OnConnected.
    m.api = GetApiClient()
    m.auth = AuthManager(m.api)
    m.session = SessionManager(m.api)
    m.library = LibraryManager(m.api)

    ShowHome()
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

    ' Clear hub-mode keys so we return to a clean login on the same server/hub.
    ' KEEP server_url (the connect endpoint) so we don't re-prompt for it.
    ' auth.logout already cleared the token/refresh/session.
    GetStorage().delete("connection_kind")
    GetStorage().delete("active_server_id")
    GetStorage().delete("active_server_name")

    ' Clear the screen stack (stale references to removed nodes) and remove all
    ' children so the next Show* call starts from a clean scene tree.
    m.screenStack.Clear()
    while m.top.GetChildCount() > 0
        m.top.RemoveChild(m.top.GetChild(0))
    end while

    ShowLogin()
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            ' Handle back button via the screen stack. PopScreen removes the top
            ' pushed scene and calls SetFocus(true) on the newly-exposed node,
            ' fixing the pre-stack bug where the remote went dead after one Back.
            ' PopScreen returns false when the stack is empty, meaning we are at
            ' the root and the channel should exit (certification item 6).
            handled = PopScreen()
        end if
    end if

    return handled
end sub