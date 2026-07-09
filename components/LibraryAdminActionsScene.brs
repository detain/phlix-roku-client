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
' <interface>. Status refresh is MANUAL (the Refresh button); after a queued
' scan/rescan/match action the OnApiResponse branch chains a RefreshStatus() so
' the new job state shows. No auto-poll (would need a Timer node) - future work.

sub Init()
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

    ' State. m.pendingOp tracks the one outstanding op (invalid = idle) so a
    ' button press while a request is in flight is ignored.
    m.libraryId = ""
    m.pendingOp = invalid

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
sub RefreshStatus()
    if m.pendingOp <> invalid then return
    if m.libraryId = "" then return

    m.pendingOp = "getLibraryScanStatus"
    SetStatus("Loading status…")
    m.apiTask.request = { op: "getLibraryScanStatus", libraryId: m.libraryId }
    m.apiTask.control = "run"
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

        if m.scanStatusLabel <> invalid then
            if job = invalid then
                m.scanStatusLabel.text = "Never scanned"
            else
                m.scanStatusLabel.text = ScanStatusSummary(job)
            end if
        end if

        SetStatus("")
    else if resp.op = "scanLibrary" or resp.op = "rescanLibrary" or resp.op = "matchLibraryMetadata" then
        if resp.ok and resp.data <> invalid then
            message = "Job queued"
            if resp.data.DoesExist("message") and resp.data.message <> invalid and resp.data.message <> "" then
                message = resp.data.message
            end if
            SetStatus(message)
            ' Chain a status refresh so the new job state shows (m.pendingOp is
            ' already cleared above, so this is a fresh serialized call).
            RefreshStatus()
        else
            SetStatus("Request failed")
        end if
    end if
end sub

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
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function