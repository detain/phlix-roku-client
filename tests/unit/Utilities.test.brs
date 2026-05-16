' tests/unit/Utilities.test.brs

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