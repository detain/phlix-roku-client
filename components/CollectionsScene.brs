' components/CollectionsScene.brs
'
' Collections browser: a one-shot LabelList of collection NAMES (collections have
' no artwork). Mirrors MusicScene's LabelList + ApiTask + OnApiResponse idiom,
' minus the mode buttons - the load fires once on Init via the `getCollections`
' op (ApiClient.getCollections -> GET /collections). Selecting a row opens that
' collection's items in a CollectionScene (PosterGrid, type-routed). HomeScene
' self-creates + focuses this scene, so it has NO <interface>.

sub Init()
    m.top.SetFocus(true)

    ' Text list (collections have no artwork).
    m.collectionsList = m.top.FindNode("collectionsList")
    if m.collectionsList <> invalid then
        m.collectionsList.ObserveField("itemSelected", "OnRowSelected")
        m.collectionsList.ObserveField("itemFocused", "OnRowFocused")
        m.collectionsList.SetFocus(true)
    end if

    m.statusLabel = m.top.FindNode("statusLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    m.collections = []

    SetStatus("Loading…")

    ' One-shot load on Init.
    m.apiTask.request = { op: "getCollections" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getCollections" then
        m.collections = []
        if resp.ok and resp.data <> invalid and resp.data.collections <> invalid and type(resp.data.collections) = "roArray" then
            m.collections = resp.data.collections
        end if

        content = CreateObject("roSGNode", "ContentNode")
        for each collection in m.collections
            if collection <> invalid then
                title = ""
                if collection.DoesExist("name") and collection.name <> invalid then title = collection.name
                content.AddChild({ title: title })
            end if
        end for

        if m.collectionsList <> invalid then m.collectionsList.content = content

        if m.collections.Count() = 0 then
            SetStatus("No collections")
        else
            SetStatus("")
        end if
    end if
end sub

sub SetStatus(text as String)
    if m.statusLabel <> invalid then m.statusLabel.text = text
end sub

sub OnRowSelected(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.collections.Count() then return

    collection = m.collections[index]
    if collection = invalid then return

    id = ""
    if collection.DoesExist("id") and collection.id <> invalid then id = collection.id
    name = ""
    if collection.DoesExist("name") and collection.name <> invalid then name = collection.name

    if id <> "" then ShowCollection(id, name)
end sub

sub OnRowFocused(event as Object)
    index = event.getData()
    if index = invalid then return
    if index < 0 or index >= m.collections.Count() then return

    collection = m.collections[index]
    if collection = invalid then return

    ' Coerce to String before SetStatus (its param is `as String`); the contract
    ' guarantees a String name but a non-String would otherwise crash the call.
    if collection.DoesExist("name") and collection.name <> invalid then
        nm = collection.name
        if type(nm) = "String" or type(nm) = "roString" then SetStatus(nm)
    end if
end sub

sub ShowCollection(collectionId as String, collectionName as String)
    name = collectionName
    if name = invalid then name = ""

    scene = CreateObject("roSGNode", "CollectionScene")
    m.top.Append(scene)
    scene.LoadCollection(collectionId, name)
end sub

' Pair every ObserveField with an UnObserveField so the scene does not leak.
sub Teardown()
    if m.collectionsList <> invalid then
        m.collectionsList.UnObserveField("itemSelected")
        m.collectionsList.UnObserveField("itemFocused")
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
