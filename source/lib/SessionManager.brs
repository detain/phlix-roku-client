' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' source/lib/SessionManager.brs

' copyright 2026 Joe Huss
'


' ===========================================
' Session Manager for Roku
' Manages active playback sessions
' ===========================================

function SessionManager(api as Object) as Object
    obj = {
        api: api
        activeSession: invalid
        sessions: []

        ' Create a new session.
        ' ApiClient.createSession persists the returned session_id internally and
        ' returns the {session_id} envelope.
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

        ' Get tracked sessions.
        ' NOTE (F0b): the canonical /api/v1 contract has no session-list endpoint;
        ' sessions are created per-device and ended via DELETE. Returns the
        ' locally tracked list only.
        getSessions: function() as Object
            return m.sessions
        end function

        ' End current session via DELETE /sessions/{id} (routed through logout's
        ' session teardown in ApiClient). On Roku the transport/stop is
        ' client-side; the server only needs the session removed.
        endSession: function() as Void
            if m.activeSession <> invalid and m.api <> invalid then
                m.api.endSession()
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