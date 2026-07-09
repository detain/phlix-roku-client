'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/MusicAlbumScene.brs

' copyright 2026 Joe Huss
'

'
' Track listing for one album. Created + appended by MusicScene, which calls the
' cross-component LoadAlbum (declared in the <interface>). Fetches the album via
' getAlbum(name); album.tracks are RAW media rows, so each is flattened by
' Utilities.NormalizeAlbumTrack and sorted by Utilities.SortByTrackOrder before
' being shown in a text LabelList (music has no artwork).
'
' Track playback reuses the proven getItem -> getItemPlaybackInfo ->
' PlayerScene.Show chain, serialized through the single m.apiTask and guarded
' against double-select by m.pendingPlay (mirrors MusicScene / HomeScene).

sub Init()
    m.top.SetFocus(true)

    m.titleLabel = m.top.FindNode("titleLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    m.trackList = m.top.FindNode("trackList")
    if m.trackList <> invalid then
        m.trackList.ObserveField("itemSelected", "OnTrackSelected")
        m.trackList.ObserveField("itemFocused", "OnTrackFocused")
        m.trackList.SetFocus(true)
    end if

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.albumName = ""
    m.tracks = []
    m.pendingPlay = invalid
end sub

' Cross-component callable (declared in the <interface>). Loads one album's tracks.
sub LoadAlbum(albumName as String)
    m.albumName = albumName
    if albumName = invalid then m.albumName = ""

    if m.titleLabel <> invalid then m.titleLabel.text = m.albumName
    if m.statusLabel <> invalid then m.statusLabel.text = "Loading…"

    if m.albumName = "" then return

    m.apiTask.request = { op: "getAlbum", albumName: m.albumName }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getAlbum" then
        OnAlbumResponse(resp)
    else if resp.op = "getItem" then
        OnPlayItemResponse(resp)
    else if resp.op = "getItemPlaybackInfo" then
        OnPlayPlaybackInfoResponse(resp)
    end if
end sub

sub OnAlbumResponse(resp as Object)
    if not resp.ok or resp.data = invalid or resp.data.album = invalid then
        m.tracks = []
        if m.trackList <> invalid then m.trackList.content = CreateObject("roSGNode", "ContentNode")
        if m.statusLabel <> invalid then m.statusLabel.text = "No tracks"
        return
    end if

    album = resp.data.album

    ' Richer header: "<name> — <artist> (<year>)".
    if m.titleLabel <> invalid then m.titleLabel.text = AlbumCaption(album)

    ' album.tracks are RAW media rows: flatten each, then sort by disc/track.
    normalized = []
    if album.DoesExist("tracks") and album.tracks <> invalid and type(album.tracks) = "roArray" then
        for each raw in album.tracks
            normalized.Push(NormalizeAlbumTrack(raw))
        end for
    end if
    m.tracks = SortByTrackOrder(normalized)

    content = CreateObject("roSGNode", "ContentNode")
    for each track in m.tracks
        content.AddChild({ title: TrackCaption(track) })
    end for
    if m.trackList <> invalid then m.trackList.content = content

    if m.statusLabel <> invalid then
        if m.tracks.Count() = 0 then
            m.statusLabel.text = "No tracks"
        else
            m.statusLabel.text = ""
        end if
    end if
end sub

sub OnTrackSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.tracks.Count() then return

    track = m.tracks[index]
    if track = invalid then return

    id = ""
    if track.DoesExist("id") and track.id <> invalid then id = track.id
    if id = "" then return

    PlayTrack(id)
end sub

sub OnTrackFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.tracks.Count() then return

    track = m.tracks[index]
    if track = invalid then return

    if m.statusLabel <> invalid then m.statusLabel.text = TrackCaption(track)
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

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.trackList <> invalid then
        m.trackList.UnObserveField("itemSelected")
        m.trackList.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function