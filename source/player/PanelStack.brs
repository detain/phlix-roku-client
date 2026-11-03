' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/player/PanelStack.brs

' ===========================================
' PlayerScene overlay-panel stack law, carved out for the headless unit
' harness (the scene body is component-scope and cannot execute there — the
' same split source/player/SleepTimer.brs ships).
'
' Two laws, both era of review roku__gameux MJ-12:
'  1. CHILD-FIRST UNWIND — the track list (audio/subtitle/chapter picker) is
'     a child of the settings panel. While both are open, Back closes the
'     CHILD. The pre-cure order tested the parent first, so Back closed the
'     settings panel underneath a still-visible child: the child stranded on
'     screen with its parent's state false, and the only way out was closing
'     the whole overlay.
'  2. FOCUS FOLLOWS THE STACK — when a child closes, focus hands back to the
'     parent ONLY while that parent is actually open; otherwise it returns to
'     the scene root, because this file's own ShowControls focus law (hiding
'     must never leave focus parked on now-invisible controls) forbids
'     parking focus on a hidden node. The chapter picker ("C") shares the
'     track-list panel WITHOUT the settings panel, which is the state the
'     old unconditional settingsList re-focus poisoned.
' ===========================================

function PlayerTopOpenPanel(settingsPanelOpen as Boolean, trackListPanelOpen as Boolean) as String
    ' The topmost open member of the settings -> trackList stack. The chapter
    ' picker rides the same trackList flag, so one decision covers both.
    if trackListPanelOpen then return "trackList"
    if settingsPanelOpen then return "settings"
    return ""
end function

function PlayerPanelCloseFocus(closingPanel as String, settingsPanelOpen as Boolean) as String
    ' Where focus goes when closingPanel closes. Only the trackList child has
    ' a live parent to hand back to; closing the settings panel (or any
    ' childless panel) returns focus to the scene root (the shipped
    ' CloseSettingsPanel idiom, :2463 era).
    if closingPanel = "trackList" and settingsPanelOpen then return "settingsList"
    return "sceneRoot"
end function
