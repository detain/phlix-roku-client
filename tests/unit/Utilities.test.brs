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
    ' Test stream format detection
    assertEqual(GetStreamFormat("mp4"), "mp4")
    assertEqual(GetStreamFormat("m4v"), "mp4")
    assertEqual(GetStreamFormat("mkv"), "mkv")
    assertEqual(GetStreamFormat("ts"), "mpegts")
    assertEqual(GetStreamFormat("webm"), "webm")
    assertEqual(GetStreamFormat("m3u8"), "hls")

    print "TestGetStreamFormat passed"
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
