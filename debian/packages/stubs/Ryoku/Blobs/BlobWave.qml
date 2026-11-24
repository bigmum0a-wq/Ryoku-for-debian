import QtQuick

BlobRect {
    id: root

    property var levels: []
    property int points: 0
    property real amplitude: 0.0
    property real gain: 1.0
    property bool mirror: false
    property real edgeInset: 0.0
    property real waveStiffness: 1.0
    property real waveDamping: 1.0
    property bool stepped: false
    property real blockPitch: 0.0
    property bool moving: false
}
