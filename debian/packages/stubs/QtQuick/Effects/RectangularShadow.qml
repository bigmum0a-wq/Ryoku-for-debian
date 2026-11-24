// RectangularShadow - Debian Qt 6.8 compatibility stub
// Qt 6.9 introduced RectangularShadow in QtQuick.Effects natively.
// This stub emulates the same API using MultiEffect (available since Qt 6.5).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

MultiEffect {
    id: shadow

    // Core RectangularShadow API surface (Qt 6.9 compatible)
    property real radius: 0
    property vector2d offset: Qt.vector2d(0.0, 1.0)
    property real spread: 0
    property color color: "#80000000"
    property real blur: 4
    property bool cached: false

    // Wire MultiEffect shadow properties
    shadowEnabled: true
    shadowOpacity: shadow.color.a
    shadowColor: Qt.rgba(shadow.color.r, shadow.color.g, shadow.color.b, 1.0)
    // MultiEffect blur is normalized [0..1]; RectangularShadow blur is in pixels
    shadowBlur: Math.max(0.0, Math.min(1.0, shadow.blur / 64.0))
    shadowHorizontalOffset: shadow.offset.x * Math.max(1, shadow.blur)
    shadowVerticalOffset:   shadow.offset.y * Math.max(1, shadow.blur)
    shadowScale: 1.0 + (shadow.spread / Math.max(width, 1))
}
