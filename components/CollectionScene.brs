'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/CollectionScene.brs

' copyright 2026 Joe Huss
'

'
' A single collection's items as a one-shot PosterGrid. Mirrors LibraryScene's
' grid build + LoadX interface fn, and FavoritesScene's type-routed selection +
' Teardown. CollectionsScene creates + appends this scene and calls the
' LoadCollection interface fn, so it HAS an <interface><function
' name="LoadCollection"/>.
'
' CARDINAL LANDMINE: GET /collections/{id} returns items as RAW DB rows (NOT
' MediaItemShaper-shaped): id/name/type are top-level but poster_url/overview/year
' live under metadata.*. Each row is flattened via NormalizeCollectionItem before
' it feeds the grid. `type` stays top-level so routing works:
'   series  -> SeriesScene (LoadSeries)
'   season  -> SeasonScene (LoadSeason)
'   else    -> DetailScene (LoadItem)   (every other media_items.type:
'                                        movie/episode/video/audio/track/
'                                        music/album/artist/book/photo/
'                                        audiobook -- note `photo`, there
'                                        is no `image` member)

sub Init()
    ApplyXmlChrome()
    m.top.SetFocus(true)

    ' Items grid.
    m.itemsGrid = m.top.FindNode("itemsGrid")
    if m.itemsGrid <> invalid then
        m.itemsGrid.ObserveField("itemSelected", "OnItemSelected")
        m.itemsGrid.ObserveField("itemFocused", "OnItemFocused")
    end if

    ' UI nodes.
    m.backButton = m.top.FindNode("backButton")
    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    ' RT-094: focusable retry for the failure arm (HomeScene exemplar);
    ' its title localizes through ApplyXmlChrome via common_retry (CHECK25).
    m.retryButton = m.top.FindNode("retryButton")
    if m.retryButton <> invalid then
        m.retryButton.ObserveField("buttonSelected", "OnCollectionRetryPressed")
    end if

    m.titleLabel = m.top.FindNode("titleLabel")
    m.descriptionLabel = m.top.FindNode("descriptionLabel")
    m.loadingLabel = m.top.FindNode("loadingLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.collectionId = ""
    m.collectionName = ""
    m.items = []

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")
end sub

' Interface fn: load + render the given collection's items. CollectionsScene
' calls this right after Append. collectionName fills the header title.
sub LoadCollection(collectionId as String, collectionName as String)
    ' [RT-093 W16L5, review roku__exploiter #2] Entry choke, the LoadItem
    ' precedent: collection ids are server returns (CollectionsScene rows,
    ' the deep-link answer), and this one assignment is where they become
    ' the /collections/ path segment for every later fetch. Refusal keeps
    ' m.collectionId at "" — the existing empty-guard below makes the whole
    ' loader inert (no request is ever built from a refused id).
    if not IsSafeContentId(collectionId) then
        print "CollectionScene: LoadCollection refused a malformed id"
        return
    end if

    m.collectionId = collectionId
    ' RT-094: retry re-fires this very load, so the name rides along.
    m.collectionName = collectionName

    if m.titleLabel <> invalid then
        name = collectionName
        if name = invalid then name = ""
        m.titleLabel.text = name
    end if

    if m.collectionId = "" then return

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
    end if

    m.apiTask.request = { op: "getCollection", collectionId: m.collectionId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getCollection" then
        ' Hide loading indicator.
        if m.loadingLabel <> invalid then
            m.loadingLabel.visible = false
        end if

        ' RT-094 [w15L9 R-B]: a failed load used to CLEAR the description
        ' strip - indistinguishable from an empty collection. The pure
        ' choke (tests/unit/CollectionSceneRoutines.test.brs; routing
        ' custody CHECK101) now discloses the failure with a retry.
        browseOutcome = CollectionBrowseOutcome(resp.ok = true, resp.data <> invalid and resp.data.items <> invalid and type(resp.data.items) = "roArray")
        if browseOutcome = "collection_failed" then
            m.items = []
            if m.itemsGrid <> invalid then
                m.itemsGrid.content = CreateObject("roSGNode", "ContentNode")
            end if
            if m.descriptionLabel <> invalid then
                m.descriptionLabel.text = Translate("collection_failed")
            end if
            if m.retryButton <> invalid then
                m.retryButton.visible = true
                m.retryButton.SetFocus(true)
            end if
            return
        end if

        ' Normalize each RAW row before it feeds the grid; skip rows with no id.
        m.items = []
        for each raw in resp.data.items
            norm = NormalizeCollectionItem(raw)
            if norm.id <> "" then m.items.Push(norm)
        end for

        content = CreateObject("roSGNode", "ContentNode")
        for each item in m.items
            contentItem = content.AddChild({
                Title: item.name
                accessibleLabel: item.name
                ShortDescriptionLine1: item.name
                Type: item.type
                id: item.id
            })

            if item.overview <> "" then
                contentItem.Description = item.overview
            end if

            if item.year <> invalid then
                yearStr = str(Int(item.year)).trim()
                if yearStr <> "0" then contentItem.ShortDescriptionLine2 = yearStr
            end if

            ' poster_url is an absolute URL (TMDB or local) or empty.
            if item.poster_url <> "" then
                contentItem.HDPosterUrl = item.poster_url
            else
                contentItem.HDPosterUrl = "pkg:/images/placeholder.png"
            end if
        end for

        if m.itemsGrid <> invalid then m.itemsGrid.content = content

        ' RT-094: stand the failure chrome down before the honest
        ' success-empty leg speaks; collection_empty stays a SOLE writer
        ' of the empty verdict over a healthy response.
        if m.retryButton <> invalid then m.retryButton.visible = false
        if m.descriptionLabel <> invalid and m.descriptionLabel.text = Translate("collection_failed") then
            m.descriptionLabel.text = Translate("common_select_item")
        end if

        if m.descriptionLabel <> invalid and m.items.Count() = 0 then
            m.descriptionLabel.text = Translate("collection_empty")
        end if
    end if
end sub

' RT-094: collection failure-vs-usable verdict, pure so the headless suite
' can convict it (same shape law; literal-key dispatch, CHECK20 intact).
function CollectionBrowseOutcome(ok as Boolean, hasItems as Boolean) as String
    if not ok or not hasItems then return "collection_failed"
    return ""
end function

sub OnCollectionRetryPressed()
    if m.retryButton <> invalid then m.retryButton.visible = false
    if m.collectionId <> "" then
        LoadCollection(m.collectionId, m.collectionName)
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    ' [RT-093 W16L5, review roku__exploiter #2] Grid-row ids are server
    ' returns — in hub mode answered by an ARBITRARY federated machine.
    ' Routing them straight through passes the typed ShowSeries/ShowSeason/
    ' ShowItemDetail parameters and onward into every path interpolation
    ' the chain makes. The shape law judges the raw Dynamic HERE, before
    ' the typed boundary. Refusal is the established ignore-posture (print
    ' + return, the OnPendingHubCommand precedent): a hostile row does not
    ' crash the render thread, it simply is not routable.
    if not IsSafeContentId(item.id) then
        print "CollectionScene: ignoring a grid item with a malformed id"
        return
    end if

    ' Items can be any type; route every type sensibly (exactly like Favorites).
    if item.type = "series" then
        ShowSeries(item.id, item.name)
    else if item.type = "season" then
        ShowSeason(item.id, item.name)
    else
        ShowItemDetail(item.id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    if m.descriptionLabel <> invalid then
        if item.overview <> "" then
            m.descriptionLabel.text = item.overview
        else
            m.descriptionLabel.text = item.name
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

' requestClose contract (docs/navigation.md): the OBSERVING parent removes the
' child that raised the signal and takes focus back (mirror of PhlixApp.
' PopScreen). The old bubble-up died below HomeScene - Back was a silent no-op
' on every Home-opened screen [review roku__casualgamer C1]. Init also
' self-observes this handler on m.top: when our OWN requestClose fires, our
' parent owns the removal and we only tear down.
' PopScreen tolerates its pre-removal unobserve because its removal runs
' in the very arm doing the unobserving - pruning can never roll back an
' already-committed RemoveChild. These handlers run INSIDE the child's
' requestClose dispatch, and a scene must never unobserve the field from
' an arm registered before its parent's (its own Teardown): the parent's
' removal arm could be pruned mid-dispatch (C03-r2; CHECK27 R6). A
' detached child's observers are freed with its subtree anyway.
sub OnChildRequestClose(event as Object)
    child = event.GetNode()
    if child = invalid then return
    if child = m.top then
        Teardown()
        return
    end if
    if child.GetParent() <> m.top then return
    m.top.RemoveChild(child)
    m.top.SetFocus(true)
end sub

sub OnBackPressed()
    m.top.requestClose = true
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.itemsGrid <> invalid then
        m.itemsGrid.UnObserveField("itemSelected")
        m.itemsGrid.UnObserveField("itemFocused")
    end if
    if m.backButton <> invalid then
        m.backButton.UnObserveField("buttonSelected")
    end if
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if
    if m.retryButton <> invalid then
        m.retryButton.UnObserveField("buttonSelected")
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

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("backButton")
    if n <> invalid then n.text = Translate("common_back")
    n = m.top.findNode("titleLabel")
    if n <> invalid then n.text = Translate("common_collection")
    n = m.top.findNode("loadingLabel")
    if n <> invalid then n.text = Translate("common_loading")
    n = m.top.findNode("descriptionLabel")
    if n <> invalid then n.text = Translate("common_select_item")
    n = m.top.findNode("retryButton")
    if n <> invalid then n.text = Translate("common_retry")
end sub
