' source/lib/AuthManager.brs

' ===========================================
' Authentication Manager for Roku
' Handles user authentication state and operations
' ===========================================

function AuthManager() as Object
    obj = {
        isAuthenticated: false
        currentUser: invalid

        ' Check if user is authenticated
        checkAuth: function() as Boolean
            if api <> invalid then
                m.isAuthenticated = api.restoreSession()
                if m.isAuthenticated then
                    m.currentUser = api.user
                end if
            end if
            return m.isAuthenticated
        end function

        ' Perform login
        login: function(username as String, password as String) as Object
            if api = invalid then
                return { success: false, error: "API not initialized" }
            end if

            result = api.login(username, password)
            if result <> invalid and result.token <> invalid then
                m.isAuthenticated = true
                m.currentUser = result.user
                return { success: true, user: result.user }
            end if

            return { success: false, error: "Login failed" }
        end function

        ' Perform logout
        logout: function()
            if api <> invalid then
                api.logout()
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