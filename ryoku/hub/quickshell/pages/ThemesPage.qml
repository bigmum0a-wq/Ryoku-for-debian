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
    property var kdeGlobalThemes: []
    property var kdeColorSchemes: []
    property string activeKdeGlobal: ""
    property string activeKdeColor: ""
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

    Process {
        id: kdeThemesProc
        command: [
            "python3", "-c",
            "import os,json,subprocess\n" +
            "cur=''\n" +
            "try:\n" +
            "  cur=subprocess.check_output(['kreadconfig6','--file','kdeglobals','--group','KDE','--key','LookAndFeelPackage'],text=True).strip()\n" +
            "except Exception: pass\n" +
            "out=[]; seen=set()\n" +
            "for base in [os.path.expanduser('~/.local/share/plasma/look-and-feel'), '/usr/share/plasma/look-and-feel']:\n" +
            "  if not os.path.isdir(base): continue\n" +
            "  for entry in sorted(os.listdir(base)):\n" +
            "    if entry in seen: continue\n" +
            "    d=os.path.join(base,entry); mp=os.path.join(d,'metadata.json')\n" +
            "    if not os.path.isfile(mp): continue\n" +
            "    try:\n" +
            "      m=json.load(open(mp))\n" +
            "      if m.get('KPackageStructure')!='Plasma/LookAndFeel': continue\n" +
            "      name=m.get('KPlugin',{}).get('Name') or entry\n" +
            "    except Exception: continue\n" +
            "    prev=''\n" +
            "    for p in ['contents/previews/preview.png','contents/previews/fullscreenpreview.jpg']:\n" +
            "      fp=os.path.join(d,p)\n" +
            "      if os.path.isfile(fp): prev='file://'+fp; break\n" +
            "    seen.add(entry); out.append({'id':entry,'name':name,'preview':prev})\n" +
            "print(json.dumps({'active':cur,'items':out}))"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var res = JSON.parse(this.text);
                    if (res.active) pg.activeKdeGlobal = res.active;
                    if (Array.isArray(res.items)) pg.kdeGlobalThemes = res.items;
                } catch (e) {}
            }
        }
    }

    Process {
        id: kdeColorsProc
        command: [
            "python3", "-c",
            "import os,json,re,subprocess\n" +
            "def to_hex(v,fb):\n" +
            "  v=(v or '').strip()\n" +
            "  if v.startswith('#') and len(v)>=7: return v[:7]\n" +
            "  p=v.split(',')\n" +
            "  if len(p)>=3:\n" +
            "    try: return '#%02x%02x%02x'%(int(p[0]),int(p[1]),int(p[2]))\n" +
            "    except Exception: pass\n" +
            "  return fb\n" +
            "cur=''\n" +
            "try:\n" +
            "  cur=subprocess.check_output(['kreadconfig6','--file','kdeglobals','--group','General','--key','ColorScheme'],text=True).strip()\n" +
            "except Exception: pass\n" +
            "out=[]; seen=set()\n" +
            "for base in [os.path.expanduser('~/.local/share/color-schemes'), '/usr/share/color-schemes']:\n" +
            "  if not os.path.isdir(base): continue\n" +
            "  for fn in sorted(os.listdir(base)):\n" +
            "    if not fn.endswith('.colors'): continue\n" +
            "    cid=fn[:-7]\n" +
            "    if cid in seen: continue\n" +
            "    seen.add(cid)\n" +
            "    secs={}; sec=''\n" +
            "    try:\n" +
            "      for line in open(os.path.join(base,fn),encoding='utf-8',errors='ignore'):\n" +
            "        s=line.strip()\n" +
            "        if not s or s.startswith('#'): continue\n" +
            "        m=re.match(r'^\\[(.+)\\]$',s)\n" +
            "        if m: sec=m.group(1); secs.setdefault(sec,{}); continue\n" +
            "        if '=' in s and sec:\n" +
            "          k,_,v=s.partition('='); secs[sec][k.strip()]=v.strip()\n" +
            "    except Exception: continue\n" +
            "    name=secs.get('General',{}).get('Name') or cid\n" +
            "    win_bg=to_hex(secs.get('Colors:Window',{}).get('BackgroundNormal'),'#232629')\n" +
            "    win_fg=to_hex(secs.get('Colors:Window',{}).get('ForegroundNormal'),'#eff0f1')\n" +
            "    view_bg=to_hex(secs.get('Colors:View',{}).get('BackgroundNormal'),win_bg)\n" +
            "    sel_bg=to_hex(secs.get('Colors:Selection',{}).get('BackgroundNormal'),'#3daee9')\n" +
            "    out.append({'id':cid,'name':name,'winBg':win_bg,'winFg':win_fg,'viewBg':view_bg,'accent':sel_bg})\n" +
            "print(json.dumps({'active':cur,'items':out}))"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var res = JSON.parse(this.text);
                    if (res.active) pg.activeKdeColor = res.active;
                    if (Array.isArray(res.items)) pg.kdeColorSchemes = res.items;
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

            SettingCard {
                width: parent.width
                title: I18n.tr("KDE & QT BRIDGE")

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Sync Ryoku palette to KDE/Qt")
                    desc: I18n.tr("Generate RyokuDynamic color scheme + Kvantum style and apply org.ryoku.desktop.")
                    controlWidth: 165
                    Rectangle {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 155; height: 30; radius: Tokens.rSm
                        color: Tokens.surface2
                        border.width: syncKdeHover.hovered ? 2 : 1
                        border.color: syncKdeHover.hovered ? Tokens.accent : Tokens.lineSoft
                        HoverHandler { id: syncKdeHover }
                        TapHandler {
                            onTapped: {
                                Quickshell.execDetached(["sh", "-c", "\"$HOME/.local/bin/ryoku-apply-kde-theme\""]);
                                pg.activeKdeGlobal = "org.ryoku.desktop";
                                pg.activeKdeColor = "RyokuDynamic";
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: I18n.tr("Sync Ryoku → KDE")
                            color: Tokens.ink
                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; font.weight: Font.Medium
                        }
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("KDE Global Theme (Look & Feel)")
                    desc: pg.activeKdeGlobal.length > 0 ? I18n.tr("Active: ") + pg.activeKdeGlobal : I18n.tr("Apply a KDE Look & Feel package.")
                    controlWidth: 0
                }

                Flow {
                    width: parent.width - Tokens.s4 * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.s3
                    topPadding: Tokens.s2
                    bottomPadding: Tokens.s3

                    Repeater {
                        model: pg.kdeGlobalThemes
                        delegate: Rectangle {
                            id: lafCard
                            required property var modelData
                            readonly property bool active: pg.activeKdeGlobal === modelData.id
                            width: 164; height: 118; radius: Tokens.rMd
                            color: Tokens.surface2
                            border.width: active ? 2 : 1
                            border.color: active ? Tokens.accent : (lafHover.hovered ? Tokens.line : Tokens.lineSoft)
                            clip: true

                            HoverHandler { id: lafHover }
                            TapHandler {
                                onTapped: {
                                    pg.activeKdeGlobal = lafCard.modelData.id;
                                    Quickshell.execDetached(["lookandfeeltool", "--apply", lafCard.modelData.id]);
                                }
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: Tokens.s2
                                spacing: Tokens.s1

                                Rectangle {
                                    width: parent.width
                                    height: 76
                                    radius: Tokens.rSm
                                    color: Tokens.surface1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: lafCard.modelData.preview || ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: (lafCard.modelData.preview || "").length > 0
                                        asynchronous: true
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        visible: (lafCard.modelData.preview || "").length === 0
                                        Rectangle { width: 16; height: 16; radius: 8; color: Tokens.accent }
                                        Rectangle { width: 16; height: 16; radius: 8; color: Tokens.inkMuted }
                                        Rectangle { width: 16; height: 16; radius: 8; color: Tokens.surface2; border.width: 1; border.color: Tokens.line }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: Tokens.s1
                                    Text {
                                        width: parent.width - (lafCard.active ? 16 : 0)
                                        text: lafCard.modelData.name || lafCard.modelData.id
                                        color: Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fSmall
                                        font.weight: lafCard.active ? Font.DemiBold : Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        visible: lafCard.active
                                        width: 12; height: 12; radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Tokens.accent
                                    }
                                }
                            }
                        }
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("KDE Color Scheme")
                    desc: pg.activeKdeColor.length > 0 ? I18n.tr("Active: ") + pg.activeKdeColor : I18n.tr("Apply a KDE .colors scheme to Qt/KDE apps.")
                    controlWidth: 0
                }

                Flow {
                    width: parent.width - Tokens.s4 * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.s3
                    topPadding: Tokens.s2
                    bottomPadding: Tokens.s4

                    Repeater {
                        model: pg.kdeColorSchemes
                        delegate: Rectangle {
                            id: csCard
                            required property var modelData
                            readonly property bool active: pg.activeKdeColor === modelData.id
                            width: 164; height: 78; radius: Tokens.rMd
                            color: modelData.winBg || Tokens.surface2
                            border.width: active ? 2 : 1
                            border.color: active ? Tokens.accent : (csHover.hovered ? Tokens.line : Tokens.lineSoft)

                            HoverHandler { id: csHover }
                            TapHandler {
                                onTapped: {
                                    pg.activeKdeColor = csCard.modelData.id;
                                    Quickshell.execDetached(["plasma-apply-colorscheme", csCard.modelData.id]);
                                }
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: Tokens.s2
                                spacing: Tokens.s2

                                Row {
                                    width: parent.width
                                    spacing: Tokens.s1
                                    Text {
                                        width: parent.width - (csCard.active ? 16 : 0)
                                        text: csCard.modelData.name || csCard.modelData.id
                                        color: csCard.modelData.winFg || Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fSmall
                                        font.weight: csCard.active ? Font.DemiBold : Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        visible: csCard.active
                                        width: 12; height: 12; radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: csCard.modelData.accent || Tokens.accent
                                    }
                                }

                                Row {
                                    spacing: 6
                                    Rectangle { width: 22; height: 14; radius: 3; color: csCard.modelData.viewBg || "#1e1e1e"; border.width: 1; border.color: "#44ffffff" }
                                    Rectangle { width: 22; height: 14; radius: 3; color: csCard.modelData.accent || "#3daee9"; border.width: 1; border.color: "#44ffffff" }
                                    Rectangle { width: 22; height: 14; radius: 3; color: csCard.modelData.winFg || "#ffffff"; border.width: 1; border.color: "#44888888" }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
