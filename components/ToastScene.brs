sub init()
    m.toastLabel = m.top.FindNode("toastLabel")
    m.toastLabel.text = m.top.message

    m.top.ObserveField("message", "OnMessageChange")

    ' Auto-dismiss after duration
    m.timer = CreateObject("roSGNode", "Timer")
    m.timer.ObserveField("fire", "OnTimerFire")
    m.timer.duration = m.top.duration / 1000.0
    m.timer.control = "start"
end sub

sub OnMessageChange(event as Object)
    m.toastLabel.text = event.getData()
end sub

sub OnTimerFire(event as Object)
    m.top.close = true
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    if press and (key = "back" or key = "OK") then
        m.top.close = true
        return true
    end if
    return false
end sub