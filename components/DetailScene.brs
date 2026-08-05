' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/DetailScene.brs

' copyright 2026 Joe Huss
'


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
    m.ratingBadge = m.top.FindNode("ratingBadge")
    m.contentRatingLabel = m.top.FindNode("contentRatingLabel")
    m.loadingLabel = m.top.FindNode("loadingLabel")

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

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
    end if

    m.apiTask.request = { op: "getItem", itemId: itemId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getItem" then
        if not resp.ok or resp.data = invalid then return

        ' Hide loading indicator.
        if m.loadingLabel <> invalid then
            m.loadingLabel.visible = false
        end if

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
            ShowErrorDialog(m.top, "Error", "Couldn't save your favourite. Please try again.")
        end if
    else if resp.op = "unfavorite" then
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.favorite = true
                RenderFavorite()
            end if
            ShowErrorDialog(m.top, "Error", "Couldn't remove your favourite. Please try again.")
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
            ShowErrorDialog(m.top, "Error", "Couldn't save your rating. Please try again.")
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
            ShowErrorDialog(m.top, "Error", "Couldn't clear your rating. Please try again.")
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

    ' Info line: year + runtime (MINUTES) + content-rating LABEL + chapter count.
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
        ' P2-S5: show chapter count if chapters are available on the item.
        if item.chapters <> invalid and type(item.chapters) = "roArray" and item.chapters.count() > 0 then
            if info <> "" then info = info + " • "
            info = info + str(item.chapters.count()).trim() + " chapters"
        end if
        m.infoLabel.text = info
    end if

    ' Show play button only for playable leaf types (see PlayableTypes() - it
    ' covers audio/track/audiobook/video too, not just movie/episode).
    if m.playButton <> invalid then
        m.playButton.visible = IsPlayableItem(item)
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

    ' Render aggregate rating (star badge showing the average score)
    RenderAggregateRating()

    ' P1-S8: Render content rating (G, PG, PG-13, R, etc.)
    RenderContentRating()
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

sub RenderAggregateRating()
    if m.ratingBadge = invalid then return

    item = m.item
    aggregateScore = invalid

    ' Try to extract aggregate rating from item data.
    ' Check common paths: ratings.aggregate.score, ratings.aggregate, rating
    if item <> invalid then
        if item.DoesExist("ratings") and item.ratings <> invalid then
            ratings = item.ratings
            if type(ratings) = "roAssociativeArray" then
                ' Try aggregate sub-object
                if ratings.DoesExist("aggregate") then
                    agg = ratings.aggregate
                    if type(agg) = "roAssociativeArray" then
                        if agg.DoesExist("score") then
                            aggregateScore = agg.score
                        else if agg.DoesExist("rating") then
                            aggregateScore = agg.rating
                        end if
                    else if type(agg) = "Float" or type(agg) = "roFloat" or type(agg) = "Integer" or type(agg) = "roInt" then
                        ' Direct numeric aggregate rating
                        aggregateScore = agg
                    end if
                end if
            end if
        end if

        ' Fallback: direct rating field if numeric and 0-10 range
        if aggregateScore = invalid and item.DoesExist("rating") then
            r = item.rating
            if type(r) = "Float" or type(r) = "roFloat" or type(r) = "Integer" or type(r) = "roInt" then
                if r >= 0 and r <= 10 then
                    aggregateScore = r
                end if
            end if
        end if
    end if

    ' Set the score on the badge (0 if not found - badge handles "N/A")
    if m.ratingBadge <> invalid then
        if aggregateScore = invalid then
            m.ratingBadge.score = 0
        else
            m.ratingBadge.score = aggregateScore
        end if
    end if
end sub

sub RenderContentRating()
    ' P1-S8: Display content rating label (G, PG, PG-13, R, etc.) prominently
    if m.contentRatingLabel = invalid then return

    item = m.item
    if item = invalid then
        m.contentRatingLabel.text = ""
        return
    end if

    contentRating = invalid

    ' Try to get content rating from item data
    ' Common paths: content_rating (string label), rating (0-6 int)
    if item.DoesExist("content_rating") and item.content_rating <> invalid then
        contentRating = item.content_rating
    else if item.DoesExist("rating") and item.rating <> invalid then
        r = item.rating
        ' If rating is a number 0-6, convert to content label
        if type(r) = "Integer" or type(r) = "roInt" or type(r) = "Float" or type(r) = "roFloat" then
            contentRating = RatingLabel(r)
        else if type(r) = "String" or type(r) = "roString" then
            ' Already a string label
            contentRating = r
        end if
    end if

    if contentRating <> invalid and contentRating <> "" then
        m.contentRatingLabel.text = "Rated " + contentRating
    else
        m.contentRatingLabel.text = ""
    end if
end sub

sub OnBackPressed()
    m.top.requestClose = true
end sub

sub OnPlayPressed()
    if m.itemId = "" or m.item = invalid then return

    ' Only playable leaf types have a stream to request. This mirrors the
    ' play-button visibility gate above, so Play is never a silent no-op for an
    ' item whose button we chose to show.
    if IsPlayableItem(m.item) then
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
    playerScene.ObserveField("requestClose", "OnChildRequestClose")
    ' P2-S5: pass trickplay sprite/timeline paths if available on the item.
    trickplay = {}
    if m.item.trickplay_sprite_path <> invalid and m.item.trickplay_sprite_path <> "" then
        trickplay.sprite_path = m.item.trickplay_sprite_path
    end if
    if m.item.trickplay_timeline_path <> invalid and m.item.trickplay_timeline_path <> "" then
        trickplay.timeline_path = m.item.trickplay_timeline_path
    end if
    trickplayArg = invalid
    if trickplay.count() > 0 then
        trickplayArg = trickplay
    end if

    playerScene.Show(m.itemId, {
        item: m.item
        playbackInfo: m.playbackInfo
        trickplay: trickplayArg
    })
end sub

' Bubble requestClose from a child scene up to PhlixApp (which holds PopScreen).
sub OnChildRequestClose()
    m.top.requestClose = true
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            m.top.requestClose = true
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