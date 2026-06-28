' components/DashboardScene.brs
'
' Read-only admin dashboard: three serialized admin reads (now-playing -> storage
' -> activity) through ONE ApiTask, rendered into a single combined LabelList of
' section-header rows + data rows. Mirrors CollectionsScene/MusicScene's ApiTask +
' OnApiResponse + SetStatus + Teardown idiom. AdminScene self-creates + focuses
' this scene (only when the user is_admin), so it has NO <interface>.
'
' All /admin/* reads require is_admin+active (AdminMiddleware -> 401/403). A 403
' returns an {error,code} body (resp.ok=true but no .data key); a cleared-token 401
' yields invalid. Either way ExtractData yields [] and the chain still completes to
' an empty render (no crash). Selection is a no-op (read-only).
'
' Numeric JSON fields (progress_percent, item_count) are coerced via str(Int(...))
' - NEVER compared with "" (Integer<>String raises a runtime type-mismatch).
' String fields (formatted_total, occurred_at, username, ...) are used directly,
' each guarded with DoesExist + invalid.

sub Init()
    m.top.SetFocus(true)

    ' Single combined read-only list.
    m.dashboardList = m.top.FindNode("dashboardList")
    if m.dashboardList <> invalid then
        ' Read-only: only itemFocused is observed (no itemSelected handler - rows
        ' are not individually actionable).
        m.dashboardList.ObserveField("itemFocused", "OnRowFocused")
        m.dashboardList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the render
    ' thread). The three reads are serialized strictly: each fires the next from
    ' OnApiResponse, so two control="run" are never outstanding at once.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.nowPlaying = []
    m.storage = []
    m.activity = []

    SetStatus("Loading…")

    ' Fire the FIRST read; storage + activity chain from OnApiResponse.
    m.apiTask.request = { op: "getAdminNowPlaying" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getAdminNowPlaying" then
        m.nowPlaying = ExtractData(resp)
        m.apiTask.request = { op: "getAdminStorage" }
        m.apiTask.control = "run"
    else if resp.op = "getAdminStorage" then
        m.storage = ExtractData(resp)
        m.apiTask.request = { op: "getAdminActivity", limit: 20 }
        m.apiTask.control = "run"
    else if resp.op = "getAdminActivity" then
        m.activity = ExtractData(resp)
        RenderDashboard()
    end if
end sub

' Pull the `.data` array out of an admin envelope ({success,data,count}). Returns
' resp.data.data when present and an roArray, else [] (covers !ok / 401 / 403 /
' malformed). Never raises.
function ExtractData(resp as Object) as Object
    if resp = invalid then return []
    if not resp.ok then return []
    if resp.data = invalid then return []
    if resp.data.data = invalid then return []
    if type(resp.data.data) <> "roArray" then return []
    return resp.data.data
end function

' Build ONE ContentNode: each section header is always emitted, followed by its
' data rows or a single "(none)" row when the section is empty.
sub RenderDashboard()
    content = CreateObject("roSGNode", "ContentNode")

    ' --- Now Playing ---
    content.AddChild({ title: "— Now Playing —" })
    if m.nowPlaying = invalid or m.nowPlaying.Count() = 0 then
        content.AddChild({ title: "(none)" })
    else
        for each row in m.nowPlaying
            if row <> invalid then
                content.AddChild({ title: NowPlayingCaption(row) })
            end if
        end for
    end if

    ' --- Storage ---
    content.AddChild({ title: "— Storage —" })
    if m.storage = invalid or m.storage.Count() = 0 then
        content.AddChild({ title: "(none)" })
    else
        for each row in m.storage
            if row <> invalid then
                content.AddChild({ title: StorageCaption(row) })
            end if
        end for
    end if

    ' --- Recent Activity ---
    content.AddChild({ title: "— Recent Activity —" })
    if m.activity = invalid or m.activity.Count() = 0 then
        content.AddChild({ title: "(none)" })
    else
        for each row in m.activity
            if row <> invalid then
                content.AddChild({ title: ActivityCaption(row) })
            end if
        end for
    end if

    if m.dashboardList <> invalid then m.dashboardList.content = content

    SetStatus("Admin data")
end sub

' "<username> — <media_title> (<progress_percent>%)". progress_percent is numeric
' -> str(Int(...)); username/media_title are Strings (guarded).
function NowPlayingCaption(row as Object) as String
    if row = invalid then return ""

    username = ""
    if row.DoesExist("username") and row.username <> invalid then username = row.username
    title = ""
    if row.DoesExist("media_title") and row.media_title <> invalid then title = row.media_title

    caption = username
    if title <> "" then
        if caption <> "" then
            caption = caption + " — " + title
        else
            caption = title
        end if
    end if

    if row.DoesExist("progress_percent") and row.progress_percent <> invalid then
        caption = caption + " (" + str(Int(row.progress_percent)).trim() + "%)"
    end if

    return caption
end function

' "<media_type>: <item_count> items, <formatted_total>". item_count is numeric ->
' str(Int(...)); media_type/formatted_total are Strings (guarded). formatted_total
' is a server-preformatted string -> used directly.
function StorageCaption(row as Object) as String
    if row = invalid then return ""

    mediaType = ""
    if row.DoesExist("media_type") and row.media_type <> invalid then mediaType = row.media_type

    countStr = "0"
    if row.DoesExist("item_count") and row.item_count <> invalid then countStr = str(Int(row.item_count)).trim()

    caption = mediaType + ": " + countStr + " items"

    if row.DoesExist("formatted_total") and row.formatted_total <> invalid and row.formatted_total <> "" then
        caption = caption + ", " + row.formatted_total
    end if

    return caption
end function

' "<occurred_at>  <username>  <event_type>". All three are Strings (guarded); the
' `details` sub-object is intentionally NOT read in F11a (shape varies by category).
function ActivityCaption(row as Object) as String
    if row = invalid then return ""

    parts = []
    if row.DoesExist("occurred_at") and row.occurred_at <> invalid and row.occurred_at <> "" then
        parts.Push(row.occurred_at)
    end if
    if row.DoesExist("username") and row.username <> invalid and row.username <> "" then
        parts.Push(row.username)
    end if
    if row.DoesExist("event_type") and row.event_type <> invalid and row.event_type <> "" then
        parts.Push(row.event_type)
    end if

    return JoinStrings(parts, "  ")
end function

sub OnRowFocused(event as Object)
    ' Read-only: rows are not individually meaningful. Index-guarded no-op (leave
    ' the status label as-is).
    index = event.getData()
    if index = invalid then return
end sub

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.dashboardList <> invalid then m.dashboardList.UnObserveField("itemFocused")
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
