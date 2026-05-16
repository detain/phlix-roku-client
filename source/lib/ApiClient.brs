' source/lib/ApiClient.brs
' @fileoverview ApiClient - Main HTTP client for Phlex Media Server API communication
' @author Phlex Team
' @version 1.0.0
' @requires Storage module for persistent storage
'
' @description
' This module provides the ApiClient factory function which creates an object
' for communicating with the Phlex Media Server REST API. It handles:
' - Authentication with device registration
' - Session management
' - Library browsing and item retrieval
' - Video playback control
' - Progress synchronization
'
' @example
' ```brightscript
' api = ApiClient("http://192.168.1.100:8096")
' user = api.login("username", "password")
' libraries = api.getLibraries()
' ```
'
' @module ApiClient
' @requires Storage

' ===========================================
' Phlex API Client for Roku
' Handles all communication with Phlex Media Server
' ===========================================

function ApiClient(baseUrl as String) as Object
    obj = {
        baseUrl: baseUrl
        token: ""
        sessionId: ""
        deviceId: ""
        deviceName: "Roku"
        deviceType: "roku"
        user: invalid

        ' Device profile for playback decisions
        deviceProfile: {
            Name: "Roku"
            MaxStreamingBitrate: 30000000
            MaxStaticBitrate: 30000000
            SupportedMediaTypes: ["Video", "Audio"]
            DirectPlayProfiles: [{
                Container: "mp4,m4v,mkv"
                Type: "Video"
                VideoCodec: "h264,hevc"
                AudioCodec: "aac,ac3,eac3,mp3,pcm"
            }]
            TranscodingProfiles: [{
                Container: "ts"
                Type: "Video"
                VideoCodec: "h264"
                AudioCodec: "aac,ac3"
            }]
        }

        ' Set authentication token
        setToken: function(token as String)
            m.token = token
            if token <> "" then
                Storage.set("auth_token", token)
            else
                Storage.delete("auth_token")
            end if
        end function

        ' Set session ID
        setSession: function(sessionId as String)
            m.sessionId = sessionId
            if sessionId <> "" then
                Storage.set("session_id", sessionId)
            else
                Storage.delete("session_id")
            end if
        end function

        ' Restore session from storage
        restoreSession: function() as Boolean
            token = Storage.get("auth_token")
            sessionId = Storage.get("session_id")

            if token <> "" then
                m.token = token
                if sessionId <> "" then m.sessionId = sessionId

                ' Validate token with server
                user = m.request("GET", "/Users/Me", {})
                if user <> invalid then
                    m.user = user
                    return true
                end if
            end if

            m.setToken("")
            m.setSession("")
            return false
        end function

        ' Make HTTP request
        request: function(method as String, path as String, body as Object) as Object
            url = m.baseUrl + "/api/v1" + path

            http = CreateObject("roUrlTransfer")
            http.SetUrl(url)
            http.SetTimeout(30000)
            http.EnableEncodings(true)

            ' Set headers
            http.AddHeader("Content-Type", "application/json")
            http.AddHeader("X-Phlex-Device-ID", m.deviceId)
            http.AddHeader("X-Phlex-Device-Name", m.deviceName)
            http.AddHeader("X-Phlex-Device-Type", m.deviceType)

            if m.token <> "" then
                http.AddHeader("Authorization", "Bearer " + m.token)
            end if

            if m.sessionId <> "" then
                http.AddHeader("X-Phlex-Session-ID", m.sessionId)
            end if

            ' Prepare body
            response = invalid
            if body <> invalid and (method = "POST" or method = "PUT" or method = "PATCH") then
                jsonBody = FormatJSON(body)
                http.SetRequest("POST")
                response = http.PostFromString(jsonBody)
            else
                response = http.GetToString()
            end if

            if response <> "" then
                return ParseJSON(response)
            end if

            return invalid
        end function

        ' Authentication methods
        login: function(username as String, password as String) as Object
            deviceInfo = {
                device_id: m.deviceId
                device_name: m.deviceName
                device_type: m.deviceType
            }

            result = m.request("POST", "/Auth/Login", {
                username: username
                password: password
                device_id: deviceInfo.device_id
                device_name: deviceInfo.device_name
                device_type: deviceInfo.device_type
            })

            if result <> invalid then
                m.setToken(result.token)
                m.setSession(result.session_id)
                m.user = result.user
            end if

            return result
        end function

        logout: function()
            if m.sessionId <> "" then
                m.request("DELETE", "/Sessions/" + m.sessionId, {})
            end if
            m.setToken("")
            m.setSession("")
            m.user = invalid
        end function

        ' Session management
        createSession: function() as Object
            if m.user = invalid then
                print "Not logged in"
                return invalid
            end if

            deviceInfo = {
                device_id: m.deviceId
                device_name: m.deviceName
                device_type: m.deviceType
                capabilities: m.deviceProfile
            }

            result = m.request("POST", "/Sessions", deviceInfo)
            if result <> invalid then
                m.setSession(result.id)
            end if

            return result
        end function

        getSessions: function() as Object
            return m.request("GET", "/Sessions", {})
        end function

        ' Library browsing
        getLibraries: function() as Object
            return m.request("GET", "/Library/VirtualFolders", {})
        end function

        getLibraryItems: function(libraryId as String, options = {} as Object) as Object
            params = []
            params.push("parentId=" + libraryId)
            params.push("includeItemTypes=" + chr(37) + "Movie,Series")
            params.push("limit=" + str(50).trim())
            params.push("startIndex=" + str(0).trim())
            params.push("sortBy=SortName")
            params.push("sortOrder=Ascending")

            query = "?" + Join(params, "&")
            return m.request("GET", "/Items" + query, {})
        end function

        getItem: function(itemId as String) as Object
            return m.request("GET", "/Items/" + itemId, {})
        end function

        getItemPlaybackInfo: function(itemId as String) as Object
            query = "?deviceProfile=roku&maxStreamingBitrate=" + str(m.deviceProfile.MaxStreamingBitrate).trim()
            return m.request("GET", "/Items/" + itemId + "/PlaybackInfo" + query, {})
        end function

        ' Playback control
        playItem: function(itemId as String, options = {} as Object) as Object
            startPosition = 0
            if options.DoesExist("startPosition") then startPosition = options.startPosition

            return m.request("POST", "/Sessions/Play", {
                item_id: itemId
                start_position_ticks: startPosition
                device_profile: m.deviceType
            })
        end function

        stopPlayback: function() as Object
            return m.request("POST", "/Playstate", {
                session_id: m.sessionId
                command: "stop"
            })
        end function

        pausePlayback: function() as Object
            return m.request("POST", "/Playstate", {
                session_id: m.sessionId
                command: "pause"
            })
        end function

        resumePlayback: function() as Object
            return m.request("POST", "/Playstate", {
                session_id: m.sessionId
                command: "play"
            })
        end function

        seekPlayback: function(positionTicks as Integer) as Object
            return m.request("POST", "/Playstate", {
                session_id: m.sessionId
                command: "seek"
                data: { position_ticks: positionTicks }
            })
        end function

        reportProgress: function(positionTicks as Integer, isPaused as Boolean) as Object
            return m.request("POST", "/Playstate/Progress", {
                session_id: m.sessionId
                position_ticks: positionTicks
                is_paused: isPaused
            })
        end function

        ' User data
        markWatched: function(itemId as String) as Object
            return m.updateUserData(itemId, { is_watched: true })
        end function

        markUnwatched: function(itemId as String) as Object
            return m.updateUserData(itemId, { is_watched: false })
        end function

        updateUserData: function(itemId as String, userData as Object) as Object
            return m.request("POST", "/Items/" + itemId + "/UserData", userData)
        end function
    }

    ' Generate device ID if not exists
    obj.deviceId = Storage.get("device_id")
    if obj.deviceId = "" or obj.deviceId = invalid then
        obj.deviceId = "roku-" + str(Rnd(999999999)).trim() + "-" + str(Rnd(999999999)).trim()
        Storage.set("device_id", obj.deviceId)
    end if

    return obj
end function