import QtQuick

Item {
    id: root

    property var group: null
    property real radius: 0.0
    property var deformMatrix: null
    property var rawDeformMatrix: null
    property bool sinks: false

    property real stiffness: 1.0
    property real damping: 1.0
    property real deformScale: 1.0
    property real taper: 0.0
    property list<Item> exclude
    property real topLeftRadius: 0.0
    property real topRightRadius: 0.0
    property real bottomLeftRadius: 0.0
    property real bottomRightRadius: 0.0
}
