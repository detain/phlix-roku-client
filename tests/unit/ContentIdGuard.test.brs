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
'
' RT-093 [W16L5, this review's #2] extends the file. The scene routing gates
' stay static-pinned (CHECK102 in scripts/verify-runtime.sh — component-scope
' subs, the WireGuard precedent stands), but the TRANSPORT law is a pair of
' PURE functions in components/ApiTask.brs riding the harness door
' (EXTRA_SOURCES.ContentIdGuard), so every limb — op-set membership, the
' per-op field mapping, gate inertness, the UrlEncode second layer, and the
' numeric-crash class — is EXECUTED here, and every crafted hostile input
' carries its own premise-falsification pin (estate law 2026-11: a lying
' fixture must redden at its pin, never silently green).
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

' ===========================================
' RT-093 [W16L5] — the ApiTask transport choke, executed.
' The two functions under test ride the EXTRA_SOURCES.ContentIdGuard door;
' they are pure (no m.top, no network), so every limb below is a real call.
' ===========================================

sub TestRt093OpSetMembership()
    ' Every id-carrying dispatch op must be in the gated set: the list here
    ' mirrors ApiTask's request-dict law EXACTLY (CHECK102 pins the function
    ' shape; this pins its membership by execution).
    gated = ["getItem", "getItemPlaybackInfo", "getItemSimilar", "startTranscode", "favorite", "unfavorite", "setRating", "clearRating", "markWatched", "markUnwatched", "like", "reportProgress", "getCollection", "addToCollection", "removeFromCollection"]
    for each op in gated
        assertTrue(OpCarriesContentId(op), "op not gated: " + op)
    end for
    ' Non-id ops and near-miss spellings must NOT be gated (a prefix bug
    ' would silently widen the refusal surface onto unrelated traffic).
    assertFalse(OpCarriesContentId("getLibraries"))
    assertFalse(OpCarriesContentId("getFavorites"))
    assertFalse(OpCarriesContentId("search"))
    assertFalse(OpCarriesContentId("logout"))
    assertFalse(OpCarriesContentId("getItemX"))
    assertFalse(OpCarriesContentId("getItems"))
    assertFalse(OpCarriesContentId(""))
    assertFalse(OpCarriesContentId(invalid))
    assertFalse(OpCarriesContentId(123))
    print "TestRt093OpSetMembership passed"
end sub

function Rt093GoodId() as String
    return "3f2504e0-4f89-11d3-9a0c-0305e4b66334"
end function

sub TestRt093ItemIdFamilyRefusals()
    ' Representative limb per itemId-family op shape: good passes, a
    ' delimiter-bearing id refuses, a MISSING id refuses (absence is
    ' hostility — an op that must carry an id and does not must never
    ' reach concat), and the numeric wire value refuses (the exact class
    ' that raised the task-thread Type Mismatch before any response).
    ops = ["getItem", "getItemPlaybackInfo", "getItemSimilar", "startTranscode", "favorite", "unfavorite", "setRating", "clearRating", "markWatched", "markUnwatched", "like"]
    for each op in ops
        assertFalse(ContentIdRequestRefused({ op: op, itemId: Rt093GoodId() }))
        assertTrue(ContentIdRequestRefused({ op: op, itemId: "a/../../b" }))
        assertTrue(ContentIdRequestRefused({ op: op }))
        assertTrue(ContentIdRequestRefused({ op: op, itemId: 42 }))
    end for
    print "TestRt093ItemIdFamilyRefusals passed"
end sub

sub TestRt093FieldMappingLimbs()
    ' Each special-shaped op reads the field the law says it reads — the
    ' mapping itself is a limb (a copy-paste field name here silently
    ' checks invalid every time: both refusal AND admit would "work").
    ' reportProgress keys off mediaItemId, NOT itemId.
    assertFalse(ContentIdRequestRefused({ op: "reportProgress", mediaItemId: Rt093GoodId() }))
    assertTrue(ContentIdRequestRefused({ op: "reportProgress", mediaItemId: "x?y=1" }))
    ' getCollection keys off collectionId, NOT itemId.
    assertFalse(ContentIdRequestRefused({ op: "getCollection", collectionId: Rt093GoodId() }))
    assertTrue(ContentIdRequestRefused({ op: "getCollection", collectionId: "x#frag" }))
    ' The two collection writes judge BOTH fields: each alone convicts.
    good = Rt093GoodId()
    assertTrue(ContentIdRequestRefused({ op: "addToCollection", collectionId: "x&extra=1", itemId: good }))
    assertTrue(ContentIdRequestRefused({ op: "addToCollection", collectionId: good, itemId: "x&extra=1" }))
    assertFalse(ContentIdRequestRefused({ op: "addToCollection", collectionId: good, itemId: good }))
    assertTrue(ContentIdRequestRefused({ op: "removeFromCollection", collectionId: "x&extra=1", itemId: good }))
    assertTrue(ContentIdRequestRefused({ op: "removeFromCollection", collectionId: good, itemId: "x&extra=1" }))
    assertFalse(ContentIdRequestRefused({ op: "removeFromCollection", collectionId: good, itemId: good }))
    print "TestRt093FieldMappingLimbs passed"
end sub

sub TestRt093GateInertness()
    ' The gate must not over-convict: an unrelated op carrying a hostile
    ' itemId stays INERT (the transport law is scoped by op membership, so
    ' no dispatch that consumes no id is ever blocked by it).
    assertFalse(ContentIdRequestRefused({ op: "getLibraries", itemId: "a/../../b" }))
    assertFalse(ContentIdRequestRefused({ op: "search", q: "anything" }))
    ' Non-AA and missing-op requests refuse nothing (fail-open to the
    ' existing dispatcher; these shapes cannot interpolate an id anyway).
    assertFalse(ContentIdRequestRefused(invalid))
    assertFalse(ContentIdRequestRefused({}))
    print "TestRt093GateInertness passed"
end sub

sub TestRt093UrlEncodeIdentityOnAdmittedAlphabet()
    ' CONTRACT-BRIDGE limb (the second layer is FREE on law-abiding ids):
    ' UrlEncode's unreserved set fully covers IsSafeContentId's allowlist,
    ' so encoding changes NOTHING for every id the gate admits — which is
    ' why wrapping the concat sites moves zero bytes on real traffic.
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-."
    assertTrue(IsSafeContentId("3f2504e0-4f89-11d3-9a0c-0305e4b66334"))
    assertEqual(UrlEncode(Rt093GoodId()), Rt093GoodId())
    sample = "a1B2_-c9"
    assertTrue(IsSafeContentId(sample))
    assertEqual(UrlEncode(sample), sample)
    ' '.' is UrlEncode-inert yet gate-rejected (allowlist is stricter than
    ' RFC3986): the pin documents which direction the contract runs.
    assertTrue(letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.")
    assertFalse(IsSafeContentId("x."))
    assertEqual(UrlEncode("x."), "x.")
    print "TestRt093UrlEncodeIdentityOnAdmittedAlphabet passed"
end sub

sub TestRt093UrlEncodeNeutralizesSurvivors()
    ' PREMISE-FALSIFICATION family: each crafted string must PROVE it
    ' carries the delimiter raw before the encoded form is demanded to be
    ' delimiter-free; a fixture that stopped containing '/' would silently
    ' green the whole second layer.
    rawSlash = "a/../../b"
    assertTrue(Instr(1, rawSlash, "/") > 0)
    enc = UrlEncode(rawSlash)
    assertEqual(Instr(1, enc, "/"), 0)
    rawQuery = "x?profile=1"
    assertTrue(Instr(1, rawQuery, "?") > 0)
    enc = UrlEncode(rawQuery)
    assertEqual(Instr(1, enc, "?"), 0)
    assertEqual(Instr(1, enc, "="), 0)
    rawFrag = "x#frag"
    assertTrue(Instr(1, rawFrag, "#") > 0)
    assertEqual(Instr(1, UrlEncode(rawFrag), "#"), 0)
    rawSpace = "a b"
    assertTrue(Instr(1, rawSpace, " ") > 0)
    assertEqual(Instr(1, UrlEncode(rawSpace), " "), 0)
    ' '%' is itself escaped (% -> %25): pre-encoded smuggling cannot wear
    ' the shape of a safe path byte.
    assertEqual(UrlEncode("50%"), "50%25")
    print "TestRt093UrlEncodeNeutralizesSurvivors passed"
end sub

function Rt093CountChar(s as String, c as String) as Integer
    n = 0
    for i = 1 to Len(s)
        if Mid(s, i, 1) = c then n = n + 1
    end for
    return n
end function

sub TestRt093DoubleLayerContractChain()
    ' End-to-end by execution for the review's FOUR named shapes: layer 1
    ' (gate refuses the request dict; scene code paths judge the same call),
    ' layer 2 (even a survivor's ENCODED path keeps exactly the two static
    ' slashes of '/media/' — no traversal bytes left to reshape it).
    shapes = ["x/../../admin/users", "x?profile=1", "x#frag", "x&extra=1"]
    for each shape in shapes
        assertFalse(IsSafeContentId(shape))
        assertTrue(ContentIdRequestRefused({ op: "getItem", itemId: shape }))
        path = "/media/" + UrlEncode(shape)
        assertEqual(Rt093CountChar(path, "/"), 2)
        assertEqual(Rt093CountChar(path, "?"), 0)
        assertEqual(Rt093CountChar(path, "#"), 0)
        assertEqual(Rt093CountChar(path, "&"), 0)
    end for
    print "TestRt093DoubleLayerContractChain passed"
end sub

sub TestRt093NumericValueCrashClassPins()
    ' The task-thread Type Mismatch class, pinned at BOTH layers: the
    ' shape law says 42 is not an id, and the transport choke refuses the
    ' exact dict {op:"getItem", itemId:42} that once crashed String +
    ' Integer at the raw concat BEFORE m.top.response could be written
    ' (the latch-forever root).
    assertFalse(IsSafeContentId(42))
    assertTrue(ContentIdRequestRefused({ op: "getItem", itemId: 42 }))
    ' A numeric STRING survives nothing new: digits are legal id bytes, so
    ' "42" is admitted exactly like a UUID would be (the law is about
    ' DELIMITERS and TYPES, not about id content).
    assertTrue(IsSafeContentId("42"))
    assertFalse(ContentIdRequestRefused({ op: "getItem", itemId: "42" }))
    print "TestRt093NumericValueCrashClassPins passed"
end sub
