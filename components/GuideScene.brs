'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/GuideScene.brs

' copyright 2026 Joe Huss
'

'
' TV Guide list: a one-shot LabelList of upcoming live-TV programs. Uses
' ListTask (extends Task) which fetches AND builds the ContentNode on its own
' thread — the scene receives a ready-to-assign ContentNode plus the raw
' programs array for navigation. This keeps the render thread free.
'
' Data flow:
'   Init() -> ListTask.op = "getGuide" : ListTask.control = "run"
'   ListTask (task thread) -> api.getGuide() + ContentNode build
'   ListTask.content -> OnGuideContent() -> programList.content = content
'   ListTask.items -> OnGuidePrograms() -> m.items = programs
'   ListTask.ok -> OnGuideOk() -> SetStatus("")
'
' This is a READ-ONLY admin view: selecting a row is inert (guide programs are
' not playable, no second op). AdminScene self-creates + focuses this scene, so
' it has NO <interface>.

 sub Init()
    m.top.SetFocus(true)

    ' Text list of programs.
    m.programList = m.top.FindNode("programList")
    if m.programList <> invalid then
        m.programList.ObserveField("itemSelected", "OnRowSelected")
        m.programList.ObserveField("itemFocused", "OnRowFocused")
        m.programList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ListTask node (off the render thread).
    ' ListTask fetches AND builds the ContentNode on its own thread, then
    ' ships the ready-to-assign content + raw programs array to this scene.
    m.guideTask = CreateObject("roSGNode", "ListTask")
    m.guideTask.ObserveField("content", "OnGuideContent")
    m.guideTask.ObserveField("items", "OnGuidePrograms")
    m.guideTask.ObserveField("ok", "OnGuideOk")

    m.items = []

    SetStatus("Loading…")

    ' One-shot load on Init (no query params = upcoming across all channels).
    m.guideTask.op = "getGuide"
    m.guideTask.control = "run"
end sub

' ContentNode is ready — assign directly to the LabelList.
sub OnGuideContent(event as Object)
    content = event.getData()
    if m.programList <> invalid then
        m.programList.content = content
    end if
end sub

' Raw programs array arrived — store for navigation (itemFocused uses it).
sub OnGuidePrograms(event as Object)
    m.items = event.getData()
end sub

' Success flag arrived — update status text.
sub OnGuideOk(event as Object)
    ok = event.getData()
    if ok then
        if m.items.Count() = 0 then
            SetStatus("No programs")
        else
            SetStatus("")
        end if
    else
        ' Guide load failed -> Live TV not configured or unavailable
        ' (routes 404, or a non-admin 403/JSON {error} body).
        SetStatus("Live TV unavailable")
    end if
end sub

' Caption for a program row: "<M/D H:MM>  <title>". start_time is a UNIX-seconds
' INTEGER -> guard DoesExist + invalid only (NEVER an Integer<>String compare),
' then hand to FormatUnixTime (which guards <=0). title guards DoesExist + invalid
' + "". If no time, just the title; if no title, just the time.
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

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.items.Count() then return

    program = m.items[index]
    if program = invalid then return

    SetStatus(ProgramRowCaption(program))
end sub

' READ-ONLY view: selecting a program is inert (guide programs are not playable;
' no second op fires).
sub OnRowSelected(event as Object)
    return
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.programList <> invalid then
        m.programList.UnObserveField("itemSelected")
        m.programList.UnObserveField("itemFocused")
    end if
    if m.guideTask <> invalid then
        m.guideTask.UnObserveField("content")
        m.guideTask.UnObserveField("items")
        m.guideTask.UnObserveField("ok")
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