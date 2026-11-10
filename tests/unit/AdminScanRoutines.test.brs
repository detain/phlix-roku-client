' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/AdminScanRoutines.test.brs

' ===============================================================
' W14L1 RT-047 [i] - the admin scan-status auto-poll.
' components/LibraryAdminActionsScene.brs rides the EXTRA_SOURCES
' door (w13L3 PhlixApp precedent). The in-flight law is pure; the
' arm/stop decision is driven through the REAL OnApiResponse with
' AA fakes - the timer's control field records, no render tree.
' ===============================================================

sub TestAdminScanIsScanJobInFlightLaw()
    ' The server state machine (ScanJobRepository): queued/running move,
    ' completed/failed are terminal. Anything else never polls.
    assertTrue(IsScanJobInFlight("queued"))
    assertTrue(IsScanJobInFlight("running"))
    assertTrue(IsScanJobInFlight("  RUNNING "))
    assertFalse(IsScanJobInFlight("completed"))
    assertFalse(IsScanJobInFlight("failed"))
    assertFalse(IsScanJobInFlight(""))
    assertFalse(IsScanJobInFlight("garbage"))
    print "TestAdminScanIsScanJobInFlightLaw passed"
end sub

sub TestAdminScanRunningJobArmsThePoll()
    g = GetGlobalAA()
    g.pendingOp = "getLibraryScanStatus"
    g.libraryId = "LIB1"
    g.scanPolling = false
    g.scanTimer = { control: "" }
    g.scanStatusLabel = { text: "" }
    g.statusLabel = { text: "old" }
    fakeEvent = {
        getData: function() as Object
            return {
                op: "getLibraryScanStatus"
                ok: true
                data: { scan_status: { job_type: "scan", status: "running" } }
            }
        end function
    }
    OnApiResponse(fakeEvent)
    assertTrue(g.scanPolling)
    assertEqual(g.scanTimer.control, "start")
    ' The summary still renders beside the arming decision.
    assertTrue(InStr(1, g.scanStatusLabel.text, "Status: running") > 0)
    print "TestAdminScanRunningJobArmsThePoll passed"
end sub

sub TestAdminScanTerminalJobStopsThePoll()
    g = GetGlobalAA()
    g.pendingOp = "getLibraryScanStatus"
    g.libraryId = "LIB1"
    g.scanPolling = true
    g.scanTimer = { control: "start" }
    g.scanStatusLabel = { text: "" }
    g.statusLabel = { text: "" }
    fakeEvent = {
        getData: function() as Object
            return {
                op: "getLibraryScanStatus"
                ok: true
                data: { scan_status: { job_type: "scan", status: "completed" } }
            }
        end function
    }
    OnApiResponse(fakeEvent)
    assertFalse(g.scanPolling)
    assertEqual(g.scanTimer.control, "stop")
    print "TestAdminScanTerminalJobStopsThePoll passed"
end sub

sub TestAdminScanFailedReadStopsThePoll()
    ' A transport failure reads as "no in-flight job": the poll stops
    ' instead of dialing forever (Refresh/re-open re-arms - documented
    ' posture in the scene's OnApiResponse comment).
    g = GetGlobalAA()
    g.pendingOp = "getLibraryScanStatus"
    g.libraryId = "LIB1"
    g.scanPolling = true
    g.scanTimer = { control: "start" }
    ' The never-scanned fallback leg is Translate (catalog state = the
    ' documented device-only headless gap, the same class as the w13L3
    ' Translate exclusions). Skipping the label node keeps this leg
    ' exercising exactly what it convicts: the poll decision, which the
    ' product now evaluates BEFORE any label rendering.
    g.scanStatusLabel = invalid
    g.statusLabel = { text: "" }
    fakeEvent = {
        getData: function() as Object
            return { op: "getLibraryScanStatus", ok: false }
        end function
    }
    OnApiResponse(fakeEvent)
    assertFalse(g.scanPolling)
    assertEqual(g.scanTimer.control, "stop")
    print "TestAdminScanFailedReadStopsThePoll passed"
end sub

sub TestAdminScanSetPollingIsIdempotent()
    g = GetGlobalAA()
    g.scanPolling = true
    g.scanTimer = { control: "start" }
    ' Already polling: no second "start" verb is ever re-issued.
    SetScanPolling(true)
    assertEqual(g.scanTimer.control, "start")
    g.scanPolling = false
    g.scanTimer = { control: "stop" }
    SetScanPolling(false)
    assertEqual(g.scanTimer.control, "stop")
    print "TestAdminScanSetPollingIsIdempotent passed"
end sub

sub TestAdminScanTickIsSilentStatusRead()
    ' OnScanPollFire routes through RefreshStatus(silent=true): the read
    ' fires, the pendingOp guard arms, and the operator's "Job queued"
    ' message is NOT overwritten by the loading text (RT-047 flash law).
    g = GetGlobalAA()
    g.pendingOp = invalid
    g.libraryId = "LIB1"
    g.statusLabel = { text: "Job queued" }
    g.apiTask = { control: "", request: invalid }
    OnScanPollFire({})
    assertEqual(g.pendingOp, "getLibraryScanStatus")
    assertEqual(g.apiTask.control, "run")
    assertEqual(g.apiTask.request.op, "getLibraryScanStatus")
    assertEqual(g.statusLabel.text, "Job queued")
    print "TestAdminScanTickIsSilentStatusRead passed"
end sub

sub TestAdminScanTickYieldsToInFlightRequest()
    ' The serialization law the card demands: a tick during an outstanding
    ' op is a no-op - never two control="run" on the single task.
    g = GetGlobalAA()
    g.pendingOp = "scanLibrary"
    g.libraryId = "LIB1"
    g.statusLabel = { text: "" }
    g.apiTask = { control: "", request: invalid }
    OnScanPollFire({})
    assertEqual(g.pendingOp, "scanLibrary")
    assertEqual(g.apiTask.control, "")
    print "TestAdminScanTickYieldsToInFlightRequest passed"
end sub

sub TestAdminScanTeardownReleasesTimer()
    ' stop + UnObserveField("fire") + RemoveChild + invalid (PhlixApp's
    ' warm-deep-link release law, applied to the new timer).
    g = GetGlobalAA()
    g.unobserved = ""
    g.removed = false
    g.scanTimer = {
        control: "start"
        UnObserveField: sub(field as String)
            GetGlobalAA().unobserved = field
        end sub
    }
    g.scanPolling = true
    g.top = {
        RemoveChild: sub(node as Object)
            if node <> invalid then GetGlobalAA().removed = true
        end sub
    }
    g.btnUnobserved = 0
    g.scanButton = {
        UnObserveField: sub(field as String)
            GetGlobalAA().btnUnobserved = GetGlobalAA().btnUnobserved + 1
        end sub
    }
    g.rescanButton = g.scanButton
    g.matchButton = g.scanButton
    g.refreshButton = g.scanButton
    g.apiTask = g.scanButton
    Teardown()
    ' All four buttons + the apiTask response observer still pair off
    ' (five), plus the new timer release below.
    assertEqual(g.btnUnobserved, 5)
    assertEqual(g.scanTimer, invalid)
    assertEqual(g.unobserved, "fire")
    assertTrue(g.removed)
    assertFalse(g.scanPolling)
    print "TestAdminScanTeardownReleasesTimer passed"
end sub
