' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/DetailSceneYear.test.brs

' ===========================================
' DetailScene Year-Gate Unit Tests (w12L3-R3)
'
' RT-036 render conviction: the revived DisplaySimilar year gate is driven
' HERE, from the shipped component file, through the harness EXTRA_SOURCES
' mechanism (brs 0.45 mocks generic ContentNode trees — probe-measured:
' CreateChild/GetChild/property get+set work and an unset field answers the
' device default ""). This is the behavioral pin the w12L3 review asked for
' next to Check 98 R3's static legs.
'
' Venue facts measured before these assertions were written (brs 0.45 and,
' where they differ, the device spelling is what the gate family covers):
'  - a ParseJSON'd integer member answers type() "Integer" (the boxed
'    Object-formal path answers "roInt"); NEVER the dead name "Int";
'  - a hand-built decimal literal answers "Float" here (device may spell it
'    "Double" — both names live in the family, and the RENDER assertion is
'    venue-agnostic);
'  - str(1998) = " 1998" — the trim() in the render is load-bearing;
'  - an AA member that is absent or JSON null reads back invalid.
' ===========================================

sub BoxedTypeOf(x as Object) as String
    return type(x)
end sub

sub TestDisplaySimilarRendersJsonIntegerYear()
    q = Chr(34)
    items = ParseJSON("[" + "{" + q + "title" + q + ": " + q + "Forever" + q + ", " + q + "year" + q + ": 1998" + "}" + "]")
    assertTrue(items <> invalid, "ParseJSON fixture must build")
    m.similarGrid = {}
    DisplaySimilar(items)
    content = m.similarGrid.content
    assertTrue(content <> invalid, "DisplaySimilar must publish the grid content")
    child = content.GetChild(0)
    assertTrue(child <> invalid, "one similar item must produce one ContentNode child")
    assertEqual(child.ShortDescriptionLine1, "1998", "RT-036: the revived boxed-family arm renders the JSON integer year through str().trim() — if the gate ever re-grows the dead ""Int"" spelling this line renders nothing and this test reddens")
    print "TestDisplaySimilarRendersJsonIntegerYear passed"
end sub

sub TestDisplaySimilarRendersHandBuiltFloatYear()
    items = [ { title: "Hellsing", year: 1998.5 } ]
    m.similarGrid = {}
    DisplaySimilar(items)
    child = m.similarGrid.content.GetChild(0)
    assertTrue(child <> invalid, "one similar item must produce one ContentNode child")
    assertEqual(child.ShortDescriptionLine1, "1998.5", "a non-JSON numeric spelling in the boxed family renders too — a family-narrowing regression (dropping Float/Double legs) reddens this test")
    print "TestDisplaySimilarRendersHandBuiltFloatYear passed"
end sub

sub TestDisplaySimilarLeavesNonNumericYearsUnrendered()
    items = [ { title: "NoYear" }, { title: "NullYear", year: invalid }, { title: "StringYear", year: "1998" } ]
    m.similarGrid = {}
    DisplaySimilar(items)
    content = m.similarGrid.content
    c0 = content.GetChild(0)
    c1 = content.GetChild(1)
    c2 = content.GetChild(2)
    assertTrue(c0 <> invalid and c1 <> invalid and c2 <> invalid, "three items must produce three children")
    ' An unset ContentNode field answers the device default "" in BOTH venues
    ' (brs mock measured; device field defaults are ""), so equality against
    ' the empty string is the venue-agnostic "rendered nothing" assertion.
    assertEqual(c0.ShortDescriptionLine1, "", "an absent year must not render")
    assertEqual(c1.ShortDescriptionLine1, "", "an invalid/JSON-null year must not render")
    assertEqual(c2.ShortDescriptionLine1, "", "a String year must not render — the gate is numeric-family only")
    print "TestDisplaySimilarLeavesNonNumericYearsUnrendered passed"
end sub

sub TestYearGateVenuePremise()
    q = Chr(34)
    o = ParseJSON("{" + q + "year" + q + ": 1998}")
    assertTrue(o <> invalid, "premise fixture must parse")
    t = type(o.year)
    assertNotEqual(t, "Int", "RT-036 law: the firmware never emits the type name ""Int"" — the name the dead arm keyed on stays extinct")
    assertTrue(t = "Integer" or t = "roInt", "a JSON integer member answers the boxed-family spellings the revived gate keys on (headless venue: Integer; boxed paths: roInt)")
    assertEqual(BoxedTypeOf(1998), "roInt", "the Object-formal boxing answers roInt — one of the family names the revival carries")
    s = str(1998)
    assertEqual(s.trim(), "1998", "str() renders with a leading space; the preserved .trim() is the render shape")
    print "TestYearGateVenuePremise passed"
end sub
