' source/components/GridItem.brs

sub Init()
    m.top.SetFocus(false)
end sub

sub itemContentChanged()
    ' Update UI based on content
    content = m.top.itemContent

    if content <> invalid then
        if m.top.DoesExist("titleLabel") then
            m.top.FindNode("titleLabel").text = content.Title
        end if

        if m.top.DoesExist("posterImage") then
            posterUrl = content.HDPosterUrl
            if posterUrl <> invalid and posterUrl <> "" then
                m.top.FindNode("posterImage").uri = posterUrl
            end if
        end if
    end if
end sub

sub focusChanged()
    ' Update appearance for focus state
    if m.top.HasFocus() then
        m.top.scale = 1.05
    else
        m.top.scale = 1.0
    end if
end sub