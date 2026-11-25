#!/usr/bin/env bash
# publish-release.sh — Crée un tag vX.Y.Z et pousse branche + tag vers GitHub
# en une seule commande pour déclencher le workflow release-debian.yml.
#
# Usage : bash debian/packages/repo/publish-release.sh v1.2.3
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" || ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vX.Y.Z (ex: $0 v1.2.3)" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo ":: Tag $TAG existe déjà localement."
else
  git tag "$TAG"
  echo ":: Tag $TAG créé."
fi

echo ":: Push de debian/port + $TAG vers myfork (entre ta passphrase SSH si demandée)..."
git push --atomic myfork debian/port "$TAG"

echo ""
echo "✅ Push terminé ! Suis la compilation et la publication sur :"
echo "   https://github.com/bigmum0a-wq/Ryoku-for-debian/actions"
