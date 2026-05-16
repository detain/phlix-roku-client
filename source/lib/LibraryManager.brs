' source/lib/LibraryManager.brs

' ===========================================
' Library Manager for Roku
' Handles library browsing and item retrieval
' ===========================================

function LibraryManager() as Object
    obj = {
        libraries: []
        currentLibrary: invalid
        currentItems: []

        ' Load all libraries
        loadLibraries: function() as Object
            if api = invalid then
                return []
            end if

            m.libraries = api.getLibraries()
            return m.libraries
        end function

        ' Get items in a library
        getLibraryItems: function(libraryId as String, startIndex = 0 as Integer, limit = 50 as Integer) as Object
            if api = invalid then
                return []
            end if

            items = api.getLibraryItems(libraryId, {
                startIndex: startIndex
                limit: limit
            })

            if items <> invalid and items.Items <> invalid then
                m.currentLibrary = libraryId
                m.currentItems = items.Items
            end if

            return m.currentItems
        end function

        ' Get item details
        getItem: function(itemId as String) as Object
            if api = invalid then
                return invalid
            end if

            return api.getItem(itemId)
        end function

        ' Get playback info for item
        getPlaybackInfo: function(itemId as String) as Object
            if api = invalid then
                return invalid
            end if

            return api.getItemPlaybackInfo(itemId)
        end function

        ' Mark item as watched
        markWatched: function(itemId as String) as Object
            if api <> invalid then
                return api.markWatched(itemId)
            end if
            return invalid
        end function

        ' Mark item as unwatched
        markUnwatched: function(itemId as String) as Object
            if api <> invalid then
                return api.markUnwatched(itemId)
            end if
            return invalid
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