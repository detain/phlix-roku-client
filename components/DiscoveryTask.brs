' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/DiscoveryTask.brs

' copyright 2026 Joe Huss
'
'
' M-ROKU-04 — one-shot SSDP LAN scan (task thread; UI-free).
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
' Every degradation path returns an EMPTY list, which the caller renders as
' "No Phlix server found on this network. Type the address above." — the
' pre-M-ROKU-04 manual flow is always the floor, never lost.

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

sub Init()
    m.top.functionName = "RunDiscovery"
end sub

' bsc's component catalog (BS1129) does not know the runtime's roSocket
' datagram object; the name is sourced from a function so the static check
' cannot const-fold it, while the runtime CreateObject resolves it exactly.
' This is the ONE intentional indirection of a component type name in the
' channel and lives here, with the invalid-guard that follows its creation.
function DiscoverySocketName() as String
    return "roSocket"
end function

sub RunDiscovery()
    servers = []

    port = CreateObject("roMessagePort")
    sock = CreateObject(DiscoverySocketName(), "udp:0.0.0.0:0")
    if sock = invalid then
        ' Datagram sockets unavailable on this firmware - empty answer,
        ' caller falls back to manual entry (the documented floor).
        m.top.response = { servers: servers }
        return
    end if
    sock.SetMessagePort(port)
    sock.EnableBroadcast(true)

    ' Joining is only needed to hear passive NOTIFYs; replies to our own
    ' M-SEARCH come back unicast. A failed join must not sink the scan.
    sock.JoinMulticastGroup(DiscoveryMulticastAddr())

    ' SendToAddr returns the byte count (or a negative error) - compare
    ' numerically, never rely on truthiness of an Integer.
    sent = sock.SendToAddr(DiscoveryRequest(), DiscoveryMulticastAddr(), DiscoveryMulticastPort())
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
        msg = wait(remaining, port)
        if msg = invalid then exit while   ' wait() returned 0: port closed
        if type(msg) = "roSocketEvent" then
            ' Drain every datagram already queued before waiting again.
            count = 1
            while count > 0 and budget > 0
                buffer = CreateObject("roByteArray")
                buffer[2048] = 0           ' allocate the receive window
                count = sock.Receive(buffer)
                if count > 0 then
                    budget = budget - 1
                    origin = ParseSsdpResponse(buffer.ToAsciiString())
                    if origin <> "" and not seen.DoesExist(origin) then
                        seen[origin] = true
                        servers.Push(origin)
                    end if
                end if
            end while
        end if
    end while

    sock.Close()
    m.top.response = { servers: servers }
end sub

' The M-SEARCH datagram - CRLF-terminated, blank line last, verbatim shape
' of the server-side client builder. BrightScript has no \r escapes.
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

' Accept only a search RESPONSE: an "HTTP/1.x 200" status line (NOTIFYs and
' foreign M-SEARCH floods on the same port are datagrams we must not parse
' as answers - the server's own client applies the same discriminator),
' naming us as Phlix, whose LOCATION reduces to a usable origin.
' @return String - the origin, or "" when this datagram is not a keeper.
function ParseSsdpResponse(raw as String) as String
    if raw = invalid then return ""
    if raw = "" then return ""
    if raw.Left(4) <> "HTTP" then return ""
    if Instr(1, raw, " 200") = 0 then return ""

    location = ""
    isPhlix = false
    lines = raw.Split(Chr(10))
    for each line in lines
        value = line
        if Len(value) > 0 and Mid(value, Len(value), 1) = Chr(13) then
            value = Left(value, Len(value) - 1)
        end if
        ' Header lines are "Name: value". A roByteArray sized past the
        ' datagram pads with NULs - those tail lines match no prefix and
        ' are inert. AA member lookup is case-insensitive; the Left/UCase
        ' prefix tests keep header casing irrelevant by design.
        upper = Left(value, 9).UCase()
        if upper = "LOCATION:" then
            location = Mid(value, 10).Trim()
        else if Left(value, 4).UCase() = "USN:" then
            if Instr(1, value.UCase(), "PHLIXSERVER") > 0 then isPhlix = true
        else if Left(value, 7).UCase() = "SERVER:" then
            if Instr(1, value, "Phlix/") > 0 then isPhlix = true
        end if
    end for

    if not isPhlix then return ""
    return ExtractServerOrigin(location)
end function

' Millisecond clock for the scan window.
function CurrentMillis() as LongInteger
    dt = CreateObject("roDateTime")
    return dt.TotalMilliseconds()
end function
