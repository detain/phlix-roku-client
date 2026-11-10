' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/CollectionSceneRoutines.test.brs

' ===============================================================
' W15L9-R2 RT-094 [M] - browse failures must render FAILURE, not
' emptiness. components/CollectionScene.brs rides the
' EXTRA_SOURCES door. The pure outcome choke carries the whole
' law: the collection grid's failure arm used to CLEAR the
' description strip (invisible to the viewer as "an empty
' collection"), and only a real roArray may land as a usable
' payload (the W-min93 M-ROKU-10 shape law the guard keeps).
' ===============================================================

sub TestCollectionBrowseOutcomeNotOk()
    ' A refused/broken response is a FAILURE, not a blank strip:
    assertEqual(CollectionBrowseOutcome(false, false), "collection_failed")
    ' ok-but-shapeless payload is also a browse failure.
    assertEqual(CollectionBrowseOutcome(true, false), "collection_failed")
    print "TestCollectionBrowseOutcomeNotOk passed"
end sub

sub TestCollectionBrowseOutcomeSuccessHasNoDisclosure()
    ' A usable (real-array) payload returns no disclosure key; the
    ' success path keeps the honest collection_empty sole-writer leg.
    assertEqual(CollectionBrowseOutcome(true, true), "")
    print "TestCollectionBrowseOutcomeSuccessHasNoDisclosure passed"
end sub

sub TestCollectionBrowseOutcomeNeverInventsEmptiness()
    ' When non-empty the verdict is the FAILURE key - never the empty
    ' collection copy over a dead server.
    k1 = CollectionBrowseOutcome(false, true)
    k2 = CollectionBrowseOutcome(false, false)
    assertEqual(k1, "collection_failed")
    assertEqual(k2, "collection_failed")
    print "TestCollectionBrowseOutcomeNeverInventsEmptiness passed"
end sub
