' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SyncPlayErrors.test.brs

' ===========================================
' W5 syncplay error localisation - pure-function tests.
' Assertions here are device-independent: they hold whether or not the locale
' catalog loaded (Translate key-echo path included), except where noted.
' ===========================================

' ---- SyncPlayErrorCodeToKey: the MAPPING LAW ----

sub TestSyncPlayErrorCodeToKeyLegacyScreaming()
    ' Legacy SCREAMING codes lowercase into errors_<lower>
    assertEqual(SyncPlayErrorCodeToKey("NOT_IN_GROUP"), "errors_not_in_group")
    assertEqual(SyncPlayErrorCodeToKey("NOT_AUTHENTICATED"), "errors_not_authenticated")
    assertEqual(SyncPlayErrorCodeToKey("PROTOCOL_VERSION_MISMATCH"), "errors_protocol_version_mismatch")
    print "TestSyncPlayErrorCodeToKeyLegacyScreaming passed"
end sub

sub TestSyncPlayErrorCodeToKeyDottedRegistry()
    ' Dotted registry twins: lowercase + "." -> "_"
    assertEqual(SyncPlayErrorCodeToKey("syncplay.group_full"), "errors_syncplay_group_full")
    assertEqual(SyncPlayErrorCodeToKey("syncplay.group_limit_reached"), "errors_syncplay_group_limit_reached")
    assertEqual(SyncPlayErrorCodeToKey("syncplay.invalid_password"), "errors_syncplay_invalid_password")
    assertEqual(SyncPlayErrorCodeToKey("syncplay.group_not_found"), "errors_syncplay_group_not_found")
    print "TestSyncPlayErrorCodeToKeyDottedRegistry passed"
end sub

sub TestSyncPlayErrorCodeToKeyDottedFlipTwins()
    ' Twin-flip law (prep #90, flip landed 9b2394ee): the dotted forms ride
    ' the SAME law as the live dotted codes - both shapes of the flip resolve,
    ' current servers speak dotted, pre-flip servers speak SCREAMING.
    assertEqual(SyncPlayErrorCodeToKey("syncplay.create_failed"), "errors_syncplay_create_failed")
    assertEqual(SyncPlayErrorCodeToKey("syncplay.join_failed"), "errors_syncplay_join_failed")
    assertEqual(SyncPlayErrorCodeToKey("syncplay.leave_failed"), "errors_syncplay_leave_failed")
    ' The legacy SCREAMING trio the flip retired (current emits) still maps to its OWN keys:
    ' the two families never collide (the point of keeping both in the census).
    assertEqual(SyncPlayErrorCodeToKey("CREATE_FAILED"), "errors_create_failed")
    assertEqual(SyncPlayErrorCodeToKey("JOIN_FAILED"), "errors_join_failed")
    assertEqual(SyncPlayErrorCodeToKey("LEAVE_FAILED"), "errors_leave_failed")
    print "TestSyncPlayErrorCodeToKeyDottedFlipTwins passed"
end sub

sub TestSyncPlayErrorCodeToKeyNormalizesNoise()
    ' Case-insensitive, trims space padding, dash maps like dot. (BrightScript
    ' string literals have no \t escape — an earlier version of this arm
    ' carried a literal backslash-t, which is ordinary noise text, not
    ' padding; the padding arms below use real spaces.)
    assertEqual(SyncPlayErrorCodeToKey("  Not_Host  "), "errors_not_host")
    assertEqual(SyncPlayErrorCodeToKey("syncplay.GROUP-FULL"), "errors_syncplay_group_full")
    print "TestSyncPlayErrorCodeToKeyNormalizesNoise passed"
end sub

sub TestSyncPlayErrorCodeToKeyTotal()
    ' Illegal states parse to the fallback key - never a crash, never ""
    assertEqual(SyncPlayErrorCodeToKey(invalid), "errors_fallback")
    assertEqual(SyncPlayErrorCodeToKey(""), "errors_fallback")
    assertEqual(SyncPlayErrorCodeToKey("   "), "errors_fallback")
    assertEqual(SyncPlayErrorCodeToKey(42), "errors_fallback")
    print "TestSyncPlayErrorCodeToKeyTotal passed"
end sub

' ---- SyncPlayKnownErrorCodes: the CI guard's anchor ----

sub TestSyncPlayKnownErrorCodesSet()
    codes = SyncPlayKnownErrorCodes()
    ' Wire-honesty split: 20 emitted-verified + 0 declared-reserved = 20.
    ' The 2026-09-25 twin flip (phlix-server 9b2394ee) promoted the reserved
    ' trio; W-min92 promoted syncplay.queue_limit_exceeded on live emission
    ' evidence (phlix-server 7baa398a, sendError at SyncPlayManager.php:1254);
    ' the reserved arm stays armed for the next flip-pending code.
    assertEqual(codes.count(), 20)
    ' Law output must be collision-free across the two code families
    seen = {}
    for each code in codes
        key = SyncPlayErrorCodeToKey(code)
        assertEqual(seen.doesExist(key), false)
        seen[key] = true
    end for
    ' Family census: 12 legacy SCREAMING (9 current + 3 pre-flip-only, kept
    ' for old-server resolution), 8 dotted registry (all emitted-verified -
    ' the 9b2394ee seven plus queue_limit_exceeded since 7baa398a) - the split
    ' Check 22 content-pins in CI.
    screaming = 0
    dotted = 0
    for each code in codes
        if Instr(1, code, ".") > 0
            dotted++
        else
            screaming++
        end if
    end for
    assertEqual(screaming, 12)
    assertEqual(dotted, 8)
    print "TestSyncPlayKnownErrorCodesSet passed"
end sub

sub TestSyncPlayReservedErrorCodesSet()
    ' The reservation ledger is EMPTY since the 2026-09-25 twin flip: its
    ' only entry (the dotted create/join/leave trio) was promoted to
    ' emitted-verified with server evidence at phlix-server 9b2394ee
    ' (SyncPlayManager.php:1588/1627/1659). The function is KEPT as the
    ' declaration-before-census-entry gate - Check 22's reserved legs stay
    ' armed. The shape/membership invariants below are vacuous on the empty
    ' set today and bite the moment a flip-pending code is declared: dotted
    ' registry name, wire-census member, never a local code.
    reserved = SyncPlayReservedErrorCodes()
    assertEqual(reserved.count(), 0)
    wireSeen = {}
    for each code in SyncPlayKnownErrorCodes()
        wireSeen[code] = true
    end for
    localSeen = {}
    for each code in SyncPlayLocalErrorCodes()
        localSeen[code] = true
    end for
    for each code in reserved
        assertTrue(Left(LCase(code), 9) = "syncplay.")
        assertEqual(wireSeen.doesExist(code), true)
        assertEqual(localSeen.doesExist(code), false)
    end for
    print "TestSyncPlayReservedErrorCodesSet passed"
end sub

sub TestSyncPlayFlipTwinsInWireCensus()
    ' The twin flip LANDED (phlix-server PR #798 @ 9b2394ee, 2026-09-25):
    ' current servers send the dotted trio, pre-flip servers still send the
    ' SCREAMING trio. Both shapes stay census members - the dual map retires
    ' a family only when its servers do.
    trio = ["syncplay.create_failed", "syncplay.join_failed", "syncplay.leave_failed"]
    legacy = ["CREATE_FAILED", "JOIN_FAILED", "LEAVE_FAILED"]
    wireSeen = {}
    for each code in SyncPlayKnownErrorCodes()
        wireSeen[code] = true
    end for
    for each code in trio
        assertEqual(wireSeen.doesExist(code), true)
    end for
    for each code in legacy
        assertEqual(wireSeen.doesExist(code), true)
    end for
    print "TestSyncPlayFlipTwinsInWireCensus passed"
end sub

' ---- LocalizeSyncPlayError: priority chain ----

sub TestLocalizeSyncPlayErrorUnknownCodeUsesServerMessage()
    ' Unknown code + server text -> text verbatim (debug fallback).
    ' Holds in both catalog states: a miss echoes the key and we fall through.
    assertEqual(LocalizeSyncPlayError("SOME_FUTURE_CODE", "raw server text"), "raw server text")
    print "TestLocalizeSyncPlayErrorUnknownCodeUsesServerMessage passed"
end sub

sub TestLocalizeSyncPlayErrorEmptyCodeUsesServerMessage()
    assertEqual(LocalizeSyncPlayError(invalid, "Connect failed"), "Connect failed")
    assertEqual(LocalizeSyncPlayError("", "Socket unavailable"), "Socket unavailable")
    print "TestLocalizeSyncPlayErrorEmptyCodeUsesServerMessage passed"
end sub

sub TestLocalizeSyncPlayErrorKnownCodeNeverEmpty()
    ' A known code always resolves to non-empty text: catalog hit, or server
    ' message, or fallback - in a loaded-catalog device run this returns the
    ' localized line for the active locale.
    result = LocalizeSyncPlayError("NOT_HOST", "server english")
    assertTrue(result <> "")
    result2 = LocalizeSyncPlayError("syncplay.group_full", "")
    assertTrue(result2 <> "")
    print "TestLocalizeSyncPlayErrorKnownCodeNeverEmpty passed"
end sub

' ---- CLIENT-GENERATED local.* FAMILY (Check 23's runtime mirror) ----

sub TestSyncPlayLocalErrorCodesCensus()
    ' The local census is non-empty and pinned - same discipline as the
    ' wire census. Every member carries the reserved "local." mint prefix.
    ' M-ROKU-14 rotated the pin 9 -> 10: local.ws_accept_invalid joined the
    ' family when the :8097 dial gained its fail-closed Sec-WebSocket-Accept
    ' proof (a refused handshake proof is its own client-minted class, never
    ' a wire code - Check 22's wire census stays untouched (local codes never join it)).
    codes = SyncPlayLocalErrorCodes()
    assertEqual(codes.count(), 10)
    for each code in codes
        assertTrue(Left(code, 6) = "local.")
    end for
    print "TestSyncPlayLocalErrorCodesCensus passed"
end sub

sub TestSyncPlayErrorCodeToKeyLocalFamily()
    ' local.* codes ride the SAME mapping law as wire codes.
    assertEqual(SyncPlayErrorCodeToKey("local.connect_failed"), "errors_local_connect_failed")
    assertEqual(SyncPlayErrorCodeToKey("local.room_create_failed"), "errors_local_room_create_failed")
    assertEqual(SyncPlayErrorCodeToKey("LOCAL.NO_HOST"), "errors_local_no_host")
    print "TestSyncPlayErrorCodeToKeyLocalFamily passed"
end sub

sub TestSyncPlayFamiliesAreDisjoint()
    ' SEPARATION LAW: the wire census never carries a minted local code, the
    ' local census never collides onto a wire key, and no local code is a
    ' duplicate within its own family.
    wireSeen = {}
    for each code in SyncPlayKnownErrorCodes()
        assertTrue(Left(LCase(code), 6) <> "local.")
        wireSeen[SyncPlayErrorCodeToKey(code)] = true
    end for
    localSeen = {}
    for each code in SyncPlayLocalErrorCodes()
        key = SyncPlayErrorCodeToKey(code)
        assertEqual(localSeen.doesExist(key), false)
        localSeen[key] = true
        assertEqual(wireSeen.doesExist(key), false)
    end for
    print "TestSyncPlayFamiliesAreDisjoint passed"
end sub

sub TestLocalizeSyncPlayLocalErrorNeverEmpty()
    ' Device-independent (holds in both catalog states): a census member, an
    ' unknown local code, and total garbage all resolve to NON-EMPTY text -
    ' catalog line, errors_fallback line, or key echo. The task thread has no
    ' other channel, so blank would be a silent failure.
    for each code in SyncPlayLocalErrorCodes()
        assertTrue(LocalizeSyncPlayLocalError(code) <> "")
    end for
    assertTrue(LocalizeSyncPlayLocalError("local.not_a_real_code") <> "")
    assertTrue(LocalizeSyncPlayLocalError(invalid) <> "")
    assertTrue(LocalizeSyncPlayLocalError(42) <> "")
    print "TestLocalizeSyncPlayLocalErrorNeverEmpty passed"
end sub

' ================================================================
' W14L1 LW-034 [minor] - the error-code census gets its CROSS-REPO
' pin. tests/fixtures/error-codes.json is a byte-for-byte vendor of
' @phlix/contracts dist/error-codes.json (trio md5 5d1783a7... held);
' the harness stages tests/fixtures into the brs root so the REAL
' bytes are parsed here - not a transcribed twin (fixture-vs-fixture
' is the vacuity class this law forbids). Registry integrity (md5) is
' convicted by Check 99 R1 in scripts/verify-runtime.sh; equality and
' containment below are convicted HERE, device-side semantics intact.
' ================================================================

sub SyncPlayFixtureCodes(codesOut as Object)
    raw = ReadAsciiFile("pkg:/tests/fixtures/error-codes.json")
    codesOut.arr = invalid
    if raw = invalid or Len(raw) = 0 then return
    reg = ParseJson(raw)
    if reg = invalid then return
    codesOut.arr = reg.codes
end sub

' Family filter over the RAW registry list: "syncplay" -> the dotted
' syncplay.* specialization family; "screaming" -> the bare (no-dot)
' carrier set. Everything else in the registry belongs to other wire
' domains and must not leak into either leg.
function SyncPlayFixtureFamily(codes as Object, family as String) as Object
    out = []
    for each c in codes
        if family = "syncplay" then
            if Left(c, 9) = "syncplay." then out.Push(c)
        else if family = "screaming" then
            if InStr(1, c, ".") = 0 then out.Push(c)
        end if
    end for
    return out
end function

sub TestSyncPlayFixtureVendsTheContractsRegistry()
    holder = {}
    SyncPlayFixtureCodes(holder)
    codes = holder.arr
    ' If this reddens, the harness stopped staging tests/fixtures (the
    ' file is pinned by Check 99 too - the pin fails LOUD, never silently).
    assertTrue(codes <> invalid)
    ' 205 wire codes (line-vs-code honesty: the registry file carries
    ' 205 ENTRIES; 210 was the route-manifest-era line count in the
    ' console twin - the count this gate pins is the CODE count).
    assertEqual(codes.Count(), 205)
    fam = SyncPlayFixtureFamily(codes, "syncplay")
    assertEqual(fam.Count(), 8)
    print "TestSyncPlayFixtureVendsTheContractsRegistry passed"
end sub

sub TestSyncPlayCensusDottedEqualsRegistrySyncplayFamily()
    holder = {}
    SyncPlayFixtureCodes(holder)
    codes = holder.arr
    assertTrue(codes <> invalid)
    registrySync = SyncPlayFixtureFamily(codes, "syncplay")
    censusDotted = []
    for each c in SyncPlayKnownErrorCodes()
        if Left(c, 9) = "syncplay." then censusDotted.Push(c)
    end for
    ' Set equality, both directions. A registry addition (a new syncplay
    ' specialization) reddens the first loop until the census maps it; a
    ' retired/dropped census code reddens the second.
    assertEqual(censusDotted.Count(), registrySync.Count())
    for each c in censusDotted
        found = false
        for each r in registrySync
            if r = c then found = true
        end for
        assertTrue(found)
    end for
    for each r in registrySync
        found2 = false
        for each c in censusDotted
            if r = c then found2 = true
        end for
        assertTrue(found2)
    end for
    print "TestSyncPlayCensusDottedEqualsRegistrySyncplayFamily passed"
end sub

sub TestSyncPlayCensusScreamingContainedInRegistry()
    ' CONTAINMENT (console LW-090-b law 3, mirrored): every SCREAMING
    ' carrier the census maps is a real registry code. The registry's
    ' bare (non-dotted) half spans OTHER wire domains too - 76 members
    ' measured in the vendored artifact, 64 of them non-syncplay
    ' snake_case codes this client never speaks - so the law here is
    ' one-directional on purpose; the syncplay.* family above is where
    ' the law is full set-equality.
    holder = {}
    SyncPlayFixtureCodes(holder)
    codes = holder.arr
    assertTrue(codes <> invalid)
    registryBare = SyncPlayFixtureFamily(codes, "screaming")
    assertEqual(registryBare.Count(), 76)
    censusScreaming = []
    for each c in SyncPlayKnownErrorCodes()
        if Left(c, 9) <> "syncplay." then censusScreaming.Push(c)
    end for
    ' 12 = 9 live + 3 pre-flip legacy twins (the twin-flip dual map).
    assertEqual(censusScreaming.Count(), 12)
    for each s in censusScreaming
        assertTrue(InStr(1, s, ".") = 0)
        found = false
        for each r in registryBare
            if r = s then found = true
        end for
        assertTrue(found)
    end for
    print "TestSyncPlayCensusScreamingContainedInRegistry passed"
end sub

sub TestSyncPlayCensusSizeIsTwenty()
    ' emitted-verified (20) + reserved (0) - the census the fixture now
    ' pins against is itself held at the 12+3+8 shape the header docblocks
    ' recite (9 live SCREAMING + 3 pre-flip legacy + 8 dotted).
    assertEqual(SyncPlayKnownErrorCodes().Count(), 20)
    assertEqual(SyncPlayReservedErrorCodes().Count(), 0)
    print "TestSyncPlayCensusSizeIsTwenty passed"
end sub
