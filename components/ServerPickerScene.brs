' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ServerPickerScene.brs

' copyright 2026 Joe Huss
'

'
' F12b hub mode: a one-shot LabelList of the hub user's servers
' (GET /me/servers via the ApiTask `getMyServers` op). Mirrors UserAdminScene's
' LabelList + ApiTask + OnApiResponse idiom - the load fires once on Init.
' Selecting a row persists active_server_id (camelCase serverId, stringify-
' guarded) + active_server_name and fires the observed `serverPicked` field;
' PhlixApp then rebuilds m.api against the relay base and shows Home.
'
' PhlixApp self-creates + focuses this scene and observes `serverPicked`, so the
' interface is an observed FIELD, not a function (mirrors ConnectScene's
' `connected`).
'
' LANDMINES: /me/servers is CAMELCASE (serverId/serverName/relayActive/
' libraryCount/status). serverId may arrive as a JSON number -> stringify-guard
' before "/" + concat (String+Integer concat CRASHES). NEVER `<> ""` on
' libraryCount (numeric) - guard DoesExist + type then str(Int()). status is a
' string (safe compare).

sub Init()
    m.top.SetFocus(true)

    ' Text list of servers.
    m.serverList = m.top.FindNode("serverList")
    if m.serverList <> invalid then
        m.serverList.ObserveField("itemSelected", "OnRowSelected")
        m.serverList.ObserveField("itemFocused", "OnRowFocused")
        m.serverList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.servers = []

    SetStatus("Loading…")

    ' One-shot load on Init. active_server_id is empty at this point, so the
    ' ApiTask's GetApiClient binds to the bare hub url -> the call hits the hub.
    m.apiTask.request = { op: "getMyServers" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getMyServers" then
        ' getMyServers() returns the WHOLE envelope {servers:[...]}.
        m.servers = []
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("servers") and type(resp.data.servers) = "roArray" then
            m.servers = resp.data.servers
        end if

        content = CreateObject("roSGNode", "ContentNode")
        for each server in m.servers
            if server <> invalid then
                content.AddChild({ title: ServerRowCaption(server) })
            end if
        end for

        if m.serverList <> invalid then m.serverList.content = content

        if m.servers.Count() = 0 then
            SetStatus("No servers")
        else
            SetStatus("")
        end if
    end if
end sub

' Caption for a server row: "<name>  (<status>, <n> libs)" - the tags are only
' appended when present. name = serverName (fallback "(server)"). status is a
' STRING (safe compare; it already conveys online/offline). libraryCount is
' NUMERIC -> str(Int()) behind a DoesExist + type guard, NEVER a `<> ""` compare.
function ServerRowCaption(server as Object) as String
    if server = invalid then return ""

    name = ""
    if server.DoesExist("serverName") and server.serverName <> invalid and server.serverName <> "" then
        name = server.serverName
    else
        name = "(server)"
    end if

    tags = []

    if server.DoesExist("status") and server.status <> invalid and server.status <> "" then
        tags.Push(server.status)
    end if

    if server.DoesExist("libraryCount") and server.libraryCount <> invalid then
        lc = server.libraryCount
        t = type(lc)
        if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
            tags.Push(str(Int(lc)).trim() + " lib(s)")
        end if
    end if

    ' (No separate "offline" tag - the status tag above already conveys it.)

    if tags.Count() = 0 then return name

    suffix = ""
    for i = 0 to tags.Count() - 1
        if i > 0 then suffix = suffix + ", "
        suffix = suffix + tags[i]
    end for

    return name + "  (" + suffix + ")"
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.servers.Count() then return

    server = m.servers[index]
    if server = invalid then return

    ' Stringify the serverId BEFORE persisting / building the relay path - a
    ' serverId may arrive as a JSON number, and "/api/v1/servers/" + an Integer
    ' would CRASH. Use a String as-is; coerce a numeric via str(Int()).
    id = ""
    if server.DoesExist("serverId") and server.serverId <> invalid then
        rawId = server.serverId
        t = type(rawId)
        if t = "roString" then
            id = rawId
        else if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
            id = str(Int(rawId)).trim()
        end if
    end if

    if id = "" then return

    name = ""
    if server.DoesExist("serverName") and server.serverName <> invalid and server.serverName <> "" then
        name = server.serverName
    end if

    GetStorage().set("active_server_id", id)
    GetStorage().set("active_server_name", name)
    GetStorage().flush()  ' R1.6: batched flush after user picks a server

    ' Notify PhlixApp (observes `serverPicked`) -> rebuild m.api + Home.
    m.top.serverPicked = true
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.servers.Count() then return

    server = m.servers[index]
    if server = invalid then return

    SetStatus(ServerRowCaption(server))
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.serverList <> invalid then
        m.serverList.UnObserveField("itemSelected")
        m.serverList.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            ' No back-out before a server is chosen (keep it simple - eat back).
            handled = true
        end if
    end if

    return handled
end function