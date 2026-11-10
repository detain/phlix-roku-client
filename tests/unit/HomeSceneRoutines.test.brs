' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/HomeSceneRoutines.test.brs

' ===============================================================
' W14L1 RT-091 [m] - the up-next launch chain arms only when its
' own request really runs. components/HomeScene.brs rides the
' EXTRA_SOURCES door. The bug class: pendingUpNext was written
' BEFORE the apiTask.state busy check, so a press during another
' caller's in-flight getItem armed the dispatcher with no request
' owed - the next getItem reply (belonging to the resume chain)
' was mis-consumed as an up-next answer, and the real press died.
' ===============================================================

sub seedUpNext(g)
    g.upNextItems = CreateObject("roArray", 1, true)
    g.upNextItems.Push({ id: "abc123" })
    g.pendingUpNext = invalid
    g.apiTask = {
        state: ""
        control: ""
        request: invalid
    }
end sub

sub TestHomeUpNextBusyTaskDoesNotArm()
    ' THE RED-FIRST LEG AT BASE: pre-fix the arm landed before the busy
    ' check, so this exact call left pendingUpNext pointing at a request
    ' that was never issued.
    g = GetGlobalAA()
    seedUpNext(g)
    g.apiTask.state = "run"
    fakeEvent = {
        getData: function() as Integer
            return 0
        end function
    }
    OnUpNextItemSelected(fakeEvent)
    assertEqual(g.pendingUpNext, invalid)
    assertEqual(g.apiTask.control, "")
    assertEqual(g.apiTask.request, invalid)
    print "TestHomeUpNextBusyTaskDoesNotArm passed"
end sub

sub TestHomeUpNextIdleTaskArmsAndIssues()
    ' The press path stays whole: armed chain + its own getItem in flight.
    g = GetGlobalAA()
    seedUpNext(g)
    fakeEvent = {
        getData: function() as Integer
            return 0
        end function
    }
    OnUpNextItemSelected(fakeEvent)
    assertTrue(g.pendingUpNext <> invalid)
    assertEqual(g.pendingUpNext.mediaItemId, "abc123")
    assertEqual(g.pendingUpNext.item, invalid)
    assertEqual(g.apiTask.request.op, "getItem")
    assertEqual(g.apiTask.request.itemId, "abc123")
    assertEqual(g.apiTask.control, "run")
    print "TestHomeUpNextIdleTaskArmsAndIssues passed"
end sub

sub TestHomeUpNextRetryAfterBusyArms()
    ' The cure's promise: a free task on the next press arms normally.
    g = GetGlobalAA()
    seedUpNext(g)
    g.apiTask.state = "run"
    fakeEvent = {
        getData: function() as Integer
            return 0
        end function
    }
    OnUpNextItemSelected(fakeEvent)
    g.apiTask.state = "fine"
    OnUpNextItemSelected(fakeEvent)
    assertTrue(g.pendingUpNext <> invalid)
    assertEqual(g.apiTask.control, "run")
    print "TestHomeUpNextRetryAfterBusyArms passed"
end sub

sub TestHomeUpNextGuardsPrecedTheArm()
    ' Out-of-bounds index, invalid item, and a media-less row never arm
    ' the chain even with an idle task (the guards above the arm hold).
    g = GetGlobalAA()
    seedUpNext(g)
    low = { getData: function() as Integer
        return 7
    end function }
    OnUpNextItemSelected(low)
    assertEqual(g.pendingUpNext, invalid)

    g.upNextItems[0] = { media_item_id: "mm9" }
    ok = { getData: function() as Integer
        return 0
    end function }
    OnUpNextItemSelected(ok)
    assertEqual(g.pendingUpNext.mediaItemId, "mm9")

    g.upNextItems[0] = { junk: 1 }
    ' Clean slate: this leg convicts the JUNK ROW guard (no arm), not the
    ' previous leg's still-standing arm.
    g.pendingUpNext = invalid
    OnUpNextItemSelected(ok)
    assertEqual(g.pendingUpNext, invalid)
    print "TestHomeUpNextGuardsPrecedTheArm passed"
end sub

sub TestHomeUpNextMalformedIdNeverArms()
    ' [RT-093 W16L5] The shape gate is EXECUTED on this door, not merely
    ' static-pinned: a delimiter-bearing and a numeric server return must
    ' both leave the pendingUpNext custody slot un-armed and the apiTask
    ' untouched. Pre-fix, the `= ""` probe admitted both shapes straight
    ' into the arm (the numeric one then raised the task-thread Type
    ' Mismatch the RT-091 law had just fenced around). Premise pins first:
    ' the fixtures are genuinely hostile, by execution (estate law 2026-11).
    ' (This call also seeds source/lib/Utilities.brs into the suite's
    ' dependency closure — the PhlixApp.test.brs precedent for door suites
    ' whose component begins calling the guard.)
    assertFalse(IsSafeContentId("abc/../../evil"), "fixture premise")
    assertFalse(IsSafeContentId(42), "fixture premise")
    g = GetGlobalAA()
    g.upNextItems = CreateObject("roArray", 2, true)
    g.upNextItems.Push({ id: "abc/../../evil" })
    g.upNextItems.Push({ id: 42 })
    g.pendingUpNext = invalid
    g.apiTask = {
        state: ""
        control: ""
        request: invalid
    }
    ev0 = {
        getData: function() as Integer
            return 0
        end function
    }
    OnUpNextItemSelected(ev0)
    assertEqual(g.pendingUpNext, invalid)
    assertEqual(g.apiTask.request, invalid)
    assertEqual(g.apiTask.control, "")
    ev1 = {
        getData: function() as Integer
            return 1
        end function
    }
    OnUpNextItemSelected(ev1)
    assertEqual(g.pendingUpNext, invalid)
    assertEqual(g.apiTask.request, invalid)
    assertEqual(g.apiTask.control, "")
    print "TestHomeUpNextMalformedIdNeverArms passed"
end sub
