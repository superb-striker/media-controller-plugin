import json
import sys

import dbus
from gi.repository import GLib

from . import mpv
from .model import build_state, pick_player, player_base
from .mpris import MprisClient, MprisMonitor
from .selection import read_selection, write_selection


class Controller:
  def __init__(self, players, mpris_client, mpv_state, mpv_play_index):
    self.players = players
    self.mpris = mpris_client
    self.mpv_state = mpv_state
    self.mpv_play_index = mpv_play_index

  def selected(self):
    preferred = read_selection()
    chosen, preference_kept = pick_player(self.players(), preferred)
    if preferred and not preference_kept:
      write_selection(None)
    return chosen

  def state(self):
    preferred = read_selection()
    state, preference_kept = build_state(self.players(), preferred, self.mpv_state())
    if preferred and not preference_kept:
      write_selection(None)
      state, _ = build_state(self.players(), None, self.mpv_state())
    return state

  def command(self, action, args):
    target = self.selected()
    if action in ("play-pause", "previous", "next"):
      return bool(target and self.mpris.transport(target["name"], action))
    if action == "seek" and len(args) == 1:
      return bool(target and self.mpris.set_position(target["name"], float(args[0])))
    if action == "seek-relative" and len(args) == 1:
      return bool(target and self.mpris.seek_relative(target["name"], float(args[0])))
    if action == "play-index" and len(args) == 1:
      return bool(target and player_base(target["name"]) == "mpv" and self.mpv_play_index(int(args[0])))
    if action == "play-track" and len(args) == 2:
      return self.mpris.goto(str(args[1]), str(args[0]))
    if action == "select-source":
      previous = target
      write_selection(args[0] if args else None)
      current = self.selected()
      if previous and previous.get("status") == "Playing":  # noqa: SIM102
        if not current or current["name"] != previous["name"]:
          self.mpris.pause(previous["name"])
      return True
    return False


class MediaService:
  def __init__(self):
    self.last_emit = None
    self.loop = GLib.MainLoop()
    self.mpris_monitor = MprisMonitor(self.emit_state)
    self.mpv_monitor = mpv.MpvMonitor(self.emit_state)
    self.controller = Controller(
      self.mpris_monitor.values,
      self.mpris_monitor.client,
      self.mpv_monitor.state,
      self.mpv_monitor.play_index,
    )
    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, self._stdin_ready)
    GLib.timeout_add_seconds(1, self._position_tick)
    GLib.timeout_add_seconds(10, self._position_resync)

  def emit_state(self, force=False):
    state = self.controller.state()
    compact = json.dumps(state, separators=(",", ":"))
    if force or compact != self.last_emit:
      try:
        print(compact, flush=True)
      except BrokenPipeError:
        self.loop.quit()
        return
      self.last_emit = compact

  def _position_tick(self):
    target = self.controller.selected()
    if target and target.get("status") == "Playing":
      self.emit_state()
    return True

  def _position_resync(self):
    self.mpris_monitor.refresh_positions()
    return True

  def _refresh_after_command(self):
    target = self.controller.selected()
    if target:
      self.mpris_monitor.refresh(target["service"])
    else:
      self.emit_state(True)
    return False

  def _stdin_ready(self, _source, condition):
    if condition & GLib.IO_HUP:
      self.loop.quit()
      return False
    line = sys.stdin.readline()
    if not line:
      self.loop.quit()
      return False
    try:
      message = json.loads(line)
      self.controller.command(message.get("action", ""), message.get("args", []))
      GLib.timeout_add(100, self._refresh_after_command)
    except (ValueError, TypeError, dbus.DBusException):
      pass
    return True

  def run(self):
    self.emit_state(True)
    self.loop.run()


def one_shot_controller():
  client = MprisClient()
  players = client.scan()

  def play_index(index):
    selected = mpv.send(["playlist-play-index", index])
    resumed = mpv.send(["set_property", "pause", False])
    return selected and resumed

  return Controller(lambda: players, client, mpv.snapshot, play_index)
