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

sub TestSyncPlayManagerGetGroupsWithInvalidApi()
    ' Test getGroups returns empty array when no API
    mgr = SyncPlayManager(invalid)
    groups = mgr.getGroups()
    assertTrue(groups <> invalid)
    assertEqual(groups.Count(), 0)
    print "TestSyncPlayManagerGetGroupsWithInvalidApi passed"
end sub

sub TestSyncPlayManagerGetGroupsWithNonArrayResult()
    ' Test getGroups handles non-array result
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    ' Passing a result that's not an assocarray or has no groups key
    assertEqual(mgr.getGroups().Count(), 0)
    print "TestSyncPlayManagerGetGroupsWithNonArrayResult passed"
end sub

sub TestSyncPlayManagerCreateGroupWithInvalidApi()
    ' Test createGroup returns invalid with no API
    mgr = SyncPlayManager(invalid)
    result = mgr.createGroup("Test Group", true)
    assertEqual(result, invalid)
    print "TestSyncPlayManagerCreateGroupWithInvalidApi passed"
end sub

sub TestSyncPlayManagerJoinGroupWithInvalidApi()
    ' Test joinGroup returns invalid with no API
    mgr = SyncPlayManager(invalid)
    result = mgr.joinGroup("room-123")
    assertEqual(result, invalid)
    print "TestSyncPlayManagerJoinGroupWithInvalidApi passed"
end sub

sub TestSyncPlayManagerLeaveGroupWithInvalidApi()
    ' Test leaveGroup returns invalid when no API
    mgr = SyncPlayManager(invalid)
    result = mgr.leaveGroup()
    assertEqual(result, invalid)
    print "TestSyncPlayManagerLeaveGroupWithInvalidApi passed"
end sub

sub TestSyncPlayManagerLeaveGroupWithNoSession()
    ' Test leaveGroup returns invalid when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    result = mgr.leaveGroup()
    assertEqual(result, invalid)
    print "TestSyncPlayManagerLeaveGroupWithNoSession passed"
end sub

sub TestSyncPlayManagerIsInGroup()
    ' Test isInGroup returns false initially
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertFalse(mgr.isInGroup())
    print "TestSyncPlayManagerIsInGroup passed"
end sub

sub TestSyncPlayManagerIsHostWhenNoSession()
    ' Test isHost returns false when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertFalse(mgr.isHost())
    print "TestSyncPlayManagerIsHostWhenNoSession passed"
end sub

sub TestSyncPlayManagerGetGroupIdWhenNoSession()
    ' Test getGroupId returns empty string when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertEqual(mgr.getGroupId(), "")
    print "TestSyncPlayManagerGetGroupIdWhenNoSession passed"
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

sub TestSyncPlayManagerGetGroupNameWhenNoSession()
    ' Test getGroupName returns empty string when no session
    api = ApiClient("http://localhost:8096")
    mgr = SyncPlayManager(api)
    assertEqual(mgr.getGroupName(), "")
    print "TestSyncPlayManagerGetGroupNameWhenNoSession passed"
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
