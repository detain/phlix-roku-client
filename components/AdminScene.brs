'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/AdminScene.brs

' copyright 2026 Joe Huss
'

'
' Admin menu: a static LabelList of admin sections (F11a has ONE row, Dashboard;
' future slices F11b/F11c/F9 append more rows). Mirrors CollectionsScene's
' LabelList + status-label idiom, minus the ApiTask - this scene just navigates
' (each row opens a child scene). HomeScene self-creates + focuses this scene
' (only when the user is_admin), so it has NO <interface>.
'
' The menu backing array m.menuItems maps each row index to a target scene name;
' OnMenuSelected index-guards against it and CreateObject's the named scene.

sub Init()
    m.top.SetFocus(true)

    ' Static menu backing array. Each row: { label, scene }. Extensible - future
    ' slices push more rows (Libraries, Users, Live TV) here.
    m.menuItems = [
        { label: "Dashboard", scene: "DashboardScene" }
        { label: "Libraries", scene: "LibraryAdminScene" }
        { label: "Users", scene: "UserAdminScene" }
        { label: "Live TV", scene: "LiveTvScene" }
        { label: "TV Guide", scene: "GuideScene" }
        { label: "Recordings", scene: "RecordingsScene" }
        { label: "Series Rules", scene: "SeriesRulesScene" }
    ]

    ' Text list (admin sections have no artwork).
    m.adminMenu = m.top.FindNode("adminMenu")
    if m.adminMenu <> invalid then
        m.adminMenu.ObserveField("itemSelected", "OnMenuSelected")
        m.adminMenu.ObserveField("itemFocused", "OnMenuFocused")
        m.adminMenu.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Build the LabelList content from the static backing array.
    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.menuItems
        if row <> invalid then
            title = ""
            if row.DoesExist("label") and row.label <> invalid then title = row.label
            content.AddChild({ title: title })
        end if
    end for
    if m.adminMenu <> invalid then m.adminMenu.content = content
end sub

sub OnMenuSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.menuItems.Count() then return

    row = m.menuItems[index]
    if row = invalid then return

    sceneName = ""
    if row.DoesExist("scene") and row.scene <> invalid then sceneName = row.scene
    if sceneName = "" then return

    scene = CreateObject("roSGNode", sceneName)
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

sub OnMenuFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.menuItems.Count() then return

    row = m.menuItems[index]
    if row = invalid then return

    if row.DoesExist("label") and row.label <> invalid then SetStatus(row.label)
end sub

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.adminMenu <> invalid then
        m.adminMenu.UnObserveField("itemSelected")
        m.adminMenu.UnObserveField("itemFocused")
    end if
end sub

' Bubble requestClose from a child scene up to PhlixApp (which holds PopScreen).
sub OnChildRequestClose()
    m.top.requestClose = true
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