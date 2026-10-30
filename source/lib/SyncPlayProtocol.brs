'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/SyncPlayProtocol.brs

' copyright 2026 Joe Huss
'

' @fileoverview SyncPlayProtocol - PURE BrightScript helpers for the Phlix
'   SyncPlay (watch-together) WebSocket protocol. NO I/O, NO UI, NO node access.
' @module SyncPlayProtocol
'
' @description
' This module is intentionally pure so it is reviewable on paper despite being
' un-runnable off-device. It provides three things:
'
'   1. A hand-rolled RFC6455 WebSocket framing codec. The Roku roStreamSocket is
'      a plaintext TCP byte stream with NO TLS and NO WebSocket layer, so we
'      build/parse frames ourselves. CLIENT frames are MASKED (RFC6455 §5.3
'      requires every client->server frame to be masked); SERVER frames arrive
'      unmasked. Opcodes used: text 0x1, close 0x8, ping 0x9, pong 0xA. Length
'      encodings: <126 inline | 126 -> 2-byte big-endian | 127 -> 8-byte BE.
'
'   2. The canonical FLAT SyncPlay JSON codec (Encode/Decode). Every SyncPlay
'      message is a single flat JSON object: { type:"syncplay_<name>",
'      protocol_version:1, timestamp:<ms>, ...payload }. Decode also defensively
'      unwraps a legacy {type,data} envelope (pre-SP2 server) so an old frame
'      still decodes.
'
'   3. An NTP-style TimeSync sub-object (offset + drift), milliseconds scale,
'      implementing the @phlix/syncplay SPEC §5 algorithm exactly.
'
' All positions/durations on the SyncPlay wire are MILLISECONDS; the Roku Video
' node uses SECONDS, so the SCENE converts at the boundary (this module stays ms).
'
' @example
' ```brightscript
' proto = SyncPlayProtocol()
' key = proto.NewWebSocketKey()
' offer = proto.BearerSubprotocolOffer(jwt)   ' -> "bearer, <jwt>" (two entries)
' headers = { "Sec-WebSocket-Protocol": offer }
' req = proto.BuildHandshakeRequest("192.168.1.5", 8097, "/syncplay", key, headers)
'   (the two-entry bearer subprotocol IS :8097 server law since phlix-server
'    424c14d0 - see docs/dev/WEBSOCKET_AUTH_CARRIERS.md; the legacy ?token=
'    query carrier is still accepted server-side TRANSITIONALLY for older
'    builds but this client no longer emits it)
' frame = proto.BuildTextFrame(proto.Encode("syncplay_time_ping", { client_time: NowMs() }))
' ```

function SyncPlayProtocol() as Object
    obj = {
        ' Protocol constants.
        PROTOCOL_VERSION: 1
        OP_TEXT: 1
        OP_CLOSE: 8
        OP_PING: 9
        OP_PONG: 10

        ' [minors W-min95 M-ROKU-24/M-ROKU-39, review roku__exploiter m3 /
        ' roku__secnet m3] the two accumulator ceilings, canonical here so
        ' BOTH WS consumers (SyncPlayTask, HubCommandTask) and this module's
        ' own ParseFrames quote ONE source of truth:
        '   MaxHandshakeHeaderBytes - the HTTP 101 handshake must terminate
        '     within this many bytes; more pre-terminator data is a drip-fed
        '     garbage stream and the dial is refused.
        '   MaxFrameBytes - the estate frame maximum. A declared payload
        '     beyond it is rejected (W-min93, review roku__crossfe m8); an
        '     INCOMPLETE accumulator that grows past frame-max + headroom
        '     can never complete honestly, so the socket is dropped instead
        '     of buffering forever.
        MaxHandshakeHeaderBytes: 65536
        MaxFrameBytes: 1048576

        ' Bearer credential carrier law: the marker subprotocol offered FIRST in
        ' the two-entry Sec-WebSocket-Protocol handshake (["bearer", <jwt>]).
        ' Mirrors SyncPlayAuthMiddleware::BEARER_SUBPROTOCOL on the server.
        BEARER_SUBPROTOCOL: "bearer"

        ' RFC6455 §1.3 magic GUID: concatenated to the offered Sec-WebSocket-Key
        ' before the SHA-1 whose Base64 the server must echo in
        ' Sec-WebSocket-Accept (VerifyHandshakeAccept, M-ROKU-14). Fixed by the
        ' RFC — never a value either peer chooses.
        WS_ACCEPT_GUID: "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

        ' TimeSync tuning (see GetAdjustedPositionMs / AddPong).
        OFFSET_SAMPLE_COUNT: 5
        MAX_RTT: 1000
        DRIFT_MIN: 0.99
        DRIFT_MAX: 1.01
        DRIFT_FACTOR: 0.1

        ' TimeSync rolling state. timestamps stored as NowMs()/1000 (seconds).
        ' offsets[] keeps recent computed offsets (ms); rtts[] the matching rtts
        ' (ms); samples[] the {offset,timestamp} pairs used for drift. We keep at
        ' most 2*OFFSET_SAMPLE_COUNT entries (small rolling buffer).
        offsets: []
        rtts: []
        samples: []
        currentOffset: 0.0
        currentLatency: 0.0
        driftRate: 1.0

        ' -----------------------------------------------------------------
        ' WebSocket framing
        ' -----------------------------------------------------------------

        ' Build a MASKED client frame for the given opcode + payload bytes.
        ' FIN=1, byte0 = 0x80 OR opcode. The length byte carries the MASK bit
        ' (0x80). 4 random mask bytes follow, then payload XOR mask[i mod 4].
        ' @param opcode Integer - 0x1 text / 0x8 close / 0xA pong / ...
        ' @param payloadBA Object - an roByteArray (may be empty)
        ' @return Object - an roByteArray holding the complete frame
        BuildClientFrame: function(opcode as Integer, payloadBA as Object) as Object
            frame = CreateObject("roByteArray")

            payLen = 0
            if payloadBA <> invalid then payLen = payloadBA.Count()

            ' byte0: FIN + opcode.
            frame.Push(128 + opcode)

            ' Length encoding with the MASK bit (0x80) always set on the length
            ' byte (client frames are always masked).
            if payLen < 126 then
                frame.Push(128 + payLen)
            else if payLen < 65536 then
                frame.Push(128 + 126)
                frame.Push(Int(payLen / 256) and 255)
                frame.Push(payLen and 255)
            else
                ' 64-bit length. High 4 bytes are 0 in practice (payloads are tiny
                ' JSON), low 4 bytes carry the length big-endian.
                frame.Push(128 + 127)
                frame.Push(0)
                frame.Push(0)
                frame.Push(0)
                frame.Push(0)
                frame.Push((Int(payLen / 16777216)) and 255)
                frame.Push((Int(payLen / 65536)) and 255)
                frame.Push((Int(payLen / 256)) and 255)
                frame.Push(payLen and 255)
            end if

            ' 4 random mask bytes.
            mask = [m.RandomByte(), m.RandomByte(), m.RandomByte(), m.RandomByte()]
            frame.Push(mask[0])
            frame.Push(mask[1])
            frame.Push(mask[2])
            frame.Push(mask[3])

            ' Masked payload.
            if payLen > 0 then
                i = 0
                while i < payLen
                    frame.Push(m.XorByte(payloadBA[i], mask[i mod 4]))
                    i = i + 1
                end while
            end if

            return frame
        end function

        ' Build a masked text (opcode 0x1) frame from a UTF-8 string.
        BuildTextFrame: function(text as String) as Object
            ba = CreateObject("roByteArray")
            ba.FromAsciiString(text)
            return m.BuildClientFrame(m.OP_TEXT, ba)
        end function

        ' Build a masked close (opcode 0x8) frame with an empty payload.
        BuildCloseFrame: function() as Object
            empty = CreateObject("roByteArray")
            return m.BuildClientFrame(m.OP_CLOSE, empty)
        end function

        ' Build a masked pong (opcode 0xA) frame echoing the ping payload bytes.
        BuildPongFrame: function(payloadBA as Object) as Object
            return m.BuildClientFrame(m.OP_PONG, payloadBA)
        end function

        ' A pseudo-random byte 0..255 (Rnd(256) returns 1..256).
        RandomByte: function() as Integer
            return Rnd(256) - 1
        end function

        ' Bitwise XOR of two bytes. BrightScript has NO native `xor` operator, so
        ' it is composed from and/or/not: a XOR b = (a OR b) AND NOT (a AND b).
        ' Masked back to a single byte (0..255).
        XorByte: function(a as Integer, b as Integer) as Integer
            return ((a or b) and (not (a and b))) and 255
        end function

        ' Parse as many COMPLETE WebSocket frames as are present in the accumulator
        ' byte buffer. Returns { frames:[{opcode,payload}], consumed:<bytes> } where
        ' `consumed` is the number of leading bytes the caller should drop (the
        ' caller rebuilds the remainder buffer via RemainderBuffer). Text payloads
        ' are decoded to a String; non-text payloads (close/ping/pong) carry the
        ' raw roByteArray under `payloadBytes`. Server frames are unmasked; if the
        ' MASK bit happens to be set we still unmask defensively.
        ' @param buffer Object - the accumulator roByteArray
        ' @return Object - { frames:[...], consumed:Integer }
        ParseFrames: function(buffer as Object) as Object
            frames = []
            consumed = 0
            ' [W-min93 M-ROKU-16 (part), review roku__crossfe m8] a crafted/garbage
            ' 127-extended header used to overflow to a NEGATIVE payLen with plain
            ' Int math (b6 >= 128 * 16777216 walks off the integer range), letting
            ' frameEnd run backwards into buffer[-n] — runtime error. Declared
            ' lengths beyond the RFC's 2^31 bound or a sane SyncPlay maximum are
            ' now a REJECTION: no frame is produced and the caller closes.
            rejected = false
            total = 0
            if buffer <> invalid then total = buffer.Count()

            cur = 0
            keepGoing = true
            while keepGoing
                ' Need at least 2 bytes for the minimal header.
                if cur + 2 > total then
                    keepGoing = false
                else
                    byte0 = buffer[cur]
                    byte1 = buffer[cur + 1]
                    opcode = byte0 and 15
                    masked = (byte1 and 128) = 128
                    len = byte1 and 127

                    headerLen = 2
                    if len = 126 then
                        headerLen = 4
                    else if len = 127 then
                        headerLen = 10
                    end if

                    ' Need the full extended-length header.
                    if cur + headerLen > total then
                        keepGoing = false
                    else
                        ' Resolve the actual payload length.
                        payLen = len
                        if len = 126 then
                            payLen = (buffer[cur + 2] * 256) + buffer[cur + 3]
                            ' [W-min93 M-ROKU-16 (part), review roku__crossfe m8]
                            ' RFC6455 minimality + sane SyncPlay maximum bound.
                            if payLen < 126 or payLen > m.MaxFrameBytes then
                                rejected = true
                            end if
                        else if len = 127 then
                            ' [W-min93 M-ROKU-16 (part)] the OLD plain-Int math
                            ' overflowed to NEGATIVE payLen when b6 >= 128, letting
                            ' frameEnd walk backwards into buffer[-n] (runtime
                            ' error). 64-bit lengths are now consumed only with
                            ' zero high word, clear top bit, and a sane bound.
                            if buffer[cur + 2] <> 0 or buffer[cur + 3] <> 0 or buffer[cur + 4] <> 0 or buffer[cur + 5] <> 0 or (buffer[cur + 6] and 128) <> 0 then
                                rejected = true
                            else
                                payLen = (buffer[cur + 6] * 16777216) + (buffer[cur + 7] * 65536) + (buffer[cur + 8] * 256) + buffer[cur + 9]
                                if payLen > m.MaxFrameBytes then
                                    rejected = true
                                end if
                            end if
                        end if

                        maskLen = 0
                        if masked then maskLen = 4

                        frameEnd = cur + headerLen + maskLen + payLen
                        if rejected then
                            ' Hostile/garbage declared length: produce NOTHING,
                            ' tell the caller via rejectedOversize to close.
                            keepGoing = false
                        else if frameEnd > total then
                            ' Incomplete frame - wait for more bytes.
                            keepGoing = false
                        else
                            dataStart = cur + headerLen + maskLen
                            maskBytes = invalid
                            if masked then
                                maskBytes = [buffer[cur + headerLen], buffer[cur + headerLen + 1], buffer[cur + headerLen + 2], buffer[cur + headerLen + 3]]
                            end if

                            payBA = CreateObject("roByteArray")
                            i = 0
                            while i < payLen
                                b = buffer[dataStart + i]
                                if masked then b = m.XorByte(b, maskBytes[i mod 4])
                                payBA.Push(b)
                                i = i + 1
                            end while

                            frame = { opcode: opcode, payloadBytes: payBA }
                            if opcode = m.OP_TEXT then
                                frame.payload = payBA.ToAsciiString()
                            else
                                frame.payload = ""
                            end if
                            frames.Push(frame)

                            cur = frameEnd
                            consumed = cur
                        end if
                    end if
                end if
            end while

            return { frames: frames, consumed: consumed, rejectedOversize: rejected }
        end function

        ' Return a NEW roByteArray containing buffer[consumed..end]. roByteArray has
        ' no slice, so copy byte-by-byte. Used by the caller to retain the
        ' unparsed remainder after ParseFrames.
        ' @param buffer Object - the accumulator roByteArray
        ' @param consumed Integer - leading bytes to drop
        ' @return Object - the remainder roByteArray
        RemainderBuffer: function(buffer as Object, consumed as Integer) as Object
            out = CreateObject("roByteArray")
            if buffer = invalid then return out
            total = buffer.Count()
            i = consumed
            while i < total
                out.Push(buffer[i])
                i = i + 1
            end while
            return out
        end function

        ' -----------------------------------------------------------------
        ' Handshake
        ' -----------------------------------------------------------------

        ' A fresh Sec-WebSocket-Key: 16 random bytes -> base64.
        NewWebSocketKey: function() as String
            ba = CreateObject("roByteArray")
            i = 0
            while i < 16
                ba.Push(m.RandomByte())
                i = i + 1
            end while
            return ba.ToBase64String()
        end function

        ' The Sec-WebSocket-Protocol OFFER value carrying the bearer JWT: the
        ' TWO-ENTRY form "bearer, <jwt>" (marker entry first, credential entry
        ' second — NEVER the dotted single-entry 'bearer.<jwt>' shape). This is
        ' :8097 server law since phlix-server 424c14d0 (estate policy
        ' WEBSOCKET_URL_QUERY_REFUSED: the token must not ride the URL query;
        ' the server still accepts the legacy ?token= carrier TRANSITIONALLY
        ' for older builds, and rejects a handshake whose two carriers disagree).
        ' A JWT is base64url + dots — all RFC 7230 token chars — so it needs no
        ' encoding here. Returns "" for an empty token: the caller then sends NO
        ' offer header at all (an empty protocol-id entry is an illegal offer;
        ' the unauthenticated dial fails server-side exactly as an empty
        ' ?token= did before).
        ' @param token String - the bearer JWT ("" when absent)
        ' @return String - "bearer, <jwt>" or ""
        BearerSubprotocolOffer: function(token as String) as String
            if Len(token) = 0 then return ""
            return m.BEARER_SUBPROTOCOL + ", " + token
        end function

        ' Build the GET upgrade request string (CRLF-joined, trailing blank line).
        ' The path already carries the relay path (`/syncplay/{server_id}`, built
        ' by the caller). We send a valid random key; the caller validates the
        ' response with HandshakeAccepted (101 status line) AND
        ' VerifyHandshakeAccept (RFC6455 accept hash) before treating the
        ' socket as a session.
        ' `extraHeaders` is an OPTIONAL assocarray of { name: value } added
        ' verbatim before the terminating blank line — the sanctioned carriers
        ' live here: the hub relay puts `Authorization: Bearer <token>` on it
        ' (S298), and the :8097 SyncPlay dial puts the two-entry bearer
        ' subprotocol offer `Sec-WebSocket-Protocol: bearer, <jwt>` on it
        ' (BearerSubprotocolOffer; server law since phlix-server 424c14d0).
        ' @param host String - the server host
        ' @param port Integer - the plaintext WS port (8097 / 8804)
        ' @param path String - the request path
        ' @param keyB64 String - NewWebSocketKey()
        ' @param extraHeaders Object - optional { "Authorization": "Bearer x" }
        ' @return String - the raw request bytes to Send
        BuildHandshakeRequest: function(host as String, port as Integer, path as String, keyB64 as String, extraHeaders = invalid as Object) as String
            crlf = Chr(13) + Chr(10)
            hostHeader = host + ":" + str(port).Trim()
            req = "GET " + path + " HTTP/1.1" + crlf
            req = req + "Host: " + hostHeader + crlf
            req = req + "Upgrade: websocket" + crlf
            req = req + "Connection: Upgrade" + crlf
            req = req + "Sec-WebSocket-Key: " + keyB64 + crlf
            req = req + "Sec-WebSocket-Version: 13" + crlf
            if extraHeaders <> invalid then
                for each h in extraHeaders
                    req = req + h + ": " + extraHeaders[h] + crlf
                end for
            end if
            req = req + crlf
            return req
        end function

        ' True when the HTTP response indicates a successful upgrade (status 101).
        ' This is the STATUS-LINE gate only. The Sec-WebSocket-Accept hash has
        ' its own fail-closed check (VerifyHandshakeAccept below) — callers run
        ' BOTH before consuming the stream as a session (M-ROKU-14 cured the
        ' era that sent a key and accepted the 101 unverified).
        ' ECHO TOLERANCE: when the client OFFERED the bearer subprotocol the
        ' server answers the 101 with exactly one `Sec-WebSocket-Protocol:
        ' bearer` response header line (marker only, never the token — phlix-
        ' server 424c14d0). This check inspects ONLY the status-line prefix of
        ' the response, so any extra response headers — the echo included —
        ' neither affect it nor desync the byte-based header terminator scan in
        ' the caller. Do not harden this into strict header matching without
        ' re-proving the echo path.
        ' @param responseText String - the upgrade response text
        ' @return Boolean - true when the response begins "HTTP/1.1 101"
        HandshakeAccepted: function(responseText as String) as Boolean
            if responseText = invalid or responseText = "" then return false
            head = responseText
            if Len(head) > 64 then head = Left(head, 64)
            upper = UCase(head)
            if Instr(1, upper, "HTTP/1.1 101") > 0 then return true
            if Instr(1, upper, " 101 ") > 0 then return true
            return false
        end function

        ' Extract the Sec-WebSocket-Accept response header value: first line of
        ' the HEADER BLOCK (bytes before the first blank line — a body may never
        ' impersonate a header), name matched case-insensitively, value Trimmed.
        ' Returns "" when the header is absent.
        ' @param responseText String - the raw upgrade response header block
        ' @return String - the accept value, or "" when absent
        SecWebSocketAcceptValue: function(responseText as String) as String
            if responseText = invalid or responseText = "" then return ""
            nl = Chr(10)
            name = "sec-websocket-accept:"
            for each line in responseText.Split(nl)
                ' .Trim() removes the CR of each CRLF pair (and the padding
                ' around the value) before comparing — Trim() is an roString
                ' method, not a global.
                cut = line.Trim()
                ' The first blank line ENDS the header block. The handshake's
                ' CRLF-CRLF terminator arrives as an empty (or CR-only) entry
                ' here — Trim() makes both shapes testable the same way, and
                ' bare-LF terminations match too — so the scan stops there and
                ' a body line can never impersonate a header. (M-ROKU-14
                ' MAJOR-1: the earlier Instr(nl + nl) truncation was dead
                ' against CRLF bytes and never fired; this stop is what makes
                ' the docblock claim above true.)
                if cut = "" then exit for
                probe = UCase(Left(cut, Len(name)))
                if probe = UCase(name) then return Mid(cut, Len(name) + 1).Trim()
            end for
            return ""
        end function

        ' True when s is exactly 40 hexadecimal characters — the canonical
        ' output shape of ifEVPDigest.Process (hex ASCII of the SHA-1 digest).
        ' Internal helper for ExpectedSecWebSocketAccept's shape gate.
        IsHex40: function(s as String) as Boolean
            if s = invalid or s.Len() <> 40 then return false
            upper = UCase(s)
            for i = 1 to 40
                c = Mid(upper, i, 1)
                if not ((c >= "0" and c <= "9") or (c >= "A" and c <= "F")) then return false
            end for
            return true
        end function

        ' The RFC6455 §1.3 accept value an honest server must answer for the
        ' key we offered: Base64(SHA1(secKey + WS_ACCEPT_GUID)).
        ' The platform digest is roEVPDigest (ifEVPDigest contract, pinned
        ' from the Roku reference): Setup("sha1") returns 0 on success, and
        ' Process(roByteArray) returns the digest as a HEX STRING. Shape gate:
        ' exactly 40 hex chars, decoded via fromHexString and length-checked
        ' before ToBase64String. Any other shape — missing component, Setup
        ' refusal, junk output — yields "" and "" FAILS the caller's check
        ' (fail-closed): a device that cannot compute SHA-1 cannot prove the
        ' server saw our key, so the dial is refused rather than trusted
        ' blindly.
        ' @param secKey String - the offered Sec-WebSocket-Key (base64, 24 chars)
        ' @return String - the expected accept value (base64) or ""
        ExpectedSecWebSocketAccept: function(secKey as String) as String
            if secKey = invalid or secKey = "" then return ""
            evp = CreateObject("roEVPDigest")
            if evp = invalid then return ""
            if evp.Setup("sha1") <> 0 then return ""
            src = CreateObject("roByteArray")
            src.fromAsciiString(secKey + m.WS_ACCEPT_GUID)
            hexStr = evp.Process(src)
            if hexStr = invalid then return ""
            hexStr = hexStr.Trim()
            if not m.IsHex40(hexStr) then return ""
            hexba = CreateObject("roByteArray")
            hexba.fromHexString(hexStr)
            if hexba = invalid or hexba.Count() <> 20 then return ""
            return hexba.ToBase64String()
        end function

        ' Fail-CLOSED RFC6455 handshake proof: the server's Sec-WebSocket-Accept
        ' MUST equal Base64(SHA1(offered key + magic GUID)). An absent header, a
        ' non-computable expectation (no roEVPDigest / Setup refusal / empty key)
        ' or any mismatch returns false and the caller must tear the socket
        ' down. A blind LAN injector that forges a `101` status line cannot
        ' forge this hash without having seen our random key on the wire —
        ' exactly the passive-sniff class review roku__exploiter M3 named.
        ' base64 is case-sensitive: the comparison is verbatim.
        ' @param responseText String - the raw upgrade response header block
        ' @param secKey String - the Sec-WebSocket-Key offered in THIS handshake
        ' @return Boolean - true only when the accept value matches
        VerifyHandshakeAccept: function(responseText as String, secKey as String) as Boolean
            if secKey = invalid then return false
            offered = secKey.Trim()
            if offered = "" then return false
            got = m.SecWebSocketAcceptValue(responseText)
            if got = "" then return false
            expected = m.ExpectedSecWebSocketAccept(offered)
            if expected = "" then return false
            return got = expected
        end function

        ' -----------------------------------------------------------------
        ' SyncPlay flat JSON codec
        ' -----------------------------------------------------------------

        ' Encode a flat SyncPlay message: the payload fields plus type +
        ' protocol_version + timestamp at the TOP LEVEL. Returns the JSON string
        ' (feed to BuildTextFrame). A nil payload is treated as {}.
        ' @param typeStr String - "syncplay_<name>"
        ' @param payload Object - the flat payload assoc (may be invalid)
        ' @return String - the JSON text
        Encode: function(typeStr as String, payload as Object) as String
            msg = {}
            if payload <> invalid and type(payload) = "roAssociativeArray" then
                for each k in payload
                    msg[k] = payload[k]
                end for
            end if
            msg.type = typeStr
            msg.protocol_version = m.PROTOCOL_VERSION
            msg.timestamp = NowMs()
            return FormatJSON(msg)
        end function

        ' Decode a SyncPlay frame to a flat assoc (or invalid on parse failure).
        ' Defensively unwraps a legacy {type,data} envelope (pre-SP2 server): if a
        ' `data` assoc is present its fields are merged up to the top level so
        ' callers always read flat fields. Mirrors @phlix/syncplay decodeMessage.
        ' @param jsonText String - the frame text payload
        ' @return Object - the flat assoc, or invalid
        Decode: function(jsonText as String) as Object
            if jsonText = invalid or jsonText = "" then return invalid
            parsed = ParseJSON(jsonText)
            if parsed = invalid then return invalid
            if type(parsed) <> "roAssociativeArray" then return invalid

            ' Legacy envelope: lift {data:{...}} fields to the top level.
            if parsed.DoesExist("data") and type(parsed.data) = "roAssociativeArray" then
                flat = {}
                for each k in parsed
                    if k <> "data" then flat[k] = parsed[k]
                end for
                for each k in parsed.data
                    flat[k] = parsed.data[k]
                end for
                return flat
            end if

            return parsed
        end function

        ' -----------------------------------------------------------------
        ' TimeSync (NTP-style offset + drift, milliseconds scale)
        ' Implements @phlix/syncplay SPEC §5 exactly.
        ' -----------------------------------------------------------------

        ' Record a pong sample. t1=client_time(ms), t2=server_time(ms, server
        ' RECEIVE time; t3 == t2 since there is no separate server_receive field),
        ' t4=NowMs() at receipt. rtt = t4 - t1 - (t3 - t2) = t4 - t1. Rejects
        ' rtt<0 or rtt>MAX_RTT. offset = t2 - t1 + rtt/2. Keeps a rolling buffer of
        ' the last 2*OFFSET_SAMPLE_COUNT and recomputes the weighted-mean offset.
        ' @param t1 LongInteger - echoed client_time (ms)
        ' @param t2 LongInteger - server_time (ms)
        ' @param t4 LongInteger - local receive time (ms)
        AddPong: function(t1 as LongInteger, t2 as LongInteger, t4 as LongInteger) as Void
            rtt# = t4 - t1
            if rtt# < 0 then return
            if rtt# > m.MAX_RTT then return

            oneWay# = rtt# / 2.0
            offset# = (t2 - t1) + oneWay#

            ' Append to the rolling buffers (cap at 2*OFFSET_SAMPLE_COUNT).
            m.offsets.Push(offset#)
            m.rtts.Push(rtt#)
            cap = 2 * m.OFFSET_SAMPLE_COUNT
            while m.offsets.Count() > cap
                m.offsets.Delete(0)
                m.rtts.Delete(0)
            end while

            ' Drift sample: { offset, timestamp(seconds) }.
            nowSec# = NowMs() / 1000.0
            m.samples.Push({ offset: offset#, timestamp: nowSec# })
            while m.samples.Count() > cap
                m.samples.Delete(0)
            end while

            m.Recompute()
        end function

        ' Recompute currentOffset (weighted mean over the last OFFSET_SAMPLE_COUNT,
        ' weight 1/max(1,rtt)), currentLatency (mean of rtt/2), and the drift EMA.
        Recompute: function() as Void
            n = m.offsets.Count()
            if n = 0 then return

            ' Use the last OFFSET_SAMPLE_COUNT samples.
            startIdx = n - m.OFFSET_SAMPLE_COUNT
            if startIdx < 0 then startIdx = 0

            weightedSum# = 0.0
            weightTotal# = 0.0
            latencySum# = 0.0
            count = 0
            i = startIdx
            while i < n
                rtt# = m.rtts[i]
                w# = 1.0 / m.Max1(rtt#)
                weightedSum# = weightedSum# + (m.offsets[i] * w#)
                weightTotal# = weightTotal# + w#
                latencySum# = latencySum# + (rtt# / 2.0)
                count = count + 1
                i = i + 1
            end while

            if weightTotal# > 0 then m.currentOffset = weightedSum# / weightTotal#
            if count > 0 then m.currentLatency = latencySum# / count

            ' Drift EMA: driftRate = 1.0 + DRIFT_FACTOR*(offsetDelta/timeDelta)/1000
            ' (timeDelta in SECONDS), clamped to [DRIFT_MIN, DRIFT_MAX]. Needs >= 2
            ' drift samples.
            sc = m.samples.Count()
            if sc >= 2 then
                first = m.samples[sc - 2]
                last = m.samples[sc - 1]
                timeDelta# = last.timestamp - first.timestamp
                if timeDelta# > 0 then
                    offsetDelta# = last.offset - first.offset
                    raw# = 1.0 + m.DRIFT_FACTOR * (offsetDelta# / timeDelta#) / 1000.0
                    if raw# < m.DRIFT_MIN then raw# = m.DRIFT_MIN
                    if raw# > m.DRIFT_MAX then raw# = m.DRIFT_MAX
                    m.driftRate = raw#
                end if
            end if
        end function

        ' max(1, x) helper used for the 1/rtt weight.
        Max1: function(x as Double) as Double
            if x < 1.0 then return 1.0
            return x
        end function

        ' The current weighted-mean clock offset (ms): serverClock ~= localClock + offset.
        GetOffset: function() as Double
            return m.currentOffset
        end function

        ' The current mean one-way latency (ms).
        GetLatency: function() as Double
            return m.currentLatency
        end function

        ' Stable when we have >= OFFSET_SAMPLE_COUNT samples AND the variance of the
        ' recent offsets is < 50 (ms^2).
        IsStable: function() as Boolean
            n = m.offsets.Count()
            if n < m.OFFSET_SAMPLE_COUNT then return false

            startIdx = n - m.OFFSET_SAMPLE_COUNT
            if startIdx < 0 then startIdx = 0

            sum# = 0.0
            count = 0
            i = startIdx
            while i < n
                sum# = sum# + m.offsets[i]
                count = count + 1
                i = i + 1
            end while
            if count = 0 then return false
            mean# = sum# / count

            varSum# = 0.0
            i = startIdx
            while i < n
                d# = m.offsets[i] - mean#
                varSum# = varSum# + (d# * d#)
                i = i + 1
            end while
            variance# = varSum# / count

            return (variance# < 50.0)
        end function

        ' The current drift rate (clamped [0.99, 1.01]).
        GetDriftRate: function() as Double
            return m.driftRate
        end function

        ' Drift-correct a host position (ms) to where it should be NOW locally.
        '   synchronizedNow = NowMs() + offset
        '   adjusted = positionMs + (synchronizedNow - serverTimeMs) * driftRate
        ' The scene converts the result ms->seconds before video.seek.
        ' @param positionMs LongInteger - the host playback position (ms)
        ' @param serverTimeMs LongInteger - the server_time on that message (ms)
        ' @return Double - the drift-corrected local position (ms)
        GetAdjustedPositionMs: function(positionMs as LongInteger, serverTimeMs as LongInteger) as Double
            synchronizedNow# = NowMs() + m.currentOffset
            elapsed# = (synchronizedNow# - serverTimeMs) * m.driftRate
            return positionMs + elapsed#
        end function

        ' Clear all TimeSync state (on disconnect / leave).
        Reset: function() as Void
            m.offsets = []
            m.rtts = []
            m.samples = []
            m.currentOffset = 0.0
            m.currentLatency = 0.0
            m.driftRate = 1.0
        end function
    }

    ' Seed the RNG once so the WS mask keys (and Sec-WebSocket-Key) vary across
    ' runs. Rnd(0) reseeds from the system clock.
    Rnd(0)

    return obj
end function

' Module-level wall-clock milliseconds as a LongInteger. The `&` literal forces
' LongInteger arithmetic so the AsSeconds()*1000 term does not overflow a 32-bit
' Integer (~24.8 days past the epoch in seconds would overflow ms otherwise).
' @return LongInteger - current time in milliseconds since the epoch
function NowMs() as LongInteger
    dt = CreateObject("roDateTime")
    return (dt.AsSeconds() * 1000&) + dt.GetMilliseconds()
end function

' M-ROKU-11: channel identity for the WS DIAL sides. The two roSocket tasks
' (SyncPlayTask, HubCommandTask) hand-roll their TCP stacks on purpose and
' their component scopes deliberately exclude AppContext.brs (bsc resolves
' function calls per scope: AppContext's bodies reference ApiClient and
' LoadLocaleStrings, which those thin task scopes do not include). This leaf
' is the sanctioned escape from that scoping: it reads the SAME firmware
' primitive GetChannelVersion() reads - roAppInfo.GetVersion(), the stamped
' manifest major.minor.build - so the X-Phlix-Client-Version that rides the
' RFC6455 handshakes can never disagree with the REST header or the About
' screen. CHECK44 R3 pins both dial sites to this function; no task may send a
' literal version. Docs: ifappinfo (vendored in brighterscript's
' roku-types/data.json, CHECK37 surface law).
' @return String - e.g. "1.0.1"; "unknown" only if firmware returns nothing
function ProtocolChannelVersion() as String
    version = CreateObject("roAppInfo").GetVersion()
    if version = invalid or version = "" then return "unknown"
    return version
end function