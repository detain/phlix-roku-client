' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/AudiobookPlayerScene.brs

' Audiobook player scene using the Audio node (R7.6).
' Audio playback with chapter navigation and progress write-back.

sub Init()
    m.top.SetFocus(true)

    ' Find all UI nodes
    m.audioPlayer = m.top.FindNode("audioPlayer")
    m.backButton = m.top.FindNode("backButton")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.coverImage = m.top.FindNode("coverImage")
    m.titleLabel2 = m.top.FindNode("titleLabel2")
    m.authorLabel = m.top.FindNode("authorLabel")
    m.chapterLabel = m.top.FindNode("chapterLabel")
    m.progressBar = m.top.FindNode("progressBar")
    m.timeLabel = m.top.FindNode("timeLabel")
    m.durationLabel = m.top.FindNode("durationLabel")
    m.chapterList = m.top.FindNode("chapterList")
    m.prevChapterButton = m.top.FindNode("prevChapterButton")
    m.rewindButton = m.top.FindNode("rewindButton")
    m.playPauseButton = m.top.FindNode("playPauseButton")
    m.forwardButton = m.top.FindNode("forwardButton")
    m.nextChapterButton = m.top.FindNode("nextChapterButton")
    m.loadingLabel = m.top.FindNode("loadingLabel")

    ' Observe audio player fields
    m.audioPlayer.ObserveField("state", "OnPlayerStateChange")
    m.audioPlayer.ObserveField("position", "OnPositionUpdate")

    ' Observe button fields
    m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    m.prevChapterButton.ObserveField("buttonSelected", "OnPrevChapterPressed")
    m.rewindButton.ObserveField("buttonSelected", "OnRewindPressed")
    m.playPauseButton.ObserveField("buttonSelected", "OnPlayPausePressed")
    m.forwardButton.ObserveField("buttonSelected", "OnForwardPressed")
    m.nextChapterButton.ObserveField("buttonSelected", "OnNextChapterPressed")
    m.chapterList.ObserveField("itemSelected", "OnChapterSelected")

    ' Observe top-level requestClose
    m.top.ObserveField("requestClose", "OnRequestClose")

    ' Create progress task for saving progress
    m.progressTask = CreateObject("roSGNode", "ApiTask")
    m.progressTask.ObserveField("response", "OnProgressResponse")

    ' Initialize state variables
    m.itemId = ""
    m.isPlaying = false
    m.chapters = []
    m.currentChapterIndex = 0
    m.pendingAudiobook = invalid
    m.chaptersLoaded = false
    m.progressLoaded = false
    m.savedPositionMs = 0
    m.savedChapterIndex = 0

    ' Progress failure tracking
    m.progressConsecutiveFailures = 0
    m.progressFailuresBeforeWarning = 3
end sub

sub LoadAudiobook(audiobook as Object)
    m.pendingAudiobook = audiobook

    ' Show loading indicator
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
    end if

    ' Set basic info from audiobook object
    m.itemId = audiobook.id

    if m.titleLabel <> invalid then
        m.titleLabel.text = audiobook.title
    end if

    if m.titleLabel2 <> invalid then
        m.titleLabel2.text = audiobook.title
    end if

    if m.authorLabel <> invalid then
        m.authorLabel.text = audiobook.author
    end if

    if m.coverImage <> invalid and audiobook.cover_url <> invalid then
        m.coverImage.uri = audiobook.cover_url
    end if

    ' Reset state
    m.chaptersLoaded = false
    m.progressLoaded = false
    m.chapters = []
    m.currentChapterIndex = 0

    ' Fire API tasks to get chapters and progress
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' Get audiobook chapters
    m.apiTask.request = { op: "getAudiobookChapters", audiobookId: m.itemId }
    if m.apiTask.state = "run" then return
    m.apiTask.control = "run"

    ' Get saved progress
    m.progressTask.request = { op: "getAudiobookProgress", audiobookId: m.itemId }
    if m.progressTask.state = "run" then return
    m.progressTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getAudiobookChapters" then
        if resp.ok and resp.data <> invalid then
            m.chapters = resp.data.chapters
            m.chaptersLoaded = true
            BuildChapterListContent()
        end if
    else if resp.op = "getAudiobookPlaybackInfo" then
        if resp.ok and resp.data <> invalid then
            ' Playback info received - handle stream URL
            streamUrl = invalid

            ' Handle both {url: "..."} and {stream: {url: "..."}} shapes
            if resp.data.url <> invalid then
                streamUrl = resp.data.url
            else if resp.data.stream <> invalid and resp.data.stream.url <> invalid then
                streamUrl = resp.data.stream.url
            end if

            if streamUrl <> invalid and streamUrl <> "" then
                StartPlaybackWithUrl(streamUrl)
            end if
        end if
    end if

    ' Start playback when both chapters and progress are loaded
    if m.chaptersLoaded and m.progressLoaded then
        StartPlayback()
    end if
end sub

sub StartPlayback()
    ' Request playback info from API
    m.apiTask.request = { op: "getAudiobookPlaybackInfo", itemId: m.itemId }
    if m.apiTask.state = "run" then return
    m.apiTask.control = "run"
end sub

sub StartPlaybackWithUrl(streamUrl as String)
    ' Hide loading indicator
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = false
    end if

    ' Build audio content
    audioContent = {
        url: streamUrl
        title: m.pendingAudiobook.title
        artist: m.pendingAudiobook.author
    }

    m.audioPlayer.audioContent = audioContent
    m.audioPlayer.control = "play"
    m.isPlaying = true

    if m.playPauseButton <> invalid then
        m.playPauseButton.title = "Pause"
    end if

    ' Restore saved position if available
    if m.savedPositionMs > 0 then
        savedSeconds = m.savedPositionMs / 1000
        m.audioPlayer.seek = savedSeconds
    end if

    ' Set initial chapter if saved
    if m.savedChapterIndex > 0 and m.savedChapterIndex < m.chapters.Count() then
        m.currentChapterIndex = m.savedChapterIndex
    end if

    UpdateChapterLabel()
end sub

sub OnPlayerStateChange(event as Object)
    state = event.getData()

    if state = "playing" then
        m.isPlaying = true
        if m.playPauseButton <> invalid then
            m.playPauseButton.title = "Pause"
        end if
    else if state = "paused" then
        m.isPlaying = false
        if m.playPauseButton <> invalid then
            m.playPauseButton.title = "Play"
        end if
    else if state = "stopped" or state = "finished" then
        m.isPlaying = false
        ClosePlayer()
    end if
end sub

sub OnPositionUpdate(event as Object)
    position = event.getData()
    duration = m.audioPlayer.duration

    if duration > 0 then
        ' Update time label
        if m.timeLabel <> invalid then
            m.timeLabel.text = FormatTime(position) + " / " + FormatTime(duration)
        end if

        ' Update duration label
        if m.durationLabel <> invalid then
            m.durationLabel.text = FormatTime(duration)
        end if

        ' Update progress bar width
        if m.progressBar <> invalid then
            progress = (position / duration) * 100
            maxWidth = 840
            m.progressBar.width = Int(maxWidth * progress / 100)
        end if

        ' Determine current chapter from position
        if m.chapters.Count() > 0 then
            for i = 0 to m.chapters.Count() - 1
                ch = m.chapters[i]
                if ch <> invalid then
                    startSec = ch.start_seconds
                    endSec = ch.end_seconds
                    if startSec <> invalid and endSec <> invalid then
                        if position >= startSec and position < endSec then
                            if m.currentChapterIndex <> i then
                                m.currentChapterIndex = i
                                UpdateChapterLabel()
                            end if
                            exit for
                        end if
                    end if
                end if
            end for
        end if
    end if
end sub

sub OnPlayPausePressed()
    OnPlayPause()
end sub

sub OnPlayPause()
    if m.isPlaying then
        m.audioPlayer.control = "pause"
    else
        m.audioPlayer.control = "resume"
    end if
end sub

sub OnRewindPressed()
    OnRewind()
end sub

sub OnRewind()
    currentPos = m.audioPlayer.position
    m.audioPlayer.seek = currentPos - 30
end sub

sub OnForwardPressed()
    OnForward()
end sub

sub OnForward()
    currentPos = m.audioPlayer.position
    m.audioPlayer.seek = currentPos + 30
end sub

sub OnPrevChapterPressed()
    OnPrevChapter()
end sub

sub OnPrevChapter()
    if m.currentChapterIndex > 0 then
        m.currentChapterIndex = m.currentChapterIndex - 1
        SeekToChapterStart()
    end if
end sub

sub OnNextChapterPressed()
    OnNextChapter()
end sub

sub OnNextChapter()
    if m.currentChapterIndex < m.chapters.Count() - 1 then
        m.currentChapterIndex = m.currentChapterIndex + 1
        SeekToChapterStart()
    end if
end sub

sub OnChapterSelected(index as Integer)
    m.currentChapterIndex = index
    SeekToChapterStart()
    UpdateChapterLabel()
end sub

sub SeekToChapterStart()
    if m.currentChapterIndex >= 0 and m.currentChapterIndex < m.chapters.Count() then
        ch = m.chapters[m.currentChapterIndex]
        if ch <> invalid and ch.start_seconds <> invalid then
            m.audioPlayer.seek = ch.start_seconds
        end if
    end if
end sub

sub OnBackPressed()
    m.top.requestClose = true
end sub

sub OnRequestClose(event as Object)
    data = event.getData()
    if data = true then
        ClosePlayer()
    end if
end sub

sub ClosePlayer()
    ' Save progress before closing
    SaveProgress()

    ' Unobserve audio player fields
    if m.audioPlayer <> invalid then
        m.audioPlayer.UnObserveField("state")
        m.audioPlayer.UnObserveField("position")
        m.audioPlayer.control = "stop"
    end if

    ' Unobserve button fields
    if m.backButton <> invalid then
        m.backButton.UnObserveField("buttonSelected")
    end if
    if m.prevChapterButton <> invalid then
        m.prevChapterButton.UnObserveField("buttonSelected")
    end if
    if m.rewindButton <> invalid then
        m.rewindButton.UnObserveField("buttonSelected")
    end if
    if m.playPauseButton <> invalid then
        m.playPauseButton.UnObserveField("buttonSelected")
    end if
    if m.forwardButton <> invalid then
        m.forwardButton.UnObserveField("buttonSelected")
    end if
    if m.nextChapterButton <> invalid then
        m.nextChapterButton.UnObserveField("buttonSelected")
    end if
    if m.chapterList <> invalid then
        m.chapterList.UnObserveField("itemSelected")
    end if

    ' Unobserve top-level requestClose
    m.top.UnObserveField("requestClose")

    ' Unobserve API task
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if

    ' Unobserve progress task
    if m.progressTask <> invalid then
        m.progressTask.UnObserveField("response")
    end if

    ' Request close
    m.top.requestClose = true
end sub

sub SaveProgress()
    ' Skip if progress task is already running
    if m.progressTask.state = "run" then return

    if m.itemId = "" or m.itemId = invalid then return

    positionMs = 0
    if m.audioPlayer.position <> invalid then
        positionMs = Int(m.audioPlayer.position * 1000)
    end if

    m.progressTask.request = {
        op: "saveAudiobookProgress"
        audiobookId: m.itemId
        positionMs: positionMs
        currentChapterIndex: m.currentChapterIndex
    }
    if m.progressTask.state = "run" then return
    m.progressTask.control = "run"
end sub

sub OnProgressResponse(event as Object)
    resp = event.getData()

    if resp = invalid then
        print "OnProgressResponse: invalid response"
        m.progressConsecutiveFailures = m.progressConsecutiveFailures + 1
        return
    end if

    ' Handle getAudiobookProgress response
    if resp.op = "getAudiobookProgress" then
        if resp.ok and resp.data <> invalid then
            m.savedPositionMs = resp.data.position_ms
            m.savedChapterIndex = resp.data.current_chapter_index
            m.progressLoaded = true
            m.progressConsecutiveFailures = 0

            ' Start playback when both are ready
            if m.chaptersLoaded then
                StartPlayback()
            end if
        else
            ' Auth/session error (resp.data = invalid)
            print "OnProgressResponse: getAudiobookProgress auth/session error"
            m.progressLoaded = true
            m.progressConsecutiveFailures = m.progressConsecutiveFailures + 1
        end if
        return
    end if

    ' Handle saveAudiobookProgress response (3-outcome pattern)
    if resp.op = "saveAudiobookProgress" then
        if resp.ok and resp.data <> invalid then
            ' Success - do nothing, clear any warning
            m.progressConsecutiveFailures = 0
            return
        end if

        if resp.data = invalid then
            ' Auth/session error
            print "OnProgressResponse: saveAudiobookProgress auth/session error"
            m.progressConsecutiveFailures = m.progressConsecutiveFailures + 1
            return
        end if

        ' Other failure
        print "OnProgressResponse: saveAudiobookProgress failed"
        m.progressConsecutiveFailures = m.progressConsecutiveFailures + 1
        return
    end if
end sub

sub BuildChapterListContent()
    if m.chapterList = invalid then return

    content = CreateObject("roSGNode", "ContentNode")

    for each ch in m.chapters
        if ch = invalid then goto nextChapterBuild
        child = CreateObject("roSGNode", "ContentNode")
        child.Title = ch.title
        content.appendChild(child)
        nextChapterBuild:
    end for

    m.chapterList.content = content
end sub

sub UpdateChapterLabel()
    if m.chapterLabel = invalid then return

    if m.currentChapterIndex >= 0 and m.currentChapterIndex < m.chapters.Count() then
        ch = m.chapters[m.currentChapterIndex]
        if ch <> invalid and ch.title <> invalid then
            m.chapterLabel.text = ch.title
        end if
    end if
end sub


