' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SyncPlayJoinCode.test.brs

' ===========================================
' JOIN-DIGEST CUSTODY - unit tests (MJ-2, deferred register)
'
' Review roku__casualgamer MJ-2: the Live Watch Together panel only joined
' groups the picker LISTED, and a password-protected room was a dead end -
' the join command carried no gate at all. The cure rides EXISTING frozen
' wire fields (SPEC §4 syncplay_group_join.password_hash; group ids are the
' shareable sp_* codes): a code form whose password arm feeds ONLY
' SyncPlayPasswordHash. These two leaves are the custody floor the scene and
' the task both call:
'   1. IsCanonicalPasswordHash() (source/lib/Utilities.brs): the exact
'      server shape - 64 chars, lowercase hex - gated CLIENT-side before a
'      digest can ride the socket (phlix-server GroupState::
'      isCanonicalPasswordHash refuses non-canonical, never coerces).
'   2. SyncPlayPasswordHash(): unsalted SHA-256 lowercase hex via roEVPDigest
'      (the VerifyHandshakeAccept sibling component), FAIL-CLOSED to "" on
'      every inability path - no component, Setup refusal, junk shape.
'      The plaintext never escapes the function.
'
' Venue: the digest half mirrors SyncPlayWsTls.test.brs - the brs headless
' harness does not implement roEVPDigest (probe: CreateObject returns
' invalid), so headless exercises the fail-closed arm while a device/
' emulator must produce the exact known SHA-256("password") vector. Both
' shapes are pinned in one test; a firmware that can neither compute nor
' honestly refuse is caught by the else-arms.
' ===========================================

sub TestIsCanonicalPasswordHashTruthTable()
    ' The canonical join-digest shape (SPEC §4; server byte-compare).
    assertTrue(IsCanonicalPasswordHash("5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8"), "vector must be canonical")
    assertTrue(IsCanonicalPasswordHash("0000000000000000000000000000000000000000000000000000000000000000"), "all-zero hex is canonical")
    assertTrue(IsCanonicalPasswordHash("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"), "all-f hex is canonical")
    ' Length: one off either side is junk.
    assertFalse(IsCanonicalPasswordHash("5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d"), "63 chars must refuse")
    assertFalse(IsCanonicalPasswordHash("5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d88"), "65 chars must refuse")
    ' CASE: uppercase hex is NOT canonical - the server byte-compares.
    assertFalse(IsCanonicalPasswordHash("5E884898DA28047151D0E56F8DC6292773603D0D6AABBDD62A11EF721D1542D8"), "uppercase hex must refuse")
    ' ALPHABET: any non-hex byte anywhere refuses.
    assertFalse(IsCanonicalPasswordHash("5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d_"), "underscore tail must refuse")
    assertFalse(IsCanonicalPasswordHash("sp_abc123def456xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"), "code-shaped junk must refuse")
    ' Empty / whitespace never canonical.
    assertFalse(IsCanonicalPasswordHash(""), "empty must refuse")
    assertFalse(IsCanonicalPasswordHash("5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8 "), "trailing space must refuse")
    print "TestIsCanonicalPasswordHashTruthTable passed"
end sub

sub TestSyncPlayPasswordHashEmptyRefused()
    ' A blank gate is not a gate: the scene only calls this for a NON-EMPTY
    ' password, and the leaf itself refuses "" (no accidental ""-hash of an
    ' empty field could ever match a real group digest law).
    assertEqual(SyncPlayPasswordHash(""), "")
    print "TestSyncPlayPasswordHashEmptyRefused passed"
end sub

sub TestSyncPlayPasswordHashCanonicalOrFailClosed()
    vector = "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8"
    h = SyncPlayPasswordHash("password")
    if h <> "" then
        ' Digest-capable firmware (every real Roku): the SHA-256 known vector,
        ' byte-exact, lowercase - and a second computation is deterministic.
        assertEqual(h, vector)
        assertTrue(IsCanonicalPasswordHash(h))
        assertEqual(SyncPlayPasswordHash("password"), h)
        ' Differing input, differing digest (collision theater guard).
        assertNotEqual(SyncPlayPasswordHash("password!"), h)
    else
        ' Headless brs (no roEVPDigest) and any future digest-less platform:
        ' the fail-closed arm is the LAW - "" means the caller must refuse the
        ' protected join outright (PlayerScene syncplay_status_hash_unavailable).
        assertEqual(h, "")
        assertEqual(SyncPlayPasswordHash("password!"), "")
    end if
    print "TestSyncPlayPasswordHashCanonicalOrFailClosed passed"
end sub

' ===========================================
' [W13L3 RT-041, review roku__secnet #5] The digest runs over RAW UTF-8
' BYTES with NO trim — SPEC §4's "unsalted SHA-256 hex of the password"
' evaluated against the byte-string the server's group gate hashes
' (PHP strings are byte strings). The pre-cure body used
' roByteArray.fromAsciiString, which ASCII-folds every code point >= 128:
' a non-ASCII password digested to a value the server could never
' reproduce, failing correct-password joins. The bytes now come from the
' shared Utf8BytesForCodePoint law (whose pure math is pinned live in
' Utilities2.test.brs). Same dual-shape venue idiom as the sibling
' canonical-or-fail-closed test: brs answers invalid for roEVPDigest, so
' headless walks the fail-closed arm while device/emulator must produce
' the byte-exact vectors.
' ===========================================

sub TestSyncPlayPasswordHashUtf8BytesDualShape()
    ' sha256(63 61 66 C3 A9) — the UTF-8 bytes of "café" ("caf" + U+00E9).
    ' The pre-cure fromAsciiString fold could NOT produce this value.
    cafeVector = "850f7dc43910ff890f8879c0ed26fe697c93a067ad93a7d50f466a7028a9bf4e"
    h = SyncPlayPasswordHash("caf" + Chr(233))
    if h <> "" then
        assertEqual(h, cafeVector)
        assertTrue(IsCanonicalPasswordHash(h))
        ' No-trim law: " pw " and "pw" are DIFFERENT passwords (the input
        ' Trim removed at base; this pins it stays removed).
        assertNotEqual(SyncPlayPasswordHash(" pw "), SyncPlayPasswordHash("pw"))
        assertEqual(SyncPlayPasswordHash("pw"), "30c952fab122c3f9759f02a6d95c3758b246b4fee239957b2d4fee46e26170c4")
    else
        ' Headless brs (no roEVPDigest) — fail-closed arm is still LAW.
        assertEqual(SyncPlayPasswordHash("caf" + Chr(233)), "")
        assertEqual(SyncPlayPasswordHash(" pw "), "")
    end if
    print "TestSyncPlayPasswordHashUtf8BytesDualShape passed"
end sub
