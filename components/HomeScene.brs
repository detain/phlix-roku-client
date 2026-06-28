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

    m.descriptionLabel = m.top.FindNode("descriptionLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread). Every op is serialized through this one task so two
    ' control="run" are never outstanding at once.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraries = []
    m.continueItems = []
    m.currentRail = "library"
    m.pendingResume = invalid

    ' Init load chain: libraries first, then continue-watching (fired from the
    ' getLibraries branch of OnApiResponse).
    LoadLibraries()
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

    if resp.op = "getLibraries" then
        OnLibrariesResponse(resp)
    else if resp.op = "getContinueWatching" then
        OnContinueWatchingResponse(resp)
    else if resp.op = "getItem" then
        OnResumeItemResponse(resp)
    else if resp.op = "getItemPlaybackInfo" then
        OnResumePlaybackInfoResponse(resp)
    end if
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

    ShowLibrary(library.id, library.name)
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

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        ' Focus switching relies on PosterGrid key bubbling: a single-row
        ' continueGrid never consumes "down" and a multi-row libraryGrid never
        ' consumes "up" on its top row, so both bubble here.
        if key = "down" and m.currentRail = "continue" then
            m.libraryGrid.SetFocus(true)
            m.currentRail = "library"
            handled = true
        else if key = "up" and m.currentRail = "library" and m.continueGrid.visible then
            m.continueGrid.SetFocus(true)
            m.currentRail = "continue"
            handled = true
        end if
    end if

    return handled
end sub
