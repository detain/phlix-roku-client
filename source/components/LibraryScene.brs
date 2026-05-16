' source/components/LibraryScene.brs

sub Init()
    m.top.SetFocus(true)

    ' Create poster grid for items
    m.posterGrid = m.top.FindNode("itemsGrid")
    m.posterGrid.ObserveField("itemSelected", "OnItemSelected")
    m.posterGrid.ObserveField("itemFocused", "OnItemFocused")

    ' UI nodes
    m.backButton = m.top.FindNode("backButton")
    m.titleLabel = m.top.FindNode("titleLabel")

    if m.backButton <> invalid then
        m.backButton.ObserveField("buttonSelected", "OnBackPressed")
    end if

    m.libraryId = ""
    m.items = []
end sub

sub LoadLibrary(libraryId as String)
    m.libraryId = libraryId

    ' Get library info
    library = api.getItem(libraryId)
    if library <> invalid and m.titleLabel <> invalid then
        m.titleLabel.text = library.Name
    end if

    ' Load items
    RefreshItems()
end sub

sub RefreshItems()
    if m.libraryId = "" then
        return
    end if

    items = api.getLibraryItems(m.libraryId)

    if items = invalid or items.Items = invalid then
        return
    end if

    m.items = items.Items

    ' Create content node for grid
    content = CreateObject("roSGNode", "ContentNode")

    for each item in m.items
        contentItem = content.AddChild({
            Title: item.Name
            Description: item.Overview
            HDPosterUrl: "pkg:/images/placeholder.png"
            ShortDescriptionLine1: item.Name
            ShortDescriptionLine2: item.ProductionYear
            Type: item.Type
            id: item.Id
        })

        ' Use poster thumbnail if available
        if item.ImageTags <> invalid and item.ImageTags.Primary <> invalid then
            contentItem.HDPosterUrl = api.baseUrl + "/Items/" + item.Id + "/Images/Primary"
        end if
    end for

    m.posterGrid.content = content
end sub

sub OnItemSelected(event as Object)
    index = event.getData()

    if index < 0 or index >= m.items.Count() then
        return
    end if

    item = m.items[index]

    if item.Type = "Folder" or item.Type = "CollectionFolder" then
        ' Navigate to sub-folder
        ShowSubFolder(item.Id, item.Name)
    else
        ' Navigate to item detail
        ShowItemDetail(item.Id)
    end if
end sub

sub OnItemFocused(event as Object)
    index = event.getData()

    if index >= 0 and index < m.items.Count() then
        item = m.items[index]
        if m.descriptionLabel <> invalid then
            if item.Overview <> invalid then
                m.descriptionLabel.text = item.Overview
            else
                m.descriptionLabel.text = item.Name
            end if
        end if
    end if
end sub

sub ShowSubFolder(folderId as String, folderName as String)
    scene = CreateObject("roSGNode", "LibraryScene")
    scene.LoadLibrary(folderId)
    scene.SetTitle(folderName)
    m.top.Append(scene)
end sub

sub ShowItemDetail(itemId as String)
    scene = CreateObject("roSGNode", "DetailScene")
    scene.LoadItem(itemId)
    m.top.Append(scene)
end sub

sub SetTitle(title as String)
    if m.titleLabel <> invalid then
        m.titleLabel.text = title
    end if
end sub

sub OnBackPressed()
    m.top.Close()
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    handled = false

    if press then
        if key = "back" then
            m.top.Close()
            handled = true
        end if
    end if

    return handled
end sub