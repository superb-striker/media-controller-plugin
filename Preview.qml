import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
Item {
  id: root
  property var bar
  property string moduleName
  property var settings
  property var mediaService
  property var hostWidget
  property int fixedWidth: (settings && settings.width) ? settings.width : 180
  property int fontPx: (settings && settings.fontSize) ? settings.fontSize : 12
  property int popupWidth: 340
  property int hoverPopupWidth: 300
  property int popupMargin: 8
  readonly property var media: mediaService ? mediaService.media : ({
    available: false, playing: false, title: "", artist: "", album: "",
    art: "", position: 0, duration: 0, queue: [], hasQueue: false,
    sources: [], canSeek: false, canGoNext: false, canGoPrevious: false,
    canPlayPause: false, seekStep: 10
  })
  readonly property bool hasPlayer: !!media.available
  property bool popupOpen: false
  property bool popupPinned: false
  property bool queueExpanded: false
  readonly property bool artworkReady: !!root.media.art && artwork.status === Image.Ready
  readonly property color popupForeground: artworkReady ? "white" : (bar ? bar.foreground : "white")
  readonly property color popupBackground: artworkReady ? "#161616" : (bar && bar.background ? bar.background : "#161616")
  // Every MPRIS source can show the popup. Seeking and track lists are
  // enabled only when that source exposes the relevant capability.
  property bool popupEligible: root.hasPlayer
  implicitHeight: bar ? bar.barSize : 28
  implicitWidth: hasPlayer ? fixedWidth : 0
  visible: hasPlayer
  clip: true
  onPopupEligibleChanged: if (!popupEligible && popupOpen) closePopup()
  Text {
    id: titleText
    anchors.fill: parent
    textFormat: Text.PlainText
    text: root.media.title + (root.media.artist ? " - " + root.media.artist : "")
    color: bar ? bar.foreground : "white"
    font.family: bar ? bar.fontFamily : undefined
    font.pixelSize: root.fontPx
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    opacity: root.popupOpen ? 0.7 : 1
  }
  MouseArea {
    id: triggerArea
    anchors.fill: parent
    enabled: root.popupEligible
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: {
      hoverCloseTimer.stop()
      root.popupOpen = true
    }
    onExited: root.scheduleHoverClose()
  }
  Timer {
    id: hoverCloseTimer
    interval: 240
    repeat: false
    onTriggered: {
      if (!root.popupPinned && !triggerArea.containsMouse && !popupHover.hovered)
        root.popupOpen = false
    }
  }
  PopupWindow {
    id: popup
    // Anchor to the window's own content item (a real Item spanning the
    // full window, always available via the standard Qt Window attached
    // property) rather than this small module or the `bar` object, whose
    // exact type we can't rely on. This keeps the popup's right edge flush
    // with the true screen edge at any resolution or display scale,
    // without any hardcoded pixel offset.
    anchor.item: root.Window.contentItem
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.top: (bar ? bar.barSize : 28) + root.popupMargin
    anchor.adjustment: PopupAdjustment.All
    implicitWidth: root.popupPinned ? root.popupWidth : root.hoverPopupWidth
    implicitHeight: contentColumn.implicitHeight + 32
    visible: root.popupOpen && root.popupEligible
    grabFocus: root.popupPinned
    color: "transparent"
    onVisibleChanged: {
      if (!visible) {
        root.closePopup()
      } else {
        if (root.popupPinned) popupFocusItem.forceActiveFocus()
      }
    }
    HyprlandFocusGrab {
      active: popup.visible && root.popupPinned
      windows: [popup]
      onCleared: root.closePopup()
    }
    Rectangle {
      id: popupFocusItem
      anchors.fill: parent
      radius: 18
      color: root.popupBackground
      border.width: 1
      border.color: Qt.alpha(root.popupForeground, 0.16)
      clip: true
      focus: true
      Keys.onEscapePressed: root.closePopup()

      Image {
        id: backdropSource
        anchors.fill: parent
        source: root.media.art || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
      }
      MultiEffect {
        anchors.fill: parent
        source: backdropSource
        visible: root.artworkReady
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 0.85
        blurMax: 48
        saturation: 0.35
        brightness: -0.35
        contrast: 0.08
      }
      Rectangle {
        anchors.fill: parent
        visible: root.artworkReady
        color: "#59000000"
      }
      HoverHandler {
        id: popupHover
        onHoveredChanged: {
          if (hovered) hoverCloseTimer.stop()
          else root.scheduleHoverClose()
        }
      }
      TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.openPinned()
      }
      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: root.popupPinned ? 12 : 10
        Flickable {
          id: sourceList
          width: parent.width
          height: visible ? 26 : 0
          visible: root.popupPinned && root.media.sources && root.media.sources.length > 1
          contentWidth: sourceRow.implicitWidth
          contentHeight: height
          flickableDirection: Flickable.HorizontalFlick
          clip: true
          Row {
            id: sourceRow
            spacing: 6
            Repeater {
              model: root.media.sources
              delegate: Rectangle {
                height: 22
                width: Math.min(sourceLabel.implicitWidth + 16, sourceList.width * 0.8)
                radius: 11
                color: modelData.selected ? root.popupForeground : Qt.alpha(root.popupForeground, 0.10)
                Text {
                  id: sourceLabel
                  anchors.centerIn: parent
                  width: parent.width - 16
                  textFormat: Text.PlainText
                  text: modelData.label
                  elide: Text.ElideRight
                  color: modelData.selected ? root.popupBackground : Qt.alpha(root.popupForeground, 0.78)
                  font.family: bar ? bar.fontFamily : undefined
                  font.pixelSize: 10
                  font.bold: modelData.selected
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.send("select-source", [modelData.name])
                }
              }
            }
          }
        }
        Rectangle {
          width: parent.width
          height: root.popupPinned ? 164 : 118
          radius: 14
          clip: true
          color: Qt.alpha(root.popupForeground, 0.07)
          Image {
            id: artwork
            anchors.fill: parent
            source: root.media.art || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
          }
          Column {
            anchors.centerIn: parent
            spacing: 8
            visible: artwork.status !== Image.Ready
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰝚"
              color: Qt.alpha(root.popupForeground, 0.42)
              font.family: bar ? bar.fontFamily : undefined
              font.pixelSize: 48
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No artwork"
              color: Qt.alpha(root.popupForeground, 0.5)
              font.family: bar ? bar.fontFamily : undefined
              font.pixelSize: 11
            }
          }
        }
        Column {
          width: parent.width
          spacing: 4
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.media.title
            color: root.popupForeground
            font.family: bar ? bar.fontFamily : undefined
            font.pixelSize: root.popupPinned ? 17 : 15
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.media.artist || "Unknown artist"
            color: Qt.alpha(root.popupForeground, 0.72)
            font.family: bar ? bar.fontFamily : undefined
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.media.album || ""
            visible: root.popupPinned && text.length > 0
            color: Qt.alpha(root.popupForeground, 0.5)
            font.family: bar ? bar.fontFamily : undefined
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
        Rectangle {
          width: parent.width
          height: root.media.duration > 0 ? 4 : 0
          radius: 2
          visible: height > 0
          color: Qt.alpha(root.popupForeground, 0.16)
          Rectangle {
            width: parent.width * (root.media.duration > 0 ? Math.min(1, root.media.position / root.media.duration) : 0)
            height: parent.height
            radius: 2
            color: root.popupForeground
          }
          MouseArea {
            anchors.fill: parent
            enabled: !!root.media.canSeek
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: mouse => root.seek(mouse.x / width)
          }
        }
        Text {
          width: parent.width
          visible: root.popupPinned && root.media.duration > 0
          text: formatTime(root.media.position) + " / " + formatTime(root.media.duration)
          color: Qt.alpha(root.popupForeground, 0.58)
          font.family: bar ? bar.fontFamily : undefined
          font.pixelSize: 10
          horizontalAlignment: Text.AlignHCenter
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          height: 44
          spacing: 9
          MediaButton { width: 38; height: 38; glyph: "󰒮"; enabled: !!root.media.canGoPrevious; onClicked: root.send("previous") }
          MediaButton {
            width: 36; height: 36
            glyph: "−" + (root.media.seekStep || 10)
            enabled: !!root.media.canSeek
            compact: true
            onClicked: root.seekRelative(-(root.media.seekStep || 10))
          }
          MediaButton {
            width: 44
            height: 44
            glyph: root.media.playing ? "󰏤" : "󰐊"
            filled: true
            enabled: !!root.media.canPlayPause
            onClicked: root.send("play-pause")
          }
          MediaButton {
            width: 36; height: 36
            glyph: "+" + (root.media.seekStep || 10)
            enabled: !!root.media.canSeek
            compact: true
            onClicked: root.seekRelative(root.media.seekStep || 10)
          }
          MediaButton { width: 38; height: 38; glyph: "󰒭"; enabled: !!root.media.canGoNext; onClicked: root.send("next") }
        }
        Item {
          width: parent.width
          height: 20
          visible: root.popupPinned && root.media.hasQueue
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.queueExpanded = !root.queueExpanded
            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6
              Text {
                text: "TRACK LIST"
                color: Qt.alpha(root.popupForeground, 0.5)
                font.family: bar ? bar.fontFamily : undefined
                font.pixelSize: 10
                font.bold: true
              }
              Text {
                text: "(" + root.media.queue.length + ")"
                color: Qt.alpha(root.popupForeground, 0.4)
                font.family: bar ? bar.fontFamily : undefined
                font.pixelSize: 10
              }
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.queueExpanded ? "󰅃" : "󰅀"
              color: Qt.alpha(root.popupForeground, 0.5)
              font.pixelSize: 12
            }
          }
        }
        ListView {
          id: queueView
          width: parent.width
          height: (root.popupPinned && root.media.hasQueue && root.queueExpanded) ? Math.min(180, root.media.queue.length * 40) : 0
          clip: true
          spacing: 2
          visible: height > 0
          model: root.media.queue
          delegate: Rectangle {
            width: queueView.width
            height: 38
            radius: 8
            color: modelData.current ? Qt.alpha(root.popupForeground, 0.14) : (rowArea.containsMouse ? Qt.alpha(root.popupForeground, 0.08) : "transparent")
            Rectangle {
              visible: modelData.current
              width: 3
              height: parent.height - 12
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: 4
              radius: 1.5
              color: root.popupForeground
            }
            Text {
              anchors.left: parent.left
              anchors.leftMargin: modelData.current ? 16 : 10
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.title
              color: modelData.current ? root.popupForeground : Qt.alpha(root.popupForeground, 0.7)
              font.family: bar ? bar.fontFamily : undefined
              font.pixelSize: 12
              font.bold: modelData.current
              elide: Text.ElideRight
            }
            MouseArea {
              id: rowArea
              anchors.fill: parent
              enabled: !modelData.current
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: modelData.trackId ? root.playTrack(modelData.trackId) : root.playIndex(modelData.index)
            }
          }
        }
      }
    }
  }
  component MediaButton: Rectangle {
    property string glyph: ""
    property bool filled: false
    property bool compact: false
    signal clicked()
    radius: width / 2
    opacity: enabled ? 1 : 0.32
    color: filled ? root.popupForeground : (buttonArea.containsMouse && enabled ? Qt.alpha(root.popupForeground, 0.13) : "transparent")
    Text {
      anchors.centerIn: parent
      text: parent.glyph
      color: parent.filled ? root.popupBackground : root.popupForeground
      font.family: bar ? bar.fontFamily : undefined
      font.pixelSize: parent.compact ? 11 : (parent.width > 40 ? 20 : 16)
      font.bold: parent.compact
    }
    MouseArea {
      id: buttonArea
      anchors.fill: parent
      enabled: parent.enabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: parent.clicked()
    }
  }
  function send(action, args) {
    if (mediaService) mediaService.send(action, args || [])
  }
  function playIndex(index) {
    send("play-index", [index])
  }
  function playTrack(trackId) {
    send("play-track", [trackId, root.media.source])
  }
  function seek(fraction) {
    if (root.media.canSeek && root.media.duration > 0) send("seek", [fraction * root.media.duration])
  }
  function seekRelative(seconds) {
    if (root.media.canSeek) send("seek-relative", [seconds])
  }
  function scheduleHoverClose() {
    if (!root.popupPinned) hoverCloseTimer.restart()
  }
  function openPinned() {
    if (!root.popupEligible) return
    hoverCloseTimer.stop()
    root.popupOpen = true
    if (!root.popupPinned && root.bar && root.hostWidget)
      root.bar.requestPopout(root.hostWidget)
    root.popupPinned = true
    popupFocusItem.forceActiveFocus()
  }
  function closePopup() {
    hoverCloseTimer.stop()
    if (root.popupPinned && root.bar && root.hostWidget)
      root.bar.releasePopout(root.hostWidget)
    root.popupPinned = false
    root.popupOpen = false
    root.queueExpanded = false
  }
  function formatTime(value) {
    if (!isFinite(value) || value < 0) return "0:00"
    const total = Math.floor(value)
    const seconds = total % 60
    const minutes = Math.floor(total / 60) % 60
    const hours = Math.floor(total / 3600)
    const sec = seconds < 10 ? "0" + seconds : seconds
    return hours > 0 ? hours + ":" + (minutes < 10 ? "0" + minutes : minutes) + ":" + sec : minutes + ":" + sec
  }
}
