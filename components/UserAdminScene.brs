' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/UserAdminScene.brs

' copyright 2026 Joe Huss
'

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
    ApplyXmlChrome()
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

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")

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
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadUser(userId, name)
end sub

' requestClose contract (docs/navigation.md): the OBSERVING parent removes the
' child that raised the signal and takes focus back (mirror of PhlixApp.
' PopScreen). The old bubble-up died below HomeScene - Back was a silent no-op
' on every Home-opened screen [review roku__casualgamer C1]. Init also
' self-observes this handler on m.top: when our OWN requestClose fires, our
' parent owns the removal and we only tear down.
' PopScreen tolerates its pre-removal unobserve because its removal runs
' in the very arm doing the unobserving - pruning can never roll back an
' already-committed RemoveChild. These handlers run INSIDE the child's
' requestClose dispatch, and a scene must never unobserve the field from
' an arm registered before its parent's (its own Teardown): the parent's
' removal arm could be pruned mid-dispatch (C03-r2; CHECK27 R6). A
' detached child's observers are freed with its subtree anyway.
sub OnChildRequestClose(event as Object)
    child = event.GetNode()
    if child = invalid then return
    if child = m.top then
        Teardown()
        return
    end if
    if child.GetParent() <> m.top then return
    m.top.RemoveChild(child)
    m.top.SetFocus(true)
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
            m.top.requestClose = true
            handled = true
        end if
    end if

    return handled
end function

' ApplyXmlChrome - localize the XML chrome literals (titles/labels that
' ship as component markup) at scene init. CHECK25 in
' scripts/verify-runtime.sh requires every user-facing components/*.xml
' string to have a programmatic Translate() override path; this sub is
' that path. The XML keeps English values as the en-fallback default,
' mirroring the DetailScene precedent.
sub ApplyXmlChrome()
    n = m.top.findNode("headerLabel")
    if n <> invalid then n.text = Translate("common_users")
    n = m.top.findNode("statusLabel")
    if n <> invalid then n.text = Translate("common_loading")
end sub
