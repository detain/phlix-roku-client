'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/player/SleepTimer.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Sleep Timer Component
' Stops playback after a user-defined duration
' with optional audio fade-out before stop
' ===========================================

' Preset durations in minutes (inline to avoid module-level assignment lint error)

function SleepTimer() as Object
    obj = {
        ' Timer state
        remainingMs: 0          ' remaining time in milliseconds
        intervalId: invalid      ' timer reference
        isActive: false         ' true when timer is running
        isPaused: false         ' true when timer is paused (not yet implemented)
        selectedPresetIndex: -1  ' index into SLEEP_TIMER_PRESETS, -1 = custom/off

        ' Fade-out state
        fadeStarted: false       ' true once fade has begun
        fadeStartMs: 5000        ' start fading 5 seconds before end
        originalVolume: 1.0      ' volume at fade start

        ' Node references
        timerLabel: invalid      ' Label node showing countdown
        panel: invalid           ' Sleep timer panel Rectangle
        presetList: invalid      ' LabelList of presets
        statusLabel: invalid     ' Status label

        ' Callback when timer fires (set by PlayerScene)
        onTimerFire: invalid     ' function reference

        ' Volume control (reference to video player)
        videoPlayer: invalid

        ' Initialize with UI nodes
        ' @param timerLabelNode Object - Label node for countdown display
        ' @param panelNode Object - Sleep timer panel Rectangle
        ' @param presetListNode Object - LabelList of preset durations
        ' @param statusLabelNode Object - Status/instruction label
        init: function(timerLabelNode as Object, panelNode as Object, presetListNode as Object, statusLabelNode as Object)
            m.timerLabel = timerLabelNode
            m.panel = panelNode
            m.presetList = presetListNode
            m.statusLabel = statusLabelNode

            if m.timerLabel <> invalid then
                m.timerLabel.visible = false
            end if
            if m.panel <> invalid then
                m.panel.visible = false
            end if
        end function

        ' Set the video player reference for volume control
        ' @param videoPlayer Object - The roVideoPlayer node
        setVideoPlayer: function(videoPlayer as Object)
            m.videoPlayer = videoPlayer
        end function

        ' Build the preset list content for LabelList
        ' @return Object - ContentNode with preset items
        buildPresetContent: function() as Object
            content = CreateObject("roSGNode", "ContentNode")
            presets = [15, 30, 45, 60, 90, 120]
            for i = 0 to presets.count() - 1
                preset = presets[i]
                item = CreateObject("roSGNode", "ContentNode")
                item.title = formatDuration(preset * 60)
                item.addFields({ presetIndex: i, durationMinutes: preset })
                content.appendChild(item)
            end for
            ' Add "Cancel" option
            cancelItem = CreateObject("roSGNode", "ContentNode")
            cancelItem.title = "Cancel Timer"
            cancelItem.addFields({ presetIndex: -1, durationMinutes: 0 })
            content.appendChild(cancelItem)
            return content
        end function

        ' Show the sleep timer panel
        showPanel: sub()
            if m.panel = invalid then return

            m.panel.visible = true
            if m.presetList <> invalid then
                m.presetList.content = m.buildPresetContent()
                m.presetList.opened = true
            end if
        end sub

        ' Hide the sleep timer panel
        hidePanel: sub()
            if m.panel = invalid then return
            m.panel.visible = false
        end sub

        ' Toggle panel visibility
        ' @return Boolean - true if panel is now visible
        togglePanel: function() as Boolean
            if m.panel = invalid then return false
            if m.panel.visible then
                m.hidePanel()
                return false
            else
                m.showPanel()
                return true
            end if
        end function

        ' Start the timer with a duration in seconds
        ' @param durationSeconds Integer - Duration in seconds
        ' @return Boolean - true if started successfully
        startWithSeconds: function(durationSeconds as Integer) as Boolean
            if durationSeconds <= 0 then
                return false
            end if

            m.stop()
            m.remainingMs = durationSeconds * 1000
            m.isActive = true
            m.isPaused = false
            m.fadeStarted = false
            m.selectedPresetIndex = -1

            ' Start the ticker
            m.startTicker()

            ' Show the countdown label
            if m.timerLabel <> invalid then
                m.timerLabel.visible = true
                m.updateTimerLabel()
            end if

            print "SleepTimer started: "; formatDuration(durationSeconds)
            return true
        end function

        ' Start timer from preset index
        ' @param presetIndex Integer - Index into presets array
        ' @return Boolean
        startFromPreset: function(presetIndex as Integer) as Boolean
            presets = [15, 30, 45, 60, 90, 120]
            if presetIndex < 0 or presetIndex >= presets.count() then
                return false
            end if
            m.selectedPresetIndex = presetIndex
            return m.startWithSeconds(presets[presetIndex] * 60)
        end function

        ' Cancel the active timer
        ' @return Boolean - true if there was an active timer to cancel
        cancel: function() as Boolean
            if not m.isActive then return false

            m.stop()
            m.remainingMs = 0
            m.isActive = false
            m.isPaused = false
            m.fadeStarted = false

            ' Restore volume if faded
            if m.videoPlayer <> invalid and m.originalVolume < 1.0 then
                m.videoPlayer.volume = 1.0
            end if

            ' Hide the countdown label
            if m.timerLabel <> invalid then
                m.timerLabel.visible = false
            end if

            print "SleepTimer cancelled"
            return true
        end function

        ' Stop the ticker
        stop: function()
            if m.intervalId <> invalid then
                m.intervalId.control = "stop"
                m.intervalId = invalid
            end if
        end function

        ' Start the internal ticker (1 second interval)
        startTicker: function()
            m.intervalId = CreateObject("roSGNode", "Timer")
            m.intervalId.duration = 1.0
            m.intervalId.control = "start"
            m.intervalId.ObserveField("fire", "OnSleepTimerTick")
        end function

        ' Called every second by the ticker
        OnSleepTimerTick: sub()
            if not m.isActive then return

            m.remainingMs = m.remainingMs - 1000

            ' Handle fade-out
            if not m.fadeStarted and m.remainingMs <= m.fadeStartMs then
                m.fadeStarted = true
                if m.videoPlayer <> invalid then
                    m.originalVolume = m.videoPlayer.volume
                end if
            end if

            if m.fadeStarted and m.videoPlayer <> invalid then
                ' Linear fade from originalVolume to 0 over fadeStartMs
                fadeProgress = 1.0 - (m.remainingMs / m.fadeStartMs)
                newVolume = m.originalVolume * (1.0 - fadeProgress)
                if newVolume < 0 then newVolume = 0
                m.videoPlayer.volume = newVolume
            end if

            ' Update display
            m.updateTimerLabel()

            ' Timer expired
            if m.remainingMs <= 0 then
                m.fireTimer()
            end if
        end sub

        ' Fire the timer action
        fireTimer: function()
            m.stop()
            m.remainingMs = 0
            m.isActive = false

            ' Restore volume before stopping
            if m.videoPlayer <> invalid then
                m.videoPlayer.volume = 1.0
            end if

            ' Hide countdown
            if m.timerLabel <> invalid then
                m.timerLabel.visible = false
            end if

            print "SleepTimer fired"

            ' Call the callback if set
            if m.onTimerFire <> invalid then
                m.onTimerFire()
            end if
        end function

        ' Update the timer label text
        updateTimerLabel: sub()
            if m.timerLabel = invalid then return

            if not m.isActive then
                m.timerLabel.text = ""
                return
            end if

            totalSeconds = int(m.remainingMs / 1000)
            hours = totalSeconds / 3600
            minutes = (totalSeconds mod 3600) / 60
            seconds = totalSeconds mod 60

            if hours > 0 then
                m.timerLabel.text = "Sleep: " + str(hours).trim() + ":" + str(minutes).trim().padz(2) + ":" + str(seconds).trim().padz(2)
            else
                m.timerLabel.text = "Sleep: " + str(minutes).trim() + ":" + str(seconds).trim().padz(2)
            end if
        end sub

        ' Get remaining time as formatted string
        ' @return String - formatted duration or ""
        getRemainingFormatted: function() as String
            if not m.isActive or m.remainingMs <= 0 then
                return ""
            end if
            totalSeconds = int(m.remainingMs / 1000)
            hours = totalSeconds / 3600
            minutes = (totalSeconds mod 3600) / 60
            seconds = totalSeconds mod 60

            if hours > 0 then
                return str(hours).trim() + ":" + str(minutes).trim().padz(2) + ":" + str(seconds).trim().padz(2)
            else
                return str(minutes).trim() + ":" + str(seconds).trim().padz(2)
            end if
        end function

        ' Check if timer is currently active
        ' @return Boolean
        isActive: function() as Boolean
            return m.isActive
        end function

        ' Get the current preset index
        ' @return Integer
        getCurrentPresetIndex: function() as Integer
            return m.selectedPresetIndex
        end function

        ' Clean up observers and resources
        cleanup: function()
            m.stop()
            m.isActive = false
            if m.timerLabel <> invalid then
                m.timerLabel.visible = false
            end if
            if m.panel <> invalid then
                m.panel.visible = false
            end if
        end function
    }

    return obj
end function

' Format seconds into MM:SS or HH:MM:SS string
' @param totalSeconds Integer - Total seconds
' @return String - Formatted duration string
function formatDuration(totalSeconds as Integer) as String
    if totalSeconds < 0 then totalSeconds = 0
    hours = totalSeconds / 3600
    minutes = (totalSeconds mod 3600) / 60
    seconds = totalSeconds mod 60

    if hours > 0 then
        return str(hours).trim() + ":" + str(minutes).trim().padz(2) + ":" + str(seconds).trim().padz(2)
    else
        return str(minutes).trim() + ":" + str(seconds).trim().padz(2)
    end if
end function

' Pad a string with zeros on the left
' @param s String - String to pad
' @param width Integer - Minimum width
' @return String - Padded string
function padz(s as String, width as Integer) as String
    while s.len() < width
        s = "0" + s
    end while
    return s
end function

' Factory function
function SleepTimerFactory() as Object
    return SleepTimer()
end function
