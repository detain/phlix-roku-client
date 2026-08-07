' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/HistoryScene.brs

' R7.4a: Watch History Display Scene
' Shows user's watch history with progress bars. Navigates to DetailScene on selection.
' Clear All removes all history (with confirm dialog).

sub Init()
    m.top.SetFocus(true)

    m.historyGrid = m.top.FindNode("historyGrid")
    if m.historyGrid <> invalid then
        m.historyGrid.ObserveField("itemSelected", "OnResultSelected")
        m.historyGrid.ObserveField("itemFocused", "OnResultFocused")
        m.historyGrid.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")
    m.clearAllButton = m.top.FindNode("clearAllButton")

    if m.clearAllButton <> invalid then
        m.clearAllButton.ObserveField("buttonSelected", "OnClearAllPressed")
    end if

    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.results = []
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid

    if m.statusLabel <> invalid then
        m.statusLabel.text = "Loading…"
    end if

    LoadHistory()
end sub

sub LoadHistory()
    ' allow-listed: callback-chained (m.apiTask is a fresh node created in Init, only one op at a time)
    if m.statusLabel <> invalid then
        m.statusLabel.text = "Loading…"
    end if

    m.apiTask.request = {
        op: "getWatchHistory"
        options: { limit: m.limit, offset: m.offset }
    }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getWatchHistory" then
        if m.statusLabel <> invalid then
            m.statusLabel.text = ""
        end if

        if not resp.ok or resp.data = invalid or resp.data.items = invalid then
            m.results = []
            if m.historyGrid <> invalid then
                m.historyGrid.content = CreateObject("roSGNode", "ContentNode")
            end if
            if m.statusLabel <> invalid then
                m.statusLabel.text = "No watch history yet"
            end if
            m.hasMore = false
            return
        end if

        newItems = resp.data.items
        itemCount = newItems.count()

        if m.offset = 0 then
            m.results = newItems
            m.contentNode = CreateObject("roSGNode", "ContentNode")
            m.historyGrid.content = m.contentNode
        else
            m.results.append(newItems)
        end if

        for each item in newItems
            contentItem = m.contentNode.AddChild({
                Title: item.title
                ShortDescriptionLine1: item.title
                Type: item.type
                id: item.id
            })

            ' Watch progress (0.0 to 1.0) shown as a backdrop field
            if item.progress <> invalid then
                contentItem.BackdropUrl = "progress:" + str(item.progress).trim()
            end if

            if item.overview <> invalid then
                contentItem.Description = item.overview
            end if

            if item.poster_url <> invalid and item.poster_url <> "" then
                contentItem.HDPosterUrl = item.poster_url
            else
                contentItem.HDPosterUrl = "pkg:/images/placeholder.png"
            end if
        end for

        m.offset = m.offset + itemCount
        m.hasMore = (itemCount = m.limit)

        if m.statusLabel <> invalid and m.results.Count() = 0 then
            m.statusLabel.text = "No watch history yet"
        end if
    end if
end sub

sub OnResultSelected(event as Object)
    index = event.getData()
    if index < 0 or index >= m.results.Count() then return

    item = m.results[index]
    if item = invalid then return

    if item.type = "series" then
        ShowSeries(item.id, item.title)
    else if item.type = "season" then
        ShowSeason(item.id, item.title)
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
        progress = ""
        if item.progress <> invalid then
            progress = " • " + str(int(item.progress * 100)).trim() + "% watched"
        end if
        m.statusLabel.text = item.title + progress
    end if
end sub

sub OnClearAllPressed(event as Object)
    ShowConfirmClearHistory()
end sub

sub ShowConfirmClearHistory()
    dialog = CreateObject("roSGNode", "Dialog")
    if dialog = invalid then return

    dialog.title = "Clear Watch History?"
    dialog.message = "This will remove all items from your watch history. This cannot be undone."
    dialog.AddButton(1, "Cancel")
    dialog.AddButton(2, "Clear All")

    m.top.Append(dialog)
    dialog.ObserveField("buttonSelected", "OnClearHistoryButton")
    m.confirmDialog = dialog
end sub

sub OnClearHistoryButton(event as Object)
    data = event.getData()
    if data = invalid then return

    if m.confirmDialog <> invalid then
        m.confirmDialog.UnObserveField("buttonSelected")
        m.top.RemoveChild(m.confirmDialog)
        m.confirmDialog = invalid
    end if

    if data = 2 then
        GetApiClient().clearWatchHistory()
        m.results = []
        m.offset = 0
        if m.historyGrid <> invalid then
            m.historyGrid.content = CreateObject("roSGNode", "ContentNode")
        end if
        if m.statusLabel <> invalid then
            m.statusLabel.text = "Watch history cleared"
        end if
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

sub Teardown()
    if m.historyGrid <> invalid then
        m.historyGrid.UnObserveField("itemSelected")
        m.historyGrid.UnObserveField("itemFocused")
    end if
    if m.clearAllButton <> invalid then
        m.clearAllButton.UnObserveField("buttonSelected")
    end if
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if
    if m.confirmDialog <> invalid then
        m.confirmDialog.UnObserveField("buttonSelected")
    end if
end sub

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