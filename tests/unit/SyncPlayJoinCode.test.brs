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
