' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SearchSceneRoutines.test.brs

' ===============================================================
' W14L1 RT-049 [i] - the pagination leg must not swallow its own
' prefetch. components/SearchScene.brs rides the EXTRA_SOURCES
' door. The bug class: m.loadingPage was raised BEFORE the
' apiTask.state check, so a busy task froze the flag with no
' response ever owed (RT-005 fixed the debounced search; this
' is the distinct LoadMoreItems leg).
' ===============================================================

sub seedIdlePage(g)
    g.loadingPage = false
    g.hasMore = true
    g.keyboard = { text: "hellsing" }
    g.searchGen = 3
    g.limit = 25
    g.offset = 25
    g.apiTask = {
        state: ""
        control: ""
        request: invalid
    }
end sub

sub TestSearchLoadMoreBusyTaskDoesNotStickFlag()
    ' THE RED-FIRST LEG AT BASE: pre-fix, the flag was raised before the
    ' busy check returned - every later prefetch was then locked out by
    ' the loadingPage guard. Post-fix: busy means nothing changed.
    g = GetGlobalAA()
    seedIdlePage(g)
    g.apiTask.state = "run"
    LoadMoreItems()
    assertFalse(g.loadingPage)
    assertEqual(g.apiTask.control, "")
    assertEqual(g.apiTask.request, invalid)
    print "TestSearchLoadMoreBusyTaskDoesNotStickFlag passed"
end sub

sub TestSearchLoadMoreIdleTaskIssuesThePage()
    ' The happy path stays intact: quiet task -> flag raised, paged
    ' request with the current generation issued.
    g = GetGlobalAA()
    seedIdlePage(g)
    LoadMoreItems()
    assertTrue(g.loadingPage)
    assertEqual(g.apiTask.control, "run")
    assertEqual(g.apiTask.request.op, "search")
    assertEqual(g.apiTask.request.searchGen, 3)
    assertEqual(g.apiTask.request.options.offset, 25)
    print "TestSearchLoadMoreIdleTaskIssuesThePage passed"
end sub

sub TestSearchLoadMoreGuardOrderPreserved()
    ' The guards before the busy check keep their precedence: an
    ' outstanding page (flag), an exhausted list (hasMore), and a short
    ' query all stay no-ops even with an idle task.
    g = GetGlobalAA()
    seedIdlePage(g)
    g.loadingPage = true
    LoadMoreItems()
    assertEqual(g.apiTask.control, "")

    seedIdlePage(g)
    g.hasMore = false
    LoadMoreItems()
    assertEqual(g.apiTask.control, "")

    seedIdlePage(g)
    g.keyboard = { text: "h" }
    LoadMoreItems()
    assertEqual(g.apiTask.control, "")
    assertFalse(g.loadingPage)
    print "TestSearchLoadMoreGuardOrderPreserved passed"
end sub

sub TestSearchLoadMoreRetryAfterBusySucceeds()
    ' The cure's promise: once the task frees, the next key event's
    ' retry really pages (pre-fix the stuck flag made this impossible).
    g = GetGlobalAA()
    seedIdlePage(g)
    g.apiTask.state = "run"
    LoadMoreItems()
    g.apiTask.state = "fine"
    LoadMoreItems()
    assertTrue(g.loadingPage)
    assertEqual(g.apiTask.control, "run")
    print "TestSearchLoadMoreRetryAfterBusySucceeds passed"
end sub

' ===============================================================
' W15L9-R2 RT-094 [M] - the search failure leg must disclose
' FAILURE, not reuse "No results" over a dead server. The pure
' outcome choke below carries the law; CHECK101 pins the routing.
' ===============================================================

sub TestSearchBrowseOutcomeNotOk()
    ' refused response and ok-but-malformed payload both fail the browse:
    assertEqual(SearchBrowseOutcome(false, false), "search_failed")
    assertEqual(SearchBrowseOutcome(true, false), "search_failed")
    print "TestSearchBrowseOutcomeNotOk passed"
end sub

sub TestSearchBrowseOutcomeSuccessHasNoDisclosure()
    ' a usable payload answers no key - search_no_results stays the
    ' honest verdict of a SUCCESSFUL zero-hit search only.
    assertEqual(SearchBrowseOutcome(true, true), "")
    print "TestSearchBrowseOutcomeSuccessHasNoDisclosure passed"
end sub

sub TestSearchBrowseOutcomeNeverInventsEmptiness()
    ' non-empty means the FAILURE key, never the no-results copy.
    k1 = SearchBrowseOutcome(false, true)
    k2 = SearchBrowseOutcome(false, false)
    assertEqual(k1, "search_failed")
    assertEqual(k2, "search_failed")
    print "TestSearchBrowseOutcomeNeverInventsEmptiness passed"
end sub
