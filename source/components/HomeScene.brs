' source/components/HomeScene.brs

sub Init()
    m.top.SetFocus(true)

    ' Create poster grid
    m.posterGrid = m.top.FindNode("libraryGrid")
    m.posterGrid.ObserveField("itemSelected", "OnItemSelected")
    m.posterGrid.ObserveField("itemFocused", "OnItemFocused")

    ' Load libraries on init
    LoadLibraries()
end sub

sub LoadLibraries()
    libraries = api.getLibraries()

    if libraries = invalid then
        return
    end if

    ' Create content node for grid
    content = CreateObject("roSGNode", "ContentNode")

    for each library in libraries
        item = content.AddChild({
            Title: library.name
            Description: "Library"
            HDPosterUrl: "pkg:/images/placeholder.png"
            ShortDescriptionLine1: library.name
            Type: "library"
            id: library.id
        })
    end for

    m.posterGrid.content = content
end sub

sub OnItemSelected(event as Object)
    index = event.getData()
    content = m.posterGrid.content.GetChild(index)

    if content.Type = "library" then
        ' Navigate to library
        ShowLibrary(content.id)
    else
        ' Navigate to item detail
        ShowItemDetail(content.id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()
    content = m.posterGrid.content.GetChild(index)

    ' Show item description
    if m.descriptionLabel <> invalid then
        m.descriptionLabel.text = content.ShortDescriptionLine1
    end if
end sub

sub ShowLibrary(libraryId as String)
    scene = CreateObject("roSGNode", "LibraryScene")
    scene.LoadLibrary(libraryId)
    m.top.Append(scene)
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    scene.LoadItem(itemId)
    m.top.Append(scene)
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false
    return handled
end sub