' source/player/SkipButton.brs

' ===========================================
' Skip Button Component
' Displays Skip Intro/Outro buttons during playback
' based on server-provided marker ranges
' ===========================================

function SkipButton() as Object
    obj = {
        ' Node references
        button: invalid
        label: invalid

        ' Marker data (in seconds)
        markers: {
            skip_intro_start: invalid
            skip_intro_end: invalid
            skip_outro_start: invalid
            skip_outro_end: invalid
        }

        ' Current state
        currentPosition: 0
        isVisible: false
        activeMarkerType: ""

        ' Initialize the skip button
        ' @param buttonNode Object - The button SGNode
        ' @param labelNode Object - The label SGNode for text
        init: function(buttonNode as Object, labelNode as Object)
            m.button = buttonNode
            m.label = labelNode

            if m.button <> invalid then
                m.button.ObserveField("buttonSelected", "OnButtonSelected")
                m.button.visible = false
            end if
        end function

        ' Set marker data from playback info
        ' @param markerData Object - Object containing skip_intro_start, skip_intro_end, etc.
        setMarkers: function(markerData as Object)
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
        end function

        ' Update button visibility based on current position
        ' @param position Float - Current playback position in seconds
        ' @return Boolean - True if position is in a marker range
        updatePosition: function(position as Float) as Boolean
            m.currentPosition = position

            ' Check if position is within intro marker range
            if m.isPositionInIntroRange(position) then
                m.showButton("intro")
                return true
            end if

            ' Check if position is within outro marker range
            if m.isPositionInOutroRange(position) then
                m.showButton("outro")
                return true
            end if

            ' Not in any marker range
            if m.isVisible then
                m.hideButton()
            end if
            return false
        end function

        ' Check if position is within intro marker range
        ' @param position Float - Current position in seconds
        ' @return Boolean
        isPositionInIntroRange: function(position as Float) as Boolean
            if m.markers.skip_intro_start = invalid or m.markers.skip_intro_end = invalid then
                return false
            end if

            return position >= m.markers.skip_intro_start and position <= m.markers.skip_intro_end
        end function

        ' Check if position is within outro marker range
        ' @param position Float - Current position in seconds
        ' @return Boolean
        isPositionInOutroRange: function(position as Float) as Boolean
            if m.markers.skip_outro_start = invalid or m.markers.skip_outro_end = invalid then
                return false
            end if

            return position >= m.markers.skip_outro_start and position <= m.markers.skip_outro_end
        end function

        ' Show the skip button with appropriate label
        ' @param markerType String - "intro" or "outro"
        showButton: function(markerType as String)
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
        end function

        ' Hide the skip button
        hideButton: function()
            if m.button = invalid then return

            m.isVisible = false
            m.activeMarkerType = ""
            m.button.visible = false
        end function

        ' Handle button press - seek to end of marker
        ' @return Float - Position to seek to (0 if no active marker)
        OnButtonSelected: function()
            targetPosition = 0

            if m.activeMarkerType = "intro" then
                targetPosition = m.markers.skip_intro_end
            else if m.activeMarkerType = "outro" then
                targetPosition = m.markers.skip_outro_end
            end if

            return targetPosition
        end function

        ' Get the target seek position without triggering seek
        ' Useful for外部 callers to get the position first
        ' @return Float - Target position in seconds
        getTargetPosition: function() as Float
            if m.activeMarkerType = "intro" then
                return m.markers.skip_intro_end
            else if m.activeMarkerType = "outro" then
                return m.markers.skip_outro_end
            end if
            return 0
        end function

        ' Check if intro markers are available
        ' @return Boolean
        hasIntroMarkers: function() as Boolean
            return m.markers.skip_intro_start <> invalid and m.markers.skip_intro_end <> invalid
        end function

        ' Check if outro markers are available
        ' @return Boolean
        hasOutroMarkers: function() as Boolean
            return m.markers.skip_outro_start <> invalid and m.markers.skip_outro_end <> invalid
        end function

        ' Clean up observers
        cleanup: function()
            if m.button <> invalid then
                m.button.UnObserveField("buttonSelected")
            end if
        end function
    }

    return obj
end function

' Factory function
function SkipButtonFactory() as Object
    return SkipButton()
end function