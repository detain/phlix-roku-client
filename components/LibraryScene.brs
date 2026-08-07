' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/LibraryScene.brs

' copyright 2026 Joe Huss
'
'
'

sub Init()
    ' Supported sort field values (must match server-side ItemRepository values).
    ' These are local to Init() but copied to m.* for access by other subs.
    m.sortName = "name"
    m.sortYear = "year"
    m.sortRating = "rating"
    m.sortDateAdded = "date_added"
    m.sortRuntime = "runtime"

    ' Sort field display labels
    m.sortLabels = {
        name: "Name (A-Z)",
        year: "Year (Newest)",
        rating: "Rating",
        date_added: "Date Added",
        runtime: "Runtime"
    }

    m.top.SetFocus(true)

    ' Create poster grid for items
    m.posterGrid = m.top.FindNode("itemsGrid")
    m.posterGrid.ObserveField("itemSelected", "OnItemSelected")
    m.posterGrid.ObserveField("itemFocused", "OnItemFocused")

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

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraryId = ""
    m.items = []

    ' Paging state for infinite scroll
    m.offset = 0
    m.limit = 50
    m.hasMore = true
    m.loadingPage = false
    m.contentNode = invalid
    m.prefetchThreshold = 15 ' one screen (5 cols x 3 rows = 15 visible)

    ' Sort/filter state
    m.sortField = m.sortName
    m.sortOrder = "asc"
    m.selectedGenre = ""
    m.selectedLetter = ""
    m.availableGenres = []
    m.letterIndex = []

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")
end sub

sub LoadLibrary(libraryId as String, libraryName as String)
    m.libraryId = libraryId

    ' Load persisted sort preference for this library
    LoadSortPreference(libraryId)

    ' Reset paging state for fresh library load
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.items = []
    m.contentNode = invalid
    m.selectedLetter = ""

    if m.titleLabel <> invalid then
        m.titleLabel.text = libraryName
    end if

    ' Update sort/filter labels
    UpdateSortFilterLabels()

    ' Fetch facets and letter index, then load items
    FetchFacets()
    FetchLetterIndex()
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

sub FetchFacets()
    ' Fetch available genres from server
    m.apiTask.request = {
        op: "getMediaFacets"
        libraryId: m.libraryId
    }
    m.apiTask.control = "run"
end sub

sub FetchLetterIndex()
    ' Fetch A-Z index from server
    m.apiTask.request = {
        op: "getLetterIndex"
        libraryId: m.libraryId
        letter: "A"
    }
    m.apiTask.control = "run"
end sub

sub UpdateSortFilterLabels()
    if m.sortLabel <> invalid then
        ' Show current sort as "Sort: Name" or similar
        sortDisplay = m.sortLabels[m.sortField]
        if sortDisplay = invalid then sortDisplay = "Name"
        m.sortLabel.text = "Sort: " + sortDisplay
    end if

    if m.filterLabel <> invalid then
        if m.selectedGenre <> "" then
            m.filterLabel.text = "Filter: " + m.selectedGenre
        else
            m.filterLabel.text = "Filter: All"
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
        label = m.sortLabels[field]
        if label = invalid then label = field
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
        ' Reset to first page and clear loaded items
        ResetAndRefresh()
    end if
end sub

sub OnGenreSelected(genre as String)
    if genre <> m.selectedGenre then
        m.selectedGenre = genre
        UpdateSortFilterLabels()
        ' Reset to first page and clear loaded items
        ResetAndRefresh()
    end if
end sub

sub OnLetterSelected(letter as String)
    if letter <> m.selectedLetter then
        m.selectedLetter = letter
        ' Reset to first page and clear loaded items
        ResetAndRefresh()
    end if
end sub

sub ResetAndRefresh()
    ' Reset offset to 0 and clear loaded items
    m.offset = 0
    m.hasMore = true
    m.loadingPage = false
    m.items = []
    m.contentNode = invalid
    RefreshItems()
end sub

sub RefreshItems()
    if m.libraryId = "" then return

    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
        if m.offset > 0 then
            m.loadingLabel.text = "Loading more..."
        else
            m.loadingLabel.text = "Loading..."
        end if
    end if

    ' Build options with sort, filter, and letter params
    options = {
        topLevel: 1
        offset: m.offset
        limit: m.limit
        sort: m.sortField
        order: m.sortOrder
    }

    ' Add genre filter if selected
    if m.selectedGenre <> "" then
        options.genres = [m.selectedGenre]
    end if

    ' Add letter filter if selected (for A-Z jump)
    if m.selectedLetter <> "" then
        ' The letter filter tells server to filter by first letter of name
        ' Server uses letter index offset directly
        options.letter = m.selectedLetter
    end if

    m.apiTask.request = {
        op: "getLibraryItems"
        libraryId: m.libraryId
        options: options
    }
    m.apiTask.control = "run"
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

        ' First page: create ContentNode; subsequent pages: append to existing
        if m.offset = 0 then
            m.items = newItems
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

            ' poster_url is an absolute URL (TMDB or local) or null.
            if item.poster_url <> invalid and item.poster_url <> "" then
                contentItem.HDPosterUrl = item.poster_url
            else
                contentItem.HDPosterUrl = "pkg:/images/placeholder.png"
            end if
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
            button.setField("buttonSelected", "OnAzButtonPressed")
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