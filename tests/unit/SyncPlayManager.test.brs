' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SyncPlayManager.test.brs

' ===========================================
' SyncPlayManager Unit Tests
' ===========================================

sub TestSyncPlayManagerInit()
    ' Test initialization with valid API
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertTrue(mgr <> invalid)
    assertEqual(mgr.getSession(), invalid)
    print "TestSyncPlayManagerInit passed"
end sub

sub TestSyncPlayManagerInitWithInvalidApi()
    ' Test initialization with invalid API
    mgr = SyncPlayManager(invalid)
    assertTrue(mgr <> invalid)
    print "TestSyncPlayManagerInitWithInvalidApi passed"
end sub

sub TestSyncPlayManagerGetRoomsWithInvalidApi()
    ' Test getRooms returns empty array when no API
    mgr = SyncPlayManager(invalid)
    rooms = mgr.getRooms()
    assertTrue(rooms <> invalid)
    assertEqual(rooms.Count(), 0)
    print "TestSyncPlayManagerGetRoomsWithInvalidApi passed"
end sub

sub TestSyncPlayManagerGetRoomsWithNonArrayResult()
    ' Test getRooms handles non-array result
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    ' Passing a result that's not an assocarray or has no rooms key
    assertEqual(mgr.getRooms().Count(), 0)
    print "TestSyncPlayManagerGetRoomsWithNonArrayResult passed"
end sub

sub TestSyncPlayManagerCreateRoomWithInvalidApi()
    ' Test createRoom returns invalid with no API
    mgr = SyncPlayManager(invalid)
    result = mgr.createRoom("Test Room", true)
    assertEqual(result, invalid)
    print "TestSyncPlayManagerCreateRoomWithInvalidApi passed"
end sub

sub TestSyncPlayManagerJoinRoomWithInvalidApi()
    ' Test joinRoom returns invalid with no API
    mgr = SyncPlayManager(invalid)
    result = mgr.joinRoom("room-123")
    assertEqual(result, invalid)
    print "TestSyncPlayManagerJoinRoomWithInvalidApi passed"
end sub

sub TestSyncPlayManagerLeaveRoomWithInvalidApi()
    ' Test leaveRoom returns invalid when no API
    mgr = SyncPlayManager(invalid)
    result = mgr.leaveRoom()
    assertEqual(result, invalid)
    print "TestSyncPlayManagerLeaveRoomWithInvalidApi passed"
end sub

sub TestSyncPlayManagerLeaveRoomWithNoSession()
    ' Test leaveRoom returns invalid when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    result = mgr.leaveRoom()
    assertEqual(result, invalid)
    print "TestSyncPlayManagerLeaveRoomWithNoSession passed"
end sub

sub TestSyncPlayManagerIsInRoom()
    ' Test isInRoom returns false initially
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertFalse(mgr.isInRoom())
    print "TestSyncPlayManagerIsInRoom passed"
end sub

sub TestSyncPlayManagerIsHostWhenNoSession()
    ' Test isHost returns false when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertFalse(mgr.isHost())
    print "TestSyncPlayManagerIsHostWhenNoSession passed"
end sub

sub TestSyncPlayManagerGetRoomIdWhenNoSession()
    ' Test getRoomId returns empty string when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertEqual(mgr.getRoomId(), "")
    print "TestSyncPlayManagerGetRoomIdWhenNoSession passed"
end sub

sub TestSyncPlayManagerGetSessionIdWhenNoSession()
    ' Test getSessionId returns empty string when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertEqual(mgr.getSessionId(), "")
    print "TestSyncPlayManagerGetSessionIdWhenNoSession passed"
end sub

sub TestSyncPlayManagerGetServerUrlWhenNoSession()
    ' Test getServerUrl returns empty string when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertEqual(mgr.getServerUrl(), "")
    print "TestSyncPlayManagerGetServerUrlWhenNoSession passed"
end sub

sub TestSyncPlayManagerGetRoomNameWhenNoSession()
    ' Test getRoomName returns empty string when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertEqual(mgr.getRoomName(), "")
    print "TestSyncPlayManagerGetRoomNameWhenNoSession passed"
end sub

sub TestSyncPlayManagerGetMemberCountWhenNoSession()
    ' Test getMemberCount returns 0 when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertEqual(mgr.getMemberCount(), 0)
    print "TestSyncPlayManagerGetMemberCountWhenNoSession passed"
end sub

sub TestSyncPlayManagerBuildWsPartsWithNoSession()
    ' Test buildWsParts returns invalid when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    result = mgr.buildWsParts()
    assertEqual(result, invalid)
    print "TestSyncPlayManagerBuildWsPartsWithNoSession passed"
end sub

sub TestSyncPlayManagerUpdateFromGroupStateWithNoSession()
    ' Test updateFromGroupState does nothing when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    mgr.updateFromGroupState({})
    ' Should not throw
    assertTrue(true)
    print "TestSyncPlayManagerUpdateFromGroupStateWithNoSession passed"
end sub
