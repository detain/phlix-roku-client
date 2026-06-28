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
    m.favoriteButton = m.top.FindNode("favoriteButton")
    m.ratingButton = m.top.FindNode("ratingButton")

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    if m.playButton <> invalid then
        m.playButton.ObserveField("buttonSelected", "OnPlayPressed")
    end if

    if m.favoriteButton <> invalid then
        m.favoriteButton.ObserveField("buttonSelected", "OnFavoriteToggle")
    end if

    if m.ratingButton <> invalid then
        m.ratingButton.ObserveField("buttonSelected", "OnRatingCommit")
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.itemId = ""
    m.item = invalid
    m.playbackInfo = invalid

    ' Actions-strip focus state machine. "none" = scene holds focus (play-on-OK
    ' works); "favorite"/"rating" = a strip button is focused.
    m.actionFocus = "none"
    m.pendingRating = 0
    m.userData = invalid
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
    else if resp.op = "favorite" then
        ' Optimistic flip already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.favorite = false
                RenderFavorite()
            end if
            print "Phlix: add favorite failed"
        end if
    else if resp.op = "unfavorite" then
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.favorite = true
                RenderFavorite()
            end if
            print "Phlix: remove favorite failed"
        end if
    else if resp.op = "setRating" then
        if not resp.ok then
            ' Revert to the server's last-known rating.
            if m.userData <> invalid then
                m.pendingRating = 0
                if m.userData.DoesExist("rating") and m.userData.rating <> invalid then
                    m.pendingRating = m.userData.rating
                end if
                RenderRating()
            end if
            print "Phlix: set rating failed"
        end if
    else if resp.op = "clearRating" then
        if not resp.ok then
            if m.userData <> invalid then
                m.pendingRating = 0
                if m.userData.DoesExist("rating") and m.userData.rating <> invalid then
                    m.pendingRating = m.userData.rating
                end if
                RenderRating()
            end if
            print "Phlix: clear rating failed"
        end if
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

    ' Favorite + rating strip: only when the server injected user_data (auth'd
    ' and the store is wired). DoesExist guards the optional key.
    m.userData = invalid
    if item.DoesExist("user_data") then
        m.userData = item.user_data
    end if

    if m.userData = invalid then
        if m.favoriteButton <> invalid then m.favoriteButton.visible = false
        if m.ratingButton <> invalid then m.ratingButton.visible = false
    else
        if m.favoriteButton <> invalid then m.favoriteButton.visible = true
        if m.ratingButton <> invalid then m.ratingButton.visible = true

        m.pendingRating = 0
        if m.userData.DoesExist("rating") and m.userData.rating <> invalid then
            m.pendingRating = m.userData.rating
        end if

        RenderFavorite()
        RenderRating()
    end if
end sub

sub RenderFavorite()
    if m.favoriteButton = invalid or m.userData = invalid then return

    isFav = false
    if m.userData.DoesExist("favorite") and m.userData.favorite = true then isFav = true

    if isFav then
        m.favoriteButton.title = "Remove from Favorites"
    else
        m.favoriteButton.title = "Add to Favorites"
    end if
end sub

sub RenderRating()
    if m.ratingButton = invalid then return

    if m.pendingRating > 0 then
        m.ratingButton.title = "Rating: " + str(m.pendingRating).trim() + "/10"
    else
        m.ratingButton.title = "Rating: not set"
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

sub OnFavoriteToggle()
    if m.userData = invalid or m.itemId = "" then return

    isFav = false
    if m.userData.DoesExist("favorite") and m.userData.favorite = true then isFav = true

    if isFav then
        ' Optimistic: clear locally, fire unfavorite; revert on failure.
        m.userData.favorite = false
        RenderFavorite()
        m.apiTask.request = { op: "unfavorite", itemId: m.itemId }
        m.apiTask.control = "run"
    else
        m.userData.favorite = true
        RenderFavorite()
        m.apiTask.request = { op: "favorite", itemId: m.itemId }
        m.apiTask.control = "run"
    end if
end sub

sub OnRatingCommit()
    if m.userData = invalid or m.itemId = "" then return

    if m.pendingRating <= 0 then
        ' 0 = clear the rating.
        m.userData.rating = invalid
        RenderRating()
        m.apiTask.request = { op: "clearRating", itemId: m.itemId }
        m.apiTask.control = "run"
    else
        m.userData.rating = m.pendingRating
        RenderRating()
        m.apiTask.request = { op: "setRating", itemId: m.itemId, rating: m.pendingRating }
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

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            m.top.Close()
            handled = true
        else if key = "play" then
            ' Dedicated Play remote button always plays.
            OnPlayPressed()
            handled = true
        else if key = "select" then
            ' Preserve play-on-OK ONLY when the scene holds focus. When a strip
            ' button is focused the framework fires its buttonSelected for OK, so
            ' do not also play (let the button consume it).
            if m.actionFocus = "none" then
                OnPlayPressed()
                handled = true
            else
                handled = false
            end if
        else if key = "down" then
            handled = OnActionDown()
        else if key = "up" then
            handled = OnActionUp()
        else if key = "left" then
            ' While the strip is entered it fully owns horizontal input so the
            ' default arrow navigation can't drift focus among the sibling
            ' Buttons and desync m.actionFocus.
            if m.actionFocus = "rating" then
                if m.pendingRating > 0 then m.pendingRating = m.pendingRating - 1
                RenderRating()
                handled = true
            else if m.actionFocus = "favorite" then
                handled = true
            end if
        else if key = "right" then
            if m.actionFocus = "rating" then
                if m.pendingRating < 10 then m.pendingRating = m.pendingRating + 1
                RenderRating()
                handled = true
            else if m.actionFocus = "favorite" then
                handled = true
            end if
        end if
    end if

    return handled
end function

' Move focus DOWN through the actions strip: scene -> favorite -> rating.
function OnActionDown() as Boolean
    if m.actionFocus = "none" then
        if m.favoriteButton <> invalid and m.favoriteButton.visible then
            m.favoriteButton.SetFocus(true)
            m.actionFocus = "favorite"
            return true
        end if
    else if m.actionFocus = "favorite" then
        if m.ratingButton <> invalid and m.ratingButton.visible then
            m.ratingButton.SetFocus(true)
            m.actionFocus = "rating"
            return true
        end if
    end if
    return false
end function

' Move focus UP through the actions strip: rating -> favorite -> scene.
function OnActionUp() as Boolean
    if m.actionFocus = "rating" then
        if m.favoriteButton <> invalid and m.favoriteButton.visible then
            m.favoriteButton.SetFocus(true)
            m.actionFocus = "favorite"
            return true
        end if
    else if m.actionFocus = "favorite" then
        m.top.SetFocus(true)
        m.actionFocus = "none"
        return true
    end if
    return false
end function
