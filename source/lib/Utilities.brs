' source/lib/Utilities.brs

' ===========================================
' Utility Functions for Roku
' Helper functions used throughout the app
' ===========================================

' Format seconds to time string (HH:MM:SS or MM:SS)
function FormatTime(seconds as Float) as String
    hours = Int(seconds / 3600)
    minutes = Int((seconds mod 3600) / 60)
    secs = Int(seconds mod 60)

    if hours > 0 then
        return str(hours).trim() + ":" + str(minutes).Trim().Right(2).Repl(" ", "0") + ":" + str(secs).Trim().Right(2).Repl(" ", "0")
    else
        return str(minutes).Trim() + ":" + str(secs).Trim().Right(2).Repl(" ", "0")
    end if
end function

' Parse a time string to seconds
function ParseTime(timeString as String) as Float
    parts = timeString.split(":")
    if parts.Count() = 3 then
        return Val(parts[0]) * 3600 + Val(parts[1]) * 60 + Val(parts[2])
    else if parts.Count() = 2 then
        return Val(parts[0]) * 60 + Val(parts[1])
    end if
    return 0
end function

' Truncate string with ellipsis
function TruncateString(str as String, maxLength as Integer) as String
    if str.Len() > maxLength then
        return str.Left(maxLength - 3) + "..."
    end if
    return str
end function

' Validate URL format
function IsValidUrl(url as String) as Boolean
    if url <> invalid and url <> "" then
        if url.Left(7).Lower() = "http://" or url.Left(8).Lower() = "https://" then
            return true
        end if
    end if
    return false
end function

' Get file extension from URL
function GetFileExtension(url as String) as String
    parts = url.Split("/")
    if parts.Count() > 0 then
        filename = parts[parts.Count() - 1]
        extParts = filename.Split(".")
        if extParts.Count() > 1 then
            return extParts[extParts.Count() - 1].Lower()
        end if
    end if
    return ""
end function

' Determine stream format from container
function GetStreamFormat(container as String) as String
    container = container.Lower()
    if container = "mp4" or container = "m4v" then
        return "mp4"
    else if container = "mkv" then
        return "mkv"
    else if container = "mov" then
        return "mov"
    else if container = "ts" then
        return "mpegts"
    else if container = "webm" then
        return "webm"
    else if container = "m3u8" then
        return "hls"
    end if
    return "mp4"
end function

' Escape string for display
function EscapeString(str as String) as String
    return str.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("""", "&quot;")
end function

' Unescape string from display
function UnescapeString(str as String) as String
    return str.Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", """").Replace("&amp;", "&")
end function

' Create content node with poster info
function CreatePosterContent(item as Object) as Object
    content = CreateObject("roSGNode", "ContentNode")

    if item.DoesExist("id") then content.id = item.id
    if item.DoesExist("name") then content.Title = item.name
    if item.DoesExist("sortName") then content.ShortDescriptionLine1 = item.sortName
    if item.DoesExist("overview") then content.Description = item.overview
    if item.DoesExist("thumb") then content.HDPosterUrl = item.thumb
    if item.DoesExist("parentThumb") then content.HDPosterUrl = item.parentThumb
    if item.DoesExist("type") then content.Type = item.type

    return content
end function

' Sleep for specified milliseconds
function SleepMs(milliseconds as Integer)
    sleep(milliseconds)
end function

' Generate random ID
function GenerateRandomId() as String
    return str(Rnd(999999999)).trim() + "-" + str(Rnd(999999999)).trim()
end function

' Join an array of strings with a separator (BrightScript roArray has no join).
' @param parts Object - array of String values
' @param sep String - the separator
' @return String - the joined result
function JoinStrings(parts as Object, sep as String) as String
    result = ""
    if parts = invalid then return result
    for i = 0 to parts.Count() - 1
        if i > 0 then result = result + sep
        result = result + parts[i]
    end for
    return result
end function

' URL-encode a string (percent-encode the URL-significant characters). Lives in
' Utilities so any component that includes Utilities + ApiClient can resolve it.
' @param str String - the raw value
' @return String - the encoded value
function UrlEncode(str as String) as String
    result = ""
    if str = invalid then return result
    for i = 1 to Len(str)
        c = Mid(str, i, 1)
        if c = " " then
            result = result + "%20"
        else if c = "&" then
            result = result + "%26"
        else if c = "=" then
            result = result + "%3D"
        else if c = "?" then
            result = result + "%3F"
        else if c = "/" then
            result = result + "%2F"
        else if c = ":" then
            result = result + "%3A"
        else if c = "#" then
            result = result + "%23"
        else if c = "[" then
            result = result + "%5B"
        else if c = "]" then
            result = result + "%5D"
        else
            result = result + c
        end if
    end for
    return result
end function

' Convert seconds (Float) to 100ns ticks (LongInteger). Double math (52-bit mantissa) keeps
' large values exact; the LongInteger return coerces the truncation. Float*1e7 would lose
' precision AND a 32-bit Int() overflows past ~214s.
function SecondsToTicks(seconds as Double) as LongInteger
    return seconds * 10000000.0
end function

' Show an error to the user. Placeholder logging implementation; the player /
' detail slices replace this with a proper SceneGraph Dialog.
' @param message String - the error message
sub ShowErrorDialog(message as String)
    print "Error: " + message
end sub

' Coerce a media-item's numeric sort key to an Integer, mapping invalid/missing
' to a large sentinel so unsorted/null values sort LAST and deterministically.
' @param item Object - a media-item assocarray (may be invalid)
' @param key String - the assoc key to read (e.g. "season_number")
' @return Integer - the value, or 999999 when invalid/missing/non-numeric
function SortKeyValue(item as Object, key as String) as Integer
    if item = invalid then return 999999
    if not item.DoesExist(key) then return 999999
    value = item[key]
    if value = invalid then return 999999
    ' Coerce; non-numeric assoc values box to 0, which is acceptable for ints.
    return Int(value)
end function

' Non-mutating insertion sort of an array of media-item assocarrays by
' season_number then episode_number. Invalid/missing numbers sort last (sentinel
' 999999). N is small (seasons/episodes per parent), so O(n^2) insertion sort is
' clear, deterministic, and avoids roArray.SortBy's missing-key quirks. Returns a
' NEW array; the input is not modified.
' @param items Object - array of media-item assocarrays (may be invalid)
' @return Object - a new sorted array (empty array when input is invalid)
function SortByEpisodeOrder(items as Object) as Object
    sorted = []
    if items = invalid then return sorted

    for each item in items
        ' Find the insertion index in `sorted` for this item.
        sKey = SortKeyValue(item, "season_number")
        eKey = SortKeyValue(item, "episode_number")
        insertAt = sorted.Count()

        for i = 0 to sorted.Count() - 1
            existing = sorted[i]
            existS = SortKeyValue(existing, "season_number")
            existE = SortKeyValue(existing, "episode_number")
            if sKey < existS or (sKey = existS and eKey < existE) then
                insertAt = i
                exit for
            end if
        end for

        if insertAt >= sorted.Count() then
            sorted.Push(item)
        else
            sorted.Unshift(invalid)
            ' Shift tail right by one, then drop the new value in.
            for j = sorted.Count() - 1 to insertAt + 1 step -1
                sorted[j] = sorted[j - 1]
            end for
            sorted[insertAt] = item
        end if
    end for

    return sorted
end function

' Build a one-line caption for an episode list row. When episode_number is
' present: "E<n>. <episode_title or name>"; otherwise just the name. Guards every
' invalid/missing field.
' @param item Object - an episode media-item assocarray (may be invalid)
' @return String - the caption (empty string when item is invalid)
function EpisodeCaption(item as Object) as String
    if item = invalid then return ""

    title = ""
    if item.DoesExist("episode_title") and item.episode_title <> invalid and item.episode_title <> "" then
        title = item.episode_title
    else if item.DoesExist("name") and item.name <> invalid then
        title = item.name
    end if

    if item.DoesExist("episode_number") and item.episode_number <> invalid then
        return "E" + str(Int(item.episode_number)).trim() + ". " + title
    end if

    return title
end function

' Flatten a RAW album-track row (from /music/albums/{name}) into the flat shape
' the music UI consumes: {id,name,artist,track_number,disc_number,duration_secs}.
' The interesting fields live under metadata.* on raw rows; read top-level first,
' then metadata fallback. metadata may arrive as a non-assoc string, so only read
' its keys when it is an roAssociativeArray (mirrors HomeScene.ContinuePosterUrl).
' The raw row's top-level `id` IS the playable media_item id. Guards invalid.
' @param raw Object - a raw media-item row (may be invalid)
' @return Object - the flattened track assocarray (sentinel {} when raw invalid)
function NormalizeAlbumTrack(raw as Object) as Object
    track = { id: "", name: "", artist: "", track_number: 0, disc_number: 0, duration_secs: 0 }
    if raw = invalid then return track

    ' Pull the optional metadata sub-object (only when it parsed to an assoc).
    meta = invalid
    if raw.DoesExist("metadata") and raw.metadata <> invalid then
        if type(raw.metadata) = "roAssociativeArray" then meta = raw.metadata
    end if

    ' id is always top-level on the raw row.
    if raw.DoesExist("id") and raw.id <> invalid then track.id = raw.id

    ' name = metadata.title -> top-level name -> "".
    if meta <> invalid and meta.DoesExist("title") and meta.title <> invalid and meta.title <> "" then
        track.name = meta.title
    else if raw.DoesExist("name") and raw.name <> invalid then
        track.name = raw.name
    end if

    ' artist: top-level then metadata.
    if raw.DoesExist("artist") and raw.artist <> invalid then
        track.artist = raw.artist
    else if meta <> invalid and meta.DoesExist("artist") and meta.artist <> invalid then
        track.artist = meta.artist
    end if

    ' track_number / disc_number: top-level then metadata; default 0.
    if raw.DoesExist("track_number") and raw.track_number <> invalid then
        track.track_number = Int(raw.track_number)
    else if meta <> invalid and meta.DoesExist("track_number") and meta.track_number <> invalid then
        track.track_number = Int(meta.track_number)
    end if

    if raw.DoesExist("disc_number") and raw.disc_number <> invalid then
        track.disc_number = Int(raw.disc_number)
    else if meta <> invalid and meta.DoesExist("disc_number") and meta.disc_number <> invalid then
        track.disc_number = Int(meta.disc_number)
    end if

    ' duration_secs: top-level then metadata; default 0.
    if raw.DoesExist("duration_secs") and raw.duration_secs <> invalid then
        track.duration_secs = Int(raw.duration_secs)
    else if meta <> invalid and meta.DoesExist("duration_secs") and meta.duration_secs <> invalid then
        track.duration_secs = Int(meta.duration_secs)
    end if

    return track
end function

' Non-mutating insertion sort of a (normalized) track array by disc_number then
' track_number. Invalid/missing numbers sort LAST (sentinel 999999) so unnumbered
' tracks sink to the end. Mirrors SortByEpisodeOrder. Returns a NEW array; the
' input is not modified. Guards non-array input -> [].
' @param tracks Object - array of normalized track assocarrays (may be invalid)
' @return Object - a new sorted array (empty array when input is invalid)
function SortByTrackOrder(tracks as Object) as Object
    sorted = []
    if tracks = invalid then return sorted

    for each track in tracks
        dKey = SortKeyValue(track, "disc_number")
        tKey = SortKeyValue(track, "track_number")
        ' SortKeyValue returns the value (0 for unnumbered); promote 0 to the
        ' end-sentinel so unnumbered tracks sink below numbered ones.
        if dKey = 0 then dKey = 999999
        if tKey = 0 then tKey = 999999
        insertAt = sorted.Count()

        for i = 0 to sorted.Count() - 1
            existing = sorted[i]
            existD = SortKeyValue(existing, "disc_number")
            existT = SortKeyValue(existing, "track_number")
            if existD = 0 then existD = 999999
            if existT = 0 then existT = 999999
            if dKey < existD or (dKey = existD and tKey < existT) then
                insertAt = i
                exit for
            end if
        end for

        if insertAt >= sorted.Count() then
            sorted.Push(track)
        else
            sorted.Unshift(invalid)
            for j = sorted.Count() - 1 to insertAt + 1 step -1
                sorted[j] = sorted[j - 1]
            end for
            sorted[insertAt] = track
        end if
    end for

    return sorted
end function

' Build a one-line caption for a track list row: "<track_number>. <name>" when
' track_number>0 else just <name>; appends "  (mm:ss)" via FormatTime when
' duration_secs>0. Guards invalid.
' @param track Object - a normalized track assocarray (may be invalid)
' @return String - the caption (empty string when track is invalid)
function TrackCaption(track as Object) as String
    if track = invalid then return ""

    name = ""
    if track.DoesExist("name") and track.name <> invalid then name = track.name

    caption = name
    if track.DoesExist("track_number") and track.track_number <> invalid and Int(track.track_number) > 0 then
        caption = str(Int(track.track_number)).trim() + ". " + name
    end if

    if track.DoesExist("duration_secs") and track.duration_secs <> invalid and Int(track.duration_secs) > 0 then
        caption = caption + "  (" + FormatTime(track.duration_secs) + ")"
    end if

    return caption
end function

' Build a one-line caption for an album list row: "<name> — <artist>" plus
' " (<year>)" when a year is present. Guards every invalid/missing field.
' @param album Object - an album assocarray (may be invalid)
' @return String - the caption (empty string when album is invalid)
function AlbumCaption(album as Object) as String
    if album = invalid then return ""

    name = ""
    if album.DoesExist("name") and album.name <> invalid then name = album.name

    caption = name
    if album.DoesExist("artist") and album.artist <> invalid and album.artist <> "" then
        caption = caption + " — " + album.artist
    end if

    if album.DoesExist("year") and album.year <> invalid then
        yearStr = str(Int(album.year)).trim()
        if yearStr <> "0" then caption = caption + " (" + yearStr + ")"
    end if

    return caption
end function

' Build the label for a photo album: its date ("YYYY-MM-DD"), mapping the
' server sentinel "Unknown" (and invalid/empty) -> "Undated". Guards invalid.
' @param album Object - a photo-album assocarray (may be invalid)
' @return String - the album date label, or "Undated"
function PhotoAlbumCaption(album as Object) as String
    if album = invalid then return "Undated"

    date = ""
    if album.DoesExist("date") and album.date <> invalid then date = album.date

    if date = "" or date = "Unknown" then return "Undated"

    return date
end function