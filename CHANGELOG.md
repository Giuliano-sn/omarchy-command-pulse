# Changelog

## 1.1.2

- Settings form: all four spinboxes (refresh interval, max bar characters,
  popup max width/height) sized up 50% from 1.1.1 — the half-width shrink
  read as too cramped.

## 1.1.1

- Settings form: interval spinbox and the "seconds/minutes/hours" dropdown
  were sized for a wider dialog than the panel actually is — shrunk both to
  half width. The popup max width/height fields were getting clipped off
  the bottom of the form; grew the settings panel ~10% (width and height
  cap) so every field, including those two, is visible without scrolling.

## 1.1.0

- Bar face now shows the **last non-blank line** of output instead of the
  first, so a multi-line command's final status is what's visible.
- **Left-click** opens the full, multi-line, ANSI-colored output in a popup,
  capped at a configurable max width/height with scrolling beyond that.
- **Right-click** opens an in-bar settings form (command, interval, sizing)
  that writes straight back to `shell.json` — no more hand-editing required.
- **Middle-click** reruns the command immediately (previously left-click).
- Disabled multiple instances (`allowMultiple`): the shell has no per-instance
  settings storage, so a second Command Pulse widget could silently overwrite
  the first one's settings once the in-bar settings form landed.

## 1.0.0

- Initial release: bar-widget that runs a configurable shell command on a
  configurable interval (seconds/minutes/hours) and renders its output —
  including ANSI colors and styles — in the Omarchy status bar.
