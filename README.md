# Media Controller for Omarchy

An artwork-focused bar widget for MPRIS media players. Hover for a compact
preview; click the preview to pin a larger view with source selection and a
track list. The service ships as Quickshell code in this repository.

## Features

- Discovers running MPRIS players and lets you switch between them, including
  separate instances of the same player.
- Uses MPRIS capabilities for play/pause, previous/next, seeking, and TrackList
  selection. Unsupported controls are disabled.
- Shows album art when available and falls back to the current Omarchy theme.
- Uses mpv IPC, when configured, for mpv's playlist and local artwork fallback.
  Other players work through MPRIS without mpv.
- Runs one Quickshell service for the whole plugin, including multiple monitors.

## Requirements

- Omarchy Quattro with plugin support
- An MPRIS-compatible media player

No extra package installation is needed on Omarchy. Quickshell handles normal
MPRIS controls, and the service uses Omarchy's existing `busctl` (from
systemd) for MPRIS TrackList, which Quickshell does not expose.

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
is active.

## Development

The plugin is composed of `BarWidget.qml`, `Preview.qml`, and `Service.qml`.
The service uses Quickshell's MPRIS API, short-lived `busctl` calls plus a
D-Bus signal monitor for TrackList, and Quickshell's Unix socket for the
optional mpv playlist. It does not launch a Python or Rust backend.

Validate the plugin and lint the QML before release:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Preview.qml Service.qml
```

## Removal

```bash
omarchy plugin remove io.github.superb-striker.media-controller
```

Removing the plugin does not change your mpv configuration.

## License

MIT
