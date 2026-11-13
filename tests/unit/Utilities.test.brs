' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/Utilities.test.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Utilities Unit Tests
' ===========================================

sub TestFormatTime()
    ' Test time formatting with hours
    result = FormatTime(3661.0)
    assertEqual(result, "1:01:01")

    ' Test time formatting without hours
    result = FormatTime(125.0)
    assertEqual(result, "2:05")

    ' Test zero
    result = FormatTime(0.0)
    assertEqual(result, "0:00")

    print "TestFormatTime passed"
end sub

sub TestParseTime()
    ' Test time parsing
    seconds = ParseTime("1:01:01")
    assertEqual(seconds, 3661.0)

    seconds = ParseTime("2:05")
    assertEqual(seconds, 125.0)

    print "TestParseTime passed"
end sub

sub TestTruncateString()
    ' Test truncation
    result = TruncateString("Hello World", 8)
    assertEqual(result, "Hello...")

    ' Test no truncation needed
    result = TruncateString("Hi", 10)
    assertEqual(result, "Hi")

    print "TestTruncateString passed"
end sub

sub TestIsValidUrl()
    ' Test valid URLs
    assertTrue(IsValidUrl("http://example.com"))
    assertTrue(IsValidUrl("https://example.com"))

    ' Test invalid URLs
    assertFalse(IsValidUrl(""))
    assertFalse(IsValidUrl("ftp://example.com"))
    assertFalse(IsValidUrl("example.com"))

    print "TestIsValidUrl passed"
end sub

sub TestGetFileExtension()
    ' Test extension extraction
    ext = GetFileExtension("http://example.com/video.mp4")
    assertEqual(ext, "mp4")

    ext = GetFileExtension("http://example.com/video.mkv")
    assertEqual(ext, "mkv")

    print "TestGetFileExtension passed"
end sub

sub TestGetStreamFormat()
    ' RT-105 [review roku__crossfe M2]: only Roku platform-valid StreamFormat
    ' tokens may be emitted; mov/m4v fold onto mp4, and every unknown or
    ' unsupported container answers "" (the honest "claim nothing" sentinel)
    ' instead of the old fabricated mp4.
    assertEqual(GetStreamFormat("mp4"), "mp4")
    assertEqual(GetStreamFormat("m4v"), "mp4")
    assertEqual(GetStreamFormat("mov"), "mp4")
    assertEqual(GetStreamFormat("mkv"), "mkv")
    assertEqual(GetStreamFormat("m3u8"), "hls")
    assertEqual(GetStreamFormat("mp3"), "mp3")
    assertEqual(GetStreamFormat("wma"), "wma")

    print "TestGetStreamFormat passed"
end sub

sub TestGetStreamFormatRejectsInvalidFormats()
    ' The three values the OLD mapper returned that are NOT valid Roku
    ' StreamFormat tokens, plus the empty/unknown/garbage shapes, all collapse
    ' to "" - the sentinel PlayerScene routes to the transcode lane.
    assertEqual(GetStreamFormat("ts"), "")
    assertEqual(GetStreamFormat("webm"), "")
    assertEqual(GetStreamFormat(""), "")
    assertEqual(GetStreamFormat("flv"), "")
    ' A signer-minted stream URL carries no dot, so the extension derivation
    ' yields "" and the format claim is "" - the exact production shape that
    ' made the old default-mp4 a capability probe that could never say no.
    signerUrl = "http://host/media/011ac181-2b3c-4d5e-8f90-1a2b3c4d5e6f/stream?exp=1790000000&sig=aB3-xY9_zW2"
    assertEqual(GetFileExtension(signerUrl), "")
    assertEqual(GetStreamFormat(GetFileExtension(signerUrl)), "")
    ' Platform-valid-set pin: every known container resolves to a token in
    ' Roku's StreamFormat table (mp4/hls/mkv/mp3/wma); nothing maps to a value
    ' outside it, and case folds through LCase.
    assertEqual(GetStreamFormat("mka"), "mkv")
    assertEqual(GetStreamFormat("mks"), "mkv")
    assertEqual(GetStreamFormat("MP4"), "mp4")
    assertEqual(GetStreamFormat("MOV"), "mp4")
    assertEqual(GetStreamFormat("M3U8"), "hls")
    print "TestGetStreamFormatRejectsInvalidFormats passed"
end sub

sub TestIsPlayableType()
    ' Every playable leaf member of the media_items.type ENUM.
    assertTrue(IsPlayableType("movie"))
    assertTrue(IsPlayableType("episode"))
    assertTrue(IsPlayableType("video"))
    assertTrue(IsPlayableType("audio"))
    assertTrue(IsPlayableType("track"))
    assertTrue(IsPlayableType("audiobook"))

    ' Containers drill down; they have no stream of their own.
    assertFalse(IsPlayableType("series"))
    assertFalse(IsPlayableType("season"))
    assertFalse(IsPlayableType("album"))
    assertFalse(IsPlayableType("artist"))
    assertFalse(IsPlayableType("music"))

    ' No video/audio track at all.
    assertFalse(IsPlayableType("book"))
    assertFalse(IsPlayableType("photo"))

    ' Unknown / malformed input is never playable.
    assertFalse(IsPlayableType(""))
    assertFalse(IsPlayableType("bogus"))
    assertFalse(IsPlayableType(invalid))
    assertFalse(IsPlayableType(42))
    assertFalse(IsPlayableType({ type: "movie" }))

    ' Case and surrounding whitespace are normalized.
    assertTrue(IsPlayableType("Movie"))
    assertTrue(IsPlayableType("AUDIOBOOK"))
    assertTrue(IsPlayableType("  track  "))

    print "TestIsPlayableType passed"
end sub

sub TestIsPlayableItem()
    assertTrue(IsPlayableItem({ id: "1", type: "movie" }))
    assertTrue(IsPlayableItem({ id: "2", type: "audio" }))
    assertFalse(IsPlayableItem({ id: "3", type: "series" }))
    assertFalse(IsPlayableItem({ id: "4", type: "photo" }))

    ' Missing/invalid containers and keys must not crash.
    assertFalse(IsPlayableItem(invalid))
    assertFalse(IsPlayableItem({}))
    assertFalse(IsPlayableItem({ id: "5" }))
    assertFalse(IsPlayableItem({ id: "6", type: invalid }))

    print "TestIsPlayableItem passed"
end sub

' ---- ConcurrentStreamLimitText (RT-032): the singular/plural selection law.
' Headless catalog state is KEY ECHO (a missing catalog returns the key), so
' the assertions compare against direct TranslateWithParams calls - the law
' holds in BOTH catalog states (loaded device run, key-echo run), per the
' TranslateWithParams.test.brs pairing precedent - and pin the branch itself
' with assertNotEqual across the singular/plural boundary.
sub TestConcurrentStreamLimitTextSelectionLaw()
    assertEqual(ConcurrentStreamLimitText(1), TranslateWithParams("parentalcontrols_current_limit_one", { count: 1 }))
    assertEqual(ConcurrentStreamLimitText(0), TranslateWithParams("parentalcontrols_current_limit", { count: 0 }))
    assertEqual(ConcurrentStreamLimitText(2), TranslateWithParams("parentalcontrols_current_limit", { count: 2 }))
    assertEqual(ConcurrentStreamLimitText(3), TranslateWithParams("parentalcontrols_current_limit", { count: 3 }))
    ' Int() truncation mirrors the MembersCountText precedent (1.7 -> 1 = singular, 3.0 -> 3 = plural).
    assertEqual(ConcurrentStreamLimitText(1.7), TranslateWithParams("parentalcontrols_current_limit_one", { count: 1 }))
    assertEqual(ConcurrentStreamLimitText(3.0), TranslateWithParams("parentalcontrols_current_limit", { count: 3 }))
    ' The branch itself: singular and plural render differently in every
    ' catalog state (echo: distinct keys; loaded: distinct values).
    assertNotEqual(ConcurrentStreamLimitText(1), ConcurrentStreamLimitText(2))
    ' Both keys are live catalog members: they resolve to a non-empty line
    ' in any catalog state (value or echo), same never-empty census class as
    ' TestTranslateWithParamsKnownCodeNeverEmpty.
    assertTrue(TranslateWithParams("parentalcontrols_current_limit", { count: 1 }) <> "")
    assertTrue(TranslateWithParams("parentalcontrols_current_limit_one", { count: 1 }) <> "")
    print "TestConcurrentStreamLimitTextSelectionLaw passed"
end sub

' ROK-27: the precomputed bare-key index must resolve exactly what the former
' per-miss section probe did (first section in Keys() order, string leaves
' only, "_metadata" skipped).
sub TestBuildBareLocaleIndexParity()
    raw = {
        _metadata: { version: "x" }
        alpha: { shared: "A", only_a: "a1", bad: [1, 2] }
        beta: { shared: "B", only_b: "b1", bad: "ok" }
    }
    idx = BuildBareLocaleIndex(raw)
    ' reference: the legacy probe over raw.Keys()
    for each k in ["shared", "only_a", "only_b", "bad", "version", "missing"]
        expected = invalid
        for each section in raw.Keys()
            if expected = invalid and section <> "_metadata"
                sd = raw[section]
                if type(sd) = "roAssociativeArray" and sd.doesExist(k)
                    v = sd[k]
                    if type(v) = "String" or type(v) = "roString" then expected = v
                end if
            end if
        end for
        if expected = invalid
            assertFalse(idx.doesExist(k))
        else
            assertEqual(idx[k], expected)
        end if
    end for
    assertEqual(BuildBareLocaleIndex(invalid).Count(), 0)
    print "TestBuildBareLocaleIndexParity passed"
end sub
