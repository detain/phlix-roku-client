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
' M-ROKU-13 (review roku__exploiter M2): this is now a thin delegate onto the
' canonical shape guard IsSafeContentId() (source/lib/Utilities.brs — source
' scripts share the main-thread scope, and components script-include it). The
' era's printable-minus-"&" checker let "/ ? = # ." and spaces through into
' ApiClient's "/media/" + itemId raw concatenation, so an ECP/launch-args
' attacker could reshape the outbound authenticated path. The allowlist
' [A-Za-z0-9_-] closes that class at this entry; the play choke
' (PhlixApp.ProcessDeepLink) re-gates independently.
' Returns true only when the id is safe to embed in a request path; the value
' is judged in its trimmed form — ExtractDeepLinkParams forwards the trimmed
' value so padding can never re-enter.
' @param contentId Dynamic - the raw contentId value (may be invalid)
' @return Boolean - true when the value passes the canonical shape law
function ValidateDeepLinkContentId(contentId as Dynamic) as Boolean
    return IsSafeContentId(contentId)
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
    lower = LCase(mediaType.Trim())
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
        k = LCase(key.Trim())
        if k = deepLinkContentIdKey then contentId = args[key]
        if k = deepLinkMediaTypeKey then mediaType = args[key]
    end for

    if not ValidateDeepLinkContentId(contentId) then return invalid
    action = MapDeepLinkMediaType(mediaType)
    if action = "" then return invalid

    ' M-ROKU-13: forward the TRIMMED id (the guard judges the trimmed form;
    ' handing downstream code the padded raw value would let whitespace re-enter
    ' the path concat). A passing id is String-typed, so .Trim() is safe here.
    return { contentId: contentId.Trim(), mediaType: mediaType, action: action }
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

    ' R6.4: Create roInput to receive warm deep links (ECP input command).
    ' roInput receives contentId/mediaType when the channel is already running.
    ' Docs: https://developer.roku.com/docs/developer-program/deep-linking
    ' Requires manifest: supports_input_launch=1 (R6.4 requirement).
    input = CreateObject("roInput")
    input.SetMessagePort(screen.GetMessagePort())

    ' M-ROKU-01: Watch the root's exitChannel flag on this same port. When the
    ' screen stack is empty and Back is pressed, PhlixApp.OnKeyEvent raises it
    ' and the loop below returns — ending the channel cleanly. (Falling through
    ' to RSG's native back handling instead only closes the focused child scene,
    ' exposing the root's black boot chrome; see review roku__casualgamer M2.)
    scene.ObserveField("exitChannel", screen.GetMessagePort())

    ' Message loop — handles screen events, the exitChannel signal, and roInput
    ' deep-link events. roInput events arrive as roInputEvent objects with an
    ' "args" field containing the same assocarray as cold-launch args
    ' (contentid, mediatype).
    while true
        msg = wait(0, screen.GetMessagePort())
        if msg = invalid then
            exit while
        end if

        ' M-ROKU-01: Clean exits. isScreenClosed covers the OS closing the root
        ' screen; the exitChannel roSGNodeEvent covers Back-at-empty-stack. Both
        ' end main(), which is the SceneGraph-correct channel exit (no creatable
        ' roApp.Exit() exists in the official component library).
        if type(msg) = "roSGScreenEvent" then
            if msg.isScreenClosed() then
                exit while
            end if
        else if type(msg) = "roSGNodeEvent" then
            if msg.GetField() = "exitChannel" then
                exit while
            end if
        end if

        ' R6.4: Handle warm deep-link events from roInput.
        ' roInputEvent is fired when ECP POSTs to :8060/input with contentId/mediaType.
        ' Docs: https://developer.roku.com/docs/developer-program/deep-linking
        if type(msg) = "roInputEvent" then
            args = msg.GetArgs()
            if args <> invalid then
                print "Warm deep link received via roInput"
                ' R6.3 validation/routing is shared: cold and warm paths map identically.
                warmDeepLinkParams = ExtractDeepLinkParams(args)
                if warmDeepLinkParams <> invalid then
                    print "Warm deep link valid: contentId=" warmDeepLinkParams.contentId " mediaType=" warmDeepLinkParams.mediaType
                    ' Signal PhlixApp to handle the warm deep link.
                    ' PhlixApp.ProcessWarmDeepLink checks for active playback,
                    ' stops it cleanly (R4.4 progress + completion), then routes.
                    scene.HandleWarmDeepLink(warmDeepLinkParams)
                else
                    print "Warm deep link invalid params"
                end if
            end if
        end if
    end while

    print "Phlix Roku App Exiting..."
end sub