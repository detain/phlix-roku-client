' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/LiveTvScene.brs

' copyright 2026 Joe Huss
'

'
' Live TV channels list: a one-shot LabelList of the server's live-TV channels.
' Mirrors UserAdminScene's LabelList + ApiTask + OnApiResponse idiom - the load
' fires once on Init via the `getChannels` op. Selecting a row fires a SECOND op
' (`getChannelStreamUrl`) to resolve that channel's stream, then opens a dedicated
' LivePlayerScene. The two ops are serialized through ONE ApiTask guarded by
' m.pendingOp (mirrors LibraryAdminActionsScene), so two control="run" are never
' outstanding. AdminScene self-creates + focuses this scene, so it has NO
' <interface>.
'
' NOTE: getChannels() returns the WHOLE envelope {success,channels:[...]} (admin
' getters do not unwrap), so OnApiResponse reads resp.data.channels and checks
' resp.data.DoesExist("channels") AND type(resp.data.channels) = "roArray"; the
' key's absence = Live TV unavailable / not configured (routes 404 / non-admin).
'
' DEVICE-UNVERIFIABLE: channel playback depends on resolving a Bearer-gated 302
' to an unauthenticated tuner/HLS url (ApiClient.resolveLocation) - roUrlTransfer
' redirect-follow behavior is firmware-dependent. If resolution fails the row
' select shows a friendly status and never opens the player. See the worklog.

sub Init()
    m.top.SetFocus(true)

    ' Text list of channels.
    m.channelList = m.top.FindNode("channelList")
    if m.channelList <> invalid then
        m.channelList.ObserveField("itemSelected", "OnRowSelected")
        m.channelList.ObserveField("itemFocused", "OnRowFocused")
        m.channelList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Channel list loads through a dedicated Task (off the render thread) to
    ' avoid UI blocking on large lists. ContentNode + raw channels array arrive
    ' ready-built.
    m.channelListTask = CreateObject("roSGNode", "ListTask")
    m.channelListTask.ObserveField("content", "OnChannelListContent")
    m.channelListTask.ObserveField("ok", "OnChannelListOk")

    ' ApiTask is reserved ONLY for getChannelStreamUrl (row selection). One op
    ' at a time is enforced by m.pendingOp guard so a select while a request
    ' is in flight is ignored.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' State. m.pendingOp tracks the one outstanding op (invalid = idle) so a row
    ' select while a request is in flight is ignored. m.pendingTitle carries the
    ' display name across the getChannelStreamUrl round-trip.
    m.channels = []
    m.pendingOp = invalid
    m.pendingTitle = ""

    SetStatus("Loading…")

    ' One-shot channel list load on Init.
    m.channelListTask.op = "getChannels"
    m.channelListTask.control = "run"
end sub

' R2.8: Channel list loads through ListTask — this handler is now
' ONLY for getChannelStreamUrl (row selection).
sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    ' The single outstanding op completed - clear the guard FIRST so any chained
    ' call (or a later row select) is a fresh serialized request.
    m.pendingOp = invalid

    if resp.op = "getChannelStreamUrl" then
        streamUrl = ""
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("stream_url") and resp.data.stream_url <> invalid then
            streamUrl = resp.data.stream_url
        end if

        if streamUrl <> "" then
            ShowPlayer(streamUrl, m.pendingTitle)
            SetStatus("")
        else
            SetStatus("Couldn't start channel")
        end if
    end if
end sub

' R2.8: Handle async channel list load from ListTask.
' The task builds the ContentNode and ships it ready-to-assign; we only
' need to plumb it into the LabelList and update status.
sub OnChannelListContent(event as Object)
    content = event.getData()
    if content = invalid then return

    m.channels = m.channelListTask.items
    if m.channelList <> invalid then m.channelList.content = content

    if m.channelListTask.ok = true then
        if m.channels.Count() = 0 then
            SetStatus("No channels")
        else
            SetStatus("")
        end if
    end if
end sub

sub OnChannelListOk(event as Object)
    ok = event.getData()
    if ok = false then
        ' ok=false -> Live TV not configured or unavailable
        ' (routes 404, or a non-admin 403/JSON {error} body).
        SetStatus("Live TV unavailable")
    end if
end sub

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Caption for a channel row: "<number>  <name>". number is an INTEGER -> guard
' DoesExist + invalid only (NEVER an Integer<>String compare), then stringify via
' str(Int(...)).trim(). name guards DoesExist + invalid + "". If no number, just
' the name; if no name, just the number.
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

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.channels.Count() then return

    channel = m.channels[index]
    if channel = invalid then return

    SetStatus(ChannelRowCaption(channel))
end sub

sub OnRowSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.channels.Count() then return

    channel = m.channels[index]
    if channel = invalid then return

    ' id is the channel UUID (== channel_id) -> the /stream path segment.
    id = ""
    if channel.DoesExist("id") and channel.id <> invalid and channel.id <> "" then
        id = channel.id
    else if channel.DoesExist("channel_id") and channel.channel_id <> invalid and channel.channel_id <> "" then
        id = channel.channel_id
    end if

    name = ChannelRowCaption(channel)

    if id <> "" then PlayChannel(id, name)
end sub

' Resolve + tune a channel (serialized, guarded). A select while an op is in
' flight is ignored (one op at a time - never two control="run"). The display
' title is parked on m.pendingTitle for the getChannelStreamUrl round-trip.
sub PlayChannel(channelId as String, title as String)
    if m.pendingOp <> invalid then return
    if channelId = "" then return

    m.pendingOp = "getChannelStreamUrl"
    m.pendingTitle = title
    SetStatus("Tuning…")
    m.apiTask.request = { op: "getChannelStreamUrl", channelId: channelId }
    m.apiTask.control = "run"
end sub

' Open the dedicated live Video player with the resolved (unauthenticated) stream
' url. Coerce an invalid title to "" before crossing the interface (LoadStream is
' typed String).
sub ShowPlayer(streamUrl as String, title as String)
    name = title
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "LivePlayerScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadStream(streamUrl, name)
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.channelList <> invalid then
        m.channelList.UnObserveField("itemSelected")
        m.channelList.UnObserveField("itemFocused")
    end if
    if m.channelListTask <> invalid then
        m.channelListTask.UnObserveField("content")
        m.channelListTask.UnObserveField("ok")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

' Bubble requestClose from a child scene up to PhlixApp (which holds PopScreen).
sub OnChildRequestClose()
    m.top.requestClose = true
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end function