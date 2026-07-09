' components/SyncPlayScene.brs

' copyright 2026 Joe Huss
'

' ===========================================
' SyncPlay Scene - P8-S4 Room management UI
' Shows public rooms list, create/join form, and room info when joined.
' ===========================================

sub Init()
    m.top.SetFocus(true)

    ' UI nodes
    m.roomListPanel = m.top.FindNode("roomListPanel")
    m.roomInfoPanel = m.top.FindNode("roomInfoPanel")
    m.backButton = m.top.FindNode("backButton")
    m.roomNameInput = m.top.FindNode("roomNameInput")
    m.publicToggle = m.top.FindNode("publicToggle")
    m.createButton = m.top.FindNode("createButton")
    m.roomList = m.top.FindNode("roomList")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.currentRoomName = m.top.FindNode("currentRoomName")
    m.roomStatus = m.top.FindNode("roomStatus")
    m.memberList = m.top.FindNode("memberList")
    m.syncStatusLabel = m.top.FindNode("syncStatusLabel")
    m.leaveButton = m.top.FindNode("leaveButton")

    ' Button observers
    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if
    if m.createButton <> invalid then
        m.createButton.ObserveField("buttonSelected", "OnCreatePressed")
    end if
    if m.leaveButton <> invalid then
        m.leaveButton.ObserveField("buttonSelected", "OnLeavePressed")
    end if
    if m.roomList <> invalid then
        m.roomList.ObserveField("itemSelected", "OnRoomSelected")
    end if

    ' Initialize SyncPlayManager
    m.syncMgr = SyncPlayManager(GetApiClient())

    ' Room data cache
    m.rooms = []

    ' Load public rooms list
    LoadRooms()
end sub

' Load public rooms from REST API
sub LoadRooms()
    SetStatus("Loading rooms...")
    m.rooms = m.syncMgr.getRooms()
    PopulateRoomList()
    if m.rooms.Count() = 0 then
        SetStatus("No public rooms available. Create one to start!")
    else
        SetStatus("")
    end if
end sub

' Populate the LabelList with rooms
sub PopulateRoomList()
    if m.roomList = invalid then return

    content = CreateObject("roSGNode", "ContentNode")
    for each room in m.rooms
        if room <> invalid then
            content.AddChild({ title: RoomCaption(room) })
        end if
    end for
    m.roomList.content = content
end sub

' Caption for a room row: "<name> (<n> members) [public/private]"
function RoomCaption(room as Object) as String
    if room = invalid then return ""

    name = "Room"
    if room.DoesExist("name") and type(room.name) = "roString" and room.name <> "" then
        name = room.name
    else if room.DoesExist("roomName") and type(room.roomName) = "roString" and room.roomName <> "" then
        name = room.roomName
    end if

    count = ""
    if room.DoesExist("memberCount") and room.memberCount <> invalid then
        count = " (" + str(Int(room.memberCount)).Trim() + " members)"
    else if room.DoesExist("member_count") and room.member_count <> invalid then
        count = " (" + str(Int(room.member_count)).Trim() + " members)"
    end if

    visibility = ""
    if room.DoesExist("isPublic") then
        if room.isPublic = true or room.isPublic = "true" then
            visibility = " [public]"
        else
            visibility = " [private]"
        end if
    end if

    return name + count + visibility
end function

' Create a new room
sub OnCreatePressed()
    if m.roomNameInput = invalid then return

    roomName = m.roomNameInput.text
    if roomName = invalid or roomName = "" then
        roomName = "Roku Room"
    end if

    isPublic = true
    if m.publicToggle <> invalid then
        isPublic = m.publicToggle.checked
    end if

    SetStatus("Creating room...")

    session = m.syncMgr.createRoom(roomName, isPublic)
    if session = invalid or session.roomId = invalid or session.roomId = "" then
        SetStatus("Failed to create room")
        return
    end if

    ' Success - notify parent that we created and joined
    m.top.action = "created:" + session.roomId
end sub

' Join selected room from list
sub OnRoomSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.rooms.Count() then return

    room = m.rooms[index]
    if room = invalid then return

    ' Get room ID (handle both id and roomId field names)
    roomId = ""
    if room.DoesExist("id") and room.id <> invalid then
        roomId = SyncStringifyId(room.id)
    else if room.DoesExist("roomId") and room.roomId <> invalid then
        roomId = SyncStringifyId(room.roomId)
    end if

    if roomId = "" then
        SetStatus("Invalid room")
        return
    end if

    SetStatus("Joining room...")

    session = m.syncMgr.joinRoom(roomId)
    if session = invalid then
        SetStatus("Failed to join room")
        return
    end if

    ' Success - notify parent
    m.top.action = "joined:" + roomId
end sub

' Leave current room
sub OnLeavePressed()
    result = m.syncMgr.leaveRoom()
    if result = invalid then
        SetStatus("Failed to leave room")
        return
    end if

    ' Show room list panel again
    ShowRoomListPanel()
    LoadRooms()

    m.top.action = "left"
end sub

' Back button pressed
sub OnBackPressed()
    ' If in a room, leave first
    if m.syncMgr.isInRoom() then
        m.syncMgr.leaveRoom()
    end if

    m.top.action = "back"
end sub

' Show room list panel (when not in a room)
sub ShowRoomListPanel()
    if m.roomListPanel <> invalid then m.roomListPanel.visible = true
    if m.roomInfoPanel <> invalid then m.roomInfoPanel.visible = false
    if m.roomList <> invalid then m.roomList.SetFocus(true)
end sub

' Show room info panel (when in a room)
sub ShowRoomInfoPanel()
    if m.roomListPanel <> invalid then m.roomListPanel.visible = false
    if m.roomInfoPanel <> invalid then m.roomInfoPanel.visible = true
    if m.leaveButton <> invalid then m.leaveButton.SetFocus(true)

    ' Update room info display
    if m.currentRoomName <> invalid then
        m.currentRoomName.text = m.syncMgr.getRoomName()
    end if
    if m.roomStatus <> invalid then
        role = "Guest"
        if m.syncMgr.isHost() then role = "Host"
        m.roomStatus.text = role + " - " + str(m.syncMgr.getMemberCount()).Trim() + " members"
    end if
    if m.syncStatusLabel <> invalid then
        m.syncStatusLabel.text = "Connected to room"
    end if
end sub

' Set status message
sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Cleanup on scene close
sub Teardown()
    if m.backButton <> invalid then m.backButton.UnObserveField("buttonSelected")
    if m.createButton <> invalid then m.createButton.UnObserveField("buttonSelected")
    if m.leaveButton <> invalid then m.leaveButton.UnObserveField("buttonSelected")
    if m.roomList <> invalid then m.roomList.UnObserveField("itemSelected")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            OnBackPressed()
            handled = true
        end if
    end if

    return handled
end function

' Stringify an id that may be numeric or string.
function SyncStringifyId(v as Object) as String
    if v = invalid then return ""
    tp = type(v)
    if tp = "String" or tp = "roString" then return v
    if tp = "Integer" or tp = "roInt" then return str(v).Trim()
    if tp = "LongInteger" or tp = "roLongInteger" then return (str(v)).Trim()
    if tp = "Float" or tp = "roFloat" or tp = "Double" or tp = "roDouble" then return str(Int(v)).Trim()
    return ""
end function