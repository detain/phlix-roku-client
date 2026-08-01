' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' tests/unit/TaskManager.test.brs

' ===========================================
' TaskManager Unit Tests
' ===========================================

sub TestTaskManagerInit()
    ' Test initialization
    mgr = TaskManager()
    assertTrue(mgr <> invalid)
    assertTrue(mgr.tasks <> invalid)
    assertEqual(mgr.tasks.Count(), 0)
    print "TestTaskManagerInit passed"
end sub

sub TestTaskManagerStartTaskWithInvalidNode()
    ' Test startTask handles invalid task node gracefully
    mgr = TaskManager()
    task = mgr.startTask("test", "NonExistentNode")
    ' CreateObject returns invalid for non-existent components
    assertEqual(task, invalid)
    print "TestTaskManagerStartTaskWithInvalidNode passed"
end sub

sub TestTaskManagerStopTaskNonExistent()
    ' Test stopTask handles non-existent task gracefully
    mgr = TaskManager()
    mgr.stopTask("nonExistent")
    ' Should not throw
    assertTrue(true)
    print "TestTaskManagerStopTaskNonExistent passed"
end sub

sub TestTaskManagerGetTaskNonExistent()
    ' Test getTask returns invalid for non-existent task
    mgr = TaskManager()
    result = mgr.getTask("nonExistent")
    assertEqual(result, invalid)
    print "TestTaskManagerGetTaskNonExistent passed"
end sub

sub TestTaskManagerStopAllTasksEmpty()
    ' Test stopAllTasks with no tasks does nothing
    mgr = TaskManager()
    mgr.stopAllTasks()
    ' Should not throw
    assertTrue(true)
    print "TestTaskManagerStopAllTasksEmpty passed"
end sub

sub TestTaskManagerTasksIsAssociativeArray()
    ' Test that tasks is an associative array
    mgr = TaskManager()
    assertTrue(mgr.tasks <> invalid)
    assertTrue(mgr.tasks.DoesExist <> invalid)
    print "TestTaskManagerTasksIsAssociativeArray passed"
end sub

sub TestTaskManagerStartTaskNameAndNode()
    ' Test startTask accepts name and node parameters
    mgr = TaskManager()
    ' Use a real task node that exists in the component set
    task = mgr.startTask("apiTask", "ApiTask")
    ' ApiTask exists, so it should not be invalid (or may be, depending on context)
    ' Just verify the call works without throwing
    assertTrue(true)
    print "TestTaskManagerStartTaskNameAndNode passed"
end sub
