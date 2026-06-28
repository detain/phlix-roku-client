' source/lib/SessionManager.brs

' ===========================================
' Session Manager for Roku
' Manages active playback sessions
' ===========================================

function SessionManager(api as Object) as Object
    obj = {
        api: api
        activeSession: invalid
        sessions: []

        ' Create a new session
        createSession: function() as Object
            if m.api = invalid or m.api.user = invalid then
                return invalid
            end if

            session = m.api.createSession()
            if session <> invalid then
                m.activeSession = session
                m.sessions.push(session)
            end if

            return session
        end function

        ' Get all sessions
        getSessions: function() as Object
            if m.api <> invalid then
                m.sessions = m.api.getSessions()
            end if
            return m.sessions
        end function

        ' End current session
        endSession: function()
            if m.activeSession <> invalid and m.api <> invalid then
                m.api.stopPlayback()
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