' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/LibraryScene.brs

' copyright 2026 Joe Huss
'
'
'

sub Init()
    ApplyXmlChrome()
    ' Supported sort field values (must match server-side ItemRepository values).
    ' These are local to Init() but copied to m.* for access by other subs.
    m.sortName = "name"
    m.sortYear = "year"
    m.sortRating = "rating"
    m.sortDateAdded = "date_added"
    m.sortRuntime = "runtime"

    ' Sort field display labels live in the locale catalog (library_sortby_*);
    ' TranslateSortLabel() resolves the localized display label for a field.

    m.top.SetFocus(true)

    ' Create poster grid for items
    m.posterGrid = m.top.FindNode("itemsGrid")
    m.posterGrid.ObserveField("itemSelected", "OnItemSelected")
    m.posterGrid.ObserveField("itemFocused", "OnItemFocused")
    m.posterGrid.ObserveField("visibleRect", "OnVisibleRectChange")

    ' UI nodes
    m.backButton = m.top.FindNode("backButton")
    m.titleLabel = m.top.FindNode("titleLabel")
    m.descriptionLabel = m.top.FindNode("descriptionLabel")
    m.loadingLabel = m.top.FindNode("loadingLabel")
    m.optionsButton = m.top.FindNode("optionsButton")
    m.sortLabel = m.top.FindNode("sortLabel")
    m.filterLabel = m.top.FindNode("filterLabel")
    m.azBar = m.top.FindNode("azBar")

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    if m.optionsButton <> invalid then
        m.optionsButton.ObserveField("buttonSelected", "OnOptionsPressed")
    end if

    ' Route all data access through one-shot ApiTask nodes (off the render
    ' thread). A SINGLE task node cannot accept a new request while its old run
    ' is in flight (control="run" is ignored mid-run, HomeScene comment R1.4),
    ' and facets + letter-index + items fire near-simultaneously on entry - so
    ' every call gets its own task, and getLibraryItems responses are matched
    ' by requestId to drop stale pages. (Precedent: HomeScene
    ' LoadLibrariesAsync.)
    m.requestSeq = 0
    m.activeItemsReqId = 0

    m.libraryId = ""
    m.items = []

    ' Paging state for infinite scroll
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)
    m.teardownOnClose = true

    ' Sort/filter state
    m.sortField = m.sortName
    m.sortOrder = "asc"
    m.selectedGenre = ""
    m.selectedLetter = ""
    m.availableGenres = []
    m.letterIndex = []
    ' True when the next getLibraryItems response REPLACES the grid (fresh
    ' load / filter change / letter jump) instead of appending a page. The
    ' old 'offset = 0' test could not express a letter jump (offset > 0 but
    ' still a fresh window), so the replace decision is tracked explicitly.
    m.replaceOnResponse = true
    ' Cumulative /media offset of the selected A-Z bucket (see OnLetterSelected);
    ' 0 = plain pagination from the start.
    m.jumpOffset = 0

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")
end sub

sub LoadLibrary(libraryId as String, libraryName as String)
    m.libraryId = libraryId

    ' Load persisted sort preference for this library
    LoadSortPreference(libraryId)

    ' Reset paging + filter state for fresh library load (a stale genre or
    ' letter-jump from the previous library must not leak into this one).
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.items = []
    m.contentNode = invalid
    m.selectedGenre = ""
    m.selectedLetter = ""
    m.jumpOffset = 0
    m.replaceOnResponse = true

    if m.titleLabel <> invalid then
        m.titleLabel.text = libraryName
    end if

    ' Update sort/filter labels
    UpdateSortFilterLabels()

    ' Fetch facets and letter index, then load the first window. The grid's
    ' own visibleRect prefetch (-> LoadMoreItems) only APPENDS; the initial
    ' page must be requested here so entry does not depend on layout timing.
    FetchFacets()
    FetchLetterIndex()
    RefreshItems()
end sub

sub LoadSortPreference(libraryId as String)
    key = "sort_" + libraryId
    stored = GetStorage().get(key)
    if stored <> "" and stored <> invalid then
        ' Parse JSON stored preference
        json = ParseJson(stored)
        if json <> invalid then
            if json.DoesExist("sort") then m.sortField = json.sort
            if json.DoesExist("order") then m.sortOrder = json.order
            ' Validate sortField against known values
            validFields = [m.sortName, m.sortYear, m.sortRating, m.sortDateAdded, m.sortRuntime]
            if validFields.find(m.sortField) = -1 then
                m.sortField = m.sortName
            end if
            if m.sortOrder <> "asc" and m.sortOrder <> "desc" then
                m.sortOrder = "asc"
            end if
        end if
    else
        m.sortField = m.sortName
        m.sortOrder = "asc"
    end if
end sub

sub SaveSortPreference(libraryId as String)
    key = "sort_" + libraryId
    json = {
        sort: m.sortField
        order: m.sortOrder
    }
    GetStorage().set(key, FormatJson(json))
end sub

' Fire one API operation on a dedicated task node (never blocks the render
' thread; response lands in OnApiResponse). Follows HomeScene LoadLibrariesAsync:
' fresh node per call, `state = "run"` busy marker set before control="run".
sub FireApiRequest(request as Object)
    task = CreateObject("roSGNode", "ApiTask")
    task.ObserveField("response", "OnApiResponse")
    task.request = request
    if task.state = "run" then return
    task.state = "run"
    task.control = "run"
end sub

sub FetchFacets()
    ' Fetch available genres from server
    FireApiRequest({
        op: "getMediaFacets"
        libraryId: m.libraryId
    })
end sub

sub FetchLetterIndex()
    ' Fetch the A-Z index from server. GET /media/letter-index takes the SAME
    ' filters as GET /media (phlix-server WebPortalRouter::getLetterIndex) - so
    ' when a genre filter is active the index is re-fetched scoped to it and
    ' the cumulative offsets stay valid for the filtered window. There is no
    ' `letter` parameter: the response's per-bucket `offset` values ARE the
    ' jump targets (see OnLetterSelected).
    request = {
        op: "getLetterIndex"
        libraryId: m.libraryId
    }
    if m.selectedGenre <> "" then
        request.genres = [m.selectedGenre]
    end if
    FireApiRequest(request)
end sub

sub UpdateSortFilterLabels()
    if m.sortLabel <> invalid then
        ' Localized "Sort: <label>" via catalog token template.
        m.sortLabel.text = TranslateWithParams("library_sort_label", { sort: TranslateSortLabel(m.sortField) })
    end if

    if m.filterLabel <> invalid then
        if m.selectedGenre <> "" then
            ' Genre names are server data - pass through unmodified.
            m.filterLabel.text = TranslateWithParams("library_filter_label", { filter: m.selectedGenre })
        else
            m.filterLabel.text = TranslateWithParams("library_filter_label", { filter: Translate("common_all") })
        end if
    end if
end sub

sub OnOptionsPressed()
    ' Show sort options dialog
    ShowSortOptions()
end sub

sub ShowSortOptions()
    ' Build list of sort options with current selection marked
    sortList = []
    idx = 0
    for each field in [m.sortName, m.sortYear, m.sortRating, m.sortDateAdded, m.sortRuntime]
        label = TranslateSortLabel(field)
        if field = m.sortField then
            label = label + " *"
        end if
        sortList.push(label)
        idx = idx + 1
    end for

    ' TODO: Show actual roListDialog or custom picker here
    ' For now, cycle through options on each press
    fields = [m.sortName, m.sortYear, m.sortRating, m.sortDateAdded, m.sortRuntime]
    currentIdx = fields.find(m.sortField)
    if currentIdx < 0 then currentIdx = 0
    nextIdx = (currentIdx + 1) mod fields.count()
    ApplySort(fields[nextIdx], m.sortOrder)
end sub

sub ApplySort(sortField as String, sortOrder as String)
    if sortField <> m.sortField or sortOrder <> m.sortOrder then
        m.sortField = sortField
        m.sortOrder = sortOrder
        SaveSortPreference(m.libraryId)
        UpdateSortFilterLabels()
        ' A new sort invalidates any A-Z jump: the letter-index offsets are
        ' computed for a name-ascending ordering only (server contract), so the
        ' letter selection (and its jump window) resets with the sort change.
        m.selectedLetter = ""
        m.jumpOffset = 0
        ' Reset window and reload from its start
        ResetAndRefresh()
    end if
end sub

sub OnGenreSelected(genre as String)
    if genre <> m.selectedGenre then
        m.selectedGenre = genre
        UpdateSortFilterLabels()
        ' The A-Z jump window is scoped to the active genre too - re-fetch the
        ' letter index (offsets change with the filter) and drop any stale
        ' letter selection before resetting the grid.
        m.selectedLetter = ""
        m.jumpOffset = 0
        FetchLetterIndex()
        ' Reset window and reload from its start
        ResetAndRefresh()
    end if
end sub

' Resolve the cumulative /media offset for a letter bucket from the
' {letter,offset,count} rows returned by GET /media/letter-index. Unknown or
' empty buckets answer -1 so callers can ignore the press.
function LetterBucketOffset(letter as String) as Integer
    for each bucket in m.letterIndex
        if bucket <> invalid and bucket.letter <> invalid and bucket.letter = letter then
            if bucket.count = invalid or bucket.count <= 0 then return -1
            if bucket.offset = invalid then return 0
            return CInt(bucket.offset)
        end if
    end for
    return -1
end function

sub OnLetterSelected(letter as String)
    if letter = m.selectedLetter then return

    ' GET /media has NO letter filter (WebPortalRouter::extractMediaQueryParams);
    ' the contract-correct A-Z jump reads /media at the bucket's cumulative
    ' OFFSET. Offsets are computed for a name-ascending sort, so the jump
    ' forces that sort for the window (persisted user preference untouched).
    jump = LetterBucketOffset(letter)
    if jump < 0 then return

    m.selectedLetter = letter
    m.jumpOffset = jump
    if m.sortField <> m.sortName or m.sortOrder <> "asc" then
        m.sortField = m.sortName
        m.sortOrder = "asc"
        UpdateSortFilterLabels()
    end if
    ' Replace the grid with the bucket window.
    ResetAndRefresh()
end sub

sub ResetAndRefresh()
    ' Restart the window at the active jump offset (0 unless a letter is selected)
    m.offset = m.jumpOffset
    m.hasMore = true
    m.loadingPage = false
    m.items = []
    m.contentNode = invalid
    m.replaceOnResponse = true
    RefreshItems()
end sub

sub RefreshItems()
    if m.libraryId = "" then return

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
        if m.offset > 0 then
            m.loadingLabel.text = Translate("common_loading_more")
        else
            m.loadingLabel.text = Translate("common_loading")
        end if
    end if

    ' Build options with sort + filter. NOTE: no `letter` param - GET /media
    ' does not accept one (WebPortalRouter::extractMediaQueryParams); the A-Z
    ' jump is already encoded in the offset below (m.jumpOffset seeds m.offset).
    options = {
        topLevel: 1
        offset: m.offset
        limit: m.limit
        sort: m.sortField
        order: m.sortOrder
    }

    ' Add genre filter if selected - serialized as repeated genres[]= entries
    ' by the getLibraryItems op (server law: is_array($query['genres'])).
    if m.selectedGenre <> "" then
        options.genres = [m.selectedGenre]
    end if

    m.requestSeq = m.requestSeq + 1
    m.activeItemsReqId = m.requestSeq
    FireApiRequest({
        op: "getLibraryItems"
        libraryId: m.libraryId
        options: options
        requestId: m.activeItemsReqId
    })
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

    if resp.op = "getLibraryItems" then
        ' Drop stale windows: if a sort/genre/letter change (or a newer page)
        ' was issued after this request, its rows belong to another window.
        if resp.requestId <> m.activeItemsReqId then return
        ' Hide loading indicator.
        if m.loadingLabel <> invalid then
            m.loadingLabel.visible = false
        end if

        if not resp.ok or resp.data = invalid or resp.data.items = invalid then
            m.loadingPage = false
            return
        end if

        newItems = resp.data.items
        itemCount = newItems.count()

        ' Fresh window (first load, filter/sort change, letter jump): create the
        ' ContentNode. Later pages of the same window: append to the existing one.
        if m.replaceOnResponse then
            m.items = newItems
            m.replaceOnResponse = false
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
                Type: item.type
                id: item.id
            })

            if item.year <> invalid then
                contentItem.ShortDescriptionLine2 = str(item.year).trim()
            end if

            ' R5: Lazy image loading — defer HDPosterUrl assignment until visible
            SetLazyPosterUrl(contentItem, item, "poster_url")
        end for

        ' Update paging state
        m.offset = m.offset + itemCount
        m.hasMore = (itemCount = m.limit)
        m.loadingPage = false

    else if resp.op = "getMediaFacets" then
        ' Store available genres for filtering
        if resp.ok and resp.data <> invalid and resp.data.genres <> invalid then
            m.availableGenres = resp.data.genres
        else
            m.availableGenres = []
        end if

    else if resp.op = "getLetterIndex" then
        ' Store letter index for A-Z jump
        if resp.ok and resp.data <> invalid and resp.data.letters <> invalid then
            m.letterIndex = resp.data.letters
        else
            m.letterIndex = []
        end if
        ' Build A-Z buttons from the letter index
        BuildAzBar()
    end if
end sub

sub BuildAzBar()
    if m.azBar = invalid then return

    ' Clear existing buttons
    m.azBar.removeChildren()

    ' Create buttons for each letter with items (count > 0)
    letterButtons = []
    for each letterData in m.letterIndex
        if letterData.count > 0 then
            letter = letterData.letter
            button = CreateObject("roSGNode", "Button")
            button.id = letter
            button.text = letter
            button.height = 35
            button.width = 40
            button.font = "font:SmallSystemFont"
            ' buttonSelected is an integer event field - the old
            ' setField("buttonSelected", "OnAzButtonPressed") assigned a STRING
            ' into it instead of wiring the callback, so rail presses were dead.
            ' ObserveField is the correct hook (fires OnAzButtonPressed with the
            ' selected index).
            button.ObserveField("buttonSelected", "OnAzButtonPressed")
            letterButtons.push(button)
        end if
    end for

    ' Add buttons to azBar
    for each btn in letterButtons
        m.azBar.appendChild(btn)
    end for
end sub

sub OnAzButtonPressed(event as Object)
    node = event.getNode()
    letter = node.id
    if letter <> invalid and letter <> "" then
        OnLetterSelected(letter)
    end if
end sub

sub ShowFilterOptions()
    ' Show genre filter dialog - cycle through available genres
    if m.availableGenres.count() = 0 then return

    ' Cycle to next genre: All -> first genre -> second -> ... -> All
    if m.selectedGenre = "" then
        ' No filter active, apply first genre
        OnGenreSelected(m.availableGenres[0])
    else
        ' Find current genre index and move to next
        idx = m.availableGenres.find(m.selectedGenre)
        if idx = -1 or idx >= m.availableGenres.count() - 1 then
            ' Last genre or not found, reset to all
            OnGenreSelected("")
        else
            OnGenreSelected(m.availableGenres[idx + 1])
        end if
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.items.Count() then return

    item = m.items[index]
    if item = invalid then return

    ' F2: a series drills into its seasons (SeriesScene); every other top-level
    ' type (movie/audio/photo/...) opens the detail scene directly, which decides
    ' for itself whether the item is playable (see IsPlayableItem).
    if item.type = "series" then
        ShowSeries(item.id, item.name)
    else
        ShowItemDetail(item.id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()

    if index >= 0 and index < m.items.Count() then
        item = m.items[index]
        if m.descriptionLabel <> invalid then
            if item.overview <> invalid then
                m.descriptionLabel.text = item.overview
            else
                m.descriptionLabel.text = item.name
            end if
        end if

        ' Prefetch: trigger LoadMoreItems when focus approaches end of loaded set
        ' (within one screen = 15 items for a 5x3 grid)
        if m.items.Count() > 0 and index >= m.items.Count() - m.prefetchThreshold then
            LoadMoreItems()
        end if
    end if
end sub

' R5: visibleRect lazy loading — load images when items come into visible range
sub OnVisibleRectChange(event as Object)
    vr = event.getData()
    if vr = invalid then return

    ' Calculate visible item range based on grid geometry
    ' numColumns=5, item width ~230, item height ~350
    ' visible rect: vr[0], vr[1] is top-left; vr[2], vr[3] is width, height

    ' For each content node child, check if its position is in visible rect
    ' and load/unload images accordingly
    if m.contentNode = invalid then return

    rowHeight = 350
    numCols = 5

    firstVisibleRow = Int(vr.y / rowHeight)
    lastVisibleRow = Int((vr.y + vr.height) / rowHeight) + 1
    firstVisibleIndex = firstVisibleRow * numCols
    lastVisibleIndex = lastVisibleRow * numCols + numCols

    i = 0
    child = m.contentNode.GetChild(i)
    while child <> invalid
        ' Activate image if in visible range (with buffer of 1 row)
        activateThreshold = firstVisibleIndex - numCols
        clearThreshold = lastVisibleIndex + numCols

        if i >= activateThreshold and i <= clearThreshold then
            if child.HDPosterUrl = "" and child.doesExist("_lazyPosterUrl") then
                ActivateLazyPosterUrl(child)
            end if
        else
            ' Out of visible range — clear to save memory (only if already loaded)
            if child.HDPosterUrl <> "" then
                ClearLazyPosterUrl(child)
            end if
        end if
        i = i + 1
        child = m.contentNode.GetChild(i)
    end while
end sub

sub ShowSeries(seriesId as String, seriesName as String)
    name = seriesName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "SeriesScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadSeries(seriesId, name)
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadItem(itemId)
end sub

' Bubble requestClose from a child scene up to the parent.
sub OnChildRequestClose()
    Teardown()
    m.top.requestClose = true
end sub

sub OnBackPressed()
    m.top.requestClose = true
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end function

sub Teardown()
    if m.posterGrid <> invalid
        m.posterGrid.UnObserveField("itemSelected")
        m.posterGrid.UnObserveField("itemFocused")
        m.posterGrid.UnObserveField("visibleRect")
    end if
    if m.backButton <> invalid
        m.backButton.UnObserveField("buttonSelected")
    end if
    if m.optionsButton <> invalid
        m.optionsButton.UnObserveField("buttonSelected")
    end if
    if m.top <> invalid
        m.top.UnObserveField("requestClose")
    end if
end sub

' TranslateSortLabel - localized display label for a library sort field.
' Literal Translate() calls (never a dynamic key) so CHECK20 can verify every
' sort label against the en_US catalog.
Function TranslateSortLabel(field as String) as String
    if field = m.sortYear then return Translate("library_sortby_year")
    if field = m.sortRating then return Translate("library_sortby_rating")
    if field = m.sortDateAdded then return Translate("library_sortby_date_added")
    if field = m.sortRuntime then return Translate("library_sortby_runtime")
    return Translate("library_sortby_name")
End Function

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("backButton")
    if n <> invalid then n.title = Translate("common_back")
    n = m.top.findNode("titleLabel")
    if n <> invalid then n.text = Translate("common_library")
    n = m.top.findNode("optionsButton")
    if n <> invalid then n.title = Translate("common_sort")
    n = m.top.findNode("jumpToLabel")
    if n <> invalid then n.text = Translate("library_jump_to")
    n = m.top.findNode("descriptionLabel")
    if n <> invalid then n.text = Translate("common_select_item")
    n = m.top.findNode("loadingLabel")
    if n <> invalid then n.text = Translate("common_loading")
end sub
