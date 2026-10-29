' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/Discovery.test.brs

' ===========================================
' M-ROKU-04 r2 — pure discovery-boundary unit tests
'
' Targets the three functions the connect/discovery front door parses LAN
' input through: ClassifyUrlFailure (curl reason -> closed bucket),
' ExtractServerOrigin (SSDP LOCATION -> connectable origin) and
' ParseSsdpResponse (raw datagram -> origin-or-empty). All three live in
' source/lib/Utilities.brs precisely so this file can reach them
' (CHECK37 R4 pins the home).
'
' Venue note: rooibos unit tests execute only on a Roku device/emulator
' (make test-unit / CI gate on ROKU_HOST); written per the Utilities.test.brs
' convention for the next device lane to run.
' ===========================================

' ---- ClassifyUrlFailure tests ----

sub TestClassifyUrlFailureNotStartedIsBadUrl()
    ' roUrlTransfer itself rejected the URL - the reason text is irrelevant.
    assertEqual(ClassifyUrlFailure("", false), "bad_url")
    assertEqual(ClassifyUrlFailure("resolve", false), "bad_url")
    print "TestClassifyUrlFailureNotStartedIsBadUrl passed"
end sub

sub TestClassifyUrlFailureDns()
    assertEqual(ClassifyUrlFailure("Could not resolve host: phlix.local", true), "dns")
    assertEqual(ClassifyUrlFailure("RESOLVE failed", true), "dns")
    print "TestClassifyUrlFailureDns passed"
end sub

sub TestClassifyUrlFailureRefused()
    assertEqual(ClassifyUrlFailure("Couldn't connect to server", true), "refused")
    assertEqual(ClassifyUrlFailure("Could not connect to 192.168.1.5", true), "refused")
    assertEqual(ClassifyUrlFailure("Connection refused", true), "refused")
    print "TestClassifyUrlFailureRefused passed"
end sub

sub TestClassifyUrlFailureTls()
    assertEqual(ClassifyUrlFailure("SSL connect error", true), "tls")
    assertEqual(ClassifyUrlFailure("certificate verified failed", true), "tls")
    assertEqual(ClassifyUrlFailure("TLS handshake timeout-ish word tls", true), "tls")
    print "TestClassifyUrlFailureTls passed"
end sub

sub TestClassifyUrlFailureTimeout()
    assertEqual(ClassifyUrlFailure("Operation timed out", true), "timeout")
    assertEqual(ClassifyUrlFailure("Connection timeout", true), "timeout")
    print "TestClassifyUrlFailureTimeout passed"
end sub

sub TestClassifyUrlFailureUnreachableIsTheHonestDefault()
    ' Anything else - unknown text or no text at all - lands on the generic
    ' bucket; the classifier never guesses a more specific cause.
    assertEqual(ClassifyUrlFailure("Connection reset by peer", true), "unreachable")
    assertEqual(ClassifyUrlFailure("", true), "unreachable")
    assertEqual(ClassifyUrlFailure(invalid, true), "unreachable")
    print "TestClassifyUrlFailureUnreachableIsTheHonestDefault passed"
end sub

' ---- ExtractServerOrigin tests ----

sub TestExtractServerOriginReducesPath()
    got1 = ExtractServerOrigin("http://192.168.1.5:8096/dlna/description.xml")
    assertEqual(got1, "http://192.168.1.5:8096")
    got2 = ExtractServerOrigin("https://phlix.example.com/secure/desc.xml")
    assertEqual(got2, "https://phlix.example.com")
    print "TestExtractServerOriginReducesPath passed"
end sub

sub TestExtractServerOriginStripsQueryAndFragment()
    got1 = ExtractServerOrigin("http://10.0.0.9:8096/d?id=7")
    assertEqual(got1, "http://10.0.0.9:8096")
    got2 = ExtractServerOrigin("http://10.0.0.9:8096#frag")
    assertEqual(got2, "http://10.0.0.9:8096")
    print "TestExtractServerOriginStripsQueryAndFragment passed"
end sub

sub TestExtractServerOriginLowercasesSchemeOnly()
    ' The scheme is normalized (case-insensitive match, lowercase output);
    ' the host part is carried through untouched.
    got = ExtractServerOrigin("HTTP://192.168.1.5:8096/x")
    assertEqual(got, "http://192.168.1.5:8096")
    print "TestExtractServerOriginLowercasesSchemeOnly passed"
end sub

sub TestExtractServerOriginRejectsForeignSchemes()
    ' Not connectable origins for this channel - no ftp, no bare host, no
    ' schemeless LOCATION.
    assertEqual(ExtractServerOrigin("ftp://192.168.1.5:21/pub"), "")
    assertEqual(ExtractServerOrigin("192.168.1.5:8096"), "")
    assertEqual(ExtractServerOrigin(""), "")
    assertEqual(ExtractServerOrigin(invalid), "")
    print "TestExtractServerOriginRejectsForeignSchemes passed"
end sub

sub TestExtractServerOriginRejectsUserinfo()
    ' An SSDP answer is LAN-influenced input: a URL carrying userinfo is a
    ' redirection smell, not a server address.
    assertEqual(ExtractServerOrigin("http://evil@attacker.test:8096/x"), "")
    assertEqual(ExtractServerOrigin("http://attacker.test@192.168.1.5/x"), "")
    print "TestExtractServerOriginRejectsUserinfo passed"
end sub

' ---- ParseSsdpResponse tests ----
' BrightScript has no \r escapes; SSDP lines are built the same way the
' request builder does it.

function SsdpCrlf() as String
    return Chr(13) + Chr(10)
end function

function SsdpDatagram(lines as Object) as String
    out = ""
    for each line in lines
        out = out + line + SsdpCrlf()
    end for
    return out + SsdpCrlf()
end function

sub TestParseSsdpResponseAcceptsPhlixUsn()
    lines = [
        "HTTP/1.1 200 OK",
        "CACHE-CONTROL: max-age=1800",
        "ST: urn:schemas-upnp-org:device:MediaServer:1",
        "USN: uuid:PHLIXSERVER::urn:schemas-upnp-org:device:MediaServer:1",
        "LOCATION: http://192.168.1.5:8096/dlna/description.xml",
        "SERVER: Ubuntu/24.04 UPnP/1.0 Phlix/1.0.0"
    ]
    assertEqual(ParseSsdpResponse(SsdpDatagram(lines)), "http://192.168.1.5:8096")
    print "TestParseSsdpResponseAcceptsPhlixUsn passed"
end sub

sub TestParseSsdpResponseAcceptsPhlixServerHeaderAlone()
    ' Identity may come from the SERVER header even if a proxy mangles USN.
    lines = [
        "HTTP/1.1 200 OK",
        "USN: uuid:other-box-000::urn:schemas-upnp-org:device:MediaServer:1",
        "SERVER: Linux UPnP/1.0 Phlix/2.0.0",
        "LOCATION: http://10.1.2.3:8096/dlna/description.xml"
    ]
    assertEqual(ParseSsdpResponse(SsdpDatagram(lines)), "http://10.1.2.3:8096")
    print "TestParseSsdpResponseAcceptsPhlixServerHeaderAlone passed"
end sub

sub TestParseSsdpResponseIgnoresNotify()
    ' Unsolicited NOTIFY advertisements are not answers to our search.
    lines = [
        "NOTIFY * HTTP/1.1",
        "HOST: 239.255.255.250:1900",
        "USN: uuid:PHLIXSERVER::urn:schemas-upnp-org:device:MediaServer:1",
        "LOCATION: http://192.168.1.5:8096/dlna/description.xml"
    ]
    assertEqual(ParseSsdpResponse(SsdpDatagram(lines)), "")
    print "TestParseSsdpResponseIgnoresNotify passed"
end sub

sub TestParseSsdpResponseIgnoresForeignSearch()
    ' A neighbor's M-SEARCH flood on the same port must never parse as a
    ' keeper even if it mentions MediaServer.
    lines = [
        "M-SEARCH * HTTP/1.1",
        "HOST: 239.255.255.250:1900",
        "MAN: ""ssdp:discover""",
        "MX: 1",
        "ST: urn:schemas-upnp-org:device:MediaServer:1"
    ]
    assertEqual(ParseSsdpResponse(SsdpDatagram(lines)), "")
    print "TestParseSsdpResponseIgnoresForeignSearch passed"
end sub

sub TestParseSsdpResponseIgnoresNonPhlixAnswer()
    ' A genuine 200 search response from someone else's MediaServer: hits
    ' neither identity marker.
    lines = [
        "HTTP/1.1 200 OK",
        "USN: uuid:Roku::urn:schemas-upnp-org:device:MediaServer:1",
        "SERVER: Linux/6.0 UPnP/1.0 SomeBox/3.2",
        "LOCATION: http://192.168.1.9:1234/root.xml"
    ]
    assertEqual(ParseSsdpResponse(SsdpDatagram(lines)), "")
    print "TestParseSsdpResponseIgnoresNonPhlixAnswer passed"
end sub

sub TestParseSsdpResponseRejectsUnusableLocation()
    ' Phlix-identifying, but the LOCATION either does not reduce to a safe
    ' origin or is absent - both must be dropped at the parse boundary.
    lines = [
        "HTTP/1.1 200 OK",
        "USN: uuid:PHLIXSERVER::x",
        "SERVER: UPnP/1.0 Phlix/1.0.0",
        "LOCATION: http://evil@attacker.test:8096/d"
    ]
    assertEqual(ParseSsdpResponse(SsdpDatagram(lines)), "")
    lines2 = [
        "HTTP/1.1 200 OK",
        "USN: uuid:PHLIXSERVER::x"
    ]
    assertEqual(ParseSsdpResponse(SsdpDatagram(lines2)), "")
    print "TestParseSsdpResponseRejectsUnusableLocation passed"
end sub

sub TestParseSsdpResponseRejectsGarbage()
    assertEqual(ParseSsdpResponse(""), "")
    assertEqual(ParseSsdpResponse(invalid), "")
    assertEqual(ParseSsdpResponse("hello world"), "")
    print "TestParseSsdpResponseRejectsGarbage passed"
end sub
