' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/ContentIdGuard.test.brs

' ===========================================
' Content-Id shape guard - unit tests
'
' Review roku__exploiter M2 (fix M-ROKU-13): the hub relay's pending_command
' frames arrive over a PLAINTEXT socket and ECP/launch deep-link args are
' attacker-settable, yet the play machinery fed their mediaId straight into
' ApiClient's "/media/" + itemId raw concatenation (only an invalid/"" check
' on the relay path; a printable-minus-"&" checker on the launch path).
' Shapes like x?profile=1, x#frag, x/../../admin/users therefore became
' arbitrary Bearer-authenticated GET paths issued by the victim's TV.
'
' The cure is the canonical guard in source/lib/Utilities.brs:
' IsSafeContentId() - type-gate, trim-form, length cap BEFORE the per-byte
' loop, then a strict [A-Za-z0-9_-] allowlist. It is applied at every entry
' (source/main.brs ValidateDeepLinkContentId delegates; PhlixApp
' OnPendingHubCommand ignores hostile frames) and at the single play choke
' (PhlixApp ProcessDeepLink fails visible). CHECK45 in
' scripts/verify-runtime.sh statically pins that wiring; the entry/choke
' functions live in component scope and are NOT callable from this harness
' (the WireGuard.test.brs precedent), so this suite pins the guard contract
' itself with the review's exact hostile shapes.
'
' Venue: rooibos on-device (`make test-unit` with ROKU_HOST); authored and
' compile-covered via `npx bsc` here, executed on a device/emulator host.
' ===========================================

sub TestIsSafeContentIdAcceptsRealIdShapes()
    ' What the estate actually ships: server media ids are CHAR(36) UUIDs,
    ' and the allowlist is deliberately one character class wider (partner
    ' ids with - / _ prefixes) while still rejecting every delimiter.
    assertTrue(IsSafeContentId("3f2504e0-4f89-11d3-9a0c-0305e4b66334"))
    assertTrue(IsSafeContentId("a1B2_-c9"))
    assertTrue(IsSafeContentId("0"))
    print "TestIsSafeContentIdAcceptsRealIdShapes passed"
end sub

sub TestIsSafeContentIdRejectsPathInjectionShapes()
    ' THE review class: each value survives the era's printable-only launch
    ' checker and the relay's invalid/"" check, then reshapes the outbound
    ' GET at "/media/" + itemId. Every URL structural byte must be red.
    assertFalse(IsSafeContentId("x/../../admin/users"))
    assertFalse(IsSafeContentId("x?profile=1"))
    assertFalse(IsSafeContentId("x#frag"))
    assertFalse(IsSafeContentId("x&extra=1"))
    assertFalse(IsSafeContentId("x=1"))
    assertFalse(IsSafeContentId("x%2f"))
    assertFalse(IsSafeContentId("x:y"))
    assertFalse(IsSafeContentId("x;1"))
    assertFalse(IsSafeContentId("a b"))
    assertFalse(IsSafeContentId("x."))
    print "TestIsSafeContentIdRejectsPathInjectionShapes passed"
end sub

sub TestIsSafeContentIdRejectsNonStringWireValues()
    ' A hostile frame can carry {"media_id":123} or an object/array where a
    ' string belongs. The guard never stringifies: a non-String is a contract
    ' violation and fails the shape law (mirrors SafeErrorMessage's posture).
    assertFalse(IsSafeContentId(invalid))
    assertFalse(IsSafeContentId(123))
    assertFalse(IsSafeContentId(1.5))
    assertFalse(IsSafeContentId(true))
    hostileAA = { "id": "x" }
    assertFalse(IsSafeContentId(hostileAA))
    hostileList = ["one", 2]
    assertFalse(IsSafeContentId(hostileList))
    print "TestIsSafeContentIdRejectsNonStringWireValues passed"
end sub

sub TestIsSafeContentIdRejectsEmptyAndControlAndHighBytes()
    assertFalse(IsSafeContentId(""))
    assertFalse(IsSafeContentId("   "))
    ' Control bytes and non-ASCII never survive: labels and paths both go.
    assertFalse(IsSafeContentId("a" + Chr(10) + "b"))
    assertFalse(IsSafeContentId("café"))
    print "TestIsSafeContentIdRejectsEmptyAndControlAndHighBytes passed"
end sub

sub TestIsSafeContentIdRejectsNulByte()
    ' Split arm (M-ROKU-15): brs collapses Chr(0) to the EMPTY string
    ' (measured Len(Chr(0))=0), so this input degrades to "ab" there and the
    ' assertion can only hold on a device, where Chr(0) is a real NUL byte
    ' the shape law rejects. Kept as its own test so the headless harness
    ' can EXCLUDE exactly this brs gap, not the whole guard suite.
    assertFalse(IsSafeContentId("a" + Chr(0) + "b"))
    print "TestIsSafeContentIdRejectsNulByte passed"
end sub

sub TestIsSafeContentIdTrimsForJudgmentOnly()
    ' CONTRACT (documented at the guard): the trimmed form is what is judged.
    ' Padding alone does not condemn an otherwise-real id; every gate site
    ' consumes the Trim()-ed value (main.brs ExtractDeepLinkParams forwards it
    ' trimmed; ProcessDeepLink fetches the trimmed copy).
    assertTrue(IsSafeContentId("  abc123  "))
    assertFalse(IsSafeContentId("  ab c  "))
    print "TestIsSafeContentIdTrimsForJudgmentOnly passed"
end sub

sub TestContentIdMaxLenIsPinnedLiteral()
    ' CHECK45 R1 pins the same literal statically; this keeps the device-side
    ' contract honest too (guard and law must agree on 255).
    assertEqual(ContentIdMaxLen(), 255)
    print "TestContentIdMaxLenIsPinnedLiteral passed"
end sub

sub TestIsSafeContentIdCapBoundaries()
    ' Length gate runs BEFORE the per-byte loop: exactly-cap passes, cap+1
    ' fails on a fully legal alphabet (the reject is the LENGTH, proving the
    ' cap arm is live and the loop never runs unbounded on megabyte strings).
    exact = ""
    for i = 1 to ContentIdMaxLen()
        exact = exact + "a"
    end for
    assertTrue(IsSafeContentId(exact))
    assertFalse(IsSafeContentId(exact + "b"))
    huge = exact + exact + exact
    assertFalse(IsSafeContentId(huge))
    print "TestIsSafeContentIdCapBoundaries passed"
end sub
