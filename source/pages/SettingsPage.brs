' source/pages/SettingsPage.brs

' ===========================================
' Settings Page
' App configuration and user preferences
' ===========================================

sub Init()
    m.top.SetFocus(true)

    ' Load settings
    m.serverUrl = Storage.get("server_url")
    if m.serverUrl = "" or m.serverUrl = invalid then
        m.serverUrl = "http://localhost:8096"
    end if

    m.username = Storage.get("username")
end sub

sub Show()
    ' Display settings UI
end sub

sub SaveSettings()
    ' Save current settings to storage
    Storage.set("server_url", m.serverUrl)
    Storage.set("username", m.username)
end sub

sub ClearCache()
    ' Clear cached data
    Storage.clear()
end sub

sub Logout()
    ' Perform logout
    authManager.logout()
    m.top.OnLogout()
end sub