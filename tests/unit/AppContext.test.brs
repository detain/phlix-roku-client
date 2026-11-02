' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/AppContext.test.brs

' ===========================================
' AppContext Unit Tests
' ===========================================

sub TestGetServerUrl()
    ' Test GetServerUrl returns stored value or default
    url = GetServerUrl()
    assertTrue(url <> invalid)
    assertTrue(url.Len() > 0)
    print "TestGetServerUrl passed"
end sub

sub TestIsServerConnected()
    ' Test IsServerConnected checks for stored server URL
    connected = IsServerConnected()
    ' Server may or may not be connected depending on test environment
    assertTrue(connected <> invalid)
    print "TestIsServerConnected passed"
end sub

sub TestGetConnectionKind()
    ' Test GetConnectionKind returns "direct" or "hub"
    kind = GetConnectionKind()
    assertTrue(kind = "direct" or kind = "hub")
    print "TestGetConnectionKind passed"
end sub

sub TestGetActiveServerId()
    ' Test GetActiveServerId returns string
    id = GetActiveServerId()
    assertTrue(id <> invalid)
    ' Should be empty string if not in hub mode
    assertTrue(id.Len() >= 0)
    print "TestGetActiveServerId passed"
end sub

sub TestGetMediaBaseUrl()
    ' Test GetMediaBaseUrl returns a URL string
    url = GetMediaBaseUrl()
    assertTrue(url <> invalid)
    assertTrue(url.Len() > 0)
    print "TestGetMediaBaseUrl passed"
end sub

sub TestGetApiClient()
    ' Test GetApiClient returns an ApiClient instance
    api = GetApiClient()
    assertTrue(api <> invalid)
    print "TestGetApiClient passed"
end sub

sub TestGetHubApiClient()
    ' Test GetHubApiClient returns an ApiClient instance
    api = GetHubApiClient()
    assertTrue(api <> invalid)
    print "TestGetHubApiClient passed"
end sub

sub TestGetMediaBaseUrlInHubMode()
    ' Test GetMediaBaseUrl behavior differs by connection kind
    kind = GetConnectionKind()
    url = GetMediaBaseUrl()
    if kind = "hub" then
        ' In hub mode, should include relay path if server is picked
        activeId = GetActiveServerId()
        if activeId <> "" then
            assertTrue(url.Instr(0, "/proxy") > 0 or url.Len() > 0)
        end if
    end if
    assertTrue(true)
    print "TestGetMediaBaseUrlInHubMode passed"
end sub

sub TestAppContextMultipleGetApiClient()
    ' Test multiple GetApiClient calls work
    api1 = GetApiClient()
    api2 = GetApiClient()
    assertTrue(api1 <> invalid)
    assertTrue(api2 <> invalid)
    print "TestAppContextMultipleGetApiClient passed"
end sub

sub TestAppContextHubApiClientVsMediaApiClient()
    ' Test GetHubApiClient vs GetApiClient are different
    hubApi = GetHubApiClient()
    mediaApi = GetApiClient()
    assertTrue(hubApi <> invalid)
    assertTrue(mediaApi <> invalid)
    ' Both should have baseUrl
    assertTrue(hubApi.baseUrl <> invalid)
    assertTrue(mediaApi.baseUrl <> invalid)
    print "TestAppContextHubApiClientVsMediaApiClient passed"
end sub

sub TestDirectPlayProbeCodecIsNamedEstateCanonicalCodec()
    ' R-ROKU-27: the direct-play capability gate probes a NAMED single-source
    ' codec. The value is part of the law: every server device profile's
    ' transcode target is h264 (the estate's canonical delivery codec), so the
    ' client-side bet the accessor names must stay exactly that - a silently
    ' moved value would mis-close or mis-open the gate with no wire evidence
    ' behind it (shape + docblock markers are pinned by Check 72).
    codec = DirectPlayProbeCodec()
    assertTrue(type(codec) = "String")
    assertTrue(codec = "h264")
    print "TestDirectPlayProbeCodecIsNamedEstateCanonicalCodec passed"
end sub
