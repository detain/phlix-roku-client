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
            _pending: [],
            MAX_PENDING: 10,

            setScene: function(scene as Object) as Void
                ' M-ROKU-17r2 (r1 ask 3): wiring a scene drains whatever
                ' queued during the pre-attach window, in FIFO order.
                m._scene = scene
                queued = m._pending
                m._pending = []
                for each entry in queued
                    m.deliver(entry.text, entry.duration)
                end for
            end function,

            deliver: function(message as String, durationMs as Integer) as Void
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

            show: function(message as String, durationMs = 3000 as Integer) as Void
                ' M-ROKU-17r2 (review roku__gameux M2, r1 ask 3): the silent
                ' pre-attach drop is gone. A notice raised before this
                ' scope's singleton is wired to a scene queues here (cap
                ' MAX_PENDING, drop-OLDEST with a loud print - never silent)
                ' and drains the moment setScene lands. The root coordinator
                ' owns its own cap (5) above this door; the two are separate
                ' bounds on separate queues.
                if m._scene = invalid then
                    if m._pending.Count() >= m.MAX_PENDING then
                        dropped = m._pending.Shift()
                        print "Toast pre-attach queue overflow (cap " m.MAX_PENDING ") - dropped oldest notice:" dropped.text
                    end if
                    m._pending.Push({ text: message, duration: durationMs })
                    return
                end if

                m.deliver(message, durationMs)
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