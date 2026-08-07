'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/ProfileActionsScene.brs

' copyright 2026 Joe Huss
'

'
' Per-profile admin actions: 7 flat "Rating: X" buttons (PUT {rating:int 0-6}),
' Clear PIN (DELETE the pin), and Refresh, plus a detail line summarizing the
' profile's state. Mirrors UserAdminActionsScene's Button + buttonSelected idiom
' and the resident-memory serialization rule: a SINGLE ApiTask, with m.pendingOp
' guarding so a button press while a request is outstanding is ignored (never two
' control="run").
'
' ProfilesScene creates + appends this scene and calls LoadProfile(id,name)
' across the component boundary, so LoadProfile is declared in the XML
' <interface>. State refresh is MANUAL (Refresh button); after a rating / clear-
' PIN action the OnApiResponse branch chains a RefreshProfile() so the new state
' shows (exactly like F11c approve/disable).
'
' LANDMINES: rating / is_admin / is_active / pin_required_for_admin are
' bool-or-TINYINT - NEVER compare them with <> "" (Integer<>String CRASH). Read
' bools via IsAdminUser / IsTruthyFlag; map the rating int via RatingLabel. An
' {error} body (400/404) still arrives with result.ok = TRUE, so MessageOf()
' reads message-or-error explicitly. getProfile() returns the WHOLE envelope
' {profile} (admin getters do not unwrap).

sub Init()
    m.top.SetFocus(true)

    ' The 7 flat rating buttons (each fires a thin handler -> QueueRating(n)).
    m.ratingGButton = m.top.FindNode("ratingGButton")
    if m.ratingGButton <> invalid then m.ratingGButton.ObserveField("buttonSelected", "OnRatingG")
    m.ratingPgButton = m.top.FindNode("ratingPgButton")
    if m.ratingPgButton <> invalid then m.ratingPgButton.ObserveField("buttonSelected", "OnRatingPg")
    m.ratingPg13Button = m.top.FindNode("ratingPg13Button")
    if m.ratingPg13Button <> invalid then m.ratingPg13Button.ObserveField("buttonSelected", "OnRatingPg13")
    m.ratingRButton = m.top.FindNode("ratingRButton")
    if m.ratingRButton <> invalid then m.ratingRButton.ObserveField("buttonSelected", "OnRatingR")
    m.ratingNc17Button = m.top.FindNode("ratingNc17Button")
    if m.ratingNc17Button <> invalid then m.ratingNc17Button.ObserveField("buttonSelected", "OnRatingNc17")
    m.ratingXButton = m.top.FindNode("ratingXButton")
    if m.ratingXButton <> invalid then m.ratingXButton.ObserveField("buttonSelected", "OnRatingX")
    m.ratingUnratedButton = m.top.FindNode("ratingUnratedButton")
    if m.ratingUnratedButton <> invalid then m.ratingUnratedButton.ObserveField("buttonSelected", "OnRatingUnrated")

    m.clearPinButton = m.top.FindNode("clearPinButton")
    if m.clearPinButton <> invalid then m.clearPinButton.ObserveField("buttonSelected", "OnClearPin")
    m.parentalControlsButton = m.top.FindNode("parentalControlsButton")
    if m.parentalControlsButton <> invalid then m.parentalControlsButton.ObserveField("buttonSelected", "OnParentalControls")
    m.refreshButton = m.top.FindNode("refreshButton")
    if m.refreshButton <> invalid then m.refreshButton.ObserveField("buttonSelected", "OnRefresh")

    m.titleLabel = m.top.FindNode("titleLabel")
    m.detailLabel = m.top.FindNode("detailLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through a SINGLE observed ApiTask node (off the
    ' render thread). Every op is serialized through this one task.
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' State. m.pendingOp tracks the one outstanding op (invalid = idle) so a
    ' button press while a request is in flight is ignored.
    m.profileId = ""
    m.profileName = ""
    m.pendingOp = invalid

    ' Focus the first rating button.
    if m.ratingGButton <> invalid then m.ratingGButton.SetFocus(true)

    ' Observe our own requestClose so a child can ask us to close.
    m.top.ObserveField("requestClose", "OnChildRequestClose")

    ' Do NOT load here - profileId is not known until LoadProfile().
end sub

' Interface fn: called by ProfilesScene with the selected profile's id+name.
sub LoadProfile(profileId as String, profileName as String)
    m.profileId = profileId

    name = profileName
    if name = invalid then name = ""
    m.profileName = name
    if m.titleLabel <> invalid then m.titleLabel.text = name

    if m.profileId = "" then return

    RefreshProfile()
end sub

' Read the current profile (serialized, guarded). Skipped while another op is in
' flight so two control="run" are never outstanding on the single task.
sub RefreshProfile()
    if m.pendingOp <> invalid then return
    if m.profileId = "" then return

    m.pendingOp = "getProfile"
    SetStatus("Loading…")
    m.apiTask.request = { op: "getProfile", profileId: m.profileId }
    m.apiTask.control = "run"
end sub

' Thin rating handlers -> QueueRating with the int 0-6.
sub OnRatingG(event as Object)
    QueueRating(0)
end sub

sub OnRatingPg(event as Object)
    QueueRating(1)
end sub

sub OnRatingPg13(event as Object)
    QueueRating(2)
end sub

sub OnRatingR(event as Object)
    QueueRating(3)
end sub

sub OnRatingNc17(event as Object)
    QueueRating(4)
end sub

sub OnRatingX(event as Object)
    QueueRating(5)
end sub

sub OnRatingUnrated(event as Object)
    QueueRating(6)
end sub

' Enqueue a rating PUT (serialized + guarded). A press while an op is in flight
' is ignored (one op at a time - never two control="run").
sub QueueRating(rating as Integer)
    if m.pendingOp <> invalid then return
    if m.profileId = "" then return

    m.pendingOp = "setProfileRating"
    SetStatus("Working…")
    m.apiTask.request = { op: "setProfileRating", profileId: m.profileId, rating: rating }
    m.apiTask.control = "run"
end sub

sub OnClearPin(event as Object)
    if m.pendingOp <> invalid then return
    if m.profileId = "" then return

    m.pendingOp = "clearProfilePin"
    SetStatus("Working…")
    m.apiTask.request = { op: "clearProfilePin", profileId: m.profileId }
    m.apiTask.control = "run"
end sub

sub OnRefresh(event as Object)
    RefreshProfile()
end sub

sub OnParentalControls(event as Object)
    ShowParentalControls(m.profileId, m.profileName)
end sub

' Open the parental controls surface (Schedules / Tags / Stream Limits).
sub ShowParentalControls(profileId as String, profileName as String)
    if profileId = "" then return

    name = profileName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "ParentalControlsScene")
    m.top.Append(scene)
    scene.ObserveField("requestClose", "OnChildRequestClose")
    scene.LoadProfile(profileId, name)
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    ' The single outstanding op completed - clear the guard FIRST so a chained
    ' RefreshProfile() is a fresh serialized request.
    m.pendingOp = invalid

    if resp.op = "getProfile" then
        ' getProfile() returns the WHOLE envelope {profile}.
        profile = invalid
        if resp.ok and resp.data <> invalid and resp.data.DoesExist("profile") then
            profile = resp.data.profile
        end if

        if m.detailLabel <> invalid then
            if profile = invalid then
                m.detailLabel.text = "Profile not found"
            else
                m.detailLabel.text = ProfileDetailSummary(profile)
            end if
        end if

        SetStatus("")
    else if resp.op = "setProfileRating" or resp.op = "clearProfilePin" then
        SetStatus(MessageOf(resp))
        ' State changed -> re-render (m.pendingOp is already cleared above, so
        ' this is a fresh serialized call - brief message flash then re-render,
        ' exactly like F11c approve/disable).
        RefreshProfile()
    end if
end sub

' Read the message-or-error key from an action response (LANDMINE: an {error}
' body still arrives with result.ok = TRUE). Prefer message (success), else
' error (failure), else a generic depending on resp.ok.
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
    return "Request failed"
end function

' Build a multi-line summary of a profile row. name guards DoesExist + invalid +
' ""; the rating line prefers settings.content_rating (label string) else the
' computed rating int via RatingLabel; the admin/active/PIN lines come from
' IsAdminUser / IsTruthyFlag (NEVER a numeric <> "" compare).
function ProfileDetailSummary(profile as Object) as String
    if profile = invalid then return ""

    lines = []

    name = ""
    if profile.DoesExist("name") and profile.name <> invalid and profile.name <> "" then name = profile.name
    lines.Push("Name: " + name)

    lines.Push("Rating: " + ProfileRatingLabel(profile))

    if IsAdminUser(profile) then
        lines.Push("Admin: yes")
    else
        lines.Push("Admin: no")
    end if

    if IsTruthyFlag(profile, "is_active") then
        lines.Push("Active: yes")
    else
        lines.Push("Active: no")
    end if

    pinRequired = false
    if profile.DoesExist("settings") and profile.settings <> invalid then
        pinRequired = IsTruthyFlag(profile.settings, "pin_required_for_admin")
    end if
    if pinRequired then
        lines.Push("PIN required: yes")
    else
        lines.Push("PIN required: no")
    end if

    summary = ""
    for i = 0 to lines.Count() - 1
        if i > 0 then summary = summary + Chr(10)
        summary = summary + lines[i]
    end for

    return summary
end function

' Resolve a profile's rating label: prefer settings.content_rating (already a
' label string), else map the computed rating int via RatingLabel. Returns
' "UNRATED" if neither is present. NEVER compares the numeric rating with <> "".
function ProfileRatingLabel(profile as Object) as String
    if profile = invalid then return "UNRATED"

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
        if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
            return RatingLabel(Int(v))
        end if
    end if

    return "UNRATED"
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.ratingGButton <> invalid then m.ratingGButton.UnObserveField("buttonSelected")
    if m.ratingPgButton <> invalid then m.ratingPgButton.UnObserveField("buttonSelected")
    if m.ratingPg13Button <> invalid then m.ratingPg13Button.UnObserveField("buttonSelected")
    if m.ratingRButton <> invalid then m.ratingRButton.UnObserveField("buttonSelected")
    if m.ratingNc17Button <> invalid then m.ratingNc17Button.UnObserveField("buttonSelected")
    if m.ratingXButton <> invalid then m.ratingXButton.UnObserveField("buttonSelected")
    if m.ratingUnratedButton <> invalid then m.ratingUnratedButton.UnObserveField("buttonSelected")
    if m.clearPinButton <> invalid then m.clearPinButton.UnObserveField("buttonSelected")
    if m.parentalControlsButton <> invalid then m.parentalControlsButton.UnObserveField("buttonSelected")
    if m.refreshButton <> invalid then m.refreshButton.UnObserveField("buttonSelected")
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