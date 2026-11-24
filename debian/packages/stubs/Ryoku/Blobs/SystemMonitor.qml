import QtQuick

Item {
    id: root

    property bool active: false
    property int samplePeriodMs: 1000
    property int historyLimit: 60
    property bool includeVirtualNetwork: false

    property real cpuPercent: 0.0
    property real memoryPercent: 0.0
    property real gpuPercent: 0.0
    property bool cpuAvailable: true
    property bool memoryAvailable: true
    property bool gpuAvailable: false

    property real gpuPowerWatts: 0.0
    property real fanRpm: 0.0
    property string cpuName: "CPU"
    property string gpuName: "GPU"
    property string userName: ""
    property string hostName: ""
    property var uptimeSeconds: 0

    property real memoryUsedGiB: 2.0
    property real memoryTotalGiB: 16.0
    property real storageUsedGiB: 20.0
    property real storageTotalGiB: 100.0
    property int sampleCount: 0

    property var cpuHistory: []
    property var networkRxHistory: []
    property var networkTxHistory: []
    property var coreLoads: []
    property int coreCount: 4
    property real cpuFrequencyGhz: 2.4
    property real loadAverage: 0.5
    property int processCount: 150

    property real swapUsedGiB: 0.0
    property real swapTotalGiB: 4.0
    property real cpuTemp: 45.0
    property bool cpuTempAvailable: false
    property string cpuTempLabel: ""
    property real gpuTemp: 0.0
    property bool gpuTempAvailable: false
    property real gpuMemoryUsedGiB: 0.0
    property real gpuMemoryTotalGiB: 0.0
    property bool gpuMemoryAvailable: false
    property real storageTemp: 35.0
    property bool storageTempAvailable: false

    property real networkRxBytesPerSec: 0.0
    property real networkTxBytesPerSec: 0.0
    property bool networkAvailable: false
    property string networkInterface: ""

    property real diskReadBytesPerSec: 0.0
    property real diskWriteBytesPerSec: 0.0
    property bool diskAvailable: false

    property real batteryPercent: 100.0
    property bool batteryCharging: false
    property bool batteryAvailable: false
}
