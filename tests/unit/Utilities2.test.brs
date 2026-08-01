' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/Utilities2.test.brs

' ===========================================
' Utilities Unit Tests - Part 2
' Additional function tests
' ===========================================

' ---- NormalizeServerUrl tests ----

sub TestNormalizeServerUrlInvalid()
    ' Test NormalizeServerUrl with invalid input
    result = NormalizeServerUrl(invalid)
    assertEqual(result, "")
    print "TestNormalizeServerUrlInvalid passed"
end sub

sub TestNormalizeServerUrlEmpty()
    ' Test NormalizeServerUrl with empty string
    result = NormalizeServerUrl("")
    assertEqual(result, "")
    print "TestNormalizeServerUrlEmpty passed"
end sub

sub TestNormalizeServerUrlWithExplicitHttp()
    ' Test NormalizeServerUrl with explicit http://
    result = NormalizeServerUrl("http://localhost:8096")
    assertEqual(result, "http://localhost:8096")
    print "TestNormalizeServerUrlWithExplicitHttp passed"
end sub

sub TestNormalizeServerUrlWithExplicitHttps()
    ' Test NormalizeServerUrl with explicit https://
    result = NormalizeServerUrl("https://example.com")
    assertEqual(result, "https://example.com")
    print "TestNormalizeServerUrlWithExplicitHttps passed"
end sub

sub TestNormalizeServerUrlLocalhostDefaultsToHttp()
    ' Test NormalizeServerUrl infers http for localhost
    result = NormalizeServerUrl("localhost:8096")
    assertEqual(result, "http://localhost:8096")
    print "TestNormalizeServerUrlLocalhostDefaultsToHttp passed"
end sub

sub TestNormalizeServerUrlPrivateIPDefaultsToHttp()
    ' Test NormalizeServerUrl infers http for private IPs
    result = NormalizeServerUrl("192.168.1.100:8096")
    assertEqual(result, "http://192.168.1.100:8096")
    result = NormalizeServerUrl("10.0.0.1")
    assertEqual(result, "http://10.0.0.1")
    result = NormalizeServerUrl("172.16.0.1")
    assertEqual(result, "http://172.16.0.1")
    print "TestNormalizeServerUrlPrivateIPDefaultsToHttp passed"
end sub

sub TestNormalizeServerUrlPublicDefaultsToHttps()
    ' Test NormalizeServerUrl infers https for public domains
    result = NormalizeServerUrl("example.com")
    assertEqual(result, "https://example.com")
    result = NormalizeServerUrl("api.example.com")
    assertEqual(result, "https://api.example.com")
    print "TestNormalizeServerUrlPublicDefaultsToHttps passed"
end sub

sub TestNormalizeServerUrlStripsTrailingSlash()
    ' Test NormalizeServerUrl strips trailing slash
    result = NormalizeServerUrl("http://example.com/")
    assertEqual(result, "http://example.com")
    print "TestNormalizeServerUrlStripsTrailingSlash passed"
end sub

sub TestNormalizeServerUrlTrimsWhitespace()
    ' Test NormalizeServerUrl trims whitespace
    result = NormalizeServerUrl("  http://example.com  ")
    assertEqual(result, "http://example.com")
    print "TestNormalizeServerUrlTrimsWhitespace passed"
end sub

' ---- HealthOk tests ----

sub TestHealthOkInvalid()
    ' Test HealthOk with invalid input
    assertFalse(HealthOk(invalid))
    print "TestHealthOkInvalid passed"
end sub

sub TestHealthOkNonAssociativeArray()
    ' Test HealthOk with non-assocarray
    assertFalse(HealthOk("string"))
    assertFalse(HealthOk([]))
    assertFalse(HealthOk(42))
    print "TestHealthOkNonAssociativeArray passed"
end sub

sub TestHealthOkStatusOk()
    ' Test HealthOk with status "ok"
    json = { status: "ok" }
    assertTrue(HealthOk(json))
    print "TestHealthOkStatusOk passed"
end sub

sub TestHealthOkWithVersion()
    ' Test HealthOk with version key
    json = { status: "not_ok", version: "1.0.0" }
    assertTrue(HealthOk(json))
    print "TestHealthOkWithVersion passed"
end sub

sub TestHealthOkNeither()
    ' Test HealthOk with neither status nor version
    json = { foo: "bar" }
    assertFalse(HealthOk(json))
    print "TestHealthOkNeither passed"
end sub

' ---- EscapeString / UnescapeString tests ----

sub TestEscapeString()
    ' Test EscapeString encodes special characters
    assertEqual(EscapeString("&"), "&amp;")
    assertEqual(EscapeString("<"), "&lt;")
    assertEqual(EscapeString(">"), "&gt;")
    assertEqual(EscapeString(Chr(34)), "&quot;")
    assertEqual(EscapeString("a<b>c"), "a&lt;b&gt;c")
    print "TestEscapeString passed"
end sub

sub TestUnescapeString()
    ' Test UnescapeString decodes special characters
    assertEqual(UnescapeString("&amp;"), "&")
    assertEqual(UnescapeString("&lt;"), "<")
    assertEqual(UnescapeString("&gt;"), ">")
    assertEqual(UnescapeString("&quot;"), Chr(34))
    print "TestUnescapeString passed"
end sub

' ---- UrlEncode tests ----

sub TestUrlEncode()
    ' Test UrlEncode encodes special characters
    assertEqual(UrlEncode(" "), "%20")
    assertEqual(UrlEncode("&"), "%26")
    assertEqual(UrlEncode("="), "%3D")
    assertEqual(UrlEncode("?"), "%3F")
    assertEqual(UrlEncode("/"), "%2F")
    assertEqual(UrlEncode(":"), "%3A")
    assertEqual(UrlEncode("#"), "%23")
    assertEqual(UrlEncode("["), "%5B")
    assertEqual(UrlEncode("]"), "%5D")
    print "TestUrlEncode passed"
end sub

sub TestUrlEncodeInvalid()
    ' Test UrlEncode with invalid input
    assertEqual(UrlEncode(invalid), "")
    print "TestUrlEncodeInvalid passed"
end sub

sub TestUrlEncodeNoSpecialChars()
    ' Test UrlEncode passes through normal chars
    assertEqual(UrlEncode("hello"), "hello")
    print "TestUrlEncodeNoSpecialChars passed"
end sub

' ---- JoinStrings tests ----

sub TestJoinStrings()
    ' Test JoinStrings joins array elements
    parts = ["a", "b", "c"]
    assertEqual(JoinStrings(parts, ","), "a,b,c")
    assertEqual(JoinStrings(parts, " "), "a b c")
    assertEqual(JoinStrings(parts, "-"), "a-b-c")
    print "TestJoinStrings passed"
end sub

sub TestJoinStringsInvalid()
    ' Test JoinStrings with invalid input
    assertEqual(JoinStrings(invalid, ","), "")
    print "TestJoinStringsInvalid passed"
end sub

sub TestJoinStringsSingleElement()
    ' Test JoinStrings with single element
    parts = ["only"]
    assertEqual(JoinStrings(parts, ","), "only")
    print "TestJoinStringsSingleElement passed"
end sub

sub TestJoinStringsEmptyArray()
    ' Test JoinStrings with empty array
    parts = []
    assertEqual(JoinStrings(parts, ","), "")
    print "TestJoinStringsEmptyArray passed"
end sub

' ---- GenerateRandomId tests ----

sub TestGenerateRandomId()
    ' Test GenerateRandomId generates unique-ish IDs
    id1 = GenerateRandomId()
    id2 = GenerateRandomId()
    assertTrue(id1 <> invalid)
    assertTrue(id2 <> invalid)
    assertTrue(id1.Len() > 0)
    assertTrue(id2.Len() > 0)
    ' IDs should be different (with very high probability)
    assertTrue(id1 <> id2)
    print "TestGenerateRandomId passed"
end sub

sub TestGenerateRandomIdFormat()
    ' Test GenerateRandomId has correct format
    id = GenerateRandomId()
    ' Format: "number-number" (e.g., "123456789-987654321")
    parts = id.Split("-")
    assertEqual(parts.Count(), 2)
    print "TestGenerateRandomIdFormat passed"
end sub

' ---- SortKeyValue tests ----

sub TestSortKeyValueInvalidItem()
    ' Test SortKeyValue with invalid item
    assertEqual(SortKeyValue(invalid, "key"), 999999)
    print "TestSortKeyValueInvalidItem passed"
end sub

sub TestSortKeyValueMissingKey()
    ' Test SortKeyValue with missing key
    item = { name: "test" }
    assertEqual(SortKeyValue(item, "missing"), 999999)
    print "TestSortKeyValueMissingKey passed"
end sub

sub TestSortKeyValueInvalidValue()
    ' Test SortKeyValue with invalid value
    item = { key: invalid }
    assertEqual(SortKeyValue(item, "key"), 999999)
    print "TestSortKeyValueInvalidValue passed"
end sub

sub TestSortKeyValueValidNumber()
    ' Test SortKeyValue with valid number
    item = { key: 42 }
    assertEqual(SortKeyValue(item, "key"), 42)
    print "TestSortKeyValueValidNumber passed"
end sub

' ---- SortByEpisodeOrder tests ----

sub TestSortByEpisodeOrderInvalid()
    ' Test SortByEpisodeOrder with invalid input
    result = SortByEpisodeOrder(invalid)
    assertTrue(result <> invalid)
    assertEqual(result.Count(), 0)
    print "TestSortByEpisodeOrderInvalid passed"
end sub

sub TestSortByEpisodeOrderEmpty()
    ' Test SortByEpisodeOrder with empty array
    result = SortByEpisodeOrder([])
    assertTrue(result <> invalid)
    assertEqual(result.Count(), 0)
    print "TestSortByEpisodeOrderEmpty passed"
end sub

sub TestSortByEpisodeOrderPreservesInput()
    ' Test SortByEpisodeOrder does not modify input
    input = [{ season_number: 1, episode_number: 2, name: "A" }]
    result = SortByEpisodeOrder(input)
    assertEqual(result.Count(), 1)
    print "TestSortByEpisodeOrderPreservesInput passed"
end sub

' ---- NormalizeAlbumTrack tests ----

sub TestNormalizeAlbumTrackInvalid()
    ' Test NormalizeAlbumTrack with invalid input
    result = NormalizeAlbumTrack(invalid)
    assertTrue(result <> invalid)
    assertEqual(result.id, "")
    print "TestNormalizeAlbumTrackInvalid passed"
end sub

sub TestNormalizeAlbumTrackWithId()
    ' Test NormalizeAlbumTrack extracts id
    raw = { id: "track-123" }
    result = NormalizeAlbumTrack(raw)
    assertEqual(result.id, "track-123")
    print "TestNormalizeAlbumTrackWithId passed"
end sub

sub TestNormalizeAlbumTrackWithMetadata()
    ' Test NormalizeAlbumTrack reads metadata
    raw = { id: "t1", metadata: { title: "Song Title", artist: "Artist Name" } }
    result = NormalizeAlbumTrack(raw)
    assertEqual(result.name, "Song Title")
    print "TestNormalizeAlbumTrackWithMetadata passed"
end sub

' ---- NormalizeCollectionItem tests ----

sub TestNormalizeCollectionItemInvalid()
    ' Test NormalizeCollectionItem with invalid input
    result = NormalizeCollectionItem(invalid)
    assertTrue(result <> invalid)
    assertEqual(result.id, "")
    print "TestNormalizeCollectionItemInvalid passed"
end sub

sub TestNormalizeCollectionItemBasic()
    ' Test NormalizeCollectionItem extracts basic fields
    raw = { id: "col-1", name: "My Collection", type: "series" }
    result = NormalizeCollectionItem(raw)
    assertEqual(result.id, "col-1")
    assertEqual(result.name, "My Collection")
    assertEqual(result.type, "series")
    print "TestNormalizeCollectionItemBasic passed"
end sub

' ---- SortByTrackOrder tests ----

sub TestSortByTrackOrderInvalid()
    ' Test SortByTrackOrder with invalid input
    result = SortByTrackOrder(invalid)
    assertTrue(result <> invalid)
    assertEqual(result.Count(), 0)
    print "TestSortByTrackOrderInvalid passed"
end sub

sub TestSortByTrackOrderEmpty()
    ' Test SortByTrackOrder with empty array
    result = SortByTrackOrder([])
    assertTrue(result <> invalid)
    assertEqual(result.Count(), 0)
    print "TestSortByTrackOrderEmpty passed"
end sub

' ---- TrackCaption tests ----

sub TestTrackCaptionInvalid()
    ' Test TrackCaption with invalid input
    assertEqual(TrackCaption(invalid), "")
    print "TestTrackCaptionInvalid passed"
end sub

sub TestTrackCaptionNoTrackNumber()
    ' Test TrackCaption without track number
    track = { name: "My Song" }
    assertEqual(TrackCaption(track), "My Song")
    print "TestTrackCaptionNoTrackNumber passed"
end sub

sub TestTrackCaptionWithTrackNumber()
    ' Test TrackCaption with track number
    track = { name: "My Song", track_number: 5 }
    caption = TrackCaption(track)
    assertTrue(caption.Left(2) = "5.")
    print "TestTrackCaptionWithTrackNumber passed"
end sub

sub TestTrackCaptionWithDuration()
    ' Test TrackCaption includes duration
    track = { name: "My Song", track_number: 1, duration_secs: 180 }
    caption = TrackCaption(track)
    assertTrue(caption.Instr(0, "3:00") > 0)
    print "TestTrackCaptionWithDuration passed"
end sub

' ---- AlbumCaption tests ----

sub TestAlbumCaptionInvalid()
    ' Test AlbumCaption with invalid input
    assertEqual(AlbumCaption(invalid), "")
    print "TestAlbumCaptionInvalid passed"
end sub

sub TestAlbumCaptionBasic()
    ' Test AlbumCaption without artist
    album = { name: "My Album" }
    assertEqual(AlbumCaption(album), "My Album")
    print "TestAlbumCaptionBasic passed"
end sub

sub TestAlbumCaptionWithArtist()
    ' Test AlbumCaption with artist
    album = { name: "My Album", artist: "My Artist" }
    caption = AlbumCaption(album)
    assertTrue(caption.Instr(0, "My Album") >= 0)
    assertTrue(caption.Instr(0, "My Artist") >= 0)
    print "TestAlbumCaptionWithArtist passed"
end sub

sub TestAlbumCaptionWithYear()
    ' Test AlbumCaption includes year
    album = { name: "My Album", artist: "Artist", year: 2024 }
    caption = AlbumCaption(album)
    assertTrue(caption.Instr(0, "2024") > 0)
    print "TestAlbumCaptionWithYear passed"
end sub

' ---- PhotoAlbumCaption tests ----

sub TestPhotoAlbumCaptionInvalid()
    ' Test PhotoAlbumCaption with invalid input
    assertEqual(PhotoAlbumCaption(invalid), "Undated")
    print "TestPhotoAlbumCaptionInvalid passed"
end sub

sub TestPhotoAlbumCaptionUnknown()
    ' Test PhotoAlbumCaption with "Unknown" date
    album = { date: "Unknown" }
    assertEqual(PhotoAlbumCaption(album), "Undated")
    print "TestPhotoAlbumCaptionUnknown passed"
end sub

sub TestPhotoAlbumCaptionEmpty()
    ' Test PhotoAlbumCaption with empty date
    album = { date: "" }
    assertEqual(PhotoAlbumCaption(album), "Undated")
    print "TestPhotoAlbumCaptionEmpty passed"
end sub

sub TestPhotoAlbumCaptionValid()
    ' Test PhotoAlbumCaption with valid date
    album = { date: "2024-01-15" }
    assertEqual(PhotoAlbumCaption(album), "2024-01-15")
    print "TestPhotoAlbumCaptionValid passed"
end sub

' ---- IsAdminUser tests ----

sub TestIsAdminUserInvalid()
    ' Test IsAdminUser with invalid input
    assertFalse(IsAdminUser(invalid))
    print "TestIsAdminUserInvalid passed"
end sub

sub TestIsAdminUserMissingKey()
    ' Test IsAdminUser with missing is_admin
    user = { name: "test" }
    assertFalse(IsAdminUser(user))
    print "TestIsAdminUserMissingKey passed"
end sub

sub TestIsAdminUserBooleanTrue()
    ' Test IsAdminUser with Boolean true
    user = { is_admin: true }
    assertTrue(IsAdminUser(user))
    print "TestIsAdminUserBooleanTrue passed"
end sub

sub TestIsAdminUserBooleanFalse()
    ' Test IsAdminUser with Boolean false
    user = { is_admin: false }
    assertFalse(IsAdminUser(user))
    print "TestIsAdminUserBooleanFalse passed"
end sub

sub TestIsAdminUserIntegerOne()
    ' Test IsAdminUser with Integer 1
    user = { is_admin: 1 }
    assertTrue(IsAdminUser(user))
    print "TestIsAdminUserIntegerOne passed"
end sub

sub TestIsAdminUserIntegerZero()
    ' Test IsAdminUser with Integer 0
    user = { is_admin: 0 }
    assertFalse(IsAdminUser(user))
    print "TestIsAdminUserIntegerZero passed"
end sub

' ---- IsTruthyFlag tests ----

sub TestIsTruthyFlagInvalid()
    ' Test IsTruthyFlag with invalid container
    assertFalse(IsTruthyFlag(invalid, "key"))
    print "TestIsTruthyFlagInvalid passed"
end sub

sub TestIsTruthyFlagNonAssociativeArray()
    ' Test IsTruthyFlag with non-assocarray
    assertFalse(IsTruthyFlag("string", "key"))
    assertFalse(IsTruthyFlag(42, "key"))
    print "TestIsTruthyFlagNonAssociativeArray passed"
end sub

sub TestIsTruthyFlagMissingKey()
    ' Test IsTruthyFlag with missing key
    container = { name: "test" }
    assertFalse(IsTruthyFlag(container, "missing"))
    print "TestIsTruthyFlagMissingKey passed"
end sub

sub TestIsTruthyFlagTrue()
    ' Test IsTruthyFlag with true value
    container = { flag: true }
    assertTrue(IsTruthyFlag(container, "flag"))
    print "TestIsTruthyFlagTrue passed"
end sub

sub TestIsTruthyFlagFalse()
    ' Test IsTruthyFlag with false value
    container = { flag: false }
    assertFalse(IsTruthyFlag(container, "flag"))
    print "TestIsTruthyFlagFalse passed"
end sub

sub TestIsTruthyFlagIntegerOne()
    ' Test IsTruthyFlag with Integer 1
    container = { flag: 1 }
    assertTrue(IsTruthyFlag(container, "flag"))
    print "TestIsTruthyFlagIntegerOne passed"
end sub

' ---- RatingLabel tests ----

sub TestRatingLabelValid()
    ' Test RatingLabel with valid ratings
    assertEqual(RatingLabel(0), "G")
    assertEqual(RatingLabel(1), "PG")
    assertEqual(RatingLabel(2), "PG-13")
    assertEqual(RatingLabel(3), "R")
    assertEqual(RatingLabel(4), "NC-17")
    assertEqual(RatingLabel(5), "X")
    assertEqual(RatingLabel(6), "UNRATED")
    print "TestRatingLabelValid passed"
end sub

sub TestRatingLabelOutOfRange()
    ' Test RatingLabel with out-of-range values
    assertEqual(RatingLabel(-1), "UNRATED")
    assertEqual(RatingLabel(7), "UNRATED")
    assertEqual(RatingLabel(100), "UNRATED")
    print "TestRatingLabelOutOfRange passed"
end sub

' ---- PlayableTypes tests ----

sub TestPlayableTypes()
    ' Test PlayableTypes returns expected array
    types = PlayableTypes()
    assertTrue(types <> invalid)
    assertEqual(types.Count(), 6)
    assertTrue(types.IndexOf("movie") >= 0)
    assertTrue(types.IndexOf("episode") >= 0)
    assertTrue(types.IndexOf("video") >= 0)
    assertTrue(types.IndexOf("audio") >= 0)
    assertTrue(types.IndexOf("track") >= 0)
    assertTrue(types.IndexOf("audiobook") >= 0)
    print "TestPlayableTypes passed"
end sub
