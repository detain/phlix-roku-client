' tests/unit/ApiClient.test.brs

' ===========================================
' ApiClient Unit Tests
' ===========================================

sub TestApiClientInit()
    ' Test initialization
    client = ApiClient("http://localhost:8096")
    assertEqual(client.deviceType, "roku")
    assertEqual(client.baseUrl, "http://localhost:8096")
    print "TestApiClientInit passed"
end sub

sub TestApiClientDeviceId()
    ' Test device ID generation
    client = ApiClient("http://localhost:8096")
    assertTrue(client.deviceId.Len() > 0)
    assertTrue(client.deviceId.Left(5) = "roku-")
    print "TestApiClientDeviceId passed"
end sub

sub TestApiClientDeviceProfile()
    ' Test device profile
    client = ApiClient("http://localhost:8096")
    assertEqual(client.deviceProfile.MaxStreamingBitrate, 30000000)
    assertEqual(client.deviceProfile.Name, "Roku")
    print "TestApiClientDeviceProfile passed"
end sub

sub TestApiClientToken()
    ' Test token setting
    client = ApiClient("http://localhost:8096")
    client.setToken("test-token")
    assertEqual(client.token, "test-token")
    print "TestApiClientToken passed"
end sub

sub TestApiClientSession()
    ' Test session setting
    client = ApiClient("http://localhost:8096")
    client.setSession("test-session")
    assertEqual(client.sessionId, "test-session")
    print "TestApiClientSession passed"
end sub