import json
import select
import socket
import time

from gi.repository import GLib

from .config import MPV_SOCKET


def request(command, timeout=0.25):
  try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(MPV_SOCKET)
    sock.sendall((json.dumps({"command": command, "request_id": 1}) + "\n").encode())
    deadline = time.monotonic() + timeout
    buffer = b""
    while time.monotonic() < deadline:
      readable, _, _ = select.select([sock], [], [], max(0.01, deadline - time.monotonic()))
      if not readable:
        continue
      chunk = sock.recv(65536)
      if not chunk:
        break
      buffer += chunk
      while b"\n" in buffer:
        line, buffer = buffer.split(b"\n", 1)
        response = json.loads(line.decode())
        if response.get("request_id") == 1:
          sock.close()
          return response.get("data") if response.get("error") == "success" else None
    sock.close()
  except (OSError, ValueError, json.JSONDecodeError):
    return None
  return None


def send(command, timeout=0.25):
  try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(MPV_SOCKET)
    sock.sendall((json.dumps({"command": command, "request_id": 0}) + "\n").encode())
    sock.close()
    return True
  except OSError:
    return False


def normalize_playlist(playlist, current):
  items = []
  for index, item in enumerate(playlist or []):
    if not isinstance(item, dict):
      continue
    path = item.get("filename") or ""
    title = item.get("title") or path.rsplit("/", 1)[-1].rsplit(".", 1)[0] or path
    items.append({
      "index": index,
      "title": title,
      "path": path,
      "current": index == current,
    })
  return items


def snapshot():
  playlist = request(["get_property", "playlist"])
  if playlist is None:
    return {"available": False, "queue": [], "playlistPos": -1, "path": ""}
  current = request(["get_property", "playlist-pos"])
  current = -1 if current is None else int(current)
  return {
    "available": True,
    "queue": normalize_playlist(playlist, current),
    "playlistPos": current,
    "path": request(["get_property", "path"]) or "",
  }


class MpvMonitor:
  def __init__(self, on_change):
    self.on_change = on_change
    self.socket = None
    self.watch_id = None
    self.buffer = b""
    self.properties = {"playlist": [], "playlist-pos": -1, "path": ""}
    self._connect()
    GLib.timeout_add_seconds(2, self._ensure_connected)

  def _connect(self):
    if self.socket is not None:
      return True
    try:
      sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
      sock.connect(MPV_SOCKET)
      sock.setblocking(False)
      self.socket = sock
      self.watch_id = GLib.io_add_watch(
        sock,
        GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR,
        self._on_io,
      )
      for observer_id, name in enumerate(("playlist", "playlist-pos", "path"), start=1):
        self._send(["observe_property", observer_id, name])
      return True
    except OSError:
      self._disconnect(False)
      return False

  def _disconnect(self, remove_watch=True):
    if remove_watch and self.watch_id is not None:
      GLib.source_remove(self.watch_id)
    self.watch_id = None
    if self.socket is not None:
      try:
        self.socket.close()
      except OSError:
        pass
    self.socket = None
    self.buffer = b""
    self.properties = {"playlist": [], "playlist-pos": -1, "path": ""}

  def _ensure_connected(self):
    if self.socket is None and self._connect():
      self.on_change()
    return True

  def _send(self, command):
    if self.socket is None:
      return False
    try:
      self.socket.sendall((json.dumps({"command": command}) + "\n").encode())
      return True
    except OSError:
      self._disconnect()
      return False

  def _on_io(self, _source, condition):
    if condition & (GLib.IO_HUP | GLib.IO_ERR):
      self.watch_id = None
      self._disconnect(False)
      self.on_change()
      return False
    try:
      chunk = self.socket.recv(65536)
    except BlockingIOError:
      return True
    except OSError:
      chunk = b""
    if not chunk:
      self.watch_id = None
      self._disconnect(False)
      self.on_change()
      return False
    self.buffer += chunk
    changed = False
    while b"\n" in self.buffer:
      line, self.buffer = self.buffer.split(b"\n", 1)
      try:
        message = json.loads(line.decode())
      except (UnicodeDecodeError, json.JSONDecodeError):
        continue
      if message.get("event") != "property-change":
        continue
      name = message.get("name")
      if name in self.properties:
        self.properties[name] = message.get("data")
        changed = True
    if changed:
      self.on_change()
    return True

  def state(self):
    current = self.properties.get("playlist-pos")
    current = -1 if current is None else int(current)
    return {
      "available": self.socket is not None,
      "queue": normalize_playlist(self.properties.get("playlist"), current),
      "playlistPos": current,
      "path": self.properties.get("path") or "",
    }

  def play_index(self, index):
    selected = self._send(["playlist-play-index", int(index)])
    resumed = self._send(["set_property", "pause", False])
    return selected and resumed
