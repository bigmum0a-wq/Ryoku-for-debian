#!/usr/bin/env bash
# install-online.sh — Automatically downloads Ryoku release parts from one or
# more sources, verifies SHA256 checksums, reassembles the archive, and
# installs all .deb packages.
#
# Usage:
#   RYOKU_RELEASE_URLS="https://github.com/OWNER/REPO/releases/download/v1.2.3" bash install-online.sh
#   (Multiple space-separated URLs can be provided as fallbacks)
set -euo pipefail

VER="${RYOKU_VER:-1.2.3}"
BASE_URLS="${RYOKU_RELEASE_URLS:-https://github.com/bigmum0a-wq/Ryoku-for-debian/releases/download/v${VER}}"
WORK_DIR="$(mktemp -d /tmp/ryoku-install.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

download_with_fallback() {
  local filename="$1"
  local dest="$2"
  for base in $BASE_URLS; do
    base="${base%/}"
    echo "   -> Downloading $filename from $base ..."
    if curl -fsSL --retry 2 --connect-timeout 15 -o "$dest" "$base/$filename"; then
      return 0
    fi
  done
  echo "Error: failed to download $filename from any configured source." >&2
  return 1
}

echo ":: Fetching Ryoku v${VER} manifest..."
download_with_fallback "parts.manifest" "$WORK_DIR/parts.manifest"
download_with_fallback "ryoku-deb-repo-${VER}.sha256" "$WORK_DIR/ryoku-deb-repo-${VER}.sha256"

while IFS= read -r part; do
  [ -n "$part" ] || continue
  download_with_fallback "$part" "$WORK_DIR/$part"
done < "$WORK_DIR/parts.manifest"

echo ":: Verifying parts and reassembling..."
(
  cd "$WORK_DIR"
  grep "\.part-" "ryoku-deb-repo-${VER}.sha256" | sha256sum -c -
  cat ryoku-deb-repo-${VER}.tar.gz.part-* > "ryoku-deb-repo-${VER}.tar.gz"
  grep "ryoku-deb-repo-${VER}\.tar\.gz$" "ryoku-deb-repo-${VER}.sha256" | sha256sum -c -
)

echo ":: Extracting .deb packages..."
mkdir -p "$WORK_DIR/repo"
tar -xzf "$WORK_DIR/ryoku-deb-repo-${VER}.tar.gz" -C "$WORK_DIR/repo"

echo ":: Cleaning up legacy Ryoku APT sources..."
sudo rm -f /etc/apt/sources.list.d/ryoku.sources \
           /etc/apt/sources.list.d/ryoku-*.list \
           /etc/apt/sources.list.d/ryoku-*.sources

PKG_POOL="$WORK_DIR/repo/out/pool/main/r/ryoku"
sudo dpkg -i "$PKG_POOL"/ryoku-archive-keyring_*.deb 2>/dev/null || true
sudo apt-get update || true
sudo apt-get install -y "$PKG_POOL"/*.deb

if [ "${EUID:-$(id -u)}" -ne 0 ] && command -v ryoku >/dev/null 2>&1; then
  ryoku materialize || true
fi

echo "✅ Ryoku v${VER} downloaded, reassembled, and installed successfully!"
