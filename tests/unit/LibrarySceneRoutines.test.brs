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

' ---- RT-092 [review roku__exploiter #1]: LetterBucketOffset box gates ----
' The /media/letter-index rows are raw DecodeJson. `m` is the global AA under
' the harness (seed g.letterIndex), the same shim the sort tests use.
sub TestLetterBucketOffsetHappyPath()
    g = GetGlobalAA()
    ' Closure pin: the gate's choke helpers must be named HERE too — the
    ' headless harness builds its program from the SUITE's reference walk, and
    ' the two calls below (which the gated site consumes) pull Utilities.brs
    ' into the program. Drop them and LetterBucketOffset's TextOrEmpty call
    ' resolves to nothing.
    assertEqual(TextOrEmpty("A"), "A")
    assertTrue(IsBoxedNumber(5))
    g.letterIndex = [ _
        { letter: "A", count: 5, offset: 0 }, _
        { letter: "B", count: 3, offset: 5 } ]
    assertEqual(LetterBucketOffset("B"), 5)
    assertEqual(LetterBucketOffset("A"), 0)   ' a real offset of 0 stays 0, not -1
    assertEqual(LetterBucketOffset("Z"), -1)  ' unmatched letter
    print "TestLetterBucketOffsetHappyPath passed"
end sub

sub TestLetterBucketOffsetMalformedShapes()
    g = GetGlobalAA()
    ' Closure pin (see HappyPath): name the choke helpers the gated site calls.
    ' The boxed-String rejection below is the same law, at the helper level.
    assertEqual(TextOrEmpty(456), "")
    assertFalse(IsBoxedNumber("9"))
    ' A boxed String count and a boxed String offset would crash the old
    ' `bucket.count <= 0` ordered compare and `CInt` respectively; the guard
    ' turns both into the documented sentinel instead. (The junk-element leg
    ' is its own array below — brs rejects a heterogeneous array LITERAL,
    ' and the product's letterIndex arrays come from DecodeJson anyway.)
    g.letterIndex = [ _
        { letter: "C", count: "9", offset: 1 }, _
        { letter: "D", count: 4 }, _
        { letter: "E", count: 2, offset: 11 } ]
    assertEqual(LetterBucketOffset("C"), -1)  ' count is not numeric -> empty bucket
    assertEqual(LetterBucketOffset("D"), 0)   ' valid count, absent offset -> 0
    assertEqual(LetterBucketOffset("E"), 11)  ' the real bucket still resolves
    ' A bare string element (not an AA) is skipped by the type gate; the old
    ' code indexed .letter on it and raised.
    g.letterIndex = ["junk-not-an-aa"]
    assertEqual(LetterBucketOffset("A"), -1)
    print "TestLetterBucketOffsetMalformedShapes passed"
end sub
