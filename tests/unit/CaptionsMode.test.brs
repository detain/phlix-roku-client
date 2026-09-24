' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/CaptionsMode.test.brs

' ===========================================
' Captions mode wire vocabulary - pure-function tests.
' Wire assertions are literal pins: they go red the moment anyone localizes
' a platform constant. Label assertions pair against Translate(key) instead
' of catalog literals, so they hold in BOTH catalog states (loaded device run
' and key-echo test run) - same convention as TranslateWithParams.test.brs.
' ===========================================

sub TestCaptionsModeWireValuesArePlatformLiterals()
    ' These four strings are the platform wire vocabulary consumed by
    ' roDeviceInfo.SetCaptionsMode() / Video.globalCaptionMode. Exact-byte
    ' pinning is the regression guard for the localized-label-into-
    ' SetCaptionsMode defect class (fix/captions-mode-wire-value).
    wire = GetCaptionsModeWireValues()
    assertEqual(wire.count(), 4)
    assertEqual(wire[0], "On")
    assertEqual(wire[1], "Off")
    assertEqual(wire[2], "Instant replay")
    assertEqual(wire[3], "When mute")
    print "TestCaptionsModeWireValuesArePlatformLiterals passed"
end sub

sub TestCaptionsModeWireIsFreshArray()
    ' Pure: every call returns a new array; callers cannot mutate shared state.
    wire = GetCaptionsModeWireValues()
    wire[0] = "mutated"
    assertEqual(GetCaptionsModeWireValues()[0], "On")
    print "TestCaptionsModeWireIsFreshArray passed"
end sub

sub TestCaptionsModeLabelsAreIndexParallel()
    ' The dialog binds button order to wire order by index; that pairing is
    ' the contract. Counts must stay locked and no label may ever be empty
    ' (value or key echo both render non-empty).
    wire = GetCaptionsModeWireValues()
    labels = CaptionsModeLabels()
    assertEqual(labels.count(), wire.count())
    for each label in labels
        assertTrue(label <> "")
    end for
    print "TestCaptionsModeLabelsAreIndexParallel passed"
end sub

sub TestCaptionsModeWireNeverCarriesCatalogKeys()
    ' Doctrine pin: the wire list holds machine values, never "settings_*"
    ' catalog keys - a key in the wire array means the label/wire swap is
    ' back.
    for each mode in GetCaptionsModeWireValues()
        assertTrue(Left(mode, 9) <> "settings_")
    end for
    print "TestCaptionsModeWireNeverCarriesCatalogKeys passed"
end sub

sub TestCaptionsModeLabelMapsWireToLocalizedLabel()
    ' Every wire value resolves to the display label at the SAME index -
    ' asserted against Translate(), so it holds whether or not the catalog
    ' is loaded.
    assertEqual(CaptionsModeLabel("On"), Translate("settings_button_caption_on"))
    assertEqual(CaptionsModeLabel("Off"), Translate("settings_button_caption_off"))
    assertEqual(CaptionsModeLabel("Instant replay"), Translate("settings_button_caption_instant_replay"))
    assertEqual(CaptionsModeLabel("When mute"), Translate("settings_button_caption_when_mute"))
    print "TestCaptionsModeLabelMapsWireToLocalizedLabel passed"
end sub

sub TestCaptionsModeLabelNormalizesSystemOff()
    ' GetCaptionsMode() answers "" when captions are disabled at the system
    ' level (the PlayerScene R6.5 start-up precedent); the settings display
    ' must render that as the "Off" mode's label, not blank.
    assertEqual(CaptionsModeLabel(""), Translate("settings_button_caption_off"))
    print "TestCaptionsModeLabelNormalizesSystemOff passed"
end sub

sub TestCaptionsModeLabelPassesUnknownThrough()
    ' An unrecognized value renders visibly rather than silently mis-mapping -
    ' the same fail-loud posture as an echoed missing catalog key.
    assertEqual(CaptionsModeLabel("FutureMode"), "FutureMode")
    print "TestCaptionsModeLabelPassesUnknownThrough passed"
end sub
