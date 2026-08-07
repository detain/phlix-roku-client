' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/SeriesScene.brs

' copyright 2026 Joe Huss
'

'
' Seasons (or, for flat shows, episodes) grid for a single series. Mirrors
' LibraryScene's PosterGrid + ApiTask pattern. Fires getLibraryItems with
' options.parentId=<seriesId> (direct-children mode, omits topLevel), re-sorts the
' children client-side (the API returns ORDER BY name), and routes:
'   season  -> SeasonScene (episodes)
'   episode -> DetailScene (flat-show case; episode plays via the existing detail)

sub Init()
    m.top.SetFocus(true)

    ' Poster grid for the children.
    m.posterGrid = m.top.FindNode("itemsGrid")
    m.posterGrid.ObserveField("itemSelected", "OnItemSelected")
    m.posterGrid.ObserveField("itemFocused", "OnItemFocused")

    ' UI nodes.
    m.backButton = m.top.FindNode("backButton")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.descriptionLabel = m.top.FindNode("descriptionLabel")
    m.loadingLabel = m.top.FindNode("loadingLabel")

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    ' Route all data access through the EpisodeListTask node (off the render thread).
    ' This handles both the API call AND ContentNode building off the render thread.
    m.listTask = CreateObject("roSGNode", "EpisodeListTask")
    m.listTask.ObserveField("content", "OnListContent")

    m.seriesId = ""
    m.children = []

    ' Paging state for infinite scroll
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")
end sub

' Cross-component callable (declared in the <interface>). Loads the children of
' the given series.
sub LoadSeries(seriesId as String, seriesName as String)
    m.seriesId = seriesId

    if m.titleLabel <> invalid then
        m.titleLabel.text = seriesName
    end if

    if m.seriesId = "" then return

    ' Reset paging state for fresh series load
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.children = []
    m.contentNode = invalid

    RefreshItems()
end sub

' Show loading indicator and run the EpisodeListTask with current offset.
sub RefreshItems()
    if m.seriesId = "" then return

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
        if m.offset > 0 then
            m.loadingLabel.text = "Loading more..."
        else
            m.loadingLabel.text = "Loading..."
        end if
    end if

    ' EpisodeListTask handles fetch + sort + ContentNode build off the render thread.
    m.listTask.libraryId = m.seriesId
    m.listTask.parentId = m.seriesId
    m.listTask.itemType = "series"
    m.listTask.offset = m.offset
    m.listTask.limit = m.limit
    m.listTask.control = "run"
end sub

' Load next page of items. Guard prevents concurrent page requests.
sub LoadMoreItems()
    ' Guard: do not run two page requests at once
    if m.loadingPage then return
    if not m.hasMore then return

    m.loadingPage = true
    RefreshItems()
end sub

' Handle EpisodeListTask response — content + items are both ready when
' m.top.content is set (task thread sets content, items, ok in sequence).
sub OnListContent(event as Object)
    content = event.getData()
    if content = invalid then return

    ' Hide loading indicator.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = false
    end if

    ' m.listTask.items holds the raw sorted items for navigation (id, name, type).
    ' m.listTask.content holds the ready-to-assign ContentNode for display.
    if m.listTask.ok then
        newItems = m.listTask.items
        newContent = m.listTask.content
        itemCount = newItems.Count()

        ' First page: create ContentNode; subsequent pages: append to existing
        if m.offset = 0 then
            m.children = newItems
            m.contentNode = newContent
            m.posterGrid.content = m.contentNode
        else
            m.children.Append(newItems)
            ' Append children from newContent to existing ContentNode
            if newContent <> invalid and m.contentNode <> invalid then
                for each child in newContent.GetChildren(-1, 0)
                    m.contentNode.AppendChild(child)
                end for
            end if
        end if

        ' Update paging state
        m.offset = m.offset + itemCount
        m.hasMore = (itemCount = m.limit)
        m.loadingPage = false
    else
        m.loadingPage = false
        m.hasMore = false
    end if
end sub

' Caption per child type: seasons show their name (fallback "Season N"); the
' flat-show episode case shows the episode caption.
function BuildCaption(item as Object) as String
    if item = invalid then return ""

    if item.type = "season" then
        if item.DoesExist("name") and item.name <> invalid and item.name <> "" then
            return item.name
        else if item.DoesExist("season_number") and item.season_number <> invalid then
            return "Season " + str(Int(item.season_number)).trim()
        end if
        return ""
    end if

    ' Episode (flat show) or any other type: build the episode caption.
    return EpisodeCaption(item)
end function

sub OnItemSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.children.Count() then return

    child = m.children[index]
    if child = invalid then return

    if child.type = "season" then
        ShowSeason(child.id, child.name)
    else
        ' Flat show: the child is an episode -> existing detail/play path.
        ShowItemDetail(child.id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()

    if index >= 0 and index < m.children.Count() then
        item = m.children[index]
        if item <> invalid and m.descriptionLabel <> invalid then
            if item.overview <> invalid then
                m.descriptionLabel.text = item.overview
            else
                m.descriptionLabel.text = BuildCaption(item)
            end if
        end if
    end if

    ' Prefetch: trigger LoadMoreItems when focus approaches end of loaded set
    ' (within one screen = 15 items for a 5x3 grid)
    if m.children.Count() > 0 and index >= m.children.Count() - m.prefetchThreshold then
        LoadMoreItems()
    end if
end sub

sub ShowSeason(seasonId as String, seasonName as String)
    name = seasonName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "SeasonScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadSeason(seasonId, name)
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadItem(itemId)
end sub

' Bubble requestClose from a child scene up to the parent.
sub OnChildRequestClose()
    m.top.requestClose = true
end sub

sub OnBackPressed()
    Teardown()
    m.top.requestClose = true
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.posterGrid <> invalid then
        m.posterGrid.UnObserveField("itemSelected")
        m.posterGrid.UnObserveField("itemFocused")
    end if
    if m.backButton <> invalid then
        m.backButton.UnObserveField("buttonSelected")
    end if
    if m.listTask <> invalid then
        m.listTask.UnObserveField("content")
    end if
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end function