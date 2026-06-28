' components/SyncPlayTask.brs
'
' ===========================================
' SyncPlayTask - long-lived SceneGraph Task owning the hand-rolled WebSocket
' SyncPlay connection. Socket I/O MUST be off the render thread, so the whole
' connection lives here on its own task thread running a single wait() loop on a
' SHARED roMessagePort that receives BOTH:
'   - roSocketEvent      (the roStreamSocket is readable)
'   - roSGNodeEvent      (the scene wrote m.top.command, observed into the port)
' A wait(PING_INTERVAL_MS, port) returning invalid = the periodic tick -> send a
' time_ping.
'
' THREAD RULE: this code runs on the task thread. It may ONLY read m.top.config /
' m.top.command and WRITE m.top.event / m.top.connectionState. It must NEVER
' touch UI/parent nodes. Only assocarray/string/number cross the boundary.
'
' Roku platform: roStreamSocket is PLAINTEXT TCP - no TLS - so this speaks ws://
' only (never wss://). See worklog §2 + README. Built to the canonical FLAT
' syncplay_* wire (worklog §1); the server WS worker is unmerged so this is
' DEVICE-UNVERIFIABLE.
' ===========================================

sub Init()
    m.top.functionName = "RunSocket"
end sub

' Periodic time_ping cadence (ms). Also the wait() timeout that drives the tick.
function PingIntervalMs() as Integer
    return 4000
end function

sub RunSocket()
    cfg = m.top.config
    if cfg = invalid then
        EmitError("No SyncPlay config")
        return
    end if

    host = ""
    port = 8097
    path = "/syncplay"
    if cfg.DoesExist("host") and cfg.host <> invalid then host = cfg.host
    if cfg.DoesExist("port") and cfg.port <> invalid then port = Int(cfg.port)
    if cfg.DoesExist("path") and cfg.path <> invalid then path = cfg.path

    if host = "" then
        EmitError("No SyncPlay host")
        return
    end if

    m.proto = SyncPlayProtocol()
    m.yourId = ""
    m.lastPingT1 = 0&
    m.buffer = CreateObject("roByteArray")
    m.handshakeDone = false
    m.handshakeText = ""

    SetState("connecting")

    ' Shared port: socket events AND the observed `command` field both arrive here.
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("command", m.port)

    ' Open the plaintext TCP socket.
    m.sock = CreateObject("roStreamSocket")
    if m.sock = invalid then
        EmitError("Socket unavailable")
        Cleanup()
        return
    end if
    m.sock.SetMessagePort(m.port)

    addr = CreateObject("roSocketAddress")
    addr.SetHostName(host)
    addr.SetPort(port)
    m.sock.SetSendToAddress(addr)
    m.sock.NotifyReadable(true)
    m.sock.NotifyWritable(true)

    ok = m.sock.Connect()
    if not ok then
        EmitError("Connect failed")
        Cleanup()
        return
    end if

    ' Wait (bounded) for the socket to become connected, then send the handshake.
    if not WaitForConnect(host, port, path) then
        EmitError("Connect timed out")
        Cleanup()
        return
    end if

    ' Main loop: tick (time_ping) on timeout, else dispatch socket/command events.
    running = true
    while running
        msg = wait(PingIntervalMs(), m.port)

        if msg = invalid then
            ' Periodic tick: send a time_ping (only once the handshake completed).
            if m.handshakeDone then SendTimePing()
        else if type(msg) = "roSocketEvent" then
            if not HandleSocketEvent() then running = false
        else if type(msg) = "roSGNodeEvent" then
            if msg.getField() = "command" then
                if not HandleCommand(msg.getData()) then running = false
            end if
        end if
    end while

    Cleanup()
end sub

' Block (bounded) until the socket reports connected, then send the WS upgrade
' request and read until "\r\n\r\n", validating the 101 response. Returns true on
' a successful upgrade. Runs ONLY at startup (before the main loop).
function WaitForConnect(host as String, port as Integer, path as String) as Boolean
    ' Up to ~10s for the TCP connect to complete.
    deadline = 0
    while deadline < 100
        if m.sock.IsConnected() then exit while
        ' Drain any writable/readable notification; ignore - we only poll.
        ev = wait(100, m.port)
        if type(ev) = "roSGNodeEvent" then
            ' Buffer a pre-connect command (e.g. a "close") - re-dispatch later by
            ' ignoring here; the scene only sends commands after "open" in
            ' practice, so this is defensive.
        end if
        deadline = deadline + 1
    end while

    if not m.sock.IsConnected() then return false

    ' The socket is connected: stop writable notifications so the loop is not woken
    ' for would-block writes; keep readable on for the handshake + frame reads.
    m.sock.NotifyWritable(false)

    ' Send the upgrade request.
    keyB64 = m.proto.NewWebSocketKey()
    req = m.proto.BuildHandshakeRequest(host, port, path, keyB64)
    sent = m.sock.SendStr(req)
    if sent < 0 then return false

    ' Read the HTTP response into a BYTE accumulator and locate the "\r\n\r\n"
    ' header terminator BY BYTES (0x0D 0x0A 0x0D 0x0A). The 101 response and the
    ' first WS frame can arrive in the SAME TCP segment, and a frame byte >=0x80
    ' would be mangled if round-tripped through an ASCII String - so we validate
    ' the header (ASCII) on its byte slice and append the BYTE remainder directly
    ' to the frame accumulator (never through a String).
    headerBytes = CreateObject("roByteArray")
    termIdx = -1
    tries = 0
    while tries < 100
        ev = wait(100, m.port)
        if type(ev) = "roSocketEvent" then
            chunk = CreateObject("roByteArray")
            n = m.sock.Receive(chunk, 0, 4096)
            if n > 0 then
                headerBytes.Append(chunk)
                termIdx = FindHeaderTerminator(headerBytes)
                if termIdx >= 0 then exit while
            else if n = 0 then
                ' Peer closed during handshake.
                return false
            end if
        end if
        tries = tries + 1
    end while

    if termIdx < 0 then return false

    ' Header portion = bytes [0 .. termIdx+3] (the 4 terminator bytes inclusive);
    ' header is ASCII so ToAsciiString of just the header slice is safe.
    headerText = HeaderSliceToString(headerBytes, termIdx + 4)
    if not m.proto.HandshakeAccepted(headerText) then return false

    ' Byte remainder = everything AFTER the 4 terminator bytes -> the first WS
    ' frame bytes. Append raw to the frame accumulator (no String round-trip).
    AppendRemainderBytes(headerBytes, termIdx + 4)

    m.handshakeDone = true
    SetState("open")
    EmitEvent({ kind: "open" })
    ' Prime the time-sync with an immediate ping.
    SendTimePing()
    return true
end function

' Locate the first "\r\n\r\n" (0x0D 0x0A 0x0D 0x0A) in a byte accumulator. Returns
' the index of the FIRST terminator byte (0x0D), or -1 if not yet present.
function FindHeaderTerminator(ba as Object) as Integer
    if ba = invalid then return -1
    total = ba.Count()
    if total < 4 then return -1
    i = 0
    last = total - 4
    while i <= last
        if ba[i] = 13 and ba[i + 1] = 10 and ba[i + 2] = 13 and ba[i + 3] = 10 then
            return i
        end if
        i = i + 1
    end while
    return -1
end function

' ASCII-decode the first `count` bytes of a byte accumulator (the HTTP header is
' ASCII, so this is safe; we never decode frame payload bytes this way).
function HeaderSliceToString(ba as Object, count as Integer) as String
    slice = CreateObject("roByteArray")
    i = 0
    while i < count and i < ba.Count()
        slice.Push(ba[i])
        i = i + 1
    end while
    return slice.ToAsciiString()
end function

' Append the byte remainder (everything from `startIdx` to the end) of the
' handshake accumulator DIRECTLY to the frame accumulator m.buffer - the first WS
' frame bytes, never round-tripped through a String.
sub AppendRemainderBytes(ba as Object, startIdx as Integer)
    total = ba.Count()
    i = startIdx
    while i < total
        m.buffer.Push(ba[i])
        i = i + 1
    end while
end sub

' Read available bytes, parse complete frames, route each. Returns false when the
' connection should close (server close frame). Returns true otherwise.
function HandleSocketEvent() as Boolean
    chunk = CreateObject("roByteArray")
    n = m.sock.Receive(chunk, 0, 4096)
    if n < 0 then
        ' Would-block / transient - keep going.
        return true
    else if n = 0 then
        ' Peer closed.
        SetState("closed")
        EmitEvent({ kind: "closed" })
        return false
    end if

    m.buffer.Append(chunk)

    res = m.proto.ParseFrames(m.buffer)
    if res.consumed > 0 then
        m.buffer = m.proto.RemainderBuffer(m.buffer, res.consumed)
    end if

    ' A single Receive can yield MULTIPLE complete frames. Rapid same-field writes
    ' to m.top.event can coalesce under SceneGraph, so collect ALL scene events
    ' from this pass and emit ONE batch field write at the end. Control-frame
    ' responses (pong) and connectionState writes stay direct.
    pending = []
    closed = false

    for each frame in res.frames
        op = frame.opcode
        if op = m.proto.OP_CLOSE then
            closed = true
            exit for
        else if op = m.proto.OP_PING then
            ' Echo the payload bytes in a pong (direct, not batched).
            pong = m.proto.BuildPongFrame(frame.payloadBytes)
            m.sock.Send(pong, 0, pong.Count())
        else if op = m.proto.OP_PONG then
            ' Ignore unsolicited pongs.
        else if op = m.proto.OP_TEXT then
            one = BuildSceneEvent(frame.payload)
            if one <> invalid then pending.Push(one)
        end if
    end for

    ' Flush collected events as a single batch (the scene loops .items).
    if pending.Count() = 1 then
        EmitEvent(pending[0])
    else if pending.Count() > 1 then
        EmitEvent({ kind: "batch", items: pending })
    end if

    if closed then
        SetState("closed")
        EmitEvent({ kind: "closed" })
        return false
    end if

    return true
end function

' Decode one text frame and BUILD the corresponding scene-event assoc (returned to
' the caller, which batches all events from one ParseFrames pass into a single
' field write). Returns invalid for an undecodable / unhandled frame. Side effects
' that must happen at decode time (TimeSync.AddPong, learning our member id) run
' here.
function BuildSceneEvent(jsonText as String) as Object
    msg = m.proto.Decode(jsonText)
    if msg = invalid then return invalid
    if not msg.DoesExist("type") then return invalid
    t = msg.type
    if type(t) <> "String" and type(t) <> "roString" then return invalid

    if t = "syncplay_time_pong" then
        ' t1 echoed client_time, t2 server_time (server receive). t4 = NowMs().
        t1 = ReadLong(msg, "client_time", m.lastPingT1)
        t2 = ReadLong(msg, "server_time", 0&)
        m.proto.AddPong(t1, t2, NowMs())
        return { kind: "timesync", offset: m.proto.GetOffset(), stable: m.proto.IsStable() }

    else if t = "syncplay_group_state" then
        yourId = ""
        if msg.DoesExist("your_id") and msg.your_id <> invalid then yourId = StringifyId(msg.your_id)
        m.yourId = yourId
        group = invalid
        if msg.DoesExist("group") and type(msg.group) = "roAssociativeArray" then group = msg.group
        return { kind: "group_state", group: group, your_id: yourId }

    else if t = "syncplay_playback_play" or t = "syncplay_playback_pause" or t = "syncplay_playback_seek" then
        memberId = ""
        if msg.DoesExist("member_id") and msg.member_id <> invalid then memberId = StringifyId(msg.member_id)
        positionMs = ReadLong(msg, "position", 0&)
        toMs = ReadLong(msg, "to_position", 0&)
        serverTimeMs = ReadLong(msg, "server_time", NowMs())

        ' Precompute the drift-corrected position so the scene can apply directly.
        ' For a seek the authoritative target is to_position; for play/pause it is
        ' position. We adjust the relevant one.
        basePos = positionMs
        if t = "syncplay_playback_seek" then basePos = toMs
        adjusted# = m.proto.GetAdjustedPositionMs(basePos, serverTimeMs)

        return {
            kind: "playback"
            type: t
            member_id: memberId
            position_ms: positionMs
            to_ms: toMs
            server_time_ms: serverTimeMs
            adjusted_ms: adjusted#
        }

    else if t = "syncplay_info" then
        ev = { kind: "info", message: ReadStr(msg, "message", "") }
        if msg.DoesExist("member_id") and msg.member_id <> invalid then ev.member_id = StringifyId(msg.member_id)
        if msg.DoesExist("member_name") and msg.member_name <> invalid then ev.member_name = ReadStr(msg, "member_name", "")
        return ev

    else if t = "syncplay_host_elect" then
        electedId = ""
        if msg.DoesExist("elected_id") and msg.elected_id <> invalid then electedId = StringifyId(msg.elected_id)
        return { kind: "host_elect", elected_id: electedId }

    else if t = "syncplay_error" then
        ' SP2 emits error_code; read it for logging, fall back to code.
        codeStr = ""
        if msg.DoesExist("error_code") and msg.error_code <> invalid then
            codeStr = StringifyId(msg.error_code)
        else if msg.DoesExist("code") and msg.code <> invalid then
            codeStr = StringifyId(msg.code)
        end if
        print "SyncPlay error_code: " + codeStr
        return { kind: "error", message: ReadStr(msg, "message", "SyncPlay error") }
    end if

    return invalid
end function

' Handle a scene->task command. Returns false when the loop should exit (close).
function HandleCommand(cmd as Object) as Boolean
    if cmd = invalid then return true
    if not cmd.DoesExist("kind") then return true
    kind = cmd.kind

    if kind = "create" then
        groupName = ""
        if cmd.DoesExist("group_name") and cmd.group_name <> invalid then groupName = cmd.group_name
        payload = { group_name: groupName }
        AddMemberName(payload)
        SendMessage("syncplay_group_create", payload)

    else if kind = "join" then
        groupId = ""
        if cmd.DoesExist("group_id") and cmd.group_id <> invalid then groupId = StringifyId(cmd.group_id)
        payload = { group_id: groupId }
        AddMemberName(payload)
        SendMessage("syncplay_group_join", payload)

    else if kind = "leave" then
        ' Best-effort leave then close the socket.
        SendMessage("syncplay_group_leave", { group_id: GroupIdOf(cmd), member_id: m.yourId })
        SendCloseAndDie()
        return false

    else if kind = "play" then
        posMs = 0&
        if cmd.DoesExist("position_ms") and cmd.position_ms <> invalid then posMs = cmd.position_ms
        SendMessage("syncplay_playback_play", { group_id: GroupIdOf(cmd), member_id: m.yourId, position: posMs, server_time: NowMs() })

    else if kind = "pause" then
        posMs = 0&
        if cmd.DoesExist("position_ms") and cmd.position_ms <> invalid then posMs = cmd.position_ms
        SendMessage("syncplay_playback_pause", { group_id: GroupIdOf(cmd), member_id: m.yourId, position: posMs, server_time: NowMs() })

    else if kind = "seek" then
        fromMs = 0&
        toMs = 0&
        if cmd.DoesExist("from_ms") and cmd.from_ms <> invalid then fromMs = cmd.from_ms
        if cmd.DoesExist("to_ms") and cmd.to_ms <> invalid then toMs = cmd.to_ms
        SendMessage("syncplay_playback_seek", { group_id: GroupIdOf(cmd), member_id: m.yourId, from_position: fromMs, to_position: toMs, server_time: NowMs() })

    else if kind = "close" then
        SendCloseAndDie()
        return false
    end if

    return true
end function

' Pull an optional group_id from a command (the scene tracks the joined group id
' and may echo it; the server authorizes by connection regardless).
function GroupIdOf(cmd as Object) as String
    if cmd <> invalid and cmd.DoesExist("group_id") and cmd.group_id <> invalid then
        return StringifyId(cmd.group_id)
    end if
    return ""
end function

' Add member_name to an outbound payload from config.memberName when present.
sub AddMemberName(payload as Object)
    cfg = m.top.config
    if cfg <> invalid and cfg.DoesExist("memberName") and cfg.memberName <> invalid and cfg.memberName <> "" then
        payload.member_name = cfg.memberName
    end if
end sub

' Send a periodic time_ping (t1 = NowMs()).
sub SendTimePing()
    t1 = NowMs()
    m.lastPingT1 = t1
    SendMessage("syncplay_time_ping", { client_time: t1 })
end sub

' Encode + frame + send a SyncPlay message. No-op if the socket is gone.
sub SendMessage(typeStr as String, payload as Object)
    if m.sock = invalid then return
    json = m.proto.Encode(typeStr, payload)
    frame = m.proto.BuildTextFrame(json)
    m.sock.Send(frame, 0, frame.Count())
end sub

' Send a WS close frame, close the socket, emit closed.
sub SendCloseAndDie()
    if m.sock <> invalid then
        closeFrame = m.proto.BuildCloseFrame()
        m.sock.Send(closeFrame, 0, closeFrame.Count())
    end if
    SetState("closed")
    EmitEvent({ kind: "closed" })
end sub

' Read a possibly-numeric JSON field as a LongInteger with a default. Guards
' DoesExist + invalid; coerces via the numeric value (never an Integer<>String
' compare). A String value falls back to the default.
function ReadLong(msg as Object, key as String, dflt as LongInteger) as LongInteger
    if not msg.DoesExist(key) then return dflt
    v = msg[key]
    if v = invalid then return dflt
    tp = type(v)
    if tp = "Integer" or tp = "roInt" or tp = "LongInteger" or tp = "roLongInteger" or tp = "Float" or tp = "roFloat" or tp = "Double" or tp = "roDouble" then
        return v
    end if
    return dflt
end function

' Read a string JSON field with a default. Guards DoesExist + invalid + type.
function ReadStr(msg as Object, key as String, dflt as String) as String
    if not msg.DoesExist(key) then return dflt
    v = msg[key]
    if v = invalid then return dflt
    if type(v) = "String" or type(v) = "roString" then return v
    return dflt
end function

' Stringify an id that may arrive as a JSON number OR string (ids must never be
' concatenated raw - an Integer concat crashes). Returns "" for invalid.
function StringifyId(v as Object) as String
    if v = invalid then return ""
    tp = type(v)
    if tp = "String" or tp = "roString" then return v
    if tp = "Integer" or tp = "roInt" then return str(v).Trim()
    if tp = "LongInteger" or tp = "roLongInteger" then return (str(v)).Trim()
    if tp = "Float" or tp = "roFloat" or tp = "Double" or tp = "roDouble" then return str(Int(v)).Trim()
    return ""
end function

' Set m.top.connectionState (thread-safe field write).
sub SetState(s as String)
    m.top.connectionState = s
end sub

' Emit a task->scene event assoc.
sub EmitEvent(ev as Object)
    m.top.event = ev
end sub

' Emit an error event + error state.
sub EmitError(message as String)
    SetState("error")
    m.top.event = { kind: "error", message: message }
end sub

' Tear down: unobserve the command field, close the socket. Pairs the ObserveField
' from RunSocket.
sub Cleanup()
    m.top.UnObserveField("command")
    if m.sock <> invalid then
        m.sock.Close()
        m.sock = invalid
    end if
end sub
