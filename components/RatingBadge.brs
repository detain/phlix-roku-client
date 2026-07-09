' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT

' components/RatingBadge.brs

' copyright 2026 Joe Huss
'
'
' RatingBadge component - displays a star icon with an aggregate score (0-10 scale)
' Used to show the average rating for a media item.

sub Init()
    m.top.width = 160
    m.top.height = 50
    m.top.color = "#1a1a2e"

    m.starLabel = m.top.FindNode("starLabel")
    m.scoreLabel = m.top.FindNode("scoreLabel")

    ' Initialize with default values
    if m.top.score = invalid then
        m.top.score = 0
    end if
end sub

sub OnScoreChange()
    score = m.top.score

    ' Guard: invalid or out-of-range scores show as "N/A"
    if score = invalid or score < 0 or score > 10 then
        if m.scoreLabel <> invalid then
            m.scoreLabel.text = "N/A"
        end if
        return
    end if

    ' Format score to one decimal place and display as "X.X/10"
    if m.scoreLabel <> invalid then
        m.scoreLabel.text = str(score).trim() + "/10"
    end if

    ' Color the star based on score range:
    ' 0-4:   red (#FF4444)
    ' 4-7:   orange (#FF6B35)
    ' 7-10:  bright yellow/gold (#FFD700)
    if m.starLabel <> invalid then
        if score < 4 then
            m.starLabel.color = "#FF4444"
        else if score < 7 then
            m.starLabel.color = "#FF6B35"
        else
            m.starLabel.color = "#FFD700"
        end if
    end if
end sub
