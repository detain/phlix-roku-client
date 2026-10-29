' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/DiscoveryTask.brs

' copyright 2026 Joe Huss
'
'
' M-ROKU-04 r2 — one-shot SSDP LAN scan (task thread; UI-free), rebuilt on
' the DOCUMENTED socket surface.
'
' The r1 scan drove an roSocket constructed with a "udp:" address string and
' called EnableBroadcast / JoinMulticastGroup / one-arg Receive — none of
' which exist in this repo's own vendored Roku documentation mirror
' (node_modules/brighterscript/dist/roku-types/data.json), and hid that from
' the compiler behind a component-name indirection. r1 could die mid-scan on a
' BrightScript runtime error, and the dead thread never wrote `response` —
' leaving the Connect screen latched on "Searching…" with a permanently
' dead Find button (the exact defect class M-ROKU-04 set out to cure).
'
' r2 follows the roDataGramSocket worked example quoted verbatim in the
' vendored mirror:
'   CreateObject("roDataGramSocket")                       ' no arguments
'   roSocketAddress + ifSocket.SetAddress                  ' BSD bind
'   ifSocketAsync.SetMessagePort / NotifyReadable          ' roSocketEvent feed
'   ifSocketCastOption.SetBroadcast / JoinGroup            ' real documented names
'   ifSocket.SetSendToAddress + SendStr                    ' the sendto half
'   ifSocketAsync.GetID vs roSocketEvent.GetSocketID       ' event ownership
'   IsReadable + ReceiveStr(length)                        ' non-blocking drain
' Every call is written by its documented name and the component-name
' indirection is gone. Enforcement truth, measured (r2 review issue 1): bsc/
' bslint do NOT resolve member calls on CreateObject-typed locals, so the
' compiler is NOT the guard here - CHECK37 (scripts/verify-runtime.sh) is:
' it pins every documented verb present and every r1 counter-doc form dead,
' so a future rename reddens the runtime gate instead of the user's living room.
'
' Sends the SAME M-SEARCH datagram shape the server's own discovery client
' builds (phlix-server src/Discovery/Ssdp/SsdpSocket.php:316-321 — method
' line, HOST, MAN "ssdp:discover", MX, ST, terminating blank line) to the
' SSDP multicast group, then collects HTTP/1.1 200 responses for a bounded
' window. Which servers count as Phlix:
'   * USN begins "uuid:PHLIXSERVER"  (phlix-server SsdpAdvertiser::USN), or
'   * SERVER header names "Phlix/"    (SsdpSearchResponder server header).
' LOCATION (e.g. http://192.168.1.5:8096/dlna/description.xml) is reduced to
' the connectable origin by ExtractServerOrigin (Utilities.brs) — the parse-
' don't-validate boundary: an SSDP answer is LAN-influenced input, so it can
' only ever prefill a text box that the existing /health probe gates.
'
' Degradation contract (CHECK37 pins it from both sides):
'   * every leg this thread can reach without erroring writes m.top.response
'     with a (possibly empty) { servers: [...] } answer;
'   * if the thread nevertheless dies, the Task node still transitions
'     state -> "finish", and ConnectScene observes BOTH fields: a finish
'     without a response renders the same honest "No Phlix server found"
'     floor as an empty scan. An errored scan never latches; Find stays
'     re-pressable; manual entry is always the floor, never lost.

' ---------------------------------------------
' Wire constants (cross-read from phlix-server, do not drift):
'   multicast group + port: SsdpSocket::MULTICAST_ADDR/PORT
'   search target:          SsdpSearchResponder::DEVICE_TYPE
'   identity markers:       SsdpAdvertiser::USN "PHLIXSERVER", "Phlix/" token
' ---------------------------------------------
function DiscoveryMulticastAddr() as String
    return "239.255.255.250"
end function

function DiscoveryMulticastPort() as Integer
    return 1900
end function

function DiscoverySearchTarget() as String
    return "urn:schemas-upnp-org:device:MediaServer:1"
end function

' The scan window. MX: 3 asks responders to spread replies over <=3 s
' (the server caps MX at 5 - SsdpSearchResponder::MAX_MX_SECONDS); the socket
' is kept a further beat past that so late-but-promised answers land.
function DiscoveryMxSeconds() as Integer
    return 3
end function

function DiscoveryWindowMs() as Integer
    return 4200
end function

' Total datagrams parsed per scan - a busy LAN segment can out-produce a TV;
' the cap bounds per-scan work exactly like the server caps inbound datagrams.
function DiscoveryMaxDatagrams() as Integer
    return 64
end function

' Per-datagram read ceiling for ReceiveStr. SSDP search responses are small
' header sets; the vendored docs' own worked example reads 512 bytes - 2048
' keeps headroom for long LOCATION/USN lines without an unbounded read.
function DiscoveryMaxDatagramBytes() as Integer
    return 2048
end function

sub Init()
    m.top.functionName = "RunDiscovery"
end sub

sub RunDiscovery()
    servers = []

    port = CreateObject("roMessagePort")
    sock = CreateObject("roDataGramSocket")
    if sock = invalid then
        ' Datagram sockets unavailable on this firmware - empty answer,
        ' caller falls back to manual entry (the documented floor).
        m.top.response = { servers: servers }
        return
    end if

    ' Bind an ephemeral local UDP port: the documented pair is
    ' ifSocketAddress.SetAddress(String) then ifSocket.SetAddress(roSocketAddress).
    bindAddr = CreateObject("roSocketAddress")
    bindAddr.SetAddress("0.0.0.0:0")
    if not sock.SetAddress(bindAddr) then
        sock.Close()
        m.top.response = { servers: servers }
        return
    end if

    ' Arm the event feed BEFORE sending so an answer that arrives instantly is
    ' queued, not missed. SetBroadcast/JoinGroup are best-effort per the docs:
    ' replies to our own M-SEARCH come back unicast; the join only adds
    ' hearing the group traffic (NOTIFYs). A refused option must not sink the
    ' scan, so their Booleans are deliberately not branched on.
    sock.SetMessagePort(port)
    sock.NotifyReadable(true)
    sock.SetBroadcast(true)

    groupAddr = CreateObject("roSocketAddress")
    groupAddr.SetAddress(DiscoveryMulticastAddr())
    sock.JoinGroup(groupAddr)

    ' Send = documented two-step: SetSendToAddress stashes the first half of
    ' the BSD sendto(), SendStr then ships the whole datagram.
    sendAddr = CreateObject("roSocketAddress")
    sendAddr.SetAddress(DiscoveryMulticastAddr() + ":" + Str(DiscoveryMulticastPort()).Trim())
    if not sock.SetSendToAddress(sendAddr) then
        sock.Close()
        m.top.response = { servers: servers }
        return
    end if

    ' SendStr returns the byte count (or a negative error) - compare
    ' numerically, never rely on truthiness of an Integer.
    sent = sock.SendStr(DiscoveryRequest())
    if sent <= 0 then
        sock.Close()
        m.top.response = { servers: servers }
        return
    end if

    seen = {}
    deadline = CurrentMillis() + DiscoveryWindowMs()
    budget = DiscoveryMaxDatagrams()

    while budget > 0
        remaining = deadline - CurrentMillis()
        if remaining <= 0 then exit while
        msg = wait(CInt(remaining), port)
        if msg = invalid then exit while   ' wait() timed out: window closed
        if type(msg) = "roSocketEvent" then
            ' The docs' event-ownership check: only act on this socket.
            if msg.GetSocketID() = sock.GetID() then
                ' Drain every datagram readable right now; IsReadable is the
                ' documented non-blocking probe so ReceiveStr never stalls the
                ' thread and an empty read ends the drain (no spin).
                while budget > 0 and sock.IsReadable()
                    raw = sock.ReceiveStr(DiscoveryMaxDatagramBytes())
                    if raw = "" then exit while
                    budget = budget - 1
                    origin = ParseSsdpResponse(raw)
                    if origin <> "" and not seen.DoesExist(origin) then
                        seen[origin] = true
                        servers.Push(origin)
                    end if
                end while
            end if
        end if
    end while

    sock.Close()
    m.top.response = { servers: servers }
end sub

' The M-SEARCH datagram - CRLF-terminated, blank line last, verbatim shape
' of the server-side client builder. BrightScript has no \r escapes.
' The parser for the answers (ParseSsdpResponse) lives in Utilities.brs -
' pure logic belongs where the unit tests can reach it (CHECK37 R4).
function DiscoveryRequest() as String
    crlf = Chr(13) + Chr(10)
    req = "M-SEARCH * HTTP/1.1" + crlf
    req = req + "HOST: " + DiscoveryMulticastAddr() + ":" + Str(DiscoveryMulticastPort()).Trim() + crlf
    req = req + "MAN: ""ssdp:discover""" + crlf
    req = req + "MX: " + Str(DiscoveryMxSeconds()).Trim() + crlf
    req = req + "ST: " + DiscoverySearchTarget() + crlf
    req = req + crlf
    return req
end function

' Millisecond clock for the scan window.
function CurrentMillis() as LongInteger
    dt = CreateObject("roDateTime")
    return dt.TotalMilliseconds()
end function
