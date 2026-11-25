pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import inir.modules.common.functions
import inir.modules.iris.style
import inir.services
import Ryoku.Ui.Singletons

// KDE-style analytical System Monitor widget: two side-by-side cards
// (Left: CPU & RAM vertical bar charts; Right: Wi-Fi speed vertical bar chart).
IrisWidgetFace {
    id: root

    implicitWidth:  root.dp(320)
    implicitHeight: root.dp(136)
    padding:        root.dp(10)
    clip:           true

    readonly property int maxSamples: 16

    // ── CPU / RAM from ResourceUsage singleton ─────────────────────────────
    readonly property real cpuPct: ResourceUsage.cpuUsage
    readonly property real ramPct: ResourceUsage.memoryUsedPercentage
    readonly property real ramUsedGb: ResourceUsage.memoryUsed / (1024 * 1024)

    property bool _holding: false
    function _syncHold() {
        if (root.live && !root._holding) {
            ResourceUsage.keepAlive();
            root._holding = true;
        } else if (!root.live && root._holding) {
            ResourceUsage.releaseKeepAlive();
            root._holding = false;
        }
    }
    onLiveChanged: root._syncHold()
    Component.onCompleted: root._syncHold()
    Component.onDestruction: { if (root._holding) ResourceUsage.releaseKeepAlive(); }

    property var cpuHistory: Array(root.maxSamples).fill(0)
    property var ramHistory: Array(root.maxSamples).fill(0)

    function _push(arr, val) {
        var n = arr.slice(1);
        n.push(Math.max(0, Math.min(1, val)));
        return n;
    }

    Connections {
        target: ResourceUsage
        function onCpuUsageChanged() {
            root.cpuHistory = root._push(root.cpuHistory, root.cpuPct);
        }
        function onMemoryUsedPercentageChanged() {
            root.ramHistory = root._push(root.ramHistory, root.ramPct);
        }
    }

    // ── Wi-Fi from /proc/net/dev ───────────────────────────────────────────
    property string netIface: "Wi-Fi"
    property real   rxKbps:   0
    property real   txKbps:   0
    property var    netHistory: Array(root.maxSamples).fill(0)

    property double _prevRx: -1
    property double _prevTx: -1
    property double _prevTs: 0

    Process {
        id: netProc
        command: ["sh", "-c",
            "awk 'NR>2 && $1 !~ /^lo:/{gsub(\":\",\"\",$1); print $1, $2, $10}' /proc/net/dev"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                var bestIface = "", rx = 0, tx = 0;
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].trim().split(/\s+/);
                    if (p.length < 3) continue;
                    var name = p[0];
                    var r = parseFloat(p[1]) || 0;
                    var t = parseFloat(p[2]) || 0;
                    if (name.indexOf("wl") === 0) {
                        bestIface = name; rx = r; tx = t;
                    } else if (bestIface === "" && (r > 0 || t > 0)) {
                        bestIface = name; rx = r; tx = t;
                    }
                }
                if (bestIface !== "") {
                    root.netIface = bestIface;
                    var now = Date.now();
                    if (root._prevRx >= 0 && root._prevTs > 0) {
                        var dt = Math.max(0.2, (now - root._prevTs) / 1000.0);
                        root.rxKbps = Math.max(0, (rx - root._prevRx) / 1024.0 / dt);
                        root.txKbps = Math.max(0, (tx - root._prevTx) / 1024.0 / dt);
                        var ratio = Math.min(1.0, (root.rxKbps + root.txKbps) / 5120.0);
                        root.netHistory = root._push(root.netHistory, ratio);
                    }
                    root._prevRx = rx;
                    root._prevTx = tx;
                    root._prevTs = now;
                }
            }
        }
    }

    Timer {
        interval: 1000
        repeat:   true
        running:  root.live
        onTriggered: { if (!netProc.running) netProc.running = true; }
    }

    function fmtSpeed(kbps) {
        if (kbps >= 1024) return (kbps / 1024).toFixed(1) + "M";
        return Math.round(kbps) + "K";
    }

    function barColor(pct, base) {
        return pct >= 0.85 ? root.danger : base;
    }

    // ── Reusable bar-chart component (fills available height cleanly) ──────
    component MiniBarChart: ColumnLayout {
        id: chart
        required property string label
        required property string readout
        required property var    history
        required property color  fillColor

        Layout.fillWidth:  true
        Layout.fillHeight: true
        spacing: root.dp(2)

        RowLayout {
            Layout.fillWidth: true
            spacing: root.dp(4)
            Text {
                text: chart.label
                font.pixelSize: root.dp(10)
                font.weight: Font.DemiBold
                color: root.ink
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Text {
                text: chart.readout
                font.pixelSize: root.dp(9.5)
                color: chart.fillColor
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            Layout.minimumHeight: root.dp(18)
            radius: root.dp(4)
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
            clip: true

            Row {
                anchors.fill:    parent
                anchors.margins: root.dp(2)
                spacing:         root.dp(2)

                Repeater {
                    model: root.maxSamples
                    delegate: Item {
                        required property int index
                        width:  Math.max(1, (parent.width - (root.maxSamples - 1) * root.dp(2)) / root.maxSamples)
                        height: parent.height

                        readonly property real sample: (chart.history && index < chart.history.length)
                            ? Math.max(0.08, Number(chart.history[index]) || 0) : 0.08

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left:   parent.left
                            anchors.right:  parent.right
                            height:  Math.max(root.dp(2), Math.round(parent.height * parent.sample))
                            radius:  root.dp(1.5)
                            color:   chart.fillColor
                            opacity: 0.45 + 0.55 * (index / (root.maxSamples - 1))
                        }
                    }
                }
            }
        }
    }

    // ── Layout: two side-by-side cards ───────────────────────────────────
    RowLayout {
        anchors.fill:    parent
        anchors.margins: root.padding
        spacing:         root.dp(6)

        // Left card: CPU + RAM
        Rectangle {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            radius:            root.dp(7)
            color:             Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
            border.width:      1
            border.color:      Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
            clip:              true

            ColumnLayout {
                anchors.fill:    parent
                anchors.margins: root.dp(6)
                spacing:         root.dp(4)

                MiniBarChart {
                    label:     "CPU"
                    readout:   Math.round(root.cpuPct * 100) + "%"
                    history:   root.cpuHistory
                    fillColor: root.barColor(root.cpuPct, root.accent)
                }

                MiniBarChart {
                    label:     "RAM"
                    readout:   Math.round(root.ramPct * 100) + "% (" + root.ramUsedGb.toFixed(1) + "G)"
                    history:   root.ramHistory
                    fillColor: root.barColor(root.ramPct, root.accent2)
                }
            }
        }

        // Right card: Wi-Fi
        Rectangle {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            radius:            root.dp(7)
            color:             Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
            border.width:      1
            border.color:      Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
            clip:              true

            ColumnLayout {
                anchors.fill:    parent
                anchors.margins: root.dp(6)
                spacing:         root.dp(4)

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text:              "Wi-Fi"
                        font.pixelSize:    root.dp(10)
                        font.weight:       Font.DemiBold
                        color:             root.ink
                        Layout.fillWidth:  true
                        elide:             Text.ElideRight
                    }
                    Text {
                        text:           root.netIface
                        font.pixelSize: root.dp(9)
                        color:          root.inkSecondary
                    }
                }

                MiniBarChart {
                    label:     "↓ " + root.fmtSpeed(root.rxKbps)
                    readout:   "↑ " + root.fmtSpeed(root.txKbps)
                    history:   root.netHistory
                    fillColor: root.highlight
                }
            }
        }
    }
}
