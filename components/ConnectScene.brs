' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ConnectScene.brs

' copyright 2026 Joe Huss
'

'
' First-run "Connect to server" screen. The user types a server (or hub) URL;
' on Connect we normalize it (Utilities.NormalizeServerUrl) and probe {url}/health
' through the single ApiTask via the `probeHealth` op (a FRESH ApiClient bound to
' the candidate url - the shared client is bound to the old/absent server_url at
' first run). On a healthy probe we persist server_url and fire connected=true.
' On a failed probe we surface an error and reveal a "Connect anyway" button which
' persists + proceeds regardless (some servers block /health), reusing the
' last-normalized url stashed in m.candidateUrl.
'
' PhlixApp self-creates + focuses this scene and observes `connected`, so it has
' no <interface> function - `connected` is an observed FIELD (mirrors LoginScene's
' loginSucceeded). ONE ApiTask + m.pendingOp serializes the single probe.

sub Init()
    m.top.SetFocus(true)

    ' UI nodes.
    m.serverInput = m.top.FindNode("serverInput")
    m.connectButton = m.top.FindNode("connectButton")
    m.connectAnywayButton = m.top.FindNode("connectAnywayButton")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.errorLabel = m.top.FindNode("errorLabel")

    ' Button handlers.
    if m.connectButton <> invalid then
        m.connectButton.ObserveField("buttonSelected", "OnConnectPressed")
    end if
    if m.connectAnywayButton <> invalid then
        m.connectAnywayButton.ObserveField("buttonSelected", "OnConnectAnywayPressed")
    end if

    ' Prefill any previously-entered server URL (defensive; first run is empty).
    savedServerUrl = Storage.get("server_url")
    if savedServerUrl <> invalid and savedServerUrl <> "" then
        if m.serverInput <> invalid then m.serverInput.text = savedServerUrl
    end if

    ' Route the probe through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' Only one probe in flight at a time.
    m.pendingOp = ""
    ' The last-normalized url, reused by "Connect anyway".
    m.candidateUrl = ""

    if m.connectButton <> invalid then m.connectButton.SetFocus(true)
end sub

sub OnConnectPressed()
    ' Ignore re-presses while a probe is in flight.
    if m.pendingOp <> "" then return

    raw = ""
    if m.serverInput <> invalid then raw = m.serverInput.text
    if raw = invalid then raw = ""

    if raw.Trim() = "" then
        ShowError("Please enter a server address")
        return
    end if

    url = NormalizeServerUrl(raw)
    if url = "" then
        ShowError("Please enter a valid server address")
        return
    end if

    ' Stash for "Connect anyway"; hide it until/unless this probe fails.
    m.candidateUrl = url
    if m.connectAnywayButton <> invalid then m.connectAnywayButton.visible = false

    HideError()
    SetStatus("Connecting…")

    m.pendingOp = "probeHealth"
    m.apiTask.request = { op: "probeHealth", url: url }
    m.apiTask.control = "run"
end sub

sub OnConnectAnywayPressed()
    if m.candidateUrl = invalid or m.candidateUrl = "" then return
    Connect(m.candidateUrl)
end sub

sub OnApiResponse(event as Object)
    ' Clear pending op at the TOP so a later press can fire a new probe.
    m.pendingOp = ""

    resp = event.getData()
    if resp = invalid then return

    if resp.op = "probeHealth" then
        if resp.ok then
            ' Reachable + healthy -> persist and proceed.
            Connect(m.candidateUrl)
        else
            ' Unreachable / blocked /health -> surface error + offer override.
            SetStatus("")
            ShowError("Couldn't reach that server")
            if m.connectAnywayButton <> invalid then
                m.connectAnywayButton.visible = true
                ' Move focus onto the just-revealed button so the user reaches it
                ' without blindly D-padding to a node that was hidden a moment ago.
                m.connectAnywayButton.SetFocus(true)
            end if
        end if
    end if
end sub

' Persist the chosen url and notify PhlixApp (observes `connected`).
sub Connect(url as String)
    if url = invalid or url = "" then return
    Storage.set("server_url", url)
    HideError()
    HideStatus()
    m.top.connected = true
end sub

sub ShowError(message as String)
    if m.errorLabel <> invalid then
        m.errorLabel.text = message
        m.errorLabel.visible = true
    end if
    HideStatus()
end sub

sub HideError()
    if m.errorLabel <> invalid then m.errorLabel.visible = false
end sub

sub SetStatus(message as String)
    if m.statusLabel <> invalid then
        m.statusLabel.text = message
        m.statusLabel.visible = (message <> "")
    end if
end sub

sub HideStatus()
    if m.statusLabel <> invalid then m.statusLabel.visible = false
end sub

sub Teardown()
    ' Pair every ObserveField with an UnObserveField so observers don't leak.
    if m.connectButton <> invalid then m.connectButton.UnObserveField("buttonSelected")
    if m.connectAnywayButton <> invalid then m.connectAnywayButton.UnObserveField("buttonSelected")
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            ' Don't allow backing out of the connect screen (no server yet).
            handled = true
        end if
    end if

    return handled
end function