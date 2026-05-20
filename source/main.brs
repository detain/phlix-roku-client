' main.brs

' ===========================================
' Phlix Media Server - Roku App
' Main entry point
' ===========================================

sub main(args as Object)
    print "Phlix Roku App Starting..."

    ' Create and show the main app component
    screen = CreateObject("roSGScreen")
    scene = screen.CreateScene("PhlixApp")
    screen.Show()

    ' Message loop
    while true
        msg = wait(0, screen.GetMessagePort())
        if msg = invalid then
            exit while
        end if
    end while

    print "Phlix Roku App Exiting..."
end sub