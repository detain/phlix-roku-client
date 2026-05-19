' tests/hub/HubAuth.test.brs

' ===========================================
' HubAuth Unit Tests
' ===========================================

' Test helper to create mock storage
function createMockStorage() as Object
    mock = {
        data: {}

        set: function(key as String, value as String)
            m.data[key] = value
        end function

        get: function(key as String) as String
            if m.data.DoesExist(key) then
                return m.data[key]
            end if
            return ""
        end function

        delete: function(key as String)
            if m.data.DoesExist(key) then
                m.data.Delete(key)
            end if
        end function

        clear: function()
            m.data.Clear()
        end function
    }
    return mock
end function

' Test that HubAuth initializes correctly
sub TestHubAuthInit()
    hubAuth = HubAuth()
    assertTrue(hubAuth <> invalid)
    print "TestHubAuthInit passed"
end sub

' Test sign in returns false on empty response (simulated)
' Note: This test validates the method exists and handles missing storage
sub TestHubAuthSignInMissingStorage()
    hubAuth = HubAuth()
    ' Without proper HTTP mocking, we can only test the failure path
    ' by ensuring signIn returns false when storage is not available
    result = hubAuth.signIn("http://localhost:8080", "test", "test")
    ' Will fail due to no HTTP mock, which is expected
    assertFalse(result)
    print "TestHubAuthSignInMissingStorage passed"
end sub

' Test sign out clears session
sub TestHubAuthSignOut()
    hubAuth = HubAuth()
    ' Set a mock session first
    Storage.set("hub_session", FormatJSON({
        accessToken: "test_token"
        refreshToken: "test_refresh"
        hubUrl: "http://localhost:8080"
    }))

    hubAuth.signOut()

    sessionJson = Storage.get("hub_session")
    assertEqual(sessionJson, "")
    print "TestHubAuthSignOut passed"
end sub

' Test list servers returns empty array when not signed in
sub TestHubAuthListServersNotSignedIn()
    hubAuth = HubAuth()
    ' Clear any existing session
    Storage.delete("hub_session")

    servers = hubAuth.listServers()
    assertTrue(servers <> invalid)
    assertEqual(servers.Count(), 0)
    print "TestHubAuthListServersNotSignedIn passed"
end sub

' Test isSignedIn returns false when no session
sub TestHubAuthIsSignedInFalse()
    hubAuth = HubAuth()
    Storage.delete("hub_session")

    isSignedIn = hubAuth.isSignedIn()
    assertFalse(isSignedIn)
    print "TestHubAuthIsSignedInFalse passed"
end sub

' Test isSignedIn returns true when valid session exists
sub TestHubAuthIsSignedInTrue()
    hubAuth = HubAuth()
    Storage.set("hub_session", FormatJSON({
        accessToken: "valid_token"
        refreshToken: "refresh_token"
        expiresAt: 3600
        userId: "user123"
        hubUrl: "http://localhost:8080"
    }))

    isSignedIn = hubAuth.isSignedIn()
    assertTrue(isSignedIn)
    print "TestHubAuthIsSignedInTrue passed"
end sub

' Test getSession returns invalid when no session
sub TestHubAuthGetSessionInvalid()
    hubAuth = HubAuth()
    Storage.delete("hub_session")

    session = hubAuth.getSession()
    assertTrue(session = invalid)
    print "TestHubAuthGetSessionInvalid passed"
end sub

' Test getSession returns session when exists
sub TestHubAuthGetSessionValid()
    hubAuth = HubAuth()
    testSession = {
        accessToken: "test_access_token"
        refreshToken: "test_refresh_token"
        expiresAt: 3600
        userId: "user123"
        hubUrl: "http://localhost:8080"
    }
    Storage.set("hub_session", FormatJSON(testSession))

    session = hubAuth.getSession()
    assertTrue(session <> invalid)
    assertEqual(session.accessToken, "test_access_token")
    assertEqual(session.refreshToken, "test_refresh_token")
    print "TestHubAuthGetSessionValid passed"
end sub

' Test setSession persists correctly
sub TestHubAuthSetSessionPersist()
    hubAuth = HubAuth()
    testSession = {
        accessToken: "new_token"
        refreshToken: "new_refresh"
        expiresAt: 7200
        userId: "user456"
        hubUrl: "http://newhub:8080"
    }

    hubAuth.setSession(testSession)

    stored = Storage.get("hub_session")
    assertTrue(stored <> "")
    parsed = ParseJSON(stored)
    assertEqual(parsed.accessToken, "new_token")
    print "TestHubAuthSetSessionPersist passed"
end sub

' Test setSession with invalid clears storage
sub TestHubAuthSetSessionClear()
    hubAuth = HubAuth()
    Storage.set("hub_session", FormatJSON({accessToken: "old_token"}))

    hubAuth.setSession(invalid)

    stored = Storage.get("hub_session")
    assertEqual(stored, "")
    print "TestHubAuthSetSessionClear passed"
end sub