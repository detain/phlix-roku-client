' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/PhotoAlbumScene.brs

' copyright 2026 Joe Huss
'

'
' Photo thumbnail grid for one date album. Created + appended by PhotosScene,
' which calls the cross-component LoadAlbum (declared in the <interface>).
' Fetches the album via getPhotoAlbum(albumId, libraryId); album.photos carry
' SIGNED thumbnail_url fields that drop straight into the PosterGrid
' HDPosterUrl (NO Bearer, NO URL building). Selecting a photo opens
' PhotoViewerScene, passing the WHOLE photos array (by reference within the
' render thread) plus the selected start index. Mirrors LibraryScene /
' MusicAlbumScene structure; the m.photos backing array maps the grid index to
' the right object.

sub Init()
    m.top.SetFocus(true)

    ' Photo thumbnail grid.
    m.photosGrid = m.top.FindNode("photosGrid")
    if m.photosGrid <> invalid then
        m.photosGrid.ObserveField("itemSelected", "OnPhotoSelected")
        m.photosGrid.ObserveField("itemFocused", "OnPhotoFocused")
    end if

    ' UI nodes.
    m.titleLabel = m.top.FindNode("titleLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.albumId = ""
    m.libraryId = ""
    m.photos = []
end sub

' Cross-component callable (declared in the <interface>). Loads one album's
' photos.
sub LoadAlbum(albumId as String, libraryId as String, title as String)
    m.albumId = albumId
    if albumId = invalid then m.albumId = ""

    m.libraryId = libraryId
    if libraryId = invalid then m.libraryId = ""

    name = title
    if name = invalid then name = ""
    if m.titleLabel <> invalid then m.titleLabel.text = name
    if m.statusLabel <> invalid then m.statusLabel.text = "Loading…"

    if m.albumId = "" or m.libraryId = "" then return

    m.apiTask.request = { op: "getPhotoAlbum", albumId: m.albumId, libraryId: m.libraryId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getPhotoAlbum" then
        OnPhotoAlbumResponse(resp)
    end if
end sub

sub OnPhotoAlbumResponse(resp as Object)
    if not resp.ok or resp.data = invalid or resp.data.album = invalid then
        m.photos = []
        if m.photosGrid <> invalid then m.photosGrid.content = CreateObject("roSGNode", "ContentNode")
        if m.statusLabel <> invalid then m.statusLabel.text = "No photos"
        return
    end if

    album = resp.data.album

    photos = []
    if album.DoesExist("photos") and album.photos <> invalid and type(album.photos) = "roArray" then
        photos = album.photos
    end if
    m.photos = photos

    content = CreateObject("roSGNode", "ContentNode")
    for each photo in m.photos
        if photo <> invalid then
            title = ""
            if photo.DoesExist("name") and photo.name <> invalid then title = photo.name

            posterUrl = "pkg:/images/placeholder.png"
            if photo.DoesExist("thumbnail_url") and photo.thumbnail_url <> invalid and photo.thumbnail_url <> "" then
                posterUrl = photo.thumbnail_url
            end if

            content.AddChild({
                Title: title
                ShortDescriptionLine1: title
                HDPosterUrl: posterUrl
            })
        end if
    end for

    if m.photosGrid <> invalid then m.photosGrid.content = content

    if m.statusLabel <> invalid then
        if m.photos.Count() = 0 then
            m.statusLabel.text = "No photos"
        else
            m.statusLabel.text = ""
        end if
    end if
end sub

sub OnPhotoSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.photos.Count() then return

    ShowViewer(index)
end sub

sub OnPhotoFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.photos.Count() then return

    photo = m.photos[index]
    if photo = invalid then return

    if m.statusLabel <> invalid then
        name = ""
        if photo.DoesExist("name") and photo.name <> invalid then name = photo.name
        m.statusLabel.text = name
    end if
end sub

sub ShowViewer(startIndex as Integer)
    ' The photos array is passed as a render-thread function argument
    ' (by-reference), NOT a node field write across a Task boundary.
    scene = CreateObject("roSGNode", "PhotoViewerScene")
    m.top.Append(scene)
    scene.LoadPhotos(m.photos, startIndex)
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.photosGrid <> invalid then
        m.photosGrid.UnObserveField("itemSelected")
        m.photosGrid.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
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