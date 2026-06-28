' source/components/HomeScene.brs

sub Init()
    m.top.SetFocus(true)

    ' Create poster grid
    m.posterGrid = m.top.FindNode("libraryGrid")
    m.posterGrid.ObserveField("itemSelected", "OnItemSelected")
    m.posterGrid.ObserveField("itemFocused", "OnItemFocused")

    m.descriptionLabel = m.top.FindNode("descriptionLabel")

    ' Route all data access through the ApiTask node (off the render thread).
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    ' Load libraries on init
    LoadLibraries()
end sub

sub LoadLibraries()
    m.apiTask.request = { op: "getLibraries" }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getLibraries" then
        if not resp.ok or resp.data = invalid then return

        ' Build the grid from each library's canonical name/id.
        content = CreateObject("roSGNode", "ContentNode")
        for each library in resp.data
            content.AddChild({
                Title: library.name
                Description: "Library"
                HDPosterUrl: "pkg:/images/placeholder.png"
                ShortDescriptionLine1: library.name
                Type: "library"
                id: library.id
            })
        end for
        m.posterGrid.content = content
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()
    content = m.posterGrid.content.GetChild(index)
    if content = invalid then return

    if content.Type = "library" then
        ShowLibrary(content.id, content.Title)
    else
        ShowItemDetail(content.id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()
    content = m.posterGrid.content.GetChild(index)
    if content = invalid then return

    if m.descriptionLabel <> invalid then
        m.descriptionLabel.text = content.ShortDescriptionLine1
    end if
end sub

sub ShowLibrary(libraryId as String, libraryName as String)
    scene = CreateObject("roSGNode", "LibraryScene")
    m.top.Append(scene)
    scene.LoadLibrary(libraryId, libraryName)
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    m.top.Append(scene)
    scene.LoadItem(itemId)
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false
    return handled
end sub
