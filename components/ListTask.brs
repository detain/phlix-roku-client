' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/ListTask.brs

' ===========================================
' ListTask — unified Live TV list loader (off the render thread).
'
' Replaces GuideTask, RecordingsListTask, and ChannelListTask with a single
' Task node driven by the `op` field:
'   op = "getGuide"      -> api.getGuide()      -> m.top.items = programs
'   op = "getRecordings" -> api.getRecordings() -> m.top.items = recordings
'   op = "getChannels"   -> api.getChannels()  -> m.top.items = channels
'
' Each op builds a ready-to-assign ContentNode off the render thread and sets
' m.top.ok = true on success.
'
' Thread rule: this function runs on the task thread; it may ONLY read its own
' m.top.op/fields and write m.top.content/items/ok. It must NOT touch
' UI/parent nodes. Only assocarray/string/number/node data crosses the thread
' boundary.
' ===========================================

sub Init()
    m.top.functionName = "LoadList"
end sub

sub LoadList()
    ' R2.8: Invalidate the Storage read cache so we re-read the freshest values
    ' from the registry.
    ResetCachedStorage(false)

    op = m.top.op

    api = GetApiClient()
    if api = invalid then
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
        return
    end if

    ' Dispatch based on op. Each branch: fetch -> guard -> extract -> build -> assign.
    if op = "getGuide" then
        LoadGuide(api)
    else if op = "getRecordings" then
        LoadRecordings(api)
    else if op = "getChannels" then
        LoadChannels(api)
    else
        ' Unknown op — fail loudly.
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
    end if
end sub

' -----------------------------------------------------------------------
' getGuide — fetches program guide and builds a ContentNode with captions.
' -----------------------------------------------------------------------
sub LoadGuide(api as Object)
    data = api.getGuide()
    if data = invalid or data.programs = invalid or type(data.programs) <> "roArray" then
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
        return
    end if

    programs = data.programs

    ' Build ContentNode off the render thread.
    content = CreateObject("roSGNode", "ContentNode")
    for each program in programs
        if program <> invalid then
            content.AddChild({ title: ProgramRowCaption(program) })
        end if
    end for

    m.top.content = content
    m.top.items = programs
    m.top.ok = true
end sub

' -----------------------------------------------------------------------
' getRecordings — fetches recordings and builds a ContentNode with captions.
' -----------------------------------------------------------------------
sub LoadRecordings(api as Object)
    data = api.getRecordings()
    if data = invalid or data.recordings = invalid or type(data.recordings) <> "roArray" then
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
        return
    end if

    recordings = data.recordings

    ' Build ContentNode off the render thread.
    content = CreateObject("roSGNode", "ContentNode")
    for each recording in recordings
        if recording <> invalid then
            content.AddChild({ title: RecordingRowCaption(recording) })
        end if
    end for

    m.top.content = content
    m.top.items = recordings
    m.top.ok = true
end sub

' -----------------------------------------------------------------------
' getChannels — fetches channel list and builds a ContentNode with captions.
' -----------------------------------------------------------------------
sub LoadChannels(api as Object)
    data = api.getChannels()
    if data = invalid or data.channels = invalid or type(data.channels) <> "roArray" then
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
        return
    end if

    channels = data.channels

    ' Build ContentNode off the render thread.
    content = CreateObject("roSGNode", "ContentNode")
    for each channel in channels
        if channel <> invalid then
            content.AddChild({ title: ChannelRowCaption(channel) })
        end if
    end for

    m.top.content = content
    m.top.items = channels
    m.top.ok = true
end sub

' -----------------------------------------------------------------------
' Caption helpers — must live here (task thread cannot call scene functions).
' -----------------------------------------------------------------------

' Caption for a program row: "<M/D H:MM>  <title>".
function ProgramRowCaption(program as Object) as String
    if program = invalid then return ""

    timeText = ""
    if program.DoesExist("start_time") and program.start_time <> invalid then
        timeText = FormatUnixTime(program.start_time)
    end if

    title = ""
    if program.DoesExist("title") and program.title <> invalid and program.title <> "" then
        title = program.title
    end if

    if timeText <> "" and title <> "" then return timeText + "  " + title
    if timeText <> "" then return timeText
    return title
end function

' Caption for a recording row: "<title>  (<status>) — <M/D H:MM>".
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

' Caption for a channel row: "<number>  <name>".
function ChannelRowCaption(channel as Object) as String
    if channel = invalid then return ""

    number = ""
    if channel.DoesExist("number") and channel.number <> invalid then
        number = str(Int(channel.number)).trim()
    end if

    name = ""
    if channel.DoesExist("name") and channel.name <> invalid and channel.name <> "" then
        name = channel.name
    end if

    if number <> "" and name <> "" then return number + "  " + name
    if number <> "" then return number
    return name
end function
