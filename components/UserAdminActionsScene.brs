'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/UserAdminActionsScene.brs

' copyright 2026 Joe Huss
'

'
' Per-user admin actions: Approve / Disable / Make-or-Remove Admin / Reset
' Password / Refresh buttons plus a detail line summarizing the user's state.
' Mirrors LibraryAdminActionsScene's Button + buttonSelected idiom and the
' resident-memory serialization rule: a SINGLE ApiTask, with m.pendingOp
' guarding so a button press while a request is outstanding is ignored (never
' two control="run").
'
' UserAdminScene creates + appends this scene and calls LoadUser(id,name) across
' the component boundary, so LoadUser is declared in the XML <interface>. State
' refresh is MANUAL (the Refresh button); after an approve/disable/set-admin
' action the OnApiResponse branch chains a RefreshUser() so the new state shows.
' reset-password does NOT chain (it keeps the one-time password visible). No
' auto-poll (would need a Timer node) - future work.
'
' LANDMINES: is_admin is a TINYINT (0/1) - read it ONLY via IsAdminUser (a
' numeric <> "" compare would CRASH). Error responses carry an {error} body but
' result.ok stays TRUE, so MessageOf() reads message-or-error explicitly.

sub Init()
    m.top.SetFocus(true)

    ' Action buttons.
    m.approveButton = m.top.FindNode("approveButton")
    if m.approveButton <> invalid then
        m.approveButton.ObserveField("buttonSelected", "OnApprove")
    end if
    m.disableButton = m.top.FindNode("disableButton")
    if m.disableButton <> invalid then
        m.disableButton.ObserveField("buttonSelected", "OnDisable")
    end if
    m.adminButton = m.top.FindNode("adminButton")
    if m.adminButton <> invalid then
        m.adminButton.ObserveField("buttonSelected", "OnToggleAdmin")
    end if
    m.resetPasswordButton = m.top.FindNode("resetPasswordButton")
    if m.resetPasswordButton <> invalid then
        m.resetPasswordButton.ObserveField("buttonSelected", "OnResetPassword")
    end if
    m.profilesButton = m.top.FindNode("profilesButton")
    if m.profilesButton <> invalid then
        m.profilesButton.ObserveField("buttonSelected", "OnProfiles")
    end if
    m.refreshButton = m.top.FindNode("refreshButton")
    if m.refreshButton <> invalid then
        m.refreshButton.ObserveField("buttonSelected", "OnRefresh")
    end if

    m.titleLabel = m.top.FindNode("titleLabel")
    m.detailLabel = m.top.FindNode("detailLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread). Every op is serialized through this one task.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' State. m.pendingOp tracks the one outstanding op (invalid = idle) so a
    ' button press while a request is in flight is ignored. m.currentIsAdmin
    ' drives the admin-toggle button title + the set-admin payload.
    m.userId = ""
    m.userName = ""
    m.currentIsAdmin = false
    m.pendingOp = invalid

    ' Focus the first action button.
    if m.approveButton <> invalid then m.approveButton.SetFocus(true)
end sub

' Interface fn: called by UserAdminScene with the selected user's id+name.
sub LoadUser(userId as String, userName as String)
    m.userId = userId

    name = userName
    if name = invalid then name = ""
    m.userName = name
    if m.titleLabel <> invalid then m.titleLabel.text = name

    if m.userId = "" then return

    ' Fire the initial state read.
    RefreshUser()
end sub

' Read the current user (serialized, guarded). Skipped while another op is in
' flight so two control="run" are never outstanding on the single task.
sub RefreshUser()
    if m.pendingOp <> invalid then return
    if m.userId = "" then return

    m.pendingOp = "getAdminUser"
    SetStatus("Loading…")
    m.apiTask.request = { op: "getAdminUser", userId: m.userId }
    m.apiTask.control = "run"
end sub

sub OnApprove(event as Object)
    QueueAction("approveUser")
end sub

sub OnDisable(event as Object)
    QueueAction("disableUser")
end sub

' Toggle admin: send the OPPOSITE of the current flag. Serialized + guarded.
sub OnToggleAdmin(event as Object)
    if m.pendingOp <> invalid then return
    if m.userId = "" then return

    m.pendingOp = "setUserAdmin"
    SetStatus("Working…")
    m.apiTask.request = { op: "setUserAdmin", userId: m.userId, isAdmin: (not m.currentIsAdmin) }
    m.apiTask.control = "run"
end sub

sub OnResetPassword(event as Object)
    QueueAction("resetUserPassword")
end sub

sub OnRefresh(event as Object)
    RefreshUser()
end sub

' Open this user's profiles list. Opening a child scene is NOT an API op on this
' scene's task, so it is NOT guarded by m.pendingOp. ProfilesScene is
' self-created + focused and reads the user via the LoadProfiles interface fn.
sub OnProfiles(event as Object)
    if m.userId = "" then return

    scene = CreateObject("roSGNode", "ProfilesScene")
    m.top.Append(scene)
    scene.LoadProfiles(m.userId, m.userName)
end sub

' Enqueue a no-arg action (approve / disable / reset-password). A press while an
' op is in flight is ignored (one op at a time - never two control="run").
sub QueueAction(op as String)
    if m.pendingOp <> invalid then return
    if m.userId = "" then return

    m.pendingOp = op
    SetStatus("Working…")
    m.apiTask.request = { op: op, userId: m.userId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    ' The single outstanding op completed - clear the guard FIRST so a chained
    ' RefreshUser() is a fresh serialized request.
    m.pendingOp = invalid

    if resp.op = "getAdminUser" then
        user = invalid
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("user") then
            user = resp.data.user
        end if

        ' is_admin is a TINYINT -> read ONLY via IsAdminUser (no numeric compare).
        m.currentIsAdmin = IsAdminUser(user)

        if m.adminButton <> invalid then
            if m.currentIsAdmin then
                m.adminButton.title = "Remove Admin"
            else
                m.adminButton.title = "Make Admin"
            end if
        end if

        if m.detailLabel <> invalid then
            if user = invalid then
                m.detailLabel.text = "User not found"
            else
                m.detailLabel.text = UserDetailSummary(user)
            end if
        end if

        SetStatus("")
    else if resp.op = "approveUser" or resp.op = "disableUser" or resp.op = "setUserAdmin" then
        SetStatus(MessageOf(resp))
        ' State changed -> re-render (m.pendingOp is already cleared above, so
        ' this is a fresh serialized call).
        RefreshUser()
    else if resp.op = "resetUserPassword" then
        pw = ""
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("new_password") and resp.data.new_password <> invalid then
            pw = resp.data.new_password
        end if

        ' Show the one-time password and keep it visible (do NOT chain
        ' RefreshUser - the rest of the user state is unchanged).
        if pw <> "" then
            SetStatus("New password: " + pw)
        else
            SetStatus(MessageOf(resp))
        end if
    end if
end sub

' Read the message-or-error key from an action response (LANDMINE: an {error}
' body still arrives with result.ok = TRUE). Prefer message (success), else
' error (failure), else resp.error (transport/API error), else a generic
' depending on resp.ok.
function MessageOf(resp as Object) as String
    if resp <> invalid and resp.data <> invalid then
        if resp.data.DoesExist("message") and resp.data.message <> invalid and resp.data.message <> "" then
            return resp.data.message
        end if
        if resp.data.DoesExist("error") and resp.data.error <> invalid and resp.data.error <> "" then
            return resp.data.error
        end if
    end if

    if resp <> invalid and resp.ok then return "Done"
    if resp <> invalid and resp.error <> invalid and resp.error <> "" then return resp.error
    return "Request failed"
end function

' Build a multi-line summary of a user row. String fields guard DoesExist +
' invalid + ""; the admin line comes from IsAdminUser (NOT a numeric compare).
function UserDetailSummary(user as Object) as String
    if user = invalid then return ""

    lines = []

    if user.DoesExist("username") and user.username <> invalid and user.username <> "" then
        lines.Push("Username: " + user.username)
    end if
    if user.DoesExist("display_name") and user.display_name <> invalid and user.display_name <> "" then
        lines.Push("Name: " + user.display_name)
    end if
    if user.DoesExist("email") and user.email <> invalid and user.email <> "" then
        lines.Push("Email: " + user.email)
    end if
    if user.DoesExist("status") and user.status <> invalid and user.status <> "" then
        lines.Push("Status: " + user.status)
    end if

    if IsAdminUser(user) then
        lines.Push("Admin: yes")
    else
        lines.Push("Admin: no")
    end if

    if user.DoesExist("last_login") and user.last_login <> invalid and user.last_login <> "" then
        lines.Push("Last login: " + user.last_login)
    end if

    summary = ""
    for i = 0 to lines.Count() - 1
        if i > 0 then summary = summary + Chr(10)
        summary = summary + lines[i]
    end for

    return summary
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.approveButton <> invalid then m.approveButton.UnObserveField("buttonSelected")
    if m.disableButton <> invalid then m.disableButton.UnObserveField("buttonSelected")
    if m.adminButton <> invalid then m.adminButton.UnObserveField("buttonSelected")
    if m.resetPasswordButton <> invalid then m.resetPasswordButton.UnObserveField("buttonSelected")
    if m.profilesButton <> invalid then m.profilesButton.UnObserveField("buttonSelected")
    if m.refreshButton <> invalid then m.refreshButton.UnObserveField("buttonSelected")
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end function