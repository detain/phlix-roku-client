' source/hub/HubConfig.brs

' ===========================================
' Hub Mode Configuration
' Manages hub URL, active server, and connection mode
' ===========================================

function HubConfig() as Object
    obj = {
        hubUrl: ""
        serverUrl: ""
        activeServer: invalid
        connectionMode: "direct"  ' "direct" or "relay"

        ' Initialize from storage
        init: function()
            m.hubUrl = Storage.get("hub_url")
            m.serverUrl = Storage.get("server_url")
            m.connectionMode = Storage.get("connection_mode")
            if m.connectionMode = "" or m.connectionMode = invalid then
                m.connectionMode = "direct"
            end if

            ' Load active server if exists
            activeServerJson = Storage.get("active_server")
            if activeServerJson <> "" and activeServerJson <> invalid then
                m.activeServer = ParseJSON(activeServerJson)
            end if
        end function

        ' Save configuration to storage
        save: function()
            Storage.set("hub_url", m.hubUrl)
            Storage.set("connection_mode", m.connectionMode)

            if m.activeServer <> invalid then
                Storage.set("active_server", FormatJSON(m.activeServer))
            else
                Storage.delete("active_server")
            end if
        end function

        ' Set hub URL
        ' @param url String - Hub server URL
        setHubUrl: function(url as String)
            m.hubUrl = url
            Storage.set("hub_url", url)
        end function

        ' Set connection mode
        ' @param mode String - "direct" or "relay"
        setConnectionMode: function(mode as String)
            m.connectionMode = mode
            Storage.set("connection_mode", mode)
        end function

        ' Set active server
        ' @param server Object - Server object with serverId, hostname, name, etc.
        setActiveServer: function(server as Object)
            m.activeServer = server
            if server <> invalid then
                Storage.set("active_server", FormatJSON(server))
            else
                Storage.delete("active_server")
            end if
        end function

        ' Get effective URL for API requests
        ' Routes through hub relay if in relay mode with active server
        ' @param path String - API path (e.g., "/api/v1/items")
        ' @return String - Effective URL
        getEffectiveUrl: function(path as String) as String
            ' If no active server, use direct server URL
            if m.activeServer = invalid then
                return m.serverUrl + path
            end if

            ' In relay mode with active server that has relay hostname
            if m.connectionMode = "relay" and m.activeServer.DoesExist("relayHostname") then
                relayPath = "/api/v1/relay/" + m.activeServer.serverId + path
                return m.hubUrl + relayPath
            end if

            ' Direct mode or server without relay hostname
            return m.activeServer.hostname + path
        end function

        ' Get authorization header value for hub requests
        ' @return String - "Bearer <token>" or empty string
        getAuthHeader: function() as String
            sessionJson = Storage.get("hub_session")
            if sessionJson = "" or sessionJson = invalid then
                return ""
            end if

            session = ParseJSON(sessionJson)
            if session = invalid or session.accessToken = "" then
                return ""
            end if

            return "Bearer " + session.accessToken
        end function

        ' Get headers for relay requests
        ' @return Object - Headers object with Authorization and X-Server-Id
        getRelayHeaders: function() as Object
            headers = {
                "Authorization": m.getAuthHeader()
            }

            if m.activeServer <> invalid and m.activeServer.serverId <> invalid then
                headers["X-Server-Id"] = m.activeServer.serverId
            end if

            return headers
        end function

        ' Check if hub mode is configured
        ' @return Boolean
        isConfigured: function() as Boolean
            return m.hubUrl <> "" and m.hubUrl <> invalid
        end function

        ' Check if relay mode is active
        ' @return Boolean
        isRelayMode: function() as Boolean
            return m.connectionMode = "relay"
        end function

        ' Clear all hub configuration
        clear: function()
            m.hubUrl = ""
            m.serverUrl = ""
            m.activeServer = invalid
            m.connectionMode = "direct"

            Storage.delete("hub_url")
            Storage.delete("connection_mode")
            Storage.delete("active_server")
        end function
    }

    ' Auto-initialize on creation
    obj.init()

    return obj
end function

' Factory function alias for convenience
function HubConfigFactory() as Object
    return HubConfig()
end function