import QtQuick

Item {
    id: root
    property bool active: false
    property int bars: 40
    property int framerate: 30
    property string method: "pipewire"
    property string source: "auto"
    property bool captureActive: false
    property bool autosens: true
    property int sensitivity: 150
    property int noiseReduction: 25
    property bool peakFollow: true
    property int staleMs: 120
    property real noiseFloor: 0.0
    property var levels: []
    property real energy: 0.0
    property bool running: false
    property bool silent: true
}
