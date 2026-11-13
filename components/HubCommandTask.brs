' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/HubCommandTask.brs

' =============================================================================
' S298 — hub relay pending_command consumer (Roku half).
'
' The hub's SyncPlay relay (`ws://<hub>:8804/syncplay/{server_id}`) is the ONLY
' surface that can receive the "Alexa, play X" push (S93's pending_command). It
' validates a per-user, server-scoped RELAY TOKEN on the upgrade request — never
' the hub JWT, never a query string (S237). This leg rides roStreamSocket —
' plaintext TCP, no WebSocket layer — and behind an https:// hub origin a
' minted relay token must never cross cleartext, so this task:
'
'   1. MINTS a relay token: POST {apiBase}/api/v1/me/servers/{serverId}/relay-token
'      with the hub access JWT (the hub's own S2a mint endpoint).
'   2. CONNECTS to the relay with the token on the `Authorization: Bearer`
'      header — a raw RFC6455 handshake can carry any header, which is why the
'      Roku client uses the header carrier (the browser subprotocol carrier is
'      a web-only surface). The upgrade is PROVED before it is trusted
'      (R-ROKU-05): the 101 must carry Sec-WebSocket-Accept equal to
'      Base64(SHA1(our offered key + RFC6455 GUID)) — fail-closed via
'      SyncPlayProtocol.VerifyHandshakeAccept, the twin of the :8097 dial law.
'   3. CONSUMES only `pending_command` / `play_media` frames, forwarding them
'      to the scene as { kind: "pending_command", mediaId, title, ... }. Every
'      other relay frame (`group_join`, `playback_*`, `room_state`, ...) is
'      ignored — this socket is a command consumer, not a room participant.
'   4. LIFECYCLE: long-lived ("open whenever the app is open"), with a bounded
'      reconnect ladder (5 attempts, 1s/2s/4s/8s/16s) that RE-MINTS on every
'      attempt because relay tokens expire hourly. A { kind: "close" } command
'      stops the ladder.
'   5. ORIGIN LAW (M-ROKU-23, review roku__secnet M2): an https:// hub origin
'      REFUSES this plaintext dial — at the scene choke (StartHubCommand
'      Consumer) and again here (defense in depth) — so a token minted over a
'      TLS lane can never silently ride cleartext. Plaintext :8804 serves
'      http/legacy hubs, whose REST lane is already cleartext (no NEW exposure
'      class). The wss variant via roSecureSocket is DEFERRED with disclosure,
'      not a platform impossibility (the hub's TLS front-end routes GET
'      /syncplay/ to the worker today — phlix-hub docs/websockets.md; the
'      client leg awaits on-device API verification, mirroring the
'      :8097-leg law as of edbbd8a).
'
' THREAD RULE: this code runs on the task thread. It may ONLY read m.top.config,
' observe m.top.command, and write m.top.event / m.top.connectionState. The
' scene owns navigation.
' =============================================================================

sub Init()
    m.top.functionName = "RunConsumer"
end sub

' MJ-8 (review roku__asphp asymmetry finding): the reconnect rungs moved to
' source/lib/SyncPlayProtocol.brs (SyncPlayBackoffMs / SyncPlayMaxAttempts) so
' the syncplay party leg ladders with EXACTLY this law - the table was
' HubCommandTask-only, and the sibling single-shot dial was the defect.
' Mirror of the ui's capped ladder: 5 rungs then give up.

sub RunConsumer()
    cfg = m.top.config
    if cfg = invalid then
        SetState("closed")
        return
    end if

    host = ""
    port = 8804
    apiBase = ""
    serverId = ""
    token = ""
    if cfg.DoesExist("host") and cfg.host <> invalid then host = cfg.host
    if cfg.DoesExist("port") and cfg.port <> invalid then port = Int(cfg.port)
    if cfg.DoesExist("apiBase") and cfg.apiBase <> invalid then apiBase = cfg.apiBase
    if cfg.DoesExist("serverId") and cfg.serverId <> invalid then serverId = cfg.serverId
    if cfg.DoesExist("token") and cfg.token <> invalid then token = cfg.token

    ' [MJ-18] Guard-contract trim BEFORE the emptiness gate: a whitespace-only
    ' id must be refused as empty, not survive to the mint composition.
    if serverId <> "" then serverId = serverId.Trim()
    if host = "" or apiBase = "" or serverId = "" or token = "" then
        SetState("closed")
        return
    end if

    ' [MJ-18, review roku__secnet] task-side path-law choke (defense in depth -
    ' the picker refuses first and GetActiveServerId degrades at read): the
    ' serverId interpolates verbatim into the mint URL and the WS upgrade
    ' request line, and ParseJSON hands back real CRLF for hub-supplied
    ' escapes. Anything outside the M-ROKU-13 shape is an honest terminal
    ' "closed" - no mint, no bearer on a forged path.
    if not IsSafeContentId(serverId) then
        SetState("closed")
        return
    end if

    ' M-ROKU-23 task-side origin choke (defense in depth — the scene refuses
    ' first): a config whose hub origin is https:// must never dial this
    ' plaintext socket. No mint, no ladder, no cleartext bearer.
    if HubRelayCleartextRefusedForOrigin(apiBase) then
        SetState("closed")
        return
    end if

    m.proto = SyncPlayProtocol()
    m.buffer = CreateObject("roByteArray")
    m.handshakeDone = false
    m.handshakeText = ""
    m.attempt = 0
    m.stopped = false
    ' MN-14: this dial's decoded-command queue (ONE field write per recv pass).
    m.pendingEvents = []

    ' Shared port: socket events, url-transfer events AND the observed
    ' `command` field all arrive here.
    m.port = CreateObject("roMessagePort")
    m.top.ObserveField("command", m.port)

    ' The open-whenever loop: connect, consume, and on any failure back off and
    ' retry (re-minting the relay token each attempt) until the ladder is spent
    ' or the scene sends a close.
    while not m.stopped
        if m.attempt > 0 then SetState("reconnecting")
        if not MintAndConnect(host, port, apiBase, serverId, token) then
            ' Connect/mint failure — ladder it.
            if BackoffAndCheckSpent() then exit while
        else
            ' Connected + handshake done: consume frames until the socket dies
            ' or the scene sends a close.
            m.attempt = 0
            running = true
            while running and not m.stopped
                msg = wait(4000, m.port)
                if msg = invalid then
                    ' Idle tick — nothing to do: the hub pushes, we never poll.
                else if type(msg) = "roSocketEvent" then
                    if not HandleSocketEvent() then running = false
                else if type(msg) = "roSGNodeEvent" then
                    if not HandleCommand(msg.getData()) then running = false
                end if
            end while
            ' The socket DIED (not a scene close): count the drop as a ladder
            ' attempt and back off before re-minting, so a hub that accepts then
            ' drops connections cannot be hammered by mint+connect cycles.
            if BackoffAndCheckSpent() then exit while
        end if
    end while

    Cleanup()
end sub

' Count one failure on the reconnect ladder, wait the backoff on the shared port
' (a "close" command interrupts the wait), and report whether the ladder is
' spent or the scene asked to stop.
' @return Boolean - true when the loop should stop (ladder spent or close)
function BackoffAndCheckSpent() as Boolean
    if m.stopped then return true
    m.attempt = m.attempt + 1
    if m.attempt > SyncPlayMaxAttempts() then
        SetState("closed")
        return true
    end if
    ' Back off on the shared port; a "close" command interrupts the wait.
    ev = wait(SyncPlayBackoffMs(m.attempt - 1), m.port)
    if type(ev) = "roSGNodeEvent" then
        HandleCommand(ev.getData())
    end if
    return m.stopped
end function

' Mint a fresh relay token, then connect + complete the WS upgrade. Returns true
' only when the socket is open and the handshake accepted (101).
function MintAndConnect(host as String, port as Integer, apiBase as String, serverId as String, token as String) as Boolean
    SetState("connecting")

    ' 1. Mint the relay token from the hub (S2a endpoint; the hub JWT is the
    '    credential here — the relay itself wants the minted token).
    mintedToken = MintRelayToken(apiBase, serverId, token)
    if mintedToken = "" then return false

    ' 2. Open the plaintext TCP socket to the relay.
    m.sock = CreateObject("roStreamSocket")
    if m.sock = invalid then return false
    m.sock.SetMessagePort(m.port)

    addr = CreateObject("roSocketAddress")
    addr.SetHostName(host)
    addr.SetPort(port)
    m.sock.SetSendToAddress(addr)
    m.sock.NotifyReadable(true)
    m.sock.NotifyWritable(true)

    ok = m.sock.Connect()
    if not ok then return false

    ' 3. Wait (bounded) for TCP connect, then send the upgrade request with the
    '    relay token on the Authorization header — the sanctioned carrier for a
    '    raw RFC6455 client (S237: query string refused by design).
    if not WaitForConnect(host, port, "/syncplay/" + serverId, mintedToken) then return false

    return true
end function

' POST {apiBase}/api/v1/me/servers/{serverId}/relay-token with the hub JWT.
' Returns the minted plaintext token, or "" on any failure.
function MintRelayToken(apiBase as String, serverId as String, token as String) as String
    url = apiBase + "/api/v1/me/servers/" + serverId + "/relay-token"
    transfer = CreateObject("roUrlTransfer")
    transfer.SetUrl(url)
    transfer.SetRequest("POST")
    transfer.SetMessagePort(m.port)
    ' ROK-13 custody: the Bearer hub JWT must never be 3xx-walked to a host
    ' the user never chose - refuse every redirect (redirect_refused law).
    transfer.EnableRedirects(false)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    transfer.AddHeader("Authorization", "Bearer " + token)
    transfer.AddHeader("Content-Type", "application/json")
    ' M-ROKU-11: honest client identity on the hub relay-token mint too —
    ' support can see WHICH channel build dialed (review roku__devops M4).
    ' ProtocolChannelVersion: this thin task scope excludes AppContext by
    ' design; the leaf reads the same roAppInfo.GetVersion() firmware source.
    transfer.AddHeader("X-Phlix-Client-Version", ProtocolChannelVersion())

    if not transfer.AsyncPostFromString("") then return ""

    ' Bounded wait for the roUrlEvent.
    deadline = 0
    while deadline < 100
        ev = wait(100, m.port)
        if type(ev) = "roUrlEvent" then
            code = ev.GetResponseCode()
            if code >= 300 and code < 400 then return "" ' redirect_refused: never followed
            if ResponseBodyExceedsCap(ev.GetContentLength(), -1) then return ""
            body = ev.GetString()
            if body <> invalid and ResponseBodyExceedsCap(-1, Len(body)) then return ""
            if code = 201 and body <> invalid and body <> "" then
                parsed = ParseJSON(body)
                ' [W-min93 M-ROKU-26, review roku__exploiter m5] a hostile/
                ' compromised hub answering {"token":123} used to cross the raw
                ' value into "Bearer " + relayToken downstream — a task-thread
                ' type error that kills the command channel before the ladder
                ' even starts. Only a String token is minted onward.
                if parsed <> invalid and type(parsed) = "roAssociativeArray" and parsed.DoesExist("token") and type(parsed.token) = "roString" then
                    return parsed.token
                end if
            end if
            return ""
        else if type(ev) = "roSGNodeEvent" then
            ' A "close" arrived while minting — honour it.
            HandleCommand(ev.getData())
            return ""
        end if
        deadline = deadline + 1
    end while
    return ""
end function

' Block (bounded) until the socket reports connected, then send the WS upgrade
' request (with the Authorization header) and read until "\r\n\r\n", validating
' the 101 status line AND — R-ROKU-05 — its Sec-WebSocket-Accept proof
' (fail-closed, twin of the :8097 dial law). Returns true only on an upgrade
' answered by a server that demonstrably saw the key THIS handshake offered.
function WaitForConnect(host as String, port as Integer, path as String, relayToken as String) as Boolean
    deadline = 0
    while deadline < 100
        if m.sock.IsConnected() then exit while
        ev = wait(100, m.port)
        if type(ev) = "roSGNodeEvent" then
            HandleCommand(ev.getData())
            if m.stopped then return false
        end if
        deadline = deadline + 1
    end while

    if not m.sock.IsConnected() then return false

    ' Stop writable notifications; keep readable on for the handshake + frames.
    m.sock.NotifyWritable(false)

    ' Send the upgrade request with the relay token on the Authorization header.
    keyB64 = m.proto.NewWebSocketKey()
    ' M-ROKU-11: version rides the relay handshake as on every other dial
    ' (CHECK44 R1 pins both handshake sites; ProtocolChannelVersion is the
    ' task-scope leaf, same roAppInfo.GetVersion() firmware source).
    req = m.proto.BuildHandshakeRequest(host, port, path, keyB64, {
        Authorization: "Bearer " + relayToken
        "X-Phlix-Client-Version": ProtocolChannelVersion()
    })
    sent = m.sock.SendStr(req)
    ' MN-11: a SHORT upgrade write desyncs the server parser exactly like a
    ' negative one - refuse the dial; the ladder re-sends it whole.
    if sent < 0 or sent < req.Len() then return false

    ' Read the HTTP response into a BYTE accumulator and locate the "\r\n\r\n"
    ' terminator BY BYTES. The 101 response and the first WS frame can arrive in
    ' the SAME TCP segment, and a frame byte >=0x80 would be mangled through an
    ' ASCII String — validate the header on its byte slice, append the BYTE
    ' remainder to the frame accumulator.
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
                ' [minors W-min95 M-ROKU-24, review roku__exploiter m3] same
                ' handshake-cap law as SyncPlayTask: a peer that never sends
                ' "\r\n\r\n" used to inflate this accumulator for the whole
                ' tries budget (~400KB). Refuse the dial past the canonical
                ' header cap instead of waiting the loop out.
                if headerBytes.Count() > m.proto.MaxHandshakeHeaderBytes then return false
                termIdx = FindHeaderTerminator(headerBytes)
                if termIdx >= 0 then exit while
            else if n = 0 then
                return false
            end if
        else if type(ev) = "roSGNodeEvent" then
            HandleCommand(ev.getData())
            if m.stopped then return false
        end if
        tries = tries + 1
    end while

    if termIdx < 0 then return false

    headerText = HeaderSliceToString(headerBytes, termIdx + 4)
    if not m.proto.HandshakeAccepted(headerText) then return false

    ' R-ROKU-05 (review roku__exploiter M3 class, fixlog/R-ROKU-05__fix.md;
    ' triage .reviews/ledger-exec/E-rok0507-triage.md): a 101 status line says
    ' A server answered; ONLY the Sec-WebSocket-Accept hash proves it saw OUR
    ' random key. Fail-closed twin of the SyncPlayTask dial (:8097 law,
    ' M-ROKU-14) — an absent header, a non-computable expectation (no
    ' roEVPDigest / Setup refusal) or any mismatch refuses the upgrade BEFORE
    ' a single frame byte reaches the accumulator, so a blind injector that
    ' forges "HTTP/1.1 101" never opens this command channel and the scoped
    ' relay token never rides a forged handshake. The refusal is the file's
    ' own idiom — return false into the backoff ladder (no m.wsAcceptFailed
    ' tag: the SyncPlayTask emit path has no consumer on this side, and
    ' Check 70 R2 keeps that divergence sanctioned). Proof, not transport:
    ' the hub's :8804 responder is RFC6455-conformant (phlix-hub vendor
    ' Protocols/Websocket.php echoes base64(SHA1(key + GUID)) on every 101),
    ' so live relays are unaffected. keyB64 is the SAME key offered to
    ' BuildHandshakeRequest above.
    if not m.proto.VerifyHandshakeAccept(headerText, keyB64) then return false

    AppendRemainderBytes(headerBytes, termIdx + 4)

    m.handshakeDone = true
    SetState("open")
    EmitEvent({ kind: "open" })
    return true
end function

' One socket event: append received bytes to the frame accumulator and dispatch
' any complete frames. Returns false when the peer closed.
function HandleSocketEvent() as Boolean
    chunk = CreateObject("roByteArray")
    n = m.sock.Receive(chunk, 0, 4096)
    if n = 0 then
        return false
    else if n < 0 then
        return false
    end if
    if not m.handshakeDone then return true
    m.buffer.Append(chunk)

    parsed = m.proto.ParseFrames(m.buffer)
    ' [minors W-min95 M-ROKU-39 parity, review roku__exploiter m3 / secnet m3]
    ' SyncPlayTask already drops on a rejected declared length (W-min93); this
    ' hub-command socket was missing the same guard, so a hostile/compromised
    ' relay could wedge a garbage frame header here forever without the socket
    ' ever closing. Mirror the room-task law: rejection means desynced/hostile
    ' peer -> drop; Run()'s BackoffAndCheckSpent handles the reconnect.
    if parsed <> invalid and parsed.rejectedOversize = true then
        return false
    end if
    if parsed <> invalid and parsed.consumed > 0 then
        m.buffer = m.proto.RemainderBuffer(m.buffer, parsed.consumed)
        for each frame in parsed.frames
            HandleFrame(frame)
            ' MN-11: a pong shortfall invalidates the socket mid-pass;
            ' stop feeding frames - the next loop is the ladder's.
            if m.sock = invalid then
                ' MN-14: what already decoded still ships before the death.
                FlushPendingEvents()
                return false
            end if
        end for
        ' MN-14: one recv pass, one event-field write.
        FlushPendingEvents()
    end if
    ' [minors W-min95 M-ROKU-39, review roku__secnet m3] post-consumption residual
    ' of an honest stream is one incomplete frame (<= MaxFrameBytes + 14-byte
    ' header) plus at most one already-sent follow-on chunk; anything beyond the
    ' canonical estate bound can never complete, so drop rather than buffer an
    ' unbounded slow-drip.
    if m.buffer.Count() > m.proto.MaxFrameBytes + 4096 + 64 then
        return false
    end if
    return true
end function

' Route one complete WS frame: pings get a masked pong; TEXT frames are parsed
' and only `pending_command` / `play_media` is surfaced. Everything else the
' relay may send is ignored — this socket is a command consumer, not a room
' participant.
sub HandleFrame(frame as Object)
    if frame = invalid then return

    if frame.opcode = m.proto.OP_PING then
        pong = m.proto.BuildPongFrame(frame.payloadBytes)
        if m.sock <> invalid then
            ' MN-11: bind the count - a half-written masked pong desyncs the
            ' stream, so the honest act is to drop the socket; RunConsumer's
            ' BackoffAndCheckSpent re-dials (the death paths already say so).
            sent = m.sock.Send(pong, 0, pong.Count())
            if sent < pong.Count() then
                m.sock.Close()
                m.sock = invalid
            end if
        end if
        return
    end if

    if frame.opcode <> m.proto.OP_TEXT then return
    if frame.payload = invalid or frame.payload = "" then return

    msg = m.proto.Decode(frame.payload)
    if msg = invalid then return
    if type(msg) <> "roAssociativeArray" then return

    ' Only the hub's pending_command / play_media frame (S93's shape,
    ' PendingCommandDispatcher) is consumed here.
    if msg.type = "pending_command" and msg.command = "play_media" then
        mediaId = ""
        title = ""
        if msg.DoesExist("media_id") and type(msg.media_id) = "roString" then mediaId = msg.media_id
        if msg.DoesExist("title") and type(msg.title) = "roString" then title = msg.title
        if mediaId = "" then return

        ' MN-14: queue, do not field-write per frame (coalescing law - see
        ' FlushPendingEvents).
        m.pendingEvents.Push({
            kind: "pending_command"
            mediaId: mediaId
            title: title
            serverId: m.top.config.serverId
        })
    end if
end sub

sub FlushPendingEvents()
    if m.pendingEvents = invalid then return
    n = m.pendingEvents.Count()
    if n = 0 then return
    if n = 1 then
        EmitEvent(m.pendingEvents[0])
    else
        EmitEvent({ kind: "batch", items: m.pendingEvents })
    end if
    m.pendingEvents = []
end sub

' Scene commands: { kind: "close" } stops the consumer loop + ladder.
function HandleCommand(cmd as Object) as Boolean
    if cmd = invalid then return true
    if cmd.kind = "close" then
        m.stopped = true
        return false
    end if
    return true
end function

' Locate the first "\r\n\r\n" (0x0D 0x0A 0x0D 0x0A) in a byte accumulator.
function FindHeaderTerminator(ba as Object) as Integer
    if ba = invalid then return -1
    total = ba.Count()
    i = 0
    while i + 3 < total
        if ba[i] = 13 and ba[i + 1] = 10 and ba[i + 2] = 13 and ba[i + 3] = 10 then return i
        i = i + 1
    end while
    return -1
end function

' ASCII-safe slice of the header bytes [0 .. count).
function HeaderSliceToString(ba as Object, count as Integer) as String
    if ba = invalid or count <= 0 then return ""
    head = CreateObject("roByteArray")
    i = 0
    while i < count and i < ba.Count()
        head.Push(ba[i])
        i = i + 1
    end while
    return head.ToAsciiString()
end function

' Append the bytes after the header terminator to the frame accumulator (no
' String round-trip — frame bytes are binary-safe).
sub AppendRemainderBytes(ba as Object, fromIndex as Integer)
    if ba = invalid then return
    total = ba.Count()
    i = fromIndex
    while i < total
        m.buffer.Push(ba[i])
        i = i + 1
    end while
end sub

sub SetState(state as String)
    m.top.connectionState = state
end sub

sub EmitEvent(e as Object)
    m.top.event = e
end sub

sub Cleanup()
    if m.sock <> invalid then
        m.sock.Close()
        m.sock = invalid
    end if
    m.top.UnobserveField("command")
    SetState("closed")
end sub