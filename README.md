# Command Pulse

An [Omarchy](https://omarchy.org/) shell bar widget that runs a shell
command on a schedule and shows its live output right in the status bar —
including ANSI colors, so a command that colors its own output (`git status
--short`, a healthcheck script, `ls --color`, a custom CLI, …) looks the
same in the bar as it does in your terminal.

## Features

- Runs **any shell command** (`bash -lc "<command>"`), on your schedule.
- Interval configurable in **seconds, minutes, or hours**.
- Renders **ANSI SGR colors and styles** (16-color, 256-color, and truecolor
  foreground, plus bold, dim, italic, underline, strikethrough, inverse) as
  real color in the bar — not just plain text.
- Hover for a tooltip with the full command, last status, and full output.
- Left-click to re-run the command immediately.
- Multiple instances allowed — add one Command Pulse widget per command.

## Install

```sh
omarchy plugin add https://github.com/Giuliano-sn/omarchy-command-pulse
```

Or clone manually into `~/.config/omarchy/plugins/` and enable it:

```sh
git clone https://github.com/Giuliano-sn/omarchy-command-pulse \
  ~/.config/omarchy/plugins/io.github.giuliano-sn.command-pulse
omarchy plugin enable io.github.giuliano-sn.command-pulse --section right
```

## Configuration

Configure the widget from the Omarchy bar widget settings, or by editing its
entry under `bar.layout.<section>` in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.giuliano-sn.command-pulse",
  "command": "git status --short | head -1",
  "intervalValue": 30,
  "intervalUnit": "seconds",
  "maxLength": 60,
  "showIcon": true,
  "hideWhenEmpty": false
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `command` | string | `uptime -p` | Shell command to run via `bash -lc`. |
| `intervalValue` | integer | `30` | How often to run it. |
| `intervalUnit` | enum (`seconds`, `minutes`, `hours`) | `seconds` | Unit for `intervalValue`. |
| `maxLength` | integer | `60` | Truncate the bar label past this many visible characters (`0` = no limit). The tooltip always shows the full output. |
| `showIcon` | boolean | `true` | Show a terminal glyph before the output. |
| `hideWhenEmpty` | boolean | `false` | Hide the widget entirely when the command's output is empty. |

Only the first line of output is shown on the bar face (bar space is
limited); the tooltip shows the full, multi-line, ANSI-colored output,
capped defensively at 40 lines / 4000 characters for very chatty commands.

If the command's stdout is empty but it printed something to stderr, that is
shown instead (and the bar face turns the bar's "urgent" color when the
command exits non-zero).

## Why "ANSI colors, respected"

The widget parses SGR (`ESC[...m`) escape codes out of the command's output
and converts them into the small subset of rich text QML's `Text.StyledText`
actually understands (`<font color="...">`, `<b>`, `<i>`, `<u>`, `<s>`) — so
a `\x1b[32mOK\x1b[0m` in your script's output really does show up green in
the bar, at the exact color the terminal would have used. Background colors
are approximated by swapping the foreground when a command uses "inverse"
video, since the bar's lightweight text renderer has no fill/highlight tag
to paint an actual background with.

## License

MIT — see [LICENSE](LICENSE).
