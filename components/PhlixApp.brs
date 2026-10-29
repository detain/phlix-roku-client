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
    ApplyXmlChrome()
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
    ' M-ROKU-16 (review roku__gameux M1/m5): wire the retry button EXACTLY
    ' ONCE, here, where the node is resolved. ShowBootError used to
    ' ObserveField("buttonSelected") on every error display, so repeated
    ' retries accumulated duplicate handlers. The button is a static child of
    ' the root scene, so boot-time wiring is the natural single owner;
    ' ShowBootError now only focuses the button (focus + OK is what raises
    ' buttonSelected — an unfocused Button is visible but unpressable).
    if m.bootRetryButton <> invalid then
        m.bootRetryButton.ObserveField("buttonSelected", "OnBootRetryButton")
    end if

    ' R3.4: Initialize toast manager
    m.toastManager = GetToastManager()
    m.toastManager.setScene(m.top)

    ' M-ROKU-17: toast coordinator state (the coordinator subs live just
    ' below OnToastNotice). The
    ' queue gives every ambient notice its own screen time in FIFO order;
    ' activeToast names the Dialog we currently own (invalid when none),
    ' the shared root-attached timer runs under a single purpose flag, and
    ' the retry pair bounds the blocked-surface probe window (see
    ' ArmToastRetry). All live on the root scene, which is always in the
    ' render tree - a Timer only ticks while attached.
    m.toastQueue = []
    m.activeToast = invalid
    m.toastTimer = invalid
    m.toastTimerPurpose = ""
    m.toastRetryArmed = false
    m.toastRetryTicks = 0
    ' M-ROKU-17 r2 (review roku__gameux M17r1 CRITICAL-1): wire the dispatch
    ' arm on the root's own observed interface fields - the self-write
    ' idiom CollectionScene ships for requestClose
    ' (m.top.ObserveField("requestClose", "OnChildRequestClose") fired by
    ' m.top.requestClose = true). Producers reach these fields through the
    ' documented GetParent chain (see source/lib/ToastManager.brs).
    m.top.ObserveField("toastSeq", "OnToastNotice")

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
    ' M-ROKU-16 (review roku__gameux M1): move focus onto the retry Button.
    ' The pre-fix display showed the error chrome with no SetFocus anywhere,
    ' and buttonSelected requires focus + OK — after a 20s boot timeout the
    ' "Retry" control was visible but NOT pressable from the remote. This is
    ' the C20-era focus law at the boot surface: the control the user is
    ' expected to act on receives focus when it appears. The buttonSelected
    ' observer is wired once in Init (no per-error re-observe, m5 cure).
    ' Timeout-triggered AND manually-shown errors both land on a live Retry.
    if m.bootRetryButton <> invalid then
        m.bootRetryButton.SetFocus(true)
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
        ShowBootError(Translate("app_boot_cannot_reach"))
    else
        ShowBootError(Translate("app_boot_unable"))
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
        ' M-ROKU-04: the pre-fix oracle here was `result.data = invalid` —
        ' restoreSession leaves data invalid on EVERY false path (first run,
        ' dead token, dead server), so first-run users were told "Unable to
        ' reach server. Please check your network." by a screen that had just
        ' probed /health successfully, and the Session Expired branch below
        ' the else was unreachable dead text. The verdict now rides the
        ' restore REASON; see HandleBootAuthFailure.
        HandleBootAuthFailure(result)
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
            StartHubCommandConsumer()
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
        ' M-ROKU-04: the pre-fix oracle here was `result.data = invalid` —
        ' restoreSession leaves data invalid on EVERY false path (first run,
        ' dead token, dead server), so first-run users were told "Unable to
        ' reach server. Please check your network." by a screen that had just
        ' probed /health successfully, and the Session Expired branch below
        ' the else was unreachable dead text. The verdict now rides the
        ' restore REASON; see HandleBootAuthFailure.
        HandleBootAuthFailure(result)
    end if
end sub

' M-ROKU-04: the boot-auth failure ladder (shared by both modes). The reason
' recorded by ApiClient.restoreSession arrives as result.error (see the
' checkAuth branches in ApiTask.brs); each outcome lands on its HONEST
' surface:
'   no_session      - first run / after logout: NOT an error at all. Show the
'                     login screen silently (ShowLogin routes to ConnectScene
'                     when no server is configured, per the M-ROKU-03 law).
'   <transport>     - dns/refused/tls/timeout/unreachable/bad_url/
'                     redirect_refused: the server
'                     never answered. Route to ConnectScene - the address is
'                     prefilled and editable, the message is per-cause, and
'                     Find/retry affordances live there. A RETRY surface,
'                     never a dead dialog over a login form that cannot work.
'   session_invalid - the server answered and rejected the token. The
'                     "Session Expired" dialog finally has a live trigger
'                     (pre-fix it was unreachable text behind the invalid-
'                     data oracle that always took the network branch).
'   server_error    - answered, but /auth/me was malformed/5xx: say that.
sub HandleBootAuthFailure(result as Object)
    reason = ""
    ' M-ROKU-11 (M-ROKU-11 CHECK44 cure): result.error rides the wire lift -
    ' type-guard before the reason reaches compares/concat below (the ring
    ' detail and the reason = "..." dispatch arms both take it as String).
    if result <> invalid then reason = WireErrorText(result.error, "")

    ' M-ROKU-11: this is a render-thread chokepoint for every boot failure
    ' (direct and hub mode both land here), so it is one of the two legal
    ' diagnostics push sites. The ring is thread-local (see AppContext.brs);
    ' the About screen reads it from the same thread.
    if reason = "" then
        RecordDiagnosticsError("bootAuth", "reason=unknown")
    else
        RecordDiagnosticsError("bootAuth", "reason=" + reason)
    end if

    if reason = "no_session" then
        ShowLogin()
        return
    end if

    if IsTransportReason(reason) then
        ShowConnect(reason)
        return
    end if

    if reason = "session_invalid" then
        ShowErrorDialog(m.top, Translate("login_expired_title"), Translate("login_expired_message"))
    else
        ShowErrorDialog(m.top, Translate("common_error"), Translate("app_server_problem_message"))
    end if
    ShowLogin()
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

' Show the connect screen. M-ROKU-04: it doubles as the transport-failure
' RETRY surface - bootReason carries a transport bucket (ClassifyUrlFailure
' law) so the scene can prefill the saved address, show the per-cause honest
' message, and offer Find/Connect-anyway instead of a dead end.
sub ShowConnect(bootReason = "" as String)
    connectScene = CreateObject("roSGNode", "ConnectScene")
    if bootReason <> "" then connectScene.bootReason = bootReason
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
    ' M-ROKU-03 (AppContext law: callers MUST check IsServerConnected() before
    ' using GetServerUrl()): showing LoginScene with no server configured lets a
    ' login attempt POST to an empty base; the transport failure surfaces as
    ' "Cannot connect to server. Check your network" — a fake network error that
    ' dead-ends the user. Route to ConnectScene instead, where the server URL can
    ' actually be entered.
    if not IsServerConnected() then
        ShowConnect()
        return
    end if

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

    ' S298: the picked server changes the hub relay identity — rebind the
    ' pending_command consumer to the new server id.
    StopHubCommandConsumer()
    StartHubCommandConsumer()

    ShowHome()
end sub

sub ShowHome()
    homeScene = CreateObject("roSGNode", "HomeScene")
    m.top.Append(homeScene)
    homeScene.SetFocus(true)
end sub

' =============================================================================
' S298 — hub relay pending_command consumer lifecycle.
'
' "Alexa, play X" lands on the hub's SyncPlay relay (`ws://<hub>:8804`), which
' matches an authenticated (hub user, server) socket — NOT a SyncPlay room. The
' consumer socket therefore opens whenever the app is open in hub mode with a
' picked server, independently of any watch-together session. Direct mode has
' no hub relay session at all (no hub token, no server id), so nothing opens.
' =============================================================================

' Start (or replace) the HubCommandTask for the current hub context.
' No-op in direct mode or before a server is picked.
sub StartHubCommandConsumer()
    if GetConnectionKind() <> "hub" then return
    serverId = GetActiveServerId()
    if serverId = "" then return

    hubUrl = GetServerUrl()
    if hubUrl = "" then return

    ' Parse the hub host out of the persisted hub URL (http://host[:port]).
    host = hubUrl
    schemeIdx = Instr(1, host, "://")
    if schemeIdx > 0 then host = Mid(host, schemeIdx + 3)
    slashIdx = Instr(1, host, "/")
    if slashIdx > 0 then host = Left(host, slashIdx - 1)
    if host = "" then return

    token = GetStorage().get("auth_token")
    if token = invalid or token = "" then return

    StopHubCommandConsumer()

    m.hubCommandTask = CreateObject("roSGNode", "HubCommandTask")
    m.hubCommandTask.ObserveField("event", "OnPendingHubCommand")
    m.top.Append(m.hubCommandTask)
    m.hubCommandTask.config = {
        host: host
        port: 8804
        apiBase: hubUrl
        serverId: serverId
        token: token
    }
    m.hubCommandTask.control = "run"
end sub

' Stop the consumer task (logout, server switch, app teardown).
sub StopHubCommandConsumer()
    if m.hubCommandTask = invalid then return
    m.hubCommandTask.UnobserveField("event")
    m.hubCommandTask.command = { kind: "close" }
    m.top.RemoveChild(m.hubCommandTask)
    m.hubCommandTask = invalid
end sub

' Route a delivered pending_command to the player through the SAME deep-link
' machinery R6.3 uses for link intents: fetch the item, then open DetailScene
' with auto-play. A second command while one is already being processed is
' ignored (a command is already in flight).
sub OnPendingHubCommand(event as Object)
    if m.hubCommandTask = invalid or m.hubCommandTask <> event.GetNode() then return
    data = event.GetData()
    if data = invalid or data.kind <> "pending_command" then return
    ' M-ROKU-13 (review roku__exploiter M2): this mediaId arrives over the
    ' PLAINTEXT hub-relay socket — a hostile hub or LAN injector can push any
    ' frame. The era's invalid/"" check let path-shaping values through into
    ' ProcessDeepLink -> ApiClient "/media/" + itemId. The canonical allowlist
    ' rejects them at the entry; the play choke re-gates independently.
    ' Reject posture = ignore (matches this handler's documented law that
    ' unusable commands are ignored, not dialog-spammed at the viewer).
    if not IsSafeContentId(data.mediaId) then return

    if m.deepLinkFetchTask <> invalid then return

    m.deepLinkParams = { contentId: data.mediaId.Trim(), action: "play" }
    ProcessDeepLink()
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
    ' M-ROKU-03: capture the teardown credentials BEFORE the wipe. The logout
    ' ApiTask used to read session_id from the registry AFTER
    ' ResetCachedStorage(true) deleted it, so the server-side
    ' DELETE /sessions/{id} saw an empty id and was skipped on every logout —
    ' the teardown was a silent no-op since the day it shipped.
    teardownToken = GetStorage().get("auth_token")
    teardownSessionId = GetStorage().get("session_id")
    ' Session-teardown base: the MEDIA base — where the session row actually
    ' lives. Wire truth (review M-ROKU-03 r1): the hub issues ONLY
    ' access/refresh tokens at login (phlix-hub
    ' src/Http/Controllers/AuthController.php:99-100,:146-147 — no
    ' session_id) and serves no user-facing /sessions HTTP route; the
    ' persisted session_id is ALWAYS a SERVER-side row. PlayerScene created
    ' it through the relay base (ApiTask ExecRequest builds GetApiClient(),
    ' i.e. GetMediaBaseUrl()), which the hub re-anchors at the picked
    ' server's /api/v1/sessions (phlix-hub src/Application.php:595-615
    ' registers the DELETE proxy; phlix-server
    ' src/Server/Core/Application.php:902 endSession). Teardown must
    ' therefore ride the SAME base + Bearer pair that created the session:
    ' direct mode GetMediaBaseUrl() is byte-identical to GetServerUrl();
    ' hub mode it is {hub}/api/v1/servers/{id}/proxy. MUST resolve BEFORE
    ' the wipe below: ResetCachedStorage(true) deletes connection_kind +
    ' active_server_id, which degrade the resolver to the bare hub url —
    ' no /sessions route there (best-effort 404; server session rows
    ' idle-expire via SessionManager cleanup). Guarded per the AppContext
    ' law (never resolve a url without checking connectivity).
    teardownBase = ""
    if IsServerConnected() then teardownBase = GetMediaBaseUrl()

    ' M-ROKU-03: wipes exactly the six auth/session keys and invalidates the
    ' read cache; server_url SURVIVES (README law: you return to the login
    ' screen on the same hub/server) so the LoginScene below has a live base.
    ResetCachedStorage(true)

    ' R4 (fail closed): the admin flag is a PROFILE fact, not a device fact.
    ' It lives in the SetIsAdmin function-property store which survives scene
    ' teardown - without this reset an admin logout followed by a non-admin
    ' login in the same channel run could leave GetIsAdmin() true until the
    ' next getMe answers, exposing the AdminScene menu (403s on every row -
    ' phlix-server AdminMiddleware on /admin/*).
    SetIsAdmin(false)

    ' S298: the hub relay consumer holds a live token-scoped socket — stop it
    ' before credentials are cleared.
    StopHubCommandConsumer()

    ' Clear the screen stack (stale references to removed nodes) and remove all
    ' children so the next Show* call starts from a clean scene tree.
    m.screenStack.Clear()
    while m.top.GetChildCount() > 0
        m.top.RemoveChild(m.top.GetChild(0))
    end while

    ' Fire server-side session teardown off the render thread (fire-and-forget)
    ' BEFORE showing the login surface. M-ROKU-03 order law: the scene
    ' transitions (OnConnected/OnLoginSuccess/OnHubDetected) pop the LAST child,
    ' so a task appended after a scene hijacks that idiom — pre-fix, appending
    ' this task after ShowLogin left the ApiTask as the last child and the next
    ' login transition removed the task instead of LoginScene. The request
    ' carries the pre-wipe base/token/session captured above: after
    ' ResetCachedStorage(true) the task can no longer re-resolve them itself.
    ' Local logout is already complete, so the user is safely signed out
    ' regardless of server reachability.
    logoutTask = CreateObject("roSGNode", "ApiTask")
    logoutTask.request = { op: "logout", base_url: teardownBase, auth_token: teardownToken, session_id: teardownSessionId }
    m.top.Append(logoutTask)
    logoutTask.control = "run"

    ' Last-child invariant restored: LoginScene is the final child. If
    ' server_url was absent (legacy wiped install, manual registry clear),
    ' ShowLogin routes to ConnectScene per the AppContext law instead of
    ' dead-ending on the fake network error.
    ShowLogin()
end sub

' OnSwitchServer - the Settings → Server URL → Switch button, actually wired
' (M-ROKU-04: this button shipped answering "not implemented" — the review's
' dead-end example). Same teardown discipline as OnLogout: capture the
' credentials before the wipe, fire the best-effort server-side session
' teardown BEFORE appending the next scene (order law from M-ROKU-03), then
' land on ConnectScene — the address-edit surface, which is what "switch"
' means. server_url survives the wipe and prefill the box so the user edits
' rather than retypes; the new URL is persisted by ConnectScene.Connect when
' the probe (or the anyway override) fires.
sub OnSwitchServer()
    teardownToken = GetStorage().get("auth_token")
    teardownSessionId = GetStorage().get("session_id")
    teardownBase = ""
    if IsServerConnected() then teardownBase = GetMediaBaseUrl()

    ' Six-key surgical wipe (auth/session + hub binding); server_url SURVIVES
    ' so the ConnectScene prefill shows the CURRENT address for editing.
    ResetCachedStorage(true)

    SetIsAdmin(false)
    StopHubCommandConsumer()

    m.screenStack.Clear()
    while m.top.GetChildCount() > 0
        m.top.RemoveChild(m.top.GetChild(0))
    end while

    ' Best-effort sign-out from the OLD server — the whole reason someone
    ' presses Switch may be that it is unreachable, so this rides the same
    ' fire-and-forget task as logout and its failure is inert by design.
    teardownTask = CreateObject("roSGNode", "ApiTask")
    teardownTask.request = { op: "logout", base_url: teardownBase, auth_token: teardownToken, session_id: teardownSessionId }
    m.top.Append(teardownTask)
    teardownTask.control = "run"

    ' Fresh address entry, no stale error: bootReason stays empty.
    ShowConnect()
end sub

' R6.3: Process a validated deep-link intent.
' M-ROKU-13: validation is enforced HERE, at the single play choke — an id
' failing the canonical shape law (IsSafeContentId) never reaches the network.
' Fetches the item metadata from the server, then routes to the appropriate
' scene based on mediaType/action:
'   "play"  -> DetailScene with auto-play
'   "series"-> DetailScene with smart-bookmark episode selection + auto-play
'   "season"-> SeasonScene (episode picker)
' If the id is malformed, the item is not found (404), or the fetch fails,
' shows a content-not-found/error dialog (R3.1) and returns to the home screen.
'
' Uses ApiTask (m.deepLinkFetchTask) to fetch item metadata off the render thread.
' Navigation is driven by the response callback OnDeepLinkItemResponse.
sub ProcessDeepLink()
    if m.deepLinkParams = invalid then return

    contentId = m.deepLinkParams.contentId
    action = m.deepLinkParams.action

    ' M-ROKU-13 (review roku__exploiter M2): THE play choke. Every route to
    ' playback - cold launch, warm roInput, login-stashed JSON, and the
    ' plaintext hub-relay pending_command - funnels through here into
    ' ApiClient's "/media/" + itemId raw concatenation. The id is judged by
    ' the canonical allowlist BEFORE any request is built, and the trimmed
    ' form is what leaves the TV: a shape-rejected id can never exist in the
    ' server's catalog (ids are UUIDs), so it fails VISIBLE (R3.1 content-not-
    ' found dialog) without ever issuing an attacker-shaped authenticated GET.
    safeId = invalid
    if IsSafeContentId(contentId) then safeId = contentId.Trim()
    if safeId = invalid then
        print "Deep link contentId rejected by shape law (M-ROKU-13)"
        ShowContentNotFoundDialog()
        return
    end if

    print "Processing deep link: contentId=" safeId " action=" action

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
    m.deepLinkFetchTask.request = { op: "getItem", itemId: safeId }
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
            handled = PopScreen()
            if not handled then
                ' Stack empty: we are on a bootstrap scene (Connect/Login/
                ' ServerPicker/Home — Home is appended, never pushed). Returning
                ' false here used to hand the key to RSG's native close, which
                ' only closes the FOCUSED child scene and leaves the root's black
                ' boot chrome on screen — a dead screen needing a second Back
                ' (review roku__casualgamer M2). Honor PopScreen's contract
                ' instead: false means "the caller must exit the channel", so we
                ' raise exitChannel (observed by main.brs, which returns and the
                ' channel exits cleanly — there is no roApp.Exit() in SceneGraph)
                ' and CONSUME the key. One Back from Home exits; no black frame.
                ' CHECK31 pins this arm.
                m.top.exitChannel = true
                handled = true
            end if
        end if
    end if

    return handled
end function

' M-ROKU-17 r2 (review roku__gameux M17r1 CRITICAL-1): the dispatch arm.
' ToastManager.deliver() - running in any consumer scope - walks the
' documented GetParent chain to this root node, writes toastMessage/
' toastDuration and bumps the alwaysNotify toastSeq trigger; the render-
' thread ObserveField wiring in Init above routes the bump here (the repo's
' proven channel: the requestClose arms deliver child -> coordinator exactly
' this way, and ShowErrorDialog observes wasClosed with named subs on a
' freshly created node). The R3.4 node.PostMessage -> onMessage pair is
' DELETED, not re-signatured: it is no articulable RokuOS node contract -
' bsc's vendored Roku types (brighterscript/dist/roku-types/data.json) model
' PostMessage exactly once, on roRenderThreadQueue (receive via
' AddMessageHandler, used nowhere in this channel), no onMessage special is
' modeled at all, and none of this repo's seven Task components rides one;
' the r1 review convicted the single-arg arm and the 689b475 two-arg re-arm
' inherits the same unmodeled door, so under either signature every notice
' died at the wire while the display machinery below sat unreachable.
' Boundary law (ROKU-12/CHECK43): the declared field types carry the String/
' Integer typing, and the duration is additionally bounded 0 < d <= 30000 -
' an out-of-range or unset (0) value falls back to the default, whatever a
' future writer posts. Copy stays app-side static end to end.
sub OnToastNotice(event as Object)
    text = m.top.toastMessage
    if text = invalid or text = "" then return
    durMs = 3000
    if m.top.toastDuration > 0 and m.top.toastDuration <= 30000 then durMs = m.top.toastDuration
    EnqueueToast(text, durMs)
end sub

' ===========================================
' M-ROKU-17 toast coordinator (the root scene owns the display queue)
'
' ToastManager delivers on the observed toastSeq channel from any scope;
' the root scene is the channel's sole toast coordinator (OnToastNotice
' above). The
' queue gives each ambient notice its full screen time in FIFO order and
' never tramples a scene-owned modal: while the current surface's dialog
' field is busy, the queue re-probes on a bounded retry tick.
'   cap    5 queued notices; overflow drops the OLDEST (the fresher
'          degraded-state signal is the one worth keeping) with a loud dev
'          print - never a silent drop
'   retry  2 s between probes, at most 15 probes (a 30 s window); an
'          expired queue is dropped WITH a print - a notice that could not
'          reach the screen in half a minute is stale by design
'   normal zero permanent drops: an unblocked arrival displays in the
'          same call
' ===========================================
sub EnqueueToast(text as String, durMs as Integer)
    m.toastQueue.Push({text: text, durMs: durMs})
    if m.toastQueue.Count() > 5 then
        dropped = m.toastQueue.Shift()
        print "Toast queue overflow (cap 5) - dropped oldest notice:" dropped.text
    end if
    TryShowToast()
end sub

sub TryShowToast()
    ' A toast we still own is on screen; its wasClosed observer drains the
    ' queue the moment it frees. A toast whose holder scene was popped
    ' under us leaves a detached node and no closing event - reclaim the
    ' state and fall through to display.
    if m.activeToast <> invalid then
        if m.activeToast.GetParent() <> invalid then return
        m.activeToast = invalid
        if m.toastTimer <> invalid then m.toastTimer.control = "stop"
    end if
    if m.toastQueue.Count() = 0 then return

    target = CurrentToastSurface()
    if target.dialog <> invalid then
        ' The surface carries a dialog (ours would have been reclaimed
        ' above; this is a scene-owned ShowErrorDialog modal): defer.
        ArmToastRetry()
        return
    end if

    notice = m.toastQueue.Shift()
    toast = CreateObject("roSGNode", "ToastScene")
    toast.title = notice.text
    toast.ObserveField("wasClosed", "OnToastClosed")
    m.activeToast = toast
    target.dialog = toast
    m.toastRetryTicks = 0
    ArmToastDismiss(notice.durMs)
end sub

' CurrentToastSurface - the topmost visible scene node.
' PushScreen and the Show* bootstrap methods append every screen as the
' LAST child of the root (the same "last appended child" idiom OnConnected
' uses to name them), so the last child is the visible surface whenever it
' is Scene-derived - only Scene nodes carry the dialog field the toast
' displays through. Boot-chrome children (Label/Group) fall through to the
' root scene itself.
function CurrentToastSurface() as Object
    childCount = m.top.GetChildCount()
    if childCount > 0 then
        last = m.top.GetChild(childCount - 1)
        if last.DoesExist("dialog") then return last
    end if
    return m.top
end function

sub ArmToastDismiss(durMs as Integer)
    EnsureToastTimer()
    m.toastTimerPurpose = "dismiss"
    m.toastTimer.control = "stop"
    m.toastTimer.duration = durMs / 1000
    m.toastTimer.control = "start"
end sub

sub ArmToastRetry()
    if m.toastRetryArmed then return
    if m.toastRetryTicks >= 15 then
        stale = m.toastQueue.Count()
        m.toastQueue.Clear()
        m.toastRetryTicks = 0
        print "Toast retry window (30s) exhausted - dropped" stale "queued notice(s); the surface stayed modal"
        return
    end if
    m.toastRetryArmed = true
    m.toastRetryTicks = m.toastRetryTicks + 1
    EnsureToastTimer()
    m.toastTimerPurpose = "retry"
    m.toastTimer.control = "stop"
    m.toastTimer.duration = 2
    m.toastTimer.control = "start"
end sub

' The timer node is a child of the ROOT scene - always in the render tree,
' unlike the freshly-created toast (a Timer only ticks while attached; the
' pre-fix ToastScene.brs CreateObject'd one and never parented it, so even
' the imagined auto-dismiss could not fire). One purpose at a time: the
' coordinator arms dismiss only while a toast is owned and retry only
' while a queue is blocked.
sub EnsureToastTimer()
    if m.toastTimer <> invalid then return
    m.toastTimer = CreateObject("roSGNode", "Timer")
    m.top.AppendChild(m.toastTimer)
    m.toastTimer.ObserveField("fire", "OnToastTimerFire")
end sub

sub OnToastTimerFire(event as Object)
    if m.toastTimerPurpose = "retry" then
        m.toastRetryArmed = false
        TryShowToast()
        return
    end if
    ' dismiss tick: close is the built-in Dialog's write-only dismiss
    ' control - setting it dismisses the dialog regardless of value (Roku
    ' Dialog reference). The wasClosed observer below then drains the
    ' queue; the pre-fix script wrote the same field on a Scene, where it
    ' is nothing at all.
    if m.activeToast <> invalid then
        m.activeToast.close = true
    end if
end sub

' wasClosed is the Dialog's documented close event: it fires on the close
' control, on Back/Home (dialogs consume both natively - this cure ships no
' custom key handling), and when another dialog supersedes this one. The
' identity guard ignores a stale event from a toast the coordinator has
' already reclaimed (holder scene popped under us), so a late arrival can
' never disarm the live toast's dismiss timer.
sub OnToastClosed(event as Object)
    if not event.GetNode().IsSameNode(m.activeToast) then return
    m.activeToast = invalid
    if m.toastTimer <> invalid then m.toastTimer.control = "stop"
    TryShowToast()
end sub

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("bootLoadingLabel")
    if n <> invalid then n.text = Translate("common_loading")
    n = m.top.findNode("bootErrorLabel")
    if n <> invalid then n.text = Translate("app_boot_cannot_reach")
    n = m.top.findNode("bootRetryButton")
    if n <> invalid then n.text = Translate("common_retry")
end sub
