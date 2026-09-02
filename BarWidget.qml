import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Command Pulse: runs a user-configured shell command on an interval and
// shows the last line of its output live in the bar, ANSI colors and all.
// Left-click opens the full (scrollable, size-capped) output; right-click
// opens settings; middle-click reruns the command immediately.
BarWidget {
  id: root
  moduleName: "io.github.giuliano-sn.command-pulse"

  readonly property string command: setting("command", "uptime -p")
  readonly property int intervalValue: Math.max(1, parseInt(setting("intervalValue", 30)) || 30)
  readonly property string intervalUnit: setting("intervalUnit", "seconds")
  readonly property int maxLength: Math.max(0, parseInt(setting("maxLength", 60)) || 0)
  readonly property bool showIcon: setting("showIcon", true) === true
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true
  readonly property int maxPopupWidth: Math.max(240, parseInt(setting("maxPopupWidth", 480)) || 480)
  readonly property int maxPopupHeight: Math.max(120, parseInt(setting("maxPopupHeight", 320)) || 320)

  readonly property bool configured: command.replace(/^\s+|\s+$/g, "").length > 0
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground

  readonly property int unitMultiplierSec: intervalUnit === "hours" ? 3600 : (intervalUnit === "minutes" ? 60 : 1)
  readonly property int intervalMs: Math.max(1000, intervalValue * unitMultiplierSec * 1000)

  property string rawOutput: ""
  property string rawError: ""
  property int lastExitCode: 0
  property bool hasRunOnce: false
  property double lastRunAt: 0

  // "": closed, "output": full-output popup, "settings": settings form.
  property string panelMode: ""
  readonly property bool opened: panelMode !== ""

  // Draft copies edited by the settings form; only committed on Save.
  property string draftCommand: ""
  property int draftIntervalValue: 30
  property string draftIntervalUnit: "seconds"
  property int draftMaxLength: 60
  property bool draftShowIcon: true
  property bool draftHideWhenEmpty: false
  property int draftMaxPopupWidth: 480
  property int draftMaxPopupHeight: 320

  // What actually feeds the bar/popup: stdout, falling back to stderr when
  // the command printed nothing but still had something to say.
  readonly property string effectiveOutput: rawOutput.length > 0 ? rawOutput : rawError

  readonly property var barMarkup: hasRunOnce ? Model.barMarkup(effectiveOutput, root.maxLength) : { html: "", isEmpty: true }
  readonly property var outputMarkup: hasRunOnce ? Model.outputMarkup(effectiveOutput) : { html: "", isEmpty: true, truncated: false }

  readonly property bool isError: configured && hasRunOnce && lastExitCode !== 0
  readonly property bool isEmpty: configured && hasRunOnce && barMarkup.isEmpty

  readonly property string updatedAtLabel: lastRunAt > 0 ? Qt.formatTime(new Date(lastRunAt), "HH:mm:ss") : "—"

  readonly property string statusLine: !configured
    ? "No command configured"
    : !hasRunOnce
      ? "Waiting for first run…"
      : (isError ? Model.exitLabel(lastExitCode) : "OK") + " · updated " + updatedAtLabel + " · every " + intervalValue + " " + intervalUnit

  readonly property string tooltipHtml: configured
    ? Model.statusTooltip(command, statusLine)
    : "<b>Command Pulse</b><br/>Right-click to set a command and get started."

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: !(hideWhenEmpty && isEmpty)

  function refresh() {
    if (!root.configured || runProc.running) return
    runProc.command = ["bash", "-lc", Model.wrapCommand(root.command)]
    runProc.running = true
  }

  function openOutput() {
    root.panelMode = "output"
  }

  function openSettings() {
    root.draftCommand = root.command
    root.draftIntervalValue = root.intervalValue
    root.draftIntervalUnit = root.intervalUnit
    root.draftMaxLength = root.maxLength
    root.draftShowIcon = root.showIcon
    root.draftHideWhenEmpty = root.hideWhenEmpty
    root.draftMaxPopupWidth = root.maxPopupWidth
    root.draftMaxPopupHeight = root.maxPopupHeight
    root.panelMode = "settings"
  }

  function saveSettings() {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry.command = root.draftCommand
    entry.intervalValue = Math.max(1, root.draftIntervalValue || 1)
    entry.intervalUnit = root.draftIntervalUnit
    entry.maxLength = Math.max(0, root.draftMaxLength || 0)
    entry.showIcon = root.draftShowIcon
    entry.hideWhenEmpty = root.draftHideWhenEmpty
    entry.maxPopupWidth = Math.max(240, root.draftMaxPopupWidth || 240)
    entry.maxPopupHeight = Math.max(120, root.draftMaxPopupHeight || 120)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    root.closePanel()
    root.refresh()
  }

  function closePanel() {
    root.panelMode = ""
  }

  function close() { root.closePanel() }
  function open() { root.openOutput() }
  function toggle() { root.opened ? root.closePanel() : root.openOutput() }

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
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function settings(): void { root.openSettings() }
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

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) root.openSettings()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.openOutput()
    }

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

  // --- full output popup (left-click) -----------------------------------

  KeyboardPanel {
    id: outputPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.panelMode === "output"
    focusTarget: outputLoader.item
    contentWidth: outputPanel.fittedContentWidth(root.maxPopupWidth)
    contentHeight: outputPanel.fittedContentHeight(outputLoader.item ? outputLoader.item.implicitHeight : 0, root.maxPopupHeight)

    Loader {
      id: outputLoader
      anchors.fill: parent
      active: root.panelMode === "output"
      sourceComponent: outputContent
    }
  }

  Component {
    id: outputContent

    PanelKeyCatcher {
      id: outputKeyCatcher
      implicitHeight: outputFlick.contentHeight
      onCloseRequested: root.closePanel()

      Flickable {
        id: outputFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: outputColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: outputColumn
          width: outputFlick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "Command Pulse"
            meta: root.statusLine
            foreground: root.barForeground
            fontFamily: Style.font.family
            iconComponent: Component {
              Text {
                text: ""
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          Text {
            width: parent.width
            visible: root.hasRunOnce && !root.outputMarkup.isEmpty
            text: root.outputMarkup.html
            textFormat: Text.StyledText
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WrapAnywhere
          }

          Text {
            width: parent.width
            visible: !root.hasRunOnce || root.outputMarkup.isEmpty
            text: !root.hasRunOnce ? "Waiting for first run…" : "(empty output)"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            visible: root.outputMarkup.truncated
            text: "… output truncated"
            font.italic: true
            color: Qt.darker(root.barForeground, 1.3)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  // --- settings popup (right-click) ---------------------------------------

  KeyboardPanel {
    id: settingsPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.panelMode === "settings"
    focusTarget: settingsLoader.item
    contentWidth: settingsPanel.fittedContentWidth(Style.space(374))
    contentHeight: settingsPanel.fittedContentHeight(settingsLoader.item ? settingsLoader.item.implicitHeight : 0, Style.space(660))

    Loader {
      id: settingsLoader
      anchors.fill: parent
      active: root.panelMode === "settings"
      sourceComponent: settingsContent
    }
  }

  Component {
    id: settingsContent

    Item {
      id: settingsRoot
      readonly property real footerBlockHeight: footerRow.implicitHeight + Style.space(21)
      implicitHeight: settingsColumn.implicitHeight + footerBlockHeight

      Keys.onEscapePressed: root.closePanel()

      Flickable {
        id: settingsFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: settingsRoot.footerBlockHeight
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: settingsColumn
          width: settingsFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Command Pulse settings"
            foreground: root.barForeground
            fontFamily: Style.font.family
            iconComponent: Component {
              Text {
                text: ""
                color: root.barForeground
                font.family: Style.font.family
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          PanelSectionHeader { text: "COMMAND"; foreground: root.barForeground }

          TextField {
            id: commandField
            width: parent.width
            text: root.draftCommand
            placeholderText: "e.g. uptime -p"
            foreground: root.barForeground
            onTextChanged: root.draftCommand = text
          }

          PanelSectionHeader { text: "SCHEDULE"; foreground: root.barForeground }

          Row {
            spacing: Style.space(16)

            NumberField {
              label: "Refresh every"
              value: root.draftIntervalValue
              from: 1
              to: 999
              stepSize: 1
              fieldWidth: Style.spacing.numberFieldWidth * 0.75
              foreground: root.barForeground
              onModified: function (value) { root.draftIntervalValue = value }
            }

            Dropdown {
              label: "Unit"
              value: root.draftIntervalUnit
              options: ["seconds", "minutes", "hours"]
              implicitWidth: Style.spacing.dropdownWidth * 0.5
              foreground: root.barForeground
              onChanged: function (value) { root.draftIntervalUnit = value }
            }
          }

          PanelSectionHeader { text: "DISPLAY"; foreground: root.barForeground }

          NumberField {
            label: "Max characters in bar (0 = no limit)"
            value: root.draftMaxLength
            from: 0
            to: 200
            stepSize: 5
            fieldWidth: Style.spacing.numberFieldWidth * 0.75
            foreground: root.barForeground
            onModified: function (value) { root.draftMaxLength = value }
          }

          Toggle {
            width: parent.width
            label: "Show icon"
            checked: root.draftShowIcon
            foreground: root.barForeground
            onClicked: root.draftShowIcon = !root.draftShowIcon
          }

          Toggle {
            width: parent.width
            label: "Hide widget when output is empty"
            checked: root.draftHideWhenEmpty
            foreground: root.barForeground
            onClicked: root.draftHideWhenEmpty = !root.draftHideWhenEmpty
          }

          PanelSectionHeader { text: "FULL OUTPUT WINDOW (LEFT-CLICK)"; foreground: root.barForeground }

          Row {
            spacing: Style.space(16)

            NumberField {
              label: "Max width (px)"
              value: root.draftMaxPopupWidth
              from: 240
              to: 1200
              stepSize: 20
              fieldWidth: Style.spacing.numberFieldWidth * 0.75
              foreground: root.barForeground
              onModified: function (value) { root.draftMaxPopupWidth = value }
            }

            NumberField {
              label: "Max height (px)"
              value: root.draftMaxPopupHeight
              from: 120
              to: 900
              stepSize: 20
              fieldWidth: Style.spacing.numberFieldWidth * 0.75
              foreground: root.barForeground
              onModified: function (value) { root.draftMaxPopupHeight = value }
            }
          }
        }
      }

      PanelSeparator {
        id: footerSeparator
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footerRow.top
        anchors.bottomMargin: Style.space(10)
        foreground: root.barForeground
      }

      Row {
        id: footerRow
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        spacing: Style.space(10)

        Button {
          text: "Cancel"
          bordered: true
          foreground: root.barForeground
          onClicked: root.closePanel()
        }

        Button {
          text: "Save"
          bordered: true
          foreground: root.barForeground
          onClicked: root.saveSettings()
        }
      }
    }
  }
}
