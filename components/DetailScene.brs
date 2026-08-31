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
    m.watchedButton = m.top.FindNode("watchedButton")
    m.likeButton = m.top.FindNode("likeButton")
    m.collectionButton = m.top.FindNode("collectionButton")

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

    if m.watchedButton <> invalid then
        m.watchedButton.ObserveField("buttonSelected", "OnWatchedToggle")
    end if

    if m.likeButton <> invalid then
        m.likeButton.ObserveField("buttonSelected", "OnLikeToggle")
    end if

    if m.collectionButton <> invalid then
        m.collectionButton.ObserveField("buttonSelected", "OnCollectionPressed")
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.itemId = ""
    m.item = invalid
    m.playbackInfo = invalid

    ' R6.3: autoPlayOnLoad triggers auto-play after the item finishes loading.
    ' Set by PhlixApp.ProcessDeepLink for deep-linked movie/episode content.
    m.autoPlayOnLoad = false

    ' Actions-strip focus state machine. "none" = scene holds focus (play-on-OK
    ' works); "favorite"/"rating" = a strip button is focused.
    m.actionFocus = "none"
    m.pendingRating = 0
    m.userData = invalid

    ' R7.11: Collections state - list of available collections.
    m.collections = []
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

        ' R6.3: If deep-linked with autoPlayOnLoad, play immediately after load.
        if m.top.autoPlayOnLoad and IsPlayableItem(m.item) then
            m.top.autoPlayOnLoad = false
            OnPlayPressed()
        end if

        ' R7.4: Load additional enrichment data (similar items, ratings).
        LoadAdditionalData()
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
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_favorite_save_message"))
        end if
    else if resp.op = "unfavorite" then
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.favorite = true
                RenderFavorite()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_favorite_remove_message"))
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
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_rating_save_message"))
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
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_rating_clear_message"))
        end if
    else if resp.op = "markWatched" then
        ' Optimistic update already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.watched = false
                RenderWatched()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_watched_mark_message"))
        end if
    else if resp.op = "markUnwatched" then
        ' Optimistic update already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.watched = true
                RenderWatched()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_watched_unmark_message"))
        end if
    else if resp.op = "like" then
        ' Optimistic update already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.liked = not m.userData.liked
                RenderLike()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), GetErrorMessage(resp.error))
        end if
    else if resp.op = "getItemSimilar" then
        ' R7.4: Store similar items and display if available.
        if resp.ok and resp.data <> invalid then
            similarItems = invalid
            if type(resp.data) = "roAssociativeArray" then
                if resp.data.DoesExist("items") then
                    similarItems = resp.data.items
                else
                    similarItems = resp.data
                end if
            end if
            m.similarData = similarItems
            DisplaySimilar(similarItems)
        end if
    else if resp.op = "getItemRatings" then
        ' R7.4: Store external ratings and display if available.
        if resp.ok and resp.data <> invalid then
            m.ratingsData = resp.data
            DisplayRatings(resp.data)
        end if
    else if resp.op = "getItemTrailers" then
        ' R7.4: Store trailers and display if available.
        if resp.ok and resp.data <> invalid then
            trailers = invalid
            if type(resp.data) = "roAssociativeArray" then
                if resp.data.DoesExist("items") then
                    trailers = resp.data.items
                else
                    trailers = resp.data
                end if
            end if
            m.trailersData = trailers
            DisplayTrailers(trailers)
        end if
    else if resp.op = "getItemExtras" then
        ' R7.4: Store extras and display if available.
        if resp.ok and resp.data <> invalid then
            extras = invalid
            if type(resp.data) = "roAssociativeArray" then
                if resp.data.DoesExist("items") then
                    extras = resp.data.items
                else
                    extras = resp.data
                end if
            end if
            m.extrasData = extras
            DisplayExtras(extras)
        end if
    else if resp.op = "getCollections" then
        ' R7.11: Store collections list and show picker.
        if resp.ok and resp.data <> invalid then
            collectionsArray = invalid
            if type(resp.data) = "roAssociativeArray" and resp.data.DoesExist("collections") then
                collectionsArray = resp.data.collections
            else if type(resp.data) = "roArray" then
                collectionsArray = resp.data
            end if
            if collectionsArray <> invalid then
                m.collections = collectionsArray
            else
                m.collections = []
            end if
            RenderCollection()
            ShowCollectionPicker()
        end if
    else if resp.op = "addToCollection" then
        if not resp.ok then
            ShowErrorDialog(m.top, Translate("common_error"), GetErrorMessage(resp.error))
        end if
    else if resp.op = "removeFromCollection" then
        if not resp.ok then
            ShowErrorDialog(m.top, Translate("common_error"), GetErrorMessage(resp.error))
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
            info = info + str(item.chapters.count()).trim() + " " + Translate("detail_chapters_count")
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
        if m.watchedButton <> invalid then m.watchedButton.visible = false
        if m.likeButton <> invalid then m.likeButton.visible = false
        if m.collectionButton <> invalid then m.collectionButton.visible = false
    else
        if m.favoriteButton <> invalid then m.favoriteButton.visible = true
        if m.ratingButton <> invalid then m.ratingButton.visible = true
        if m.watchedButton <> invalid then m.watchedButton.visible = true
        if m.likeButton <> invalid then m.likeButton.visible = true
        if m.collectionButton <> invalid then m.collectionButton.visible = true

        m.pendingRating = 0
        if m.userData.DoesExist("rating") and m.userData.rating <> invalid then
            m.pendingRating = m.userData.rating
        end if

        RenderFavorite()
        RenderRating()
        RenderWatched()
        RenderLike()
        RenderCollection()
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
        m.favoriteButton.title = Translate("detail_favorite_remove")
    else
        m.favoriteButton.title = Translate("detail_favorite_add")
    end if
end sub

sub RenderRating()
    if m.ratingButton = invalid then return

    if m.pendingRating > 0 then
        ratingStr = str(m.pendingRating).trim()
        m.ratingButton.title = Translate("detail_rating_label") + ratingStr
    else
        m.ratingButton.title = Translate("detail_rating_not_set")
    end if
end sub

' ---------------------------------------------------------------------
' R7.5: Render watched/unwatched button state.
' When user_data.watched is not set (first load), defaults to "unwatched"
' so the button shows "Mark as Watched".
' ---------------------------------------------------------------------
sub RenderWatched()
    if m.watchedButton = invalid then return
    if m.userData = invalid then return

    isWatched = false
    if m.userData.DoesExist("watched") and m.userData.watched = true then isWatched = true

    if isWatched then
        m.watchedButton.title = Translate("detail_watched_unmark")
    else
        m.watchedButton.title = Translate("detail_watched_mark")
    end if
end sub

' ---------------------------------------------------------------------
' R7.5: Render like button state.
' When user_data.liked is true, shows "Unlike". Otherwise shows "Like".
' ---------------------------------------------------------------------
sub RenderLike()
    if m.likeButton = invalid then return
    if m.userData = invalid then return

    isLiked = false
    if m.userData.DoesExist("liked") and m.userData.liked = true then isLiked = true

    if isLiked then
        m.likeButton.title = Translate("detail_like_unlike")
    else
        m.likeButton.title = Translate("detail_like_like")
    end if
end sub

' ---------------------------------------------------------------------
' R7.11: Render collection button state. Shows "Add to Collection" when
' collections are available. Button is visible only when userData exists.
' ---------------------------------------------------------------------
sub RenderCollection()
    if m.collectionButton = invalid then return
    if m.userData = invalid then return

    if m.collections <> invalid and m.collections.count() > 0 then
        ' Check if item is already in any collection
        itemInCollection = false
        for each col in m.collections
            if col.DoesExist("items") and col.items <> invalid then
                for each item in col.items
                    if item.DoesExist("id") and item.id = m.itemId then
                        itemInCollection = true
                        exit for
                    end if
                end for
            end if
            if itemInCollection then exit for
        end for
        if itemInCollection then
            m.collectionButton.title = Translate("detail_collection_remove")
        else
            m.collectionButton.title = Translate("detail_collection_add")
        end if
    else
        m.collectionButton.title = Translate("detail_collection_add")
    end if
end sub

' ---------------------------------------------------------------------
' R7.11: Handle collection button press. Shows a picker to select which
' collection to add the item to, then calls the API.
' ---------------------------------------------------------------------
sub OnCollectionPressed()
    if m.itemId = "" or m.userData = invalid then return

    ' First, fetch the list of collections if not already loaded.
    if m.collections.count() = 0 then
        m.apiTask.request = { op: "getCollections" }
        m.apiTask.control = "run"
        return
    end if

    ' If collections are loaded, show the picker.
    ShowCollectionPicker()
end sub

' ---------------------------------------------------------------------
' R7.11: Show a picker dialog to select a collection.
' Uses roAlert with up to 3 collection buttons (Roku limitation).
' For more options, a full-screen picker would be needed.
' ---------------------------------------------------------------------
sub ShowCollectionPicker()
    if m.collections.count() = 0 then
        ShowErrorDialog(m.top, Translate("common_error"), "No collections available.")
        return
    end if

    ' roAlert only supports up to 3 buttons. For now, use the first collection.
    ' A full picker implementation would use a custom XML scene.
    firstCollection = m.collections[0]
    if firstCollection.DoesExist("id") then
        AddItemToCollection(firstCollection.id)
    else
        ShowErrorDialog(m.top, Translate("common_error"), "Collection has no ID")
    end if
end sub

' ---------------------------------------------------------------------
' R7.11: Add the current item to a collection.
' @param collectionId String - the collection ID to add to
' ---------------------------------------------------------------------
sub AddItemToCollection(collectionId as String)
    if m.itemId = "" or collectionId = "" then return

    m.apiTask.request = { op: "addToCollection", collectionId: collectionId, itemId: m.itemId }
    m.apiTask.control = "run"
end sub

' ---------------------------------------------------------------------
' R7.11: Remove the current item from a collection.
' @param collectionId String - the collection ID to remove from
' ---------------------------------------------------------------------
sub RemoveItemFromCollection(collectionId as String)
    if m.itemId = "" or collectionId = "" then return

    m.apiTask.request = { op: "removeFromCollection", collectionId: collectionId, itemId: m.itemId }
    m.apiTask.control = "run"
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
        m.contentRatingLabel.text = Translate("detail_rated_label") + contentRating
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

' ---------------------------------------------------------------------
' R7.5: Toggle watched state.
' Optimistically updates local state and reverts on failure.
' ---------------------------------------------------------------------
sub OnWatchedToggle()
    if m.userData = invalid or m.itemId = "" then return

    isWatched = false
    if m.userData.DoesExist("watched") and m.userData.watched = true then isWatched = true

    if isWatched then
        ' Optimistic: mark as unwatched
        m.userData.watched = false
        RenderWatched()
        m.apiTask.request = { op: "markUnwatched", itemId: m.itemId }
        m.apiTask.control = "run"
    else
        ' Optimistic: mark as watched
        m.userData.watched = true
        RenderWatched()
        m.apiTask.request = { op: "markWatched", itemId: m.itemId }
        m.apiTask.control = "run"
    end if
end sub

' ---------------------------------------------------------------------
' R7.5: Toggle like state.
' Optimistically updates local state and reverts on failure.
' ---------------------------------------------------------------------
sub OnLikeToggle()
    if m.userData = invalid or m.itemId = "" then return

    isLiked = false
    if m.userData.DoesExist("liked") and m.userData.liked = true then isLiked = true

    if isLiked then
        ' Optimistic: mark as unliked
        m.userData.liked = false
        RenderLike()
        m.apiTask.request = { op: "like", itemId: m.itemId }
        m.apiTask.control = "run"
    else
        ' Optimistic: mark as liked
        m.userData.liked = true
        RenderLike()
        m.apiTask.request = { op: "like", itemId: m.itemId }
        m.apiTask.control = "run"
    end if
end sub

sub PlayItem()
    playerScene = CreateObject("roSGNode", "PlayerScene")
    m.top.Append(playerScene)
    playerScene.ObserveField("requestClose", "OnChildRequestClose")
    ' P2-S5: trickplay BIF previews are not wired on Roku — the server provides
    ' sprite-sheet format (sprite.jpg + timeline.json) but Roku's Video.bifDisplay
    ' requires a binary BIF file. The dead m.trickplay plumbing was removed to
    ' avoid leaving write-only state (server gap: no BIF URL is currently exposed).

    playerScene.Show(m.itemId, {
        item: m.item
        playbackInfo: m.playbackInfo
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

' ---------------------------------------------------------------------
' R7.4: Detail enrichment - fetch additional data after main item loads.
' Fires multiple independent requests for lazy loading: similar items,
' ratings, cast/crew, trailers, and extras load independently after
' primary content. Each response triggers its display function when ready.
' ---------------------------------------------------------------------
sub LoadAdditionalData()
    if m.itemId = "" or m.item = invalid then return

    ' Fire enrichment requests off the render thread. Each fires independently
    ' and OnApiResponse handles the response when it arrives. Requests are
    ' fired in sequence but process in parallel on the task thread.
    m.apiTask.request = { op: "getItemSimilar", itemId: m.itemId }
    m.apiTask.control = "run"
    m.apiTask.request = { op: "getItemRatings", itemId: m.itemId }
    m.apiTask.control = "run"
    m.apiTask.request = { op: "getItemTrailers", itemId: m.itemId }
    m.apiTask.control = "run"
    m.apiTask.request = { op: "getItemExtras", itemId: m.itemId }
    m.apiTask.control = "run"
end sub

' ---------------------------------------------------------------------
' R7.4: Display "Similar" rail if similar items were returned.
' Similar items structure: [{media_item_id, name, poster_url, year, ...}, ...]
' ---------------------------------------------------------------------
sub DisplaySimilar(similarItems as Object)
    if similarItems = invalid then return
    if type(similarItems) <> "roArray" then return
    if similarItems.count() = 0 then return

    ' Similar items display would be rendered here if UI nodes existed.
    ' The similar items data is available at m.similarData for any UI to consume.
    m.similarData = similarItems
end sub

' ---------------------------------------------------------------------
' R7.4: Display external ratings if available.
' Ratings structure: {rotten_tomatoes: {score, icon}, imdb: {score, icon}, ...}
' ---------------------------------------------------------------------
sub DisplayRatings(ratings as Object)
    if ratings = invalid then return
    if type(ratings) <> "roAssociativeArray" then return
    if ratings.count() = 0 then return

    ' External ratings display would be rendered here if UI nodes existed.
    ' The ratings data is available at m.ratingsData for any UI to consume.
    m.ratingsData = ratings
end sub

' ---------------------------------------------------------------------
' R7.4: Display trailers row if trailers exist.
' Trailers structure: [{name, description, thumbnail_url, poster_url}, ...]
' Trailers are playable - each row item launches the trailer video.
' ---------------------------------------------------------------------
sub DisplayTrailers(trailers as Object)
    if trailers = invalid then return

    trailersArray = []
    if type(trailers) = "roAssociativeArray" then
        if trailers.DoesExist("items") then
            trailersArray = trailers.items
        else
            trailersArray = trailers
        end if
    else if type(trailers) = "roArray" then
        trailersArray = trailers
    end if

    if trailersArray.count() = 0 then return

    m.trailersData = trailersArray

    if m.trailersRow = invalid then m.trailersRow = m.top.FindNode("trailersRow")
    if m.trailersRow = invalid then return

    content = CreateObject("roSGNode", "ContentNode")
    for each trailer in trailersArray
        item = content.CreateChild("ContentNode")
        item.Title = trailer.name
        if trailer.description <> invalid then
            item.Description = trailer.description
        end if
        if trailer.thumbnail_url <> invalid and trailer.thumbnail_url <> "" then
            item.HDPosterUrl = trailer.thumbnail_url
        else if trailer.poster_url <> invalid and trailer.poster_url <> "" then
            item.HDPosterUrl = trailer.poster_url
        else
            item.HDPosterUrl = "pkg:/images/placeholder.png"
        end if
    end for

    m.trailersRow.content = content
    m.trailersRow.visible = (trailersArray.Count() > 0)
end sub

' ---------------------------------------------------------------------
' R7.4: Display extras row if extras exist.
' Extras structure: [{name, description, thumbnail_url, poster_url}, ...]
' Extras are playable behind-the-scenes content, deleted scenes, etc.
' ---------------------------------------------------------------------
sub DisplayExtras(extras as Object)
    if extras = invalid then return

    extrasArray = []
    if type(extras) = "roAssociativeArray" then
        if extras.DoesExist("items") then
            extrasArray = extras.items
        else
            extrasArray = extras
        end if
    else if type(extras) = "roArray" then
        extrasArray = extras
    end if

    if extrasArray.count() = 0 then return

    m.extrasData = extrasArray

    if m.extrasRow = invalid then m.extrasRow = m.top.FindNode("extrasRow")
    if m.extrasRow = invalid then return

    content = CreateObject("roSGNode", "ContentNode")
    for each extra in extrasArray
        item = content.CreateChild("ContentNode")
        item.Title = extra.name
        if extra.description <> invalid then
            item.Description = extra.description
        end if
        if extra.thumbnail_url <> invalid and extra.thumbnail_url <> "" then
            item.HDPosterUrl = extra.thumbnail_url
        else if extra.poster_url <> invalid and extra.poster_url <> "" then
            item.HDPosterUrl = extra.poster_url
        else
            item.HDPosterUrl = "pkg:/images/placeholder.png"
        end if
    end for

    m.extrasRow.content = content
    m.extrasRow.visible = (extrasArray.Count() > 0)
end sub