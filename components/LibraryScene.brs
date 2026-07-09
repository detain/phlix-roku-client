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

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraryId = ""
    m.items = []
end sub

sub LoadLibrary(libraryId as String, libraryName as String)
    m.libraryId = libraryId

    if m.titleLabel <> invalid then
        m.titleLabel.text = libraryName
    end if

    RefreshItems()
end sub

sub RefreshItems()
    if m.libraryId = "" then return

    m.apiTask.request = {
        op: "getLibraryItems"
        libraryId: m.libraryId
        options: { topLevel: 1 }
    }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getLibraryItems" then
        if not resp.ok or resp.data = invalid or resp.data.items = invalid then return

        m.items = resp.data.items

        content = CreateObject("roSGNode", "ContentNode")
        for each item in m.items
            contentItem = content.AddChild({
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

        m.posterGrid.content = content
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    ' F2: a series drills into its seasons (SeriesScene); every other top-level
    ' type (movie/audio/image) opens the detail scene directly.
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
    m.top.Close()
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end sub