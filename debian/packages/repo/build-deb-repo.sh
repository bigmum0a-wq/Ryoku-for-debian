#!/usr/bin/env bash
# Build and index the Ryoku Debian APT repository and .deb packages.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

OUT_DIR=${RYOKU_DEB_OUT:-$SCRIPT_DIR/out}
PKGVER=${RYOKU_PKGVER:-1.1.0-1}
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
if command -v gpg >/dev/null 2>&1 && [ -f "$REPO_ROOT/keys/ryoku-release-key.pub.asc" ]; then
  gpg --dearmor < "$REPO_ROOT/keys/ryoku-release-key.pub.asc" > "$KEYRING_DIR/usr/share/keyrings/ryoku-archive-keyring.gpg"
fi
cat << 'EOF' > "$KEYRING_DIR/etc/apt/sources.list.d/ryoku.sources"
Types: deb
URIs: https://repo.ryoku.dev/stable/debian
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
if ! pkg-config --exists wayland-protocols 2>/dev/null; then
  log "wayland-protocols dev package not found; staging prebuilt ryoku-shell and fallback livewall"
  PREBUILT_SHELL="$WORK_DIR/prebuilt-shell"
  mkdir -p "$PREBUILT_SHELL"
  ( cd "$REPO_ROOT/ryoku/shell/ipc" && CGO_ENABLED=0 go build -trimpath -mod=vendor -o "$PREBUILT_SHELL/ryoku-shell" . )
  printf '#!/bin/sh\n# ryoku-livewall fallback stub\nexit 0\n' > "$PREBUILT_SHELL/ryoku-livewall"
  chmod 755 "$PREBUILT_SHELL/ryoku-livewall"
  RYOKU_PREBUILT_DIR="$PREBUILT_SHELL" RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" build
  RYOKU_PREBUILT_DIR="$PREBUILT_SHELL" RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" install "$SHELL_DIR" systemd
else
  RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" build
  RYOKU_BUILD_DIR="$SHELL_BUILD" "$REPO_ROOT/release/packages/ryoku-shell/payload.sh" install "$SHELL_DIR" systemd
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
package_deb "ryoku-palette-bridge" "$ARCH" "ryoku-cli" \
  "Ryoku Palette Bridge for dynamic wallpaper-derived color sync" "$PALETTE_DIR"

# 5. ryoku-desktop (metapackage and shared configs)
log "Building ryoku-desktop"
DESKTOP_DIR="$WORK_DIR/desktop"
DESKTOP_BUILD="$WORK_DIR/build/desktop"
mkdir -p "$DESKTOP_DIR" "$DESKTOP_BUILD"
RYOKU_BUILD_DIR="$DESKTOP_BUILD" "$REPO_ROOT/release/packages/ryoku-desktop/payload.sh" install "$DESKTOP_DIR" systemd
package_deb "ryoku-desktop" "all" \
  "ryoku-cli (>= $PKGVER), ryoku-shell (>= $PKGVER), ryoku-palette-bridge (>= $PKGVER), wireplumber, pipewire" \
  "Ryoku Desktop Environment (metapackage and system configuration)" "$DESKTOP_DIR"

# 6. Index packages into repository
log "Indexing APT repository"
cd "$OUT_DIR"
dpkg-scanpackages --multiversion pool/ > "$DISTS_DIR/Packages"
gzip -9c "$DISTS_DIR/Packages" > "$DISTS_DIR/Packages.gz"

# Generate Release metadata
apt-ftparchive release "$OUT_DIR/dists/$SUITE" > "$WORK_DIR/Release.tmp"
cat "$WORK_DIR/Release.tmp" > "$OUT_DIR/dists/$SUITE/Release"

# 7. release.json for ryoku update
cat << EOF > "$OUT_DIR/release.json"
{"schema":1,"release":"$PKGVER","name":"$CODENAME","channel":"stable","version":"$PKGVER","commit":"$COMMIT","date":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF

log "Debian repository ready at $OUT_DIR"
