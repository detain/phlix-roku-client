' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ChannelListTask.brs

' ===========================================
' ChannelListTask — loads live-TV channel list off the render thread.
'
' The problem: LiveTvScene uses ApiTask for the HTTP call, but OnApiResponse
' processes the result (ContentNode build + ChannelRowCaption) on the render
' thread. With large lists this causes visible UI blocking.
'
' The fix: this dedicated Task fetches AND builds the ContentNode on its own
' thread, then ships a ready-to-assign ContentNode and raw channels array to
' the scene. The scene uses the raw channels for navigation (id/name) and the
' ContentNode for display.
'
' Thread rule: this function runs on the task thread; it may ONLY read its own
' m.top.* fields and write m.top.content/channels/ok. It must NOT touch
' UI/parent nodes. Only assocarray/string/number/node data crosses the thread
' boundary.
' ===========================================

sub Init()
    m.top.functionName = "LoadChannels"
end sub

sub LoadChannels()
    ' R2.7: Invalidate the Storage read cache so we re-read the freshest values
    ' from the registry.
    ResetCachedStorage(false)

    api = GetApiClient()
    if api = invalid then
        m.top.response = {
            ok: false,
            channels: [],
            content: invalid
        }
        return
    end if

    ' Fetch channels via getChannels (returns the WHOLE envelope {success,channels:[...]}).
    data = api.getChannels()
    if data = invalid or data.channels = invalid or type(data.channels) <> "roArray" then
        m.top.response = {
            ok: false,
            channels: [],
            content: invalid
        }
        return
    end if

    channels = data.channels

    ' Build the ContentNode tree off the render thread.
    content = CreateObject("roSGNode", "ContentNode")

    for each channel in channels
        if channel <> invalid then
            content.AddChild({ title: ChannelRowCaption(channel) })
        end if
    end for

    m.top.content = content
    m.top.channels = channels
    m.top.ok = true
    m.top.response = {
        ok: true,
        channels: channels,
        content: content
    }
end sub

' Caption for a channel row: "<number>  <name>". number is an INTEGER -> guard
' DoesExist + invalid only (NEVER an Integer<>String compare), then stringify via
' str(Int(...)).trim(). name guards DoesExist + invalid + "". If no number, just
' the name; if no name, just the number.
' NOTE: This is a copy of LiveTvScene.ChannelRowCaption for thread-safety -
' task thread cannot call scene functions.
function ChannelRowCaption(channel as Object) as String
    if channel = invalid then return ""

    number = ""
    if channel.DoesExist("number") and channel.number <> invalid then
        number = str(Int(channel.number)).trim()
    end if

    name = ""
    if channel.DoesExist("name") and channel.name <> invalid and channel.name <> "" then
        name = channel.name
    end if

    if number <> "" and name <> "" then return number + "  " + name
    if number <> "" then return number
    return name
end function