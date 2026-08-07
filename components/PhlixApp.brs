'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/components/PhlixApp.brs

' copyright 2026 Joe Huss
'

' @fileoverview PhlixApp - Main application controller for SceneGraph
' @author Phlix Team
' @version 1.0.0
' @requires ApiClient, Storage, AuthManager
' @note R7.5: SessionManager, LibraryManager, and TaskManager were removed — they
' wrapped ApiClient 1:1 and scenes call ApiClient/ApiTask directly instead.
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

    ' R7.5: Initialize AuthManager only. SessionManager, LibraryManager, and
    ' TaskManager were deleted — they wrapped ApiClient 1:1 and added no value;
    ' scenes call ApiClient/ApiTask directly instead.
    m.auth = AuthManager(m.api)

    ' R6.8: Initialize device capabilities once at boot for use throughout the app.
    ' Records model, videoMode, and memory tier; gates direct play via DeviceCanDecodeVideo.
    InitDeviceInfo()

    ' R7.12: Load i18n strings on startup
    InitLocale()

    ' Bootstrap auth state tracking
    m.authCheckDone = false
    m.retryCount = 0
    m.bootLoadingLabel = m.top.FindNode("bootLoadingLabel")
    m.bootErrorGroup = m.top.FindNode("bootErrorGroup")
    m.bootErrorLabel = m.top.FindNode("bootErrorLabel")
    m.bootRetryButton = m.top.FindNode("bootRetryButton")

    ' R3.4: Initialize toast manager
    m.toastManager = GetToastManager()
    m.toastManager.setScene(m.top)

    ' R6.3: Capture cold-launch deep-link params passed from main.brs.
    ' Stored so they can be processed after the auth flow completes.
    m.deepLinkParams = invalid
    if m.top.deepLinkParams <> invalid and type(m.top.deepLinkParams) = "roAssociativeArray" then
        m.deepLinkParams = m.top.deepLinkParams
        print "Deep link params captured: action=" m.deepLinkParams.action
    end if

    ' R6.3: Check for a pending deep link from a previous unauthenticated attempt.
    ' If the user deep-linked while signed out, we stashed the params and resume
    ' after they log in successfully (see ProcessDeepLinkAfterLogin).
    pendingDeepLink = GetStorage().get("pending_deep_link")
    if pendingDeepLink <> invalid and pendingDeepLink <> "" then
        ' Parse the JSON we stashed; if it fails treat as no pending link.
        parsed = ParseJson(pendingDeepLink)
        if parsed <> invalid and parsed.contentId <> invalid then
            m.deepLinkParams = parsed
            print "Resuming pending deep link: action=" m.deepLinkParams.action
        end if
        ' Clear it whether or not it was valid — we only resume once per app run.
        GetStorage().set("pending_deep_link", "")
        GetStorage().flush()
    end if

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
'   1. Authenticated + deep link -> process deep link (R6.3)
'   2. Authenticated + no deep link -> ShowHome()
'   3. Not authenticated + deep link -> stash deep link, ShowLogin()
'   4. Not authenticated / server error -> ShowLogin() (R6.3: no deep link to stash)
'   5. Timeout already fired -> ignore (error was already shown)
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
        ' Authenticated — check for a pending deep link (R6.3)
        if m.deepLinkParams <> invalid then
            ' Authenticated with a deep link: process it instead of showing home
            ProcessDeepLink()
        else
            ' Outcome 2: Authenticated, no deep link -> show home
            ShowHome()
        end if
    else
        ' Not authenticated or server error
        ' R6.3: Stash deep link so it can be resumed after login
        if m.deepLinkParams <> invalid then
            stashJson = FormatJson(m.deepLinkParams)
            if stashJson <> "" then
                GetStorage().set("pending_deep_link", stashJson)
                GetStorage().flush()
            end if
            print "Deep link stashed for post-login resume"
        end if
        ' Derive error message since restoreSession doesn't populate result.error
        if result <> invalid and result.data = invalid then
            ShowErrorDialog(m.top, "Connection Error", "Unable to reach server. Please check your network.")
        else
            ShowErrorDialog(m.top, "Session Expired", "Your session has expired. Please log in again.")
        end if
        ShowLogin()
    end if
end sub

' OnHubAuthResponse - handles the hub-mode auth check result.
' Five distinct outcomes:
'   1. Authenticated + server picked + deep link -> process deep link (R6.3)
'   2. Authenticated + server picked + no deep link -> ShowHome()
'   3. Authenticated + no server picked -> ShowServerPicker()
'   4. Not authenticated + deep link -> stash deep link, ShowLogin()
'   5. Not authenticated + no deep link -> ShowLogin()
'   6. Timeout already fired -> ignore (error was already shown)
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
        ' Authenticated
        if GetActiveServerId() <> "" then
            ' Outcome 1 & 2: server is picked
            if m.deepLinkParams <> invalid then
                ProcessDeepLink()
            else
                ShowHome()
            end if
        else
            ' Outcome 3: server not yet picked -> server picker
            ShowServerPicker()
        end if
    else
        ' Not authenticated or server error
        ' R6.3: Stash deep link so it can be resumed after login
        if m.deepLinkParams <> invalid then
            stashJson = FormatJson(m.deepLinkParams)
            if stashJson <> "" then
                GetStorage().set("pending_deep_link", stashJson)
                GetStorage().flush()
            end if
            print "Deep link stashed for post-login resume"
        end if
        ' Derive error message since restoreSession doesn't populate result.error
        if result <> invalid and result.data = invalid then
            ShowErrorDialog(m.top, "Connection Error", "Unable to reach server. Please check your network.")
        else
            ShowErrorDialog(m.top, "Session Expired", "Your session has expired. Please log in again.")
        end if
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

    ' Rebuild the shared API client + AuthManager so they bind to the newly
    ' persisted server_url (the originals were built against the absent default).
    m.api = GetApiClient()
    m.auth = AuthManager(m.api)

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

    ' Rebuild the shared API client + AuthManager so they bind to the relay base
    ' (GetApiClient now returns the relay url because active_server_id is set).
    ' A manager left bound to the pre-pick (bare hub) base would silently route
    ' media calls to the wrong place - same lesson as OnConnected.
    m.api = GetApiClient()
    m.auth = AuthManager(m.api)

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
    ' R6.3: If a deep link was stashed (user deep-linked while signed out),
    ' ProcessDeepLinkAfterLogin will be called by the login observer chain.
    ' Check for pending deep link first.
    pendingDeepLink = GetStorage().get("pending_deep_link")
    if pendingDeepLink <> invalid and pendingDeepLink <> "" then
        parsed = ParseJson(pendingDeepLink)
        if parsed <> invalid and parsed.contentId <> invalid then
            m.deepLinkParams = parsed
            GetStorage().set("pending_deep_link", "")
            GetStorage().flush()
            ProcessDeepLink()
            return
        end if
    end if
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

' R6.3: Process a validated deep-link intent.
' Fetches the item metadata from the server, then routes to the appropriate
' scene based on mediaType/action:
'   "play"  -> DetailScene with auto-play
'   "series"-> DetailScene with smart-bookmark episode selection + auto-play
'   "season"-> SeasonScene (episode picker)
' If the item is not found (404) or fetch fails, shows a content-not-found
' dialog (R3.1) and returns to the home screen.
'
' Uses ApiTask (m.deepLinkFetchTask) to fetch item metadata off the render thread.
' Navigation is driven by the response callback OnDeepLinkItemResponse.
sub ProcessDeepLink()
    if m.deepLinkParams = invalid then return

    contentId = m.deepLinkParams.contentId
    action = m.deepLinkParams.action

    print "Processing deep link: contentId=" contentId " action=" action

    if contentId = invalid or contentId = "" then
        ShowDeepLinkError()
        return
    end if

    ' Use the library manager to fetch the item metadata.
    ' R6.3: We need to get the item to validate it exists and get its details
    ' before routing. If the item doesn't exist, show the content-not-found
    ' dialog per R3.1 (not a blank screen).
    m.deepLinkFetchTask = CreateObject("roSGNode", "ApiTask")
    m.deepLinkFetchTask.ObserveField("response", "OnDeepLinkItemResponse")
    m.top.Append(m.deepLinkFetchTask)

    ' Build the request based on action type:
    ' - "play", "series" -> fetch the item directly (episode/movie itemId)
    ' - "season" -> for season, we fetch the season item to show the episode list
    ' For series, we may need to resolve which episode to play (smart bookmark).
    ' For now, treat series like play — the DetailScene will show the series
    ' overview; the user can navigate to episodes from there.
    ' TODO: smart-bookmark logic for series to auto-select next unwatched episode
    m.deepLinkFetchTask.request = { op: "getItem", itemId: contentId }
    m.deepLinkFetchTask.control = "run"
end sub

' OnDeepLinkItemResponse - callback for ProcessDeepLink item fetch.
' Handles three outcomes:
'   1. Fetch succeeded + item found -> route based on mediaType/action
'   2. Fetch failed (network error) -> show error dialog, go home
'   3. Item not found (404 / ok=false) -> show content-not-found dialog (R3.1)
sub OnDeepLinkItemResponse(event as Object)
    if m.deepLinkFetchTask = invalid or m.deepLinkFetchTask <> event.GetNode() then return

    result = event.GetData()
    m.top.RemoveChild(m.deepLinkFetchTask)
    m.deepLinkFetchTask = invalid

    if result = invalid or result.ok <> true then
        ' Network / server error
        print "Deep link fetch failed: " + type(result)
        ShowDeepLinkError()
        return
    end if

    if result.data = invalid then
        ' Item not found (R3.1: real dialog, not blank screen)
        print "Deep link item not found: " + m.deepLinkParams.contentId
        ShowContentNotFoundDialog()
        return
    end if

    item = result.data
    action = m.deepLinkParams.action

    ' Route based on the mediaType-derived action (R6.3 / Roku deep-linking spec)
    if action = "play" or action = "series" then
        ' "play": movie/episode/shortformvideo/tvspecial -> detail then auto-play
        ' "series": smart-bookmark series -> detail scene (smart bookmark handled there)
        ' Push DetailScene and tell it to auto-play when loaded.
        detailScene = PushScreen("DetailScene", {})
        detailScene.autoPlayOnLoad = true
        detailScene.LoadItem(item.id)
    else if action = "season" then
        ' season: show the season/episode picker scene
        ' item.name provides the display title for the season header
        seasonName = ""
        if item <> invalid and item.name <> invalid then seasonName = item.name
        seasonScene = PushScreen("SeasonScene", {})
        seasonScene.LoadSeason(item.id, seasonName)
    else
        ' Unknown action — fall back to home
        print "Unknown deep link action: " + action
        ShowHome()
    end if
end sub

' ShowContentNotFoundDialog - R3.1: display a real dialog when deep-linked content
' does not exist in the catalog (404 / item not found), rather than a blank screen.
' After the user dismisses the dialog they are returned to the home screen.
sub ShowContentNotFoundDialog()
    ShowErrorDialog(m.top, "Content Not Available", "This content is not available in your library. Please check your subscription or try again later.")
    ' After dialog, return to home
    ShowHome()
end sub

' ShowDeepLinkError - show a generic error dialog when deep-link processing fails
' due to a network or server error (not a missing-content case).
' Returns to home after dismissal.
sub ShowDeepLinkError()
    ShowErrorDialog(m.top, "Unable to Load Content", "Could not load the requested content. Please try again later.")
    ShowHome()
end sub

' R6.4: Handle a warm deep link that arrives via roInput while the channel is
' already running. If a player is active (mid-playback), stop it cleanly per
' R4.4 — report progress and completion — before navigating to the new content.
' Do NOT leave an orphaned session.
'
' @param deepLinkParams {Object} - Validated deep-link params from ExtractDeepLinkParams
'                                  { contentId, mediaType, action }
sub HandleWarmDeepLink(deepLinkParams as Object)
    if deepLinkParams = invalid then return

    m.deepLinkParams = deepLinkParams
    print "HandleWarmDeepLink: action=" deepLinkParams.action

    ' R6.4: If PlayerScene is active on the stack, stop playback cleanly.
    ' StopPlayback reports final progress and sends session completion (R4.4).
    ' Then ClosePlayer tears down the UI and triggers PopScreen via requestClose.
    playerScene = FindActivePlayerScene()
    if playerScene <> invalid then
        print "HandleWarmDeepLink: stopping active playback before deep link"
        playerScene.StopPlayback()
        playerScene.ClosePlayer()
        ' ClosePlayer set requestClose=true, which triggers PopScreen async.
        ' We need to wait one event loop tick for PopScreen to complete before
        ' we can push the new scene. Use a one-shot Timer to defer ProcessDeepLink.
        deferTimer = CreateObject("roSGNode", "Timer")
        deferTimer.duration = 0.1
        deferTimer.repeat = false
        deferTimer.ObserveField("fire", "OnWarmDeepLinkDeferred")
        m.top.Append(deferTimer)
        deferTimer.control = "start"
    else
        ' No active player — process the deep link immediately.
        ProcessDeepLink()
    end if
end sub

' R6.4: One-shot timer callback to defer ProcessDeepLink by one event-loop tick.
' This allows PopScreen (triggered by ClosePlayer's requestClose) to complete
' before we push a new scene onto the stack.
sub OnWarmDeepLinkDeferred()
    ProcessDeepLink()
end sub

' R6.4: Find PlayerScene on the screen stack, if it is the topmost scene.
' Returns the PlayerScene node if found, otherwise invalid.
' We identify PlayerScene by the presence of the videoPlayer node (set in Init).
' @returns {Object} - The PlayerScene roSGNode or invalid
function FindActivePlayerScene() as Object
    if m.screenStack.Count() = 0 then return invalid

    topScene = m.screenStack.Peek()
    if topScene <> invalid and type(topScene) = "roSGNode" then
        ' PlayerScene initializes m.videoPlayer in Init(). If this node exists
        ' and is currently playing or paused, we have an active playback session.
        if topScene.videoPlayer <> invalid then
            state = topScene.videoPlayer.state
            if state = "playing" or state = "paused" or state = "buffering" then
                return topScene
            end if
        end if
    end if
    return invalid
end function

function OnKeyEvent(key as String, press as Boolean) as Boolean
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
end function

' R3.4: Handle messages from child nodes (e.g., showToast from ToastManager)
sub onMessage(msg as Object)
    if msg = invalid then return

    messageType = ""
    data = invalid

    ' Extract message type and data from the roSGNodeEvent-style assoc
    if type(msg) = "roAssociativeArray" then
        if msg.DoesExist("messageType") then messageType = msg.messageType
        if msg.DoesExist("data") then data = msg.data
    end if

    if messageType = "showToast" then
        content = data
        toast = CreateObject("roSGNode", "ToastScene")
        toast.message = content.title
        toast.duration = content.duration
        m.top.ComponentController.Dialog = toast
    end if
end sub