' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/DetailScene.brs

' copyright 2026 Joe Huss
'


sub Init()
    ApplyXmlChrome()
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
    m.fetchSpinner = m.top.FindNode("fetchSpinner")
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

    ' [review roku__gameux CR-1] "More Like This" overlay wiring: selection is
    ' index-keyed into m.similarItems (the SearchScene results[] idiom), and
    ' the panel is entered ONLY through the OnActionDown ladder once it has
    ' content — visible is false until then, so no phantom focus stop exists.
    m.similarGrid = m.top.FindNode("similarGrid")
    m.similarPanel = m.top.FindNode("similarPanel")
    m.similarItems = []
    if m.similarGrid <> invalid then
        m.similarGrid.ObserveField("itemSelected", "OnSimilarSelected")
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
    ' works); "favorite"/"rating" = a strip button is focused; "similar" = the
    ' "More Like This" overlay grid holds focus [CR-1].
    m.actionFocus = "none"
    m.pendingRating = 0
    m.userData = invalid

    ' R7.11: Collections state - list of available collections.
    m.collections = []

    ' [W-min93 M-ROKU-22/23, review roku__exploiter m1/m2] In-flight guards —
    ' the ParentalControlsScene m.pendingOp serialization idiom at the detail
    ' surface. m.playPending: a Play press while getItemPlaybackInfo is
    ' outstanding is ignored (was: N concurrent PlayerScene instances, N
    ' stream sessions, self-inflicted 429s). m.mutationPending: at most one
    ' favorite/rating/watched/like/collection mutation in flight; presses
    ' during the window are ignored instead of bursting requests and racing
    ' the revert-on-failure flips against a single shared apiTask stream.
    m.playPending = false
    m.mutationPending = false

    ' [MJ-1] Resume position for this item, in seconds, fetched once at load
    ' from the continue-watching feed (the only wire source of a per-item
    ' bookmark) and handed to PlayerScene.Show. Stays 0.0 when the item is
    ' not in the feed -> playback starts from the beginning, as before.
    m.resumeSeconds = 0.0
end sub

' Single serialization point for every detail-page mutation (see guards in
' Init). [W-min93 M-ROKU-23]
sub SendMutation(request as Object)
    if m.mutationPending then return
    m.mutationPending = true
    m.apiTask.request = request
    m.apiTask.control = "run"
end sub

' Release the mutation guard when the owning response lands (success OR
' failure — the arms below keep their own revert logic). [W-min93 M-ROKU-23]
sub EndMutation()
    m.mutationPending = false
end sub

sub LoadItem(itemId as String)
    m.itemId = itemId

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
    end if
    if m.fetchSpinner <> invalid then m.fetchSpinner.visible = true

    m.apiTask.request = { op: "getItem", itemId: itemId }
    m.apiTask.control = "run"

    ' [MJ-1] Parallel one-shot resume lookup on an ad-hoc task node (the
    ' HomeScene deferred-rail shape: fresh node per call, firmware-read state
    ' before control): the shared m.apiTask stays dedicated to the
    ' mutation/playback chain (W-min93 serialization law), and ApiTask's
    ' GET:/me/continue-watching cache usually serves this from the rail fetch
    ' that just happened - no extra network in the common path.
    LoadResumePosition()
end sub

' [MJ-1] The resume position reaches the detail page only through the
' continue-watching feed: the server exposes no per-item bookmark route
' (WatchHistory::getResumePosition has no HTTP surface), so the shipped list
' is queried once per load and matched by media_item_id here.
sub LoadResumePosition()
    task = CreateObject("roSGNode", "ApiTask")
    task.ObserveField("response", "OnApiResponse")
    task.request = { op: "getContinueWatching" }
    task.control = "run"
end sub

' [MJ-1] Pull this item's resume offset out of the continue-watching rows.
' Rows carry media_item_id + position_ticks (100ns units - the same
' convention HomeScene's rails divide by 10_000_000 for). A failed lookup is
' DEGRADED silently and on purpose (start at 0): resume is an enhancement
' and must never block, error or double-fire the Play button.
sub ApplyResumeFromContinueWatching(resp as Object)
    if resp = invalid or not resp.ok or resp.data = invalid then return
    items = invalid
    if type(resp.data) = "roAssociativeArray" and resp.data.DoesExist("items") then
        items = resp.data.items
    end if
    if items = invalid or type(items) <> "roArray" then return
    for each cw in items
        if cw <> invalid and type(cw) = "roAssociativeArray" then
            if cw.DoesExist("media_item_id") and cw.media_item_id = m.itemId then
                if cw.DoesExist("position_ticks") then
                    ' Numeric lift per the repo's boxed-type idiom (JSON numbers
                    ' arrive as roInteger/roLongInteger/roDouble; hand-built
                    ' assocarrays in unit paths carry the intrinsic names).
                    ticksType = type(cw.position_ticks)
                    if ticksType = "Integer" or ticksType = "roInt" or ticksType = "LongInteger" or ticksType = "roLongInteger" or ticksType = "Float" or ticksType = "roFloat" or ticksType = "Double" or ticksType = "roDouble" then
                        if cw.position_ticks > 0 then
                            m.resumeSeconds = cw.position_ticks / 10000000.0
                        end if
                    end if
                end if
            end if
        end if
    end for
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getItem" then
        if not resp.ok or resp.data = invalid then
            ' MN-10: failure must retract the cue too, or the detail pane
            ' sits at "Loading" forever once the default-visible flicker
            ' is gone — the strand was pre-existing, the cure makes it
            ' impossible rather than merely rarer.
            if m.loadingLabel <> invalid then m.loadingLabel.visible = false
            if m.fetchSpinner <> invalid then m.fetchSpinner.visible = false
            return
        end if

        ' Hide loading indicator.
        if m.loadingLabel <> invalid then
            m.loadingLabel.visible = false
        end if
        if m.fetchSpinner <> invalid then m.fetchSpinner.visible = false

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
        m.playPending = false
        ' MN-1: retract the cue. PlayItem() below normally transitions away;
        ' the restore keeps the swap honest if this scene survives the answer.
        if m.playButton <> invalid then m.playButton.title = Translate("common_play")
        ' Markers/chapters may legitimately be empty; launch the player either way.
        if resp.ok then
            m.playbackInfo = resp.data
        else
            m.playbackInfo = invalid
        end if
        PlayItem()
    else if resp.op = "favorite" then
        EndMutation()
        ' Optimistic flip already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.favorite = false
                RenderFavorite()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_favorite_save_message"))
        end if
    else if resp.op = "unfavorite" then
        EndMutation()
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.favorite = true
                RenderFavorite()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_favorite_remove_message"))
        end if
    else if resp.op = "setRating" then
        EndMutation()
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
        EndMutation()
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
        EndMutation()
        ' Optimistic update already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.watched = false
                RenderWatched()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_watched_mark_message"))
        end if
    else if resp.op = "markUnwatched" then
        EndMutation()
        ' Optimistic update already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.watched = true
                RenderWatched()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_error_watched_unmark_message"))
        end if
    else if resp.op = "like" then
        EndMutation()
        ' Optimistic update already applied; revert on failure.
        if not resp.ok then
            if m.userData <> invalid then
                m.userData.liked = not m.userData.liked
                RenderLike()
            end if
            ShowErrorDialog(m.top, Translate("common_error"), GetErrorMessage(resp.error))
        end if
    else if resp.op = "getItemSimilar" then
        ' R7.4: "More Like This" enrichment — the one enrichment wire that is
        ' both live (WebPortalRouter /media/{id}/similar) AND playable on this
        ' platform (the items are media items; selecting one re-enters
        ' DetailScene). Trailers/extras/cast/crew fetches were removed with
        ' CR-1: no HTTP-playable url shape, cast/crew no route at all.
        if resp.ok and resp.data <> invalid then
            similarItems = invalid
            if type(resp.data) = "roAssociativeArray" then
                if resp.data.DoesExist("items") then
                    similarItems = resp.data.items
                else
                    similarItems = resp.data
                end if
            end if
            DisplaySimilar(similarItems)
        end if
    else if resp.op = "getCollections" then
        EndMutation()
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
        EndMutation()
        if not resp.ok then
            ShowErrorDialog(m.top, Translate("common_error"), GetErrorMessage(resp.error))
        end if
    else if resp.op = "removeFromCollection" then
        EndMutation()
        if not resp.ok then
            ShowErrorDialog(m.top, Translate("common_error"), GetErrorMessage(resp.error))
        end if
    else if resp.op = "getContinueWatching" then
        ' [MJ-1] Reply of the LoadResumePosition one-shot lookup: it rides its
        ' own task node but the same op-multiplexed observer, so the file's
        ' single-response-handler shape is preserved.
        ApplyResumeFromContinueWatching(resp)
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
            info = info + TranslateWithParams("detail_chapters_count", { count: item.chapters.count() })
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
        m.ratingButton.title = TranslateWithParams("detail_rating_label", { rating: m.pendingRating })
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
    if m.mutationPending then return

    ' First, fetch the list of collections if not already loaded.
    if m.collections.count() = 0 then
        SendMutation({ op: "getCollections" })
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
        ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_no_collections_available"))
        return
    end if

    ' roAlert only supports up to 3 buttons. For now, use the first collection.
    ' A full picker implementation would use a custom XML scene.
    firstCollection = m.collections[0]
    if firstCollection.DoesExist("id") then
        AddItemToCollection(firstCollection.id)
    else
        ShowErrorDialog(m.top, Translate("common_error"), Translate("detail_collection_no_id"))
    end if
end sub

' ---------------------------------------------------------------------
' R7.11: Add the current item to a collection.
' @param collectionId String - the collection ID to add to
' ---------------------------------------------------------------------
sub AddItemToCollection(collectionId as String)
    if m.itemId = "" or collectionId = "" then return

    SendMutation({ op: "addToCollection", collectionId: collectionId, itemId: m.itemId })
end sub

' ---------------------------------------------------------------------
' R7.11: Remove the current item from a collection.
' @param collectionId String - the collection ID to remove from
' ---------------------------------------------------------------------
sub RemoveItemFromCollection(collectionId as String)
    if m.itemId = "" or collectionId = "" then return

    SendMutation({ op: "removeFromCollection", collectionId: collectionId, itemId: m.itemId })
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
        m.contentRatingLabel.text = TranslateWithParams("detail_rated_label", { rating: contentRating })
    else
        m.contentRatingLabel.text = ""
    end if
end sub

sub OnBackPressed()
    m.top.requestClose = true
end sub

sub OnPlayPressed()
    if m.itemId = "" or m.item = invalid then return

    ' [W-min93 M-ROKU-22] One playback request at a time: a press while the
    ' playback-info read is outstanding is ignored (the flag clears in the
    ' response arm, and a failed launch never leaves it stuck because the arm
    ' runs for ok AND error envelopes).
    if m.playPending then return

    ' Only playable leaf types have a stream to request. This mirrors the
    ' play-button visibility gate above, so Play is never a silent no-op for an
    ' item whose button we chose to show.
    if IsPlayableItem(m.item) then
        m.playPending = true
        ' MN-1: the playback-info fetch is a network round-trip and repeat
        ' presses are gated off above - the button was a silent no-op for its
        ' whole latency. Swap the label to the shipped loading copy (the
        ' CHECK58 sole-writer law is about the DESCRIPTION strip; this is the
        ' button's own title).
        if m.playButton <> invalid then m.playButton.title = Translate("common_loading")
        m.apiTask.request = { op: "getItemPlaybackInfo", itemId: m.itemId }
        m.apiTask.control = "run"
    end if
end sub

sub OnFavoriteToggle()
    if m.userData = invalid or m.itemId = "" then return
    if m.mutationPending then return

    isFav = false
    if m.userData.DoesExist("favorite") and m.userData.favorite = true then isFav = true

    if isFav then
        ' Optimistic: clear locally, fire unfavorite; revert on failure.
        m.userData.favorite = false
        RenderFavorite()
        SendMutation({ op: "unfavorite", itemId: m.itemId })
    else
        m.userData.favorite = true
        RenderFavorite()
        SendMutation({ op: "favorite", itemId: m.itemId })
    end if
end sub

sub OnRatingCommit()
    if m.userData = invalid or m.itemId = "" then return
    if m.mutationPending then return

    if m.pendingRating <= 0 then
        ' 0 = clear the rating.
        m.userData.rating = invalid
        RenderRating()
        SendMutation({ op: "clearRating", itemId: m.itemId })
    else
        m.userData.rating = m.pendingRating
        RenderRating()
        SendMutation({ op: "setRating", itemId: m.itemId, rating: m.pendingRating })
    end if
end sub

' ---------------------------------------------------------------------
' R7.5: Toggle watched state.
' Optimistically updates local state and reverts on failure.
' ---------------------------------------------------------------------
sub OnWatchedToggle()
    if m.userData = invalid or m.itemId = "" then return
    if m.mutationPending then return

    isWatched = false
    if m.userData.DoesExist("watched") and m.userData.watched = true then isWatched = true

    if isWatched then
        ' Optimistic: mark as unwatched
        m.userData.watched = false
        RenderWatched()
        SendMutation({ op: "markUnwatched", itemId: m.itemId })
    else
        ' Optimistic: mark as watched
        m.userData.watched = true
        RenderWatched()
        SendMutation({ op: "markWatched", itemId: m.itemId })
    end if
end sub

' ---------------------------------------------------------------------
' R7.5: Toggle like state.
' Optimistically updates local state and reverts on failure.
' ---------------------------------------------------------------------
sub OnLikeToggle()
    if m.userData = invalid or m.itemId = "" then return
    if m.mutationPending then return

    isLiked = false
    if m.userData.DoesExist("liked") and m.userData.liked = true then isLiked = true

    if isLiked then
        ' Optimistic: mark as unliked
        m.userData.liked = false
        RenderLike()
        SendMutation({ op: "like", itemId: m.itemId })
    else
        ' Optimistic: mark as liked
        m.userData.liked = true
        RenderLike()
        SendMutation({ op: "like", itemId: m.itemId })
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
        ' [MJ-1] Thread the load-time resume offset straight through - same
        ' field name and seconds unit the HomeScene continue rail uses; 0
        ' when the item carries no bookmark (unchanged behavior).
        resumeSeconds: m.resumeSeconds
    })
end sub

' requestClose contract (docs/navigation.md): the OBSERVING parent removes the
' child that raised the signal and takes focus back - the mirror of
' PhlixApp.PopScreen. The old one-line bubble re-set this scene's own
' requestClose, a signal that dies below HomeScene, leaving Back a silent
' no-op on the Home-opened screens [review roku__casualgamer C1].
' PopScreen tolerates its pre-removal unobserve because its removal runs
' in the very arm doing the unobserving - pruning can never roll back an
' already-committed RemoveChild. These handlers run INSIDE the child's
' requestClose dispatch, and a scene must never unobserve the field from
' an arm registered before its parent's (its own Teardown): the parent's
' removal arm could be pruned mid-dispatch (C03-r2; CHECK27 R6). A
' detached child's observers are freed with its subtree anyway.
sub OnChildRequestClose(event as Object)
    child = event.GetNode()
    if child = invalid or child.GetParent() <> m.top then return
    m.top.RemoveChild(child)
    m.top.SetFocus(true)
    ' [CR-1] Coming back from a "More Like This" child detail: the panel this
    ' grid lives in is still open, so hand focus back where the user was
    ' instead of the bare scene (the overlay's only stop is the grid).
    if m.actionFocus = "similar" and m.similarGrid <> invalid then
        m.similarGrid.SetFocus(true)
    end if
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            ' [CR-1] Back inside the enrichment overlay closes the overlay,
            ' not the scene — the panel is a mode of this page, and leaving
            ' detail because a user backed out of "More Like This" is the
            ' two-backs-for-one-exit trap the grid would otherwise create.
            if m.actionFocus = "similar" then
                CloseSimilarPanel()
                handled = true
            else
                m.top.requestClose = true
                handled = true
            end if
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

' Move focus DOWN through the actions strip: scene -> favorite -> rating ->
' "More Like This" grid (only once it has content — empty = no stop exists).
' [review roku__gameux CR-1] The terminal stop is the enrichment overlay; the
' old rows sat below this ladder's reach AND below the canvas - both gone.
function OnActionDown() as Boolean
    if m.actionFocus = "none" then
        if m.favoriteButton <> invalid and m.favoriteButton.visible then
            m.favoriteButton.SetFocus(true)
            m.actionFocus = "favorite"
            return true
        end if
        ' No favorite stop (unauthenticated / store unwired): fall through to
        ' rating, then the grid, so Down is never a dead end when targets exist.
        if m.ratingButton <> invalid and m.ratingButton.visible then
            m.ratingButton.SetFocus(true)
            m.actionFocus = "rating"
            return true
        end if
        return OpenSimilarPanel()
    else if m.actionFocus = "favorite" then
        if m.ratingButton <> invalid and m.ratingButton.visible then
            m.ratingButton.SetFocus(true)
            m.actionFocus = "rating"
            return true
        end if
        return OpenSimilarPanel()
    else if m.actionFocus = "rating" then
        return OpenSimilarPanel()
    end if
    return false
end function

' Move focus UP through the actions strip: grid -> rating -> favorite -> scene.
function OnActionUp() as Boolean
    if m.actionFocus = "similar" then
        CloseSimilarPanel()
        return true
    else if m.actionFocus = "rating" then
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

' Enter the "More Like This" overlay. Honest Boolean: the stop exists only
' when the similar fetch landed content — callers treat false as "Down is a
' wall here", never as failure. The opaque Rectangle already covers the page
' chrome; focus lands on the grid itself (index 0 default on first SetFocus).
function OpenSimilarPanel() as Boolean
    if m.similarPanel = invalid or m.similarGrid = invalid then return false
    if m.similarItems.Count() = 0 then return false

    m.similarPanel.visible = true
    m.similarGrid.SetFocus(true)
    m.actionFocus = "similar"
    return true
end function

' Leave the overlay: hide the panel, restore the scene. The grid keeps its
' last selection index, so re-entering lands where the user left off.
sub CloseSimilarPanel()
    if m.similarPanel <> invalid then m.similarPanel.visible = false
    m.actionFocus = "none"
    m.top.SetFocus(true)
end sub

' ---------------------------------------------------------------------
' R7.4: Detail enrichment - fetch additional data after main item loads.
' [review roku__gameux CR-1] This used to fire FOUR requests back-to-back
' (similar, ratings, trailers, extras) by re-setting m.apiTask.request and
' control="run" four times — on one serialized task node, so the later runs
' raced the earlier ones, and three of the four fed display code written
' against fabricated response shapes (cast/crew never had a route; trailers
' and extras ship TMDB YouTube links / local file paths, which Roku Video
' cannot play; the ratings fetch had no UI consumer). Only the similar wire
' is both live and actionable on this platform, so it is the only fetch
' that survives.
' ---------------------------------------------------------------------
sub LoadAdditionalData()
    if m.itemId = "" or m.item = invalid then return

    m.apiTask.request = { op: "getItemSimilar", itemId: m.itemId }
    m.apiTask.control = "run"
end sub

' ---------------------------------------------------------------------
' R7.4: Render the "More Like This" overlay from the /similar response.
' Similar items structure (server getSimilarItems): [{id, title, posterUrl,
' year, score, reason}, ...]. [review roku__gameux CR-1] This used to be a
' no-op that only parked the array on m.similarData ("displayed if UI nodes
' existed" - none ever did, and the Row chrome that did exist was off-canvas
' and unreachable); the cast/ratings/trailers/extras siblings that shared
' this fetch were dead chrome over fabricated response shapes and are gone.
' Now it actually feeds the PosterGrid the scene ships, so the enrichment is
' real and reachable.
' ---------------------------------------------------------------------
sub DisplaySimilar(similarItems as Object)
    if similarItems = invalid then return
    if type(similarItems) <> "roArray" then return
    if similarItems.count() = 0 then return
    if m.similarGrid = invalid then return

    m.similarItems = similarItems

    content = CreateObject("roSGNode", "ContentNode")
    for each sim in similarItems
        if type(sim) = "roAssociativeArray" then
            node = content.CreateChild("ContentNode")
            if sim.title <> invalid then node.Title = sim.title
            if sim.title <> invalid then node.accessibleLabel = sim.title
            if sim.posterUrl <> invalid and sim.posterUrl <> "" then
                node.HDPosterUrl = sim.posterUrl
            else
                node.HDPosterUrl = "pkg:/images/placeholder.png"
            end if
            ' Same numeric-year idiom as RenderItem above (str().trim()).
            if sim.year <> invalid and type(sim.year) = "Int" then
                node.ShortDescriptionLine1 = str(sim.year).trim()
            end if
        end if
    end for

    m.similarGrid.content = content
end sub

' Grid selection carries the focused index; resolve it back to the similar
' item's media id and open a fresh DetailScene child (the child-scene +
' OnChildRequestClose idiom this scene already uses for PlayerScene).
sub OnSimilarSelected(event as Object)
    index = event.getData()
    if index < 0 or index >= m.similarItems.Count() then return

    sim = m.similarItems[index]
    if sim = invalid or type(sim) <> "roAssociativeArray" then return

    mediaId = sim.id
    if mediaId = invalid or mediaId = "" then return

    child = CreateObject("roSGNode", "DetailScene")
    m.top.Append(child)
    child.ObserveField("requestClose", "OnChildRequestClose")
    child.LoadItem(mediaId)
end sub

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("backButton")
    if n <> invalid then n.title = Translate("common_back")
    n = m.top.findNode("playButton")
    if n <> invalid then n.title = Translate("common_play")
    n = m.top.findNode("loadingLabel")
    if n <> invalid then n.text = Translate("common_loading")
end sub
