import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Live system metrics on the bar: CPU, memory, GPU, GPU memory, and network
// throughput.
//
// A tick runs sample.sh, which prints raw kernel counters; the differencing
// into percentages and rates happens here, so the script stays a stateless
// one-shot and a missed or slow tick just widens the interval it averages
// over instead of producing a spike.
//
// Colors come from the bar host (`bar.barForeground`, `bar.urgent`), which
// the shell re-binds on every theme change, so the widget follows the theme
// without watching for it.
BarWidget {
  id: root
  moduleName: "io.github.ztrek7.system-metrics"

  // Metrics to show, in bar order. Drop entries to hide them.
  readonly property var items: setting("items", ["cpu", "mem", "gpu", "gpumem", "down", "up", "ping"])
  readonly property int intervalMs: Math.max(500, setting("interval", 2) * 1000)
  // Percentage at or above which a reading is painted in the bar's urgent
  // color. Rates have no natural ceiling, so they never alert.
  readonly property real alertPercent: setting("alertPercent", 90)
  // Pin the widget to one interface instead of following the default route.
  readonly property string configuredInterface: setting("interface", "")

  // What the latency cell measures the path to. The literal "gateway" probes
  // the router instead, which separates a bad wifi link from a slow internet.
  // Probed on its own slower timer: a round trip is not a counter to be read,
  // it is traffic, and one every couple of seconds is more than a glanceable
  // number needs.
  readonly property string latencyTarget: setting("latencyTarget", "1.1.1.1")
  readonly property bool latencyEnabled: items.some(function (item) {
    return ["ping", "latency"].indexOf(String(item).toLowerCase()) !== -1
  })
  readonly property int latencyIntervalMs: Math.max(1000, setting("latencyInterval", 5) * 1000)
  readonly property real latencyAlertMs: setting("latencyAlertMs", 150)

  // Previous sample, held to difference against. -1 marks "no sample yet",
  // which is what keeps the first tick from reporting a rate equal to the
  // machine's whole uptime of traffic.
  property real prevCpuTotal: -1
  property real prevCpuIdle: 0
  property real prevRx: -1
  property real prevTx: 0
  property real prevClock: 0
  property string prevInterface: ""

  property real cpuPercent: -1
  property real memPercent: -1
  property real memUsedKb: 0
  property real memTotalKb: 0
  property real gpuPercent: -1
  property real gpuMemUsedMb: 0
  property real gpuMemTotalMb: 0
  property real rxRate: -1
  property real txRate: -1
  // Milliseconds, or -1 for "no answer" — which covers an unreachable target
  // and a link that is down, and reads the same way on the bar either way.
  property real latencyMs: -1
  property string activeInterface: ""
  // Whether this machine has a GPU sample.sh can read at all. Until the first
  // sample lands the GPU cells are laid out optimistically, so the bar does
  // not visibly shuffle a moment after login on the machines that do have one.
  property bool gpuPresent: true

  function refresh() {
    if (!sampler.running) sampler.running = true
    probeLatency()
  }

  function probeLatency() {
    if (latencyEnabled && !latencyProbe.running) latencyProbe.running = true
  }

  function applySample(line) {
    var f = String(line).trim().split(/\s+/)
    if (f.length < 11) return

    var cpuTotal = Number(f[0])
    var cpuIdle = Number(f[1])
    var memTotal = Number(f[2])
    var memAvail = Number(f[3])
    var rx = Number(f[4])
    var tx = Number(f[5])
    var gpuUtil = Number(f[6])
    var gpuUsed = Number(f[7])
    var gpuTotal = Number(f[8])
    var clock = Number(f[9])
    var iface = f[10] === "-" ? "" : f[10]

    memTotalKb = memTotal
    memUsedKb = Math.max(0, memTotal - memAvail)
    memPercent = memTotal > 0 ? (memUsedKb / memTotal) * 100 : -1

    gpuPresent = gpuUtil >= 0
    gpuPercent = gpuPresent ? gpuUtil : -1
    gpuMemUsedMb = gpuUsed
    gpuMemTotalMb = gpuTotal

    // Jiffies are monotonic, but a suspend/resume or a counter wrap can still
    // hand back a non-positive window; skip those rather than paint a spike.
    var totalDelta = cpuTotal - prevCpuTotal
    var idleDelta = cpuIdle - prevCpuIdle
    if (prevCpuTotal >= 0 && totalDelta > 0)
      cpuPercent = Math.max(0, Math.min(100, (1 - idleDelta / totalDelta) * 100))
    prevCpuTotal = cpuTotal
    prevCpuIdle = cpuIdle

    // Byte counters are per-interface and reset when the link changes, so a
    // roam from wifi to ethernet starts a fresh baseline instead of reporting
    // the difference between two unrelated counters.
    var elapsed = clock - prevClock
    if (prevRx >= 0 && iface === prevInterface && elapsed > 0) {
      rxRate = Math.max(0, (rx - prevRx) / elapsed)
      txRate = Math.max(0, (tx - prevTx) / elapsed)
    } else {
      rxRate = -1
      txRate = -1
    }
    prevRx = rx
    prevTx = tx
    prevClock = clock
    prevInterface = iface
    activeInterface = iface
  }

  function formatPercent(value) {
    return value < 0 ? "—" : Math.round(value) + "%"
  }

  function formatBytes(bytes, unitSuffix) {
    if (bytes < 0) return "—"
    var units = ["B", "K", "M", "G", "T"]
    var value = bytes
    var i = 0
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024
      i++
    }
    var text = value < 10 && i > 0 ? value.toFixed(1) : String(Math.round(value))
    return text + units[i] + (unitSuffix || "")
  }

  // `prevKey` lets GPU memory drop its own icon when it sits directly after
  // GPU utilization: the two read as one "GPU: 18% 416M" group under a single
  // board icon, which is a cell's worth of bar space back. Moved apart, it
  // labels itself with the memory glyph again.
  function formatLatency(ms) {
    if (ms < 0) return "\u2014"
    if (ms >= 1000) return (ms / 1000).toFixed(1) + "s"
    return (ms < 10 ? ms.toFixed(1) : String(Math.round(ms))) + "ms"
  }

  function cellFor(key, prevKey) {
    switch (key) {
    case "cpu":
      return { icon: "", text: formatPercent(cpuPercent), sample: "100%",
               alert: cpuPercent >= alertPercent }
    case "mem":
      return { icon: "󰘚", text: formatPercent(memPercent), sample: "100%",
               alert: memPercent >= alertPercent }
    case "gpu":
      if (!gpuPresent) return null
      return { icon: "󰢮", text: formatPercent(gpuPercent), sample: "100%",
               alert: gpuPercent >= alertPercent }
    case "gpumem":
      if (!gpuPresent) return null
      return { icon: prevKey === "gpu" ? "" : "󰘚",
               text: formatBytes(gpuMemUsedMb * 1024 * 1024), sample: "1023M",
               alert: gpuMemTotalMb > 0 && (gpuMemUsedMb / gpuMemTotalMb) * 100 >= alertPercent }
    case "down":
      return { icon: "󰇚", text: formatBytes(rxRate), sample: "1023M", alert: false }
    case "up":
      return { icon: "󰕒", text: formatBytes(txRate), sample: "1023M", alert: false }
    case "ping":
    case "latency":
      return { icon: "󰔛", text: formatLatency(latencyMs), sample: "999ms",
               alert: latencyMs < 0 || latencyMs >= latencyAlertMs }
    }
    return null
  }

  readonly property var cells: {
    var out = []
    for (var i = 0; i < items.length; i++) {
      var key = String(items[i]).toLowerCase()
      var cell = cellFor(key, i > 0 ? String(items[i - 1]).toLowerCase() : "")
      if (cell) out.push(cell)
    }
    return out
  }

  readonly property color valueColor: bar ? bar.barForeground : Color.bar.text
  readonly property color alertColor: bar ? bar.urgent : Color.bar.active
  // Icons sit behind their numbers so a glance lands on the reading. Derived
  // from the live foreground rather than a fixed grey, so it stays legible on
  // a light theme.
  readonly property color iconColor: Util.alpha(valueColor, 0.55)

  readonly property string tooltipText: {
    var lines = []
    lines.push("CPU " + formatPercent(cpuPercent))
    lines.push("Memory " + formatPercent(memPercent)
      + (memTotalKb > 0 ? "  (" + formatBytes(memUsedKb * 1024) + " / " + formatBytes(memTotalKb * 1024) + ")" : ""))
    if (gpuPresent) {
      lines.push("GPU " + formatPercent(gpuPercent))
      lines.push("GPU memory " + formatBytes(gpuMemUsedMb * 1024 * 1024)
        + (gpuMemTotalMb > 0 ? " / " + formatBytes(gpuMemTotalMb * 1024 * 1024) : ""))
    }
    var link = activeInterface === "" ? "no default route" : activeInterface
    lines.push("Down " + formatBytes(rxRate, "/s") + "   Up " + formatBytes(txRate, "/s") + "   (" + link + ")")
    if (latencyEnabled)
      lines.push("Latency " + (latencyMs < 0 ? "no answer" : formatLatency(latencyMs)) + " to " + latencyTarget)
    lines.push("Left click btop · right click nvtop")
    return lines.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: sampler
    command: ["bash", Qt.resolvedUrl("sample.sh").toString().replace(/^file:\/\//, ""), root.configuredInterface]
    stdout: SplitParser {
      onRead: function (line) { root.applySample(line) }
    }
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!sampler.running) sampler.running = true
    }
  }

  Process {
    id: latencyProbe
    command: ["bash", Qt.resolvedUrl("latency.sh").toString().replace(/^file:\/\//, ""), root.latencyTarget]
    stdout: SplitParser {
      onRead: function (line) {
        var ms = Number(String(line).trim())
        root.latencyMs = isNaN(ms) ? -1 : ms
      }
    }
  }

  Timer {
    interval: root.latencyIntervalMs
    running: root.latencyEnabled
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probeLatency()
  }

  IpcHandler {
    target: "io.github.ztrek7.system-metrics"

    function refresh(): void { root.broadcast("refresh") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.cells.length > 0
    tooltipText: root.tooltipText
    horizontalMargin: 6
    fixedWidth: root.vertical ? -1 : content.implicitWidth + Style.spaceReal(12)
    fixedHeight: root.vertical ? content.implicitHeight + Style.spaceReal(8) : -1

    onPressed: function (b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-launch-or-focus-tui nvtop")
      else root.bar.run("omarchy-launch-or-focus-tui btop")
    }

    Grid {
      id: content
      anchors.centerIn: parent
      // One row of cells on a horizontal bar; one column of them on a
      // vertical bar, where a cell stacks its icon over its number to fit the
      // 28px width.
      columns: root.vertical ? 1 : root.cells.length
      rows: root.vertical ? root.cells.length : 1
      // Horizontal gaps live inside the cells, which lets a cell that dropped
      // its icon sit tight against the one labelling it.
      columnSpacing: 0
      rowSpacing: Style.spaceReal(2)

      Repeater {
        model: root.cells

        Item {
          id: cell
          required property var modelData
          required property int index

          readonly property bool labelled: String(modelData.icon) !== ""
          // A cell borrowing its neighbour's icon closes up against it; a cell
          // carrying its own opens a full gap, so the bar reads as groups
          // rather than an even run of numbers.
          readonly property real gap: index === 0 ? 0 : Style.spaceReal(labelled ? 9 : 4)
          readonly property real iconGap: labelled ? Style.spaceReal(3) : 0

          implicitWidth: root.vertical ? root.barSize : gap + icon.implicitWidth + iconGap + valueMetrics.width
          implicitHeight: root.vertical ? Style.bar.iconSlot + value.implicitHeight : Math.max(icon.implicitHeight, value.implicitHeight)

          TextMetrics {
            id: valueMetrics
            font.family: value.font.family
            font.pixelSize: value.font.pixelSize
            text: cell.modelData.sample
          }

          Text {
            id: icon
            text: cell.modelData.icon
            color: root.iconColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering
            x: root.vertical ? Math.round((cell.width - implicitWidth) / 2) : cell.gap
            y: root.vertical ? 0 : Math.round((cell.height - implicitHeight) / 2)

            Behavior on color {
              enabled: !root.bar || root.bar.foregroundAnimationEnabled
              ColorAnimation { duration: 160 }
            }
          }

          Text {
            id: value
            text: cell.modelData.text
            color: cell.modelData.alert ? root.alertColor : root.valueColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering
            // The number is right-aligned in a slot sized for the widest
            // reading it can take, so a climbing figure does not shove its
            // neighbours along the bar.
            width: valueMetrics.width
            horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignRight
            x: root.vertical ? Math.round((cell.width - width) / 2) : cell.width - width
            y: root.vertical ? Style.bar.iconSlot : Math.round((cell.height - implicitHeight) / 2)

            Behavior on color {
              enabled: !root.bar || root.bar.foregroundAnimationEnabled
              ColorAnimation { duration: 160 }
            }
          }
        }
      }
    }
  }
}
