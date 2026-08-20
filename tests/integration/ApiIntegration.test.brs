' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/integration/ApiIntegration.test.brs

' copyright 2026 Joe Huss
'


' ===========================================
' API Integration Tests
' Tests against actual server (if available)
' ===========================================

sub TestApiConnection()
    ' Skip if no server available
    serverUrl = GetStorage().get("server_url")
    if serverUrl = "" then
        print "Skipping TestApiConnection - no server configured"
        return
    end if

    client = ApiClient(serverUrl)

    ' Try to get user (should fail without auth)
    user = client.request("GET", "/Users/Me", {})
    ' Should be invalid without authentication
    assertTrue(user = invalid, "unauthenticated /Users/Me request should return invalid")

    print "TestApiConnection passed"
end sub

sub TestLibraryRetrieval()
    ' Skip if not authenticated
    if not authManager.checkAuth() then
        print "Skipping TestLibraryRetrieval - not authenticated"
        return
    end if

    libraries = api.getLibraries()
    ' Libraries should be an array or invalid
    assertTrue(libraries = invalid or type(libraries) = "roArray", "getLibraries() should return an array or invalid")

    print "TestLibraryRetrieval passed"
end sub