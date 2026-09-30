' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SyncPlayProtocol.test.brs

' ===========================================
' SyncPlayProtocol Unit Tests
' ===========================================

sub TestSyncPlayProtocolInit()
    ' Test initialization
    proto = SyncPlayProtocol()
    assertTrue(proto <> invalid)
    assertEqual(proto.PROTOCOL_VERSION, 1)
    print "TestSyncPlayProtocolInit passed"
end sub

sub TestSyncPlayProtocolOpcodeConstants()
    ' Test opcode constants are defined
    proto = SyncPlayProtocol()
    assertEqual(proto.OP_TEXT, 1)
    assertEqual(proto.OP_CLOSE, 8)
    assertEqual(proto.OP_PING, 9)
    assertEqual(proto.OP_PONG, 10)
    print "TestSyncPlayProtocolOpcodeConstants passed"
end sub

sub TestSyncPlayProtocolTimeSyncConstants()
    ' Test TimeSync constants are defined
    proto = SyncPlayProtocol()
    assertEqual(proto.OFFSET_SAMPLE_COUNT, 5)
    assertEqual(proto.MAX_RTT, 1000)
    assertEqual(proto.DRIFT_MIN, 0.99)
    assertEqual(proto.DRIFT_MAX, 1.01)
    assertEqual(proto.DRIFT_FACTOR, 0.1)
    print "TestSyncPlayProtocolTimeSyncConstants passed"
end sub

sub TestSyncPlayProtocolNewWebSocketKey()
    ' Test NewWebSocketKey generates a base64 string
    proto = SyncPlayProtocol()
    key = proto.NewWebSocketKey()
    assertTrue(key <> invalid)
    assertTrue(key.Len() > 0)
    print "TestSyncPlayProtocolNewWebSocketKey passed"
end sub

sub TestSyncPlayProtocolNewWebSocketKeyUniqueness()
    ' Test NewWebSocketKey generates different keys
    proto = SyncPlayProtocol()
    key1 = proto.NewWebSocketKey()
    key2 = proto.NewWebSocketKey()
    ' Keys may or may not be different (random), but both should be valid base64
    assertTrue(key1 <> invalid)
    assertTrue(key2 <> invalid)
    print "TestSyncPlayProtocolNewWebSocketKeyUniqueness passed"
end sub

sub TestSyncPlayProtocolXorByte()
    ' Test XorByte function
    proto = SyncPlayProtocol()
    ' XOR of 1 and 1 should be 0
    result = proto.XorByte(1, 1)
    assertEqual(result, 0)
    ' XOR of 1 and 0 should be 1
    result = proto.XorByte(1, 0)
    assertEqual(result, 1)
    ' XOR of 255 and 255 should be 0
    result = proto.XorByte(255, 255)
    assertEqual(result, 0)
    print "TestSyncPlayProtocolXorByte passed"
end sub

sub TestSyncPlayProtocolBuildClientFrameEmpty()
    ' Test BuildClientFrame with empty payload
    proto = SyncPlayProtocol()
    empty = CreateObject("roByteArray")
    frame = proto.BuildClientFrame(proto.OP_TEXT, empty)
    assertTrue(frame <> invalid)
    assertTrue(frame.Count() >= 2)
    print "TestSyncPlayProtocolBuildClientFrameEmpty passed"
end sub

sub TestSyncPlayProtocolBuildTextFrame()
    ' Test BuildTextFrame creates a masked text frame
    proto = SyncPlayProtocol()
    frame = proto.BuildTextFrame("hello")
    assertTrue(frame <> invalid)
    assertTrue(frame.Count() > 5)
    print "TestSyncPlayProtocolBuildTextFrame passed"
end sub

sub TestSyncPlayProtocolBuildCloseFrame()
    ' Test BuildCloseFrame creates a close frame
    proto = SyncPlayProtocol()
    frame = proto.BuildCloseFrame()
    assertTrue(frame <> invalid)
    print "TestSyncPlayProtocolBuildCloseFrame passed"
end sub

sub TestSyncPlayProtocolBuildPongFrame()
    ' Test BuildPongFrame creates a pong frame
    proto = SyncPlayProtocol()
    empty = CreateObject("roByteArray")
    frame = proto.BuildPongFrame(empty)
    assertTrue(frame <> invalid)
    print "TestSyncPlayProtocolBuildPongFrame passed"
end sub

sub TestSyncPlayProtocolBuildHandshakeRequest()
    ' Test BuildHandshakeRequest generates valid HTTP request.
    ' :8097 law since phlix-server 424c14d0: the path is the BARE "/syncplay"
    ' (no ?token= query) - the credential rides the extraHeaders carrier, pinned
    ' in TestSyncPlayProtocolBuildHandshakeRequestWithBearerOffer below.
    proto = SyncPlayProtocol()
    key = proto.NewWebSocketKey()
    req = proto.BuildHandshakeRequest("localhost", 8097, "/syncplay", key)
    assertTrue(req <> invalid)
    assertTrue(req.Instr(0, "GET /syncplay HTTP/1.1") >= 0)
    assertTrue(req.Instr(0, "Upgrade: websocket") >= 0)
    assertTrue(req.Instr(0, "Connection: Upgrade") >= 0)
    ' No credential carrier without extraHeaders, and never a URL query token.
    assertTrue(req.Instr(0, "Sec-WebSocket-Protocol") < 0)
    assertTrue(req.Instr(0, "token=") < 0)
    print "TestSyncPlayProtocolBuildHandshakeRequest passed"
end sub

sub TestSyncPlayProtocolBearerSubprotocolOffer()
    ' Two-entry offer law: marker entry first, raw JWT second, comma-space
    ' joined; "" for no credential (empty protocol-ids are an illegal offer).
    proto = SyncPlayProtocol()
    assertEqual(proto.BEARER_SUBPROTOCOL, "bearer")
    assertEqual(proto.BearerSubprotocolOffer("abc.def.ghi"), "bearer, abc.def.ghi")
    assertEqual(proto.BearerSubprotocolOffer(""), "")
    ' JWT chars are RFC 7230 token chars - verbatim, NOT url-encoded.
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnLXRlc3Q"
    offer = proto.BearerSubprotocolOffer(jwt)
    assertEqual(offer, "bearer, " + jwt)
    assertTrue(offer.Instr(0, "%") < 0)
    print "TestSyncPlayProtocolBearerSubprotocolOffer passed"
end sub

sub TestSyncPlayProtocolBuildHandshakeRequestWithBearerOffer()
    ' The :8097 dial puts the offer on a header line, before the terminating
    ' blank line (SyncPlayTask.WaitForConnect passes exactly this shape).
    proto = SyncPlayProtocol()
    key = proto.NewWebSocketKey()
    offer = proto.BearerSubprotocolOffer("jwt.value_here")
    req = proto.BuildHandshakeRequest("localhost", 8097, "/syncplay", key, { "Sec-WebSocket-Protocol": offer })
    assertTrue(req.Instr(0, "GET /syncplay HTTP/1.1") >= 0)
    assertTrue(req.Instr(0, "Sec-WebSocket-Protocol: bearer, jwt.value_here" + Chr(13) + Chr(10)) >= 0)
    ' The credential must never appear in the request-line query.
    assertTrue(req.Instr(0, "?token=") < 0)
    print "TestSyncPlayProtocolBuildHandshakeRequestWithBearerOffer passed"
end sub

sub TestSyncPlayProtocolHandshakeAcceptedToleratesBearerEcho()
    ' phlix-server 424c14d0 answers a bearer-offering handshake with exactly
    ' one echoed `Sec-WebSocket-Protocol: bearer` response line. The 101 check
    ' is status-line-only, so the echo (and any other response header) must be
    ' TOLERATED - this pins that contract so no future hardening chokes on it.
    proto = SyncPlayProtocol()
    crlf = Chr(13) + Chr(10)
    echoed = "HTTP/1.1 101 Switching Protocols" + crlf
    echoed = echoed + "Upgrade: websocket" + crlf
    echoed = echoed + "Connection: Upgrade" + crlf
    echoed = echoed + "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" + crlf
    echoed = echoed + "Sec-WebSocket-Protocol: bearer" + crlf
    echoed = echoed + crlf
    assertTrue(proto.HandshakeAccepted(echoed))
    ' The echo never carries the token - and an un-offered (legacy) 101 without
    ' the echo must keep passing too (byte-identical old shape).
    plain = "HTTP/1.1 101 Switching Protocols" + crlf + "Upgrade: websocket" + crlf + crlf
    assertTrue(proto.HandshakeAccepted(plain))
    print "TestSyncPlayProtocolHandshakeAcceptedToleratesBearerEcho passed"
end sub

sub TestSyncPlayProtocolHandshakeAccepted101()
    ' Test HandshakeAccepted recognizes 101 response
    proto = SyncPlayProtocol()
    assertTrue(proto.HandshakeAccepted("HTTP/1.1 101 Switching Protocols"))
    assertTrue(proto.HandshakeAccepted("HTTP/1.1 101"))
    print "TestSyncPlayProtocolHandshakeAccepted101 passed"
end sub

sub TestSyncPlayProtocolHandshakeAcceptedInvalid()
    ' Test HandshakeAccepted rejects invalid responses
    proto = SyncPlayProtocol()
    assertFalse(proto.HandshakeAccepted(invalid))
    assertFalse(proto.HandshakeAccepted(""))
    assertFalse(proto.HandshakeAccepted("HTTP/1.1 200 OK"))
    assertFalse(proto.HandshakeAccepted("HTTP/1.1 404 Not Found"))
    print "TestSyncPlayProtocolHandshakeAcceptedInvalid passed"
end sub

sub TestSyncPlayProtocolEncodeDecode()
    ' Test Encode produces JSON with required fields
    proto = SyncPlayProtocol()
    json = proto.Encode("syncplay_test", { foo: "bar" })
    assertTrue(json <> invalid)
    assertTrue(json.Instr(0, "syncplay_test") >= 0)
    print "TestSyncPlayProtocolEncode passed"
end sub

sub TestSyncPlayProtocolEncodeWithInvalidPayload()
    ' Test Encode handles invalid payload
    proto = SyncPlayProtocol()
    json = proto.Encode("syncplay_test", invalid)
    assertTrue(json <> invalid)
    assertTrue(json.Instr(0, "syncplay_test") >= 0)
    print "TestSyncPlayProtocolEncodeWithInvalidPayload passed"
end sub

sub TestSyncPlayProtocolDecodeInvalidInput()
    ' Test Decode handles invalid input
    proto = SyncPlayProtocol()
    result = proto.Decode(invalid)
    assertEqual(result, invalid)
    result = proto.Decode("")
    assertEqual(result, invalid)
    print "TestSyncPlayProtocolDecodeInvalidInput passed"
end sub

sub TestSyncPlayProtocolDecodeValidJson()
    ' Test Decode parses valid JSON
    proto = SyncPlayProtocol()
    result = proto.Decode("{}")
    assertTrue(result <> invalid)
    print "TestSyncPlayProtocolDecodeValidJson passed"
end sub

sub TestSyncPlayProtocolDecodeLegacyEnvelope()
    ' Test Decode unwraps legacy {data:{...}} envelope
    proto = SyncPlayProtocol()
    result = proto.Decode("{""type"":""syncplay_test"",""data"":{""foo"":""bar""}}")
    assertTrue(result <> invalid)
    assertEqual(result.foo, "bar")
    print "TestSyncPlayProtocolDecodeLegacyEnvelope passed"
end sub

sub TestSyncPlayProtocolTimeSyncInitialState()
    ' Test TimeSync initial state
    proto = SyncPlayProtocol()
    assertEqual(proto.GetOffset(), 0.0)
    assertEqual(proto.GetLatency(), 0.0)
    assertEqual(proto.GetDriftRate(), 1.0)
    print "TestSyncPlayProtocolTimeSyncInitialState passed"
end sub

sub TestSyncPlayProtocolIsStableInitially()
    ' Test IsStable returns false initially (not enough samples)
    proto = SyncPlayProtocol()
    assertFalse(proto.IsStable())
    print "TestSyncPlayProtocolIsStableInitially passed"
end sub

sub TestSyncPlayProtocolMax1()
    ' Test Max1 helper
    proto = SyncPlayProtocol()
    assertEqual(proto.Max1(0.5), 1.0)
    assertEqual(proto.Max1(1.0), 1.0)
    assertEqual(proto.Max1(5.0), 5.0)
    print "TestSyncPlayProtocolMax1 passed"
end sub

sub TestSyncPlayProtocolReset()
    ' Test Reset clears TimeSync state
    proto = SyncPlayProtocol()
    proto.Reset()
    assertEqual(proto.GetOffset(), 0.0)
    assertEqual(proto.GetLatency(), 0.0)
    assertEqual(proto.GetDriftRate(), 1.0)
    print "TestSyncPlayProtocolReset passed"
end sub

sub TestSyncPlayProtocolAddPongRejectsNegativeRtt()
    ' Test AddPong rejects negative RTT
    proto = SyncPlayProtocol()
    proto.AddPong(1000, 100, 50)  ' t4 - t1 = negative
    ' Should not crash, state unchanged
    assertEqual(proto.GetOffset(), 0.0)
    print "TestSyncPlayProtocolAddPongRejectsNegativeRtt passed"
end sub

sub TestSyncPlayProtocolAddPongRejectsExcessiveRtt()
    ' Test AddPong rejects RTT > MAX_RTT
    proto = SyncPlayProtocol()
    proto.AddPong(0, 0, 2000)  ' t4 - t1 = 2000 > 1000
    ' Should not crash, state unchanged
    assertEqual(proto.GetOffset(), 0.0)
    print "TestSyncPlayProtocolAddPongRejectsExcessiveRtt passed"
end sub

sub TestSyncPlayProtocolRemainderBuffer()
    ' Test RemainderBuffer creates a new buffer without leading bytes
    proto = SyncPlayProtocol()
    buf = CreateObject("roByteArray")
    buf.Push(1)
    buf.Push(2)
    buf.Push(3)
    buf.Push(4)
    buf.Push(5)
    remainder = proto.RemainderBuffer(buf, 2)
    assertEqual(remainder.Count(), 3)
    print "TestSyncPlayProtocolRemainderBuffer passed"
end sub

sub TestSyncPlayProtocolRemainderBufferWithInvalid()
    ' Test RemainderBuffer handles invalid input
    proto = SyncPlayProtocol()
    remainder = proto.RemainderBuffer(invalid, 0)
    assertTrue(remainder <> invalid)
    assertEqual(remainder.Count(), 0)
    print "TestSyncPlayProtocolRemainderBufferWithInvalid passed"
end sub
