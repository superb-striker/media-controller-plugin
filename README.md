# Media Controller for Omarchy

An artwork-focused bar widget for MPRIS media players. Hover for a compact
preview; click the preview to pin a larger view with source selection and a
track list. The backend ships in this repository and starts with the plugin.

## Features

- Discovers running MPRIS players and lets you switch between them, including
  separate instances of the same player.
- Uses MPRIS capabilities for play/pause, previous/next, seeking, and TrackList
  selection. Unsupported controls are disabled.
- Shows album art when available and falls back to the current Omarchy theme.
- Uses mpv IPC, when configured, for mpv's playlist and local artwork fallback.
  Other players work through MPRIS without mpv.
- Runs one event-driven Python backend for the whole plugin, including multiple
  monitors.

## Requirements

- Omarchy Quattro with plugin support
- Python 3, `python-dbus`, and `python-gobject`
- An MPRIS-compatible media player

On Omarchy, install the Python bindings once:

```bash
omarchy pkg add python python-dbus python-gobject
```

The Python backend source is bundled with the plugin. Omarchy's plugin manager
clones and validates repositories; it does not run install hooks or install
system packages, so the Python runtime bindings remain a system dependency.

## Install

From a local checkout:

```bash
omarchy plugin validate .
omarchy plugin add "$PWD" --enable
```

After publishing this repository, use its GitHub URL instead:

```bash
omarchy plugin add https://github.com/superb-striker/media-controller-plugin.git --enable
```

Omarchy places the widget in the right bar section by default. If an older
manual installation of `media-title`, `media-prev`, `media-play-pause`, and
`media-next` is still configured in your bar, remove those entries to avoid
duplicate controls.

The plugin uses Omarchy's own-service API, which the built-in bar exposes to
third-party widgets. Some replacement bars may not expose that service API.

## Optional mpv playlist integration

mpv is included with Omarchy. To expose its playlist to this plugin, add the
settings in [`config/mpv.conf`](config/mpv.conf) to your mpv configuration or
include that file from `~/.config/mpv/mpv.conf`:

```text
input-ipc-server=/tmp/mpv-socket
cover-art-auto=exact
```

Restart mpv after changing its configuration. Without the socket, mpv still
works through MPRIS if its MPRIS integration is enabled; the extra IPC playlist
features are simply unavailable. Set `MPV_SOCKET` if your socket has another
path.

## Controls

- Previous track, play/pause, and next track are visible in the bar.
- Hover over the title to see the minimal preview. Click inside to pin it;
  Escape or clicking outside closes it.
- The pinned preview has source selection and a track list. The list starts
  collapsed and includes previous and upcoming entries when the player exposes
  them through MPRIS TrackList or mpv IPC.
- Seek buttons step backward/forward ten seconds. Seeking is disabled when the
  selected player does not report `CanSeek`.

The selected source is stored in the user runtime directory while the session
is active. To override that location, set `MEDIA_CONTROLLER_SELECTION_FILE`.

## Development

The plugin is composed of `BarWidget.qml`, `Preview.qml`, and `Service.qml`.
`Service.qml` launches the bundled `backend/media-backend.py` using a path
resolved relative to its own installed location. The backend listens to D-Bus
signals and streams state to the QML service as JSON lines. Its package has no
player-specific dependency beyond the optional mpv IPC integration.

Validate the plugin and lint the QML before release:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Preview.qml Service.qml
```

## Removal

```bash
omarchy plugin remove io.github.superb-striker.media-controller
```

Removing the plugin does not remove the system Python packages or your mpv
configuration.

## License

MIT
