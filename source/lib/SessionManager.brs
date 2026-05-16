' source/lib/SessionManager.brs

' ===========================================
' Session Manager for Roku
' Manages active playback sessions
' ===========================================

function SessionManager() as Object
    obj = {
        activeSession: invalid
        sessions: []

        ' Create a new session
        createSession: function() as Object
            if api = invalid or api.user = invalid then
                return invalid
            end if

            session = api.createSession()
            if session <> invalid then
                m.activeSession = session
                m.sessions.push(session)
            end if

            return session
        end function

        ' Get all sessions
        getSessions: function() as Object
            if api <> invalid then
                m.sessions = api.getSessions()
            end if
            return m.sessions
        end function

        ' End current session
        endSession: function()
            if m.activeSession <> invalid and api <> invalid then
                api.stopPlayback()
                m.activeSession = invalid
            end if
        end function

        ' Get active session
        getActiveSession: function() as Object
            return m.activeSession
        end function
    }

    return obj
end function