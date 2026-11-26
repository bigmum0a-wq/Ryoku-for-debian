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

    function resolveAppInfo(appClass) {
        var cls = (appClass || "").trim();
        if (!cls)
            return { name: "Application", icon: Quickshell.iconPath("application-x-executable") };
        var entry = DesktopEntries.heuristicLookup(cls);
        if (!entry)
            entry = DesktopEntries.byId(cls);
        var displayName = (entry && entry.name) ? entry.name : cls;
        var iconName = (entry && entry.icon) ? entry.icon : cls.toLowerCase();
        var resolved = Quickshell.iconPath(iconName, "application-x-executable");
        return { name: displayName, icon: resolved };
    }

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
                    readonly property var topInfo: root.stashed.length > 0
                        ? root.resolveAppInfo(root.stashed[0]["class"])
                        : ({ name: "", icon: "" })

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

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 5
                            Image {
                                source: topInfo.icon
                                width: 16
                                height: 16
                                sourceSize.width: 16
                                sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit
                                visible: source !== ""
                            }
                            Text {
                                text: topInfo.name
                                color: "#e2e8f0"
                                font.pixelSize: 11
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
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

    // Expanded: concentric-ring floating cards starting right beside the click point; click outside to collapse
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
        readonly property int cardW: 152
        readonly property int cardH: 82

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
            easing.overshoot: 1.12
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

        // Pack cards into concentric arcs from innermost (capacity 2) outward (3, 4, 5, ...)
        function cardLayout(idx, total) {
            var cx = expandedWin.originX;
            var cy = expandedWin.originY;

            var ring = 0;
            var ringStart = 0;
            var ringCap = 2;
            while (idx >= ringStart + ringCap) {
                ringStart += ringCap;
                ring += 1;
                ringCap = ring + 2;
            }

            var posInRing = idx - ringStart;
            var remaining = total - ringStart;
            var countInRing = Math.min(ringCap, remaining);

            var r = 165 + ring * 112;
            var theta;
            var rot;
            if (countInRing === 1) {
                theta = Math.PI * 1.25;
                rot = -3;
            } else {
                var frac = posInRing / (countInRing - 1);
                theta = Math.PI * (1.05 + frac * 0.40);
                rot = -8 + frac * 14;
            }

            var rawX = cx + r * Math.cos(theta) - cardW / 2;
            var rawY = cy + r * Math.sin(theta) - cardH / 2;
            return {
                x: Math.max(16, Math.min(expandedWin.width - cardW - 16, rawX)),
                y: Math.max(16, Math.min(expandedWin.height - cardH - 16, rawY)),
                rot: rot
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
                readonly property var appInfo: root.resolveAppInfo(modelData["class"])
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
                        spacing: 7

                        Image {
                            source: card.appInfo.icon
                            width: 24
                            height: 24
                            sourceSize.width: 24
                            sourceSize.height: 24
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Text {
                            text: card.appInfo.name
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
            width: 96
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
