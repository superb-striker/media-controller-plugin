import os

from .config import SELECTION_FILE


def read_selection():
  try:
    with open(SELECTION_FILE, encoding="utf-8") as handle:
      value = handle.read().strip()
      return value or None
  except OSError:
    return None


def write_selection(name):
  try:
    if not name or name == "auto":
      if os.path.exists(SELECTION_FILE):
        os.remove(SELECTION_FILE)
    else:
      with open(SELECTION_FILE, "w", encoding="utf-8") as handle:
        handle.write(name)
  except OSError:
    pass
