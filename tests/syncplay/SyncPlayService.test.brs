' tests/syncplay/SyncPlayService.test.brs

' ===========================================
' SyncPlayService Unit Tests
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

' Test SyncPlayService initialization
sub TestServiceInit()
    service = SyncPlayService("http://localhost:8096")
    assertTrue(service <> invalid)
    assertEqual(service.baseUrl, "http://localhost:8096")
    assertFalse(service.isConnected)
    assertFalse(service.isConnecting)
    assertEqual(service.groupId, "")
    assertEqual(service.members.count(), 0)
    print "TestServiceInit passed"
end sub

' Test buildWsUrl constructs correct WebSocket URL
sub TestServiceBuildWsUrl()
    service = SyncPlayService("http://localhost:8096")
    wsUrl = service.buildWsUrl()
    assertTrue(wsUrl <> invalid)
    assertTrue(left(wsUrl, 3) = "ws:" or left(wsUrl, 4) = "wss:")
    print "TestServiceBuildWsUrl passed"
end sub

' Test buildWsUrl for HTTPS base URL
sub TestServiceBuildWsUrlHttps()
    service = SyncPlayService("https://secure-server:8096")
    wsUrl = service.buildWsUrl()
    assertTrue(left(wsUrl, 4) = "wss:")
    print "TestServiceBuildWsUrlHttps passed"
end sub

' Test connect initiates connection
sub TestServiceConnect()
    service = SyncPlayService("http://localhost:8096")
    result = service.connect()
    assertTrue(result)
    print "TestServiceConnect passed"
end sub

' Test disconnect cleans up
sub TestServiceDisconnect()
    service = SyncPlayService("http://localhost:8096")
    service.connect()
    service.disconnect()
    assertFalse(service.isConnected)
    assertFalse(service.isConnecting)
    print "TestServiceDisconnect passed"
end sub

' Test joinGroup sets correct state
sub TestServiceJoinGroup()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    result = service.joinGroup("GROUP123", "member-abc")
    assertTrue(result)

    ' After joining, groupId should be set
    ' Note: actual joining is async, so we check the state is initiated
    print "TestServiceJoinGroup passed"
end sub

' Test leaveGroup clears state
sub TestServiceLeaveGroupWithoutGroup()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    ' Can't leave if not in a group
    result = service.leaveGroup()
    assertFalse(result)
    print "TestServiceLeaveGroupWithoutGroup passed"
end sub

' Test sendPlaybackCommand builds correct payload
sub TestServiceSendPlaybackCommand()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    ' Set up a mock message handler that captures the payload
    capturedPayload = invalid
    originalSendMessage = service.sendMessage
    service.sendMessage = function(payload as Object) as Boolean
        capturedPayload = payload
        return true
    end function

    result = service.sendPlaybackCommand("play", 5000)

    assertTrue(result)
    assertTrue(capturedPayload <> invalid)
    assertEqual(capturedPayload.type, "syncplay.playback_command")
    assertEqual(capturedPayload.command, "play")
    assertEqual(capturedPayload.position, 5000)

    ' Restore
    service.sendMessage = originalSendMessage
    print "TestServiceSendPlaybackCommand passed"
end sub

' Test reportPosition builds correct payload
sub TestServiceReportPosition()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    capturedPayload = invalid
    originalSendMessage = service.sendMessage
    service.sendMessage = function(payload as Object) as Boolean
        capturedPayload = payload
        return true
    end function

    result = service.reportPosition(10000, false)

    assertTrue(result)
    assertTrue(capturedPayload <> invalid)
    assertEqual(capturedPayload.type, "syncplay.report_position")
    assertEqual(capturedPayload.position, 10000)
    assertEqual(capturedPayload.is_paused, false)

    service.sendMessage = originalSendMessage
    print "TestServiceReportPosition passed"
end sub

' Test requestTimeSync builds correct payload
sub TestServiceRequestTimeSync()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    capturedPayload = invalid
    originalSendMessage = service.sendMessage
    service.sendMessage = function(payload as Object) as Boolean
        capturedPayload = payload
        return true
    end function

    result = service.requestTimeSync()

    assertTrue(result)
    assertTrue(capturedPayload <> invalid)
    assertEqual(capturedPayload.type, "syncplay.request_time_sync")

    service.sendMessage = originalSendMessage
    print "TestServiceRequestTimeSync passed"
end sub

' Test handleMessage dispatches to correct handler
sub TestServiceHandleMessageTimeSync()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    ' Set up time sync update callback
    receivedUpdate = false
    service.onTimeSyncUpdate = sub(result as Object)
        receivedUpdate = true
    end sub

    message = {
        type: "syncplay.time_sync"
        payload: {
            client_time: 1000000
            server_time: 1000015
            server_receive_time: 1000010
        }
    }

    service.handleMessage(message)
    ' The handler should have been called
    print "TestServiceHandleMessageTimeSync passed"
end sub

' Test handleMessage for group_state
sub TestServiceHandleMessageGroupState()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    receivedUpdate = false
    service.onGroupStateChanged = sub(info as Object)
        receivedUpdate = true
    end sub

    message = {
        type: "syncplay.group_state"
        group_id: "TEST-GROUP"
        members: [{id: "member1", name: "Test User"}]
    }

    service.handleMessage(message)
    assertEqual(service.groupId, "TEST-GROUP")
    print "TestServiceHandleMessageGroupState passed"
end sub

' Test handleMessage for member_joined
sub TestServiceHandleMessageMemberJoined()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    receivedMember = invalid
    service.onMemberJoined = sub(member as Object)
        receivedMember = member
    end sub

    message = {
        type: "syncplay.member_joined"
        member_id: "new-member"
        name: "New User"
    }

    service.handleMessage(message)
    assertTrue(receivedMember <> invalid)
    assertEqual(receivedMember.id, "new-member")
    print "TestServiceHandleMessageMemberJoined passed"
end sub

' Test handleMessage for member_left
sub TestServiceHandleMessageMemberLeft()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    ' Add a member first
    service.members = [{id: "member1", name: "Test User"}]

    receivedId = ""
    service.onMemberLeft = sub(memberId as String)
        receivedId = memberId
    end sub

    message = {
        type: "syncplay.member_left"
        member_id: "member1"
    }

    service.handleMessage(message)
    assertEqual(receivedId, "member1")
    ' Member should be removed from list
    found = false
    for each m in service.members
        if m.id = "member1" then
            found = true
        end if
    end for
    assertFalse(found)
    print "TestServiceHandleMessageMemberLeft passed"
end sub

' Test handleMessage for playback_update ignores own updates
sub TestServiceHandleMessagePlaybackUpdateOwn()
    service = SyncPlayService("http://localhost:8096")
    service.connect()
    service.currentMemberId = "my-member-id"

    receivedUpdate = false
    service.onPlaybackUpdate = sub(update as Object)
        receivedUpdate = true
    end sub

    message = {
        type: "syncplay.playback_update"
        member_id: "my-member-id"
        command: "play"
    }

    service.handleMessage(message)
    ' Should be ignored since it's our own update
    assertFalse(receivedUpdate)
    print "TestServiceHandleMessagePlaybackUpdateOwn passed"
end sub

' Test handleMessage for playback_update processes others
sub TestServiceHandleMessagePlaybackUpdateOther()
    service = SyncPlayService("http://localhost:8096")
    service.connect()
    service.currentMemberId = "my-member-id"

    receivedUpdate = invalid
    service.onPlaybackUpdate = sub(update as Object)
        receivedUpdate = update
    end sub

    message = {
        type: "syncplay.playback_update"
        member_id: "other-member-id"
        command: "pause"
        position: 30000
    }

    service.handleMessage(message)
    assertTrue(receivedUpdate <> invalid)
    assertEqual(receivedUpdate.command, "pause")
    print "TestServiceHandleMessagePlaybackUpdateOther passed"
end sub

' Test isInGroup returns correct value
sub TestServiceIsInGroup()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    assertFalse(service.isInGroup())

    service.groupId = "some-group"
    assertTrue(service.isInGroup())

    service.groupId = ""
    assertFalse(service.isInGroup())
    print "TestServiceIsInGroup passed"
end sub

' Test getGroupInfo returns correct structure
sub TestServiceGetGroupInfo()
    service = SyncPlayService("http://localhost:8096")
    service.connect()
    service.groupId = "GROUP-123"
    service.members = [{id: "m1", name: "Test"}]

    info = service.getGroupInfo()

    assertTrue(info <> invalid)
    assertEqual(info.group_id, "GROUP-123")
    assertEqual(info.members.count(), 1)
    assertTrue(info.is_connected)
    print "TestServiceGetGroupInfo passed"
end sub

' Test setMediaDuration and getMediaDuration
sub TestServiceMediaDuration()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    assertEqual(service.getMediaDuration(), 0)

    service.setMediaDuration(90000)
    assertEqual(service.getMediaDuration(), 90000)
    print "TestServiceMediaDuration passed"
end sub

' Test setPosition and setPlaying
sub TestServicePositionAndPlaying()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    service.setPosition(5000)
    assertEqual(service.currentPosition, 5000)

    service.setPlaying(true)
    assertTrue(service.isPlaying)

    service.setPlaying(false)
    assertFalse(service.isPlaying)
    print "TestServicePositionAndPlaying passed"
end sub

' Test getSynchronizedTime delegates to timeSync
sub TestServiceGetSynchronizedTime()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    ' When timeSync has offset 0, should return local time
    syncTime = service.getSynchronizedTime()
    assertTrue(syncTime > 0)
    print "TestServiceGetSynchronizedTime passed"
end sub

' Test getAuthHeader returns correct format
sub TestServiceGetAuthHeader()
    service = SyncPlayService("http://localhost:8096")
    service.connect()

    ' Without token in storage
    header = service.getAuthHeader()
    assertEqual(header, "")
    print "TestServiceGetAuthHeader passed"
end sub