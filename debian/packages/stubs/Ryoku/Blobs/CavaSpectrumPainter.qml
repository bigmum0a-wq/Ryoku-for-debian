pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property var points: []
    property string visualizerType: "bars"
    property real normalizationCeiling: 100.0
    property real fillRatio: 1.0
    property real spectrumOpacity: 1.0
    property color spectrumColor: "transparent"
    property var spectrumColors: []
    property real sampleStartRatio: 0.0
    property real sampleEndRatio: 1.0
    property bool reverseFrequency: false
    property real pixelsPerBar: 4.0
    property real barSpacing: 2.0
    property real barRadius: 2.0
    property real barMinHeight: 0.0
    property string barsOrigin: "bottom"
    property int smoothing: 2
    property string waveMode: "smooth"
    property real lineWidth: 2.0
    property real edgeInset: 0.0
    property real leftRadius: 0.0
    property real rightRadius: 0.0
    property real topLeftRadius: 0.0
    property real topRightRadius: 0.0
    property real bottomLeftRadius: 0.0
    property real bottomRightRadius: 0.0
    property real edgeSoftness: 0.0
    property string frequencyProfile: "flat"
    property real accentStrength: 0.0
    property bool mirroredStereo: false
    property real startOpacity: 1.0
    property real endOpacity: 1.0
    property real startTaper: 0.0
    property real endTaper: 0.0
    property var clipSegments: []
}
