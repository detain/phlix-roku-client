'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/SyncPlayManager.brs

' copyright 2026 Joe Huss
'

' ===========================================
' SyncPlay Manager for Roku
' Coordinates REST API calls and WebSocket connection for SyncPlay (watch-together).
' ===========================================
'
' Types (mirroring @phlix/contracts v0.3.6):
'   SyncPlaySession: { roomId, sessionId, serverUrl }
'   SyncPlayRoom: { id, name, isPublic, memberCount }
'   SyncPlayUser: { sessionId, displayName }
'   SyncPlayPlaybackCommand: { type: 'play' | 'pause' | 'seek', position?: number, timestamp: number }
'
' API Endpoints:
'   GET  /api/v1/syncplay/rooms        - public rooms list
'   POST /api/v1/syncplay/rooms        - create room { name, isPublic } -> { roomId, sessionId, serverUrl }
'   POST /api/v1/syncplay/rooms/{id}/join   - join room -> { sessionId, members, currentState }
'   DELETE /api/v1/syncplay/rooms/{id}/leave - leave room
'   WS   /api/v1/syncplay/{roomId}?token=JWT - WebSocket for real-time sync
'
' Usage:
'   syncMgr = SyncPlayManager(GetApiClient())
'   rooms = syncMgr.getRooms()
'   session = syncMgr.createRoom("My Room", true)
'   syncMgr.joinRoom(session.roomId)
'   syncMgr.leaveRoom()
'

function SyncPlayManager(api as Object) as Object
    obj = {
        api: api

        ' Current SyncPlay session state
        ' { roomId, sessionId, serverUrl, roomName, isHost, members[] }
        _session: invalid

        ' ============================================================= '
        ' Room List (REST)
        ' ============================================================= '

        ' GET /syncplay/rooms -> {rooms:[{id,name,isPublic,memberCount}]}
        ' Returns array of public rooms or empty array on failure.
        getRooms: function() as Object
            if m.api = invalid then return []

            result = m.api.getSyncPlayRooms()
            if result = invalid then return []

            ' The response is {rooms: [...]} per ApiClient convention
            if type(result) <> "roAssociativeArray" then return []
            if not result.DoesExist("rooms") then return []
            rooms = result.rooms
            if type(rooms) <> "roArray" then return []

            return rooms
        end function

        ' ============================================================= '
        ' Room Management (REST)
        ' ============================================================= '

        ' POST /syncplay/rooms {name,isPublic} -> {roomId,sessionId,serverUrl}
        ' Creates a new room and returns the session info for WebSocket connection.
        ' Returns invalid on failure.
        createRoom: function(name as String, isPublic as Boolean) as Object
            if m.api = invalid then return invalid

            result = m.api.createSyncPlayRoom(name, isPublic)
            if result = invalid then return invalid

            ' Parse response: {roomId, sessionId, serverUrl}
            if type(result) <> "roAssociativeArray" then return invalid
            if not result.DoesExist("roomId") then return invalid

            m._session = {
                roomId: result.roomId
                sessionId: result.sessionId
                serverUrl: result.serverUrl
                roomName: name
                isHost: true
                members: []
            }

            return m._session
        end function

        ' POST /syncplay/rooms/{id}/join -> {sessionId,members,currentState}
        ' Joins an existing room by roomId.
        ' Returns invalid on failure.
        joinRoom: function(roomId as String) as Object
            if m.api = invalid then return invalid

            result = m.api.joinSyncPlayRoom(roomId)
            if result = invalid then return invalid

            ' Parse response: {sessionId, members:[...], currentState:{...}}
            if type(result) <> "roAssociativeArray" then return invalid
            if not result.DoesExist("sessionId") then return invalid

            members = []
            if result.DoesExist("members") and type(result.members) = "roArray" then
                members = result.members
            end if

            currentState = invalid
            if result.DoesExist("currentState") and type(result.currentState) = "roAssociativeArray" then
                currentState = result.currentState
            end if

            m._session = {
                roomId: roomId
                sessionId: result.sessionId
                serverUrl: ""
                roomName: ""
                isHost: false
                members: members
                currentState: currentState
            }

            return m._session
        end function

        ' DELETE /syncplay/rooms/{id}/leave -> {message}
        ' Leaves the current room and clears session state.
        leaveRoom: function() as Object
            if m.api = invalid or m._session = invalid then return invalid

            roomId = m._session.roomId
            result = m.api.leaveSyncPlayRoom(roomId)

            m._session = invalid
            return result
        end function

        ' ============================================================= '
        ' Session State Accessors
        ' ============================================================= '

        ' Get current session or invalid if not in a room.
        getSession: function() as Object
            return m._session
        end function

        ' True if currently in a SyncPlay room.
        isInRoom: function() as Boolean
            return m._session <> invalid
        end function

        ' True if this device is the host of the current room.
        isHost: function() as Boolean
            if m._session = invalid then return false
            return m._session.isHost
        end function

        ' Get the room ID of the current session.
        getRoomId: function() as String
            if m._session = invalid then return ""
            return m._session.roomId
        end function

        ' Get the session ID of the current session.
        getSessionId: function() as String
            if m._session = invalid then return ""
            return m._session.sessionId
        end function

        ' Get the WebSocket server URL for the current room.
        getServerUrl: function() as String
            if m._session = invalid then return ""
            return m._session.serverUrl
        end function

        ' Get the room name.
        getRoomName: function() as String
            if m._session = invalid then return ""
            return m._session.roomName
        end function

        ' Get member count.
        getMemberCount: function() as Integer
            if m._session = invalid then return 0
            if m._session.members = invalid then return 0
            return m._session.members.Count()
        end function

        ' ============================================================= '
        ' WebSocket Configuration Builder
        ' ============================================================= '

        ' Build WebSocket URL parts from the current session's serverUrl.
        ' Returns {host, port, path} for SyncPlayTask.config.
        ' Forces ws:// (plaintext TCP, no TLS).
        ' Returns invalid if not in a room or no serverUrl.
        buildWsParts: function() as Object
            if m._session = invalid then return invalid

            serverUrl = m._session.serverUrl
            if serverUrl = invalid or serverUrl = "" then return invalid

            ' Strip scheme
            rest = serverUrl
            schemeIdx = Instr(1, rest, "://")
            if schemeIdx > 0 then rest = Mid(rest, schemeIdx + 3)

            ' Drop any path/query after authority
            slashIdx = Instr(1, rest, "/")
            if slashIdx > 0 then rest = Left(rest, slashIdx - 1)

            ' Split host:port
            host = rest
            colonIdx = Instr(1, rest, ":")
            if colonIdx > 0 then host = Left(rest, colonIdx - 1)
            if host = "" then return invalid

            ' Extract port if present
            port = 8097
            if colonIdx > 0 then
                portStr = Mid(rest, colonIdx + 1)
                portVal = 0
                for i = 1 to Len(portStr)
                    c = Asc(Mid(portStr, i, 1))
                    if c >= 48 and c <= 57 then
                        portVal = portVal * 10 + (c - 48)
                    else
                        exit for
                    end if
                end for
                if portVal > 0 then port = portVal
            end if

            ' Build path with roomId and token
            token = Storage.get("auth_token")
            if token = invalid then token = ""

            path = "/syncplay/" + m._session.roomId + "?token=" + UrlEncode(token)

            return { host: host, port: port, path: path }
        end function

        ' ============================================================= '
        ' State Updates (from WebSocket events)
        ' ============================================================= '

        ' Update session state from a group_state event.
        ' event = { group: {...}, your_id: "..." }
        updateFromGroupState: function(event as Object) as Void
            if m._session = invalid then return

            if event.DoesExist("your_id") and event.your_id <> invalid then
                m._session.yourId = event.your_id
            end if

            if event.DoesExist("group") and type(event.group) = "roAssociativeArray" then
                group = event.group

                if group.DoesExist("group_name") and type(group.group_name) = "roString" then
                    m._session.roomName = group.group_name
                end if

                if group.DoesExist("member_count") then
                    m._session.memberCount = group.member_count
                end if

                if group.DoesExist("host_id") and group.host_id <> invalid then
                    hostIdStr = StringifyId(group.host_id)
                    m._session.isHost = (hostIdStr <> "" and hostIdStr = m._session.yourId)
                end if

                if group.DoesExist("members") and type(group.members) = "roArray" then
                    m._session.members = group.members
                end if
            end if
        end function
    }

    return obj
end function

' Helper: Stringify an id that may be numeric or string.
' Avoids crashes from Integer<>String comparison.
function StringifyId(v as Object) as String
    if v = invalid then return ""
    tp = type(v)
    if tp = "String" or tp = "roString" then return v
    if tp = "Integer" or tp = "roInt" then return str(v).Trim()
    if tp = "LongInteger" or tp = "roLongInteger" then return (str(v)).Trim()
    if tp = "Float" or tp = "roFloat" or tp = "Double" or tp = "roDouble" then return str(Int(v)).Trim()
    return ""
end function