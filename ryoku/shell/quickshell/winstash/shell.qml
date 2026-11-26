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

    // ─── Collapsed: stacked miniature cards in bottom-right corner ───────────
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
                    // ── CARD DIMENSIONS: 86 × 68 px — reference size ───────────
                    width: 86; height: 68
                    x: 16 + rev * 7; y: 16 + rev * 5
                    rotation: (rev - 1) * 3.5; radius: 12
                    color: rev === 0 ? "#e6101828" : (rev === 1 ? "#cc162238" : "#aa1c2d4a")
                    border.width: 1
                    border.color: rev === 0 ? "#8038bdf8" : "#4094a3b8"

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8
                        visible: rev === 0; spacing: 3
                        RowLayout {
                            Layout.fillWidth: true; spacing: 5
                            Image {
                                source: topInfo.icon; width: 14; height: 14
                                sourceSize.width: 14; sourceSize.height: 14
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                text: topInfo.name; color: "#e2e8f0"
                                font.pixelSize: 10; font.bold: true
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                        Text {
                            text: root.stashed.length > 0 ? (root.stashed[0].title || "") : ""
                            color: "#94a3b8"; font.pixelSize: 8; elide: Text.ElideRight
                            maximumLineCount: 2; wrapMode: Text.Wrap; Layout.fillWidth: true
                        }
                    }
                }
            }
            Rectangle {
                anchors { top: parent.top; right: parent.right; topMargin: 8; rightMargin: 8 }
                width: 22; height: 22; radius: 11; color: "#38bdf8"
                Text { anchors.centerIn: parent; text: root.stashed.length; color: "#061529"; font.pixelSize: 11; font.bold: true }
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: root.runAction(["toggle-ui"])
            }
        }
    }

    // ─── Expanded: Adaptive Concentric Arc Layout ─────────────────────────────
    //
    //  Three independent operations (never mixed):
    //    1. DIMENSIONING  — fixed 86 × 68 px, identical to the collapsed stack card.
    //                       Never changed, never scaled, not on hover, not at any arc.
    //    2. POSITIONING   — computed on concentric arcs:
    //                         origin  = bottom-right corner (W, H)
    //                         sector  = 90°  [θ = π … 3π/2]  (left → up)
    //                         arc r   = rStart + ring × rStep
    //                         capacity(r) = ⌊(π/2) / ((cW+gap)/r)⌋   — never hardcoded
    //    3. ORIENTATION   — common geometric rule for all cards:
    //                         The card's bottom-right corner always points toward
    //                         the arc origin (screen corner).
    //                         rotDeg = atan2(−sinθ, −cosθ)·180/π − atan2(cH/2, cW/2)·180/π
    //                               ≈  varies from −38° (θ=π) to +52° (θ=3π/2)
    //
    PanelWindow {
        id: expandedWin
        visible: root.stashed.length > 0 && root.expanded
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "ryoku-winstash-fan"

        // ══ 1. DIMENSIONING — absolutely fixed ════════════════════════════════
        readonly property int cardW:   86    // px — matches collapsed stack card width
        readonly property int cardH:   68    // px — matches collapsed stack card height
        // ══ 2. ARC GEOMETRY — relative to screen size, never hardcoded ════════
        readonly property int cardGap: 10    // minimum tangential gap between cards (px at arc)
        // Inner arc radius: 9% of the shorter screen dimension (clears stack UI on any screen)
        readonly property int rStart:  Math.round(Math.min(width, height) * 0.09)
        // Radial pitch: 11% of shorter screen dimension — always > card radial extent + gap
        readonly property int rStep:   Math.round(Math.min(width, height) * 0.11)

        property real animProgress: 0

        onVisibleChanged: {
            if (visible) { animProgress = 0; burstAnim.restart(); }
            else animProgress = 0;
        }

        NumberAnimation {
            id: burstAnim
            target: expandedWin; property: "animProgress"
            from: 0; to: 1; duration: 300
            easing.type: Easing.OutBack; easing.overshoot: 1.08
        }

        // ── Core layout function ───────────────────────────────────────────────
        // Returns { x, y, rot } for card at position `idx` among `total`.
        // All three operations (position, rotation, dimensions) are independent.
        function arcLayout(idx, total) {
            var cW       = expandedWin.cardW;
            var cH       = expandedWin.cardH;
            var gap      = expandedWin.cardGap;
            var r0       = expandedWin.rStart;
            var rS       = expandedWin.rStep;
            var sector   = Math.PI / 2;     // 90° — fixed sector angle
            var thetaMin = Math.PI;          // 180° — straight left of origin
            var thetaMax = Math.PI * 1.5;    // 270° — straight above origin

            // ── 2. POSITIONING: find ring and angular position ─────────────────
            var ring = 0, placed = 0;
            while (ring < 20) {
                var r   = r0 + ring * rS;
                // Adaptive capacity: how many fixed-size cards fit on this arc.
                // Derived from arc length in the sector vs. card angular footprint.
                var cap = Math.max(1, Math.floor(sector / ((cW + gap) / r)));

                if (idx < placed + cap) {
                    var posInRing = idx - placed;
                    // Distribute cards evenly from thetaMin to thetaMax inclusive.
                    // Single card → midpoint of sector.
                    var theta = (cap === 1)
                        ? (thetaMin + thetaMax) / 2
                        : thetaMin + (posInRing / (cap - 1)) * sector;

                    // ── 3. ORIENTATION: bottom-right corner → origin ───────────
                    // Unrotated, the card's bottom-right corner is at angle:
                    var baseDeg   = Math.atan2(cH / 2, cW / 2) * 180 / Math.PI; // ≈ 38.3°
                    // Direction from card centre toward the arc origin, in screen space
                    // (Y-down): vector (−cosθ, −sinθ), angle = atan2(−sinθ, −cosθ).
                    var targetDeg = Math.atan2(-Math.sin(theta), -Math.cos(theta)) * 180 / Math.PI;
                    // Required QML clockwise rotation:
                    var rotDeg = targetDeg - baseDeg;

                    // Card top-left corner (x, y) so that the card centre sits on the arc
                    var rawX = expandedWin.width  + r * Math.cos(theta) - cW / 2;
                    var rawY = expandedWin.height + r * Math.sin(theta) - cH / 2;

                    // Safety clamp — keep cards on-screen even on small displays
                    rawX = Math.max(20, Math.min(expandedWin.width  - cW - 20, rawX));
                    rawY = Math.max(20, Math.min(expandedWin.height - cH - 20, rawY));

                    return { x: rawX, y: rawY, rot: rotDeg };
                }
                placed += cap;
                ring++;
            }
            return { x: 60, y: 60, rot: 0 }; // unreachable fallback
        }

        // Click-away backdrop (dismiss the fan)
        Rectangle {
            anchors.fill: parent; color: "#28040914"; opacity: expandedWin.animProgress
            MouseArea { anchors.fill: parent; onClicked: root.runAction(["toggle-ui"]) }
        }

        // ── Miniature arc cards ────────────────────────────────────────────────
        Repeater {
            model: root.stashed
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index

                readonly property var layout:  expandedWin.arcLayout(index, root.stashed.length)
                readonly property var appInfo: root.resolveAppInfo(modelData["class"])

                // Burst: cards fly from the bottom-right corner to their arc position.
                // Only x, y, rotation and opacity are animated — NEVER width/height.
                readonly property real cornerX: expandedWin.width  - expandedWin.cardW / 2
                readonly property real cornerY: expandedWin.height - expandedWin.cardH / 2

                // ══ DIMENSIONS: fixed — never touched ══════════════════════════
                width:  expandedWin.cardW   // 86 px — constant
                height: expandedWin.cardH   // 68 px — constant
                // scale is intentionally absent (defaults to 1.0 — never scaled)

                x:        cornerX + (layout.x - cornerX) * expandedWin.animProgress
                y:        cornerY + (layout.y - cornerY) * expandedWin.animProgress
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
                    onClicked: root.runAction(["focus", modelData.address, "--swap"])
                }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 3

                    // Icon + name on the same row
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
                        // Close button
                        Rectangle {
                            width: 15; height: 15; radius: 4
                            color: delMa.containsMouse ? "#55fb7185" : "#22fb7185"
                            Text { anchors.centerIn: parent; text: "✕"; color: "#fda4af"; font.pixelSize: 8 }
                            MouseArea {
                                id: delMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runAction(["close", modelData.address])
                            }
                        }
                    }

                    // Window title (truncated to remaining height)
                    Text {
                        text: modelData.title || ""
                        color: "#94a3b8"; font.pixelSize: 8
                        elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                        Layout.fillWidth: true; Layout.fillHeight: true
                    }
                }
            }
        }

        // "Tout ouvrir" pill — small floating button near the corner
        Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 20; bottomMargin: 24 }
            width: 94; height: 26; radius: 13
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
                onClicked: root.runAction(["restore-all"])
            }
        }
    }
}
