' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/HubCommandTask.brs

' =============================================================================
' S298 — hub relay pending_command consumer (Roku half).
'
' The hub's SyncPlay relay (`ws://<hub>:8804/syncplay/{server_id}`) is the ONLY
' surface that can receive the "Alexa, play X" push (S93's pending_command). It
' validates a per-user, server-scoped RELAY TOKEN on the upgrade request — never
' the hub JWT, never a query string (S237). The Roku roStreamSocket is plaintext
' TCP with NO TLS and NO WebSocket layer, so this task:
'
'   1. MINTS a relay token: POST {apiBase}/api/v1/me/servers/{serverId}/relay-token
'      with the hub access JWT (the hub's own S2a mint endpoint).
'   2. CONNECTS to the relay with the token on the `Authorization: Bearer`
'      header — a raw RFC6455 handshake can carry any header, which is why the
'      Roku client uses the header carrier (the browser subprotocol carrier is
'      a web-only surface).
'   3. CONSUMES only `pending_command` / `play_media` frames, forwarding them
'      to the scene as { kind: "pending_command", mediaId, title, ... }. Every
'      other relay frame (`group_join`, `playback_*`, `room_state`, ...) is
'      ignored — this socket is a command consumer, not a room participant.
'   4. LIFECYCLE: long-lived ("open whenever the app is open"), with a bounded
'      reconnect ladder (5 attempts, 1s/2s/4s/8s/16s) that RE-MINTS on every
'      attempt because relay tokens expire hourly. A { kind: "close" } command
'      stops the ladder.
'
' THREAD RULE: this code runs on the task thread. It may ONLY read m.top.config,
' observe m.top.command, and write m.top.event / m.top.connectionState. The
' scene owns navigation.
' =============================================================================

sub Init()
    m.top.functionName = "RunConsumer"
end sub

' Reconnect ladder (ms), 5 rungs then give up — mirror of the ui's capped ladder.
function BackoffMs(attempt as Integer) as Integer
    delays = [1000, 2000, 4000, 8000, 16000]
    if attempt < delays.Count() then return delays[attempt]
    return 16000
end function

' Max reconnect attempts before giving up.
function MaxAttempts() as Integer
    return 5
end function

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

    if host = "" or apiBase = "" or serverId = "" or token = "" then
        SetState("closed")
        return
    end if

    m.proto = SyncPlayProtocol()
    m.buffer = CreateObject("roByteArray")
    m.handshakeDone = false
    m.handshakeText = ""
    m.attempt = 0
    m.stopped = false

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
    if m.attempt > MaxAttempts() then
        SetState("closed")
        return true
    end if
    ' Back off on the shared port; a "close" command interrupts the wait.
    ev = wait(BackoffMs(m.attempt - 1), m.port)
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
    transfer.AddHeader("Authorization", "Bearer " + token)
    transfer.AddHeader("Content-Type", "application/json")

    if not transfer.AsyncPostFromString("") then return ""

    ' Bounded wait for the roUrlEvent.
    deadline = 0
    while deadline < 100
        ev = wait(100, m.port)
        if type(ev) = "roUrlEvent" then
            code = ev.GetResponseCode()
            body = ev.GetString()
            if code = 201 and body <> "" then
                parsed = ParseJSON(body)
                if parsed <> invalid and type(parsed) = "roAssociativeArray" and parsed.DoesExist("token") then
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
' the 101 response. Returns true on a successful upgrade.
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
    req = m.proto.BuildHandshakeRequest(host, port, path, keyB64, {
        Authorization: "Bearer " + relayToken
    })
    sent = m.sock.SendStr(req)
    if sent < 0 then return false

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
    if parsed <> invalid and parsed.consumed > 0 then
        m.buffer = m.proto.RemainderBuffer(m.buffer, parsed.consumed)
        for each frame in parsed.frames
            HandleFrame(frame)
        end for
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
        if m.sock <> invalid then m.sock.Send(pong, 0, pong.Count())
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

        EmitEvent({
            kind: "pending_command"
            mediaId: mediaId
            title: title
            serverId: m.top.config.serverId
        })
    end if
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