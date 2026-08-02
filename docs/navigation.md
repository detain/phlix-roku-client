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

**Status: Fixed in R0.4.** The migration replaced all 34 `m.top.Close()` calls with
`m.top.requestClose = true`. The `requestClose` field was added to all relevant XMLs and
8 primary parent scenes are wired. See the Known Limitation note in CHANGELOG.md for the
remaining gap.

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
`false` when the stack is empty, signaling that the channel should exit.

```brightscript
' In OnKeyEvent:
if key = "back" then
    handled = PopScreen()
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

`alwaysNotify="true"` ensures the observer fires even when the value is set to
`true` multiple times (important for scenes that may set it during `Init`).

## Bootstrap Flow vs. the Stack

The initial screens (Connect, Login, ServerPicker, Home) are **bootstrap scenes** that
are managed by `Show*` methods and `On*` handlers, NOT by the screen stack. They are
direct children of `m.top` and are removed/added by explicit `RemoveChild` calls in
the transition handlers.

The screen stack is used for **pushed screens** — scenes that are opened on top of
HomeScene (Library, Detail, Player, Search, etc.).

When the stack is empty and the user presses Back, `PopScreen()` returns `false`,
which causes `OnKeyEvent` to return `false`, allowing the Roku OS to handle the
back press and exit the channel. This fixes certification item 6: the previous
implementation never exited the channel because it swallowed Back at the root.

## Architectural Note: Nested Scenes

All 42 child components in this channel `extend="Scene"` and are added as children
of other Scene nodes via `CreateObject("roSGNode", "XScene")` + `m.top.Append(scene)`.
This is **not idiomatic Roku**: SceneGraph expects a single root `Scene` with `Group`
nodes as children, not nested `Scene` nodes. The stack mechanism works correctly
with the nested-Scene pattern, but a future refactor should consider flattening to
the idiomatic `Group`-as-child pattern. That refactor is deliberately out of scope
for this step to keep the diff reviewable.

## Known Limitations

### Un-wired parent scenes (~13 remaining)

Approximately 13 parent scenes (~21 `m.top.Append` calls) are **not yet wired** with an
`ObserveField("requestClose", "OnChildRequestClose")` handler. Child scenes in those
branches that call `m.top.requestClose = true` will have the signal silently ignored.

Affected branches include:
- `SearchScene` → `SeriesScene` / `SeasonScene` / `DetailScene`
- `WatchHistoryScene` → `…`
- And others listed in `CHANGELOG.md` under the R0.4 fix entry.

This is a **pre-existing gap** — not a regression introduced by R0.4. R0.4 wired the
8 primary parent scenes (HomeScene, FavoritesScene, MusicScene, AdminScene,
CollectionsScene, DetailScene, LibraryAdminScene, LiveTvScene). Future work should
wire the remaining branches.
