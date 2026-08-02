' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/RecordingsScene.brs

' copyright 2026 Joe Huss
'

'
' Recordings list: a one-shot LabelList of the server's live-TV recordings.
' Mirrors GuideScene's LabelList + ApiTask + OnApiResponse idiom - the load fires
' once on Init via the `getRecordings` op (no status filter = all recordings).
' This is a READ-ONLY admin view: selecting a row is inert (recordings have no
' scouted playback route, no second op). AdminScene self-creates + focuses this
' scene, so it has NO <interface>.
'
' NOTE: getRecordings() returns the WHOLE envelope {success,recordings:[...]}
' (admin getters do not unwrap), so OnApiResponse reads resp.data.recordings and
' checks resp.data.DoesExist("recordings") AND type(resp.data.recordings) =
' "roArray"; the key's absence = Live TV unavailable / not configured (routes 404,
' or a non-admin 403/JSON {error} body).

sub Init()
    m.top.SetFocus(true)

    ' Text list of recordings.
    m.recordingList = m.top.FindNode("recordingList")
    if m.recordingList <> invalid then
        m.recordingList.ObserveField("itemSelected", "OnRowSelected")
        m.recordingList.ObserveField("itemFocused", "OnRowFocused")
        m.recordingList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.recordings = []

    SetStatus("Loading…")

    ' One-shot load on Init (no status filter = all recordings).
    m.apiTask.request = { op: "getRecordings" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getRecordings" then
        ' getRecordings() returns the WHOLE envelope {recordings:[...]}.
        m.recordings = []
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("recordings") and type(resp.data.recordings) = "roArray" then
            m.recordings = resp.data.recordings

            content = CreateObject("roSGNode", "ContentNode")
            for each recording in m.recordings
                if recording <> invalid then
                    content.AddChild({ title: RecordingRowCaption(recording) })
                end if
            end for

            if m.recordingList <> invalid then m.recordingList.content = content

            if m.recordings.Count() = 0 then
                SetStatus("No recordings")
            else
                SetStatus("")
            end if
        else
            ' resp.data invalid / no recordings key -> Live TV not configured or
            ' unavailable (routes 404, or a non-admin 403/JSON {error} body).
            SetStatus("Live TV unavailable")
        end if
    end if
end sub

' Caption for a recording row: "<title>  (<status>) — <M/D H:MM>". title and
' status guard DoesExist + invalid + ""; start_time is a UNIX-seconds INTEGER ->
' guard DoesExist + invalid only (NEVER an Integer<>String compare), then hand to
' FormatUnixTime (which guards <=0). If no title, fall back to status, then
' "(recording)". The time suffix is appended only when present.
function RecordingRowCaption(recording as Object) as String
    if recording = invalid then return ""

    title = ""
    if recording.DoesExist("title") and recording.title <> invalid and recording.title <> "" then
        title = recording.title
    end if

    status = ""
    if recording.DoesExist("status") and recording.status <> invalid and recording.status <> "" then
        status = recording.status
    end if

    caption = title
    if caption = "" then
        if status <> "" then
            caption = status
        else
            caption = "(recording)"
        end if
    else if status <> "" then
        caption = caption + "  (" + status + ")"
    end if

    timeText = ""
    if recording.DoesExist("start_time") and recording.start_time <> invalid then
        timeText = FormatUnixTime(recording.start_time)
    end if
    if timeText <> "" then caption = caption + " — " + timeText

    return caption
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.recordings.Count() then return

    recording = m.recordings[index]
    if recording = invalid then return

    SetStatus(RecordingRowCaption(recording))
end sub

' READ-ONLY view: selecting a recording is inert (no scouted playback route; no
' second op fires).
sub OnRowSelected(event as Object)
    return
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.recordingList <> invalid then
        m.recordingList.UnObserveField("itemSelected")
        m.recordingList.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
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