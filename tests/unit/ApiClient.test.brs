' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/ApiClient.test.brs

' copyright 2026 Joe Huss
'


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
    assertTrue(Left(client.deviceId, 5) = "roku-")
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

' R-ROKU-24 — the keep-on-server_error law (folds in the candidate follow-up
' named by the M-ROKU-04 r2 disclosure). Every restoreSession failure arm that
' carries NO verdict on this token preserves the stored credentials; only the
' 401/403 verdict ("session_invalid") and the empty-state ("no_session") arms
' reach the wipe tail. request() is stubbed through the client's own member
' slot (m.stubEnv) so the ladder is driven end-to-end without a server.
' Venue (M-ROKU-04 Discovery.test.brs precedent): the suite constructs through
' ApiClient() which attaches function-object state brs cannot carry (runner
' EXCLUDED census), and rooibos needs hardware the CI has none of — CHECK68
' holds the static teeth meanwhile; these subs are the device-lane deliverable.
sub TestRestoreSessionKeepsOnServerError()
    client = ApiClient("http://localhost:8096")
    client.setToken("rok24-token")
    client.setRefreshToken("rok24-refresh")
    client.setSession("rok24-session")
    client.request = function(method as String, path as String, body as Object) as Object
        return m.stubEnv
    end function

    ' Arm 1: 2xx /auth/me with no user payload — server shape failure.
    client.stubEnv = { ok: true, status: 200, data: {} }
    assertEqual(client.restoreSession(), false)
    assertEqual(client.restoreReason, "server_error")
    assertEqual(GetStorage().get("auth_token"), "rok24-token")
    assertEqual(GetStorage().get("refresh_token"), "rok24-refresh")
    assertEqual(GetStorage().get("session_id"), "rok24-session")

    ' Arm 2: answered failure without a token verdict (5xx class).
    client.stubEnv = { ok: false, status: 500, error: "Server Error" }
    assertEqual(client.restoreSession(), false)
    assertEqual(client.restoreReason, "server_error")
    assertEqual(GetStorage().get("auth_token"), "rok24-token")

    ' Arm 3: the transport layer handed back nothing classifiable (invalid
    ' envelope) — still no verdict on the token, so still keep.
    client.stubEnv = invalid
    assertEqual(client.restoreSession(), false)
    assertEqual(client.restoreReason, "server_error")
    assertEqual(GetStorage().get("auth_token"), "rok24-token")

    ' Regression fence (M-ROKU-04): the transport arm keeps, untouched by the
    ' rider — the law this lane extends, not replaces.
    client.stubEnv = { ok: false, status: 0, error: "timeout" }
    assertEqual(client.restoreSession(), false)
    assertEqual(client.restoreReason, "timeout")
    assertEqual(GetStorage().get("auth_token"), "rok24-token")
    print "TestRestoreSessionKeepsOnServerError passed"
end sub

sub TestRestoreSessionWipesOnVerdictsOnly()
    client = ApiClient("http://localhost:8096")
    client.request = function(method as String, path as String, body as Object) as Object
        return m.stubEnv
    end function

    ' session_invalid: 401 — the server answered and rejected THIS token.
    client.setToken("rok24v-token")
    client.setRefreshToken("rok24v-refresh")
    client.setSession("rok24v-session")
    client.stubEnv = { ok: false, status: 401, error: "unauthorized" }
    assertEqual(client.restoreSession(), false)
    assertEqual(client.restoreReason, "session_invalid")
    assertEqual(GetStorage().get("auth_token"), invalid)
    assertEqual(GetStorage().get("refresh_token"), invalid)
    assertEqual(GetStorage().get("session_id"), invalid)

    ' session_invalid: 403 — same verdict, same wipe.
    client.setToken("rok24v-token")
    client.stubEnv = { ok: false, status: 403, error: "forbidden" }
    assertEqual(client.restoreSession(), false)
    assertEqual(client.restoreReason, "session_invalid")
    assertEqual(GetStorage().get("auth_token"), invalid)

    ' no_session: empty storage is the login answer, not a network accusation.
    client.setToken("rok24v-token")
    client.setToken("")
    client.stubEnv = { ok: true, status: 200, data: { user: { id: "nobody" } } }
    assertEqual(client.restoreSession(), false)
    assertEqual(client.restoreReason, "no_session")

    ' authenticated: the one true path, user payload lands on the client.
    client.setToken("rok24v-token")
    client.stubEnv = { ok: true, status: 200, data: { user: { id: "u-rok24" } } }
    assertEqual(client.restoreSession(), true)
    assertEqual(client.restoreReason, "authenticated")
    assertEqual(client.user.id, "u-rok24")

    ' Leave storage as found: the authenticated arm persisted nothing, but the
    ' seeded test token is still riding in the registry — clear the trio.
    client.setToken("")
    client.setRefreshToken("")
    client.setSession("")
    print "TestRestoreSessionWipesOnVerdictsOnly passed"
end sub