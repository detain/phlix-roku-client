' source/components/PlayerScene.brs

' copyright 2026 Joe Huss
'


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

    ' ============================================================= '
    ' F13 SyncPlay "Watch Together" - additive, gated behind the panel. '
    ' All state initialised inert; the socket task is created LAZILY on   '
    ' first panel open (ToggleSyncPanel), so the default playback path is '
    ' byte-unchanged until then.                                         '
    ' ============================================================= '
    m.proto = SyncPlayProtocol()
    m.syncTask = invalid            ' the SyncPlayTask node (lazily created)
    m.syncActive = false            ' true once connected/active
    m.syncPanelOpen = false         ' true while the overlay is visible
    m.syncFollowing = false         ' true once in a group (apply remote playback)
    m.syncIsHost = false            ' true when this device is the group host
    m.syncGroupId = ""              ' the joined group_id
    m.yourId = ""                   ' our member id (from group_state.your_id)
    m.applyingRemote = false        ' guard: a remote-driven change must NOT rebroadcast
    m.syncGroupIds = []             ' parallel array of group ids for syncGroupList rows

    m.syncPanel = m.top.FindNode("syncPanel")
    m.syncGroupList = m.top.FindNode("syncGroupList")
    m.syncCreateButton = m.top.FindNode("syncCreateButton")
    m.syncLeaveButton = m.top.FindNode("syncLeaveButton")
    m.syncStatusLabel = m.top.FindNode("syncStatusLabel")

    if m.syncGroupList <> invalid then m.syncGroupList.ObserveField("itemSelected", "OnSyncGroupSelected")
    if m.syncCreateButton <> invalid then m.syncCreateButton.ObserveField("buttonSelected", "OnSyncCreatePressed")
    if m.syncLeaveButton <> invalid then m.syncLeaveButton.ObserveField("buttonSelected", "OnSyncLeavePressed")

    ' REST group-list snapshot task is created LAZILY on first panel open (see
    ' ToggleSyncPanel) so the default playback path is truly byte-unchanged - no
    ' extra ApiTask node nor observer when SyncPlay is never used.
    m.syncListTask = invalid

    ' ============================================================= '
    ' G4 Quality picker (multi-variant ABR) - additive, inert until the '
    ' user opens the panel (the Up key). "Auto" = the multi-variant       '
    ' master (native ABR, byte-unchanged from before); a pinned rung swaps '
    ' to that variant's own HLS media playlist. The ladder is populated    '
    ' from the transcode start/status response (server A7); it stays empty  '
    ' for a direct-play or legacy single-variant stream, where the picker   '
    ' shows Auto only and no-ops gracefully.                                '
    ' ============================================================= '
    m.variants = []                 ' parsed A7 ladder ({id,label,url}); empty until a transcode
    m.masterUrl = ""                ' the multi-variant master url (Auto / native ABR)
    m.qualityPanelOpen = false      ' true while the picker overlay is visible
    m.qualityIds = []               ' parallel id array for qualityList rows ("auto" + rung ids)
    m.switchingQuality = false      ' one-shot guard: a content swap is in flight (see OnPlayerStateChange)

    m.qualityPanel = m.top.FindNode("qualityPanel")
    m.qualityList = m.top.FindNode("qualityList")
    m.qualityStatusLabel = m.top.FindNode("qualityStatusLabel")

    if m.qualityList <> invalid then m.qualityList.ObserveField("itemSelected", "OnQualitySelected")
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
        ' P2-S5: store trickplay data (sprite_path, timeline_path, dimensions)
        ' for chapter thumbnail markers on the seekbar.
        if args.trickplay <> invalid then
            m.trickplay = args.trickplay
        else
            m.trickplay = invalid
        end if
    end if

    ' P2-S5: initialize trickplay/chapter UI state
    m.chapterLabel = m.top.FindNode("chapterLabel")
    m.chapterLabelTimer = invalid
    m.chapterMarkers = []

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

    ' P2-S5: build chapter markers on the seekbar once duration is known.
    ' Defer until first OnPositionUpdate when duration > 0.
    m.chaptersReady = false

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

    ' G4 quality-switch guard. OnQualitySelected reassigns `content` on a *live*
    ' Video node to change quality; on several Roku firmwares/models assigning a
    ' new ContentNode to a playing Video emits a TRANSIENT state="stopped" before
    ' "buffering"/"playing". Without this guard that transient stop would hit the
    ' "stopped" branch below and tear the whole player down (ClosePlayer) instead
    ' of switching quality. We clear the one-shot flag on the first NON-"stopped"
    ' transition (buffering/playing) so any transient stop that arrives before the
    ' new source is confirmed is suppressed; on firmware that emits NO transient
    ' stop the flag clears immediately here -> pure no-op with zero downside. A
    ' genuine stop AFTER playback resumes still closes the player (flag already
    ' cleared), and BACK closes via OnBackPressed->ClosePlayer regardless of it.
    if state <> "stopped" then m.switchingQuality = false

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
        ' Suppress the transient "stopped" some firmware emits mid quality-switch
        ' content swap (see the guard note above); a real stop still closes.
        if m.switchingQuality then return
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
            CaptureVariants(data)
            PlayPreferredOrMaster()
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
            CaptureVariants(data)
            PlayPreferredOrMaster()
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

        ' P2-S5: build chapter markers on first frame when duration is known.
        if not m.chaptersReady then
            BuildChapterMarkers()
            m.chaptersReady = true
        end if

        ' P2-S5: update chapter label if playing (hide if not near a chapter).
        UpdateChapterLabel(position, duration)

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

' P2-S5: Build chapter tick markers on the seekbar.
' Chapters come from playbackInfo.chapters: [{start_seconds, end_seconds, title}, ...]
' Each marker is a small colored Rectangle positioned at the chapter start.
sub BuildChapterMarkers()
    if m.chapterMarkers.Count() > 0 then
        ' Already built (e.g. on resume after transcode).
        return
    end if

    if m.playbackInfo = invalid or m.playbackInfo.chapters = invalid then
        return
    end if
    if m.videoPlayer = invalid or m.videoPlayer.duration <= 0 then
        return
    end if

    duration = m.videoPlayer.duration
    chapters = m.playbackInfo.chapters
    if type(chapters) <> "roArray" or chapters.Count() = 0 then
        return
    end if

    ' The seekbar parent is at translation [213,40] with height 80.
    ' We place markers just above the seekbar (at y offset 32 = 40 - 8).
    seekbarX = 213
    seekbarY = 32
    seekbarWidth = 854
    markerHeight = 6
    markerWidth = 3

    for each ch in chapters
        if ch = invalid then goto nextChapter
        startSec = ch.start_seconds
        endSec = ch.end_seconds
        title = ch.title

        if startSec = invalid or startSec < 0 then goto nextChapter
        if endSec = invalid or endSec <= startSec then goto nextChapter

        ' Convert chapter start time to x position on seekbar.
        chapterX = seekbarX + Int((startSec / duration) * seekbarWidth)
        if chapterX < seekbarX then chapterX = seekbarX
        if chapterX > seekbarX + seekbarWidth - markerWidth then goto nextChapter

        marker = CreateObject("roSGNode", "Rectangle")
        marker.height = markerHeight
        marker.width = markerWidth
        marker.color = "#ffcc00"   ' gold tick for chapter start
        marker.translation = [chapterX, seekbarY]
        marker.visible = true

        m.top.Append(marker)
        m.chapterMarkers.Push(marker)

        nextChapter:
    end for
end sub

' P2-S5: Show the chapter label briefly when the user seeks near a chapter.
' @param position Float - current playback position in seconds
' @param duration Float - total duration in seconds
sub UpdateChapterLabel(position as Float, duration as Float)
    chapter = GetChapterAtPosition(position, duration)
    if chapter <> invalid then
        title = chapter.title
        if title <> invalid and title <> "" then
            ShowChapterLabel(title)
        end if
    end if
end sub

' P2-S5: Return the chapter object at the given position, or invalid.
function GetChapterAtPosition(position as Float, duration as Float) as Object
    if m.playbackInfo = invalid or m.playbackInfo.chapters = invalid then
        return invalid
    end if

    chapters = m.playbackInfo.chapters
    if type(chapters) <> "roArray" or chapters.Count() = 0 then
        return invalid
    end if

    for each ch in chapters
        if ch = invalid then goto nextGetChapter
        startSec = ch.start_seconds
        endSec = ch.end_seconds

        if startSec = invalid or endSec = invalid then goto nextGetChapter

        if position >= startSec and position < endSec then
            return ch
        end if

        nextGetChapter:
    end for
    return invalid
end function

' P2-S5: Display the chapter label for 2 seconds then fade it out.
' @param title String - chapter title to display
sub ShowChapterLabel(title as String)
    if m.chapterLabel = invalid then return

    m.chapterLabel.text = title
    m.chapterLabel.visible = true

    ' Reset existing timer if chapter changed mid-countdown.
    if m.chapterLabelTimer <> invalid then
        m.chapterLabelTimer.control = "stop"
        m.chapterLabelTimer.UnObserveField("fire")
        m.top.RemoveChild(m.chapterLabelTimer)
    end if

    m.chapterLabelTimer = CreateObject("roSGNode", "Timer")
    m.chapterLabelTimer.duration = 2
    m.chapterLabelTimer.repeat = false
    m.chapterLabelTimer.ObserveField("fire", "OnChapterLabelTimerFire")
    m.top.Append(m.chapterLabelTimer)
    m.chapterLabelTimer.control = "start"
end sub

' P2-S5: Hide the chapter label when the timer fires.
sub OnChapterLabelTimerFire()
    if m.chapterLabel <> invalid then
        m.chapterLabel.visible = false
    end if
    if m.chapterLabelTimer <> invalid then
        m.chapterLabelTimer.UnObserveField("fire")
        m.top.RemoveChild(m.chapterLabelTimer)
        m.chapterLabelTimer = invalid
    end if
end sub

sub ClosePlayer()
    ' Clean up timers
    stopTranscodePollTimer()
    stopProgressTimer()

    ' Clean up skip button
    if m.skipButtonComponent <> invalid then
        m.skipButtonComponent.cleanup()
    end if

    ' P2-S5: clean up chapter markers
    for each marker in m.chapterMarkers
        if marker <> invalid then
            m.top.RemoveChild(marker)
        end if
    end for
    m.chapterMarkers = []

    ' P2-S5: clean up chapter label timer
    if m.chapterLabelTimer <> invalid then
        m.chapterLabelTimer.UnObserveField("fire")
        m.top.RemoveChild(m.chapterLabelTimer)
        m.chapterLabelTimer = invalid
    end if
    if m.chapterLabel <> invalid then
        m.chapterLabel.visible = false
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

    ' --- F13 SyncPlay teardown (pairs every ObserveField from Init/open). ---
    if m.syncTask <> invalid then
        m.syncTask.UnObserveField("event")
        ' Best-effort close of the WS connection.
        m.syncTask.command = { kind: "close" }
        m.syncTask = invalid
    end if
    if m.syncGroupList <> invalid then m.syncGroupList.UnObserveField("itemSelected")
    if m.syncCreateButton <> invalid then m.syncCreateButton.UnObserveField("buttonSelected")
    if m.syncLeaveButton <> invalid then m.syncLeaveButton.UnObserveField("buttonSelected")
    if m.syncListTask <> invalid then m.syncListTask.UnObserveField("response")

    ' --- G4 Quality picker teardown (pairs the ObserveField from Init). ---
    if m.qualityList <> invalid then m.qualityList.UnObserveField("itemSelected")

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
        ' --- F13 SyncPlay: panel handling (additive). When the panel is open,
        '     "back"/"options" close it and the panel widgets own the rest. ---
        if m.syncPanelOpen then
            if key = "back" or key = "options" then
                CloseSyncPanel()
                handled = true
            end if
            return handled
        end if

        ' --- G4 Quality picker: when open, "back"/"up" close it and the
        '     LabelList owns the rest of navigation/selection. ---
        if m.qualityPanelOpen then
            if key = "back" or key = "up" then
                CloseQualityPanel()
                handled = true
            end if
            return handled
        end if

        ' "*" (options) opens Watch Together. Disabled in hub mode.
        if key = "options" then
            ToggleSyncPanel()
            handled = true
        else if key = "up" then
            ' G4: Up opens the video-quality picker.
            ToggleQualityPanel()
            handled = true
        else if key = "back" then
            OnBackPressed()
            handled = true
        else if key = "play" then
            if m.isPlaying then
                m.videoPlayer.control = "pause"
                SyncBroadcastPause()
            else
                m.videoPlayer.control = "resume"
                SyncBroadcastPlay()
            end if
            handled = true
        else if key = "pause" then
            m.videoPlayer.control = "pause"
            SyncBroadcastPause()
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

    ' P2-S5: show chapter label if we landed near a chapter boundary.
    chapter = GetChapterAtPosition(newPosition, duration)
    if chapter <> invalid and chapter.title <> invalid then
        ShowChapterLabel(chapter.title)
    end if

    ' F13 SyncPlay: a host's local seek is broadcast (from old -> new position).
    SyncBroadcastSeek(position, newPosition)
end sub

' ===================================================================== '
' F13 SyncPlay "Watch Together" - additive integration. Nothing below   '
' runs unless the user opens the panel (ToggleSyncPanel). When the panel '
' is never opened, m.syncTask stays invalid and every guard is false, so '
' the default playback path is byte-unchanged.                          '
' ===================================================================== '

' Open/close the panel. On first open: gate hub mode out, fetch the REST group
' snapshot, and lazily create + connect the SyncPlayTask. roStreamSocket is
' plaintext-only -> ws:// against :8097 (see worklog §1e/§2).
sub ToggleSyncPanel()
    if m.syncPanelOpen then
        CloseSyncPanel()
        return
    end if

    ' Hub mode: no WS relay path (hub SP1 pending) -> disabled with a message.
    if GetConnectionKind() = "hub" then
        ShowErrorDialog("Watch Together isn't available in hub mode yet")
        return
    end if

    m.syncPanelOpen = true
    if m.syncPanel <> invalid then m.syncPanel.visible = true
    SetSyncStatus("Loading groups…")

    ' Lazily create the REST group-list ApiTask + its observer on first open, so
    ' the default playback path never spins up an extra node/observer.
    if m.syncListTask = invalid then
        m.syncListTask = CreateObject("roSGNode", "ApiTask")
        m.syncListTask.ObserveField("response", "OnSyncListResponse")
    end if

    ' Refresh the group list snapshot.
    m.syncListTask.request = { op: "getSyncPlayGroups" }
    m.syncListTask.control = "run"

    ' Lazily create + connect the socket task.
    if m.syncTask = invalid then ConnectSyncTask()

    if m.syncGroupList <> invalid then m.syncGroupList.SetFocus(true)
end sub

sub CloseSyncPanel()
    m.syncPanelOpen = false
    if m.syncPanel <> invalid then m.syncPanel.visible = false
    m.top.SetFocus(true)
end sub

' Build the plaintext ws:// SyncPlay url parts from the connected server origin and
' create + connect the SyncPlayTask. Direct mode only (hub gated in ToggleSyncPanel).
sub ConnectSyncTask()
    parts = BuildSyncPlayWsParts()
    if parts = invalid then
        SetSyncStatus("SyncPlay unavailable")
        return
    end if

    m.syncTask = CreateObject("roSGNode", "SyncPlayTask")
    m.syncTask.ObserveField("event", "OnSyncEvent")

    memberName = Storage.get("device_name")
    if memberName = invalid or memberName = "" then memberName = "Roku"

    m.syncTask.config = {
        host: parts.host
        port: parts.port
        path: parts.path
        memberName: memberName
    }
    m.syncActive = true
    m.syncTask.control = "run"
    SetSyncStatus("Connecting…")
end sub

' Derive { host, port:8097, path:"/syncplay?token=..." } from GetServerUrl().
' Forces ws scheme implicitly (we only return host/port/path; the Task opens a
' plaintext socket). Returns invalid when no token / host can be derived.
function BuildSyncPlayWsParts() as Object
    serverUrl = GetServerUrl()
    if serverUrl = invalid or serverUrl = "" then return invalid

    ' Strip scheme.
    rest = serverUrl
    schemeIdx = Instr(1, rest, "://")
    if schemeIdx > 0 then rest = Mid(rest, schemeIdx + 3)

    ' Drop any path/query after the authority.
    slashIdx = Instr(1, rest, "/")
    if slashIdx > 0 then rest = Left(rest, slashIdx - 1)

    ' Split host:port (we IGNORE the origin port; SyncPlay is always :8097).
    host = rest
    colonIdx = Instr(1, rest, ":")
    if colonIdx > 0 then host = Left(rest, colonIdx - 1)
    if host = "" then return invalid

    token = Storage.get("auth_token")
    if token = invalid then token = ""

    path = "/syncplay?token=" + UrlEncode(token)
    return { host: host, port: 8097, path: path }
end function

' REST group-list snapshot response -> populate the LabelList + parallel id array.
sub OnSyncListResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return
    if resp.op <> "getSyncPlayGroups" then return

    m.syncGroupIds = []
    content = CreateObject("roSGNode", "ContentNode")

    groups = invalid
    if resp.ok and resp.data <> invalid and resp.data.DoesExist("groups") and type(resp.data.groups) = "roArray" then
        groups = resp.data.groups
    end if

    if groups <> invalid then
        for each g in groups
            if g <> invalid then
                ' id may be a number -> stringify before any later URL/wire use.
                gid = ""
                if g.DoesExist("id") and g.id <> invalid then gid = SyncStringifyId(g.id)
                m.syncGroupIds.Push(gid)
                content.AddChild({ title: SyncGroupCaption(g) })
            end if
        end for
    end if

    if m.syncGroupList <> invalid then m.syncGroupList.content = content

    if m.syncGroupIds.Count() = 0 then
        SetSyncStatus("No groups - create one to start")
    else
        SetSyncStatus("Select a group to join, or Create")
    end if
end sub

' Caption for a group row: "<name> (<n>) [lock]". member_count is numeric ->
' guard DoesExist+invalid then stringify (never an Integer<>String compare).
function SyncGroupCaption(g as Object) as String
    if g = invalid then return ""
    name = ""
    ' Harden: a possibly-numeric JSON field must be type-guarded before the
    ' <> "" / concat (Integer<>String comparison crashes).
    if g.DoesExist("name") and type(g.name) = "roString" and g.name <> "" then name = g.name
    if name = "" then name = "Group"

    count = ""
    if g.DoesExist("member_count") and g.member_count <> invalid then
        count = " (" + str(Int(g.member_count)).Trim() + ")"
    end if

    lock = ""
    if SyncIsTruthy(g, "has_password") then lock = "  [locked]"

    return name + count + lock
end function

' Join the selected group over the WS.
sub OnSyncGroupSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.syncGroupIds.Count() then return
    gid = m.syncGroupIds[index]
    if gid = "" then return
    if m.syncTask = invalid then return

    SetSyncStatus("Joining…")
    m.syncTask.command = { kind: "join", group_id: gid }
end sub

' Create a new group (no on-screen keyboard - name is derived from the device).
sub OnSyncCreatePressed()
    if m.syncTask = invalid then return
    deviceName = Storage.get("device_name")
    if deviceName = invalid or deviceName = "" then deviceName = "Roku"
    SetSyncStatus("Creating group…")
    m.syncTask.command = { kind: "create", group_name: deviceName + "'s Room" }
end sub

' Leave the current group (also closes the socket task-side).
sub OnSyncLeavePressed()
    if m.syncTask = invalid then return
    m.syncTask.command = { kind: "leave", group_id: m.syncGroupId }
    m.syncFollowing = false
    m.syncIsHost = false
    m.syncGroupId = ""
    SetSyncStatus("Left the group")
end sub

' Task->scene event observer. THREAD-SAFE: only assoc/string/number cross. The
' task may batch multiple events from a single socket read into
' { kind:"batch", items:[...] } (rapid same-field writes coalesce under
' SceneGraph) - unwrap and dispatch each via HandleSyncEvent; otherwise dispatch
' the single event directly.
sub OnSyncEvent(event as Object)
    ev = event.getData()
    if ev = invalid then return
    if not ev.DoesExist("kind") then return

    if ev.kind = "batch" then
        if ev.DoesExist("items") and type(ev.items) = "roArray" then
            for each one in ev.items
                if one <> invalid then HandleSyncEvent(one)
            end for
        end if
        return
    end if

    HandleSyncEvent(ev)
end sub

' Dispatch ONE scene event assoc (shared by the single and batched paths).
sub HandleSyncEvent(ev as Object)
    if ev = invalid then return
    if not ev.DoesExist("kind") then return
    kind = ev.kind

    if kind = "open" then
        SetSyncStatus("Connected")

    else if kind = "group_state" then
        group = invalid
        if ev.DoesExist("group") and type(ev.group) = "roAssociativeArray" then group = ev.group
        yourId = ""
        if ev.DoesExist("your_id") and ev.your_id <> invalid then yourId = ev.your_id
        m.yourId = yourId
        m.syncFollowing = true

        if group <> invalid then
            if group.DoesExist("group_id") and group.group_id <> invalid then m.syncGroupId = SyncStringifyId(group.group_id)
            hostId = ""
            if group.DoesExist("host_id") and group.host_id <> invalid then hostId = SyncStringifyId(group.host_id)
            m.syncIsHost = (hostId <> "" and hostId = m.yourId)

            gname = ""
            if group.DoesExist("group_name") and type(group.group_name) = "roString" and group.group_name <> "" then gname = group.group_name
            count = ""
            if group.DoesExist("member_count") and group.member_count <> invalid then count = str(Int(group.member_count)).Trim() + " in group"
            role = "Guest"
            if m.syncIsHost then role = "Host"
            SetSyncStatus(gname + " - " + count + " - " + role)
        end if

    else if kind = "playback" then
        ApplyRemotePlayback(ev)

    else if kind = "info" then
        msg = ""
        if ev.DoesExist("message") and type(ev.message) = "roString" then msg = ev.message
        if ev.DoesExist("member_name") and type(ev.member_name) = "roString" and ev.member_name <> "" then
            msg = ev.member_name + " joined"
        end if
        if msg <> "" then SetSyncStatus(msg)

    else if kind = "host_elect" then
        electedId = ""
        if ev.DoesExist("elected_id") and ev.elected_id <> invalid then electedId = ev.elected_id
        m.syncIsHost = (electedId <> "" and electedId = m.yourId)
        if m.syncIsHost then
            SetSyncStatus("You are now host")
        else
            SetSyncStatus("Host changed")
        end if

    else if kind = "timesync" then
        ' A bool crossing the task->scene field boundary may box as "roBoolean"
        ' (not just "Boolean") - accept BOTH.
        stable = false
        if ev.DoesExist("stable") and (type(ev.stable) = "Boolean" or type(ev.stable) = "roBoolean") then stable = ev.stable
        if stable then
            SetSyncStatus("In sync")
        end if

    else if kind = "error" then
        msg = "SyncPlay error"
        if ev.DoesExist("message") and type(ev.message) = "roString" and ev.message <> "" then msg = ev.message
        SetSyncStatus(msg)
        m.syncFollowing = false
        m.syncIsHost = false

    else if kind = "closed" then
        SetSyncStatus("Disconnected")
        m.syncFollowing = false
        m.syncIsHost = false
        m.syncActive = false
    end if
end sub

' Apply a host's rebroadcast play/pause/seek to the local Video node. Echo-
' suppressed by member_id == our id. The drift-corrected position arrives as
' adjusted_ms (ms) from the task -> convert ms->seconds before seek. The
' m.applyingRemote guard prevents the resulting local state change from
' re-broadcasting.
sub ApplyRemotePlayback(ev as Object)
    if not m.syncFollowing then return
    if m.videoPlayer = invalid then return

    ' Echo-suppression: ignore our own rebroadcast.
    if ev.DoesExist("member_id") and ev.member_id <> invalid and ev.member_id = m.yourId then return

    t = ""
    if ev.DoesExist("type") and ev.type <> invalid then t = ev.type

    adjustedMs# = 0.0
    if ev.DoesExist("adjusted_ms") and ev.adjusted_ms <> invalid then adjustedMs# = ev.adjusted_ms
    seconds# = adjustedMs# / 1000.0
    if seconds# < 0 then seconds# = 0.0

    m.applyingRemote = true

    if t = "syncplay_playback_play" then
        m.videoPlayer.seek = seconds#
        m.videoPlayer.control = "play"
        m.isPlaying = true
    else if t = "syncplay_playback_pause" then
        m.videoPlayer.seek = seconds#
        m.videoPlayer.control = "pause"
        m.isPlaying = false
    else if t = "syncplay_playback_seek" then
        m.videoPlayer.seek = seconds#
    end if

    m.applyingRemote = false
end sub

' --- Host broadcast helpers. Only the group host broadcasts, and only when the
'     change was NOT itself remote-applied (m.applyingRemote). All are no-ops
'     unless syncActive + syncIsHost. Positions go out as MILLISECONDS. ---

function SyncShouldBroadcast() as Boolean
    if not m.syncActive then return false
    if not m.syncIsHost then return false
    if m.applyingRemote then return false
    if m.syncTask = invalid then return false
    return true
end function

' Current local position in MS as a LongInteger (position is seconds Float;
' multiply with a LongInteger literal to stay 64-bit-safe).
function SyncPositionMs() as LongInteger
    if m.videoPlayer = invalid then return 0&
    pos# = m.videoPlayer.position
    return Int(pos# * 1000.0)
end function

sub SyncBroadcastPlay()
    if not SyncShouldBroadcast() then return
    m.syncTask.command = { kind: "play", group_id: m.syncGroupId, position_ms: SyncPositionMs() }
end sub

sub SyncBroadcastPause()
    if not SyncShouldBroadcast() then return
    m.syncTask.command = { kind: "pause", group_id: m.syncGroupId, position_ms: SyncPositionMs() }
end sub

sub SyncBroadcastSeek(fromSeconds as Float, toSeconds as Float)
    if not SyncShouldBroadcast() then return
    fromMs = Int(fromSeconds * 1000.0)
    toMs = Int(toSeconds * 1000.0)
    m.syncTask.command = { kind: "seek", group_id: m.syncGroupId, from_ms: fromMs, to_ms: toMs }
end sub

sub SetSyncStatus(text as String)
    if m.syncStatusLabel <> invalid then m.syncStatusLabel.text = text
end sub

' Stringify an id that may be a JSON number OR string (never concat a raw number).
function SyncStringifyId(v as Object) as String
    if v = invalid then return ""
    tp = type(v)
    if tp = "String" or tp = "roString" then return v
    if tp = "Integer" or tp = "roInt" then return str(v).Trim()
    if tp = "LongInteger" or tp = "roLongInteger" then return (str(v)).Trim()
    if tp = "Float" or tp = "roFloat" or tp = "Double" or tp = "roDouble" then return str(Int(v)).Trim()
    return ""
end function

' Truthy guard for a possibly-bool/numeric JSON flag (never an Integer<>String
' compare). Accepts Boolean true, a non-zero number, or the string "true"/"1".
function SyncIsTruthy(container as Object, key as String) as Boolean
    if container = invalid then return false
    if not container.DoesExist(key) then return false
    v = container[key]
    if v = invalid then return false
    tp = type(v)
    if tp = "Boolean" or tp = "roBoolean" then return v
    if tp = "Integer" or tp = "roInt" or tp = "LongInteger" or tp = "roLongInteger" or tp = "Float" or tp = "roFloat" or tp = "Double" or tp = "roDouble" then return (v <> 0)
    if tp = "String" or tp = "roString" then return (v = "true" or v = "1")
    return false
end function

' ===================================================================== '
' G4 Quality picker (multi-variant ABR). Additive: nothing here runs     '
' unless a transcode has produced a ladder AND the user opens the panel  '
' (the Up key). "Auto" plays the multi-variant master (native ABR); a    '
' pinned rung plays that variant's own signed HLS media playlist. The    '
' chosen quality is persisted (Storage "preferred_quality") and re-applied'
' on the next ready transcode. Direct-play / legacy single-variant jobs   '
' carry no ladder, so the picker offers Auto only and no-ops gracefully.  '
' ===================================================================== '

' Capture the ladder + master url from a ready transcode start/status response.
' parseVariants (ApiClient) yields a compact {id,label,url} list, highest-first.
sub CaptureVariants(data as Object)
    m.masterUrl = ""
    if data <> invalid and data.DoesExist("master_url") and (type(data.master_url) = "roString" or type(data.master_url) = "String") then
        m.masterUrl = data.master_url
    end if
    m.variants = GetApiClient().parseVariants(data)
    if m.variants = invalid then m.variants = []
end sub

' Play the stream matching the persisted quality preference: a pinned rung's
' media playlist, else the multi-variant master (Auto). Falls back to the master
' whenever the preference is "auto"/unset or the pinned rung is absent from THIS
' job's clamped ladder (e.g. a 1080p pin against a 720p-max source). With no
' ladder this is byte-identical to the old PlayHls(master_url) behaviour.
sub PlayPreferredOrMaster()
    pref = Storage.get("preferred_quality")
    if pref = invalid then pref = ""

    url = m.masterUrl
    if pref <> "" and pref <> "auto" then
        variantUrl = FindVariantUrl(pref)
        if variantUrl <> "" then url = variantUrl
    end if

    PlayHls(url)
end sub

' Return the media-playlist url of the rung with this id, or "" when absent.
function FindVariantUrl(id as String) as String
    for each v in m.variants
        if v <> invalid and v.id = id then return v.url
    end for
    return ""
end function

' Open/close the picker. On open, build the row list (Auto first, then each rung
' highest-first) and focus the list. The video keeps playing behind the overlay.
sub ToggleQualityPanel()
    if m.qualityPanelOpen then
        CloseQualityPanel()
        return
    end if

    m.qualityPanelOpen = true
    if m.qualityPanel <> invalid then m.qualityPanel.visible = true

    m.qualityIds = ["auto"]
    content = CreateObject("roSGNode", "ContentNode")
    content.AddChild({ title: QualityRowCaption("auto", "Auto") })
    for each v in m.variants
        if v <> invalid then
            m.qualityIds.Push(v.id)
            content.AddChild({ title: QualityRowCaption(v.id, v.label) })
        end if
    end for
    if m.qualityList <> invalid then m.qualityList.content = content

    if m.variants.Count() = 0 then
        SetQualityStatus("Adaptive streaming - no fixed-quality ladder for this stream")
    else
        SetQualityStatus("Auto adapts to your connection; pick a rung to lock it")
    end if

    if m.qualityList <> invalid then m.qualityList.SetFocus(true)
end sub

sub CloseQualityPanel()
    m.qualityPanelOpen = false
    if m.qualityPanel <> invalid then m.qualityPanel.visible = false
    m.top.SetFocus(true)
end sub

' Caption for a row; the currently-persisted preference is marked "(current)".
' (Plain text - the Roku system font has no reliable check-mark glyph.)
function QualityRowCaption(id as String, label as String) as String
    pref = Storage.get("preferred_quality")
    if pref = invalid or pref = "" then pref = "auto"
    if id = pref then return label + "  (current)"
    return label
end function

' Row selected: persist the choice, preserve the current position across the
' source swap (seed the existing resume machinery so OnPlayerStateChange re-seeks
' on the next "playing"), then play the master (Auto) or the pinned rung's url.
sub OnQualitySelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.qualityIds.Count() then return
    id = m.qualityIds[index]

    Storage.set("preferred_quality", id)

    ' Resolve the target stream url first so the (live) content swap happens
    ' exactly once. Auto -> the multi-variant master; a pinned rung -> its own
    ' media playlist, falling back to the master when the rung is absent from
    ' THIS job's clamped ladder.
    url = ""
    if id = "auto" then
        url = m.masterUrl
    else
        url = FindVariantUrl(id)
        if url = "" then url = m.masterUrl
    end if

    ' No ladder / no master to swap to -> just close the picker; the current
    ' stream keeps playing untouched (and we must NOT arm the switch guard, or a
    ' later genuine stop could be wrongly suppressed).
    if url = "" then
        CloseQualityPanel()
        return
    end if

    ' Preserve the current position across the source swap (seed the existing
    ' resume machinery so OnPlayerStateChange re-seeks on the next "playing").
    if m.videoPlayer <> invalid then
        currentPos = m.videoPlayer.position
        if currentPos > 0 then
            m.resumeSeconds = currentPos
            m.resumeApplied = false
        end if
    end if

    ' Arm the quality-switch guard just BEFORE the content reassignment (inside
    ' PlayHls) so OnPlayerStateChange does not misread the firmware's transient
    ' "stopped" as a real stop. See the guard note in OnPlayerStateChange.
    m.switchingQuality = true

    PlayHls(url)

    CloseQualityPanel()
end sub

sub SetQualityStatus(text as String)
    if m.qualityStatusLabel <> invalid then m.qualityStatusLabel.text = text
end sub