' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/SessionManager.test.brs

' ===========================================
' SessionManager Unit Tests
' ===========================================

sub TestSessionManagerInit()
    ' Test initialization
    api = ApiClient("http://localhost:8096")
    mgr = SessionManager(api)
    assertTrue(mgr <> invalid)
    assertEqual(mgr.activeSession, invalid)
    assertTrue(mgr.sessions <> invalid)
    assertEqual(mgr.sessions.Count(), 0)
    print "TestSessionManagerInit passed"
end sub

sub TestSessionManagerCreateSessionWithInvalidApi()
    ' Test createSession returns invalid with no API
    mgr = SessionManager(invalid)
    result = mgr.createSession()
    assertEqual(result, invalid)
    print "TestSessionManagerCreateSessionWithInvalidApi passed"
end sub

sub TestSessionManagerCreateSessionWithNoUser()
    ' Test createSession returns invalid when no user
    api = ApiClient("http://localhost:8096")
    mgr = SessionManager(api)
    result = mgr.createSession()
    assertEqual(result, invalid)
    print "TestSessionManagerCreateSessionWithNoUser passed"
end sub

sub TestSessionManagerGetSessions()
    ' Test getSessions returns the sessions array
    api = ApiClient("http://localhost:8096")
    mgr = SessionManager(api)
    sessions = mgr.getSessions()
    assertTrue(sessions <> invalid)
    assertEqual(sessions.Count(), 0)
    print "TestSessionManagerGetSessions passed"
end sub

sub TestSessionManagerEndSessionWithNoActiveSession()
    ' Test endSession does nothing when no active session
    api = ApiClient("http://localhost:8096")
    mgr = SessionManager(api)
    mgr.endSession()
    assertEqual(mgr.activeSession, invalid)
    print "TestSessionManagerEndSessionWithNoActiveSession passed"
end sub

sub TestSessionManagerEndSessionWithInvalidApi()
    ' Test endSession handles invalid API
    mgr = SessionManager(invalid)
    mgr.endSession()
    print "TestSessionManagerEndSessionWithInvalidApi passed"
end sub

sub TestSessionManagerGetActiveSession()
    ' Test getActiveSession returns current session
    api = ApiClient("http://localhost:8096")
    mgr = SessionManager(api)
    assertEqual(mgr.getActiveSession(), invalid)
    mgr.activeSession = { sessionId: "test-123" }
    assertTrue(mgr.getActiveSession() <> invalid)
    print "TestSessionManagerGetActiveSession passed"
end sub

sub TestSessionManagerActiveSessionTracking()
    ' Test activeSession can be tracked
    api = ApiClient("http://localhost:8096")
    mgr = SessionManager(api)
    mgr.activeSession = { sessionId: "abc-123" }
    assertEqual(mgr.getActiveSession().sessionId, "abc-123")
    print "TestSessionManagerActiveSessionTracking passed"
end sub
