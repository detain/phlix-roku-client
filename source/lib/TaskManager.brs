' source/lib/TaskManager.brs

' ===========================================
' Task Manager for Roku
' Manages background tasks and async operations
' ===========================================

function TaskManager() as Object
    obj = {
        tasks: {}

        ' Create and start a task
        startTask: function(taskName as String, taskNode as String) as Object
            task = CreateObject("roSGNode", taskNode)
            if task <> invalid then
                task.control = "run"
                m.tasks[taskName] = task
            end if
            return task
        end function

        ' Stop a task
        stopTask: function(taskName as String)
            if m.tasks.DoesExist(taskName) then
                task = m.tasks[taskName]
                task.control = "stop"
                m.tasks.Delete(taskName)
            end if
        end function

        ' Get task by name
        getTask: function(taskName as String) as Object
            if m.tasks.DoesExist(taskName) then
                return m.tasks[taskName]
            end if
            return invalid
        end function

        ' Stop all tasks
        stopAllTasks: function()
            for each taskName in m.tasks
                m.stopTask(taskName)
            end for
        end function
    }

    return obj
end function