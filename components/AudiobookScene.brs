' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/AudiobookScene.brs

' copyright 2026 Joe Huss
'
'
' Audiobook library grid with paging (R7.6).
' Displays audiobooks in a poster grid with infinite scroll paging.
' Mirrors LibraryScene pattern but simpler (no A-Z bar, no sort/filter).
' On item selection, opens AudiobookPlayerScene for playback.

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

    m.items = []

    ' Paging state for infinite scroll (R5.1 pattern)
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)
end sub

sub LoadAudiobooks()
    ' Reset paging state for fresh load
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.items = []
    m.contentNode = invalid

    RefreshItems()
end sub

sub RefreshItems()
    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
        if m.offset > 0 then
            m.loadingLabel.text = "Loading more..."
        else
            m.loadingLabel.text = "Loading..."
        end if
    end if

    if m.apiTask.state = "run" then return
    m.apiTask.request = {
        op: "getAudiobooks"
        options: {
            offset: m.offset
            limit: m.limit
        }
    }
    m.apiTask.state = "run"
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

    if resp.op = "getAudiobooks" then
        ' Hide loading indicator.
        if m.loadingLabel <> invalid then
            m.loadingLabel.visible = false
        end if

        if not resp.ok or resp.data = invalid then
            m.loadingPage = false
            return
        end if

        ' Extract audiobooks from envelope (server returns {audiobooks:[...],total,limit,offset})
        newItems = []
        if resp.data.audiobooks <> invalid then
            newItems = resp.data.audiobooks
        else if type(resp.data) = "roArray" then
            ' Fallback: treat the response as the array directly
            newItems = resp.data
        end if

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
                ShortDescriptionLine2: item.author
                Type: "audiobook"
                id: item.id
            })

            ' poster_url is an absolute URL or null.
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

    else if resp.op = "getAudiobook" then
        ' Item detail response - launch player
        if resp.ok and resp.data <> invalid then
            ShowAudiobookPlayer(resp.data)
        end if
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    ' Fetch full audiobook details then launch player
    if m.apiTask.state = "run" then return
    m.apiTask.request = { op: "getAudiobook", audiobookId: item.id }
    m.apiTask.state = "run"
    m.apiTask.control = "run"
end sub

sub OnItemFocused(event as Object)
    index = event.getData()

    if index >= 0 and index < m.items.Count() then
        item = m.items[index]
        if m.descriptionLabel <> invalid then
            desc = ""
            if item.overview <> invalid then
                desc = item.overview
            else if item.name <> invalid then
                desc = item.name
            end if
            ' Add author if available
            if item.author <> invalid and item.author <> "" then
                desc = item.author + " - " + desc
            end if
            m.descriptionLabel.text = desc
        end if

        ' Prefetch: trigger LoadMoreItems when focus approaches end of loaded set
        ' (within one screen = 15 items for a 5x3 grid)
        if m.items.Count() > 0 and index >= m.items.Count() - m.prefetchThreshold then
            LoadMoreItems()
        end if
    end if
end sub

sub ShowAudiobookPlayer(audiobook as Object)
    scene = CreateObject("roSGNode", "AudiobookPlayerScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadAudiobook(audiobook)
end sub

sub OnBackPressed()
    m.top.requestClose = true
end sub

sub OnChildRequestClose()
    m.top.requestClose = true
end sub

' Pair every ObserveField with UnObserveField so the scene does not leak.
sub Teardown()
    if m.backButton <> invalid then
        m.backButton.UnObserveField("buttonSelected")
    end if
    if m.posterGrid <> invalid then
        m.posterGrid.UnObserveField("itemSelected")
        m.posterGrid.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end sub
