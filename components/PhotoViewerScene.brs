' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/PhotoViewerScene.brs

' copyright 2026 Joe Huss
'

'
' Full-screen photo viewer (F7a BASIC). Created + appended by PhotoAlbumScene,
' which calls the cross-component LoadPhotos (declared in the <interface>),
' passing the WHOLE photos array (by reference within the render thread) plus a
' start index. Shows one photo at a time in a full-screen Poster using the
' photo's SIGNED full_url (NO Bearer, NO URL building). Left/Right page through
' the album with wrap-around; Back closes.
'
' F7b adds a toggleable EXIF info overlay (read from the photo's already-loaded
' metadata) + a slideshow that auto-advances the in-memory m.photos array on a
' client Timer. Because the scene now observes the Timer's `fire`, it gains a
' Teardown() that the Back path calls before Close to avoid a leaked Timer.

sub Init()
    m.top.SetFocus(true)

    m.fullImage = m.top.FindNode("fullImage")
    m.captionLabel = m.top.FindNode("captionLabel")

    ' F7b: EXIF info overlay (hidden until Up is pressed).
    m.infoOverlay = m.top.FindNode("infoOverlay")
    m.infoLabel = m.top.FindNode("infoLabel")

    ' F7b: slideshow Timer, created in code (mirrors SearchScene). Repeating, 5s.
    m.slideshowTimer = m.top.CreateChild("Timer")
    m.slideshowTimer.duration = 5
    m.slideshowTimer.repeat = true
    m.slideshowTimer.ObserveField("fire", "OnSlideshowTick")

    m.photos = []
    m.index = 0

    ' F7b state.
    m.infoVisible = false
    m.slideshow = false
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

    ' F7b: refresh the EXIF overlay text every render (cheap; keeps it correct
    ' whenever it is shown). metadata may be absent or non-assoc -> guarded.
    if m.infoLabel <> invalid then
        summary = ""
        if photo.DoesExist("metadata") and photo.metadata <> invalid then
            summary = FormatExifSummary(photo.metadata)
        end if
        if summary = "" then
            m.infoLabel.text = "No photo info"
        else
            m.infoLabel.text = summary
        end if
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
            ' F7b: a manual move resets the slideshow dwell.
            if m.slideshow and m.slideshowTimer <> invalid then
                m.slideshowTimer.control = "stop"
                m.slideshowTimer.control = "start"
            end if
            handled = true
        else if key = "right" then
            if count > 1 then
                m.index = (m.index + 1) mod count
                RenderCurrent()
            end if
            ' F7b: a manual move resets the slideshow dwell.
            if m.slideshow and m.slideshowTimer <> invalid then
                m.slideshowTimer.control = "stop"
                m.slideshowTimer.control = "start"
            end if
            handled = true
        else if key = "up" then
            ' F7b: show the EXIF info overlay.
            m.infoVisible = true
            if m.infoOverlay <> invalid then m.infoOverlay.visible = true
            handled = true
        else if key = "down" then
            ' F7b: hide the EXIF info overlay.
            m.infoVisible = false
            if m.infoOverlay <> invalid then m.infoOverlay.visible = false
            handled = true
        else if key = "play" then
            ' F7b: dedicated Play/Pause remote key toggles the slideshow.
            ToggleSlideshow()
            handled = true
        else if key = "OK" then
            ' F7b: OK also toggles the slideshow (remotes without a Play key).
            ToggleSlideshow()
            handled = true
        else if key = "back" then
            ' F7b: stop the slideshow + tear down the Timer observer before close.
            StopSlideshow()
            Teardown()
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function

' F7b: flip the slideshow on/off. Never runs over a single photo (guard
' count > 1) and is a no-op when the Timer could not be created.
sub ToggleSlideshow()
    if m.slideshowTimer = invalid then return
    if m.photos.Count() <= 1 then return

    m.slideshow = not m.slideshow
    if m.slideshow then
        m.slideshowTimer.control = "start"
    else
        m.slideshowTimer.control = "stop"
    end if
end sub

' F7b: Timer fired -> advance one photo to the right with wrap. Guarded so a
' single (or empty) album never mods by zero.
sub OnSlideshowTick(event as Object)
    count = m.photos.Count()
    if count > 1 then
        m.index = (m.index + 1) mod count
        RenderCurrent()
    end if
end sub

' F7b: stop the slideshow and its Timer (safe when the Timer is invalid).
sub StopSlideshow()
    m.slideshow = false
    if m.slideshowTimer <> invalid then m.slideshowTimer.control = "stop"
end sub

' F7b: the scene now observes the Timer's `fire`, so pair it with an
' UnObserveField (and stop the Timer) on Back/close to avoid a leak.
sub Teardown()
    if m.slideshowTimer <> invalid then
        m.slideshowTimer.control = "stop"
        m.slideshowTimer.UnObserveField("fire")
    end if
end sub