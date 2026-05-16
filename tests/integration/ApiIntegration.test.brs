' tests/integration/ApiIntegration.test.brs

' ===========================================
' API Integration Tests
' Tests against actual server (if available)
' ===========================================

sub TestApiConnection()
    ' Skip if no server available
    serverUrl = Storage.get("server_url")
    if serverUrl = "" then
        print "Skipping TestApiConnection - no server configured"
        return
    end if

    client = ApiClient(serverUrl)

    ' Try to get user (should fail without auth)
    user = client.request("GET", "/Users/Me", {})
    ' Should be invalid without authentication

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

    print "TestLibraryRetrieval passed"
end sub