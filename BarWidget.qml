import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.superb-striker.media-controller"

  readonly property var mediaService: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var media: mediaService ? mediaService.media : ({ available: false })
  readonly property bool hasPlayer: !!media.available
  readonly property bool opened: preview.popupPinned

  function send(action, args) {
    if (mediaService) mediaService.send(action, args || [])
  }

  function open() {
    if (hasPlayer) preview.openPinned()
  }

  function close() {
    preview.closePopup()
  }

  function closeForPopoutSwitch() {
    close()
  }

  visible: hasPlayer
  implicitWidth: hasPlayer ? controls.implicitWidth : 0
  implicitHeight: barSize

  Row {
    id: controls
    anchors.fill: parent
    spacing: Math.max(1, Math.round(root.barSize / 13))

    TransportButton {
      glyph: "󰒮"
      enabled: root.hasPlayer && !!root.media.canGoPrevious
      onClicked: root.send("previous")
    }
    TransportButton {
      glyph: root.media.playing ? "󰏤" : "󰐊"
      enabled: root.hasPlayer && !!root.media.canPlayPause
      onClicked: root.send("play-pause")
    }
    TransportButton {
      glyph: "󰒭"
      enabled: root.hasPlayer && !!root.media.canGoNext
      onClicked: root.send("next")
    }
    Preview {
      id: preview
      bar: root.bar
      moduleName: root.moduleName
      settings: root.settings
      mediaService: root.mediaService
      hostWidget: root
    }
  }

  component TransportButton: Item {
    property string glyph: ""
    signal clicked()
    implicitWidth: root.barSize
    implicitHeight: root.barSize
    opacity: enabled ? 1 : 0.35

    Text {
      anchors.centerIn: parent
      text: parent.glyph
      color: root.bar ? root.bar.foreground : "white"
      font.family: root.bar ? root.bar.fontFamily : undefined
      font.pixelSize: preview.fontPx
    }
    MouseArea {
      anchors.fill: parent
      enabled: parent.enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: parent.clicked()
    }
  }
}
