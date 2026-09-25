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
    ' Case-insensitive, trims padding, dash maps like dot
    assertEqual(SyncPlayErrorCodeToKey("  Not_Host\t"), "errors_not_host")
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
    ' Wire-honesty split: 19 emitted-verified + 0 declared-reserved = 19.
    ' The 2026-09-25 twin flip (phlix-server 9b2394ee) promoted the reserved
    ' trio; the reserved arm stays armed for the next flip-pending code.
    assertEqual(codes.count(), 19)
    ' Law output must be collision-free across the two code families
    seen = {}
    for each code in codes
        key = SyncPlayErrorCodeToKey(code)
        assertEqual(seen.doesExist(key), false)
        seen[key] = true
    end for
    ' Family census: 12 legacy SCREAMING (9 current + 3 pre-flip-only, kept
    ' for old-server resolution), 7 dotted registry (all emitted-verified
    ' since the flip) - the split Check 22 content-pins in CI.
    screaming = 0
    dotted = 0
    for each code in codes
        if code.Instr(".") > 0
            dotted++
        else
            screaming++
        end if
    end for
    assertEqual(screaming, 12)
    assertEqual(dotted, 7)
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
        assertTrue(LCase(code).Left(9) = "syncplay.")
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
    codes = SyncPlayLocalErrorCodes()
    assertEqual(codes.count(), 9)
    for each code in codes
        assertTrue(code.Left(6) = "local.")
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
        assertTrue(LCase(code).Left(6) <> "local.")
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
