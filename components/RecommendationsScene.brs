' @copyright 2026 Joe Huss <detain@interserver.net>
' @license   MIT
' components/RecommendationsScene.brs

' copyright 2026 Joe Huss


sub Init()
    m.top.SetFocus(true)

    m.recommendationsList = m.top.FindNode("recommendationsList")
    m.loadingLabel = m.top.FindNode("loadingLabel")
    m.emptyLabel = m.top.FindNode("emptyLabel")

    if m.recommendationsList <> invalid then
        m.recommendationsList.ObserveField("itemSelected", "OnItemSelected")
    end if

    ' Route through ApiTask like other scenes
    m.apiTask = CreateObject("roSGNode", "ApiTask")
    m.apiTask.ObserveField("response", "OnApiResponse")

    LoadRecommendations()
end sub

sub LoadRecommendations()
    m.loadingLabel.visible = true
    m.emptyLabel.visible = false

    m.apiTask.request = { op: "getRecommendations", limit: 20 }
    m.apiTask.control = "run"
end sub

sub OnApiResponse(event as Object)
    resp = event.getData()
    if resp = invalid then return

    if resp.op = "getRecommendations" then
        OnRecommendationsResponse(resp)
    end if
end sub

sub OnRecommendationsResponse(resp as Object)
    m.loadingLabel.visible = false

    if resp.ok and resp.data <> invalid then
        recommendations = resp.data.recommendations

        if recommendations = invalid or recommendations.count() = 0 then
            m.emptyLabel.visible = true
            return
        end if

        content = CreateObject("roSGNode", "ContentNode")
        for each rec in recommendations
            item = CreateObject("roSGNode", "ContentNode")
            item.Title = rec.title
            item.Year = rec.year
            item.HDPosterUrl = rec.posterUrl
            item.Score = rec.score
            item.Id = rec.id
            content.AppendChild(item)
        end for

        if m.recommendationsList <> invalid then
            m.recommendationsList.content = content
        end if
    else
        m.emptyLabel.visible = true
    end if
end sub

sub OnItemSelected(event as Object)
    index = event.getData()
    if m.recommendationsList.content <> invalid then
        item = m.recommendationsList.content.GetChild(index)
        if item <> invalid then
            ' Navigate to player/detail with item.Id
            print "Selected recommendation: "; item.Title; " id: "; item.Id
        end if
    end if
end sub

sub OnKeyEvent(key as String, press as Boolean) as Boolean
    if press then
        if key = "back" then
            return true
        end if
    end if
    return false
end sub
