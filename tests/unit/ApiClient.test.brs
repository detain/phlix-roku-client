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

sub TestApiClientParseVariants()
    ' G4: the A7 variant ladder is parsed to a compact {id,label,url} list,
    ' preserving the server's highest-first order.
    client = ApiClient("http://localhost:8096")
    resp = {
        master_url: "/hls/j1/master.m3u8?sig=m"
        variants: [
            { id: "original", label: "Original (1080p)", url: "/hls/j1/media_voriginal.m3u8?sig=a" }
            { id: "720p", label: "720p", url: "/hls/j1/media_v720p.m3u8?sig=b" }
            { id: "480p", label: "480p", url: "/hls/j1/media_v480p.m3u8?sig=c" }
        ]
    }
    out = client.parseVariants(resp)
    assertEqual(out.Count(), 3)
    assertEqual(out[0].id, "original")
    assertEqual(out[0].label, "Original (1080p)")
    assertEqual(out[1].id, "720p")
    assertEqual(out[1].url, "/hls/j1/media_v720p.m3u8?sig=b")
    assertEqual(out[2].id, "480p")
    print "TestApiClientParseVariants passed"
end sub

sub TestApiClientParseVariantsLegacy()
    ' G4: a legacy single-variant job sends variants:null (or omits it) -> [];
    ' invalid input and malformed rungs (missing id/url) never crash and are
    ' dropped; a rung missing only a label falls back to its id.
    client = ApiClient("http://localhost:8096")
    assertEqual(client.parseVariants({ master_url: "/hls/j2/master.m3u8" }).Count(), 0)
    assertEqual(client.parseVariants({ variants: invalid }).Count(), 0)
    assertEqual(client.parseVariants(invalid).Count(), 0)

    ' A non-assocarray resp (roString / roArray) must return [] without a runtime
    ' type error - it passes the `invalid` check but has no .DoesExist member.
    assertEqual(client.parseVariants("not-a-response").Count(), 0)
    assertEqual(client.parseVariants([1, 2, 3]).Count(), 0)

    ' A `variants` field present but NOT an roArray (a string or assocarray) is a
    ' non-array robustness case -> [] via the type(variants) <> "roArray" guard.
    assertEqual(client.parseVariants({ variants: "720p" }).Count(), 0)
    assertEqual(client.parseVariants({ variants: { id: "720p" } }).Count(), 0)

    ' An EMPTY variants array is a valid roArray that passes every guard and
    ' reaches the for-each loop with zero iterations -> [] (distinct input shape
    ' from variants:null/omitted, which short-circuit before the loop).
    assertEqual(client.parseVariants({ variants: [] }).Count(), 0)

    resp = { variants: [ { id: "720p" }, { url: "/x.m3u8" }, invalid, { id: "480p", url: "/hls/j2/media_v480p.m3u8" } ] }
    out = client.parseVariants(resp)
    assertEqual(out.Count(), 1)
    assertEqual(out[0].id, "480p")
    assertEqual(out[0].label, "480p")
    print "TestApiClientParseVariantsLegacy passed"
end sub