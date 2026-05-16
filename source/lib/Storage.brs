' source/lib/Storage.brs

' ===========================================
' Persistent Storage for Roku
' Uses roRegistry for key-value storage
' ===========================================

function Storage() as Object
    obj = {
        registry: CreateObject("roRegistrySection", "phlex")

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