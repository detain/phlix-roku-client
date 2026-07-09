'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/AuthManager.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Authentication Manager for Roku
' Handles user authentication state and operations
' ===========================================

function AuthManager(api as Object) as Object
    obj = {
        api: api
        isAuthenticated: false
        currentUser: invalid

        ' Check if user is authenticated
        checkAuth: function() as Boolean
            if m.api <> invalid then
                m.isAuthenticated = m.api.restoreSession()
                if m.isAuthenticated then
                    m.currentUser = m.api.user
                end if
            end if
            return m.isAuthenticated
        end function

        ' Perform login
        login: function(username as String, password as String) as Object
            if m.api = invalid then
                return { success: false, error: "API not initialized" }
            end if

            result = m.api.login(username, password)
            if result <> invalid and result.access_token <> invalid then
                m.isAuthenticated = true
                m.currentUser = result.user
                return { success: true, user: result.user }
            end if

            return { success: false, error: "Login failed" }
        end function

        ' Perform logout
        logout: function()
            if m.api <> invalid then
                m.api.logout()
            end if
            m.isAuthenticated = false
            m.currentUser = invalid
        end function

        ' Get current user info
        getCurrentUser: function() as Object
            return m.currentUser
        end function
    }

    return obj
end function