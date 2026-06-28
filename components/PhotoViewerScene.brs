' components/PhotoViewerScene.brs
'
' Full-screen photo viewer (F7a BASIC). Created + appended by PhotoAlbumScene,
' which calls the cross-component LoadPhotos (declared in the <interface>),
' passing the WHOLE photos array (by reference within the render thread) plus a
' start index. Shows one photo at a time in a full-screen Poster using the
' photo's SIGNED full_url (NO Bearer, NO URL building). Left/Right page through
' the album with wrap-around; Back closes.
'
' This scene observes NO fields, so it needs no Teardown. A single
' RenderCurrent() seam draws the current photo + caption; F7b extends it with
' an EXIF overlay + slideshow auto-advance (no EXIF / slideshow here).

sub Init()
    m.top.SetFocus(true)

    m.fullImage = m.top.FindNode("fullImage")
    m.captionLabel = m.top.FindNode("captionLabel")

    m.photos = []
    m.index = 0
end sub

' Cross-component callable (declared in the <interface>). Stores the photo
' array and the start index (clamped), then renders.
sub LoadPhotos(photos as Object, startIndex as Integer)
    if photos <> invalid and type(photos) = "roArray" then
        m.photos = photos
    else
        m.photos = []
    end if

    idx = startIndex
    if idx = invalid then idx = 0

    count = m.photos.Count()
    if count = 0 then
        m.index = 0
    else
        if idx < 0 then idx = 0
        if idx >= count then idx = count - 1
        m.index = idx
    end if

    RenderCurrent()
end sub

' Draw the current photo + caption. Single seam F7b extends (EXIF / slideshow).
sub RenderCurrent()
    count = m.photos.Count()
    if count = 0 then return

    ' Defensive clamp (callers always clamp, but keep RenderCurrent safe alone).
    if m.index < 0 then m.index = 0
    if m.index >= count then m.index = count - 1

    photo = m.photos[m.index]
    if photo = invalid then return

    if m.fullImage <> invalid then
        url = "pkg:/images/placeholder.png"
        if photo.DoesExist("full_url") and photo.full_url <> invalid and photo.full_url <> "" then
            url = photo.full_url
        end if
        m.fullImage.uri = url
    end if

    if m.captionLabel <> invalid then
        name = ""
        if photo.DoesExist("name") and photo.name <> invalid then name = photo.name
        m.captionLabel.text = name + "  (" + str(m.index + 1).trim() + " / " + str(count).trim() + ")"
    end if
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        count = m.photos.Count()

        if key = "left" then
            if count > 1 then
                m.index = (m.index - 1 + count) mod count
                RenderCurrent()
            end if
            handled = true
        else if key = "right" then
            if count > 1 then
                m.index = (m.index + 1) mod count
                RenderCurrent()
            end if
            handled = true
        else if key = "back" then
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function
