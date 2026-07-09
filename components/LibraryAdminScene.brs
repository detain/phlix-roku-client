'@copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/LibraryAdminScene.brs

' copyright 2026 Joe Huss
'

'
' Libraries admin list: a one-shot LabelList of the server's libraries. Mirrors
' CollectionsScene's LabelList + ApiTask + OnApiResponse idiom - the load fires
' once on Init via the `getLibraries` op. Selecting a row opens that library's
' per-library actions (Scan / Rescan / Match Metadata / Refresh Status) in a
' LibraryAdminActionsScene. AdminScene self-creates + focuses this scene, so it
' has NO <interface>.
'
' NOTE: ApiClient.getLibraries() returns the libraries ARRAY directly (NOT a
' {libraries} envelope - it unwraps server-side), so OnApiResponse reads
' resp.data directly and checks type(resp.data) = "roArray" (different from
' CollectionsScene, which reads resp.data.collections).

sub Init()
    m.top.SetFocus(true)

    ' Text list of libraries.
    m.libraryList = m.top.FindNode("libraryList")
    if m.libraryList <> invalid then
        m.libraryList.ObserveField("itemSelected", "OnRowSelected")
        m.libraryList.ObserveField("itemFocused", "OnRowFocused")
        m.libraryList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.libraries = []

    SetStatus("Loading…")

    ' One-shot load on Init.
    m.apiTask.request = { op: "getLibraries" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getLibraries" then
        ' getLibraries() returns the ARRAY directly (NOT {libraries}).
        m.libraries = []
        if resp.ok and resp.data <> invalid and type(resp.data) = "roArray" then
            m.libraries = resp.data
        end if

        content = CreateObject("roSGNode", "ContentNode")
        for each library in m.libraries
            if library <> invalid then
                content.AddChild({ title: LibraryRowCaption(library) })
            end if
        end for

        if m.libraryList <> invalid then m.libraryList.content = content

        if m.libraries.Count() = 0 then
            SetStatus("No libraries")
        else
            SetStatus("")
        end if
    end if
end sub

' Caption for a library row: "<name>  (<type>)" when a type is present, else
' just the name. All fields here are Strings - guard DoesExist + invalid + "".
function LibraryRowCaption(lib as Object) as String
    if lib = invalid then return ""

    name = ""
    if lib.DoesExist("name") and lib.name <> invalid then name = lib.name

    if lib.DoesExist("type") and lib.type <> invalid and lib.type <> "" then
        return name + "  (" + lib.type + ")"
    end if

    return name
end function

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.libraries.Count() then return

    library = m.libraries[index]
    if library = invalid then return

    id = ""
    if library.DoesExist("id") and library.id <> invalid then id = library.id
    name = ""
    if library.DoesExist("name") and library.name <> invalid then name = library.name

    if id <> "" then ShowActions(id, name)
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.libraries.Count() then return

    library = m.libraries[index]
    if library = invalid then return

    SetStatus(LibraryRowCaption(library))
end sub

' Open the per-library actions surface (Scan/Rescan/Match/Refresh). Coerce an
' invalid name to "" before crossing the interface (LoadLibrary is typed String).
sub ShowActions(libraryId as String, libraryName as String)
    name = libraryName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "LibraryAdminActionsScene")
    m.top.Append(scene)
    scene.LoadLibrary(libraryId, name)
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.libraryList <> invalid then
        m.libraryList.UnObserveField("itemSelected")
        m.libraryList.UnObserveField("itemFocused")
    end if
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