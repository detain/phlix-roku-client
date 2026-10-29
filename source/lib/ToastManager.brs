' R3.4: Generalized toast/notification system for background errors
' Singleton accessible via GetToastManager()
'
' M-ROKU-17 (review roku__gameux M2) scope law: BrightScript m is per
' component-script-scope, so EVERY component that script-includes this file
' owns its own manager instance — a scope must setScene(its m.top) before
' show() delivers anything (this is why PlayerScene's progress warning was
' silently dead: nobody ever wired that scope's singleton). Delivery always
' lands on the root scene component, which is the channel's sole onMessage
' coordinator; the stored scene only has to be a node in this channel's
' tree, and the PostMessage below finds the root by walking the documented
' GetParent chain (consumer scenes nest to arbitrary depth — PlayerScene
' rides under DetailScene when pushed from there).
' The pre-fix era posted straight to the stored scene; combined with the
' fabricated ComponentController write in the root handler, the pipeline
' could not display from any caller.

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
                target = m._scene
                parent = target.GetParent()
                while parent <> invalid
                    target = parent
                    parent = target.GetParent()
                end while
                target.PostMessage("showToast", content)
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