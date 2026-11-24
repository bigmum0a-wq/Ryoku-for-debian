import QtQuick

Item {
    id: root

    property var points: []
    property string visualizerType: "bars"
    property real normalizationCeiling: 1.0
    property real fillRatio: 1.0
    property real spectrumOpacity: 1.0
    property color spectrumColor: "white"
    property var spectrumColors: []
    property real sampleStartRatio: 0.0
    property real sampleEndRatio: 1.0
    property bool reverseFrequency: false
    property real pixelsPerBar: 4.0
    property real barSpacing: 2.0
    property real barRadius: 2.0
    property real barMinHeight: 1.0
    property string barsOrigin: "bottom"
    property int smoothing: 2
    property string waveMode: "lines"
    property real lineWidth: 1.0
    property real edgeInset: 0.0
    property real leftRadius: 0.0
    property real rightRadius: 0.0
}
