' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/WatchHistoryScene.brs

' copyright 2026 Joe Huss
'

'
' Watch History browse screen: a one-shot PosterGrid of the user's recently watched items.
' Mirrors FavoritesScene's grid + ApiTask + type-routed selection idiom.
' Uses the getWatchHistory op (ApiClient.getWatchHistory -> GET /me/history).
' Items are canonical media items, so selecting one routes exactly like LibraryScene/
' FavoritesScene:
'   series  -> SeriesScene (LoadSeries)
'   season  -> SeasonScene (LoadSeason)
'   else    -> DetailScene (LoadItem)   (every other media_items.type:
'                                        movie/episode/video/audio/track/
'                                        music/album/artist/book/photo/
'                                        audiobook -- note `photo`, there
'                                        is no `image` member)

sub Init()
    m.top.SetFocus(true)

    ' History grid.
    m.historyGrid = m.top.FindNode("historyGrid")
    if m.historyGrid <> invalid then
        m.historyGrid.ObserveField("itemSelected", "OnResultSelected")
        m.historyGrid.ObserveField("itemFocused", "OnResultFocused")
        m.historyGrid.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.results = []

    if m.statusLabel <> invalid then
        m.statusLabel.text = "Loading…"
    end if

    ' One-shot load on Init.
    m.apiTask.request = {
        op: "getWatchHistory"
        options: { limit: 100 }
    }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getWatchHistory" then
        if not resp.ok or resp.data = invalid or resp.data.items = invalid then
            m.results = []
            if m.historyGrid <> invalid then
                m.historyGrid.content = CreateObject("roSGNode", "ContentNode")
            end if
            if m.statusLabel <> invalid then
                m.statusLabel.text = "No watch history yet"
            end if
            return
        end if

        m.results = resp.data.items

        content = CreateObject("roSGNode", "ContentNode")
        for each item in m.results
            caption = BuildResultCaption(item)

            contentItem = content.AddChild({
                Title: caption
                ShortDescriptionLine1: caption
                Type: item.type
                id: item.id
            })

            if item.overview <> invalid then
                contentItem.Description = item.overview
            end if

            ' poster_url is an absolute URL or null.
            if item.poster_url <> invalid and item.poster_url <> "" then
                contentItem.HDPosterUrl = item.poster_url
            else
                contentItem.HDPosterUrl = "pkg:/images/placeholder.png"
            end if
        end for

        m.historyGrid.content = content

        if m.statusLabel <> invalid then
            if m.results.Count() = 0 then
                m.statusLabel.text = "No watch history yet"
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

    ' Watch history can be any type; route every type sensibly.
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

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.historyGrid <> invalid then
        m.historyGrid.UnObserveField("itemSelected")
        m.historyGrid.UnObserveField("itemFocused")
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