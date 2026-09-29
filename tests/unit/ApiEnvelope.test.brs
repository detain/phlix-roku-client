' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/ApiEnvelope.test.brs

' copyright 2026 Joe Huss
'
'
' ===========================================
' API Envelope Law - unit tests for UnwrapApiEnvelope()
'
' Regression shield for the 2c119f9 consumer gap: ApiClient.request() returns
' the transport envelope {status, ok, data, error} and the server payload rides
' at .data. Every reader must unwrap once through UnwrapApiEnvelope() (see the
' law block in source/lib/ApiClient.brs and docs/api-envelope.md). These tests
' pin the helper's contract; CHECK 26 in scripts/verify-runtime.sh pins that no
' shipped code bypasses it.
' ===========================================

sub TestUnwrapApiEnvelopeReturnsPayload()
    ' A transport envelope unwraps to its .data member.
    env = { status: 200, ok: true, data: { libraries: [ { id: "lib1" } ] }, error: "" }
    payload = UnwrapApiEnvelope(env)
    assertEqual(payload.libraries.Count(), 1)
    assertEqual(payload.libraries[0].id, "lib1")
    print "TestUnwrapApiEnvelopeReturnsPayload passed"
end sub

sub TestUnwrapApiEnvelopeRequiresBothMarkers()
    ' Only request() builds envelopes, and it ALWAYS sets status AND ok. An
    ' assocarray carrying just one marker is a server payload (or a helper that
    ' already returned data) and must pass through untouched - never silently
    ' collapse to .data.
    onlyOk = { ok: true, data: { item: { id: "x" } } }
    passthrough = UnwrapApiEnvelope(onlyOk)
    assertEqual(passthrough.data.item.id, "x")

    onlyStatus = { status: 200, item: { id: "y" } }
    passthrough2 = UnwrapApiEnvelope(onlyStatus)
    assertEqual(passthrough2.item.id, "y")
    print "TestUnwrapApiEnvelopeRequiresBothMarkers passed"
end sub

sub TestUnwrapApiEnvelopeFailureYieldsInvalid()
    ' A failed request carries invalid at .data - unwrap returns invalid so the
    ' caller's guard (env.ok + payload <> invalid) fires instead of rendering a
    ' phantom object.
    env = { status: 404, ok: false, data: invalid, error: "not_found" }
    payload = UnwrapApiEnvelope(env)
    assertTrue(payload = invalid)
    print "TestUnwrapApiEnvelopeFailureYieldsInvalid passed"
end sub

sub TestUnwrapApiEnvelopeNonObjectPassThrough()
    ' invalid, strings and arrays are not envelopes - returned unchanged, no
    ' crash (the helper must be safe on any value a pre-unwrapped helper hands it).
    assertTrue(UnwrapApiEnvelope(invalid) = invalid)
    assertEqual(UnwrapApiEnvelope("plain"), "plain")
    list = [1, 2, 3]
    assertTrue(UnwrapApiEnvelope(list) = list)
    print "TestUnwrapApiEnvelopeNonObjectPassThrough passed"
end sub

sub TestUnwrapApiEnvelopePayloadPassthrough()
    ' Pre-unwrapped helpers (getMe-style: they already drilled the envelope)
    ' hand back plain payloads. A payload without BOTH envelope markers flows
    ' through unchanged so one call site pattern works everywhere.
    user = { id: "u1", is_admin: true }
    out = UnwrapApiEnvelope(user)
    assertEqual(out.id, "u1")
    assertTrue(out.is_admin)
    print "TestUnwrapApiEnvelopePayloadPassthrough passed"
end sub

sub TestUnwrapApiEnvelopeLoginShape()
    ' login() now returns the same transport envelope as request() (the raw
    ' {access_token,...} body rides at .data - there is NO success key on the
    ' server or hub response; the old `data.success = true` verdict made every
    ' login fail). Pin the unwrap for that shape.
    env = {
        status: 200
        ok: true
        data: { access_token: "at", refresh_token: "rt", user: { id: "u9" } }
        error: ""
    }
    payload = UnwrapApiEnvelope(env)
    assertEqual(payload.access_token, "at")
    assertEqual(payload.user.id, "u9")
    print "TestUnwrapApiEnvelopeLoginShape passed"
end sub
