import QtQuick

Item {
    id: root
    property string state: "idle"
    property string preset: "default"
    property color ink: "#ffffff"
    property bool animated: true
    property real speed: 1.0
    property bool paused: false
    property var frameCount: 0
}
