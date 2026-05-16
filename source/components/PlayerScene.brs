' source/components/PlayerScene.brs

' ===========================================
' Phlex Player Scene
' Handles video playback on Roku
' ===========================================

sub Init()
    m.top.SetFocus(true)

    ' Create video player
    m.videoPlayer = m.top.FindNode("videoPlayer")
    m.videoPlayer.EnableCookies()
    m.videoPlayer.SetCertificatesFile("common:/certs/ca-bundle.crt")

    ' Set up listeners
    m.videoPlayer.ObserveField("state", "OnPlayerStateChange")
    m.videoPlayer.ObserveField("position", "OnPositionUpdate")

    ' UI nodes
    m.progressBar = m.top.FindNode("progressBar")
    m.timeLabel = m.top.FindNode("timeLabel")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.backButton = m.top.FindNode("backButton")

    ' Setup button handlers
    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    m.itemId = ""
    m.playbackInfo = invalid
    m.isPlaying = false
    m.lastReportedPosition = 0
end sub

sub Show(itemId as String, playbackInfo as Object)
    m.itemId = itemId
    m.playbackInfo = playbackInfo
    m.isPlaying = false
    m.lastReportedPosition = 0

    ' Set title
    if m.titleLabel <> invalid and playbackInfo.item <> invalid then
        m.titleLabel.text = playbackInfo.item.Name
    end if

    ' Determine stream URL
    streamUrl = playbackInfo.playback_info.Url
    if streamUrl = invalid or streamUrl = "" then
        print "No stream URL available"
        return
    end if

    ' Configure stream
    stream = CreateObject("roSGNode", "ContentNode")
    stream.url = streamUrl
    stream.streamformat = playbackInfo.playback_info.Container

    if playbackInfo.playback_info.Transcoded = true then
        stream.streamformat = "hls"
    end if

    ' Set content and start playback
    m.videoPlayer.content = stream
    m.videoPlayer.control = "play"
    m.isPlaying = true

    ' Start progress reporting
    startProgressTimer()
end sub

sub OnPlayerStateChange(event as Object)
    state = event.getData()

    if state = "error" then
        print "Video playback error: "; m.videoPlayer.errorCode
        ShowErrorDialog("Playback failed. Please try again.")
    else if state = "playing" then
        m.isPlaying = true
        ShowControls(false)
    else if state = "paused" then
        m.isPlaying = false
    else if state = "stopped" then
        m.isPlaying = false
        ClosePlayer()
    end if
end sub

sub OnPositionUpdate(event as Object)
    position = event.getData()
    duration = m.videoPlayer.duration

    if duration > 0 then
        ' Update progress bar
        progress = (position / duration) * 100
        if m.progressBar <> invalid then
            m.progressBar.width = Int(854 * progress / 100)
        end if

        ' Update time label
        if m.timeLabel <> invalid then
            currentTime = FormatTime(position)
            totalTime = FormatTime(duration)
            m.timeLabel.text = currentTime + " / " + totalTime
        end if

        ' Report progress to server (every 10 seconds)
        positionTicks = Int(position * 10000000)
        if positionTicks - m.lastReportedPosition > 100000000 then
            ReportProgress(positionTicks)
            m.lastReportedPosition = positionTicks
        end if
    end if
end sub

sub OnBackPressed()
    StopPlayback()
    ClosePlayer()
end sub

sub ShowControls(show as Boolean)
    ' Animate controls visibility
end sub

sub StopPlayback()
    if m.videoPlayer <> invalid then
        m.videoPlayer.control = "stop"
    end if

    ' Report final position
    position = m.videoPlayer.position
    if position > 0 then
        ReportProgress(Int(position * 10000000))
    end if

    ' Stop progress timer
    stopProgressTimer()
end sub

sub ReportProgress(positionTicks as Integer)
    ' Report to Phlex server
    api.reportProgress(positionTicks, not m.isPlaying)
end sub

sub ClosePlayer()
    ' Navigate back
    m.top.Close()
end sub

' Progress timer
m.progressTimer = invalid

sub startProgressTimer()
    if m.progressTimer = invalid then
        m.progressTimer = CreateObject("roTimer")
        m.progressTimer.SetPort(m.top.GetNodePort())
        m.progressTimer.StartPeriod(1)
        m.progressTimer.ObserveField("fire", "OnTimerFire")
    end if
end sub

sub stopProgressTimer()
    if m.progressTimer <> invalid then
        m.progressTimer.Stop()
        m.progressTimer = invalid
    end if
end sub

sub OnTimerFire()
    ' Keep Roku awake during playback
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            OnBackPressed()
            handled = true
        else if key = "play" then
            if m.isPlaying then
                m.videoPlayer.control = "pause"
            else
                m.videoPlayer.control = "resume"
            end if
            handled = true
        else if key = "pause" then
            m.videoPlayer.control = "pause"
            handled = true
        else if key = "rewind" then
            SeekRelative(-10)
            handled = true
        else if key = "fastforward" then
            SeekRelative(10)
            handled = true
        else if key = "left" then
            SeekRelative(-30)
            handled = true
        else if key = "right" then
            SeekRelative(30)
            handled = true
        end if
    end if

    return handled
end sub

sub SeekRelative(seconds as Float)
    if m.videoPlayer = invalid then return

    position = m.videoPlayer.position
    duration = m.videoPlayer.duration

    newPosition = position + seconds
    if newPosition < 0 then newPosition = 0
    if newPosition > duration then newPosition = duration

    m.videoPlayer.seek = newPosition
end sub