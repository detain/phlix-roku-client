' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/HubRelayOriginLaw.test.brs

' ===========================================
' Hub relay plaintext-origin law - unit tests (M-ROKU-23)
'
' Review roku__secnet M2: StartHubCommandConsumer stripped the hub URL's
' scheme and dialed the FIXED plaintext :8804 relay listener regardless of the
' hub origin, carrying the hub MINTED relay token (Authorization: Bearer on
' the raw RFC6455 handshake) across cleartext while the hub's own identity was
' TLS — a passive path sniffer could capture a live push-into-the-session
' credential AND inject "Alexa, play X" commands behind an https hub.
'
' The cure is the M-ROKU-14 doctrine on the relay leg: HubRelayCleartext
' RefusedForOrigin() (source/lib/Utilities.brs) refuses the dial for an
' https:// origin BEFORE the credential is read, at BOTH the scene choke and
' the task; CHECK55 in scripts/verify-runtime.sh statically pins the wiring
' and the refuse-before-token order. The wss arm via roSecureSocket is
' DEFERRED with disclosure (hub-side GET /syncplay/ TLS route exists today),
' not declared impossible.
'
' The predicate is a source/lib global using ONLY documented surfaces:
' global LCase/Left + the ifStringOps Trim member. No member .Mid (0-based on
' the platform vs 1-based globals) and no member .Lower (NOT a Roku string
' method at all — see the M-ROKU-23 fixlog Observations) anywhere in this
' family's law code.
'
' Venue: rooibos on-device (`make test-unit` with ROKU_HOST); authored and
' compile-covered via `npx bsc` here. The same truth table was executed under
' the brs interpreter in the fix lane (pure globals run for real) — output
' recorded in .reviews/fixlog/M-ROKU-23__fix.md.
' ===========================================

sub TestHubRelayCleartextRefusedForOriginTruthTable()
    ' The exploitable class: minted relay token on a cleartext socket behind
    ' a TLS hub identity.
    assertTrue(HubRelayCleartextRefusedForOrigin("https://hub.example.com"))
    assertTrue(HubRelayCleartextRefusedForOrigin("https://hub.example.com:8443"))
    assertTrue(HubRelayCleartextRefusedForOrigin("HTTPS://Hub.Example.COM"))
    assertTrue(HubRelayCleartextRefusedForOrigin("  https://hub.example.com  "))
    ' http / legacy origins keep dialling (their REST lane is already
    ' cleartext — no NEW exposure class; behavior identical to pre-cure).
    assertFalse(HubRelayCleartextRefusedForOrigin("http://hub.example.com"))
    assertFalse(HubRelayCleartextRefusedForOrigin("http://192.168.1.5:8080"))
    ' "" / whitespace / invalid / scheme-less speak through the caller's own
    ' empty guards (unchanged legacy dial path for scheme-less rows).
    assertFalse(HubRelayCleartextRefusedForOrigin(""))
    assertFalse(HubRelayCleartextRefusedForOrigin("   "))
    assertFalse(HubRelayCleartextRefusedForOrigin("hub.example.com:8804"))
    ' Near-miss schemes must NOT refuse (the law is exactly "https://").
    assertFalse(HubRelayCleartextRefusedForOrigin("https:/hub.example.com"))
    assertFalse(HubRelayCleartextRefusedForOrigin("httpss://hub.example.com"))
    assertFalse(HubRelayCleartextRefusedForOrigin("ws://hub.example.com"))
end sub
