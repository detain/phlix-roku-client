' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/RedirectCustody.test.brs

' ===========================================
' M-ROKU-15 credential custody - unit tests
'
' Review roku__exploiter M4: the Connect/pair flow let a typed (or "Connect
' anyway"-forced) http:// origin persist to storage with no cleartext warning,
' and every credentialed ApiClient send left redirect policy to the firmware -
' a 302 chain could walk the login password or a Bearer token to a host the
' user never chose. The cure's logic lives in pure leaves in
' source/lib/Utilities.brs (HostOfUrl, IsPrivateHostAddress,
' ServerUrlUsesCleartextToRemoteHost, OriginOfUrl, IsCredentialSafeRedirectHop,
' ResolveRedirectTarget, RedirectHopLimit, the ClassifyUrlFailure
' redirect_refused arm); the call sites (ConnectScene persist choke, ApiClient
' hop loops) live in component scope and are statically pinned by CHECK48 in
' scripts/verify-runtime.sh - the WireGuard/SyncPlayWsTls.test.brs precedent.
'
' Venue (R-ROKU-18 truth pass): the obs3 theater is cured at the roots —
' six of these seven subs execute in CI on EVERY push through the device-
' free headless brs gate (`make test-unit` device-free arm and
' .github/workflows/test.yml both run run-headless-unit.mjs, whose
' ALLOWED list names this suite), and TestResolveRedirectTargetShapes is
' excluded THERE for the MEASURED brs gap recorded in that script's
' EXCLUDED_TESTS (Chr(0) collapses to "" headless, so the CR/LF/NUL guard
' would fire on every input), its law staying pinned by the CHECK48 leg.
' The device-dead members the expectations once collided with (.Lower,
' zero-based member .Mid) are extinct — CHECK65 R1 sweeps source/,
' components/ AND tests/, and CHECK65 R5 guards the headless wiring
' against re-deadening. rooibos on-device (`make test-unit` with
' ROKU_HOST) remains the venue that executes all seven subs for real.
' ===========================================

sub TestHostOfUrlVectors()
    ' Scheme-bearing, case-folded, port/path-stripped.
    assertEqual(HostOfUrl("HTTP://Box.Example.com:8096/api"), "box.example.com")
    assertEqual(HostOfUrl("https://h.example?x=1#f"), "h.example")
    assertEqual(HostOfUrl("http://192.168.1.5:8096/dlna/description.xml"), "192.168.1.5")
    ' Scheme-less (the Connect screen infers BEFORE a scheme exists).
    assertEqual(HostOfUrl("10th-street.example.com:8096/x"), "10th-street.example.com")
    ' IPv6 keeps its brackets; a bare ::1 passes through.
    assertEqual(HostOfUrl("http://[::1]:8096/api"), "[::1]")
    assertEqual(HostOfUrl("::1"), "::1")
    ' Malformed / hostile shapes return "".
    assertEqual(HostOfUrl("user@evil.example"), "")
    assertEqual(HostOfUrl("http://[unclosed:8096/"), "")
    assertEqual(HostOfUrl(""), "")
    assertEqual(HostOfUrl("   "), "")
    print "TestHostOfUrlVectors passed"
end sub

sub TestIsPrivateHostAddressTruthTable()
    ' RFC1918 dotted quads are the documented LAN class.
    assertTrue(IsPrivateHostAddress("10.1.2.3"))
    assertTrue(IsPrivateHostAddress("192.168.1.100"))
    assertTrue(IsPrivateHostAddress("172.16.0.1"))
    assertTrue(IsPrivateHostAddress("172.31.255.255"))
    ' Loopback + link-local join the class (the README's "LAN/loopback" promise).
    assertTrue(IsPrivateHostAddress("127.0.0.1"))
    assertTrue(IsPrivateHostAddress("localhost"))
    assertTrue(IsPrivateHostAddress("[::1]"))
    assertTrue(IsPrivateHostAddress("::1"))
    assertTrue(IsPrivateHostAddress("169.254.10.10"))
    ' Public and near-miss names stay OUTSIDE it - the R4.7 census rule.
    assertFalse(IsPrivateHostAddress("172.15.0.1"))
    assertFalse(IsPrivateHostAddress("172.32.0.1"))
    assertFalse(IsPrivateHostAddress("10th-street.example.com"))
    assertFalse(IsPrivateHostAddress("box.example.com"))
    assertFalse(IsPrivateHostAddress("8.8.8.8"))
    assertFalse(IsPrivateHostAddress("1.2.3"))
    assertFalse(IsPrivateHostAddress(""))
    print "TestIsPrivateHostAddressTruthTable passed"
end sub

sub TestCleartextRemoteGateTruthTable()
    ' The exploitable class: cleartext scheme, non-private host.
    assertTrue(ServerUrlUsesCleartextToRemoteHost("http://box.example.com"))
    assertTrue(ServerUrlUsesCleartextToRemoteHost("HTTP://ATTACKER.EXAMPLE:8096"))
    assertTrue(ServerUrlUsesCleartextToRemoteHost("http://10th-street.example.com"))
    ' LAN/loopback http stays silent - the documented home-server normal.
    assertFalse(ServerUrlUsesCleartextToRemoteHost("http://192.168.1.100:8096"))
    assertFalse(ServerUrlUsesCleartextToRemoteHost("http://10.1.2.3"))
    assertFalse(ServerUrlUsesCleartextToRemoteHost("http://localhost:8096"))
    assertFalse(ServerUrlUsesCleartextToRemoteHost("http://[::1]:8096"))
    ' TLS and scheme-less (never persisted without one) are not this class.
    assertFalse(ServerUrlUsesCleartextToRemoteHost("https://box.example.com"))
    assertFalse(ServerUrlUsesCleartextToRemoteHost("box.example.com"))
    assertFalse(ServerUrlUsesCleartextToRemoteHost(""))
    ' Scheme inference itself: the loopback broaden (127.0.0.1 used to infer
    ' https as a dotted quad failing every RFC1918 arm - cleartext on
    ' loopback is not a sniff class, and the README promised loopback http).
    assertEqual(NormalizeServerUrl("127.0.0.1:8096"), "http://127.0.0.1:8096")
    assertEqual(NormalizeServerUrl("box.example.com"), "https://box.example.com")
    assertEqual(NormalizeServerUrl("192.168.1.50"), "http://192.168.1.50")
    print "TestCleartextRemoteGateTruthTable passed"
end sub

sub TestOriginOfUrlNormalization()
    assertEqual(OriginOfUrl("https://H.Example.COM/api/v1/media"), "https://h.example.com")
    ' Default ports fold; non-default ports stay significant.
    assertEqual(OriginOfUrl("http://h:80/x"), "http://h")
    assertEqual(OriginOfUrl("https://h:443"), "https://h")
    assertEqual(OriginOfUrl("http://h:8096/x"), "http://h:8096")
    assertEqual(OriginOfUrl("https://h:8443"), "https://h:8443")
    ' IPv6 with and without a port.
    assertEqual(OriginOfUrl("http://[::1]:8096/api"), "http://[::1]:8096")
    ' Refusals: foreign scheme, no host, userinfo, junk port, unclosed bracket.
    assertEqual(OriginOfUrl("ftp://h/x"), "")
    assertEqual(OriginOfUrl("https:///x"), "")
    assertEqual(OriginOfUrl("https://user:pw@h/x"), "")
    assertEqual(OriginOfUrl("https://h:abc/x"), "")
    assertEqual(OriginOfUrl("https://[::1/x"), "")
    assertEqual(OriginOfUrl("h.example.com"), "")
    print "TestOriginOfUrlNormalization passed"
end sub

sub TestCredentialSafeRedirectHopLaw()
    ' Same origin, spelled with and without the default port, is followable.
    assertTrue(IsCredentialSafeRedirectHop("http://h:8096/a", "http://h:8096/b"))
    assertTrue(IsCredentialSafeRedirectHop("https://h/x", "https://h:443/y"))
    ' The one safe non-identical hop: same host, cleartext -> standard TLS.
    assertTrue(IsCredentialSafeRedirectHop("http://h.example/api", "https://h.example/login"))
    ' Every custody-relevant class is refused: cross-host, any port change,
    ' downgrade, weird-port upgrade, userinfo, malformed target.
    assertFalse(IsCredentialSafeRedirectHop("http://h.example/a", "http://evil.example/b"))
    assertFalse(IsCredentialSafeRedirectHop("http://h:8096/a", "http://h:9000/b"))
    assertFalse(IsCredentialSafeRedirectHop("https://h/a", "http://h/b"))
    assertFalse(IsCredentialSafeRedirectHop("http://h:8080/a", "https://h:8443/b"))
    assertFalse(IsCredentialSafeRedirectHop("http://h/a", "ftp://h/b"))
    assertFalse(IsCredentialSafeRedirectHop("http://h/a", "http://user@evil/"))
    assertFalse(IsCredentialSafeRedirectHop("http://h/a", ""))
    ' The hop budget is a live literal (CHECK48 pins the same value).
    assertEqual(RedirectHopLimit(), 3)
    print "TestCredentialSafeRedirectHopLaw passed"
end sub

sub TestResolveRedirectTargetShapes()
    ' Absolute passthrough (trimmed).
    assertEqual(ResolveRedirectTarget("https://h/api/x", "https://h/api/y"), "https://h/api/y")
    assertEqual(ResolveRedirectTarget("https://h/api/x", " HTTP://H:443/Z "), "HTTP://H:443/Z")
    ' Protocol-relative rides the SOURCE scheme.
    assertEqual(ResolveRedirectTarget("https://h/a", "//h2/b"), "https://h2/b")
    assertEqual(ResolveRedirectTarget("http://h:8096/a", "//h2/b"), "http://h2/b")
    ' Absolute path and bare relative ride the source origin (port kept).
    assertEqual(ResolveRedirectTarget("http://h:8096/a/b", "/c"), "http://h:8096/c")
    assertEqual(ResolveRedirectTarget("http://h:8096/a/b", "c"), "http://h:8096/a/b/c")
    ' Control chars and empties are malformed - never a re-issued request line.
    assertEqual(ResolveRedirectTarget("https://h/a", "/b" + Chr(13) + Chr(10) + "X-Injected: 1"), "")
    assertEqual(ResolveRedirectTarget("https://h/a", ""), "")
    assertEqual(ResolveRedirectTarget("https://h/a", invalid), "")
    assertEqual(ResolveRedirectTarget("gopher://h/a", "/b"), "")
    print "TestResolveRedirectTargetShapes passed"
end sub

sub TestRedirectBucketClassification()
    ' The client-minted refusal texts all land on the honest custody bucket -
    ' BEFORE the word "refused" could misfile them as a connection refusal.
    assertEqual(ClassifyUrlFailure("unsafe redirect refused (custody law: target is not the same origin)", true), "redirect_refused")
    assertEqual(ClassifyUrlFailure("redirect refused (malformed Location)", true), "redirect_refused")
    assertEqual(ClassifyUrlFailure("redirect refused (hop limit reached)", true), "redirect_refused")
    ' curl's own redirect-cap text (firmwares with an internal cap) too.
    assertEqual(ClassifyUrlFailure("Maximum (48) redirects followed", true), "redirect_refused")
    ' Sibling buckets untouched: a real connection refusal still reads as one.
    assertEqual(ClassifyUrlFailure("Couldn't connect to server", true), "refused")
    assertEqual(ClassifyUrlFailure("Could not resolve host: x", true), "dns")
    ' The transport guard admits the new bucket (restoreSession's keep arm).
    assertTrue(IsTransportReason("redirect_refused"))
    assertFalse(IsTransportReason("session_invalid"))
    print "TestRedirectBucketClassification passed"
end sub
