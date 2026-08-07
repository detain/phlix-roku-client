' R3.4: Generalized toast/notification system for background errors
' Singleton accessible via GetToastManager()

function GetToastManager()
    if m._toastManager = invalid then
        m._toastManager = {
            _toasts: [],
            _scene: invalid,

            setScene: function(scene as Object) as Void
                m._scene = scene
            end function,

            show: function(message as String, durationMs = 3000 as Integer) as Void
                if m._scene = invalid then return

                ' Create toast content node
                content = CreateObject("roSGNode", "ContentNode")
                content.title = message
                content.duration = durationMs

                ' Post to the scene's controller
                m._scene.PostMessage("showToast", content)
            end function,

            showError: function(message as String) as Void
                m.show("[ERROR] " + message, 5000)
            end function,

            showWarning: function(message as String) as Void
                m.show("[WARNING] " + message, 4000)
            end function,

            showInfo: function(message as String) as Void
                m.show(message, 3000)
            end function
        }
    end if
    return m._toastManager
end function