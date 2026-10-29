' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ConnectScene.brs

' copyright 2026 Joe Huss
'

'
' First-run "Connect to server" screen — and (since M-ROKU-04) the honest
' RETRY surface for every connect-path failure.
'
' Day-1 flow, minimal typing:
'   1. "Find Phlix server on network" — an SSDP M-SEARCH (the same wire shape
'      the server's own client-side discovery uses; see DiscoveryTask.brs)
'      lists whatever Phlix servers answer on the LAN. One answer prefills
'      the address box; several answers become a pickable list. A LAN IP
'      changes when the router reboots — this replaces hunt-and-peck as the
'      primary path, while manual full-URL typing STAYS as the documented
'      fallback (different subnet, remote URL, discovery off).
'   2. Connect probes {url}/health through the single ApiTask via the
'      probeHealth op (a FRESH ApiClient bound to the candidate url - the
'      shared client is bound to the old/absent server_url at first run).
'      A healthy probe persists server_url and fires connected=true.
'   3. Every failure now says WHAT failed: probeHealth answers a classified
'      verdict (ok | http | dns | refused | tls | timeout | bad_url |
'      unreachable — the ClassifyUrlFailure bucket law in Utilities.brs)
'      and each bucket renders exactly one catalog message
'      (connect_err_<bucket>, CHECK34 pins the triangle). The "Connect
'      anyway" override survives on every failure: some servers block
'      /health while serving /api/v1 just fine.
'   4. PhlixApp routes boot-time transport failures here with the reason in
'      the bootReason interface field; Init surfaces the same per-cause
'      message over the prefilled saved address, so "my server went to
'      sleep" reads as that and lands where the address is editable — not
'      on a login form behind a fake network accusation.
'
' PhlixApp self-creates + focuses this scene and observes `connected`, so it
' has no <interface> function - `connected` is an observed FIELD (mirrors
' LoginScene's loginSucceeded). ONE ApiTask + m.pendingOp serializes the
' probe; discovery runs on its own short-lived Task node (UDP, off-thread).

sub Init()
    ApplyXmlChrome()
    m.top.SetFocus(true)

    ' UI nodes.
    m.serverInput = m.top.FindNode("serverInput")
    m.connectButton = m.top.FindNode("connectButton")
    m.connectAnywayButton = m.top.FindNode("connectAnywayButton")
    m.findButton = m.top.FindNode("findServerButton")
    m.serverList = m.top.FindNode("serverList")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.errorLabel = m.top.FindNode("errorLabel")

    ' Button handlers.
    if m.connectButton <> invalid then
        m.connectButton.ObserveField("buttonSelected", "OnConnectPressed")
    end if
    if m.connectAnywayButton <> invalid then
        m.connectAnywayButton.ObserveField("buttonSelected", "OnConnectAnywayPressed")
    end if
    if m.findButton <> invalid then
        m.findButton.ObserveField("buttonSelected", "OnFindPressed")
    end if
    if m.serverList <> invalid then
        m.serverList.ObserveField("buttonSelected", "OnServerSelected")
    end if

    ' Prefill any previously-entered server URL (first run is empty; a
    ' re-entry after a boot transport failure arrives fully populated).
    savedServerUrl = GetStorage().get("server_url")
    if savedServerUrl <> invalid and savedServerUrl <> "" then
        if m.serverInput <> invalid then m.serverInput.text = savedServerUrl
    end if

    ' M-ROKU-04 retry surface: PhlixApp routed a boot-time transport failure
    ' here. Show the per-cause honest message over the prefilled address and
    ' offer the same anyway-override as a failed probe.
    bootReason = m.top.bootReason
    if bootReason <> invalid and bootReason <> "" and IsTransportReason(bootReason) then
        ShowError(TranslateTransportReason(bootReason))
        if m.connectAnywayButton <> invalid then m.connectAnywayButton.visible = true
    end if

    ' Route the probe through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' Only one probe in flight at a time.
    m.pendingOp = ""
    ' The last-normalized url, reused by "Connect anyway".
    m.candidateUrl = ""
    ' Origins already offered by the last discovery (dedupe across re-scans).
    m.discovered = []

    if m.connectButton <> invalid then m.connectButton.SetFocus(true)
end sub

sub OnConnectPressed()
    ' Ignore re-presses while a probe is in flight.
    if m.pendingOp <> "" then return

    raw = ""
    if m.serverInput <> invalid then raw = m.serverInput.text
    if raw = invalid then raw = ""

    if raw.Trim() = "" then
        ShowError(Translate("connect_err_empty"))
        return
    end if

    url = NormalizeServerUrl(raw)
    if url = "" then
        ShowError(Translate("connect_err_invalid"))
        return
    end if

    ' Stash for "Connect anyway"; hide it until/unless this probe fails.
    m.candidateUrl = url
    if m.connectAnywayButton <> invalid then m.connectAnywayButton.visible = false

    HideError()
    SetStatus(Translate("connect_status_connecting"))

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
            ' M-ROKU-04: classified failure - one honest sentence per cause
            ' (bucket law + CHECK34 triangle in Utilities.brs), plus the
            ' anyway-override for the "server blocks /health" class.
            SetStatus("")
            ShowError(ProbeFailureMessage(resp.data))
            if m.connectAnywayButton <> invalid then
                m.connectAnywayButton.visible = true
                ' Move focus onto the just-revealed button so the user reaches it
                ' without blindly D-padding to a node that was hidden a moment ago.
                m.connectAnywayButton.SetFocus(true)
            end if
        end if
    end if
end sub

' Map a failed probe verdict to its catalog message. state "http" means the
' host ANSWERED but /health was not a healthy Phlix body; every other failed
' state is already a transport bucket. Explicit literals, no dynamic keys -
' the same law CHECK20/24 enforce elsewhere.
function ProbeFailureMessage(data as Object) as String
    if data = invalid or data.state = invalid then
        return Translate("connect_err_unreachable")
    end if
    if data.state = "http" then
        return Translate("connect_err_health_blocked")
    end if
    return TranslateTransportReason(data.state)
end function

' ---------------------------------------------
' M-ROKU-04 — LAN discovery ("Find Phlix server")
'
' The Roku idiom for minimizing typed input: devices announce themselves.
' The server's DLNA/SSDP advertiser answers M-SEARCH on 239.255.255.250:1900
' for the MediaServer search target and names itself with USN
' uuid:PHLIXSERVER / a SERVER header containing "Phlix/" (verified read of
' phlix-server src/Dlna/SsdpSearchResponder.php + SsdpAdvertiser.php, and the
' request shape mirrors the server's own client SsdpSocket.php:316 verbatim).
' LOCATION carries http://<ip>:<port>/dlna/description.xml; ExtractServerOrigin
' reduces it to the connectable base, and the chosen candidate goes through
' the SAME /health probe as a typed address — a spoofed SSDP answer can only
' ever reach the probe, never the persisted state.
'
' Every failure degrades to the pre-M-ROKU-04 flow (type the address):
' an empty/absent answer set reads "No Phlix server found on this network".
' ---------------------------------------------
sub OnFindPressed()
    if m.findTask <> invalid then return   ' one scan at a time
    SetStatus(Translate("connect_find_searching"))
    HideError()

    m.findTask = CreateObject("roSGNode", "DiscoveryTask")
    m.findTask.ObserveField("response", "OnDiscoveryResponse")
    m.top.Append(m.findTask)
    m.findTask.control = "run"
end sub

sub OnDiscoveryResponse(event as Object)
    ' NOTE: DiscoveryTask is NOT an API transport - its response is a plain
    ' task-level payload {servers:[...]} it builds itself. The local is named
    ' `answer` (not resp) so the envelope-law scanner (CHECK26, which reads
    ' variable NAMES as the envelope fingerprint) cannot confuse this
    ' discovery frame with an ApiClient transport envelope.
    answer = event.getData()

    ' The task is done; retire it before any early return so the next press
    ' can re-scan (m.findTask doubles as the in-flight guard).
    if m.findTask <> invalid then
        m.findTask.UnObserveField("response")
        m.top.RemoveChild(m.findTask)
        m.findTask = invalid
    end if

    SetStatus("")

    servers = invalid
    if answer <> invalid then servers = answer.servers
    if servers = invalid or type(servers) <> "roArray" or servers.Count() = 0 then
        ' Honest empty-handed outcome - manual entry remains the documented
        ' fallback (it is always visible; nothing was taken away).
        ShowError(Translate("connect_find_none"))
        if m.connectButton <> invalid then m.connectButton.SetFocus(true)
        return
    end if

    if servers.Count() = 1 then
        ' Single find: prefill the address box; the user presses Connect
        ' (or edits). One typed-character-free step from done.
        if m.serverInput <> invalid then m.serverInput.text = servers[0]
        SetStatus(Translate("connect_find_one"))
        if m.serverList <> invalid then m.serverList.visible = false
        if m.connectButton <> invalid then m.connectButton.SetFocus(true)
        return
    end if

    ' Several finds: offer the list; selection prefills like the single case.
    FillServerList(servers)
    if m.serverList <> invalid then
        m.serverList.visible = true
        m.serverList.selectItem = true
        m.serverList.SetFocus(true)
    end if
end sub

' Rebuild the LabelList content from the discovered origins.
sub FillServerList(servers as Object)
    if m.serverList = invalid then return
    content = CreateObject("roSGNode", "Node")
    for each origin in servers
        item = CreateObject("roSGNode", "ContentNode")
        item.title = origin   ' ContentNode ships a built-in title field;
                              ' LabelList renders it (no AddFields dance)
        content.AppendChild(item)
    end for
    m.serverList.content = content
    m.discovered = servers
end sub

sub OnServerSelected(event as Object)
    if m.serverList = invalid then return
    idx = event.GetData()
    if idx = invalid or m.discovered = invalid then return
    if idx < 0 or idx >= m.discovered.Count() then return
    if m.serverInput <> invalid then m.serverInput.text = m.discovered[idx]
    SetStatus(Translate("connect_find_picked"))
    if m.connectButton <> invalid then m.connectButton.SetFocus(true)
end sub

' Persist the chosen url and notify PhlixApp (observes `connected`).
sub Connect(url as String)
    if url = invalid or url = "" then return
    GetStorage().set("server_url", url)
    GetStorage().flush()  ' R1.6: persist the URL before the first boot auth check
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
    if m.findButton <> invalid then m.findButton.UnObserveField("buttonSelected")
    if m.serverList <> invalid then m.serverList.UnObserveField("buttonSelected")
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
    if m.findTask <> invalid then m.findTask.UnObserveField("response")
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

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("headerLabel")
    if n <> invalid then n.text = Translate("connect_title")
    n = m.top.findNode("serverAddressLabel")
    if n <> invalid then n.text = Translate("connect_server_address")
    n = m.top.findNode("findServerButton")
    if n <> invalid then n.title = Translate("connect_find_button")
    n = m.top.findNode("connectButton")
    if n <> invalid then n.title = Translate("connect_button")
    n = m.top.findNode("connectAnywayButton")
    if n <> invalid then n.title = Translate("connect_anyway")
end sub
