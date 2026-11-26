import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var stashed: []
    property bool expanded: false
    property string lastRaw: ""
    readonly property string stateFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-winstash-open"

    function resolveAppInfo(appClass) {
        var cls = (appClass || "").trim();
        if (!cls) return { name: "Application", icon: Quickshell.iconPath("application-x-executable") };
        var entry = DesktopEntries.heuristicLookup(cls);
        if (!entry) entry = DesktopEntries.byId(cls);
        var displayName = (entry && entry.name) ? entry.name : cls;
        var iconName    = (entry && entry.icon) ? entry.icon : cls.toLowerCase();
        return { name: displayName, icon: Quickshell.iconPath(iconName, "application-x-executable") };
    }

    function refresh() { if (!listProc.running) listProc.running = true; }

    Timer { interval: 600; running: true; repeat: true; onTriggered: root.refresh() }

    Process {
        id: listProc
        command: ["bash", "-c",
            "printf '%s\\n' \"$([ -f '" + root.stateFile + "' ] && echo 1 || echo 0)\"; ryoku-winstash list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (this.text || "").trim().split("\n");
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
    function runAction(args) {
        actionProc.command = ["ryoku-winstash"].concat(args);
        actionProc.running = true;
    }

    // ─── Collapsed: stacked cards in bottom-right corner ─────────────────────
    PanelWindow {
        id: collapsedWin
        visible: root.stashed.length > 0 && !root.expanded
        anchors { right: true; bottom: true }
        margins { right: 16; bottom: 24 }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash"
        implicitWidth: 128; implicitHeight: 104

        Item {
            anchors.fill: parent

            Repeater {
                model: Math.min(4, root.stashed.length)
                delegate: Rectangle {
                    required property int index
                    readonly property int rev: Math.min(4, root.stashed.length) - 1 - index
                    readonly property var topInfo: root.stashed.length > 0
                        ? root.resolveAppInfo(root.stashed[0]["class"]) : ({ name: "", icon: "" })
                    width: 86; height: 68
                    x: 16 + rev * 7; y: 16 + rev * 5
                    rotation: (rev - 1) * 3.5; radius: 12
                    color: rev === 0 ? "#e6101828" : (rev === 1 ? "#cc162238" : "#aa1c2d4a")
                    border.width: 1
                    border.color: rev === 0 ? "#8038bdf8" : "#4094a3b8"

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8
                        visible: rev === 0; spacing: 4
                        RowLayout {
                            Layout.fillWidth: true; spacing: 5
                            Image {
                                source: topInfo.icon
                                width: 16; height: 16
                                sourceSize.width: 16; sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                text: topInfo.name; color: "#e2e8f0"
                                font.pixelSize: 11; font.bold: true
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                        Text {
                            text: root.stashed.length > 0 ? (root.stashed[0].title || "") : ""
                            color: "#94a3b8"; font.pixelSize: 9; elide: Text.ElideRight
                            maximumLineCount: 2; wrapMode: Text.Wrap; Layout.fillWidth: true
                        }
                    }
                }
            }

            Rectangle {
                anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                width: 24; height: 24; radius: 12; color: "#38bdf8"
                Text { anchors.centerIn: parent; text: root.stashed.length; color: "#061529"; font.pixelSize: 12; font.bold: true }
            }

            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.runAction(["toggle-ui"])
            }
        }
    }

    // ─── Expanded: Adaptive Concentric Arc Layout (quarter-circle, 90°) ───────
    //
    //  Origin of arcs = bottom-right corner of screen (cx, cy) = (W, H).
    //  Sector angle   = 90° from straight-left (θ=180°) to straight-up (θ=270°).
    //  Each arc's capacity = floor( (π/2) / ((cardW + gap) / r) )
    //    → capacity grows with radius, never hard-coded.
    //  Cards fill the innermost arc first, then overflow to the next.
    //  Each card is tangentially aligned: its long axis follows the arc tangent.
    //
    PanelWindow {
        id: expandedWin
        visible: root.stashed.length > 0 && root.expanded
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash-fan"

        // Card dimensions (px)
        readonly property int cardW: 148
        readonly property int cardH: 80
        // Minimum angular gap between two cards, expressed in screen-px at the arc radius
        readonly property int cardGap: 14
        // Innermost arc radius (px from corner). Enough to clear the stacked-card UI.
        readonly property int rStart: 165
        // Radial distance between successive arcs. Must be ≥ cardH + gap to avoid overlap.
        readonly property int rStep: 108

        property real animProgress: 0

        onVisibleChanged: {
            if (visible) { animProgress = 0; burstAnim.restart(); }
            else animProgress = 0;
        }

        NumberAnimation {
            id: burstAnim
            target: expandedWin; property: "animProgress"
            from: 0; to: 1; duration: 300
            easing.type: Easing.OutBack; easing.overshoot: 1.1
        }

        // ── Core layout algorithm ─────────────────────────────────────────────
        // Returns { x, y, rot } for card at index `idx` among `total` cards.
        //
        //  Sector: θ ∈ [π, 3π/2]  (180° → 270° in screen/math convention, Y-down)
        //    θ = π     → card is directly to the LEFT  of the corner
        //    θ = 3π/2  → card is directly ABOVE the corner
        //    θ = 5π/4  → diagonal (centre of the sector)
        //
        //  Card position:
        //    cx = screen_width + r·cos(θ)   → goes left as θ → π
        //    cy = screen_height + r·sin(θ)  → goes up  as θ → 3π/2
        //
        //  Tangential rotation:
        //    The long axis of the card (width direction) must align with the arc tangent.
        //    Arc tangent at θ: perpendicular to radius = angle (θ + π/2).
        //    In QML clockwise degrees: rotDeg = θ_deg − 270°
        //      θ=180° → rot=−90° (card is vertical)
        //      θ=270° → rot=0°   (card is horizontal)
        //      θ=225° → rot=−45° (card is diagonal)
        //
        function arcLayout(idx, total) {
            var cx        = expandedWin.width;
            var cy        = expandedWin.height;
            var cW        = expandedWin.cardW;
            var cH        = expandedWin.cardH;
            var gap       = expandedWin.cardGap;
            var r0        = expandedWin.rStart;
            var rS        = expandedWin.rStep;
            var sector    = Math.PI / 2;           // 90° in radians
            var thetaMin  = Math.PI;               // 180° — straight left
            var thetaMax  = Math.PI * 1.5;         // 270° — straight up

            var ring = 0, placed = 0;

            while (ring < 20) {
                var r   = r0 + ring * rS;
                // Capacity: number of cards that fit on this arc without overlapping
                var cap = Math.max(1, Math.floor(sector / ((cW + gap) / r)));

                if (idx < placed + cap) {
                    var posInRing = idx - placed;
                    var theta;

                    if (cap === 1) {
                        // Single card → centre of the sector
                        theta = (thetaMin + thetaMax) / 2;
                    } else {
                        // Distribute evenly: first card at thetaMin, last at thetaMax
                        theta = thetaMin + (posInRing / (cap - 1)) * sector;
                    }

                    // Tangential alignment
                    var rotDeg = (theta * 180 / Math.PI) - 270;

                    // Card centre position on the arc
                    var rawX = cx + r * Math.cos(theta) - cW / 2;
                    var rawY = cy + r * Math.sin(theta) - cH / 2;

                    // Clamp to stay within screen (generous 20 px inset)
                    rawX = Math.max(20, Math.min(expandedWin.width  - cW - 20, rawX));
                    rawY = Math.max(20, Math.min(expandedWin.height - cH - 20, rawY));

                    return { x: rawX, y: rawY, rot: rotDeg };
                }

                placed += cap;
                ring++;
            }

            // Safety fallback (shouldn't be reached for realistic window counts)
            return { x: 60, y: 60, rot: 0 };
        }

        // Transparent backdrop — click anywhere outside the cards to collapse
        Rectangle {
            anchors.fill: parent; color: "#28040914"; opacity: expandedWin.animProgress
            MouseArea { anchors.fill: parent; onClicked: root.runAction(["toggle-ui"]) }
        }

        // ── Individual floating cards ────────────────────────────────────────
        Repeater {
            model: root.stashed
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                readonly property var layout:  expandedWin.arcLayout(index, root.stashed.length)
                readonly property var appInfo: root.resolveAppInfo(modelData["class"])

                // Burst animation: cards originate from the stacked-card position (corner)
                readonly property real cornerX: expandedWin.width  - expandedWin.cardW / 2
                readonly property real cornerY: expandedWin.height - expandedWin.cardH / 2

                width: expandedWin.cardW; height: expandedWin.cardH
                x: cornerX + (layout.x - cornerX) * expandedWin.animProgress
                y: cornerY + (layout.y - cornerY) * expandedWin.animProgress
                rotation: layout.rot * expandedWin.animProgress
                scale:    (0.45 + 0.55 * expandedWin.animProgress) * (cardMa.containsMouse ? 1.09 : 1.0)
                opacity:  Math.min(1, expandedWin.animProgress * 1.5)
                z: cardMa.containsMouse ? 30 : (10 + index)

                radius: 14
                color: cardMa.containsMouse ? "#f0132540" : "#ea0d1729"
                border.width: 1
                border.color: cardMa.containsMouse ? "#a038bdf8" : "#4038bdf8"

                Behavior on scale {
                    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    id: cardMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runAction(["focus", modelData.address, "--swap"])
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 9; spacing: 4

                    RowLayout {
                        Layout.fillWidth: true; spacing: 7

                        Image {
                            source: card.appInfo.icon
                            width: 22; height: 22
                            sourceSize.width: 22; sourceSize.height: 22
                            fillMode: Image.PreserveAspectFit; smooth: true
                        }

                        Text {
                            text: card.appInfo.name
                            color: "#f1f5f9"; font.pixelSize: 11; font.bold: true
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }

                        Rectangle {
                            width: 18; height: 18; radius: 6
                            color: delMa.containsMouse ? "#55fb7185" : "#22fb7185"
                            Text { anchors.centerIn: parent; text: "✕"; color: "#fda4af"; font.pixelSize: 9 }
                            MouseArea {
                                id: delMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["close", modelData.address])
                            }
                        }
                    }

                    Text {
                        text: modelData.title || ""
                        color: "#94a3b8"; font.pixelSize: 9
                        elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                        Layout.fillWidth: true; Layout.fillHeight: true
                    }
                }
            }
        }

        // "Tout ouvrir" pill — floats near the origin corner, unobtrusive
        Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 20; bottomMargin: 22 }
            width: 100; height: 30; radius: 15
            color: restoreMa.containsMouse ? "#e616324f" : "#cc0d1b2e"
            border.width: 1; border.color: "#6038bdf8"
            opacity: expandedWin.animProgress

            Text {
                anchors.centerIn: parent
                text: "Tout ouvrir (" + root.stashed.length + ")"
                color: "#7dd3fc"; font.pixelSize: 10; font.bold: true
            }
            MouseArea {
                id: restoreMa; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runAction(["restore-all"])
            }
        }
    }
}
