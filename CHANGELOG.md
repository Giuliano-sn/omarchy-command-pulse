# Changelog

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
