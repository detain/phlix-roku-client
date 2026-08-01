' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SleepTimer.test.brs

' ===========================================
' SleepTimer Unit Tests
' ===========================================

sub TestSleepTimerInit()
    ' Test initialization
    timer = SleepTimer()
    assertTrue(timer <> invalid)
    assertEqual(timer.remainingMs, 0)
    assertFalse(timer.isActive)
    print "TestSleepTimerInit passed"
end sub

sub TestSleepTimerInitWithNodes()
    ' Test init with UI nodes
    timer = SleepTimer()
    ' Create mock nodes (in real BrightScript these would be actual nodes)
    timer.init(invalid, invalid, invalid, invalid)
    assertTrue(timer <> invalid)
    print "TestSleepTimerInitWithNodes passed"
end sub

sub TestSleepTimerSetVideoPlayer()
    ' Test setVideoPlayer stores reference
    timer = SleepTimer()
    timer.setVideoPlayer(invalid)
    assertEqual(timer.videoPlayer, invalid)
    print "TestSleepTimerSetVideoPlayer passed"
end sub

sub TestSleepTimerBuildPresetContent()
    ' Test buildPresetContent creates content nodes
    timer = SleepTimer()
    content = timer.buildPresetContent()
    assertTrue(content <> invalid)
    print "TestSleepTimerBuildPresetContent passed"
end sub

sub TestSleepTimerShowPanelWithInvalidPanel()
    ' Test showPanel does nothing when panel is invalid
    timer = SleepTimer()
    timer.panel = invalid
    timer.showPanel()
    ' Should not throw
    assertTrue(true)
    print "TestSleepTimerShowPanelWithInvalidPanel passed"
end sub

sub TestSleepTimerHidePanelWithInvalidPanel()
    ' Test hidePanel does nothing when panel is invalid
    timer = SleepTimer()
    timer.panel = invalid
    timer.hidePanel()
    ' Should not throw
    assertTrue(true)
    print "TestSleepTimerHidePanelWithInvalidPanel passed"
end sub

sub TestSleepTimerTogglePanelWithInvalidPanel()
    ' Test togglePanel returns false when panel is invalid
    timer = SleepTimer()
    timer.panel = invalid
    result = timer.togglePanel()
    assertFalse(result)
    print "TestSleepTimerTogglePanelWithInvalidPanel passed"
end sub

sub TestSleepTimerStartWithSecondsInvalid()
    ' Test startWithSeconds rejects invalid duration
    timer = SleepTimer()
    result = timer.startWithSeconds(0)
    assertFalse(result)
    result = timer.startWithSeconds(-1)
    assertFalse(result)
    print "TestSleepTimerStartWithSecondsInvalid passed"
end sub

sub TestSleepTimerStartWithSecondsValid()
    ' Test startWithSeconds accepts valid duration
    timer = SleepTimer()
    result = timer.startWithSeconds(60)
    assertTrue(result)
    print "TestSleepTimerStartWithSecondsValid passed"
end sub

sub TestSleepTimerStartFromPresetInvalidIndex()
    ' Test startFromPreset rejects invalid index
    timer = SleepTimer()
    assertFalse(timer.startFromPreset(-1))
    assertFalse(timer.startFromPreset(10))
    assertFalse(timer.startFromPreset(100))
    print "TestSleepTimerStartFromPresetInvalidIndex passed"
end sub

sub TestSleepTimerCancelWhenNotActive()
    ' Test cancel returns false when not active
    timer = SleepTimer()
    result = timer.cancel()
    assertFalse(result)
    print "TestSleepTimerCancelWhenNotActive passed"
end sub

sub TestSleepTimerStopWhenNotRunning()
    ' Test stop handles not-running state
    timer = SleepTimer()
    timer.stop()
    ' Should not throw
    assertTrue(true)
    print "TestSleepTimerStopWhenNotRunning passed"
end sub

sub TestSleepTimerGetRemainingFormattedWhenNotActive()
    ' Test getRemainingFormatted returns empty when not active
    timer = SleepTimer()
    result = timer.getRemainingFormatted()
    assertEqual(result, "")
    print "TestSleepTimerGetRemainingFormattedWhenNotActive passed"
end sub

sub TestSleepTimerIsActive()
    ' Test isActive returns current state
    timer = SleepTimer()
    assertFalse(timer.isActive())
    print "TestSleepTimerIsActive passed"
end sub

sub TestSleepTimerGetCurrentPresetIndex()
    ' Test getCurrentPresetIndex returns initial value
    timer = SleepTimer()
    assertEqual(timer.getCurrentPresetIndex(), -1)
    print "TestSleepTimerGetCurrentPresetIndex passed"
end sub

sub TestSleepTimerCleanup()
    ' Test cleanup stops timer and hides UI
    timer = SleepTimer()
    timer.cleanup()
    ' Should not throw
    assertFalse(timer.isActive)
    print "TestSleepTimerCleanup passed"
end sub

sub TestSleepTimerOnSleepTimerTickNotActive()
    ' Test OnSleepTimerTick does nothing when not active
    timer = SleepTimer()
    timer.OnSleepTimerTick()
    ' Should not throw
    assertTrue(true)
    print "TestSleepTimerOnSleepTimerTickNotActive passed"
end sub

sub TestFormatDuration()
    ' Test formatDuration function
    assertEqual(formatDuration(0), "0:00")
    assertEqual(formatDuration(60), "1:00")
    assertEqual(formatDuration(3600), "1:00:00")
    assertEqual(formatDuration(3661), "1:01:01")
    assertEqual(formatDuration(90), "1:30")
    print "TestFormatDuration passed"
end sub

sub TestFormatDurationNegative()
    ' Test formatDuration handles negative input
    result = formatDuration(-100)
    assertEqual(result, "0:00")
    print "TestFormatDurationNegative passed"
end sub

sub TestPadz()
    ' Test padz function
    assertEqual(padz("1", 2), "01")
    assertEqual(padz("12", 2), "12")
    assertEqual(padz("1", 4), "0001")
    assertEqual(padz("12345", 3), "12345")
    print "TestPadz passed"
end sub

sub TestSleepTimerFactory()
    ' Test SleepTimerFactory function
    timer = SleepTimerFactory()
    assertTrue(timer <> invalid)
    assertEqual(timer.remainingMs, 0)
    print "TestSleepTimerFactory passed"
end sub
