' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/LibrarySceneRoutines.test.brs

' ===============================================================
' W14L1 RT-048 [m] - the Options-cycle sort law.
' components/LibraryScene.brs rides the EXTRA_SOURCES door.
' The pure step function carries the whole law: five fields,
' wrap flips asc<->desc, mid-list keeps the direction; the label
' marker surfaces the descending leg without minting catalog
' keys (the 392-key set is pinned by the locale Checks).
' ===============================================================

sub seedSortConsts(g)
    g.sortName = "name"
    g.sortYear = "year"
    g.sortRating = "rating"
    g.sortDateAdded = "added"
    g.sortRuntime = "runtime"
end sub

sub TestLibraryNextSortStepFullCycle()
    ' Ten presses from name/asc walk every (field, order) pair the UI
    ' can reach: fields cycle, direction flips ONLY on the wrap.
    g = GetGlobalAA()
    seedSortConsts(g)
    nxt = NextSortStep("name", "asc")
    assertEqual(nxt.field, "year")
    assertEqual(nxt.order, "asc")
    nxt = NextSortStep("year", "asc")
    assertEqual(nxt.field, "rating")
    nxt = NextSortStep("rating", "asc")
    assertEqual(nxt.field, "added")
    nxt = NextSortStep("added", "asc")
    assertEqual(nxt.field, "runtime")
    ' The wrap: back to name, direction FLIPPED.
    nxt = NextSortStep("runtime", "asc")
    assertEqual(nxt.field, "name")
    assertEqual(nxt.order, "desc")
    ' Descending walk: same field order, no flips until the next wrap.
    nxt = NextSortStep("name", "desc")
    assertEqual(nxt.field, "year")
    assertEqual(nxt.order, "desc")
    nxt = NextSortStep("runtime", "desc")
    assertEqual(nxt.field, "name")
    assertEqual(nxt.order, "asc")
    print "TestLibraryNextSortStepFullCycle passed"
end sub

sub TestLibraryNextSortStepUnknownStart()
    ' A stored sort field outside the list (fossil from an older build)
    ' starts at the first step, exactly like the retired inline arm.
    g = GetGlobalAA()
    seedSortConsts(g)
    nxt = NextSortStep("fossil", "asc")
    assertEqual(nxt.field, "year")
    assertEqual(nxt.order, "asc")
    print "TestLibraryNextSortStepUnknownStart passed"
end sub

sub TestLibraryToggleSortOrder()
    assertEqual(ToggleSortOrder("asc"), "desc")
    assertEqual(ToggleSortOrder("desc"), "asc")
    ' Garbage self-heals through the flip: not-desc -> desc -> asc.
    assertEqual(ToggleSortOrder(""), "desc")
    assertEqual(ToggleSortOrder("garbage"), "desc")
    assertEqual(ToggleSortOrder("DESC"), "asc")
    print "TestLibraryToggleSortOrder passed"
end sub

sub TestLibrarySortOrderMarker()
    ' Pure label chrome: no suffix ascending (the baked labels read
    ' that way), " v" descending. ASCII only - never a catalog key.
    assertEqual(SortOrderMarker("asc"), "")
    assertEqual(SortOrderMarker("desc"), " v")
    assertEqual(SortOrderMarker("DESC"), " v")
    assertEqual(SortOrderMarker(""), "")
    print "TestLibrarySortOrderMarker passed"
end sub

sub TestLibrarySortOrderCompositionLaw()
    ' The full two-value state the UI cycles through, with the label
    ' marker consistent at every stop. UpdateSortFilterLabels itself
    ' composes catalog copy through TranslateWithParams - device-only
    ' headless (the documented LoadLocaleStrings gap, same class as the
    ' w13L3 Translate exclusions) - so the composition LINE is convicted
    ' statically by Check 99 R4 and the state/marker law is convicted
    ' exhaustively here.
    g = GetGlobalAA()
    seedSortConsts(g)
    field = "name"
    order = "asc"
    seen = 0
    for i = 1 to 10
        nxt = NextSortStep(field, order)
        field = nxt.field
        order = nxt.order
        assertTrue(SortOrderMarker(order) = "" or SortOrderMarker(order) = " v")
        if order = "desc" then
            assertEqual(SortOrderMarker(order), " v")
        else
            assertEqual(SortOrderMarker(order), "")
        end if
        seen = seen + 1
    end for
    ' Ten presses round the full cycle back to the start state.
    assertEqual(seen, 10)
    assertEqual(field, "name")
    assertEqual(order, "asc")
    print "TestLibrarySortOrderCompositionLaw passed"
end sub
