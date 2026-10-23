import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// IoT switchboard for the bar.
//
// Discovery and control live in bin/omarchy-iot (avahi mDNS + the Shelly
// HTTP/RPC APIs), so this panel keeps no state beyond what is in flight:
// every render is a fresh `list` from the helper. A Shelly device found
// unauthenticated is drivable (Switch.Set / relay endpoint); anything else
// on the LAN with a web UI is listed with an "open" action instead.
Panel {
  id: root
  moduleName: "loocist.iot"
  ipcTarget: "loocist.iot"
  manageIpc: false

  readonly property int pollIntervalSec: setting("pollIntervalSec", 10)
  readonly property int backgroundIntervalSec: setting("backgroundIntervalSec", 120)
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true

  // The helper ships inside the plugin; resolved from this file's own URL
  // so the directory name stays the user's to change.
  readonly property string helper: String(Qt.resolvedUrl("bin/omarchy-iot")).replace(/^file:\/\/[^/]*\//, "/").replace(/^file:\/\//, "")

  property var devices: []
  property bool loading: false
  property string errorText: ""

  // ip of the device being switched, "" when idle. One at a time: a switch
  // flip takes a moment and overlapping them makes the row states lie.
  property string busyIp: ""
  property string busyAction: ""

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var switches: Model.controllableOf(devices)
  readonly property var others: Model.othersOf(devices)
  readonly property bool anyOn: Model.countOn(devices) > 0
  readonly property bool busy: busyIp !== ""

  // U+F1E6 plug — from the same Font Awesome block the shell font already
  // draws the VPN lock and refresh glyphs from.
  readonly property string barGlyph: "\uF1E6"

  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0
  visible: !hideWhenEmpty || devices.length > 0 || opened

  // --- data ------------------------------------------------------------------

  // force=true bypasses the helper's scan cache (r key, panel open).
  function refresh(force) {
    if (listProc.running)
      return
    loading = true
    var cache = force ? 0 : Math.min(pollIntervalSec, backgroundIntervalSec)
    listProc.command = [helper, "list", "--cache", String(cache)]
    listProc.running = true
  }

  function applyList(raw) {
    loading = false
    var parsed = Model.parseResponse(raw)
    if (!parsed || parsed.ok !== true) {
      errorText = "Could not scan the network — check curl, jq and avahi are installed"
      return
    }
    errorText = ""
    devices = Model.devicesOf(parsed)
    if (cursorIndex >= switches.length)
      cursorIndex = Math.max(0, switches.length - 1)
  }

  function deviceByIp(ip) {
    for (var i = 0; i < devices.length; i++)
      if (devices[i].ip === ip)
        return devices[i]
    return null
  }

  // --- actions ---------------------------------------------------------------

  function toggleDevice(dev) {
    if (!dev || busy)
      return
    startAction([helper, "toggle", dev.ip], dev.ip, dev.on === true ? "off" : "on")
  }

  // Never derived from cached state: an explicit set must land even if the
  // list in hand is stale (a flip from outside, or this same panel a second
  // ago). The helper reads the device itself.
  function startAction(command, ip, optimistic) {
    errorText = ""
    busyIp = ip
    busyAction = optimistic
    actionProc.command = command
    actionProc.running = true
  }

  function applyAction(raw) {
    var parsed = Model.parseResponse(raw)
    if (parsed && parsed.ok === true)
      return
    errorText = parsed && parsed.error ? parsed.error : "The device did not answer"
  }

  // Open a device's web UI in the default browser.
  function openDevice(dev) {
    if (!dev)
      return
    Quickshell.execDetached(["xdg-open", "http://" + dev.ip])
  }

  function toggleByIp(ip) {
    var dev = deviceByIp(ip)
    if (dev) {
      toggleDevice(dev)
    } else if (!busy) {
      startAction([helper, "toggle", ip], ip, "on")
    }
  }

  function setByIp(ip, state) {
    setDeviceIp(ip, state)
  }

  function setDeviceIp(ip, state) {
    if (busy || (state !== "on" && state !== "off"))
      return
    startAction([helper, "set", ip, state], ip, state)
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyList(text)
    }
    onExited: function (exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.errorText === "")
        root.errorText = "The bundled IoT helper failed — check curl, jq and avahi are installed"
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAction(text)
    }
    onExited: function () {
      root.busyIp = ""
      root.busyAction = ""
      // The helper caches by timestamp, so force a fresh read of the
      // switched device rather than redrawing whatever the cache held.
      root.refresh(true)
    }
  }

  // Brisk while the panel is on screen, slow in the background — the bar
  // face only needs to know whether anything is there at all.
  Timer {
    interval: (root.opened ? Math.max(3, root.pollIntervalSec) : Math.max(30, root.backgroundIntervalSec)) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      errorText = ""
      refresh(true)
    }
  }

  IpcHandler {
    target: "loocist.iot"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh(true) }
    function list(): string { return root.devices.map(function (d) { return d.name }).join(", ") }
    function count(): int { return root.devices.length }
    function set(ip: string, state: string): void { root.setByIp(ip, state) }
    function toggleDevice(ip: string): void { root.toggleByIp(ip) }
    function openDevice(ip: string): void { root.openDevice(root.deviceByIp(ip)) }
  }

  // --- bar face ----------------------------------------------------------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barGlyph
    active: root.opened || root.anyOn
    opacity: root.devices.length > 0 ? 1.0 : 0.65
    tooltipText: Model.barTooltip(root.devices, root.loading)

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton)
        root.refresh(true)
      else
        root.toggle()
    }
  }

  // --- panel -------------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) {
        if (root.switches.length === 0)
          return
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        if (dy !== 0)
          root.cursorIndex = Math.max(0, Math.min(root.switches.length - 1, root.cursorIndex + dy))
      }
      // Guarded on cursorActive so the first key press only arms the
      // cursor — a stray Space must not flip a plug behind the user's back.
      onActivateRequested: {
        if (root.cursorActive && root.cursorIndex < root.switches.length)
          root.toggleDevice(root.switches[root.cursorIndex])
      }
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "r" || t === "R")
          root.refresh(true)
        else if ((t === "o" || t === "O") && root.cursorIndex < root.switches.length)
          root.openDevice(root.switches[root.cursorIndex])
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "IoT"
            meta: Model.heroMeta(root.devices, root.loading)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.devices.length > 0 ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: root.barGlyph
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            visible: root.switches.length > 0
            foreground: root.foreground
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)
            visible: root.switches.length > 0

            PanelSectionHeader {
              Layout.fillWidth: true
              text: "SWITCHES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            PanelActionButton {
              // U+F021 refresh
              iconText: "\uF021"
              tooltipText: "Rescan the network (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.loading
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.refresh(true)
            }
          }

          Column {
            id: switchColumn
            width: parent.width
            spacing: Style.space(4)
            visible: root.switches.length > 0

            Repeater {
              model: root.switches

              Row {
                required property var modelData
                required property int index
                width: switchColumn.width
                spacing: Style.space(4)

                readonly property bool rowBusy: root.busyIp === modelData.ip

                Toggle {
                  width: parent.width - openButton.width - parent.spacing
                  label: modelData.name
                  description: Model.deviceMeta(modelData, rowBusy, root.busyAction)
                  checked: rowBusy ? root.busyAction === "on" : modelData.on === true
                  hasCursor: root.cursorActive && root.cursorIndex === index
                  enabled: !root.busy || rowBusy
                  foreground: root.foreground
                  fontFamily: root.fontFamily

                  onHovered: function (isHovered) {
                    if (isHovered) {
                      root.cursorActive = true
                      root.cursorIndex = index
                    }
                  }
                  onClicked: root.toggleDevice(modelData)
                }

                PanelActionButton {
                  id: openButton
                  // U+F141 external link
                  iconText: "\uF141"
                  tooltipText: "Open the web UI"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: root.openDevice(modelData)
                }
              }
            }
          }

          PanelSeparator {
            visible: root.others.length > 0
            foreground: root.foreground
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)
            visible: root.others.length > 0

            PanelSectionHeader {
              Layout.fillWidth: true
              text: "NETWORK"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            PanelActionButton {
              iconText: "\uF021"
              tooltipText: "Rescan the network (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.loading
              Layout.alignment: Qt.AlignVCenter
              onClicked: root.refresh(true)
            }
          }

          Column {
            id: otherColumn
            width: parent.width
            spacing: Style.space(4)
            visible: root.others.length > 0

            Repeater {
              model: root.others

              Button {
                required property var modelData
                width: otherColumn.width
                text: modelData.name + "  —  " + Model.otherMeta(modelData)
                foreground: root.foreground
                fontFamily: root.fontFamily
                leftAlign: true
                onClicked: root.openDevice(modelData)
              }
            }
          }

          Text {
            visible: root.devices.length === 0
            width: parent.width
            text: root.loading ? "Scanning…" : "No IoT devices answered on the network. Shelly devices, Home Assistant, Hue bridges and anything with a web UI that advertises mDNS will appear here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
