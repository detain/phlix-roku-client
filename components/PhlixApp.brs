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

    ' Bootstrap auth state tracking
    m.authCheckDone = false
    m.retryCount = 0
    m.bootLoadingLabel = m.top.FindNode("bootLoadingLabel")
    m.bootErrorGroup = m.top.FindNode("bootErrorGroup")
    m.bootErrorLabel = m.top.FindNode("bootErrorLabel")
    m.bootRetryButton = m.top.FindNode("bootRetryButton")

    ' First-run gate: with no server chosen yet, show the Connect screen. Only
    ' once a server_url is persisted do we run the normal auth flow.
    if not IsServerConnected() then
        HideBootUI()
        ShowConnect()
    else if GetConnectionKind() = "hub" then
        ' Hub mode: validate the HUB session against the BARE hub url - /auth/me
        ' over the relay returns the hub-user perspective on the server (the
        ' server has no such local user) and is unreliable, so we must hit the
        ' hub directly here, NOT GetApiClient (which is the relay base once a
        ' server is picked).
        m.hubApi = GetHubApiClient()
        m.hubAuth = AuthManager(m.hubApi)
        ' Show loading frame immediately; auth check runs on ApiTask with timeout
        StartHubAuthCheck()
    else
        ' Show loading frame immediately; auth check runs on ApiTask with timeout
        StartAuthCheck()
    end if
end sub

' StartAuthCheck - fires the direct-mode auth check on ApiTask (off render thread).
' Shows the loading label immediately so the user sees a frame before any network.
sub StartAuthCheck()
    m.authCheckDone = false
    m.retryCount = 0
    ShowBootLoading()

    ' Unhook any stale observers before replacing the old task/timer
    if m.authTask <> invalid then
        m.authTask.UnObserveField("response")
    end if
    if m.authTimer <> invalid then
        m.authTimer.UnObserveField("fire")
    end if

    ' Create single ApiTask for boot auth (serialized, not concurrent)
    m.authTask = CreateObject("roSGNode", "ApiTask")
    m.authTask.ObserveField("response", "OnAuthResponse")
    m.top.Append(m.authTask)

    ' 20-second scene-level timeout
    m.authTimer = CreateObject("roSGNode", "Timer")
    m.authTimer.SetDuration(20000)
    m.authTimer.ObserveField("fire", "OnAuthTimeout")
    m.authTimer.control = "start"

    m.authTask.request = { op: "checkAuth" }
    m.authTask.control = "run"
end sub

' StartHubAuthCheck - fires the hub-mode auth check on ApiTask.
sub StartHubAuthCheck()
    m.authCheckDone = false
    m.retryCount = 0
    ShowBootLoading()

    ' Unhook any stale observers before replacing the old task/timer
    if m.authTask <> invalid then
        m.authTask.UnObserveField("response")
    end if
    if m.authTimer <> invalid then
        m.authTimer.UnObserveField("fire")
    end if

    m.authTask = CreateObject("roSGNode", "ApiTask")
    m.authTask.ObserveField("response", "OnHubAuthResponse")
    m.top.Append(m.authTask)

    m.authTimer = CreateObject("roSGNode", "Timer")
    m.authTimer.SetDuration(20000)
    m.authTimer.ObserveField("fire", "OnAuthTimeout")
    m.authTimer.control = "start"

    m.authTask.request = { op: "checkAuthHub" }
    m.authTask.control = "run"
end sub

sub ShowBootLoading()
    if m.bootLoadingLabel <> invalid then
        m.bootLoadingLabel.visible = true
    end if
    if m.bootErrorGroup <> invalid then
        m.bootErrorGroup.visible = false
    end if
end sub

sub ShowBootError(msg as String)
    if m.bootLoadingLabel <> invalid then
        m.bootLoadingLabel.visible = false
    end if
    if m.bootErrorGroup <> invalid then
        m.bootErrorGroup.visible = true
        if m.bootErrorLabel <> invalid then
            m.bootErrorLabel.text = msg
        end if
    end if
    ' Wire retry button so timeout-triggered AND manually-shown errors both retry
    if m.bootRetryButton <> invalid then
        m.bootRetryButton.ObserveField("buttonSelected", "OnBootRetryButton")
    end if
end sub

sub HideBootUI()
    if m.bootLoadingLabel <> invalid then
        m.bootLoadingLabel.visible = false
    end if
    if m.bootErrorGroup <> invalid then
        m.bootErrorGroup.visible = false
    end if
end sub

' OnAuthTimeout - scene-level 20s timeout for boot auth.
' Fires when ApiTask has not responded in 20s (server unreachable).
sub OnAuthTimeout()
    if m.authCheckDone then return
    m.authCheckDone = true

    ' Clean up the pending task
    if m.authTask <> invalid then
        m.top.RemoveChild(m.authTask)
        m.authTask = invalid
    end if
    if m.authTimer <> invalid then
        m.authTimer.Stop()
    end if

    m.retryCount = m.retryCount + 1
    if m.retryCount <= 3 then
        ShowBootError("Can't reach the server")
    else
        ShowBootError("Unable to connect after multiple attempts")
    end if
end sub

' OnBootRetryButton - handles retry button press on the boot error screen.
sub OnBootRetryButton()
    ' Reset so StartAuthCheck can re-fire
    m.authCheckDone = false
    ' Stop any stale timer before starting a fresh one
    if m.authTimer <> invalid then
        m.authTimer.Stop()
    end if
    StartAuthCheck()
end sub

' OnAuthResponse - handles the direct-mode auth check result.
' Four distinct outcomes:
'   1. Authenticated -> ShowHome()
'   2. Not authenticated -> ShowLogin()
'   3. Timeout already fired -> ignore (error was already shown)
'   4. (Server error maps to outcome 2 - ShowLogin)
sub OnAuthResponse(event as Object)
    if m.authCheckDone then return
    m.authCheckDone = true

    if m.authTimer <> invalid then
        m.authTimer.Stop()
    end if

    if m.authTask = invalid or m.authTask <> event.GetNode() then return

    result = event.GetData()
    HideBootUI()

    ' Remove task from scene tree
    m.top.RemoveChild(m.authTask)
    m.authTask = invalid

    if result <> invalid and result.ok and result.data <> invalid then
        ' Outcome 1: Authenticated -> show home
        ShowHome()
    else
        ' Outcome 2: Not authenticated or server error -> show login
        ShowLogin()
    end if
end sub

' OnHubAuthResponse - handles the hub-mode auth check result.
' Four distinct outcomes:
'   1. Authenticated + server picked -> ShowHome()
'   2. Authenticated + no server picked -> ShowServerPicker()
'   3. Not authenticated -> ShowLogin()
'   4. Timeout already fired -> ignore (error was already shown)
sub OnHubAuthResponse(event as Object)
    if m.authCheckDone then return
    m.authCheckDone = true

    if m.authTimer <> invalid then
        m.authTimer.Stop()
    end if

    if m.authTask = invalid or m.authTask <> event.GetNode() then return

    result = event.GetData()
    HideBootUI()

    m.top.RemoveChild(m.authTask)
    m.authTask = invalid

    if result <> invalid and result.ok and result.data <> invalid then
        ' Outcome 1: Authenticated + server picked -> show home
        if GetActiveServerId() <> "" then
            ShowHome()
        else
            ' Outcome 2: Authenticated + no server picked -> show server picker
            ShowServerPicker()
        end if
    else
        ' Outcome 3: Not authenticated -> show login
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

    ' Fire auth check on ApiTask (off render thread). Uses the same 20s timeout
    ' and boot UI as the boot flow. Server unreachable shows error with retry.
    StartAuthCheck()
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
    ' R1.6: Invalidate the storage read cache so the next GetApiClient call
    ' picks up the new active_server_id without reading stale cached values.
    ResetCachedStorage(false)

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
    ' R1.3: Clear local state FIRST so logout works even if server unreachable.
    ' R1.6: ResetCachedStorage(fullReset) uses DeleteAll+Flush (1 NVRAM write
    ' instead of 6 separate delete+flush cycles) and invalidates the read cache.
    ResetCachedStorage(true)

    ' Clear the screen stack (stale references to removed nodes) and remove all
    ' children so the next Show* call starts from a clean scene tree.
    m.screenStack.Clear()
    while m.top.GetChildCount() > 0
        m.top.RemoveChild(m.top.GetChild(0))
    end while

    ShowLogin()

    ' Fire server-side session teardown off the render thread (fire-and-forget).
    ' Uses GetServerUrl() directly so baseUrl is correct even though m.api.baseUrl
    ' may have been cleared above. OnLogout has already cleared local credentials
    ' so the user is safely logged out locally regardless of server reachability.
    logoutTask = CreateObject("roSGNode", "ApiTask")
    logoutTask.request = { op: "logout" }
    m.top.Append(logoutTask)
    logoutTask.control = "run"
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