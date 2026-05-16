' main.brs

' ===========================================
' Phlex Media Server - Roku App
' Main entry point
' ===========================================

sub main(args as Object)
    print "Phlex Roku App Starting..."

    ' Create and show the main app component
    screen = CreateObject("roSGScreen")
    scene = screen.CreateScene("PhlexApp")
    screen.Show()

    ' Message loop
    while true
        msg = wait(0, screen.GetMessagePort())
        if msg = invalid then
            exit while
        end if
    end while

    print "Phlex Roku App Exiting..."
end sub