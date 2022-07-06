function init()
  m.device = CreateObject("roDeviceInfo")
  m.category_screen = m.top.findNode("category_screen")
  m.content_screen = m.top.findNode("content_screen")
  m.details_screen = m.top.findNode("details_screen")
  m.login_screen = m.top.findNode("login_screen")
  m.streamCheckTimer = m.top.findNode("stream_timer")

  m.feedpage = 0
  m.default_edge = "Edge01-na.floatplane.com"
  m.live = false
  m.playButtonPressed = false

  m.videoplayer = m.top.findNode("videoplayer")

  m.login_screen.observeField("next", "onNext")
  m.category_screen.observeField("category_selected", "onCategorySelected")
  m.content_screen.observeField("content_selected", "onContentSelected")
  m.content_screen.observeField("itemIndex", "onItemFocus")
  m.details_screen.observeField("play_button_pressed", "onPlayButtonPressed")
  m.streamCheckTimer.observeField("fire","checkStream")

  m.itemFocus = 0

  m.supported = m.device.GetSupportedGraphicsResolutions()
  
  m.arrutil = ArrayUtil()

  registry = RegistryUtil()
  if registry.read("sails", "hydravion") <> invalid then
    'Check whether cookies are set, if not we login. If found, we head over to onNext()
    onNext("test")
    'Signal that we are logged in and we have completed launch
    'm.top.signalBeacon("AppDialogComplete")
  end if

  'Signal that launch is complete
  'sleep(200)
  m.top.signalBeacon("AppLaunchComplete")
end function

sub onDeepLinking(obj)
  'showTestDialog()
  m.videoplayer.notificationInterval = 1
  m.videoplayer.observeField("position", "onPlayerPositionChanged")
  m.videoplayer.observeField("state", "onPlayerStateChanged")
  videoContent = createObject("roSGNode", "ContentNode")
  videoContent.url = "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
  videoContent.StreamFormat = "mp4"
  m.videoplayer.visible = true
  m.videoplayer.setFocus(true)
  m.videoplayer.content = videoContent
  m.videoplayer.control = "play"
  'Required for deep linking
  m.top.signalBeacon("AppLaunchComplete")
end sub

sub onRowInput(obj)
  '? "onRowInputEvent: " + obj.getData()
end sub

sub onNext(obj)
  m.login_screen.visible = false
  'Now that we have cookies, we can initialize the video/live player
  initializeVideoPlayer()

  showUpdateDialog()

  registry = RegistryUtil()
  if type(obj) <> "String"
    'Get Edge Servers
    'm.edge_task = CreateObject("roSGNode", "edgesUrlTask")
    'm.edge_task.observeField("response", "onEdges")
    'edges = "https://www.floatplane.com/api/edges"
    'm.edge_task.setField("url", edges)
    'm.edge_task.control = "RUN"
    registry.write("edge", "edge03-na.floatplane.com", "hydravion")
    getSubs("")
  else
  ''  if registry.read("edge", "hydravion") = invalid then
  ''    registry.write("edge", "Edge03-na.floatplane.com", "hydravion")
  ''  end if
    getSubs("")
  end if
  if registry.read("edge", "hydravion") = invalid then
    registry.write("edge", "edge03-na.floatplane.com", "hydravion")
  end if
end sub

sub onEdges(obj)
  'Find best edge server
  m.edges = obj.getData()
  m.best_edge = CreateObject("roSGNode", "edgesTask")
  m.best_edge.observeField("bestEdge", "bestEdge")
  m.best_edge.setField("edges", obj.getData())
  m.best_edge.control = "RUN"
end sub

sub bestEdge(obj)
  'Got best edge, set best edge
  registry = RegistryUtil()
  edge = obj.getData()
  if edge = "" then
    'Edge didn't return, so let's just use the default
    registry.write("edge", m.default_edge, "hydravion")
  else if edge.Instr(m.default_edge) > -1 then
    'Edge found, not default, so let's use it
    registry.write("edge", m.default_edge, "hydravion")
  else
    'In case something else happens, just use the default
    registry.write("edge", edge, "hydravion")
  end if
  'Get subs
  getSubs(obj)
end sub

sub getSubs(obj)
  m.subs_task = CreateObject("roSGNode", "urlTask")
  url = "https://www.floatplane.com/api/v3/user/subscriptions"
  m.subs_task.setField("url", url)
  m.subs_task.observeField("response", "onSubs")
  m.subs_task.control = "RUN"
end sub

sub onSubs(obj)
  m.top.subscriptions = obj.getData()
  m.category_screen.visible = true
  m.category_screen.setFocus(true)
end sub

sub onCategoryResponse(obj)
  m.feed_task = createObject("roSGNode", "setupCategoriesTask")
  m.feed_task.setField("unparsed", obj.getData())
  m.feed_task.observeField("category_node", "onCateogrySetup")
  m.feed_task.control = "RUN"
end sub

sub onCateogrySetup(obj)
  m.category_screen.findNode("category_list").content = obj.getData()
  m.category_screen.setFocus(true)
end sub

sub onCategorySelected(obj)
  'Load feed for specific subscription
  list = m.category_screen.findNode("category_list")
  item = list.content.getChild(obj.getData())
  ? item.title + " [" + item.creatorGUID + "]"
  m.content_screen.setField("feed_name", item.title)
  m.content_screen.setField("category_node", item)

  'Grab stream info
  m.stream_cdn = CreateObject("roSGNode", "urlTask")
  url = "https://www.floatplane.com/api/cdn/delivery?type=live&creator=" + item.creatorGUID
  m.stream_cdn.setField("url", url)
  m.stream_cdn.observeField("response", "onGetStreamURL")
  m.stream_cdn.observeField("error", "onGotStreamError")
  m.stream_cdn.control = "RUN"
  m.creatorGUID = item.creatorGUID

  m.feed_url = item.feed_url
  m.feed_page = 0
end sub

sub onGetStreamURL(obj)
  json = ParseJSON(obj.getData())
  cdn = json.cdn
  uri = json.resource.uri
  if json.resource.data <> invalid
    regexObj = CreateObject("roRegex", "\{(.*?)\}", "i")
    regUri = regexObj.matchAll(uri)
    for i = 0 to regUri.Count() - 1
      data = json.resource.data[regUri[i][1]]
      uri = strReplace(uri, regUri[i][0], data)
    end for
  end if
  m.streamUri = cdn + uri

  m.stream_info = CreateObject("roSGNode", "urlTask")
  url = "https://www.floatplane.com/api/creator/info?creatorGUID=" + m.creatorGUID
  m.stream_info.setField("url", url)
  m.stream_info.observeField("response", "onGetStreamInfo")
  m.stream_info.control = "RUN"
end sub

sub onGotStreamError(obj)
  m.content_screen.setField("streaming", false)
  loadFeed(m.feed_url, m.feed_page)
end sub

sub onGetStreamInfo(obj)
  info = ParseJSON(obj.getData())
  if info[0].liveStream <> invalid
    if info[0].title <> invalid
      'If stream info found, create node
      node = createObject("roSGNode", "ContentNode")
      if info[0].liveStream.thumbnail <> invalid
        node.HDPosterURL = info[0].liveStream.thumbnail.path
      end if
      node.title = "LIVE: " + info[0].liveStream.title
      node.ShortDescriptionLine1 = "LIVE: " + info[0].liveStream.title
      if info[0].liveStream.description <> invalid
        node.Description = info[0].liveStream.description
      end if
      node.guid = m.streamUri
      node.id = "live"
      node.streamformat = "hls"
      m.stream_node = node

      'Start stream check timer'
      checkStream()
      m.streamCheckTimer.control = "start"
      m.isStreaming = false
      loadFeed(m.feed_url, m.feed_page)
    else
      m.isStreaming = false
      loadFeed(m.feed_url, m.feed_page)
    end if
  else
    m.isStreaming = false
    loadFeed(m.feed_url, m.feed_page)
  end if
end sub

sub checkStream()
  'm.stream_node.guid'
  'Check to see if creator is actually streaming'
  m.stream_check = createObject("roSGNode", "streamCheckTask")
  m.stream_check.setField("url", m.streamUri)
  m.stream_check.observeField("response", "isStreaming")
  m.stream_check.observeField("error", "notStreaming")
  m.stream_check.control = "RUN"
end sub

sub notStreaming()
  m.isStreaming = false
  'loadFeed(m.feed_url, m.feed_page)
  ? "Streaming: FALSE"
end sub

sub isStreaming()
  m.isStreaming = true
  m.streamCheckTimer.control = "stop"
  loadFeed(m.feed_url, m.feed_page)
  ? "Streaming: TRUE"
end sub

sub loadFeed(url, page)
  'Used to load subscription feed given url and page
  after = 20 * page
  newurl = url + "&fetchAfter=" + after.ToStr() + ""
  m.feed_task = createObject("roSGNode", "urlTask")
  m.feed_task.setField("url", newurl)
  m.feed_task.observeField("response", "onFeedResponse")
  m.feed_task.control = "RUN"
  m.feedpage = page
  m.feedurl = url
end sub

sub onFeedResponse(obj)
  'We will setup the feed node in the setupFeedTask, allowing us to manually cache thumbnail images
  unparsed_json = obj.getData()
  m.setupFeed_task = createObject("roSGNode", "setupFeedTask")
  m.setupFeed_task.setField("unparsed_feed", unparsed_json)
  m.setupFeed_task.setField("streaming", m.isStreaming)
  ''? m.stream_node
  m.setupFeed_task.setField("stream_node", m.stream_node)
  m.setupFeed_task.setField("page", m.feedpage)
  m.setupFeed_task.observeField("feed", "onFeedSetup")
  m.setupFeed_task.control = "RUN"
end sub

sub onFeedSetup(obj)
  'Set item focus if stream find after timer run'
  if m.itemFocus <> 0
    if m.isStreaming
      m.content_screen.setField("jumpTo", m.itemFocus + 1)
    end if
  end if

  'Feed node has been setup, show it to user
  m.content_screen.setField("page", m.feedpage)
  m.content_screen.setField("feed_node", obj.getData())
  m.category_screen.visible = false
  m.content_screen.visible = true
end sub

sub onItemFocus(event)
  ''? "New Item Focus: " + event.getData().ToStr()
  m.itemFocus = event.getData()
end sub

sub onContentSelected(obj)
  selected_index = obj.getData()
  m.selected_media = m.content_screen.findNode("content_grid").content.getChild(selected_index)
  m.selected_index = selected_index
  if m.selected_media.title = "nextpage"
    'User selected next page
    m.feedpage = m.feedpage + 1
    loadFeed(m.feedurl, m.feedpage)
  else if m.selected_media.title = "backpage"
    'User selected back page
    if m.feedpage <> 0
      m.feedpage = m.feedpage - 1
      loadFeed(m.feedurl, m.feedpage)
    end if
  else if m.selected_media.id = "live"
    m.live = true
    m.selected_media.description = removeHtmlTags(m.selected_media.description)
    m.details_screen.content = m.selected_media
    m.content_screen.visible = false
    m.details_screen.visible = true
    m.details_screen.setFocus(true)
  else
    m.live = false
    gpi = CreateObject("roSGNode", "urlTask")
    url = "https://www.floatplane.com/api/v3/content/post?id=" + m.selected_media.postId
    gpi.setField("url", url)
    gpi.observeField("response", "onPostInfo")
    gpi.control = "RUN"
  end if
end sub

sub onPostInfo(obj)
  info = ParseJSON(obj.getData())
  m.selected_media.userInteraction = info.userInteraction
  '? m.selected_media

  if m.selected_media.hasVideo = true
    m.selected_task = CreateObject("roSGNode", "urlTask")
    '? m.selected_media.guid
    '? m.selected_media.videoAttachments
    url = "https://www.floatplane.com/api/video/info?videoGUID=" + m.selected_media.videoAttachments[0]
    m.selected_task.setField("url", url)
    m.selected_task.observeField("response", "onVideoSelectedSetup")
    m.selected_task.control = "RUN"
  else
    m.selected_media.description = removeHtmlTags(m.selected_media.description)
    m.details_screen.content = m.selected_media
    m.content_screen.visible = false
    m.details_screen.visible = true
    m.details_screen.setFocus(true)
  end if
end sub

sub onVideoSelectedSetup(obj)
  'Got available resolutions for selected video
  unparsed = obj.getData()
  info = ParseJSON(unparsed)

  resolutions = createObject("roArray", 10, true)
  twentyonesixty = false
  'Push parsed resolutions to array for easy access
  for each level in info.levels
    resolutions.Push(level.name)
    if level.width = 2160 and level.height = 1080
      twentyonesixty = true
    end if
  end for

  'Loop through supported resolutions, finding highest available that also exists for video
  ? m.selected_media.title
  height = ""
  model = m.device.GetModel()
  for i = m.supported.Count() - 1 to 0 step -1
    tv = (strI(m.supported[i].height)).trim()
    if m.arrutil.contains(resolutions, tv)
      height = tv
      if twentyonesixty = true and height = "1080"
        if model = "3700X" or model = "3710X" or model = "3600X"
          height = "720"
        end if
      end if
      exit for
    end if
  end for
  if height = ""
    height = "720"
  end if

  'Set the resolution to be used as default for video
  m.resolution = height

  'Fix video descriptions
  m.selected_media.description = info.description

  'Print selected media node for debug
  ? m.selected_media


  m.video_pre_task = CreateObject("roSGNode", "urlTask")
  url = "https://www.floatplane.com/api/v2/cdn/delivery?type=vod&guid=" + m.selected_media.guid
  m.video_pre_task.setField("url", url)
  m.video_pre_task.observeField("response", "onProcessVideoSelected")
  m.video_pre_task.control = "RUN"
end sub

sub onProcessVideoSelected(obj)
  unparsed = obj.getData()
  info = ParseJSON(unparsed)
  m.selected_media.url = info.cdn + info.resource.uri
  m.info = info
  if m.resolution = invalid then
    m.resolution = "1080"
  end if

  'Replace qualityLevelsParams.token
  regexObj = CreateObject("roRegex", "{qualityLevelParams.token}", "i")
  regUri = regexObj.match(m.selected_media.url)
  resolutions = info.resource.data.qualityLevelParams
  res = resolutions.Lookup(m.resolution)
  if res = Invalid
    'TODO -- Notify user that default quality wasn't found?
    key = resolutions.Keys().Peek()
    res = resolutions.Lookup(key)
    m.resolution = key
  end if
  m.selected_media.url = strReplace(m.selected_media.url, regUri[0], res.token)

  'Replace qualityLevels
  regexObj = CreateObject("roRegex", "(?<=\/)({qualityLevels})(?=[.]mp4\/)", "i")
  regUri = regexObj.match(m.selected_media.url)
  m.selected_media.url = strReplace(m.selected_media.url, regUri[0], m.resolution)

  if m.playButtonPressed
    'We are just going to pass it some info... No need, really, but I will fix this later
    onPlayVideo(info)
  else
    'User selected video, let's prebuffer while on detail screen
    ''Just gonna needlessly pass info here as well
    onPreBuffer(info)
  end if
end sub

sub onPreBuffer(obj)
  'Setup videoplayer for prebuffering while user is on detail screen
  'CURRENTLY NOT IN USE'
  'registry = RegistryUtil()
  'edge = registry.read("edge", "hydravion")
  'm.details_screen.visible = false
  'm.videoplayer.visible = true
  'm.videoplayer.setFocus(true)
  ''? obj.getData()
  'm.selected_media.url = obj.getData().GetEntityEncode().Replace("&quot;","").Replace(m.default_edge,edge).DecodeUri()
  'm.selected_media.url = obj.getData().GetEntityEncode().Replace("&quot;","").DecodeUri()
  '? m.selected_media.url
  m.videoplayer.content = m.selected_media
  'm.videoplayer.visible = false
  'm.videoplayer.setFocus(false)
  'm.videoplayer.control = "prebuffer"
  m.details_screen.content = m.selected_media
  m.content_screen.visible = false
  m.details_screen.visible = true
  m.details_screen.setFocus(true)
end sub

sub onPlayButtonPressed(obj)
  if m.live then
    doLive()
  else
    'Prebuffering currently DISABLED
    'Video is already prebuffered, we just need to hide the detail screen, focus on the video player, and play the video
    m.details_screen.visible = false
    m.details_screen.setFocus(false)
    m.videoplayer.visible = true
    m.videoplayer.setFocus(true)
    m.videoplayer.control = "play"
    if m.video_task <> invalid
      m.playButtonPressed = true
    end if
  end if
end sub

sub doLive()
  'Grab stream info from earlier
  streamInfo = m.stream_node
  if streamInfo <> invalid
    if m.top.getScene().dialog <> invalid
      'If we tried to play the stream from the options dialog, close said dialog
      m.top.getScene().dialog.close = true
    end if
    url = streamInfo.guid
    if url.Instr("floatplane") > -1 then
      loadLiveFloat(url)
      else
      m.live_task = createObject("roSGNode", "liveTask")
      m.live_task.setField("url", url)
      m.live_task.observeField("done", "loadLiveStuff")
      m.live_task.control = "RUN"
    end if
  end if
end sub

sub loadLiveFloat(obj)
  'Load livestream from Floatplane CDN'
  videoContent = createObject("roSGNode", "ContentNode")
  videoContent.url = obj
  videoContent.StreamFormat = "hls"
  videoContent.PlayStart = 999999999
  videoContent.live = true

  m.content_screen.visible = false
  m.videoplayer.visible = true
  m.videoplayer.setFocus(true)
  m.videoplayer.content = videoContent
  m.videoplayer.control = "play"
end sub

sub loadLiveStuff(obj)
  'Load livestream from 3rd party CDN; doesn't like to load directly, so we have to save it and then read the temporary file'
  videoContent = createObject("roSGNode", "ContentNode")
  videoContent.url = "tmp:/live.m3u8"
  videoContent.StreamFormat = "hls"
  videoContent.PlayStart = 999999999
  videoContent.live = true

  m.content_screen.visible = false
  m.videoplayer.visible = true
  m.videoplayer.setFocus(true)
  m.videoplayer.content = videoContent
  m.videoplayer.control = "play"
end sub

sub onPlayVideo(obj)
  ? "TITLE: " + m.selected_media.ShortDescriptionLine1
  if m.resolution <> invalid then
    ? "RESOLUTION SELECTED: " + m.resolution
    ourl =  m.info.cdn + m.info.resource.uri
    'Replace qualityLevels
    regexObj = CreateObject("roRegex", "(?<=\/)({qualityLevels})(?=[.]mp4\/)", "i")
    regUri = regexObj.match(ourl)
    m.selected_media.url = strReplace(ourl, regUri[0], m.resolution)

    'Replace qualityLevelsParams.token
    regexObj = CreateObject("roRegex", "{qualityLevelParams.token}", "i")
    regUri = regexObj.match(m.selected_media.url)
    resolutions = m.info.resource.data.qualityLevelParams
    m.selected_media.url = strReplace(m.selected_media.url, regUri[0], resolutions.Lookup(m.resolution).token)
  end if

  m.details_screen.visible = false
  m.videoplayer.visible = true
  m.videoplayer.setFocus(true)
  m.videoplayer.content = m.selected_media
  m.videoplayer.control = "play"

end sub

sub initializeVideoPlayer()
  'Setup video player with proper cookies
  registry = RegistryUtil()
  sails = registry.read("sails", "hydravion")
  cookies = "sails.sid=" + sails
  m.videoplayer.EnableCookies()
  m.videoplayer.setCertificatesFile("common:/certs/ca-bundle.crt")
  m.videoplayer.initClientCertificates()
  m.videoplayer.SetConnectionTimeout(30)
  m.videoplayer.AddHeader("User-Agent", "Hydravion (Roku), CFNetwork")
  m.videoplayer.AddHeader("Cookie", cookies)
  m.videoplayer.notificationInterval = 1
  m.videoplayer.observeField("position", "onPlayerPositionChanged")
  m.videoplayer.observeField("state", "onPlayerStateChanged")
end sub

sub onPlayerPositionChanged(obj)
  ? "Position: ", obj.getData()
end sub

sub onPlayerStateChanged(obj)
  ? "State: ", obj.getData()
  state = obj.getData()
  if state = "finished"
    'Close video player when finished player
    closeVideo()
  else if state = "error"
    'Video couldn't play
    '-1 HTTP error: malformed headers or HTTP error result
    '-2 Connection timed out
    '-3 Unknown error
    '-4 Empty list; no streams specified to play
    '-5 Media error; the media format is unknown or unsupported
    '-6 DRM error
    error = "[Error " + m.videoplayer.errorCode.ToStr() + "] " + m.videoplayer.errorMsg
    ? error
    showVideoError(m.videoplayer.errorCode.ToStr(), m.videoplayer.errorMsg)
  end if
end sub

sub showVideoError(code, error)
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Error " + code 
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "Video cannot be played! " + error
  setupDialogPalette()
end sub

sub showTestDialog()
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Deep Linking Test"
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "This is a test."
  setupDialogPalette()
end sub

sub closeVideo()
  m.resolution = invalid
  m.videoplayer.control = "stop"
  m.videoplayer.visible = false
  m.content_screen.visible = true
  m.content_screen.setFocus(true)
  m.playButtonPressed = false
end sub

sub showOptions()
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Options"
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "Select Option"
  m.top.getScene().dialog.buttons = ["Watch Stream","Logout"]
  setupDialogPalette()
  m.top.getScene().dialog.observeField("buttonSelected","handleOptions")
end sub

sub showMainOptions()
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Options"
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "Select Option"
  m.top.getScene().dialog.buttons = ["Change Server","Logout"]
  setupDialogPalette()
  m.top.getScene().dialog.observeField("buttonSelected","handleMainOptions")
end sub

sub showDetailOptions()
  'Grab resolutions available for the video
  m.res_task = CreateObject("roSGNode", "urlTask")
  url = "https://www.floatplane.com/api/video/info?videoGUID=" + m.selected_media.guid
  m.res_task.setField("url", url)
  m.res_task.observeField("response", "makeDetailOptions")
  m.res_task.control = "RUN"
end sub

sub makeDetailOptions(obj)
  'Display available resolutions for selected video
  unparsed = obj.getData()
  info = ParseJSON(unparsed)
  m.dbuttons = createObject("roArray", 10, true)
  for each level in info.levels
    m.dbuttons.Push(level.name)
  end for
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Resolution"
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "Select Stream Resolution"
  m.top.getScene().dialog.buttons = m.dbuttons
  m.top.getScene().dialog.observeField("buttonSelected","handleDetailOptions")
  setupDialogPalette()
end sub

sub handleDetailOptions()
  url = ""
  m.video_task = CreateObject("roSGNode", "urlTask")
  m.resolution = m.dbuttons[m.top.getScene().dialog.buttonSelected]
  ? "RESOLUTION SELECTED: " + m.resolution
  m.top.getScene().dialog.close = true
  m.content_screen.setFocus(true)
  onPlayVideo(m.resolution)
end sub

sub handleMainOptions()
  'Determines which option was selected on main screen'
  if m.top.getScene().dialog.buttonSelected = 0
    getEdgeOptions()
  else if m.top.getScene().dialog.buttonSelected = 1
    showLogoutDialog()
  end if
end sub

sub getEdgeOptions()
  'Gets list of all edge servers'
  m.video_task = CreateObject("roSGNode", "urlTask")
  m.top.getScene().dialog.close = true
  m.video_task.setField("url", "https://www.floatplane.com/api/edges")
  m.video_task.observeField("response", "makeEdgeOptions")
  m.video_task.control = "RUN"
end sub

sub makeEdgeOptions(obj)
  'Display possible edge servers
  unparsed = obj.getData()
  info = ParseJSON(unparsed)
  m.ebuttons = createObject("roArray", 7, true)
  for each edge in info.edges
    m.ebuttons.Push(edge.hostname)
  end for

  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  'm.top.getScene().dialog.title = "Edge CDN Servers"
  m.top.getScene().dialog.showCancel = false
  'm.top.getScene().dialog.text = "Select a server:"
  'm.top.getScene().dialog.buttons = m.ebuttons
  m.top.getScene().dialog.title = "Edge Selection Disabled"
  m.top.getScene().dialog.text = "Edge servers are currently not used -- Floatplane itself provides the CDN server to use."
  setupDialogPalette()
  m.top.getScene().dialog.observeField("buttonSelected","handleEdgeOptions")
end sub

sub handleEdgeOptions()
  'Set the newely user-chosen edge server'
  'edge = m.ebuttons[m.top.getScene().dialog.buttonSelected]
  'registry = RegistryUtil()
  'registry.write("edge", edge, "hydravion")
  'edge = registry.read("edge", "hydravion")
  '? "[Edge Server] User selected " + edge
  m.top.getScene().dialog.close = true
end sub

sub handleOptions()
  'Determines which option was selected'
  if m.top.getScene().dialog.buttonSelected = 0
    doLive()
  else if m.top.getScene().dialog.buttonSelected = 1
    showLogoutDialog()
  end if
end sub

sub showLogoutDialog()
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Logout?"
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "Press OK to logout"
  setupDialogPalette()
  m.top.getScene().dialog.observeField("buttonSelected","doLogout")
end sub

sub showLiveDialog()
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Play stream?"
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "Press OK to play stream"
  setupDialogPalette()
  m.top.getScene().dialog.observeField("buttonSelected","doLive")
end sub

sub doLogout()
  'Logs the user out'
  m.top.getScene().dialog.close = true
  registry = RegistryUtil()
  registry.deleteSection("hydravion")
  m.details_screen.visible = false
  m.content_screen.visible = false
  m.category_screen.visible = false
  m.login_screen.visible = true
  m.login_screen.setFocus(true)
  m.login_screen.findNode("username").setFocus(true)
  m.login_screen.findNode("username").text = "username"
  m.login_screen.findNode("password").text = "password"
end sub

sub showUpdateDialog()
  'Check whether to show update dialog'
  registry = RegistryUtil()
  version = registry.read("version", "hydravion")
  appInfo = createObject("roAppInfo")
  if version <> invalid
    if version <> appInfo.getVersion()
      doUpdateDialog(appInfo)
      registry.write("version", appInfo.getVersion(), "hydravion")
    end if
  else
    registry.write("version", appInfo.getVersion(), "hydravion")
    doUpdateDialog(appInfo)
  end if
end sub

sub doUpdateDialog(appInfo)
  m.top.getScene().dialog = createObject("roSGNode", "SimpleDialog")
  m.top.getScene().dialog.title = "Update " + appInfo.getVersion()
  m.top.getScene().dialog.showCancel = false
  m.top.getScene().dialog.text = "-Updated channel UI" + Chr(10) + "-Updated channel icon/splash" + Chr(10) + "-Added likes/dislikes" + Chr(10) + "-Fix playback on older non-1080 devices" + Chr(10) + "-Removed (some) deprecated code"
  setupDialogPalette()
  m.top.getScene().dialog.observeField("buttonSelected","closeUpdateDialog")
end sub

sub closeUpdateDialog()
  m.top.getScene().dialog.close = true
end sub

sub setupDialogPalette()
  palette = createObject("roSGNode", "RSGPalette")
  palette.colors = {   DialogBackgroundColor: "0x152130FF"}
  m.top.getScene().dialog.palette = palette
end sub

function removeHtmlTags(baseStr as String) as String
    r = createObject("roRegex", "<[^<]+?>", "i")
    return r.replaceAll(baseStr, " ")
end function

function strReplace(basestr As String, oldsub As String, newsub As String) As String
    newstr = ""
    i = 1
    while i <= Len(basestr)
        x = Instr(i, basestr, oldsub)
        if x = 0 then
            newstr = newstr + Mid(basestr, i)
            exit while
        endif
        if x > i then
            newstr = newstr + Mid(basestr, i, x-i)
            i = x
        endif
        newstr = newstr + newsub
        i = i + Len(oldsub)
    end while
    return newstr
end function

function ArrayUtil() as Object
  'Borrowed function(s) from https://github.com/juliomalves/roku-libs because I was too lazy to write my own
  util = {
    contains: function(arr as Object, element as Dynamic) as Boolean
      return m.indexOf(arr, element) >= 0
    end function
    indexOf: function(arr as Object, element as Dynamic) as Integer
      if not m.isArray(arr) then return -1
      size = arr.count()
      if size = 0 then return -1
        for i = 0 to size - 1
          if arr[i] = element then return i
        end for
      return -1
    end function
    isArray: function(arr) as Boolean
      return type(arr) = "roArray"
    end function
  }
  return util
end function

function onKeyEvent(key, press) as Boolean
  if key = "back" and press
    if m.details_screen.visible
      m.details_screen.visible = false
      m.content_screen.visible = true
      m.content_screen.setFocus(true)
      m.itemFocus = m.selected_index
      m.content_screen.setField("itemIndex", m.selected_index)
      m.content_screen.setField("jumpTo", m.selected_index)
      m.playButtonPressed = false
      return true
    else if m.videoplayer.visible
      m.resolution = invalid
      m.videoplayer.control = "stop"
      m.videoplayer.visible = false
      m.content_screen.visible = true
      m.details_screen.visible = false
      m.content_screen.setFocus(true)
      m.content_screen.FindNode("content_grid").setFocus(true)
      m.playButtonPressed = false
      return true
    else if m.content_screen.visible
      m.streamCheckTimer.control = "stop"
      m.itemFocus = 0
      m.content_screen.setField("itemIndex", 0)
      m.content_screen.setField("jumpTo", 0)
      m.content_screen.visible = false
      m.category_screen.visible = true
      m.category_screen.setFocus(true)
      return true
    end if
  else if key = "options" and press
    if m.videoplayer.visible = false
      if m.content_screen.visible = true
        showOptions()
      else if m.details_screen.visible = true
        showDetailOptions()
      else
        showMainOptions()
      end if
      return true
    end if
  else if key = "play" and press
    if m.videoplayer.visible = false
      if m.content_screen.visible = true
        showLiveDialog()
        return true
      end if
    end if
  end if
  return false
end function
