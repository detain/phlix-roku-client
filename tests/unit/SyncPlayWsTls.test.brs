' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SyncPlayWsTls.test.brs

' ===========================================
' SyncPlay plaintext-origin law + Sec-WebSocket-Accept proof - unit tests
'
' Review roku__exploiter M3 (fix M-ROKU-14): PlayerScene's :8097 dial offered
' the MAIN ACCOUNT JWT verbatim in the cleartext bearer-subprotocol handshake
' regardless of the server origin's scheme, and SyncPlayProtocol accepted any
' "101" status line without checking the Sec-WebSocket-Accept hash. On an
' https origin that meant a passive LAN sniffer captured a TLS-established
' account credential; on any origin a blind injector could forge a 101 with
' no handshake proof at all.
'
' The cure has two halves, both pinned here (the call sites live in component
' scope and are NOT callable from this harness — the WireGuard.test.brs
' precedent — but the two predicates under test are source/lib globals):
'   1. SyncPlayWsRefusedForOrigin() (source/lib/Utilities.brs): an https://
'      origin refuses the plaintext dial BEFORE the credential is read.
'   2. SyncPlayProtocol.VerifyHandshakeAccept(): the answer must carry
'      Base64(SHA1(offered key + RFC6455 GUID)); absent header /
'      non-computable expectation / mismatch are FAIL-CLOSED refusals.
' CHECK46 in scripts/verify-runtime.sh statically pins the wiring of both into
' PlayerScene + SyncPlayTask.
'
' Venue: rooibos on-device (`make test-unit` with ROKU_HOST); authored and
' compile-covered via `npx bsc` here, executed on a device/emulator host. The
' RFC6455 §1.3 positive vector needs the roEVPDigest SHA1 — exercised on the
' device; a firmware without SHA1 support must take the fail-closed branch,
' which the same test pins.
' ===========================================

sub TestSyncPlayWsRefusedForOriginTruthTable()
    ' The exploitable class: TLS-established JWT on a cleartext handshake.
    assertTrue(SyncPlayWsRefusedForOrigin("https://box.example.com"))
    assertTrue(SyncPlayWsRefusedForOrigin("https://box.example.com:8443/api"))
    assertTrue(SyncPlayWsRefusedForOrigin("HTTPS://BOX.Example.COM"))
    assertTrue(SyncPlayWsRefusedForOrigin("  https://box.example.com  "))
    ' http origins keep dialling (REST is already cleartext there — no new
    ' exposure class; the dial itself stays accept-verified regardless).
    assertFalse(SyncPlayWsRefusedForOrigin("http://192.168.1.50:8096"))
    ' "" / invalid / scheme-less speak through the caller's own guards.
    assertFalse(SyncPlayWsRefusedForOrigin(""))
    assertFalse(SyncPlayWsRefusedForOrigin("   "))
    assertFalse(SyncPlayWsRefusedForOrigin("box.example.com"))
    print "TestSyncPlayWsRefusedForOriginTruthTable passed"
end sub

sub TestSecWebSocketAcceptValueParsing()
    proto = SyncPlayProtocol()
    crlf = Chr(13) + Chr(10)
    resp = "HTTP/1.1 101 Switching Protocols" + crlf + "Upgrade: websocket" + crlf
    resp = resp + "Connection: Upgrade" + crlf
    resp = resp + "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" + crlf + crlf

    assertEqual(proto.SecWebSocketAcceptValue(resp), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    ' Header-name match is case-insensitive, value whitespace is trimmed.
    lower = "HTTP/1.1 101 Switching Protocols" + crlf + "sec-websocket-accept:   s3pPLMBiTxaQ9kYGzzhZRbK+xOo=  " + crlf + crlf
    assertEqual(proto.SecWebSocketAcceptValue(lower), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    ' Absent header / empty input extract to "" (the fail-closed side of the law).
    noHeader = "HTTP/1.1 101 Switching Protocols" + crlf + "Upgrade: websocket" + crlf + crlf
    assertEqual(proto.SecWebSocketAcceptValue(noHeader), "")
    assertEqual(proto.SecWebSocketAcceptValue(""), "")

    ' A body may never impersonate a header: the fake accept line sits AFTER
    ' the blank-line terminator, so the header-block scan must not see it.
    spoofed = "HTTP/1.1 101 Switching Protocols" + crlf + crlf
    spoofed = spoofed + "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" + crlf
    assertEqual(proto.SecWebSocketAcceptValue(spoofed), "")

    ' Paired guard: with a REAL accept header present AND a spoofed copy
    ' after the terminator, the answer is the header block's value — the
    ' scan stops at the first blank line and the body line is never seen.
    realThenSpoof = "HTTP/1.1 101 Switching Protocols" + crlf
    realThenSpoof = realThenSpoof + "Sec-WebSocket-Accept: realHeaderAcceptValue==" + crlf + crlf
    realThenSpoof = realThenSpoof + "Sec-WebSocket-Accept: spoofedBodyAcceptVal==" + crlf
    assertEqual(proto.SecWebSocketAcceptValue(realThenSpoof), "realHeaderAcceptValue==")
    print "TestSecWebSocketAcceptValueParsing passed"
end sub

sub TestIsHex40Shape()
    proto = SyncPlayProtocol()
    assertTrue(proto.IsHex40("0123456789ABCDEF0123456789abcdef01234567"))
    assertFalse(proto.IsHex40("0123456789ABCDEF0123456789abcdef0123456"))   ' 39 chars
    assertFalse(proto.IsHex40("0123456789ABCDEF0123456789abcdef01234567Z")) ' non-hex
    assertFalse(proto.IsHex40(""))
    print "TestIsHex40Shape passed"
end sub

sub TestVerifyHandshakeAcceptFailClosed()
    proto = SyncPlayProtocol()
    crlf = Chr(13) + Chr(10)
    key = "dGhlIHNhbXBsZSBub25jZQ=="
    goodResp = "HTTP/1.1 101 Switching Protocols" + crlf
    goodResp = goodResp + "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" + crlf + crlf

    ' An empty offered key can never produce a proof.
    assertFalse(proto.VerifyHandshakeAccept(goodResp, ""))
    ' A 101-shaped response WITHOUT the accept header is refused (era posture
    ' accepted these blindly).
    assertFalse(proto.VerifyHandshakeAccept("HTTP/1.1 101 Switching Protocols" + crlf + crlf, key))
    ' A wrong accept VALUE never matches, no matter how it is dressed.
    wrongValue = "HTTP/1.1 101 Switching Protocols" + crlf
    wrongValue = wrongValue + "Sec-WebSocket-Accept: AAAAAAAAAAAAAAAAAAAAAAAAAAA=" + crlf + crlf
    assertFalse(proto.VerifyHandshakeAccept(wrongValue, key))
    ' Case matters in base64 — a lowercased echo of the right bytes is a mismatch.
    lowered = "HTTP/1.1 101 Switching Protocols" + crlf
    lowered = lowered + "Sec-WebSocket-Accept: s3pplmbitxaq9kygzzhzrbk+xoo=" + crlf + crlf
    assertFalse(proto.VerifyHandshakeAccept(lowered, key))
    print "TestVerifyHandshakeAcceptFailClosed passed"
end sub

sub TestRfc6455AcceptVector()
    ' The RFC6455 §1.3 example: key "dGhlIHNhbXBsZSBub25jZQ==" must answer the
    ' accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=". On-device roEVPDigest decides
    ' branch proves: a firmware that can compute SHA1 must produce (and match)
    ' the value; a firmware that cannot must FAIL CLOSED on the same response.
    proto = SyncPlayProtocol()
    crlf = Chr(13) + Chr(10)
    key = "dGhlIHNhbXBsZSBub25jZQ=="
    resp = "HTTP/1.1 101 Switching Protocols" + crlf
    resp = resp + "Upgrade: websocket" + crlf + "Connection: Upgrade" + crlf
    resp = resp + "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" + crlf + crlf

    expected = proto.ExpectedSecWebSocketAccept(key)
    if expected = "" then
        ' No SHA1 on this device: the proof is non-computable, so the law is
        ' refusal — the vector's own accept line must NOT be waved through.
        assertFalse(proto.VerifyHandshakeAccept(resp, key))
        print "TestRfc6455AcceptVector passed (fail-closed branch: no SHA1 support)"
        return
    end if

    assertEqual(expected, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    assertTrue(proto.VerifyHandshakeAccept(resp, key))

    ' The header may sit anywhere in the block and still verify; a DIFFERENT
    ' offered key must reject the same response (the hash binds our key).
    shuffled = "HTTP/1.1 101 Switching Protocols" + crlf
    shuffled = shuffled + "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" + crlf
    shuffled = shuffled + "Upgrade: websocket" + crlf + crlf
    assertTrue(proto.VerifyHandshakeAccept(shuffled, key))
    assertFalse(proto.VerifyHandshakeAccept(shuffled, "bm90dGhlc2FtcGxla2V5MTIzNDU2"))
    print "TestRfc6455AcceptVector passed"
end sub
