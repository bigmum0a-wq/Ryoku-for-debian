pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import shell.services

// Fullscreen macOS Launchpad-inspired application launcher.
// Background blur is applied natively by Hyprland via layer_rule on namespace "ryoku-launchpad".
PanelWindow {
    id: pad

    property bool open: false

    function toggle() { open = !open; }
    function close() { open = false; }

    visible: open || animProgress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-launchpad"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property real animProgress: 0
    property string searchQuery: ""
    property int currentPage: 0
    property int appRevision: 0
    property var xdgApps: []

    onOpenChanged: {
        if (open) {
            searchQuery = "";
            currentPage = 0;
            pad.appRevision++;
            if (!xdgScanProc.running)
                xdgScanProc.running = true;
            openAnim.restart();
            Qt.callLater(() => searchInput.forceActiveFocus());
        } else {
            closeAnim.restart();
        }
    }

    Component.onCompleted: {
        if (!xdgScanProc.running)
            xdgScanProc.running = true;
    }

    Connections {
        target: (typeof DesktopEntries !== "undefined" && DesktopEntries.applications) ? DesktopEntries.applications : null
        ignoreUnknownSignals: true
        function onValuesChanged() { pad.appRevision++; }
        function onObjectInsertedPost() { pad.appRevision++; }
        function onObjectRemovedPost() { pad.appRevision++; }
    }

    // Universal Freedesktop XDG .desktop + Icon Theme resolver (active Ryoku theme first, native app icon second)
    Process {
        id: xdgScanProc
        command: [
            "python3", "-c",
            "import os, json, configparser\n" +
            "cfg = os.environ.get('XDG_CONFIG_HOME', os.path.expanduser('~/.config'))\n" +
            "tf = os.path.join(cfg, 'ryoku', 'icon-theme')\n" +
            "active_theme = open(tf).read().strip() if os.path.isfile(tf) else ''\n" +
            "icon_roots = [os.path.expanduser('~/.local/share/icons'), os.path.expanduser('~/.icons'), '/usr/local/share/icons', '/usr/share/icons', '/var/lib/flatpak/exports/share/icons']\n" +
            "def build_idx(themes):\n" +
            "    idx = {}\n" +
            "    exts = ('.svg', '.png', '.xpm')\n" +
            "    for t in themes:\n" +
            "        if not t: continue\n" +
            "        for r in icon_roots:\n" +
            "            td = os.path.join(r, t)\n" +
            "            if not os.path.isdir(td): continue\n" +
            "            for dp, _, fns in os.walk(td):\n" +
            "                if '/cursors/' in dp: continue\n" +
            "                for fn in fns:\n" +
            "                    if not fn.endswith(exts): continue\n" +
            "                    stem = os.path.splitext(fn)[0]\n" +
            "                    if stem not in idx: idx[stem] = os.path.join(dp, fn)\n" +
            "    return idx\n" +
            "theme_idx = build_idx([active_theme]) if active_theme else {}\n" +
            "native_idx = build_idx(['hicolor', 'breeze', 'Papirus'])\n" +
            "pixmaps = {}\n" +
            "if os.path.isdir('/usr/share/pixmaps'):\n" +
            "    for fn in os.listdir('/usr/share/pixmaps'):\n" +
            "        stem = os.path.splitext(fn)[0]\n" +
            "        if stem not in pixmaps: pixmaps[stem] = os.path.join('/usr/share/pixmaps', fn)\n" +
            "def resolve_icon(iv, aid):\n" +
            "    if iv.startswith('/') and os.path.isfile(iv):\n" +
            "        base = os.path.splitext(os.path.basename(iv))[0]\n" +
            "        p = theme_idx.get(base) or iv\n" +
            "        return 'file://' + p\n" +
            "    for c in (iv, iv.lower(), aid, aid.lower()):\n" +
            "        if c and c in theme_idx: return 'file://' + theme_idx[c]\n" +
            "    for c in (iv, iv.lower(), aid, aid.lower()):\n" +
            "        if not c: continue\n" +
            "        if c in native_idx: return 'file://' + native_idx[c]\n" +
            "        if c in pixmaps: return 'file://' + pixmaps[c]\n" +
            "    return ''\n" +
            "dirs = [os.path.expanduser('~/.local/share/applications')]\n" +
            "for d in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':'):\n" +
            "    if d: dirs.append(os.path.join(d, 'applications'))\n" +
            "dirs += ['/var/lib/flatpak/exports/share/applications', '/var/lib/snapd/desktop/applications']\n" +
            "seen, out = set(), []\n" +
            "for root in dirs:\n" +
            "    if not os.path.isdir(root): continue\n" +
            "    for dp, _, fns in os.walk(root):\n" +
            "        for fn in fns:\n" +
            "            if not fn.endswith('.desktop'): continue\n" +
            "            rel = os.path.relpath(os.path.join(dp, fn), root).replace('/', '-')\n" +
            "            if rel in seen: continue\n" +
            "            seen.add(rel)\n" +
            "            cp = configparser.ConfigParser(interpolation=None, strict=False)\n" +
            "            try:\n" +
            "                cp.read(os.path.join(dp, fn), encoding='utf-8')\n" +
            "                if 'Desktop Entry' not in cp: continue\n" +
            "                e = cp['Desktop Entry']\n" +
            "                if e.get('Type', 'Application') != 'Application': continue\n" +
            "                if e.get('NoDisplay', '').lower() == 'true' or e.get('Hidden', '').lower() == 'true': continue\n" +
            "                name = e.get('Name', '').strip()\n" +
            "                exec_cmd = e.get('Exec', '').strip()\n" +
            "                if not name or not exec_cmd: continue\n" +
            "                aid = rel[:-8]\n" +
            "                iv = e.get('Icon', '').strip()\n" +
            "                out.append({'id': aid, 'desktopPath': os.path.join(dp, fn), 'name': name, 'icon': iv, 'resolvedIcon': resolve_icon(iv, aid), 'comment': e.get('Comment', '').strip()})\n" +
            "            except Exception: pass\n" +
            "out.sort(key=lambda x: x['name'].lower())\n" +
            "print(json.dumps(out))\n"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text || "[]");
                    if (Array.isArray(parsed)) pad.xdgApps = parsed;
                } catch (e) {}
            }
        }
    }

    NumberAnimation {
        id: openAnim
        target: pad; property: "animProgress"
        to: 1.0; duration: 220; easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: closeAnim
        target: pad; property: "animProgress"
        to: 0.0; duration: 160; easing.type: Easing.InCubic
    }

    // Use resolved XDG entries (with verified active-theme / native-app icon paths) first
    readonly property var allApps: {
        void pad.appRevision;
        if (pad.xdgApps && pad.xdgApps.length > 0)
            return pad.xdgApps;
        var list = (typeof DesktopEntries !== "undefined" && DesktopEntries.applications && DesktopEntries.applications.values)
            ? DesktopEntries.applications.values : [];
        var out = [];
        for (var i = 0; i < list.length; i++) {
            var app = list[i];
            if (!app || app.noDisplay) continue;
            var name = String(app.name || "").trim();
            if (!name) continue;
            out.push({
                id: String(app.id || ""),
                name: name,
                icon: String(app.icon || ""),
                resolvedIcon: "",
                comment: String(app.comment || ""),
                desktopPath: "",
                entry: app
            });
        }
        out.sort(function(a, b) {
            return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
        });
        return out;
    }

    readonly property var filteredApps: {
        var q = pad.searchQuery.trim().toLowerCase();
        if (!q) return pad.allApps;
        return pad.allApps.filter(function(app) {
            var n = String(app.name || "").toLowerCase();
            var c = String(app.comment || "").toLowerCase();
            var id = String(app.id || "").toLowerCase();
            return n.indexOf(q) !== -1 || c.indexOf(q) !== -1 || id.indexOf(q) !== -1;
        });
    }

    // Responsive grid geometry adapting to screen resolution
    readonly property int cols: width >= 1600 ? 7 : (width >= 1200 ? 6 : 5)
    readonly property int rows: height >= 900 ? 5 : 4
    readonly property int perPage: cols * rows
    readonly property int pageCount: Math.max(1, Math.ceil(filteredApps.length / perPage))

    onFilteredAppsChanged: {
        if (currentPage >= pageCount) currentPage = Math.max(0, pageCount - 1);
    }

    readonly property var pageApps: {
        var start = currentPage * perPage;
        return filteredApps.slice(start, start + perPage);
    }

    function launchApp(app) {
        if (!app) return;
        if (app.entry && typeof app.entry.execute === "function") {
            app.entry.execute();
        } else if (app.desktopPath) {
            Quickshell.execDetached(["sh", "-c", 'gio launch "$1" >/dev/null 2>&1 || gtk-launch "$2" >/dev/null 2>&1 &', "sh", app.desktopPath, app.id]);
        } else if (app.id) {
            Quickshell.execDetached(["gtk-launch", app.id]);
        }
        pad.close();
    }

    function appIcon(app) {
        if (!app) return Quickshell.iconPath("application-x-executable");
        if (app.resolvedIcon && String(app.resolvedIcon).length > 0)
            return String(app.resolvedIcon);
        var iconName = String(app.icon || "").trim();
        if (iconName) {
            if (iconName.startsWith("/")) return "file://" + iconName;
            return Quickshell.iconPath(iconName, "application-x-executable");
        }
        try {
            var d = Dock.iconFor(String(app.id || ""));
            if (d) return d;
        } catch (e) {}
        return Quickshell.iconPath("application-x-executable");
    }

    // Translucent dark veil over the blurred desktop background
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.03, 0.05, 0.10, 0.52 * pad.animProgress)

        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                if (wheel.angleDelta.y < 0 && pad.currentPage < pad.pageCount - 1)
                    pad.currentPage++;
                else if (wheel.angleDelta.y > 0 && pad.currentPage > 0)
                    pad.currentPage--;
            }
            onClicked: pad.close()
        }
    }

    // Main content container animated smoothly from the bottom launcher button
    Item {
        id: contentLayer
        anchors.fill: parent
        opacity: pad.animProgress
        transformOrigin: Item.Bottom
        scale: 0.92 + 0.08 * pad.animProgress

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                pad.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown) {
                if (pad.currentPage < pad.pageCount - 1) pad.currentPage++;
                event.accepted = true;
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp) {
                if (pad.currentPage > 0) pad.currentPage--;
                event.accepted = true;
            }
        }

        // Top search bar (macOS Launchpad style)
        Rectangle {
            id: searchBox
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: Math.max(28, Math.round(parent.height * 0.045)) }
            width: Math.min(340, Math.round(parent.width * 0.34))
            height: 36
            radius: 18
            color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
            border.color: searchInput.activeFocus ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(1, 1, 1, 0.18)

            MouseArea { anchors.fill: parent; onClicked: searchInput.forceActiveFocus() }

            Row {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⌕"
                    color: Qt.rgba(1, 1, 1, 0.65)
                    font.pixelSize: 15
                }

                TextInput {
                    id: searchInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28
                    color: "#ffffff"
                    font.pixelSize: 13
                    clip: true
                    onTextChanged: {
                        pad.searchQuery = text;
                        pad.currentPage = 0;
                    }
                    Keys.onEscapePressed: pad.close()
                    Keys.onReturnPressed: {
                        if (pad.filteredApps.length > 0)
                            pad.launchApp(pad.filteredApps[0]);
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Rechercher une application…"
                        color: Qt.rgba(1, 1, 1, 0.45)
                        font.pixelSize: 13
                        visible: searchInput.text.length === 0
                    }
                }
            }
        }

        // Responsive fullscreen app grid
        Item {
            id: gridFrame
            anchors {
                top: searchBox.bottom
                bottom: pageDots.top
                left: parent.left
                right: parent.right
                topMargin: Math.max(24, Math.round(parent.height * 0.04))
                bottomMargin: 20
                leftMargin: Math.max(48, Math.round(parent.width * 0.08))
                rightMargin: Math.max(48, Math.round(parent.width * 0.08))
            }

            readonly property real cellW: width / pad.cols
            readonly property real cellH: height / pad.rows
            readonly property int iconPx: Math.max(52, Math.min(76, Math.round(Math.min(cellW, cellH) * 0.48)))

            Grid {
                anchors.centerIn: parent
                columns: pad.cols
                rows: pad.rows
                width: pad.cols * gridFrame.cellW
                height: pad.rows * gridFrame.cellH

                Repeater {
                    model: pad.pageApps
                    delegate: Item {
                        id: appTile
                        required property var modelData
                        width: gridFrame.cellW
                        height: gridFrame.cellH

                        Rectangle {
                            anchors { fill: parent; margins: 8 }
                            radius: 16
                            color: tileMa.containsMouse ? Qt.rgba(1, 1, 1, 0.13) : "transparent"
                            scale: tileMa.pressed ? 0.92 : (tileMa.containsMouse ? 1.05 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 12
                                spacing: 8

                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    source: pad.appIcon(appTile.modelData)
                                    width: gridFrame.iconPx
                                    height: gridFrame.iconPx
                                    sourceSize.width: gridFrame.iconPx
                                    sourceSize.height: gridFrame.iconPx
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                Text {
                                    width: parent.width
                                    text: String(appTile.modelData.name || "")
                                    color: "#f8fafc"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                        }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pad.launchApp(appTile.modelData)
                        }
                    }
                }
            }
        }

        // Page indicator dots
        Row {
            id: pageDots
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 28 }
            spacing: 10
            visible: pad.pageCount > 1

            Repeater {
                model: pad.pageCount
                delegate: Rectangle {
                    required property int index
                    width: pad.currentPage === index ? 10 : 8
                    height: width
                    radius: width / 2
                    color: pad.currentPage === index ? "#ffffff" : Qt.rgba(1, 1, 1, 0.35)
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pad.currentPage = index
                    }
                }
            }
        }
    }
}
