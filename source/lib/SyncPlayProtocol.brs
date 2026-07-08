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
' req = proto.BuildHandshakeRequest("192.168.1.5", 8097, "/syncplay?token=x", key)
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
                        else if len = 127 then
                            ' 64-bit: high 4 bytes ignored (0 in practice); read
                            ' the low 4 bytes big-endian.
                            payLen = (buffer[cur + 6] * 16777216) + (buffer[cur + 7] * 65536) + (buffer[cur + 8] * 256) + buffer[cur + 9]
                        end if

                        maskLen = 0
                        if masked then maskLen = 4

                        frameEnd = cur + headerLen + maskLen + payLen
                        if frameEnd > total then
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

            return { frames: frames, consumed: consumed }
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

        ' Build the GET upgrade request string (CRLF-joined, trailing blank line).
        ' The path already carries the ?token=<access_token> query (built by the
        ' scene). We send a valid random key but do NOT verify the server's
        ' Sec-WebSocket-Accept hash (see HandshakeAccepted).
        ' @param host String - the server host
        ' @param port Integer - the plaintext WS port (8097)
        ' @param path String - "/syncplay?token=..."
        ' @param keyB64 String - NewWebSocketKey()
        ' @return String - the raw request bytes to Send
        BuildHandshakeRequest: function(host as String, port as Integer, path as String, keyB64 as String) as String
            crlf = Chr(13) + Chr(10)
            hostHeader = host + ":" + str(port).Trim()
            req = "GET " + path + " HTTP/1.1" + crlf
            req = req + "Host: " + hostHeader + crlf
            req = req + "Upgrade: websocket" + crlf
            req = req + "Connection: Upgrade" + crlf
            req = req + "Sec-WebSocket-Key: " + keyB64 + crlf
            req = req + "Sec-WebSocket-Version: 13" + crlf
            req = req + crlf
            return req
        end function

        ' True when the HTTP response indicates a successful upgrade (status 101).
        ' We accept on the "101" status line and do NOT verify the
        ' Sec-WebSocket-Accept SHA-1 hash (deferred - see worklog §3). A real MITM
        ' is out of scope for a LAN plaintext socket.
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
        ' Implements @phlix/syncplay SPEC §5 / worklog §1f exactly.
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