' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/SettingsScene.brs
' R7.1: Settings scene with 6 sections (Account, Server, Playback, Captions, Watch History, About)

sub Init()
    m.top.isSubcomponent = false

    ' Define settings items with section headers and menu entries
    m.settingsItems = [
        { title: "Account", type: "header" },
        { title: "User Email", type: "info", description: "View your account email and log out" },
        { title: "Server", type: "header" },
        { title: "Server URL", type: "info", description: "View and switch the server address" },
        { title: "Playback", type: "header" },
        { title: "Playback Preferences", type: "info", description: "Configure playback quality and autoplay" },
        { title: "Captions", type: "header" },
        { title: "Caption Mode", type: "info", description: "Toggle captions on or off" },
        { title: "Picture-in-Picture", type: "toggle", description: "Enable PiP during playback" },
        { title: "Watch History", type: "header" },
        { title: "Clear History", type: "action", description: "Remove all watch history data" },
        { title: "View History", type: "action", description: "Browse your watch history" },
        { title: "Notifications", type: "header" },
        { title: "Push Notifications", type: "toggle", description: "Receive push notifications" },
        { title: "Email Notifications", type: "toggle", description: "Receive email notifications" },
        { title: "About", type: "header" },
        { title: "Version", type: "info", description: "App version and device information" }
    ]

    m.settingsList = m.top.findNode("settingsList")
    m.detailLabel = m.top.findNode("detailLabel")
    m.statusLabel = m.top.findNode("statusLabel")

    m.settingsList.observeField("itemSelected", "OnItemSelected")
    m.settingsList.observeField("itemFocused", "OnItemFocused")

    BuildLabelList()
end sub

sub BuildLabelList()
    items = []

    for each item in m.settingsItems
        listItem = {
            Title: item.title
        }
        if item.type = "header"
            listItem.Title = item.title
        else
            listItem.Title = "  " + item.title
        end if
        items.push(listItem)
    end for

    m.settingsList.content = CreateObject("roSGNode", "ContentNode")
    for each item in items
        itemNode = CreateObject("roSGNode", "ContentNode")
        itemNode.title = item.Title
        m.settingsList.content.appendChild(itemNode)
    end for
end sub

sub OnItemSelected(event as Object)
    index = event.getData()
    item = m.settingsItems[index]

    if item = invalid then return

    if item.type = "header" then return

    if index = 1 then
        ShowAccount()
    else if index = 3 then
        ShowServer()
    else if index = 5 then
        ShowPlayback()
    else if index = 7 then
        ShowCaptions()
    else if index = 8 then
        TogglePip()
    else if index = 10 then
        ShowWatchHistory()
    else if index = 11 then
        ShowHistory()
    else if index = 12 then
        ' Notifications header - do nothing, sub-items handle toggles
    else if index = 13 then
        TogglePushNotifications()
    else if index = 14 then
        ToggleEmailNotifications()
    else if index = 15 then
        ShowAbout()
    else if index = 16 then
        ShowAbout()
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()
    item = m.settingsItems[index]

    if item = invalid then return

    if item.description <> invalid then
        m.detailLabel.text = item.description
    else
        m.detailLabel.text = ""
    end if
end sub

sub ShowAccount()
    userEmail = GetApiClient().user.email
    m.statusLabel.text = "Logged in as: " + userEmail

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Account"
    dialog.message = "Email: " + userEmail + Chr(10) + Chr(10) + "Do you want to log out?"
    dialog.buttons = ["Cancel", "Log Out"]
    dialog.observeField("buttonSelected", "OnLogoutConfirmed")
    m.top.dialog = dialog
end sub

sub OnLogoutConfirmed(index as Integer)
    if m.top.dialog = invalid then return
    m.top.dialog = invalid

    if index = 1 then
        ' R1.3: Call OnLogout to clear ALL 6 registry keys, not just ApiClient.logout()
        m.top.GetParent().GetParent().OnLogout()
    end if
end sub

sub ShowServer()
    serverUrl = GetServerUrl()
    m.statusLabel.text = "Server: " + serverUrl

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Server"
    dialog.message = "Current server: " + serverUrl + Chr(10) + Chr(10) + "Do you want to switch servers?"
    dialog.buttons = ["Cancel", "Switch"]
    dialog.observeField("buttonSelected", "OnSwitchServerConfirmed")
    m.top.dialog = dialog
end sub

sub OnSwitchServerConfirmed(index as Integer)
    if m.top.dialog = invalid then return
    m.top.dialog = invalid

    if index = 1 then
        m.statusLabel.text = "Server switching not implemented"
    end if
end sub

sub ShowPlayback()
    result = GetApiClient().getPlaybackPreferences()
    m.statusLabel.text = "Loading playback preferences..."

    if result <> invalid and result.data <> invalid and result.data.preferences <> invalid then
        prefs = result.data.preferences
        prefStr = "Quality: " + IIF(prefs.quality <> invalid, prefs.quality, "Auto") + Chr(10)
        prefStr = prefStr + "Autoplay: " + IIF(prefs.autoplay <> invalid, IIF(prefs.autoplay, "On", "Off"), "On")
        m.statusLabel.text = prefStr
    else
        m.statusLabel.text = "Unable to load playback preferences"
    end if
end sub

sub ShowCaptions()
    deviceInfo = CreateObject("roDeviceInfo")
    currentMode = deviceInfo.GetCaptionsMode()

    m.statusLabel.text = "Caption mode: " + currentMode

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Captions"
    dialog.message = "Current caption mode: " + currentMode + Chr(10) + Chr(10) + "Select a mode:"
    dialog.buttons = ["On", "Off", "Instant Replay", "When Mute"]
    dialog.observeField("buttonSelected", "OnCaptionsModeSelected")
    m.top.dialog = dialog
end sub

sub OnCaptionsModeSelected(index as Integer)
    if m.top.dialog = invalid then return
    m.top.dialog = invalid

    modes = ["On", "Off", "Instant replay", "When mute"]
    if index >= 0 and index < modes.count() then
        deviceInfo = CreateObject("roDeviceInfo")
        deviceInfo.SetCaptionsMode(modes[index])
        m.statusLabel.text = "Caption mode set to: " + modes[index]
    end if
end sub

sub ShowWatchHistory()
    m.statusLabel.text = "Watch history options"

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = "Watch History"
    dialog.message = "This will remove all your watch history data." + Chr(10) + Chr(10) + "Are you sure?"
    dialog.buttons = ["Cancel", "Clear"]
    dialog.observeField("buttonSelected", "OnClearHistoryConfirmed")
    m.top.dialog = dialog
end sub

sub OnClearHistoryConfirmed(index as Integer)
    if m.top.dialog = invalid then return
    m.top.dialog = invalid

    if index = 1 then
        m.statusLabel.text = "Clearing watch history..."
        GetApiClient().clearWatchHistory()
        m.statusLabel.text = "Watch history cleared"
    end if
end sub

sub ShowHistory()
    scene = CreateObject("roSGNode", "HistoryScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
end sub

sub TogglePip()
    ' R7.4b: Toggle Picture-in-Picture setting
    current = GetStorage().get("pip_enabled")
    ' Default to true if not set
    if current = invalid or current = "" or current = "true" then
        newValue = "false"
    else
        newValue = "true"
    end if
    GetStorage().set("pip_enabled", newValue)
    GetStorage().flush()
    enabledStr = IIF(newValue = "true", "enabled", "disabled")
    m.statusLabel.text = "Picture-in-Picture " + enabledStr
end sub

sub ShowNotifications()
    ' R7.4b: Notifications header - show current state
    prefsJson = GetStorage().get("notification_prefs")
    if prefsJson <> invalid and prefsJson <> "" then
        ' prefsJson is stored as a simple "push_email" string for now
        ' Parse it when API is ready
        m.statusLabel.text = "Notification preferences (local only)"
    else
        m.statusLabel.text = "Notification preferences not set"
    end if
end sub

sub TogglePushNotifications()
    ' R7.4b: Toggle push notification preference
    prefsJson = GetStorage().get("notification_prefs")
    pushEnabled = true
    emailEnabled = true

    if prefsJson <> invalid and prefsJson <> "" then
        parts = prefsJson.Split("_")
        if parts.Count() >= 2 then
            pushEnabled = (parts[0] = "1")
            emailEnabled = (parts[1] = "1")
        end if
    end if

    ' Toggle push
    pushEnabled = not pushEnabled
    newPrefs = IIF(pushEnabled, "1", "0") + "_" + IIF(emailEnabled, "1", "0")
    GetStorage().set("notification_prefs", newPrefs)
    GetStorage().flush()

    m.statusLabel.text = "Preferences saved locally — syncing with server when available"
end sub

sub ToggleEmailNotifications()
    ' R7.4b: Toggle email notification preference
    prefsJson = GetStorage().get("notification_prefs")
    pushEnabled = true
    emailEnabled = true

    if prefsJson <> invalid and prefsJson <> "" then
        parts = prefsJson.Split("_")
        if parts.Count() >= 2 then
            pushEnabled = (parts[0] = "1")
            emailEnabled = (parts[1] = "1")
        end if
    end if

    ' Toggle email
    emailEnabled = not emailEnabled
    newPrefs = IIF(pushEnabled, "1", "0") + "_" + IIF(emailEnabled, "1", "0")
    GetStorage().set("notification_prefs", newPrefs)
    GetStorage().flush()

    m.statusLabel.text = "Preferences saved locally — syncing with server when available"
end sub

sub ShowAbout()
    version = "1.0.1"
    deviceModel = GetDeviceModel()
    deviceId = GetStorage().get("device_id")
    videoMode = GetDeviceVideoMode()
    totalMemoryMB = DeviceInfoData().totalMemoryMB

    info = "Version: " + version + Chr(10)
    info = info + "Device Model: " + deviceModel + Chr(10)
    info = info + "Device ID: " + IIF(deviceId <> invalid, deviceId, "Unknown") + Chr(10)
    info = info + "Video Mode: " + videoMode + Chr(10)
    info = info + "Total Memory: " + str(totalMemoryMB).trim() + " MB"

    m.statusLabel.text = info
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if key = "back" then
        if m.top.dialog <> invalid then
            m.top.dialog = invalid
            return true
        else
            Teardown()
            m.top.requestClose = true
            return true
        end if
    end if

    return false
end function

sub Teardown()
    if m.settingsList <> invalid then
        m.settingsList.unobserveField("itemSelected")
        m.settingsList.unobserveField("itemFocused")
    end if
end sub

sub OnChildRequestClose()
    m.top.requestClose = true
end sub

' Helper function to handle conditional values
function IIF(condition as Boolean, trueValue as String, falseValue as String) as String
    if condition then
        return trueValue
    else
        return falseValue
    end if
end function