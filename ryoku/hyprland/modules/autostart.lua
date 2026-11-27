-- The Hyprland provider's login bootstrap; a second compositor ships its own.
hl.on("hyprland.start", function()
    -- Isolate session: stop conflicting KDE/third-party desktop daemons and back up shared configs
    hl.exec_cmd("command -v ryoku-session-guard >/dev/null 2>&1 && ryoku-session-guard enter-ryoku >/dev/null 2>&1 || true")
    -- Start the GNOME keyring's secrets + pkcs11 agents before anything that
    -- might ask for a stored secret, and propagate env to systemd/D-Bus.
    hl.exec_cmd("systemctl --user start gnome-keyring-daemon.service 2>/dev/null || true")
    hl.exec_cmd("eval $(gnome-keyring-daemon --start --components=secrets,pkcs11 2>/dev/null) && dbus-update-activation-environment --systemd --all >/dev/null 2>&1 || true")
    -- XWayland access control: rootless XWayland uses Server-Interpreted ACLs
    -- (SI:localuser:<user>), not MIT-MAGIC-COOKIEs. Without adding localuser:root,
    -- any GUI app launched with sudo/pkexec (e.g. sudo virt-manager, gparted)
    -- strips WAYLAND_DISPLAY, falls back to DISPLAY, and crashes with
    -- "Authorization required, but no authorization protocol specified".
    hl.exec_cmd("command -v xhost >/dev/null 2>&1 && xhost +si:localuser:root >/dev/null 2>&1 || true")
    hl.exec_cmd("systemctl --user import-environment RYOKU_SESSION_KEY RYOKU_ACTIVE HYPRLAND_INSTANCE_SIGNATURE DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE NO_AT_BRIDGE QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION GSK_RENDERER GDK_BACKEND QT_QPA_PLATFORM QT_AUTO_SCREEN_SCALE_FACTOR ELECTRON_OZONE_PLATFORM_HINT RYOKU_POLKIT_AGENT XCURSOR_THEME XCURSOR_SIZE 2>/dev/null || true")
    hl.exec_cmd("dbus-update-activation-environment --systemd RYOKU_SESSION_KEY RYOKU_ACTIVE HYPRLAND_INSTANCE_SIGNATURE DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE NO_AT_BRIDGE QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION GSK_RENDERER GDK_BACKEND QT_QPA_PLATFORM QT_AUTO_SCREEN_SCALE_FACTOR ELECTRON_OZONE_PLATFORM_HINT RYOKU_POLKIT_AGENT XCURSOR_THEME XCURSOR_SIZE >/dev/null 2>&1 || true")
    hl.exec_cmd("ryoku-wm-hyprland act cursor.set Bibata-Modern-Ice 24")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    -- adw-gtk3-dark, not Adwaita-dark: stock Adwaita GTK3 hardcodes its colours,
    -- so the palette Ryoku generates barely reaches GTK3 apps, while adw-gtk3
    -- derives its rules from the named colours we already emit. The daemon owns
    -- accent-color; do not set it here.
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark")
    -- Folder icons follow the wallpaper accent: ryoku-cmd-folders builds a small
    -- Papirus-Dark overlay under ~/.local/share/icons tinted to the palette and
    -- selects it. Rebuilt on every palette change by the shell's matugen hook.
    hl.exec_cmd("command -v ryoku-cmd-folders >/dev/null 2>&1 && ryoku-cmd-folders")
    -- The shared entrypoint keeps this config init-neutral while preserving
    -- the ordered environment handoff and stale-session restart on every
    -- supported service supervisor.
    hl.exec_cmd("systemctl --user stop xdg-desktop-portal-kde.service 2>/dev/null || true")
    hl.exec_cmd("ryoku-host session start xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service")
    -- Polkit authentication is answered by the shell's own agent (the island
    -- that matches the rest of the desktop), so the stock Qt agent must not
    -- take the session's single agent slot. Stopping it is idempotent and
    -- harmless when it was never started.
    hl.exec_cmd("systemctl --user stop hyprpolkitagent plasma-polkit-agent.service 2>/dev/null || true")
    hl.exec_cmd("command -v ryoku-monitor >/dev/null 2>&1 && ryoku-monitor autoscale")
    -- per-output tiling kept while the display link is off; does nothing when linked
    hl.exec_cmd("command -v ryoku-output-tiling >/dev/null 2>&1 && ryoku-output-tiling restore")
    -- Per-device Bluetooth codec memory. WirePlumber restores a device's PROFILE
    -- across reconnects but not its A2DP codec, so a user who picked one has to
    -- pick it again every single time the buds come back. `watch` reconciles on
    -- every card event and owns a per-user lock, so compositor reloads cannot
    -- create duplicate subscriptions.
    hl.exec_cmd("command -v ryoku-bt-audio >/dev/null 2>&1 && (systemd-run --user --scope --slice=ryoku-session.slice --unit=ryoku-bt-audio-watch ryoku-bt-audio watch >/dev/null 2>&1 || ryoku-bt-audio watch) &")
    -- Keyring default: no app ever prompts for a keyring password out of the box.
    -- `keyring init` records the mode once and seeds a blank passwordless default
    -- keyring for never-ask (idempotent; a no-op once a mode is chosen). Best
    -- effort: an old ryoku without the subcommand just fails silently here.
    hl.exec_cmd("command -v ryoku >/dev/null 2>&1 && ryoku keyring init")
    -- Ensure VS Code (Debian/Microsoft .deb) uses gnome-libsecret under Hyprland
    hl.exec_cmd([[command -v code >/dev/null 2>&1 && python3 -c 'import json,os,re; p=os.path.expanduser("~/.vscode/argv.json"); os.makedirs(os.path.dirname(p),exist_ok=True); raw=open(p).read() if os.path.exists(p) else ""; d=json.loads(re.sub(r"^\s*//.*$","",raw,flags=re.M)) if raw.strip() else {}; (d.get("password-store")!="gnome-libsecret") and (d.__setitem__("password-store","gnome-libsecret"), json.dump(d,open(p,"w"),indent=4))' 2>/dev/null || true]])
    hl.exec_cmd("command -v ryoku-gpu >/dev/null 2>&1 && ryoku-gpu persist")
    -- Power knobs the kernel forgets across a reboot: the battery charge ceiling
    -- and the PCIe link policy are plain sysfs values, so a stored choice has to
    -- be pushed back at login or it silently lapses. A no-op with no
    -- ~/.config/ryoku/power.json, and on a desktop or a box without the knobs.
    hl.exec_cmd("command -v ryoku-power >/dev/null 2>&1 && ryoku-power apply")
    -- Device lighting: push the stored look back at the keyboards and mice the
    -- user put under Ryoku's control (wallpaper picker > Settings > Lighting). A no-op, and
    -- no OpenRGB at all, until lighting is on with a device adopted.
    hl.exec_cmd("command -v ryoku-hub >/dev/null 2>&1 && ryoku-hub lighting apply")
    hl.exec_cmd("command -v ryoku-mic >/dev/null 2>&1 && ryoku-mic")
    -- Night light: hyprsunset is a plain process a reboot drops, so restore the
    -- warm screen when the user left it on. A no-op when it was off or absent.
    hl.exec_cmd("command -v ryoku-cmd-nightlight >/dev/null 2>&1 && ryoku-cmd-nightlight restore")
    -- Booted into a btrfs snapshot from the Limine menu: offer the one-click
    -- restore. limine-snapper-sync ships this as an XDG autostart entry, which
    -- Hyprland never runs (no autostart manager), so start it here; on a normal
    -- boot it detects no snapshot and exits silently.
    hl.exec_cmd("command -v limine-snapper-restore >/dev/null 2>&1 && limine-snapper-restore --notify")
    -- AI UI translation: seed ~/.config/ryoku/i18n-llm.json (empty key) so the
    -- file exists for the user to paste an API key into; idempotent, a no-op if
    -- present. The Hub's Language > "Generate with AI" then reads it.
    hl.exec_cmd("command -v ryoku-i18n >/dev/null 2>&1 && ryoku-i18n ensure >/dev/null 2>&1")
    -- Welcome tour and first-boot keyboard hint: the tour once per tour
    -- version, the hint exactly once ever. The behaviour lives in
    -- ryoku-session-intro so every compositor's autostart calls the same
    -- script. Bump the tour version in the helper when the tour changes
    -- materially (beta 18 = 18).
    hl.exec_cmd("command -v ryoku-session-intro >/dev/null 2>&1 && ryoku-session-intro welcome")
    hl.exec_cmd("command -v ryoku-session-intro >/dev/null 2>&1 && ryoku-session-intro keys-hint")
    -- Hide redundant GTK CSD close/max/min buttons (replaced by working Hyprland corner controls)
    hl.exec_cmd("command -v gsettings >/dev/null 2>&1 && gsettings set org.gnome.desktop.wm.preferences button-layout ':' >/dev/null 2>&1 &")
    -- macOS-style window stash overlay & eco livewall CPU guard (scoped inside ryoku-session.slice)
    hl.exec_cmd("(systemd-run --user --scope --slice=ryoku-session.slice --unit=ryoku-winstash-ui flock -n /tmp/ryoku-winstash-ui.lock quickshell -p \"$HOME/.config/quickshell/winstash/shell.qml\" || flock -n /tmp/ryoku-winstash-ui.lock quickshell -p \"$HOME/.config/quickshell/winstash/shell.qml\") >/dev/null 2>&1 &")
    hl.exec_cmd("(systemd-run --user --scope --slice=ryoku-session.slice --unit=ryoku-livewall-eco flock -n /tmp/ryoku-livewall-eco.lock ryoku-livewall-eco || flock -n /tmp/ryoku-livewall-eco.lock ryoku-livewall-eco) >/dev/null 2>&1 &")
    hl.exec_cmd("command -v ryoku-dock-sync >/dev/null 2>&1 && ryoku-dock-sync >/dev/null 2>&1 &")
end)
