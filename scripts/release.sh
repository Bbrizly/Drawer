#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
if [[ -z "$tag" ]]; then
  echo "Usage: ./scripts/release.sh v1.0.0" >&2
  exit 1
fi

if [[ ! "$tag" =~ ^v[0-9] ]]; then
  echo "Tag should look like v1.0.0 (must start with v)." >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Commit or stash your changes before releasing." >&2
  exit 1
fi

echo "Running tests..."
swift test

if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag $tag already exists locally."
else
  git tag "$tag"
  echo "Created tag $tag"
fi

echo "Pushing tag to GitHub..."
git push origin "$tag"

echo ""
echo "Done. GitHub Actions is building Drawer-macOS.zip and publishing the release."
echo "Watch progress: https://github.com/Bbrizly/Drawer/actions"
echo "Release page:   https://github.com/Bbrizly/Drawer/releases/tag/$tag"
