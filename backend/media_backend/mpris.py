import time

import dbus

from .config import (
  DBUS_INTERFACE,
  DBUS_PATH,
  MPRIS_PATH,
  MPRIS_PREFIX,
  PLAYER_INTERFACE,
  PROPERTIES_INTERFACE,
  ROOT_INTERFACE,
  TRACKLIST_INTERFACE,
)


def service_name(name):
  return name if name.startswith(MPRIS_PREFIX) else MPRIS_PREFIX + name


def player_name(service):
  return service.removeprefix(MPRIS_PREFIX)


def seconds(value):
  try:
    return max(0.0, float(value) / 1_000_000)
  except (TypeError, ValueError):
    return 0.0


def text(value):
  return str(value) if value is not None else ""


def artist_text(value):
  if isinstance(value, (list, tuple, dbus.Array)):
    return ", ".join(str(item) for item in value if str(item))
  return text(value)


class MprisClient:
  def __init__(self, bus=None):
    self.bus = bus or dbus.SessionBus()

  def services(self):
    return sorted(name for name in self.bus.list_names() if name.startswith(MPRIS_PREFIX))

  def interfaces(self, name):
    obj = self.bus.get_object(service_name(name), MPRIS_PATH)
    return dbus.Interface(obj, PLAYER_INTERFACE), dbus.Interface(obj, PROPERTIES_INTERFACE)

  def read_player(self, service):
    _, properties = self.interfaces(service)
    values = properties.GetAll(PLAYER_INTERFACE, timeout=0.75)
    try:
      identity = text(properties.Get(ROOT_INTERFACE, "Identity", timeout=0.5))
    except dbus.DBusException:
      identity = ""
    metadata = values.get("Metadata", {})
    position = values.get("Position")
    if position is None:
      try:
        position = properties.Get(PLAYER_INTERFACE, "Position", timeout=0.5)
      except dbus.DBusException:
        position = 0
    record = {
      "service": service_name(service),
      "name": player_name(service),
      "identity": identity,
      "status": text(values.get("PlaybackStatus", "Stopped")),
      "title": text(metadata.get("xesam:title", "")),
      "artist": artist_text(metadata.get("xesam:artist", [])),
      "album": text(metadata.get("xesam:album", "")),
      "art": text(metadata.get("mpris:artUrl", "")),
      "trackId": text(metadata.get("mpris:trackid", "")),
      "path": text(metadata.get("xesam:url", "")),
      "position": seconds(position),
      "positionSampledAt": time.monotonic(),
      "duration": seconds(metadata.get("mpris:length", 0)),
      "canSeek": bool(values.get("CanSeek", False)),
      "canGoNext": bool(values.get("CanGoNext", False)),
      "canGoPrevious": bool(values.get("CanGoPrevious", False)),
      "canPlay": bool(values.get("CanPlay", False)),
      "canPause": bool(values.get("CanPause", False)),
      "queue": [],
      "playlistPos": -1,
    }
    record["queue"], record["playlistPos"] = self.read_tracklist(service, record["trackId"])
    return record

  def read_tracklist(self, service, current_id=""):
    try:
      obj = self.bus.get_object(service_name(service), MPRIS_PATH)
      properties = dbus.Interface(obj, PROPERTIES_INTERFACE)
      tracklist = dbus.Interface(obj, TRACKLIST_INTERFACE)
      track_ids = properties.Get(TRACKLIST_INTERFACE, "Tracks", timeout=0.75)
      metadata_list = tracklist.GetTracksMetadata(track_ids, timeout=1.5)
      items = []
      current_index = -1
      for index, metadata in enumerate(metadata_list):
        track_id = text(metadata.get("mpris:trackid", track_ids[index]))
        title = text(metadata.get("xesam:title", ""))
        url = text(metadata.get("xesam:url", ""))
        if not title:
          title = url.rsplit("/", 1)[-1].split("?", 1)[0] or url or "Unknown track"
        current = track_id == current_id
        if current:
          current_index = index
        items.append({
          "index": index,
          "trackId": track_id,
          "title": title,
          "path": url,
          "current": current,
        })
      return items, current_index
    except dbus.DBusException:
      return [], -1

  def scan(self):
    players = []
    for service in self.services():
      try:
        players.append(self.read_player(service))
      except dbus.DBusException:
        continue
    return players

  def position(self, name):
    _, properties = self.interfaces(name)
    return seconds(properties.Get(PLAYER_INTERFACE, "Position", timeout=0.5))

  def transport(self, name, action):
    method = {"play-pause": "PlayPause", "previous": "Previous", "next": "Next"}.get(action)
    if not method:
      return False
    try:
      player, _ = self.interfaces(name)
      getattr(player, method)(timeout=0.75)
      return True
    except dbus.DBusException:
      return False

  def pause(self, name):
    try:
      player, _ = self.interfaces(name)
      player.Pause(timeout=0.75)
      return True
    except dbus.DBusException:
      return False

  def seek_relative(self, name, offset_seconds):
    try:
      player, properties = self.interfaces(name)
      if not bool(properties.Get(PLAYER_INTERFACE, "CanSeek", timeout=0.5)):
        return False
      player.Seek(dbus.Int64(round(float(offset_seconds) * 1_000_000)), timeout=0.75)
      return True
    except (dbus.DBusException, TypeError, ValueError):
      return False

  def set_position(self, name, position_seconds):
    try:
      player, properties = self.interfaces(name)
      if not bool(properties.Get(PLAYER_INTERFACE, "CanSeek", timeout=0.5)):
        return False
      metadata = properties.Get(PLAYER_INTERFACE, "Metadata", timeout=0.5)
      track_id = metadata.get("mpris:trackid")
      if not track_id:
        return False
      player.SetPosition(
        dbus.ObjectPath(str(track_id)),
        dbus.Int64(round(float(position_seconds) * 1_000_000)),
        timeout=0.75,
      )
      return True
    except (dbus.DBusException, TypeError, ValueError):
      return False

  def goto(self, name, track_id):
    try:
      obj = self.bus.get_object(service_name(name), MPRIS_PATH)
      dbus.Interface(obj, TRACKLIST_INTERFACE).GoTo(dbus.ObjectPath(track_id), timeout=0.75)
      return True
    except (dbus.DBusException, TypeError, ValueError):
      return False


class MprisMonitor:
  def __init__(self, on_change, bus=None):
    self.client = MprisClient(bus)
    self.bus = self.client.bus
    self.on_change = on_change
    self.players = {}
    self.receivers = {}
    self.bus.add_signal_receiver(
      self._name_owner_changed,
      signal_name="NameOwnerChanged",
      dbus_interface=DBUS_INTERFACE,
      bus_name=DBUS_INTERFACE,
      path=DBUS_PATH,
    )
    for service in self.client.services():
      self._register(service)

  def values(self):
    return list(self.players.values())

  def _register(self, service):
    if service in self.receivers:
      return
    try:
      self.players[service] = self.client.read_player(service)
    except dbus.DBusException:
      return

    def properties_changed(interface, _changed, _invalidated, watched=service):
      if interface == PLAYER_INTERFACE:
        self.refresh(watched)
      elif interface == TRACKLIST_INTERFACE:
        self.refresh_tracklist(watched)

    def tracklist_changed(*_args, watched=service):
      self.refresh_tracklist(watched)

    def seeked(position, watched=service):
      player = self.players.get(watched)
      if not player:
        return
      player["position"] = seconds(position)
      player["positionSampledAt"] = time.monotonic()
      self.on_change()

    property_kwargs = {
      "signal_name": "PropertiesChanged",
      "dbus_interface": PROPERTIES_INTERFACE,
      "bus_name": service,
      "path": MPRIS_PATH,
    }
    self.bus.add_signal_receiver(properties_changed, **property_kwargs)
    registrations = [(properties_changed, property_kwargs)]

    seeked_kwargs = {
      "signal_name": "Seeked",
      "dbus_interface": PLAYER_INTERFACE,
      "bus_name": service,
      "path": MPRIS_PATH,
    }
    self.bus.add_signal_receiver(seeked, **seeked_kwargs)
    registrations.append((seeked, seeked_kwargs))

    for signal in ("TrackListReplaced", "TrackAdded", "TrackRemoved", "TrackMetadataChanged"):
      kwargs = {
        "signal_name": signal,
        "dbus_interface": TRACKLIST_INTERFACE,
        "bus_name": service,
        "path": MPRIS_PATH,
      }
      self.bus.add_signal_receiver(tracklist_changed, **kwargs)
      registrations.append((tracklist_changed, kwargs))
    self.receivers[service] = registrations

  def _unregister(self, service):
    for handler, kwargs in self.receivers.pop(service, []):
      self.bus.remove_signal_receiver(handler, **kwargs)
    self.players.pop(service, None)

  def _name_owner_changed(self, name, _old_owner, new_owner):
    name = str(name)
    if not name.startswith(MPRIS_PREFIX):
      return
    if new_owner:
      self._register(name)
    else:
      self._unregister(name)
    self.on_change()

  def refresh(self, service):
    try:
      self.players[service] = self.client.read_player(service)
    except dbus.DBusException:
      self._unregister(service)
    self.on_change()

  def refresh_tracklist(self, service):
    player = self.players.get(service)
    if not player:
      return
    queue, position = self.client.read_tracklist(service, player.get("trackId", ""))
    player["queue"] = queue
    player["playlistPos"] = position
    self.on_change()

  def refresh_positions(self):
    changed = False
    for player in list(self.players.values()):
      if player.get("status") not in ("Playing", "Paused"):
        continue
      try:
        player["position"] = self.client.position(player["name"])
        player["positionSampledAt"] = time.monotonic()
        changed = True
      except dbus.DBusException:
        continue
    if changed:
      self.on_change()
