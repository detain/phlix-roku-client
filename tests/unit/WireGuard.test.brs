' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/WireGuard.test.brs

' ===========================================
' Wire-Text Hostile-Input Guard - unit tests
'
' Review roku__exploiter M1 (fix M-ROKU-12): a hostile server or LAN injector
' answers {"error":123} / {"error":{"code":1}} and the render thread dies on
' the first String operation over the untyped value. The cure is the guard
' family in source/lib/Utilities.brs: SafeErrorMessage() type-gates ANY wire
' value (roString/String or typed fallback), caps it at WireErrorMessageMax()
' BEFORE the control-char strip loop, strips ASCII control chars, trims, and
' collapses whitespace-only input to the fallback. GetErrorMessage() rides
' the same guard before its legacy http_* map.
'
' These tests exercise the guards with the exact hostile shapes from the
' review. CHECK43 in scripts/verify-runtime.sh statically pins that no shipped
' .brs bypasses them; the component-scope task choke (DeriveResponseError /
' WireErrorPresent in components/ApiTask.brs) is not callable from the unit
' harness (component script scope) and is covered by CHECK43's R2 law pins
' instead.
' ===========================================

sub TestSafeErrorMessagePassesTypedStrings()
    ' A well-behaved wire string survives, trimmed.
    assertEqual(SafeErrorMessage("Bad credentials", "GENERIC"), "Bad credentials")
    assertEqual(SafeErrorMessage("  ok  ", "GENERIC"), "ok")
    print "TestSafeErrorMessagePassesTypedStrings passed"
end sub

sub TestSafeErrorMessageRejectsNonStringWireValues()
    ' THE crash class: parent code fed these into `<> ""`/concat and raised a
    ' runtime type mismatch. The guard returns the caller's typed fallback -
    ' a non-String is a contract violation, never partially rendered.
    assertEqual(SafeErrorMessage(123, "GENERIC"), "GENERIC")
    assertEqual(SafeErrorMessage(1.5, "GENERIC"), "GENERIC")
    assertEqual(SafeErrorMessage(true, "GENERIC"), "GENERIC")
    assertEqual(SafeErrorMessage(invalid, "GENERIC"), "GENERIC")
    hostileAA = { "code": 1 }
    assertEqual(SafeErrorMessage(hostileAA, "GENERIC"), "GENERIC")
    hostileList = ["one", 2]
    assertEqual(SafeErrorMessage(hostileList, "GENERIC"), "GENERIC")
    print "TestSafeErrorMessageRejectsNonStringWireValues passed"
end sub

sub TestSafeErrorMessageFallsBackOnEmptyAndWhitespace()
    ' Empty and control-only text carries no information: fallback, not "".
    assertEqual(SafeErrorMessage("", "GENERIC"), "GENERIC")
    assertEqual(SafeErrorMessage("   ", "GENERIC"), "GENERIC")
    assertEqual(SafeErrorMessage(Chr(0) + Chr(10) + Chr(9), "GENERIC"), "GENERIC")
    print "TestSafeErrorMessageFallsBackOnEmptyAndWhitespace passed"
end sub

sub TestSafeErrorMessageCapsHostileLength()
    ' A multi-kilobyte "error" is noise, not information: capped at
    ' WireErrorMessageMax() with a visible ellipsis tail (display honesty).
    big = ""
    for i = 1 to 1200
        big = big + "x"
    end for
    out = SafeErrorMessage(big, "GENERIC")
    assertTrue(Len(out) = WireErrorMessageMax())
    assertEqual(Mid(out, WireErrorMessageMax(), 1), "…")
    ' A string at exactly the cap is untouched (no off-by-one truncation).
    exact = ""
    for i = 1 to WireErrorMessageMax()
        exact = exact + "y"
    end for
    assertEqual(Len(SafeErrorMessage(exact, "GENERIC")), WireErrorMessageMax())
    print "TestSafeErrorMessageCapsHostileLength passed"
end sub

sub TestSafeErrorMessageStripsControlChars()
    ' CR/LF/TAB/NUL/DEL never reach a Label: single-line chrome stays intact.
    mixed = "line1" + Chr(13) + Chr(10) + "line2" + Chr(0) + Chr(9) + "!" + Chr(127)
    assertEqual(SafeErrorMessage(mixed, "GENERIC"), "line1line2!")
    print "TestSafeErrorMessageStripsControlChars passed"
end sub

sub TestWireErrorMessageMaxIsPinnedLiteral()
    ' CHECK43 R2 pins the same literal statically; this keeps the device-side
    ' contract honest too (guard and law must agree on 300).
    assertEqual(WireErrorMessageMax(), 300)
    print "TestWireErrorMessageMaxIsPinnedLiteral passed"
end sub

sub TestGetErrorMessageSurvivesHostileEnvelopes()
    ' The scenes' legacy helper now rides the guard: hostile non-String values
    ' degrade to the generic text instead of raising at the http_ compare.
    generic = "An error occurred. Please try again."
    assertEqual(GetErrorMessage(123), generic)
    hostileAA = { "code": 1 }
    assertEqual(GetErrorMessage(hostileAA), generic)
    assertEqual(GetErrorMessage(invalid), generic)
    assertEqual(GetErrorMessage(""), generic)
    ' Well-behaved values keep their mapped semantics.
    assertEqual(GetErrorMessage("http_401"), "You are not logged in. Please sign in again.")
    assertEqual(GetErrorMessage("http_404"), "The requested item was not found.")
    ' M-ROKU-03 (review roku__webux, shipped in W-min89) is the NEWER law for
    ' everything else: server prose is not user copy. A non-transport string
    ' is printed for diagnostics and replaced by the generic caption — the
    ' old pass-through expectation this suite shipped with is extinct.
    assertEqual(GetErrorMessage("Bad credentials"), generic)
    print "TestGetErrorMessageSurvivesHostileEnvelopes passed"
end sub

sub TestGetErrorMessageTraversesGuardBeforeMap()
    ' A hostile long string is capped BEFORE the http_ compare and a control
    ' char inside cannot split the sink: order of the choke is observable.
    padded = "  http_401  " + Chr(10)
    assertEqual(GetErrorMessage(padded), "You are not logged in. Please sign in again.")
    long = "http_"
    for i = 1 to 400
        long = long + "9"
    end for
    ' 400+5 chars: capped to 300 with ellipsis, still an unknown http_ code,
    ' so it lands on the generic arm of the map - never raw-rendered.
    assertEqual(GetErrorMessage(long), "An error occurred. Please try again.")
    print "TestGetErrorMessageTraversesGuardBeforeMap passed"
end sub
