import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Command Pulse: runs a user-configured shell command on an interval and
// shows its output live in the bar, ANSI colors and all. Left-click reruns
// the command immediately; hover shows the command, status, and full output.
BarWidget {
  id: root
  moduleName: "io.github.giuliano-sn.command-pulse"

  readonly property string command: setting("command", "uptime -p")
  readonly property int intervalValue: Math.max(1, parseInt(setting("intervalValue", 30)) || 30)
  readonly property string intervalUnit: setting("intervalUnit", "seconds")
  readonly property int maxLength: Math.max(0, parseInt(setting("maxLength", 60)) || 0)
  readonly property bool showIcon: setting("showIcon", true) === true
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true

  readonly property bool configured: command.replace(/^\s+|\s+$/g, "").length > 0

  readonly property int unitMultiplierSec: intervalUnit === "hours" ? 3600 : (intervalUnit === "minutes" ? 60 : 1)
  readonly property int intervalMs: Math.max(1000, intervalValue * unitMultiplierSec * 1000)

  property string rawOutput: ""
  property string rawError: ""
  property int lastExitCode: 0
  property bool hasRunOnce: false
  property bool running: false
  property double lastRunAt: 0

  // What actually feeds the bar/tooltip: stdout, falling back to stderr when
  // the command printed nothing but still had something to say.
  readonly property string effectiveOutput: rawOutput.length > 0 ? rawOutput : rawError

  readonly property var barMarkup: hasRunOnce ? Model.barMarkup(effectiveOutput, root.maxLength) : { html: "", plain: "", isEmpty: true }

  readonly property bool isError: configured && hasRunOnce && lastExitCode !== 0
  readonly property bool isEmpty: configured && hasRunOnce && barMarkup.isEmpty

  readonly property string statusLine: !configured
    ? "No command configured"
    : !hasRunOnce
      ? "Waiting for first run…"
      : (isError ? ("Exit code " + lastExitCode) : "OK") + " · updated " + updatedAtLabel + " · every " + intervalValue + " " + intervalUnit

  readonly property string updatedAtLabel: lastRunAt > 0 ? Qt.formatTime(new Date(lastRunAt), "HH:mm:ss") : "—"

  readonly property string tooltipHtml: configured
    ? Model.tooltipMarkup(command, statusLine, effectiveOutput)
    : "<b>Command Pulse</b><br/>Set a command in the widget settings to get started."

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: !(hideWhenEmpty && isEmpty)

  function refresh() {
    if (!root.configured || runProc.running) return
    root.running = true
    runProc.command = ["bash", "-lc", root.command]
    runProc.running = true
  }

  Process {
    id: runProc
    stdout: StdioCollector {
      id: outCollector
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: errCollector
      waitForEnd: true
    }
    onExited: function (exitCode) {
      root.rawOutput = outCollector.text
      root.rawError = errCollector.text
      root.lastExitCode = exitCode
      root.lastRunAt = Date.now()
      root.hasRunOnce = true
      root.running = false
    }
  }

  Timer {
    interval: root.intervalMs
    running: root.configured
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.moduleName

    function refresh(): void { root.broadcast("refresh") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.showIcon || outputLabel.text.length > 0
    tooltipText: root.tooltipHtml
    active: root.isError
    fixedHeight: root.barSize
    fixedWidth: root.vertical ? root.barSize : Math.max(12, contentRow.implicitWidth + scaledHorizontalMargin * 2)

    onPressed: function (buttonCode) { root.refresh() }

    Row {
      id: contentRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: root.showIcon ? Style.space(6) : 0

      Text {
        visible: root.showIcon
        anchors.verticalCenter: parent.verticalCenter
        text: "" // Nerd Font: terminal glyph
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      Text {
        id: outputLabel
        anchors.verticalCenter: parent.verticalCenter
        text: !root.configured ? "configure command" : (root.hasRunOnce ? root.barMarkup.html : "…")
        textFormat: Text.StyledText
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }

    Text {
      visible: root.vertical
      anchors.centerIn: parent
      text: ""
      color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
    }
  }
}
