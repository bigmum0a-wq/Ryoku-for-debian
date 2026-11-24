import QtQuick

Item {
    id: root

    property var source: null
    property bool active: false
    property bool animated: true
    property var channels: ["cpu", "memory", "gpu"]
    property var colors: []
    property bool fill: true
    property bool showGrid: true
    property bool detailPoints: true
    property color gridColor: "transparent"
    property real lineWidth: 2.0
    property int sampleCount: 0
    property int windowSeconds: 60
    property var frameCount: 0
}
