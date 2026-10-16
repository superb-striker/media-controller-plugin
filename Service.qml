import QtQuick
import Quickshell.Io

// One backend process serves every bar instance, including multiple monitors.
Item {
  id: root

  property var shell: null
  readonly property var emptyMedia: ({
    available: false, playing: false, title: "", artist: "", album: "",
    art: "", position: 0, duration: 0, queue: [], hasQueue: false,
    sources: [], canSeek: false, canGoNext: false, canGoPrevious: false,
    canPlayPause: false, seekStep: 10
  })
  property var media: emptyMedia

  // Qt.resolvedUrl is relative to this installed Service.qml. The plugin
  // manager clones the whole repository, so this path moves with the plugin.
  readonly property string backendPath: decodeURIComponent(
    String(Qt.resolvedUrl("backend/media-backend.py")).replace(/^file:\/\//, "")
  )

  function send(action, args) {
    if (mediaDaemon.running)
      mediaDaemon.write(JSON.stringify({ action: action, args: args || [] }) + "\n")
  }

  Process {
    id: mediaDaemon
    command: ["python3", root.backendPath, "daemon"]
    stdinEnabled: true
    running: true
    stdout: SplitParser {
      onRead: data => {
        try {
          root.media = JSON.parse(data)
        } catch (error) {
          console.warn("media-controller: invalid backend state:", error)
        }
      }
    }
    onExited: {
      root.media = root.emptyMedia
      restartTimer.start()
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: if (!mediaDaemon.running) mediaDaemon.running = true
  }
}
