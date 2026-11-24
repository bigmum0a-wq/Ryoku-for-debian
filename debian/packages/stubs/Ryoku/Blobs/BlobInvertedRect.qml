import QtQuick

Item {
    id: root

    property var group: null
    property real radius: 0.0
    property var deformMatrix: null
    property var rawDeformMatrix: null
    property bool sinks: false

    property real borderLeft: 0.0
    property real borderRight: 0.0
    property real borderTop: 0.0
    property real borderBottom: 0.0
}
