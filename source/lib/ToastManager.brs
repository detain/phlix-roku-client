' R3.4: Generalized toast/notification system for background errors
' Singleton accessible via GetToastManager()
'
' M-ROKU-17 (review roku__gameux M2) scope law: BrightScript m is per
' component-script-scope, so EVERY component that script-includes this file
' owns its own manager instance — a scope must setScene(its m.top) before
' show() delivers anything (this is why PlayerScene's progress warning was
' silently dead: nobody ever wired that scope's singleton). Delivery always
' lands on the root scene component, which is the channel's sole toast
' coordinator; the stored scene only has to be a node in this channel's
' tree, and the walk below finds the root by the documented GetParent chain
' (consumer scenes nest to arbitrary depth — PlayerScene rides under
' DetailScene when pushed from there).
'
' M-ROKU-17 r2 (review roku__gameux M17r1 CRITICAL-1) dispatch law: delivery
' rides the root scene's OBSERVED INTERFACE FIELDS — the proven render-thread
' channel this repo ships everywhere: child scenes flip their own
' requestClose interface field and the coordinator arm collects it via
' ObserveField, and ShowErrorDialog rides the same observe-by-name mechanics
' for wasClosed. deliver() writes the notice as plain String + Integer
' payload fields on the walked root node, then bumps the alwaysNotify
' toastSeq trigger; PhlixApp's Init wires that trigger to its OnToastNotice
' dispatch arm, which enqueues. The R3.4 wire is RETIRED, not repaired:
' node.PostMessage to an onMessage handler is no articulable RokuOS node
' contract — bsc's vendored Roku types (the component-library authority this
' channel lints against; brighterscript/dist/roku-types/data.json) model
' PostMessage exactly once, on roRenderThreadQueue, whose documented receive
' path is AddMessageHandler — used nowhere here, and none of this repo's
' seven Task components rides onMessage either — so the old sender bound
' nothing to any roSGNode receive contract and the notices died at the wire.
' The copy stays app-side static and String-typed at every hop
' (ROKU-12/CHECK43 law intact).

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
                ' Deliver on the root scene's observed toast channel
                ' (M-ROKU-17 r2): walk up, write the payload, bump the
                ' trigger LAST so the coordinator never observes a half-
                ' written notice. The DoesExist guard keeps a foreign root
                ' (a tree that is not this channel's PhlixApp scene) a
                ' silent no-op, matching the invalid-scene posture in show.
                target = m._scene
                parent = target.GetParent()
                while parent <> invalid
                    target = parent
                    parent = target.GetParent()
                end while
                if not target.DoesExist("toastSeq") then return
                target.toastMessage = message
                target.toastDuration = durationMs
                target.toastSeq = target.toastSeq + 1
            end function,

            show: function(message as String, durationMs = 3000 as Integer) as Void
                ' M-ROKU-17r2 (review roku__gameux M17r1, r1 ask 3): the
                ' silent pre-attach drop is gone. A notice raised before
                ' this scope's singleton is wired to a scene queues here
                ' (cap MAX_PENDING, drop-OLDEST with a loud print - never
                ' silent) and drains the moment setScene lands. The root
                ' coordinator owns its own cap (5) above this door; the two
                ' are separate bounds on separate queues.
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
