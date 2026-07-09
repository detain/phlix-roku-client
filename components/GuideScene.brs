' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/GuideScene.brs

' copyright 2026 Joe Huss
'

'
' TV Guide list: a one-shot LabelList of upcoming live-TV programs. Mirrors
' LiveTvScene's LabelList + ApiTask + OnApiResponse idiom - the load fires once on
' Init via the `getGuide` op (no query params = upcoming across ALL channels,
' capped server-side). This is a READ-ONLY admin view: selecting a row is inert
' (guide programs are not playable, no second op). AdminScene self-creates +
' focuses this scene, so it has NO <interface>.
'
' NOTE: getGuide() returns the WHOLE envelope {success,programs:[...]} (admin
' getters do not unwrap), so OnApiResponse reads resp.data.programs and checks
' resp.data.DoesExist("programs") AND type(resp.data.programs) = "roArray"; the
' key's absence = Live TV unavailable / not configured (routes 404, or a non-admin
' 403/JSON {error} body).

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

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.programs = []

    SetStatus("Loading…")

    ' One-shot load on Init (no query params = upcoming across all channels).
    m.apiTask.request = { op: "getGuide" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getGuide" then
        ' getGuide() returns the WHOLE envelope {programs:[...]}.
        m.programs = []
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("programs") and type(resp.data.programs) = "roArray" then
            m.programs = resp.data.programs

            content = CreateObject("roSGNode", "ContentNode")
            for each program in m.programs
                if program <> invalid then
                    content.AddChild({ title: ProgramRowCaption(program) })
                end if
            end for

            if m.programList <> invalid then m.programList.content = content

            if m.programs.Count() = 0 then
                SetStatus("No programs")
            else
                SetStatus("")
            end if
        else
            ' resp.data invalid / no programs key -> Live TV not configured or
            ' unavailable (routes 404, or a non-admin 403/JSON {error} body).
            SetStatus("Live TV unavailable")
        end if
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
    if index < 0 or index >= m.programs.Count() then return

    program = m.programs[index]
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
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function