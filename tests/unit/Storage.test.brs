' tests/unit/Storage.test.brs

' ===========================================
' Storage Unit Tests
' ===========================================

sub TestStorageInit()
    ' Test initialization
    storage = Storage()
    assertTrue(storage <> invalid)
    print "TestStorageInit passed"
end sub

sub TestStorageSetAndGet()
    ' Test set and get
    storage = Storage()
    storage.set("test_key", "test_value")
    value = storage.get("test_key")
    assertEqual(value, "test_value")
    storage.delete("test_key")
    print "TestStorageSetAndGet passed"
end sub

sub TestStorageDelete()
    ' Test delete
    storage = Storage()
    storage.set("delete_test", "value")
    storage.delete("delete_test")
    value = storage.get("delete_test")
    assertEqual(value, "")
    print "TestStorageDelete passed"
end sub

sub TestStorageClear()
    ' Test clear all
    storage = Storage()
    storage.set("key1", "value1")
    storage.set("key2", "value2")
    storage.clear()
    assertEqual(storage.get("key1"), "")
    assertEqual(storage.get("key2"), "")
    print "TestStorageClear passed"
end sub