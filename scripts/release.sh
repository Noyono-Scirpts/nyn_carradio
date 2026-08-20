#!/usr/bin/env bash
# Bump fxmanifest version, package zip, write public nyn_versions catalog,
# commit + tag + push, create GitHub Release.
set -euo pipefail

export PATH="${HOME}/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=nyn-versions.sh
source "$ROOT/scripts/nyn-versions.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release.sh patch|minor|major
  scripts\release.bat patch|minor|major

Bumps version in fxmanifest.lua, zips shippable files, writes that version
into public Noyono-Scirpts/nyn_versions, then commits, tags, pushes, and
creates a GitHub Release with the zip.

  patch  1.0.0 → 1.0.1  bugfix / small change
  minor  1.0.0 → 1.1.0  new feature, still compatible
  major  1.0.0 → 2.0.0  breaking change

Resource folder name = this repo directory name.
Override with RESOURCE_NAME=nyn_foo ./scripts/release.sh patch

  SKIP_PUSH=1      commit + tag locally, do not push or create GitHub Release
  SKIP_VERSIONS=1  do not update the versions catalog
  NYN_VERSIONS_REPO=Noyono-Scirpts/nyn_versions
EOF
}

BUMP="${1:-}"
if [[ ! "$BUMP" =~ ^(patch|minor|major)$ ]]; then
  usage
  exit 1
fi

RESOURCE="${RESOURCE_NAME:-$(basename "$ROOT")}"
MANIFEST="$ROOT/fxmanifest.lua"

if [[ ! -f "$MANIFEST" ]]; then
  echo "error: fxmanifest.lua not found" >&2
  exit 1
fi

CURRENT="$(grep -E "^version ['\"]" "$MANIFEST" | head -1 | sed -E "s/^version ['\"]([0-9]+\.[0-9]+\.[0-9]+)['\"].*/\1/")"
if [[ ! "$CURRENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: could not read version from fxmanifest.lua (expected version 'x.y.z')" >&2
  exit 1
fi

IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW="${MAJOR}.${MINOR}.${PATCH}"

tmp="$(mktemp)"
awk -v ver="$NEW" '
  /^version / { print "version '\''" ver "'\''"; next }
  { print }
' "$MANIFEST" > "$tmp"
mv "$tmp" "$MANIFEST"

echo "version $CURRENT → $NEW ($BUMP)"
nyn_bump_readme_version

if [[ -f "$ROOT/web/package.json" ]]; then
  echo "building ui from web/"
  (cd "$ROOT/web" && npm install && npm run build)
fi

nyn_publish_versions

STAGE="$ROOT/releases/$RESOURCE"
rm -rf "$STAGE"
mkdir -p "$STAGE"

copy_if() {
  local src="$1"
  if [[ -e "$ROOT/$src" ]]; then
    cp -R "$ROOT/$src" "$STAGE/"
  fi
}

copy_if client
copy_if server
copy_if shared
copy_if locales
copy_if ui
copy_if sql
copy_if fxmanifest.lua
copy_if README.md
copy_if LICENSE

ZIP_NAME="${RESOURCE}-${NEW}.zip"
ZIP_PATH="$ROOT/releases/${ZIP_NAME}"
nyn_make_zip "$ZIP_PATH"

echo
echo "staged  releases/${RESOURCE}/"
echo "zip     releases/${ZIP_NAME}"

nyn_git_release "$ZIP_PATH"
