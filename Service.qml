import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Omarchy creates one service for all bar instances.
Item {
  id: root
  property var shell: null
  readonly property string prefix: "org.mpris.MediaPlayer2."
  readonly property string objectPath: "/org/mpris/MediaPlayer2"
  readonly property string trackInterface: "org.mpris.MediaPlayer2.TrackList"
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayers: players.filter(p => p && (p.isPlaying || p.playbackState === MprisPlaybackState.Paused))
  property string preferredSource: ""
  readonly property var activePlayer: {
    for (const p of activePlayers)
      if (p.dbusName === prefix + preferredSource) return p
    for (const p of activePlayers) if (p.isPlaying) return p
    return activePlayers.length ? activePlayers[0] : null
  }
  readonly property string sourceName: activePlayer ? String(activePlayer.dbusName).replace(prefix, "") : ""
  readonly property bool isMpv: sourceName.split(".")[0].toLowerCase() === "mpv"
  property var trackQueue: []
  property var trackIds: []
  property string queueSource: ""
  property var mpvQueue: []
  property string mpvPath: ""
  property int mpvPosition: -1
  property var hasListReply: null
  property var tracksReply: null
  property var metadataReply: null
  property var currentTrackReply: null
  property bool refreshPending: false
  property int positionTick: 0
  property var artCandidates: []
  property int artCandidateIndex: 0
  property string localArt: ""
  readonly property string artProbeSource: artCandidateIndex < artCandidates.length
    ? artCandidates[artCandidateIndex] : ""
  property var media: emptyState()

  function emptyState() {
    return { available: false, playing: false, title: "", artist: "", album: "",
      art: "", position: 0, duration: 0, queue: [], hasQueue: false,
      source: "", sources: [], canSeek: false, canGoNext: false,
      canGoPrevious: false, canPlayPause: false, seekStep: 10 }
  }
  function parse(line) {
    try { return JSON.parse(String(line)) }
    catch (error) { console.warn("media-controller: invalid JSON:", error); return null }
  }
  function value(variant) { return variant && variant.data !== undefined ? variant.data : null }
  function label(p) {
    return String(p.identity || p.desktopEntry || String(p.dbusName).replace(prefix, "").split(".")[0] || "Player")
  }
  function localPath(url) {
    const raw = String(url || "")
    if (raw.startsWith("file://")) return decodeURIComponent(raw.slice(7))
    return raw.indexOf("://") < 0 ? raw : ""
  }
  function mpvMatches(p) {
    if (!isMpv || !mpv.connected) return false
    const playerPath = localPath(p.metadata["xesam:url"] || "")
    const socketPath = localPath(mpvPath)
    if (!socketPath) return false
    if (playerPath) return playerPath === socketPath
    return activePlayers.filter(other => String(other.dbusName).startsWith(prefix + "mpv")).length === 1
  }
  function probeArtwork() {
    localArt = ""
    artCandidates = []
    artCandidateIndex = 0
    const p = activePlayer
    if (!p || p.trackArtUrl) return
    const path = localPath(p.metadata["xesam:url"] || (isMpv ? mpvPath : ""))
    if (!path || !path.startsWith("/")) return
    const slash = path.lastIndexOf("/")
    const directory = path.slice(0, slash + 1)
    const filename = path.slice(slash + 1)
    const dot = filename.lastIndexOf(".")
    const stem = dot > 0 ? filename.slice(0, dot) : filename
    const names = [stem, "cover", "Cover", "folder", "Folder", "front", "Front", "AlbumArt", "albumart"]
    const extensions = [".jpg", ".jpeg", ".png", ".webp", ".avif"]
    const candidates = []
    for (const name of names)
      for (const ext of extensions)
        candidates.push("file://" + (directory + name + ext).split("/").map(encodeURIComponent).join("/"))
    artCandidates = candidates
  }
  function rebuild() {
    const p = activePlayer
    if (!p) { media = emptyState(); return }
    const queue = mpvMatches(p) ? mpvQueue : (queueSource === sourceName ? trackQueue : [])
    const sources = activePlayers.map(other => {
      const name = String(other.dbusName).replace(prefix, "")
      const display = label(other)
      const duplicate = activePlayers.filter(candidate => label(candidate) === display).length > 1
      return { name: name, label: duplicate ? display + " (" + name + ")" : display,
        title: other.trackTitle || display, artist: other.trackArtist || "",
        playing: !!other.isPlaying, selected: other === p }
    })
    // The position timer triggers this read while playback is advancing.
    const tick = positionTick
    media = { available: true, playing: !!p.isPlaying,
      title: p.trackTitle || label(p), artist: p.trackArtist || "",
      album: p.trackAlbum || "", art: String(p.trackArtUrl || localArt || ""),
      position: Number(p.position || 0), duration: Number(p.length || 0),
      queue: queue, hasQueue: queue.length > 0, source: sourceName, sources: sources,
      canSeek: !!p.canSeek, canGoNext: !!p.canGoNext,
      canGoPrevious: !!p.canGoPrevious,
      canPlayPause: !!(p.isPlaying ? p.canPause : p.canPlay), seekStep: 10 }
  }
  function send(action, args) {
    const p = activePlayer
    const values = args || []
    if (action === "select-source") {
      const requested = String(values[0] || "")
      if (!activePlayers.some(candidate => candidate.dbusName === prefix + requested)) return
      if (p && p.isPlaying && sourceName !== requested && p.canPause) p.pause()
      preferredSource = requested
      selectionFile.setText(requested)
      return
    }
    if (!p) return
    if (action === "play-pause" && (p.canTogglePlaying || p.canPlay || p.canPause)) p.togglePlaying()
    else if (action === "previous" && p.canGoPrevious) p.previous()
    else if (action === "next" && p.canGoNext) p.next()
    else if (action === "seek-relative" && p.canSeek && values.length === 1) p.seek(Number(values[0]))
    else if (action === "seek" && p.canSeek && values.length === 1) p.position = Number(values[0])
    else if (action === "play-track" && values.length === 2 &&
             String(values[1]) === sourceName && trackIds.indexOf(String(values[0])) >= 0) {
      dbusCommand.command = ["busctl", "--user", "call", p.dbusName, objectPath,
        trackInterface, "GoTo", "o", String(values[0])]
      dbusCommand.running = true
    } else if (action === "play-index" && isMpv && mpvMatches(p) && values.length === 1) {
      const index = Number(values[0])
      if (!Number.isInteger(index) || index < 0 || index >= mpvQueue.length) return
      mpv.write(JSON.stringify({ command: ["playlist-play-index", index] }) + "\n")
      mpv.write(JSON.stringify({ command: ["set_property", "pause", false] }) + "\n")
      mpv.flush()
    }
  }
  function refreshQueue() {
    if (!activePlayer) return
    if (hasList.running || tracksRead.running || metadataRead.running || currentTrackRead.running) {
      refreshPending = true
      return
    }
    queueSource = sourceName
    trackIds = []
    trackQueue = []
    hasListReply = null
    hasList.command = ["busctl", "--json=short", "--user", "get-property",
      activePlayer.dbusName, objectPath, "org.mpris.MediaPlayer2", "HasTrackList"]
    hasList.running = true
    rebuild()
  }
  function finishQueueRefresh() {
    if (refreshPending) { refreshPending = false; queueRefresh.restart() }
    else rebuild()
  }
  onPlayersChanged: {
    if (preferredSource && !players.some(p => p.dbusName === prefix + preferredSource)) {
      preferredSource = ""
      selectionFile.setText("")
    }
    rebuild()
  }
  onActivePlayerChanged: {
    trackQueue = []
    trackIds = []
    queueSource = ""
    mpvQueue = []
    mpvPath = ""
    probeArtwork()
    queueRefresh.restart()
    rebuild()
  }
  onTrackQueueChanged: rebuild()
  onMpvQueueChanged: rebuild()
  onMpvPathChanged: { probeArtwork(); rebuild() }
  onLocalArtChanged: rebuild()
  onPositionTickChanged: if (activePlayer && activePlayer.isPlaying) rebuild()
  Connections {
    target: root.activePlayer
    function onMetadataChanged() { queueRefresh.restart(); root.probeArtwork(); root.rebuild() }
    function onTrackChanged() { queueRefresh.restart(); root.rebuild() }
    function onPlaybackStateChanged() { root.rebuild() }
    function onPositionChanged() { root.rebuild() }
    function onCanSeekChanged() { root.rebuild() }
    function onCanGoNextChanged() { root.rebuild() }
    function onCanGoPreviousChanged() { root.rebuild() }
    function onCanPlayChanged() { root.rebuild() }
    function onCanPauseChanged() { root.rebuild() }
  }
  FileView {
    id: selectionFile
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/media-controller-plugin-selected"
    watchChanges: false
    printErrors: false
    onLoaded: { root.preferredSource = text().trim(); root.rebuild() }
  }
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.positionTick++ }
  Timer { id: queueRefresh; interval: 180; repeat: false; onTriggered: root.refreshQueue() }
  Image {
    source: root.artProbeSource
    asynchronous: true
    visible: false
    onStatusChanged: {
      if (status === Image.Ready) root.localArt = root.artProbeSource
      else if (status === Image.Error) root.artCandidateIndex++
    }
  }
  Process {
    id: hasList
    stdout: SplitParser { onRead: line => root.hasListReply = root.parse(line) }
    onExited: code => {
      if (root.queueSource !== root.sourceName) { root.finishQueueRefresh(); return }
      if (code !== 0 || !root.hasListReply || root.hasListReply.type !== "b" ||
          root.hasListReply.data !== true) { root.finishQueueRefresh(); return }
      root.tracksReply = null
      tracksRead.command = ["busctl", "--json=short", "--user", "get-property",
        root.activePlayer.dbusName, root.objectPath, root.trackInterface, "Tracks"]
      tracksRead.running = true
    }
  }
  Process {
    id: tracksRead
    stdout: SplitParser { onRead: line => root.tracksReply = root.parse(line) }
    onExited: code => {
      if (root.queueSource !== root.sourceName || code !== 0 || !root.tracksReply ||
          root.tracksReply.type !== "ao") { root.finishQueueRefresh(); return }
      root.trackIds = root.tracksReply.data || []
      if (!root.trackIds.length) { root.finishQueueRefresh(); return }
      root.metadataReply = null
      metadataRead.command = ["busctl", "--json=short", "--user", "call",
        root.activePlayer.dbusName, root.objectPath, root.trackInterface,
        "GetTracksMetadata", "ao", String(root.trackIds.length)].concat(root.trackIds)
      metadataRead.running = true
    }
  }
  Process {
    id: metadataRead
    stdout: SplitParser { onRead: line => root.metadataReply = root.parse(line) }
    onExited: code => {
      if (root.queueSource !== root.sourceName || code !== 0 || !root.metadataReply ||
          root.metadataReply.type !== "aa{sv}") { root.finishQueueRefresh(); return }
      const rows = root.metadataReply.data[0] || []
      root.trackQueue = rows.map((row, index) => {
        const id = String(root.value(row["mpris:trackid"]) || root.trackIds[index])
        const url = String(root.value(row["xesam:url"]) || "")
        const title = String(root.value(row["xesam:title"]) ||
          decodeURIComponent(url.split("/").pop().split("?")[0]) || "Unknown track")
        return { index: index, trackId: id, title: title, path: url, current: false }
      })
      root.currentTrackReply = null
      currentTrackRead.command = ["busctl", "--json=short", "--user", "get-property",
        root.activePlayer.dbusName, root.objectPath, "org.mpris.MediaPlayer2.Player", "Metadata"]
      currentTrackRead.running = true
    }
  }
  Process {
    id: currentTrackRead
    stdout: SplitParser { onRead: line => root.currentTrackReply = root.parse(line) }
    onExited: code => {
      if (root.queueSource !== root.sourceName) { root.finishQueueRefresh(); return }
      if (code === 0 && root.currentTrackReply) {
        const data = root.currentTrackReply.data
        const metadata = Array.isArray(data) ? data[0] : data
        const id = String(root.value(metadata && metadata["mpris:trackid"]) || "")
        root.trackQueue = root.trackQueue.map(entry => ({
          index: entry.index, trackId: entry.trackId, title: entry.title,
          path: entry.path, current: entry.trackId === id }))
      }
      root.finishQueueRefresh()
    }
  }
  Process { id: dbusCommand }
  // TrackList is absent from Quickshell's MPRIS API. Monitor D-Bus and
  // coalesce changes; unsupported players simply have no list.
  Process {
    id: trackChanges
    running: true
    command: ["busctl", "--json=short", "--user", "monitor",
      "--match=type='signal',path='/org/mpris/MediaPlayer2'"]
    stdout: SplitParser {
      onRead: line => {
        const message = root.parse(line)
        if (!message || message.type !== "signal" || !root.activePlayer) return
        const changed = message.interface === root.trackInterface ||
          (message.interface === "org.freedesktop.DBus.Properties" &&
           message.payload && message.payload.data &&
           message.payload.data[0] === root.trackInterface)
        if (changed) queueRefresh.restart()
      }
    }
    onExited: monitorRestart.start()
  }
  Timer {
    id: monitorRestart
    interval: 2000
    repeat: false
    onTriggered: if (!trackChanges.running) trackChanges.running = true
  }
  Socket {
    id: mpv
    path: Quickshell.env("MPV_SOCKET") || "/tmp/mpv-socket"
    onConnectedChanged: {
      if (!connected) { root.mpvQueue = []; root.mpvPath = ""; return }
      for (const entry of [[1, "playlist"], [2, "playlist-pos"], [3, "path"]])
        write(JSON.stringify({ command: ["observe_property", entry[0], entry[1]] }) + "\n")
      flush()
    }
    parser: SplitParser {
      onRead: line => {
        const message = root.parse(line)
        if (!message || message.event !== "property-change") return
        if (message.name === "playlist") {
          root.mpvQueue = (message.data || []).map((entry, index) => {
            const path = String(entry.filename || "")
            return { index: index, title: String(entry.title || path.split("/").pop() || "Unknown track"),
              path: path, current: index === root.mpvPosition }
          })
        } else if (message.name === "playlist-pos") {
          root.mpvPosition = Number(message.data === null ? -1 : message.data)
          root.mpvQueue = root.mpvQueue.map((entry, index) => ({
            index: index, title: entry.title, path: entry.path,
            current: index === root.mpvPosition }))
        } else if (message.name === "path") root.mpvPath = String(message.data || "")
      }
    }
  }
  Timer {
    interval: 2000
    running: root.isMpv
    repeat: true
    onTriggered: if (!mpv.connected) mpv.connected = true
  }
  onIsMpvChanged: {
    mpv.connected = false
    if (isMpv) mpv.connected = true
  }
  Component.onCompleted: if (isMpv) mpv.connected = true
}
