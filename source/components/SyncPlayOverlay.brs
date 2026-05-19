' source/components/SyncPlayOverlay.brs

' ===========================================
' SyncPlay Overlay Component
' SyncPlay UI for the player screen
' ===========================================

sub Init()
    m.top.SetFocus(false)

    ' Find nodes
    m.syncplayToggle = m.top.FindNode("syncplayToggle")
    m.syncStateBg = m.top.FindNode("syncStateBg")
    m.syncStateLabel = m.top.FindNode("syncStateLabel")
    m.memberListPanel = m.top.FindNode("memberListPanel")
    m.memberList = m.top.FindNode("memberList")
    m.leaveGroupButton = m.top.FindNode("leaveGroupButton")
    m.groupDialog = m.top.FindNode("groupDialog")
    m.createGroupButton = m.top.FindNode("createGroupButton")
    m.groupIdInput = m.top.FindNode("groupIdInput")
    m.joinGroupButton = m.top.FindNode("joinGroupButton")
    m.cancelDialogButton = m.top.FindNode("cancelDialogButton")
    m.notificationToast = m.top.FindNode("notificationToast")
    m.notificationText = m.top.FindNode("notificationText")

    ' Set up button observers
    if m.syncplayToggle <> invalid then
        m.syncplayToggle.ObserveField("buttonSelected", "OnSyncPlayToggle")
    end if

    if m.leaveGroupButton <> invalid then
        m.leaveGroupButton.ObserveField("buttonSelected", "OnLeaveGroup")
    end if

    if m.createGroupButton <> invalid then
        m.createGroupButton.ObserveField("buttonSelected", "OnCreateGroup")
    end if

    if m.joinGroupButton <> invalid then
        m.joinGroupButton.ObserveField("buttonSelected", "OnJoinGroup")
    end if

    if m.cancelDialogButton <> invalid then
        m.cancelDialogButton.ObserveField("buttonSelected", "OnCancelDialog")
    end if

    ' Service reference
    m.service = invalid
    m.memberNodes = []

    ' Dialog state
    m.dialogVisible = false

    ' Initial state
    m.top.visible = false
end sub

' Set the SyncPlay service
' @param service Object - SyncPlayService instance
sub setService(service as Object)
    m.service = service

    if m.service <> invalid then
        ' Set up callbacks
        m.service.onGroupStateChanged = sub(info)
            m.OnGroupStateChanged(info)
        end sub

        m.service.onMemberJoined = sub(member)
            m.OnMemberJoined(member)
        end sub

        m.service.onMemberLeft = sub(memberId)
            m.OnMemberLeft(memberId)
        end sub

        m.service.onPlaybackUpdate = sub(update)
            m.OnPlaybackUpdate(update)
        end sub

        m.service.onTimeSyncUpdate = sub(result)
            m.OnTimeSyncUpdate(result)
        end sub
    end if
end sub

' Toggle SyncPlay dialog
sub OnSyncPlayToggle()
    if m.dialogVisible then
        hideDialog()
    else
        showDialog()
    end if
end sub

' Show the group create/join dialog
sub showDialog()
    m.dialogVisible = true
    if m.groupDialog <> invalid then
        m.groupDialog.visible = true
    end if
    if m.groupIdInput <> invalid then
        m.groupIdInput.text = ""
        m.groupIdInput.SetFocus(true)
    end if
end sub

' Hide the dialog
sub hideDialog()
    m.dialogVisible = false
    if m.groupDialog <> invalid then
        m.groupDialog.visible = false
    end if
end sub

' Create a new SyncPlay group
sub OnCreateGroup()
    if m.service = invalid then return

    hideDialog()

    ' Generate a group ID (in practice, server would create the group)
    groupId = GenerateGroupId()
    memberId = GenerateMemberId()

    success = m.service.joinGroup(groupId, memberId)

    if success then
        m.top.visible = true
        m.showNotification("Group created! ID: " + groupId)
        m.updateSyncState(true)
    else
        m.showNotification("Failed to create group")
    end if
end sub

' Join existing group
sub OnJoinGroup()
    if m.service = invalid then return

    groupId = ""
    if m.groupIdInput <> invalid then
        groupId = trim(m.groupIdInput.text)
    end if

    if groupId = "" then
        m.showNotification("Please enter a Group ID")
        return
    end if

    hideDialog()

    memberId = GenerateMemberId()
    success = m.service.joinGroup(groupId, memberId)

    if success then
        m.top.visible = true
        m.showNotification("Joined group: " + groupId)
        m.updateSyncState(true)
    else
        m.showNotification("Failed to join group")
    end if
end sub

' Leave the current group
sub OnLeaveGroup()
    if m.service = invalid then return

    success = m.service.leaveGroup()

    if success then
        m.top.visible = false
        m.updateSyncState(false)
        m.showNotification("Left group")
        m.clearMemberList()
    end if
end sub

' Cancel dialog
sub OnCancelDialog()
    hideDialog()
end sub

' Handle group state change
sub OnGroupStateChanged(info as Object)
    if info.members <> invalid then
        m.updateMemberList(info.members)
    end if
end sub

' Handle member joined notification
sub OnMemberJoined(member as Object)
    if member <> invalid then
        m.showNotification(member.name + " joined the group")
        m.addMemberToList(member)
    end if
end sub

' Handle member left notification
sub OnMemberLeft(memberId as String)
    m.showNotification("Member left the group")
    m.removeMemberFromList(memberId)
end sub

' Handle playback update from another member
sub OnPlaybackUpdate(update as Object)
    ' Sync playback - this would be called when another member
    ' sends a play/pause/seek command
    if update = invalid or m.service = invalid then return

    ' Notify the player to sync
    m.top.syncPlaybackUpdate = update
end sub

' Handle time sync update
sub OnTimeSyncUpdate(result as Object)
    if result <> invalid and result.is_stable = true then
        m.updateSyncIndicator(true)
    else
        m.updateSyncIndicator(false)
    end if
end sub

' Update sync state indicator
sub updateSyncState(inGroup as Boolean)
    if m.syncStateBg <> invalid then
        m.syncStateBg.visible = inGroup
    end if

    if inGroup then
        m.updateSyncIndicator(false)
    end if
end sub

' Update sync indicator
sub updateSyncIndicator(isSynced as Boolean)
    if m.syncStateLabel <> invalid then
        if isSynced then
            m.syncStateLabel.text = "SYNCED"
            m.syncStateLabel.color = "#00FF00"
        else
            m.syncStateLabel.text = "SYNCING..."
            m.syncStateLabel.color = "#FFAA00"
        end if
    end if
end sub

' Update member list
sub updateMemberList(members as Object)
    m.clearMemberList()

    if members = invalid then return

    for each member in members
        m.addMemberToList(member)
    end for
end sub

' Add member to the list UI
sub addMemberToList(member as Object)
    if member = invalid or m.memberList = invalid then return

    memberLabel = CreateObject("roSGNode", "Label")
    memberLabel.text = member.name
    memberLabel.color = "#FFFFFF"
    memberLabel.height = 30
    memberLabel.width = 280

    if member.is_local = true then
        memberLabel.text = member.name + " (You)"
        memberLabel.color = "#0095d5"
    end if

    m.memberList.append(memberLabel)
    m.memberNodes.push(memberLabel)
end sub

' Remove member from list
sub removeMemberFromList(memberId as String)
    ' Find and remove the member node
    ' This is a simplified implementation
end sub

' Clear the member list
sub clearMemberList()
    if m.memberList = invalid then return

    for each node in m.memberNodes
        m.memberList.removeChild(node)
    end for
    m.memberNodes = []
end sub

' Show notification toast
' @param message String - Message to show
sub showNotification(message as String)
    if m.notificationText <> invalid then
        m.notificationText.text = message
    end if

    if m.notificationToast <> invalid then
        m.notificationToast.visible = true

        ' Auto-hide after 3 seconds
        m.hideNotificationTimer = CreateObject("roTimer")
        m.hideNotificationTimer.SetPort(m.top.GetNodePort())
        m.hideNotificationTimer.StartPeriod(3)
        m.hideNotificationTimer.ObserveField("fire", "OnHideNotification")
    end if
end sub

' Hide notification timer handler
sub OnHideNotification()
    if m.hideNotificationTimer <> invalid then
        m.hideNotificationTimer.Stop()
        m.hideNotificationTimer = invalid
    end if

    if m.notificationToast <> invalid then
        m.notificationToast.visible = false
    end if
end sub

' Generate a random group ID
' @return String - Group ID
function GenerateGroupId() as String
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    groupId = ""
    for i = 0 to 6
        idx = Rnd(36) - 1
        groupId = groupId + mid(chars, idx + 1, 1)
    end for
    return groupId
end function

' Generate a unique member ID for this client
' @return String - Member ID
function GenerateMemberId() as String
    deviceId = Storage.get("device_id")
    if deviceId = "" or deviceId = invalid then
        deviceId = "roku-" + str(Rnd(999999999)).trim() + "-" + str(Rnd(999999999)).trim()
        Storage.set("device_id", deviceId)
    end if
    return deviceId
end function

' Handle key events
function OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            if m.dialogVisible then
                hideDialog()
                handled = true
            end if
        end if
    end if

    return handled
end function

' Cleanup when component is destroyed
sub Cleanup()
    if m.hideNotificationTimer <> invalid then
        m.hideNotificationTimer.Stop()
        m.hideNotificationTimer = invalid
    end if
end sub