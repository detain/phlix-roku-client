'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/Storage.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Persistent Storage for Roku
' Uses roRegistry for key-value storage
' ===========================================

' Returns a Storage instance. Components should cache this in m.storage
' to avoid repeated instantiation.
' @return Object - storage object with get/set/delete/clear methods
function GetStorage() as Object
    return Storage()
end function

' Factory function - creates a new storage instance with roRegistrySection.
' @return Object - storage object with get/set/delete/clear methods
function Storage() as Object
    obj = {
        registry: CreateObject("roRegistrySection", "phlix")

        get: function(key as String) as String
            return m.registry.Read(key)
        end function

        set: function(key as String, value as String)
            m.registry.Write(key, value)
            m.registry.Flush()
        end function

        delete: function(key as String)
            m.registry.Delete(key)
            m.registry.Flush()
        end function

        clear: function()
            m.registry.DeleteAll()
            m.registry.Flush()
        end function
    }

    return obj
end function