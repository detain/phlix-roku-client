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
' Types (mirroring @phlix/contracts + actual server fields):
'   SyncPlaySession: { roomId, sessionId, serverUrl, roomName, isHost, members }
'     NOTE: sessionId is set client-side from WS yourId, not from server response.
'           serverUrl is derived client-side from ApiClient baseUrl (ws://host:8097).
'   SyncPlayGroup: { id, name, member_count, has_password, current_media, is_playing }
'     (list response — snake_case per SyncPlaySnapshotService.php:149-156)
'   SyncPlayUser/SyncPlayMember: { id, name, is_host, joined_at }
'     (from GroupState.php getState() members dict — SyncPlay.d.ts:71-76)
'   SyncPlayPlaybackCommand: { type: 'play' | 'pause' | 'seek', position?: number, timestamp: number }
'
' API Endpoints (all under /api/v1/syncplay):
'   GET  /syncplay/groups        -> {groups:[{id,name,member_count,has_password,current_media,is_playing}]}
'   POST /syncplay/groups        -> {success,group:{group_id,group_name,members:{...},...}}
'                                  body: {name,is_public?} — is_public IGNORED by server
'   POST /syncplay/groups/{id}/join -> {success,group:{group_id,group_name,members:{...},...}}
'   POST /syncplay/groups/{id}/leave -> {success,message?:string}
'   WS   /syncplay/{roomId}?token=JWT  -> real-time sync (ws://host:8097/syncplay/{roomId}?token=...)
'
' Usage:
'   syncMgr = SyncPlayManager(GetApiClient())
'   groups = syncMgr.getGroups()
'   session = syncMgr.createGroup("My Group", true)
'   syncMgr.joinGroup(session.roomId)
'   syncMgr.leaveGroup()
'

function SyncPlayManager(api as Object) as Object
    obj = {
        api: api

        ' Current SyncPlay session state
        ' { roomId, sessionId, serverUrl, roomName, isHost, members[] }
        _session: invalid

        ' ============================================================= '
        ' Group List (REST)
        ' ============================================================= '

        ' GET /syncplay/groups -> {groups:[{id,name,member_count,has_password,current_media,is_playing}]}
        ' Server returns snake_case fields (per SyncPlaySnapshotService.php:127-160).
        ' Returns array of public groups or empty array on failure.
        getGroups: function() as Object
            if m.api = invalid then return []

            result = m.api.getSyncPlayGroups()
            if result = invalid then return []

            ' The response is {groups: [...]} per ApiClient convention
            if type(result) <> "roAssociativeArray" then return []
            if not result.DoesExist("groups") then return []
            groups = result.groups
            if type(groups) <> "roArray" then return []

            return groups
        end function

        ' ============================================================= '
        ' Group Management (REST)
        ' ============================================================= '

        ' POST /syncplay/groups {name,is_public} -> {success,group:{group_id,...}}
        ' Creates a new group. Server does NOT return roomId/sessionId/serverUrl;
        ' roomId is derived from group.group_id in the response.
        ' Returns invalid on failure.
        createGroup: function(name as String, isPublic as Boolean) as Object
            if m.api = invalid then return invalid

            result = m.api.createSyncPlayGroup(name, isPublic)
            if result = invalid then return invalid

            ' Parse response: {success, group:{group_id,group_name,member_count,...}}
            ' Source: SyncPlayController.php (controller) + SyncPlayManager.php createGroup (manager)
            '   - group.group_id  -> roomId
            '   - group.group_name -> roomName
            '   - group.members   -> members (associative array, keyed by memberId)
            '   - sessionId/serverUrl are NOT returned by the server; sessionId will be
            '     set to the host's memberId once the WS event confirms our yourId.
            if type(result) <> "roAssociativeArray" then return invalid
            if not result.DoesExist("group") then return invalid
            g = result.group
            if type(g) <> "roAssociativeArray" then return invalid
            if not g.DoesExist("group_id") then return invalid

            roomId = ""
            if g.DoesExist("group_id") and g.group_id <> invalid then roomId = StringifyId(g.group_id)

            ' Extract members from the group object (associative array keyed by memberId)
            members = []
            if g.DoesExist("members") and type(g.members) = "roAssociativeArray" then
                ' Convert the members dict (keyed by memberId) into an array for the session
                for each k in g.members
                    members.Push(g.members[k])
                end for
            end if

            ' Derive roomName from group_name, falling back to the original name param
            roomName = name
            if g.DoesExist("group_name") and type(g.group_name) = "roString" and g.group_name <> "" then
                roomName = g.group_name
            end if

            m._session = {
                roomId: roomId
                sessionId: ""  ' Will be set to our memberId from the WS group_state event
                serverUrl: ""  ' Derived from ApiClient baseUrl (ws://host:8097)
                roomName: roomName
                isHost: true
                members: members
            }

            return m._session
        end function

        ' POST /syncplay/groups/{id}/join -> {success,group:{group_id,group_name,members,...}}
        ' Joins an existing group by roomId. Server does NOT return sessionId at top level;
        ' sessionId is set to our own memberId from the WS group_state event.
        ' Returns invalid on failure.
        joinGroup: function(roomId as String) as Object
            if m.api = invalid then return invalid

            result = m.api.joinSyncPlayGroup(roomId)
            if result = invalid then return invalid

            ' Parse response: {success, group:{group_id,group_name,members:{...},...}}
            ' Source: SyncPlayController.php joinGroup + SyncPlayManager.php joinGroup
            '   - roomId comes from the path parameter (not result.group.group_id)
            '   - group.group_name -> roomName
            '   - group.members    -> members (associative array keyed by memberId)
            '   - currentState fields (playback_position, playback_state) are at group level
            '   - sessionId is NOT returned at top level; we use our own memberId as sessionId
            if type(result) <> "roAssociativeArray" then return invalid
            if not result.DoesExist("group") then return invalid
            g = result.group
            if type(g) <> "roAssociativeArray" then return invalid

            ' Extract members from the group object (associative array keyed by memberId)
            members = []
            if g.DoesExist("members") and type(g.members) = "roAssociativeArray" then
                for each k in g.members
                    members.Push(g.members[k])
                end for
            end if

            ' currentState equivalent: playback_position + playback_state at group level
            currentState = invalid
            if g.DoesExist("playback_position") or g.DoesExist("playback_state") then
                pbPos = 0
                if g.DoesExist("playback_position") then pbPos = g.playback_position
                pbState = "stopped"
                if g.DoesExist("playback_state") then pbState = g.playback_state
                currentState = {
                    playback_position: pbPos
                    playback_state: pbState
                }
            end if

            ' Derive the hub origin for WebSocket from the ApiClient baseUrl.
            ' In hub mode, baseUrl = {hubUrl}/api/v1/servers/{id}/proxy so we strip
            ' the suffix. In direct mode, baseUrl is already the server origin.
            serverUrl = ""
            if m.api.DoesExist("baseUrl") and m.api.baseUrl <> invalid and m.api.baseUrl <> "" then
                base = m.api.baseUrl
                ' Strip scheme:// if present
                schemeIdx = Instr(1, base, "://")
                if schemeIdx > 0 then base = Mid(base, schemeIdx + 3)
                ' Strip any /api/v1/... suffix to get the origin
                slashIdx = Instr(1, base, "/")
                if slashIdx > 0 then base = Left(base, slashIdx - 1)
                ' Strip trailing / if present
                if Right(base, 1) = "/" then base = Left(base, Len(base) - 1)
                if base <> "" then serverUrl = base
            end if

            ' Derive roomName from group_name
            roomName = ""
            if g.DoesExist("group_name") and type(g.group_name) = "roString" and g.group_name <> "" then
                roomName = g.group_name
            end if

            m._session = {
                roomId: roomId
                sessionId: ""  ' Set to our own memberId from WS group_state event
                serverUrl: serverUrl
                roomName: roomName
                isHost: false
                members: members
                currentState: currentState
            }

            return m._session
        end function

        ' POST /syncplay/groups/{id}/leave -> {message}
        ' Leaves the current group and clears session state.
        leaveGroup: function() as Object
            if m.api = invalid or m._session = invalid then return invalid

            roomId = m._session.roomId
            result = m.api.leaveSyncPlayGroup(roomId)

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

        ' True if currently in a SyncPlay group.
        isInGroup: function() as Boolean
            return m._session <> invalid
        end function

        ' True if this device is the host of the current room.
        isHost: function() as Boolean
            if m._session = invalid then return false
            return m._session.isHost
        end function

        ' Get the group ID of the current session.
        getGroupId: function() as String
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

        ' Get the group name.
        getGroupName: function() as String
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