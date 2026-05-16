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

    m.itemId = ""
    m.item = invalid
end sub

sub LoadItem(itemId as String)
    m.itemId = itemId

    ' Fetch item details
    m.item = api.getItem(itemId)

    if m.item = invalid then
        return
    end if

    ' Update UI
    if m.titleLabel <> invalid then
        m.titleLabel.text = m.item.Name
    end if

    if m.descriptionLabel <> invalid then
        if m.item.Overview <> invalid then
            m.descriptionLabel.text = m.item.Overview
        end if
    end if

    if m.posterImage <> invalid and m.item.ImageTags <> invalid and m.item.ImageTags.Primary <> invalid then
        m.posterImage.uri = api.baseUrl + "/Items/" + m.item.Id + "/Images/Primary"
    end if

    ' Update info label with metadata
    if m.infoLabel <> invalid then
        info = ""
        if m.item.ProductionYear <> invalid then
            info = info + str(m.item.ProductionYear).trim()
        end if
        if m.item.RunTimeTicks <> invalid then
            runtime = Int(m.item.RunTimeTicks / 10000000)
            info = info + " • " + FormatTime(runtime)
        end if
        if m.item.OfficialRating <> invalid then
            info = info + " • " + m.item.OfficialRating
        end if
        m.infoLabel.text = info
    end if

    ' Hide play button if not playable
    if m.playButton <> invalid then
        if m.item.Type <> "Movie" and m.item.Type <> "Episode" and m.item.Type <> "Video" then
            m.playButton.visible = false
        end if
    end if
end sub

sub OnBackPressed()
    m.top.Close()
end sub

sub OnPlayPressed()
    if m.itemId = "" or m.item = invalid then
        return
    end if

    ' Only play video content
    if m.item.Type = "Movie" or m.item.Type = "Episode" or m.item.Type = "Video" then
        PlayItem()
    end if
end sub

sub PlayItem()
    ' Get playback info
    playbackInfo = api.getItemPlaybackInfo(m.itemId)

    if playbackInfo = invalid or playbackInfo.PlaybackInfo = invalid then
        print "No playback info available"
        return
    end if

    ' Create and show player
    playerScene = CreateObject("roSGNode", "PlayerScene")
    m.top.Append(playerScene)
    playerScene.Show(m.itemId, {
        item: m.item
        playback_info: playbackInfo.PlaybackInfo
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