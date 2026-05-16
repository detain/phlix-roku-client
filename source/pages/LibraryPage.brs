' source/pages/LibraryPage.brs

' ===========================================
' Library Page
' Displays items within a library
' ===========================================

sub Show(libraryId as String)
    ' Create library scene
    libraryScene = CreateObject("roSGNode", "LibraryScene")
    libraryScene.LoadLibrary(libraryId)
    m.top.ComponentController.SendEvent("show", { scene: libraryScene })
end sub