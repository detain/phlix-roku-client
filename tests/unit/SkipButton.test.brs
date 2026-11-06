' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SkipButton.test.brs

' copyright 2026 Joe Huss
'


' ===========================================
' SkipButton Unit Tests
' ===========================================

' Test SkipButton initialization
sub TestSkipButtonInit()
    skipBtn = SkipButton()
    assertTrue(skipBtn <> invalid)
    print "TestSkipButtonInit passed"
end sub

' Test setMarkers with valid intro markers
sub TestSetMarkersWithIntro()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: invalid
        skip_outro_end: invalid
    })

    assertTrue(skipBtn.hasIntroMarkers())
    assertFalse(skipBtn.hasOutroMarkers())
    print "TestSetMarkersWithIntro passed"
end sub

' Test setMarkers with valid outro markers
sub TestSetMarkersWithOutro()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: invalid
        skip_intro_end: invalid
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    assertFalse(skipBtn.hasIntroMarkers())
    assertTrue(skipBtn.hasOutroMarkers())
    print "TestSetMarkersWithOutro passed"
end sub

' Test setMarkers with both intro and outro
sub TestSetMarkersWithBoth()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    assertTrue(skipBtn.hasIntroMarkers())
    assertTrue(skipBtn.hasOutroMarkers())
    print "TestSetMarkersWithBoth passed"
end sub

' Test setMarkers with null clears markers
sub TestSetMarkersNullClears()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    skipBtn.setMarkers(invalid)

    assertFalse(skipBtn.hasIntroMarkers())
    assertFalse(skipBtn.hasOutroMarkers())
    print "TestSetMarkersNullClears passed"
end sub

' Test isPositionInIntroRange returns true when in range
sub TestIsPositionInIntroRangeTrue()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: invalid
        skip_outro_end: invalid
    })

    assertTrue(skipBtn.isPositionInIntroRange(50))
    assertTrue(skipBtn.isPositionInIntroRange(10))
    assertTrue(skipBtn.isPositionInIntroRange(90))
    print "TestIsPositionInIntroRangeTrue passed"
end sub

' Test isPositionInIntroRange returns false when out of range
sub TestIsPositionInIntroRangeFalse()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: invalid
        skip_outro_end: invalid
    })

    assertFalse(skipBtn.isPositionInIntroRange(5))
    assertFalse(skipBtn.isPositionInIntroRange(100))
    print "TestIsPositionInIntroRangeFalse passed"
end sub

' Test isPositionInIntroRange returns false when no markers
sub TestIsPositionInIntroRangeNoMarkers()
    skipBtn = SkipButton()
    skipBtn.setMarkers(invalid)

    assertFalse(skipBtn.isPositionInIntroRange(50))
    print "TestIsPositionInIntroRangeNoMarkers passed"
end sub

' Test isPositionInOutroRange returns true when in range
sub TestIsPositionInOutroRangeTrue()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: invalid
        skip_intro_end: invalid
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    assertTrue(skipBtn.isPositionInOutroRange(2400))
    assertTrue(skipBtn.isPositionInOutroRange(2340))
    assertTrue(skipBtn.isPositionInOutroRange(2520))
    print "TestIsPositionInOutroRangeTrue passed"
end sub

' Test isPositionInOutroRange returns false when out of range
sub TestIsPositionInOutroRangeFalse()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: invalid
        skip_intro_end: invalid
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    assertFalse(skipBtn.isPositionInOutroRange(2300))
    assertFalse(skipBtn.isPositionInOutroRange(2600))
    print "TestIsPositionInOutroRangeFalse passed"
end sub

' Test updatePosition shows intro button when in intro range
sub TestUpdatePositionShowsIntroButton()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: invalid
        skip_outro_end: invalid
    })

    inRange = skipBtn.updatePosition(50)
    assertTrue(inRange)
    assertEqual(skipBtn.activeMarkerType, "intro")
    print "TestUpdatePositionShowsIntroButton passed"
end sub

' Test updatePosition shows outro button when in outro range
sub TestUpdatePositionShowsOutroButton()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: invalid
        skip_intro_end: invalid
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    inRange = skipBtn.updatePosition(2400)
    assertTrue(inRange)
    assertEqual(skipBtn.activeMarkerType, "outro")
    print "TestUpdatePositionShowsOutroButton passed"
end sub

' Test updatePosition returns false when not in any range
sub TestUpdatePositionReturnsFalseWhenNotInRange()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    inRange = skipBtn.updatePosition(500)
    assertFalse(inRange)
    assertEqual(skipBtn.activeMarkerType, "")
    print "TestUpdatePositionReturnsFalseWhenNotInRange passed"
end sub

' Test getTargetPosition returns correct position for intro
sub TestGetTargetPositionIntro()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: invalid
        skip_outro_end: invalid
    })

    skipBtn.updatePosition(50)
    target = skipBtn.getTargetPosition()
    assertEqual(target, 90)
    print "TestGetTargetPositionIntro passed"
end sub

' Test getTargetPosition returns correct position for outro
sub TestGetTargetPositionOutro()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: invalid
        skip_intro_end: invalid
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    skipBtn.updatePosition(2400)
    target = skipBtn.getTargetPosition()
    assertEqual(target, 2520)
    print "TestGetTargetPositionOutro passed"
end sub

' Test getTargetPosition returns 0 when no active marker
sub TestGetTargetPositionNoActiveMarker()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    ' Position not in any range
    skipBtn.updatePosition(500)
    target = skipBtn.getTargetPosition()
    assertEqual(target, 0)
    print "TestGetTargetPositionNoActiveMarker passed"
end sub

' Test intro markers don't trigger outro range
sub TestIntroDoesNotTriggerOutro()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    ' Position in intro range should not show outro
    inRange = skipBtn.updatePosition(50)
    assertTrue(inRange)
    assertEqual(skipBtn.activeMarkerType, "intro")
    assertEqual(skipBtn.getTargetPosition(), 90)
    print "TestIntroDoesNotTriggerOutro passed"
end sub

' Test outro markers don't trigger intro range
sub TestOutroDoesNotTriggerIntro()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
        skip_outro_start: 2340
        skip_outro_end: 2520
    })

    ' Position in outro range should not show intro
    inRange = skipBtn.updatePosition(2400)
    assertTrue(inRange)
    assertEqual(skipBtn.activeMarkerType, "outro")
    assertEqual(skipBtn.getTargetPosition(), 2520)
    print "TestOutroDoesNotTriggerIntro passed"
end sub
' ============================================================
' [RT-003 review roku__exploiter M4] The wire is untyped: a skip marker can
' arrive as a JSON string ("90"), a Boolean, or a container. The pre-fix
' setMarkers copied raw values, so the range law became a mixed-type compare
' (`position >= "10"` crashes the render thread on device) and the raw value
' rode skipRequested, a typed float field. The cure parses at the boundary:
' boxed numerics are kept, everything else becomes invalid so the existing
' invalid-guards treat it as "no marker" instead of tripping over it.
' ============================================================

' Test a string-marker pair is parsed away, not kept (red at the parent:
' the raw copy made hasIntroMarkers() claim a pair of Strings exists).
sub TestSetMarkersStringValuesBecomeInvalid()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: "10"
        skip_intro_end: "90"
        skip_outro_start: invalid
        skip_outro_end: invalid
    })

    assertFalse(skipBtn.hasIntroMarkers())
    assertFalse(skipBtn.isPositionInIntroRange(50))
    print "TestSetMarkersStringValuesBecomeInvalid passed"
end sub

' Test a non-associative marker payload (array shape) clears every pair.
sub TestSetMarkersNonAssocArrayClears()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
        skip_intro_end: 90
    })
    assertTrue(skipBtn.hasIntroMarkers())

    skipBtn.setMarkers(["skip_intro_start", 10, 90])

    assertFalse(skipBtn.hasIntroMarkers())
    assertFalse(skipBtn.hasOutroMarkers())
    print "TestSetMarkersNonAssocArrayClears passed"
end sub

' Test fractional seconds survive the parse (the reader must not be
' Integer-only: markers are Float seconds on the wire).
sub TestSetMarkersFloatSecondsKept()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10.5
        skip_intro_end: 90.25
    })

    assertTrue(skipBtn.hasIntroMarkers())
    assertTrue(skipBtn.isPositionInIntroRange(50))
    assertEqual(skipBtn.getTargetPosition(), 0)
    print "TestSetMarkersFloatSecondsKept passed"
end sub

' Test a lone half-pair (missing key) is not a pair: hasIntroMarkers must
' refuse when only the start leg exists on the wire.
sub TestSetMarkersHalfPairIsNotAPair()
    skipBtn = SkipButton()
    skipBtn.setMarkers({
        skip_intro_start: 10
    })

    assertFalse(skipBtn.hasIntroMarkers())
    assertFalse(skipBtn.isPositionInIntroRange(50))
    print "TestSetMarkersHalfPairIsNotAPair passed"
end sub
