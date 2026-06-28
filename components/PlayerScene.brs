' source/components/PlayerScene.brs

' ===========================================
' Phlix Player Scene
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

    ' Skip button nodes
    m.skipButton = m.top.FindNode("skipButton")
    m.skipButtonLabel = m.top.FindNode("skipButtonLabel")

    ' Initialize skip button component
    m.skipButtonComponent = SkipButton()
    m.skipButtonComponent.init(m.skipButton, m.skipButtonLabel)

    ' Setup button handlers
    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    if m.skipButton <> invalid then
        m.skipButton.ObserveField("buttonSelected", "OnSkipButtonSelected")
    end if

    ' ApiTask: transcode start/status (observed). progressTask: session +
    ' progress reporting (NOT observed - fire-and-forget).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")
    m.progressTask = CreateObject("roSGNode", "ApiTask")

    m.itemId = ""
    m.item = invalid
    m.playbackInfo = invalid
    m.isPlaying = false
    ' Throttle is tracked in SECONDS (Float), never in 100ns ticks (a 32-bit
    ' Int overflows past ~214s).
    m.lastReportedPosition = 0
    m.transcodeAttempted = false
    m.transcodeJobId = ""
    m.transcodePollCount = 0
    m.resumeSeconds = 0.0
    m.resumeApplied = false
end sub

sub Show(itemId as String, args as Object)
    m.itemId = itemId
    m.isPlaying = false
    m.lastReportedPosition = 0
    m.transcodeAttempted = false
    m.transcodeJobId = ""
    m.transcodePollCount = 0

    ' Optional resume position (F3 continue-watching). DetailScene omits it ->
    ' stays 0 -> playback starts from the beginning (no behavior change).
    m.resumeSeconds = 0.0
    m.resumeApplied = false

    if args <> invalid then
        m.item = args.item
        m.playbackInfo = args.playbackInfo
        if args.resumeSeconds <> invalid and args.resumeSeconds > 0 then
            m.resumeSeconds = args.resumeSeconds
        end if
    end if

    ' Title
    if m.titleLabel <> invalid and m.item <> invalid then
        m.titleLabel.text = m.item.name
    end if

    ' Skip markers - pass the playback-info skip_button_spec straight through
    ' (its keys match SkipButton's expected skip_intro_start/... fields).
    if m.playbackInfo <> invalid and m.playbackInfo.skip_button_spec <> invalid then
        m.skipButtonComponent.setMarkers(m.playbackInfo.skip_button_spec)
    else
        m.skipButtonComponent.setMarkers(invalid)
    end if

    ' Signed direct-play URL (no Bearer needed).
    streamUrl = invalid
    if m.item <> invalid then streamUrl = m.item.stream_url
    if streamUrl = invalid or streamUrl = "" then
        ShowErrorDialog("No stream URL available")
        return
    end if

    ' streamformat best-effort: the signed stream_url has no extension. mp4
    ' direct-play works on most models; failures trigger the transcode fallback.
    stream = CreateObject("roSGNode", "ContentNode")
    stream.url = streamUrl
    stream.streamformat = "mp4"
    m.videoPlayer.content = stream
    m.videoPlayer.control = "play"
    m.isPlaying = true

    ' Create a session once so progress reports have a session_id (persisted to
    ' Storage by ApiClient.createSession; a later fresh GetApiClient restores it).
    m.progressTask.request = { op: "createSession" }
    m.progressTask.control = "run"

    ' Start progress reporting timer
    startProgressTimer()
end sub

sub OnPlayerStateChange(event as Object)
    state = event.getData()

    if state = "error" then
        print "Video playback error: "; m.videoPlayer.errorCode
        ' Transcode fallback (attempt once).
        if not m.transcodeAttempted then
            m.transcodeAttempted = true
            if m.titleLabel <> invalid and m.item <> invalid then
                m.titleLabel.text = m.item.name + " (Preparing...)"
            end if
            m.apiTask.request = { op: "startTranscode", itemId: m.itemId }
            m.apiTask.control = "run"
        else
            ShowErrorDialog("Playback failed. Please try again.")
        end if
    else if state = "playing" then
        m.isPlaying = true
        ShowControls(false)

        ' Resume seek on the FIRST "playing" transition only (reliable Roku
        ' resume pattern - content is loaded). The single resumeApplied guard
        ' also covers the transcode-fallback PlayHls path, which yields its own
        ' "playing" transition.
        if m.resumeSeconds > 0 and not m.resumeApplied then
            m.videoPlayer.seek = m.resumeSeconds
            m.resumeApplied = true
        end if
    else if state = "paused" then
        m.isPlaying = false
    else if state = "stopped" then
        m.isPlaying = false
        ClosePlayer()
    end if
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "startTranscode" then
        if not resp.ok or resp.data = invalid then
            ShowErrorDialog("Could not start transcode.")
            return
        end if
        data = resp.data
        if data.status = "ready" or data.playlist_ready = true then
            PlayHls(data.master_url)
        else
            m.transcodeJobId = data.job_id
            m.transcodePollCount = 0
            startTranscodePollTimer()
        end if
    else if resp.op = "getTranscodeStatus" then
        if not resp.ok or resp.data = invalid then return
        data = resp.data
        if data.status = "ready" or data.playlist_ready = true then
            stopTranscodePollTimer()
            PlayHls(data.master_url)
        else if data.status = "failed" then
            stopTranscodePollTimer()
            ShowErrorDialog("Transcode failed.")
        end if
    end if
end sub

sub PlayHls(url as Object)
    if url = invalid or url = "" then
        ShowErrorDialog("Transcode produced no stream URL.")
        return
    end if

    if m.titleLabel <> invalid and m.item <> invalid then
        m.titleLabel.text = m.item.name
    end if

    stream = CreateObject("roSGNode", "ContentNode")
    stream.url = url
    stream.streamformat = "hls"
    m.videoPlayer.content = stream
    m.videoPlayer.control = "play"
    m.isPlaying = true
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

        ' Update skip button based on position
        if m.skipButtonComponent <> invalid then
            m.skipButtonComponent.updatePosition(position)
        end if

        ' Report progress to server (throttled to once every 10 seconds).
        ' Throttle is tracked in SECONDS to avoid the 32-bit tick overflow.
        if position - m.lastReportedPosition > 10 then
            ReportProgress(position)
            m.lastReportedPosition = position
        end if
    end if
end sub

sub OnBackPressed()
    StopPlayback()
    ClosePlayer()
end sub

sub OnSkipButtonSelected()
    ' Get target position from skip button component
    if m.skipButtonComponent <> invalid then
        targetPosition = m.skipButtonComponent.getTargetPosition()
        if targetPosition > 0 and m.videoPlayer <> invalid then
            m.videoPlayer.seek = targetPosition
        end if
    end if
end sub

sub ShowControls(shouldShow as Boolean)
    ' Animate controls visibility
end sub

sub StopPlayback()
    if m.videoPlayer <> invalid then
        m.videoPlayer.control = "stop"
    end if

    ' Report final position
    position = m.videoPlayer.position
    if position > 0 then
        ReportProgress(position)
    end if

    ' Stop progress timer
    stopProgressTimer()
end sub

' positionSeconds is in SECONDS. Ticks are 100ns; SecondsToTicks uses Double math
' returning LongInteger so values past ~214s do not overflow a 32-bit Integer.
sub ReportProgress(positionSeconds as Float)
    positionTicks = SecondsToTicks(positionSeconds)
    durationTicks = SecondsToTicks(m.videoPlayer.duration)
    m.progressTask.request = {
        op: "reportProgress"
        mediaItemId: m.itemId
        positionTicks: positionTicks
        durationTicks: durationTicks
        isPaused: (not m.isPlaying)
    }
    m.progressTask.control = "run"
end sub

sub ClosePlayer()
    ' Clean up timers
    stopTranscodePollTimer()
    stopProgressTimer()

    ' Clean up skip button
    if m.skipButtonComponent <> invalid then
        m.skipButtonComponent.cleanup()
    end if

    ' Unobserve the video node fields registered in Init.
    if m.videoPlayer <> invalid then
        m.videoPlayer.UnObserveField("state")
        m.videoPlayer.UnObserveField("position")
    end if

    ' Unobserve button observers registered in Init.
    if m.backButton <> invalid then
        m.backButton.UnObserveField("buttonSelected")
    end if
    if m.skipButton <> invalid then
        m.skipButton.UnObserveField("buttonSelected")
    end if

    ' Stop observing the API task.
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if

    ' Navigate back
    m.top.Close()
end sub

' Progress timer (SceneGraph Timer node - roTimer is not usable in SceneGraph)
sub startProgressTimer()
    if m.progressTimer = invalid then
        m.progressTimer = m.top.CreateChild("Timer")
        m.progressTimer.duration = 1
        m.progressTimer.repeat = true
        m.progressTimer.ObserveField("fire", "OnTimerFire")
        m.progressTimer.control = "start"
    end if
end sub

sub stopProgressTimer()
    if m.progressTimer <> invalid then
        m.progressTimer.control = "stop"
        m.progressTimer.UnObserveField("fire")
        m.top.RemoveChild(m.progressTimer)
        m.progressTimer = invalid
    end if
end sub

sub OnTimerFire()
    ' Keep Roku awake during playback
end sub

' Transcode status poll timer (fires getTranscodeStatus every 2s while pending).
sub startTranscodePollTimer()
    if m.transcodePollTimer = invalid then
        m.transcodePollTimer = m.top.CreateChild("Timer")
        m.transcodePollTimer.duration = 2
        m.transcodePollTimer.repeat = true
        m.transcodePollTimer.ObserveField("fire", "OnTranscodePollFire")
        m.transcodePollTimer.control = "start"
    end if
end sub

sub stopTranscodePollTimer()
    if m.transcodePollTimer <> invalid then
        m.transcodePollTimer.control = "stop"
        m.transcodePollTimer.UnObserveField("fire")
        m.top.RemoveChild(m.transcodePollTimer)
        m.transcodePollTimer = invalid
    end if
end sub

sub OnTranscodePollFire()
    ' Nothing to poll without a job id.
    if m.transcodeJobId = invalid or m.transcodeJobId = "" then
        stopTranscodePollTimer()
        return
    end if

    ' Bound the poll so a stuck job can't spin the timer forever (~30 polls at
    ' 2s = ~60s).
    m.transcodePollCount = m.transcodePollCount + 1
    if m.transcodePollCount > 30 then
        stopTranscodePollTimer()
        ShowErrorDialog("Transcode timed out. Please try again.")
        return
    end if

    m.apiTask.request = { op: "getTranscodeStatus", jobId: m.transcodeJobId }
    m.apiTask.control = "run"
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
