import QtQuick

Item {
    id: root

    property int fitMode: 0
    property url depthPath
    property url mattePath
    property real imageZoom: 1.0
    property real outputAspect: 1.0
    property real sourceAspect: 1.0
    property real focusDistance: 0.0
    property real backgroundDistance: 0.0
    property bool valid: false
}
