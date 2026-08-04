' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/RecordingsListTask.brs

' ===========================================
' RecordingsListTask — loads live-TV recordings off the render thread.
'
' The problem: RecordingsScene uses ApiTask for the HTTP call, but
' OnApiResponse processes the result (ContentNode build) on the render
' thread. With large lists this causes visible UI blocking.
'
' The fix: this dedicated Task fetches AND builds the ContentNode on its own
' thread, then ships a ready-to-assign ContentNode and raw recordings array to
' the scene. The scene uses the raw recordings for navigation and the
' ContentNode for display.
'
' Thread rule: this function runs on the task thread; it may ONLY read its own
' m.top.* fields and write m.top.content/recordings/ok. It must NOT touch
' UI/parent nodes. Only assocarray/string/number/node data crosses the thread
' boundary.
' ===========================================

sub Init()
    m.top.functionName = "LoadList"
end sub

sub LoadList()
    ' R1.6: Invalidate the Storage read cache so we re-read the freshest values
    ' from the registry.
    ResetCachedStorage(false)

    api = GetApiClient()
    if api = invalid then
        m.top.content = invalid
        m.top.recordings = []
        m.top.ok = false
        return
    end if

    ' Fetch recordings via getRecordings (no status filter = all recordings).
    data = api.getRecordings()
    if data = invalid or data.recordings = invalid or type(data.recordings) <> "roArray" then
        m.top.content = invalid
        m.top.recordings = []
        m.top.ok = false
        return
    end if

    recordings = data.recordings

    ' Build the ContentNode tree off the render thread.
    content = CreateObject("roSGNode", "ContentNode")

    for each recording in recordings
        if recording <> invalid then
            content.AddChild({ title: RecordingRowCaption(recording) })
        end if
    end for

    m.top.content = content
    m.top.recordings = recordings
    m.top.ok = true
end sub

' Caption for a recording row: "<title>  (<status>) — <M/D H:MM>".
' Mirrors RecordingsScene.RecordingRowCaption but lives here for thread-safety.
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