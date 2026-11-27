import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var stashed: []
    property var activeWindows: []
    property bool expanded: false
    property string lastRaw: ""
    property string lastWinRaw: ""

    // Draggable stack position (margins from right & bottom edges)
    property real stackRight: 16
    property real stackBottom: 24

    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-winstash-open"
    readonly property string winstashCmd: "BIN=$([ -x \"$HOME/.local/bin/ryoku-winstash\" ] && echo \"$HOME/.local/bin/ryoku-winstash\" || echo ryoku-winstash)"

    function resolveAppInfo(appClass) {
        var cls = (appClass || "").trim();
        if (!cls) return { name: "Application", icon: Quickshell.iconPath("application-x-executable") };
        var entry = DesktopEntries.heuristicLookup(cls);
        if (!entry) entry = DesktopEntries.byId(cls);
        var displayName = (entry && entry.name) ? entry.name : cls;
        var iconName    = (entry && entry.icon) ? entry.icon : cls.toLowerCase();
        return { name: displayName, icon: Quickshell.iconPath(iconName, "application-x-executable") };
    }

    function refresh() {
        if (!listProc.running)
            listProc.running = true;
    }

    Timer { interval: 500; running: true; repeat: true; onTriggered: root.refresh() }

    Process {
        id: listProc
        command: [
            "bash", "-c",
            root.winstashCmd + "; printf '%s\\n' \"$([ -f '" + root.stateFile + "' ] && echo 1 || echo 0)\"; \"$BIN\" list; echo '---WINLIST---'; \"$BIN\" win-list"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = (this.text || "").trim();
                var sep = raw.indexOf("\n---WINLIST---\n");
                var stashPart = sep >= 0 ? raw.slice(0, sep) : raw;
                var winPart = sep >= 0 ? raw.slice(sep + 15).trim() : "[]";

                var lines = stashPart.split("\n");
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
                if (winPart !== root.lastWinRaw) {
                    root.lastWinRaw = winPart;
                    try {
                        var parsedWins = JSON.parse(winPart);
                        if (Array.isArray(parsedWins)) root.activeWindows = parsedWins;
                    } catch (e) {}
                }
            }
        }
    }

    Process { id: actionProc; onExited: root.refresh() }
    function runAction(args) {
        var quoted = args.map(function(a) {
            return "'" + String(a).replace(/'/g, "'\\''") + "'";
        }).join(" ");
        actionProc.command = ["bash", "-c", root.winstashCmd + "; exec \"$BIN\" " + quoted];
        actionProc.running = true;
    }

    // ─── Per-window corner touch/mouse controls (− □ ✕) ──────────────────────
    // Click-through everywhere except on the tiny 74x22 pill at each window's top-right corner.
    // Right-click any pill (or run `ryoku-winstash controls-toggle`) to hide/show.
    PanelWindow {
        id: winControlsWin
        visible: root.activeWindows.length > 0 && !root.expanded
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "ryoku-wincontrols"

        // Input mask: only the pill rectangles receive events, the rest is click-through.
        // We use item-based regions — rebuilt lazily via Qt.callLater to avoid tight loops.
        property Component _regionComp: Component {
            Region { }
        }
        property var _maskRegs: []

        function rebuildMask() {
            // Destroy previous region objects
            for (var j = 0; j < _maskRegs.length; j++) {
                if (_maskRegs[j] && !_maskRegs[j].destroyed) _maskRegs[j].destroy();
            }
            var regs = [];
            for (var i = 0; i < pillRepeater.count; i++) {
                var it = pillRepeater.itemAt(i);
                if (it && it.visible) {
                    var r = _regionComp.createObject(winControlsWin, { item: it });
                    if (r) regs.push(r);
                }
            }
            _maskRegs = regs;
            controlsMask.regions = regs;
        }

        mask: Region {
            id: controlsMask
            regions: []
        }

        Repeater {
            id: pillRepeater
            model: root.activeWindows
            onCountChanged: Qt.callLater(winControlsWin.rebuildMask)

            delegate: Rectangle {
                id: pill
                required property var modelData

                // Position pill at top-right of its window (screen-absolute coordinates from win-list)
                x: Math.max(4, Math.min(winControlsWin.width  - width  - 4,
                                        modelData.x + modelData.w - width - 8))
                y: Math.max(4, Math.min(winControlsWin.height - height - 4,
                                        modelData.y + 6))
                width: 76; height: 22; radius: 11
                color: "#d90d1729"
                border.width: 1; border.color: "#4438bdf8"

                // Rebuild mask whenever a pill moves (window moved/resized)
                onXChanged: Qt.callLater(winControlsWin.rebuildMask)
                onYChanged: Qt.callLater(winControlsWin.rebuildMask)
                Component.onCompleted: Qt.callLater(winControlsWin.rebuildMask)
                Component.onDestruction: Qt.callLater(winControlsWin.rebuildMask)

                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    // ── Stash / hide (−) ──────────────────────────────────────
                    Rectangle {
                        width: 22; height: 18; radius: 9
                        color: minMa.containsMouse ? "#44facc15" : "transparent"
                        Text {
                            anchors.centerIn: parent; text: "−"
                            color: "#fde047"; font.pixelSize: 13; font.bold: true
                        }
                        MouseArea {
                            id: minMa; anchors.fill: parent; hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    root.runAction(["controls-toggle"]);
                                else
                                    root.runAction(["hide-addr", modelData.address]);
                            }
                        }
                    }

                    // ── Resize cycle: □ normal→max | ❐ max→medium | ▫ medium→compact ──
                    Rectangle {
                        width: 22; height: 18; radius: 9
                        color: maxMa.containsMouse ? "#444ade80" : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (modelData.sizeState === "max")     return "❐";
                                if (modelData.sizeState === "medium")  return "▫";
                                if (modelData.sizeState === "compact") return "□";
                                return "□";
                            }
                            color: modelData.sizeState === "max" ? "#7dd3fc" : "#86efac"
                            font.pixelSize: 10; font.bold: true
                        }
                        MouseArea {
                            id: maxMa; anchors.fill: parent; hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    root.runAction(["controls-toggle"]);
                                else
                                    root.runAction(["maximize", modelData.address]);
                            }
                        }
                    }

                    // ── Close (✕) ─────────────────────────────────────────────
                    Rectangle {
                        width: 22; height: 18; radius: 9
                        color: closeWinMa.containsMouse ? "#55fb7185" : "transparent"
                        Text {
                            anchors.centerIn: parent; text: "✕"
                            color: "#fda4af"; font.pixelSize: 10; font.bold: true
                        }
                        MouseArea {
                            id: closeWinMa; anchors.fill: parent; hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    root.runAction(["controls-toggle"]);
                                else
                                    root.runAction(["close", modelData.address]);
                            }
                        }
                    }
                }
            }
        }
    }

    // ─── Collapsed: stacked miniature cards (long-press + drag to move anywhere) ───
    PanelWindow {
        id: collapsedWin
        visible: root.stashed.length > 0 && !root.expanded
        anchors { right: true; bottom: true }
        margins { right: root.stackRight; bottom: root.stackBottom }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash"
        // Fixed dimensions: card 90×72 + 3-card fan offset (3×8=24 x, 3×6=18 y) + 14px padding
        width: 136; height: 110

        property bool dragging: false
        property bool justDragged: false
        property real pressX: 0
        property real pressY: 0

        // Computed top-card info (index 0 = most recently stashed)
        readonly property var topInfo: root.stashed.length > 0
            ? root.resolveAppInfo(root.stashed[0]["class"]) : ({ name: "", icon: "" })

        Item {
            anchors.fill: parent

            // ── Fan of up to 4 ghost cards behind the top card ──────────────
            Repeater {
                model: Math.min(4, root.stashed.length)
                delegate: Rectangle {
                    required property int index
                    // rev=0 → topmost (frontmost) card; rev=3 → deepest background
                    readonly property int rev: Math.min(4, root.stashed.length) - 1 - index

                    // Cards are 90×72, fanned from bottom-left corner with small offsets
                    width: 90; height: 72
                    // Anchor fan to bottom-left: main card at (10, 14), background cards shift right+up
                    x: 10 + rev * 8
                    y: 14 + rev * 6
                    rotation: rev === 0 ? 0 : (rev % 2 === 0 ? 2.5 : -2.5)
                    radius: 12
                    color: {
                        if (rev === 0) return collapsedWin.dragging ? "#f0101828" : "#e6101828";
                        if (rev === 1) return "#cc162238";
                        if (rev === 2) return "#aa1c2d4a";
                        return "#771c2d4a";
                    }
                    border.width: rev === 0 && collapsedWin.dragging ? 2 : 1
                    border.color: rev === 0
                        ? (collapsedWin.dragging ? "#38bdf8" : "#8038bdf8")
                        : "#3094a3b8"

                    // Only the top card shows content
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8
                        visible: rev === 0; spacing: 4

                        RowLayout {
                            Layout.fillWidth: true; spacing: 5
                            Image {
                                source: collapsedWin.topInfo.icon
                                width: 16; height: 16
                                sourceSize.width: 16; sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit; smooth: true
                            }
                            Text {
                                text: collapsedWin.topInfo.name
                                color: "#e2e8f0"; font.pixelSize: 10; font.bold: true
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                        Text {
                            text: root.stashed.length > 0 ? (root.stashed[0].title || "") : ""
                            color: "#94a3b8"; font.pixelSize: 8
                            elide: Text.ElideRight; maximumLineCount: 2
                            wrapMode: Text.Wrap; Layout.fillWidth: true; Layout.fillHeight: true
                        }
                    }
                }
            }

            // ── Count badge (circle) — top-right corner of the panel ────────
            Rectangle {
                id: countBadge
                anchors { top: parent.top; right: parent.right; topMargin: 6; rightMargin: 6 }
                width: 24; height: 24; radius: 12
                color: "#38bdf8"
                border.width: 2; border.color: "#0d1b2e"
                Text {
                    anchors.centerIn: parent
                    text: root.stashed.length
                    color: "#061529"; font.pixelSize: 11; font.bold: true
                }
            }

            // ── Drag / click handler ─────────────────────────────────────────
            MouseArea {
                anchors.fill: parent
                pressAndHoldInterval: 300
                cursorShape: collapsedWin.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                z: 10

                onPressed: mouse => {
                    collapsedWin.pressX = mouse.x;
                    collapsedWin.pressY = mouse.y;
                    collapsedWin.justDragged = false;
                }
                onPressAndHold: {
                    collapsedWin.dragging = true;
                    collapsedWin.justDragged = true;
                }
                onPositionChanged: mouse => {
                    if (!collapsedWin.dragging) return;
                    var dx = mouse.x - collapsedWin.pressX;
                    var dy = mouse.y - collapsedWin.pressY;
                    var scrW = collapsedWin.screen ? collapsedWin.screen.width  : 1280;
                    var scrH = collapsedWin.screen ? collapsedWin.screen.height : 720;
                    root.stackRight  = Math.max(0, Math.min(scrW - collapsedWin.width,  root.stackRight  - dx));
                    root.stackBottom = Math.max(0, Math.min(scrH - collapsedWin.height, root.stackBottom - dy));
                }
                onReleased: { collapsedWin.dragging = false; }
                onClicked: {
                    if (!collapsedWin.justDragged) root.runAction(["toggle-ui"]);
                    collapsedWin.justDragged = false;
                }
            }
        }
    }

    // ─── Expanded: Adaptive Concentric Arc Layout (quarter-circle, 90°) ───────
    // Adapts its 90° sector inward from wherever the stack is currently positioned.
    PanelWindow {
        id: expandedWin
        visible: root.stashed.length > 0 && root.expanded
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash-fan"

        readonly property int cardW:   86
        readonly property int cardH:   68
        readonly property int cardGap: 10
        readonly property int rStart:  Math.max(145, Math.round(Math.min(width, height) * 0.19))
        readonly property int rStep:   Math.max(120, Math.round(Math.min(width, height) * 0.15))

        property real animProgress: 0
        property bool inputReady: false

        // Origin = center of the stack at its current dragged position
        readonly property real originX: Math.max(cardW / 2, width - root.stackRight - 64)
        readonly property real originY: Math.max(cardH / 2, height - root.stackBottom - 52)

        Timer {
            id: readyTimer
            interval: 220
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
            from: 0; to: 1; duration: 280
            easing.type: Easing.OutBack; easing.overshoot: 1.08
        }

        function arcLayout(idx, total) {
            var cW       = expandedWin.cardW;
            var cH       = expandedWin.cardH;
            var gap      = expandedWin.cardGap;
            var r0       = expandedWin.rStart;
            var rS       = expandedWin.rStep;
            var sector   = Math.PI / 2;

            // Pick 90° quadrant pointing inward toward screen center from (originX, originY)
            var goLeft = expandedWin.originX >= expandedWin.width / 2;
            var goUp   = expandedWin.originY >= expandedWin.height / 2;
            var thetaMin;
            if (goLeft && goUp)        thetaMin = Math.PI;          // 180° -> 270° (left to up)
            else if (!goLeft && goUp)  thetaMin = Math.PI * 1.5;    // 270° -> 360° (up to right)
            else if (!goLeft && !goUp) thetaMin = 0;                // 0°   -> 90°  (right to down)
            else                       thetaMin = Math.PI * 0.5;    // 90°  -> 180° (down to left)

            var thetaMax = thetaMin + sector;
            var ring = 0, placed = 0;

            while (ring < 20) {
                var r   = r0 + ring * rS;
                var cap = Math.max(1, Math.floor(sector / ((cW + gap) / r)));

                if (idx < placed + cap) {
                    var posInRing = idx - placed;
                    var theta = (cap === 1)
                        ? (thetaMin + thetaMax) / 2
                        : thetaMin + (posInRing / (cap - 1)) * sector;

                    var baseDeg   = Math.atan2(cH / 2, cW / 2) * 180 / Math.PI;
                    var targetDeg = Math.atan2(-Math.sin(theta), -Math.cos(theta)) * 180 / Math.PI;
                    var rotDeg    = targetDeg - baseDeg;

                    var rawX = expandedWin.originX + r * Math.cos(theta) - cW / 2;
                    var rawY = expandedWin.originY + r * Math.sin(theta) - cH / 2;

                    rawX = Math.max(20, Math.min(expandedWin.width  - cW - 20, rawX));
                    rawY = Math.max(20, Math.min(expandedWin.height - cH - 20, rawY));

                    return { x: rawX, y: rawY, rot: rotDeg };
                }
                placed += cap;
                ring++;
            }
            return { x: 60, y: 60, rot: 0 };
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
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                readonly property var layout:  expandedWin.arcLayout(index, root.stashed.length)
                readonly property var appInfo: root.resolveAppInfo(modelData["class"])
                readonly property real startX: expandedWin.originX - expandedWin.cardW / 2
                readonly property real startY: expandedWin.originY - expandedWin.cardH / 2

                width:  expandedWin.cardW
                height: expandedWin.cardH
                x:        startX + (layout.x - startX) * expandedWin.animProgress
                y:        startY + (layout.y - startY) * expandedWin.animProgress
                rotation: layout.rot * expandedWin.animProgress
                opacity:  Math.min(1.0, expandedWin.animProgress * 1.6)
                z: cardMa.containsMouse ? 30 : (10 + index)

                radius: 12
                color: cardMa.containsMouse ? "#f0132540" : "#ea0d1729"
                border.width: 1
                border.color: cardMa.containsMouse ? "#a038bdf8" : "#4038bdf8"

                MouseArea {
                    id: cardMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (expandedWin.inputReady) root.runAction(["focus", modelData.address])
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 3

                    RowLayout {
                        Layout.fillWidth: true; spacing: 5
                        Image {
                            source: card.appInfo.icon
                            width: 14; height: 14
                            sourceSize.width: 14; sourceSize.height: 14
                            fillMode: Image.PreserveAspectFit; smooth: true
                        }
                        Text {
                            text: card.appInfo.name
                            color: "#f1f5f9"; font.pixelSize: 10; font.bold: true
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Rectangle {
                            width: 15; height: 15; radius: 4
                            color: delMa.containsMouse ? "#55fb7185" : "#22fb7185"
                            Text { anchors.centerIn: parent; text: "✕"; color: "#fda4af"; font.pixelSize: 8 }
                            MouseArea {
                                id: delMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (expandedWin.inputReady) root.runAction(["close", modelData.address])
                            }
                        }
                    }

                    Text {
                        text: modelData.title || ""
                        color: "#94a3b8"; font.pixelSize: 8
                        elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                        Layout.fillWidth: true; Layout.fillHeight: true
                    }
                }
            }
        }

        // "Tout ouvrir" pill — offset from stack click spot so a double-click never triggers it
        Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 148; bottomMargin: 24 }
            width: 96; height: 26; radius: 13
            color: restoreMa.containsMouse ? "#e616324f" : "#cc0d1b2e"
            border.width: 1; border.color: "#6038bdf8"
            opacity: expandedWin.animProgress

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
