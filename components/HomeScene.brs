' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' source/components/HomeScene.brs

' copyright 2026 Joe Huss
'


sub Init()
    m.top.SetFocus(true)

    ' Libraries grid (multi-row).
    m.libraryGrid = m.top.FindNode("libraryGrid")
    m.libraryGrid.ObserveField("itemSelected", "OnLibraryItemSelected")
    m.libraryGrid.ObserveField("itemFocused", "OnLibraryItemFocused")

    ' Continue Watching rail (single row, hidden until populated).
    m.continueGrid = m.top.FindNode("continueGrid")
    m.continueLabel = m.top.FindNode("continueLabel")
    m.continueGrid.ObserveField("itemSelected", "OnContinueItemSelected")
    m.continueGrid.ObserveField("itemFocused", "OnContinueItemFocused")

    ' R7.2: Up Next rail (single row, hidden until populated).
    m.upNextGrid = m.top.FindNode("upNextGrid")
    m.upNextLabel = m.top.FindNode("upNextLabel")
    m.upNextItems = []
    if m.upNextGrid <> invalid then
        m.upNextGrid.ObserveField("itemSelected", "OnUpNextItemSelected")
        m.upNextGrid.ObserveField("itemFocused", "OnUpNextItemFocused")
    end if

    ' Search entry (header). Opens the SearchScene.
    m.searchButton = m.top.FindNode("searchButton")
    if m.searchButton <> invalid then
        m.searchButton.ObserveField("buttonSelected", "OnSearchPressed")
    end if

    ' Favorites entry (header, beside Search). Opens the FavoritesScene.
    m.favoritesButton = m.top.FindNode("favoritesButton")
    if m.favoritesButton <> invalid then
        m.favoritesButton.ObserveField("buttonSelected", "OnFavoritesPressed")
    end if

    ' Collections entry (header, beside Favorites). Opens the CollectionsScene.
    m.collectionsButton = m.top.FindNode("collectionsButton")
    if m.collectionsButton <> invalid then
        m.collectionsButton.ObserveField("buttonSelected", "OnCollectionsPressed")
    end if

    ' For You entry (header). Opens the RecommendationsScene.
    m.forYouButton = m.top.FindNode("forYouButton")
    if m.forYouButton <> invalid then
        m.forYouButton.ObserveField("buttonSelected", "OnForYouPressed")
    end if

    ' Admin entry (header, beside Collections). Hidden by default (visible="false"
    ' in XML); revealed only when the current user is_admin (see OnMeResponse).
    ' Opens the AdminScene menu.
    m.adminButton = m.top.FindNode("adminButton")
    if m.adminButton <> invalid then
        m.adminButton.ObserveField("buttonSelected", "OnAdminPressed")
    end if

    ' Settings entry (header, beside Collections). Opens the SettingsScene.
    m.settingsButton = m.top.FindNode("settingsButton")
    if m.settingsButton <> invalid then
        m.settingsButton.ObserveField("buttonSelected", "OnSettingsPressed")
    end if

    m.descriptionLabel = m.top.FindNode("descriptionLabel")
    m.loadingLabel = m.top.FindNode("loadingLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread). Every op is serialized through this one task so two
    ' control="run" are never outstanding at once.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraries = []
    m.continueItems = []
    m.currentRail = "library"
    ' Which header button is focused while m.currentRail = "search":
    ' "search", "forYou", "favorites", "collections" or "admin" (default "search").
    ' "admin" is only ever reached when m.isAdmin (the button is otherwise hidden).
    m.headerCol = "search"
    m.isAdmin = false
    m.pendingResume = invalid
    ' R7.2: Pending up-next item while fetching its playback info.
    m.pendingUpNext = invalid
    ' Guards against the async continue-watching response stealing focus when the
    ' user has already moved focus away from the continue rail (line 208). Only
    ' set focus on the FIRST successful load; subsequent refreshes skip the focus
    ' move so an async response never yanks focus mid-interaction.
    m.continueGridFirstLoaded = false

    ' Init load chain (serialized through the single task): getMe FIRST (gates the
    ' admin button), which then chains libraries -> continue-watching from the
    ' getMe branch of OnApiResponse.
    LoadMe()
end sub

' Fetch the current user (GET /auth/me). The response gates the admin button and
' then continues the original chain (libraries -> continue-watching).
sub LoadMe()
    ' Show loading indicator while data loads off the render thread.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = true
    end if

    m.apiTask.request = { op: "getMe" }
    m.apiTask.control = "run"
end sub

sub LoadLibraries()
    m.apiTask.request = { op: "getLibraries" }
    m.apiTask.control = "run"
end sub

sub LoadContinueWatching()
    m.apiTask.request = { op: "getContinueWatching" }
    m.apiTask.control = "run"
end sub

' ===========================================
' Async row loaders — each creates its own dedicated Task node so the two
' HTTP calls run in parallel (GET /libraries and GET /history/continue).
' Both are launched from OnMeResponse after the getMe op completes.
' m.apiTask stays reserved for serialized resume ops (getItem + playbackInfo).
' ===========================================
sub LoadLibrariesAsync()
    ' Each call creates a fresh task node → runs on its own task thread.
    ' No result tracking needed — the observer (OnLibrariesResponse) handles
    ' the content assignment directly.
    task = CreateObject("roSGNode", "ApiTask")
    task.ObserveField("response", "OnLibrariesResponse")
    task.request = { op: "getLibraries" }
    if task.state = "run" then return
    task.state = "run"
    task.control = "run"
end sub

sub LoadContinueWatchingAsync()
    task = CreateObject("roSGNode", "ApiTask")
    task.ObserveField("response", "OnContinueWatchingResponse")
    task.request = { op: "getContinueWatching" }
    if task.state = "run" then return
    task.state = "run"
    task.control = "run"
end sub

' R7.2: Load Up Next item (single row, hidden until populated).
sub LoadUpNextAsync()
    task = CreateObject("roSGNode", "ApiTask")
    task.ObserveField("response", "OnUpNextResponse")
    task.request = { op: "getNextUp" }
    if task.state = "run" then return
    task.state = "run"
    task.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getMe" then
        OnMeResponse(resp)
    else if resp.op = "getLibraries" then
        OnLibrariesResponse(resp)
    else if resp.op = "getContinueWatching" then
        OnContinueWatchingResponse(resp)
    else if resp.op = "getNextUp" then
        OnUpNextResponse(resp)
    else if resp.op = "getItem" then
        ' R7.2: Distinguish up-next getItem from resume getItem
        if m.pendingUpNext <> invalid then
            OnUpNextItemLoaded(resp)
        else
            OnResumeItemResponse(resp)
        end if
    else if resp.op = "getItemPlaybackInfo" then
        ' R7.2: Distinguish up-next playback info from resume
        if m.pendingUpNext <> invalid then
            OnUpNextPlaybackInfoLoaded(resp)
        else
            OnResumePlaybackInfoResponse(resp)
        end if
    end if
end sub

' getMe response: gate the admin button via IsAdminUser, then continue the
' original load chain (libraries -> continue-watching) regardless of admin state.
sub OnMeResponse(resp as Object)
    ' Hide loading indicator.
    if m.loadingLabel <> invalid then
        m.loadingLabel.visible = false
    end if

    if resp.ok and resp.data <> invalid then
        m.isAdmin = IsAdminUser(resp.data)
        if m.isAdmin and m.adminButton <> invalid then m.adminButton.visible = true
    end if

    ' getMe is done - launch BOTH row loads in parallel (not chained anymore).
    ' This cuts row population latency roughly in half vs the old sequential chain.
    ' m.apiTask is now free for resume ops (getItem/getItemPlaybackInfo) which
    ' MUST stay serialized through the original single-task instance.
    LoadLibrariesAsync()
    LoadContinueWatchingAsync()
    ' R7.2: Also fetch the Up Next item for the rail.
    LoadUpNextAsync()
end sub

sub OnLibrariesResponse(resp as Object)
    if resp.ok and resp.data <> invalid then
        m.libraries = resp.data

        ' Build the grid from each library's canonical name/id.
        content = CreateObject("roSGNode", "ContentNode")
        for each library in m.libraries
            content.AddChild({
                Title: library.name
                Description: "Library"
                HDPosterUrl: "pkg:/images/placeholder.png"
                ShortDescriptionLine1: library.name
                Type: "library"
                id: library.id
            })
        end for
        m.libraryGrid.content = content
    end if
    ' NOTE: no chain to continue-watching here - it's now launched in parallel
    ' from OnMeResponse via LoadContinueWatchingAsync()
end sub

sub OnContinueWatchingResponse(resp as Object)
    if not resp.ok or resp.data = invalid then return

    items = resp.data.items
    if items = invalid or items.Count() = 0 then return

    m.continueItems = items

    content = CreateObject("roSGNode", "ContentNode")
    for each item in items
        content.AddChild({
            Title: item.name
            ShortDescriptionLine1: item.name
            Type: "continue"
            HDPosterUrl: ContinuePosterUrl(item)
        })
    end for
    m.continueGrid.content = content

    m.continueLabel.visible = true
    m.continueGrid.visible = true

    ' Surface the rail. Only move focus on first load — never yank focus back
    ' mid-interaction if the user has already moved elsewhere.
    if not m.continueGridFirstLoaded then
        m.continueGrid.SetFocus(true)
        m.currentRail = "continue"
        m.continueGridFirstLoaded = true
    end if
end sub

' R7.2: Handle getNextUp response — populate the Up Next rail.
sub OnUpNextResponse(resp as Object)
    if not resp.ok or resp.data = invalid then return

    ' getNextUp returns {item: {...}} — extract the item
    item = resp.data
    if item = invalid then return
    if type(item) <> "roAssociativeArray" then return

    m.upNextItems = [item]

    content = CreateObject("roSGNode", "ContentNode")
    content.AddChild({
        Title: item.name
        ShortDescriptionLine1: item.name
        Type: "upnext"
        HDPosterUrl: UpNextPosterUrl(item)
    })
    if m.upNextGrid <> invalid then m.upNextGrid.content = content

    if m.upNextLabel <> invalid then m.upNextLabel.visible = true
    if m.upNextGrid <> invalid then m.upNextGrid.visible = true
end sub

' R7.2: Best-effort poster for an up-next tile.
function UpNextPosterUrl(item as Object) as String
    if item <> invalid then
        ' Try metadata.poster_url or metadata.poster
        if item.DoesExist("metadata") and type(item.metadata) = "roAssociativeArray" then
            meta = item.metadata
            if meta.DoesExist("poster_url") and meta.poster_url <> invalid and meta.poster_url <> "" then
                return meta.poster_url
            end if
            if meta.DoesExist("poster") and meta.poster <> invalid and meta.poster <> "" then
                return meta.poster
            end if
        end if
        ' Direct poster field
        if item.DoesExist("poster_url") and item.poster_url <> invalid and item.poster_url <> "" then
            return item.poster_url
        end if
        if item.DoesExist("poster") and item.poster <> invalid and item.poster <> "" then
            return item.poster
        end if
    end if
    return "pkg:/images/placeholder.png"
end function

' R7.2: Handle Up Next item selection — fetch playback info and launch PlayerScene.
sub OnUpNextItemSelected(event as Object)
    index = event.getData()
    if index < 0 or index >= m.upNextItems.Count() then return

    item = m.upNextItems[index]
    if item = invalid then return

    mediaItemId = ""
    if item.DoesExist("id") then
        mediaItemId = item.id
    else if item.DoesExist("media_item_id") then
        mediaItemId = item.media_item_id
    end if

    if mediaItemId = "" then return

    ' Start the serialized launch chain: getItem -> getItemPlaybackInfo -> PlayerScene.Show
    m.pendingUpNext = {
        mediaItemId: mediaItemId
        item: invalid
    }
    if m.apiTask.state = "run" then return
    m.apiTask.request = { op: "getItem", itemId: mediaItemId }
    m.apiTask.state = "run"
    m.apiTask.control = "run"
end sub

sub OnUpNextItemFocused(event as Object)
    m.currentRail = "upnext"

    index = event.getData()
    if index < 0 or index >= m.upNextItems.Count() then return

    item = m.upNextItems[index]
    if item = invalid then return

    if m.descriptionLabel <> invalid and item.name <> invalid then
        m.descriptionLabel.text = item.name
    end if
end sub

' Best-effort poster for a continue-watching tile. CW items are RAW JOIN rows
' with NO poster_url; try metadata.poster_url then metadata.poster, else the
' placeholder.
function ContinuePosterUrl(item as Object) as String
    if item <> invalid and item.metadata <> invalid then
        meta = item.metadata
        ' metadata may arrive as a raw string instead of a parsed object; only
        ' read poster keys when it is an assoc (else fall through to placeholder).
        if type(meta) = "roAssociativeArray" then
            if meta.DoesExist("poster_url") and meta.poster_url <> invalid and meta.poster_url <> "" then
                return meta.poster_url
            end if
            if meta.DoesExist("poster") and meta.poster <> invalid and meta.poster <> "" then
                return meta.poster
            end if
        end if
    end if
    return "pkg:/images/placeholder.png"
end function

sub OnLibraryItemSelected(event as Object)
    index = event.getData()
    if index < 0 or index >= m.libraries.Count() then return

    library = m.libraries[index]
    if library = invalid then return

    ' Music libraries have no artwork -> route to the text-list MusicScene
    ' (music aggregates server-side, so MusicScene needs no library id).
    ' Photo libraries -> the date-album PosterGrid PhotosScene (F7).
    if library.DoesExist("type") and library.type = "music" then
        ShowMusic()
    else if library.DoesExist("type") and library.type = "photo" then
        ShowPhotos(library.id, library.name)
    else
        ShowLibrary(library.id, library.name)
    end if
end sub

sub OnLibraryItemFocused(event as Object)
    m.currentRail = "library"

    index = event.getData()
    if index < 0 or index >= m.libraries.Count() then return

    library = m.libraries[index]
    if library = invalid then return

    if m.descriptionLabel <> invalid then
        m.descriptionLabel.text = library.name
    end if
end sub

sub OnContinueItemSelected(event as Object)
    ' A resume launch is already in flight (its getItem/getItemPlaybackInfo is
    ' outstanding on the single task) - ignore a rapid second select so two
    ' control="run" are never outstanding. Cleared when the launch completes.
    if m.pendingResume <> invalid then return

    index = event.getData()
    if index < 0 or index >= m.continueItems.Count() then return

    cw = m.continueItems[index]
    if cw = invalid then return

    mediaItemId = cw.media_item_id
    if mediaItemId = invalid or mediaItemId = "" then return

    resumeSeconds = 0.0
    if cw.position_ticks <> invalid then
        resumeSeconds = cw.position_ticks / 10000000.0
    end if

    ' Start the serialized resume-launch chain: getItem -> getItemPlaybackInfo
    ' -> PlayerScene.Show. Tracked through m.pendingResume.
    m.pendingResume = {
        mediaItemId: mediaItemId
        resumeSeconds: resumeSeconds
        item: invalid
    }
    m.apiTask.request = { op: "getItem", itemId: mediaItemId }
    m.apiTask.control = "run"
end sub

sub OnContinueItemFocused(event as Object)
    m.currentRail = "continue"

    index = event.getData()
    if index < 0 or index >= m.continueItems.Count() then return

    cw = m.continueItems[index]
    if cw = invalid then return

    if m.descriptionLabel <> invalid and cw.name <> invalid then
        m.descriptionLabel.text = cw.name
    end if
end sub

sub OnResumeItemResponse(resp as Object)
    if m.pendingResume = invalid then return

    if not resp.ok or resp.data = invalid then
        m.pendingResume = invalid
        return
    end if

    m.pendingResume.item = resp.data
    m.apiTask.request = { op: "getItemPlaybackInfo", itemId: m.pendingResume.mediaItemId }
    m.apiTask.control = "run"
end sub

sub OnResumePlaybackInfoResponse(resp as Object)
    if m.pendingResume = invalid then return

    if not resp.ok or resp.data = invalid then
        m.pendingResume = invalid
        return
    end if

    scene = CreateObject("roSGNode", "PlayerScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.Show(m.pendingResume.mediaItemId, {
        item: m.pendingResume.item
        playbackInfo: resp.data
        resumeSeconds: m.pendingResume.resumeSeconds
    })

    m.pendingResume = invalid
end sub

' R7.2: Handle getItem response for an up-next item.
sub OnUpNextItemLoaded(resp as Object)
    if m.pendingUpNext = invalid then return

    if not resp.ok or resp.data = invalid then
        m.pendingUpNext = invalid
        return
    end if

    m.pendingUpNext.item = resp.data
    m.apiTask.request = { op: "getItemPlaybackInfo", itemId: m.pendingUpNext.mediaItemId }
    m.apiTask.control = "run"
end sub

' R7.2: Handle getItemPlaybackInfo response — launch PlayerScene for the up-next item.
sub OnUpNextPlaybackInfoLoaded(resp as Object)
    if m.pendingUpNext = invalid then return

    if not resp.ok or resp.data = invalid then
        m.pendingUpNext = invalid
        return
    end if

    scene = CreateObject("roSGNode", "PlayerScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")

    scene.Show(m.pendingUpNext.mediaItemId, {
        item: m.pendingUpNext.item
        playbackInfo: resp.data
        resumeSeconds: 0!
    })

    m.pendingUpNext = invalid
end sub

sub ShowLibrary(libraryId as String, libraryName as String)
    scene = CreateObject("roSGNode", "LibraryScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadLibrary(libraryId, libraryName)
end sub

' Open the music browser (Artists/Albums/Tracks). Reached by selecting a
' type="music" library tile; mirrors OnSearchPressed's create + focus.
sub ShowMusic()
    scene = CreateObject("roSGNode", "MusicScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

' Open the photos browser (date-album PosterGrid). Reached by selecting a
' type="photo" library tile; mirrors ShowLibrary's create + LoadLibrary.
sub ShowPhotos(libraryId as String, libraryName as String)
    name = libraryName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "PhotosScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadLibrary(libraryId, name)
end sub

sub OnSearchPressed(event as Object)
    scene = CreateObject("roSGNode", "SearchScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

sub OnFavoritesPressed(event as Object)
    scene = CreateObject("roSGNode", "FavoritesScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

sub OnCollectionsPressed(event as Object)
    scene = CreateObject("roSGNode", "CollectionsScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

sub OnForYouPressed(event as Object)
    scene = CreateObject("roSGNode", "RecommendationsScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

' Open the admin menu (AdminScene). Only reachable via the admin header button,
' which is shown only when m.isAdmin. Mirrors OnCollectionsPressed.
sub OnAdminPressed(event as Object)
    scene = CreateObject("roSGNode", "AdminScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

' Open the settings menu (SettingsScene). Available to all users.
sub OnSettingsPressed(event as Object)
    scene = CreateObject("roSGNode", "SettingsScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.SetFocus(true)
end sub

' Move focus into the header (search) zone, onto whichever header button
' m.headerCol currently points at (default "search"). Sets m.currentRail.
sub FocusHeaderZone()
    if m.headerCol = "forYou" and m.forYouButton <> invalid then
        m.forYouButton.SetFocus(true)
    else if m.headerCol = "favorites" and m.favoritesButton <> invalid then
        m.favoritesButton.SetFocus(true)
    else if m.headerCol = "collections" and m.collectionsButton <> invalid then
        m.collectionsButton.SetFocus(true)
    else if m.headerCol = "admin" and m.adminButton <> invalid then
        m.adminButton.SetFocus(true)
    else if m.searchButton <> invalid then
        m.searchButton.SetFocus(true)
        m.headerCol = "search"
    else if m.forYouButton <> invalid then
        m.forYouButton.SetFocus(true)
        m.headerCol = "forYou"
    else if m.favoritesButton <> invalid then
        m.favoritesButton.SetFocus(true)
        m.headerCol = "favorites"
    end if
    m.currentRail = "search"
end sub

' Bubble requestClose from a child scene up to PhlixApp (which holds PopScreen).
sub OnChildRequestClose()
    m.top.requestClose = true
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        ' Horizontal header nav: while in the "search" (header) zone, Left/Right
        ' cycle through the four header buttons (Search <-> Favorites <->
        ' Collections <-> Admin), stopping at the ends (never wrapping). The Admin
        ' button is only entered (Right from Collections) when m.isAdmin, so focus
        ' never lands on the hidden button. The header buttons never consume
        ' left/right themselves, so they bubble.
        if key = "left" and m.currentRail = "search" then
            if m.headerCol = "admin" and m.collectionsButton <> invalid then
                m.collectionsButton.SetFocus(true)
                m.headerCol = "collections"
                handled = true
            else if m.headerCol = "collections" and m.favoritesButton <> invalid then
                m.favoritesButton.SetFocus(true)
                m.headerCol = "favorites"
                handled = true
            else if m.headerCol = "favorites" and m.forYouButton <> invalid then
                m.forYouButton.SetFocus(true)
                m.headerCol = "forYou"
                handled = true
            else if m.headerCol = "forYou" and m.searchButton <> invalid then
                m.searchButton.SetFocus(true)
                m.headerCol = "search"
                handled = true
            end if
        else if key = "right" and m.currentRail = "search" then
            if m.headerCol = "search" and m.forYouButton <> invalid then
                m.forYouButton.SetFocus(true)
                m.headerCol = "forYou"
                handled = true
            else if m.headerCol = "forYou" and m.favoritesButton <> invalid then
                m.favoritesButton.SetFocus(true)
                m.headerCol = "favorites"
                handled = true
            else if m.headerCol = "favorites" and m.collectionsButton <> invalid then
                m.collectionsButton.SetFocus(true)
                m.headerCol = "collections"
                handled = true
            else if m.headerCol = "collections" and m.isAdmin and m.adminButton <> invalid then
                m.adminButton.SetFocus(true)
                m.headerCol = "admin"
                handled = true
            end if
        else if key = "down" then
            ' 3-zone vertical chain: search (top) <-> continue (if visible) <->
            ' library (bottom). Focus switching relies on PosterGrid/Button key
            ' bubbling: the header buttons never consume "down", a single-row
            ' continueGrid never consumes "up"/"down", and a multi-row
            ' libraryGrid never consumes "up" on its top row, so they bubble.
            if m.currentRail = "search" then
                if m.continueGrid.visible then
                    m.continueGrid.SetFocus(true)
                    m.currentRail = "continue"
                else
                    m.libraryGrid.SetFocus(true)
                    m.currentRail = "library"
                end if
                handled = true
            else if m.currentRail = "continue" then
                m.libraryGrid.SetFocus(true)
                m.currentRail = "library"
                handled = true
            end if
        else if key = "up" then
            if m.currentRail = "library" then
                if m.continueGrid.visible then
                    m.continueGrid.SetFocus(true)
                    m.currentRail = "continue"
                else
                    FocusHeaderZone()
                end if
                handled = true
            else if m.currentRail = "continue" then
                FocusHeaderZone()
                handled = true
            end if
        end if
    end if

    return handled
end sub