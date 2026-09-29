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
    ApplyXmlChrome()
    m.top.SetFocus(true)

    m.adminMenu = m.top.FindNode("adminMenu")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' R4 (admin gate): every row this scene renders targets an ADMIN-ONLY
    ' server surface - Dashboard/Storage/Activity are /admin/dashboard/*,
    ' Users is /admin/users*, Profiles is /admin/profiles*, Live TV/Guide/
    ' Recordings/Series Rules are /admin/livetv/*, and the library actions
    ' (scan/rescan/match-metadata) are requireAdmin-gated bare /libraries/*
    ' routes (phlix-server registers /admin/* behind AdminMiddleware:
    ' 401 unauthenticated, 403 for a non-admin profile). Gate the WHOLE menu
    ' on GetIsAdmin() instead of only some rows, and say so honestly when a
    ' non-admin somehow lands here (back-pressure against the previous
    ' fail-open where the base rows rendered for everyone and 403'd).
    if not GetIsAdmin() then
        if m.adminMenu <> invalid then m.adminMenu.content = CreateObject("roSGNode", "ContentNode")
        SetStatus(Translate("admin_access_required"))
        return
    end if

    ' R7.9: Admin menu (all rows are admin-only; the Live TV family kept its
    ' own guard historically - now the whole scene shares the one gate above).
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
    if m.adminMenu <> invalid then
        m.adminMenu.ObserveField("itemSelected", "OnMenuSelected")
        m.adminMenu.ObserveField("itemFocused", "OnMenuFocused")
        m.adminMenu.SetFocus(true)
    end if

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

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("headerLabel")
    if n <> invalid then n.text = Translate("common_admin")
    n = m.top.findNode("statusLabel")
    if n <> invalid then n.text = Translate("admin_select_section")
end sub
