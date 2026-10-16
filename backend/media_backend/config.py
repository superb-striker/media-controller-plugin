import os

MPRIS_PREFIX = "org.mpris.MediaPlayer2."
MPRIS_PATH = "/org/mpris/MediaPlayer2"
PLAYER_INTERFACE = "org.mpris.MediaPlayer2.Player"
TRACKLIST_INTERFACE = "org.mpris.MediaPlayer2.TrackList"
PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"
DBUS_INTERFACE = "org.freedesktop.DBus"
DBUS_PATH = "/org/freedesktop/DBus"

MPV_SOCKET = os.environ.get("MPV_SOCKET", "/tmp/mpv-socket")
SELECTION_FILE = os.environ.get(
  "MEDIA_CONTROLLER_SELECTION_FILE",
  os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), f"media-controller-selected-{os.getuid()}")
)
SEEK_STEP_SECONDS = 10
ART_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".avif")
ROOT_INTERFACE = "org.mpris.MediaPlayer2"
