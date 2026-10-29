# Screen Navigation Stack

## Overview

PhlixApp uses a **screen stack** to manage navigation between scenes. This replaces the
previous pattern where child scenes called `m.top.Close()` (which does not exist on
`Scene` or `Group` nodes and causes runtime error `&hF4`).

## The Problem with `m.top.Close()`

`Close()` is a method on `roSGScreen`, not on `Scene` or `Group` nodes. None of the
Phlix components declare a `Close` function in their `<interface>`, so calling
`m.top.Close()` from any child scene produces error `&hF4` ("Member function not found")
every time the user presses Back.

Additionally, the pre-stack back handler (`PhlixApp.OnKeyEvent`) called
`m.top.RemoveChild()` without calling `SetFocus(true)` on the newly-exposed node.
After one Back press, the remote control became unresponsive because the newly-visible
scene never received focus.

**Status: Fixed in R0.4 (signal side); contract completed by C03/C03-r2 (observer
side, 2026-10-28/29).** The migration replaced all 34 `m.top.Close()` calls with
`m.top.requestClose = true` and added the `requestClose` field to all relevant
XMLs — but the parent half (observers actually removing the child) stayed broken
until C03. See the Back/Close contract note under Known Limitations below for
the final state.

## The Screen Stack

### PushScreen(nodeType as String, params as Object) as Object

Creates a child scene, appends it to `m.top`, sets focus on it, records it on the
stack, and returns it. The caller is responsible for calling any setup methods
(like `LoadLibrary`, `Show`) on the returned node after `PushScreen` returns.

```brightscript
sub ShowLibrary(libraryId as String, libraryName as String)
    scene = PushScreen("LibraryScene", {})
    scene.LoadLibrary(libraryId, libraryName)
end sub
```

### PopScreen() as Boolean

Removes the top scene from the stack, removes it from `m.top`, calls `SetFocus(true)`
on the newly-exposed node (fixing the dead-remote bug), and returns `true`. Returns
`false` when the stack is empty, signaling that the channel should exit — and
(M-ROKU-01) `OnKeyEvent` acts on that signal instead of forwarding the raw false
to the OS:

```brightscript
' In OnKeyEvent:
if key = "back" then
    handled = PopScreen()
    if not handled then
        m.top.exitChannel = true   ' observed by main.brs, which ends main(): clean exit
        handled = true             ' consume — never fall through to RSG's native close
    end if
end if
return handled
```

### The requestClose Contract

Every child scene declares a `requestClose` field in its `<interface>`:

```xml
<interface>
    <field id="requestClose" type="boolean" alwaysNotify="true" />
    <!-- other fields and functions -->
</interface>
```

When a scene needs to close itself (e.g., a Back button handler inside the scene),
it sets:

```brightscript
m.top.requestClose = true
```

`PhlixApp` observes this field on every pushed node. When it fires, `PopScreen()`
is called automatically. This lets a child scene request removal **without**
knowing its parent or having a reference to `PhlixApp`.

Scenes opened from **HomeScene** (and every nested parent) are not on that stack:
they are appended by their parent scene, which observes the child's `requestClose`
and removes it locally (`event.GetNode()` + `RemoveChild` + `SetFocus`), the
parent-side mirror of `PopScreen`. The signal is never re-bubbled upward —
`scripts/verify-runtime.sh` CHECK27 fails loud on a bubble-style handler.
Scenes that also self-observe their own `requestClose` treat a self-fired event
as "our parent is removing us": they run their local `Teardown()` and return.

`alwaysNotify="true"` ensures the observer fires even when the value is set to
`true` multiple times (important for scenes that may set it during `Init`).

## Bootstrap Flow vs. the Stack

The initial screens (Connect, Login, ServerPicker, Home) are **bootstrap scenes** that
are managed by `Show*` methods and `On*` handlers, NOT by the screen stack. They are
direct children of `m.top` and are removed/added by explicit `RemoveChild` calls in
the transition handlers.

The screen stack is used for **pushed screens** — scenes that are opened on top of
HomeScene (Library, Detail, Player, Search, etc.).

When the stack is empty and the user presses Back, `PopScreen()` returns `false`.
The earlier implementation returned that `false` verbatim and claimed "the Roku OS
handles the back press and exits the channel" — that was fiction: with nested child
scenes (this channel's bootstrap screens are appended children of the root, not the
root itself), RSG's native back handling closes only the FOCUSED scene. The user saw
the root's black boot chrome as a dead screen and needed a second Back to actually
exit (review roku__casualgamer M2). The shipped law (M-ROKU-01, CHECK31):
`OnKeyEvent` consumes the key at stack-bottom and raises the root's
`exitChannel` field; `main.brs` observes it on the screen message port and ends
`main()`, which is the SceneGraph-correct channel exit (the official Roku component
library has no creatable `roApp.Exit()`). One Back from Home — or from any other
bootstrap screen — exits cleanly with no intermediate black frame.

## Architectural Note: Nested Scenes

All 42 child components in this channel `extend="Scene"` and are added as children
of other Scene nodes via `CreateObject("roSGNode", "XScene")` + `m.top.Append(scene)`.
This is **not idiomatic Roku**: SceneGraph expects a single root `Scene` with `Group`
nodes as children, not nested `Scene` nodes. The stack mechanism works correctly
with the nested-Scene pattern, but a future refactor should consider flattening to
the idiomatic `Group`-as-child pattern. That refactor is deliberately out of scope
for this step to keep the diff reviewable.

## Known Limitations

### Back/Close contract (C03 — fixed 2026-10-28, reworked 2026-10-29)

The parent-side removal above replaced the old bubble-up contract (C03,
2026-10-28). Before that fix, every parent `OnChildRequestClose` handler
re-bubbled `m.top.requestClose = true` and the chain silently died at
HomeScene — Back was a no-op on every screen opened from Home, and the
"un-wired parent scenes" gap listed here earlier was this dead bubble
contract. The round-1 claim that the fix closed Back for every Home-opened
screen was wrong: RecommendationsScene ("For You") swallowed Back without
ever firing `requestClose`, so no parent machinery could close it — for that
one screen it genuinely WAS a wiring gap, fixed in C03-r2. All 23 parent
handlers (the 22 C03 files plus PlayerScene's pre-existing R7.2 handler) now
remove the requesting child locally, and LibraryScene's self-fired
`Teardown()` no longer unobserves `requestClose` mid-dispatch (that unobserve
could prune the parent's pending removal). `scripts/verify-runtime.sh`
CHECK27 pins both halves of the contract: R1-R3 police the handler bodies
(local removal, no bubble), R4 requires every `requestClose` observer to name
a handler the observing component defines, R5 requires every observed child
scene to fire `requestClose = true` itself, and R6 forbids unobserving
`requestClose` inside `Teardown`. Bootstrap scenes (Connect, Login,
ServerPicker) still transition via their own events and remain outside the
stack, as documented above.
