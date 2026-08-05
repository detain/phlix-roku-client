' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' main.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Phlix Media Server - Roku App
' Main entry point
' ===========================================

' Deep-link argument keys (lowercase). Roku passes these in the launch query
' string (e.g. /launch/dev?contentId=123&mediaType=movie) and they appear
' as lowercase keys in the args assocarray. We check case-insensitively per
' Roku's deep-linking docs:
' https://developer.roku.com/docs/developer-program/deep-linking

' Validate a deep-link contentId before using it in a URL path.
' contentId is a URL-encoded ASCII string (max 255 chars) from an external
' partner (Roku Search, ECP curl, etc.). Reject anything suspicious:
' - missing/invalid
' - too long (>255 chars)
' - contains unencoded & (URL delimiter)
' - contains non-printable or non-ASCII bytes
' Returns true only when the id is safe to embed in a request path.
' @param contentId Dynamic - the raw contentId value (may be invalid)
' @return Boolean - true when the value passes all checks
function ValidateDeepLinkContentId(contentId as Dynamic) as Boolean
    if contentId = invalid then return false
    if type(contentId) <> "String" and type(contentId) <> "roString" then return false
    trimmed = contentId.Trim()
    if trimmed = "" then return false
    ' Max 255 chars per Roku spec
    if trimmed.Len() > 255 then return false
    ' No unencoded & (URL delimiter) — raw & would break query-string parsing
    if Instr(1, trimmed, "&") > 0 then return false
    ' Reject non-printable / non-ASCII (allow only ASCII printable range)
    for i = 1 to trimmed.Len()
        c = Asc(Mid(trimmed, i, 1))
        if c < 32 or c > 126 then return false
    end for
    return true
end function

' Map a Roku mediaType to a routing action.
' MediaType values from Roku deep-linking spec:
'   movie, episode, shortformvideo, tvspecial -> direct playback (DetailScene)
'   series -> smart bookmark (play next unwatched or resume position)
'   season -> episode picker (SeasonScene)
' Returns "" when the mediaType is not recognized.
' @param mediaType String - the raw mediaType from deep-link args
' @return String - routing action: "play", "series", "season", or ""
function MapDeepLinkMediaType(mediaType as String) as String
    if mediaType = invalid then return ""
    lower = mediaType.Trim().Lower()
    ' Direct-playback types: movie, episode, shortformvideo, tvspecial
    if lower = "movie" or lower = "episode" or lower = "shortformvideo" or lower = "tvspecial" then
        return "play"
    else if lower = "series" then
        return "series"
    else if lower = "season" then
        return "season"
    end if
    return ""
end function

' Extract and validate deep-link parameters from the launch args.
' Returns an assocarray with keys { contentId, mediaType, action } when valid,
' or invalid when either parameter is absent/invalid.
' @param args Object - the assocarray passed to Main()
' @return Object - valid deep-link params, or invalid
function ExtractDeepLinkParams(args as Object) as Object
    if args = invalid or type(args) <> "roAssociativeArray" then return invalid

    ' Deep-link keys (lowercase, per Roku's deep-linking documentation)
    deepLinkContentIdKey = "contentid"
    deepLinkMediaTypeKey = "mediatype"

    ' Per Roku docs, use case-insensitive key lookup
    contentId = invalid
    mediaType = invalid
    for each key in args.Keys()
        k = key.Trim().Lower()
        if k = deepLinkContentIdKey then contentId = args[key]
        if k = deepLinkMediaTypeKey then mediaType = args[key]
    end for

    if not ValidateDeepLinkContentId(contentId) then return invalid
    action = MapDeepLinkMediaType(mediaType)
    if action = "" then return invalid

    return { contentId: contentId, mediaType: mediaType, action: action }
end function

sub main(args as Object)
    print "Phlix Roku App Starting..."

    ' Extract and validate cold-launch deep-link parameters (R6.3).
    ' If args are absent or invalid the app boots normally; if they are present
    ' but fail validation we fall through to the home screen rather than
    ' erroring, per Roku's deep-linking certification requirements.
    ' Docs: https://developer.roku.com/docs/developer-program/deep-linking
    deepLinkParams = ExtractDeepLinkParams(args)
    if deepLinkParams <> invalid then
        print "Deep link received: contentId=" deepLinkParams.contentId " mediaType=" deepLinkParams.mediaType
    else
        print "No valid deep link in launch args"
    end if

    ' Create and show the main app component
    screen = CreateObject("roSGScreen")
    scene = screen.CreateScene("PhlixApp")

    ' Pass validated deep-link params to PhlixApp so it can route the user
    ' to the correct scene instead of the home screen (R6.3 requirement).
    ' PhlixApp.Init reads m.top.deepLinkParams and processes it after auth.
    if deepLinkParams <> invalid then
        scene.deepLinkParams = deepLinkParams
    end if

    screen.Show()

    ' Message loop
    while true
        msg = wait(0, screen.GetMessagePort())
        if msg = invalid then
            exit while
        end if
    end while

    print "Phlix Roku App Exiting..."
end sub