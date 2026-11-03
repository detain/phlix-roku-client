' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/PanelStack.test.brs

' ===========================================
' PlayerScene panel-stack law - unit tests (MJ-12 era)
'
' The scene itself is component-scope and cannot execute in the headless
' harness (same split the SleepTimer suite proves); these tests drive the
' carved-out decision functions in source/player/PanelStack.brs, and
' components/PlayerScene.brs OnKeyEvent/CloseTrackListPanel route through
' them, so a scene-side re-order or re-raw focus change cannot keep CI green
' unless the pinned decision changes with it.
'
' RED-AT-PARENT MEASUREMENT: on the pre-cure tree these functions do not
' exist - the whole suite fails unresolved-call (measured, see fix log),
' which is exactly the order law nothing pinned before MJ-12.
' ===========================================

sub TestPanelStackChildClosesFirst()
    ' THE MJ-12 law: with the track list open on top of the settings panel,
    ' the stack's topmost owner is the CHILD - Back closes the track list and
    ' the settings panel survives. The pre-cure arm order answered "settings".
    assertEqual(PlayerTopOpenPanel(true, true), "trackList")
    print "TestPanelStackChildClosesFirst passed"
end sub

sub TestPanelStackSingletonsUnchanged()
    ' One open panel answers for itself; nothing open answers "".
    assertEqual(PlayerTopOpenPanel(true, false), "settings")
    assertEqual(PlayerTopOpenPanel(false, true), "trackList")
    assertEqual(PlayerTopOpenPanel(false, false), "")
    print "TestPanelStackSingletonsUnchanged passed"
end sub

sub TestPanelStackCloseFocusFollowsStack()
    ' Closing the child while the parent is open hands focus to the settings
    ' list; with the parent hidden (chapter-picker state) focus goes to the
    ' scene root - the old unconditional settingsList re-focus parked on an
    ' invisible node there.
    assertEqual(PlayerPanelCloseFocus("trackList", true), "settingsList")
    assertEqual(PlayerPanelCloseFocus("trackList", false), "sceneRoot")
    print "TestPanelStackCloseFocusFollowsStack passed"
end sub

sub TestPanelStackCloseFocusParentlessPanels()
    ' Closing the settings panel (or any panel without an open parent below
    ' it) never claims a hand-off: sceneRoot, matching the shipped
    ' CloseSettingsPanel idiom.
    assertEqual(PlayerPanelCloseFocus("settings", true), "sceneRoot")
    assertEqual(PlayerPanelCloseFocus("settings", false), "sceneRoot")
    assertEqual(PlayerPanelCloseFocus("quality", true), "sceneRoot")
    print "TestPanelStackCloseFocusParentlessPanels passed"
end sub
