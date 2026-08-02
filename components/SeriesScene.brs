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

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.seriesId = ""
    m.children = []
end sub

' Cross-component callable (declared in the <interface>). Loads the children of
' the given series.
sub LoadSeries(seriesId as String, seriesName as String)
    m.seriesId = seriesId

    if m.titleLabel <> invalid then
        m.titleLabel.text = seriesName
    end if

    if m.seriesId = "" then return

    ' parentId switches getLibraryItems to direct-children mode and omits
    ' topLevel; limit is high enough to return every season/episode at once.
    m.apiTask.request = {
        op: "getLibraryItems"
        libraryId: m.seriesId
        options: { parentId: m.seriesId, limit: 200 }
    }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getLibraryItems" then
        if not resp.ok or resp.data = invalid or resp.data.items = invalid then return

        ' API returns children ORDER BY name; re-sort by season then episode.
        m.children = SortByEpisodeOrder(resp.data.items)

        content = CreateObject("roSGNode", "ContentNode")
        for each item in m.children
            caption = BuildCaption(item)

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

        m.posterGrid.content = content
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
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
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