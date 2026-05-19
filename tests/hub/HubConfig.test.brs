' tests/hub/HubConfig.test.brs

' ===========================================
' HubConfig Unit Tests
' ===========================================

' Test that HubConfig initializes correctly
sub TestHubConfigInit()
    ' Clear any existing config
    Storage.delete("hub_url")
    Storage.delete("connection_mode")
    Storage.delete("active_server")

    hubConfig = HubConfig()
    assertTrue(hubConfig <> invalid)
    assertEqual(hubConfig.connectionMode, "direct")
    print "TestHubConfigInit passed"
end sub

' Test getEffectiveUrl returns direct URL when no active server
sub TestGetEffectiveUrlDirectMode()
    ' Clear any existing config
    Storage.delete("hub_url")
    Storage.delete("connection_mode")
    Storage.delete("active_server")

    hubConfig = HubConfig()
    hubConfig.serverUrl = "http://server:8096"

    effectiveUrl = hubConfig.getEffectiveUrl("/api/v1/items")
    assertEqual(effectiveUrl, "http://server:8096/api/v1/items")
    print "TestGetEffectiveUrlDirectMode passed"
end sub

' Test getEffectiveUrl returns direct URL in direct mode with active server
sub TestGetEffectiveUrlWithServerDirectMode()
    ' Clear any existing config
    Storage.delete("hub_url")
    Storage.delete("connection_mode")
    Storage.delete("active_server")

    hubConfig = HubConfig()
    hubConfig.serverUrl = "http://server:8096"
    hubConfig.connectionMode = "direct"
    hubConfig.setActiveServer({
        serverId: "srv-123"
        name: "Test Server"
        hostname: "http://direct-server:8096"
    })

    effectiveUrl = hubConfig.getEffectiveUrl("/api/v1/items")
    assertEqual(effectiveUrl, "http://direct-server:8096/api/v1/items")
    print "TestGetEffectiveUrlWithServerDirectMode passed"
end sub

' Test getEffectiveUrl routes through relay in relay mode
sub TestGetEffectiveUrlRelayMode()
    ' Clear any existing config
    Storage.delete("hub_url")
    Storage.delete("connection_mode")
    Storage.delete("active_server")

    hubConfig = HubConfig()
    hubConfig.serverUrl = "http://server:8096"
    hubConfig.hubUrl = "http://hub:8080"
    hubConfig.connectionMode = "relay"
    hubConfig.setActiveServer({
        serverId: "srv-456"
        name: "Relay Server"
        hostname: "http://direct-server:8096"
        relayHostname: "relay.hub.io"
    })

    effectiveUrl = hubConfig.getEffectiveUrl("/api/v1/items")
    expectedUrl = "http://hub:8080/api/v1/relay/srv-456/api/v1/items"
    assertEqual(effectiveUrl, expectedUrl)
    print "TestGetEffectiveUrlRelayMode passed"
end sub

' Test getEffectiveUrl uses direct mode when server has no relay hostname
sub TestGetEffectiveUrlRelayModeNoRelayHostname()
    ' Clear any existing config
    Storage.delete("hub_url")
    Storage.delete("connection_mode")
    Storage.delete("active_server")

    hubConfig = HubConfig()
    hubConfig.serverUrl = "http://server:8096"
    hubConfig.hubUrl = "http://hub:8080"
    hubConfig.connectionMode = "relay"
    hubConfig.setActiveServer({
        serverId: "srv-789"
        name: "Direct Only Server"
        hostname: "http://direct-server:8096"
        ' No relayHostname key
    })

    effectiveUrl = hubConfig.getEffectiveUrl("/api/v1/items")
    assertEqual(effectiveUrl, "http://direct-server:8096/api/v1/items")
    print "TestGetEffectiveUrlRelayModeNoRelayHostname passed"
end sub

' Test setConnectionMode saves correctly
sub TestSetConnectionMode()
    ' Clear any existing config
    Storage.delete("connection_mode")

    hubConfig = HubConfig()
    hubConfig.setConnectionMode("relay")

    mode = Storage.get("connection_mode")
    assertEqual(mode, "relay")
    print "TestSetConnectionMode passed"
end sub

' Test isRelayMode returns correct value
sub TestIsRelayMode()
    ' Clear any existing config
    Storage.delete("connection_mode")

    hubConfig = HubConfig()
    assertFalse(hubConfig.isRelayMode())

    hubConfig.setConnectionMode("relay")
    assertTrue(hubConfig.isRelayMode())

    hubConfig.setConnectionMode("direct")
    assertFalse(hubConfig.isRelayMode())
    print "TestIsRelayMode passed"
end sub

' Test getAuthHeader returns empty when no session
sub TestGetAuthHeaderNoSession()
    ' Clear any existing config
    Storage.delete("hub_session")

    hubConfig = HubConfig()
    header = hubConfig.getAuthHeader()
    assertEqual(header, "")
    print "TestGetAuthHeaderNoSession passed"
end sub

' Test getAuthHeader returns Bearer token when session exists
sub TestGetAuthHeaderWithSession()
    Storage.set("hub_session", FormatJSON({
        accessToken: "test_bearer_token"
        refreshToken: "refresh"
        hubUrl: "http://hub:8080"
    }))

    hubConfig = HubConfig()
    header = hubConfig.getAuthHeader()
    assertEqual(header, "Bearer test_bearer_token")

    Storage.delete("hub_session")
    print "TestGetAuthHeaderWithSession passed"
end sub

' Test getRelayHeaders returns correct headers
sub TestGetRelayHeaders()
    Storage.set("hub_session", FormatJSON({
        accessToken: "relay_token"
        refreshToken: "refresh"
        hubUrl: "http://hub:8080"
    }))

    hubConfig = HubConfig()
    hubConfig.setActiveServer({
        serverId: "srv-relay-123"
        name: "Relay Server"
        hostname: "http://direct:8096"
    })

    headers = hubConfig.getRelayHeaders()
    assertEqual(headers["Authorization"], "Bearer relay_token")
    assertEqual(headers["X-Server-Id"], "srv-relay-123")

    Storage.delete("hub_session")
    print "TestGetRelayHeaders passed"
end sub

' Test isConfigured returns false when no hub URL
sub TestIsConfiguredFalse()
    Storage.delete("hub_url")

    hubConfig = HubConfig()
    assertFalse(hubConfig.isConfigured())
    print "TestIsConfiguredFalse passed"
end sub

' Test isConfigured returns true when hub URL is set
sub TestIsConfiguredTrue()
    Storage.set("hub_url", "http://hub:8080")

    hubConfig = HubConfig()
    assertTrue(hubConfig.isConfigured())

    Storage.delete("hub_url")
    print "TestIsConfiguredTrue passed"
end sub

' Test clear removes all configuration
sub TestClearConfig()
    Storage.set("hub_url", "http://hub:8080")
    Storage.set("connection_mode", "relay")
    Storage.set("active_server", FormatJSON({serverId: "srv-clear"}))

    hubConfig = HubConfig()
    hubConfig.clear()

    assertEqual(Storage.get("hub_url"), "")
    assertEqual(Storage.get("connection_mode"), "")
    assertEqual(Storage.get("active_server"), "")
    print "TestClearConfig passed"
end sub