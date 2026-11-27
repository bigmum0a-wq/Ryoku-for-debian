# Ryoku for Debian — Reinstallation & Dependencies Guide

This guide explains how to cleanly install or reinstall **Ryoku Desktop** on a fresh **Debian 13 (Trixie)** or Debian-based (`amd64`) system.

---

## Method 1 — Full Online Installation (via APT Repository)

### Quick option (automated script)
```bash
git clone https://github.com/bigmum0a-wq/Ryoku-for-debian.git
cd Ryoku-for-debian
bash debian-port/install-deps.sh
```

### Manual option (3 commands without cloning the repository)
```bash
curl -fsSL https://bigmum0a-wq.github.io/Ryoku-for-debian/ryoku-debian-release.pub.asc \
  | sudo gpg --yes --dearmor -o /usr/share/keyrings/ryoku-archive-keyring.gpg
sudo chmod 644 /usr/share/keyrings/ryoku-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/ryoku-archive-keyring.gpg] https://bigmum0a-wq.github.io/Ryoku-for-debian/apt trixie main" \
  | sudo tee /etc/apt/sources.list.d/ryoku.list >/dev/null
sudo chmod 644 /etc/apt/sources.list.d/ryoku.list

sudo apt-get update && sudo apt-get install -y ryoku-desktop
ryoku materialize
```

> Once `ryoku-archive-keyring` is installed, `/etc/apt/sources.list.d/ryoku.sources` is configured automatically; you can remove `/etc/apt/sources.list.d/ryoku.list` to avoid duplicate entries during `apt update`.

---

## Method 2 — Offline Reinstallation (USB Drive / `.tar.gz` Archive)

1. Download `ryoku-deb-repo-<version>.tar.gz` from [GitHub Releases](https://github.com/bigmum0a-wq/Ryoku-for-debian/releases).
2. Install system dependencies (if you have internet access for Debian APT only, or from a local mirror):
   ```bash
   bash debian-port/install-deps.sh --deps-only
   ```
3. Extract and install the 7 `.deb` packages:
   ```bash
   tar -xzf ryoku-deb-repo-*.tar.gz
   sudo dpkg -i out/pool/main/r/ryoku/ryoku-archive-keyring_*.deb
   sudo apt-get update || true
   sudo apt-get install -y out/pool/main/r/ryoku/*.deb
   ryoku materialize
   ```

---

## Method 3 — Build `.deb` Packages from Source

1. Install build dependencies:
   ```bash
   bash debian-port/install-deps.sh --build
   ```
   *(Make sure **Go 1.26+** is installed in your `PATH` to compile `ryoku-shell` and `ryoku-hub`.)*
2. Build the full APT repository:
   ```bash
   umask 0022
   bash debian/packages/repo/build-deb-repo.sh
   ```
   Generated packages will be placed in `debian/packages/repo/out/`.

---

## System Dependencies List

- **Compositor & Shell:** `hyprland`, `quickshell`, `qml6-module-qtquick3d`
- **Portals & D-Bus Session:** `xdg-desktop-portal`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-hyprland`, `dbus-user-session`, `gnome-keyring`, `libsecret-1-0`
- **Audio, Video & Capture:** `pipewire`, `wireplumber`, `playerctl`, `cava`, `ffmpeg`, `mpv`, `grim`, `slurp`, `wl-clipboard`, `tesseract-ocr`
- **Hyprland Tools & Theming:** `hyprpicker`, `hyprsunset`, `hypridle`, `qt6ct`, `papirus-icon-theme`
- **Ryoku Script Utilities:** `python3`, `jq`, `socat`, `x11-xserver-utils` (`xhost`), `libglib2.0-bin` (`gsettings`)

---

## Post-Installation

1. Log out and select the **Hyprland** session on your display manager (SDDM/GDM/LightDM).
2. Useful shortcuts:
   - **`Super + ,`**: Open settings (**Ryoku Hub**)
   - **`Super + H`**: Stash the active window into the corner stack (`winstash`)
   - **`Super + Shift + H`** (or click the stack): Expand stashed windows in concentric arcs
   - **Long press & drag** on the stack: Move the stack anywhere on screen
