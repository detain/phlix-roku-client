' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/TranslateWithParams.test.brs

' ===========================================
' i18n token substitution - pure-function tests.
' ApplyNamedTokens/TokenValueText never touch the catalog, so every assertion
' here is device-independent. TranslateWithParams assertions pair against
' Translate(key) instead of catalog literals, so they hold in BOTH catalog
' states (loaded device run and key-echo test run).
' ===========================================

' ---- ApplyNamedTokens: position-free substitution by name ----

sub TestApplyNamedTokensPositionFree()
    ' The whole point: the value renders wherever the token sits in the
    ' sentence - token-first, mid-phrase, or phrase-first locales alike.
    assertEqual(ApplyNamedTokens("{count} chapters", { count: "3" }), "3 chapters")
    assertEqual(ApplyNamedTokens("Hauptkapitel {count}", { count: "3" }), "Hauptkapitel 3")
    assertEqual(ApplyNamedTokens("メンバー{count}人", { count: "7" }), "メンバー7人")
    print "TestApplyNamedTokensPositionFree passed"
end sub

sub TestApplyNamedTokensMultiParam()
    params = { email: "user@x.io", url: "http://h:8096" }
    result = ApplyNamedTokens("{email} on {url}", params)
    assertEqual(result, "user@x.io on http://h:8096")
    print "TestApplyNamedTokensMultiParam passed"
end sub

sub TestApplyNamedTokensRepeatedToken()
    ' Replace is by name and replaces every occurrence of the token.
    assertEqual(ApplyNamedTokens("{a}-{a}", { a: "x" }), "x-x")
    print "TestApplyNamedTokensRepeatedToken passed"
end sub

sub TestApplyNamedTokensUnknownTokensLeftAlone()
    ' Params name tokens the text does not carry: no-op. Text carries tokens
    ' the params do not name: the literal braces stay visible (fail-loud,
    ' same rendering class as a missing catalog key).
    assertEqual(ApplyNamedTokens("plain text", { ghost: "g" }), "plain text")
    assertEqual(ApplyNamedTokens("keep {ghost} out", { named: "n" }), "keep {ghost} out")
    print "TestApplyNamedTokensUnknownTokensLeftAlone passed"
end sub

sub TestApplyNamedTokensNonStringCoercion()
    ' Integers render sign-free (the repo's str().trim() idiom), booleans
    ' render true/false, unknown-typed values leave the token visible.
    assertEqual(ApplyNamedTokens("v{ n }", { "n": invalid }), "v{ n }")
    p1 = { n: 42 }
    assertEqual(ApplyNamedTokens("n={n}", p1), "n=42")
    p2 = { n: -7 }
    assertEqual(ApplyNamedTokens("n={n}", p2), "n=-7")
    p3 = { n: true }
    assertEqual(ApplyNamedTokens("n={n}", p3), "n=true")
    p4 = { n: false }
    assertEqual(ApplyNamedTokens("n={n}", p4), "n=false")
    print "TestApplyNamedTokensNonStringCoercion passed"
end sub

sub TestApplyNamedTokensInvalidParamsDegrade()
    ' Total on bad dictionary input: unchanged text, never a crash.
    assertEqual(ApplyNamedTokens("{a} b", invalid), "{a} b")
    assertEqual(ApplyNamedTokens("{a} b", {}), "{a} b")
    assertEqual(ApplyNamedTokens("{a} b", "not-an-aa"), "{a} b")
    print "TestApplyNamedTokensInvalidParamsDegrade passed"
end sub

sub TestApplyNamedTokensPurity()
    ' Same inputs, same output; the input AA is not consumed or mutated.
    params = { count: "9" }
    first = ApplyNamedTokens("{count} items", params)
    second = ApplyNamedTokens("{count} items", params)
    assertEqual(first, second)
    assertEqual(params.count(), 1)
    print "TestApplyNamedTokensPurity passed"
end sub

' ---- TokenValueText: the render/coerce decision ----

sub TestTokenValueTextRendersAndRejects()
    assertEqual(TokenValueText("s"), "s")
    p = 5
    assertEqual(TokenValueText(p), "5")
    assertEqual(TokenValueText(true), "true")
    assertEqual(TokenValueText(invalid), invalid)
    assertEqual(TokenValueText({}), invalid)
    assertEqual(TokenValueText([]), invalid)
    print "TestTokenValueTextRendersAndRejects passed"
end sub

' ---- TranslateWithParams: catalog bound + degradation ----

sub TestTranslateWithParamsEqualsTranslateOnDegradedParams()
    ' Device-independent in both catalog states: degraded params must behave
    ' exactly like plain Translate(key) - no substitution, no crash.
    key = "settings_status_logged_in_as"
    assertEqual(TranslateWithParams(key, invalid), Translate(key))
    assertEqual(TranslateWithParams(key, {}), Translate(key))
    print "TestTranslateWithParamsEqualsTranslateOnDegradedParams passed"
end sub

sub TestTranslateWithParamsNeverCrashesOnUnknownKey()
    ' Unknown key echoes through the substitution untouched (both catalog
    ' states): the key text carries no braces, so nothing substitutes.
    result = TranslateWithParams("no_such_key_anywhere", { token: "v" })
    assertEqual(result, "no_such_key_anywhere")
    print "TestTranslateWithParamsNeverCrashesOnUnknownKey passed"
end sub

sub TestTranslateWithParamsKnownCodeNeverEmpty()
    ' Every token-bearing catalog key consumed by the client resolves to a
    ' non-empty line in any catalog state (value or key echo), and passing
    ' its documented params never yields "".
    keys = []
    keys.push("settings_status_logged_in_as")
    keys.push("settings_status_server")
    keys.push("settings_caption_mode_label")
    keys.push("settings_caption_mode_set_to")
    keys.push("settings_about_version")
    keys.push("settings_about_device_model")
    keys.push("settings_about_device_id")
    keys.push("settings_autoplay_label")
    keys.push("settings_quality_label")
    keys.push("settings_dialog_account_message")
    keys.push("settings_dialog_server_message")
    keys.push("settings_dialog_captions_message")
    keys.push("detail_chapters_count")
    keys.push("detail_rating_label")
    keys.push("detail_rated_label")
    keys.push("syncplay_members_count")
    for each key in keys
        assertTrue(TranslateWithParams(key, { token: "v" }) <> "")
    end for
    print "TestTranslateWithParamsKnownCodeNeverEmpty passed"
end sub
