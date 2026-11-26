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
find "$DESKTOP_DIR/usr/share/ryoku" \( -name "README.md" -o -name "__pycache__" -o -name "*.pyc" \) -exec rm -rf {} + 2>/dev/null || true
package_deb "ryoku-desktop" "$ARCH" \
  "ryoku-cli (>= $PKGVER), ryoku-shell (>= $PKGVER), ryoku-palette-bridge (>= $PKGVER), ryoku-blobs (>= $PKGVER), ryoku-desktop-hyprland (>= $PKGVER), qml6-module-qtquick3d, wireplumber, pipewire, grim, slurp, wl-clipboard, tesseract-ocr, playerctl, cava, hyprpicker, hyprsunset, hypridle, ffmpeg, mpv, jq, socat, python3, gnome-keyring, libsecret-1-0, xdg-desktop-portal-gtk, xdg-desktop-portal-hyprland, x11-xserver-utils, libglib2.0-bin, dbus-user-session, qt6ct, papirus-icon-theme" \
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
