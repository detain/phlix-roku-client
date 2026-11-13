'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/SearchScene.brs

' copyright 2026 Joe Huss
'

'
' Global search screen: an on-screen Keyboard (left) drives a live results
' PosterGrid (right). Mirrors LibraryScene's PosterGrid + ApiTask pattern but
' fires the dedicated `search` op (ApiClient.search -> GET /media?search=<q>,
' NO libraryId/topLevel, so results span every library and CAN include
' season/episode rows). Selecting a result routes exactly like LibraryScene:
'   series  -> SeriesScene
'   season  -> SeasonScene
'   else    -> DetailScene (every other media_items.type: movie/episode/video/
'              audio/track/music/album/artist/book/photo/audiobook -- note
'              `photo`, there is no `image` member)
'
' Query is debounced: a non-repeating ~1s Timer is restarted on each keystroke
' and only fires the search when the trimmed query length is >= 2.

sub Init()
    ApplyXmlChrome()
    m.top.SetFocus(true)

    ' Keyboard (left). Start focus here; observe its text for live queries.
    m.keyboard = m.top.FindNode("keyboard")
    if m.keyboard <> invalid then
        m.keyboard.ObserveField("text", "OnQueryChanged")
        m.keyboard.SetFocus(true)
    end if

    ' Results grid (right).
    m.resultsGrid = m.top.FindNode("resultsGrid")
    if m.resultsGrid <> invalid then
        m.resultsGrid.ObserveField("itemSelected", "OnResultSelected")
        m.resultsGrid.ObserveField("itemFocused", "OnResultFocused")
        m.resultsGrid.ObserveField("visibleRect", "OnGridVisibleRectChange")
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' RT-094: focusable retry for the failure arm (HomeScene exemplar);
    ' its title localizes through ApplyXmlChrome via common_retry (CHECK25).
    m.retryButton = m.top.FindNode("retryButton")
    if m.retryButton <> invalid then
        m.retryButton.ObserveField("buttonSelected", "OnSearchRetryPressed")
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' Debounce timer (render thread). Non-repeating; restarted on each keystroke.
    m.searchTimer = m.top.CreateChild("Timer")
    m.searchTimer.duration = 1
    m.searchTimer.repeat = false
    m.searchTimer.ObserveField("fire", "OnSearchTimerFire")

    m.results = []
    ' Focus zone: "keyboard" or "results".
    m.zone = "keyboard"

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")

    ' Paging state for infinite scroll (R5.2)
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)

    if m.statusLabel <> invalid then
        m.statusLabel.text = Translate("search_hint")
    end if

    ' R5.2: Generation counter to discard stale (out-of-order) responses.
    m.searchGen = 0
end sub

' Keyboard text changed: debounce a search, or clear when the query is too short.
sub OnQueryChanged(event as Object)
    query = event.getData()
    if query = invalid then query = ""
    trimmed = query.trim()

    if Len(trimmed) < 2 then
        ' Too short: stop any pending search and clear the grid.
        m.searchTimer.control = "stop"
        m.results = []
        m.contentNode = invalid
        m.hasMore = false
        m.loadingPage = false
        if m.resultsGrid <> invalid then
            m.resultsGrid.content = CreateObject("roSGNode", "ContentNode")
        end if
        if m.statusLabel <> invalid then
            m.statusLabel.text = Translate("search_hint")
        end if
        return
    end if

    ' Debounce: restart the non-repeating timer; the search fires on its `fire`.
    m.searchTimer.control = "stop"
    m.searchTimer.control = "start"
end sub

' Timer fired: run the search for the current keyboard text.
sub OnSearchTimerFire(event as Object)
    if m.keyboard = invalid then return

    query = m.keyboard.text
    if query = invalid then query = ""
    if Len(query.trim()) < 2 then return

    ' Reset paging state for fresh search
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.results = []
    m.contentNode = invalid

    ' RT-005: a request is still in flight. This handler runs FROM the
    ' one-shot timer, which is already consumed - dropping the query here
    ' would leave the newest keyboard text unsearched until some later
    ' keystroke happened to arm it again. Re-arm the debounce instead: the
    ' guard self-heals, and the search for the latest text always runs.
    if m.apiTask.state = "run" then
        m.searchTimer.control = "stop"
        m.searchTimer.control = "start"
        return
    end if

    ' R5.2: Increment generation counter so stale responses are discarded.
    m.searchGen = m.searchGen + 1

    m.apiTask.request = {
        op: "search"
        query: query
        options: { limit: m.limit, offset: m.offset }
        searchGen: m.searchGen
    }
    m.apiTask.control = "run"
end sub

' Load next page of items. Guard prevents concurrent page requests.
sub LoadMoreItems()
    ' Guard: do not run two page requests at once
    if m.loadingPage then return
    if not m.hasMore then return

    if m.keyboard = invalid then return
    query = m.keyboard.text
    if query = invalid or Len(query.trim()) < 2 then return

    ' RT-049 [W14L1, review roku__gameux #5]: the busy check used to run
    ' AFTER the flag was raised, so a page request attempted while the
    ' shared apiTask still ran a search set loadingPage=true, returned
    ' without issuing anything, and NOTHING ever cleared the flag again
    ' (OnApiResponse clears it only when a response for this generation
    ' lands). Every later prefetch was then locked out by the guard above:
    ' the lost page. The check now precedes the flag — busy means "retry
    ' on the next key event", and the flag keeps its honest meaning: a
    ' page request is genuinely outstanding. (RT-005 healed the debounced
    ' search leg; this is the distinct pagination leg.)
    if m.apiTask.state = "run" then return

    m.loadingPage = true

    ' R5.2: Capture current generation so stale page responses are discarded
    ' if a new search fires before this page loads.
    currentGen = m.searchGen

    m.apiTask.request = {
        op: "search"
        query: query
        options: { limit: m.limit, offset: m.offset }
        searchGen: currentGen
    }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "search" then
        ' R5.2: Discard stale response if generation counter has advanced.
        if resp.searchGen <> invalid and resp.searchGen <> m.searchGen then
            return
        end if

        ' Hide loading indicator.
        if m.statusLabel <> invalid and m.loadingPage then
            m.statusLabel.text = ""
        end if

        ' RT-094 [w15L9 R-B]: a failed search used to render "No results" -
        ' the same emptiness-over-dead-server class as FavoritesScene. The
        ' pure choke (tests/unit/SearchSceneRoutines.test.brs) owns the
        ' verdict; CHECK101 pins the routing.
        browseOutcome = SearchBrowseOutcome(resp.ok = true, resp.data <> invalid and resp.data.items <> invalid)
        if browseOutcome = "search_failed" then
            m.results = []
            if m.resultsGrid <> invalid then
                m.resultsGrid.content = CreateObject("roSGNode", "ContentNode")
            end if
            if m.statusLabel <> invalid and not m.loadingPage then
                m.statusLabel.text = Translate("search_failed")
            end if
            if m.retryButton <> invalid and not m.loadingPage then
                m.retryButton.visible = true
                m.retryButton.SetFocus(true)
            end if
            m.loadingPage = false
            m.hasMore = false
            return
        end if

        newItems = resp.data.items
        itemCount = newItems.count()

        ' First page: create ContentNode; subsequent pages: append to existing
        if m.offset = 0 then
            m.results = newItems
            m.contentNode = CreateObject("roSGNode", "ContentNode")
            m.resultsGrid.content = m.contentNode
        else
            m.results.append(newItems)
        end if

        ' Build ContentNode children for the new items
        for each item in newItems
            caption = BuildResultCaption(item)

            contentItem = m.contentNode.AddChild({
                Title: caption
                accessibleLabel: caption
                ShortDescriptionLine1: caption
                Type: item.type
                id: item.id
            })

            if item.overview <> invalid then
                contentItem.Description = item.overview
            end if

            ' poster_url is an absolute URL (TMDB or local) or null.
            ' ROK-3: lazy poster - URL stored now, HDPosterUrl set by the shared windowed activator
            SetLazyPosterUrl(contentItem, item, "poster_url")
        end for

        ' Update paging state
        m.offset = m.offset + itemCount
        m.hasMore = (itemCount = m.limit)
        m.loadingPage = false

        if m.statusLabel <> invalid then
            if m.results.Count() = 0 then
                m.statusLabel.text = Translate("search_no_results")
            else
                m.statusLabel.text = ""
            end if
        end if

        ' RT-094: a healthy response (even a zero-hit one) stands the
        ' failure chrome down - no-results is now ONLY a success verdict.
        if m.retryButton <> invalid then m.retryButton.visible = false
    end if
end sub

' RT-094: search failure-vs-no-results verdict, pure so the headless suite
' can convict it (same shape law as FavoritesBrowseOutcome; the literal-key
' dispatch keeps CHECK20's single dynamic exemption untouched).
function SearchBrowseOutcome(ok as Boolean, hasItems as Boolean) as String
    if not ok or not hasItems then return "search_failed"
    return ""
end function

sub OnSearchRetryPressed()
    ' Re-run the current query through the shipped debounce: re-arming the
    ' consumed one-shot timer (RT-005 idiom) fires OnSearchTimerFire, which
    ' reads m.keyboard.text fresh - no synthetic event, no second search path.
    if m.retryButton <> invalid then m.retryButton.visible = false
    if m.searchTimer <> invalid then
        m.searchTimer.control = "stop"
        m.searchTimer.control = "start"
    end if
end sub

' Caption per result type: episodes use the episode caption; everything else
' shows its name.
function BuildResultCaption(item as Object) as String
    if item = invalid then return ""

    if item.type = "episode" then
        return EpisodeCaption(item)
    end if

    if item.DoesExist("name") and item.name <> invalid then
        return item.name
    end if
    return ""
end function

sub OnResultSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.results.Count() then return

    item = m.results[index]
    if item = invalid then return

    ' [RT-093 W16L5, review roku__exploiter #2] Server-returned row ids are
    ' routed to typed scene parameters below; the shape law judges the raw
    ' Dynamic before that boundary (full note: CollectionScene's matching
    ' OnItemSelected gate). Ignore-posture on refusal.
    if not IsSafeContentId(item.id) then
        print "SearchScene: ignoring a result row with a malformed id"
        return
    end if

    ' Search can return seasons/episodes; route every type sensibly.
    if item.type = "series" then
        ShowSeries(item.id, item.name)
    else if item.type = "season" then
        ShowSeason(item.id, item.name)
    else
        ShowItemDetail(item.id)
    end if
end sub

sub OnResultFocused(event as Object)
    m.zone = "results"

    index = event.getData()
    if index < 0 or index >= m.results.Count() then return

    item = m.results[index]
    if item = invalid then return

    if m.statusLabel <> invalid then
        if item.overview <> invalid then
            m.statusLabel.text = item.overview
        else
            m.statusLabel.text = BuildResultCaption(item)
        end if
    end if

    ' Prefetch: trigger LoadMoreItems when focus approaches end of loaded set
    ' (within one screen = 15 items for a 5x3 grid)
    if m.results.Count() > 0 and index >= m.results.Count() - m.prefetchThreshold then
        LoadMoreItems()
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

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.keyboard <> invalid then
        m.keyboard.UnObserveField("text")
    end if
    if m.resultsGrid <> invalid then
        m.resultsGrid.UnObserveField("itemSelected")
        m.resultsGrid.UnObserveField("itemFocused")
        m.resultsGrid.UnObserveField("visibleRect")
    end if
    if m.apiTask <> invalid then
        m.apiTask.UnObserveField("response")
    end if
    if m.searchTimer <> invalid then
        m.searchTimer.control = "stop"
        m.searchTimer.UnObserveField("fire")
    end if
    if m.retryButton <> invalid then
        m.retryButton.UnObserveField("buttonSelected")
    end if
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        ' Horizontal keyboard<->results focus. The Roku Keyboard is a key grid;
        ' "right" at its right edge bubbles to the scene more reliably than
        ' "down". NOTE: exact Keyboard edge-bubbling is DEVICE-UNVERIFIABLE
        ' without hardware - implemented per the F4 spec assumption.
        if key = "right" and m.zone = "keyboard" and m.results.Count() > 0 then
            if m.resultsGrid <> invalid then
                m.resultsGrid.SetFocus(true)
                m.zone = "results"
                handled = true
            end if
        else if key = "down" and m.zone = "keyboard" and m.results.Count() > 0 then
            ' [W-min94 M-ROKU-32, review roku__gameux m4] alternative binding
            ' for the keyboard->results hop: where the firmware does NOT bubble
            ' right-at-edge (the review's failure mode — results unreachable),
            ' DOWN reaches the rail anyway. Additive-by-construction: a
            ' firmware whose Keyboard grid consumes down internally never
            ' delivers it here, so existing row navigation is untouched.
            if m.resultsGrid <> invalid then
                m.resultsGrid.SetFocus(true)
                m.zone = "results"
                handled = true
            end if
        else if key = "left" and m.zone = "results" then
            if m.keyboard <> invalid then
                m.keyboard.SetFocus(true)
                m.zone = "keyboard"
                handled = true
            end if
        else if key = "back" then
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
    n = m.top.findNode("headerLabel")
    if n <> invalid then n.text = Translate("common_search")
    n = m.top.findNode("statusLabel")
    if n <> invalid then n.text = Translate("search_hint")
    n = m.top.findNode("retryButton")
    if n <> invalid then n.text = Translate("common_retry")
end sub

' ROK-3: windowed lazy poster activation via the shared Utilities leaf.
sub OnGridVisibleRectChange(event as Object)
    vr = event.getData()
    if vr = invalid then return
    if m.resultsGrid = invalid then return
    content = m.resultsGrid.content
    if content = invalid then return
    ActivateVisibleRange(content, vr, 3, 230, 285)
end sub
