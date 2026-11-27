import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property string mode: Quickshell.env("RYOKU_DOCK_PICKER_MODE") || "manage"
    readonly property string targetId: Quickshell.env("RYOKU_DOCK_PICKER_TARGET") || ""

    property var allApps: []
    property string query: ""

    readonly property var filteredApps: {
        var q = root.query.trim().toLowerCase();
        if (!q) return root.allApps;
        return root.allApps.filter(function(a) {
            return (a.name || "").toLowerCase().indexOf(q) !== -1
                || (a.id || "").toLowerCase().indexOf(q) !== -1;
        });
    }

    function reload() {
        listProc.running = true;
    }

    Component.onCompleted: reload()

    Process {
        id: listProc
        command: ["sh", "-c", 'exec "$(command -v ryoku-dock-picker || echo "$HOME/.local/bin/ryoku-dock-picker")" --list']
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text || "[]");
                    if (Array.isArray(parsed))
                        root.allApps = parsed;
                } catch (e) {}
            }
        }
    }

    Process {
        id: actProc
        onExited: {
            if (root.mode === "replace")
                Qt.quit();
            else
                root.reload();
        }
    }

    PanelWindow {
        visible: true
        anchors {
            bottom: true
        }
        margins {
            bottom: 84
        }
        implicitWidth: 440
        implicitHeight: 520
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "ryoku-dock-picker"

        Shortcut {
            sequence: "Escape"
            onActivated: Qt.quit()
        }

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: "#f20b1322"
            border.width: 1
            border.color: "#5538bdf8"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.mode === "replace"
                              ? ("Replace \"" + root.targetId + "\"")
                              : "Manage dock apps"
                        color: "#f1f5f9"
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 8
                        color: closeMa.containsMouse ? "#33ffffff" : "#18ffffff"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: "#cbd5e1"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.quit()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    radius: 10
                    color: "#18ffffff"
                    border.width: 1
                    border.color: searchInput.activeFocus ? "#8038bdf8" : "#25ffffff"

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.margins: 9
                        color: "#f8fafc"
                        font.pixelSize: 13
                        focus: true
                        clip: true
                        onTextChanged: root.query = text

                        Text {
                            anchors.fill: parent
                            text: "Rechercher une application..."
                            color: "#64748b"
                            font.pixelSize: 13
                            visible: !searchInput.text && !searchInput.activeFocus
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.filteredApps

                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 46
                        radius: 10
                        color: itemMa.containsMouse ? "#2838bdf8" : (modelData.pinned ? "#1638bdf8" : "#10ffffff")
                        border.width: 1
                        border.color: modelData.pinned ? "#5538bdf8" : "#18ffffff"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    text: modelData.name || modelData.id
                                    color: "#f1f5f9"
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.id
                                    color: "#94a3b8"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Rectangle {
                                width: root.mode === "replace" ? 72 : 68
                                height: 24
                                radius: 7
                                color: root.mode === "replace"
                                       ? "#2a38bdf8"
                                       : (modelData.pinned ? "#3338bdf8" : "#18ffffff")
                                Text {
                                    anchors.centerIn: parent
                                    text: root.mode === "replace"
                                          ? "Select"
                                          : (modelData.pinned ? "Pinned" : "Add")
                                    color: modelData.pinned || root.mode === "replace" ? "#7dd3fc" : "#cbd5e1"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                        }

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.mode === "replace")
                                    actProc.command = ["sh", "-c", 'exec "$(command -v ryoku-dock-picker || echo "$HOME/.local/bin/ryoku-dock-picker")" --replace "$1" "$2"', "sh", root.targetId, modelData.id];
                                else
                                    actProc.command = ["sh", "-c", 'exec "$(command -v ryoku-dock-picker || echo "$HOME/.local/bin/ryoku-dock-picker")" --toggle "$1"', "sh", modelData.id];
                                actProc.running = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
