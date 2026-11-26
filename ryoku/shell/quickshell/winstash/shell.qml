import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var stashed: []
    property bool expanded: false
    property string lastRaw: ""
    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-winstash-open"

    function refresh() {
        if (!listProc.running)
            listProc.running = true;
    }

    Timer {
        interval: 600
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        command: [
            "bash", "-c",
            "printf '%s\\n' \"$([ -f '" + root.stateFile + "' ] && echo 1 || echo 0)\"; ryoku-winstash list"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (this.text || "").trim().split("\n");
                if (lines.length >= 2) {
                    root.expanded = (lines[0].trim() === "1");
                    var jsonStr = lines.slice(1).join("\n");
                    if (jsonStr !== root.lastRaw) {
                        root.lastRaw = jsonStr;
                        try {
                            var parsed = JSON.parse(jsonStr);
                            if (Array.isArray(parsed))
                                root.stashed = parsed;
                        } catch (e) {}
                    }
                }
            }
        }
    }

    Process {
        id: actionProc
        onExited: root.refresh()
    }

    function runAction(args) {
        actionProc.command = ["ryoku-winstash"].concat(args);
        actionProc.running = true;
    }

    // Collapsed: macOS-style fanned card stack ("billets glissés de côté") in bottom-right
    PanelWindow {
        id: collapsedWin
        visible: root.stashed.length > 0 && !root.expanded
        anchors {
            right: true
            bottom: true
        }
        margins {
            right: 16
            bottom: 24
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash"

        implicitWidth: 128
        implicitHeight: 104

        Item {
            anchors.fill: parent

            Repeater {
                model: Math.min(4, root.stashed.length)
                delegate: Rectangle {
                    required property int index
                    readonly property int rev: Math.min(4, root.stashed.length) - 1 - index
                    width: 86
                    height: 68
                    x: 16 + rev * 7
                    y: 16 + rev * 5
                    rotation: (rev - 1) * 3.5
                    radius: 12
                    color: rev === 0 ? "#e6101828" : (rev === 1 ? "#cc162238" : "#aa1c2d4a")
                    border.width: 1
                    border.color: rev === 0 ? "#8038bdf8" : "#4094a3b8"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: rev === 0
                        spacing: 4

                        Text {
                            text: root.stashed.length > 0 ? (root.stashed[0]["class"] || "app") : ""
                            color: "#e2e8f0"
                            font.pixelSize: 11
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: root.stashed.length > 0 ? (root.stashed[0].title || "") : ""
                            color: "#94a3b8"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Count pill badge
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 8
                anchors.rightMargin: 8
                width: 24
                height: 24
                radius: 12
                color: "#38bdf8"
                Text {
                    anchors.centerIn: parent
                    text: root.stashed.length
                    color: "#061529"
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runAction(["toggle-ui"])
            }
        }
    }

    // Expanded: container-free floating cards fanned across the screen; click anywhere outside to collapse
    PanelWindow {
        id: expandedWin
        visible: root.stashed.length > 0 && root.expanded
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash-fan"

        property real animProgress: 0
        readonly property real originX: width - 96
        readonly property real originY: height - 84
        readonly property int cardW: 156
        readonly property int cardH: 88

        onVisibleChanged: {
            if (visible) {
                animProgress = 0;
                burstAnim.restart();
            } else {
                animProgress = 0;
            }
        }

        NumberAnimation {
            id: burstAnim
            target: expandedWin
            property: "animProgress"
            from: 0
            to: 1
            duration: 240
            easing.type: Easing.OutBack
            easing.overshoot: 1.15
        }

        // Subtle click-anywhere backdrop to collapse back into the corner stack
        Rectangle {
            anchors.fill: parent
            color: "#30040914"
            opacity: expandedWin.animProgress

            MouseArea {
                anchors.fill: parent
                onClicked: root.runAction(["toggle-ui"])
            }
        }

        function cardLayout(idx, total) {
            var cx = expandedWin.originX;
            var cy = expandedWin.originY;

            if (total <= 4) {
                var r = 140 + Math.max(0, total - 1) * 68;
                var theta = (total === 1)
                    ? (Math.PI * 1.25)
                    : (Math.PI * (1.04 + (idx / (total - 1)) * 0.42));
                var rot = (total === 1) ? -4 : (-10 + (idx / (total - 1)) * 18);
                return {
                    x: cx + r * Math.cos(theta) - cardW / 2,
                    y: cy + r * Math.sin(theta) - cardH / 2,
                    rot: rot
                };
            }

            if (total <= 8) {
                if (idx < 3) {
                    var r1 = 245;
                    var t1 = Math.PI * (1.06 + (idx / 2) * 0.38);
                    return {
                        x: cx + r1 * Math.cos(t1) - cardW / 2,
                        y: cy + r1 * Math.sin(t1) - cardH / 2,
                        rot: -8 + (idx / 2) * 14
                    };
                }
                var outerN = total - 3;
                var outerIdx = idx - 3;
                var r2 = 410;
                var t2 = (outerN === 1)
                    ? (Math.PI * 1.25)
                    : (Math.PI * (1.03 + (outerIdx / (outerN - 1)) * 0.44));
                return {
                    x: cx + r2 * Math.cos(t2) - cardW / 2,
                    y: cy + r2 * Math.sin(t2) - cardH / 2,
                    rot: (outerN === 1) ? 0 : (-10 + (outerIdx / (outerN - 1)) * 18)
                };
            }

            // 9+ windows: neat floating grid radiating up-left, still without any container box
            var cols = 4;
            var col = idx % cols;
            var row = Math.floor(idx / cols);
            return {
                x: Math.max(24, expandedWin.width - 190 - col * (cardW + 14)),
                y: Math.max(24, expandedWin.height - 150 - row * (cardH + 14)),
                rot: ((idx % 3) - 1) * 2
            };
        }

        // Floating individual cards (no enclosing container)
        Repeater {
            model: root.stashed
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                readonly property var pos: expandedWin.cardLayout(index, root.stashed.length)
                readonly property real startX: expandedWin.originX - expandedWin.cardW / 2
                readonly property real startY: expandedWin.originY - expandedWin.cardH / 2

                width: expandedWin.cardW
                height: expandedWin.cardH
                x: startX + (pos.x - startX) * expandedWin.animProgress
                y: startY + (pos.y - startY) * expandedWin.animProgress
                rotation: cardMa.containsMouse ? 0 : pos.rot * expandedWin.animProgress
                scale: (0.55 + 0.45 * expandedWin.animProgress) * (cardMa.containsMouse ? 1.07 : 1.0)
                z: cardMa.containsMouse ? 30 : (10 + index)
                opacity: Math.min(1, expandedWin.animProgress * 1.35)

                radius: 14
                color: cardMa.containsMouse ? "#f2132540" : "#e80d1729"
                border.width: 1
                border.color: cardMa.containsMouse ? "#9938bdf8" : "#4438bdf8"

                Behavior on scale {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on rotation {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    id: cardMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction(["focus", modelData.address, "--swap"])
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 7
                            color: "#2b38bdf8"
                            Text {
                                anchors.centerIn: parent
                                text: (modelData["class"] || "?").substring(0, 2).toUpperCase()
                                color: "#7dd3fc"
                                font.pixelSize: 10
                                font.bold: true
                            }
                        }

                        Text {
                            text: modelData["class"] || "Application"
                            color: "#f1f5f9"
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 6
                            color: delMa.containsMouse ? "#55fb7185" : "#22fb7185"
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: "#fda4af"
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: delMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["close", modelData.address])
                            }
                        }
                    }

                    Text {
                        text: modelData.title || ""
                        color: "#94a3b8"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
            }
        }

        // Small floating "Tout ouvrir" pill in the corner (no enclosing box)
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 20
            anchors.bottomMargin: 22
            width: 92
            height: 30
            radius: 15
            color: restoreMa.containsMouse ? "#e616324f" : "#cc0d1b2e"
            border.width: 1
            border.color: "#6638bdf8"
            opacity: expandedWin.animProgress

            Text {
                anchors.centerIn: parent
                text: "Tout ouvrir (" + root.stashed.length + ")"
                color: "#7dd3fc"
                font.pixelSize: 10
                font.bold: true
            }

            MouseArea {
                id: restoreMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runAction(["restore-all"])
            }
        }
    }
}
