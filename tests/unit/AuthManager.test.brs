' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/AuthManager.test.brs

' ===========================================
' AuthManager Unit Tests
' ===========================================

sub TestAuthManagerInit()
    ' Test initialization with valid API
    api = ApiClient("http://localhost:8096")
    auth = AuthManager(api)
    assertTrue(auth <> invalid)
    assertFalse(auth.isAuthenticated)
    print "TestAuthManagerInit passed"
end sub

sub TestAuthManagerInitWithInvalid()
    ' Test initialization with invalid API
    auth = AuthManager(invalid)
    assertTrue(auth <> invalid)
    print "TestAuthManagerInitWithInvalid passed"
end sub

sub TestAuthManagerCheckAuthWithValidApi()
    ' Test checkAuth returns false when no token stored
    api = ApiClient("http://localhost:8096")
    auth = AuthManager(api)
    result = auth.checkAuth()
    assertFalse(result)
    print "TestAuthManagerCheckAuthWithValidApi passed"
end sub

sub TestAuthManagerCheckAuthWithInvalidApi()
    ' Test checkAuth handles invalid API gracefully
    auth = AuthManager(invalid)
    result = auth.checkAuth()
    assertFalse(result)
    print "TestAuthManagerCheckAuthWithInvalidApi passed"
end sub

sub TestAuthManagerLoginWithInvalidApi()
    ' Test login with invalid API
    auth = AuthManager(invalid)
    result = auth.login("user", "pass")
    assertFalse(result.success)
    assertEqual(result.error, "API not initialized")
    print "TestAuthManagerLoginWithInvalidApi passed"
end sub

sub TestAuthManagerLogout()
    ' Test logout clears state
    api = ApiClient("http://localhost:8096")
    auth = AuthManager(api)
    auth.isAuthenticated = true
    auth.currentUser = { name: "test" }
    auth.logout()
    assertFalse(auth.isAuthenticated)
    assertEqual(auth.currentUser, invalid)
    print "TestAuthManagerLogout passed"
end sub

sub TestAuthManagerLogoutWithApi()
    ' Test logout calls api logout
    api = ApiClient("http://localhost:8096")
    auth = AuthManager(api)
    auth.isAuthenticated = true
    auth.currentUser = { name: "test" }
    auth.logout()
    assertFalse(auth.isAuthenticated)
    print "TestAuthManagerLogoutWithApi passed"
end sub

sub TestAuthManagerGetCurrentUser()
    ' Test getCurrentUser returns current user
    api = ApiClient("http://localhost:8096")
    auth = AuthManager(api)
    assertEqual(auth.getCurrentUser(), invalid)
    auth.currentUser = { name: "test", id: "123" }
    assertEqual(auth.getCurrentUser().name, "test")
    print "TestAuthManagerGetCurrentUser passed"
end sub

sub TestAuthManagerGetCurrentUserAfterLogin()
    ' Test getCurrentUser after setting user
    api = ApiClient("http://localhost:8096")
    auth = AuthManager(api)
    auth.currentUser = { name: "TestUser" }
    user = auth.getCurrentUser()
    assertEqual(user.name, "TestUser")
    print "TestAuthManagerGetCurrentUserAfterLogin passed"
end sub
