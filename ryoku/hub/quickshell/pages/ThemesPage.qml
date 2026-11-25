pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "../Singletons"
import "../schema/ThemeCatalog.js" as ThemeCatalog
import ".."

Item {
    id: pg
    property var hub

    readonly property string pTitle: I18n.tr("Themes & Colors")
    readonly property string pEyebrow: I18n.tr("LOOK")
    readonly property string pBlurb: I18n.tr("Switch color schemes, dynamic wallpaper palette mode, and window surface styling.")

    property var catalogSchemes: ThemeCatalog.schemes
    readonly property string activeTheme: {
        Settings.revision;
        var t = Settings.get("theme.theme");
        return (typeof t === "string" && t.length > 0) ? t : "Wallpaper";
    }
    readonly property string matugenMode: {
        Settings.revision;
        var m = Settings.get("theme.matugen.mode");
        return (m === "light") ? "light" : "dark";
    }
    readonly property real windowOpacity: {
        Settings.revision;
        var v = Settings.get("theme.attributes.window_opacity");
        return (typeof v === "number" && v >= 0.3 && v <= 1.0) ? v : 1.0;
    }
    readonly property int borderWidth: {
        Settings.revision;
        var v = Settings.get("theme.attributes.sizing.border_width");
        return (typeof v === "number" && v >= 0) ? Math.round(v) : 2;
    }
    readonly property int windowRadius: {
        Settings.revision;
        var v = Settings.get("theme.attributes.sizing.radius_window");
        return (typeof v === "number" && v >= 0) ? Math.round(v) : 8;
    }
    readonly property int widgetRadius: {
        Settings.revision;
        var v = Settings.get("theme.attributes.sizing.radius_widget");
        return (typeof v === "number" && v >= 0) ? Math.round(v) : 8;
    }

    function resetDefaults() {
        Settings.patch("theme.theme", "Wallpaper");
        Settings.patch("theme.matugen.mode", "dark");
        Settings.patch("theme.attributes.window_opacity", 1.0);
        Settings.patch("theme.attributes.sizing.border_width", 2);
        Settings.patch("theme.attributes.sizing.radius_window", 8);
        Settings.patch("theme.attributes.sizing.radius_widget", 8);
    }

    Process {
        id: themeCatalogProc
        command: ["ryoku-shell", "theme", "catalog"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(this.text);
                    if (Array.isArray(parsed) && parsed.length > 0)
                        pg.catalogSchemes = parsed;
                } catch (e) {}
            }
        }
    }

    SchemaPage {
        id: scaffold
        anchors {
            fill: parent
            leftMargin: Tokens.s6
            rightMargin: Tokens.s6
            topMargin: Tokens.s5
        }
        schema: []
        draft: null
        defaults: ({})
        title: pg.pTitle
        eyebrow: pg.pEyebrow
        blurb: pg.pBlurb

        Column {
            id: col
            width: parent.width
            spacing: Tokens.s5

            SettingCard {
                width: parent.width
                title: I18n.tr("COLOR SCHEME")

                Text {
                    width: parent.width
                    leftPadding: Tokens.s4; rightPadding: Tokens.s4
                    topPadding: Tokens.s3; bottomPadding: Tokens.s2
                    text: I18n.tr("Pick a built-in palette, follow your current wallpaper dynamically, or use installed RyoStore schemes. Changes apply live.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    wrapMode: Text.WordWrap
                }

                Flow {
                    width: parent.width - Tokens.s4 * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.s3
                    bottomPadding: Tokens.s4

                    Repeater {
                        model: pg.catalogSchemes

                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool selected: pg.activeTheme === modelData.id
                            readonly property bool isDyn: modelData.dynamic === true
                            readonly property var sw: Array.isArray(modelData.sw) ? modelData.sw : []

                            width: 164
                            height: 92
                            radius: Tokens.rMd
                            color: (!isDyn && sw.length > 0) ? sw[0] : Tokens.surface2
                            border.width: selected ? 2 : 1
                            border.color: selected ? Tokens.accent : (cardHover.hovered ? Tokens.line : Tokens.lineSoft)

                            HoverHandler { id: cardHover }
                            TapHandler {
                                onTapped: Settings.patch("theme.theme", card.modelData.id)
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: Tokens.s3
                                spacing: Tokens.s2

                                Row {
                                    width: parent.width
                                    spacing: Tokens.s2

                                    Text {
                                        width: parent.width - (checkBadge.visible ? checkBadge.width + Tokens.s2 : 0)
                                        text: card.modelData.label || card.modelData.id
                                        color: (!card.isDyn && card.sw.length > 1) ? card.sw[1] : Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fSmall
                                        font.weight: card.selected ? Font.DemiBold : Font.Medium
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        id: checkBadge
                                        visible: card.selected
                                        width: 18; height: 18; radius: 9
                                        color: Tokens.accent
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: Tokens.inkOnBone
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                Row {
                                    visible: !card.isDyn && card.sw.length >= 6
                                    spacing: 5
                                    Repeater {
                                        model: Math.min(6, Math.max(0, card.sw.length - 1))
                                        delegate: Rectangle {
                                            required property int index
                                            width: 18; height: 18; radius: 4
                                            color: card.sw[index + 1]
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.14)
                                        }
                                    }
                                }

                                Text {
                                    visible: card.isDyn
                                    text: card.modelData.id === "Wallpaper"
                                        ? I18n.tr("Dynamic (Matugen)")
                                        : I18n.tr("Built-in default")
                                    color: Tokens.inkDim
                                    font.family: Tokens.ui
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("WALLPAPER & MODE")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Dynamic palette mode")
                    desc: I18n.tr("Choose dark or light tone when following your wallpaper.")
                    controlWidth: 160
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        Repeater {
                            model: [
                                { id: "dark", label: I18n.tr("Dark") },
                                { id: "light", label: I18n.tr("Light") }
                            ]
                            delegate: Rectangle {
                                id: modeBtn
                                required property var modelData
                                readonly property bool active: pg.matugenMode === modelData.id
                                width: 72; height: 28; radius: Tokens.rSm
                                color: active ? Tokens.bone : (mHover.hovered ? Tokens.tint10 : Tokens.surface2)
                                border.width: 1
                                border.color: active ? Tokens.bone : Tokens.lineSoft
                                HoverHandler { id: mHover }
                                TapHandler { onTapped: Settings.patch("theme.matugen.mode", modeBtn.modelData.id) }
                                Text {
                                    anchors.centerIn: parent
                                    text: modeBtn.modelData.label
                                    color: modeBtn.active ? Tokens.inkOnBone : Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                }
                            }
                        }
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Wallpaper picker")
                    desc: I18n.tr("Browse wallpapers, color filters, and visual effects (Super+W).")
                    controlWidth: 230
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        Rectangle {
                            width: 112; height: 28; radius: Tokens.rSm
                            color: wpHover.hovered ? Tokens.tint10 : Tokens.surface2
                            border.width: 1; border.color: Tokens.lineSoft
                            HoverHandler { id: wpHover }
                            TapHandler { onTapped: Quickshell.execDetached(["ryogami", "wallpaper", "ui"]) }
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Open Picker")
                                color: Tokens.ink
                                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                            }
                        }
                        Rectangle {
                            width: 108; height: 28; radius: Tokens.rSm
                            color: rndHover.hovered ? Tokens.tint10 : Tokens.surface2
                            border.width: 1; border.color: Tokens.lineSoft
                            HoverHandler { id: rndHover }
                            TapHandler { onTapped: Quickshell.execDetached(["ryogami", "wallpaper", "random"]) }
                            Text {
                                anchors.centerIn: parent
                                text: I18n.tr("Randomize")
                                color: Tokens.ink
                                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                            }
                        }
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("WINDOWS & SURFACES")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Window opacity")
                    value: Math.round(pg.windowOpacity * 100) + "%"
                    controlWidth: 220
                    Slid {
                        anchors.fill: parent
                        from: 0.30; to: 1.0
                        value: pg.windowOpacity
                        onModified: (v) => Settings.patch("theme.attributes.window_opacity", Math.round(v * 20) / 20)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Border width")
                    value: pg.borderWidth + " px"
                    controlWidth: 220
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 6
                        value: pg.borderWidth
                        onModified: (v) => Settings.patch("theme.attributes.sizing.border_width", Math.round(v))
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Window corner radius")
                    value: pg.windowRadius + " px"
                    controlWidth: 220
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 24
                        value: pg.windowRadius
                        onModified: (v) => Settings.patch("theme.attributes.sizing.radius_window", Math.round(v))
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Widget corner radius")
                    value: pg.widgetRadius + " px"
                    controlWidth: 220
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 24
                        value: pg.widgetRadius
                        onModified: (v) => Settings.patch("theme.attributes.sizing.radius_widget", Math.round(v))
                    }
                }
            }
        }
    }
}
