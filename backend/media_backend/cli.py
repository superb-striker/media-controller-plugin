import json
import sys

from dbus.mainloop.glib import DBusGMainLoop

from .service import MediaService, one_shot_controller

USAGE = (
  "usage: media-backend.py daemon | state | command "
  "<play-pause|previous|next|play-index|play-track|seek|seek-relative|select-source>"
)


def main(argv=None):
  argv = list(sys.argv[1:] if argv is None else argv)
  if not argv:
    print(USAGE)
    return 1

  mode = argv[0]
  if mode == "daemon":
    DBusGMainLoop(set_as_default=True)
    MediaService().run()
    return 0
  if mode == "state":
    print(json.dumps(one_shot_controller().state(), separators=(",", ":")))
    return 0
  if mode == "command" and len(argv) > 1:
    return 0 if one_shot_controller().command(argv[1], argv[2:]) else 1

  print(USAGE)
  return 1
