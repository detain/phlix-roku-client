' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/GuideTask.brs

' copyright 2026 Joe Huss

'
' ===========================================
' GuideTask — loads TV guide data off the render thread.
'
' The problem: GuideScene uses ApiTask for the HTTP call, but OnApiResponse
' processes the result (ContentNode build) on the render thread. With large
' lists this causes visible UI blocking.
'
' The fix: this dedicated Task fetches AND builds the ContentNode on its own
' thread, then ships a ready-to-assign ContentNode and raw programs array to
' the scene. The scene uses the raw programs for navigation and the
' ContentNode for display.
'
' Thread rule: this function runs on the task thread; it may ONLY read its own
' m.top.* fields and write m.top.content/programs/ok. It must NOT touch
' UI/parent nodes. Only assocarray/string/number/node data crosses the thread
' boundary.
' ===========================================

sub Init()
    m.top.functionName = "LoadGuide"
end sub

sub LoadGuide()
    ' R1.6: Invalidate the Storage read cache so we re-read the freshest values
    ' from the registry.
    ResetCachedStorage(false)

    api = GetApiClient()
    if api = invalid then
        m.top.content = invalid
        m.top.programs = []
        m.top.ok = false
        return
    end if

    ' Fetch guide data (no params = upcoming across all channels, capped server-side).
    data = api.getGuide()
    if data = invalid or data.programs = invalid or type(data.programs) <> "roArray" then
        m.top.content = invalid
        m.top.programs = []
        m.top.ok = false
        return
    end if

    programs = data.programs

    m.top.content = invalid
    m.top.programs = programs
    m.top.ok = true
end sub