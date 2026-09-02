.pragma library

// ANSI SGR -> Qt rich text conversion, plus small text-safety helpers, for
// Command Pulse. Kept dependency-free (plain ECMAScript) so it loads as a
// Quickshell JS module without any QtQml import.

var ESC = ""

// Standard 16-color xterm/GNOME Terminal palette. Used both directly for
// SGR 30-37/40-47/90-97/100-107 and as the low end of the 256-color table.
var PALETTE16 = [
  "#000000", "#cc0000", "#4e9a06", "#c4a000",
  "#3465a4", "#75507b", "#06989a", "#d3d7cf",
  "#555753", "#ef2929", "#8ae234", "#fce94f",
  "#729fcf", "#ad7fa8", "#34e2e2", "#eeeeec"
]

// Safety caps for the full-output popup — generous, but a runaway command
// (a busy log tail, say) still can't be allowed to freeze the panel.
var VIEW_MAX_CHARS = 20000
var VIEW_MAX_LINES = 500

// Safety caps for the command process itself. StdioCollector buffers a
// stream's bytes in full until the process exits, so without these a noisy
// producer (a busy log tail) or a hung one (a stuck network call) can grow
// without bound or block the long-lived shell process indefinitely. The
// byte cap is enforced at the source, before Quickshell ever sees the
// bytes; the deadline guarantees the process — and the run it belongs to —
// eventually ends no matter what the command does.
var RUN_TIMEOUT_SEC = 15
var RUN_KILL_AFTER_SEC = 2
var RUN_OUTPUT_BYTE_CAP = 262144
// GNU coreutils `timeout` exit codes: 124 = deadline hit, ran to term;
// 128+9 = still alive after the kill-after grace period, sent SIGKILL.
var TIMEOUT_EXIT_CODE = 124
var TIMEOUT_KILLED_EXIT_CODE = 137

function clamp(n, lo, hi) {
  return Math.max(lo, Math.min(hi, n))
}

function toHex2(n) {
  var s = clamp(Math.round(n), 0, 255).toString(16)
  return s.length === 1 ? "0" + s : s
}

function rgbToHex(r, g, b) {
  return "#" + toHex2(r) + toHex2(g) + toHex2(b)
}

function ansi256ToHex(n) {
  n = clamp(parseInt(n, 10) || 0, 0, 255)
  if (n < 16) return PALETTE16[n]
  if (n <= 231) {
    var i = n - 16
    var levels = [0, 95, 135, 175, 215, 255]
    var r = Math.floor(i / 36)
    var g = Math.floor((i % 36) / 6)
    var b = i % 6
    return rgbToHex(levels[r], levels[g], levels[b])
  }
  var v = 8 + (n - 232) * 10
  return rgbToHex(v, v, v)
}

function mixTowardGray(hex, ratio) {
  var r = parseInt(hex.substr(1, 2), 16)
  var g = parseInt(hex.substr(3, 2), 16)
  var b = parseInt(hex.substr(5, 2), 16)
  var gray = 128
  return rgbToHex(
    r + (gray - r) * ratio,
    g + (gray - g) * ratio,
    b + (gray - b) * ratio
  )
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function defaultStyle() {
  return { fg: null, bg: null, bold: false, dim: false, italic: false, underline: false, strike: false, inverse: false }
}

function cloneStyle(s) {
  return {
    fg: s.fg, bg: s.bg, bold: s.bold, dim: s.dim,
    italic: s.italic, underline: s.underline, strike: s.strike, inverse: s.inverse
  }
}

function applySgr(state, codes) {
  for (var k = 0; k < codes.length; k++) {
    var raw = codes[k]
    var code = raw === "" ? 0 : parseInt(raw, 10)
    if (isNaN(code)) continue

    if (code === 0) {
      var fresh = defaultStyle()
      for (var key in fresh) state[key] = fresh[key]
    } else if (code === 1) state.bold = true
    else if (code === 2) state.dim = true
    else if (code === 3) state.italic = true
    else if (code === 4) state.underline = true
    else if (code === 7) state.inverse = true
    else if (code === 9) state.strike = true
    else if (code === 21) state.bold = false
    else if (code === 22) { state.bold = false; state.dim = false }
    else if (code === 23) state.italic = false
    else if (code === 24) state.underline = false
    else if (code === 27) state.inverse = false
    else if (code === 29) state.strike = false
    else if (code >= 30 && code <= 37) state.fg = PALETTE16[code - 30]
    else if (code === 38) {
      if (codes[k + 1] === "5") { state.fg = ansi256ToHex(codes[k + 2]); k += 2 }
      else if (codes[k + 1] === "2") { state.fg = rgbToHex(codes[k + 2] || 0, codes[k + 3] || 0, codes[k + 4] || 0); k += 4 }
    }
    else if (code === 39) state.fg = null
    else if (code >= 40 && code <= 47) state.bg = PALETTE16[code - 40]
    else if (code === 48) {
      if (codes[k + 1] === "5") { state.bg = ansi256ToHex(codes[k + 2]); k += 2 }
      else if (codes[k + 1] === "2") { state.bg = rgbToHex(codes[k + 2] || 0, codes[k + 3] || 0, codes[k + 4] || 0); k += 4 }
    }
    else if (code === 49) state.bg = null
    else if (code >= 90 && code <= 97) state.fg = PALETTE16[8 + (code - 90)]
    else if (code >= 100 && code <= 107) state.bg = PALETTE16[8 + (code - 100)]
  }
}

// Parses raw command output (which may contain ANSI SGR color/style codes,
// other CSI/OSC escapes, and newlines) into a flat list of
// { text, style } runs. Non-SGR escapes (cursor moves, OSC titles/links,
// etc.) are recognized and dropped rather than leaking into the text.
function parseAnsi(raw) {
  var text = String(raw || "")
  var segments = []
  var state = defaultStyle()
  var buf = ""
  var i = 0

  function flush() {
    if (buf.length > 0) {
      segments.push({ text: buf, style: cloneStyle(state) })
      buf = ""
    }
  }

  while (i < text.length) {
    var ch = text.charAt(i)

    if (ch === ESC && text.charAt(i + 1) === "[") {
      var j = i + 2
      while (j < text.length && !/[\x40-\x7e]/.test(text.charAt(j))) j++
      var finalByte = text.charAt(j)
      var params = text.slice(i + 2, j)
      if (finalByte === "m") {
        flush()
        applySgr(state, params.split(";"))
      }
      i = j + 1
      continue
    }

    if (ch === ESC && text.charAt(i + 1) === "]") {
      var bel = text.indexOf("", i)
      var st = text.indexOf(ESC + "\\", i)
      var end = -1
      if (bel !== -1 && (st === -1 || bel < st)) end = bel + 1
      else if (st !== -1) end = st + 2
      i = end === -1 ? text.length : end
      continue
    }

    if (ch === ESC) { i++; continue }
    if (ch === "\r") { i++; continue }

    buf += ch
    i++
  }
  flush()
  return segments
}

// QML's Text.StyledText renderer is a lightweight parser, not a full
// QTextDocument HTML engine: it only understands a handful of legacy tags
// (<font color="...">, <b>, <i>, <u>, <s>, <br>) and silently drops CSS-style
// attributes such as `<span style="...">` or `background-color`. So color
// goes out as <font color>, never <span style>, and background/inverse is
// approximated by swapping the foreground color rather than painting a fill.
function styledOpenClose(style) {
  var fg = style.fg
  if (style.inverse) fg = style.bg || "#000000"
  if (style.dim && fg) fg = mixTowardGray(fg, 0.45)

  var open = "", close = ""
  if (fg) {
    open += '<font color="' + fg + '">'
    close = "</font>" + close
  }
  if (style.bold) { open += "<b>"; close = "</b>" + close }
  if (style.italic) { open += "<i>"; close = "</i>" + close }
  if (style.underline) { open += "<u>"; close = "</u>" + close }
  if (style.strike) { open += "<s>"; close = "</s>" + close }
  return { open: open, close: close }
}

function segmentsToHtml(segments) {
  var parts = []
  for (var i = 0; i < segments.length; i++) {
    var seg = segments[i]
    var escaped = escapeHtml(seg.text).replace(/\n/g, "<br/>")
    var tags = styledOpenClose(seg.style)
    parts.push(tags.open + escaped + tags.close)
  }
  return parts.join("")
}

function segmentsPlainLength(segments) {
  var n = 0
  for (var i = 0; i < segments.length; i++) n += segments[i].text.length
  return n
}

// Caps a segment list to `maxChars` visible characters (0 = unlimited),
// appending an ellipsis to whatever survives when it truncates something.
function truncateSegments(segments, maxChars) {
  if (!maxChars || maxChars <= 0) return segments
  var result = []
  var used = 0
  var truncated = false
  for (var i = 0; i < segments.length; i++) {
    var seg = segments[i]
    if (used >= maxChars) { truncated = true; break }
    var remaining = maxChars - used
    if (seg.text.length <= remaining) {
      result.push(seg)
      used += seg.text.length
    } else {
      result.push({ text: seg.text.slice(0, remaining), style: seg.style })
      used = maxChars
      truncated = true
      break
    }
  }
  if (truncated) {
    if (result.length === 0) result.push({ text: "", style: defaultStyle() })
    var last = result[result.length - 1]
    result[result.length - 1] = { text: last.text + "…", style: last.style }
  }
  return result
}

// Last line of the output that has visible (non-ANSI, non-whitespace)
// content — trailing blank lines a command prints (a final newline, a
// spacer) are skipped so the bar face always shows something meaningful.
function lastNonEmptyLine(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = lines.length - 1; i >= 0; i--) {
    var candidate = lines[i].replace(/\r$/, "")
    var plain = stripAnsi(candidate).replace(/^[ \t]+|[ \t]+$/g, "")
    if (plain.length > 0) return candidate.replace(/^[ \t]+|[ \t]+$/g, "")
  }
  return ""
}

// Builds the compact single-line rich text shown on the bar face itself:
// the last non-blank line of output, ANSI colors preserved, capped at
// `maxChars` visible characters (0 = unlimited).
function barMarkup(raw, maxChars) {
  var line = lastNonEmptyLine(raw)
  var segments = parseAnsi(line)
  var truncated = truncateSegments(segments, maxChars)
  return {
    html: segmentsToHtml(truncated),
    isEmpty: segmentsPlainLength(segments) === 0
  }
}

// Builds the full multi-line rich text shown in the "view output" popup,
// ANSI colors preserved, defensively capped so a runaway command can't
// freeze the panel.
function outputMarkup(raw) {
  var lines = String(raw || "").split("\n")
  var lineTruncated = lines.length > VIEW_MAX_LINES
  if (lineTruncated) lines = lines.slice(0, VIEW_MAX_LINES)
  var joined = lines.join("\n")

  var segments = parseAnsi(joined)
  var charTruncated = segmentsPlainLength(segments) > VIEW_MAX_CHARS
  var shown = truncateSegments(segments, VIEW_MAX_CHARS)
  return {
    html: segmentsToHtml(shown),
    isEmpty: segmentsPlainLength(segments) === 0,
    truncated: lineTruncated || charTruncated
  }
}

// Short plain-text hint for the hover tooltip: command + current status.
// Full output lives in the click-driven popup, not the tooltip.
function statusTooltip(command, statusLine) {
  return "<b>" + escapeHtml("$ " + command) + "</b><br/>" + escapeHtml(statusLine) +
    "<br/><i>Left-click: full output · Right-click: settings · Middle-click: run now</i>"
}

function stripAnsi(raw) {
  return segmentsToHtml(parseAnsi(String(raw || ""))).replace(/<[^>]*>/g, "")
}

// POSIX single-quoting: close the quote, emit an escaped literal quote,
// reopen it. Safe for any byte sequence a user's command string can contain.
function shellSingleQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

// Wraps the user's command so the process that actually runs it (a) cannot
// outlive a fixed wall-clock deadline and (b) cannot hand back more than a
// fixed number of bytes per stream — both enforced by the shell/coreutils
// before Quickshell's StdioCollector ever buffers a byte, not after. Exit
// code passes through unchanged from `timeout` on the normal path; 124 or
// 128+9 signal the deadline/kill cases (see TIMEOUT_EXIT_CODE below).
function wrapCommand(userCommand) {
  var quoted = shellSingleQuote(userCommand)
  var capOut = "head -c " + RUN_OUTPUT_BYTE_CAP
  return "timeout -k " + RUN_KILL_AFTER_SEC + "s " + RUN_TIMEOUT_SEC + "s bash -lc " + quoted +
    " > >(" + capOut + ") 2> >(" + capOut + " >&2)"
}

// Turns an exit code into a short human label, special-casing the two
// shapes `timeout` produces so a hung command reads as "timed out" instead
// of a bare, confusing exit code.
function exitLabel(code) {
  if (code === TIMEOUT_EXIT_CODE) return "Timed out after " + RUN_TIMEOUT_SEC + "s"
  if (code === TIMEOUT_KILLED_EXIT_CODE) return "Timed out after " + RUN_TIMEOUT_SEC + "s (killed)"
  return "Exit code " + code
}
