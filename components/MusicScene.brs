' components/MusicScene.brs

' copyright 2026 Joe Huss
'

'
' Music browser: Artists / Albums / Tracks modes shown as text LabelLists (music
' has no artwork). Mirrors HomeScene/SearchScene's ApiTask + OnApiResponse +
' index-guarded selection patterns. HomeScene self-creates + focuses this scene
' when a type="music" library tile is selected, so it has NO <interface>.
'
' Three header mode buttons drive m.mode ("artists"|"albums"|"tracks"); the
' focused button is tracked by m.modeCol (mirrors HomeScene's m.headerCol header
' nav). The CURRENT list is backed by m.rows so the LabelList itemSelected index
' maps to the right object. Artist browse filters the cached albums client-side
' via m.artistFilter (no per-artist endpoint is used).
'
' Track playback reuses the proven HomeScene resume chain (getItem ->
' getItemPlaybackInfo -> PlayerScene.Show), minus resumeSeconds, serialized
' through the single m.apiTask and guarded against double-select by m.pendingPlay.

sub Init()
    m.top.SetFocus(true)

    ' Header mode buttons.
    m.artistsButton = m.top.FindNode("artistsButton")
    if m.artistsButton <> invalid then
        m.artistsButton.ObserveField("buttonSelected", "OnArtistsMode")
    end if
    m.albumsButton = m.top.FindNode("albumsButton")
    if m.albumsButton <> invalid then
        m.albumsButton.ObserveField("buttonSelected", "OnAlbumsMode")
    end if
    m.tracksButton = m.top.FindNode("tracksButton")
    if m.tracksButton <> invalid then
        m.tracksButton.ObserveField("buttonSelected", "OnTracksMode")
    end if

    ' Text list.
    m.musicList = m.top.FindNode("musicList")
    if m.musicList <> invalid then
        m.musicList.ObserveField("itemSelected", "OnRowSelected")
        m.musicList.ObserveField("itemFocused", "OnRowFocused")
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread). Every op is serialized through this one task.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' State. Caches start invalid so each mode loads lazily on first view.
    m.mode = "albums"
    m.modeCol = "albums"
    m.zone = "modes"
    m.artistFilter = ""
    m.rows = []
    m.artists = invalid
    m.albums = invalid
    m.tracks = invalid
    m.pendingPlay = invalid

    ' Focus the default mode button (modes zone), then load the default mode.
    if m.albumsButton <> invalid then m.albumsButton.SetFocus(true)
    LoadMode("albums")
end sub

' Switch to a mode. Loads its data lazily when the cache is empty, else renders
' from cache immediately.
sub LoadMode(mode as String)
    ' Never issue a browse op while a play chain is in flight on the single
    ' task: that would leave two control="run" outstanding. m.pendingPlay clears
    ' when the chain launches the player or fails, so this only blocks the brief
    ' in-flight window (and the player is appended on top of this scene anyway).
    if m.pendingPlay <> invalid then return

    m.mode = mode

    if mode = "artists" then
        if m.artists = invalid then
            SetStatus("Loading…")
            m.apiTask.request = { op: "getArtists" }
            m.apiTask.control = "run"
        else
            RenderList()
        end if
    else if mode = "tracks" then
        if m.tracks = invalid then
            SetStatus("Loading…")
            m.apiTask.request = { op: "getTracks", options: { limit: 100 } }
            m.apiTask.control = "run"
        else
            RenderList()
        end if
    else
        ' albums
        if m.albums = invalid then
            SetStatus("Loading…")
            m.apiTask.request = { op: "getAlbums" }
            m.apiTask.control = "run"
        else
            RenderList()
        end if
    end if
end sub

sub OnArtistsMode(event as Object)
    m.modeCol = "artists"
    LoadMode("artists")
end sub

sub OnAlbumsMode(event as Object)
    m.modeCol = "albums"
    ' An explicit Albums press shows ALL albums (clear any artist filter).
    m.artistFilter = ""
    LoadMode("albums")
end sub

sub OnTracksMode(event as Object)
    m.modeCol = "tracks"
    LoadMode("tracks")
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getArtists" then
        m.artists = []
        if resp.ok and resp.data <> invalid and resp.data.artists <> invalid and type(resp.data.artists) = "roArray" then
            m.artists = resp.data.artists
        end if
        if m.mode = "artists" then RenderList()
    else if resp.op = "getAlbums" then
        m.albums = []
        if resp.ok and resp.data <> invalid and resp.data.albums <> invalid and type(resp.data.albums) = "roArray" then
            m.albums = resp.data.albums
        end if
        if m.mode = "albums" then RenderList()
    else if resp.op = "getTracks" then
        m.tracks = []
        if resp.ok and resp.data <> invalid and resp.data.tracks <> invalid and type(resp.data.tracks) = "roArray" then
            m.tracks = resp.data.tracks
        end if
        if m.mode = "tracks" then RenderList()
    else if resp.op = "getItem" then
        OnPlayItemResponse(resp)
    else if resp.op = "getItemPlaybackInfo" then
        OnPlayPlaybackInfoResponse(resp)
    end if
end sub

' Build the LabelList content + the m.rows backing array for the current mode.
sub RenderList()
    content = CreateObject("roSGNode", "ContentNode")
    m.rows = []
    emptyText = ""

    if m.mode = "artists" then
        emptyText = "No artists"
        list = m.artists
        if list <> invalid then
            for each artist in list
                if artist <> invalid then
                    title = ""
                    if artist.DoesExist("name") and artist.name <> invalid then title = artist.name
                    content.AddChild({ title: title })
                    m.rows.Push(artist)
                end if
            end for
        end if
    else if m.mode = "tracks" then
        emptyText = "No tracks"
        list = m.tracks
        if list <> invalid then
            for each track in list
                if track <> invalid then
                    content.AddChild({ title: TrackCaption(track) })
                    m.rows.Push(track)
                end if
            end for
        end if
    else
        ' albums (optionally filtered by m.artistFilter)
        emptyText = "No albums"
        list = m.albums
        if list <> invalid then
            for each album in list
                if album <> invalid then
                    include = true
                    if m.artistFilter <> "" then
                        albumArtist = ""
                        if album.DoesExist("artist") and album.artist <> invalid then albumArtist = album.artist
                        include = (albumArtist = m.artistFilter)
                    end if
                    if include then
                        content.AddChild({ title: AlbumCaption(album) })
                        m.rows.Push(album)
                    end if
                end if
            end for
        end if
    end if

    if m.musicList <> invalid then m.musicList.content = content

    if m.rows.Count() = 0 then
        SetStatus(emptyText)
    else
        SetStatus("")
    end if
end sub

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.rows.Count() then return

    row = m.rows[index]
    if row = invalid then return

    if m.mode = "artists" then
        ' Filter the albums list to this artist, then switch to albums mode
        ' WITHOUT clearing the filter (only the Albums button press clears it).
        name = ""
        if row.DoesExist("name") and row.name <> invalid then name = row.name
        m.artistFilter = name
        m.modeCol = "albums"
        LoadMode("albums")
    else if m.mode = "tracks" then
        id = ""
        if row.DoesExist("id") and row.id <> invalid then id = row.id
        if id <> "" then PlayTrack(id)
    else
        ' albums -> open the album's track listing.
        name = ""
        if row.DoesExist("name") and row.name <> invalid then name = row.name
        if name <> "" then ShowAlbum(name)
    end if
end sub

sub OnRowFocused(event as Object)
    m.zone = "list"

    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.rows.Count() then return

    row = m.rows[index]
    if row = invalid then return

    if m.mode = "artists" then
        if row.DoesExist("name") and row.name <> invalid then SetStatus(row.name)
    else if m.mode = "tracks" then
        SetStatus(TrackCaption(row))
    else
        SetStatus(AlbumCaption(row))
    end if
end sub

' Start the serialized play chain for a track id. Guarded so a rapid second
' select never leaves two control="run" outstanding on the single task.
sub PlayTrack(trackId as String)
    if m.pendingPlay <> invalid then return

    m.pendingPlay = { id: trackId, item: invalid }
    m.apiTask.request = { op: "getItem", itemId: trackId }
    m.apiTask.control = "run"
end sub

sub OnPlayItemResponse(resp as Object)
    if m.pendingPlay = invalid then return

    if not resp.ok or resp.data = invalid then
        m.pendingPlay = invalid
        return
    end if

    m.pendingPlay.item = resp.data
    m.apiTask.request = { op: "getItemPlaybackInfo", itemId: m.pendingPlay.id }
    m.apiTask.control = "run"
end sub

sub OnPlayPlaybackInfoResponse(resp as Object)
    if m.pendingPlay = invalid then return

    playbackInfo = invalid
    if resp.ok then playbackInfo = resp.data

    scene = CreateObject("roSGNode", "PlayerScene")
    m.top.Append(scene)
    scene.Show(m.pendingPlay.id, {
        item: m.pendingPlay.item
        playbackInfo: playbackInfo
    })

    m.pendingPlay = invalid
end sub

sub ShowAlbum(albumName as String)
    scene = CreateObject("roSGNode", "MusicAlbumScene")
    m.top.Append(scene)
    scene.LoadAlbum(albumName)
end sub

' Focus the header mode button that m.modeCol points at.
sub FocusModeButton()
    if m.modeCol = "artists" and m.artistsButton <> invalid then
        m.artistsButton.SetFocus(true)
    else if m.modeCol = "tracks" and m.tracksButton <> invalid then
        m.tracksButton.SetFocus(true)
    else if m.albumsButton <> invalid then
        m.albumsButton.SetFocus(true)
        m.modeCol = "albums"
    end if
    m.zone = "modes"
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.artistsButton <> invalid then m.artistsButton.UnObserveField("buttonSelected")
    if m.albumsButton <> invalid then m.albumsButton.UnObserveField("buttonSelected")
    if m.tracksButton <> invalid then m.tracksButton.UnObserveField("buttonSelected")
    if m.musicList <> invalid then
        m.musicList.UnObserveField("itemSelected")
        m.musicList.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        ' Header L/R among the three mode buttons while in the modes zone. The
        ' buttons never consume left/right themselves, so they bubble here.
        if key = "left" and m.zone = "modes" then
            if m.modeCol = "tracks" and m.albumsButton <> invalid then
                m.albumsButton.SetFocus(true)
                m.modeCol = "albums"
                handled = true
            else if m.modeCol = "albums" and m.artistsButton <> invalid then
                m.artistsButton.SetFocus(true)
                m.modeCol = "artists"
                handled = true
            end if
        else if key = "right" and m.zone = "modes" then
            if m.modeCol = "artists" and m.albumsButton <> invalid then
                m.albumsButton.SetFocus(true)
                m.modeCol = "albums"
                handled = true
            else if m.modeCol = "albums" and m.tracksButton <> invalid then
                m.tracksButton.SetFocus(true)
                m.modeCol = "tracks"
                handled = true
            end if
        else if key = "down" and m.zone = "modes" then
            ' Down from the header focuses the list. The mode buttons never
            ' consume "down", so this bubbles from the focused button.
            if m.musicList <> invalid then
                m.musicList.SetFocus(true)
                m.zone = "list"
                handled = true
            end if
        else if key = "up" and m.zone = "list" then
            ' Up from the list's top row returns to the focused mode button. A
            ' LabelList does not consume "up" on its top row, so it bubbles.
            FocusModeButton()
            handled = true
        else if key = "back" then
            Teardown()
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function