' components/UserAdminScene.brs
'
' Users admin list: a one-shot LabelList of the server's users. Mirrors
' LibraryAdminScene's LabelList + ApiTask + OnApiResponse idiom - the load fires
' once on Init via the `getAdminUsers` op (no status = all users). Selecting a
' row opens that user's per-user actions (Approve / Disable / Make-or-Remove
' Admin / Reset Password / Refresh) in a UserAdminActionsScene. AdminScene
' self-creates + focuses this scene, so it has NO <interface>.
'
' NOTE: getAdminUsers() returns the WHOLE envelope (admin getters do not
' unwrap), so OnApiResponse reads resp.data.users and checks
' resp.data.DoesExist("users") AND type(resp.data.users) = "roArray" (different
' from LibraryAdminScene, whose getLibraries unwraps to the array directly).

sub Init()
    m.top.SetFocus(true)

    ' Text list of users.
    m.userList = m.top.FindNode("userList")
    if m.userList <> invalid then
        m.userList.ObserveField("itemSelected", "OnRowSelected")
        m.userList.ObserveField("itemFocused", "OnRowFocused")
        m.userList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.users = []

    SetStatus("Loading…")

    ' One-shot load on Init (no status = all users).
    m.apiTask.request = { op: "getAdminUsers" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getAdminUsers" then
        ' getAdminUsers() returns the WHOLE envelope {users:[...]}.
        m.users = []
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("users") and type(resp.data.users) = "roArray" then
            m.users = resp.data.users
        end if

        content = CreateObject("roSGNode", "ContentNode")
        for each user in m.users
            if user <> invalid then
                content.AddChild({ title: UserRowCaption(user) })
            end if
        end for

        if m.userList <> invalid then m.userList.content = content

        if m.users.Count() = 0 then
            SetStatus("No users")
        else
            SetStatus("")
        end if
    end if
end sub

' Caption for a user row: "<name>  (<status>, admin)" - status and admin tag are
' only appended when present. name = username (fallback display_name, fallback
' "(user)"). is_admin is a TINYINT -> read it ONLY via IsAdminUser (never a
' numeric <> "" compare). All string fields guard DoesExist + invalid + "".
function UserRowCaption(user as Object) as String
    if user = invalid then return ""

    name = ""
    if user.DoesExist("username") and user.username <> invalid and user.username <> "" then
        name = user.username
    else if user.DoesExist("display_name") and user.display_name <> invalid and user.display_name <> "" then
        name = user.display_name
    else
        name = "(user)"
    end if

    tags = []
    if user.DoesExist("status") and user.status <> invalid and user.status <> "" then
        tags.Push(user.status)
    end if
    if IsAdminUser(user) then tags.Push("admin")

    if tags.Count() = 0 then return name

    suffix = ""
    for i = 0 to tags.Count() - 1
        if i > 0 then suffix = suffix + ", "
        suffix = suffix + tags[i]
    end for

    return name + "  (" + suffix + ")"
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.users.Count() then return

    user = m.users[index]
    if user = invalid then return

    id = ""
    if user.DoesExist("id") and user.id <> invalid then id = user.id

    name = ""
    if user.DoesExist("username") and user.username <> invalid and user.username <> "" then
        name = user.username
    else if user.DoesExist("display_name") and user.display_name <> invalid and user.display_name <> "" then
        name = user.display_name
    end if

    if id <> "" then ShowActions(id, name)
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.users.Count() then return

    user = m.users[index]
    if user = invalid then return

    SetStatus(UserRowCaption(user))
end sub

' Open the per-user actions surface (Approve/Disable/Admin/Reset/Refresh). Coerce
' an invalid name to "" before crossing the interface (LoadUser is typed String).
sub ShowActions(userId as String, userName as String)
    name = userName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "UserAdminActionsScene")
    m.top.Append(scene)
    scene.LoadUser(userId, name)
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.userList <> invalid then
        m.userList.UnObserveField("itemSelected")
        m.userList.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            Teardown()
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end function
