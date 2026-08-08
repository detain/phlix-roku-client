'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/FavoritesScene.brs

' copyright 2026 Joe Huss
'

'
' Favorites browse screen: a one-shot PosterGrid of the user's favorited items.
' Mirrors SearchScene's results-grid + ApiTask + type-routed selection idiom,
' minus the keyboard/debounce - the load fires once on Init via the `getFavorites`
' op (ApiClient.getFavorites -> GET /users/me/favorites). Favorites are normal
' canonical media items, so selecting one routes exactly like LibraryScene/
' SearchScene:
'   series  -> SeriesScene (LoadSeries)
'   season  -> SeasonScene (LoadSeason)
'   else    -> DetailScene (LoadItem)   (every other media_items.type:
'                                        movie/episode/video/audio/track/
'                                        music/album/artist/book/photo/
'                                        audiobook -- note `photo`, there
'                                        is no `image` member)

sub Init()
    m.top.SetFocus(true)

    ' Favorites grid.
    m.favoritesGrid = m.top.FindNode("favoritesGrid")
    if m.favoritesGrid <> invalid then
        m.favoritesGrid.ObserveField("itemSelected", "OnResultSelected")
        m.favoritesGrid.ObserveField("itemFocused", "OnResultFocused")
        m.favoritesGrid.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' R5.4: Observe visibility to refetch when returning after a favorite change
    ' in a child scene (e.g., DetailScene).
    m.top.ObserveField("visible", "OnVisibilityChanged")

    m.results = []

    ' Paging state for infinite scroll (R5.4)
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)

    if m.statusLabel <> invalid then
        m.statusLabel.text = "Loading…"
    end if

    ' One-shot load on Init (no keyboard, no debounce).
    m.apiTask.request = {
        op: "getFavorites"
        options: { limit: m.limit, offset: m.offset }
    }
    m.apiTask.control = "run"
end sub

' Load next page of items. Guard prevents concurrent page requests.
sub LoadMoreItems()
    ' Guard: do not run two page requests at once
    if m.loadingPage then return
    if not m.hasMore then return

    m.loadingPage = true

    if m.statusLabel <> invalid then
        m.statusLabel.text = "Loading…"
    end if

    m.apiTask.request = {
        op: "getFavorites"
        options: { limit: m.limit, offset: m.offset }
    }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getFavorites" then
        ' Hide loading indicator
        if m.statusLabel <> invalid and m.loadingPage then
            m.statusLabel.text = ""
        end if

        if not resp.ok or resp.data = invalid or resp.data.items = invalid then
            m.results = []
            if m.favoritesGrid <> invalid then
                m.favoritesGrid.content = CreateObject("roSGNode", "ContentNode")
            end if
            if m.statusLabel <> invalid and not m.loadingPage then
                m.statusLabel.text = "No favorites yet"
            end if
            m.loadingPage = false
            m.hasMore = false
            return
        end if

        newItems = resp.data.items
        itemCount = newItems.count()

        ' First page: create ContentNode; subsequent pages: append to existing
        if m.offset = 0 then
            m.results = newItems
            m.contentNode = CreateObject("roSGNode", "ContentNode")
            m.favoritesGrid.content = m.contentNode
        else
            m.results.append(newItems)
        end if

        ' Build ContentNode children for the new items
        for each item in newItems
            caption = BuildResultCaption(item)

            contentItem = m.contentNode.AddChild({
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

        ' Update paging state
        m.offset = m.offset + itemCount
        m.hasMore = (itemCount = m.limit)
        m.loadingPage = false

        if m.statusLabel <> invalid then
            if m.results.Count() = 0 then
                m.statusLabel.text = "No favorites yet"
            else
                m.statusLabel.text = ""
            end if
        end if
    end if
end sub

' Caption per result type: episodes use the episode caption; everything else
' shows its name.
function BuildResultCaption(item as Object) as String
    if item = invalid then return ""

    if item.type = "episode" then
        return EpisodeCaption(item)
    end if

    if item.DoesExist("name") and item.name <> invalid then
        return item.name
    end if
    return ""
end function

sub OnResultSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.results.Count() then return

    item = m.results[index]
    if item = invalid then return

    ' Favorites can be any type; route every type sensibly.
    if item.type = "series" then
        ShowSeries(item.id, item.name)
    else if item.type = "season" then
        ShowSeason(item.id, item.name)
    else
        ShowItemDetail(item.id)
    end if
end sub

sub OnResultFocused(event as Object)
    index = event.getData()
    if index < 0 or index >= m.results.Count() then return

    item = m.results[index]
    if item = invalid then return

    if m.statusLabel <> invalid then
        if item.overview <> invalid then
            m.statusLabel.text = item.overview
        else
            m.statusLabel.text = BuildResultCaption(item)
        end if
    end if

    ' Prefetch: trigger LoadMoreItems when focus approaches end of loaded set
    ' (within one screen = 15 items for a 5x3 grid)
    if m.results.Count() > 0 and index >= m.results.Count() - m.prefetchThreshold then
        LoadMoreItems()
    end if
end sub

sub ShowSeries(seriesId as String, seriesName as String)
    name = seriesName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "SeriesScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadSeries(seriesId, name)
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

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.favoritesGrid <> invalid then
        m.favoritesGrid.UnObserveField("itemSelected")
        m.favoritesGrid.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if
    m.top.UnObserveField("visible")
end sub

' R5.4: Refetch favorites when scene becomes visible again after a child
' scene (e.g., DetailScene) was used to remove a favorite.
sub OnVisibilityChanged(event as Object)
    if event.getData() = true then
        ' Scene became visible — refetch to reflect any removals made in child scenes.
        RefetchFavorites()
    end if
end sub

' R5.4: Reset paging state and fire a fresh getFavorites request.
sub RefetchFavorites()
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.results = []
    m.contentNode = invalid

    if m.favoritesGrid <> invalid then
        m.favoritesGrid.content = CreateObject("roSGNode", "ContentNode")
    end if

    if m.statusLabel <> invalid then
        m.statusLabel.text = "Loading…"
    end if

    m.apiTask.request = {
        op: "getFavorites"
        options: { limit: m.limit, offset: m.offset }
    }
    m.apiTask.control = "run"
end sub

' Bubble requestClose from a child scene up to PhlixApp (which holds PopScreen).
sub OnChildRequestClose()
    m.top.requestClose = true
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