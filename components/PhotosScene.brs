' components/PhotosScene.brs

' copyright 2026 Joe Huss
'

'
' Date-album grid for a type="photo" library (entry point for the photos
' browse flow). Created + appended + driven by HomeScene, which calls the
' cross-component LoadLibrary (declared in the <interface>). Fetches the album
' list via getPhotoAlbums(libraryId); albums are shown in a PosterGrid using
' each album's SIGNED cover_photo.thumbnail_url (photos HAVE artwork, unlike
' music). Selecting an album opens PhotoAlbumScene. Mirrors LibraryScene's
' ApiTask + OnApiResponse + index-guarded selection + HDPosterUrl/placeholder
' fallback patterns. The m.albums backing array maps the grid index to the
' right object.

sub Init()
    m.top.SetFocus(true)

    ' Album poster grid.
    m.albumsGrid = m.top.FindNode("albumsGrid")
    if m.albumsGrid <> invalid then
        m.albumsGrid.ObserveField("itemSelected", "OnAlbumSelected")
        m.albumsGrid.ObserveField("itemFocused", "OnAlbumFocused")
    end if

    ' UI nodes.
    m.titleLabel = m.top.FindNode("titleLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraryId = ""
    m.libraryName = ""
    m.albums = []
end sub

' Cross-component callable (declared in the <interface>). Loads a photo
' library's date albums.
sub LoadLibrary(libraryId as String, libraryName as String)
    m.libraryId = libraryId
    if libraryId = invalid then m.libraryId = ""

    m.libraryName = libraryName
    if libraryName = invalid then m.libraryName = ""

    if m.titleLabel <> invalid then m.titleLabel.text = m.libraryName
    if m.statusLabel <> invalid then m.statusLabel.text = "Loading…"

    if m.libraryId = "" then return

    m.apiTask.request = { op: "getPhotoAlbums", libraryId: m.libraryId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getPhotoAlbums" then
        OnPhotoAlbumsResponse(resp)
    end if
end sub

sub OnPhotoAlbumsResponse(resp as Object)
    if not resp.ok or resp.data = invalid or resp.data.albums = invalid or type(resp.data.albums) <> "roArray" then
        m.albums = []
        if m.albumsGrid <> invalid then m.albumsGrid.content = CreateObject("roSGNode", "ContentNode")
        if m.statusLabel <> invalid then m.statusLabel.text = "No photos"
        return
    end if

    m.albums = resp.data.albums

    content = CreateObject("roSGNode", "ContentNode")
    for each album in m.albums
        if album <> invalid then
            caption = PhotoAlbumCaption(album)

            count = 0
            if album.DoesExist("photo_count") and album.photo_count <> invalid then count = Int(album.photo_count)

            posterUrl = "pkg:/images/placeholder.png"
            if album.DoesExist("cover_photo") and album.cover_photo <> invalid and type(album.cover_photo) = "roAssociativeArray" then
                cover = album.cover_photo
                if cover.DoesExist("thumbnail_url") and cover.thumbnail_url <> invalid and cover.thumbnail_url <> "" then
                    posterUrl = cover.thumbnail_url
                end if
            end if

            content.AddChild({
                Title: caption
                ShortDescriptionLine1: caption
                ShortDescriptionLine2: str(count).trim() + " photos"
                HDPosterUrl: posterUrl
            })
        end if
    end for

    if m.albumsGrid <> invalid then m.albumsGrid.content = content

    if m.statusLabel <> invalid then
        if m.albums.Count() = 0 then
            m.statusLabel.text = "No photos"
        else
            m.statusLabel.text = ""
        end if
    end if
end sub

sub OnAlbumSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.albums.Count() then return

    album = m.albums[index]
    if album = invalid then return

    albumId = ""
    if album.DoesExist("id") and album.id <> invalid then albumId = album.id
    if albumId = "" then return

    ShowAlbum(albumId, PhotoAlbumCaption(album))
end sub

sub OnAlbumFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.albums.Count() then return

    album = m.albums[index]
    if album = invalid then return

    count = 0
    if album.DoesExist("photo_count") and album.photo_count <> invalid then count = Int(album.photo_count)

    if m.statusLabel <> invalid then
        m.statusLabel.text = PhotoAlbumCaption(album) + "  (" + str(count).trim() + " photos)"
    end if
end sub

sub ShowAlbum(albumId as String, title as String)
    name = title
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "PhotoAlbumScene")
    m.top.Append(scene)
    scene.LoadAlbum(albumId, m.libraryId, name)
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.albumsGrid <> invalid then
        m.albumsGrid.UnObserveField("itemSelected")
        m.albumsGrid.UnObserveField("itemFocused")
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