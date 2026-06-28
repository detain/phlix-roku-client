' components/ApiTask.brs

' ===========================================
' ApiTask - generic SceneGraph Task node
' Runs ONE API operation on its own task thread so the blocking wait() in
' ApiClient.sendRaw no longer runs on the render thread. Scenes set the
' `request` assocarray, set control="run", and observe `response`.
'
' THREAD RULE: this function runs on the task thread; it may ONLY read its own
' m.top.request and write m.top.response. It must NOT touch UI/parent nodes.
' Only assocarray/string/number data crosses the thread boundary (ApiClient
' returns parsed-JSON assocarrays - safe).
' ===========================================

sub Init()
    m.top.functionName = "ExecRequest"
end sub

sub ExecRequest()
    req = m.top.request
    api = GetApiClient()
    result = { op: "", ok: false, data: invalid }

    if req <> invalid and req.op <> invalid then
        result.op = req.op

        if req.op = "getLibraries" then
            result.data = api.getLibraries()
            result.ok = (result.data <> invalid)
        else if req.op = "getLibraryItems" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getLibraryItems(req.libraryId, opts)
            result.ok = (result.data <> invalid)
        else if req.op = "getItem" then
            result.data = api.getItem(req.itemId)
            result.ok = (result.data <> invalid)
        else if req.op = "getItemPlaybackInfo" then
            result.data = api.getItemPlaybackInfo(req.itemId)
            result.ok = (result.data <> invalid)
        else if req.op = "startTranscode" then
            result.data = api.startTranscode(req.itemId)
            result.ok = (result.data <> invalid)
        else if req.op = "getTranscodeStatus" then
            result.data = api.getTranscodeStatus(req.jobId)
            result.ok = (result.data <> invalid)
        else if req.op = "createSession" then
            result.data = api.createSession()
            result.ok = (result.data <> invalid)
        else if req.op = "reportProgress" then
            result.data = api.reportProgress(req.mediaItemId, req.positionTicks, req.durationTicks, req.isPaused)
            result.ok = true
        else if req.op = "getContinueWatching" then
            result.data = api.getContinueWatching()
            result.ok = (result.data <> invalid)
        else if req.op = "search" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.search(req.query, opts)
            result.ok = (result.data <> invalid)
        else if req.op = "favorite" then
            result.data = api.addFavorite(req.itemId)
            result.ok = (result.data <> invalid)
        else if req.op = "unfavorite" then
            result.data = api.removeFavorite(req.itemId)
            result.ok = (result.data <> invalid)
        else if req.op = "setRating" then
            result.data = api.setRating(req.itemId, req.rating)
            result.ok = (result.data <> invalid)
        else if req.op = "clearRating" then
            result.data = api.clearRating(req.itemId)
            result.ok = (result.data <> invalid)
        else if req.op = "getFavorites" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getFavorites(opts)
            result.ok = (result.data <> invalid)
        else if req.op = "getArtists" then
            result.data = api.getArtists()
            result.ok = (result.data <> invalid)
        else if req.op = "getAlbums" then
            result.data = api.getAlbums()
            result.ok = (result.data <> invalid)
        else if req.op = "getAlbum" then
            result.data = api.getAlbum(req.albumName)
            result.ok = (result.data <> invalid)
        else if req.op = "getTracks" then
            opts = req.options
            if opts = invalid then opts = {}
            result.data = api.getTracks(opts)
            result.ok = (result.data <> invalid)
        else if req.op = "getPhotoAlbums" then
            result.data = api.getPhotoAlbums(req.libraryId)
            result.ok = (result.data <> invalid)
        else if req.op = "getPhotoAlbum" then
            result.data = api.getPhotoAlbum(req.albumId, req.libraryId)
            result.ok = (result.data <> invalid)
        else if req.op = "getCollections" then
            result.data = api.getCollections()
            result.ok = (result.data <> invalid)
        else if req.op = "getCollection" then
            result.data = api.getCollection(req.collectionId)
            result.ok = (result.data <> invalid)
        else if req.op = "getMe" then
            result.data = api.getMe()
            result.ok = (result.data <> invalid)
        else if req.op = "getAdminNowPlaying" then
            result.data = api.getAdminNowPlaying()
            result.ok = (result.data <> invalid)
        else if req.op = "getAdminStorage" then
            result.data = api.getAdminStorage()
            result.ok = (result.data <> invalid)
        else if req.op = "getAdminActivity" then
            limit = 20
            if req.DoesExist("limit") and req.limit <> invalid then limit = req.limit
            result.data = api.getAdminActivity(limit)
            result.ok = (result.data <> invalid)
        end if
    end if

    m.top.response = result
end sub
