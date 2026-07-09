' components/SyncPlayOverlay.brs

' copyright 2026 Joe Huss
'

' ===========================================
' SyncPlay Overlay - P8-S4
' Shows room status when user is in a SyncPlay room during playback.
' Designed to be displayed as an overlay on PlayerScene.
' ===========================================

' Factory function to create a SyncPlay overlay controller.
' Returns an object with methods to control the overlay visibility and state.
'
' @param scene Object - the parent scene node (m.top of the scene)
' @param overlayNode Object - the Rectangle node for the overlay
' @param statusLabel Object - the Label node for status text
' @param memberCountLabel Object - the Label node for member count
' @param leaveButton Object - the Button node for leave action
' @return Object - controller with show(), hide(), update(), setLeaveCallback()
function SyncPlayOverlay(scene as Object, overlayNode as Object, statusLabel as Object, memberCountLabel as Object, leaveButton as Object) as Object
    obj = {
        _scene: scene
        _overlay: overlayNode
        _statusLabel: statusLabel
        _memberCountLabel: memberCountLabel
        _leaveButton: leaveButton
        _leaveCallback: invalid
        _isVisible: false

        ' Initialize observers on the leave button
        init: function()
            if m._leaveButton <> invalid then
                m._leaveButton.ObserveField("buttonSelected", "OnLeavePressed")
            end if
        end function

        ' Show the overlay
        show: function()
            if m._overlay <> invalid then
                m._overlay.visible = true
                m._isVisible = true
            end if
            if m._leaveButton <> invalid then
                m._leaveButton.SetFocus(true)
            end if
        end function

        ' Hide the overlay
        hide: function()
            if m._overlay <> invalid then
                m._overlay.visible = false
                m._isVisible = false
            end if
        end function

        ' Toggle visibility
        toggle: function()
            if m._isVisible then
                m.hide()
            else
                m.show()
            end if
        end function

        ' Update overlay with current room state
        ' @param roomName String - name of the room
        ' @param memberCount Integer - number of members
        ' @param isHost Boolean - true if this device is the host
        ' @param syncStatus String - current sync status ("synced", "connecting", etc.)
        update: function(roomName as String, memberCount as Integer, isHost as Boolean, syncStatus as String)
            if m._statusLabel <> invalid then
                role = "Guest"
                if isHost then role = "Host"
                m._statusLabel.text = roomName + " - " + role + " - " + syncStatus
            end if
            if m._memberCountLabel <> invalid then
                m._memberCountLabel.text = str(memberCount).Trim() + " member(s)"
            end if
        end function

        ' Set the callback function for when leave button is pressed
        ' @param callback Function - the function to call
        setLeaveCallback: function(callback as Function)
            m._leaveCallback = callback
        end function

        ' Handle leave button pressed
        OnLeavePressed: function()
            if m._leaveCallback <> invalid then
                m._leaveCallback()
            end if
        end function

        ' Cleanup observers
        cleanup: function()
            if m._leaveButton <> invalid then
                m._leaveButton.UnObserveField("buttonSelected")
            end if
        end function

        ' Check if overlay is currently visible
        isVisible: function() as Boolean
            return m._isVisible
        end function
    }

    obj.init()
    return obj
end function