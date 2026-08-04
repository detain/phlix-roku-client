' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/EpisodeListTask.brs

' ===========================================
' EpisodeListTask — loads episode/season list data off the render thread.
'
' The problem: SeriesScene and SeasonScene use ApiTask for the HTTP call, but
' OnApiResponse processes the result (sort + ContentNode build) on the render
' thread. With large lists this causes visible UI blocking.
'
' The fix: this dedicated Task fetches AND builds the ContentNode on its own
' thread, then ships a ready-to-assign ContentNode and raw items array to the
' scene. The scene uses the raw items for navigation (id/name/type) and the
' ContentNode for display.
'
' Thread rule: this function runs on the task thread; it may ONLY read its own
' m.top.* fields and write m.top.content/items/ok. It must NOT touch UI/parent
' nodes. Only assocarray/string/number/node data crosses the thread boundary.
' ===========================================

sub Init()
    m.top.functionName = "LoadList"
end sub

sub LoadList()
    ' R1.6: Invalidate the Storage read cache so we re-read the freshest values
    ' from the registry.
    ResetCachedStorage(false)

    libraryId = m.top.libraryId
    parentId = m.top.parentId
    itemType = m.top.itemType

    if libraryId = invalid or parentId = invalid or libraryId = "" or parentId = "" then
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
        return
    end if

    api = GetApiClient()
    if api = invalid then
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
        return
    end if

    ' Fetch children via getLibraryItems (direct-children mode via parentId).
    data = api.getLibraryItems(libraryId, { parentId: parentId, limit: 200 })
    if data = invalid or data.items = invalid then
        m.top.content = invalid
        m.top.items = []
        m.top.ok = false
        return
    end if

    ' Sort by season then episode order (same logic as SeriesScene/SeasonScene).
    sortedItems = SortByEpisodeOrder(data.items)

    ' Build the ContentNode tree off the render thread.
    content = CreateObject("roSGNode", "ContentNode")

    for each item in sortedItems
        if itemType = "season" then
            caption = EpisodeCaption(item)
        else
            ' For series, show season name or "Season N" for seasons,
            ' episode caption for episodes (flat-show case).
            if item.type = "season" then
                if item.DoesExist("name") and item.name <> invalid and item.name <> "" then
                    caption = item.name
                else if item.DoesExist("season_number") and item.season_number <> invalid then
                    caption = "Season " + str(Int(item.season_number)).trim()
                else
                    caption = ""
                end if
            else
                caption = EpisodeCaption(item)
            end if
        end if

        contentItem = content.AddChild({
            Title: caption
            ShortDescriptionLine1: caption
            Type: item.type
            id: item.id
        })

        if item.overview <> invalid then
            contentItem.Description = item.overview
        end if

        ' poster_url is an absolute URL (TMDB or local) or null.
        if item.poster_url <> invalid and item.poster_url <> "" then
            contentItem.HDPosterUrl = item.poster_url
        else
            contentItem.HDPosterUrl = "pkg:/images/placeholder.png"
        end if
    end for

    m.top.content = content
    m.top.items = sortedItems
    m.top.ok = true
end sub
