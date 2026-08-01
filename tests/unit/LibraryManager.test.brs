' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/LibraryManager.test.brs

' ===========================================
' LibraryManager Unit Tests
' ===========================================

sub TestLibraryManagerInit()
    ' Test initialization
    api = ApiClient("http://localhost:8096")
    mgr = LibraryManager(api)
    assertTrue(mgr <> invalid)
    assertTrue(mgr.libraries <> invalid)
    assertEqual(mgr.libraries.Count(), 0)
    assertEqual(mgr.currentLibrary, invalid)
    assertTrue(mgr.currentItems <> invalid)
    print "TestLibraryManagerInit passed"
end sub

sub TestLibraryManagerLoadLibrariesWithInvalidApi()
    ' Test loadLibraries returns empty when no API
    mgr = LibraryManager(invalid)
    result = mgr.loadLibraries()
    assertTrue(result <> invalid)
    assertEqual(result.Count(), 0)
    print "TestLibraryManagerLoadLibrariesWithInvalidApi passed"
end sub

sub TestLibraryManagerGetLibraryItemsWithInvalidApi()
    ' Test getLibraryItems returns empty when no API
    mgr = LibraryManager(invalid)
    result = mgr.getLibraryItems("lib-123")
    assertTrue(result <> invalid)
    assertEqual(result.Count(), 0)
    print "TestLibraryManagerGetLibraryItemsWithInvalidApi passed"
end sub

sub TestLibraryManagerGetItemWithInvalidApi()
    ' Test getItem returns invalid when no API
    mgr = LibraryManager(invalid)
    result = mgr.getItem("item-123")
    assertEqual(result, invalid)
    print "TestLibraryManagerGetItemWithInvalidApi passed"
end sub

sub TestLibraryManagerGetPlaybackInfoWithInvalidApi()
    ' Test getPlaybackInfo returns invalid when no API
    mgr = LibraryManager(invalid)
    result = mgr.getPlaybackInfo("item-123")
    assertEqual(result, invalid)
    print "TestLibraryManagerGetPlaybackInfoWithInvalidApi passed"
end sub

sub TestLibraryManagerMarkWatched()
    ' Test markWatched is stubbed to return invalid
    api = ApiClient("http://localhost:8096")
    mgr = LibraryManager(api)
    result = mgr.markWatched("item-123")
    assertEqual(result, invalid)
    print "TestLibraryManagerMarkWatched passed"
end sub

sub TestLibraryManagerMarkUnwatched()
    ' Test markUnwatched is stubbed to return invalid
    api = ApiClient("http://localhost:8096")
    mgr = LibraryManager(api)
    result = mgr.markUnwatched("item-123")
    assertEqual(result, invalid)
    print "TestLibraryManagerMarkUnwatched passed"
end sub

sub TestLibraryManagerGetLibraries()
    ' Test getLibraries returns the libraries array
    api = ApiClient("http://localhost:8096")
    mgr = LibraryManager(api)
    libs = mgr.getLibraries()
    assertTrue(libs <> invalid)
    assertEqual(libs.Count(), 0)
    print "TestLibraryManagerGetLibraries passed"
end sub

sub TestLibraryManagerGetCurrentItems()
    ' Test getCurrentItems returns current items array
    api = ApiClient("http://localhost:8096")
    mgr = LibraryManager(api)
    items = mgr.getCurrentItems()
    assertTrue(items <> invalid)
    assertEqual(items.Count(), 0)
    print "TestLibraryManagerGetCurrentItems passed"
end sub
