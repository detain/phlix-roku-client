' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/SeasonScene.brs

' copyright 2026 Joe Huss
'

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
    m.loadingLabel = m.top.FindNode("loadingLabel")

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    ' Route all data access through the EpisodeListTask node (off the render thread).
    ' This handles both the API call AND ContentNode building off the render thread.
    m.listTask = CreateObject("roSGNode", "EpisodeListTask")
    m.listTask.ObserveField("content", "OnListContent")

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

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
    end if

    ' EpisodeListTask handles fetch + sort + ContentNode build off the render thread.
    m.listTask.libraryId = m.seasonId
    m.listTask.parentId = m.seasonId
    m.listTask.itemType = "season"
    m.listTask.control = "run"
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
        m.children = m.listTask.items
        m.posterGrid.content = m.listTask.content
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