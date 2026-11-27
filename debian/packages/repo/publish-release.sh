#!/usr/bin/env bash
# publish-release.sh — Creates a vX.Y.Z tag and pushes branch + tag to GitHub
# in a single command to trigger the release-debian.yml workflow.
#
# Usage: bash debian/packages/repo/publish-release.sh v1.2.3
set -euo pipefail

TAG="${1:-}"
if [[ -z "$TAG" || ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vX.Y.Z (e.g. $0 v1.2.3)" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo ":: Tag $TAG already exists locally."
else
  git tag "$TAG"
  echo ":: Tag $TAG created."
fi

echo ":: Pushing debian/port + $TAG to myfork (enter your SSH passphrase if prompted)..."
git push --atomic myfork debian/port "$TAG"

echo ""
echo "✅ Push complete! Follow the build and release at:"
echo "   https://github.com/bigmum0a-wq/Ryoku-for-debian/actions"
