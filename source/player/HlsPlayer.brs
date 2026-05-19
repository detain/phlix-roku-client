' source/player/HlsPlayer.brs

' ===========================================
' Relay-Aware HLS Player
' Handles HLS playback with hub relay support
' ===========================================

function HlsPlayer() as Object
    obj = {
        videoPlayer: invalid
        contentNode: invalid
        hubConfig: invalid

        ' Initialize HLS player with video player node reference
        ' @param videoPlayer Object - The roSGNode video player
        init: function(videoPlayer as Object)
            m.videoPlayer = videoPlayer
            m.hubConfig = HubConfig()

            if m.videoPlayer <> invalid then
                m.videoPlayer.EnableCookies()
                m.videoPlayer.SetCertificatesFile("common:/certs/ca-bundle.crt")
            end if
        end function

        ' Play HLS stream with relay support
        ' @param streamUrl String - The HLS manifest URL
        ' @param headers Object - Optional additional headers
        playHls: function(streamUrl as String, headers = {} as Object)
            ' Check if we need to route through relay
            effectiveUrl = m.getEffectiveStreamUrl(streamUrl)

            ' Merge headers
            requestHeaders = m.getRequestHeaders(headers)

            ' Set up content node
            m.contentNode = CreateObject("roSGNode", "ContentNode")
            m.contentNode.url = effectiveUrl
            m.contentNode.streamformat = "hls"

            ' Add headers to content node if supported
            ' Note: roSGNode ContentNode headers support varies by Roku OS version
            if requestHeaders.Count() > 0 then
                ' Try to set headers - this may not work on all versions
                ' Fall back to direct URL if headers can't be set
                m.contentNode.AddHeader("Authorization", requestHeaders["Authorization"])
                if requestHeaders.DoesExist("X-Server-Id") then
                    m.contentNode.AddHeader("X-Server-Id", requestHeaders["X-Server-Id"])
                end if
            end if

            if m.videoPlayer <> invalid then
                m.videoPlayer.content = m.contentNode
                m.videoPlayer.control = "play"
            end if
        end function

        ' Get effective stream URL, routing through relay if needed
        ' @param streamUrl String - Original stream URL
        ' @return String - Effective URL to use
        getEffectiveStreamUrl: function(streamUrl as String) as String
            if not m.hubConfig.isConfigured() then
                return streamUrl
            end if

            ' If not in relay mode, use direct URL
            if not m.hubConfig.isRelayMode() then
                return streamUrl
            end if

            ' If no active server with relay hostname, use direct
            if m.hubConfig.activeServer = invalid then
                return streamUrl
            end if

            if not m.hubConfig.activeServer.DoesExist("relayHostname") then
                return streamUrl
            end if

            ' Build relay URL for HLS manifest
            ' Format: {hubUrl}/api/v1/relay/{serverId}/hls/{manifest_path}
            serverId = m.hubConfig.activeServer.serverId
            relayUrl = m.hubConfig.hubUrl + "/api/v1/relay/" + serverId + "/hls"

            return relayUrl + "?url=" +.UrlEncode(streamUrl)
        end function

        ' Get request headers for playback
        ' @param additionalHeaders Object - Additional headers to merge
        ' @return Object - Combined headers object
        getRequestHeaders: function(additionalHeaders = {} as Object) as Object
            headers = {}

            ' Get hub auth headers if configured
            if m.hubConfig.isConfigured() then
                relayHeaders = m.hubConfig.getRelayHeaders()
                for each key in relayHeaders
                    headers[key] = relayHeaders[key]
                end for
            end if

            ' Merge additional headers
            for each key in additionalHeaders
                headers[key] = additionalHeaders[key]
            end for

            return headers
        end function

        ' Stop playback
        stop: function()
            if m.videoPlayer <> invalid then
                m.videoPlayer.control = "stop"
            end if
        end function

        ' Pause playback
        pause: function()
            if m.videoPlayer <> invalid then
                m.videoPlayer.control = "pause"
            end if
        end function

        ' Resume playback
        resume: function()
            if m.videoPlayer <> invalid then
                m.videoPlayer.control = "resume"
            end if
        end function

        ' Seek to position
        ' @param position Float - Position in seconds
        seek: function(position as Float)
            if m.videoPlayer <> invalid then
                m.videoPlayer.seek = position
            end if
        end function

        ' Get current position
        ' @return Float - Current position in seconds
        getPosition: function() as Float
            if m.videoPlayer <> invalid then
                return m.videoPlayer.position
            end if
            return 0
        end function

        ' Get playback state
        ' @return String - Current state (playing, paused, stopped, etc.)
        getState: function() as String
            if m.videoPlayer <> invalid then
                return m.videoPlayer.state
            end if
            return "stopped"
        end function
    }

    return obj
end function

' URL encode helper
' @param str String - String to encode
' @return String - URL encoded string
function UrlEncode(str as String) as String
    result = ""
    for i = 1 to len(str)
        c = mid(str, i, 1)
        if c = " " then
            result = result + "%20"
        else if c = "&" then
            result = result + "%26"
        else if c = "=" then
            result = result + "%3D"
        else if c = "?" then
            result = result + "%3F"
        else if c = "/" then
            result = result + "%2F"
        else if c = ":" then
            result = result + "%3A"
        else if c = "#" then
            result = result + "%23"
        else if c = "[" then
            result = result + "%5B"
        else if c = "]" then
            result = result + "%5D"
        else
            result = result + c
        end if
    end for
    return result
end function

' Factory function alias
function HlsPlayerFactory() as Object
    return HlsPlayer()
end function