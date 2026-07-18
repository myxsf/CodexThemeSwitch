#!/bin/bash

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
VERSION="$(/usr/bin/tr -d '[:space:]' < "$ROOT/macos/VERSION")"
RELEASE="$ROOT/release"
STAGE="$(/usr/bin/mktemp -d /private/tmp/codex-wardrobe-delivery.XXXXXX)"
trap '/bin/rm -rf "$STAGE"' EXIT

APP="$HOME/Desktop/Codex 主题衣橱.app"
"$ROOT/macos/scripts/build-theme-switcher-macos.sh" "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

/bin/mkdir -p \
  "$STAGE/windows/Codex Theme Wardrobe $VERSION/windows" \
  "$STAGE/windows/Codex Theme Wardrobe $VERSION/themes" \
  "$STAGE/windows/Codex Theme Wardrobe $VERSION/macos" \
  "$STAGE/assets/Codex Theme Background Assets $VERSION"

/usr/bin/rsync -a --exclude release --exclude .DS_Store "$ROOT/windows/" "$STAGE/windows/Codex Theme Wardrobe $VERSION/windows/"
/usr/bin/rsync -a --exclude .DS_Store "$ROOT/themes/" "$STAGE/windows/Codex Theme Wardrobe $VERSION/themes/"
/usr/bin/rsync -a --exclude .DS_Store "$ROOT/macos/themes/" "$STAGE/windows/Codex Theme Wardrobe $VERSION/macos/themes/"
/bin/cp "$ROOT/release/README.zh-CN.md" "$STAGE/windows/Codex Theme Wardrobe $VERSION/README.zh-CN.md"
/bin/cp "$ROOT/windows/Install Codex Theme Wardrobe.cmd" "$STAGE/windows/Codex Theme Wardrobe $VERSION/Install Codex Theme Wardrobe.cmd"

WINDOWS_STAGE="$STAGE/windows/Codex Theme Wardrobe $VERSION"
[ -f "$WINDOWS_STAGE/windows/scripts/install-dream-skin.ps1" ] || {
  printf 'Windows package installer is missing.\n' >&2
  exit 1
}
/usr/bin/grep -Fq 'INSTALLER=%~dp0windows\scripts\install-dream-skin.ps1' \
  "$WINDOWS_STAGE/Install Codex Theme Wardrobe.cmd" || {
    printf 'Windows package launcher does not target the packaged installer.\n' >&2
    exit 1
  }
! /usr/bin/grep -q 'docs\\images\\gallery' "$WINDOWS_STAGE/windows/scripts/install-dream-skin.ps1" || {
  printf 'Windows installer still requires the unbundled legacy gallery.\n' >&2
  exit 1
}
/bin/bash "$WINDOWS_STAGE/windows/tests/run-tests.sh"

for theme_id in skin-01 skin-02 skin-03 skin-04 skin-05 skin-06 skin-07 skin-08; do
  theme_dir="$ROOT/macos/themes/$theme_id"
  target="$STAGE/assets/Codex Theme Background Assets $VERSION/$theme_id"
  image="$(/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node -e 'console.log(require(process.argv[1]).image)' "$theme_dir/theme.json")"
  /bin/mkdir -p "$target"
  /bin/cp "$theme_dir/theme.json" "$theme_dir/$image" "$target/"
done
/bin/cp "$ROOT/docs/BACKGROUND-ASSETS.zh-CN.md" "$STAGE/assets/Codex Theme Background Assets $VERSION/README.md"

/bin/mkdir -p "$RELEASE"
/usr/bin/find "$RELEASE" -mindepth 1 -maxdepth 1 ! -name 'README.zh-CN.md' -exec /bin/rm -rf {} +
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$APP" "$RELEASE/Codex-Theme-Wardrobe-v$VERSION-macos-universal.zip"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$STAGE/windows/Codex Theme Wardrobe $VERSION" "$RELEASE/Codex-Theme-Wardrobe-v$VERSION-windows.zip"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$STAGE/assets/Codex Theme Background Assets $VERSION" "$RELEASE/Codex-Theme-Wardrobe-v$VERSION-background-assets.zip"

(
  cd "$RELEASE"
  /usr/bin/shasum -a 256 \
    "Codex-Theme-Wardrobe-v$VERSION-macos-universal.zip" \
    "Codex-Theme-Wardrobe-v$VERSION-windows.zip" \
    "Codex-Theme-Wardrobe-v$VERSION-background-assets.zip" \
    README.zh-CN.md > SHA256SUMS.txt
)

/usr/bin/printf 'Created final delivery %s\n' "$VERSION"
