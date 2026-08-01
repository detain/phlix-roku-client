' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/Theme.test.brs

' ===========================================
' Theme Unit Tests
' ===========================================

sub TestThemeInit()
    ' Test Theme initialization
    theme = Theme()
    assertTrue(theme <> invalid)
    print "TestThemeInit passed"
end sub

sub TestThemeColors()
    ' Test Theme colors are defined
    theme = Theme()
    assertTrue(theme.colors <> invalid)
    assertTrue(theme.colors.primary <> invalid)
    assertTrue(theme.colors.secondary <> invalid)
    assertTrue(theme.colors.accent <> invalid)
    assertTrue(theme.colors.textPrimary <> invalid)
    assertTrue(theme.colors.textSecondary <> invalid)
    assertTrue(theme.colors.background <> invalid)
    assertTrue(theme.colors.surface <> invalid)
    print "TestThemeColors passed"
end sub

sub TestThemeColorValues()
    ' Test Theme color values are valid hex strings
    theme = Theme()
    assertEqual(theme.colors.primary, "#1a1a2e")
    assertEqual(theme.colors.secondary, "#0d0d1a")
    assertEqual(theme.colors.accent, "#0095d5")
    print "TestThemeColorValues passed"
end sub

sub TestThemeFonts()
    ' Test Theme fonts are defined
    theme = Theme()
    assertTrue(theme.fonts <> invalid)
    assertTrue(theme.fonts.largeBold <> invalid)
    assertTrue(theme.fonts.large <> invalid)
    assertTrue(theme.fonts.mediumBold <> invalid)
    assertTrue(theme.fonts.medium <> invalid)
    assertTrue(theme.fonts.small <> invalid)
    print "TestThemeFonts passed"
end sub

sub TestThemeSpacing()
    ' Test Theme spacing values are defined
    theme = Theme()
    assertTrue(theme.spacing <> invalid)
    assertTrue(theme.spacing.xs > 0)
    assertTrue(theme.spacing.sm > 0)
    assertTrue(theme.spacing.md > 0)
    assertTrue(theme.spacing.lg > 0)
    assertTrue(theme.spacing.xl > 0)
    print "TestThemeSpacing passed"
end sub

sub TestThemeSizes()
    ' Test Theme sizes are defined
    theme = Theme()
    assertTrue(theme.sizes <> invalid)
    assertTrue(theme.sizes.headerHeight > 0)
    assertTrue(theme.sizes.footerHeight > 0)
    assertTrue(theme.sizes.posterWidth > 0)
    assertTrue(theme.sizes.posterHeight > 0)
    assertTrue(theme.sizes.buttonHeight > 0)
    assertTrue(theme.sizes.buttonWidth > 0)
    assertTrue(theme.sizes.iconSize > 0)
    print "TestThemeSizes passed"
end sub

sub TestThemeGrid()
    ' Test Theme grid settings are defined
    theme = Theme()
    assertTrue(theme.grid <> invalid)
    assertTrue(theme.grid.numColumns > 0)
    assertTrue(theme.grid.numRows > 0)
    assertTrue(theme.grid.itemSpacing > 0)
    assertTrue(theme.grid.basePosterWidth > 0)
    assertTrue(theme.grid.basePosterHeight > 0)
    print "TestThemeGrid passed"
end sub
