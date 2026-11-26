#!/usr/bin/env bash
# install-deps.sh — Portable dependency & Ryoku Desktop installer for Debian 13+ (Trixie)
# and compatible Debian-based distributions.
#
# Usage:
#   bash debian-port/install-deps.sh             # Install deps + add APT repo + install ryoku-desktop
#   bash debian-port/install-deps.sh --deps-only # Install runtime dependencies only (e.g. before offline .deb install)
#   bash debian-port/install-deps.sh --build     # Install build dependencies to compile .deb packages from source
set -euo pipefail

MODE="full"
for arg in "$@"; do
  case "$arg" in
    --deps-only) MODE="deps" ;;
    --build)     MODE="build" ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

RUNTIME_DEPS=(
  hyprland
  quickshell
  qml6-module-qtquick3d
  xdg-desktop-portal
  xdg-desktop-portal-gtk
  xdg-desktop-portal-hyprland
  wireplumber
  pipewire
  grim
  slurp
  wl-clipboard
  tesseract-ocr
  playerctl
  cava
  hyprpicker
  hyprsunset
  hypridle
  ffmpeg
  mpv
  jq
  socat
  python3
  gnome-keyring
  libsecret-1-0
  x11-xserver-utils
  libglib2.0-bin
  dbus-user-session
  qt6ct
  papirus-icon-theme
  curl
  gnupg
)

BUILD_DEPS=(
  dpkg-dev
  apt-utils
  gnupg
  pkg-config
  wayland-protocols
  libwayland-dev
  libavformat-dev
  libavcodec-dev
  libavutil-dev
  libswscale-dev
  git
  ca-certificates
)

echo ":: Updating APT package index..."
sudo apt-get update

if [ "$MODE" = "build" ]; then
  echo ":: Installing build dependencies..."
  sudo apt-get install -y "${BUILD_DEPS[@]}"
  echo ":: Checking Go toolchain (Go 1.26+ required for ryoku-shell / ryoku-hub)..."
  if command -v go >/dev/null 2>&1; then
    echo "   Found: $(go version)"
  else
    echo "   Warning: 'go' not found in PATH. Install Go 1.26+ from https://go.dev/dl/ before running build-deb-repo.sh."
  fi
  echo "✅ Build dependencies installed."
  exit 0
fi

echo ":: Installing Ryoku runtime dependencies..."
sudo apt-get install -y "${RUNTIME_DEPS[@]}"

if [ "$MODE" = "deps" ]; then
  echo "✅ Runtime dependencies installed. You can now install local .deb packages."
  exit 0
fi

echo ":: Configuring Ryoku Debian APT repository..."
sudo mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
curl -fsSL https://bigmum0a-wq.github.io/Ryoku-for-debian/ryoku-debian-release.pub.asc \
  | sudo gpg --yes --dearmor -o /usr/share/keyrings/ryoku-archive-keyring.gpg
sudo chmod 644 /usr/share/keyrings/ryoku-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/ryoku-archive-keyring.gpg] https://bigmum0a-wq.github.io/Ryoku-for-debian/apt trixie main" \
  | sudo tee /etc/apt/sources.list.d/ryoku.list >/dev/null
sudo chmod 644 /etc/apt/sources.list.d/ryoku.list

echo ":: Installing ryoku-desktop..."
sudo apt-get update
sudo apt-get install -y ryoku-desktop

# ryoku-archive-keyring ships /etc/apt/sources.list.d/ryoku.sources; remove temporary .list to avoid duplicate source warnings
if [ -f /etc/apt/sources.list.d/ryoku.sources ]; then
  sudo rm -f /etc/apt/sources.list.d/ryoku.list
fi

if [ "${EUID:-$(id -u)}" -ne 0 ] && command -v ryoku >/dev/null 2>&1; then
  echo ":: Materializing user configs..."
  ryoku materialize || true
fi

if [ "${EUID:-$(id -u)}" -ne 0 ] && command -v ryoku-dock-sync >/dev/null 2>&1; then
  ryoku-dock-sync || true
fi

echo "✅ Ryoku Desktop installed! Log out and select the 'Hyprland' session."
