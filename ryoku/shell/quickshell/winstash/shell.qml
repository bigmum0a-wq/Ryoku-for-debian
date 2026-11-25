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

    PanelWindow {
        id: win
        visible: root.stashed.length > 0
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

        implicitWidth: root.expanded ? 320 : 128
        implicitHeight: root.expanded ? Math.min(520, 68 + root.stashed.length * 64) : 104

        // Collapsed: macOS-style fanned card stack ("billets glissés de côté")
        Item {
            anchors.fill: parent
            visible: !root.expanded

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

        // Expanded: fanned list of stashed windows with focus-swap & close
        Rectangle {
            anchors.fill: parent
            visible: root.expanded
            radius: 16
            color: "#ec0b1322"
            border.width: 1
            border.color: "#5538bdf8"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Fenêtres rangées (" + root.stashed.length + ")"
                        color: "#e2e8f0"
                        font.pixelSize: 13
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: 78
                        height: 24
                        radius: 8
                        color: restoreMa.containsMouse ? "#3338bdf8" : "#1f38bdf8"
                        Text {
                            anchors.centerIn: parent
                            text: "Tout ouvrir"
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
                    Rectangle {
                        width: 24
                        height: 24
                        radius: 8
                        color: closeUiMa.containsMouse ? "#33ffffff" : "#18ffffff"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: "#cbd5e1"
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: closeUiMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runAction(["toggle-ui"])
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: root.stashed
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 56
                        radius: 10
                        color: cardMa.containsMouse ? "#2838bdf8" : "#18ffffff"
                        border.width: 1
                        border.color: cardMa.containsMouse ? "#8038bdf8" : "#22ffffff"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 8
                                color: "#2638bdf8"
                                Text {
                                    anchors.centerIn: parent
                                    text: (modelData["class"] || "?").substring(0, 2).toUpperCase()
                                    color: "#7dd3fc"
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    text: modelData["class"] || "Application"
                                    color: "#f1f5f9"
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.title || ""
                                    color: "#94a3b8"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 6
                                color: delMa.containsMouse ? "#44fb7185" : "#18fb7185"
                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: "#fda4af"
                                    font.pixelSize: 11
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

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            anchors.rightMargin: 34
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runAction(["focus", modelData.address, "--swap"])
                        }
                    }
                }
            }
        }
    }
}
