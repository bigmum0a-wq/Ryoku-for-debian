#!/usr/bin/env bash
# split-release.sh — Découpe une archive Ryoku en morceaux de 20 Mo max
# avec somme SHA256 et manifeste pour hébergement GitHub Releases / multi-sources.
set -euo pipefail

VER="${1:-1.2.3}"
EXPORT_DIR="${EXPORT_DIR:-$HOME/ryoku-export}"
TARBALL="$EXPORT_DIR/ryoku-deb-repo-${VER}.tar.gz"
OUT_DIR="$EXPORT_DIR/release-parts-${VER}"

if [ ! -f "$TARBALL" ]; then
  echo "Erreur: archive introuvable: $TARBALL" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo ":: Découpage de $(basename "$TARBALL") en morceaux de 20 Mo..."
split -b 20M -d -a 2 "$TARBALL" "$OUT_DIR/ryoku-deb-repo-${VER}.tar.gz.part-"

(
  cd "$OUT_DIR"
  sha256sum ryoku-deb-repo-${VER}.tar.gz.part-* > "ryoku-deb-repo-${VER}.sha256"
  ls -1 ryoku-deb-repo-${VER}.tar.gz.part-* > "parts.manifest"
  # Empreinte de l'archive complète une fois réassemblée
  sha256sum "$TARBALL" | awk -v name="ryoku-deb-repo-${VER}.tar.gz" '{print $1 "  " name}' >> "ryoku-deb-repo-${VER}.sha256"
)

echo ":: Fichiers générés dans $OUT_DIR :"
ls -lh "$OUT_DIR"
