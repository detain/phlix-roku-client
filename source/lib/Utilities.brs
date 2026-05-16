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
    return str.Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", """")).Replace("&amp;", "&")
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