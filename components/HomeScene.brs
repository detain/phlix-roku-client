' source/components/HomeScene.brs

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

    ' Admin entry (header, beside Collections). Hidden by default (visible="false"
    ' in XML); revealed only when the current user is_admin (see OnMeResponse).
    ' Opens the AdminScene menu.
    m.adminButton = m.top.FindNode("adminButton")
    if m.adminButton <> invalid then
        m.adminButton.ObserveField("buttonSelected", "OnAdminPressed")
    end if

    m.descriptionLabel = m.top.FindNode("descriptionLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread). Every op is serialized through this one task so two
    ' control="run" are never outstanding at once.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraries = []
    m.continueItems = []
    m.currentRail = "library"
    ' Which header button is focused while m.currentRail = "search":
    ' "search", "favorites", "collections" or "admin" (default "search").
    ' "admin" is only ever reached when m.isAdmin (the button is otherwise hidden).
    m.headerCol = "search"
    m.isAdmin = false
    m.pendingResume = invalid

    ' Init load chain (serialized through the single task): getMe FIRST (gates the
    ' admin button), which then chains libraries -> continue-watching from the
    ' getMe branch of OnApiResponse.
    LoadMe()
end sub

' Fetch the current user (GET /auth/me). The response gates the admin button and
' then continues the original chain (libraries -> continue-watching).
sub LoadMe()
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

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getMe" then
        OnMeResponse(resp)
    else if resp.op = "getLibraries" then
        OnLibrariesResponse(resp)
    else if resp.op = "getContinueWatching" then
        OnContinueWatchingResponse(resp)
    else if resp.op = "getItem" then
        OnResumeItemResponse(resp)
    else if resp.op = "getItemPlaybackInfo" then
        OnResumePlaybackInfoResponse(resp)
    end if
end sub

' getMe response: gate the admin button via IsAdminUser, then continue the
' original load chain (libraries -> continue-watching) regardless of admin state.
sub OnMeResponse(resp as Object)
    if resp.ok and resp.data <> invalid then
        m.isAdmin = IsAdminUser(resp.data)
        if m.isAdmin and m.adminButton <> invalid then m.adminButton.visible = true
    end if
    LoadLibraries()   ' continue the original chain regardless of admin state
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

    ' Chain continue-watching AFTER libraries (serialized through one task).
    LoadContinueWatching()
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

    ' Surface the rail and move focus to it.
    m.continueGrid.SetFocus(true)
    m.currentRail = "continue"
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
    scene.Show(m.pendingResume.mediaItemId, {
        item: m.pendingResume.item
        playbackInfo: resp.data
        resumeSeconds: m.pendingResume.resumeSeconds
    })

    m.pendingResume = invalid
end sub

sub ShowLibrary(libraryId as String, libraryName as String)
    scene = CreateObject("roSGNode", "LibraryScene")
    m.top.Append(scene)
    scene.LoadLibrary(libraryId, libraryName)
end sub

' Open the music browser (Artists/Albums/Tracks). Reached by selecting a
' type="music" library tile; mirrors OnSearchPressed's create + focus.
sub ShowMusic()
    scene = CreateObject("roSGNode", "MusicScene")
    m.top.Append(scene)
    scene.SetFocus(true)
end sub

' Open the photos browser (date-album PosterGrid). Reached by selecting a
' type="photo" library tile; mirrors ShowLibrary's create + LoadLibrary.
sub ShowPhotos(libraryId as String, libraryName as String)
    name = libraryName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "PhotosScene")
    m.top.Append(scene)
    scene.LoadLibrary(libraryId, name)
end sub

sub OnSearchPressed(event as Object)
    scene = CreateObject("roSGNode", "SearchScene")
    m.top.Append(scene)
    scene.SetFocus(true)
end sub

sub OnFavoritesPressed(event as Object)
    scene = CreateObject("roSGNode", "FavoritesScene")
    m.top.Append(scene)
    scene.SetFocus(true)
end sub

sub OnCollectionsPressed(event as Object)
    scene = CreateObject("roSGNode", "CollectionsScene")
    m.top.Append(scene)
    scene.SetFocus(true)
end sub

' Open the admin menu (AdminScene). Only reachable via the admin header button,
' which is shown only when m.isAdmin. Mirrors OnCollectionsPressed.
sub OnAdminPressed(event as Object)
    scene = CreateObject("roSGNode", "AdminScene")
    m.top.Append(scene)
    scene.SetFocus(true)
end sub

' Move focus into the header (search) zone, onto whichever header button
' m.headerCol currently points at (default "search"). Sets m.currentRail.
sub FocusHeaderZone()
    if m.headerCol = "favorites" and m.favoritesButton <> invalid then
        m.favoritesButton.SetFocus(true)
    else if m.headerCol = "collections" and m.collectionsButton <> invalid then
        m.collectionsButton.SetFocus(true)
    else if m.headerCol = "admin" and m.adminButton <> invalid then
        m.adminButton.SetFocus(true)
    else if m.searchButton <> invalid then
        m.searchButton.SetFocus(true)
        m.headerCol = "search"
    else if m.favoritesButton <> invalid then
        m.favoritesButton.SetFocus(true)
        m.headerCol = "favorites"
    end if
    m.currentRail = "search"
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
            else if m.headerCol = "favorites" and m.searchButton <> invalid then
                m.searchButton.SetFocus(true)
                m.headerCol = "search"
                handled = true
            end if
        else if key = "right" and m.currentRail = "search" then
            if m.headerCol = "search" and m.favoritesButton <> invalid then
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
