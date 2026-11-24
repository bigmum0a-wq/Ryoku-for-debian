import QtQuick

Item {
    id: root

    property bool active: false
    property string source: ""
    property var samples: []
    property bool running: false
    property bool silent: true

    signal frame()
}
