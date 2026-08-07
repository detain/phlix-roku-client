' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/PosterMetaTask.brs

' ===========================================
' PosterMetaTask — fetches poster image dimensions off the render thread.
'
' The problem: when a PosterGrid scrolls and new Posters appear, the runtime
' must decode image data to determine dimensions for aspect-ratio-correct rendering.
' If this happens on the render thread during scroll, it causes frame drops.
'
' The fix: pre-fetch image dimensions on a background Task using roBitmap,
' which runs on its own thread and does not block the render thread.
'
' THREAD RULE: this function runs on the task thread; it may ONLY read its own
' m.top.urls and write m.top.results. It must NOT touch UI/parent nodes.
' ===========================================

sub Init()
    m.top.functionName = "FetchPosterMeta"
end sub

' Fetch dimensions for all URLs in m.top.urls (an array of string URLs).
' Results are written to m.top.results as an assocarray:
'   { results: [ {url, width, height, aspectRatio, ok}, ... ] }
sub FetchPosterMeta()
    urls = m.top.urls
    if urls = invalid or type(urls) <> "roArray" then
        m.top.results = { results: [], ok: false }
        return
    end if

    results = []
    for each url in urls
        meta = GetPosterMeta(url)
        results.Push(meta)
    end for

    m.top.results = { results: results, ok: true }
end sub

' Fetch metadata for a single poster URL.
' Returns an assocarray: {url, width, height, aspectRatio, ok}
function GetPosterMeta(url as String) as Object
    meta = { url: url, width: 0, height: 0, aspectRatio: 0#, ok: false }

    if url = invalid or url = "" or left(url, 4) <> "http" then
        ' Skip non-http URLs (e.g., pkg:/ package assets)
        return meta
    end if

    ' roBitmap can be created directly from a remote URL string.
    ' This downloads and decodes the image on the task thread, not the render thread.
    ' If the image cannot be loaded (network error, invalid image), the bitmap
    ' creation returns invalid and we return meta with ok=false.
    bmp = CreateObject("roBitmap", url)
    if bmp = invalid then
        return meta
    end if

    width = bmp.GetWidth()
    height = bmp.GetHeight()

    if width > 0 and height > 0 then
        meta.width = width
        meta.height = height
        meta.aspectRatio = width / height
        meta.ok = true
    end if

    return meta
end function
