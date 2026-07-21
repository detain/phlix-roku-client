'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/CollectionScene.brs

' copyright 2026 Joe Huss
'

'
' A single collection's items as a one-shot PosterGrid. Mirrors LibraryScene's
' grid build + LoadX interface fn, and FavoritesScene's type-routed selection +
' Teardown. CollectionsScene creates + appends this scene and calls the
' LoadCollection interface fn, so it HAS an <interface><function
' name="LoadCollection"/>.
'
' CARDINAL LANDMINE: GET /collections/{id} returns items as RAW DB rows (NOT
' MediaItemShaper-shaped): id/name/type are top-level but poster_url/overview/year
' live under metadata.*. Each row is flattened via NormalizeCollectionItem before
' it feeds the grid. `type` stays top-level so routing works:
'   series  -> SeriesScene (LoadSeries)
'   season  -> SeasonScene (LoadSeason)
'   else    -> DetailScene (LoadItem)   (every other media_items.type:
'                                        movie/episode/video/audio/track/
'                                        music/album/artist/book/photo/
'                                        audiobook -- note `photo`, there
'                                        is no `image` member)

sub Init()
    m.top.SetFocus(true)

    ' Items grid.
    m.itemsGrid = m.top.FindNode("itemsGrid")
    if m.itemsGrid <> invalid then
        m.itemsGrid.ObserveField("itemSelected", "OnItemSelected")
        m.itemsGrid.ObserveField("itemFocused", "OnItemFocused")
    end if

    ' UI nodes.
    m.backButton = m.top.FindNode("backButton")
    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if
    m.titleLabel = m.top.FindNode("titleLabel")
    m.descriptionLabel = m.top.FindNode("descriptionLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.collectionId = ""
    m.items = []
end sub

' Interface fn: load + render the given collection's items. CollectionsScene
' calls this right after Append. collectionName fills the header title.
sub LoadCollection(collectionId as String, collectionName as String)
    m.collectionId = collectionId

    if m.titleLabel <> invalid then
        name = collectionName
        if name = invalid then name = ""
        m.titleLabel.text = name
    end if

    if m.collectionId = "" then return

    m.apiTask.request = { op: "getCollection", collectionId: m.collectionId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getCollection" then
        if not resp.ok or resp.data = invalid or resp.data.items = invalid or type(resp.data.items) <> "roArray" then
            m.items = []
            if m.itemsGrid <> invalid then
                m.itemsGrid.content = CreateObject("roSGNode", "ContentNode")
            end if
            if m.descriptionLabel <> invalid then
                m.descriptionLabel.text = ""
            end if
            return
        end if

        ' Normalize each RAW row before it feeds the grid; skip rows with no id.
        m.items = []
        for each raw in resp.data.items
            norm = NormalizeCollectionItem(raw)
            if norm.id <> "" then m.items.Push(norm)
        end for

        content = CreateObject("roSGNode", "ContentNode")
        for each item in m.items
            contentItem = content.AddChild({
                Title: item.name
                ShortDescriptionLine1: item.name
                Type: item.type
                id: item.id
            })

            if item.overview <> "" then
                contentItem.Description = item.overview
            end if

            if item.year <> invalid then
                yearStr = str(Int(item.year)).trim()
                if yearStr <> "0" then contentItem.ShortDescriptionLine2 = yearStr
            end if

            ' poster_url is an absolute URL (TMDB or local) or empty.
            if item.poster_url <> "" then
                contentItem.HDPosterUrl = item.poster_url
            else
                contentItem.HDPosterUrl = "pkg:/images/placeholder.png"
            end if
        end for

        if m.itemsGrid <> invalid then m.itemsGrid.content = content

        if m.descriptionLabel <> invalid and m.items.Count() = 0 then
            m.descriptionLabel.text = "This collection is empty"
        end if
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    ' Items can be any type; route every type sensibly (exactly like Favorites).
    if item.type = "series" then
        ShowSeries(item.id, item.name)
    else if item.type = "season" then
        ShowSeason(item.id, item.name)
    else
        ShowItemDetail(item.id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    if m.descriptionLabel <> invalid then
        if item.overview <> "" then
            m.descriptionLabel.text = item.overview
        else
            m.descriptionLabel.text = item.name
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

sub ShowSeason(seasonId as String, seasonName as String)
    name = seasonName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "SeasonScene")
    m.top.Append(scene)
    scene.LoadSeason(seasonId, name)
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    m.top.Append(scene)
    scene.LoadItem(itemId)
end sub

sub OnBackPressed()
    m.top.Close()
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.itemsGrid <> invalid then
        m.itemsGrid.UnObserveField("itemSelected")
        m.itemsGrid.UnObserveField("itemFocused")
    end if
    if m.backButton <> invalid then
        m.backButton.UnObserveField("buttonSelected")
    end if
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function