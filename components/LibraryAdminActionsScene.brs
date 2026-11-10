' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/LibraryAdminActionsScene.brs

' copyright 2026 Joe Huss
'

'
' Per-library admin actions: Scan / Rescan / Match Metadata / Refresh Status
' buttons plus a status line driven by the scan-status job row. Mirrors the
' Button + buttonSelected idiom used by HomeScene header buttons / MusicScene
' mode buttons, and the resident-memory serialization rule: a SINGLE ApiTask,
' with m.pendingOp guarding so a button press while a request is outstanding is
' ignored (never two control="run" - mirrors HomeScene's m.pendingResume).
'
' LibraryAdminScene creates + appends this scene and calls LoadLibrary(id,name)
' across the component boundary, so LoadLibrary is declared in the XML
' <interface>. Status refresh starts MANUAL (the Refresh button); after a queued
' scan/rescan/match action the OnApiResponse branch chains a RefreshStatus() so
' the new job state shows. RT-047 [W14L1, review roku__gameux #4] delivers the
' auto-poll this header used to defer as "future work": a repeating 5-second
' Timer node re-runs the status read while the job row reports an in-flight
' state (IsScanJobInFlight), stops at terminal/failed reads, and is released on
' Teardown. Ticks ride the SAME pendingOp-serialized RefreshStatus, so the
' one-outstanding-request law still holds — a tick during an in-flight request
' is simply a no-op.

sub Init()
    ApplyXmlChrome()
    m.top.SetFocus(true)

    ' Action buttons.
    m.scanButton = m.top.FindNode("scanButton")
    if m.scanButton <> invalid then
        m.scanButton.ObserveField("buttonSelected", "OnScan")
    end if
    m.rescanButton = m.top.FindNode("rescanButton")
    if m.rescanButton <> invalid then
        m.rescanButton.ObserveField("buttonSelected", "OnRescan")
    end if
    m.matchButton = m.top.FindNode("matchButton")
    if m.matchButton <> invalid then
        m.matchButton.ObserveField("buttonSelected", "OnMatch")
    end if
    m.refreshButton = m.top.FindNode("refreshButton")
    if m.refreshButton <> invalid then
        m.refreshButton.ObserveField("buttonSelected", "OnRefresh")
    end if

    m.titleLabel = m.top.FindNode("titleLabel")
    m.scanStatusLabel = m.top.FindNode("scanStatusLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread). Every op is serialized through this one task.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' RT-047: repeating status-poll timer (SearchScene's searchTimer owns the
    ' same CreateChild idiom). It is only STARTED while a scan job reports an
    ' in-flight state (SetScanPolling via OnApiResponse); an idle timer never
    ' dials. duration 5s is the estate on-screen poll era (the server-side
    ' sweep cadence is slower; this is user-visible state, not a lock).
    m.scanTimer = m.top.CreateChild("Timer")
    if m.scanTimer <> invalid then
        m.scanTimer.duration = 5
        m.scanTimer.repeat = true
        m.scanTimer.ObserveField("fire", "OnScanPollFire")
    end if

    ' State. m.pendingOp tracks the one outstanding op (invalid = idle) so a
    ' button press while a request is in flight is ignored.
    m.libraryId = ""
    m.pendingOp = invalid
    m.scanPolling = false

    ' Focus the first action button.
    if m.scanButton <> invalid then m.scanButton.SetFocus(true)
end sub

' Interface fn: called by LibraryAdminScene with the selected library's id+name.
sub LoadLibrary(libraryId as String, libraryName as String)
    m.libraryId = libraryId

    name = libraryName
    if name = invalid then name = ""
    if m.titleLabel <> invalid then m.titleLabel.text = name

    if m.libraryId = "" then return

    ' Fire the initial status read.
    RefreshStatus()
end sub

' Read the current scan-status (serialized, guarded). Skipped while another op
' is in flight so two control="run" are never outstanding on the single task.
sub RefreshStatus(silent = false as Boolean)
    if m.pendingOp <> invalid then return
    if m.libraryId = "" then return

    m.pendingOp = "getLibraryScanStatus"
    ' RT-047: timer ticks pass silent=true - a status read every five seconds
    ' must not re-flash "Loading status…" over the operator's "Job queued"
    ' message; only manual/initial reads announce the load.
    if not silent then SetStatus("Loading status…")
    m.apiTask.request = { op: "getLibraryScanStatus", libraryId: m.libraryId }
    m.apiTask.control = "run"
end sub

' RT-047: poll tick = a silent status read. RefreshStatus's own pendingOp
' guard makes a tick during an in-flight request a no-op (never two
' control="run" on the single task), and its libraryId guard covers the
' pre-LoadLibrary window.
sub OnScanPollFire(event as Object)
    RefreshStatus(true)
end sub

' RT-047: start/stop the repeating timer, idempotent in both directions.
' The m.scanPolling flag is the truth of intent; the timer's control field
' only accepts verbs, so state is tracked here (never re-issued every tick).
sub SetScanPolling(wanted as Boolean)
    if m.scanTimer = invalid then return
    if wanted then
        if m.scanPolling then return
        m.scanPolling = true
        m.scanTimer.control = "start"
    else
        if not m.scanPolling then return
        m.scanPolling = false
        m.scanTimer.control = "stop"
    end if
end sub

sub OnScan(event as Object)
    QueueJob("scanLibrary")
end sub

sub OnRescan(event as Object)
    QueueJob("rescanLibrary")
end sub

sub OnMatch(event as Object)
    QueueJob("matchLibraryMetadata")
end sub

sub OnRefresh(event as Object)
    RefreshStatus()
end sub

' Enqueue a scan/rescan/match job (serialized, guarded). A press while an op is
' in flight is ignored (one op at a time - never two control="run").
sub QueueJob(op as String)
    if m.pendingOp <> invalid then return
    if m.libraryId = "" then return

    m.pendingOp = op
    SetStatus("Queuing…")
    m.apiTask.request = { op: op, libraryId: m.libraryId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    ' The single outstanding op completed - clear the guard before any chained
    ' call so the post-action RefreshStatus() is a fresh serialized request.
    m.pendingOp = invalid

    if resp.op = "getLibraryScanStatus" then
        job = invalid
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("scan_status") then
            job = resp.data.scan_status
        end if

        ' RT-047: arm or stop the poll from the SAME response that renders the
        ' summary - covers the initial read (an already-running job starts
        ' auto-polling the moment the screen opens), post-action chains, manual
        ' refreshes, and the ticks themselves. A failed/absent job row reads
        ' as not-in-flight, so a transport failure stops the poll rather than
        ' dialing forever; the Refresh button (or a re-open) re-arms it.
        ' The decision sits ABOVE the label rendering: the never-scanned
        ' fallback leg below routes through Translate (catalog state - a
        ' device-only headless gap the w13L3 exclusions already document),
        ' and the poll law must stand no matter what the label carrier can
        ' execute.
        jobStatus = ""
        if job <> invalid and job.DoesExist("status") and job.status <> invalid then
            jobStatus = job.status
        end if
        SetScanPolling(IsScanJobInFlight(jobStatus))

        if m.scanStatusLabel <> invalid then
            if job = invalid then
                m.scanStatusLabel.text = Translate("libraryadminactions_never_scanned")
            else
                m.scanStatusLabel.text = ScanStatusSummary(job)
            end if
        end if

        SetStatus("")
    else if resp.op = "scanLibrary" or resp.op = "rescanLibrary" or resp.op = "matchLibraryMetadata" then
        if resp.ok and resp.data <> invalid then
            message = SafeErrorMessage(resp.data.message, "Job queued")
            SetStatus(message)
            ' Chain a status refresh so the new job state shows (m.pendingOp is
            ' already cleared above, so this is a fresh serialized call).
            RefreshStatus()
        else
            SetStatus(MessageOf(resp))
        end if
    end if
end sub

' RT-047: the in-flight law for scan job rows, from the server's own state
' machine (phlix-server ScanJobRepository: 'queued' -> 'running' ->
' 'completed' | 'failed'). TRUE means the job can still move - keep polling.
' Anything else (terminal, unknown, empty, garbage) stops the poll: polling
' only while the server says work is pending is the whole duty. Pure.
function IsScanJobInFlight(status as String) as Boolean
    if status = invalid then return false
    s = LCase(status.Trim())
    return s = "queued" or s = "running"
end function

' Build a multi-line summary of a scan-status job row. All fields are Strings -
' guard DoesExist + invalid + "" (no numeric <> "" comparisons).
function ScanStatusSummary(job as Object) as String
    if job = invalid then return ""

    lines = []

    if job.DoesExist("job_type") and job.job_type <> invalid and job.job_type <> "" then
        lines.Push("Type: " + job.job_type)
    end if
    if job.DoesExist("status") and job.status <> invalid and job.status <> "" then
        lines.Push("Status: " + job.status)
    end if
    if job.DoesExist("current_path") and job.current_path <> invalid and job.current_path <> "" then
        lines.Push("Current: " + job.current_path)
    end if
    if job.DoesExist("started_at") and job.started_at <> invalid and job.started_at <> "" then
        lines.Push("Started: " + job.started_at)
    end if
    if job.DoesExist("completed_at") and job.completed_at <> invalid and job.completed_at <> "" then
        lines.Push("Completed: " + job.completed_at)
    end if

    summary = ""
    for i = 0 to lines.Count() - 1
        if i > 0 then summary = summary + Chr(10)
        summary = summary + lines[i]
    end for

    return summary
end function

' Read the message-or-error key from an action response. Prefer message
' (success), else error (failure), else resp.error (transport/API error),
' else a generic depending on resp.ok.
function MessageOf(resp as Object) as String
    if resp <> invalid and resp.data <> invalid then
        ' M-ROKU-12 (review roku__exploiter M1): type-guard the wire keys via
        ' SafeErrorMessage - a raw non-String {"error":{...}} used to raise on
        ' the `<> ""` compare / String-return before ever reaching the screen.
        messageText = SafeErrorMessage(resp.data.message, "")
        if messageText <> "" then
            return messageText
        end if
        errorText = SafeErrorMessage(resp.data.error, "")
        if errorText <> "" then
            return errorText
        end if
    end if

    if resp <> invalid and resp.ok then return "Job queued"
    if resp <> invalid then
        transportError = SafeErrorMessage(resp.error, "")
        if transportError <> "" then return transportError
    end if
    return "Request failed"
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.scanButton <> invalid then m.scanButton.UnObserveField("buttonSelected")
    if m.rescanButton <> invalid then m.rescanButton.UnObserveField("buttonSelected")
    if m.matchButton <> invalid then m.matchButton.UnObserveField("buttonSelected")
    if m.refreshButton <> invalid then m.refreshButton.UnObserveField("buttonSelected")
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
    ' RT-047: the poll timer pairs with Init the same way the rest does -
    ' stop the tick, drop the observer, leave the tree (PhlixApp's warm-deep
    ' link timer release law: stop, UnObserveField("fire"), RemoveChild).
    if m.scanTimer <> invalid then
        m.scanTimer.control = "stop"
        m.scanTimer.UnObserveField("fire")
        m.top.RemoveChild(m.scanTimer)
        m.scanTimer = invalid
    end if
    m.scanPolling = false
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.requestClose = true
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
    n = m.top.findNode("titleLabel")
    if n <> invalid then n.text = Translate("common_library")
    n = m.top.findNode("scanButton")
    if n <> invalid then n.title = Translate("libraryadminactions_scan")
    n = m.top.findNode("rescanButton")
    if n <> invalid then n.title = Translate("libraryadminactions_rescan")
    n = m.top.findNode("matchButton")
    if n <> invalid then n.title = Translate("libraryadminactions_match")
    n = m.top.findNode("refreshButton")
    if n <> invalid then n.title = Translate("libraryadminactions_refresh_status")
    n = m.top.findNode("statusLabel")
    if n <> invalid then n.text = Translate("libraryadminactions_loading_status")
end sub
