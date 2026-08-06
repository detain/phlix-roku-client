'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/LibraryManager.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Library Manager for Roku
' Handles library browsing and item retrieval
' ===========================================

function LibraryManager(api as Object) as Object
    obj = {
        api: api
        libraries: []
        currentLibrary: invalid
        currentItems: []

        ' Load all libraries
        loadLibraries: function() as Object
            if m.api = invalid then
                return []
            end if

            m.libraries = m.api.getLibraries()
            return m.libraries
        end function

        ' Get items in a library
        getLibraryItems: function(libraryId as String, startIndex = 0 as Integer, limit = 50 as Integer) as Object
            if m.api = invalid then
                return []
            end if

            items = m.api.getLibraryItems(libraryId, {
                offset: startIndex
                limit: limit
            })

            if items <> invalid and items.items <> invalid then
                m.currentLibrary = libraryId
                m.currentItems = items.items
            end if

            return m.currentItems
        end function

        ' Get item details
        getItem: function(itemId as String) as Object
            if m.api = invalid then
                return invalid
            end if

            return m.api.getItem(itemId)
        end function

        ' Get playback info for item
        getPlaybackInfo: function(itemId as String) as Object
            if m.api = invalid then
                return invalid
            end if

            return m.api.getItemPlaybackInfo(itemId)
        end function

        ' Mark item as watched.
        ' R7.5: POST /users/me/history/{mediaItemId} to explicitly mark watched.
        markWatched: function(itemId as String) as Object
            if m.api = invalid then return invalid
            return m.api.markWatched(itemId)
        end function

        ' Mark item as unwatched.
        ' R7.5: DELETE /users/me/history/{mediaItemId} to explicitly mark unwatched.
        markUnwatched: function(itemId as String) as Object
            if m.api = invalid then return invalid
            return m.api.markUnwatched(itemId)
        end function

        ' Get current libraries
        getLibraries: function() as Object
            return m.libraries
        end function

        ' Get current items
        getCurrentItems: function() as Object
            return m.currentItems
        end function
    }

    return obj
end function