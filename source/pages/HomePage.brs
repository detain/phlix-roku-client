' source/pages/HomePage.brs

' ===========================================
' Home Page
' Displays library selection and quick access
' ===========================================

sub Show()
    ' Create home scene
    homeScene = CreateObject("roSGNode", "HomeScene")
    m.top.ComponentController.SendEvent("show", { scene: homeScene })
end sub