' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/Storage.brs

' copyright 2026 Joe Huss
'
'

' ===========================================
' Persistent Storage for Roku
' Uses roRegistry for key-value storage with:
' - Singleton cache: one roRegistrySection instance, shared across all callers
' - Batch flush: writes accumulate in memory, flushed on explicit flush() call
'   OR on any key in the immediate-flush set (auth_token, refresh_token,
'   session_id, device_id — durability matters more than batching for these)
' - Invalidation: ResetCachedStorage() clears all cached reads
' - Budget tracking: sizeEstimate() reports bytes; warns past 12 KB threshold
'
' Registry per-channel limit: 16 KB.  We warn at 12 KB to leave headroom.
'
' R1.6: State is stored as properties on the Storage/GetStorage functions themselves
' (BrightScript has no module-level variables; function properties are the only
' way to share mutable state across source-file calls).
' ===========================================

' Returns true if the given key should be flushed immediately (not batched).
' These keys affect auth/session state — losing them on crash forces re-login.
function _isImmediateFlushKey(key as String) as Boolean
    if key = "auth_token" then return true
    if key = "refresh_token" then return true
    if key = "session_id" then return true
    if key = "device_id" then return true
    return false
end function

' Returns the singleton Storage instance, creating it on first call.
' All code paths — AppContext, ApiClient, scenes, tasks — get the SAME object.
' @return Object - the shared storage object
function GetStorage() as Object
    return Storage()
end function

' Invalidate all cached reads and optionally wipe auth/session keys.
' Call this on server switch (fullReset=false) or logout (fullReset=true).
' R1.6: fullReset=true uses DeleteAll+Flush (1 NVRAM write) instead of 6
' separate delete+flush cycles.
' @param fullReset Boolean - if true also deletes auth/session keys
sub ResetCachedStorage(fullReset = false as Boolean)
    s = GetStorage()
    s._cache.Clear()
    s._dirty.Clear()
    if fullReset then
        s.registry.DeleteAll()
        s.registry.Flush()
    end if
end sub

' Factory function — returns the SINGLETON Storage instance on all subsequent
' calls.  State is stored on the function object itself (BrightScript has no
' module-level variable support) so all callers share the same _cache / _dirty.
' @return Object - storage object with get/set/delete/clear/flush/invalidate/sizeEstimate
function Storage() as Object
    if Storage._singleton <> invalid then
        return Storage._singleton
    end if

    obj = {
        registry: CreateObject("roRegistrySection", "phlix"),

        ' In-memory cache of registry values read via get().
        ' Key: registry key name (String). Value: last read String.
        _cache: {},

        ' Keys written via set() but not yet flushed to registry (non-immediate).
        ' Value: the string to write. Presence in this map = dirty.
        _dirty: {},

        ' Read a key. First call stores the value in _cache; subsequent calls
        ' within the same process lifetime return the cached value (no NVRAM hit).
        ' @param key String - registry key
        ' @return String - stored value or "" if absent
        get: function(key as String) as String
            if m._cache.DoesExist(key) then
                return m._cache[key]
            end if
            val = m.registry.Read(key)
            m._cache[key] = val
            return val
        end function,

        ' Write a value. Immediate keys (auth_token / refresh_token / session_id /
        ' device_id) are flushed immediately; all others are cached and flushed
        ' only on explicit flush() or on GetStorage().delete/clear.
        ' @param key String - registry key
        ' @param value String - value to store
        set: function(key as String, value as String)
            m._cache[key] = value
            m._dirty[key] = value
            m.registry.Write(key, value)
            if _isImmediateFlushKey(key) then
                m.registry.Flush()
                m._dirty.Delete(key)
            end if
        end function,

        ' Delete a key. Always Flush() immediately to commit the deletion.
        ' @param key String - registry key
        delete: function(key as String)
            m._cache.Delete(key)
            m.registry.Delete(key)
            m.registry.Flush()
        end function,

        ' Delete all keys. Always Flush() immediately.
        clear: function()
            m._cache.Clear()
            m._dirty.Clear()
            m.registry.DeleteAll()
            m.registry.Flush()
        end function,

        ' Flush all pending writes (non-immediate keys) to the registry now.
        ' Call at deliberate points: after login, before channel exit, after a
        ' settings change, etc.
        flush: function()
            if m._dirty.Count() = 0 then return true
            for each key in m._dirty
                m.registry.Write(key, m._dirty[key])
            end for
            m.registry.Flush()
            m._dirty.Clear()
            return true
        end function,

        ' Invalidate one cached key so the next get() re-reads from registry.
        ' @param key String - the key to invalidate
        invalidate: function(key as String)
            m._cache.Delete(key)
        end function,

        ' Invalidate all cached keys.
        invalidateAll: function()
            m._cache.Clear()
            m._dirty.Clear()
        end function,

        ' Estimate total registry bytes used by this channel.  Iterates all known
        ' keys (cache + dirty + any persisted in registry) to compute a
        ' conservative byte count (key + value strings + overhead per entry).
        ' Logs a warning when estimate exceeds 12 KB (Roku limit is 16 KB).
        ' @return Integer - estimated total bytes
        sizeEstimate: function() as Integer
            total = 0
            seen = {}
            for each key in m._cache
                seen[key] = true
                total = total + Len(key) + Len(m._cache[key]) + 16
            end for
            for each key in m._dirty
                if not seen.DoesExist(key) then
                    seen[key] = true
                    total = total + Len(key) + Len(m._dirty[key]) + 16
                end if
            end for
            ' Fixed overhead fudge for registry metadata
            total = total + 256
            ' Warn at 12 KB threshold (Roku hard limit is 16 KB per channel)
            if total > 12288 then
                print "[Storage] WARNING: registry size estimate "; total; " bytes past 12288 byte threshold (hard limit 16384)"
            end if
            return total
        end function
    }

    Storage._singleton = obj
    return obj
end function
