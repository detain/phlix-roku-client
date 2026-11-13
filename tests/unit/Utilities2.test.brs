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

' ---- UrlEncode new behavior tests (RFC 3986 allow-list) ----

sub TestUrlEncodeNewBehavior()
    ' Criterion 5: allow-list characters encoded correctly
    ' Percent sign encoded first to prevent double-encoding
    assertEqual(UrlEncode("50% off"), "50%25%20off")
    ' Plus sign is NOT unreserved (RFC 3986) — encodes to %2B
    assertEqual(UrlEncode("C++"), "C%2B%2B")
    ' Non-ASCII (U+00EF = ï) encoded as 3-byte UTF-8: C3 AF
    assertEqual(UrlEncode("naïve"), "na%C3%AFve")
    ' Empty string
    assertEqual(UrlEncode(""), "")
    ' Only reserved character — plus sign encodes to %2B
    assertEqual(UrlEncode("+"), "%2B")
    print "TestUrlEncodeNewBehavior passed"
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
    assertTrue(Left(caption, 2) = "5.")
    print "TestTrackCaptionWithTrackNumber passed"
end sub

sub TestTrackCaptionWithDuration()
    ' Test TrackCaption includes duration
    track = { name: "My Song", track_number: 1, duration_secs: 180 }
    caption = TrackCaption(track)
    ' The .Instr member form exists only in some runtimes (brs serves it
    ' 0-based); the device-safe shape is the global three-arg Instr.
    assertTrue(Instr(1, caption, "3:00") > 0)
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

' Device-safe membership scan: roArray exposes no IndexOf on the device
' (and brs does not either — measured), so the old .IndexOf arms could never
' have executed anywhere; a plain loop is the shape that works on both.
function __typeListHas(arr as Object, want as String) as Boolean
    for each e in arr
        if e = want then return true
    end for
    return false
end function

sub TestPlayableTypes()
    ' Test PlayableTypes returns expected array
    types = PlayableTypes()
    assertTrue(types <> invalid)
    assertEqual(types.Count(), 6)
    assertTrue(__typeListHas(types, "movie"), "movie in playable types")
    assertTrue(__typeListHas(types, "episode"), "episode in playable types")
    assertTrue(__typeListHas(types, "video"), "video in playable types")
    assertTrue(__typeListHas(types, "audio"), "audio in playable types")
    assertTrue(__typeListHas(types, "track"), "track in playable types")
    assertTrue(__typeListHas(types, "audiobook"), "audiobook in playable types")
    print "TestPlayableTypes passed"
end sub

' ---- Utf8BytesForCodePoint (W13L3 RT-041, review roku__secnet #5) ----
' The repo's single UTF-8 law: code point -> 1..4 byte values. UrlEncode
' percent-escapes these bytes (its live "naïve" -> na%C3%AFve pin covers the
' percent-escape leg); SyncPlayPasswordHash digests the raw bytes. Pure
' integer in / integer array out - fully live headless (no roByteArray
' needed), so this table runs in the battery, not only on-device.
sub TestUtf8BytesForCodePointTruthTable()
    ' ASCII: identity single byte (boundaries: 0, 127).
    a = Utf8BytesForCodePoint(97)
    assertEqual(a.Count(), 1)
    assertEqual(a[0], 97)
    z = Utf8BytesForCodePoint(127)
    assertEqual(z.Count(), 1)
    assertEqual(z[0], 127)
    ' 2-byte family (U+00E9 e-acute -> C3 A9 = [195,169]).
    e = Utf8BytesForCodePoint(233)
    assertEqual(e.Count(), 2)
    assertEqual(e[0], 195)
    assertEqual(e[1], 169)
    ' 2-byte boundary (U+07FF -> DF BF).
    b = Utf8BytesForCodePoint(2047)
    assertEqual(b.Count(), 2)
    assertEqual(b[0], 223)
    assertEqual(b[1], 191)
    ' 3-byte family (U+20AC EURO -> E2 82 AC = [226,130,172], probe-measured
    ' headless).
    u = Utf8BytesForCodePoint(8364)
    assertEqual(u.Count(), 3)
    assertEqual(u[0], 226)
    assertEqual(u[1], 130)
    assertEqual(u[2], 172)
    ' 3-byte top-of-range boundary (U+FFFF -> EF BF BF, probe-measured).
    ' NOTE the variable is mx, never m: `m` is BrightScript's reserved
    ' scope-pointer token and rebinding it collapses a local to the
    ' ambient AA (a probe's m.Count() answered 0 on exactly these bytes).
    mx = Utf8BytesForCodePoint(65535)
    assertEqual(mx.Count(), 3)
    assertEqual(mx[0], 239)
    assertEqual(mx[1], 191)
    assertEqual(mx[2], 191)
    ' 4-byte family (U+10437 DESERET LETTER YEA -> F0 90 90 B7, probe-measured).
    s = Utf8BytesForCodePoint(66615)
    assertEqual(s.Count(), 4)
    assertEqual(s[0], 240)
    assertEqual(s[1], 144)
    assertEqual(s[2], 144)
    assertEqual(s[3], 183)
    print "TestUtf8BytesForCodePointTruthTable passed"
end sub

' W14L1 RT-041 fold-in: the string-level UTF-8 fold the join-password
' digest now routes through. Every byte law pinned per-code-point above
' is composed HERE over whole strings - and the digest call-site wiring
' is pinned statically by Check 99 (the roEVPDigest leg stops headless
' execution short of the loop, so this vector pin + that static leg are
' the full conviction the reviewer's M-041A proved missing).
sub TestUtf8BytesFromStringTruthTable()
    ' ASCII identity + multibyte folds, probe-truth-tabled vectors.
    empty = Utf8BytesFromString("")
    assertEqual(empty.Count(), 0)

    ab = Utf8BytesFromString("ab")
    assertEqual(ab.Count(), 2)
    assertEqual(ab[0], 97)
    assertEqual(ab[1], 98)

    cafe = Utf8BytesFromString("café")
    assertEqual(cafe.Count(), 5)
    assertEqual(cafe[0], 99)
    assertEqual(cafe[1], 97)
    assertEqual(cafe[2], 102)
    assertEqual(cafe[3], 195)
    assertEqual(cafe[4], 169)

    euro = Utf8BytesFromString("€")
    assertEqual(euro.Count(), 3)
    assertEqual(euro[0], 226)
    assertEqual(euro[1], 130)
    assertEqual(euro[2], 172)

    mixed = Utf8BytesFromString("a€b")
    assertEqual(mixed.Count(), 5)
    assertEqual(mixed[0], 97)
    assertEqual(mixed[4], 98)
    print "TestUtf8BytesFromStringTruthTable passed"
end sub

' ---- RT-092 boxed-type-lift helpers (review roku__exploiter #1) ----
' The cohort choke: every DecodeJson scalar that crosses into a typed String
' field, an ordered numeric compare, or arithmetic routes through these three.
' Static per-site pins live in Check 100; these are the behavior table so a
' re-boxed site (or a broken helper) reddens both ways.

sub TestIsBoxedNumberTruthTable()
    ' The whole numeric family (intrinsic + ro names) answers true.
    assertTrue(IsBoxedNumber(5))
    assertTrue(IsBoxedNumber(-1))
    assertTrue(IsBoxedNumber(2.5))
    assertTrue(IsBoxedNumber(0))
    ' Non-numeric shapes answer false - including a numeric STRING and true,
    ' the two the old `<> invalid` guard waved straight through to `Int()`.
    assertFalse(IsBoxedNumber("5"))
    assertFalse(IsBoxedNumber(true))
    assertFalse(IsBoxedNumber(false))
    assertFalse(IsBoxedNumber(invalid))
    assertFalse(IsBoxedNumber({}))
    assertFalse(IsBoxedNumber([]))
    print "TestIsBoxedNumberTruthTable passed"
end sub

sub TestTextOrEmptyTruthTable()
    ' A real string is byte-identical.
    assertEqual(TextOrEmpty("hello"), "hello")
    assertEqual(TextOrEmpty(""), "")
    ' invalid and every non-string box answer "" (the empty-text sentinel)
    ' instead of crashing the downstream .text= write / string compare.
    assertEqual(TextOrEmpty(invalid), "")
    assertEqual(TextOrEmpty(456), "")
    assertEqual(TextOrEmpty({}), "")
    assertEqual(TextOrEmpty([]), "")
    assertEqual(TextOrEmpty(true), "")
    print "TestTextOrEmptyTruthTable passed"
end sub

sub TestNormalizeCollectionItemLiftsMalformedShapes()
    ' Happy path: a well-formed row keeps every value verbatim.
    good = NormalizeCollectionItem({ id: "c1", name: "Star Wars", type: "movie", overview: "A film", year: 1977 })
    assertEqual(good.id, "c1")
    assertEqual(good.name, "Star Wars")
    assertEqual(good.type, "movie")
    assertEqual(good.overview, "A film")
    assertEqual(good.year, 1977)

    ' Wire drift: name/overview arrive boxed as numbers and type as an AA.
    ' The old `<> invalid` guards waved these through to a crashing .text=
    ' write; the lift answers "" (no dead button, no Type Mismatch).
    bad = NormalizeCollectionItem({ id: 12, name: 456, type: { a: 1 }, metadata: { overview: 789, year: "2020" } })
    assertEqual(bad.id, "")
    assertEqual(bad.name, "")
    assertEqual(bad.type, "")
    assertEqual(bad.overview, "")
    assertTrue(bad.year = invalid)

    ' metadata as a bare string (the docblock's named hazard) is not read as an AA.
    strMeta = NormalizeCollectionItem({ name: "X", metadata: "not-an-aa" })
    assertEqual(strMeta.name, "X")
    assertEqual(strMeta.overview, "")

    ' invalid row collapses to the empty sentinel shape.
    nulled = NormalizeCollectionItem(invalid)
    assertEqual(nulled.id, "")
    assertEqual(nulled.name, "")
    assertTrue(nulled.year = invalid)
    print "TestNormalizeCollectionItemLiftsMalformedShapes passed"
end sub

' ---- IsImageUrlAdmissible tests (ROK-14 / ROK-36 image-lane leaf) ----

sub TestIsImageUrlAdmissibleLeafRefusals()
    https = "https://phlix.example.com"
    ' pkg:/ placeholder and root-relative paths always pass.
    assertTrue(IsImageUrlAdmissible(https, "pkg:/images/placeholder.png"))
    assertTrue(IsImageUrlAdmissible(https, "/api/v1/images/1.jpg"))
    assertTrue(IsImageUrlAdmissible(https, "https://cdn.example.com/a.jpg"))
    ' http downgrade off an https origin is refused; http origin keeps http.
    assertFalse(IsImageUrlAdmissible(https, "http://cdn.example.com/a.jpg"))
    assertTrue(IsImageUrlAdmissible("http://192.168.1.5:8096", "http://192.168.1.5:8096/a.jpg"))
    ' foreign / hostile shapes: file://, data://, userinfo games, blank, non-string.
    assertFalse(IsImageUrlAdmissible(https, "file:///etc/passwd"))
    assertFalse(IsImageUrlAdmissible(https, "data://x"))
    assertFalse(IsImageUrlAdmissible(https, "https://phlix.example.com@evil.example/a.jpg"))
    assertFalse(IsImageUrlAdmissible(https, ""))
    assertFalse(IsImageUrlAdmissible(https, "   "))
    assertFalse(IsImageUrlAdmissible(https, invalid))
    assertFalse(IsImageUrlAdmissible(https, 42))
    print "TestIsImageUrlAdmissibleLeafRefusals passed"
end sub

' ---- WatchStateCaption tests (ROK-S23 / ROK-24 watched/progress cue) ----

sub TestWatchStateCaptionWatchedWins()
    ' A watched row says the (caller-localized) label even with progress numbers.
    ud = { watched: true, position_ticks: 10, duration_ticks: 100, progress_percent: 10 }
    assertEqual(WatchStateCaption(ud, "Watched"), "Watched")
    print "TestWatchStateCaptionWatchedWins passed"
end sub

sub TestWatchStateCaptionPercentFromServerOrTicks()
    assertEqual(WatchStateCaption({ watched: false, progress_percent: 42.5 }, "Watched"), "42%")
    ' ticks fallback when progress_percent is absent
    assertEqual(WatchStateCaption({ watched: false, position_ticks: 300, duration_ticks: 1000 }, "Watched"), "30%")
    ' a started row under 1% earns 1%; clamp holds at 100
    assertEqual(WatchStateCaption({ watched: false, position_ticks: 1, duration_ticks: 1000000 }, "Watched"), "1%")
    assertEqual(WatchStateCaption({ watched: false, progress_percent: 400 }, "Watched"), "100%")
    print "TestWatchStateCaptionPercentFromServerOrTicks passed"
end sub

sub TestWatchStateCaptionNeverRendersBlind()
    ' Absent / non-AA / empty / zero progress -> no line, not a lie.
    assertEqual(WatchStateCaption(invalid, "Watched"), "")
    assertEqual(WatchStateCaption("nope", "Watched"), "")
    assertEqual(WatchStateCaption({}, "Watched"), "")
    assertEqual(WatchStateCaption({ watched: false, position_ticks: 0, duration_ticks: 0, progress_percent: 0 }, "Watched"), "")
    assertEqual(WatchStateCaption({ watched: "yes", position_ticks: "5" }, "Watched"), "")
    print "TestWatchStateCaptionNeverRendersBlind passed"
end sub
