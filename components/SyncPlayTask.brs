'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/SyncPlayTask.brs

' copyright 2026 Joe Huss
'

'
' ===========================================
' SyncPlayTask - long-lived SceneGraph Task owning the hand-rolled WebSocket
' SyncPlay connection. Socket I/O MUST be off the render thread, so the whole
' connection lives here on its own task thread running a single wait() loop on a
' SHARED roMessagePort that receives BOTH:
'   - roSocketEvent      (the roStreamSocket is readable)
'   - roSGNodeEvent      (the scene wrote m.top.command, observed into the port)
' A wait(PING_INTERVAL_MS, port) returning invalid = the periodic tick -> send a
' time_ping. Since the MJ-8 era the thread OUTLIVES a transient drop: every
' dial runs inside a bounded reconnect ladder (the rung table is shared with
' HubCommandTask in source/lib/SyncPlayProtocol.brs) and the learned group is
' re-joined behind each fresh handshake; "closed"/"error" reach the scene only
' at true terminal or an explicit leave/close.
'
' THREAD RULE: this code runs on the task thread. It may ONLY read m.top.config /
' m.top.command and WRITE m.top.event / m.top.connectionState. It must NEVER
' touch UI/parent nodes. Only assocarray/string/number cross the boundary.
'
' Transport law (claims rotated to truth by M-ROKU-22): this component rides
' roStreamSocket - PLAINTEXT TCP, no TLS - so it speaks ws:// only and never
' dials wss://. That is a BUILD limitation, not a platform one: Roku's TLS
' client socket roSecureSocket exists and a wss migration stays a deferred
' option (docs/static-checks.md, Check 46 scope note). Custody therefore rests
' on the shipped law, never on the transport being unable to do TLS: an https
' server origin is refused UPSTREAM (PlayerScene.SyncPlayWsRefusedForOrigin —
' M-ROKU-14): the account JWT must never be offered on a cleartext handshake
' behind a TLS-restored origin. Once dialled, the 101 alone proves nothing:
' every session here additionally requires the RFC6455 Sec-WebSocket-Accept
' hash to match our offered key (SyncPlayProtocol.VerifyHandshakeAccept,
' fail-closed). Built to the canonical FLAT
' syncplay_* wire (README "Wire contract") against the MERGED + shipped :8097
' SyncPlay WS worker. Server law since phlix-server 424c14d0: dual-carrier handshake, the
' two-entry ['bearer', jwt] subprotocol preferred and the legacy ?token= query
' retiring. This task offers the bearer pair via the BearerSubprotocolOffer law
' in source/lib/SyncPlayProtocol.brs (carrier flip landed at 07eef68).
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
        EmitError("local.no_config")
        return
    end if

    host = ""
    port = 8097
    path = "/syncplay"
    bearerToken = ""
    if cfg.DoesExist("host") and cfg.host <> invalid then host = cfg.host
    if cfg.DoesExist("port") and cfg.port <> invalid then port = Int(cfg.port)
    if cfg.DoesExist("path") and cfg.path <> invalid then path = cfg.path
    ' The JWT rides the handshake (two-entry bearer subprotocol), NEVER the
    ' path query — estate policy WEBSOCKET_URL_QUERY_REFUSED, server law since
    ' phlix-server 424c14d0 (docs/dev/WEBSOCKET_AUTH_CARRIERS.md).
    if cfg.DoesExist("bearerToken") and cfg.bearerToken <> invalid then bearerToken = cfg.bearerToken

    if host = "" then
        EmitError("local.no_host")
        return
    end if

    m.proto = SyncPlayProtocol()
    m.yourId = ""
    m.lastPingT1 = 0&
    m.buffer = CreateObject("roByteArray")
    m.handshakeDone = false
    m.handshakeText = ""
    ' M-ROKU-14: set only when the upgrade got its 101 but the Sec-WebSocket-
    ' Accept proof failed — RunSocket reports that distinctly from a timeout.
    m.wsAcceptFailed = false

    SetState("connecting")

    ' Shared port: socket events AND the observed `command` field both arrive here.
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("command", m.port)

    ' MJ-6: a scene field-write BEFORE this attach produces no event and is
    ' never replayed - the first tap on a group used to be silently lost while
    ' the thread was still spawning. Funnel law: catch up on the field's
    ' current value here, drain port-queued command events in both pre-loop
    ' waits, and replay the funnel at the main-loop gate (after the handshake,
    ' so every command rides a live upgraded socket). A roSGNodeEvent carries
    ' the same AA reference the scene wrote, so BrightScript object identity on
    ' m.lastCommand dedups the write-between-attach-and-read micro-race exactly.
    m.pendingCommands = []
    m.lastCommand = invalid
    catchUp = m.top.command
    if catchUp <> invalid then m.pendingCommands.Push(catchUp)

    ' MJ-8 (review roku__asphp): the party leg must survive a transient drop.
    ' RunSocket was single-shot (one dead dial or one socket death ended the
    ' party permanently) while its sibling HubCommandTask shipped a full 5-rung
    ' ladder - the asymmetry WAS the defect. Ladder law below: every dial runs
    ' DialAndConsume; unexpected failures back off on the shared port with the
    ' SHARED rungs and re-dial, re-joining the learned group (m.replayCmd) so
    ' the scene contract stays open/closed-only.
    m.stopped = false
    m.attempt = 0
    m.needsRejoin = false
    m.replayCmd = invalid
    m.missedPings = 0
    m.wasEverOpen = false
    m.dialConnectFailed = false

    ' MJ-8: the open-whenever ladder - the shape its sibling has always shipped.
    ' A dial failure or socket death backs off on the shared port and re-dials;
    ' a command that arrives mid-backoff rides the funnel (see the local
    ' BackoffAndCheckSpent), and the learned group is re-joined behind every
    ' fresh handshake. Terminal reporting is DEFERRED to exhaustion so the
    ' scene keeps its honest open/closed law (MJ-7 stop custody unchanged).
    outcome = ""
    while not m.stopped
        if m.attempt > 0 then SetState("reconnecting")
        outcome = DialAndConsume(host, port, path, bearerToken)
        if m.stopped then exit while
        if outcome = "terminal" then exit while
        if outcome = "connected" then
            ' A full session lived since the last failure: the ladder restarts
            ' from rung 1 (a hub that accepts-then-drops still spends it).
            m.attempt = 0
            m.needsRejoin = true
        end if
        if BackoffAndCheckSpent() then exit while
    end while

    if not m.stopped then
        if outcome = "terminal" then
            EmitError("local.socket_unavailable")
        else if outcome = "connected" or m.wasEverOpen then
            ' Ladder spent AFTER a live connection: the party is genuinely
            ' over - the scene's closed arm owns the chrome reset (exactly the
            ' pre-MJ-8 socket-death contract, once the retries gave up).
            SetState("closed")
            EmitEvent({ kind: "closed" })
        else if m.wsAcceptFailed then
            ' The last dial got its 101 without the accept proof landing: the
            ' honest class stays separate from a timeout (M-ROKU-14).
            EmitError("local.ws_accept_invalid")
        else if m.dialConnectFailed then
            EmitError("local.connect_failed")
        else
            EmitError("local.connect_timeout")
        end if
    end if

    Cleanup()
end sub

' MJ-8: ONE dial lifecycle - socket (with OS keepalive), WS handshake, the
' post-handshake group re-join and funnel replay, then the consume loop.
' Returns:
'   "terminal"   no socket object at all (device class - honest terminal)
'   "dial"       connect or handshake failed (the ladder decides)
'   "connected"  a session lived and ended (re-dial must re-join the group)
function DialAndConsume(host as String, port as Integer, path as String, bearerToken as String) as String
    m.sock = CreateObject("roStreamSocket")
    if m.sock = invalid then return "terminal"
    m.sock.SetMessagePort(m.port)
    ' MJ-8 (review roku__asphp): OS-level keepalive probes were NEVER called
    ' on this socket - a black-holed route (packets vanish without RST) then
    ' hangs TCP-side; the pong watchdog below is the application-side partner.
    m.sock.SetKeepAlive(true)
    addr = CreateObject("roSocketAddress")
    addr.SetHostName(host)
    addr.SetPort(port)
    m.sock.SetSendToAddress(addr)
    m.sock.NotifyReadable(true)
    m.sock.NotifyWritable(true)
    ' Fresh dial, fresh framing state: the old buffer may hold half a frame
    ' from the dead connection (stale bytes would desync the new one), and
    ' the tick must not ping before THIS handshake completes.
    m.handshakeDone = false
    m.buffer = CreateObject("roByteArray")
    m.missedPings = 0
    ' MJ-12: a fresh dial's byte stream starts unfragmented.
    m.proto.fragOpcode = invalid
    m.proto.fragBytes = invalid
    m.dialConnectFailed = false
    if not m.sock.Connect() then
        m.dialConnectFailed = true
        m.sock.Close()
        m.sock = invalid
        return "dial"
    end if
    if not WaitForConnect(host, port, path, bearerToken) then
        m.sock.Close()
        m.sock = invalid
        return "dial"
    end if

    ' MJ-8: a re-dial RE-JOINS before anything else rides the new socket -
    ' group membership is per-connection on the server, so the party chrome
    ' and MJ-9's anchor adoption (through the fresh "open" event below) resume
    ' exactly as if the member had joined again. A failed re-join send leaves
    ' m.needsRejoin armed; the fresh socket will die fast and re-ladder.
    if m.replayCmd <> invalid and m.needsRejoin then
        m.yourId = ""
        if SendMessage(m.replayCmd.type, m.replayCmd.payload) then
            m.needsRejoin = false
        end if
    end if

    SetState("open")
    EmitEvent({ kind: "open" })
    m.wasEverOpen = true
    ' Prime the time-sync with an immediate ping.
    SendTimePing()

    ' MJ-6: replay the funnel in scene order now that the socket is upgraded.
    running = true
    while m.pendingCommands.Count() > 0 and running
        rc = m.pendingCommands.Shift()
        if rc <> m.lastCommand then
            m.lastCommand = rc
            if not HandleCommand(rc) then running = false
        end if
    end while

    ' Main loop: tick (time_ping) on timeout, else dispatch socket/command events.
    while running
        msg = wait(PingIntervalMs(), m.port)

        if msg = invalid then
            ' Periodic tick: send a time_ping (only once the handshake completed).
            if m.handshakeDone then
                if m.missedPings >= 3 then
                    ' MJ-8 pong watchdog: three consecutive ticks with no
                    ' syncplay_time_pong means the route is black-holed. Drop
                    ' the socket into the ladder instead of pinging into the
                    ' void for the TCP-retransmit horizon (review finding).
                    running = false
                else if not SendTimePing() then
                    ' MN-11: a send shortfall = a desynced stream. Same drop.
                    running = false
                end if
            end if
        else if type(msg) = "roSocketEvent" then
            if not HandleSocketEvent() then running = false
        else if type(msg) = "roSGNodeEvent" then
            if msg.getField() = "command" then
                ' MJ-6: identity dedup - the same write may have reached us
                ' through the catch-up read or a pre-loop drain already.
                cd = msg.getData()
                if cd <> m.lastCommand then
                    m.lastCommand = cd
                    if not HandleCommand(cd) then running = false
                end if
            end if
        end if
    end while
    return "connected"
end function

' Count one failure on the reconnect ladder, wait the SHARED rung on the
' shared port, and report whether the ladder is spent. Unlike the hub
' consumer's sibling, a command event arriving DURING the wait joins the
' MJ-6 funnel instead of executing immediately: the socket is down, and
' HandleCommand would consume the write into a dead SendMessage.
' @return Boolean - true when the RunSocket loop must stop
function BackoffAndCheckSpent() as Boolean
    if m.stopped then return true
    m.attempt = m.attempt + 1
    if m.attempt > SyncPlayMaxAttempts() then
        return true
    end if
    ev = wait(SyncPlayBackoffMs(m.attempt - 1), m.port)
    ' MJ-6 funnel law, third window (nested shape on purpose: Check 79
    ' counts the two PRE-LOOP drain arms by their single-line form).
    if type(ev) = "roSGNodeEvent" then
        if ev.GetField() = "command" then
            bc = ev.GetData()
            if bc <> invalid then m.pendingCommands.Push(bc)
        end if
    end if
    return m.stopped
end function

' Block (bounded) until the socket reports connected, then send the WS upgrade
' request and read until "\r\n\r\n", validating the 101 response AND the
' RFC6455 Sec-WebSocket-Accept proof (fail-closed; m.wsAcceptFailed tells the
' two classes apart for the caller). Returns true on a verified upgrade.
' Runs on EVERY ladder dial (the consume loop lives behind it in
' DialAndConsume - MJ-8 era).
' `bearerToken` is the JWT for the two-entry bearer subprotocol carrier
' ("Sec-WebSocket-Protocol: bearer, <jwt>" — :8097 server law since phlix-server
' 424c14d0); "" sends no offer (the dial then fails server-side unauthenticated,
' exactly as an empty ?token= did under the retired query carrier).
function WaitForConnect(host as String, port as Integer, path as String, bearerToken as String) as Boolean
    ' Fresh handshake attempt: the accept-proof flag speaks only for THIS dial.
    m.wsAcceptFailed = false
    ' Up to ~10s for the TCP connect to complete.
    deadline = 0
    while deadline < 100
        if m.sock.IsConnected() then exit while
        ' Drain any writable/readable notification; ignore - we only poll.
        ev = wait(100, m.port)
        if type(ev) = "roSGNodeEvent" and ev.GetField() = "command" then
            ' MJ-6: a command queued during the connect poll belongs to this
            ' session - funnel it for the post-handshake replay instead of
            ' discarding it. (The old 'the scene only sends commands after
            ' open' prose was false: the first tap IS this exact window.)
            dc = ev.GetData()
            if dc <> invalid then m.pendingCommands.Push(dc)
        end if
        deadline = deadline + 1
    end while

    if not m.sock.IsConnected() then return false

    ' The socket is connected: stop writable notifications so the loop is not woken
    ' for would-block writes; keep readable on for the handshake + frame reads.
    m.sock.NotifyWritable(false)

    ' Send the upgrade request. The JWT rides the two-entry bearer subprotocol
    ' offer header when present (SyncPlayProtocol.BearerSubprotocolOffer); an
    ' empty token sends no offer (illegal empty protocol-id) and the handshake
    ' then fails unauthenticated server-side.
    keyB64 = m.proto.NewWebSocketKey()
    ' M-ROKU-11: the channel version rides EVERY server dial, the raw RFC6455
    ' handshake included (extraHeaders is the sanctioned carrier - see
    ' SyncPlayProtocol.BuildHandshakeRequest). Firmware-derived via
    ' ProtocolChannelVersion (the roAppInfo.GetVersion() leaf this scope
    ' already includes - AppContext is deliberately NOT in task scope);
    ' unknown request headers are inert for the :8097 worker (it reads the
    ' specific fields it knows). CHECK44 R2 pins this site.
    extraHeaders = { "X-Phlix-Client-Version": ProtocolChannelVersion() }
    offer = m.proto.BearerSubprotocolOffer(bearerToken)
    if offer <> "" then
        extraHeaders.AddReplace("Sec-WebSocket-Protocol", offer)
    end if
    req = m.proto.BuildHandshakeRequest(host, port, path, keyB64, extraHeaders)
    sent = m.sock.SendStr(req)
    ' MJ-8/MN-11: a SHORT write desyncs the server-side parser exactly like
    ' a negative one (the upgrade request is one atomic message) - refuse
    ' the dial; the ladder re-sends it whole on a fresh socket.
    if sent < 0 or sent < req.Len() then return false

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
                ' [minors W-min95 M-ROKU-24, review roku__exploiter m3] a peer
                ' that drip-feeds without ever sending "\r\n\r\n" used to inflate
                ' this accumulator for the whole tries budget (~400KB). No
                ' honest 101 response exceeds the canonical header cap; refuse
                ' the dial beyond it instead of waiting the loop out.
                if headerBytes.Count() > m.proto.MaxHandshakeHeaderBytes then return false
                termIdx = FindHeaderTerminator(headerBytes)
                if termIdx >= 0 then exit while
            else if n = 0 then
                ' Peer closed during handshake.
                return false
            end if
        else if type(ev) = "roSGNodeEvent" and ev.GetField() = "command" then
            ' MJ-6: same funnel law while reading the 101 header.
            hc = ev.GetData()
            if hc <> invalid then m.pendingCommands.Push(hc)
        end if
        tries = tries + 1
    end while

    if termIdx < 0 then return false

    ' Header portion = bytes [0 .. termIdx+3] (the 4 terminator bytes inclusive);
    ' header is ASCII so ToAsciiString of just the header slice is safe.
    ' A bearer-offering handshake is answered with a `Sec-WebSocket-Protocol:
    ' bearer` echo line (phlix-server 424c14d0): HandshakeAccepted inspects only
    ' the status line and the byte-scan above keys off \r\n\r\n, so the echo is
    ' parsed and tolerated by design — never tighten this to exact-header
    ' matching without re-proving the echo path.
    headerText = HeaderSliceToString(headerBytes, termIdx + 4)
    if not m.proto.HandshakeAccepted(headerText) then return false

    ' M-ROKU-14 (review roku__exploiter M3): the 101 says a server answered;
    ' ONLY the accept hash says it saw OUR key. Fail-closed — an absent
    ' header, a non-computable expectation, or any mismatch refuses the dial
    ' before a single frame byte is treated as session traffic.
    if not m.proto.VerifyHandshakeAccept(headerText, keyB64) then
        m.wsAcceptFailed = true
        return false
    end if

    ' Byte remainder = everything AFTER the 4 terminator bytes -> the first WS
    ' frame bytes. Append raw to the frame accumulator (no String round-trip).
    AppendRemainderBytes(headerBytes, termIdx + 4)

    m.handshakeDone = true
    ' MJ-8: the open trio lives in DialAndConsume now - the group re-join
    ' must land behind the fresh handshake BEFORE the scene sees "open".
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
        ' Peer closed. MJ-8: the LADDER decides terminality - a death
        ' mid-session backs off and re-dials; "closed" reaches the scene only
        ' at exhaustion, so a transient drop never resets the party chrome.
        return false
    end if

    m.buffer.Append(chunk)

    res = m.proto.ParseFrames(m.buffer)
    ' [W-min93 M-ROKU-16 (part)] ParseFrames rejects declared lengths it cannot
    ' safely consume (negative-overflow / beyond-sane-max classes, review
    ' roku__crossfe m8). A rejection means the peer is desynced or hostile:
    ' drop the socket; the reconnect ladder (MJ-8 era) re-dials from a fresh
    ' handshake, and the scene's closed-arm chrome fires only at exhaustion.
    if res.rejectedOversize = true then
        ' MJ-8: desynced/hostile stream - drop into the ladder.
        return false
    end if
    if res.consumed > 0 then
        m.buffer = m.proto.RemainderBuffer(m.buffer, res.consumed)
    end if
    ' [minors W-min95 M-ROKU-39, review roku__secnet m3] a peer that declares an
    ' honest-looking frame then slow-drips it (or dribbles fewer bytes than a
    ' full 126/127 extended header, which ParseFrames cannot even reject yet)
    ' grew this accumulator WITHOUT bound between receives — ParseFrames bounds
    ' declared lengths, not arrival volume. The post-consumption residual of an
    ' honest stream is one incomplete frame (<= MaxFrameBytes + 14-byte header)
    ' plus at most one already-sent follow-on chunk; anything beyond that cap
    ' can never complete legitimately, so drop the socket; the ladder
    ' re-dials (MJ-8) and the scene sees "closed" only at exhaustion.
    if m.buffer.Count() > m.proto.MaxFrameBytes + 4096 + 64 then
        return false
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
            ' MN-11: a short pong write desyncs the stream - drop to the ladder.
            pong = m.proto.BuildPongFrame(frame.payloadBytes)
            sent = m.sock.Send(pong, 0, pong.Count())
            if sent < pong.Count() then return false
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
        ' MJ-8: the server said goodbye - the ladder re-dials (a
        ' rolling restart is exactly this frame); "closed" fires at exhaustion.
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
        ' MJ-15: t1 is OUR monotonic stamp echoed verbatim; t4 rides the same
        ' base, so rtt = t4 - t1 cannot be forged by an NTP step mid-flight.
        t1 = ReadLong(msg, "client_time", m.lastPingT1)
        t2 = ReadLong(msg, "server_time", 0&)
        m.proto.AddPong(t1, t2, m.proto.NowMonoMs())
        ' MJ-8: the route answered - the pong watchdog restarts.
        m.missedPings = 0
        return { kind: "timesync", offset: m.proto.GetOffset(), stable: m.proto.IsStable() }

    else if t = "syncplay_group_state" then
        yourId = ""
        if msg.DoesExist("your_id") and msg.your_id <> invalid then yourId = StringifyId(msg.your_id)
        m.yourId = yourId
        group = invalid
        if msg.DoesExist("group") and type(msg.group) = "roAssociativeArray" then group = msg.group
        ' MJ-8: upgrade the ladder's re-join payload to THIS server-learned
        ' group id the moment it arrives (a create must come back as a join;
        ' the group is only reachable by id on the next connection).
        if group <> invalid and m.replayCmd <> invalid then
            gid = ""
            if group.DoesExist("group_id") and group.group_id <> invalid then gid = StringifyId(group.group_id)
            if gid <> "" then
                replayPayload = { group_id: gid }
                AddMemberName(replayPayload)
                m.replayCmd = { type: "syncplay_group_join", payload: replayPayload }
            end if
        end if
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
        ' MN-22: only the bounded code alphabet may reach the log;
        ' message-sized wire text gets a count, never content.
        if IsErrorCodeToken(codeStr) then
            print "SyncPlay error_code: " + codeStr
        else
            print "SyncPlay error_code: <wire text " + Str(Len(codeStr)).Trim() + " chars suppressed>"
        end if
        ' W5 error-code-first: a recognized code resolves to the localized catalog
        ' line; the server message is only the debug fallback for unknown codes.
        ' Utilities.brs is in this component's script closure (SyncPlayTask.xml).
        localized = LocalizeSyncPlayError(codeStr, ReadStr(msg, "message", ""))
        ' M-ROKU-20: even the unknown-code fallback rides the catalog - the
        ' party banner is user-visible UI copy, not a debug line.
        if localized = "" then localized = Translate("player_party_error_fallback")
        return { kind: "error", message: localized }
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
        ' MJ-8: remember the join recipe the ladder must replay (the
        ' group_state arm upgrades a create to the learned id).
        m.replayCmd = { type: "syncplay_group_create", payload: payload }
        if not SendMessage("syncplay_group_create", payload) then return false

    else if kind = "join" then
        groupId = ""
        if cmd.DoesExist("group_id") and cmd.group_id <> invalid then groupId = StringifyId(cmd.group_id)
        payload = { group_id: groupId }
        AddMemberName(payload)
        ' MJ-2: a password-protected join presents the SPEC §4 digest, never
        ' the gate string itself (the plaintext never rides this socket). The
        ' scene computed it; a present-but-malformed carry is DROPPED here -
        ' the server refuses non-canonical shapes outright (fail-closed twice).
        if cmd.DoesExist("password_hash") and type(cmd.password_hash) = "roString" then
            if IsCanonicalPasswordHash(cmd.password_hash) then
                payload.password_hash = cmd.password_hash
            end if
        end if
        ' MJ-8: the ladder replays exactly this join after a re-dial.
        m.replayCmd = { type: "syncplay_group_join", payload: payload }
        if not SendMessage("syncplay_group_join", payload) then return false

    else if kind = "leave" then
        ' MJ-7/MJ-8: the goodbye is best-effort, the STOP is authoritative -
        ' m.stopped keeps the reconnect ladder from re-joining a left group.
        m.replayCmd = invalid
        m.stopped = true
        SendMessage("syncplay_group_leave", { group_id: GroupIdOf(cmd), member_id: m.yourId })
        SendCloseAndDie()
        return false

    else if kind = "play" then
        posMs = 0&
        if cmd.DoesExist("position_ms") and cmd.position_ms <> invalid then posMs = cmd.position_ms
        if not SendMessage("syncplay_playback_play", { group_id: GroupIdOf(cmd), member_id: m.yourId, position: posMs, server_time: NowMs() }) then return false

    else if kind = "pause" then
        posMs = 0&
        if cmd.DoesExist("position_ms") and cmd.position_ms <> invalid then posMs = cmd.position_ms
        if not SendMessage("syncplay_playback_pause", { group_id: GroupIdOf(cmd), member_id: m.yourId, position: posMs, server_time: NowMs() }) then return false

    else if kind = "seek" then
        fromMs = 0&
        toMs = 0&
        if cmd.DoesExist("from_ms") and cmd.from_ms <> invalid then fromMs = cmd.from_ms
        if cmd.DoesExist("to_ms") and cmd.to_ms <> invalid then toMs = cmd.to_ms
        if not SendMessage("syncplay_playback_seek", { group_id: GroupIdOf(cmd), member_id: m.yourId, from_position: fromMs, to_position: toMs, server_time: NowMs() }) then return false

    else if kind = "close" then
        ' MJ-8: latch the stop BEFORE the close - the ladder must never
        ' outlive an explicit scene close (Check 79's stop custody contract).
        m.replayCmd = invalid
        m.stopped = true
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

 ' Send the periodic time_ping (t1 = NowMonoMs(), MJ-15 - the server echoes
' client_time verbatim, so the base only has to be stable CLIENT-side).
' Skipped while not joined
 ' (m.yourId is set on group_state, confirming join). MJ-8: every SENT ping
 ' counts against the pong watchdog (BuildSceneEvent resets the counter when
 ' a syncplay_time_pong decodes); the return reports the MN-11 send custody
 ' so the main loop can drop a black-holed dial into the ladder.
 function SendTimePing() as Boolean
     if m.yourId = "" or m.yourId = invalid then return true
     t1 = m.proto.NowMonoMs()
    m.lastPingT1 = t1
    m.missedPings = m.missedPings + 1
    return SendMessage("syncplay_time_ping", { client_time: t1 })
end function

' Encode + frame + send a SyncPlay message. MJ-8/MN-11: TRUE ONLY ON A
' COMPLETE WRITE. roStreamSocket on a full non-blocking buffer returns a short
' count - the frame then sits half-emitted and desyncs the byte stream with no
' wire-level resync point, so a shortfall IS a dead socket: every caller
' routes false to the reconnect ladder. Gone-socket returns false for the
' same reason (the dial is already dying). SendCloseAndDie stays best-effort:
' it is the intentional-death path where the ladder is latched off.
function SendMessage(typeStr as String, payload as Object) as Boolean
    if m.sock = invalid then return false
    json = m.proto.Encode(typeStr, payload)
    frame = m.proto.BuildTextFrame(json)
    sent = m.sock.Send(frame, 0, frame.Count())
    return sent = frame.Count()
end function

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

' Emit an error event + error state for a CLIENT-GENERATED failure. The
' argument is a "local.*" census code (SyncPlayLocalErrorCodes in
' Utilities.brs), never a display literal and never a wire code - this task
' minted the string, so it resolves through the shared mapping law to an
' errors_local_* catalog line in the device language. Check 23 pins the
' call-site law; the wire family keeps its own route (LocalizeSyncPlayError
' in BuildSceneEvent, pinned by Check 22).
sub EmitError(code as String)
    SetState("error")
    m.top.event = { kind: "error", message: LocalizeSyncPlayLocalError(code) }
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