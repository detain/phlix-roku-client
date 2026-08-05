' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/LibraryScene.brs

' copyright 2026 Joe Huss
'


sub Init()
    m.top.SetFocus(true)

    ' Create poster grid for items
    m.posterGrid = m.top.FindNode("itemsGrid")
    m.posterGrid.ObserveField("itemSelected", "OnItemSelected")
    m.posterGrid.ObserveField("itemFocused", "OnItemFocused")

    ' UI nodes
    m.backButton = m.top.FindNode("backButton")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.descriptionLabel = m.top.FindNode("descriptionLabel")
    m.loadingLabel = m.top.FindNode("loadingLabel")

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraryId = ""
    m.items = []

    ' Paging state for infinite scroll
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)
end sub

sub LoadLibrary(libraryId as String, libraryName as String)
    m.libraryId = libraryId

    ' Reset paging state for fresh library load
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.items = []
    m.contentNode = invalid

    if m.titleLabel <> invalid then
        m.titleLabel.text = libraryName
    end if

    RefreshItems()
end sub

sub RefreshItems()
    if m.libraryId = "" then return

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
        if m.offset > 0 then
            m.loadingLabel.text = "Loading more..."
        else
            m.loadingLabel.text = "Loading..."
        end if
    end if

    m.apiTask.request = {
        op: "getLibraryItems"
        libraryId: m.libraryId
        options: { topLevel: 1, offset: m.offset, limit: m.limit }
    }
    m.apiTask.control = "run"
end sub

' Load next page of items. Guard prevents concurrent page requests (R1.4 Task pattern).
sub LoadMoreItems()
    ' Guard: do not run two page requests at once
    if m.loadingPage then return
    if not m.hasMore then return

    m.loadingPage = true
    RefreshItems()
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getLibraryItems" then
        ' Hide loading indicator.
        if m.loadingLabel <> invalid then
            m.loadingLabel.visible = false
        end if

        if not resp.ok or resp.data = invalid or resp.data.items = invalid then
            m.loadingPage = false
            return
        end if

        newItems = resp.data.items
        itemCount = newItems.count()

        ' First page: create ContentNode; subsequent pages: append to existing
        if m.offset = 0 then
            m.items = newItems
            m.contentNode = CreateObject("roSGNode", "ContentNode")
            m.posterGrid.content = m.contentNode
        else
            m.items.append(newItems)
        end if

        ' Build ContentNode children for the new items
        for each item in newItems
            contentItem = m.contentNode.AddChild({
                Title: item.name
                Description: item.overview
                ShortDescriptionLine1: item.name
                Type: item.type
                id: item.id
            })

            if item.year <> invalid then
                contentItem.ShortDescriptionLine2 = str(item.year).trim()
            end if

            ' poster_url is an absolute URL (TMDB or local) or null.
            if item.poster_url <> invalid and item.poster_url <> "" then
                contentItem.HDPosterUrl = item.poster_url
            else
                contentItem.HDPosterUrl = "pkg:/images/placeholder.png"
            end if
        end for

        ' Update paging state
        m.offset = m.offset + itemCount
        m.hasMore = (itemCount = m.limit)
        m.loadingPage = false
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    ' F2: a series drills into its seasons (SeriesScene); every other top-level
    ' type (movie/audio/photo/...) opens the detail scene directly, which decides
    ' for itself whether the item is playable (see IsPlayableItem).
    if item.type = "series" then
        ShowSeries(item.id, item.name)
    else
        ShowItemDetail(item.id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()

    if index >= 0 and index < m.items.Count() then
        item = m.items[index]
        if m.descriptionLabel <> invalid then
            if item.overview <> invalid then
                m.descriptionLabel.text = item.overview
            else
                m.descriptionLabel.text = item.name
            end if
        end if

        ' Prefetch: trigger LoadMoreItems when focus approaches end of loaded set
        ' (within one screen = 15 items for a 5x3 grid)
        if m.items.Count() > 0 and index >= m.items.Count() - m.prefetchThreshold then
            LoadMoreItems()
        end if
    end if
end sub

sub ShowSeries(seriesId as String, seriesName as String)
    name = seriesName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "SeriesScene")
    m.top.Append(scene)
    scene.LoadSeries(seriesId, name)
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    m.top.Append(scene)
    scene.LoadItem(itemId)
end sub

sub OnBackPressed()
    m.top.requestClose = true
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end sub