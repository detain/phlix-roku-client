' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/FavoritesSceneRoutines.test.brs

' ===============================================================
' W15L9-R2 RT-094 [M] - browse failures must render FAILURE, not
' emptiness. components/FavoritesScene.brs rides the
' EXTRA_SOURCES door. The pure outcome choke carries the whole
' law: a not-ok response or a malformed payload returns the
' failure copy key; a usable payload returns the empty string so
' the success-side empty/success handling stands untouched. The
' failure branch of OnApiResponse may only ever translate the
' choke's verdict - the CHECK101 static legs pin that routing.
' ===============================================================

sub TestFavoritesBrowseOutcomeNotOk()
    ' A refused/broken response is a FAILURE, never "No favorites yet":
    ' the old merged arm rendered emptiness over a dead server.
    assertEqual(FavoritesBrowseOutcome(false, false), "favorites_failed")
    ' Malformed-but-successful shape (ok, no usable items payload) is
    ' still a browse failure - the server never delivered a list.
    assertEqual(FavoritesBrowseOutcome(true, false), "favorites_failed")
    print "TestFavoritesBrowseOutcomeNotOk passed"
end sub

sub TestFavoritesBrowseOutcomeSuccessHasNoDisclosure()
    ' A usable payload returns no disclosure key: the success path owns
    ' the empty/success distinction (favorites_empty stays a SOLE writer
    ' of an honest "empty" verdict over a healthy response).
    assertEqual(FavoritesBrowseOutcome(true, true), "")
    print "TestFavoritesBrowseOutcomeSuccessHasNoDisclosure passed"
end sub

sub TestFavoritesBrowseOutcomeNeverInventsEmptiness()
    ' The outcome key, when non-empty, is the FAILURE key - it must never
    ' answer favorites_empty (the collapse this cure closes).
    k1 = FavoritesBrowseOutcome(false, true)
    k2 = FavoritesBrowseOutcome(false, false)
    assertEqual(k1, "favorites_failed")
    assertEqual(k2, "favorites_failed")
    print "TestFavoritesBrowseOutcomeNeverInventsEmptiness passed"
end sub
