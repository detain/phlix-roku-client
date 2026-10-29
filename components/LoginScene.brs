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
        ShowError(Translate("login_err_no_inputs"))
        return
    end if

    ' Save username (server_url is owned by the Connect screen now)
    GetStorage().set("username", username)

    ' Immediate UI feedback: disable button + show status
    if m.loginButton <> invalid then
        m.loginButton.disabled = true
    end if
    ShowStatus(Translate("login_status_signing_in"))

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
' Failure outcomes (M-ROKU-04: every message is a catalog literal; transport
' failures are named per cause through the bucket ladder):
'   1. Wrong credentials (401)       -> login_err_bad_credentials
'   2. Transport failure             -> TranslateTransportReason(bucket)
'      (dns / refused / tls / timeout / unreachable / bad_url /
'      redirect_refused - the causes
'      the server never got the chance to name)
'   3. Server error (5xx, other 4xx) -> login_err_server ({detail} token)
'   4. Login ok but getMyServers fails -> login_err_servers
sub OnLoginResponse(event as Object)
    result = event.GetData()
    ' Fail fast on a malformed task frame before any member access.
    if result = invalid then
        ReEnableButton()
        HideStatus()
        ShowError(Translate("login_err_failed"))
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

            ' Distinguish the failure cases. M-ROKU-04: transport failures
            ' carry a reason BUCKET (dns/refused/tls/timeout/unreachable/
            ' bad_url/redirect_refused - the ClassifyUrlFailure law), so each cause renders
            ' its own honest, cataloged sentence. The pre-fix test was
            ' `error = "connect" or error = "timeout"` — two labels produced
            ' by guessing, both pointing at one fake network accusation.
            ' M-ROKU-12 (review roku__exploiter M1): result.data is the
            ' SERVER PAYLOAD (envelope law) - a hostile {"error":{"code":1}}
            ' body used to reach lcase()/instr() and the {detail} substitution
            ' here as a raw Object and raised a type mismatch ON THIS RENDER
            ' THREAD. Every wire-sourced candidate now rides SafeErrorMessage.
            detail = ""
            if result.data <> invalid and type(result.data) = "roAssociativeArray" then
                detail = SafeErrorMessage(result.data.error, "")
            end if
            envelopeError = SafeErrorMessage(result.error, "")
            if detail = "" and envelopeError <> "" and not IsTransportReason(envelopeError) then
                detail = envelopeError
            end if

            if IsTransportReason(envelopeError) then
                ' Case 2 (now per-cause): the named bucket's message
                ShowError(TranslateTransportReason(envelopeError))
            else if instr(1, lcase(detail), "invalid") > 0 or instr(1, lcase(detail), "credential") > 0 or instr(1, lcase(detail), "unauthorized") > 0 or instr(1, lcase(detail), "401") > 0 then
                ' Case 1: wrong credentials (common error strings from server)
                ShowError(Translate("login_err_bad_credentials"))
            else if detail <> "" then
                ' Case 3: server error with detail (token law: {detail}
                ' rides TranslateWithParams - CHECK24 pins the substitution)
                ShowError(TranslateWithParams("login_err_server", { detail: detail }))
            else
                ' Generic fallback
                ShowError(Translate("login_err_failed"))
            end if
            return
        end if

        ' Login succeeded. Clear errors and proceed to getMyServers (serialized).
        HideError()
        ShowStatus(Translate("login_status_loading"))

        m.apiTask.request = { op: "getMyServers" }
        m.apiTask.control = "run"

    else if result.op = "getMyServers" then
        ' ---- GETMYSEVERS RESPONSE ----
        HideStatus()

        ' Case 4: getMyServers failed
        if result = invalid or result.ok <> true or result.data = invalid then
            ReEnableButton()
            ShowError(Translate("login_err_servers"))
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
    ' M-ROKU-16 (review roku__gameux M1): Back is never disabled here. The old
    ' arm swallowed the press, so a user on the login screen could not leave
    ' the channel except via Home/power — a certification violation and a
    ' contradiction of docs/navigation.md, whose root-back law already covers
    ' every bootstrap screen. Returning false bubbles the press to
    ' PhlixApp.OnKeyEvent: at the empty stack it raises exitChannel and
    ' main.brs exits cleanly, no black dead-screen in between (CHECK31).
    ' Pinned by CHECK47 R1 (bootstrap OnKeyEvent must not consume back).
    return false
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
