' source/hub/HubAuth.brs

' ===========================================
' Hub Authentication and Session Management
' Handles hub sign-in, server listing, and session persistence
' ===========================================

function HubAuth() as Object
    obj = {
        hubUrl: ""

        ' Sign in to hub with credentials
        ' @param hubUrl String - Base URL of the hub server
        ' @param username String - Hub username
        ' @param password String - Hub password
        ' @return Boolean - true on success, false on failure
        signIn: function(hubUrl as String, username as String, password as String) as Boolean
            m.hubUrl = hubUrl

            ' Build login request
            url = hubUrl + "/api/v1/auth/login"

            http = CreateObject("roUrlTransfer")
            http.SetUrl(url)
            http.SetTimeout(30000)
            http.EnableEncodings(true)
            http.AddHeader("Content-Type", "application/json")

            requestBody = {
                username: username
                password: password
            }

            jsonBody = FormatJSON(requestBody)
            response = http.PostFromString(jsonBody)

            if response = "" then
                print "HubAuth.signIn: empty response"
                return false
            end if

            result = ParseJSON(response)
            if result = invalid then
                print "HubAuth.signIn: failed to parse response"
                return false
            end if

            if result.status <> 200 and result.status <> invalid then
                print "HubAuth.signIn: HTTP "; result.status
                return false
            end if

            if result.body = invalid and result.access_token = invalid then
                print "HubAuth.signIn: no access token in response"
                return false
            end if

            ' Extract tokens - handle both {body: {access_token: ...}} and {access_token: ...} formats
            accessToken = ""
            refreshToken = ""
            expiresIn = 3600
            userId = ""

            if result.body <> invalid then
                accessToken = result.body.access_token
                refreshToken = result.body.refresh_token
                expiresIn = result.body.expires_in
                userId = result.body.user_id
            else
                accessToken = result.access_token
                refreshToken = result.refresh_token
                expiresIn = result.expires_in
                userId = result.user_id
            end if

            session = {
                accessToken: accessToken
                refreshToken: refreshToken
                expiresAt: expiresIn
                userId: userId
                hubUrl: hubUrl
            }

            m.setSession(session)
            return true
        end function

        ' Sign out from hub
        signOut: function()
            m.setSession(invalid)
        end function

        ' List claimed servers from hub
        ' @return Object - Array of servers or empty array on failure
        listServers: function() as Object
            session = m.getSession()
            if session = invalid then
                print "HubAuth.listServers: no session"
                return []
            end if

            if m.hubUrl = "" then
                m.hubUrl = session.hubUrl
            end if

            url = m.hubUrl + "/api/v1/me/servers"

            http = CreateObject("roUrlTransfer")
            http.SetUrl(url)
            http.SetTimeout(30000)
            http.EnableEncodings(true)
            http.AddHeader("Authorization", "Bearer " + session.accessToken)

            response = http.GetToString()

            if response = "" then
                print "HubAuth.listServers: empty response"
                return []
            end if

            result = ParseJSON(response)
            if result = invalid then
                print "HubAuth.listServers: failed to parse response"
                return []
            end if

            if result.status <> 200 and result.status <> invalid then
                print "HubAuth.listServers: HTTP "; result.status
                return []
            end if

            if result.body <> invalid then
                return result.body.servers
            end if

            return []
        end function

        ' Check if user is signed in to hub
        ' @return Boolean
        isSignedIn: function() as Boolean
            session = m.getSession()
            return session <> invalid and session.accessToken <> ""
        end function

        ' Get active session
        ' @return Object - Session object or invalid
        getSession: function() as Object
            sessionJson = Storage.get("hub_session")
            if sessionJson = "" or sessionJson = invalid then
                return invalid
            end if

            session = ParseJSON(sessionJson)
            if session = invalid then
                return invalid
            end if

            m.hubUrl = session.hubUrl
            return session
        end function

        ' Persist session to storage
        ' @param session Object - Session object to persist, or invalid to clear
        setSession: function(session as Object)
            if session = invalid then
                Storage.delete("hub_session")
                return
            end if

            sessionJson = FormatJSON(session)
            Storage.set("hub_session", sessionJson)
        end function
    }

    return obj
end function

' Factory function alias for convenience
function HubAuthFactory() as Object
    return HubAuth()
end function