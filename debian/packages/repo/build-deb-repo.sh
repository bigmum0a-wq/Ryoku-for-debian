#!/usr/bin/env bash
# Build and index the Ryoku Debian APT repository and .deb packages.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

OUT_DIR=${RYOKU_DEB_OUT:-$SCRIPT_DIR/out}
PKGVER=${RYOKU_PKGVER:-1.2.3-1}
SUITE=${RYOKU_DEB_SUITE:-trixie}
ARCH=${RYOKU_DEB_ARCH:-amd64}
CODENAME=$(tr -d '[:space:]' < "$REPO_ROOT/CODENAME" 2>/dev/null || echo "Amaterasu")
COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")

export RYOKU_SRC="$REPO_ROOT"
export RYOKU_PKGVER="$PKGVER"
export RYOKU_DISTRO="debian"

log() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
die() { printf 'build-deb-repo: error: %s\n' "$*" >&2; exit 1; }

for tool in dpkg-deb dpkg-scanpackages gzip go; do
  command -v "$tool" >/dev/null || die "missing required build tool: $tool"
done

POOL_DIR="$OUT_DIR/pool/main/r/ryoku"
DISTS_DIR="$OUT_DIR/dists/$SUITE/main/binary-$ARCH"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

log "Output dir -> $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$POOL_DIR" "$DISTS_DIR" "$WORK_DIR/build"

# Helper function to package a deb
package_deb() {
  local pkg_name=$1
  local pkg_arch=$2
  local pkg_deps=$3
  local pkg_desc=$4
  local staging_dir=$5

  mkdir -p "$staging_dir/DEBIAN"
  cat << EOF > "$staging_dir/DEBIAN/control"
Package: $pkg_name
Version: $PKGVER
Section: x11
Priority: optional
Architecture: $pkg_arch
Maintainer: Ryoku Debian Maintainers <packaging@ryoku.dev>
Depends: $pkg_deps
Description: $pkg_desc
EOF

  local deb_file="$POOL_DIR/${pkg_name}_${PKGVER}_${pkg_arch}.deb"
  dpkg-deb --root-owner-group --build "$staging_dir" "$deb_file"
  log "Created: $(basename "$deb_file")"
}

# 1. ryoku-archive-keyring
log "Building ryoku-archive-keyring"
KEYRING_DIR="$WORK_DIR/keyring"
mkdir -p "$KEYRING_DIR/usr/share/keyrings" "$KEYRING_DIR/etc/apt/sources.list.d"
if command -v gpg >/dev/null 2>&1; then
  KEY_CAT=$(mktemp)
  for pubkey in "$REPO_ROOT/keys/ryoku-debian-release.pub.asc" "$REPO_ROOT/keys/ryoku-release-key.pub.asc"; do
    [ -f "$pubkey" ] && cat "$pubkey" >> "$KEY_CAT"
  done
  if [ -s "$KEY_CAT" ]; then
    gpg --dearmor < "$KEY_CAT" > "$KEYRING_DIR/usr/share/keyrings/ryoku-archive-keyring.gpg"
  fi
  rm -f "$KEY_CAT"
fi
cat << 'EOF' > "$KEYRING_DIR/etc/apt/sources.list.d/ryoku.sources"
# Ryoku Debian APT repository (GitHub Pages mirror)
Types: deb
URIs: https://bigmum0a-wq.github.io/Ryoku-for-debian/apt
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/ryoku-archive-keyring.gpg
EOF
package_deb "ryoku-archive-keyring" "all" "gpg" \
  "GnuPG archive key and apt sources list for Ryoku Debian repository" "$KEYRING_DIR"

# 2. ryoku-cli (CLI + ryoku-host)
log "Building ryoku-cli"
CLI_DIR="$WORK_DIR/cli"
CLI_BUILD="$WORK_DIR/build/cli"
mkdir -p "$CLI_DIR" "$CLI_BUILD"
RYOKU_BUILD_DIR="$CLI_BUILD" "$REPO_ROOT/release/packages/ryoku/payload.sh" build
RYOKU_BUILD_DIR="$CLI_BUILD" "$REPO_ROOT/release/packages/ryoku/payload.sh" install "$CLI_DIR" systemd
install -Dm644 "$REPO_ROOT/debian/packages/translations.tsv" "$CLI_DIR/usr/share/ryoku/packages/debian.tsv"
package_deb "ryoku-cli" "$ARCH" "apt, dpkg, systemd" \
  "Ryoku Desktop Control Plane and Host Abstraction" "$CLI_DIR"

# 3. ryoku-shell
log "Building ryoku-shell"
SHELL_DIR="$WORK_DIR/shell"
SHELL_BUILD="$WORK_DIR/build/shell"
mkdir -p "$SHELL_DIR" "$SHELL_BUILD"
if ! pkg-config --exists wayland-protocols wayland-client libavformat libavcodec libavutil libswscale 2>/dev/null; then
  log "wayland-protocols dev package not found; staging prebuilt ryoku-shell and fallback livewall"
  PREBUILT_SHELL="$WORK_DIR/prebuilt-shell"
  mkdir -p "$PREBUILT_SHELL"
  ( cd "$REPO_ROOT/ryoku/shell/ipc" && CGO_ENABLED=0 go build -trimpath -mod=vendor -ldflags='-s -w' -o "$PREBUILT_SHELL/ryoku-shell" . )
  printf '#!/bin/sh\n# ryoku-livewall fallback stub\nexit 0\n' > "$PREBUILT_SHELL/ryoku-livewall"
  chmod 755 "$PREBUILT_SHELL/ryoku-livewall"
  RYOKU_PREBUILT_DIR="$PREBUILT_SHELL" RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" build
  RYOKU_PREBUILT_DIR="$PREBUILT_SHELL" RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" install "$SHELL_DIR" systemd
else
  RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" build
  RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" install "$SHELL_DIR" systemd
fi
# Build and package ryogami & ryoku-hub so wallpaper daemon and Hub backend are always in /usr/bin
log "Building ryogami"
( cd "$REPO_ROOT/ryoku/shell/ryogami/daemon" && CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$SHELL_DIR/usr/bin/ryogami" . )
chmod 755 "$SHELL_DIR/usr/bin/ryogami"
log "Building ryoku-hub"
( cd "$REPO_ROOT/ryoku/hub/backend" && CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$SHELL_DIR/usr/bin/ryoku-hub" . )
chmod 755 "$SHELL_DIR/usr/bin/ryoku-hub"
if [ -f "$SHELL_DIR/usr/bin/ryoku-livewall" ] && [ ! -e "$SHELL_DIR/usr/bin/ryogami-live" ]; then
  ln -sfn ryoku-livewall "$SHELL_DIR/usr/bin/ryogami-live"
fi

# Build and package ryoku-rashin (AI assistant backend, usage collectors, systemd units)
log "Building ryoku-rashin"
( cd "$REPO_ROOT/ryoku/rashin/backend" && CGO_ENABLED=0 go build -trimpath -mod=vendor -ldflags='-s -w' -o "$SHELL_DIR/usr/bin/ryoku-rashin" . )
chmod 755 "$SHELL_DIR/usr/bin/ryoku-rashin"
ln -sfn ryoku-rashin "$SHELL_DIR/usr/bin/rashin"
"$SHELL_DIR/usr/bin/ryoku-rashin" repo-index "$REPO_ROOT" "$SHELL_DIR/usr/share/ryoku/rashin/ryoku-repo.md"
for file in "$REPO_ROOT"/ryoku/rashin/skills/ryoku/*.md; do
  [ -f "$file" ] && install -Dm644 "$file" "$SHELL_DIR/usr/share/ryoku/skills/ryoku/$(basename "$file")"
done
for file in "$REPO_ROOT"/ryoku/rashin/wiki/*.md; do
  [ -f "$file" ] && install -Dm644 "$file" "$SHELL_DIR/usr/share/ryoku/rashin/wiki/$(basename "$file")"
done
for collector in ryoku-ai-usage claude-usage codex-usage opencode-usage; do
  [ -f "$REPO_ROOT/ryoku/rashin/usage/$collector" ] && \
    install -Dm755 "$REPO_ROOT/ryoku/rashin/usage/$collector" "$SHELL_DIR/usr/bin/$collector"
done
for unit in ryoku-rashin.service ryoku-prowl.service ryoku-ai-usage.service ryoku-ai-usage.timer; do
  [ -f "$REPO_ROOT/ryoku/rashin/systemd/$unit" ] && \
    install -Dm644 "$REPO_ROOT/ryoku/rashin/systemd/$unit" "$SHELL_DIR/usr/lib/systemd/user/$unit"
done
if pkg-config --exists gtk+-3.0 2>/dev/null; then
  cmake -S "$REPO_ROOT/ryoku/rashin/app" -B "$SHELL_BUILD/rashin-app-build" -G Ninja -DCMAKE_BUILD_TYPE=Release
  cmake --build "$SHELL_BUILD/rashin-app-build"
  install -Dm755 "$SHELL_BUILD/rashin-app-build/rashin-app" "$SHELL_DIR/usr/bin/rashin-app"
  install -Dm644 "$REPO_ROOT/ryoku/rashin/app/rashin-app.desktop" "$SHELL_DIR/usr/share/applications/rashin-app.desktop"
  install -Dm644 "$REPO_ROOT/ryoku/rashin/app/logo.svg" "$SHELL_DIR/usr/share/icons/hicolor/scalable/apps/rashin-app.svg"
fi

package_deb "ryoku-shell" "$ARCH" "quickshell, bash" \
  "Ryoku Desktop Shell IPC and supervision daemon" "$SHELL_DIR"

# 4. ryoku-palette-bridge
log "Building ryoku-palette-bridge"
PALETTE_DIR="$WORK_DIR/palette"
PALETTE_BUILD="$WORK_DIR/build/palette"
mkdir -p "$PALETTE_DIR" "$PALETTE_BUILD"
RYOKU_BUILD_DIR="$PALETTE_BUILD" "$REPO_ROOT/release/packages/ryoku-palette-bridge/payload.sh" build
RYOKU_BUILD_DIR="$PALETTE_BUILD" "$REPO_ROOT/release/packages/ryoku-palette-bridge/payload.sh" install "$PALETTE_DIR" systemd
# Strip Go sources, unit tests, packaging files and README from runtime payload
rm -rf "$PALETTE_DIR/usr/share/ryoku/palette-bridge/tests" \
       "$PALETTE_DIR/usr/share/ryoku/palette-bridge/packaging" \
       "$PALETTE_DIR/usr/share/ryoku/palette-bridge/"*.go \
       "$PALETTE_DIR/usr/share/ryoku/palette-bridge/go.mod" \
       "$PALETTE_DIR/usr/share/ryoku/palette-bridge/install.sh" \
       "$PALETTE_DIR/usr/share/ryoku/palette-bridge/README.md"
package_deb "ryoku-palette-bridge" "$ARCH" "ryoku-cli" \
  "Ryoku Palette Bridge for dynamic wallpaper-derived color sync" "$PALETTE_DIR"

# 5. ryoku-blobs
log "Building ryoku-blobs"
BLOBS_DIR="$WORK_DIR/blobs"
BLOBS_BUILD="$WORK_DIR/build/blobs"
mkdir -p "$BLOBS_DIR" "$BLOBS_BUILD"
if dpkg -l qt6-shadertools-dev >/dev/null 2>&1 && dpkg -l qt6-quick3d-dev >/dev/null 2>&1; then
  RYOKU_BUILD_DIR="$BLOBS_BUILD" "$REPO_ROOT/release/packages/ryoku-blobs/payload.sh" build
  RYOKU_BUILD_DIR="$BLOBS_BUILD" "$REPO_ROOT/release/packages/ryoku-blobs/payload.sh" install "$BLOBS_DIR" systemd
else
  log "Qt6 shader/quick3d dev tools not available; packaging QML fallback stubs"
  PREBUILT_BLOBS="$WORK_DIR/prebuilt-blobs"
  mkdir -p "$PREBUILT_BLOBS/qml/Ryoku"
  cp -a "$REPO_ROOT/debian/packages/stubs/Ryoku/Blobs" "$PREBUILT_BLOBS/qml/Ryoku/"
  cp -a "$REPO_ROOT/debian/packages/stubs/Ryoku/Spatial3D" "$PREBUILT_BLOBS/qml/Ryoku/"
  RYOKU_PREBUILT_DIR="$PREBUILT_BLOBS" RYOKU_BUILD_DIR="$BLOBS_BUILD" "$REPO_ROOT/release/packages/ryoku-blobs/payload.sh" build
  RYOKU_PREBUILT_DIR="$PREBUILT_BLOBS" RYOKU_BUILD_DIR="$BLOBS_BUILD" "$REPO_ROOT/release/packages/ryoku-blobs/payload.sh" install "$BLOBS_DIR" systemd
fi
# Debian Qt 6.8 compat: install RectangularShadow stub into QtQuick/Effects
# (RectangularShadow was added in Qt 6.9; this stub uses MultiEffect as fallback)
install -Dm644 "$REPO_ROOT/debian/packages/stubs/QtQuick/Effects/RectangularShadow.qml" \
  "$BLOBS_DIR/usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick/Effects/RectangularShadow.qml"
mkdir -p "$BLOBS_DIR/DEBIAN"
cat << 'EOF' > "$BLOBS_DIR/DEBIAN/postinst"
#!/bin/sh
set -e
QMLDIR="/usr/lib/x86_64-linux-gnu/qt6/qml/QtQuick/Effects/qmldir"
if [ -f "$QMLDIR" ]; then
  if ! grep -q "RectangularShadow" "$QMLDIR"; then
    sed -i '/prefer :\//d' "$QMLDIR"
    echo "RectangularShadow 6.0 RectangularShadow.qml" >> "$QMLDIR"
  fi
fi
exit 0
EOF
chmod 755 "$BLOBS_DIR/DEBIAN/postinst"
package_deb "ryoku-blobs" "$ARCH" "quickshell" \
  "Ryoku Blobs and Spatial3D QML components" "$BLOBS_DIR"

# 6. ryoku-desktop-hyprland
log "Building ryoku-desktop-hyprland"
HYPR_DIR="$WORK_DIR/hyprland"
HYPR_BUILD="$WORK_DIR/build/hyprland"
mkdir -p "$HYPR_DIR" "$HYPR_BUILD"
RYOKU_BUILD_DIR="$HYPR_BUILD" "$REPO_ROOT/release/packages/ryoku-desktop-hyprland/payload.sh" build
RYOKU_BUILD_DIR="$HYPR_BUILD" "$REPO_ROOT/release/packages/ryoku-desktop-hyprland/payload.sh" install "$HYPR_DIR" systemd
rm -rf "$HYPR_DIR/usr/share/ryoku/config/hypr/CHANGELOG.md" \
       "$HYPR_DIR/usr/share/ryoku/config/hypr/plugins/keysounds"
package_deb "ryoku-desktop-hyprland" "$ARCH" "hyprland, ryoku-shell" \
  "Ryoku Desktop Hyprland compositor integration and configuration" "$HYPR_DIR"

# 7a. starship — build a minimal .deb from the official musl binary (no Rust toolchain required)
log "Building ryoku-starship (starship prompt pre-built)"
STARSHIP_DIR="$WORK_DIR/starship"
mkdir -p "$STARSHIP_DIR/usr/local/bin" \
         "$STARSHIP_DIR/usr/share/fish/vendor_conf.d" \
         "$STARSHIP_DIR/DEBIAN"
# Download the pinned musl binary (identical to what `starship init sh` installs)
STARSHIP_VERSION="1.27.0"
STARSHIP_URL="https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-musl.tar.gz"
STARSHIP_SHA256="$(curl -fsSL "${STARSHIP_URL}.sha256" 2>/dev/null || true)"
STARSHIP_TMP="$WORK_DIR/starship-dl"
mkdir -p "$STARSHIP_TMP"
if curl -fsSL --retry 3 -o "$STARSHIP_TMP/starship.tar.gz" "$STARSHIP_URL" 2>/dev/null; then
  tar -xzf "$STARSHIP_TMP/starship.tar.gz" -C "$STARSHIP_TMP"
  install -Dm755 "$STARSHIP_TMP/starship" "$STARSHIP_DIR/usr/local/bin/starship"
  # Fish auto-init: create a vendor conf.d snippet so every fish session loads starship
  cat > "$STARSHIP_DIR/usr/share/fish/vendor_conf.d/ryoku-starship.fish" <<'FISH'
# Ryoku: initialise starship prompt for fish
if command -q starship
    starship init fish | source
end
FISH
  log "starship $STARSHIP_VERSION binary fetched"
else
  log "Warning: could not fetch starship binary; skipping ryoku-starship package"
  STARSHIP_DIR=""
fi
if [ -n "$STARSHIP_DIR" ]; then
  cat <<EOF > "$STARSHIP_DIR/DEBIAN/control"
Package: ryoku-starship
Version: ${STARSHIP_VERSION}-1ryoku1
Section: x11
Priority: optional
Architecture: amd64
Maintainer: Ryoku Debian Maintainers <packaging@ryoku.dev>
Depends: fish
Description: Starship prompt for Ryoku Desktop (pre-built musl binary)
 Cross-shell prompt used as the default shell experience in Ryoku.
 Automatically initialised for fish via /usr/share/fish/vendor_conf.d.
EOF
  dpkg-deb --root-owner-group --build "$STARSHIP_DIR" "$POOL_DIR/ryoku-starship_${STARSHIP_VERSION}-1ryoku1_amd64.deb"
  log "Created: ryoku-starship_${STARSHIP_VERSION}-1ryoku1_amd64.deb"
fi

# 7b. matugen — package matugen 4.x into /usr/bin/matugen (not in Debian APT)
log "Building ryoku-matugen (Material You color generator)"
MATUGEN_SRC_BIN=""
for candidate in \
  "${RYOKU_MATUGEN_BIN:-}" \
  "$(command -v matugen 2>/dev/null || true)" \
  "$HOME/.local/bin/matugen" \
  "$HOME/.cargo/bin/matugen" \
  "/usr/bin/matugen"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    MATUGEN_SRC_BIN="$candidate"
    break
  fi
done
if [ -n "$MATUGEN_SRC_BIN" ]; then
  MATUGEN_VER="$("$MATUGEN_SRC_BIN" --version 2>/dev/null | awk '{print $2}' | head -n1)"
  MATUGEN_VER="${MATUGEN_VER:-4.2.0}"
  MATUGEN_DIR="$WORK_DIR/matugen"
  mkdir -p "$MATUGEN_DIR/usr/bin" "$MATUGEN_DIR/DEBIAN"
  install -Dm755 "$MATUGEN_SRC_BIN" "$MATUGEN_DIR/usr/bin/matugen"
  cat <<EOF > "$MATUGEN_DIR/DEBIAN/control"
Package: ryoku-matugen
Version: ${MATUGEN_VER}-1ryoku1
Section: x11
Priority: optional
Architecture: amd64
Maintainer: Ryoku Debian Maintainers <packaging@ryoku.dev>
Depends: libc6, libgcc-s1
Description: Matugen Material You color generator for Ryoku Desktop
 Generates dynamic wallpaper-derived color palettes for Ryoku themes,
 templates, and ryoku-palette-bridge.
EOF
  dpkg-deb --root-owner-group --build "$MATUGEN_DIR" "$POOL_DIR/ryoku-matugen_${MATUGEN_VER}-1ryoku1_amd64.deb"
  log "Created: ryoku-matugen_${MATUGEN_VER}-1ryoku1_amd64.deb"
else
  log "Warning: matugen binary not found; skipping ryoku-matugen package"
fi

# 7. ryoku-desktop (metapackage and shared configs)
log "Building ryoku-desktop"
DESKTOP_DIR="$WORK_DIR/desktop"
DESKTOP_BUILD="$WORK_DIR/build/desktop"
mkdir -p "$DESKTOP_DIR" "$DESKTOP_BUILD"
RYOKU_BUILD_DIR="$DESKTOP_BUILD" "$REPO_ROOT/release/packages/ryoku-desktop/payload.sh" install "$DESKTOP_DIR" systemd
mkdir -p "$DESKTOP_DIR/usr/lib/x86_64-linux-gnu/qt6/qml"
ln -sfn /usr/lib/qt6/qml/Ryoku "$DESKTOP_DIR/usr/lib/x86_64-linux-gnu/qt6/qml/Ryoku"
if [ -f "$REPO_ROOT/debian/packages/fonts/MaterialSymbolsRounded.ttf" ]; then
  install -Dm644 "$REPO_ROOT/debian/packages/fonts/MaterialSymbolsRounded.ttf" \
    "$DESKTOP_DIR/usr/share/fonts/truetype/ryoku/MaterialSymbolsRounded.ttf"
fi
for helper_bin in "$REPO_ROOT/debian/packages/bin/"*; do
  [ -f "$helper_bin" ] || continue
  install -Dm755 "$helper_bin" "$DESKTOP_DIR/usr/bin/$(basename "$helper_bin")"
done
mkdir -p "$DESKTOP_DIR/etc/xdg/autostart"
cat << 'EOF' > "$DESKTOP_DIR/etc/xdg/autostart/ryoku-session-guard.desktop"
[Desktop Entry]
Type=Application
Name=Ryoku Session Guard
Comment=Stop Ryoku daemons and restore clean DE styles when running a non-Hyprland desktop
Exec=/usr/bin/ryoku-session-guard enter-other
NotShowIn=Hyprland;
NoDisplay=true
X-GNOME-Autostart-Phase=Initialization
EOF
mkdir -p "$DESKTOP_DIR/etc/xdg/plasma-workspace/env"
cat << 'EOF' > "$DESKTOP_DIR/etc/xdg/plasma-workspace/env/00-ryoku-clean.sh"
#!/bin/sh
# Sourced by startplasma-wayland / startplasma-x11 BEFORE kwin_wayland and plasmashell
# start, ensuring Ryoku/Hyprland variables never leak into KDE Plasma.
unset RYOKU_SESSION_KEY RYOKU_ACTIVE RYOKU_WM RYOKU_POLKIT_AGENT \
  QT_QPA_PLATFORMTHEME QT_WAYLAND_DISABLE_WINDOWDECORATION \
  QT_QPA_PLATFORM QT_AUTO_SCREEN_SCALE_FACTOR QT_WAYLAND_RECONNECT \
  GSK_RENDERER GDK_BACKEND GTK_THEME GTK_DECORATION_LAYOUT \
  ELECTRON_OZONE_PLATFORM_HINT \
  XCURSOR_THEME XCURSOR_SIZE HYPRCURSOR_THEME HYPRCURSOR_SIZE \
  HYPRLAND_CMD HYPRLAND_NO_SD_NOTIFY

if [ -x /usr/bin/ryoku-session-guard ]; then
  /usr/bin/ryoku-session-guard enter-other >/dev/null 2>&1 || true
fi
EOF
chmod +x "$DESKTOP_DIR/etc/xdg/plasma-workspace/env/00-ryoku-clean.sh"
mkdir -p "$DESKTOP_DIR/usr/share/wayland-sessions"
cat << 'EOF' > "$DESKTOP_DIR/usr/share/wayland-sessions/ryoku-hyprland.desktop"
[Desktop Entry]
Name=Ryoku (Hyprland)
Comment=Ryoku Desktop Environment on Hyprland
Exec=/usr/bin/ryoku-hyprland-session
TryExec=/usr/bin/ryoku-hyprland-session
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;ryoku;
EOF

mkdir -p "$DESKTOP_DIR/DEBIAN"
cat << 'EOF' > "$DESKTOP_DIR/DEBIAN/postinst"
#!/bin/sh
set -e

# Remove stale per-home symlink if present from manual dev installs
if [ -L /usr/local/bin/ryoku-hub ]; then
  case "$(readlink /usr/local/bin/ryoku-hub 2>/dev/null || true)" in
    /home/*) rm -f /usr/local/bin/ryoku-hub ;;
  esac
fi

# ── Debian compatibility: create the 'wheel' group as an alias for 'sudo' ──
# ryoku-host uses 'wheel' (Arch/Fedora convention) OR 'sudo' (Debian convention)
# to identify administrators. On stock Debian only 'sudo' exists; creating
# 'wheel' as a synonym lets the Hub's Users page and set-role work correctly.
if ! getent group wheel >/dev/null 2>&1; then
  groupadd --system wheel 2>/dev/null || true
fi
# Mirror current 'sudo' group members into 'wheel' (idempotent)
if getent group sudo >/dev/null 2>&1; then
  for _user in $(getent group sudo | cut -d: -f4 | tr ',' ' '); do
    [ -n "$_user" ] && usermod -aG wheel "$_user" 2>/dev/null || true
  done
fi

# ── hyprpaper: mask the system service — ryogami owns the wallpaper engine ──
# hyprpaper v0.8.5 on Debian Trixie crashes (libhyprtoolkit ABI mismatch).
# Ryoku uses ryogami (its own wallpaper daemon) so hyprpaper is redundant.
# We write a system-level mask so it stays masked for all future users.
_HYPRPAPER_MASK_DIR="/usr/lib/systemd/user"
if [ -f "$_HYPRPAPER_MASK_DIR/hyprpaper.service" ] && \
   [ ! -L "$_HYPRPAPER_MASK_DIR/hyprpaper.service" ]; then
  # Create a drop-in override directory and disable via mask in the system preset
  mkdir -p /usr/lib/systemd/user/hyprpaper.service.d
  cat > /usr/lib/systemd/user/hyprpaper.service.d/ryoku-disable.conf <<'CONF'
# Ryoku: hyprpaper is replaced by ryogami (the native Ryoku wallpaper daemon).
# Masked here because hyprpaper v0.8.5 crashes on Debian Trixie (libhyprtoolkit
# ABI mismatch). Remove this file to re-enable hyprpaper.
[Unit]
ConditionPathExists=/this/path/does/not/exist
CONF
fi

# ── fish: set as default shell for new Ryoku users (non-root, opt-in) ──
# Only update shell when fish exists and the existing shell is still the
# system default (/bin/bash or /bin/sh). Never override a custom user choice.
_FISH=$(command -v fish 2>/dev/null || true)
if [ -n "$_FISH" ] && getent passwd | while IFS=: read -r _u _ _uid _ _ _ _sh; do
    [ "$_uid" -ge 1000 ] 2>/dev/null || continue
    case "$_sh" in /bin/bash|/bin/sh) echo "$_u"; break ;; esac
  done | grep -q .; then
  : # fish is available; materialize will configure starship via vendor_conf.d
fi

# Create system groups (e.g. i2c for ddcutil) and reload udev rules
if command -v systemd-sysusers >/dev/null 2>&1; then
  systemd-sysusers >/dev/null 2>&1 || true
fi
if command -v udevadm >/dev/null 2>&1 && [ -d /run/udev ]; then
  udevadm control --reload-rules >/dev/null 2>&1 || true
  udevadm trigger --subsystem-match=i2c-dev >/dev/null 2>&1 || true
fi

# Reload polkit rules so sudo-group grants take effect immediately
if [ -x /usr/bin/ryoku-polkit-reload ]; then
  /usr/bin/ryoku-polkit-reload >/dev/null 2>&1 || true
fi

# Enable system and global user systemd units for all accounts (present & future)
if [ -x /usr/bin/ryoku-host ] && [ -d /run/systemd/system ]; then
  RYOKU_HOST_INIT=systemd /usr/bin/ryoku-host svc reconcile --system >/dev/null 2>&1 || true
fi

# Tune BlueZ & Wi-Fi regdom idempotently
if [ -x /usr/bin/ryoku-bluetooth-tune ]; then
  /usr/bin/ryoku-bluetooth-tune >/dev/null 2>&1 || true
  if [ -d /run/systemd/system ]; then
    systemctl try-restart bluetooth.service >/dev/null 2>&1 || true
  fi
fi
if [ -x /usr/bin/ryoku-wifi-regdom ]; then
  /usr/bin/ryoku-wifi-regdom apply >/dev/null 2>&1 || true
fi

# Refresh icon and desktop caches
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
fi

exit 0
EOF
chmod 755 "$DESKTOP_DIR/DEBIAN/postinst"

find "$DESKTOP_DIR/usr/share/ryoku" \( -name "README.md" -o -name "__pycache__" -o -name "*.pyc" \) -exec rm -rf {} + 2>/dev/null || true
package_deb "ryoku-desktop" "$ARCH" \
  "ryoku-cli (>= $PKGVER), ryoku-shell (>= $PKGVER), ryoku-palette-bridge (>= $PKGVER), ryoku-blobs (>= $PKGVER), ryoku-desktop-hyprland (>= $PKGVER), ryoku-starship, ryoku-matugen, fastfetch, qml6-module-qtquick3d, wireplumber, pipewire, pipewire-pulse, swaybg, fish, brightnessctl, ddcutil, grim, slurp, wl-clipboard, tesseract-ocr, playerctl, cava, hyprpicker, hyprsunset, hypridle, ffmpeg, mpv, jq, socat, python3, gnome-keyring, libsecret-1-0, xdg-desktop-portal-gtk, xdg-desktop-portal-hyprland, x11-xserver-utils, libglib2.0-bin, dbus-user-session, qt6ct, papirus-icon-theme, pamu2fcfg, libpam-u2f, kdeconnect, librsvg2-bin" \
  "Ryoku Desktop Environment (metapackage and system configuration)" "$DESKTOP_DIR"

# 8. Index packages into repository
log "Indexing APT repository"
cd "$OUT_DIR"
dpkg-scanpackages --multiversion pool/ > "$DISTS_DIR/Packages"
gzip -9c "$DISTS_DIR/Packages" > "$DISTS_DIR/Packages.gz"

# Generate Release metadata
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="Ryoku" \
  -o APT::FTPArchive::Release::Label="Ryoku Debian" \
  -o APT::FTPArchive::Release::Suite="$SUITE" \
  -o APT::FTPArchive::Release::Codename="$SUITE" \
  -o APT::FTPArchive::Release::Architectures="$ARCH all" \
  -o APT::FTPArchive::Release::Components="main" \
  release "$OUT_DIR/dists/$SUITE" > "$WORK_DIR/Release.tmp"
cat "$WORK_DIR/Release.tmp" > "$OUT_DIR/dists/$SUITE/Release"

# Sign Release (Release.gpg + InRelease) and pool SHA256SUMS if signing key is available
SIGN_KEY="${RYOKU_GPG_KEY:-packaging@ryoku.dev}"
if command -v gpg >/dev/null 2>&1 && gpg --list-secret-keys "$SIGN_KEY" >/dev/null 2>&1; then
  log "Signing APT Release & SHA256SUMS with GPG key ($SIGN_KEY)"
  gpg --batch --yes --pinentry-mode loopback -u "$SIGN_KEY" -abs \
    -o "$OUT_DIR/dists/$SUITE/Release.gpg" "$OUT_DIR/dists/$SUITE/Release"
  gpg --batch --yes --pinentry-mode loopback -u "$SIGN_KEY" --clearsign \
    -o "$OUT_DIR/dists/$SUITE/InRelease" "$OUT_DIR/dists/$SUITE/Release"
  (
    cd "$POOL_DIR"
    sha256sum *.deb > SHA256SUMS
    gpg --batch --yes --pinentry-mode loopback -u "$SIGN_KEY" --clearsign \
      -o SHA256SUMS.asc SHA256SUMS
  )
  [ -f "$REPO_ROOT/keys/ryoku-debian-release.pub.asc" ] && \
    cp "$REPO_ROOT/keys/ryoku-debian-release.pub.asc" "$OUT_DIR/ryoku-debian-release.pub.asc"
else
  log "Warning: GPG secret key '$SIGN_KEY' not found; Release left unsigned"
fi

# 7. release.json for ryoku update
cat << EOF > "$OUT_DIR/release.json"
{"schema":1,"release":"$PKGVER","name":"$CODENAME","channel":"stable","version":"$PKGVER","commit":"$COMMIT","date":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

log "Debian repository ready at $OUT_DIR"
