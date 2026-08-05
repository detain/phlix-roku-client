' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/SettingsScene.brs

' Settings scene: 6 section rows (Account, Server, Playback, Captions,
' Watch History, About). Each row opens a sub-section or info panel.
' R7.1

sub Init()
    m.top.SetFocus(true)

    m.settingsList = m.top.FindNode("settingsList")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Static settings menu backing array. Each row: { label, description }
    m.settingsItems = [
        { label: "Account", description: "Manage your account settings" }
        { label: "Server", description: "Server connection and preferences" }
        { label: "Playback", description: "Playback behavior and quality" }
        { label: "Captions", description: "Subtitle and caption options" }
        { label: "Watch History", description: "View and manage watch history" }
        { label: "About", description: "App version and server info" }
    ]

    if m.settingsList <> invalid then
        m.settingsList.ObserveField("itemSelected", "OnItemSelected")
        m.settingsList.ObserveField("itemFocused", "OnItemFocused")
        m.settingsList.SetFocus(true)
    end if

    ' Build the LabelList content from the backing array.
    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.settingsItems
        if row <> invalid then
            title = ""
            if row.DoesExist("label") and row.label <> invalid then title = row.label
            content.AddChild({ title: title })
        end if
    end for
    if m.settingsList <> invalid then m.settingsList.content = content
end sub

sub OnItemSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.settingsItems.Count() then return

    row = m.settingsItems[index]
    if row = invalid then return

    ' Each section row selection - handled per section type.
    ' Currently displays the selection; future slices wire actual sub-scenes.
    label = ""
    if row.DoesExist("label") and row.label <> invalid then label = row.label
    if m.statusLabel <> invalid then
        m.statusLabel.text = "Selected: " + label
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.settingsItems.Count() then return

    row = m.settingsItems[index]
    if row = invalid then return

    desc = ""
    if row.DoesExist("description") and row.description <> invalid then desc = row.description
    if m.statusLabel <> invalid then
        m.statusLabel.text = desc
    end if
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.settingsList <> invalid then
        m.settingsList.UnObserveField("itemSelected")
        m.settingsList.UnObserveField("itemFocused")
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