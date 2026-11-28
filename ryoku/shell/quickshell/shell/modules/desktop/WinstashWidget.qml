import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import shell.services
import "Singletons"

Item {
    id: root

    property real s: 1.0
    property bool active: true
    property real slotX: 0
    property real slotY: 0
    property real slotW: 78
    property real slotH: 78

    property var stashed: []
    property bool expanded: false
    property string lastRaw: ""

    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-winstash-open"
    readonly property string winstashCmd: "BIN=$([ -x \"$HOME/.local/bin/ryoku-winstash\" ] && echo \"$HOME/.local/bin/ryoku-winstash\" || echo ryoku-winstash)"

    readonly property int orbSize: Math.round(64 * s)
    implicitWidth: orbSize + 14
    implicitHeight: orbSize + 14

    function resolveAppInfo(appClass) {
        var cls = (appClass || "").trim();
        if (!cls)
            return { name: "Stash", icon: Quickshell.iconPath("view-grid-symbolic", "application-x-executable") };
        var dockIcon = "";
        try { dockIcon = Dock.iconFor(cls) || ""; } catch (e) {}
        var low = cls.toLowerCase();
        var base = low.split("-")[0];
        var entry = DesktopEntries.heuristicLookup(cls)
            || DesktopEntries.byId(cls)
            || DesktopEntries.heuristicLookup(low)
            || DesktopEntries.byId(low)
            || (base !== low ? (DesktopEntries.heuristicLookup(base) || DesktopEntries.byId(base)) : null);
        var iconPath = dockIcon !== "" ? dockIcon
            : Quickshell.iconPath((entry && entry.icon) ? entry.icon : low, "application-x-executable");
        return {
            name: (entry && entry.name) ? entry.name : cls,
            icon: iconPath
        };
    }

    readonly property var topInfo: root.stashed.length > 0
        ? root.resolveAppInfo(root.stashed[0]["class"])
        : ({ name: "Stash", icon: Quickshell.iconPath("view-grid-symbolic", "application-x-executable") })

    function refresh() {
        if (root.active && !listProc.running)
            listProc.running = true;
    }

    function toggleExpanded() {
        runAction(["toggle-ui"]);
    }

    function runAction(args) {
        var quoted = args.map(function(a) {
            return "'" + String(a).replace(/'/g, "'\\''") + "'";
        }).join(" ");
        actionProc.command = ["bash", "-c", root.winstashCmd + "; exec \"$BIN\" " + quoted];
        actionProc.running = true;
    }

    Timer {
        interval: 450
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    Process {
        id: listProc
        command: [
            "bash", "-c",
            root.winstashCmd + "; printf '%s\\n' \"$([ -f '" + root.stateFile + "' ] && echo 1 || echo 0)\"; \"$BIN\" list"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = (this.text || "").trim();
                var lines = raw.split("\n");
                if (lines.length >= 2) {
                    root.expanded = (lines[0].trim() === "1");
                    var jsonStr = lines.slice(1).join("\n");
                    if (jsonStr !== root.lastRaw) {
                        root.lastRaw = jsonStr;
                        try {
                            var parsed = JSON.parse(jsonStr);
                            if (Array.isArray(parsed)) root.stashed = parsed;
                        } catch (e) {}
                    }
                }
            }
        }
    }

    Process { id: actionProc; onExited: root.refresh() }

    // Subtle outer concentric ring
    Rectangle {
        anchors.centerIn: orb
        width: orb.width + (root.stashed.length > 1 ? 10 : 4)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: "#2a38bdf8"
    }

    // Main circular orb (dragged & clicked natively by WidgetSlot)
    Rectangle {
        id: orb
        anchors.centerIn: parent
        width: root.orbSize
        height: root.orbSize
        radius: width / 2
        color: root.expanded ? "#ee14243d" : "#e0101828"
        border.width: root.expanded ? 2 : 1.5
        border.color: root.stashed.length > 0 ? "#7038bdf8" : "#3094a3b8"

        Image {
            anchors.centerIn: parent
            source: root.topInfo.icon
            width: Math.round(28 * root.s)
            height: Math.round(28 * root.s)
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: root.stashed.length > 0 ? 1.0 : 0.6
        }
    }

    // Circular count badge
    Rectangle {
        visible: root.stashed.length > 0
        anchors { top: orb.top; right: orb.right; topMargin: -2; rightMargin: -2 }
        width: Math.round(22 * root.s)
        height: width
        radius: width / 2
        color: "#38bdf8"
        border.width: 2
        border.color: "#0d1b2e"
        Text {
            anchors.centerIn: parent
            text: root.stashed.length
            color: "#061529"
            font.pixelSize: Math.max(9, Math.round(10 * root.s))
            font.bold: true
        }
    }

    // ─── Expanded Overlay: 360° (center) / 180° (edge) / 90° (corner) ─────────
    PanelWindow {
        id: expandedWin
        visible: root.active && root.stashed.length > 0 && root.expanded
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash-fan"

        readonly property int cardW:   72
        readonly property int cardH:   72
        readonly property int cardGap: 14
        readonly property int rStart:  Math.max(125, Math.round(Math.min(width, height) * 0.16))
        readonly property int rStep:   Math.max(100, Math.round(Math.min(width, height) * 0.13))

        property real animProgress: 0
        property bool inputReady: false

        readonly property real originX: Math.max(40, Math.min(width - 40, root.slotX + root.slotW / 2))
        readonly property real originY: Math.max(40, Math.min(height - 40, root.slotY + root.slotH / 2))
        readonly property string nodeShape: Config.winstashShape || "circle"

        Timer {
            id: readyTimer
            interval: 180
            onTriggered: expandedWin.inputReady = true
        }

        onVisibleChanged: {
            if (visible) {
                animProgress = 0;
                inputReady = false;
                burstAnim.restart();
                readyTimer.restart();
            } else {
                animProgress = 0;
                inputReady = false;
                readyTimer.stop();
            }
        }

        NumberAnimation {
            id: burstAnim
            target: expandedWin; property: "animProgress"
            from: 0; to: 1; duration: 260
            easing.type: Easing.OutBack; easing.overshoot: 1.08
        }

        function arcLayout(idx, total) {
            var cW       = expandedWin.cardW;
            var cH       = expandedWin.cardH;
            var gap      = expandedWin.cardGap;
            var r0       = expandedWin.rStart;
            var rS       = expandedWin.rStep;
            var edgeMarginX = expandedWin.width  * 0.22;
            var edgeMarginY = expandedWin.height * 0.22;

            var nearLeft   = expandedWin.originX < edgeMarginX;
            var nearRight  = expandedWin.originX > expandedWin.width  - edgeMarginX;
            var nearTop    = expandedWin.originY < edgeMarginY;
            var nearBottom = expandedWin.originY > expandedWin.height - edgeMarginY;

            var sector = Math.PI * 2;
            var thetaMin = -Math.PI / 2;
            var fullCircle = true;

            if ((nearLeft || nearRight) && (nearTop || nearBottom)) {
                fullCircle = false;
                sector = Math.PI / 2;
                if (nearRight && nearBottom)      thetaMin = Math.PI;
                else if (nearLeft && nearBottom)  thetaMin = Math.PI * 1.5;
                else if (nearLeft && nearTop)     thetaMin = 0;
                else                              thetaMin = Math.PI * 0.5;
            } else if (nearLeft || nearRight || nearTop || nearBottom) {
                fullCircle = false;
                sector = Math.PI;
                if (nearLeft)        thetaMin = -Math.PI / 2;
                else if (nearRight)  thetaMin =  Math.PI / 2;
                else if (nearTop)    thetaMin =  0;
                else                 thetaMin =  Math.PI;
            }

            var ring = 0, placed = 0;

            while (ring < 20) {
                var r   = r0 + ring * rS;
                var cap = Math.max(1, Math.floor(sector / ((cW + gap) / r)));

                if (idx < placed + cap) {
                    var posInRing = idx - placed;
                    var countInRing = Math.min(cap, total - placed);
                    var theta;
                    if (fullCircle) {
                        theta = thetaMin + (posInRing / countInRing) * sector;
                    } else {
                        theta = (countInRing === 1)
                            ? (thetaMin + sector / 2)
                            : thetaMin + (posInRing / (countInRing - 1)) * sector;
                    }

                    var rawX = expandedWin.originX + r * Math.cos(theta) - cW / 2;
                    var rawY = expandedWin.originY + r * Math.sin(theta) - cH / 2;

                    rawX = Math.max(20, Math.min(expandedWin.width  - cW - 20, rawX));
                    rawY = Math.max(20, Math.min(expandedWin.height - cH - 20, rawY));

                    return { x: rawX, y: rawY };
                }
                placed += cap;
                ring++;
            }
            return { x: 60, y: 60 };
        }

        // Click-away backdrop
        Rectangle {
            anchors.fill: parent; color: "#28040914"; opacity: expandedWin.animProgress
            MouseArea {
                anchors.fill: parent
                onClicked: if (expandedWin.inputReady) root.runAction(["toggle-ui"])
            }
        }

        Repeater {
            model: root.stashed
            delegate: Item {
                id: card
                required property var modelData
                required property int index

                readonly property var layout:  expandedWin.arcLayout(index, root.stashed.length)
                readonly property var appInfo: root.resolveAppInfo(modelData["class"])
                readonly property real startX: expandedWin.originX - expandedWin.cardW / 2
                readonly property real startY: expandedWin.originY - expandedWin.cardH / 2

                width:  expandedWin.cardW
                height: expandedWin.cardH
                x:      startX + (layout.x - startX) * expandedWin.animProgress
                y:      startY + (layout.y - startY) * expandedWin.animProgress
                opacity: Math.min(1.0, expandedWin.animProgress * 1.6)
                z: cardMa.containsMouse ? 30 : (10 + index)

                Rectangle {
                    anchors.fill: parent
                    rotation: expandedWin.nodeShape === "diamond" ? 45 : 0
                    scale: expandedWin.nodeShape === "diamond" ? 0.84 : 1.0
                    radius: {
                        if (expandedWin.nodeShape === "circle")   return width / 2;
                        if (expandedWin.nodeShape === "squircle") return 18;
                        if (expandedWin.nodeShape === "diamond")  return 10;
                        return 4;
                    }
                    color: cardMa.containsMouse ? "#f2132540" : "#ea0d1729"
                    border.width: cardMa.containsMouse ? 2 : 1.5
                    border.color: cardMa.containsMouse ? "#38bdf8" : "#5538bdf8"
                }

                MouseArea {
                    id: cardMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (expandedWin.inputReady) root.runAction(["focus", modelData.address])
                }

                Image {
                    anchors.centerIn: parent
                    source: card.appInfo.icon
                    width: 30; height: 30
                    sourceSize.width: 30; sourceSize.height: 30
                    fillMode: Image.PreserveAspectFit; smooth: true
                }

                Rectangle {
                    anchors { top: parent.top; right: parent.right; topMargin: -2; rightMargin: -2 }
                    width: 20; height: 20; radius: 10
                    color: delMa.containsMouse ? "#e6fb7185" : "#cc1e293b"
                    border.width: 1; border.color: "#80fb7185"
                    Text { anchors.centerIn: parent; text: "✕"; color: delMa.containsMouse ? "#ffffff" : "#fda4af"; font.pixelSize: 9; font.bold: true }
                    MouseArea {
                        id: delMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (expandedWin.inputReady) root.runAction(["close", modelData.address])
                    }
                }

                Rectangle {
                    anchors { top: parent.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
                    width: Math.min(110, lbl.implicitWidth + 12)
                    height: 18; radius: 9
                    color: "#d90b1322"
                    border.width: 1; border.color: cardMa.containsMouse ? "#6038bdf8" : "#2594a3b8"
                    Text {
                        id: lbl
                        anchors.centerIn: parent
                        width: Math.min(98, implicitWidth)
                        text: card.appInfo.name
                        color: "#e2e8f0"; font.pixelSize: 9; font.bold: true
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Bottom-right control strip: Shape selector + "Tout ouvrir (N)"
        Row {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 28; bottomMargin: 24 }
            spacing: 8
            opacity: expandedWin.animProgress

            Rectangle {
                height: 26; width: shapeRow.implicitWidth + 12; radius: 13
                color: "#cc0d1b2e"
                border.width: 1; border.color: "#4038bdf8"
                Row {
                    id: shapeRow
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: [
                            { id: "circle",   glyph: "●" },
                            { id: "squircle", glyph: "▢" },
                            { id: "square",   glyph: "■" },
                            { id: "diamond",  glyph: "◆" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 20; height: 20; radius: 10
                            color: expandedWin.nodeShape === modelData.id ? "#38bdf8" : (shMa.containsMouse ? "#3038bdf8" : "transparent")
                            Text {
                                anchors.centerIn: parent
                                text: modelData.glyph
                                color: expandedWin.nodeShape === modelData.id ? "#061529" : "#94a3b8"
                                font.pixelSize: 10; font.bold: true
                            }
                            MouseArea {
                                id: shMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (expandedWin.inputReady) Config.winstashShape = modelData.id
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 102; height: 26; radius: 13
                color: restoreMa.containsMouse ? "#e616324f" : "#cc0d1b2e"
                border.width: 1; border.color: "#6038bdf8"
                Text {
                    anchors.centerIn: parent
                    text: "Tout ouvrir (" + root.stashed.length + ")"
                    color: "#7dd3fc"; font.pixelSize: 9; font.bold: true
                }
                MouseArea {
                    id: restoreMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (expandedWin.inputReady) root.runAction(["restore-all"])
                }
            }
        }
    }
}
