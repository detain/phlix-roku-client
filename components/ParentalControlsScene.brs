' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/ParentalControlsScene.brs

' copyright 2026 Joe Huss
'

'
' P5-S5 Parental Controls scene with three sections:
' - Schedules: access time windows with day-of-week and start/end time
' - Tags: blocked tag management (add/remove)
' - Stream Limits: max concurrent streams configuration
'
' ProfileActionsScene creates + appends + focuses this scene and calls
' LoadProfile(profileId, profileName) across the component boundary, so
' LoadProfile is declared in the XML <interface>.
'
' State refresh is MANUAL (Refresh button); after mutations the OnApiResponse
' chains a RefreshAll() so the new state shows.
'
' LANDMINES:
' - profile ids may arrive as JSON numbers -> MUST stringify before API paths
' - type-guard ALL numeric comparisons (Integer <> "" CRASHES)
' - m.pendingOp guards so a button press while a request is outstanding is ignored

sub Init()
    m.top.SetFocus(true)

    ' Section tabs
    m.tabSchedulesButton = m.top.FindNode("tabSchedulesButton")
    if m.tabSchedulesButton <> invalid then
        m.tabSchedulesButton.ObserveField("buttonSelected", "OnTabSchedules")
        m.tabSchedulesButton.SetFocus(true)
    end if
    m.tabTagsButton = m.top.FindNode("tabTagsButton")
    if m.tabTagsButton <> invalid then m.tabTagsButton.ObserveField("buttonSelected", "OnTabTags")
    m.tabStreamLimitsButton = m.top.FindNode("tabStreamLimitsButton")
    if m.tabStreamLimitsButton <> invalid then m.tabStreamLimitsButton.ObserveField("buttonSelected", "OnTabStreamLimits")

    ' Schedules section nodes
    m.schedulesSection = m.top.FindNode("schedulesSection")
    m.schedulesList = m.top.FindNode("schedulesList")
    if m.schedulesList <> invalid then
        m.schedulesList.ObserveField("itemSelected", "OnScheduleSelected")
    end if
    m.scheduleNameInput = m.top.FindNode("scheduleNameInput")
    m.startTimeInput = m.top.FindNode("startTimeInput")
    m.endTimeInput = m.top.FindNode("endTimeInput")
    m.addScheduleButton = m.top.FindNode("addScheduleButton")
    if m.addScheduleButton <> invalid then m.addScheduleButton.ObserveField("buttonSelected", "OnAddSchedule")
    m.deleteScheduleButton = m.top.FindNode("deleteScheduleButton")
    if m.deleteScheduleButton <> invalid then m.deleteScheduleButton.ObserveField("buttonSelected", "OnDeleteSchedule")

    ' Day-of-week buttons
    m.dayMonButton = m.top.FindNode("dayMonButton")
    if m.dayMonButton <> invalid then m.dayMonButton.ObserveField("buttonSelected", "OnDayMon")
    m.dayTueButton = m.top.FindNode("dayTueButton")
    if m.dayTueButton <> invalid then m.dayTueButton.ObserveField("buttonSelected", "OnDayTue")
    m.dayWedButton = m.top.FindNode("dayWedButton")
    if m.dayWedButton <> invalid then m.dayWedButton.ObserveField("buttonSelected", "OnDayWed")
    m.dayThuButton = m.top.FindNode("dayThuButton")
    if m.dayThuButton <> invalid then m.dayThuButton.ObserveField("buttonSelected", "OnDayThu")
    m.dayFriButton = m.top.FindNode("dayFriButton")
    if m.dayFriButton <> invalid then m.dayFriButton.ObserveField("buttonSelected", "OnDayFri")
    m.daySatButton = m.top.FindNode("daySatButton")
    if m.daySatButton <> invalid then m.daySatButton.ObserveField("buttonSelected", "OnDaySat")
    m.daySunButton = m.top.FindNode("daySunButton")
    if m.daySunButton <> invalid then m.daySunButton.ObserveField("buttonSelected", "OnDaySun")

    ' Tags section nodes
    m.tagsSection = m.top.FindNode("tagsSection")
    m.tagsList = m.top.FindNode("tagsList")
    if m.tagsList <> invalid then
        m.tagsList.ObserveField("itemSelected", "OnTagSelected")
    end if
    m.tagNameInput = m.top.FindNode("tagNameInput")
    m.addTagButton = m.top.FindNode("addTagButton")
    if m.addTagButton <> invalid then m.addTagButton.ObserveField("buttonSelected", "OnAddTag")
    m.removeTagButton = m.top.FindNode("removeTagButton")
    if m.removeTagButton <> invalid then m.removeTagButton.ObserveField("buttonSelected", "OnRemoveTag")

    ' Stream limits section nodes
    m.streamLimitsSection = m.top.FindNode("streamLimitsSection")
    m.currentStreamLimitLabel = m.top.FindNode("currentStreamLimitLabel")
    m.maxStreamsInput = m.top.FindNode("maxStreamsInput")
    m.updateStreamLimitButton = m.top.FindNode("updateStreamLimitButton")
    if m.updateStreamLimitButton <> invalid then m.updateStreamLimitButton.ObserveField("buttonSelected", "OnUpdateStreamLimit")

    ' Labels
    m.titleLabel = m.top.FindNode("titleLabel")
    m.statusLabel = m.top.FindNode("statusLabel")

    ' Single ApiTask for all operations
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' State
    m.profileId = ""
    m.profileName = ""
    m.pendingOp = invalid
    m.schedules = []
    m.tags = []
    m.streamLimit = invalid
    m.selectedScheduleIndex = -1
    m.selectedTagIndex = -1
    m.selectedDays = { mon: false, tue: false, wed: false, thu: false, fri: false, sat: false, sun: false }
    m.currentSection = "schedules"

    ' Show schedules section by default
    ShowSection("schedules")
end sub

' Interface fn: called by ProfileActionsScene with the selected profile's id+name.
sub LoadProfile(profileId as String, profileName as String)
    m.profileId = StringifyId(profileId)

    name = profileName
    if name = invalid then name = ""
    m.profileName = name
    if m.titleLabel <> invalid then m.titleLabel.text = "Parental Controls — " + name

    if m.profileId = "" then return

    RefreshAll()
end sub

' Refresh all parental control data (schedules, tags, stream limits).
' Serialized through m.pendingOp guard.
sub RefreshAll()
    if m.pendingOp <> invalid then return
    if m.profileId = "" then return

    SetStatus("Loading…")

    ' Start with schedules - they load first to determine next pending op
    m.pendingOp = "getProfileSchedules"
    m.apiTask.request = { op: "getProfileSchedules", profileId: m.profileId }
    m.apiTask.control = "run"
end sub

' Convert any profile id (numeric or string) to a String for API paths.
' CRASH PROTECTION: "/profiles/" + Integer CRASHES, so we MUST stringify.
function StringifyId(id as Object) as String
    if id = invalid then return ""
    t = type(id)
    if t = "roString" or t = "String" then return id
    if t = "Integer" or t = "roInt" or t = "LongInteger" or t = "roLongInteger" or t = "Float" or t = "roFloat" or t = "Double" or t = "roDouble" then
        return str(Int(id)).trim()
    end if
    return ""
end function

' Guard: ensure we have a valid profile id before any API call.
function HasProfileId() as Boolean
    return m.profileId <> ""
end function

' Guard: ensure no other operation is in flight.
function CanStartOp() as Boolean
    return m.pendingOp = invalid and HasProfileId()
end function

' Show the specified section, hide the others.
sub ShowSection(section as String)
    m.currentSection = section

    if m.schedulesSection <> invalid then m.schedulesSection.visible = (section = "schedules")
    if m.tagsSection <> invalid then m.tagsSection.visible = (section = "tags")
    if m.streamLimitsSection <> invalid then m.streamLimitsSection.visible = (section = "streamLimits")

    ' Focus appropriate button
    if section = "schedules" and m.tabSchedulesButton <> invalid then
        m.tabSchedulesButton.SetFocus(true)
    else if section = "tags" and m.tabTagsButton <> invalid then
        m.tabTagsButton.SetFocus(true)
    else if section = "streamLimits" and m.tabStreamLimitsButton <> invalid then
        m.tabStreamLimitsButton.SetFocus(true)
    end if
end sub

' Tab button handlers
sub OnTabSchedules()
    ShowSection("schedules")
end sub

sub OnTabTags()
    ShowSection("tags")
end sub

sub OnTabStreamLimits()
    ShowSection("streamLimits")
end sub

' Schedule selection
sub OnScheduleSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.schedules.Count() then return
    m.selectedScheduleIndex = index
end sub

' Add new schedule
sub OnAddSchedule()
    if not CanStartOp() then return

    name = ""
    if m.scheduleNameInput <> invalid and m.scheduleNameInput.text <> invalid then
        name = m.scheduleNameInput.text.trim()
    end if
    if name = "" then
        SetStatus("Please enter a schedule name")
        return
    end if

    startTime = ""
    if m.startTimeInput <> invalid and m.startTimeInput.text <> invalid then
        startTime = ValidateTimeString(m.startTimeInput.text.trim())
    end if
    if startTime = "" then
        SetStatus("Please enter a valid start time (HH:MM)")
        return
    end if

    endTime = ""
    if m.endTimeInput <> invalid and m.endTimeInput.text <> invalid then
        endTime = ValidateTimeString(m.endTimeInput.text.trim())
    end if
    if endTime = "" then
        SetStatus("Please enter a valid end time (HH:MM)")
        return
    end if

    ' Collect selected days
    days = []
    if m.selectedDays.mon then days.Push("mon")
    if m.selectedDays.tue then days.Push("tue")
    if m.selectedDays.wed then days.Push("wed")
    if m.selectedDays.thu then days.Push("thu")
    if m.selectedDays.fri then days.Push("fri")
    if m.selectedDays.sat then days.Push("sat")
    if m.selectedDays.sun then days.Push("sun")

    if days.Count() = 0 then
        SetStatus("Please select at least one day")
        return
    end if

    m.pendingOp = "createProfileSchedule"
    SetStatus("Adding schedule…")
    m.apiTask.request = {
        op: "createProfileSchedule",
        profileId: m.profileId,
        schedule: {
            name: name,
            startTime: startTime,
            endTime: endTime,
            daysOfWeek: days,
            isActive: true
        }
    }
    m.apiTask.control = "run"
end sub

' Delete selected schedule
sub OnDeleteSchedule()
    if not CanStartOp() then return
    if m.selectedScheduleIndex < 0 or m.selectedScheduleIndex >= m.schedules.Count() then
        SetStatus("Please select a schedule to delete")
        return
    end if

    schedule = m.schedules[m.selectedScheduleIndex]
    if schedule = invalid then return

    scheduleId = StringifyId(schedule.id)
    if scheduleId = "" then
        SetStatus("Cannot delete: schedule has no id")
        return
    end if

    m.pendingOp = "deleteProfileSchedule"
    SetStatus("Deleting schedule…")
    m.apiTask.request = { op: "deleteProfileSchedule", profileId: m.profileId, scheduleId: scheduleId }
    m.apiTask.control = "run"
end sub

' Day-of-week button handlers
sub OnDayMon()
    m.selectedDays.mon = not m.selectedDays.mon
    UpdateDayButtonStyle(m.dayMonButton, m.selectedDays.mon)
end sub

sub OnDayTue()
    m.selectedDays.tue = not m.selectedDays.tue
    UpdateDayButtonStyle(m.dayTueButton, m.selectedDays.tue)
end sub

sub OnDayWed()
    m.selectedDays.wed = not m.selectedDays.wed
    UpdateDayButtonStyle(m.dayWedButton, m.selectedDays.wed)
end sub

sub OnDayThu()
    m.selectedDays.thu = not m.selectedDays.thu
    UpdateDayButtonStyle(m.dayThuButton, m.selectedDays.thu)
end sub

sub OnDayFri()
    m.selectedDays.fri = not m.selectedDays.fri
    UpdateDayButtonStyle(m.dayFriButton, m.selectedDays.fri)
end sub

sub OnDaySat()
    m.selectedDays.sat = not m.selectedDays.sat
    UpdateDayButtonStyle(m.daySatButton, m.selectedDays.sat)
end sub

sub OnDaySun()
    m.selectedDays.sun = not m.selectedDays.sun
    UpdateDayButtonStyle(m.daySunButton, m.selectedDays.sun)
end sub

' Update day button appearance (selected state)
sub UpdateDayButtonStyle(button as Object, isSelected as Boolean)
    if button = invalid then return
    if isSelected then
        button.backgroundColor = "#4CAF50"
    else
        button.backgroundColor = "#333333"
    end if
end sub

' Tag selection
sub OnTagSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.tags.Count() then return
    m.selectedTagIndex = index
end sub

' Add new blocked tag
sub OnAddTag()
    if not CanStartOp() then return

    tagName = ""
    if m.tagNameInput <> invalid and m.tagNameInput.text <> invalid then
        tagName = m.tagNameInput.text.trim()
    end if
    if tagName = "" then
        SetStatus("Please enter a tag name")
        return
    end if

    m.pendingOp = "createProfileTag"
    SetStatus("Adding tag…")
    m.apiTask.request = {
        op: "createProfileTag",
        profileId: m.profileId,
        tag: { tag: tagName, tagType: "blocked" }
    }
    m.apiTask.control = "run"
end sub

' Remove selected tag
sub OnRemoveTag()
    if not CanStartOp() then return
    if m.selectedTagIndex < 0 or m.selectedTagIndex >= m.tags.Count() then
        SetStatus("Please select a tag to remove")
        return
    end if

    tag = m.tags[m.selectedTagIndex]
    if tag = invalid then return

    tagId = StringifyId(tag.id)
    if tagId = "" then
        SetStatus("Cannot delete: tag has no id")
        return
    end if

    m.pendingOp = "deleteProfileTag"
    SetStatus("Removing tag…")
    m.apiTask.request = { op: "deleteProfileTag", profileId: m.profileId, tagId: tagId }
    m.apiTask.control = "run"
end sub

' Update stream limit
sub OnUpdateStreamLimit()
    if not CanStartOp() then return

    maxStreams = 0
    if m.maxStreamsInput <> invalid and m.maxStreamsInput.text <> invalid then
        maxStreams = Int(m.maxStreamsInput.text.trim())
    end if

    if maxStreams < 1 or maxStreams > 10 then
        SetStatus("Please enter a value between 1 and 10")
        return
    end if

    m.pendingOp = "updateProfileStreamLimits"
    SetStatus("Updating stream limit…")
    m.apiTask.request = {
        op: "updateProfileStreamLimits",
        profileId: m.profileId,
        limits: { maxConcurrentStreams: maxStreams }
    }
    m.apiTask.control = "run"
end sub

' Handle all API responses
sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    ' Clear pending op FIRST so chained refreshes can queue new operations
    priorOp = m.pendingOp
    m.pendingOp = invalid

    if resp.op = "getProfileSchedules" then
        m.schedules = []
        if resp.ok and resp.data <> invalid then
            if resp.data.DoesExist("schedules") and type(resp.data.schedules) = "roArray" then
                m.schedules = resp.data.schedules
            end if
        end if
        RenderSchedulesList()

        ' Now load tags
        m.pendingOp = "getProfileTags"
        m.apiTask.request = { op: "getProfileTags", profileId: m.profileId }
        m.apiTask.control = "run"

    else if resp.op = "getProfileTags" then
        m.tags = []
        if resp.ok and resp.data <> invalid then
            if resp.data.DoesExist("tags") and type(resp.data.tags) = "roArray" then
                m.tags = resp.data.tags
            end if
        end if
        RenderTagsList()

        ' Now load stream limits
        m.pendingOp = "getProfileStreamLimits"
        m.apiTask.request = { op: "getProfileStreamLimits", profileId: m.profileId }
        m.apiTask.control = "run"

    else if resp.op = "getProfileStreamLimits" then
        m.streamLimit = invalid
        if resp.ok and resp.data <> invalid then
            if resp.data.DoesExist("stream_limit") then
                m.streamLimit = resp.data.stream_limit
            end if
        end if
        RenderStreamLimits()

        SetStatus("")

    else if resp.op = "createProfileSchedule" then
        SetStatus(MessageOf(resp))
        RefreshAll()

    else if resp.op = "deleteProfileSchedule" then
        SetStatus(MessageOf(resp))
        m.selectedScheduleIndex = -1
        RefreshAll()

    else if resp.op = "createProfileTag" then
        SetStatus(MessageOf(resp))
        RefreshAll()

    else if resp.op = "deleteProfileTag" then
        SetStatus(MessageOf(resp))
        m.selectedTagIndex = -1
        RefreshAll()

    else if resp.op = "updateProfileStreamLimits" then
        SetStatus(MessageOf(resp))
        RefreshAll()
    end if
end sub

' Render the schedules list
sub RenderSchedulesList()
    if m.schedulesList = invalid then return

    content = CreateObject("roSGNode", "ContentNode")
    for each schedule in m.schedules
        if schedule <> invalid then
            content.AddChild({ title: ScheduleCaption(schedule) })
        end if
    end for
    m.schedulesList.content = content
end sub

' Build a caption for a schedule row: "name  (days HH:MM-HH:MM)"
function ScheduleCaption(schedule as Object) as String
    if schedule = invalid then return ""

    name = "(schedule)"
    if schedule.DoesExist("name") and schedule.name <> invalid and schedule.name <> "" then
        name = schedule.name
    end if

    daysStr = ""
    if schedule.DoesExist("daysOfWeek") and schedule.daysOfWeek <> invalid then
        days = schedule.daysOfWeek
        if type(days) = "roArray" and days.Count() > 0 then
            ' Short day names
            dayMap = { mon: "M", tue: "T", wed: "W", thu: "T", fri: "F", sat: "S", sun: "S" }
            parts = []
            for each d in days
                if dayMap.DoesExist(d) then parts.Push(dayMap[d])
            end for
            daysStr = JoinStrings(parts, "")
        end if
    end if

    startTime = ""
    if schedule.DoesExist("startTime") and schedule.startTime <> invalid then startTime = schedule.startTime
    endTime = ""
    if schedule.DoesExist("endTime") and schedule.endTime <> invalid then endTime = schedule.endTime

    timeStr = ""
    if startTime <> "" and endTime <> "" then timeStr = " " + startTime + "-" + endTime

    activeStr = ""
    if schedule.DoesExist("isActive") and schedule.isActive <> invalid then
        if not IsTruthyFlag(schedule, "isActive") then activeStr = " (inactive)"
    end if

    return name + "  (" + daysStr + timeStr + ")" + activeStr
end function

' Render the tags list
sub RenderTagsList()
    if m.tagsList = invalid then return

    content = CreateObject("roSGNode", "ContentNode")
    for each tag in m.tags
        if tag <> invalid then
            content.AddChild({ title: TagCaption(tag) })
        end if
    end for
    m.tagsList.content = content
end sub

' Build a caption for a tag row: "[blocked] tag"
function TagCaption(tag as Object) as String
    if tag = invalid then return ""

    tagName = "(tag)"
    if tag.DoesExist("tag") and tag.tag <> invalid and tag.tag <> "" then
        tagName = tag.tag
    end if

    tagType = ""
    if tag.DoesExist("tagType") and tag.tagType <> invalid then
        tagType = "[" + tag.tagType + "] "
    end if

    return tagType + tagName
end function

' Render stream limits display
sub RenderStreamLimits()
    if m.currentStreamLimitLabel = invalid then return

    if m.streamLimit = invalid then
        m.currentStreamLimitLabel.text = "No stream limit configured"
        if m.maxStreamsInput <> invalid then m.maxStreamsInput.text = ""
        return
    end if

    maxStreams = 0
    if m.streamLimit.DoesExist("maxConcurrentStreams") and m.streamLimit.maxConcurrentStreams <> invalid then
        maxStreams = Int(m.streamLimit.maxConcurrentStreams)
    end if

    m.currentStreamLimitLabel.text = "Current limit: " + str(maxStreams).trim() + " concurrent stream(s)"
    if m.maxStreamsInput <> invalid then m.maxStreamsInput.text = str(maxStreams).trim()
end sub

' Validate and normalize a time string to HH:MM:SS format
function ValidateTimeString(input as String) as String
    if input = invalid or input = "" then return ""

    ' Handle HH:MM or HH:MM:SS formats
    parts = input.split(":")
    if parts.Count() < 2 or parts.Count() > 3 then return ""

    hours = Int(parts[0])
    minutes = Int(parts[1])
    seconds = 0
    if parts.Count() = 3 then seconds = Int(parts[2])

    if hours < 0 or hours > 23 then return ""
    if minutes < 0 or minutes > 59 then return ""
    if seconds < 0 or seconds > 59 then return ""

    return str(hours).trim() + ":" + str(minutes).Trim().Right(2).Repl(" ", "0") + ":" + str(seconds).Trim().Right(2).Repl(" ", "0")
end function

' Read the message-or-error key from an action response.
' LANDMINE: an {error} body still arrives with result.ok = TRUE.
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

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

' Pair every ObserveField with an UnObserveField to prevent leaks.
sub Teardown()
    ' Tabs
    if m.tabSchedulesButton <> invalid then m.tabSchedulesButton.UnObserveField("buttonSelected")
    if m.tabTagsButton <> invalid then m.tabTagsButton.UnObserveField("buttonSelected")
    if m.tabStreamLimitsButton <> invalid then m.tabStreamLimitsButton.UnObserveField("buttonSelected")

    ' Schedules
    if m.schedulesList <> invalid then m.schedulesList.UnObserveField("itemSelected")
    if m.addScheduleButton <> invalid then m.addScheduleButton.UnObserveField("buttonSelected")
    if m.deleteScheduleButton <> invalid then m.deleteScheduleButton.UnObserveField("buttonSelected")

    ' Days
    if m.dayMonButton <> invalid then m.dayMonButton.UnObserveField("buttonSelected")
    if m.dayTueButton <> invalid then m.dayTueButton.UnObserveField("buttonSelected")
    if m.dayWedButton <> invalid then m.dayWedButton.UnObserveField("buttonSelected")
    if m.dayThuButton <> invalid then m.dayThuButton.UnObserveField("buttonSelected")
    if m.dayFriButton <> invalid then m.dayFriButton.UnObserveField("buttonSelected")
    if m.daySatButton <> invalid then m.daySatButton.UnObserveField("buttonSelected")
    if m.daySunButton <> invalid then m.daySunButton.UnObserveField("buttonSelected")

    ' Tags
    if m.tagsList <> invalid then m.tagsList.UnObserveField("itemSelected")
    if m.addTagButton <> invalid then m.addTagButton.UnObserveField("buttonSelected")
    if m.removeTagButton <> invalid then m.removeTagButton.UnObserveField("buttonSelected")

    ' Stream limits
    if m.updateStreamLimitButton <> invalid then m.updateStreamLimitButton.UnObserveField("buttonSelected")

    ' ApiTask
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
