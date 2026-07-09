' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/SeriesRulesScene.brs

' copyright 2026 Joe Huss
'

'
' Series Rules list: a one-shot LabelList of the server's live-TV series recording
' rules. Mirrors GuideScene's LabelList + ApiTask + OnApiResponse idiom - the load
' fires once on Init via the `getSeriesRules` op (active rules). This is a
' READ-ONLY admin view: selecting a row is inert (no CRUD scouted, no second op).
' AdminScene self-creates + focuses this scene, so it has NO <interface>.
'
' NOTE: getSeriesRules() returns the WHOLE envelope {success,rules:[...]} (admin
' getters do not unwrap), so OnApiResponse reads resp.data.rules and checks
' resp.data.DoesExist("rules") AND type(resp.data.rules) = "roArray"; the key's
' absence = Live TV unavailable / not configured (routes 404, or a non-admin
' 403/JSON {error} body).
'
' LANDMINE: a rule has NO top-level `id` field (its identifier is `rule_id`); this
' scene never reads `rule.id`. priority is an INTEGER -> guard DoesExist + invalid
' only (NEVER an Integer<>String compare), then stringify via str(Int(...)).trim().

sub Init()
    m.top.SetFocus(true)

    ' Text list of series rules.
    m.ruleList = m.top.FindNode("ruleList")
    if m.ruleList <> invalid then
        m.ruleList.ObserveField("itemSelected", "OnRowSelected")
        m.ruleList.ObserveField("itemFocused", "OnRowFocused")
        m.ruleList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.rules = []

    SetStatus("Loading…")

    ' One-shot load on Init (active series rules).
    m.apiTask.request = { op: "getSeriesRules" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getSeriesRules" then
        ' getSeriesRules() returns the WHOLE envelope {rules:[...]}.
        m.rules = []
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("rules") and type(resp.data.rules) = "roArray" then
            m.rules = resp.data.rules

            content = CreateObject("roSGNode", "ContentNode")
            for each rule in m.rules
                if rule <> invalid then
                    content.AddChild({ title: RuleRowCaption(rule) })
                end if
            end for

            if m.ruleList <> invalid then m.ruleList.content = content

            if m.rules.Count() = 0 then
                SetStatus("No series rules")
            else
                SetStatus("")
            end if
        else
            ' resp.data invalid / no rules key -> Live TV not configured or
            ' unavailable (routes 404, or a non-admin 403/JSON {error} body).
            SetStatus("Live TV unavailable")
        end if
    end if
end sub

' Caption for a series-rule row: "<title>  (priority <n>)". title guards DoesExist
' + invalid + "" with fallback to series_id then "(rule)". priority is an INTEGER
' -> guard DoesExist + invalid only (NEVER an Integer<>String compare), then
' stringify via str(Int(...)).trim(); the suffix is appended only when present.
' A rule has NO `id` field - never read it.
function RuleRowCaption(rule as Object) as String
    if rule = invalid then return ""

    title = ""
    if rule.DoesExist("title") and rule.title <> invalid and rule.title <> "" then
        title = rule.title
    else if rule.DoesExist("series_id") and rule.series_id <> invalid and rule.series_id <> "" then
        title = rule.series_id
    else
        title = "(rule)"
    end if

    if rule.DoesExist("priority") and rule.priority <> invalid then
        return title + "  (priority " + str(Int(rule.priority)).trim() + ")"
    end if

    return title
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.rules.Count() then return

    rule = m.rules[index]
    if rule = invalid then return

    SetStatus(RuleRowCaption(rule))
end sub

' READ-ONLY view: selecting a rule is inert (no CRUD scouted; no second op fires).
sub OnRowSelected(event as Object)
    return
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.ruleList <> invalid then
        m.ruleList.UnObserveField("itemSelected")
        m.ruleList.UnObserveField("itemFocused")
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