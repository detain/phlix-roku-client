' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ProfilesScene.brs

' copyright 2026 Joe Huss
'

'
' Read-only per-user profile list: a one-shot LabelList of one user's profiles.
' Mirrors UserAdminScene's LabelList + ApiTask + OnApiResponse idiom, but is
' parameterized by userId - the load fires from LoadProfiles (the interface fn)
' once the userId is known, NOT from Init. Selecting a row opens that profile's
' per-profile actions (Set Rating / Clear PIN / Refresh) in a ProfileActionsScene.
'
' UserAdminActionsScene self-creates + appends + focuses this scene and calls
' LoadProfiles(userId,userName) across the component boundary, so LoadProfiles is
' declared in the XML <interface>.
'
' NOTE: getUserProfiles() returns the WHOLE envelope {profiles:[...]} (admin
' getters do not unwrap), so OnApiResponse reads resp.data.profiles and checks
' resp.data.DoesExist("profiles") AND type(resp.data.profiles) = "roArray".
'
' LANDMINES: rating / is_admin / is_active / pin_required_for_admin are
' bool-or-TINYINT - NEVER compare them with <> "" (Integer<>String CRASH). Read
' bools via IsAdminUser / IsTruthyFlag; map the rating int via RatingLabel. A
' profile id may arrive as a JSON number, so it is stringified (type-guarded)
' before crossing the LoadProfile interface (typed String) - "/admin/profiles/"
' + an Integer would CRASH.

sub Init()
    m.top.SetFocus(true)

    ' Text list of profiles.
    m.profileList = m.top.FindNode("profileList")
    if m.profileList <> invalid then
        m.profileList.ObserveField("itemSelected", "OnRowSelected")
        m.profileList.ObserveField("itemFocused", "OnRowFocused")
        m.profileList.SetFocus(true)
    end if

    m.titleLabel = m.top.FindNode("titleLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.profiles = []
    m.userId = ""
    m.userName = ""

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")

    ' Do NOT fire the load here - userId is not known until LoadProfiles().
end sub

' Interface fn: called by UserAdminActionsScene with the selected user's id+name.
sub LoadProfiles(userId as String, userName as String)
    m.userId = userId

    name = userName
    if name = invalid then name = ""
    m.userName = name
    if m.titleLabel <> invalid then m.titleLabel.text = "Profiles — " + name

    if m.userId = "" then return

    SetStatus("Loading…")
    m.apiTask.request = { op: "getUserProfiles", userId: m.userId }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getUserProfiles" then
        ' getUserProfiles() returns the WHOLE envelope {profiles:[...]}.
        m.profiles = []
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("profiles") and type(resp.data.profiles) = "roArray" then
            m.profiles = resp.data.profiles
        end if

        content = CreateObject("roSGNode", "ContentNode")
        for each profile in m.profiles
            if profile <> invalid then
                content.AddChild({ title: ProfileRowCaption(profile) })
            end if
        end for

        if m.profileList <> invalid then m.profileList.content = content

        if m.profiles.Count() = 0 then
            SetStatus("No profiles")
        else
            SetStatus("")
        end if
    end if
end sub

' Caption for a profile row: "<name>  (<rating>, admin, active, PIN)" - the tags
' are only appended when present. name = profile.name (fallback "(profile)").
' rating = settings.content_rating (label string) if present, else the computed
' rating int via RatingLabel. is_admin via IsAdminUser; is_active and the
' settings PIN flag via IsTruthyFlag (NEVER a numeric <> "" compare).
function ProfileRowCaption(profile as Object) as String
    if profile = invalid then return ""

    name = ""
    if profile.DoesExist("name") and profile.name <> invalid and profile.name <> "" then
        name = profile.name
    else
        name = "(profile)"
    end if

    tags = []

    rating = ProfileRatingLabel(profile)
    if rating <> "" then tags.Push(rating)

    if IsAdminUser(profile) then tags.Push("admin")
    if IsTruthyFlag(profile, "is_active") then tags.Push("active")

    settings = invalid
    if profile.DoesExist("settings") and profile.settings <> invalid then settings = profile.settings
    if settings <> invalid and IsTruthyFlag(settings, "pin_required_for_admin") then tags.Push("PIN")

    if tags.Count() = 0 then return name

    suffix = ""
    for i = 0 to tags.Count() - 1
        if i > 0 then suffix = suffix + ", "
        suffix = suffix + tags[i]
    end for

    return name + "  (" + suffix + ")"
end function

' Resolve a profile's rating label: prefer settings.content_rating (already a
' label string), else map the computed rating int via RatingLabel. Returns "" if
' neither is present. NEVER compares the numeric rating with <> "".
function ProfileRatingLabel(profile as Object) as String
    if profile = invalid then return ""

    settings = invalid
    if profile.DoesExist("settings") and profile.settings <> invalid then settings = profile.settings
    if settings <> invalid and type(settings) = "roAssociativeArray" then
        if settings.DoesExist("content_rating") and settings.content_rating <> invalid then
            cr = settings.content_rating
            if type(cr) = "roString" and cr <> "" then return cr
        end if
    end if

    if profile.DoesExist("rating") and profile.rating <> invalid then
        v = profile.rating
        t = type(v)
        if t = "String" or t = "roString" then
            return v
        else if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
            return RatingLabel(Int(v))
        end if
    end if

    return ""
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.profiles.Count() then return

    profile = m.profiles[index]
    if profile = invalid then return

    SetStatus(ProfileRowCaption(profile))
end sub

sub OnRowSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.profiles.Count() then return

    profile = m.profiles[index]
    if profile = invalid then return

    ' Stringify the id BEFORE crossing the LoadProfile interface (typed String) -
    ' a profile id may arrive as a JSON number, and "/admin/profiles/" + an
    ' Integer would CRASH. Use a String as-is; coerce a numeric via str(Int()).
    id = ""
    if profile.DoesExist("id") and profile.id <> invalid then
        rawId = profile.id
        t = type(rawId)
        if t = "roString" then
            id = rawId
        else if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
            id = str(Int(rawId)).trim()
        end if
    end if

    name = ""
    if profile.DoesExist("name") and profile.name <> invalid and profile.name <> "" then
        name = profile.name
    end if

    if id <> "" then ShowProfileActions(id, name)
end sub

' Open the per-profile actions surface (Set Rating / Clear PIN / Refresh). Coerce
' an invalid name to "" before crossing the interface (LoadProfile is typed String).
sub ShowProfileActions(profileId as String, profileName as String)
    name = profileName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "ProfileActionsScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadProfile(profileId, name)
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.profileList <> invalid then
        m.profileList.UnObserveField("itemSelected")
        m.profileList.UnObserveField("itemFocused")
    end if
    if m.apiTask <> invalid then m.apiTask.UnObserveField("response")
end sub

' Bubble requestClose from a child scene up to the parent.
sub OnChildRequestClose()
    m.top.requestClose = true
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