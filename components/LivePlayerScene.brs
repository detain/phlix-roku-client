' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/LivePlayerScene.brs

' copyright 2026 Joe Huss
'

'
' Dedicated lightweight LIVE video player. A live channel has NO media item, NO
' transcode, NO progress reporting, NO skip markers and NO session - so it does
' NOT reuse the VOD PlayerScene (whose on-error path fires startTranscode with an
' empty itemId). This scene is just a Video node + a title + a status label; its
' on-error path only shows a message, never a transcode.
'
' The Video node configuration (EnableCookies + SetCertificatesFile + the state
' observer) mirrors PlayerScene. LiveTvScene creates + appends this scene and
' calls LoadStream(url,title) across the component boundary, so LoadStream is
' declared in the XML <interface>.
'
' DEVICE-UNVERIFIABLE: the stream url is the resolved (unauthenticated) tuner/HLS
' target of a Bearer-gated 302 (see ApiClient.resolveLocation). Whether the Roku
' Video node can play a raw MPEG-TS tuner stream (streamFormat "mpegts") vs an
' "hls" .m3u8 is firmware/model + tuner dependent; the streamFormat heuristic
' below is best-effort and can only be confirmed on a device. See the worklog.

sub Init()
    m.top.SetFocus(true)

    ' Create video player (mirror PlayerScene's Video node configuration).
    m.videoPlayer = m.top.FindNode("videoPlayer")
    m.videoPlayer.EnableCookies()
    m.videoPlayer.SetCertificatesFile("common:/certs/ca-bundle.crt")

    ' Observe playback state for the error / playing status messages.
    m.videoPlayer.ObserveField("state", "OnPlayerStateChange")

    m.titleLabel = m.top.FindNode("titleLabel")
    m.statusLabel = m.top.FindNode("statusLabel")
end sub

' Interface fn: called by LiveTvScene with the resolved stream url + display
' title. Coerce an invalid title to "". A missing url shows a status and returns.
' streamFormat is a best-effort heuristic: an .m3u8 target is HLS, otherwise a
' raw tuner stream is MPEG-TS.
sub LoadStream(streamUrl as String, title as String)
    name = title
    if name = invalid then name = ""
    if m.titleLabel <> invalid then m.titleLabel.text = name

    if streamUrl = invalid or streamUrl = "" then
        SetStatus("No stream URL available")
        return
    end if

    fmt = "mpegts"
    if Instr(1, streamUrl, ".m3u8") > 0 then fmt = "hls"

    stream = CreateObject("roSGNode", "ContentNode")
    stream.url = streamUrl
    stream.streamformat = fmt

    if m.videoPlayer <> invalid then
        m.videoPlayer.content = stream
        m.videoPlayer.control = "play"
        m.videoPlayer.SetFocus(true)
    end if
end sub

' On-error path is status-only: a live stream has no transcode fallback.
sub OnPlayerStateChange(event as Object)
    state = event.getData()
    if state = "error" then
        SetStatus("Playback failed")
    else if state = "playing" then
        SetStatus("")
    end if
end sub

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Stop playback and pair the state ObserveField with an UnObserveField so the
' scene does not leak.
sub Teardown()
    if m.videoPlayer <> invalid then
        m.videoPlayer.control = "stop"
        m.videoPlayer.UnObserveField("state")
    end if
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end function