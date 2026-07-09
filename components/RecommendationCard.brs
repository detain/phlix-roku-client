' components/RecommendationCard.brs

' copyright 2026 Joe Huss


sub Init()
    m.top.SetFocus(false)
end sub

sub itemContentChanged()
    content = m.top.itemContent

    if content <> invalid then
        titleLabel = m.top.FindNode("titleLabel")
        yearLabel = m.top.FindNode("yearLabel")
        reasonBadge = m.top.FindNode("reasonBadge")
        scoreLabel = m.top.FindNode("scoreLabel")
        poster = m.top.FindNode("poster")

        if titleLabel <> invalid then
            titleLabel.text = content.Title
        end if

        if yearLabel <> invalid and content.Year <> invalid then
            yearLabel.text = str(content.Year).trim()
        end if

        if reasonBadge <> invalid then
            reasonBadge.text = "Because You Watched"
        end if

        if scoreLabel <> invalid and content.Score <> invalid then
            scoreLabel.text = str(int(content.Score * 100)) + "% match"
        end if

        if poster <> invalid then
            posterUrl = content.HDPosterUrl
            if posterUrl <> invalid and posterUrl <> "" then
                poster.uri = posterUrl
            end if
        end if
    end if
end sub

sub focusChanged()
    if m.top.HasFocus() then
        m.top.scale = 1.05
    else
        m.top.scale = 1.0
    end if
end sub
