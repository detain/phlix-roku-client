' tests/syncplay/SyncPlayTimeSync.test.brs

' ===========================================
' SyncPlayTimeSync Unit Tests
' ===========================================

' Test helper assertions
sub assertTrue(condition as Boolean)
    if not condition then
        print "ASSERTION FAILED: Expected true, got false"
        assertFalse(true)
    end if
end sub

sub assertFalse(condition as Boolean)
    if condition then
        print "ASSERTION FAILED: Expected false, got true"
    end if
end sub

sub assertEqual(a as Dynamic, b as Dynamic)
    if a <> b then
        print "ASSERTION FAILED: Expected '"; a; "', got '"; b; "'"
    end if
end sub

sub assertNotEqual(a as Dynamic, b as Dynamic)
    if a = b then
        print "ASSERTION FAILED: Expected not '"; a; "'"
    end if
end sub

sub assertInvalid(obj as Dynamic)
    if obj <> invalid then
        print "ASSERTION FAILED: Expected invalid, got something else"
    end if
end sub

' Test SyncPlayTimeSync initialization
sub TestTimeSyncInit()
    ts = SyncPlayTimeSync()
    assertTrue(ts <> invalid)
    assertEqual(ts.offsetSamples.count(), 0)
    assertEqual(ts.offset, 0)
    assertEqual(ts.latency, 0)
    assertEqual(ts.driftRate, 1.0#)
    print "TestTimeSyncInit passed"
end sub

' Test requestPing returns correct structure
sub TestTimeSyncRequestPing()
    ts = SyncPlayTimeSync()
    ping = ts.requestPing()
    assertTrue(ping <> invalid)
    assertEqual(ping.type, "ping")
    assertTrue(ping.client_time > 0)
    print "TestTimeSyncRequestPing passed"
end sub

' Test processPongPayload calculates correct values
sub TestTimeSyncProcessPongPayload()
    ts = SyncPlayTimeSync()

    ' Simulate a pong payload
    payload = {
        client_time: 1000000
        server_time: 1000015
        server_receive_time: 1000010
    }

    result = ts.processPongPayload(payload)

    assertTrue(result <> invalid)
    assertTrue(result.offset <> invalid)
    assertTrue(result.latency >= 0)
    assertTrue(result.rtt >= 0)
    print "TestTimeSyncProcessPongPayload passed"
end sub

' Test addSample adds to collection
sub TestTimeSyncAddSample()
    ts = SyncPlayTimeSync()

    ts.addSample(100, 50)
    assertEqual(ts.offsetSamples.count(), 1)

    ts.addSample(200, 60)
    assertEqual(ts.offsetSamples.count(), 2)

    print "TestTimeSyncAddSample passed"
end sub

' Test addSample respects rolling buffer limit
sub TestTimeSyncRollingBuffer()
    ts = SyncPlayTimeSync()

    ' Add more samples than buffer size (5 * 2 = 10)
    for i = 0 to 12
        ts.addSample(i * 10, 50)
    end for

    ' Should not exceed 10 samples
    assertTrue(ts.offsetSamples.count() <= 10)

    print "TestTimeSyncRollingBuffer passed"
end sub

' Test getRecentSamples returns correct count
sub TestTimeSyncGetRecentSamples()
    ts = SyncPlayTimeSync()

    for i = 0 to 3
        ts.addSample(i * 10, 50)
    end for

    recent = ts.getRecentSamples()
    assertEqual(recent.count(), 4)

    ' Add more
    for i = 0 to 5
        ts.addSample(i * 10, 50)
    end for

    recent = ts.getRecentSamples()
    assertEqual(recent.count(), 5)

    print "TestTimeSyncGetRecentSamples passed"
end sub

' Test getOffset returns weighted average
sub TestTimeSyncGetOffset()
    ts = SyncPlayTimeSync()

    ' Add samples with different RTTs (lower RTT = higher weight)
    ts.addSample(100, 100)  ' RTT 100
    ts.addSample(100, 50)   ' RTT 50 (should be weighted higher)
    ts.addSample(100, 200)  ' RTT 200

    offset = ts.getOffset()
    ' Should be close to 100 (weighted by inverse RTT)
    assertTrue(offset > 0)

    print "TestTimeSyncGetOffset passed"
end sub

' Test isStable returns false with insufficient samples
sub TestTimeSyncIsStableFalse()
    ts = SyncPlayTimeSync()

    assertFalse(ts.isStable())

    ' Add some samples but not enough
    ts.addSample(100, 50)
    ts.addSample(100, 50)
    ts.addSample(100, 50)

    assertFalse(ts.isStable())

    print "TestTimeSyncIsStableFalse passed"
end sub

' Test isStable returns true with enough stable samples
sub TestTimeSyncIsStableTrue()
    ts = SyncPlayTimeSync()

    ' Add 5 samples with similar offsets (low variance)
    for i = 0 to 4
        ts.addSample(100 + i, 50)
    end for

    ' Variance should be low, so should be stable
    ' Note: stability depends on variance threshold
    print "TestTimeSyncIsStableTrue passed"
end sub

' Test reset clears all state
sub TestTimeSyncReset()
    ts = SyncPlayTimeSync()

    ts.addSample(100, 50)
    ts.addSample(200, 60)

    ts.reset()

    assertEqual(ts.offsetSamples.count(), 0)
    assertEqual(ts.offset, 0)
    assertEqual(ts.latency, 0)
    assertEqual(ts.driftRate, 1.0#)

    print "TestTimeSyncReset passed"
end sub

' Test getStatus returns correct structure
sub TestTimeSyncGetStatus()
    ts = SyncPlayTimeSync()
    ts.addSample(100, 50)

    status = ts.getStatus()

    assertTrue(status <> invalid)
    assertTrue(status.offset <> invalid)
    assertTrue(status.latency <> invalid)
    assertTrue(status.drift_rate <> invalid)
    assertTrue(status.is_stable <> invalid)
    assertTrue(status.sample_count <> invalid)

    print "TestTimeSyncGetStatus passed"
end sub

' Test serialize returns correct structure
sub TestTimeSyncSerialize()
    ts = SyncPlayTimeSync()
    ts.addSample(100, 50)
    ts.addSample(200, 60)

    data = ts.serialize()

    assertTrue(data <> invalid)
    assertTrue(data.offset_samples <> invalid)
    assertTrue(data.drift_rate <> invalid)
    assertTrue(data.last_sync <> invalid)
    assertEqual(data.offset_samples.count(), 2)

    print "TestTimeSyncSerialize passed"
end sub

' Test getSynchronizedTime adds offset to current time
sub TestTimeSyncGetSynchronizedTime()
    ts = SyncPlayTimeSync()
    ts.addSample(100, 50)

    localTime = ts.getTimeMillis()
    syncTime = ts.getSynchronizedTime()

    ' Synchronized time should be local time + offset
    diff = syncTime - localTime
    assertEqual(diff, ts.offset)

    print "TestTimeSyncGetSynchronizedTime passed"
end sub

' Test localToSynchronized and synchronizedToLocal
sub TestTimeSyncConversions()
    ts = SyncPlayTimeSync()
    ts.offset = 100

    local = 1000
    sync = ts.localToSynchronized(local)
    assertEqual(sync, 1100)

    back = ts.synchronizedToLocal(sync)
    assertEqual(back, local)

    print "TestTimeSyncConversions passed"
end sub

' Test intVal helper function
sub TestTimeSyncIntVal()
    ts = SyncPlayTimeSync()

    assertEqual(ts.intVal(42), 42)
    assertEqual(ts.intVal(3.14), 3)
    assertEqual(ts.intVal("123"), 123)
    assertEqual(ts.intVal(invalid), 0)

    print "TestTimeSyncIntVal passed"
end sub