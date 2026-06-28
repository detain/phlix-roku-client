' components/SeasonScene.brs
'
' Episodes grid for a single season. Mirrors LibraryScene's PosterGrid + ApiTask
' pattern. Fires getLibraryItems with options.parentId=<seasonId> (direct-children
' mode, omits topLevel), re-sorts the episodes client-side (the API returns ORDER
' BY name), and routes a selected episode to the existing DetailScene (which plays
' it via PlayerScene).

sub Init()
    m.top.SetFocus(true)

    ' Poster grid for the episodes.
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

    m.seasonId = ""
    m.children = []
end sub

' Cross-component callable (declared in the <interface>). Loads the episodes of
' the given season.
sub LoadSeason(seasonId as String, seasonName as String)
    m.seasonId = seasonId

    if m.titleLabel <> invalid then
        m.titleLabel.text = seasonName
    end if

    if m.seasonId = "" then return

    ' parentId switches getLibraryItems to direct-children mode and omits
    ' topLevel; limit is high enough to return every episode at once.
    m.apiTask.request = {
        op: "getLibraryItems"
        libraryId: m.seasonId
        options: { parentId: m.seasonId, limit: 200 }
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
            caption = EpisodeCaption(item)

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

sub OnItemSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.children.Count() then return

    episode = m.children[index]
    if episode = invalid then return

    ' Episode -> existing DetailScene (mints stream_url, plays via PlayerScene).
    ShowItemDetail(episode.id)
end sub

sub OnItemFocused(event as Object)
    index = event.getData()

    if index >= 0 and index < m.children.Count() then
        item = m.children[index]
        if item <> invalid and m.descriptionLabel <> invalid then
            if item.overview <> invalid then
                m.descriptionLabel.text = item.overview
            else
                m.descriptionLabel.text = EpisodeCaption(item)
            end if
        end if
    end if
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    m.top.Append(scene)
    scene.LoadItem(itemId)
end sub

sub OnBackPressed()
    Teardown()
    m.top.Close()
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
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function
