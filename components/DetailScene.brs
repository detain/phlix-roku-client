' source/components/DetailScene.brs

sub Init()
    m.top.SetFocus(true)

    ' UI nodes
    m.backButton = m.top.FindNode("backButton")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.posterImage = m.top.FindNode("posterImage")
    m.descriptionLabel = m.top.FindNode("descriptionLabel")
    m.playButton = m.top.FindNode("playButton")
    m.infoLabel = m.top.FindNode("infoLabel")

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    if m.playButton <> invalid then
        m.playButton.ObserveField("buttonSelected", "OnPlayPressed")
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.itemId = ""
    m.item = invalid
    m.playbackInfo = invalid
end sub

sub LoadItem(itemId as String)
    m.itemId = itemId
    m.apiTask.request = { op: "getItem", itemId: itemId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getItem" then
        if not resp.ok or resp.data = invalid then return
        m.item = resp.data
        RenderItem()
    else if resp.op = "getItemPlaybackInfo" then
        ' Markers/chapters may legitimately be empty; launch the player either way.
        if resp.ok then
            m.playbackInfo = resp.data
        else
            m.playbackInfo = invalid
        end if
        PlayItem()
    end if
end sub

sub RenderItem()
    item = m.item

    if m.titleLabel <> invalid then
        m.titleLabel.text = item.name
    end if

    if m.descriptionLabel <> invalid then
        if item.overview <> invalid then
            m.descriptionLabel.text = item.overview
        end if
    end if

    if m.posterImage <> invalid and item.poster_url <> invalid and item.poster_url <> "" then
        m.posterImage.uri = item.poster_url
    end if

    ' Info line: year + runtime (MINUTES) + content-rating LABEL.
    if m.infoLabel <> invalid then
        info = ""
        if item.year <> invalid then
            info = info + str(item.year).trim()
        end if
        if item.runtime <> invalid then
            if info <> "" then info = info + " • "
            info = info + FormatTime(item.runtime * 60)
        end if
        if item.rating <> invalid and item.rating <> "" then
            if info <> "" then info = info + " • "
            info = info + item.rating
        end if
        m.infoLabel.text = info
    end if

    ' Show play button only for playable video types (canonical lowercase).
    if m.playButton <> invalid then
        if item.type = "movie" or item.type = "episode" then
            m.playButton.visible = true
        else
            m.playButton.visible = false
        end if
    end if
end sub

sub OnBackPressed()
    m.top.Close()
end sub

sub OnPlayPressed()
    if m.itemId = "" or m.item = invalid then return

    ' Only play video content.
    if m.item.type = "movie" or m.item.type = "episode" then
        m.apiTask.request = { op: "getItemPlaybackInfo", itemId: m.itemId }
        m.apiTask.control = "run"
    end if
end sub

sub PlayItem()
    playerScene = CreateObject("roSGNode", "PlayerScene")
    m.top.Append(playerScene)
    playerScene.Show(m.itemId, {
        item: m.item
        playbackInfo: m.playbackInfo
    })
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            m.top.Close()
            handled = true
        else if key = "play" or key = "select" then
            OnPlayPressed()
            handled = true
        end if
    end if

    return handled
end sub
