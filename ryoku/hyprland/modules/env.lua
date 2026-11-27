hl.env("XCURSOR_THEME",     "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE",      "24")
hl.env("HYPRCURSOR_THEME",  "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE",   "24")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE",    "wayland")
hl.env("NO_AT_BRIDGE",        "1")

-- Master session key: gates every Ryoku systemd user unit so nothing can start
-- outside an active Ryoku session (e.g. under KDE/GNOME/XFCE).
local session_key = os.getenv("RYOKU_SESSION_KEY")
if not session_key or session_key == "" then
    local f = io.open("/proc/sys/kernel/random/uuid", "r")
    if f then
        session_key = (f:read("*l") or ""):gsub("%s+", "")
        f:close()
    end
    if not session_key or session_key == "" then
        session_key = "ryoku-" .. tostring(os.time())
    end
end
hl.env("RYOKU_SESSION_KEY", session_key)
hl.env("RYOKU_ACTIVE",      "1")

-- VA-API/GLX hints are nvidia-only, and forcing them when an iGPU drives the
-- panel freezes video decode on hybrid laptops (#55); set them only when nvidia
-- actually drives the internal panel, else let mesa auto-detect. Detect by the
-- vendor of the card whose eDP/LVDS/DSI connector is connected -- stable across
-- reboots and MUX/offload/dedicated modes, unlike backlight-interface names.
local function panel_vendor()
    local p = io.popen([[
        for c in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-* /sys/class/drm/card*-DSI-*; do
            [ -e "$c/status" ] && [ "$(cat "$c/status")" = connected ] || continue
            card=${c%-*}; card=${card%-*}
            cat "$card/device/vendor" 2>/dev/null && break
        done
    ]])
    if not p then return nil end
    local out = p:read("*a") or ""
    p:close()
    return out:match("0x%x+")
end

local nvidia = io.open("/proc/driver/nvidia/version")
if nvidia then nvidia:close() end
local panel = panel_vendor()
-- Intel (0x8086) or AMD (0x1002) on the panel is the hybrid case: the iGPU decodes.
local igpu_panel = panel == "0x8086" or panel == "0x1002"

if nvidia and not igpu_panel then
    hl.env("LIBVA_DRIVER_NAME",         "nvidia")
    hl.env("NVD_BACKEND",               "direct") -- nvidia VA-API direct backend, Turing+
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("__GL_GSYNC_ALLOWED",        "0")
    hl.env("__GL_VRR_ALLOWED",          "0")
elseif not nvidia then
    -- dodges Hyprland's post-capture black screen (#11315). Not on nvidia: it
    -- can't import the modifier-less buffer and SIGABRTs the first multi-GPU commit.
    hl.env("AQ_NO_MODIFIERS", "1")
end

hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Prefer native Wayland (fall back to X11) so GTK/Qt get the compositor's
-- fractional scale, instead of XWayland force_zero_scaling drawing them at 1:1
-- in a corner of a logical-sized window at non-integer scales.
hl.env("GDK_BACKEND",                    "wayland,x11,*")
hl.env("QT_QPA_PLATFORM",                "wayland;xcb")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR",    "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

-- GTK4 apps (nautilus, the file manager) hang at startup on wlroots compositors:
-- the default renderer opens its display through org.gnome.Mutter.ServiceChannel,
-- which only exists under GNOME's Mutter, so on Hyprland it never connects. The
-- GL renderer takes a direct Wayland path instead, so pin it: a GTK stack upgrade
-- must never leave the file manager unable to open.
hl.env("GSK_RENDERER", "gl")

-- qt6ct only, never kde: Ryoku is self-contained and never reads/writes ~/.config/kdeglobals.
-- If qt6ct is absent, leave QT_QPA_PLATFORMTHEME unset so Qt uses its built-in Fusion style.
local qt6ct_bin = io.open("/usr/bin/qt6ct", "r")
if qt6ct_bin then
    qt6ct_bin:close()
    hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
end

-- Session-scoped GTK theme (never written globally to dconf/gsettings)
hl.env("GTK_THEME", "adw-gtk3-dark")

-- Shared QML modules (Ryoku.Ui, Ryoku.PluginKit, Ryoku.Blobs) live in
-- /usr/lib/qt6/qml on an installed system, which Qt finds on its own. A
-- deploy.sh checkout puts them under ~/.local instead, and only the daemon
-- injects that path (ipc/daemon.go setupQmlImportPath) -- so the configs it
-- supervises resolve the imports while `qs -c hub` from a keybind does not.
-- Set it for the session so both paths behave the same.
hl.env("QML_IMPORT_PATH",  os.getenv("HOME") .. "/.local/lib/qt6/qml")

-- The shell daemon registers as the PolicyKit1 authentication agent, so an
-- administrator password is asked for on a Ryoku island instead of the stock
-- agent's grey dialog. The daemon reads it at startup; without it the daemon
-- leaves the slot alone.
hl.env("RYOKU_POLKIT_AGENT", "1")
hl.env("QML2_IMPORT_PATH", os.getenv("HOME") .. "/.local/lib/qt6/qml")

-- deploy.sh builds the ryoku-* binaries into ~/.local/bin; put it first so the
-- session runs them, not the package's /usr/bin copies. Inert on a package
-- install, where ~/.local/bin holds no ryoku binaries.
local local_bin = (os.getenv("HOME") or "") .. "/.local/bin"
local entries = { local_bin }
local inherited = os.getenv("PATH") or ""
-- An empty PATH has no components; splitting it would add "" (the cwd).
if inherited ~= "" then
    for entry in (inherited .. ":"):gmatch("(.-):") do
        if entry ~= local_bin then
            entries[#entries + 1] = entry
        end
    end
end
hl.env("PATH", table.concat(entries, ":"))


hl.env("EDITOR", "nvim")
hl.env("VISUAL", "nvim")

-- ── Hyprland startup warnings ─────────────────────────────────────────────
-- Suppress the "not using start-hyprland" warning that Hyprland emits when
-- argv[0] is not literally "start-hyprland" (which is the case when SDDM
-- launches the session via the .desktop Exec path). The warning is cosmetic:
-- the compositor runs correctly through /usr/bin/start-hyprland; we just
-- don't want it cluttering the boot splash.
hl.env("HYPRLAND_NO_SD_NOTIFY", "1")

-- ── XWayland authority ────────────────────────────────────────────────────
-- Hyprland starts Xwayland but does not export XAUTHORITY into the session
-- environment. Without it, apps that escalate privileges (virt-manager,
-- gparted, root-owned GUIs) cannot open their window on the X display and
-- crash with "Authorization required, but no authorization protocol specified".
-- ~/.Xauthority is the canonical location; xauth creates it automatically
-- when the first XWayland client connects.
local home = os.getenv("HOME") or ""
hl.env("XAUTHORITY", home .. "/.Xauthority")