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
'   book, photo, audiobook
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
' R7.12: i18n support (wiring completed in the key-resolution fix)
' Uses function-property pattern (like DeviceInfoData) to cache locale strings.
'
' KEY CONVENTION: the catalog nests BARE keys under sections
' ("settings": {"button_cancel": "Cancel"}), while every call site passes the
' FLATTENED, section-prefixed form ("settings_button_cancel"). The loader
' flattens "<section>_<bareKey>" -> value once at parse time so the dominant
' call-site style resolves with zero call-site churn. To add a string: nest the
' bare key under its section in locale/<tag>/strings.json and call
' Translate("<section>_<bareKey>").
' ===========================================

' Flatten a parsed catalog into a single-level "<section>_<bareKey>" lookup
' table. "_metadata" is skipped. String leaves only: a non-string value
' (array/object under a section) is SKIPPED, because Translate() returns
' `as String` and receiving a non-string would type-crash on device — the
' skip lets the documented raw-key fallback happen instead. Check 20 rejects
' such leaves in CI, so this guard is defense-in-depth, not an invitation.
' Pure: returns a new assocarray; raw is never mutated.
' @param raw Object|invalid - parsed catalog (sections of bare-key assocarrays)
' @return Object - roAssociativeArray of flattened keys to string values
function FlattenLocaleCatalog(raw as Object) as Object
    flat = CreateObject("roAssociativeArray")
    if raw = invalid then return flat
    for each section in raw.getKeysAsArray()
        if section <> "_metadata"
            sectionData = raw[section]
            if type(sectionData) = "roAssociativeArray"
                for each bareKey in sectionData.getKeysAsArray()
                    leaf = sectionData[bareKey]
                    if type(leaf) = "String" or type(leaf) = "roString"
                        flat[section + "_" + bareKey] = leaf
                    end if
                end for
            end if
        end if
    end for
    return flat
end function

' Load locale strings from the bundled JSON catalog (called at app startup via
' AppContext.InitLocale; Translate retries lazily until it succeeds).
'
' MOUNT: direct pkg:/ read. The former "locale://..." URL requires the
' locale=/country_code= manifest keys that mount that protocol; this channel's
' manifest never declared them, so roFileSystem.Exists() was always false and
' the catalog silently never loaded. pkg:/ needs no manifest wiring. NOTE: the
' locale/ tree must stay in the package zip (see Makefile `package` target and
' bsconfig.json "files") or these paths do not exist on device.
'
' SELECTION: roAppInfo.GetCurrentLocale() picks locale/<tag>/strings.json when
' it exists and has content. Firmware varies between "en-US" and "en_US", so
' the tag is normalized to underscores before folder resolution. ReadAsciiFile
' returns "" for BOTH missing and empty files, so an empty/whitespace-only
' device catalog counts as missing. Fallback: the base locale en_US.
sub LoadLocaleStrings()
    ' Cached on the function object itself
    if LoadLocaleStrings._loaded = true then return

    base = "pkg:/locale/en_US/strings.json"
    data = invalid

    appInfo = CreateObject("roAppInfo")
    if appInfo <> invalid
        tag = appInfo.GetCurrentLocale()
        if tag <> invalid and tag.Trim() <> ""
            candidate = "pkg:/locale/" + tag.Trim().Replace("-", "_") + "/strings.json"
            if candidate <> base
                deviceData = ReadAsciiFile(candidate)
                if deviceData <> invalid and deviceData.Trim() <> "" then data = deviceData
            end if
        end if
    end if

    if data = invalid then data = ReadAsciiFile(base)
    if data = invalid or data.Trim() = "" then return
    raw = ParseJson(data)
    if raw = invalid then return

    LoadLocaleStrings._raw = raw
    LoadLocaleStrings._cache = FlattenLocaleCatalog(raw)
    LoadLocaleStrings._loaded = true
end sub

' Translate a string key using the loaded locale.
' Resolution order (first hit wins):
'   1. exact match in the flattened "<section>_<bareKey>" table — the call-site
'      convention every scene uses ("settings_button_cancel")
'   2. nested probe raw[section][key] — legacy support for bare-key callers
'   3. return the key unchanged — graceful fallback that renders visibly
'      broken instead of silently wrong, and keeps Translate total.
' Only string-typed catalog values are returned; a non-string leaf (a shape
' Check 20 rejects in CI) falls through steps 1-2 to the raw-key return.
' @param key String - the translation key
' @return String - the translated string, or the key if not found
function Translate(key as String) as String
    if LoadLocaleStrings._loaded <> true then LoadLocaleStrings()
    if LoadLocaleStrings._loaded <> true then return key

    cache = LoadLocaleStrings._cache
    if cache <> invalid and cache.doesExist(key) then
        flatResult = cache.lookup(key)
        if flatResult <> invalid then return flatResult
    end if

    raw = LoadLocaleStrings._raw
    sections = ["common", "utilities", "settings", "detail", "syncplay", "errors"]
    for each section in sections
        if raw <> invalid and raw.doesExist(section) then
            sectionData = raw.lookup(section)
            if type(sectionData) = "roAssociativeArray" and sectionData.doesExist(key) then
                result = sectionData.lookup(key)
                ' String-typed values only — same guard as the flat table, so a
                ' CI-rejected non-string leaf falls through to the raw key instead
                ' of crashing this function's `as String` return.
                if result <> invalid and (type(result) = "String" or type(result) = "roString") then return result
            end if
        end if
    end for
    return key
end function

' ===========================================
' TOKEN SUBSTITUTION (i18n {placeholder} family)
'
' Some catalog values carry {name} placeholders ("Logged in as: {email}").
' Concatenating the value at the call site renders the literal braces on the
' TV and hard-codes the token's POSITION in the English sentence - a locale
' that moves the value inside the phrase cannot express it. The law: every
' token-bearing catalog value is consumed through TranslateWithParams, which
' substitutes each placeholder BY NAME (position-free), generalizing the
' MembersCountText {count} Replace exemplar from PR #86/#87. Check 24 in
' scripts/verify-runtime.sh enforces the law (raw-Translate rejection, dead-
' copy detection, param-completeness against the catalog token set).
' ===========================================

' Pure token-substitution core: replace every "{name}" in TEXT with the
' rendered value of PARAMS[name]. Total by construction:
'   - unknown tokens (name not in TEXT) are simply no-ops
'   - tokens whose value has no display form (invalid, arrays, objects) stay
'     visible in the output - the same fail-loud brace rendering as a missing
'     key, never a silently erased slot
'   - invalid/non-associative-array params return TEXT unchanged
' No catalog, no globals, no mutation: same inputs, same output.
' @param text String - the (already localized) line carrying {name} tokens
' @param params Object - roAssociativeArray of token name -> value
' @return String - TEXT with every renderable named token substituted
function ApplyNamedTokens(text as String, params as Object) as String
    if params = invalid then return text
    if type(params) <> "roAssociativeArray" then return text
    result = text
    for each token in params
        rendered = TokenValueText(params[token])
        if rendered <> invalid then
            result = result.Replace("{" + token + "}", rendered)
        end if
    end for
    return result
end function

' Render one placeholder value to display text, or return invalid when the
' value has no sane text form (caller then leaves the token visible).
' Strings pass through; booleans render "true"/"false"; integers and floats
' render sign-free via the repo's str().trim() idiom; anything else is
' rejected as invalid.
' @param value Object - the raw parameter value
' @return Object - String when renderable, invalid otherwise
function TokenValueText(value as Object) as Object
    t = type(value)
    if t = "String" or t = "roString" then return value
    if t = "Boolean" then
        if value = true then return "true"
        return "false"
    end if
    if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInt" then return str(value).trim()
    if t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then return str(value).trim()
    return invalid
end function

' Translate KEY, then substitute its {name} tokens position-free from PARAMS.
' The single consumption path for every token-bearing catalog value (law above
' and Check 24). Degradation is total: invalid params behave like plain
' Translate(key), so no call site can crash on a missing dictionary.
' @param key String - the translation key
' @param params Object - roAssociativeArray of token name -> value
' @return String - the localized line with every renderable token substituted
function TranslateWithParams(key as String, params as Object) as String
    return ApplyNamedTokens(Translate(key), params)
end function
' ===========================================
' CAPTIONS MODE VOCABULARY (R6.5 / settings dialog)
'
' Doctrine: localized text is NOT the wire value. roDeviceInfo.SetCaptionsMode()
' and Video.globalCaptionMode accept only the platform's fixed WIRE strings;
' feeding them translated button labels silently mis-sets captions on every
' non-English locale (the defect this family closes). WIRE values go to the OS,
' DISPLAY labels go to the eye - bound by index, never by string equality.
' PlayerScene renders its caption list FROM this function (review #91 retired
' its local copies of the array), so the wire bytes have exactly one source.
' ===========================================

' The four platform captions modes per
' https://developer.roku.com/dev/docs/video (globalCaptionMode field):
'   "On"            captions always on
'   "Off"           captions always off
'   "Instant replay" on only during instant replay
'   "When mute"     on only when volume is muted (Roku TVs only)
' These bytes go to the OS, never to the eye: DO NOT translate them.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of 4 wire strings, index-parallel with CaptionsModeLabels()
function GetCaptionsModeWireValues() as Object
    return ["On", "Off", "Instant replay", "When mute"]
end function

' Localized display labels for the same four modes, in the exact order of
' GetCaptionsModeWireValues(). Literal Translate() calls keep Check 20's
' catalog-resolution coverage on these keys.
' @return Object - roArray of 4 localized label strings
function CaptionsModeLabels() as Object
    return [Translate("settings_button_caption_on"), Translate("settings_button_caption_off"), Translate("settings_button_caption_instant_replay"), Translate("settings_button_caption_when_mute")]
end function

' Map a captions WIRE value to its localized display label. "" is the
' documented system-level-off reading of roDeviceInfo.GetCaptionsMode()
' (mirrors PlayerScene R6.5 start-up normalisation) and renders as the
' "Off" label; any unrecognized value passes through unchanged so it stays
' visible for debugging instead of silently lying.
' @param wireMode String - value from roDeviceInfo.GetCaptionsMode()
' @return String - localized label, or the input itself when unknown
function CaptionsModeLabel(wireMode as String) as String
    wire = GetCaptionsModeWireValues()
    labels = CaptionsModeLabels()
    mode = wireMode
    if mode = "" then mode = "Off"
    for i = 0 to wire.count() - 1
        if wire[i] = mode then return labels[i]
    end for
    return mode
end function
' ===========================================
' W5 THIN-CLIENT ERROR LOCALISATION (syncplay_error frames)
'
' Doctrine: error-code-first. The stable error_code on a server frame selects
' the catalog string; the server's English message is only a debug fallback for
' codes this build does not recognize. Server text NEVER overrides a resolved
' code.
'
' MAPPING LAW (single source of truth, mirrored by Check 22 in
' scripts/verify-runtime.sh):
'   wire     = msg.error_code, else msg.code, else ""   (read in SyncPlayTask)
'   key      = "errors_" + LCase(wire) with "." and "-" replaced by "_"
'   invalid/non-string/empty wire -> "errors_fallback"
' Deterministic for both code families the server emits:
'   legacy SCREAMING: NOT_IN_GROUP            -> errors_not_in_group
'   dotted registry:  syncplay.group_full     -> errors_syncplay_group_full
' Unknown future codes miss the catalog, Translate echoes the key, and the
' resolver falls through to the server message - forward compatible by design.
'
' CENSUS SPLIT (wire-honesty redesign, 2026-09-25):
' The wire census SyncPlayKnownErrorCodes() is a SUPERSET of what the server
' emits today: census ⊇ emitted, and every census member that is NOT (yet)
' emitted must be DECLARED in SyncPlayReservedErrorCodes(). Check 22 pins the
' census by content equality against {emitted-verified ∪ declared-reserved},
' so an undeclared future code cannot ride in on a count bump.
'   emitted-verified: 12 legacy SCREAMING + 4 dotted registry codes, read off
'     phlix-server origin/master e0e010b07c7f4cc21baf10d9a945bac24edab45c
'     (src/Session/SyncPlay/SyncPlayManager.php + src/Server/WebSocket/
'     MessageHandler.php sendError literals).
'   declared-reserved: 3 dotted twins syncplay.create_failed / join_failed /
'     leave_failed - registered in the phlix-contracts error registry
'     (dist/error-codes.json) but NOT yet emitted by any server build.
' TWIN-FLIP TIMELINE: the server will switch its group create/join/leave
' failure wraps from SCREAMING (SyncPlayManager.php:1586/1623/1652
' 'CREATE_FAILED'/'JOIN_FAILED'/'LEAVE_FAILED') to the dotted registry forms.
' This client is already prepared: both shapes normalize (law) onto distinct,
' fully-populated catalog keys, so no client change is needed at flip time.
' After the flip, the 3 members are PROMOTED (reserved -> emitted-verified in
' Check 22 + this docblock); the SCREAMING trio stays in the census to keep
' old servers resolving - a family retires only when its servers do.
' ===========================================

' Canonical client-reachable syncplay wire codes: the 16 emitted-verified
' codes (12 legacy SCREAMING + 4 dotted registry twins, read off phlix-server
' origin/master e0e010b0 sendError literals) UNION the 3 codes declared in
' SyncPlayReservedErrorCodes() (contracts-registered, flip-pending) = 19.
' Every element MUST have a matching errors_<law(key)> entry in ALL seven
' locale catalogs - Check 22 enforces the en_US side by CONTENT equality
' against that split (the guard law: silent fallback must not hide a missing
' translation, and an undeclared future code must not ride in on a count
' bump) and Check 21 pins cross-locale key parity from the catalogs themselves.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of 19 code strings as they appear (or will appear)
'         on the wire
function SyncPlayKnownErrorCodes() as Object
    codes = []
    codes.push("NOT_AUTHENTICATED")
    codes.push("NOT_IN_GROUP")
    codes.push("NOT_HOST")
    codes.push("UNKNOWN_MESSAGE")
    codes.push("HANDLER_ERROR")
    codes.push("PROTOCOL_VERSION_MISMATCH")
    codes.push("INVALID_NEW_HOST")
    codes.push("MEMBER_NOT_FOUND")
    codes.push("SAME_HOST")
    codes.push("CREATE_FAILED")
    codes.push("JOIN_FAILED")
    codes.push("LEAVE_FAILED")
    codes.push("syncplay.group_limit_reached")
    codes.push("syncplay.group_not_found")
    codes.push("syncplay.invalid_password")
    codes.push("syncplay.group_full")
    ' Declared-reserved dotted twins (SyncPlayReservedErrorCodes) - the
    ' server's create/join/leave flip target; resolvable BEFORE the flip so
    ' localized rendering covers both shapes the day the wire changes.
    codes.push("syncplay.create_failed")
    codes.push("syncplay.join_failed")
    codes.push("syncplay.leave_failed")
    return codes
end function

' The census members the CURRENT server build does not emit: the 3 dotted
' twins registered in the phlix-contracts error registry (v0.5.1,
' dist/error-codes.json) awaiting the server-side twin flip. Declaration,
' not discovery - Check 22 pins this set to exactly these 3 names, requires
' each to live in the wire census, and forbids the two sets from drifting:
' census == emitted-verified ∪ reserved. When the flip lands, a member is
' promoted (removed here, recorded as emitted in Check 22's evidence set and
' the docblock above); the census and catalogs stay byte-stable.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of 3 dotted registry codes (never SCREAMING,
'         never "local.")
function SyncPlayReservedErrorCodes() as Object
    codes = []
    codes.push("syncplay.create_failed")
    codes.push("syncplay.join_failed")
    codes.push("syncplay.leave_failed")
    return codes
end function

' Apply the MAPPING LAW above: wire error_code -> flat "errors_*" catalog key.
' Total function: any input shape (invalid, number, empty, padded) parses into
' exactly one of {errors_<normalized>, errors_fallback}.
' @param code Object - raw error_code/code value from the frame
' @return String - flat Translate() key
function SyncPlayErrorCodeToKey(code as Object) as String
    if code = invalid then return "errors_fallback"
    tp = type(code)
    if tp <> "String" and tp <> "roString" then return "errors_fallback"
    raw = code.Trim()
    if raw = "" then return "errors_fallback"
    normalized = LCase(raw).Replace(".", "_").Replace("-", "_")
    return "errors_" + normalized
end function

' Resolve the user-facing text for one syncplay_error frame.
' Priority (first hit wins):
'   1. recognized code -> its catalog entry in the active locale
'   2. unrecognized/absent code + non-empty server message -> that message
'   3. errors_fallback catalog entry (generic localized line)
'   4. "" - catalog entirely unavailable; the caller supplies its own
'      last-resort literal so this function never renders a raw key.
' Pure apart from Translate()'s cached catalog load; no global mutation.
' @param code Object - wire error_code (or legacy code) value
' @param serverMessage String - frame "message" text, may be ""
' @return String - localized (or debug-fallback) user-facing text
function LocalizeSyncPlayError(code as Object, serverMessage as String) as String
    key = SyncPlayErrorCodeToKey(code)
    if key <> "errors_fallback"
        text = Translate(key)
        if text <> key then return text
    end if
    if serverMessage <> "" then return serverMessage
    fallback = Translate("errors_fallback")
    if fallback <> "errors_fallback" then return fallback
    return ""
end function

' ===========================================
' CLIENT-GENERATED ERROR FAMILY (local.*) - NEVER WIRE CODES
'
' The setup failures in components/SyncPlayTask.brs (config/host/socket/
' connect) and the REST-path failures in components/SyncPlayScene.brs
' (create/join/leave/invalid) are produced ON THIS DEVICE and ride no frame.
' They are not "unrecognized server codes", so they must not squat in the
' wire census SyncPlayKnownErrorCodes() (Check 22 pins that list by content
' to exactly the 16 emitted-verified + 3 declared-reserved wire codes, and
' that honesty is the point).
'
' They DO reuse the W5 MAPPING LAW verbatim (SyncPlayErrorCodeToKey) under a
' reserved "local." mint prefix: law("local.connect_failed") =
' "errors_local_connect_failed", so the catalog keeps ONE errors registry
' and the resolver keeps ONE normalization. The `local.` prefix can never be
' produced by the server registry (domains are SCREAMING legacy or dotted
' namespaces like syncplay.*), so provenance is carried by the census, not
' by the key shape.
'
' SEPARATION LAW (mirrored by Check 23 in scripts/verify-runtime.sh):
'   1. every SyncPlayLocalErrorCodes() entry matches local.<snake_name>
'   2. no SyncPlayKnownErrorCodes() entry starts with "local."
'   3. the two families never normalize onto one catalog key
'   4. every errors_local_* key in en_US is a member of the local census,
'      and every errors_* key belongs to wire OR fallback OR local
'      (bidirectional registry - nothing unaccounted may squat)
'   5. EmitError call sites pass census codes, never raw display literals
' ===========================================

' Canonical client-generated error codes (SyncPlayTask setup + SyncPlayScene
' REST paths). Every element MUST resolve to an errors_<law(key)> entry in
' ALL seven locale catalogs - Check 23 enforces the en_US side plus the
' separation law, Check 21 pins cross-locale parity.
' Pure: returns a fresh array; callers must not mutate module state through it.
' @return Object - roArray of "local.*" code strings (never wire values)
function SyncPlayLocalErrorCodes() as Object
    codes = []
    codes.push("local.no_config")
    codes.push("local.no_host")
    codes.push("local.socket_unavailable")
    codes.push("local.connect_failed")
    codes.push("local.connect_timeout")
    codes.push("local.room_create_failed")
    codes.push("local.room_join_failed")
    codes.push("local.room_leave_failed")
    codes.push("local.invalid_room")
    return codes
end function

' Resolve the user-facing line for one client-generated local.* code.
' Unlike LocalizeSyncPlayError (wire frames - a "" return lets the caller's
' last-resort literal speak), this resolver NEVER returns empty and never
' needs an English literal argument: the string was minted here, so the
' priority is catalog hit -> errors_fallback line -> raw key echo. A fully
' dead catalog rendering the key is VISIBLE breakage, which beats a blank
' status label (the task thread has no other channel to report through).
' @param code Object - "local.*" code string
' @return String - non-empty user-facing text in the device language
function LocalizeSyncPlayLocalError(code as Object) as String
    key = SyncPlayErrorCodeToKey(code)
    text = Translate(key)
    if text <> key then return text
    fallback = Translate("errors_fallback")
    if fallback <> "errors_fallback" then return fallback
    return key
end function
