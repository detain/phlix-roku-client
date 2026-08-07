' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/SkipButton.brs

' copyright 2026 Joe Huss


' ===========================================
' Skip Button Component
' Owns its button and exposes skipRequested interface
' ===========================================

sub Init()
    ' Find child nodes
    m.button = m.top.findNode("button")
    m.label = m.top.findNode("label")

    if m.button <> invalid then
        m.button.ObserveField("buttonSelected", "OnButtonSelected")
        m.button.visible = false
    end if

    ' Initialize marker state
    m.markers = {
        skip_intro_start: invalid
        skip_intro_end: invalid
        skip_outro_start: invalid
        skip_outro_end: invalid
    }

    m.currentPosition = 0
    m.isVisible = false
    m.activeMarkerType = ""
end sub

' Handle markers field change (set from external)
sub OnMarkersChange(event as Object)
    markerData = event.getData()

    if markerData = invalid then
        m.markers.skip_intro_start = invalid
        m.markers.skip_intro_end = invalid
        m.markers.skip_outro_start = invalid
        m.markers.skip_outro_end = invalid
    else
        m.markers.skip_intro_start = markerData.skip_intro_start
        m.markers.skip_intro_end = markerData.skip_intro_end
        m.markers.skip_outro_start = markerData.skip_outro_start
        m.markers.skip_outro_end = markerData.skip_outro_end
    end if

    ' Reset visibility when markers change
    m.isVisible = false
    m.activeMarkerType = ""
    if m.button <> invalid then
        m.button.visible = false
    end if
end sub

' Set marker data from playback info
' @param markerData Object - Object containing skip_intro_start, skip_intro_end, etc.
sub setMarkers(markerData as Object)
    if markerData = invalid then
        m.markers.skip_intro_start = invalid
        m.markers.skip_intro_end = invalid
        m.markers.skip_outro_start = invalid
        m.markers.skip_outro_end = invalid
    else
        m.markers.skip_intro_start = markerData.skip_intro_start
        m.markers.skip_intro_end = markerData.skip_intro_end
        m.markers.skip_outro_start = markerData.skip_outro_start
        m.markers.skip_outro_end = markerData.skip_outro_end
    end if

    ' Reset visibility when markers change
    m.isVisible = false
    m.activeMarkerType = ""
    if m.button <> invalid then
        m.button.visible = false
    end if
end sub

' Update button visibility based on current position
' @param position Float - Current playback position in seconds
' @return Boolean - True if position is in a marker range
function updatePosition(position as Float) as Boolean
    m.currentPosition = position

    ' Check if position is within intro marker range
    if isPositionInIntroRange(position) then
        showButton("intro")
        return true
    end if

    ' Check if position is within outro marker range
    if isPositionInOutroRange(position) then
        showButton("outro")
        return true
    end if

    ' Not in any marker range
    if m.isVisible then
        hideButton()
    end if
    return false
end function

' Check if position is within intro marker range
' @param position Float - Current position in seconds
' @return Boolean
function isPositionInIntroRange(position as Float) as Boolean
    if m.markers.skip_intro_start = invalid or m.markers.skip_intro_end = invalid then
        return false
    end if

    return position >= m.markers.skip_intro_start and position <= m.markers.skip_intro_end
end function

' Check if position is within outro marker range
' @param position Float - Current position in seconds
' @return Boolean
function isPositionInOutroRange(position as Float) as Boolean
    if m.markers.skip_outro_start = invalid or m.markers.skip_outro_end = invalid then
        return false
    end if

    return position >= m.markers.skip_outro_start and position <= m.markers.skip_outro_end
end function

' Show the skip button with appropriate label
' @param markerType String - "intro" or "outro"
sub showButton(markerType as String)
    if m.button = invalid then return

    m.activeMarkerType = markerType
    m.isVisible = true
    m.button.visible = true

    if m.label <> invalid then
        if markerType = "intro" then
            m.label.text = "Skip Intro"
        else if markerType = "outro" then
            m.label.text = "Skip Outro"
        end if
    end if
end sub

' Hide the skip button
sub hideButton()
    if m.button = invalid then return

    m.isVisible = false
    m.activeMarkerType = ""
    m.button.visible = false
end sub

' Handle button press - seek to end of marker
sub OnButtonSelected()
    targetPosition = 0#

    if m.activeMarkerType = "intro" then
        targetPosition = m.markers.skip_intro_end
    else if m.activeMarkerType = "outro" then
        targetPosition = m.markers.skip_outro_end
    end if

    ' Fire skipRequested interface field - this is what PlayerScene observes
    m.top.skipRequested = targetPosition
end sub

' Get the target seek position without triggering seek
' Useful for external callers to get the position first
' @return Float - Target position in seconds
function getTargetPosition() as Float
    if m.activeMarkerType = "intro" then
        return m.markers.skip_intro_end
    else if m.activeMarkerType = "outro" then
        return m.markers.skip_outro_end
    end if
    return 0#
end function

' Check if intro markers are available
' @return Boolean
function hasIntroMarkers() as Boolean
    return m.markers.skip_intro_start <> invalid and m.markers.skip_intro_end <> invalid
end function

' Check if outro markers are available
' @return Boolean
function hasOutroMarkers() as Boolean
    return m.markers.skip_outro_start <> invalid and m.markers.skip_outro_end <> invalid
end function

' Clean up observers
sub cleanup()
    if m.button <> invalid then
        m.button.UnObserveField("buttonSelected")
    end if
end sub