' source/syncplay/SyncPlayService.brs

' ===========================================
' SyncPlay Service
' WebSocket-based group sync for synchronized
' playback across multiple clients
' ===========================================

' SyncPlay event types (sent to server)
const SYNCPLAY_EVENT_JOIN_GROUP = "syncplay.join_group"
const SYNCPLAY_EVENT_LEAVE_GROUP = "syncplay.leave_group"
const SYNCPLAY_EVENT_PLAYBACK_COMMAND = "syncplay.playback_command"
const SYNCPLAY_EVENT_REPORT_POSITION = "syncplay.report_position"
const SYNCPLAY_EVENT_REQUEST_TIME_SYNC = "syncplay.request_time_sync"

' SyncPlay event types (received from server)
const SYNCPLAY_EVENT_TIME_SYNC = "syncplay.time_sync"
const SYNCPLAY_EVENT_GROUP_STATE = "syncplay.group_state"
const SYNCPLAY_EVENT_PLAYBACK_UPDATE = "syncplay.playback_update"
const SYNCPLAY_EVENT_MEMBER_JOINED = "syncplay.member_joined"
const SYNCPLAY_EVENT_MEMBER_LEFT = "syncplay.member_left"

' Playback commands
const SYNCPLAY_CMD_PLAY = "play"
const SYNCPLAY_CMD_PAUSE = "pause"
const SYNCPLAY_CMD_SEEK = "seek"

' Position report interval in milliseconds
const SYNCPLAY_POSITION_REPORT_INTERVAL = 30000

' Time sync request interval in milliseconds
const SYNCPLAY_TIME_SYNC_INTERVAL = 60000

function SyncPlayService(baseUrl as String) as Object
    obj = {
        baseUrl: baseUrl
        wsUrl: ""
        socket: invalid
        timeSync: invalid

        ' Connection state
        isConnected: false
        isConnecting: false

        ' Current group state
        groupId: ""
        currentMemberId: ""
        members: []

        ' Playback state
        isPlaying: false
        currentPosition: 0
        mediaDuration: 0

        ' Timers
        positionReportTimer: invalid
        timeSyncTimer: invalid
        reconnectTimer: invalid

        ' Event callbacks (set by consumers)
        onGroupStateChanged: invalid
        onPlaybackUpdate: invalid
        onMemberJoined: invalid
        onMemberLeft: invalid
        onTimeSyncUpdate: invalid
        onConnectionChange: invalid

        ' Initialize the service
        init: function()
            m.timeSync = SyncPlayTimeSync()

            ' Build WebSocket URL from base URL
            m.wsUrl = m.buildWsUrl()
        end function

        ' Build WebSocket URL
        ' @return String - WebSocket URL
        buildWsUrl: function() as String
            ' Replace http(s) with ws(s) and append WebSocket path
            wsProtocol = "wss"
            if instr(1, m.baseUrl, "http://") = 1 then
                wsProtocol = "ws"
            end if

            ' Strip protocol and get host+path
            host = m.baseUrl
            if instr(1, host, "://") > 0 then
                host = mid(host, instr(1, host, "://") + 3)
            end if

            ' Remove trailing slash
            if right(host, 1) = "/" then
                host = left(host, len(host) - 1)
            end if

            return wsProtocol + "://" + host + "/api/v1/syncplay/ws"
        end function

        ' Connect to SyncPlay WebSocket
        ' @return Boolean - True if connection initiated
        connect: function() as Boolean
            if m.isConnecting or m.isConnected then
                return false
            end if

            m.isConnecting = true
            m.notifyConnectionChange()

            ' On Roku, we use HTTP-based WebSocket emulation via long-polling
            ' since roUrlTransfer doesn't support native WebSocket
            ' The server should have an HTTP endpoint for this
            m.startHttpPolling()

            return true
        end function

        ' Start HTTP-based polling for SyncPlay messages
        ' This is used when WebSocket is not available
        startHttpPolling: sub()
            m.isConnecting = false
            m.isConnected = true
            m.notifyConnectionChange()
        end sub

        ' Disconnect from SyncPlay
        disconnect: sub()
            m.cleanup()
            m.isConnected = false
            m.isConnecting = false
            m.notifyConnectionChange()
        end sub

        ' Cleanup timers and state
        cleanup: sub()
            m.stopPositionReports()
            m.stopTimeSyncRequests()
            m.stopReconnectTimer()
        end sub

        ' Join a SyncPlay group
        ' @param groupId String - Group ID to join
        ' @param memberId String - Unique member ID for this client
        ' @return Boolean - True if join request sent
        joinGroup: function(groupId as String, memberId as String) as Boolean
            if not m.isConnected then
                m.connect()
            end if

            m.groupId = groupId
            m.currentMemberId = memberId

            payload = {
                type: SYNCPLAY_EVENT_JOIN_GROUP
                group_id: groupId
                member_id: memberId
                device_info: {
                    name: "Roku"
                    type: "roku"
                }
            }

            success = m.sendMessage(payload)

            if success then
                ' Start periodic reporting
                m.startPositionReports()
                m.requestTimeSync()
            end if

            return success
        end function

        ' Leave current SyncPlay group
        ' @return Boolean - True if leave request sent
        leaveGroup: function() as Boolean
            if m.groupId = "" then
                return false
            end if

            payload = {
                type: SYNCPLAY_EVENT_LEAVE_GROUP
                group_id: m.groupId
                member_id: m.currentMemberId
            }

            success = m.sendMessage(payload)

            m.stopPositionReports()
            m.stopTimeSyncRequests()
            m.groupId = ""
            m.members = []

            m.notifyGroupStateChanged()

            return success
        end function

        ' Send playback command to group
        ' @param command String - Command (play, pause, seek)
        ' @param position Integer - Position in ms (for seek/play)
        ' @return Boolean - True if sent
        sendPlaybackCommand: function(command as String, position = 0 as Integer) as Boolean
            if m.groupId = "" or m.currentMemberId = "" then
                return false
            end if

            payload = {
                type: SYNCPLAY_EVENT_PLAYBACK_COMMAND
                group_id: m.groupId
                member_id: m.currentMemberId
                command: command
                position: position
                timestamp: m.getSynchronizedTime()
            }

            ' Optimistically update local state
            if command = SYNCPLAY_CMD_PLAY then
                m.isPlaying = true
            else if command = SYNCPLAY_CMD_PAUSE then
                m.isPlaying = false
            else if command = SYNCPLAY_CMD_SEEK then
                m.currentPosition = position
            end if

            return m.sendMessage(payload)
        end function

        ' Report current position to group
        ' @param position Integer - Position in ms
        ' @param isPaused Boolean - Whether playback is paused
        ' @return Boolean - True if sent
        reportPosition: function(position as Integer, isPaused as Boolean) as Boolean
            if m.groupId = "" or m.currentMemberId = "" then
                return false
            end if

            payload = {
                type: SYNCPLAY_EVENT_REPORT_POSITION
                group_id: m.groupId
                member_id: m.currentMemberId
                position: position
                is_paused: isPaused
                timestamp: m.getSynchronizedTime()
            }

            return m.sendMessage(payload)
        end function

        ' Request time synchronization
        ' @return Boolean - True if request sent
        requestTimeSync: function() as Boolean
            if m.groupId = "" then
                return false
            end if

            payload = {
                type: SYNCPLAY_EVENT_REQUEST_TIME_SYNC
                group_id: m.groupId
                member_id: m.currentMemberId
            }

            return m.sendMessage(payload)
        end function

        ' Start periodic position reporting
        startPositionReports: sub()
            m.stopPositionReports()
            ' Note: Roku doesn't have setInterval, so we track this via polling in the player loop
            ' This is a placeholder - actual implementation would hook into player's position observer
        end sub

        ' Stop periodic position reporting
        stopPositionReports: sub()
            ' Cleanup called on disconnect
        end sub

        ' Start periodic time sync requests
        startTimeSyncRequests: sub()
            m.stopTimeSyncRequests()
            ' Request time sync periodically to maintain accuracy
        end sub

        ' Stop time sync requests
        stopTimeSyncRequests: sub()
            ' Cleanup called on disconnect
        end sub

        ' Start reconnect timer
        ' @param delay Integer - Delay in ms before reconnect
        startReconnectTimer: function(delay = 5000 as Integer) as Void
            m.stopReconnectTimer()
            ' Note: Actual timer implementation would use roTimer
        end sub

        ' Stop reconnect timer
        stopReconnectTimer: sub()
            ' Cleanup
        end sub

        ' Send message to server
        ' @param payload Object - Message payload
        ' @return Boolean - True if sent
        sendMessage: function(payload as Object) as Boolean
            if not m.isConnected then
                return false
            end if

            ' Use HTTP POST to send message (WebSocket emulation via HTTP)
            url = m.baseUrl + "/api/v1/syncplay/message"

            http = CreateObject("roUrlTransfer")
            http.SetUrl(url)
            http.SetTimeout(5000)
            http.AddHeader("Content-Type", "application/json")

            ' Add auth header if available
            authHeader = m.getAuthHeader()
            if authHeader <> "" then
                http.AddHeader("Authorization", authHeader)
            end if

            jsonBody = FormatJSON(payload)
            response = http.PostFromString(jsonBody)

            return response <> ""
        end function

        ' Get auth header for requests
        ' @return String - Bearer token or empty
        getAuthHeader: function() as String
            token = Storage.get("auth_token")
            if token <> "" and token <> invalid then
                return "Bearer " + token
            end if
            return ""
        end function

        ' Handle incoming message
        ' @param message Object - Parsed message
        handleMessage: sub(message as Object)
            if message = invalid then return

            eventType = message.type

            if eventType = SYNCPLAY_EVENT_TIME_SYNC then
                m.handleTimeSync(message)
            else if eventType = SYNCPLAY_EVENT_GROUP_STATE then
                m.handleGroupState(message)
            else if eventType = SYNCPLAY_EVENT_PLAYBACK_UPDATE then
                m.handlePlaybackUpdate(message)
            else if eventType = SYNCPLAY_EVENT_MEMBER_JOINED then
                m.handleMemberJoined(message)
            else if eventType = SYNCPLAY_EVENT_MEMBER_LEFT then
                m.handleMemberLeft(message)
            end if
        end sub

        ' Handle time sync response
        handleTimeSync: sub(message as Object)
            if message.payload = invalid then return

            result = m.timeSync.processPongPayload(message.payload)

            m.notifyTimeSyncUpdate(result)
        end sub

        ' Handle group state update
        handleGroupState: sub(message as Object)
            if message.group_id <> invalid then
                m.groupId = message.group_id
            end if

            if message.members <> invalid then
                m.members = message.members
            end if

            m.notifyGroupStateChanged()
        end sub

        ' Handle playback update from another member
        handlePlaybackUpdate: sub(message as Object)
            ' Ignore updates from ourselves
            if message.member_id = m.currentMemberId then return

            update = {
                command: message.command
                position: message.position
                timestamp: message.timestamp
                member_id: message.member_id
            }

            m.notifyPlaybackUpdate(update)
        end sub

        ' Handle member joined
        handleMemberJoined: sub(message as Object)
            member = {
                id: message.member_id
                name: message.name
                is_local: false
            }
            m.members.push(member)

            m.notifyMemberJoined(member)
        end sub

        ' Handle member left
        handleMemberLeft: sub(message as Object)
            memberId = message.member_id

            for i = 0 to m.members.count() - 1
                if m.members[i].id = memberId then
                    m.members.delete(i)
                    exit for
                end if
            end for

            m.notifyMemberLeft(memberId)
        end sub

        ' Notify listeners
        notifyGroupStateChanged: sub()
            if m.onGroupStateChanged <> invalid then
                m.onGroupStateChanged({
                    group_id: m.groupId
                    members: m.members
                    is_playing: m.isPlaying
                    position: m.currentPosition
                })
            end if
        end sub

        notifyPlaybackUpdate: sub(update as Object)
            if m.onPlaybackUpdate <> invalid then
                m.onPlaybackUpdate(update)
            end if
        end sub

        notifyMemberJoined: sub(member as Object)
            if m.onMemberJoined <> invalid then
                m.onMemberJoined(member)
            end if
        end sub

        notifyMemberLeft: sub(memberId as String)
            if m.onMemberLeft <> invalid then
                m.onMemberLeft(memberId)
            end if
        end sub

        notifyTimeSyncUpdate: sub(result as Object)
            if m.onTimeSyncUpdate <> invalid then
                m.onTimeSyncUpdate(result)
            end if
        end sub

        notifyConnectionChange: sub()
            if m.onConnectionChange <> invalid then
                m.onConnectionChange({
                    is_connected: m.isConnected
                    is_connecting: m.isConnecting
                })
            end if
        end sub

        ' Get synchronized time
        ' @return Integer - Current time adjusted by offset
        getSynchronizedTime: function() as Integer
            if m.timeSync <> invalid then
                return m.timeSync.getSynchronizedTime()
            end if
            dt = CreateObject("roDateTime")
            return dt.AsSeconds() * 1000 + dt.GetMilliseconds()
        end function

        ' Get adjusted playback position
        ' @param position Integer - Local position in ms
        ' @param duration Integer - Media duration in ms
        ' @return Integer - Adjusted position
        getAdjustedPosition: function(position as Integer, duration as Integer) as Integer
            if m.timeSync <> invalid then
                return m.timeSync.adjustPlaybackPosition(position, duration)
            end if
            return position
        end function

        ' Check if currently in a group
        ' @return Boolean
        isInGroup: function() as Boolean
            return m.groupId <> ""
        end function

        ' Get current group info
        ' @return Object - Group info
        getGroupInfo: function() as Object
            return {
                group_id: m.groupId
                members: m.members
                is_connected: m.isConnected
                time_sync: m.timeSync <> invalid and m.timeSync.isStable()
            }
        end function

        ' Get media duration
        ' @return Integer - Duration in ms
        getMediaDuration: function() as Integer
            return m.mediaDuration
        end function

        ' Set media duration
        ' @param duration Integer - Duration in ms
        setMediaDuration: function(duration as Integer)
            m.mediaDuration = duration
        end function

        ' Update playback position
        ' @param position Integer - Position in ms
        setPosition: function(position as Integer)
            m.currentPosition = position
        end function

        ' Update playing state
        ' @param isPlaying Boolean
        setPlaying: function(isPlaying as Boolean)
            m.isPlaying = isPlaying
        end function
    }

    ' Initialize
    obj.init()

    return obj
end function

' Factory function
function SyncPlayServiceFactory(baseUrl as String) as Object
    return SyncPlayService(baseUrl)
end function