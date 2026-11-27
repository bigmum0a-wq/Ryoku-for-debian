#!/usr/bin/env bash
# split-release.sh — Splits a Ryoku archive into chunks of at most 20 MB
# with SHA256 checksums and a manifest for GitHub Releases / multi-source hosting.
set -euo pipefail

VER="${1:-1.2.3}"
EXPORT_DIR="${EXPORT_DIR:-$HOME/ryoku-export}"
TARBALL="$EXPORT_DIR/ryoku-deb-repo-${VER}.tar.gz"
OUT_DIR="$EXPORT_DIR/release-parts-${VER}"

if [ ! -f "$TARBALL" ]; then
  echo "Error: archive not found: $TARBALL" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo ":: Splitting $(basename "$TARBALL") into 20 MB chunks..."
split -b 20M -d -a 2 "$TARBALL" "$OUT_DIR/ryoku-deb-repo-${VER}.tar.gz.part-"

(
  cd "$OUT_DIR"
  sha256sum ryoku-deb-repo-${VER}.tar.gz.part-* > "ryoku-deb-repo-${VER}.sha256"
  ls -1 ryoku-deb-repo-${VER}.tar.gz.part-* > "parts.manifest"
  # Checksum of the complete archive once reassembled
  sha256sum "$TARBALL" | awk -v name="ryoku-deb-repo-${VER}.tar.gz" '{print $1 "  " name}' >> "ryoku-deb-repo-${VER}.sha256"
)

echo ":: Generated files in $OUT_DIR:"
ls -lh "$OUT_DIR"
