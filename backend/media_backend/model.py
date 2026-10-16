import os
import time
from pathlib import Path
from urllib.parse import unquote, urlparse

from .config import ART_EXTENSIONS, SEEK_STEP_SECONDS

EMPTY_STATE = {
  "available": False, "playing": False, "title": "", "artist": "",
  "album": "", "position": 0, "duration": 0, "playlistPos": -1,
  "path": "", "art": "", "queue": [], "hasQueue": False,
  "source": "", "sources": [], "canSeek": False,
  "canGoNext": False, "canGoPrevious": False, "canPlayPause": False,
  "seekStep": SEEK_STEP_SECONDS, "autoSelected": True
}


def player_base(name):
  return (name or "").split(".")[0].lower()


def friendly_name(player):
  identity = str(player.get("identity", "")).strip()
  return identity or player_base(player.get("name", "")).capitalize() or "Player"


def priority_score(player):
  return 0 if player["status"] == "Playing" else 1


def active_players(players):
  return [player for player in players if player.get("status") in ("Playing", "Paused")]


def pick_player(players, preferred=None):
  players = active_players(players)
  if not players:
    return None, preferred is None

  if preferred:
    match = next((player for player in players if player["name"] == preferred), None)
    if match:
      return match, True

  return min(players, key=priority_score), preferred is None


def current_position(player):
  position = float(player.get("position", 0) or 0)
  sampled_at = float(player.get("positionSampledAt", 0) or 0)
  if player.get("status") == "Playing" and sampled_at:
    position += max(0.0, time.monotonic() - sampled_at)
  duration = float(player.get("duration", 0) or 0)
  return min(position, duration) if duration > 0 else position


def find_art(path):
  if not path:
    return ""
  parsed = urlparse(path)
  if parsed.scheme and parsed.scheme != "file":
    return ""
  path = unquote(parsed.path) if parsed.scheme == "file" else os.path.expanduser(path)
  if not os.path.isfile(path):
    return ""
  directory = os.path.dirname(path)
  stem = os.path.splitext(os.path.basename(path))[0]
  candidates = [os.path.join(directory, stem + ext) for ext in ART_EXTENSIONS]
  for name in ("cover", "Cover", "folder", "Folder", "front", "Front", "AlbumArt", "albumart"):
    candidates.extend(os.path.join(directory, name + ext) for ext in ART_EXTENSIONS)
  for candidate in candidates:
    if os.path.isfile(candidate):
      return Path(candidate).as_uri()
  return ""


def mpv_matches_player(player_path, ipc_path, mpv_player_count):
  if not ipc_path:
    return False
  if not player_path:
    return mpv_player_count == 1
  parsed = urlparse(player_path)
  if parsed.scheme and parsed.scheme != "file":
    return False
  local_path = unquote(parsed.path) if parsed.scheme == "file" else player_path
  return os.path.realpath(local_path) == os.path.realpath(ipc_path)


def build_state(players, preferred=None, mpv_state=None):
  players = active_players(players)
  chosen, preference_kept = pick_player(players, preferred)
  if chosen is None:
    return dict(EMPTY_STATE), preference_kept

  queue = chosen.get("queue", [])
  playlist_pos = chosen.get("playlistPos", -1)
  path = chosen.get("path", "")
  art = chosen.get("art", "")

  mpv_player_count = sum(player_base(player["name"]) == "mpv" for player in players)
  if (player_base(chosen["name"]) == "mpv" and mpv_state and mpv_state.get("available")
      and mpv_matches_player(path, mpv_state.get("path", ""), mpv_player_count)):
    queue = mpv_state.get("queue", [])
    playlist_pos = mpv_state.get("playlistPos", -1)
    path = mpv_state.get("path") or path
  if not art:
    art = find_art(path)

  labels = [friendly_name(player) for player in players]

  sources = [{
    "name": player["name"],
    "label": label if labels.count(label) == 1 else f"{label} ({player['name']})",
    "title": player.get("title") or label,
    "artist": player.get("artist", ""),
    "playing": player["status"] == "Playing",
    "selected": player["name"] == chosen["name"]
  } for player, label in zip(players, labels)]

  return {
    "available": True,
    "playing": chosen["status"] == "Playing",
    "title": chosen.get("title") or friendly_name(chosen),
    "artist": chosen.get("artist", ""),
    "album": chosen.get("album", ""),
    "position": current_position(chosen),
    "duration": chosen.get("duration", 0),
    "playlistPos": playlist_pos,
    "path": path,
    "art": art,
    "queue": queue,
    "hasQueue": len(queue) > 0,
    "source": chosen["name"],
    "canSeek": bool(chosen.get("canSeek", False)),
    "canGoNext": bool(chosen.get("canGoNext", False)),
    "canGoPrevious": bool(chosen.get("canGoPrevious", False)),
    "canPlayPause": bool(chosen.get("canPause") if chosen["status"] == "Playing" else chosen.get("canPlay")),
    "seekStep": SEEK_STEP_SECONDS,
    "sources": sources,
    "autoSelected": preferred is None
  }, preference_kept
