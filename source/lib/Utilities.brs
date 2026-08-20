'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/Utilities.brs

' copyright 2026 Joe Huss
'


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

' Format a UNIX epoch timestamp (seconds) as a short local "M/D H:MM" wall-clock
' string for guide/recording captions. Distinct from FormatTime (a DURATION
' formatter). roDateTime.FromSeconds takes an Integer; UNIX seconds fit in 32-bit
' until 2038 so Int() is safe (unlike 100ns ticks - see SecondsToTicks).
function FormatUnixTime(seconds as Double) as String
    if seconds <= 0 then return ""
    dt = CreateObject("roDateTime")
    dt.FromSeconds(Int(seconds))
    dt.ToLocalTime()
    minute = str(dt.GetMinutes()).trim()
    if Len(minute) < 2 then minute = "0" + minute
    return str(dt.GetMonth()).trim() + "/" + str(dt.GetDayOfMonth()).trim() + " " + str(dt.GetHours()).trim() + ":" + minute
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

' Normalize a raw server/hub URL typed on the Connect screen into a bare origin
' ApiClient can consume (ApiClient builds {baseUrl} + "/api/v1" + path). Trims
' surrounding whitespace; keeps an explicit http://|https:// scheme; otherwise
' infers the scheme from the host (local hosts -> http://, everything else ->
' https://); finally strips a single trailing "/". Guards invalid/empty -> "".
' @param raw String - the user-entered URL (may be invalid)
' @return String - the normalized bare origin (empty string when nothing usable)
function NormalizeServerUrl(raw as String) as String
    if raw = invalid then return ""

    url = raw.Trim()
    if url = "" then return ""

    lower = url.Lower()
    if lower.Left(7) = "http://" or lower.Left(8) = "https://" then
        ' Explicit scheme - keep as typed.
    else
        ' Infer scheme from the host. Local/private hosts default to http://,
        ' everything else (a real domain) to https://.
        ' R4.7 fix: only apply RFC1918 checks to actual IP addresses (not hostnames
        ' like "10th-street.example.com" that happen to start with a private prefix).
        isLocal = false

        ' Extract just the host portion (strip any path / port)
        host = lower
        slashPos = Instr(1, host, "/")
        if slashPos > 0 then host = Left(host, slashPos - 1)
        colonPos = Instr(1, host, ":")
        if colonPos > 0 then host = Left(host, colonPos - 1)

        ' Only apply RFC1918 checks when host is a dotted-quad IP (all 4 parts numeric)
        if host <> "" then
            parts = host.Split(".")
            if parts.Count() = 4 then
                allNumeric = true
                for each p in parts
                    ' Len check + digit check: each part must be 1-3 digits
                    if Len(p) < 1 or Len(p) > 3 then
                        allNumeric = false
                        exit for
                    end if
                    for i = 1 to Len(p)
                        c = Mid(p, i, 1)
                        if c < "0" or c > "9" then
                            allNumeric = false
                            exit for
                        end if
                    end for
                    if not allNumeric then exit for
                end for

                if allNumeric then
                    ' Now safe to apply RFC1918 range checks (parts are IP octets)
                    if parts[0] = "10" then isLocal = true
                    if parts[0] = "192" and parts[1] = "168" then isLocal = true
                    if parts[0] = "172" then
                        octet = 0
                        for i = 1 to Len(parts[1])
                            octet = octet * 10 + Asc(Mid(parts[1], i, 1)) - 48
                        end for
                        if octet >= 16 and octet <= 31 then isLocal = true
                    end if
                end if
            end if
        end if

        if isLocal then
            url = "http://" + url
        else
            url = "https://" + url
        end if
    end if

    ' Strip a single trailing slash so ApiClient's "/api/v1" concat stays clean.
    if Len(url) > 0 and Right(url, 1) = "/" then
        url = Left(url, Len(url) - 1)
    end if

    return url
end function

' True when a parsed /health JSON body indicates a reachable Phlix host. The body
' is {status:"ok", service, version, ...}; we accept it when status="ok" OR a
' "version" key is present. NEVER compare a possibly-numeric field with "" - read
' status (a string, safe to compare) and only DoesExist("version"). Guards invalid.
' @param json Object - the parsed /health body (may be invalid)
' @return Boolean - true when the body looks like a healthy Phlix host
function HealthOk(json as Object) as Boolean
    if json = invalid then return false
    if type(json) <> "roAssociativeArray" then return false

    if json.DoesExist("status") and json.status <> invalid then
        s = json.status
        if (type(s) = "String" or type(s) = "roString") and s = "ok" then return true
    end if

    if json.DoesExist("version") then return true

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

' R5: Lazy image loader — defers HDPosterUrl assignment until item is near visible area
' Usage: Call SetLazyPosterUrl(contentNode, item, "poster_url") after creating each content item
' This stores the URL in a _lazyPosterUrl field instead of setting HDPosterUrl directly
sub SetLazyPosterUrl(contentNode as Object, item as Object, urlField as String)
    ' Store the URL for later instead of loading immediately
    if item.DoesExist(urlField) and item.lookup(urlField) <> invalid and item.lookup(urlField) <> "" then
        contentNode._lazyPosterUrl = item.lookup(urlField)
    else
        contentNode._lazyPosterUrl = "pkg:/images/placeholder.png"
    end if
    ' Don't set HDPosterUrl yet — wait until item is actually visible
end sub

' R5: Activate lazy image — call when item comes into visible range
' Call SetLazyPosterUrl first, then call this to actually load the image
sub ActivateLazyPosterUrl(contentNode as Object)
    if contentNode <> invalid and type(contentNode) = "roSGNode" then
        if contentNode.doesExist("_lazyPosterUrl") then
            url = contentNode.lookup("_lazyPosterUrl")
            if url <> invalid and url <> "" then
                contentNode.HDPosterUrl = url
            end if
        end if
    end if
end sub

' R5: Clear lazy image — call when item goes out of visible range to free memory
sub ClearLazyPosterUrl(contentNode as Object)
    if contentNode <> invalid and type(contentNode) = "roSGNode" then
        contentNode.HDPosterUrl = ""
    end if
end sub

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

' Convert a byte (0-255) to a 2-character uppercase hex string.
' Used by UrlEncode for percent-encoding.
' @param n Integer - byte value (0-255)
' @return String - 2-character hex string (e.g., "20" for space)
function ByteToHex(n as Integer) as String
    hexDigits = "0123456789ABCDEF"
    hi = (n \ 16) mod 16
    lo = n mod 16
    return hexDigits.Mid(hi, 1) + hexDigits.Mid(lo, 1)
end function

' URL-encode a string (percent-encode according to RFC 3986).
' roUrlTransfer.Escape() does not exist in the Roku SDK (verified against ROKU_SDK_12+).
' RFC 3986 unreserved characters: A-Z a-z 0-9 - . _ ~
' Everything else gets percent-encoded. % is encoded first to prevent double-encoding.
' Non-ASCII characters are encoded as UTF-8 bytes, then each byte is percent-encoded.
' Lives in Utilities so any component that includes Utilities + ApiClient can resolve it.
' @param str String - the raw value
' @return String - the encoded value
function UrlEncode(str as String) as String
    result = ""
    if str = invalid then return result

    for i = 1 to Len(str)
        c = Mid(str, i, 1)
        code = Asc(c)

        ' RFC 3986 unreserved characters pass through unchanged:
        ' A-Z (65-90), a-z (97-122), 0-9 (48-57), - (45), . (46), _ (95), ~ (126)
        if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code = 45 or code = 46 or code = 95 or code = 126 then
            result = result + c
        else
            ' Encode % first to prevent double-encoding of other percent-encoded values
            if code = 37 then
                ' Percent sign - encode first
                result = result + "%25"
            else if code >= 128 then
                ' Non-ASCII: encode as UTF-8 bytes, then percent-encode each byte
                ' Characters 128-2047 need 2 UTF-8 bytes
                ' Characters 2048-65535 need 3 UTF-8 bytes
                ' Characters 65536+ need 4 UTF-8 bytes
                if code < 2048 then
                    ' 2-byte UTF-8: 110xxxxx 10xxxxxx
                    b1 = 192 + (code \ 64)
                    b2 = 128 + (code mod 64)
                    result = result + "%" + ByteToHex(b1) + "%" + ByteToHex(b2)
                else if code < 65536 then
                    ' 3-byte UTF-8: 1110xxxx 10xxxxxx 10xxxxxx
                    b1 = 224 + (code \ 4096)
                    b2 = 128 + ((code \ 64) mod 64)
                    b3 = 128 + (code mod 64)
                    result = result + "%" + ByteToHex(b1) + "%" + ByteToHex(b2) + "%" + ByteToHex(b3)
                else
                    ' 4-byte UTF-8: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
                    b1 = 240 + (code \ 262144)
                    b2 = 128 + ((code \ 4096) mod 64)
                    b3 = 128 + ((code \ 64) mod 64)
                    b4 = 128 + (code mod 64)
                    result = result + "%" + ByteToHex(b1) + "%" + ByteToHex(b2) + "%" + ByteToHex(b3) + "%" + ByteToHex(b4)
                end if
            else
                ' All other characters (including space, &, =, ?, /, :, #, [, ], etc.)
                result = result + "%" + ByteToHex(code)
            end if
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

' Show a SceneGraph Dialog node attached to the given scene.
' Supports two shapes:
'   - Info dialog: one button ("OK") — just dismisses.
'   - Retry dialog: two buttons ("Retry", "Cancel") — callback is called with
'     button index (0 = Retry, 1 = Cancel) so the caller can retry the failed op.
' @param scene Object - the scene to attach the dialog to (m.top of the scene)
' @param title String - dialog title
' @param message String - dialog message
' @param buttons Object - optional array of button labels (default ["OK"])
' @param callback Function - optional(buttonIndex as Integer) callback for retry dialogs
sub ShowErrorDialog(scene as Object, title as String, message as String, buttons = ["OK"] as Object, callback = invalid as Function)
    if scene = invalid then return
    if buttons = invalid or (type(buttons) = "roArray" and buttons.Count() = 0) then buttons = ["OK"]

    ' Track the currently-focused node so we can restore it when the dialog closes.
    ' R3.1: Without this, focus is lost on dismiss → remote becomes unresponsive.
    previousFocus = invalid
    for each child in scene.GetChildren(-1, 0)
        if child.IsInFocusChain() then
            previousFocus = child
            exit for
        end if
    end for

    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = title
    dialog.message = message
    dialog.buttons = buttons

    ' Store callback on the dialog node so observers can invoke it.
    if callback <> invalid then
        dialog.observeField("buttonSelected", "OnDialogButtonSelected")
        dialog.callback = callback
    end if

    ' R3.1: Store previous focus on the dialog for restoration on dismiss.
    dialog.previousFocus = previousFocus

    dialog.observeField("wasClosed", "OnDialogClosed")
    scene.dialog = dialog
end sub

' Observer handler for dialog buttonSelected — fires when user presses a button.
' Invokes the stored callback with the button index, then closes and restores focus.
sub OnDialogButtonSelected(event as Object)
    dialog = event.GetNode()
    index = event.GetData()
    if dialog.callback <> invalid then
        dialog.callback(index)
    end if
    dialog.Close = true
    ' R3.1: Restore focus to the previously-focused node if it's not already focused.
    if dialog.previousFocus <> invalid and not dialog.previousFocus.IsInFocusChain() then
        dialog.previousFocus.SetFocus(true)
    end if
end sub

' Observer handler for dialog wasClosed — fires when user dismisses via Back.
' Closes the dialog (if not already closing) and restores focus to the previous node.
sub OnDialogClosed(event as Object)
    dialog = event.GetNode()
    ' wasClosed fires after any button press too; guard to avoid double-close.
    if dialog.Close <> true then
        dialog.Close = true
    end if
    ' R3.1: Restore focus to the previously-focused node if it's not already focused.
    if dialog.previousFocus <> invalid and not dialog.previousFocus.IsInFocusChain() then
        dialog.previousFocus.SetFocus(true)
    end if
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
    if items = invalid then return []

    ' Build a sort-key array: { sortKey: number, item: assocarray }
    ' Key = season*100000 + episode so season takes precedence.
    decorated = []
    for each item in items
        s = SortKeyValue(item, "season_number")
        e = SortKeyValue(item, "episode_number")
        decorated.Push({ sortKey: s * 100000 + e, item: item })
    end for

    ' ArraySort is O(n log n) merge sort; sort by sortKey ascending.
    decorated.SortBy("sortKey", "asc", false)

    ' Extract the sorted items back out.
    result = []
    for each d in decorated
        result.Push(d.item)
    end for
    return result
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

' Flatten a RAW collection-item row (from GET /collections/{id}) into the shape
' the grid + type-routing consume: {id,name,type,poster_url,overview,year}.
' Collection items are NOT MediaItemShaper-shaped: id/name/type are top-level but
' poster_url/overview/year live under metadata.* (mirrors NormalizeAlbumTrack /
' ContinuePosterUrl). metadata MAY arrive as a non-assoc string, so only read its
' keys when it is an roAssociativeArray. `type` stays top-level so series ->
' SeriesScene / season -> SeasonScene routing still works. Reads top-level first
' then metadata fallback (defensive; raw rows have these only under metadata).
' `year` is kept as-is (Integer or invalid). Guards invalid.
' @param raw Object - a raw collection-item row (may be invalid)
' @return Object - the normalized item (sentinel with empty strings when invalid)
function NormalizeCollectionItem(raw as Object) as Object
    item = { id: "", name: "", type: "", poster_url: "", overview: "", year: invalid }
    if raw = invalid then return item

    meta = invalid
    if raw.DoesExist("metadata") and raw.metadata <> invalid then
        if type(raw.metadata) = "roAssociativeArray" then meta = raw.metadata
    end if

    if raw.DoesExist("id") and raw.id <> invalid then item.id = raw.id
    if raw.DoesExist("name") and raw.name <> invalid then item.name = raw.name
    if raw.DoesExist("type") and raw.type <> invalid then item.type = raw.type

    ' poster_url: top-level (defensive) then metadata.
    if raw.DoesExist("poster_url") and raw.poster_url <> invalid and raw.poster_url <> "" then
        item.poster_url = raw.poster_url
    else if meta <> invalid and meta.DoesExist("poster_url") and meta.poster_url <> invalid and meta.poster_url <> "" then
        item.poster_url = meta.poster_url
    end if

    ' overview: top-level then metadata.
    if raw.DoesExist("overview") and raw.overview <> invalid then
        item.overview = raw.overview
    else if meta <> invalid and meta.DoesExist("overview") and meta.overview <> invalid then
        item.overview = meta.overview
    end if

    ' year: top-level then metadata (kept as-is; may be Integer or invalid).
    if raw.DoesExist("year") and raw.year <> invalid then
        item.year = raw.year
    else if meta <> invalid and meta.DoesExist("year") and meta.year <> invalid then
        item.year = meta.year
    end if

    return item
end function

' Non-mutating insertion sort of a (normalized) track array by disc_number then
' track_number. Invalid/missing numbers sort LAST (sentinel 999999) so unnumbered
' tracks sink to the end. Mirrors SortByEpisodeOrder. Returns a NEW array; the
' input is not modified. Guards non-array input -> [].
' @param tracks Object - array of normalized track assocarrays (may be invalid)
' @return Object - a new sorted array (empty array when input is invalid)
function SortByTrackOrder(tracks as Object) as Object
    if tracks = invalid then return []

    ' Build a sort-key array: { sortKey: number, track: assocarray }
    ' Key = disc*100000 + track so disc takes precedence.
    ' SortKeyValue returns 999999 for invalid/missing, which sorts last.
    decorated = []
    for each track in tracks
        d = SortKeyValue(track, "disc_number")
        t = SortKeyValue(track, "track_number")
        if d = 0 then d = 999999
        if t = 0 then t = 999999
        decorated.Push({ sortKey: d * 100000 + t, track: track })
    end for

    ' ArraySort is O(n log n) merge sort; sort by sortKey ascending.
    decorated.SortBy("sortKey", "asc", false)

    ' Extract the sorted tracks back out.
    result = []
    for each d in decorated
        result.Push(d.track)
    end for
    return result
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
    if album = invalid then return Translate("utilities_photo_album_undated")

    date = ""
    if album.DoesExist("date") and album.date <> invalid then date = album.date

    if date = "" or date = "Unknown" then return Translate("utilities_photo_album_undated")

    return date
end function

' Build a multi-line EXIF summary (Chr(10)-joined) from whichever metadata fields
' are present, skipping absent fields so there are no empty/"invalid" lines.
' Lines (each emitted ONLY when its source is present):
'   Camera     = camera_make + " " + camera_model (emit if either present)
'   Lens       = lens
'   Settings   = aperture, shutter_speed, focal_length, "ISO "+iso joined by "  •  "
'   Dimensions = width + " × " + height (only when BOTH are valid Ints > 0)
'   Date       = date_taken_formatted (fallback date_taken_year)
'   GPS        = gps_display (already "lat, lng" formatted)
' metadata MAY arrive as a non-assoc, so only read keys when it is an
' roAssociativeArray (mirrors NormalizeAlbumTrack / ContinuePosterUrl). Pure; NO
' node access. Returns "" when exif is invalid/non-assoc/empty (caller shows a
' "No photo info" placeholder).
' @param exif Object - a photo metadata assocarray (may be invalid)
' @return String - the multi-line summary (empty string when nothing present)
function FormatExifSummary(exif as Object) as String
    if exif = invalid then return ""
    if type(exif) <> "roAssociativeArray" then return ""

    lines = []

    ' Camera: camera_make + camera_model (emit if either present).
    make = ""
    if exif.DoesExist("camera_make") and exif.camera_make <> invalid and exif.camera_make <> "" then
        make = exif.camera_make
    end if
    model = ""
    if exif.DoesExist("camera_model") and exif.camera_model <> invalid and exif.camera_model <> "" then
        model = exif.camera_model
    end if
    if make <> "" or model <> "" then
        camera = make
        if make <> "" and model <> "" then
            camera = make + " " + model
        else if model <> "" then
            camera = model
        end if
        lines.Push(camera)
    end if

    ' Lens.
    if exif.DoesExist("lens") and exif.lens <> invalid and exif.lens <> "" then
        lines.Push(exif.lens)
    end if

    ' Settings: aperture • shutter_speed • focal_length • "ISO "+iso.
    settings = []
    if exif.DoesExist("aperture") and exif.aperture <> invalid and exif.aperture <> "" then
        settings.Push(exif.aperture)
    end if
    if exif.DoesExist("shutter_speed") and exif.shutter_speed <> invalid and exif.shutter_speed <> "" then
        settings.Push(exif.shutter_speed)
    end if
    if exif.DoesExist("focal_length") and exif.focal_length <> invalid and exif.focal_length <> "" then
        settings.Push(exif.focal_length)
    end if
    if exif.DoesExist("iso") and exif.iso <> invalid then
        isoVal = Int(exif.iso)
        if isoVal > 0 then settings.Push(Translate("utilities_iso_prefix") + str(isoVal).trim())
    end if
    if settings.Count() > 0 then
        lines.Push(JoinStrings(settings, "  •  "))
    end if

    ' Dimensions: width × height (emit only when BOTH are valid Ints > 0).
    if exif.DoesExist("width") and exif.width <> invalid and exif.DoesExist("height") and exif.height <> invalid then
        w = Int(exif.width)
        h = Int(exif.height)
        if w > 0 and h > 0 then
            lines.Push(str(w).trim() + " × " + str(h).trim())
        end if
    end if

    ' Date: date_taken_formatted -> date_taken_year. The year may arrive as a
    ' String ("YYYY") or an Integer, so branch on type — comparing an Integer
    ' with "" raises a runtime type-mismatch (would crash the viewer render).
    if exif.DoesExist("date_taken_formatted") and exif.date_taken_formatted <> invalid and exif.date_taken_formatted <> "" then
        lines.Push(exif.date_taken_formatted)
    else if exif.DoesExist("date_taken_year") and exif.date_taken_year <> invalid then
        yearValue = exif.date_taken_year
        if type(yearValue) = "String" or type(yearValue) = "roString" then
            if yearValue <> "" then lines.Push(yearValue)
        else
            yearInt = Int(yearValue)
            if yearInt > 0 then lines.Push(str(yearInt).trim())
        end if
    end if

    ' GPS: gps_display (already "lat, lng" formatted).
    if exif.DoesExist("gps_display") and exif.gps_display <> invalid and exif.gps_display <> "" then
        lines.Push(exif.gps_display)
    end if

    if lines.Count() = 0 then return ""

    return JoinStrings(lines, Chr(10))
end function

' R3.2: Get user-friendly error message, falling back to generic message for HTTP codes
function GetErrorMessage(apiError as String) as String
    if apiError = "" or apiError = invalid then return "An error occurred. Please try again."
    if left(apiError, 5) = "http_" then
        ' Generic HTTP error codes - use friendly messages
        code = right(apiError, len(apiError) - 5)
        if code = "401" then return "You are not logged in. Please sign in again."
        if code = "403" then return "You don't have permission to do that."
        if code = "404" then return "The requested item was not found."
        if code = "500" then return "Server error. Please try again later."
        if code = "502" or code = "503" then return "Server is temporarily unavailable."
        return "An error occurred. Please try again."
    end if
    ' Specific server error message - use it
    if len(apiError) > 0 then return apiError
    return "An error occurred. Please try again."
end function

' True when the user assocarray is flagged admin. is_admin arrives from JSON as a
' TINYINT Integer (1/0) but may be a Boolean; both coerce via Int() (Int(true)=1,
' Int(false)=0). Only Int()-coerce numeric/boolean types — Int() on a String can
' raise, so guard the type first. Guards invalid/missing -> false.
' @param user Object - a user assocarray (may be invalid)
' @return Boolean - true only when is_admin is truthy (1 / true)
function IsAdminUser(user as Object) as Boolean
    if user = invalid then return false
    if not user.DoesExist("is_admin") then return false
    v = user.is_admin
    if v = invalid then return false

    t = type(v)
    if t = "Boolean" or t = "roBoolean" then
        return v
    else if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
        return (Int(v) = 1)
    end if

    return false
end function

' Truthy test for a bool-or-numeric (TINYINT) flag under container[key]. Mirrors
' IsAdminUser's type-guard (a numeric <> "" compare CRASHES). Returns false when
' missing/invalid/non-bool-non-numeric.
' @param container Object - assocarray that may hold the flag (may be invalid)
' @param key String - the flag key
' @return Boolean - true only when container[key] is truthy (1 / true)
function IsTruthyFlag(container as Object, key as String) as Boolean
    if container = invalid then return false
    if type(container) <> "roAssociativeArray" then return false
    if not container.DoesExist(key) then return false
    v = container[key]
    if v = invalid then return false
    t = type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return (Int(v) = 1)
    return false
end function

' The playable leaf members of the server's `media_items.type` ENUM - the types
' that actually resolve to a video/audio stream, so the only ones worth offering
' a Play button for.
'
' The full ENUM is:
'   movie, series, season, episode, track, music, album, artist, video, audio,
    '   book, photo
'
' Excluded on purpose: series/season/album/artist/music are CONTAINERS (they
' drill down to children, they have no stream of their own), and book/photo
' carry no video or audio track at all.
'
' Keep this in sync with the server-side allowlist if the ENUM ever grows - an
' unknown type is treated as NOT playable, so a new type silently loses its Play
' button until it is added here (safe default: no dead button).
' @return Object - roArray of canonical lowercase type strings
function PlayableTypes() as Object
    return ["movie", "episode", "video", "audio", "track", "audiobook"]
end function

' Is this a playable leaf type? Comparison is case-insensitive on a defensive
' copy - a non-string `itemType` would CRASH a bare `=` compare against a string
' (same type-guard rationale as IsTruthyFlag).
' @param itemType Dynamic - the raw item type (may be invalid / non-string)
' @return Boolean - true only for a member of PlayableTypes()
function IsPlayableType(itemType as Dynamic) as Boolean
    if itemType = invalid then return false
    t = type(itemType)
    if t <> "String" and t <> "roString" then return false

    needle = itemType.Trim().Lower()
    if needle = "" then return false

    for each candidate in PlayableTypes()
        if candidate = needle then return true
    end for
    return false
end function

' Convenience wrapper: is THIS item playable? Guards the container and the
' missing/invalid `type` key so callers stay one-liners.
' @param item Object - a media item assocarray (may be invalid)
' @return Boolean - true only when item.type is a playable leaf type
function IsPlayableItem(item as Object) as Boolean
    if item = invalid then return false
    if type(item) <> "roAssociativeArray" then return false
    if not item.DoesExist("type") then return false
    return IsPlayableType(item.type)
end function

' Map a content-rating int (0-6) to its label. Out-of-range -> "UNRATED".
' (0=G,1=PG,2=PG-13,3=R,4=NC-17,5=X,6=UNRATED.)
' @param n Integer - the rating int
' @return String - the label
function RatingLabel(n as Integer) as String
    if n < 0 or n > 6 then return Translate("utilities_rating_unrated")
    labels = ["utilities_rating_g", "utilities_rating_pg", "utilities_rating_pg13", "utilities_rating_r", "utilities_rating_nc17", "utilities_rating_x", "utilities_rating_unrated"]
    return Translate(labels[n])
end function

' ===========================================
' R7.12: i18n support
' Uses function-property pattern (like DeviceInfoData) to cache locale strings.
' ===========================================

' Load locale strings from JSON file (called at app startup via AppContext.InitLocale)
sub LoadLocaleStrings()
    ' Cached on the function object itself
    if LoadLocaleStrings._loaded = true then return
    path = "locale://locale/en_US/strings.json"
    f = CreateObject("roFileSystem")
    if not f.Exists(path) then return
    data = ReadAsciiFile(path)
    if data = "" or data = invalid then return
    LoadLocaleStrings._cache = ParseJson(data)
    LoadLocaleStrings._loaded = true
end sub

' Translate a string key using loaded locale
' @param key String - the translation key
' @return String - the translated string, or the key if not found
function Translate(key as String) as String
    if LoadLocaleStrings._loaded <> true then LoadLocaleStrings()
    if LoadLocaleStrings._loaded <> true then return key

    cache = LoadLocaleStrings._cache
    sections = ["common", "utilities", "settings", "detail"]
    for each section in sections
        if cache.doesExist(section) then
            sectionData = cache.lookup(section)
            if type(sectionData) = "roAssociativeArray" and sectionData.doesExist(key) then
                result = sectionData.lookup(key)
                if result <> invalid then return result
            end if
        end if
    end for
    return key
end function