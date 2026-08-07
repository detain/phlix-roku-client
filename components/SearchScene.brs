'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/SearchScene.brs

' copyright 2026 Joe Huss
'

'
' Global search screen: an on-screen Keyboard (left) drives a live results
' PosterGrid (right). Mirrors LibraryScene's PosterGrid + ApiTask pattern but
' fires the dedicated `search` op (ApiClient.search -> GET /media?search=<q>,
' NO libraryId/topLevel, so results span every library and CAN include
' season/episode rows). Selecting a result routes exactly like LibraryScene:
'   series  -> SeriesScene
'   season  -> SeasonScene
'   else    -> DetailScene (every other media_items.type: movie/episode/video/
'              audio/track/music/album/artist/book/photo/audiobook -- note
'              `photo`, there is no `image` member)
'
' Query is debounced: a non-repeating ~1s Timer is restarted on each keystroke
' and only fires the search when the trimmed query length is >= 2.

sub Init()
    m.top.SetFocus(true)

    ' Keyboard (left). Start focus here; observe its text for live queries.
    m.keyboard = m.top.FindNode("keyboard")
    if m.keyboard <> invalid then
        m.keyboard.ObserveField("text", "OnQueryChanged")
        m.keyboard.SetFocus(true)
    end if

    ' Results grid (right).
    m.resultsGrid = m.top.FindNode("resultsGrid")
    if m.resultsGrid <> invalid then
        m.resultsGrid.ObserveField("itemSelected", "OnResultSelected")
        m.resultsGrid.ObserveField("itemFocused", "OnResultFocused")
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' Debounce timer (render thread). Non-repeating; restarted on each keystroke.
    m.searchTimer = m.top.CreateChild("Timer")
    m.searchTimer.duration = 1
    m.searchTimer.repeat = false
    m.searchTimer.ObserveField("fire", "OnSearchTimerFire")

    m.results = []
    ' Focus zone: "keyboard" or "results".
    m.zone = "keyboard"

    ' Paging state for infinite scroll (R5.2)
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)

    if m.statusLabel <> invalid then
        m.statusLabel.text = "Type to search…"
    end if
end sub

' Keyboard text changed: debounce a search, or clear when the query is too short.
sub OnQueryChanged(event as Object)
    query = event.getData()
    if query = invalid then query = ""
    trimmed = query.trim()

    if Len(trimmed) < 2 then
        ' Too short: stop any pending search and clear the grid.
        m.searchTimer.control = "stop"
        m.results = []
        m.contentNode = invalid
        m.hasMore = false
        m.loadingPage = false
        if m.resultsGrid <> invalid then
            m.resultsGrid.content = CreateObject("roSGNode", "ContentNode")
        end if
        if m.statusLabel <> invalid then
            m.statusLabel.text = "Type to search…"
        end if
        return
    end if

    ' Debounce: restart the non-repeating timer; the search fires on its `fire`.
    m.searchTimer.control = "stop"
    m.searchTimer.control = "start"
end sub

' Timer fired: run the search for the current keyboard text.
sub OnSearchTimerFire(event as Object)
    if m.keyboard = invalid then return

    query = m.keyboard.text
    if query = invalid then query = ""
    if Len(query.trim()) < 2 then return

    ' Reset paging state for fresh search
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.results = []
    m.contentNode = invalid

    if m.apiTask.state = "run" then return
    m.apiTask.request = {
        op: "search"
        query: query
        options: { limit: m.limit, offset: m.offset }
    }
    m.apiTask.state = "run"
    m.apiTask.control = "run"
end sub

' Load next page of items. Guard prevents concurrent page requests.
sub LoadMoreItems()
    ' Guard: do not run two page requests at once
    if m.loadingPage then return
    if not m.hasMore then return

    if m.keyboard = invalid then return
    query = m.keyboard.text
    if query = invalid or Len(query.trim()) < 2 then return

    m.loadingPage = true

    m.apiTask.request = {
        op: "search"
        query: query
        options: { limit: m.limit, offset: m.offset }
    }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "search" then
        ' Hide loading indicator.
        if m.statusLabel <> invalid and m.loadingPage then
            m.statusLabel.text = ""
        end if

        if not resp.ok or resp.data = invalid or resp.data.items = invalid then
            m.results = []
            if m.resultsGrid <> invalid then
                m.resultsGrid.content = CreateObject("roSGNode", "ContentNode")
            end if
            if m.statusLabel <> invalid and not m.loadingPage then
                m.statusLabel.text = "No results"
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
            m.resultsGrid.content = m.contentNode
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
                m.statusLabel.text = "No results"
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

    ' Search can return seasons/episodes; route every type sensibly.
    if item.type = "series" then
        ShowSeries(item.id, item.name)
    else if item.type = "season" then
        ShowSeason(item.id, item.name)
    else
        ShowItemDetail(item.id)
    end if
end sub

sub OnResultFocused(event as Object)
    m.zone = "results"

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
    if m.keyboard <> invalid then
        m.keyboard.UnObserveField("text")
    end if
    if m.resultsGrid <> invalid then
        m.resultsGrid.UnObserveField("itemSelected")
        m.resultsGrid.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if
    if m.searchTimer <> invalid then
        m.searchTimer.control = "stop"
        m.searchTimer.UnObserveField("fire")
    end if
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        ' Horizontal keyboard<->results focus. The Roku Keyboard is a key grid;
        ' "right" at its right edge bubbles to the scene more reliably than
        ' "down". NOTE: exact Keyboard edge-bubbling is DEVICE-UNVERIFIABLE
        ' without hardware - implemented per the F4 spec assumption.
        if key = "right" and m.zone = "keyboard" and m.results.Count() > 0 then
            if m.resultsGrid <> invalid then
                m.resultsGrid.SetFocus(true)
                m.zone = "results"
                handled = true
            end if
        else if key = "left" and m.zone = "results" then
            if m.keyboard <> invalid then
                m.keyboard.SetFocus(true)
                m.zone = "keyboard"
                handled = true
            end if
        else if key = "back" then
            Teardown()
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end function