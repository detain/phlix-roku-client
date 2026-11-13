' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/TrackSelection.test.brs

' ROK-S2: persist-only-if-applied for OnAudioTrackSelected /
' OnSubtitleTrackSelected. Both scene subs persist the preference only when the
' pure node-wins matchers below answer a non-empty key; an id the Video node
' does not list answers "" and so is never applied nor stored. The matchers
' live in source/lib/Utilities.brs so this headless suite can drive them
' without a PlayerScene (brs cannot run Translate/function-object state).

sub TestNodeAudioTrackKeyMatch()
    tracks = [
        { id: 1, Track: "t1", Name: "English" },
        { id: "2", Track: "t2", Name: "French" },
    ]
    assertEqual(NodeAudioTrackKey(tracks, "1"), "t1")
    assertEqual(NodeAudioTrackKey(tracks, "2"), "t2")
    print "TestNodeAudioTrackKeyMatch passed"
end sub

sub TestNodeAudioTrackKeyUnmatchedIsNotApplied()
    tracks = [{ id: 1, Track: "t1" }]
    ' Unlisted id: "" => audioApplied stays false => preference NOT persisted.
    assertEqual(NodeAudioTrackKey(tracks, "99"), "")
    ' Matched entry lacking a Track key: also not applicable.
    assertEqual(NodeAudioTrackKey([{ id: 5 }], "5"), "")
    assertEqual(NodeAudioTrackKey([], "1"), "")
    assertEqual(NodeAudioTrackKey([invalid, { id: 1, Track: "t1" }], "1"), "t1")
    print "TestNodeAudioTrackKeyUnmatchedIsNotApplied passed"
end sub

sub TestNodeSubtitleTrackNameMatch()
    tracks = [
        { id: 3, TrackName: "eng" },
        { id: "4", name: "French" },
        { id: 5, language: "deu" },
    ]
    assertEqual(NodeSubtitleTrackName(tracks, "3"), "eng")
    assertEqual(NodeSubtitleTrackName(tracks, "4"), "French")
    assertEqual(NodeSubtitleTrackName(tracks, "5"), "deu")
    print "TestNodeSubtitleTrackNameMatch passed"
end sub

sub TestNodeSubtitleTrackNameUnmatchedIsNotApplied()
    tracks = [{ id: 3, TrackName: "eng" }]
    assertEqual(NodeSubtitleTrackName(tracks, "42"), "")
    assertEqual(NodeSubtitleTrackName([{ id: 3 }], "3"), "")
    assertEqual(NodeSubtitleTrackName([], "3"), "")
    print "TestNodeSubtitleTrackNameUnmatchedIsNotApplied passed"
end sub
